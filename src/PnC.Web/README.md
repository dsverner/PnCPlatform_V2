# PnC.Web — the platform's browser front end (decision #163)

React 19 + TypeScript, built by Vite into `../PnC.Api/wwwroot/app` (git-ignored) and served by the API at `/app/`
under the shell's content-security policy (no inline script or style; no CDN).

- `npm ci` then `npm run build` — the release packager (`tools/package_release.py`) runs both and lists the lockfile's
  packages in `sbom.json`.
- `npm run dev` — Vite on port 5220, proxying `/api` and `/health` to the DEV API on 5210.
- `src/lib/api.ts` is the whole API surface (view reads, procedure calls, /me, /health); `src/lib/hooks.ts` wraps it in
  TanStack Query; `src/components/ui` are the shared parts; one page per screen under `src/pages`.
