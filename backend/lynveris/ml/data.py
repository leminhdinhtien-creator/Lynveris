import argparse
import hashlib
import json
import re
from datetime import date, datetime, timedelta, timezone
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


def observation_bounds(record):
    """Conservative ordering envelope, not a fabricated event timestamp.

    Source date32 values have day precision and no timezone. A +/-14 hour
    envelope excludes ambiguous boundary days instead of guessing a local time.
    """
    if record.get("temporal_basis") == "source_collection_date":
        day = date.fromisoformat(record["observed_at"])
        start = datetime.combine(day, datetime.min.time(), tzinfo=timezone.utc)
        return start - timedelta(hours=14), start + timedelta(days=1, hours=14)
    instant = timestamp(record["observed_at"])
    return instant, instant


def fits_split(record, split, validation_at, test_at, protocol="event_time"):
    reserved = record.get("reserved_for")
    if (reserved == "test" and split != "test") or (reserved == "development" and split == "test"):
        return False
    calendar = record.get("temporal_basis") == "source_collection_date"
    if calendar and protocol != "retrospective_collection_date":
        raise ValueError("Collection-day records require explicit retrospective protocol")
    lo, hi = observation_bounds(record)
    within = (
        hi < validation_at
        if split == "train"
        else validation_at <= lo and hi < test_at
        if split == "validation"
        else lo >= test_at
    )
    if not within:
        return False
    boundary = validation_at if split == "train" else test_at if split == "validation" else None
    return calendar or boundary is None or timestamp(record["label_at"]) < boundary


def validate_record(record):
    calendar = record.get("temporal_basis") == "source_collection_date"
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
        if key not in record or (
            record[key] in (None, "") and not (calendar and key == "label_at")
        ):
            raise ValueError(f"Missing provenance field: {key}")
    if type(record["label"]) is not int or record["label"] not in {0, 1}:
        raise ValueError("label must be 0 (reviewed legitimate exact URL) or 1 (phishing)")
    parse_url(record["url"])
    if calendar:
        if (
            record.get("time_precision") != "day"
            or record["label_at"] is not None
            or not re.fullmatch(r"[0-9a-f]{40}", record.get("source_version", ""))
        ):
            raise ValueError(
                "Source collection dates must preserve unknown exact label time and pinned revision"
            )
        day = date.fromisoformat(record["observed_at"])
        if day > datetime.now(timezone.utc).date():
            raise ValueError("Future collection date")
        timestamp(record.get("labels_available_by"))
        if record.get("threat"):
            raise ValueError(
                "Day-only historical data cannot infer contemporaneous blacklist state"
            )
    else:
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


def partition(rows, validation_start, test_start, protocol="event_time"):
    if protocol not in {"event_time", "retrospective_collection_date"}:
        raise ValueError("Unknown evaluation protocol")
    validation_at, test_at = timestamp(validation_start), timestamp(test_start)
    if validation_at >= test_at:
        raise ValueError("Validation must precede test")
    parts = {"train": [], "validation": [], "test": []}
    audit = {"duplicates": 0, "excluded_overlap": 0, "input": len(rows)}
    ordered = sorted((validate_record(x) for x in rows), key=lambda x: observation_bounds(x)[0])
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
        # Near endpoints are grouping keys, not proof of duplicate content. Different
        # form IDs/query values may be independently legitimate or phishing.
        f = hashlib.sha256(r["url"].encode()).hexdigest()
        if f in seen:
            if seen[f] != r["label"]:
                raise ValueError(
                    "Conflicting labels for duplicate endpoint; review before splitting"
                )
            audit["duplicates"] += 1
            continue
        seen[f] = r["label"]
        dt = observation_bounds(r)[0]
        split = "train" if dt < validation_at else "validation" if dt < test_at else "test"
        # Labels learned after a boundary cannot be used to choose a model for that boundary.
        if not fits_split(r, split, validation_at, test_at, protocol):
            reason = (
                "source_split_restriction"
                if (
                    (r.get("reserved_for") == "test" and split != "test")
                    or (r.get("reserved_for") == "development" and split == "test")
                )
                else (
                    "ambiguous_date_boundary"
                    if r.get("temporal_basis") == "source_collection_date"
                    else "late_labels"
                )
            )
            audit[reason] = audit.get(reason, 0) + 1
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
    parser.add_argument(
        "--protocol", choices=["event_time", "retrospective_collection_date"], default="event_time"
    )
    args = parser.parse_args()
    output = Path(args.output)
    if output.exists():
        raise SystemExit("Use a new output directory; locked split files are never overwritten")
    parts, audit = partition(
        read_records(args.input), args.validation_start, args.test_start, args.protocol
    )
    output.mkdir(parents=True)
    manifest = {
        "input_sha256": sha(args.input),
        "validation_start": args.validation_start,
        "test_start": args.test_start,
        "audit": audit,
        "files": {},
        "evaluation_protocol": args.protocol,
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
