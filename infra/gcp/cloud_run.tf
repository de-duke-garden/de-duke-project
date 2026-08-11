# De-Duke GCP Infrastructure -- Cloud Run services (replaces Fargate API +
# worker pools) and the LB's serverless backend for the API.

# ---------------------------------------------------------------------------
# API service
# ---------------------------------------------------------------------------
resource "google_cloud_run_v2_service" "api" {
  name     = "de-duke-api"
  location = var.gcp_region
  project  = var.gcp_project_id

  # Provider default is true; this service is purely code-defined infra (no
  # operator-created state inside), so replacement on config change is safe.
  deletion_protection = false

  ingress = "INGRESS_TRAFFIC_ALL"

  # Provider auto-populates this service-level scaling block from the API
  # (manual_instance_count/min_instance_count); declaring it explicitly with
  # the values the API reports prevents the perpetual `0 -> null` diff that
  # occurs when the block is left undeclared.
  scaling {
    manual_instance_count = 0
    min_instance_count    = 0
  }

  template {
    # Two dynamic scaling blocks (only one emits): the google provider
    # perpetually diffs on an explicit `min_instance_count = 0` (Cloud Run
    # normalizes it to null on read-back -- scale-to-zero IS the default),
    # so min is only emitted when actually > 0.
    dynamic "scaling" {
      for_each = var.api_min_instances > 0 ? [1] : []
      content {
        min_instance_count = var.api_min_instances
        max_instance_count = var.api_max_instances
      }
    }
    dynamic "scaling" {
      for_each = var.api_min_instances > 0 ? [] : [1]
      content {
        max_instance_count = var.api_max_instances
      }
    }

    service_account = google_service_account.backend.email

    containers {
      name  = "backend-api"
      image = local.backend_image

      # The backend listens on 8000 (Dockerfile EXPOSE/Cmd). The placeholder
      # nginx image is remapped to 8000 the same way the AWS task definition
      # does it, so the container contract matches once a real image deploys.
      command = var.image_tag != "" ? [] : ["sh", "-c", "sed -i 's/listen  *80;/listen 8000;/' /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"]

      ports {
        container_port = 8000
      }

      resources {
        cpu_idle          = true
        startup_cpu_boost = false
        limits = {
          cpu    = var.api_cpu
          memory = var.api_memory
        }
      }

      # Startup probe hits /health/live (process-alive) rather than
      # /health/ready: readiness requires Redis (cache check), which is
      # deliberately NOT deployed on GCP yet (Memorystore deferred by
      # operator choice). A readiness-based probe would permanently mark the
      # service unhealthy and the LB would never route to it. The app's own
      # /health/ready still honestly reports DB+Redis state to callers.
      dynamic "startup_probe" {
        for_each = var.image_tag != "" ? [1] : []
        content {
          http_get {
            path = "/health/live"
            port = 8000
          }
          initial_delay_seconds = 5
          timeout_seconds       = 3
          period_seconds        = 10
          failure_threshold     = 6
        }
      }

      env {
        name  = "DEDUKE_ENVIRONMENT"
        value = var.environment
      }
      env {
        name  = "LOG_LEVEL"
        value = "INFO"
      }
      # Cloud SQL Auth Proxy sidecar listens on 127.0.0.1:5432 -- the same
      # DB_PROXY_ENDPOINT contract the app already consumes (config.py
      # assembles postgresql+asyncpg://user:pass@127.0.0.1:5432/deduke).
      env {
        name  = "DB_PROXY_ENDPOINT"
        value = "127.0.0.1"
      }
      env {
        name  = "MEDIA_BUCKET_NAME"
        value = google_storage_bucket.media.name
      }
      env {
        name  = "MEDIA_CDN_DOMAIN"
        value = local.cdn_fqdn
      }
      env {
        name  = "PAYSTACK_FALLBACK_EMAIL"
        value = var.paystack_fallback_email
      }
      # Deferred on GCP for now (Memorystore not yet built): leave the app's
      # redis_url at its localhost default. The app degrades gracefully --
      # search falls back to filter/keyword-only per FEAT-031.
      # REDIS_URL intentionally omitted.

      # Same JSON contracts the app already reads:
      #   APP_SECRETS      -> app/core/config.py _apply_deployed_secrets
      #   DB_CREDENTIALS   -> username/password JSON for database_url
      env {
        name = "APP_SECRETS"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.app_secrets.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "DB_CREDENTIALS"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_credentials.secret_id
            version = "latest"
          }
        }
      }
    }

    # Cloud SQL Auth Proxy sidecar -- authenticates the TUNNEL with the
    # service account's roles/cloudsql.client and exposes 127.0.0.1:5432 to
    # the backend container on the same pod. Deliberately NO --auto-iam-authn:
    # the app authenticates to Postgres itself with the deduke_app username +
    # password from DB_CREDENTIALS (config.py's _apply_deployed_secrets), and
    # --auto-iam-authn would force IAM-based DB auth that this password user
    # cannot satisfy.
    containers {
      name  = "cloud-sql-proxy"
      image = "gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.14.3"

      args = [
        "--address=127.0.0.1",
        "--port=5432",
        local.db_connection_name,
      ]

      resources {
        limits = {
          cpu    = "0.5"
          memory = "512Mi"
        }
      }
    }
  }

  depends_on = [
    terraform_data.api_propagation,
    google_secret_manager_secret_version.app_secrets,
    google_secret_manager_secret_version.db_credentials,
  ]
}

# ---------------------------------------------------------------------------
# Worker service (Background Task Processor)
# ---------------------------------------------------------------------------
# Pub/Sub push subscription delivers messages as HTTP POSTs to this service.
# NOTE: the app codebase currently has NO SQS/Pub-Sub consumer loop
# (app/workers/* explicitly documents that wiring it is owned by other
# feature slices -- see app/workers/listing_embedding_worker.py etc.). This
# service is provisioned so the infra side (topic -> push -> Cloud Run) is
# complete and ready; the worker's receiving command/endpoint is an app-side
# wiring item at cutover (README step 3). Until a real image with a worker
# entrypoint is pushed, it runs the same placeholder image as the API.
resource "google_cloud_run_v2_service" "worker" {
  name     = "de-duke-worker"
  location = var.gcp_region
  project  = var.gcp_project_id

  # Same rationale as the API service: no operator-created state inside.
  deletion_protection = false

  ingress = "INGRESS_TRAFFIC_ALL"

  # Same service-level scaling declaration as the API service (perpetual-diff
  # prevention).
  scaling {
    manual_instance_count = 0
    min_instance_count    = 0
  }

  template {
    # Same min-instance normalization pattern as the API service.
    dynamic "scaling" {
      for_each = var.worker_min_instances > 0 ? [1] : []
      content {
        min_instance_count = var.worker_min_instances
        max_instance_count = var.worker_max_instances
      }
    }
    dynamic "scaling" {
      for_each = var.worker_min_instances > 0 ? [] : [1]
      content {
        max_instance_count = var.worker_max_instances
      }
    }

    service_account = google_service_account.backend.email

    containers {
      name  = "backend-worker"
      image = local.backend_image

      # Placeholder image: remap nginx to 8000 like the API. Once a real
      # image is deployed, set the worker entrypoint command here (app-side
      # wiring item -- do NOT invent one; the worker consumer loop does not
      # exist in the codebase yet).
      command = var.image_tag != "" ? null : ["sh", "-c", "sed -i 's/listen  *80;/listen 8000;/' /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"]

      ports {
        container_port = 8000
      }

      resources {
        cpu_idle          = true
        startup_cpu_boost = false
        limits = {
          cpu    = var.worker_cpu
          memory = var.worker_memory
        }
      }

      env {
        name  = "DEDUKE_ENVIRONMENT"
        value = var.environment
      }
      env {
        name  = "DB_PROXY_ENDPOINT"
        value = "127.0.0.1"
      }
      env {
        name  = "MEDIA_BUCKET_NAME"
        value = google_storage_bucket.media.name
      }
      env {
        name  = "MEDIA_CDN_DOMAIN"
        value = local.cdn_fqdn
      }
      env {
        name  = "PAYSTACK_FALLBACK_EMAIL"
        value = var.paystack_fallback_email
      }
      env {
        name = "APP_SECRETS"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.app_secrets.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "DB_CREDENTIALS"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_credentials.secret_id
            version = "latest"
          }
        }
      }
    }

    containers {
      name  = "cloud-sql-proxy"
      image = "gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.14.3"

      args = [
        "--address=127.0.0.1",
        "--port=5432",
        local.db_connection_name,
      ]

      resources {
        limits = {
          cpu    = "0.5"
          memory = "512Mi"
        }
      }
    }
  }

  depends_on = [
    terraform_data.api_propagation,
    google_secret_manager_secret_version.app_secrets,
    google_secret_manager_secret_version.db_credentials,
  ]
}

# ---------------------------------------------------------------------------
# LB -> Cloud Run serverless backend for the API
# ---------------------------------------------------------------------------
resource "google_compute_region_network_endpoint_group" "api" {
  name                  = "de-duke-api-neg"
  project               = var.gcp_project_id
  region                = var.gcp_region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.api.name
  }

  depends_on = [terraform_data.api_propagation]
}

resource "google_compute_backend_service" "api" {
  name    = "de-duke-api-backend"
  project = var.gcp_project_id

  protocol  = "HTTP"
  port_name = "http"

  backend {
    group = google_compute_region_network_endpoint_group.api.id
  }

  # No timeout_sec: custom timeouts are not supported for serverless NEG
  # backends (GCP enforces its own). No health_check needed either:
  # serverless NEGs are health-checked by the platform.

  depends_on = [terraform_data.api_propagation]
}

# ---------------------------------------------------------------------------
# Database migration job
# ---------------------------------------------------------------------------
# One-off Cloud Run job running `alembic upgrade head` against Cloud SQL,
# with the same proxy sidecar + env contract as the API service (mirrors the
# AWS workflow's "Run database migrations" step). Run it after every deploy
# before the new revision serves traffic.
resource "google_cloud_run_v2_job" "migrate" {
  name     = "de-duke-migrate"
  location = var.gcp_region
  project  = var.gcp_project_id

  template {
    task_count = 1

    template {
      service_account = google_service_account.backend.email

      containers {
        name  = "backend-migrate"
        image = local.backend_image

        # The image's default CMD is uvicorn (the API server); this job
        # overrides command+args to run alembic. alembic reads database_url
        # from the same DB_PROXY_ENDPOINT + DB_CREDENTIALS assembly as the API.
        command = ["alembic"]
        args    = ["upgrade", "head"]

        resources {
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }

        env {
          name  = "DEDUKE_ENVIRONMENT"
          value = var.environment
        }
        env {
          name  = "DB_PROXY_ENDPOINT"
          value = "127.0.0.1"
        }
        env {
          name = "APP_SECRETS"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.app_secrets.secret_id
              version = "latest"
            }
          }
        }
        env {
          name = "DB_CREDENTIALS"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.db_credentials.secret_id
              version = "latest"
            }
          }
        }
      }

      containers {
        name  = "cloud-sql-proxy"
        image = "gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.14.3"

        args = [
          "--address=127.0.0.1",
          "--port=5432",
          local.db_connection_name,
        ]

        resources {
          limits = {
            cpu    = "0.5"
            memory = "512Mi"
          }
        }
      }
    }
  }

  depends_on = [
    terraform_data.api_propagation,
    google_secret_manager_secret_version.app_secrets,
    google_secret_manager_secret_version.db_credentials,
  ]
}

# ---------------------------------------------------------------------------
# Admin bootstrap job
# ---------------------------------------------------------------------------
# One-off Cloud Run job running `python scripts/bootstrap_admin.py` -- the
# ONLY way to create the first deduke_admin account (FEAT-033), mirroring the
# AWS "one-off task" pattern. Cloud Run has no SSH/exec, so operator actions
# like this run as jobs. Non-interactive via ADMIN_* env vars (the script
# falls back to prompts only on a real terminal). Run via the
# admin-bootstrap workflow_dispatch (see .github/workflows/admin-bootstrap.yml).
resource "google_cloud_run_v2_job" "bootstrap_admin" {
  name     = "de-duke-bootstrap-admin"
  location = var.gcp_region
  project  = var.gcp_project_id

  template {
    task_count = 1

    template {
      service_account = google_service_account.backend.email

      containers {
        name  = "backend-bootstrap-admin"
        image = local.backend_image

        # Override the uvicorn CMD to run the bootstrap script. Admin
        # identity comes from ADMIN_* env vars supplied at job execution
        # time (never stored in the config -- gcloud run jobs execute
        # --env, or the workflow's inputs).
        command = ["python"]
        args    = ["scripts/bootstrap_admin.py"]

        resources {
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }

        env {
          name  = "DEDUKE_ENVIRONMENT"
          value = var.environment
        }
        env {
          name  = "DB_PROXY_ENDPOINT"
          value = "127.0.0.1"
        }
        env {
          name = "APP_SECRETS"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.app_secrets.secret_id
              version = "latest"
            }
          }
        }
        env {
          name = "DB_CREDENTIALS"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.db_credentials.secret_id
              version = "latest"
            }
          }
        }
      }

      containers {
        name  = "cloud-sql-proxy"
        image = "gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.14.3"

        args = [
          "--address=127.0.0.1",
          "--port=5432",
          local.db_connection_name,
        ]

        resources {
          limits = {
            cpu    = "0.5"
            memory = "512Mi"
          }
        }
      }
    }
  }

  depends_on = [
    terraform_data.api_propagation,
    google_secret_manager_secret_version.app_secrets,
    google_secret_manager_secret_version.db_credentials,
  ]
}
