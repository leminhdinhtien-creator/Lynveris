from datetime import date

import pytest

from lynveris.ml.collection import keep_sample, metadata_record


def test_source_date_is_preserved_without_inventing_label_time():
    row = metadata_record(
        {
            "url": "https://example.org/Login?x=A",
            "label": "benign",
            "date": date(2025, 2, 4),
            "target": None,
            "sha256": "a" * 64,
        },
        "train",
    )
    assert row["url"] == "https://example.org/Login?x=A"
    assert row["source_collected_date"] == "2025-02-04"
    assert row["label_time"] is None
    assert row["label"] == 0 and row["original_split"] == "train"


def test_source_sampling_uses_only_exact_url_and_never_label_or_date():
    assert keep_sample("https://example.org/A", 8) == keep_sample("https://example.org/A", 8)
    with pytest.raises(ValueError):
        metadata_record(
            {"url": "https://example.org", "label": "uncertain", "date": date(2025, 2, 4)}, "train"
        )
