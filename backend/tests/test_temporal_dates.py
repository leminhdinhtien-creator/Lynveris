from datetime import datetime, timezone

import pytest

from lynveris.ml.data import fits_split, observation_bounds, partition, validate_record


def source_record(url, day):
    return dict(
        url=url,
        label=0,
        observed_at=day,
        label_at=None,
        temporal_basis="source_collection_date",
        source_version="a" * 40,
        labels_available_by="2026-02-07T00:00:00Z",
        source="https://huggingface.co/datasets/phreshphish/phreshphish",
        license="CC-BY-4.0",
        evidence="Publisher source class; collection date only; exact label time unavailable.",
        category="source_label",
        time_precision="day",
    )


def test_source_day_does_not_claim_exact_event_or_label_time():
    row = source_record("https://one.example", "2025-01-10")
    validate_record(row)
    assert row["observed_at"] == "2025-01-10" and row["label_at"] is None
    lo, hi = observation_bounds(row)
    assert lo < datetime(2025, 1, 10, tzinfo=timezone.utc) < hi
    with pytest.raises(ValueError):
        partition([row], "2025-02-01T00:00:00Z", "2025-04-01T00:00:00Z")


def test_retrospective_dates_require_explicit_protocol_and_boundary_gap():
    rows = [
        source_record("https://one.example", "2025-01-10"),
        source_record("https://two.example", "2025-03-10"),
        source_record("https://three.example", "2025-05-10"),
        source_record("https://boundary.example", "2025-02-01"),
    ]
    parts, audit = partition(
        rows,
        "2025-02-01T00:00:00Z",
        "2025-04-01T00:00:00Z",
        protocol="retrospective_collection_date",
    )
    assert [len(parts[k]) for k in ("train", "validation", "test")] == [1, 1, 1]
    assert audit["ambiguous_date_boundary"] == 1


def test_source_day_cannot_attach_today_as_historical_blacklist():
    row = source_record("https://one.example", "2025-01-10")
    row["threat"] = {"status": "not_found", "source": "OpenPhish Community"}
    with pytest.raises(ValueError):
        validate_record(row)


def test_publisher_test_cannot_become_training_even_with_old_collection_date():
    row = source_record("https://one.example", "2025-01-10")
    row["reserved_for"] = "test"
    assert not fits_split(
        row,
        "train",
        datetime(2025, 2, 1, tzinfo=timezone.utc),
        datetime(2025, 4, 1, tzinfo=timezone.utc),
        "retrospective_collection_date",
    )
