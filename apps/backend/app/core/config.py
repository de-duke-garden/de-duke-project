"""Application configuration, loaded from environment variables.

In deployed environments, the individual secret fields below do NOT arrive
as their own flat env vars. The ECS task definition (see
infra/modules/fargate_service) injects three raw pieces instead:

  - DB_PROXY_ENDPOINT   (plain env var) -- the RDS Proxy hostname.
  - DB_CREDENTIALS      (secret)        -- AWS-managed master user secret
                                           JSON, `{"username": ..., "password": ...}`,
                                           sourced from RDS's
                                           `manage_master_user_password`.
  - APP_SECRETS         (secret)        -- a single JSON blob holding every
                                           other application-level secret
                                           (Paystack, JWT, Firebase, etc.),
                                           see infra/modules/secrets.

`Settings` assembles `database_url` from the first two, and flattens
APP_SECRETS' keys onto their matching fields, in `_apply_deployed_secrets`
below -- but only when a field is still at its REPLACE_ME/localhost
placeholder default, so a locally-populated `.env` file (see `.env.example`)
is never overridden.
"""

import json
import os
from functools import lru_cache

from pydantic import model_validator
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

    @model_validator(mode="after")
    def _apply_deployed_secrets(self) -> "Settings":
        """Fill in fields shipped by ECS as DB_PROXY_ENDPOINT/DB_CREDENTIALS/
        APP_SECRETS instead of their own flat env vars (see module docstring).

        Only overwrites a field when it is still at its placeholder default,
        so a developer's `.env` (loaded above via env_file) always wins.
        """
        db_proxy_endpoint = os.environ.get("DB_PROXY_ENDPOINT")
        db_credentials_raw = os.environ.get("DB_CREDENTIALS")
        if (
            self.database_url == self.model_fields["database_url"].default
            and db_proxy_endpoint
            and db_credentials_raw
        ):
            creds = json.loads(db_credentials_raw)
            username = creds["username"]
            password = creds["password"]
            # Database name is fixed per infra/modules/rds_postgres's
            # `database_name` variable (default "deduke"); it is not part of
            # either secret, so it is not templated here.
            self.database_url = (
                f"postgresql+asyncpg://{username}:{password}@{db_proxy_endpoint}:5432/deduke"
            )

        app_secrets_raw = os.environ.get("APP_SECRETS")
        if app_secrets_raw:
            app_secrets = json.loads(app_secrets_raw)
            # Maps each APP_SECRETS JSON key (see infra/modules/secrets) to
            # its matching Settings field, only replacing still-default
            # placeholder values.
            field_by_key = {
                "PAYSTACK_SECRET_KEY": "paystack_secret_key",
                "PAYSTACK_PUBLIC_KEY": "paystack_public_key",
                "PAYSTACK_WEBHOOK_SECRET": "paystack_webhook_secret",
                "GOOGLE_MAPS_API_KEY": "google_maps_api_key",
                "FIREBASE_SERVICE_ACCOUNT_JSON": "firebase_service_account_json",
                "FIRESTORE_PROJECT_ID": "firestore_project_id",
                "FCM_SERVER_KEY": "fcm_server_key",
                "AWS_SES_SENDER_EMAIL": "aws_ses_sender_email",
                "SENTRY_DSN": "sentry_dsn",
                "ANALYTICS_WRITE_KEY": "analytics_write_key",
                "JWT_SIGNING_SECRET": "jwt_signing_secret",
            }
            for key, field_name in field_by_key.items():
                if key not in app_secrets:
                    continue
                current = getattr(self, field_name)
                if current == self.model_fields[field_name].default:
                    setattr(self, field_name, app_secrets[key])

        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
