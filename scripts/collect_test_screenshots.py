"""Collect our debug app's integration screenshots, optionally verify real PostgreSQL rows."""

import argparse
import json
import os
import shutil
import subprocess
import time
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("device")
    parser.add_argument("--wait-seconds", type=int, default=600)
    parser.add_argument("--product", action="store_true")
    parser.add_argument("--output", default="artifacts/screenshots")
    parser.add_argument(
        "--adb",
        default=shutil.which("adb")
        or str(Path(os.environ.get("LOCALAPPDATA", "")) / "Android/sdk/platform-tools/adb.exe"),
    )
    args = parser.parse_args()
    engine = None
    if args.product:
        from lynveris.config import Settings
        from lynveris.database import ResearchEvent, engine_for
        from sqlalchemy import select

        engine = engine_for(Settings().database_url)
        with engine.connect() as db:
            before = set(db.execute(select(ResearchEvent.id)).scalars())
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + args.wait_seconds
    remote_directory = None
    while time.monotonic() < deadline:
        for candidate in ("code_cache", "cache"):
            marker = subprocess.run(
                [
                    args.adb,
                    "-s",
                    args.device,
                    "exec-out",
                    "run-as",
                    "vn.lynveris.lynveris",
                    "cat",
                    f"{candidate}/qa-ready",
                ],
                capture_output=True,
                timeout=15,
            )
            if marker.stdout.strip() == b"ready":
                remote_directory = candidate
                break
        if remote_directory:
            break
        time.sleep(1)
    else:
        raise TimeoutError(
            "Start the Android integration test with CAPTURE_QA=true while this collector runs"
        )

    def remote(*command):
        return subprocess.run(
            [args.adb, "-s", args.device, "exec-out", "run-as", "vn.lynveris.lynveris", *command],
            capture_output=True,
            check=True,
            timeout=30,
        ).stdout

    names = ("lynveris-home", "lynveris-insufficient", "lynveris-warning")
    if args.product:
        from uuid import UUID

        proof = json.loads(remote("cat", f"{remote_directory}/qa-proof.json"))
        ids = [str(UUID(value)) for value in proof["ids"]]
        assert len(ids) == 3 and len(set(ids)) == 3
        names = proof["screenshots"]
        assert all(
            name.startswith("lynveris-") and name.replace("-", "").isalpha() for name in names
        )
        with engine.connect() as db:
            rows = (
                db.execute(select(ResearchEvent.__table__).where(ResearchEvent.id.in_(ids)))
                .mappings()
                .all()
            )
            assert len(rows) == 3
            assert len({row["owner_hash"] for row in rows}) == 1
            by_id = {row["id"]: row for row in rows}
            assert [by_id[i]["source_status"] for i in ids] == [
                "not_found",
                "not_found",
                "detected",
            ]
        print(
            "Android -> FastAPI -> PostgreSQL: three real response IDs independently read from SQL."
        )
    for name in names:
        result = subprocess.run(
            [
                args.adb,
                "-s",
                args.device,
                "exec-out",
                "run-as",
                "vn.lynveris.lynveris",
                "cat",
                f"{remote_directory}/{name}.png",
            ],
            capture_output=True,
            check=True,
            timeout=30,
        )
        if not result.stdout.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError(
                f"Expected test PNG was not present; header={result.stdout[:16].hex()}, bytes={len(result.stdout)}"
            )
        (output / f"{name}.png").write_bytes(result.stdout)
        print(f"Saved {name}.png ({len(result.stdout)} bytes)")
    subprocess.run(
        [
            args.adb,
            "-s",
            args.device,
            "exec-out",
            "run-as",
            "vn.lynveris.lynveris",
            "touch",
            f"{remote_directory}/qa-collected",
        ],
        capture_output=True,
        check=True,
        timeout=15,
    )
    if args.product:
        for _ in range(120):
            try:
                if remote("cat", f"{remote_directory}/qa-erased").strip() == b"erased":
                    break
            except subprocess.CalledProcessError:
                pass
            time.sleep(0.5)
        else:
            raise TimeoutError("Flutter did not complete its own research deletion")
        with engine.connect() as db:
            after = set(db.execute(select(ResearchEvent.id)).scalars())
            assert not set(ids) & after
            assert before <= after
        engine.dispose()
        remote("touch", f"{remote_directory}/qa-verified")
        (output.parent / "real-device-verification.json").write_text(
            json.dumps(
                {
                    "database": "lynveris",
                    "database_port": 5432,
                    "insert_read_delete": "passed",
                    "preserved_preexisting_rows": True,
                    "emulator": args.device,
                    "source": "OpenPhish Community",
                    "model": None,
                    "screenshots": names,
                },
                indent=2,
            ),
            encoding="utf-8",
        )
        print("Flutter deletion verified in SQL; preexisting rows preserved.")


if __name__ == "__main__":
    main()
