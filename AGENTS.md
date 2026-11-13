# AGENTS.md: De-Duke

De-Duke is a fully implemented Nigerian property marketplace: a Flutter mobile app, a FastAPI backend, a Next.js admin console, and a Next.js marketing site. This file routes any agent to the files that define how to work here. It is a pointer, not a duplicate. Read the referenced files before starting work.

## Where the truth lives

| Question | Read |
|---|---|
| Product requirements, features, screens, states, data model, roadmap | `docs/De-Duke/` (the spec; `README.md` is the entry point) |
| Frozen API surface: endpoints, request/response shapes, errors | `CONTRACTS.md` |
| Team ownership, task board, conventions, commands, definition of done | `DELIVERY.md` |
| Asset ledger: paths, formats, families, what must never be regenerated | `ASSETS.md` |

If they conflict: `docs/De-Duke/` is the source of truth. `DELIVERY.md`, `CONTRACTS.md`, and `ASSETS.md` are coordination and must conform to it. `CONTRACTS.md` is authoritative for the API surface the code implements.

## Rules that apply everywhere

- Never write to `docs/De-Duke/`. The spec is read-only for every agent; report gaps to the project maintainer instead of editing the docs yourself.
- The spec holds requirements only: no implementation details, no logs, no em dashes.
- Never commit secrets; never hardcode a backend URL, API key, or credential in source.
- Conventional Commits (`type(scope): description`), with an `Implements: <FEAT-###>` footer where a feature applies.
- Run tests before committing; only `main` carries verified work (per `DELIVERY.md`).
- Style only through theme tokens. A payment or booking is never marked succeeded from a client-reported result, only from a verified webhook. No negotiation or offer UI anywhere (fixed pricing).

## How to work here

1. Read the product docs for what to build (`docs/De-Duke/`), the frozen contract for the API (`CONTRACTS.md`), and `DELIVERY.md` for who owns which files, the task board, and conventions.
2. Check `ASSETS.md` before creating or using any visual asset. Shipped assets are recorded there and must never be regenerated or moved.
3. Local development runs through the docker-compose stack; setup, port map, and commands are in `DELIVERY.md` (Key Commands). Backend env comes from `apps/backend/.env.example`.
4. Release operations (iOS TestFlight/App Store, backend deploy) are documented in the CI workflows under `.github/workflows/`.