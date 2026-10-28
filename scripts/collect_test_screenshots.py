"""Retrieve only three named PNGs created by our integration test in our debug app's cache."""

import argparse
import os
import shutil
import subprocess
import time
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("device")
    parser.add_argument("--wait-seconds", type=int, default=600)
    parser.add_argument("--output", default="artifacts/screenshots")
    parser.add_argument(
        "--adb",
        default=shutil.which("adb")
        or str(Path(os.environ.get("LOCALAPPDATA", "")) / "Android/sdk/platform-tools/adb.exe"),
    )
    args = parser.parse_args()
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
    for name in ("lynveris-home", "lynveris-insufficient", "lynveris-warning"):
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


if __name__ == "__main__":
    main()
