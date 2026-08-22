# Infrastructure as Code Plan

## Goal

Bring the Azure estate for diermair.at under Infrastructure as Code using Bicep
and auto-deploy infrastructure changes through GitHub Actions, following the
same pattern already established in the
[alpakasoelde repository](https://github.com/JakobFerdinand/alpakasoelde/commit/e90d1c5427d6407005260b29a93a7121990f2e27).
Only changes to `infrastructure/**` trigger the infra deployment; the existing
app build-and-deploy workflow (`azure-static-web-apps-gray-plant-0450feb03.yml`)
stays untouched.

This estate is significantly simpler than Alpakasoelde's: a single Static Web
App with no app settings, no APIs, no storage and no secrets. The plan is
therefore reduced accordingly — no Key Vault, no seed/sync scripts.

## Current Azure estate (resource group RG-diermairat)

| Resource | Name | Notes |
| --- | --- | --- |
| Static Web App | `diermairat` | Free SKU, westeurope; default hostname `gray-plant-0450feb03.4.azurestaticapps.net`; GitHub integration for `JakobFerdinand/diermair.at`, branch `main`; **app settings are empty** |
| Custom domains | `diermair.at`, `www.diermair.at` | Both validated (`Ready`) since Jan 2025 |

Deployment today happens via the auto-generated Static Web App GitHub-integration
workflow (`azure-static-web-apps-gray-plant-0450feb03.yml`), which runs
`npm install && npm run build` and uploads `./dist`. There is no IaC in the repo yet.

## Approach: adopt existing resources in place

Bicep declares the existing resources with their current names, resource group,
location and SKU, so the first deployment is an idempotent adopt with no
recreation or downtime. `az deployment group what-if` verifies this before applying.

The custom domains (`diermair.at`, `www.diermair.at`) are the adoption hotspot:
they are declared as `Microsoft.Web/staticSites/customDomains@2023-12-01` child
resources, but gated on a what-if review first — if what-if reports a destructive
`Replace` or `Delete`, they are left out of IaC initially and stay portal-managed
(they are already configured and validated).

## Milestones (tracked)

Checkboxes are updated as work progresses.

- [ ] Create git branch `feat/infrastructure-as-code`
- [x] Write infrastructure plan (`docs/plans/infrastructure-as-code.md`)
- [ ] Scaffold Bicep templates (`main.bicep`, optional `main-subscription.bicep`, modules, `*.bicepparam`, `bicepconfig.json`)
- [ ] Validate templates locally (`az bicep build` + `az deployment group what-if`)
- [ ] Write `.github/workflows/infra-deploy.yml` (what-if PR job + deploy on main)
- [ ] Manual: create service principal + OIDC federated credential scoped to RG-diermairat, add GitHub secrets (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`)
- [ ] First deploy: review what-if → apply → verify site stays live and custom domains remain intact
- [ ] Optional: create subscription cost budget via `main-subscription.bicep`
- [ ] Update README (and add an AGENTS.md section) documenting the deployment commands
- [ ] Open pull request and merge to main

## 1. Bicep structure under `infrastructure/`

```
infrastructure/
  main.bicep              # RG-scoped orchestrator (targetScope = resourceGroup)
  main.bicepparam         # values: SWA name, location, custom domains
  main-subscription.bicep # subscription-scoped deployment (optional cost budget)
  main-subscription.bicepparam
  bicepconfig.json        # lint rules
  modules/
    static-sites.bicep    # SWA + custom domains (adopt in place)
    budget.bicep          # subscription cost budget + action group (new resource)
```

Details:

- `static-sites.bicep` declares the `diermairat` Static Web App (Free SKU,
  westeurope, `allowConfigFileUpdates: true`) plus the two custom domains as
  child resources.
- Unlike alpakasoelde there are no storage/communication/observability/keyvault
  modules — those resources do not exist in this estate.
- There are no app settings to manage, so no Key Vault and no
  `seed-keyvault.sh` / `sync-swappsettings.sh` scripts are needed.
- The subscription-scoped budget template mirrors alpakasoelde's pattern
  (`Diermairat-Budget`, monthly grain, notifications at 20/80/100% via action
  group). This creates a **new** budget — none exists today — and can be
  deferred or dropped if not wanted.

## 2. Secret management

Not applicable. The Static Web App has empty app settings and the site holds no
secrets. If app settings are introduced later (e.g. a form API), adopt the
alpakasoelde pattern: Key Vault + seed/sync scripts + workflow-applied settings.

## 3. GitHub Actions – infra auto-deploy

New workflow `.github/workflows/infra-deploy.yml`:

- Triggers: push to `main` with paths `infrastructure/**`, and `pull_request`
  for a what-if preview job; both also support `workflow_dispatch`.
- Env: `RESOURCE_GROUP=RG-diermairat`, `DEPLOYMENT_LOCATION=westeurope`.

Deploy identity (one-time setup):

- Create a service principal for this repo.
- Add an OIDC federated credential for `JakobFerdinand/diermair.at`.
- Grant Contributor on `RG-diermairat` only (least privilege; add subscription
  scope only if the budget module is adopted).
- Store `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` in repo
  secrets (separate from the alpakasoelde ones).

Jobs:

- **what-if** (pull requests): `azure/login@v2` (OIDC) → `az bicep build` →
  `az deployment group what-if` → post the diff as a PR comment (marker-based
  upsert), so infra PRs show their impact before merge.
- **deploy** (main): `azure/login@v2` → `az bicep build` → what-if guard that
  fails on any `Delete`/`Replace` change → `az deployment group create`;
  optionally `az deployment sub create` for the budget.

## 4. Rollout order (safe, no downtime)

1. One-time prep: create service principal + OIDC federated credential, add
   the three GitHub secrets.
2. Scaffold the Bicep templates; run `az bicep build` locally and then
   `az deployment group what-if --resource-group RG-diermairat
   --template-file infrastructure/main.bicep --parameters
   infrastructure/main.bicepparam` to confirm zero destructive changes on the
   Static Web App and its custom domains (the adoption hotspot).
3. Commit the templates plus `infra-deploy.yml`; open a PR and check the
   posted what-if comment.
4. Merge; verify the deploy job succeeds, the site stays live at
   https://diermair.at, and both custom domains still resolve.
5. Optionally deploy the subscription budget.
6. Update README with an "Infrastructure" section pointing at
   `infrastructure/` and the workflow behaviour.

## 5. Known limitations (kept manual, documented)

- Custom-domain DNS validation records cannot be managed by Bicep.
- The SWA↔GitHub connection (build/deploy integration) remains managed by the
  auto-generated workflow; Bicep only declares the resource itself.

## Decisions

- Bicep with a single RG-scoped `main.bicep`; subscription-scoped
  `main-subscription.bicep` reserved for the optional cost budget.
- Adopt existing resources in place; no recreation, no downtime.
- No Key Vault: the estate has no secrets today.
- Existing app build-and-deploy workflow stays untouched; infra changes deploy
  through a separate path-filtered workflow.
- Pull requests: infra changes run a what-if job that posts the diff as a PR
  comment; deploys refuse destructive changes via a what-if guard.
