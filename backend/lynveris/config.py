from typing import Literal

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_prefix="LYNVERIS_", extra="ignore", hide_input_in_errors=True
    )
    database_url: str = "sqlite:///./lynveris.db"
    google_api_key: str = ""
    model_directory: str = ""
    cors_origins: list[str] = ["http://localhost:8080", "http://127.0.0.1:8080"]
    rate_limit_per_minute: int = Field(default=30, ge=1, le=600)
    auto_create_dev_database: bool = True
    retention_cleanup_enabled: bool = True
    threat_provider: Literal["google", "openphish", "combined"] = "google"
    openphish_academic_use: bool = False
    deployment_mode: Literal["development", "release"] = "development"

    @property
    def threat_configured(self) -> bool:
        google = bool(self.google_api_key)
        openphish = self.openphish_academic_use
        return {
            "google": google,
            "openphish": openphish,
            "combined": google and openphish,
        }[self.threat_provider]

    @model_validator(mode="after")
    def validate_release(self):
        if self.deployment_mode != "release":
            return self
        if not self.database_url.startswith("postgresql+psycopg://"):
            raise ValueError("Release requires a PostgreSQL runtime connection.")
        if self.auto_create_dev_database or not self.retention_cleanup_enabled:
            raise ValueError("Release requires explicit migrations and retention cleanup.")
        if not self.model_directory or not self.threat_configured:
            raise ValueError("Release requires a model directory and configured threat sources.")
        if any(not origin.startswith("https://") for origin in self.cors_origins):
            raise ValueError("Release CORS origins must use HTTPS.")
        return self
