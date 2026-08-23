# AGENTS.md

Guidance for coding agents working in this repository.

## Project overview

- Astro static site for [diermair.at](https://diermair.at); pages in `src/pages`, reusable pieces in `src/components`, content collections configured in `src/content.config.ts`.
- Deployed to Azure Static Web App `diermairat` (RG-diermairat, westeurope, Free SKU) by the auto-generated `.github/workflows/azure-static-web-apps-gray-plant-0450feb03.yml`: `pnpm install --frozen-lockfile && pnpm run build`, uploads `./dist`.
- Use pnpm for all JavaScript dependency management (`pnpm install`, `pnpm run ...`); npm must not be used. The pinned version is declared in `package.json#packageManager`.
- `api/`: Azure Functions managed API (C# .NET isolated); serves the `POST /api/pageview` endpoint and writes page views to Azure Table Storage (account `stdiermairat`, table `pageviews`). See `docs/plans/website-analytics.md`.
- `staticwebapp.config.json` is copied into the build output and configures headers/redirects plus the managed-functions `apiRuntime` (`dotnet-isolated:9.0`) for the Static Web App.

## Infrastructure as Code

- `infrastructure/`: Bicep templates that adopt the Azure estate in place (`main.bicep` declares the Static Web App `diermairat`, the storage account `stdiermairat`, custom domains `diermair.at` / `www.diermair.at` and the resource-group scoped `Diermairat-Budget`). The only secret-ish value, the storage connection string, is applied as the SWA app setting `StorageConnection` by the infra workflow — never committed, no Key Vault.
- Changes to `infrastructure/**` deploy automatically through `.github/workflows/infra-deploy.yml`: PRs get a what-if preview comment, pushes to `main` apply (guarded against Delete/Replace changes).
- Validate locally before committing infra changes:
  - `az bicep build --file infrastructure/main.bicep`
  - `az deployment group what-if --resource-group RG-diermairat --template-file infrastructure/main.bicep --parameters infrastructure/main.bicepparam`
- See `docs/plans/infrastructure-as-code.md` for the adoption plan and rollout notes.

## Coding style

- Use two-space indentation in Astro/TS/JSON files and keep copy in dedicated `.astro` or `.md` fragments.
- Conventional Commits (`feat:`, `fix:`, `docs:`, `ci:`, `chore:`).

## Environment & Configuration

- Never commit secrets; there are none committed today. The SWA app setting `StorageConnection` (storage account connection string for the pageview API) is applied by the infra deploy workflow, not stored in the repo or Bicep.
