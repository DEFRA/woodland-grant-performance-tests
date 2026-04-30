#!/bin/bash
set -e

docker build -t woodland-grant-performance-tests .
MSYS_NO_PATHCONV=1 docker run --rm \
  -v "$(pwd)/reports:/reports" \
  -e VU_COUNT=1 \
  -e DURATION_SECONDS=60 \
  woodland-grant-performance-tests
