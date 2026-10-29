"""Source metadata, without fabricating missing observation or label timestamps."""

import hashlib
from datetime import date


def keep_sample(url, modulus=8):
    if not 1 <= modulus <= 10000:
        raise ValueError("Invalid sampling modulus")
    return int.from_bytes(hashlib.sha256(url.encode()).digest()[:8], "big") % modulus == 0


def metadata_record(row, original_split):
    if row["label"] not in {"benign", "phish"} or original_split not in {"train", "test"}:
        raise ValueError("Unsupported source label/split")
    day = row["date"]
    day = day.isoformat() if isinstance(day, date) else day
    date.fromisoformat(day)
    return dict(
        url=row["url"],
        label=int(row["label"] == "phish"),
        source_collected_date=day,
        time_precision="day",
        label_time=None,
        target=row.get("target"),
        source_id=row.get("sha256"),
        original_split=original_split,
    )
