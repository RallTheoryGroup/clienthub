#!/usr/bin/env bash
set -euo pipefail
host="https://${APP}-staging.azurewebsites.net"
curl -fsS --retry 12 --retry-all-errors "$host/health"
actual=$(curl -fsS "$host/version" | jq -r .version)
test "$actual" = "$RELEASE"
jq -n --arg v "$RELEASE" --arg id "$(uuidgen)" \
  --arg host "$host" --arg commit "$GITHUB_SHA" \
  --arg run "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
  '{Id:$id,AnnotationName:"ClientHub staging \($v)",
    Category:"Deployment",EventTime:(now|todate),
    Properties:({ReleaseName:$v,Host:$host,Commit:$commit,
                 Run:$run}|tojson)}' > note.json
az rest -m put -b @note.json -o none \
  -u "https://management.azure.com$AI_ID/Annotations?api-version=2015-05-01"
echo "Healthy staging $RELEASE; deployment annotation written."
echo "### ClientHub staging $RELEASE" >> "$GITHUB_STEP_SUMMARY"
echo "Health and version verified; Deployment annotation written." >> "$GITHUB_STEP_SUMMARY"
