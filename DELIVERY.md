# De-Duke: DELIVERY.md

## 1. Source of Truth

`docs/De-Duke/` is the spec (the product is addressed as **De-Duke**). This file is coordination only, never a substitute for the docs.

## 2. Team & File Ownership

| Agent | Owns (writable) | Read-only |
|---|---|---|
| frontend-engineer | `apps/mobile/lib/` (Flutter), `apps/admin-console/src/` (Next.js admin), `apps/marketing-site/src/` (Next.js marketing) | `docs/De-Duke/`, `CONTRACTS.md`, `ASSETS.md` |
| backend-engineer | `apps/backend/app/` (FastAPI), `apps/backend/alembic/`, `apps/backend/tests/` | `docs/De-Duke/`, `CONTRACTS.md` |
| infra-engineer | `infra/` (Terraform GCP), `.github/workflows/`, `docker-compose.yml`, root build/config files | `docs/De-Duke/architecture.md`, `AGENTS.md` |
| qa-engineer | integration test suites under each app's test tree | `docs/De-Duke/`, `CONTRACTS.md` |
| image-artist | asset output dirs recorded in `ASSETS.md` | `docs/De-Duke/branding.md` |

Canonical shared files (only the Tech Lead writes): `DELIVERY.md`, `CONTRACTS.md`, `ASSETS.md`. `docs/De-Duke/` is read-only for the whole squad. Root `AGENTS.md` is a pointer that routes agents to these files.

## 3. Tech Stack

| Layer | Choice | Version |
|---|---|---|
| Mobile client | Flutter (Dart) | latest stable |
| Backend API | FastAPI (Python, async) | latest stable |
| ORM / migrations | SQLModel + SQLAlchemy 2.0 async, GeoAlchemy2, pgvector-sqlalchemy; Alembic (expand-contract) | latest stable |
| Primary DB | Cloud SQL PostgreSQL 16 (PostGIS + pgvector) via Auth Proxy sidecar | 16 |
| Chat store | Google Cloud Firestore (project `de-duke-services`) | managed |
| Cache | Upstash Redis (`rediss://`) | managed |
| Task queue | Google Cloud Pub/Sub + DLQ; Cloud Scheduler for hold-expiry sweep | managed |
| File storage | GCS + Cloud CDN | managed |
| Payments | Paystack (checkout, commission, transfers, subscription) | API |
| Maps/geocoding | Google Maps API | API |
| Push | Firebase Cloud Messaging | API |
| Email | Amazon SES | API |
| Admin console / marketing site | Next.js on Vercel | latest stable |
| IaC / CI | Terraform (GCP); GitHub Actions with Workload Identity Federation | latest stable |
| Auth | Firebase Auth (consumer) + backend-managed email/password (Staff/Admin) | - |

## 4. Project Structure

```
apps/mobile/        Flutter app (feature-first: lib/features/<feature>/{screens,logic,data})
apps/backend/       FastAPI (app/api/v1, app/models, app/schemas, app/services, app/workers, alembic)
apps/admin-console/ Next.js staff/admin console
apps/marketing-site/Next.js marketing site (SSG, cinematic 2D; content in apps/marketing-site/content/)
infra/gcp/          Terraform (the infra/environments/ AWS tree is decommissioned reference)
```

Naming: snake_case Python, PascalCase Dart classes and Pydantic models, lowerCamelCase Dart members, kebab-case API routes. All endpoints under `/v1`.

Marketing content (About page and Legal & Policy pages, FEAT-037/FEAT-038) is authored as plain Markdown in `apps/marketing-site/content/` and ships as content-only changes with no engineering involvement.

## 5. Contracts

`CONTRACTS.md` holds the frozen API surface (C-001..C-043), derived from the implemented backend. Frontend and backend build against Frozen contracts; any change is a revision that re-dispatches both owners.

## 6. Theme & Token Map

- Mobile: theme lives in `apps/mobile/lib/core/theme/` as Flutter `ThemeData`. `branding.md` tokens map to `ColorScheme` (primary `#0D6B2D`, surface, semantic states), `TextTheme` (Manrope display / Inter body / JetBrains Mono), spacing 4px grid, radius and the two-layer shadow system. Dark mode is a value swap, never separate `-dark` sibling tokens. The in-app wordmark is composed separately from the brand mark (Manrope display, 700 weight, uppercase, slight tracking), per the Logo Usage spec.
- Admin console: Tailwind config (`apps/admin-console/tailwind.config.ts`) mapping the same tokens.
- Marketing site: `apps/marketing-site/src/styles/tokens.css` plus the Cinematic 2D motion system (GSAP + ScrollTrigger, Ken Burns, mask-wipe reveals) per `branding.md` Sections 5-8.
- Extended (not in `branding.md`): none beyond the shipped tokens. Skipped: none.

## 7. Asset Ledger

`ASSETS.md` records all shipped assets (brand mark family F-001, photography family F-002), all Done. No regeneration allowed.

## 8. Coding Style & Conventions

- **Flutter/Dart:** `dart format`, `flutter analyze` clean before commit; feature-first folders; data access isolated from UI.
- **Python/FastAPI:** `ruff` lint + format, `mypy` strict; async-native handlers; Pydantic v2 request/response schemas; ORM models never reused as API schemas; cursor pagination; structured multi-file upload contract (explicit ids, never `image__0__is_primary`).
- **Migrations:** Alembic autogenerate, hand-reviewed; expand-contract only; test against docker-compose before committing.
- **Idempotency:** every payment-initiating request carries a client-generated idempotency key.

## 9. Behavior Rules

- Never commit secrets (`.env`, service account JSON, credentials); use `.env.example` / `.env.example.json` only.
- Run tests before committing; Conventional Commits with `Implements: <FEAT-###>`.
- Never write to `docs/De-Duke/`.
- Style only through theme tokens; no hardcoded colors.
- A payment/booking is never marked succeeded from a client-reported result; only a verified Paystack webhook.
- No negotiation/offer UI or endpoint anywhere (fixed pricing).
- Role checks enforced server-side, never by hiding UI.
- Humanize any user-facing copy you author via the `humanizer` skill, deferring to `branding.md` tone.

## 10. Document Map

| Document | Read by | For |
|---|---|---|
| `docs/De-Duke/README.md` | all | Product concept, scope, market |
| `user_personas.md` | frontend | UX depth per persona |
| `branding.md` | frontend, image-artist | Theme tokens, creative/motion brief |
| `features.md` | all | FEAT-### specs, acceptance criteria, dependencies |
| `roadmap.md` | tech-lead, all | Phase ordering (window: April 2025 - August 2026) |
| `architecture.md` | all | Components, data stores, integrations, deployment |
| `monetization.md` | backend, tech-lead | Commission, gates, billing events |
| `risk_log.md` | all | Mitigations to implement (circuit breakers, reconciliation) |
| `user_flow.md` | frontend | Navigation, validation, offline/error paths |
| `screens.md` + `screens/` | frontend | Screen specs, states, data needs |
| `schema.md` | backend | Entities, relationships, request/response shapes |

## 11. Task Board

The product is fully implemented. The board below records the baseline so future work starts from a verified state. `Verified` marks code that passed the implemented test suites; the squad's first QA pass can re-verify and update these.

| Task | Feature | Owner | Status | Depends On | Contract | Verified |
|---|---|---|---|---|---|---|
| T-001 | Foundation: scaffold, CI/CD, infra | infra | Done | - | - | Yes (implemented) |
| T-002 | Foundation: backend models/auth/API | backend | Done | - | - | Yes (implemented) |
| T-003 | Foundation: mobile theme/routing | frontend | Done | - | - | Yes (implemented) |
| T-004 | Phase 1 (20 P0 features) | squad | Done | T-001..003 | C-001..C-043 | Yes (implemented) |
| T-005 | Phase 2 (13 P1 features) | squad | Done | T-004 | C-001..C-043 | Yes (implemented) |
| T-006 | Phase 3 (11 P2 features) | squad | Done | T-005 | C-001..C-043 | Yes (implemented) |
| T-007 | Phase 4 (FEAT-018) | squad | Done | T-006 | C-036 | Yes (implemented) |
| T-008 | Phase 5 (Marketing Website) | squad | Done | T-004 (FEAT-037) | - | Yes (implemented) |
| T-009 | Contracts frozen from implemented code | tech-lead | Done | - | C-001..C-043 Frozen | - |
| T-010 | Docs regenerated as De-Duke | product-shaper | Done | - | - | - |
| T-011 | iOS crash fix: add GMSApiKey slot to `ios/Runner/Info.plist` (empty placeholder + comment) | frontend | Done | - | - | Verified: key present in build-8 IPA artifact |
| T-012 | iOS crash fix: inject GOOGLE_MAPS_API_KEY into `ios/Runner/Info.plist` (GMSApiKey) before `flutter build ipa` | infra | Done | T-011 (order-robust: insert-or-replace) | - | Verified: injection ran in run 35846312791; GMSApiKey (len 39) confirmed in built `Runner.app/Info.plist` |
| T-013 | iOS crash fix: call `GMSServices.provideAPIKey()` in `AppDelegate.swift` from the injected `GMSApiKey` slot before engine start | frontend | Done | T-011, T-012 | - | Build 10 (run 35900589443) green; key confirmed in artifact; device test pending |
| T-014 | Domain migration: preserve `.com` zone, add `.org` zone in `infra/gcp` | infra | Done | - | - | `.com` zone/records unchanged in plan; `de-duke-org` zone created |
| T-015 | Domain migration: delegate `de-duke.org` to Cloud DNS at Namecheap | infra | In Progress | T-014 | - | - |
| T-016 | Domain migration: create `.org` records + swap LB cert/url-map to `.org` | infra | Backlog | T-015 | - | - |
| T-017 | Domain migration: rename backend/marketing/admin/mobile/CI to `de-duke.org` | squad | Backlog | T-016 | - | - |
| T-018 | Domain migration: rebuild mobile, fix assetlinks SHA-256, verify App Links on `.org` | frontend+infra | Backlog | T-017 | - | - |
| T-019 | Domain migration: update store listings, route docs to product-shaper, final sweep | squad | Backlog | T-018 | - | - |
| T-020 | iOS release: preserve the built IPA when an upload fails (`if: always()` artifact) and add `reuse-ipa-from-run` to retry the upload without rebuilding | infra | Done | - | - | YAML parses, gates verified; pending a live retry run |

**Open:** no dispatched work. Root cause chain complete: plugin never calls `provideAPIKey`, SDK `+sharedServices` throws without it (builds 8-9 proved plist-only insufficient). T-013 lands the missing initialization; build 10 is with the tester — final sign-off is the device opening Listing Detail without the crash. Next work is defined by the user (new features, fixes, or a QA re-baseline pass).

## 12. Decisions Log

| ID | Decision | Rationale | Date | Author |
|---|---|---|---|---|
| D-001 | Regenerate product docs as `docs/De-Duke/`; product addressed as De-Duke | Docs were produced by an older process; user requested regeneration | 2026-09-12 | User |
| D-002 | Experience Tier = Creative; Target Platform = Cross-platform | Marketing site is a Creative-tier surface; mobile iOS/Android plus web surfaces | 2026-09-12 | User |
| D-003 | Remove `CHANGENOTE.md` and `website-design-patterns.md`; absorb marketing creative direction into `branding.md` | Docs are product spec, not logs; new skill system places creative direction in branding | 2026-09-12 | Tech Lead |
| D-004 | Consolidate risk log to 15 risks; drop dated Risk Trends changelog | Skill caps top risks; dated table is log content | 2026-09-12 | Tech Lead |
| D-005 | FEAT-040 no longer depends on FEAT-012 | FEAT-012 is P2/Phase 3, FEAT-040 is P1/Phase 2; the collision scenario is not a hard blocker | 2026-09-12 | Tech Lead |
| D-006 | Roadmap timeline condensed to April 2025 - August 2026, all phases kept | User directive; earlier dates were not followed | 2026-09-12 | User |
| D-007 | Freeze API contracts from the implemented backend (code is the contract) | Product is fully implemented; contracts must reflect reality | 2026-09-12 | Tech Lead |
| D-008 | Delete `IMPLEMENTATION.md`; replace `AGENTS.md` with a pointer that routes agents to ASSETS/CONTRACTS/DELIVERY/docs. iOS local runbook preserved in `ios-release.yml` comments; docker-compose local-dev details moved into DELIVERY.md Key Commands | Both files served the old Implementor flow only; any agent now works from the coordination files and the spec | 2026-09-12 | User |
| D-009 | Fix iOS Listing-Detail crash by injecting `GOOGLE_MAPS_API_KEY` into `ios/Runner/Info.plist` (`GMSApiKey`) at CI build time; keep an empty placeholder in source | Native Google Maps iOS SDK requires the key registered via `GMSApiKey`; the release workflow only passed it as a Dart define, so the first `GoogleMap` (Listing Detail's location preview) crashed on iOS/TestFlight. Android unaffected (manifest wiring). Secret stays out of the repo; inject-or-replace makes commit ordering irrelevant | 2026-09-22 | User (confirmed fix approach) |
| D-010 | Migrate every public surface from `de-duke.com` to `de-duke.org` | The old domain is registered/DNS-hosted on AWS with no remaining access. This is a hard cutover: no `.com` redirect layer is possible, and already-shipped app builds that hardcode `api.de-duke.com` will break until a new release ships | 2026-11-02 | User |
| D-011 | Move email addresses (`info`, `hello`, `legal`, `privacy`, `support`, `noreply`) to `@de-duke.org` | Brand consistency requires the mail domain to match the public domain; Zoho mailboxes and ZeptoMail sending/return-path verification must be re-established on `.org` before any transactional mail sends | 2026-11-02 | User |
| D-012 | Authoritative DNS for `de-duke.org` lives in Google Cloud DNS | The live infrastructure is already GCP-managed; a single Cloud DNS zone keeps DNS, load-balancer certificates, and Terraform in one plane | 2026-11-02 | User |
| D-013 | Keep mobile app identity unchanged (`com.deduke.de_duke_mobile`, `com.deduke.deDukeMobile`) and keep Firebase project `de-duke-services` | Domain and app identity are independent. Changing the package/bundle ID would create new store listings, lose the existing install base and reviews, and force re-registration of FCM, OAuth, Sign in with Apple, Maps, and App Links. No technical requirement to change it for a domain move | 2026-11-02 | User (confirmed), Tech Lead (recommendation) |
| D-014 | Revise D-010: keep the live `de-duke.com` Cloud DNS zone and add `de-duke.org` as a second zone. Dual-domain, not a zone rename | The AWS account is closed, which locks the `de-duke.com` registration to AWS, but the DNS records were migrated to Google Cloud DNS before closure and the `.com` zone is live and Terraform-managed. Renaming it would delete live DNS. Both zones carry `prevent_destroy`; `.com` keeps resolving and `.com` mail records stay until the domain is recovered. Once `.org` is verified stable, Vercel redirects `.com` to `.org`; both domains run together when `.com` is recovered | 2026-11-02 | User (clarified), Tech Lead |
| D-015 | `.org` is the only live domain today; preserve the `.com` zone for recovery but do not rely on serving `.com` redirects now. Restoring the GCP billing account is a prerequisite for a stable `.org` on Cloud DNS | Public-DNS checks show `de-duke.com` is already undelegated (no NS or A records), so no redirect can be served until the registration is recovered. `de-duke.org` currently delegates to Namecheap nameservers (`dns1/dns2.registrar-servers.com`) and is parked, not on Google Cloud DNS. Separately, the GCP billing account is delinquent/disabled, so Terraform cannot read state and no new GCP resource (Cloud DNS zone, managed cert, Cloud Run) can be created until billing is restored | 2026-11-02 | Tech Lead (verified) |
| D-016 | `.org` registrar confirmed Namecheap; Cloud DNS zone created with `ns-cloud-b1..b4.googledomains.com`. Rollout is staged: delegate NS first, then create `.org` records + swap the managed cert/url-map, then point backend env at `.org` | Namecheap holds the `.org` registration, so the NS change happens there, not Google Cloud Domains. Staging prevents the backend from advertising `.org` URLs before the load balancer has a valid `.org` certificate. The `.com` zone remains intact and unchanged | 2026-11-02 | Tech Lead |
| D-017 | An iOS release retry reuses the signed IPA from the failed run instead of rebuilding it | Upload failures are Apple-side (agreement gates, App Store Connect errors) and the binary from the failed run is still correct, so discarding it forced a full macOS rebuild for nothing. The artifact now persists on failure and a dispatch naming the source run uploads it as-is, resolved through the API by exact artifact name rather than a wildcard so a stale or mismatched IPA can never reach App Store Connect. Uses the preinstalled `gh` CLI, so no third-party action enters the release path | 2026-11-13 | User (approved), Tech Lead |

## 13. Definition of Done

- Every acceptance criterion in `features.md` has a passing test.
- Every screen state in `screens/` is implemented (loading, empty, error, offline, submitting, validation).
- Build, lint, and tests green (flutter analyze/dart format, ruff/mypy/pytest).
- No hardcoded tokens; style only through the theme.
- No prototype placeholders; contracts conform to `CONTRACTS.md`.
- No em dashes or AI-isms in any shipped copy (humanizer pass).

## 14. Key Commands

**Backend:** `pip install -e .` · `uvicorn app.main:app --reload` · `pytest` · `ruff check . && ruff format --check .` · `mypy .` · `alembic upgrade head`
**Mobile:** `flutter pub get` · `flutter run --dart-define-from-file=.env.json` · `flutter test` · `flutter analyze` · `dart format --set-exit-if-changed .`
**Local stack:** `cp apps/backend/.env.example apps/backend/.env` · `docker compose up -d --build` · `docker compose exec backend alembic upgrade head` · `docker compose exec backend python -m pytest`
**Infra:** `terraform plan` / `terraform apply` (per environment, `infra/gcp/`)
**iOS release (local, from `apps/mobile/ios/`):** `bundle install` · `bundle exec fastlane ios bootstrap_match` (one-time) · `bundle exec fastlane ios match_appstore` · `bundle exec fastlane ios upload_testflight` (needs `IPA_PATH`) · `bundle exec fastlane ios upload_appstore` (no auto-submit). CI version: `.github/workflows/ios-release.yml`. **Upload failure retry (CI):** re-dispatch with `reuse-ipa-from-run: <failed run ID>` to upload that run's IPA without rebuilding.

### Local development stack (docker-compose)

`docker-compose.yml` at the repo root mirrors the managed services so backend work runs end to end locally:

| Service | Image | Emulates |
|---|---|---|
| `db` | `garapadev/postgres-postgis-pgvector:latest` (Postgres 16 + PostGIS + pgvector) | Primary Database |
| `redis` | `redis:7-alpine` | Cache |
| `localstack` | `localstack/localstack:3` (SQS only) | Task Queue |
| `backend` | Built from `apps/backend/Dockerfile.dev` (hot-reload, bind-mounted) | Backend API Service |

Local-only port remaps (host to container): `db` 5433→5432, `redis` 6380→6379, `backend` 8080→8000, `localstack` 4566 (unchanged). Firestore is not emulated: point `FIRESTORE_PROJECT_ID` / `FIREBASE_SERVICE_ACCOUNT_JSON` in `apps/backend/.env` at a real free-tier GCP project. Paystack, Google Maps, FCM, SES, Sentry, and analytics stay at their `REPLACE_ME` defaults unless real sandbox credentials are added.