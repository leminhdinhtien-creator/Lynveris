import argparse
import json
from pathlib import Path

import numpy as np

from ..features import features
from ..model import UrlModel
from ..urls import inspect_url, parse_url
from .data import read_records, sha
from .metrics import fused_scores, metrics
from .train import rule_vector, threat_vector, validate_size


def evaluate(splits, artifact, output):
    root, out = Path(splits), Path(output)
    model = UrlModel(artifact)
    if model.pipeline is None:
        raise ValueError("Compatible, locked model required")
    manifest = model.manifest
    if sha(root / "split-manifest.json") != manifest["split_manifest_sha256"]:
        raise ValueError("Wrong dataset")
    path = root / "test.jsonl"
    if sha(path) != manifest["split_files"]["test"]["sha256"]:
        raise ValueError("Test split changed")
    lock = Path(artifact) / "test-evaluation.lock"
    # Exclusive one-shot lock. Failed evaluation also leaves a trace.
    with lock.open("x", encoding="utf8") as f:
        f.write(
            json.dumps(
                {"test_sha256": sha(path), "manifest_sha256": sha(Path(artifact) / "manifest.json")}
            )
        )
    rows = read_records(path)
    validate_size(rows, "test")
    labels = [r["label"] for r in rows]
    scores = model.pipeline.predict_proba([features(r["url"]) for r in rows])[:, 1]
    detected = threat_vector(rows)
    combined = fused_scores(scores, detected, rule_vector(rows)) >= manifest["threshold"]
    # Match runtime's incomplete shortener/provider failure states. Unknown counts as negative,
    # not removed from the confusion matrix.
    concluded = [
        bool(combined[i])
        or not (
            inspect_url(parse_url(r["url"])).shortener
            or r.get("threat", {}).get("status") in {"error", "timeout", "quota", "not_configured"}
        )
        for i, r in enumerate(rows)
    ]

    def subset(indices):
        return metrics(
            [labels[i] for i in indices],
            [combined[i] for i in indices],
            concluded=[concluded[i] for i in indices],
        )

    known = [
        i
        for i, r in enumerate(rows)
        if r.get("threat", {}).get("status") in {"detected", "not_found"}
    ]
    # "new" must be explicitly observed absent in a contemporaneous snapshot, not unknown/error.
    new = [
        i
        for i, r in enumerate(rows)
        if r["label"] == 1 and r.get("threat", {}).get("status") == "not_found"
    ]
    report = dict(
        threshold=manifest["threshold"],
        test_sha256=sha(path),
        positive_definition=manifest["positive_definition"],
        url_only=metrics(labels, scores >= manifest["url_only_threshold"]),
        blacklist_only=metrics(
            labels, detected, concluded=[i in set(known) for i in range(len(rows))]
        ),
        combined=subset(range(len(rows))),
        categories={
            c: subset([i for i, r in enumerate(rows) if r["category"] == c])
            for c in sorted({r["category"] for r in rows})
        },
        new_urls={
            "n": len(new),
            "recall_combined": float(np.mean(combined[new])) if new else None,
            "recall_blacklist": 0.0 if new else None,
            "improvement_percentage_points": 100 * float(np.mean(combined[new])) if new else None,
        },
        threat_snapshot_coverage=len(known) / len(rows),
        limitations=[
            "Unknowns remain in all denominators.",
            "A frozen current feed is not a historical blacklist snapshot.",
        ],
    )
    report["hypothesis_1_supported_on_this_test"] = bool(
        new
        and report["new_urls"]["improvement_percentage_points"] >= 30
        and report["combined"]["fpr"] <= 0.05
        and len(known) == len(rows)
    )
    with out.open("x", encoding="utf8") as f:
        json.dump(report, f, indent=2)
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("splits")
    parser.add_argument("artifact")
    parser.add_argument("output")
    args = parser.parse_args()
    print(json.dumps(evaluate(args.splits, args.artifact, args.output), indent=2))


if __name__ == "__main__":
    main()
