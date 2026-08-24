# Analytics Session & Visitor Tracking Plan

## Goal

Upgrade the first-party pageview analytics with session tracking and a
persistent visitor ID, mark reloads/back-forward navigations, normalize
paths, and gate beacons to production hostnames. All new fields are optional
end-to-end so every deploy step stays independently safe; reloads are counted
but **marked**, never dropped.

Concretely:

- Beacon gains three optional fields:
  - `sessionId` — random UUID per tab/browser session (`sessionStorage`, key
    `lt-session`),
  - `visitorId` — random UUID persisted across visits (`localStorage`, key
    `lt-visitor`),
  - `navigationType` — `"navigate" | "reload" | "back_forward"` from the
    Navigation Timing API.
- Production gating: beacon only on `diermair.at` / `www.diermair.at`;
  never on localhost or preview deployments (`*.azurestaticapps.net`).
- Path normalization: strip trailing slash except root (`/leistungen/` →
  `/leistungen`).
- Updating the Datenschutzerklärung is **mandatory** — it currently claims no
  local storage and no user IDs, which becomes false.

## Current state

- **Frontend is an MPA** (static Astro output, no `<ClientRouter>` /
  view transitions anywhere in `src/`). Every navigation is a full page load,
  so the existing one-beacon-per-`window.load` model needs **no SPA dedupe
  logic** — a reload or back/forward produces exactly one new load and one
  beacon, which is what `navigationType` will mark.
- Tracking snippet: inline script in `src/layouts/Layout.astro:95–116`,
  present on every page (including `/404.html` via the SWA rewrite). It fires
  once on `window.load`, guards on `'sendBeacon' in navigator`, and sends
  `{ path: location.pathname, referrerHost, viewportWidth: screen.width }`
  via `navigator.sendBeacon('/api/pageview', …)`.
- Write side: `api/features/pageviews/PageView.cs`
  - `[Function("pageview")]`, `HttpTrigger(AuthorizationLevel.Anonymous,
    "post")` (`PageView.cs:19–22`).
  - Payload record `{ Path, ReferrerHost, ViewportWidth }` at
    `PageView.cs:56`; deserialized case-insensitively via System.Text.Json
    (`PageView.cs:14–17`) — unknown JSON properties are silently ignored.
  - Manual validation in `Handler.Validate` (`PageView.cs:64–87`): path must
    start with `/`, max 200 chars; referrerHost max 200; viewportWidth
    0–10000. Invalid JSON / null → 400, failure → 400 with detail, success →
    204.
  - Entity mapping in `Handler.SaveAsync` (`PageView.cs:89–100`):
    `PartitionKey = "Pv|yyyy-MM-dd"`, `RowKey = Guid`.
  - Store: `TablePageViewStore` (`PageView.cs:108–177`) writes to table
    `pageviews` (`CreateIfNotExistsAsync`) and runs a lazy 36-month retention
    purge guarded by a `Cleanup`/`last` marker entity. The cleanup filter
    `PartitionKey ge 'Pv|'` (`PageView.cs:147`) is unaffected by new columns.
- Entity schema: `api/shared/entities/PageViewEntity.cs` — `Path`,
  `ReferrerHost?`, `ViewportWidth`, plus `ITableEntity` plumbing. Azure Data
  Tables omits `null` properties when serializing, so adding nullable columns
  needs **no migration**; old rows simply read back without them.
- Read side/dashboard: **does not exist.** Plan 002 decided write-only
  tracking ("no read endpoint, no dashboard"); data is inspected ad hoc via
  Azure portal or `az storage table query`. This plan records the new fields
  per row but adds no aggregation UI — see Gap note below.
- Privacy page: `src/pages/datenschutzerklaerung.astro` already has a
  "Pseudonyme Besuchsstatistik" section (added by plan 002), but still claims:
  - Line 17–18: heading "Keine Cookies & kein Local Storage", body
    "verwendet keine Cookies und keinen Local Storage".
  - Line 22: "keine Nutzer-IDs und kein User-Agent gespeichert. Eine
    Identifizierung einzelner Besucher ist nicht möglich."
  - Line 23: "ausschließlich pseudonyme, einwilligungsfreie Daten … ist kein
    Opt-out erforderlich."
  - Line 34: "ist keine Identifizierung einzelner Besucher möglich."
- Build/lint/test: `pnpm run build` (= `astro check & astro build`,
  `package.json:8`) is the typecheck/build for the site;
  `dotnet publish api/diermair-api.csproj -o dist-api` builds the API. No
  test framework or separate linter is configured in this repo — do not
  invent commands.

### Gap note

There is no dashboard/aggregation layer, so sessions, visitors, and reloads
will exist only as per-row attributes until a read side is built. Ad-hoc
analysis remains possible, e.g. distinct visitors per day:

```
az storage table query --account-name stdiermairat \
  --table-name pageviews \
  --filter "PartitionKey eq 'Pv|2026-08-24'" \
  --select PartitionKey VisitorId --marker @'
'@ | jq '[.[].visitorId] | unique | length'
```

A future plan (read endpoint / dashboard) can consume these fields without
any further write-path change.

## Component changes

### 1. Client beacon — `src/layouts/Layout.astro`

Extend the inline script at lines 95–116:

1. **Production gating (first check, before anything else):**

   ```js
   const productionHosts = ['diermair.at', 'www.diermair.at'];
   if (!productionHosts.includes(location.hostname)) return;
   ```

   A positive allowlist covers localhost, `*.azurestaticapps.net` PR previews
   (the workflow deploys every PR, `.github/workflows/azure-static-web-apps-gray-plant-0450feb03.yml:18`)
   and any future staging host in one rule. Local dev (`pnpm run dev`) and
   `swa start` therefore stop sending data entirely.

2. **Path normalization:** `let path = location.pathname; if (path.length > 1 && path.endsWith('/')) path = path.slice(0, -1);` — root `/` stays intact. Query strings are not part of `pathname`; nothing else to strip.

3. **IDs** (each wrapped in try/catch so private-mode storage failures degrade
   to omitting the field):

   ```js
   function randomId() {
     if (crypto.randomUUID) return crypto.randomUUID();
     return (String(1e7) + -1e3 + -4e3 + -8e3 + -1e11).replace(
       /[018]/g,
       (c) => (c ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> c / 4).toString(16)
     );
   }
   ```

   - `sessionId`: read `sessionStorage['lt-session']`; if missing set
     `randomId()`. `sessionStorage` is per-tab and cleared when the tab
     closes — matches "one browsing session".
   - `visitorId`: same pattern against `localStorage['lt-visitor']`;
     persists across visits until the visitor clears site data.
   - If storage throws (disabled/blocked), leave both fields `undefined`.

4. **navigationType:** prefer the Navigation Timing API, omit when
   unavailable or out of vocabulary (e.g. `"prerender"`):

   ```js
   let navigationType;
   const navEntry = performance.getEntriesByType?.('navigation')?.[0];
   if (navEntry && ['navigate', 'reload', 'back_forward'].includes(navEntry.type)) {
     navigationType = navEntry.type;
   }
   ```

5. Payload becomes `{ path, referrerHost, viewportWidth, sessionId?,
   visitorId?, navigationType? }`. Still a single `sendBeacon` on
   `window.load`.

Note: the site is served over HTTPS, so `crypto.randomUUID` (secure-context
only) is available to all real visitors; the fallback exists only for
completeness.

### 2. API payload & validation — `api/features/pageviews/PageView.cs`

1. Extend the payload record (`PageView.cs:56`):

   ```csharp
   public sealed record Payload(
       string? Path,
       string? ReferrerHost,
       int? ViewportWidth,
       string? SessionId = null,
       string? VisitorId = null,
       string? NavigationType = null);
   ```

2. Validation rules appended in `Handler.Validate` (`PageView.cs:64–87`) —
   each field optional, but validated strictly when present:
   - `SessionId` / `VisitorId`: non-empty, ≤ 64 chars, must parse via
     `Guid.TryParse` (rejects junk injected into the open endpoint).
   - `NavigationType`: must be exactly `"navigate"`, `"reload"` or
     `"back_forward"`.
   Failure → existing 400-with-detail path.

3. Mapping in `Handler.SaveAsync` (`PageView.cs:89–100`): assign
   `SessionId = payload.SessionId`, `VisitorId = payload.VisitorId`,
   `NavigationType = payload.NavigationType`. Do **not** fold IDs into
   `PartitionKey`/`RowKey` — the daily-partition scheme and the retention
   filter stay untouched.

Deploy-order safety of this shape:

| API \ Client | Old (no new fields) | New |
| --- | --- | --- |
| **Old** | unchanged | unknown JSON properties ignored → rows stored with nulls |
| **New** | fields null → nullable entity props omitted | full row |

System.Text.Json's default ignore-unmatched-properties behavior
(`PayloadJsonOptions`, `PageView.cs:14–17`) is what makes shipping the API
first safe.

### 3. Entity schema — `api/shared/entities/PageViewEntity.cs`

Add three nullable properties after `ReferrerHost` (line 10):

```csharp
public string? SessionId { get; set; }

public string? VisitorId { get; set; }

public string? NavigationType { get; set; }
```

Azure.Data.Tables serializes `null` properties as *absent*, so existing rows
are untouched and read back null; no migration, no Bicep change (the table
already self-creates via `CreateIfNotExistsAsync`, `PageView.cs:116`).

### 4. Manual testing aid — `api/requests.http`

Extend the existing POST examples with one request carrying all new fields
and keep one minimal legacy-shaped request to prove it still returns 204.

### 5. Datenschutzerklärung — `src/pages/datenschutzerklaerung.astro` (MANDATORY)

Must go live **before or together with** the frontend change that starts
sending the fields:

- Lines 17–18: replace "Keine Cookies & kein Local Storage" section. New
  wording discloses that no cookies are used, but `localStorage`/
  `sessionStorage` store two randomly generated identifiers (`lt-visitor`,
  `lt-session`) that are not linked to any personal identity.
- Line 21: extend the recorded-fields list with "eine zufällige Besucher-ID
  und Sitzungs-ID sowie die Navigationsart (Seitenaufruf, Reload,
  Vor-/Rückwärts-Navigation)".
- Line 22: drop "keine Nutzer-IDs"; replace "Eine Identifizierung einzelner
  Besucher ist nicht möglich" with accurate wording, e.g. "Eine Zuordnung zu
  einer bestimmten Person ist nicht möglich; wiederholte Besuche desselben
  Browsers lassen sich jedoch anhand der Zufalls-ID erkennen."
- Line 23: keep the pseudonymity/storage/delete statements but re-evaluate
  the sentence "einwilligungsfreie Daten … kein Opt-out erforderlich" given a
  now-persistent identifier; at minimum the text must remain truthful. An
  easy-to-honor opt-out note ("Kennzeichnen durch Blockieren der Speicherung
  in den Browser-Einstellungen") is a low-cost addition.
- Line 34: soften "ist keine Identifizierung einzelner Besucher möglich"
  consistently with line 22.
- Line 46: update the version date ("datiert auf den 23. August 2026").

### Not changed

- No Bicep/workflow changes (no new resources, settings, or build steps).
- No dedupe logic beyond the current fire-once-on-load (MPA).
- Retention/cleanup untouched (`Cleanup` marker partition sorts outside the
  `Pv|` range).

## Rollout order

Each step is independently safe; steps 1–2 can share one PR as sequential
commits, since GitHub Actions deploys on merge to `main`:

1. **API first:** extend `Payload`, validation, and `PageViewEntity`
   (`api/features/pageviews/PageView.cs`, `api/shared/entities/PageViewEntity.cs`,
   `api/requests.http`). Deployed alone, behavior is byte-for-byte identical
   for the current frontend; new rows gain empty columns only once step 2
   ships.
2. **Privacy statement:** update
   `src/pages/datenschutzerklaerung.astro` and merge/deploy before the
   tracking change goes live.
3. **Frontend last:** gating + normalization + IDs + `navigationType` in
   `src/layouts/Layout.astro`. From this deploy on, production rows carry the
   new fields; preview deployments and localhost stay silent regardless of
   deploy order thanks to the client-side allowlist.

## Verification

Build checks (no test suite exists):

- `pnpm run build` passes (includes `astro check`).
- `dotnet publish api/diermair-api.csproj -o dist-api` succeeds.

Endpoint tests (local function or production):

1. Full payload → `204`:
   `curl -i -X POST https://diermair.at/api/pageview -H "Content-Type: application/json" -d '{"path":"/leistungen/holzernte","referrerHost":"google.at","viewportWidth":1920,"sessionId":"0b9e6c59-39a0-4f07-9db1-2b58e7f6a111","visitorId":"5f0d5b1e-93a1-4bd2-a1e4-c3aa2f0b9d42","navigationType":"reload"}'`
2. Legacy minimal payload `{"path":"/","referrerHost":"","viewportWidth":1920}`
   → `204` (backwards compatibility).
3. `{}` → `204` (all fields optional), invalid JSON → `400`.
4. Bad values → `400`: non-GUID `sessionId`, unknown `navigationType`
   (`"hover"`), path not starting with `/`.

Storage checks:

- `az storage table query --account-name stdiermairat --table-name pageviews`
  shows `sessionId` / `visitorId` / `navigationType` properties only on rows
  created after step 3; older entities read back without them.

Browser checks (on production, DevTools):

- Application tab: `lt-visitor` persists across tabs/restarts;
  `lt-session` is per-tab and cleared when the tab closes.
- Reload → new row with `navigationType: "reload"`; normal link navigation →
  `"navigate"`; back button → `"back_forward"`. Reloads are counted, marked,
  never dropped.
- Visiting a PR preview URL (`*.azurestaticapps.net`) or localhost: no
  request to `/api/pageview` in the Network tab.
- `/leistungen/` style URLs land in storage as `/leistungen`; `/` stays `/`.

Content check:

- Datenschutzerklärung live at `/datenschutzerklaerung` with corrected
  wording; no remaining claim of "kein Local Storage" or "keine Nutzer-IDs".

## Milestones (tracked)

- [ ] Extend `Payload` + validation + `PageViewEntity` + `requests.http`
      (API accepts/stores optional fields)
- [ ] Update `datenschutzerklaerung.astro` (mandatory wording corrections)
- [ ] Update beacon in `Layout.astro` (host allowlist, path normalization,
      `lt-session` / `lt-visitor`, `navigationType`)
- [ ] Merge & deploy API; verify legacy payloads unaffected
- [ ] Merge & deploy frontend + privacy page; verify end-to-end per
      verification checklist
