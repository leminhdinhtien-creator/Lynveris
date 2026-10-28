"""Import an authorized local PhishTank export. Does not visit any listed URL."""

import argparse
import hashlib
import json
from pathlib import Path

from lynveris.ml.data import validate_record


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("export", help="JSON from documented online-valid.json endpoint")
    parser.add_argument("output")
    parser.add_argument(
        "--license-reference",
        required=True,
        help="Reviewed applicable license/terms reference",
    )
    args = parser.parse_args()
    export = Path(args.export)
    raw = export.read_bytes()
    snapshot = hashlib.sha256(raw).hexdigest()
    rows = json.loads(raw)
    count = 0
    with Path(args.output).open("x", encoding="utf8") as output:
        for row in rows:
            if row.get("verified") != "yes":
                continue
            record = dict(
                url=row["url"],
                label=1,
                observed_at=row["submission_time"],
                label_at=row["verification_time"],
                source="https://phishtank.org/developer_info.php",
                evidence=f"PhishTank community verified phish ID {row['phish_id']}; export SHA256 {snapshot}",
                license=args.license_reference,
                category="public_phishing",
                source_snapshot=snapshot,
            )
            # A current export is NOT evidence of historical blacklist state. No threat field inferred.
            validate_record(record)
            output.write(json.dumps(record, ensure_ascii=False) + "\n")
            count += 1
    print(f"Imported {count} source-labelled URLs; historical blacklist coverage remains unknown.")


if __name__ == "__main__":
    main()
