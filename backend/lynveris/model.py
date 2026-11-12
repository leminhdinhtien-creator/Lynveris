import hashlib
import json
from pathlib import Path

import joblib
import sklearn

from .features import FEATURE_VERSION, features
from .schemas import ModelResult


class UrlModel:
    def __init__(self, directory=""):
        self.pipeline = None
        self.manifest = None
        self.failed = False
        self.evaluation = None
        if not directory:
            return
        try:
            root = Path(directory)
            manifest = json.loads((root / "manifest.json").read_text(encoding="utf8"))
            artifact = root / "model.joblib"
            from .service import data_versions

            if (
                manifest["feature_version"] != FEATURE_VERSION
                or manifest["policy_version"] != "model-ti-rules-v1"
                or hashlib.sha256(artifact.read_bytes()).hexdigest() != manifest["sha256"]
                or manifest["validation"]["combined"]["fpr"] > 0.05
                or not 0 < manifest["threshold"] <= 1
                or manifest["sklearn"] != sklearn.__version__
                or manifest["data_versions"] != data_versions()
                or any(
                    hashlib.sha256((Path(__file__).parent / name).read_bytes()).hexdigest()
                    != digest
                    for name, digest in manifest.get("feature_code_sha256", {}).items()
                    if name in {"features.py", "urls.py"}
                )
            ):
                raise ValueError("incompatible model")
            # Trusted local artifacts only. Never accept uploads or download pickles in the API.
            self.pipeline = joblib.load(artifact)
            self.manifest = manifest
            report_path = root / "test-report.json"
            if report_path.exists():
                report = json.loads(report_path.read_text(encoding="utf8"))
                if report.get("model_sha256") == manifest["sha256"]:
                    self.evaluation = report
        except (OSError, ValueError, KeyError, TypeError, ImportError):
            self.failed = True

    def predict(self, url: str) -> ModelResult:
        if self.pipeline is None:
            return ModelResult(status="error" if self.failed else "unavailable")
        try:
            score = float(self.pipeline.predict_proba([features(url)])[0, 1])
            return ModelResult(
                status="ready",
                version=self.manifest["version"],
                score=score,
                threshold=self.manifest["threshold"],
                policy_version=self.manifest["policy_version"],
                alert=score >= self.manifest["threshold"],
                release_stage="research",
            )
        except (ValueError, KeyError, TypeError):
            return ModelResult(status="error")
