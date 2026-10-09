#!/usr/bin/env bash
set -euo pipefail
host="${APP}-staging.azurewebsites.net"
base="https://$host"
actual=$(curl -fsS --retry 12 --retry-all-errors "$base/version" | jq -r .version)
test "$actual" = "$RELEASE"
curl -fsS "$base/health" >/dev/null
curl -fsS "$base/lab/probe" >/dev/null
start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
count=20
case "$SCENARIO" in
  empty) count=0 ;;
  insufficient) count=19 ;;
  unhealthy|healthy) ;;
  *) exit 1 ;;
esac
for ((i=1; i<=count; i++)); do
  fail=false
  if [[ "$SCENARIO" == unhealthy && "$i" == 20 ]]; then fail=true; fi
  code=$(curl -sS -o /dev/null -w '%{http_code}' \
    "$base/lab/probe?release=$RELEASE&case=$GITHUB_RUN_ID&fail=$fail")
  if [[ "$fail" == true ]]; then test "$code" = 500; else test "$code" = 200; fi
done
query="AppRequests
| where TimeGenerated >= datetime($start)
| where tostring(parse_url(Url).Host) =~ '$host'
| where Url contains '/lab/probe?release=$RELEASE&case=$GITHUB_RUN_ID&'
| summarize Total=sum(ItemCount), Failed=sumif(ItemCount,Success==false),
            P95Ms=percentile(DurationMs,95)
| extend Pass=Total >= 20 and Failed == 0 and P95Ms < 1000"
for ((attempt=1; attempt<=24; attempt++)); do
  result=$(az monitor log-analytics query -w "$WORKSPACE_ID" \
    --analytics-query "$query" -o json)
  total=$(jq -r '.[0].Total // 0' <<< "$result")
  if [[ "$total" -ge "$count" && "$attempt" -ge 3 ]]; then break; fi
  sleep 20
done
echo "$result"
{
  echo "## ClientHub candidate telemetry"
  echo "| Scenario | Requests | Failures | p95 ms | Pass |"
  echo "|---|---:|---:|---:|---|"
  jq -r --arg s "$SCENARIO" \
    '.[0] | "| \($s) | \(.Total) | \(.Failed) | \(.P95Ms) | \(.Pass) |"' <<< "$result"
  echo ""
  echo "Scope: staging hostname, this release, this run, after deployment."
} >> "$GITHUB_STEP_SUMMARY"
pass=$(jq -r '.[0].Pass // false' <<< "$result")
if [[ "$pass" != true ]]; then
  echo "Promotion blocked: unhealthy, missing or insufficient telemetry."
  exit 1
fi
echo "Telemetry gate passed; production still requires review."
