"""Prospective snapshots only, collected now; never backdated to historical observations."""

import argparse
import asyncio
import hashlib
import json
import secrets
from pathlib import Path

from lynveris.config import Settings
from lynveris.ml.data import read_records
from lynveris.threats import GoogleSafeBrowsing
from lynveris.urls import parse_url


async def collect(input_path, output):
    settings = Settings()
    if not settings.google_api_key:
        raise ValueError(
            "Configure LYNVERIS_GOOGLE_API_KEY on backend; never supply it as a CLI argument"
        )
    source = GoogleSafeBrowsing(settings.google_api_key)
    rows = read_records(input_path)
    # Private, consented research input only. This file contains URLs; never commit it.
    with Path(output).open("x", encoding="utf8") as stream:
        for row in rows:
            p = parse_url(row["url"])
            result = await source.check(p.fetch_url)
            snapshot = dict(
                snapshot_id=secrets.token_hex(16),
                url_sha256=hashlib.sha256(p.original.encode()).hexdigest(),
                source=result.source,
                status=result.status,
                checked_at=result.checked_at.isoformat() if result.checked_at else None,
                expires_at=result.expires_at.isoformat() if result.expires_at else None,
                note="Prospective observation, cannot be joined to an earlier URL observed_at.",
            )
            stream.write(json.dumps(snapshot) + "\n")
            stream.flush()
            if result.status in {"quota", "error", "timeout"}:
                break
            await asyncio.sleep(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("output")
    args = parser.parse_args()
    asyncio.run(collect(args.input, args.output))


if __name__ == "__main__":
    main()
