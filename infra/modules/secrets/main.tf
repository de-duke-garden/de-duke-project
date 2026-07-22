# De-Duke — Secrets Store module
# A single AWS Secrets Manager secret holds every application-level
# third-party credential. Terraform only creates the secret container and
# seeds each key with a REPLACE_ME placeholder — real values are populated
# manually by an operator directly in the AWS Secrets Manager console, never
# committed to source control or passed as Terraform variables.
#
# The database credential is a SEPARATE secret, auto-created and managed by
# AWS itself (see modules/rds_postgres's `manage_master_user_password`) —
# nothing to define here for that one.

resource "aws_secretsmanager_secret" "app" {
  name        = "${var.environment}/de-duke/app-secrets"
  description = "De-Duke application-level secrets (Paystack, Google Maps, FCM, SES, Firestore service account, Sentry, analytics). Populate manually after apply."
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id

  # NOTE: every value below is a literal placeholder. Terraform will not
  # overwrite manually-populated values on a re-apply as long as this
  # resource is not re-created — see README note on `ignore_changes`.
  secret_string = jsonencode({
    # PAYSTACK_SECRET_KEY also verifies incoming webhook signatures --
    # Paystack signs webhooks with your account's SECRET key, not a
    # separate value, so there is no PAYSTACK_WEBHOOK_SECRET key here
    # anymore (see app/services/payment_service.py's
    # verify_webhook_signature). Note: because this resource's
    # `secret_string` is under `ignore_changes` below, removing this key
    # here does NOT retroactively delete it from an already-populated,
    # already-applied secret in a live environment -- an operator would
    # still need to remove it manually from the Secrets Manager console
    # if it was ever populated there.
    PAYSTACK_SECRET_KEY           = "REPLACE_ME"
    PAYSTACK_PUBLIC_KEY           = "REPLACE_ME"
    GOOGLE_MAPS_API_KEY           = "REPLACE_ME"
    FIREBASE_SERVICE_ACCOUNT_JSON = "REPLACE_ME"
    FIRESTORE_PROJECT_ID          = "REPLACE_ME"
    FCM_SERVER_KEY                = "REPLACE_ME"
    AWS_SES_SENDER_EMAIL          = "REPLACE_ME"
    SENTRY_DSN                    = "REPLACE_ME"
    ANALYTICS_WRITE_KEY           = "REPLACE_ME"
    JWT_SIGNING_SECRET            = "REPLACE_ME"
    GEMINI_API_KEY                = "REPLACE_ME"
  })

  lifecycle {
    # After first apply + manual population in the console, later `terraform
    # apply` runs must never clobber operator-entered real values.
    ignore_changes = [secret_string]
  }
}
