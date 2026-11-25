"""W06 live API and PostgreSQL checks, scoped to one disposable record."""

import hashlib
import json
import secrets
import time
from datetime import datetime, timezone
from pathlib import Path

import httpx
from lynveris.config import Settings
from lynveris.database import ResearchEvent, engine_for
from sqlalchemy import select


def main():
    engine = engine_for(Settings().database_url)
    assert engine.dialect.name == "postgresql"
    with engine.connect() as db:
        before = set(db.execute(select(ResearchEvent.id)).scalars())
    results = []

    def record(case_id, expected, passed, detail):
        results.append({"id": case_id, "expected": expected, "passed": passed, "actual": detail})

    with httpx.Client(timeout=18, follow_redirects=False) as client:
        record(
            "LIVE01",
            "ready, PostgreSQL and model available",
            (body := client.get("http://127.0.0.1:8000/ready").json())["status"] == "ready",
            body,
        )

        def check(url, base="http://127.0.0.1:8000", **extra):
            response = client.post(
                base + "/v1/check",
                json={
                    "url": url,
                    "use_threat_intelligence": True,
                    "research_consent": False,
                    **extra,
                },
            )
            if response.status_code == 429:
                time.sleep(61)
                return check(url, base, **extra)
            return response

        body = check("https://www.iana.org/help/example-domains").json()
        record(
            "LIVE02",
            "no_signs, both real sources not_found",
            body["verdict"] == "no_signs"
            and len(body["threat"]["checks"]) == 2
            and all(c["status"] == "not_found" for c in body["threat"]["checks"]),
            body,
        )
        body = check("https://testsafebrowsing.appspot.com/s/phishing.html").json()
        record(
            "LIVE03",
            "high, real threat match",
            body["verdict"] == "high" and body["threat"]["status"] == "detected",
            body,
        )
        body = check("https://paypal.com@verify.example.org/login").json()
        record(
            "LIVE04",
            "caution, true hostname and userinfo signal",
            body["verdict"] == "caution"
            and body["url"]["hostname"] == "verify.example.org"
            and any(s["code"] == "misleading_userinfo" for s in body["signals"]),
            body,
        )
        for case_id, url in (("LIVE05", ""), ("LIVE06", "file:///private-document")):
            response = check(url)
            record(case_id, "HTTP422", response.status_code == 422, {"http": response.status_code})
        body = check(
            "https://www.iana.org/help/example-domains", base="http://127.0.0.1:8003"
        ).json()
        record(
            "LIVE07",
            "insufficient, partial source",
            body["verdict"] == "insufficient" and body["threat"]["partial"],
            body,
        )

        # Use a fresh ownership token. The existing user's tokens are never read.
        token = secrets.token_hex(32)
        event_id = None
        try:
            body = check(
                "https://www.iana.org/help/example-domains",
                use_threat_intelligence=False,
                research_consent=True,
                deletion_token=token,
            ).json()
            event_id = body["id"]
            with engine.connect() as db:
                row = (
                    db.execute(select(ResearchEvent.__table__).where(ResearchEvent.id == event_id))
                    .mappings()
                    .one()
                )
                anonymous = row["owner_hash"] == hashlib.sha256(token.encode()).hexdigest()
                anonymous = anonymous and "url" not in row and "message" not in row
            record(
                "LIVE08",
                "one minimal event read from PostgreSQL",
                anonymous,
                {
                    "id": event_id,
                    "verdict": row["verdict"],
                    "model": row["model_version"],
                    "fields": list(row.keys()),
                },
            )
        finally:
            if event_id:
                deletion = client.delete(
                    "http://127.0.0.1:8000/v1/research", headers={"X-Deletion-Token": token}
                )
                assert deletion.status_code == 200
                assert deletion.json()["deleted"] == 1
        with engine.connect() as db:
            after = set(db.execute(select(ResearchEvent.id)).scalars())
        record(
            "LIVE09",
            "delete only our event, keep existing IDs",
            before == after,
            {"before_count": len(before), "after_count": len(after)},
        )
    output = Path("artifacts/w06/live-checks.json")
    output.write_text(
        json.dumps(
            {
                "checked_at": datetime.now(timezone.utc).isoformat(),
                "database": "PostgreSQL",
                "total": len(results),
                "passed": sum(r["passed"] for r in results),
                "checks": results,
                "existing_ids_preserved": before == after,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    print(
        json.dumps(
            {
                "total": len(results),
                "passed": sum(r["passed"] for r in results),
                "existing_ids_preserved": before == after,
            }
        )
    )
    if not all(r["passed"] for r in results):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
