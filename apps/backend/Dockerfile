# De-Duke Backend API Service -- built/pushed to Amazon ECR by the
# GitHub Actions pipeline (.github/workflows/backend-deploy.yml), deployed
# to AWS Fargate per architecture.md. Multi-stage so build-only tooling
# (a C compiler for any wheel that needs one) never ships in the final
# image.
FROM python:3.12-slim AS builder

WORKDIR /build

# Build-time OS deps for wheels that compile from source on slim images
# (e.g. psycopg-family / cryptography extras pulled in transitively).
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml ./
COPY app ./app

# Install into a relocatable prefix so the runtime stage can copy just the
# installed packages, not pip's build cache or the compiler toolchain.
RUN pip install --no-cache-dir --prefix=/install .

FROM python:3.12-slim AS runtime

# Runs as a non-root user -- least-privilege inside the container, matching
# the "every sensitive action" security posture the rest of this project
# holds itself to (AGENTS.md).
RUN useradd --create-home --uid 10001 appuser
WORKDIR /app

COPY --from=builder /install /usr/local
COPY app ./app
# One-off operator scripts (e.g. bootstrap_admin.py, see its own docstring)
# -- not run by the service itself, but shipped so they're reachable via
# `aws ecs execute-command` against the running task rather than needing a
# separate deploy mechanism just to invoke them.
COPY scripts ./scripts
# Migrations -- not run by the service's own CMD, but needed in-image so
# .github/workflows/backend-deploy.yml's "Run database migrations" step can
# override this container's command to `alembic upgrade head` as a one-off
# ECS task using this exact image.
COPY alembic.ini ./alembic.ini
COPY alembic ./alembic

USER appuser

# Fargate's ALB target group health check hits GET /health/ready (see
# infra/modules/fargate_service's health_check block).
EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
