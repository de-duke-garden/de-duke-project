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

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # -- Environment --
    # validation_alias="DEDUKE_ENVIRONMENT" -- a plain `environment: str`
    # field only ever reads an ENVIRONMENT env var by pydantic-settings'
    # default convention, but the ECS task definition
    # (infra/modules/fargate_service/main.tf) and .env.example both set
    # DEDUKE_ENVIRONMENT specifically. Confirmed bug: without this alias,
    # this field silently stayed "development" in every real deployed
    # environment (staging/production included) regardless of the actual
    # env var's value -- undermining anything keyed off it, e.g. Sentry's
    # environment tag (app/main.py).
    environment: str = Field(default="development", validation_alias="DEDUKE_ENVIRONMENT")
    # Observability Stack (architecture.md) -- root logger level, see
    # app/core/logging_config.py. INFO by default so the logger.info(...)
    # calls already scattered across the codebase (email_service,
    # checkout, payment_service, etc.) are actually visible instead of
    # being silently dropped by Python's unconfigured-by-default root
    # logger (WARNING level, no handler).
    log_level: str = "INFO"

    # -- Database (Primary Database, via the Connection Pooler in deployed envs) --
    database_url: str = "postgresql+asyncpg://REPLACE_ME:REPLACE_ME@localhost:5432/deduke"

    # -- Cache (Redis) --
    redis_url: str = "redis://localhost:6379/0"

    # -- Task Queue (SQS) --
    sqs_queue_url: str = "REPLACE_ME"

    # -- File Storage (S3 + CDN, see infra/modules/s3_cdn and app/core/storage.py) --
    # media_bucket_name/media_cdn_domain arrive as their own plain env vars
    # (MEDIA_BUCKET_NAME/MEDIA_CDN_DOMAIN) from the ECS task definition --
    # unlike database_url/APP_SECRETS above, these aren't secrets, so no
    # _apply_deployed_secrets-style assembly is needed; pydantic-settings'
    # env_file/env-var loading picks them up directly.
    media_bucket_name: str = "REPLACE_ME"
    media_cdn_domain: str = "REPLACE_ME"
    # AWS region for the S3 client itself (distinct from aws_region used by
    # Terraform/CI) -- defaults to the same region every environment
    # deploys into per infra/environments/*/main.tf.
    aws_region: str = "eu-west-1"
    # Only ever set locally (docker-compose.yml), to point the S3 client at
    # LocalStack instead of real AWS. Left empty ("") in every deployed
    # environment, where boto3 talks to real AWS by default.
    aws_endpoint_url: str = ""
    # Only relevant locally, and only when media_cdn_domain is unset: the
    # backend container reaches LocalStack via aws_endpoint_url's Docker
    # network hostname (`localstack`), but a developer's browser (outside
    # Docker) needs the host-published port instead (`localhost`) to
    # actually view an uploaded file. Defaults to aws_endpoint_url when
    # unset, so this only needs setting when the two legitimately differ
    # (as they do in docker-compose.yml).
    media_local_public_base_url: str = ""

    # -- SMS (Amazon SNS, app/services/sms_service.py) --
    # No longer used by FEAT-001 (phone sign-up/login OTP now runs through
    # Firebase Authentication's own phone/OTP flow client-side) -- kept
    # configured for any future backend-initiated SMS need, see
    # sms_service.py's module docstring. No separate third-party
    # vendor/secret needed (unlike Paystack/SES below) -- SNS uses the
    # same AWS account/IAM role already granted to this task
    # (infra/environments/*/iam.tf). Still gated on this being a real,
    # non-placeholder value before actually sending: Nigeria's mobile
    # networks filter SMS from an unregistered Sender ID, so a real one
    # must be registered with AWS SNS first, not just configured here.
    aws_sns_sender_id: str = "REPLACE_ME"

    # -- Auth --
    jwt_signing_secret: str = "REPLACE_ME"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 14  # 14 days, mobile-first session persistence

    # -- Third-party providers (all REPLACE_ME until populated from Secrets Manager) --
    paystack_secret_key: str = "REPLACE_ME"
    # Removed `paystack_webhook_secret` as a separate field -- confirmed
    # confusing in practice (the "PAYSTACK_WEBHOOK_SECRET" name suggested a
    # distinct value existed to copy from the Paystack dashboard, but
    # Paystack signs every webhook payload with your account's ordinary
    # SECRET key via HMAC-SHA512; there is no separate "webhook secret" it
    # issues anywhere. `payment_service.verify_webhook_signature` now keys
    # its HMAC off `paystack_secret_key` directly -- one value to configure,
    # matching how Paystack itself actually works.
    paystack_public_key: str = "REPLACE_ME"
    # FEAT-013 checkout AC: Paystack's `/transaction/initialize` requires a
    # real-looking `email` field and 400s on anything else -- but FEAT-001's
    # Firebase phone/OTP sign-in never collects an email at all, so
    # `User.email` is genuinely null for some payers (see
    # app/api/v1/checkout.py's `initiate_checkout`). A plain Settings field
    # (not a Secrets Manager entry -- this isn't sensitive) rather than a
    # hardcoded literal, so it's replaceable per environment/at any time
    # without a code change -- set PAYSTACK_FALLBACK_EMAIL in .env locally,
    # or as a plain (non-secret) env var on the ECS task definition/GitHub
    # Environment variable in deployed environments.
    paystack_fallback_email: str = "info@de-duke.com"
    google_maps_api_key: str = "REPLACE_ME"
    firebase_service_account_json: str = "REPLACE_ME"
    firestore_project_id: str = "REPLACE_ME"
    fcm_server_key: str = "REPLACE_ME"
    aws_ses_sender_email: str = "REPLACE_ME"
    sentry_dsn: str = "REPLACE_ME"
    analytics_write_key: str = "REPLACE_ME"

    # -- Business rules (defaults per features.md; admin-configurable at runtime where noted) --
    booking_hold_duration_minutes: int = 15  # FEAT-032 default; see risk_log.md R-018

    # -- Semantic Search / Embeddings (FEAT-031) --
    # Vendor chosen: Gemini (Google's `gemini-embedding-001` model via
    # generativelanguage.googleapis.com -- see
    # app/services/embedding_service.py's GeminiEmbeddingProvider). "local"
    # remains the zero-dependency, deterministic fallback that
    # get_embedding_provider() still returns whenever embedding_provider !=
    # "gemini" or gemini_api_key is still REPLACE_ME -- an incomplete/typo'd
    # config must never hard-break search, only run it in degraded mode.
    embedding_provider: str = "local"
    embedding_api_key: str = "REPLACE_ME"
    # Google AI Studio API key for the Gemini embedding endpoint -- a
    # distinct Google API product/key from google_maps_api_key above.
    gemini_api_key: str = "REPLACE_ME"
    # Must match app/models/listing.py's Listing.description_embedding Vector
    # column width -- changing this requires a new Alembic migration (a
    # pgvector Vector column is fixed-width), not just a config change.
    embedding_dimensions: int = 256
    # Bounded timeout for the *query-time* embedding call inside
    # search_service.search_listings -- keeps a single slow/unavailable
    # ranking service from ever stalling a search request (FEAT-031 AC +
    # AGENTS.md's external-dependency resilience rule). The background
    # (re)embedding worker uses its own, more generous timeout since it is
    # not user-facing -- see app/workers/listing_embedding_worker.py.
    semantic_search_timeout_seconds: float = 0.4
    # Cache TTL for repeated/common first-page free-text search results
    # (FEAT-031 AC) -- 5 minutes, within the "short TTL, e.g. 5-10 min"
    # guidance; stored in the shared Cache (Redis), never per-task memory.
    semantic_search_cache_ttl_seconds: int = 300

    # -- Cross-app links --
    # Base URL of the Admin Web Console (apps/admin-console), used to build
    # links that leave the backend's own response (e.g. FEAT-033 staff
    # invite links). Never hardcode this -- it differs per environment
    # (local dev, staging, production).
    admin_console_url: str = "http://localhost:3000"
    # Placeholder base for FEAT-012's Agency Team invite link -- distinct
    # from admin_console_url above: agency team members accept their invite
    # in the MOBILE app (AcceptInviteScreen), not the Admin Web Console, so
    # this must never reuse admin_console_url (that was a real bug -- see
    # app/api/v1/agency.py's fix). Update once a real marketing/landing
    # domain and mobile deep-linking are configured.
    mobile_app_invite_base_url: str = "https://app.deduke.example"
    # Base URL of the public marketing site (apps/marketing-site), now that
    # Android App Links (see apps/mobile/android/app/src/main/
    # AndroidManifest.xml's autoVerify intent-filter) and the
    # apps/marketing-site/public/.well-known/assetlinks.json it requires
    # ARE configured (unlike mobile_app_invite_base_url above, which still
    # predates that work). Used to build `Paystack.initialize`'s
    # `callback_url` (see payment_service.initiate_paystack_transaction) --
    # Paystack's hosted checkout redirects the guest's browser here after
    # payment, and this specific host+path is what the marketing site's
    # `.well-known/assetlinks.json` declares the app as the verified
    # handler for, so Android intercepts the redirect and opens the app
    # directly instead of the browser ever rendering the fallback page.
    marketing_site_url: str = "https://de-duke.com"

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
                "GOOGLE_MAPS_API_KEY": "google_maps_api_key",
                "FIREBASE_SERVICE_ACCOUNT_JSON": "firebase_service_account_json",
                "FIRESTORE_PROJECT_ID": "firestore_project_id",
                "FCM_SERVER_KEY": "fcm_server_key",
                "AWS_SES_SENDER_EMAIL": "aws_ses_sender_email",
                "SENTRY_DSN": "sentry_dsn",
                "ANALYTICS_WRITE_KEY": "analytics_write_key",
                "JWT_SIGNING_SECRET": "jwt_signing_secret",
                "GEMINI_API_KEY": "gemini_api_key",
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
