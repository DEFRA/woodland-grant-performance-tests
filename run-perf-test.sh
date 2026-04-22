#!/bin/bash
set -e

docker build -t woodland-grant-performance-tests .
MSYS_NO_PATHCONV=1 docker run --rm \
  --network grants-ui-net \
  -v "$(pwd)/reports:/reports" \
  woodland-grant-performance-tests
