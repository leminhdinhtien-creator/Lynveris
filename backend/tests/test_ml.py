import pytest

from lynveris.ml.data import partition, validate_record
from lynveris.ml.metrics import choose_threshold, fused_scores, metrics


def record(url="https://example.com", date="2026-01-01T00:00:00Z", **kw):
    return dict(
        url=url,
        label=0,
        observed_at=date,
        label_at=date,
        source="https://example.org/evidence",
        license="CC-BY-4.0",
        evidence="manual review of this exact URL",
        category="login",
        **kw,
    )


def test_no_fake_or_missing_timestamps():
    r = record()
    del r["observed_at"]
    with pytest.raises(ValueError):
        validate_record(r)


def test_future_threat_snapshot_rejected():
    r = record(
        threat={
            "status": "not_found",
            "checked_at": "2026-02-01T00:00:00Z",
            "source": "Google Safe Browsing",
            "snapshot_id": "abc",
        }
    )
    with pytest.raises(ValueError):
        validate_record(r)


def test_domain_and_near_duplicate_leakage_removed():
    rows = [
        record(),
        record("https://sub.example.com/path", "2026-03-01T00:00:00Z"),
        record("https://different.org", "2026-03-02T00:00:00Z"),
        record("https://third.net", "2026-05-01T00:00:00Z"),
    ]
    parts, audit = partition(rows, "2026-02-01T00:00:00Z", "2026-04-01T00:00:00Z")
    assert len(parts["train"]) == 1 and len(parts["validation"]) == 1
    assert len(parts["test"]) == 1 and audit["excluded_overlap"] == 1


def test_campaign_aliases_are_grouped_transitively_before_splitting():
    rows = [
        record("https://first.org/one", campaign="x"),
        record("https://second.net/two", "2026-03-01T00:00:00Z", campaign="y"),
        record("https://second.net/three", "2026-05-01T00:00:00Z", campaign="x"),
    ]
    parts, audit = partition(rows, "2026-02-01T00:00:00Z", "2026-04-01T00:00:00Z")
    assert len(parts["train"]) == 1
    assert not parts["validation"] and not parts["test"]
    assert audit["excluded_overlap"] == 2


def test_different_query_values_are_grouped_not_deleted_as_duplicate_labels():
    good = record("https://shared.example/view?document=legitimate")
    phish = record("https://shared.example/view?document=phishing")
    phish["label"] = 1
    parts, audit = partition([good, phish], "2026-02-01T00:00:00Z", "2026-04-01T00:00:00Z")
    assert len(parts["train"]) == 2 and audit["duplicates"] == 0


def test_threshold_uses_fpr_constraint_and_combined_policy():
    y = [0, 0, 0, 1, 1]
    scores = fused_scores([0.1, 0.2, 0.3, 0.8, 0.9], [False] * 5)
    t = choose_threshold(y, scores, max_fpr=0.05)
    m = metrics(y, [s >= t for s in scores])
    assert m["fpr"] == 0 and m["recall"] == 1
    with pytest.raises(ValueError):
        choose_threshold([0, 1], [1, 1], max_fpr=0.05, require_recall=True)


def test_confusion_and_unknown_not_hidden():
    m = metrics([1, 1, 0, 0], [True, False, True, False], concluded=[True, False, True, True])
    assert (m["tp"], m["fn"], m["fp"], m["tn"]) == (1, 1, 1, 1)
    assert m["coverage"] == 0.75 and m["unknown_rate"] == 0.25


def test_final_rules_cannot_hide_false_positives_with_threshold():
    with pytest.raises(ValueError):
        choose_threshold([0, 1], fused_scores([0.1, 0.8], [False, False], [True, False]))


def test_synthetic_pipeline_roundtrip_only_in_temporary_directory(tmp_path):
    """Software lifecycle test with synthetic labels/times; NOT detection quality evidence."""
    import json

    from lynveris.ml.data import sha
    from lynveris.ml.evaluate import evaluate
    from lynveris.ml.train import train
    from lynveris.model import UrlModel

    root = tmp_path / "splits"
    root.mkdir()
    files = {}
    for split in ("train", "validation", "test"):
        rows = []
        for label in (0, 1):
            for i in range(50):
                url = (
                    f"https://clean-{split}-{i}.org/"
                    if label == 0
                    else f"https://paypal-secure-{split}-{i}.example/login"
                )
                date = {
                    "train": "2025-01-01T00:00:00Z",
                    "validation": "2025-03-01T00:00:00Z",
                    "test": "2025-05-01T00:00:00Z",
                }[split]
                r = record(url, date)
                r["label"] = label
                r["evidence"] = (
                    "Synthetic test fixture; not a real-world observation or phishing label"
                )
                rows.append(r)
        path = root / f"{split}.jsonl"
        path.write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf8")
        files[split] = {"sha256": sha(path), "count": len(rows)}
    (root / "split-manifest.json").write_text(
        json.dumps(
            {
                "files": files,
                "validation_start": "2025-02-01T00:00:00Z",
                "test_start": "2025-04-01T00:00:00Z",
            }
        ),
        encoding="utf8",
    )
    artifact = tmp_path / "synthetic-test-artifact"
    manifest = train(root, artifact)
    model = UrlModel(str(artifact))
    assert model.predict("https://example.org/").status == "ready"
    assert manifest["validation"]["combined"]["fpr"] <= 0.05
    output = tmp_path / "test-report.json"
    report = evaluate(root, artifact, output)
    assert report["combined"]["n"] == 100
    assert report["hypothesis_1_supported_on_this_test"] is False
    with pytest.raises(FileExistsError):
        evaluate(root, artifact, tmp_path / "forbidden-rerun.json")
