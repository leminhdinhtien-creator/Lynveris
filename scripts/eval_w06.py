"""W06 diagnostic evaluation using development data and the live local API.

The locked research test and the fitted model are read-only. The 30-case
diagnostic cohort intentionally includes observed development mistakes.
"""

import argparse
import hashlib
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import httpx
from lynveris.model import UrlModel
from lynveris.urls import inspect_url, parse_url

OUT = Path("artifacts/w06")
VALIDATION = Path("data/phreshphish-splits-20261029-v1/validation.jsonl")


def write(name, data):
    OUT.mkdir(exist_ok=True, parents=True)
    (OUT / name).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def prepare():
    target = OUT / "cohort.json"
    if target.exists():
        raise SystemExit("Existing cohort retained. Choose a new output for a new experiment.")
    model = UrlModel("artifacts/model-phreshphish-v1")
    if model.pipeline is None:
        raise RuntimeError("Compatible existing model required")
    # The first 400 stored validation rows are fixed before examining their outputs.
    rows = [json.loads(line) for line in VALIDATION.read_text(encoding="utf-8").splitlines()[:400]]
    first = []
    for label in (0, 1):
        first.extend([r for r in rows if r["label"] == label][:10])
    selected = {r["url"] for r in first}
    discovery = []
    for row in rows:
        prediction = model.predict(row["url"])
        signals = inspect_url(parse_url(row["url"])).signals
        alert = prediction.alert or any(s.severity == "strong" for s in signals)
        discovery.append(
            {
                "url": row["url"],
                "source_id": row["source_id"],
                "label": row["label"],
                "model_score": prediction.score,
                "predicted_alert": alert,
                "signals": [s.code for s in signals],
                "passed": alert == bool(row["label"]),
            }
        )
    errors = [r for r in discovery if not r["passed"] and r["url"] not in selected][:10]
    if len(errors) != 10:
        raise RuntimeError("Fewer than 10 observed mistakes in the fixed discovery sample")
    by_url = {r["url"]: r for r in rows}
    cohort = []
    for i, row in enumerate(first):
        cohort.append({"id": f"N{i + 1:02}", "selection": "fixed_first_10_per_class", **row})
    for i, error in enumerate(errors):
        cohort.append(
            {
                "id": f"R{i + 1:02}",
                "selection": "observed_development_mistake",
                **by_url[error["url"]],
            }
        )
    write(
        "discovery.json",
        {
            "observed_at": datetime.now(timezone.utc).isoformat(),
            "model": model.manifest["version"],
            "validation_sha256": digest(VALIDATION),
            "sampling": "first 400 validation rows as stored",
            "total": len(rows),
            "errors": sum(not r["passed"] for r in discovery),
            "records": discovery,
        },
    )
    write(
        "cohort.json",
        {
            "created_at": datetime.now(timezone.utc).isoformat(),
            "scope": "development diagnostic, selection enriched with errors",
            "model_version": model.manifest["version"],
            "validation_sha256": digest(VALIDATION),
            "positive_definition": "high or caution",
            "threat_intelligence": False,
            "rubric": "alert agrees with the publisher label; insufficient or HTTP failure is not a pass",
            "cases": cohort,
        },
    )
    print(
        json.dumps(
            {
                "discovery": len(rows),
                "observed_errors": sum(not r["passed"] for r in discovery),
                "cohort": len(cohort),
                "error_cases": len(errors),
            }
        )
    )


def run():
    cohort_path = OUT / "cohort.json"
    cohort = json.loads(cohort_path.read_text(encoding="utf-8"))
    baseline = json.loads(
        Path(".verification/release-baseline.json").read_text(encoding="utf-8-sig")
    )
    rows = []
    with httpx.Client(timeout=20, follow_redirects=False) as client:
        for case in cohort["cases"]:
            started = time.perf_counter()
            response = client.post(
                "http://127.0.0.1:8000/v1/check",
                json={
                    "url": case["url"],
                    "use_threat_intelligence": False,
                    "research_consent": False,
                },
            )
            if response.status_code == 429:
                time.sleep(61)
                response = client.post(
                    "http://127.0.0.1:8000/v1/check",
                    json={
                        "url": case["url"],
                        "use_threat_intelligence": False,
                        "research_consent": False,
                    },
                )
            body = response.json()
            verdict = body.get("verdict")
            passed = (
                response.status_code == 200
                and verdict in {"high", "caution", "no_signs"}
                and ((verdict in {"high", "caution"}) == bool(case["label"]))
            )
            rows.append(
                {
                    "id": case["id"],
                    "selection": case["selection"],
                    "url": case["url"],
                    "publisher_label": case["label"],
                    "source_id": case["source_id"],
                    "source_date": case["observed_at"],
                    "http": response.status_code,
                    "verdict": verdict,
                    "passed": passed,
                    "elapsed_seconds": round(time.perf_counter() - started, 3),
                    "response": body,
                }
            )
            time.sleep(2.1)
    report = {
        "checked_at": datetime.now(timezone.utc).isoformat(),
        "cohort_sha256": digest(cohort_path),
        "scope": cohort["scope"],
        "model": cohort["model_version"],
        "total": len(rows),
        "passed": sum(r["passed"] for r in rows),
        "pass_rate": sum(r["passed"] for r in rows) / len(rows),
        "cases": rows,
        "locked_files_unchanged": {
            p: digest(p) == expected for p, expected in baseline["files"].items()
        },
        "limitations": [
            "Validation data used for diagnosis; this rate is not an unbiased model quality estimate.",
            "Ten cases selected from observed errors. The cohort is intentionally difficult.",
            "Publisher labels describe historical samples, not a current assessment of the destination.",
            "Threat lookups disabled to isolate URL model and rules; current TI checked separately.",
            "No model, threshold, rule or locked test is changed by this script.",
        ],
    }
    write("eval-w06.json", report)
    print(json.dumps({k: report[k] for k in ("total", "passed", "pass_rate")}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("prepare", "run"))
    args = parser.parse_args()
    prepare() if args.action == "prepare" else run()
