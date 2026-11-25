"""Run against Compose on a Docker host; record readiness and isolation checks."""

import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

import httpx


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    records = []

    def record(name, actual, expected):
        records.append(
            {"check": name, "actual": actual, "expected": expected, "passed": actual == expected}
        )

    with httpx.Client(base_url="http://127.0.0.1:8000", timeout=15) as client:
        ready = client.get("/ready")
        record("PostgreSQL readiness", ready.status_code, 200)
        body = client.post("/v1/check", json={"url": "https://example.org"}).json()
        record("Unconfigured model is transparent", body["model"]["status"], "unavailable")
        record("No false clear verdict without model", body["verdict"], "insufficient")
        record(
            "Invalid scheme rejected",
            client.post("/v1/check", json={"url": "file:///private"}).status_code,
            422,
        )
        huge = client.post("/v1/check", content=b"x" * 16385)
        record("Oversize body rejected", huge.status_code, 413)
        record("Rejection not cached", huge.headers.get("cache-control"), "no-store")
    record(
        "API runs as non-root",
        command("docker", "compose", "exec", "-T", "api", "id", "-u"),
        "10001",
    )
    container = command("docker", "compose", "ps", "-q", "api")
    record(
        "Read-only root filesystem",
        command("docker", "inspect", "--format", "{{.HostConfig.ReadonlyRootfs}}", container),
        "true",
    )
    db = command("docker", "compose", "ps", "-q", "db")
    record("Database port not published", command("docker", "port", db), "")
    output = Path("artifacts/w07/compose-checks.json")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(
            {
                "checked_at": datetime.now(timezone.utc).isoformat(),
                "environment": "GitHub Actions Ubuntu Docker Compose",
                "checks": records,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(json.dumps({"compose_checks": len(records), "passed": sum(r["passed"] for r in records)}))
    if not all(r["passed"] for r in records):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
