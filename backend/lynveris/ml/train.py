import argparse
import hashlib
import json
import platform
from datetime import datetime, timezone
from pathlib import Path

import joblib
import sklearn
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.feature_extraction import DictVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

from ..features import FEATURE_VERSION, features
from ..service import data_versions
from .data import fits_split, group_keys, read_records, sha, timestamp
from .metrics import choose_threshold, fused_scores, metrics


def threat_vector(rows):
    return [r.get("threat", {}).get("status") == "detected" for r in rows]


def rule_vector(rows):
    return [features(r["url"])["strong_signals"] > 0 for r in rows]


def validate_size(rows, name, minimum=50):
    for label in (0, 1):
        n = sum(r["label"] == label for r in rows)
        if n < minimum:
            raise ValueError(
                f"{name}: need at least {minimum} independent URLs of each label; label {label} has {n}"
            )


def train(split_dir, output):
    root, out = Path(split_dir), Path(output)
    if out.exists():
        raise ValueError("Use a new artifact directory to preserve model/threshold lock")
    split_manifest = json.loads((root / "split-manifest.json").read_text())
    for name in ("train", "validation"):
        if sha(root / f"{name}.jsonl") != split_manifest["files"][name]["sha256"]:
            raise ValueError("Split has changed")
    # Intentionally never read test.jsonl here.
    training, validation = (
        read_records(root / "train.jsonl"),
        read_records(root / "validation.jsonl"),
    )
    validation_at = timestamp(split_manifest["validation_start"])
    test_at = timestamp(split_manifest["test_start"])
    protocol = split_manifest.get("evaluation_protocol", "event_time")
    if validation_at >= test_at or any(
        not fits_split(r, "train", validation_at, test_at, protocol) for r in training
    ):
        raise ValueError("Training observations and labels must precede validation")
    if any(not fits_split(r, "validation", validation_at, test_at, protocol) for r in validation):
        raise ValueError("Validation observations and labels must precede the locked test boundary")
    validate_size(training, "train")
    validate_size(validation, "validation")
    if set().union(*(group_keys(r) for r in training)) & set().union(
        *(group_keys(r) for r in validation)
    ):
        raise ValueError("Train/validation leakage")
    x, y = [features(r["url"]) for r in training], [r["label"] for r in training]
    vx, vy = [features(r["url"]) for r in validation], [r["label"] for r in validation]
    models = {
        "logistic": make_pipeline(
            DictVectorizer(sparse=False),
            StandardScaler(),
            LogisticRegression(max_iter=2000, class_weight="balanced", random_state=42),
        ),
        "hist_gradient_boosting": make_pipeline(
            DictVectorizer(sparse=False),
            HistGradientBoostingClassifier(
                max_iter=150, max_leaf_nodes=15, l2_regularization=2, random_state=42
            ),
        ),
    }
    reports, candidates = {}, []
    for name, pipeline in models.items():
        pipeline.fit(x, y)
        scores = pipeline.predict_proba(vx)[:, 1]
        try:
            url_threshold = choose_threshold(vy, scores, require_recall=True)
            threshold = choose_threshold(
                vy,
                fused_scores(scores, threat_vector(validation), rule_vector(validation)),
                require_recall=True,
            )
        except ValueError as exc:
            reports[name] = {"rejected": str(exc)}
            continue
        combined = metrics(
            vy,
            fused_scores(scores, threat_vector(validation), rule_vector(validation)) >= threshold,
        )
        reports[name] = dict(
            threshold=threshold,
            url_only_threshold=url_threshold,
            combined=combined,
            url_only=metrics(vy, scores >= url_threshold),
            blacklist_only=(
                {"status": "not_measurable_historical_ti_missing", "metrics": None}
                if not any(r.get("threat") for r in validation)
                else {
                    "status": "available_snapshots_only",
                    "metrics": metrics(
                        vy,
                        threat_vector(validation),
                        concluded=[
                            r.get("threat", {}).get("status") in {"detected", "not_found"}
                            for r in validation
                        ],
                    ),
                }
            ),
        )
        candidates.append((combined["recall"], combined["precision"], name, threshold))
    if not candidates:
        raise ValueError("No useful model satisfies final combined FPR <=5% on validation")
    _, _, selected, threshold = max(candidates)
    # No refitting on validation; selected threshold remains tied to the trained estimator.
    out.mkdir(parents=True)
    artifact = out / "model.joblib"
    joblib.dump(models[selected], artifact)
    report = reports[selected]
    manifest = dict(
        version=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
        feature_version=FEATURE_VERSION,
        policy_version="model-ti-rules-v1",
        threshold=threshold,
        url_only_threshold=report["url_only_threshold"],
        sha256=sha(artifact),
        selected=selected,
        validation=report,
        candidates=reports,
        split_manifest_sha256=sha(root / "split-manifest.json"),
        split_files=split_manifest["files"],
        data_versions=data_versions(),
        feature_code_sha256={
            name: sha(Path(__file__).parent.parent / name) for name in ("features.py", "urls.py")
        },
        python=platform.python_version(),
        sklearn=sklearn.__version__,
        positive_definition="high or caution: model above locked threshold OR strong URL rule OR TI detected",
        evaluation_protocol=protocol,
        date_precision="source day with +/-14h envelope"
        if protocol == "retrospective_collection_date"
        else "event timestamp",
        development_group_hashes=sorted(
            {
                hashlib.sha256(key.encode()).hexdigest()
                for r in training + validation
                for key in group_keys(r)
            }
        ),
        limitations=[
            "Empirical FPR on validation is not a population guarantee.",
            "Scores are not calibrated phishing probabilities.",
            "No final independent test has yet been performed.",
            *(
                [
                    "Retrospective collection-day holdout. Exact label-decision times and historical TI are unavailable; not evidence for H1."
                ]
                if protocol == "retrospective_collection_date"
                else []
            ),
        ],
    )
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf8")
    return manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("splits")
    parser.add_argument("output")
    args = parser.parse_args()
    print(json.dumps(train(args.splits, args.output), indent=2))


if __name__ == "__main__":
    main()
