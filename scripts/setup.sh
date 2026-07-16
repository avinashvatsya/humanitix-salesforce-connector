#!/usr/bin/env bash
#
# Create a scratch org, deploy the connector, and assign the admin permission set.
# Requires the Salesforce CLI (sf v2) and an authenticated Dev Hub.
#
# Usage:  ./scripts/setup.sh [org-alias]
#
set -euo pipefail

ALIAS="${1:-htx-dev}"

echo "==> Creating scratch org '$ALIAS' (7 days)"
sf org create scratch --definition-file config/project-scratch-def.json --alias "$ALIAS" --duration-days 7 --wait 10 --set-default

echo "==> Deploying source"
sf project deploy start --target-org "$ALIAS" --wait 30

echo "==> Assigning permission set Humanitix_Integration_Admin"
sf org assign permset --name Humanitix_Integration_Admin --target-org "$ALIAS"

cat <<'EONOTE'

==> Done.

Next steps (see docs/CONFIGURATION.md):
  1. Setup > Security > Named Credentials > External Credentials > "Humanitix API"
     -> open the "Humanitix_Named_Principal" principal, add an Authentication
        Parameter named exactly "ApiKey" and paste your Humanitix API key.
  2. Make sure the running/integration user is a Marketing User (to sync
     Campaigns and Campaign Members).
  3. Open the "Humanitix Integration" app > "Humanitix Setup" tab and click
     "Run Sync Now", or schedule it:
        HumanitixSyncScheduler.schedule('Humanitix Nightly Sync', '0 0 2 * * ?');
EONOTE

sf org open --target-org "$ALIAS"
