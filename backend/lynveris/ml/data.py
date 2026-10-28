import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import parse_qsl

from ..urls import parse_url


def timestamp(value, allow_future=False):
    if not isinstance(value, str):
        raise ValueError("Missing trustworthy timestamp; never substitute collection date")
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        raise ValueError("Invalid timestamp") from None
    if dt.tzinfo is None or (not allow_future and dt > datetime.now(timezone.utc)):
        raise ValueError("Timezone required; future timestamps not accepted")
    return dt


def validate_record(record):
    for key in (
        "url",
        "label",
        "observed_at",
        "label_at",
        "source",
        "license",
        "evidence",
        "category",
    ):
        if key not in record or record[key] in (None, ""):
            raise ValueError(f"Missing provenance field: {key}")
    if type(record["label"]) is not int or record["label"] not in {0, 1}:
        raise ValueError("label must be 0 (reviewed legitimate exact URL) or 1 (phishing)")
    parse_url(record["url"])
    timestamp(record["observed_at"])
    timestamp(record["label_at"])
    if not record["source"].startswith("https://") or len(record["evidence"]) < 12:
        raise ValueError("Evidence/source must justify the exact URL label")
    if record.get("threat"):
        t = record["threat"]
        if t.get("status") not in {
            "detected",
            "not_found",
            "error",
            "timeout",
            "quota",
            "not_configured",
            "skipped",
        }:
            raise ValueError("Invalid threat snapshot status")
        if not t.get("source") or not t.get("snapshot_id"):
            raise ValueError("Threat snapshot provenance missing")
        checked = timestamp(t.get("checked_at"))
        observed = timestamp(record["observed_at"])
        if checked > observed:
            raise ValueError("Historical evaluation cannot use a later threat lookup")
        if t["status"] in {"detected", "not_found"}:
            expires = timestamp(t.get("expires_at"), allow_future=True)
            if not checked <= observed < expires:
                raise ValueError("Threat snapshot must still be valid at the observation time")
            if t["source"] == "Google Safe Browsing" and (observed - checked).total_seconds() > (
                1800 if t["status"] == "detected" else 60
            ):
                raise ValueError("Google snapshot outside its allowed cache window")
    return record


def read_records(path):
    rows = []
    for i, line in enumerate(Path(path).read_text(encoding="utf8").splitlines(), 1):
        if line.strip():
            try:
                rows.append(validate_record(json.loads(line)))
            except (ValueError, TypeError, KeyError) as exc:
                raise ValueError(f"Record {i}: {exc}") from None
    return rows


def fingerprint(url):
    p = parse_url(url)
    # Strip tracking values, numeric/random identifiers and scheme/fragment for near duplicates.
    path = re.sub(r"[0-9a-f]{8,}|\d+", "{id}", p.path.lower()).rstrip("/")
    keys = sorted(
        {
            k
            for k, v in parse_qsl(p.query, max_num_fields=4096)
            if not k.lower().startswith(("utm_", "fbclid", "gclid"))
        }
    )
    return hashlib.sha256((p.hostname + path + "?" + "&".join(keys)).encode()).hexdigest()


def group_keys(record):
    p = parse_url(record["url"])
    keys = {"domain:" + (p.registered_domain or p.hostname), "near:" + fingerprint(record["url"])}
    if record.get("campaign"):
        keys.add("campaign:" + record["campaign"])
    return keys


def partition(rows, validation_start, test_start):
    validation_at, test_at = timestamp(validation_start), timestamp(test_start)
    if validation_at >= test_at:
        raise ValueError("Validation must precede test")
    parts = {"train": [], "validation": [], "test": []}
    audit = {"duplicates": 0, "excluded_overlap": 0, "input": len(rows)}
    ordered = sorted((validate_record(x) for x in rows), key=lambda x: timestamp(x["observed_at"]))
    parents = {}

    def find(key):
        parents.setdefault(key, key)
        while parents[key] != key:
            parents[key] = parents[parents[key]]
            key = parents[key]
        return key

    # Union all domain/campaign aliases BEFORE assigning temporal partitions.
    for r in ordered:
        keys = sorted(group_keys(r))
        root = find(keys[0])
        for key in keys[1:]:
            parents[find(key)] = root
    owners, seen = {}, {}
    for r in ordered:
        f = fingerprint(r["url"])
        if f in seen:
            if seen[f] != r["label"]:
                raise ValueError(
                    "Conflicting labels for duplicate endpoint; review before splitting"
                )
            audit["duplicates"] += 1
            continue
        seen[f] = r["label"]
        dt = timestamp(r["observed_at"])
        split = "train" if dt < validation_at else "validation" if dt < test_at else "test"
        # Labels learned after a boundary cannot be used to choose a model for that boundary.
        boundary = validation_at if split == "train" else test_at if split == "validation" else None
        if boundary and timestamp(r["label_at"]) >= boundary:
            audit.setdefault("late_labels", 0)
            audit["late_labels"] += 1
            continue
        component = find(next(iter(group_keys(r))))
        owner = owners.setdefault(component, split)
        if owner != split:
            audit["excluded_overlap"] += 1
            continue
        parts[split].append(r)
    return parts, audit


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(
        description="Validate provenance and create locked temporal splits"
    )
    parser.add_argument("input")
    parser.add_argument("output")
    parser.add_argument("--validation-start", required=True)
    parser.add_argument("--test-start", required=True)
    args = parser.parse_args()
    output = Path(args.output)
    if output.exists():
        raise SystemExit("Use a new output directory; locked split files are never overwritten")
    parts, audit = partition(read_records(args.input), args.validation_start, args.test_start)
    output.mkdir(parents=True)
    manifest = {
        "input_sha256": sha(args.input),
        "validation_start": args.validation_start,
        "test_start": args.test_start,
        "audit": audit,
        "files": {},
    }
    for split, rows in parts.items():
        path = output / f"{split}.jsonl"
        path.write_text(
            "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf8"
        )
        manifest["files"][split] = {"sha256": sha(path), "count": len(rows)}
    (output / "split-manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf8")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
