# Website Analytics Plan

## Goal

Track basic website usage (page views) for diermair.at in a cookie-free,
first-party, privacy-friendly way: the site beacons a small JSON payload to an
HTTP endpoint on the Static Web App, which writes one row per page view into
Azure Table Storage. No cookies, no third-party SDKs, no IP addresses.

## What is needed (inventory)

| Component | New? | Notes |
| --------- | ---- | ----- |
| Storage account (Azure Table Storage) | **New** | Stores the `pageviews` table; only new Azure resource |
| Function hosting | **No new resource** | Hosted by the Static Web App itself as *managed functions* (consumption plan, HTTP-only triggers) — no separate Function App resource, no extra cost |
| Function code (`api/` in this repo) | **New** | C# .NET isolated, HTTP trigger `POST /api/pageview`, writes to Table Storage |
| Beacon script in `Layout.astro` | **New** | `navigator.sendBeacon` on `window` load |
| SWA app setting `StorageConnection` | **New** | Storage connection string; set via workflow, not committed |
| `staticwebapp.config.json` | **Edit** | Declare `apiRuntime` for managed functions |
| Build-and-deploy workflow (`azure-static-web-apps-gray-plant-0450feb03.yml`) | **Edit** | Build and publish the API, pass `api_location` |
| Infra workflow (`infra-deploy.yml`) | **Edit** | Set the `StorageConnection` app setting after each infra deploy |
| `.gitignore` / `.github/dependabot.yml` | **Edit** | Ignore API build artifacts; add nuget ecosystem |
| Datenschutzerklärung (`src/pages/datenschutzerklaerung.astro`) | **Edit** | Current text claims "kein Tracking" and "keine personenbezogenen Daten" and must be corrected |

No Key Vault is introduced; the storage key is fetched in the infra deploy
workflow and never enters the repository. Application Insights is optional and
not required.

## Decisions

- **Managed functions instead of a separate Function App.** The API runs inside
  the existing Static Web App (`diermairat`, Free SKU, `westeurope`). The Free
  plan includes enough function executions for this traffic volume. Consequence:
  only HTTP triggers are supported — retention cleanup must run lazily inside
  the write path, not on a timer.
- **Write-only tracking for now.** No read endpoint, no dashboard, no stats
  page. Data is inspected ad hoc via Azure portal or `az storage table query`.
  A protected read endpoint can be added later without changing the write path.
- **Cookie-free and first-party.** No cookies, no localStorage, no SDKs. The
  beacon goes to the same origin (`/api/pageview`), so no CORS is needed.
- **Privacy by design (DSGVO, Art. 6 lit. f).** Store no IP address, no user
  agent, no user ID, no full referrer URL. Only: path, referrer *host* (origin
  only), and viewport width. Disclose the tracking on the privacy page.
- **Anonymous write endpoint.** `AuthorizationLevel.Anonymous` — it must be
  callable by any visitor without credentials.
- **Table auto-created by the function** (`CreateIfNotExistsAsync`), not
  declared in Bicep.
- **Retention: 36 months**, enforced via a lazy purge in the write path (see
  below).

## 1. Azure resources (Bicep)

### New storage module

Add `infrastructure/modules/storage.bicep` and wire it into `main.bicep`:

- **Storage account** `stdiermairat` — `Standard_LRS`, `StorageV2`, Hot tier,
  `westeurope`, HTTPS-only, TLS 1.2 minimum. Global name must stay unique
  (3–24 chars, lowercase).
- No tables declared in Bicep; the function creates `pageviews` itself.
- **Cost:** negligible (few MB of rows; LRS transaction prices at this volume).

`main.bicep` gains a `storage` module; `main.bicepparam` gains the storage
account name param. The existing what-if guard in `infra-deploy.yml` stays
valid: a new storage account is a `Create`, not a destructive change. The
existing OIDC service principal (Contributor on `RG-diermairat`) already covers
the new resource — no new identity needed.

### SWA app setting

After every infra deployment, the workflow fetches the account key and sets the
connection string on the SWA:

```bash
KEY=$(az storage account keys list --resource-group RG-diermairat \
  --account-name stdiermairat --query "[0].value" -o tsv)
az staticwebapp appsettings set --name diermairat --resource-group RG-diermairat \
  --setting-names "StorageConnection=DefaultEndpointsProtocol=https;AccountName=stdiermairat;AccountKey=$KEY;EndpointSuffix=core.windows.net" \
  --output none
```

The function reads `StorageConnection` from its environment (SWA app settings
become env vars; the name does not collide with the reserved `AzureWeb*`,
`WEBSITE*`, … prefixes). Wrap the key fetch in `::group::`/`::endgroup::` and
use `--output none` so the key never appears in pipeline logs.

**Why not Bicep-declared app settings?** The ARM schema
`Microsoft.Web/staticSites/config` does support app settings, but the
workflow step is kept deliberately:

- The connection string would otherwise be materialized via `listKeys(...)`
  into what-if output and deployment history (readable by anyone with Reader on
  the resource group).
- Settings become drift-prone "side effects" when declared outside the step.
- `--output none` keeps the key out of pipeline logs; `az staticwebapp
  appsettings set` would otherwise print all settings, including values.

## 2. Function code (`api/`)

New `api/` directory in the repo, C# .NET isolated:

- `api/diermair-api.csproj` — net9.0 (`dotnet-isolated:9.0` is currently the
  newest .NET runtime supported by SWA managed functions), packages
  `Microsoft.Azure.Functions.Worker`, `.Extensions.Http`,
  `Microsoft.Azure.Functions.Worker.Sdk`, `Azure.Data.Tables`.
- `api/Program.cs` — reads `StorageConnection` (throw if unset), registers a
  singleton `TableServiceClient` and the page-view handler/store.
- `api/features/pageviews/PageView.cs` —
  - `[Function("pageview")]`, `[HttpTrigger(AuthorizationLevel.Anonymous, "post")]`
    → route `/api/pageview`.
  - Payload: `{ path, referrerHost, viewportWidth }`.
  - Validation: `path` required, starts with `/`, max 200 chars; `referrerHost`
    max 200 chars; `viewportWidth` 0–10000. Invalid JSON → 400, validation
    failure → 400 with detail, success → `204 No Content`.
  - Writes a `PageViewEntity`: `PartitionKey = "Pv|{yyyy-MM-dd}"` (daily
    partitions), `RowKey = Guid`, fields `Path`, `ReferrerHost`,
    `ViewportWidth`; storage sets `Timestamp`. No requester data is derived
    server-side.
  - **Retention:** on write, if the last cleanup marker (`Cleanup`/`last`
    entity) is older than one day, delete all partitions older than 36 months
    in 100-row transaction batches. Cleanup failures are logged and swallowed
    (fail-open — tracking must never break because of purge errors).
- `api/shared/EnvironmentVariables.cs`, `api/shared/entities/PageViewEntity.cs`.
- `api/requests.http` for manual endpoint testing.

### Runtime declaration

`staticwebapp.config.json` gets:

```json
{
  "platform": { "apiRuntime": "dotnet-isolated:9.0" },
  "responseOverrides": { ... existing ... }
}
```

If SWA adds a newer managed-functions runtime later, bump both `apiRuntime`
here and `<TargetFramework>` in the csproj together.

## 3. Client beacon (`Layout.astro`)

Inline script in `Layout.astro` (present on every page):

- Fire once on `window` `load`, guarded by `'sendBeacon' in navigator`.
- `navigator.sendBeacon('/api/pageview', new Blob([JSON.stringify(payload)], { type: 'application/json' }))`
  — fire-and-forget, survives page unload.
- Payload: `path: location.pathname`, `referrerHost` = host of
  `document.referrer` (never the full URL; empty string if none),
  `viewportWidth: screen.width`.

## 4. Deployment workflows

### Build-and-deploy (`azure-static-web-apps-gray-plant-0450feb03.yml`)

1. Keep the Astro build as-is.
2. New steps: setup .NET 9 SDK, then `dotnet publish api/diermair-api.csproj -o dist-api`
   (API output outside the static app output).
3. In `Azure/static-web-apps-deploy@v1`: `api_location: "dist-api"` and
   `skip_api_build: true`. Existing `app_location`, token and PR-close job stay
   unchanged.

Local development: use the SWA CLI (`swa start dist --api-location api`) or run
the function directly with a local `StorageConnection`; keep `requests.http`
for manual endpoint testing.

### Infra deploy (`infra-deploy.yml`)

New final step in the deploy job (after the existing deployments): fetch the
storage account key and set the `StorageConnection` app setting as shown above.
PR what-if job needs no change.

## 5. Datenschutzerklärung

`src/pages/datenschutzerklaerung.astro` currently claims "keine Cookies,
Web-Beacons oder vergleichbare Tracking-Technologien", "weder personenbezogene
Daten erhoben noch gespeichert" and "keine Server-Logs" — those statements must
be corrected before or together with this feature. New section (pseudonymous
visit statistics):

- Recorded fields: page path, referrer host (origin only), viewport width.
- No cookies, no IP addresses, no user IDs, no user agent.
- Storage in Azure Table Storage (EU, `westeurope`), automatic deletion after
  36 months.
- Legal basis: legitimate interest (DSGVO Art. 6 lit. f).
- Adjust the related sections ("Keine Cookies & kein Tracking",
  "Server- und Logdaten", "Weitergabe von Daten", "Betroffenenrechte") so the
  page stays internally consistent.

## Milestones (tracked)

Checkboxes are updated as work progresses.

- [x] Decide final storage account name (`stdiermairat`) and retention (36 months)
- [x] Add `storage.bicep` module + `main.bicep` wiring; validate with `az bicep build` + `az deployment group what-if` (expect only `Create`)
- [x] Extend `infra-deploy.yml` deploy job to set the `StorageConnection` app setting
- [x] Scaffold `api/` (csproj, Program.cs, pageview feature, requests.http); verify `dotnet publish`
- [x] Add beacon script to `Layout.astro`; update `staticwebapp.config.json` (`apiRuntime`)
- [x] Update `azure-static-web-apps-gray-plant-0450feb03.yml` (dotnet publish + `api_location`)
- [x] Update `datenschutzerklaerung.astro` (pseudonymous statistics section)
- [x] Ignore API build artifacts; add nuget dependabot updates
- [x] Update `AGENTS.md` (new `api/` dir, app setting note)
- [ ] Merge; deploy infrastructure; verify storage account exists
- [ ] Deploy app; verify: beacon fires, 204 returned, rows appear in the
      `pageviews` table (`az storage table query`)

## Verification checklist

1. `curl -i -X POST https://diermair.at/api/pageview -H "Content-Type: application/json" -d '{"path":"/","referrerHost":"google.at","viewportWidth":1920}'`
   → `204`.
2. Invalid payloads (`{}`, path without `/`) → `400`.
3. `az storage table query --account-name stdiermairat --table-name pageviews`
   shows one entity per request with today's `Pv|yyyy-MM-dd` partition.
4. Privacy page reflects the new section; no cookies set (check DevTools /
   `curl -v` response headers).
