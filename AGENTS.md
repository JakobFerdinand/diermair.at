# AGENTS.md

Guidance for coding agents working in this repository.

## Project overview

- Astro static site for [diermair.at](https://diermair.at); pages in `src/pages`, reusable pieces in `src/components`, content collections configured in `src/content.config.ts`.
- Deployed to Azure Static Web App `diermairat` (RG-diermairat, westeurope, Free SKU) by the auto-generated `.github/workflows/azure-static-web-apps-gray-plant-0450feb03.yml`: `npm install && npm run build`, uploads `./dist`.
- `staticwebapp.config.json` is copied into the build output and configures headers/redirects for the Static Web App.

## Infrastructure as Code

- `infrastructure/`: Bicep templates that adopt the Azure estate in place (`main.bicep` declares the Static Web App `diermairat` plus custom domains `diermair.at` / `www.diermair.at`; `main-subscription.bicep` provisions the `Diermairat-Budget`). There are no secrets or app settings in this estate, hence no Key Vault.
- Changes to `infrastructure/**` deploy automatically through `.github/workflows/infra-deploy.yml`: PRs get a what-if preview comment, pushes to `main` apply (guarded against Delete/Replace changes).
- Validate locally before committing infra changes:
  - `az bicep build --file infrastructure/main.bicep`
  - `az bicep build --file infrastructure/main-subscription.bicep`
  - `az deployment group what-if --resource-group RG-diermairat --template-file infrastructure/main.bicep --parameters infrastructure/main.bicepparam`
- See `docs/plans/infrastructure-as-code.md` for the adoption plan and rollout notes.

## Coding style

- Use two-space indentation in Astro/TS/JSON files and keep copy in dedicated `.astro` or `.md` fragments.
- Conventional Commits (`feat:`, `fix:`, `docs:`, `ci:`, `chore:`).

## Environment & Configuration

- Never commit secrets; there are none today. If app settings become necessary later, follow the Key Vault pattern from the alpakasoelde repo instead of storing values in Bicep.
