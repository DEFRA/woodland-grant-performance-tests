# woodland-grant-performance-tests

## Overview

Performance test suite for Defra's [grants-ui](https://github.com/DEFRA/grants-ui) platform, maintained by the Grants Application Enablement (GAE) team.

## Test Coverage

The suite provides performance testing for the Woodland Management Plan (WMP) grant application journey.

## Technology Stack

- **Grafana k6** for load testing and performance measurement

## Test Scenarios

Individual test scripts are located in the `/scenarios` directory, with each script targeting a specific grant application journey.

Current test scenarios:
- `woodland-grant.js` - Woodland Management Plan grant application journey with Defra ID authentication

## Configuration

Test scenarios are parameterized via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `HOST_URL` | `https://grants-ui.perf-test.cdp-int.defra.cloud` | Base URL of the grants-ui instance under test |
| `DURATION_SECONDS` | `180` | Total test duration in seconds |
| `RAMPUP_SECONDS` | `30` | Time to ramp up to target VU count |
| `VU_COUNT` | `100` | Number of concurrent virtual users |
| `P95_THRESHOLD_MS` | `3000` | 95th percentile response time threshold in milliseconds |
| `GENERATE_REPORT` | `true` | Toggles HTML report generation if not needed |

## Test Assertions

Each test scenario includes:

**Reference Number Assertion:**
- Validates the confirmation page contains a valid `WMP-` reference number, indicating successful end-to-end submission to GAS

**Page Load Metrics:**
- Each journey page records its load time as a `duration_<page>` Trend metric (e.g. `duration_start`, `duration_eligibility_land_registered`). These are used for per-page p95 thresholds and reported in the HTML report as page load times sorted by p95 descending.

### Thresholds

The test enforces the following thresholds:
- Per-page p(95) < `P95_THRESHOLD_MS`ms - 95th percentile page load time for each journey page must be under the configured threshold (default 3000ms). Each journey page has its own `duration_<page>` Trend metric.
- `http_req_failed` rate == 0 - no HTTP request failures are permitted

## Running Tests

### Via CDP Portal

Tests are executed from the CDP Portal under the **Test Suites** section for the **Perf-Test** environment.

**Execution:**
1. Navigate to Test Suites in the CDP Portal
2. Configure the test via environment variables if the defaults need to be overridden
3. Execute the test
4. View reports in the portal once the test completes

**Reports:**
- HTML reports are generated and published to S3
- Accessible through the CDP Portal interface

### Running Locally

**Prerequisites:**
- Docker

**Build:**
```bash
docker build -t woodland-grant-performance-tests .
```

**Run with defaults:**
```bash
# Git Bash on Windows
MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd)/reports:/reports" woodland-grant-performance-tests

# Linux/Mac
docker run --rm -v "$(pwd)/reports:/reports" woodland-grant-performance-tests
```

**Run with custom parameters:**
```bash
# Git Bash on Windows
MSYS_NO_PATHCONV=1 docker run --rm \
  -e HOST_URL=http://localhost:3000 \
  -e DURATION_SECONDS=60 \
  -e RAMPUP_SECONDS=10 \
  -e VU_COUNT=10 \
  -e P95_THRESHOLD_MS=3000 \
  -v "$(pwd)/reports:/reports" \
  woodland-grant-performance-tests
```

Reports are written to the `./reports` directory.

**Using Docker Compose** (includes LocalStack, Redis, and grants-ui):

```bash
docker compose up --build
```

This brings up:

* `development`: the container that runs your performance tests
* `localstack`: simulates AWS S3, SNS, SQS, etc.
* `redis`: backing service for cache
* `service`: grants-ui, the application under test

Once all services are healthy, your performance tests will automatically start. Reports are written to `./reports` on your host.

## Project Structure

```
woodland-grant-performance-tests/
├── scenarios/             # k6 test scenarios (.js files)
│   ├── lib/               # Vendored third-party k6 libraries
│   ├── woodland-grant.js  # Woodland Management Plan journey
│   └── dal-users.csv      # User data (CRNs for authentication)
├── reports/               # Generated test reports (gitignored)
├── compose/               # Docker Compose support files
├── Dockerfile             # Container image definition
├── entrypoint.sh          # Test execution script
├── generate-report.sh     # HTML report generation script
└── README.md
```

## Dependencies

Third-party k6 libraries are vendored into `scenarios/lib/` rather than fetched at runtime, to avoid network dependencies during test execution.

| File | Source | Version |
|------|--------|---------|
| `scenarios/lib/k6chaijs.js` | https://jslib.k6.io/k6chaijs/4.3.4.3/index.js | 4.3.4.3 |

To update a library, download the new version and replace the file:
```bash
curl -fsSL --ssl-no-revoke https://jslib.k6.io/k6chaijs/<new-version>/index.js -o scenarios/lib/k6chaijs.js
```

Then update the version in the table above.

## Test Data

The `dal-users.csv` file contains Customer Reference Numbers (CRNs) for test users sourced from the DAL stub. These users must exist in the Defra ID stub and DAL stub in both CI and Perf-Test environments.

**Format:**
```csv
crn
1102838829
...
```

## Related Repositories

- [grants-ui](https://github.com/DEFRA/grants-ui) - Grants application frontend service
- [grants-ui-backend](https://github.com/DEFRA/grants-ui-backend) - Backend service, included in the scope of these tests
- [fcp-defra-id-stub](https://github.com/DEFRA/fcp-defra-id-stub) - Authentication stub for testing

## Support

For questions or issues, contact the Grants Application Enablement (GAE) team.

## Licence

THIS INFORMATION IS LICENSED UNDER THE CONDITIONS OF THE OPEN GOVERNMENT LICENCE found at:

<http://www.nationalarchives.gov.uk/doc/open-government-licence/version/3>

The following attribution statement MUST be cited in your products and applications when using this information.

> Contains public sector information licensed under the Open Government licence v3

### About the licence

The Open Government Licence (OGL) was developed by the Controller of Her Majesty's Stationery Office (HMSO) to enable
information providers in the public sector to license the use and re-use of their information under a common open
licence.

It is designed to encourage use and re-use of information freely and flexibly, with only a few conditions.
