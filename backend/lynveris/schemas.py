from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class Signal(BaseModel):
    code: str
    title: str
    detail: str
    severity: Literal["info", "weak", "strong"]
    source: Literal["url", "model", "threat"] = "url"


class ThreatResult(BaseModel):
    source: str = "Google Safe Browsing"
    status: Literal[
        "detected", "not_found", "error", "timeout", "quota", "not_configured", "skipped"
    ]
    checked_at: datetime | None = None
    expires_at: datetime | None = None
    cached: bool = False
    categories: list[str] = Field(default_factory=list)
    attribution: str | None = None
    advisory_url: str | None = None


class ModelResult(BaseModel):
    status: Literal["ready", "unavailable", "error"]
    version: str | None = None
    feature_version: str = "url-v1"
    policy_version: str = "conservative-v1"
    score: float | None = None  # classifier score, deliberately not called probability
    threshold: float | None = None
    alert: bool = False


class CheckRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    url: str = Field(min_length=1, max_length=4096)
    use_threat_intelligence: bool = False
    research_consent: bool = False
    deletion_token: str | None = Field(
        default=None, min_length=32, max_length=128, pattern=r"^[a-zA-Z0-9_-]+$"
    )


class UrlInfo(BaseModel):
    original: str
    hostname: str
    unicode_hostname: str
    registered_domain: str | None
    suffix: str
    scheme: str
    port: int | None
    has_userinfo: bool


class CheckResult(BaseModel):
    id: str
    checked_at: datetime
    verdict: Literal["high", "caution", "no_signs", "insufficient"]
    title: str
    summary: str
    url: UrlInfo
    signals: list[Signal]
    model: ModelResult
    threat: ThreatResult
    redirect: dict[str, str]
    limitations: list[str]
    actions: list[str]
    versions: dict[str, str]
