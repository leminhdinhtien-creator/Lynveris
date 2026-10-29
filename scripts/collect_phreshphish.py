"""Read only URL/label/date metadata using Parquet HTTP ranges. Never read/execute HTML.

Publisher: https://huggingface.co/datasets/phreshphish/phreshphish (CC BY 4.0).
Uniform deterministic URL-hash sampling is fixed before model selection; no difficulty filter.
Original test remains separate. Collection dates are dates, not invented timestamps.
"""

import argparse
import hashlib
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

import httpx
from lynveris.ml.collection import keep_sample, metadata_record


def collect(output, revision, modulus):
    import fsspec
    import pyarrow.parquet as pq

    root = Path(output)
    root.mkdir(parents=True, exist_ok=True)
    config = dict(
        source="https://huggingface.co/datasets/phreshphish/phreshphish",
        revision=revision,
        sample_modulus=modulus,
        license="CC-BY-4.0",
        attribution="Dalton et al., PhreshPhish, arXiv:2507.10854v2 (2026)",
        paper="https://arxiv.org/html/2507.10854v2",
        columns=["url", "label", "date", "target", "sha256"],
        label_time_available=False,
        historical_blacklist_available=False,
    )
    path = root / "collection-config.json"
    if path.exists() and json.loads(path.read_text()) != config:
        raise ValueError("Output is locked to a different collection configuration")
    path.write_text(json.dumps(config, indent=2), encoding="utf-8")
    with httpx.Client(timeout=45, follow_redirects=True) as client:
        response = client.get(
            f"https://huggingface.co/api/datasets/phreshphish/phreshphish/tree/{revision}/data?limit=1000"
        )
        response.raise_for_status()
        shards = response.json()
    summaries = []
    for shard in sorted(shards, key=lambda x: x["path"]):
        name = Path(shard["path"]).name
        if not name.endswith(".parquet"):
            continue
        original_split = "train" if name.startswith("train-") else "test"
        target = root / (name + ".jsonl")
        manifest_path = root / (name + ".manifest.json")
        if manifest_path.exists():
            summary = json.loads(manifest_path.read_text())
            if hashlib.sha256(target.read_bytes()).hexdigest() != summary["selected_sha256"]:
                raise ValueError("Collected shard changed; preserve original evidence")
            summaries.append(summary)
            continue
        url = f"https://huggingface.co/datasets/phreshphish/phreshphish/resolve/{revision}/{shard['path']}"
        counts = Counter()
        date_counts = Counter()
        # A partial file without a manifest belongs to this interrupted collection only.
        with target.open("w", encoding="utf-8") as out:
            with fsspec.open(url, "rb", block_size=65536, cache_type="readahead") as stream:
                parquet = pq.ParquetFile(stream)
                source_rows = parquet.metadata.num_rows
                for batch in parquet.iter_batches(batch_size=2048, columns=config["columns"]):
                    for row in batch.to_pylist():
                        if not keep_sample(row["url"], modulus):
                            continue
                        record = metadata_record(row, original_split)
                        record["source_file"] = shard["path"]
                        out.write(json.dumps(record, ensure_ascii=False) + "\n")
                        counts[str(record["label"])] += 1
                        date_counts[record["source_collected_date"]] += 1
        summary = dict(
            file=shard["path"],
            source_rows=source_rows,
            selected=sum(counts.values()),
            label_counts=dict(counts),
            date_counts=dict(date_counts),
            source_lfs=shard.get("lfs"),
            source_bytes=shard["size"],
            selected_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
            collected_at=datetime.now(timezone.utc).isoformat(),
            note="Metadata columns only. No phishing destination was visited. No label time or historical TI inferred.",
        )
        manifest_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
        summaries.append(summary)
        print(
            json.dumps(
                {
                    "shard": name,
                    "source_rows": source_rows,
                    "selected": sum(counts.values()),
                    "labels": dict(counts),
                }
            ),
            flush=True,
        )
    manifest = dict(config, shards=summaries, collected_at=datetime.now(timezone.utc).isoformat())
    (root / "collection-manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(
        "Metadata collection complete; original test is separate and has not been scored.",
        flush=True,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output")
    parser.add_argument("--revision", required=True)
    parser.add_argument("--sample-modulus", type=int, default=8)
    args = parser.parse_args()
    collect(args.output, args.revision, args.sample_modulus)


if __name__ == "__main__":
    main()
