#!/usr/bin/env bash
set -euo pipefail

# Usage: PLAYFLOW_API_KEY=pf_... bash tools/upload_playflow.sh [builds/playflow-server.zip]
# Uploads the server ZIP as the next "default" build and waits until it is ready.
# Uses only curl and sed so it runs in the CI container (no python3 or jq).
cd "$(dirname "$0")/.."
: "${PLAYFLOW_API_KEY:?Set PLAYFLOW_API_KEY to your server key (pf_...)}"
case "$PLAYFLOW_API_KEY" in
  pf_*) ;;
  *) echo 'A server API key (pf_...) is required; the client key cannot upload.' >&2; exit 1 ;;
esac
zip_path="${1:-builds/playflow-server.zip}"
[ -f "$zip_path" ] || { echo "Missing $zip_path; run tools/prepare_playflow.sh first." >&2; exit 1; }
api='https://api.computeflow.cloud/api/v3/builds'
build_name="${PLAYFLOW_BUILD_NAME:-default}"

json_field() { sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" | head -n 1; }

response="$(curl --fail-with-body --silent --show-error --request POST \
  "$api/upload-url?name=$build_name&executable_path=Server.x86_64" \
  --header "api-key: $PLAYFLOW_API_KEY")"
build_id="$(printf '%s' "$response" | json_field build_id)"
upload_url="$(printf '%s' "$response" | json_field upload_url | sed 's#\\/#/#g; s/\\u0026/\&/g')"
[ -n "$build_id" ] && [ -n "$upload_url" ] || { echo "Unexpected upload-url response: $response" >&2; exit 1; }
echo "Uploading $zip_path as build '$build_name' ($build_id)"
curl --fail --silent --show-error --request PUT --upload-file "$zip_path" \
  --header 'Content-Type: application/zip' "$upload_url"

for _ in $(seq 1 60); do
  status="$(curl --fail --silent --show-error "$api/$build_id" --header "api-key: $PLAYFLOW_API_KEY" | json_field status)"
  echo "Build status: $status"
  case "$status" in
    ready) echo "PlayFlow build '$build_name' is ready; the next server start uses it."; exit 0 ;;
    failed) curl --silent "$api/$build_id/logs" --header "api-key: $PLAYFLOW_API_KEY" >&2; echo; exit 1 ;;
  esac
  sleep 10
done
echo 'Timed out waiting for the build to become ready.' >&2
exit 1
