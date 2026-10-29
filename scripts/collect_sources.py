"""Fixed-source downloads. Never follows or opens URLs in a phishing dataset."""

import argparse
import csv
import hashlib
import io
import json
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

UCI = "https://archive.ics.uci.edu/static/public/967/phiusiil+phishing+url+dataset.zip"
SOURCE = "https://archive.ics.uci.edu/dataset/967/phiusiil+phishing+url+dataset"


def main():
    parser = argparse.ArgumentParser(
        description="Collect UCI dataset into quarantine, not temporal training"
    )
    parser.add_argument("output")
    parser.add_argument("--archive", help="Reuse an official ZIP downloaded earlier")
    args = parser.parse_args()
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=False)
    if args.archive:
        content = Path(args.archive).read_bytes()
    else:
        with urlopen(
            Request(UCI, headers={"User-Agent": "Lynveris-research/0.1"}), timeout=45
        ) as response:
            content = response.read(25_000_001)
    if len(content) > 25_000_000:
        raise ValueError("Source exceeds size limit")
    (out / "phiusiil.zip").write_bytes(content)
    with zipfile.ZipFile(io.BytesIO(content)) as archive:
        with archive.open("PhiUSIIL_Phishing_URL_Dataset.csv") as data:
            reader = csv.DictReader(io.TextIOWrapper(data, encoding="utf-8-sig"))
            columns = reader.fieldnames
            counts = {"0": 0, "1": 0}
            for row in reader:
                counts[row["label"]] += 1
    manifest = dict(
        source=SOURCE,
        download=UCI,
        license="CC-BY-4.0",
        attribution="Prasad, A. & Chandra, S. (2024), PhiUSIIL Phishing URL (Website), UCI.",
        retrieved_at=datetime.fromtimestamp(
            Path(args.archive).stat().st_mtime, timezone.utc
        ).isoformat()
        if args.archive
        else datetime.now(timezone.utc).isoformat(),
        sha256=hashlib.sha256(content).hexdigest(),
        columns=columns,
        label_counts_original=counts,
        label_mapping="UCI 0=phishing; UCI 1=legitimate",
        temporal_training_eligible=False,
        reason="No per-row observation/label timestamps. Retrieval time does not replace them.",
    )
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf8")
    print(json.dumps({k: v for k, v in manifest.items() if k != "columns"}, indent=2))


if __name__ == "__main__":
    main()
