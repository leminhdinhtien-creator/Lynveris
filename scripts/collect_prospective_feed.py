"""Private academic snapshots: independent OpenPhish labels and live Google predictions.

Does not visit feed URLs, infer first-seen times or backfill historical observations.
"""

import argparse
import asyncio
import hashlib
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

import httpx
from lynveris.config import Settings
from lynveris.model import UrlModel
from lynveris.openphish import OpenPhishCommunity
from lynveris.threats import GoogleSafeBrowsing
from lynveris.urls import UrlError, inspect_url, parse_url


async def collect(output):
    settings = Settings()
    if not settings.google_api_key or not settings.openphish_academic_use:
        raise ValueError("Local Google key and academic OpenPhish opt-in required")
    root = Path(output)
    root.mkdir(parents=True, exist_ok=False)
    async with httpx.AsyncClient(timeout=15, follow_redirects=False, trust_env=False) as client:
        async with client.stream(
            "GET", OpenPhishCommunity.ENDPOINT, headers={"User-Agent": "Lynveris-academic/0.1"}
        ) as response:
            response.raise_for_status()
            body = bytearray()
            async for chunk in response.aiter_bytes():
                body.extend(chunk)
                if len(body) > 2 * 1024 * 1024:
                    raise ValueError("Oversize source")
            headers = {k: response.headers.get(k) for k in ("etag", "last-modified", "date")}
    received = datetime.now(timezone.utc).isoformat()
    (root / "feed.txt").write_bytes(body)
    source = GoogleSafeBrowsing(settings.google_api_key)
    model = UrlModel(settings.model_directory)
    counts, unsupported = Counter(), 0
    with (root / "observations.jsonl").open("x", encoding="utf8") as stream:
        for url in dict.fromkeys(body.decode("utf8").splitlines()):
            try:
                p = parse_url(url)
            except UrlError:
                unsupported += 1
                continue
            result = await source.check(p.fetch_url)
            prediction = model.predict(p.original)
            observed = datetime.now(timezone.utc).isoformat()
            record = {
                "url": p.original,
                "url_sha256": hashlib.sha256(p.original.encode()).hexdigest(),
                "label": 1,
                "label_source": OpenPhishCommunity.ENDPOINT,
                "label_available_at": received,
                "source_label_decision_at": None,
                "source_reported_at": None,
                "source_verified_at": None,
                "source_feed_sha256": hashlib.sha256(body).hexdigest(),
                "source_feed_received_at": received,
                "source_headers": headers,
                "observed_at": observed,
                "threat": result.model_dump(mode="json"),
                "model": prediction.model_dump(mode="json"),
                "strong_url_rule": any(s.severity == "strong" for s in inspect_url(p).signals),
                "evidence": "Exact URL in received OpenPhish Community feed; independent Google lookup at stated time. No page visit or LLM labeling.",
                "license": "OpenPhish academic/personal research terms; private, no redistribution",
                "limitations": "Feed receipt is not first appearance or original label time. Positive-only observational snapshot, no FPR/H1 claim.",
            }
            stream.write(json.dumps(record, ensure_ascii=False) + "\n")
            stream.flush()
            counts[result.status] += 1
            if result.status in {"quota", "error", "timeout", "not_configured"}:
                break
            await asyncio.sleep(0.2)
    summary = {
        "source": OpenPhishCommunity.ENDPOINT,
        "source_feed_received_at": received,
        "feed_sha256": hashlib.sha256(body).hexdigest(),
        "observations_sha256": hashlib.sha256(
            (root / "observations.jsonl").read_bytes()
        ).hexdigest(),
        "observed_positive_labels": sum(counts.values()),
        "google_status_counts": dict(counts),
        "unsupported_feed_urls": unsupported,
        "source_label_time_available": False,
        "historical_backfill": False,
        "label_predictor_independent": True,
        "negative_class_collected": False,
        "hypothesis_1_evidence": False,
    }
    (root / "manifest.json").write_text(json.dumps(summary, indent=2), encoding="utf8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("output")
    asyncio.run(collect(parser.parse_args().output))
