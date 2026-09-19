#!/usr/bin/env bash
set -euo pipefail

# Restarts every active instance onto the current 'default' build (e.g. after a deploy).
# PlayFlow gives players no warning; clients notice the drop and auto-rejoin by polling.
: "${PLAYFLOW_API_KEY:?Set PLAYFLOW_API_KEY to your server key (pf_...)}"
case "$PLAYFLOW_API_KEY" in
  pf_*) ;;
  *) echo 'A server API key is required; do not use the client key.' >&2; exit 1 ;;
esac
API='https://api.computeflow.cloud/api/v3/servers'
ids=$(curl --fail-with-body --silent --show-error "$API?include_launching=true" \
  --header "api-key: $PLAYFLOW_API_KEY" \
  | python3 -c 'import json,sys; print("\n".join(s["instance_id"] for s in json.load(sys.stdin).get("servers", [])))')
if [ -z "$ids" ]; then
  echo 'No active servers; the next player to press Play starts one.'
  exit 0
fi
for id in $ids; do
  echo "Restarting $id"
  curl --fail-with-body --silent --show-error --request POST "$API/$id/restart" \
    --header "api-key: $PLAYFLOW_API_KEY" --header 'Content-Type: application/json' \
    --data '{"version_tag":"default"}'
  echo
done
