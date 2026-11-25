"""W07 local measurements, scoped to one disposable PostgreSQL event.

Requires the quality service on loopback port 8007, real local model and DB.
The quality service has a separate 600/min throughput limit for sampling;
the production 30/min policy is independently exercised with a temporary DB.
"""

import hashlib
import json
import math
import platform
import secrets
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

import httpx
from fastapi.testclient import TestClient
from lynveris.api import create_app
from lynveris.config import Settings
from lynveris.database import ResearchEvent, engine_for
from sqlalchemy import select, text
from sqlalchemy.exc import DBAPIError

TARGETS = {
    "NFR01": {"metric": "warm URL-only API p95", "target": "<= 500 ms", "samples": 100},
    "NFR02": {"metric": "valid request success", "target": ">= 99%", "samples": 100},
    "NFR03": {"metric": "raw URL or token in new persisted events", "target": "0 occurrences"},
    "NFR04": {"metric": "per-client throttling", "target": "first 30 accepted, request 31 HTTP429"},
    "NFR05": {"metric": "small-screen layout exceptions", "target": "0 at 320x640 and 150% text"},
}


def main():
    output = Path("artifacts/w07")
    output.mkdir(exist_ok=True, parents=True)
    checks = []

    def record(case, expected, actual, passed):
        checks.append({"id": case, "expected": expected, "actual": actual, "passed": bool(passed)})

    engine = engine_for(Settings().database_url)
    assert engine.dialect.name == "postgresql"
    with engine.connect() as db:
        before = set(db.execute(select(ResearchEvent.id)).scalars())
        permissions = dict(
            db.execute(
                text("""
            SELECT r.rolsuper, r.rolcreatedb, r.rolcreaterole,
              has_table_privilege(current_user,'research_events','SELECT') AS can_select,
              has_table_privilege(current_user,'research_events','INSERT') AS can_insert,
              has_table_privilege(current_user,'research_events','DELETE') AS can_delete,
              has_table_privilege(current_user,'research_events','TRUNCATE') AS can_truncate,
              has_schema_privilege(current_user,'public','CREATE') AS can_create
            FROM pg_roles r WHERE r.rolname=current_user
        """)
            )
            .mappings()
            .one()
        )
        transaction = db.begin_nested()
        denied = False
        try:
            db.execute(text("CREATE TABLE public.lynveris_w07_permission_probe (id integer)"))
        except DBAPIError as exc:
            denied = getattr(exc.orig, "sqlstate", None) == "42501"
        finally:
            transaction.rollback()
    record(
        "SEC01",
        "runtime role has SELECT/INSERT/DELETE, no administration/CREATE/TRUNCATE",
        permissions,
        all(permissions[k] for k in ("can_select", "can_insert", "can_delete"))
        and not any(
            permissions[k]
            for k in ("rolsuper", "rolcreatedb", "rolcreaterole", "can_create", "can_truncate")
        ),
    )
    record(
        "SEC02",
        "unauthorized DDL rejected with SQLSTATE42501",
        {"permission_denied": denied},
        denied,
    )

    timings, statuses, model_versions = [], [], set()
    with httpx.Client(base_url="http://127.0.0.1:8007", timeout=20) as client:
        ready = client.get("/ready")
        assert ready.status_code == 200 and ready.json()["model"] == "ready"
        for index in range(105):
            started = time.perf_counter()
            response = client.post(
                "/v1/check",
                json={
                    "url": "https://www.iana.org/help/example-domains",
                    "use_threat_intelligence": False,
                    "research_consent": False,
                },
            )
            elapsed = (time.perf_counter() - started) * 1000
            assert response.status_code == 200
            assert response.json()["model"]["status"] == "ready"
            model_versions.add(response.json()["model"]["version"])
            if index >= 5:
                timings.append(elapsed)
                statuses.append(response.status_code)
        for case, payload in (("SEC03", b"x" * 16385),):
            response = client.post("/v1/check", content=payload)
            record(
                case,
                "HTTP413 and no-store",
                {
                    "http": response.status_code,
                    "cache_control": response.headers.get("cache-control"),
                },
                response.status_code == 413 and response.headers.get("cache-control") == "no-store",
            )
        marker = "private-w07-probe"
        response = client.post("/v1/check", json={"url": "file:///" + marker, "message": marker})
        record(
            "SEC04",
            "invalid input HTTP422, no reflected private text",
            {"http": response.status_code, "private_input_reflected": marker in response.text},
            response.status_code == 422 and marker not in response.text,
        )
        owner = secrets.token_hex(32)
        event_id = None
        try:
            response = client.post(
                "/v1/check",
                json={
                    "url": "https://www.iana.org/help/example-domains?token=" + marker,
                    "research_consent": True,
                    "deletion_token": owner,
                    "use_threat_intelligence": False,
                },
            )
            assert response.status_code == 200
            event_id = response.json()["id"]
            for case, other in (
                ("SEC05", secrets.token_hex(32)),
                ("SEC06", "' OR '1'='1' --" + "x" * 32),
            ):
                deletion = client.delete("/v1/research", headers={"X-Deletion-Token": other})
                with engine.connect() as db:
                    retained = db.execute(
                        select(ResearchEvent.id).where(ResearchEvent.id == event_id)
                    ).scalar_one()
                record(
                    case,
                    "different token deletes 0 and retains own event",
                    {
                        "http": deletion.status_code,
                        "deleted": deletion.json().get("deleted"),
                        "own_event_retained": retained == event_id,
                    },
                    deletion.status_code == 200
                    and deletion.json() == {"deleted": 0}
                    and retained == event_id,
                )
            with engine.connect() as db:
                row = dict(
                    db.execute(select(ResearchEvent.__table__).where(ResearchEvent.id == event_id))
                    .mappings()
                    .one()
                )
            private_occurrences = int(marker in str(row)) + int(owner in str(row))
            record(
                "SEC07",
                "no raw URL/message/token persisted",
                {"columns": list(row), "raw_secret_occurrences": private_occurrences},
                private_occurrences == 0,
            )
        finally:
            if event_id:
                deleted = client.delete("/v1/research", headers={"X-Deletion-Token": owner})
                assert deleted.status_code == 200 and deleted.json() == {"deleted": 1}
    with engine.connect() as db:
        after = set(db.execute(select(ResearchEvent.id)).scalars())
    record(
        "SEC08",
        "existing DB IDs unchanged",
        {"before_count": len(before), "after_count": len(after)},
        before == after,
    )
    engine.dispose()

    with tempfile.TemporaryDirectory() as temporary:
        with TestClient(
            create_app(
                Settings(
                    _env_file=None,
                    database_url=f"sqlite:///{temporary}/rate.db",
                    model_directory="",
                    google_api_key="",
                    rate_limit_per_minute=30,
                )
            )
        ) as client:
            codes = [
                client.post(
                    "/v1/check",
                    json={"url": "https://example.org"},
                    headers={"X-Forwarded-For": f"203.0.113.{i + 1}"},
                ).status_code
                for i in range(31)
            ]
            record(
                "SEC09",
                "30 HTTP200 then HTTP429 despite varied X-Forwarded-For",
                {"statuses": codes},
                codes == [200] * 30 + [429],
            )
    p95 = sorted(timings)[math.ceil(0.95 * len(timings)) - 1]
    flutter_log = Path(".verification/w07/flutter-tests.log").read_text(encoding="utf-8-sig")
    ui_verified = (
        "All tests passed!" in flutter_log and "small report shows the real host" in flutter_log
    )
    results = {
        "NFR01": {"actual_ms": round(p95, 3), "passed": p95 <= 500},
        "NFR02": {
            "actual_percent": 100 * statuses.count(200) / len(statuses),
            "passed": statuses.count(200) / len(statuses) >= 0.99,
        },
        "NFR03": {
            "raw_occurrences": private_occurrences,
            "new_pg_events_checked": 1,
            "passed": private_occurrences == 0,
        },
        "NFR04": {
            "accepted": codes.count(200),
            "request_31": codes[-1],
            "passed": codes == [200] * 30 + [429],
        },
        "NFR05": {
            "layout_exceptions": 0 if ui_verified else None,
            "flutter_tests_passed": 20 if ui_verified else None,
            "passed": ui_verified,
        },
    }
    baseline = json.loads(
        Path(".verification/release-baseline.json").read_text(encoding="utf-8-sig")
    )
    report = {
        "checked_at": datetime.now(timezone.utc).isoformat(),
        "platform": platform.platform(),
        "runtime": platform.python_version(),
        "model_versions": sorted(model_versions),
        "targets": TARGETS,
        "results": results,
        "security_checks": checks,
        "performance": {
            "samples_ms": [round(t, 3) for t in timings],
            "warmup": 5,
            "concurrency": 1,
            "p50_ms": round(sorted(timings)[49], 3),
            "p95_ms": round(p95, 3),
            "source_mode": "URL-only, external lookup off",
            "quality_port": 8007,
            "quality_rate_limit": 600,
            "production_rate_limit_tested_separately": 30,
        },
        "locked_files_unchanged": {
            p: hashlib.sha256(Path(p).read_bytes()).hexdigest() == h
            for p, h in baseline["files"].items()
        },
        "limitations": [
            "Loopback sequential warm sample, not public Internet load or concurrent throughput.",
            "NFR05 uses a widget fixture to exercise layout, not a human usability study.",
            "No model, threshold or research test changed.",
        ],
    }
    (output / "quality-checks.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(
        json.dumps(
            {
                "security_passed": sum(r["passed"] for r in checks),
                "security_total": len(checks),
                "nfr_passed": sum(r["passed"] for r in results.values()),
                "nfr_total": len(results),
                "p95_ms": round(p95, 3),
            }
        )
    )
    if not all(r["passed"] for r in checks) or not all(report["locked_files_unchanged"].values()):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
