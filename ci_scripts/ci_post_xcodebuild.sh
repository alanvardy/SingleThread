#!/bin/sh
set -eu

# dSYMs only exist for archive actions.
if [ -z "${CI_ARCHIVE_PATH:-}" ]; then
    exit 0
fi

if [ -z "${SENTRY_AUTH_TOKEN:-}" ] || [ -z "${SENTRY_ORG:-}" ] || [ -z "${SENTRY_PROJECT:-}" ]; then
    echo "sentry-cli: SENTRY_* upload credentials not set; skipping dSYM upload."
    exit 0
fi

sentry-cli debug-files upload \
    --org "$SENTRY_ORG" \
    --project "$SENTRY_PROJECT" \
    "$CI_ARCHIVE_PATH"