#!/bin/bash
# grants-ui must be running with the CI compose override (compose.ci.yml) so that
# grants-ui-net friendly URLs are served.
# e.g. docker compose -f compose.yml -f compose.ha.yml -f compose.land-grants.yml -f compose.ci.yml up -d
set -e

docker build -t woodland-grant-performance-tests .
MSYS_NO_PATHCONV=1 docker run --rm \
  --network grants-ui-net \
  -v "$(pwd)/reports:/reports" \
  -e HOST_URL=https://grants-ui-proxy:4000 \
  -e K6_INSECURE_SKIP_TLS_VERIFY=true \
  -e VU_COUNT=1 \
  -e DURATION_SECONDS=90 \
  woodland-grant-performance-tests
