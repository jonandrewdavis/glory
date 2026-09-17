#!/usr/bin/env bash
set -euo pipefail

# Upload builds/playflow-server.zip in the dashboard before running this.
# The private server key belongs only in this operator's environment.
: "${PLAYFLOW_API_KEY:?Set PLAYFLOW_API_KEY to your server key (pf_...)}"
case "$PLAYFLOW_API_KEY" in
  pf_*) ;;
  *) echo 'A server API key is required; do not use the client key.' >&2; exit 1 ;;
esac
curl --fail-with-body --silent --show-error \
  --request POST 'https://api.computeflow.cloud/api/v3/servers/start' \
  --header "api-key: $PLAYFLOW_API_KEY" \
  --header 'Content-Type: application/json' \
  --data '{"name":"glory","region":"us-east","compute_size":"small","ttl":3600,"version_tag":"default","port_configs":[{"name":"godot_websocket","internal_port":8080,"protocol":"tcp","tls_enabled":true}]}'
