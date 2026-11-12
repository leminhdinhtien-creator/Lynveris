"""Lock chronological URL-only splits from a pinned, date32 source release.

Retrospective collection-day evaluation: no exact source label times or historical
blacklist snapshots exist in this export. Neither is inferred from today's lookup.
"""

import argparse
import json
from collections import Counter
from pathlib import Path

from lynveris.ml.data import fits_split, partition, sha, timestamp, validate_record
from lynveris.urls import SHORTENERS, UrlError, parse_url


def categories(url):
    p = parse_url(url)
    values = []
    if p.hostname in SHORTENERS:
        values.append("shortener")
    if len(url) > 200:
        values.append("long_url")
    if any(ord(c) > 127 for c in p.unicode_hostname):
        values.append("idn")
    if any(k in p.path.lower() for k in ["login", "signin", "auth", "account"]):
        values.append("login")
    if any(k in p.query.lower() for k in ["utm_", "gclid", "fbclid", "ref="]):
        values.append("tracking")
    return values or ["other"]


def prepare(source, output, validation_start, test_start, labels_available_by):
    root, out = Path(source), Path(output)
    if out.exists():
        raise ValueError("Use a new locked output directory")
    source_manifest = json.loads((root / "collection-manifest.json").read_text())
    protocol = "retrospective_collection_date"
    va, ta = timestamp(validation_start), timestamp(test_start)
    rows = []
    unsupported = []
    raw_counts = Counter()
    for shard in source_manifest["shards"]:
        path = root / (Path(shard["file"]).name + ".jsonl")
        if sha(path) != shard["selected_sha256"]:
            raise ValueError("Source metadata changed")
        for line in path.read_text(encoding="utf-8").splitlines():
            raw = json.loads(line)
            raw_counts[(raw["original_split"], str(raw["label"]))] += 1
            record = dict(
                url=raw["url"],
                label=raw["label"],
                observed_at=raw["source_collected_date"],
                label_at=None,
                temporal_basis="source_collection_date",
                time_precision="day",
                labels_available_by=labels_available_by,
                source_version=source_manifest["revision"],
                source=source_manifest["source"],
                license=source_manifest["license"],
                evidence=f"PhreshPhish publisher class; source ID {raw['source_id']}; pinned file {raw['source_file']}; paper https://arxiv.org/html/2507.10854v2. Exact label-decision time not provided.",
                category="other",
                source_id=raw["source_id"],
                original_split=raw["original_split"],
                reserved_for="test" if raw["original_split"] == "test" else "development",
            )
            try:
                record["strata"] = categories(record["url"])
                record["category"] = record["strata"][0]
                validate_record(record)
            except (UrlError, ValueError):
                # Retain unsupported test inputs as negative/unknown operational outcomes.
                record["unsupported_input"] = True
                if raw["original_split"] == "test" and fits_split(record, "test", va, ta, protocol):
                    unsupported.append(record)
                continue
            rows.append(record)
    parts, audit = partition(rows, validation_start, test_start, protocol)
    out.mkdir(parents=True)
    manifest = dict(
        input_sha256=sha(root / "collection-manifest.json"),
        source_manifest=str(root / "collection-manifest.json"),
        source_revision=source_manifest["revision"],
        validation_start=validation_start,
        test_start=test_start,
        evaluation_protocol=protocol,
        audit=audit,
        raw_counts={f"{a}:{b}": n for (a, b), n in raw_counts.items()},
        files={},
        limitations=[
            "Only source collection dates are available. +/-14 hour date envelope excludes ambiguous boundary days.",
            "Exact source label-decision times unavailable; labels known by the pinned release, not assumed known at past deployment time.",
            "Retrospective chronological collection-date benchmark, not prospective first-appearance or H1 evidence.",
            "No historical blacklist state inferred. The publisher test remains separate from all model selection.",
            "Campaign IDs unavailable; registrable-domain and near-endpoint grouping are conservative proxies.",
        ],
    )
    for name, records in {**parts, "test_unsupported": unsupported}.items():
        path = out / (name + ".jsonl")
        path.write_text(
            "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in records), encoding="utf-8"
        )
        manifest["files"][name] = dict(
            sha256=sha(path),
            count=len(records),
            labels=dict(Counter(str(r["label"]) for r in records)),
            strata={
                s: dict(Counter(str(r["label"]) for r in records if s in r.get("strata", [])))
                for s in ["shortener", "long_url", "idn", "login", "tracking", "other"]
            },
        )
    (out / "split-manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(
        json.dumps(
            {"evaluation_protocol": protocol, "audit": audit, "files": manifest["files"]}, indent=2
        )
    )


def main():
    p = argparse.ArgumentParser()
    p.add_argument("source")
    p.add_argument("output")
    p.add_argument("--validation-start", required=True)
    p.add_argument("--test-start", required=True)
    p.add_argument("--labels-available-by", required=True)
    args = p.parse_args()
    prepare(
        args.source, args.output, args.validation_start, args.test_start, args.labels_available_by
    )


if __name__ == "__main__":
    main()
