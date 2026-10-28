from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="LYNVERIS_", extra="ignore")
    database_url: str = "sqlite:///./lynveris.db"
    google_api_key: str = ""
    model_directory: str = ""
    cors_origins: list[str] = ["http://localhost:8080", "http://127.0.0.1:8080"]
    rate_limit_per_minute: int = 30
    auto_create_dev_database: bool = True
