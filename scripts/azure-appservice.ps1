[CmdletBinding()]
param(
    [ValidateSet('Inspect', 'Plan', 'Provision', 'Deploy', 'Verify')][string]$Mode = 'Inspect',
    [Parameter(Mandatory = $true)][string]$SubscriptionId,
    [string]$ResourceGroup,
    [string]$ParametersFile,
    [string]$AppName,
    [string]$Location = 'southeastasia',
    [switch]$Approved
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
function Run-Az {
    param([string[]]$Arguments)
    & az @Arguments --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw 'Azure command failed; inspect its sanitized error before continuing.' }
}
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Install Azure CLI and sign in with az login; no changes were made.' }
if ($Mode -in @('Provision', 'Deploy') -and -not $Approved) { throw 'Explicit approval of cost and deployment is required; pass -Approved only after approval.' }
# Every operation targets the explicit subscription, never a machine-wide default.
$subscriptionArgs = @('--subscription', $SubscriptionId)
if ($Mode -eq 'Inspect') {
    Run-Az -Arguments (@('account', 'show') + $subscriptionArgs + @('--query', '{id:id,name:name,state:state,tenantId:tenantId}', '-o', 'json'))
    Run-Az -Arguments (@('resource', 'list') + $subscriptionArgs + @('--query', '[].{name:name,type:type,location:location,resourceGroup:resourceGroup}', '-o', 'json'))
    Run-Az -Arguments (@('appservice', 'plan', 'list') + $subscriptionArgs + @('--query', '[].{id:id,name:name,location:location,sku:sku.name,linux:reserved,apps:numberOfSites}', '-o', 'json'))
    Run-Az -Arguments (@('webapp', 'list-runtimes', '--os', 'linux') + $subscriptionArgs + @('-o', 'json'))
    return
}
if (-not $ResourceGroup) { throw '-ResourceGroup is required.' }
if ($Mode -in @('Plan', 'Provision')) {
    if (-not $ParametersFile) { throw '-ParametersFile is required; use credential-free parameters.example.json as a starting point.' }
    $parametersPath = (Resolve-Path -LiteralPath $ParametersFile).Path
    $parameters = Get-Content -LiteralPath $parametersPath -Raw | ConvertFrom-Json
    if (($parameters | ConvertTo-Json -Depth 20) -match 'REPLACE') { throw 'Resolve parameter placeholders first.' }
    if ($parameters.parameters.location.value -ne $Location) { throw 'Parameter location must match -Location.' }
    $backendUri = [Uri]$parameters.parameters.supabaseUrl.value
    if ($backendUri.Scheme -ne 'https' -or $backendUri.UserInfo -or $backendUri.AbsolutePath -ne '/' -or $backendUri.Query -or $backendUri.Fragment) { throw 'Supabase URL must be an HTTPS origin.' }
    $deploymentArgs = @('--resource-group', $ResourceGroup, '--template-file', (Join-Path $repoRoot 'deploy/azure/main.json'), '--parameters', "@$parametersPath") + $subscriptionArgs
    if ($Mode -eq 'Plan') {
        # Requires a pre-existing resource group; Plan never creates one.
        Run-Az -Arguments (@('deployment', 'group', 'validate') + $deploymentArgs + @('-o', 'none'))
        Run-Az -Arguments (@('deployment', 'group', 'what-if') + $deploymentArgs)
        return
    }
    Run-Az -Arguments (@('group', 'create', '--name', $ResourceGroup, '--location', $Location) + $subscriptionArgs + @('-o', 'none'))
    Run-Az -Arguments (@('deployment', 'group', 'create', '--mode', 'Incremental') + $deploymentArgs + @('--query', 'properties.outputs', '-o', 'json'))
    return
}
if (-not $AppName) { throw '-AppName is required.' }
$appArgs = @('--resource-group', $ResourceGroup, '--name', $AppName) + $subscriptionArgs
if ($Mode -eq 'Deploy') {
    & node (Join-Path $repoRoot 'scripts/azure-package.cjs')
    if ($LASTEXITCODE -ne 0) { throw 'Package preparation failed.' }
    $zipPath = Join-Path $repoRoot '.dart_tool/azure-workers/workers.zip'
    Compress-Archive -Path (Join-Path $repoRoot '.dart_tool/azure-workers/package/*') -DestinationPath $zipPath -Force
    Run-Az -Arguments (@('webapp', 'log', 'config') + $appArgs + @('--docker-container-logging', 'filesystem', '-o', 'none'))
    Run-Az -Arguments (@('webapp', 'deploy') + $appArgs + @('--src-path', $zipPath, '--type', 'zip', '-o', 'none'))
    return
}
$hostName = Run-Az -Arguments (@('webapp', 'show') + $appArgs + @('--query', 'defaultHostName', '-o', 'tsv'))
foreach ($path in @('/healthz', '/readyz')) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "https://$hostName$path" -TimeoutSec 30
        Write-Output "$path $($response.StatusCode)"
    } catch {
        # Never print request headers, provider response bodies or secrets.
        Write-Output "$path failed or not ready"
        throw 'Endpoint verification did not pass; workers may still be intentionally disabled.'
    }
}
# Downloading/tailing logs can include historical provider data: inspect locally,
# redact before sharing. The adapter itself only emits allowlisted route/status/timing.
Write-Output 'Endpoints passed. Next inspect: az webapp log tail --subscription <id> --resource-group <group> --name <app>'
