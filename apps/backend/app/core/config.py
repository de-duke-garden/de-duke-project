"""Application configuration, loaded from environment variables.

In deployed environments, DATABASE_URL and the individual APP_SECRETS fields
arrive via the ECS task definition's `secrets` block (see
infra/modules/fargate_service), sourced from AWS Secrets Manager. Locally,
they come from a `.env` file (see `.env.example`) that a developer populates
by hand from Secrets Manager -- never committed to source control.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # -- Environment --
    environment: str = "development"

    # -- Database (Primary Database, via the Connection Pooler in deployed envs) --
    database_url: str = "postgresql+asyncpg://REPLACE_ME:REPLACE_ME@localhost:5432/deduke"

    # -- Cache (Redis) --
    redis_url: str = "redis://localhost:6379/0"

    # -- Task Queue (SQS) --
    sqs_queue_url: str = "REPLACE_ME"

    # -- Auth --
    jwt_signing_secret: str = "REPLACE_ME"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 14  # 14 days, mobile-first session persistence

    # -- Third-party providers (all REPLACE_ME until populated from Secrets Manager) --
    paystack_secret_key: str = "REPLACE_ME"
    paystack_public_key: str = "REPLACE_ME"
    paystack_webhook_secret: str = "REPLACE_ME"
    google_maps_api_key: str = "REPLACE_ME"
    firebase_service_account_json: str = "REPLACE_ME"
    firestore_project_id: str = "REPLACE_ME"
    fcm_server_key: str = "REPLACE_ME"
    aws_ses_sender_email: str = "REPLACE_ME"
    sentry_dsn: str = "REPLACE_ME"
    analytics_write_key: str = "REPLACE_ME"

    # -- Business rules (defaults per features.md; admin-configurable at runtime where noted) --
    booking_hold_duration_minutes: int = 15  # FEAT-032 default; see risk_log.md R-018

    # -- Cross-app links --
    # Base URL of the Admin Web Console (apps/admin-console), used to build
    # links that leave the backend's own response (e.g. FEAT-033 staff
    # invite links). Never hardcode this -- it differs per environment
    # (local dev, staging, production).
    admin_console_url: str = "http://localhost:3000"


@lru_cache
def get_settings() -> Settings:
    return Settings()
