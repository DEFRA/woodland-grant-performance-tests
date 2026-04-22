# CLAUDE.md

## Project overview

A k6 performance test suite for the `grants-ui` platform, covering the Woodland Management Plan (WMP) grant journey. The scenario walks a virtual user through the full application from login to confirmation.

This suite is used for **standalone load testing** — run via the CDP Portal against the Perf-Test environment with a high VU count and configurable duration.

This suite was modelled on `grants-ui-performance-tests`. Refer to that repo for patterns if adding new pages or features.

## Reference sources for the WMP journey

When updating the journey (new pages, changed field names, removed pages), check both:

- **`woodland-grant-journey-tests`** (`test/specs/application-journey.spec.js`) — the Playwright journey test; shows the full page flow, form interactions, and field names as exercised end-to-end
- **`grants-ui`** (`src/server/common/forms/definitions/woodland.yaml`) — the authoritative form definition; shows page paths, field names, conditions, and section structure

## Key files

- `scenarios/woodland-grant.js` — the single k6 test scenario, covering the full WMP journey with Defra ID authentication
- `scenarios/dal-users.csv` — CRNs for test users sourced from the DAL; used to drive virtual users through authentication
- `scenarios/lib/k6chaijs.js` — vendored k6 assertion library (do not fetch at runtime)
- `entrypoint.sh` — Docker entrypoint; runs k6 and optionally generates an HTML report published to S3
- `generate-report.sh` — generates an HTML report from the k6 JSON metrics output

## Test scenario structure

The scenario (`woodland-grant.js`) walks a virtual user through the full WMP journey:

1. Login with CRN from `dal-users.csv` (password `x`), select first organisation if the `/organisations` page appears
2. Click "Clear application state" to reset prior state
3. Walk each journey page in order, submitting the form and recording a `duration_<page>` Trend metric
4. Assert the confirmation page contains a reference number (`WMP-`)

Each page has a corresponding p95 threshold enforced via `P95_THRESHOLD_MS` (default 3000ms).

The journey exercises several conditional branches to give those pages load coverage:
- `check-details`: submits No first (→ exit page → Continue) then Yes
- `eligibility-land-registered`: submits No first (→ exit page → Back) then Yes
- `eligibility-management-control`: submits No (→ countersignature path)
- `eligibility-countersignature`: submits No first (→ exit page → Back) then Yes
- `eligibility-tenant`: submits Yes (→ tenant obligations path)
- `eligibility-tenant-obligations`: submits Yes first (→ exit page → Back) then No
- `eligibility-valid-wmp`: submits Yes (→ wmp-agreement page)

## WMP journey pages (in order)

All pages are prefixed `/woodland/`:

| Path | Description |
|---|---|
| `/check-details` | Confirm applicant/org details |
| `/tasks` | Task list |
| `/eligibility-land-registered` | Land registered with RPA? |
| `/eligibility-management-control` | Management control for duration? |
| `/eligibility-countersignature` | Landlord countersignature (conditional: management control = No) |
| `/eligibility-tenant` | Tenant of a public body? |
| `/eligibility-tenant-obligations` | Works required by tenancy? (conditional: public body tenant = Yes) |
| `/eligibility-grazing-rights` | Land with common/shared grazing rights? |
| `/eligibility-valid-wmp` | Existing valid WMPs? |
| `/eligibility-wmp-agreement` | Enter existing WMP agreement numbers (conditional: valid WMP = Yes) |
| `/eligibility-higher-tier` | Intend to apply for CSHT? |
| `/land-parcels` | Select eligible land parcels |
| `/total-area-of-woodland` | Total area of woodland over and under 10 years old (ha) |
| `/centre-of-woodland` | Grid reference for centre of woodland |
| `/which-forestry-commission-team` | FC team advising |
| `/summary` | Check your answers |
| `/potential-funding` | Potential funding estimate |
| `/declaration` | Submit your application |
| `/confirmation` | Application received |

Exit/terminal pages (exercised in the journey but not the primary path): `/exit-eligibility-land-registered`, `/exit-eligibility-countersignature`, `/exit-eligibility-tenant-obligations`.

## User data

`dal-users.csv` contains CRNs only (no SBIs). The first SBI is selected dynamically from the page if the organisations screen appears. The filename `dal-users.csv` is significant — do not rename it.

This specific set of users is required (not arbitrary test CRNs) because they must exist in all of the following systems with land parcel data configured:

- **DAL stub** — must have land parcels configured for the user's SBI; required because the journey includes a `land-parcels` page that renders checkboxes from DAL data. Without this, there are no parcels to select and the journey fails.
- **Defra ID stub (Perf-Test)** — used to authenticate in the Perf-Test environment
- **Defra ID stub (CI)** — used to authenticate in the grants-ui CI pipeline (if this suite is ever run there)

## Running locally

Requires Docker. No Node.js or k6 installation needed.

Use `run-local.sh`, which builds the image and runs the suite against a local grants-ui instance. grants-ui must be running with the CI compose override (`compose.ci.yml`) so that grants-ui-net friendly URLs are served.

```bash
bash run-local.sh
```

Reports are written to `./reports/`.

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HOST_URL` | `https://grants-ui.perf-test.cdp-int.defra.cloud` | Target grants-ui instance |
| `DURATION_SECONDS` | `180` | Total test duration |
| `RAMPUP_SECONDS` | `30` | Ramp-up period |
| `VU_COUNT` | `100` | Concurrent virtual users |
| `P95_THRESHOLD_MS` | `3000` | p95 response time threshold (ms) |
| `GENERATE_REPORT` | `true` | Set to `true` to generate and publish an HTML report to S3 |

## Adding new journey pages

When a new page is added to the WMP journey:

1. Add a `Trend` constant at the top of the scenario file
2. Add the corresponding threshold in `options.thresholds`
3. Add a `group()` block in the correct position in the journey, recording the trend and submitting the form with the correct field names (check the actual form payload by inspecting the page source or network tab)

For land parcel selection pages, use the dynamic selection pattern:
```js
const firstParcel = response.html().find('input[name="landParcels"]').first().attr('value')
submitJourneyForm({ landParcels: firstParcel })
```

## Vendored libraries

Third-party k6 libraries live in `scenarios/lib/` and are checked in — they are not fetched at runtime. To update:

```bash
curl -fsSL --ssl-no-revoke https://jslib.k6.io/k6chaijs/<version>/index.js -o scenarios/lib/k6chaijs.js
```
