import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

from ..features import features
from ..model import UrlModel
from ..urls import UrlError, inspect_url, parse_url
from .data import fits_split, group_keys, read_records, sha, timestamp
from .metrics import fused_scores, metrics
from .train import rule_vector, threat_vector, validate_size


def evaluation_report(rows, scores, manifest, unsupported=()):
    """Account for every held-out input; absent historical TI is not a measured baseline."""
    n_supported = len(rows)
    all_rows = list(rows) + list(unsupported)
    labels = [r["label"] for r in all_rows]
    detected = threat_vector(rows) + [False] * len(unsupported)
    combined = np.concatenate(
        [
            fused_scores(scores, threat_vector(rows), rule_vector(rows)) >= manifest["threshold"],
            np.zeros(len(unsupported), dtype=bool),
        ]
    )
    url_alerts = np.concatenate(
        [
            np.asarray(scores) >= manifest["url_only_threshold"],
            np.zeros(len(unsupported), dtype=bool),
        ]
    )
    concluded = [
        bool(combined[i])
        or not (
            inspect_url(parse_url(r["url"])).shortener
            or r.get("threat", {}).get("status") in {"error", "timeout", "quota", "not_configured"}
            or r.get("threat", {}).get("partial", False)
        )
        for i, r in enumerate(rows)
    ] + [False] * len(unsupported)

    def subset(indices):
        return metrics(
            [labels[i] for i in indices],
            [combined[i] for i in indices],
            concluded=[concluded[i] for i in indices],
        )

    known = {
        i
        for i, r in enumerate(rows)
        if r.get("threat", {}).get("status") in {"detected", "not_found"}
        and not r.get("threat", {}).get("partial", False)
    }
    new = [
        i
        for i, r in enumerate(rows)
        if i in known and r["label"] == 1 and r["threat"]["status"] == "not_found"
    ]
    retrospective = manifest.get("evaluation_protocol") == "retrospective_collection_date"
    baseline_status = (
        "not_measurable_historical_ti_missing"
        if not known
        else "partial_snapshot_coverage"
        if len(known) != len(all_rows)
        else "measured"
    )
    report = dict(
        threshold=manifest["threshold"],
        evaluation_protocol=manifest.get("evaluation_protocol", "event_time"),
        positive_definition=manifest.get(
            "positive_definition", "model OR strong URL rule OR TI hit"
        ),
        supported_inputs=n_supported,
        unsupported_inputs=len(unsupported),
        combined_method="model + URL rules; historical TI unavailable"
        if not known
        else "model + URL rules + available TI",
        url_only=metrics(
            labels, url_alerts, concluded=[True] * n_supported + [False] * len(unsupported)
        ),
        blacklist_only={
            "status": baseline_status,
            "n": len(all_rows),
            "observed_snapshots": len(known),
            "metrics": metrics(
                labels, detected, concluded=[i in known for i in range(len(all_rows))]
            )
            if known
            else None,
        },
        combined=subset(range(len(all_rows))),
        categories={
            c: subset(
                [
                    i
                    for i, r in enumerate(all_rows)
                    if (c in r.get("strata", [r.get("category", "unsupported")]))
                ]
            )
            for c in sorted(
                {c for r in all_rows for c in r.get("strata", [r.get("category", "unsupported")])}
            )
        },
        new_urls={
            "n": len(new),
            "recall_combined": float(np.mean(combined[new])) if new else None,
            "recall_blacklist": 0.0 if new else None,
            "improvement_percentage_points": 100 * float(np.mean(combined[new])) if new else None,
        },
        threat_snapshot_coverage=len(known) / len(all_rows),
        limitations=[
            "Unknown/unsupported inputs remain in every overall denominator as non-detections.",
            "Missing historical TI is not a measured zero-recall blacklist baseline.",
            "Current threat lookups are never substituted for historical state.",
            "Unsupported URLs cannot be verified for registrable-domain grouping; retained as operational unknowns.",
            *(
                [
                    "Collection dates have day precision; label-decision times are unknown. This is retrospective, not H1 evidence."
                ]
                if retrospective
                else []
            ),
        ],
    )
    report["hypothesis_1_supported_on_this_test"] = bool(
        not retrospective
        and new
        and report["new_urls"]["improvement_percentage_points"] >= 30
        and report["combined"]["fpr"] <= 0.05
        and len(known) == len(all_rows)
    )
    return report


def evaluate(splits, artifact, output):
    root, out = Path(splits), Path(output)
    model = UrlModel(artifact)
    if model.pipeline is None:
        raise ValueError("Compatible, locked model required")
    manifest = model.manifest
    split_manifest = json.loads((root / "split-manifest.json").read_text(encoding="utf8"))
    if sha(root / "split-manifest.json") != manifest["split_manifest_sha256"]:
        raise ValueError("Wrong dataset")
    for name in ("test", "test_unsupported"):
        if (
            name in manifest["split_files"]
            and sha(root / f"{name}.jsonl") != manifest["split_files"][name]["sha256"]
        ):
            raise ValueError("Test split changed")
    lock = Path(artifact) / "test-evaluation.lock"
    with lock.open("x", encoding="utf8") as f:
        json.dump(
            {
                "test_sha256": sha(root / "test.jsonl"),
                "manifest_sha256": sha(Path(artifact) / "manifest.json"),
            },
            f,
        )
    rows = read_records(root / "test.jsonl")
    validate_size(rows, "test")
    protocol = split_manifest.get("evaluation_protocol", "event_time")
    va, ta = timestamp(split_manifest["validation_start"]), timestamp(split_manifest["test_start"])
    development = set(manifest["development_group_hashes"])
    if any(not fits_split(r, "test", va, ta, protocol) for r in rows):
        raise ValueError("Test observations outside locked time boundary")
    if any(
        hashlib.sha256(k.encode()).hexdigest() in development for r in rows for k in group_keys(r)
    ):
        raise ValueError("Test leaks development domain/campaign/near-endpoint")
    unsupported = []
    if "test_unsupported" in manifest["split_files"]:
        for line in (root / "test_unsupported.jsonl").read_text(encoding="utf8").splitlines():
            r = json.loads(line)
            if (
                not r.get("unsupported_input")
                or r["label"] not in (0, 1)
                or not fits_split(r, "test", va, ta, protocol)
            ):
                raise ValueError("Invalid unsupported holdout record")
            try:
                parse_url(r["url"])
            except UrlError:
                unsupported.append(r)
            else:
                raise ValueError("Supported URL mislabeled as unsupported")
    scores = model.pipeline.predict_proba([features(r["url"]) for r in rows])[:, 1]
    report = evaluation_report(rows, scores, manifest, unsupported)
    report["test_sha256"] = sha(root / "test.jsonl")
    report["split_manifest_sha256"] = sha(root / "split-manifest.json")
    report["model_sha256"] = manifest["sha256"]
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
