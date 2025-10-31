## Copilot instructions for MereMiners (concise)

This repo is a TypeScript full‑stack web app: React + Vite frontend in `client/`, Node backend in `server/`, and shared types/constants in `shared/`.

Key boundaries and flows
- Frontend (`client/`): UI, pages in `src/pages/`, components in `src/components/`, hooks in `src/hooks/` (e.g., `useAuth.ts`). Uses Tailwind and React Query (`client/src/lib/queryClient.ts`).
- Backend (`server/`): domain controllers (`server/controllers/`), services (`server/*.ts`, e.g., `tronService.ts`), background jobs (`server/jobs/`), and workers (`server/workers/`). Entrypoint: `server/index.ts` and API wiring in `api/index.ts`.
- Shared (`shared/`): canonical TypeScript types (see `shared/schema.ts`) and constants used by both sides.

Important integrations
- Tron USDT: logic in `server/tronService.ts` and `server/lib/tron.ts`; SQL schema in `server/sql/tron_usdt.sql`.
- Supabase/storage: `server/supabase.ts`, `storage.ts`, and `storageFiles.ts`.
- Database: Drizzle ORM. Config: `drizzle.config.ts`. Migrations and helper tools live in `server/tools/` and `server/sql/`.

Developer workflows (practical)
- Install deps: run at repo root and in packages as needed (`npm install` at root; then `cd client && npm install`, `cd server && npm install`).
- Start frontend: `cd client && npm run dev` (Vite). Frontend hot reload expected.
- Start backend: `cd server && npm run dev` or `npm run start` from `server/`.
- Tests: unit tests with Vitest (`vitest.config.ts`). Run from repo root or `client/` depending on script (`npm run test` / `npm run test:watch`).
- DB migrations: use Drizzle CLI configured by `drizzle.config.ts` or run helper scripts in `server/tools/` (e.g., `dbApplyTronUSDT.ts`).

Repository conventions and examples
- Type-first: update `shared/schema.ts` when adding new domain types; modify server logic and then update frontend pages/components.
- Business logic belongs on the server. Frontend should call REST endpoints (see `server/controllers/` and `api/index.ts`).
- Background processing: use `server/jobs/scheduler.ts` and workers under `server/workers/` (e.g., `depositScanner.ts`, `sweeper.ts`). When adding periodic logic, add a job and register it with the scheduler.
- Admin & maintenance scripts: add one-off maintenance scripts under `server/tools/` and document usage inline. Examples: `dbSanity.ts`, `grantTrialMiner.ts`.

Files worth checking when making changes
- `shared/schema.ts` — shared types
- `client/src/pages/` and `client/src/components/` — frontend wiring
- `server/controllers/` and `server/*.ts` — API and service logic
- `server/jobs/`, `server/workers/`, `server/tools/` — background and admin tools
- `drizzle.config.ts`, `server/sql/` — DB config and migrations

Do / Don't (practical)
- Do: preserve shared types in `shared/` first, then adapt server and client.
- Do: register new background tasks in `server/jobs/scheduler.ts`.
- Don't: put business rules in UI components; prefer server-side where possible.

If something's missing or unclear, tell me which workflows you need (local dev, Docker, CI) and I will expand the doc with exact commands and examples.

References: read `README.md`, `drizzle.config.ts`, `server/routes.ts`, and `server/tronService.ts` for canonical patterns.
