param(
    [string]$ResourceGroup = 'rg-clienthub-ch11',
    [string]$AppName = 'clienthub-rtg-aa',
    [string]$MonitoringGroup = 'rg-clienthub-monitor-ch16',
    [string]$InsightsName = 'ai-ralltheory-qwh5vxpgarqhg',
    [string]$WorkspaceName = 'la-ralltheory-qwh5vxpgarqhg',
    [string]$SharedGroup = 'rg-ralltheory-shared'
)
$ErrorActionPreference = 'Stop'
$account = az account show -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Azure sign-in failed' }
$insights = az monitor app-insights component show -g $SharedGroup --app $InsightsName -o json | ConvertFrom-Json
$workspace = az monitor log-analytics workspace show -g $SharedGroup -n $WorkspaceName -o json | ConvertFrom-Json
if (!$insights.connectionString -or !$workspace.customerId) { throw 'Monitoring destination missing' }
foreach ($slot in 'production','staging') {
    $arguments = @('webapp','config','appsettings','set','-g',$ResourceGroup,'-n',$AppName,
        '--slot-settings',"APPLICATIONINSIGHTS_CONNECTION_STRING=$($insights.connectionString)",'-o','none')
    if ($slot -eq 'staging') { $arguments += @('--slot','staging') }
    az @arguments
    if ($LASTEXITCODE -ne 0) { throw 'App setting failed' }
}
$insights.connectionString = $null
gh variable set AI_ID -b $insights.id
gh variable set WORKSPACE_ID -b $workspace.customerId
$variables = gh variable list --json name,value | ConvertFrom-Json
$principal = ($variables | Where-Object name -eq AZURE_CLIENT_ID).value
foreach ($assignment in @(
    @('Application Insights Component Contributor',$insights.id),
    @('Log Analytics Reader',$workspace.id)
)) {
    az role assignment create --assignee $principal --role $assignment[0] --scope $assignment[1] -o none
    if ($LASTEXITCODE -ne 0) { throw 'Scoped monitoring role failed' }
}
az group create -n $MonitoringGroup -l centralus -o none
$testName = 'ch16-clienthub-health'
$testId = "/subscriptions/$($account.id)/resourceGroups/$SharedGroup/providers/Microsoft.Insights/webtests/$testName"
$test = @{
    location='eastus'; tags=@{("hidden-link:$($insights.id)")='Resource'}
    properties=@{
        SyntheticMonitorId=$testName; Name=$testName; Enabled=$true
        Frequency=300; Timeout=30; Kind='standard'; RetryEnabled=$true
        Locations=@(@{Id='us-ca-sjc-azr'},@{Id='us-il-ch1-azr'},@{Id='emea-nl-ams-azr'})
        Request=@{RequestUrl="https://$AppName-staging.azurewebsites.net/health";HttpVerb='GET';ParseDependentRequests=$false}
        ValidationRules=@{ExpectedHttpStatusCode=200;IgnoreHttpStatusCode=$false}
    }
}
$test | ConvertTo-Json -Depth 8 | Set-Content monitor-test.json
az rest -m put -u "https://management.azure.com${testId}?api-version=2022-06-15" -b '@monitor-test.json' -o none
if ($LASTEXITCODE -ne 0) { throw 'Availability test creation failed' }
$alertName = 'ch16-clienthub-availability'
$alertId = "/subscriptions/$($account.id)/resourceGroups/$MonitoringGroup/providers/Microsoft.Insights/metricAlerts/$alertName"
$alert = @{
    location='global'
    properties=@{
        description='ClientHub staging availability: one failing test location'
        severity=2;enabled=$true;scopes=@($insights.id,$testId)
        evaluationFrequency='PT1M';windowSize='PT5M';autoMitigate=$true
        criteria=@{
            'odata.type'='Microsoft.Azure.Monitor.WebtestLocationAvailabilityCriteria'
            webTestId=$testId;componentId=$insights.id;failedLocationCount=1
        }
        actions=@()
    }
}
$alert | ConvertTo-Json -Depth 8 | Set-Content monitor-alert.json
az rest -m put -u "https://management.azure.com${alertId}?api-version=2018-03-01" -b '@monitor-alert.json' -o none
if ($LASTEXITCODE -ne 0) { throw 'Availability alert creation failed' }
Remove-Item monitor-test.json,monitor-alert.json
Write-Output 'Sticky telemetry settings, scoped roles, availability test and alert ready.'
