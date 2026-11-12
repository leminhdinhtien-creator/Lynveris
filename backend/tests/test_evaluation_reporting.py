"""Reporting fixtures verify accounting, never claim detection quality."""

from lynveris.ml.evaluate import evaluation_report


def test_unsupported_rows_stay_in_denominators_and_missing_ti_is_not_a_baseline():
    rows = [
        {"url": "https://example.org/", "label": 0, "category": "login"},
        {"url": "https://example.net/", "label": 1, "category": "other"},
    ]
    unsupported = [{"label": 0}, {"label": 1}]
    report = evaluation_report(
        rows,
        [0.1, 0.9],
        {
            "threshold": 0.5,
            "url_only_threshold": 0.5,
            "evaluation_protocol": "retrospective_collection_date",
        },
        unsupported,
    )
    assert report["combined"]["n"] == 4
    assert report["combined"]["fn"] == 1
    assert report["combined"]["tn"] == 2
    assert report["combined"]["coverage"] == 0.5
    assert report["blacklist_only"]["status"] == "not_measurable_historical_ti_missing"
    assert report["blacklist_only"]["metrics"] is None
    assert report["new_urls"]["n"] == 0
    assert not report["hypothesis_1_supported_on_this_test"]


def test_retrospective_dates_cannot_support_h1_even_if_snapshots_are_supplied():
    rows = [
        {
            "url": "https://example.org/",
            "label": 0,
            "category": "other",
            "threat": {"status": "not_found"},
        },
        {
            "url": "https://example.net/",
            "label": 1,
            "category": "other",
            "threat": {"status": "not_found"},
        },
    ]
    report = evaluation_report(
        rows,
        [0.1, 0.9],
        {
            "threshold": 0.5,
            "url_only_threshold": 0.5,
            "evaluation_protocol": "retrospective_collection_date",
        },
    )
    assert not report["hypothesis_1_supported_on_this_test"]
