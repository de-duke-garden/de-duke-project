# AGENTS.md — De-Duke

## 1. Source of Truth

`docs/De-Duke/` is the **primary source of truth** for product requirements, features, design, data model, and rollout order. This file is a **complementary quick-reference only** — if it ever conflicts with `docs/De-Duke/`, the docs win and this file should be corrected.

## 2. Tech Stack

Stack is fully specified by `docs/De-Duke/architecture.md` — pin to latest stable within each major version at time of scaffolding:

| Layer | Choice | Notes |
|---|---|---|
| Mobile client | Flutter (Dart, latest stable channel) | Cross-platform iOS + Android |
| Backend API | FastAPI (Python, async-first) | Stateless containers on AWS Fargate |
| ORM / Schema | SQLModel (SQLAlchemy 2.0 async core) + GeoAlchemy2 (PostGIS columns) + pgvector-sqlalchemy (embedding columns) | ORM models only — kept separate from API request/response Pydantic schemas |
| Migrations | Alembic | Autogenerate off `SQLModel.metadata`; expand-contract pattern only |
| Primary DB | PostgreSQL + PostGIS + pgvector | Writer + read replicas from launch |
| Chat store | Google Cloud Firestore | Real-time three-way chat; separate from Primary DB |
| Cache | Redis (Multi-AZ) | Hot search results, embeddings, rate-limit counters |
| Task queue | Amazon SQS (+ DLQ) | Background Task Processor consumes |
| File storage | Amazon S3 + CDN | Listing photos, verification docs |
| Payments | Paystack | Checkout, commission capture, subscription billing |
| Maps/Geocoding | Google Maps API | Address autocomplete, reverse geocoding, embedded maps |
| Push | Firebase Cloud Messaging | |
| Email | Amazon SES | Transactional email |
| Error tracking | Sentry (or equivalent) | |
| Analytics | Amplitude/Mixpanel or self-hosted equivalent | Feeds FEAT-034/FEAT-035 dashboards |
| IaC | Terraform | All AWS infra, version-controlled |
| CI/CD | GitHub Actions | Test → build → ECR push → terraform → rolling Fargate deploy → smoke tests |
| Admin Web Console | Next.js (latest stable) | Staff/Admin operational tool |
| Marketing Website (Phase 5) | Next.js (latest stable), statically-generated (SSG export) + Three.js/React Three Fiber for the Hero | Fully independent deploy target, zero backend dependency |

Auth: email or phone (OTP) + secure session tokens, stateless validation on every request, role-based access (seeker, individual_host, agency, corporate, deduke_staff, deduke_admin).

Deployment: AWS single-region, Multi-AZ, Dev/Staging/Production environments, each with isolated Terraform state.

## 3. Project Structure

Monorepo, top-level `apps/` — confirmed structure:

```
de-duke-project/
├── docs/De-Duke/          # Source of truth (do not edit as part of implementation)
├── AGENTS.md
└── apps/
    ├── mobile/            # Flutter app (feature-first: lib/features/<feature>/{screens,logic,data})
    │   ├── lib/
    │   │   ├── core/          # theme, routing, shared widgets, utils, API client
    │   │   ├── features/      # one folder per feature slice (auth, listings, chat, payments, ...)
    │   │   └── main.dart
    │   └── test/
    ├── backend/           # FastAPI service
    │   ├── app/
    │   │   ├── api/v1/        # versioned routers
    │   │   ├── models/        # ORM models (mirrors schema.md entities)
    │   │   ├── schemas/        # Pydantic request/response schemas
    │   │   ├── services/       # business logic (verification, search, payments, commission)
    │   │   ├── workers/        # background task processor jobs
    │   │   └── core/           # config, security, db session, dependencies
    │   ├── tests/
    │   └── alembic/            # migrations (expand-contract pattern)
    ├── admin-console/     # Staff/Admin web console
    └── marketing-site/    # Phase 5, independent deploy, own CI/CD
infra/                     # Terraform (networking, Fargate, RDS, Redis, S3, CDN, WAF, Secrets)
```

Naming: snake_case for Python modules/files, PascalCase for Dart classes and Python Pydantic/ORM models, lowerCamelCase for Dart variables/functions, kebab-case for API routes.

## 4. Coding Style & Conventions

- **Flutter/Dart:** `dart format`, `flutter analyze` clean before commit. Prefer feature-first folders (see above) with layered internal structure (UI/state separated from data access, per `architecture.md`'s Client Application component). Data access isolated into its own package/module.
- **Python/FastAPI:** `ruff` for lint + format, `mypy` for type checking. Async-native throughout (async DB driver, async endpoint handlers) — never block the event loop. Pydantic v2 models for all request/response contracts.
- **ORM layer:** SQLModel classes in `app/models/` map 1:1 to `schema.md` entities (table-per-type FK relationships for polymorphic entities — e.g. `HostAccount` + its 6 subtype tables, `Listing` + `CommercialListing`/`ShortletListing` — never SQLAlchemy joined-table inheritance). `Listing.location` uses a `GeoAlchemy2` `Geography` column; listing/query embeddings use `pgvector-sqlalchemy`'s `Vector` column. **ORM models are never reused as API schemas** — every endpoint defines its own Pydantic request/response schema in `app/schemas/`, so role-based field visibility (e.g. hiding `statusReason` from non-staff) and the structured multi-file upload contract stay decoupled from the raw DB row shape.
- **Migrations:** Alembic autogenerate against `SQLModel.metadata`, always reviewed and hand-edited before applying — never trust autogenerate blindly for PostGIS/pgvector column types. Every migration follows the expand-contract pattern (add new shape → backfill → cut over → remove old shape in a later deploy) — never a breaking single-step migration.
- **Multi-file/multi-record uploads** (listing photos, room details, host verification documents): always use the structured contract from `architecture.md` — a JSON array of sub-record objects with an explicit `id`/temp-key per entry, matched against multipart file fields. Never encode array index + field name into ad hoc form-field names (e.g. `image__0__is_primary`).
- **API versioning:** all endpoints under `/v1/...` from first release.
- **Pagination:** cursor-based (keyset) for every list-returning endpoint — never offset/page-number.
- **Idempotency:** all checkout/payment-initiating requests carry a client-generated idempotency key.

## 5. Behavior Rules

- Never mark a payment/booking "succeeded" from a client-reported result alone — only a verified, signature-checked Paystack webhook can do that.
- Every external dependency call (Paystack, Google Maps, FCM, SES, embedding model) uses a bounded timeout + circuit breaker; degrade gracefully (e.g., keyword-only search fallback for FEAT-031) rather than cascading failure.
- Every sensitive Admin Web Console action (ban listing, resolve dispute, change commission rate, invite/deactivate/promote staff, view a conversation) writes an immutable `AuditLogEntry` before/as part of the action taking effect.
- Never implement a negotiation/offer/counter-offer UI or endpoint anywhere — all pricing is fixed, per `features.md` FEAT-011's removal note.
- Enforce role/permission checks server-side, never rely on hiding UI elements client-side (Staff vs Admin, Owner vs professionally-verified host types).
- Rate limiting and hold-expiry counters live in the shared Cache (Redis) — never per-task in-memory state, since the backend runs as many stateless Fargate tasks.
- Never commit secrets (`.env`, `.env.json`, service account JSON, DB credentials) — use the Secrets Store / local `.env.example` (or `.env.example.json` for mobile) only. Never hardcode a backend URL, API key, or secret directly in source for any app -- always go through the relevant env file.
- Prefer creating new commits over amending; use feature branches; PRs run tests + lint via GitHub Actions before merge.
- **Commit messages must follow Conventional Commits** (`type(scope): description`, e.g. `feat(mobile): add host verification upload flow`, `fix(backend): correct commission rounding`). Allowed types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `ci`, `build`. Scope should name the app/module (`mobile`, `backend`, `admin-console`, `marketing-site`, `infra`).
- Every filterable/sortable field exposed in the UI (FEAT-007) must be backed by a database index — never ship an unindexed "coming soon" filter.
- Every screen must implement all states listed in `screens.md` (loading, empty, error, offline, submitting, validation error) — partial implementations are not acceptable.
- Accessibility is non-negotiable: 48x48px minimum touch targets, WCAG AA contrast, icon+text pairing for all status indicators (never color alone), visible focus rings on web/admin surfaces.

## 6. Document Map

| Document | Use When |
|---|---|
| `docs/De-Duke/README.md` | Understanding product concept, target audience, and SWOT-derived business constraints |
| `docs/De-Duke/user_personas.md` | Making UX decisions, setting onboarding depth, choosing UI complexity per role (Amaka/Tunde/Ngozi/David) |
| `docs/De-Duke/branding.md` | Implementing theme, colors, typography, spacing, dark mode, accessibility, component tokens (mobile app + admin console); creative/motion direction for the Marketing Website |
| `docs/De-Duke/features.md` | Implementing or modifying any FEAT-###, writing tests against acceptance criteria, checking feature dependencies |
| `docs/De-Duke/roadmap.md` | Determining implementation order and launch (Phase 1) scope; what's explicitly deferred |
| `docs/De-Duke/monetization.md` | Implementing commission deduction, Agency Tier gating, subscription billing events, key metrics instrumentation |
| `docs/De-Duke/risk_log.md` | Adding resilience: circuit breakers, graceful degradation, hold-expiry job monitoring, audit logging, NDPR-compliant data handling |
| `docs/De-Duke/user_flow.md` | Implementing navigation, validation rules, decision points, error/offline handling per flow |
| `docs/De-Duke/website-design-patterns.md` | Marketing Website only: render loop, WebGL/Canvas layer stack, scroll engine, shader pipeline, per-section motion strategy, AI asset prompts |
| `docs/De-Duke/screens.md` | Building any screen — route, platform components, data needs, and ALL states (loading/empty/error/offline/submitting/validation) |
| `docs/De-Duke/architecture.md` | Scaffolding project structure, connecting data stores, wiring external integrations, cross-cutting concerns (auth, payment correctness, security, resilience) |
| `docs/De-Duke/schema.md` | Creating data models/ORM classes, migrations, API request/response contracts, entity relationships |

## 7. Local Development (docker-compose)

`docker-compose.yml` at the repo root runs a local stack mirroring `architecture.md`'s managed services, so backend features can be built and tested end to end before touching any deployed AWS environment:

| Service | What it is | Emulates |
|---|---|---|
| `db` | `garapadev/postgres-postgis-pgvector:latest` (Postgres 16 + PostGIS 3.4 + pgvector) | Primary Database |
| `redis` | `redis:7-alpine` | Cache |
| `localstack` | `localstack/localstack:3`, SQS only | Task Queue (SQS + DLQ) |
| `backend` | Built from `apps/backend/Dockerfile.dev` (hot-reload, bind-mounted source) | Backend API Service |

**Not emulated locally:**
- **Chat Data Store (Firestore)** — no local emulator; point `FIRESTORE_PROJECT_ID`/`FIREBASE_SERVICE_ACCOUNT_JSON` in `apps/backend/.env` at a real, free-tier GCP project instead.
- **Third-party integrations with no local equivalent** (Paystack, Google Maps, FCM, SES, Sentry, analytics) — left at their `REPLACE_ME` defaults (`app/core/config.py`) unless you populate real sandbox credentials in `.env`. Features that don't touch these work fine without them.

**First-time setup:**
```bash
cp apps/backend/.env.example apps/backend/.env   # gitignored; fill in real sandbox creds as needed
docker compose up -d --build
docker compose exec backend alembic upgrade head
```

**Local-only port remap** (avoids colliding with other local Postgres/Redis/services you may already be running) — the app talks to these over the compose network by service name regardless:
- `db`: host `5433` → container `5432`
- `redis`: host `6380` → container `6379`
- `backend`: host `8080` → container `8000`
- `localstack`: host `4566` (unchanged)

**Common commands:**
- `docker compose up -d` — start the stack (idempotent)
- `docker compose logs -f backend` — tail backend logs
- `docker compose exec backend alembic upgrade head` — apply migrations
- `docker compose exec backend python scripts/bootstrap_admin.py` — bootstrap the first admin locally
- `docker compose exec backend python -m pytest` — run the test suite inside the container
- `docker compose down` — stop the stack (data persists in named volumes)
- `docker compose down -v` — stop and wipe all data (fresh slate)

Whenever a schema change is made (`alembic revision --autogenerate`), always test it against this stack before committing — hand-review the generated migration for the known autogenerate failure classes (missing imports, circular FK ordering, GeoAlchemy2's auto-created spatial indexes duplicating explicit ones, timezone-naive `DateTime` columns) before trusting it.

## 8. Key Commands

_To be finalized per app at scaffold time; conventions below:_

**Mobile (`apps/mobile/`):**
- `flutter pub get` — install dependencies
- Copy `.env.example.json` → `.env.json` (gitignored) and fill in real values before running; never hardcode config (e.g. `API_BASE_URL`) in Dart source — see `apps/mobile/lib/core/config/env.dart`
- `flutter run --dart-define-from-file=.env.json` — run app
- `flutter test` — unit/widget tests
- `flutter test integration_test/ --dart-define-from-file=.env.json` — integration tests
- `flutter analyze` — static analysis
- `dart format --set-exit-if-changed .` — format check

**Backend (`apps/backend/`):**
- `pip install -e .` (using `pyproject.toml`) — install dependencies
- `uvicorn app.main:app --reload` — run dev server
- `pytest` — unit/integration tests
- `ruff check . && ruff format --check .` — lint/format check
- `mypy .` — type check
- `alembic upgrade head` — apply migrations

**Infra (`infra/`):**
- `terraform plan` / `terraform apply` — per-environment infra changes

**Root:**
- `git status`, standard git flow via feature branches
