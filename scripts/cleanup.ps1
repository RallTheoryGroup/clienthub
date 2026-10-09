param(
    [string]$ResourceGroup = 'rg-clienthub-ch11',
    [string]$MonitoringGroup = 'rg-clienthub-monitor-ch16',
    [string]$SharedGroup = 'rg-ralltheory-shared'
)
$ErrorActionPreference = 'Stop'
$account = az account show -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Azure sign-in failed' }
$variables = gh variable list --json name,value | ConvertFrom-Json
$principal = ($variables | Where-Object name -eq AZURE_CLIENT_ID).value
if (!$principal) { throw 'Deployment identity must be recorded before cleanup' }
$assignments = az role assignment list --assignee $principal --all -o json | ConvertFrom-Json
foreach ($assignment in $assignments) {
    az role assignment delete --ids $assignment.id
    if ($LASTEXITCODE -ne 0) { throw 'Role cleanup failed' }
}
az monitor app-insights web-test delete -g $SharedGroup -n ch16-clienthub-health --yes
if ($LASTEXITCODE -ne 0) { throw 'Availability test cleanup failed' }
az group delete -n $MonitoringGroup --yes
if ($LASTEXITCODE -ne 0) { throw 'Monitoring group cleanup failed' }
az group delete -n $ResourceGroup --yes
if ($LASTEXITCODE -ne 0) { throw 'App Service group cleanup failed' }
az ad app delete --id $principal
if ($LASTEXITCODE -ne 0) { throw 'App registration cleanup failed' }
foreach ($name in 'AZURE_CLIENT_ID','AZURE_TENANT_ID',
    'AZURE_SUBSCRIPTION_ID','AI_ID','WORKSPACE_ID') {
    gh variable delete $name
}
foreach ($environment in 'staging','production') {
    $items = gh variable list --env $environment --json name | ConvertFrom-Json
    foreach ($item in $items) { gh variable delete $item.name --env $environment }
}
Remove-Variable principal,assignments,account,variables
Write-Output 'Owned app, monitoring resources, deployment identity, roles and Azure variables removed.'
