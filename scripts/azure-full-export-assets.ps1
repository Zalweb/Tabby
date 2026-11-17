[CmdletBinding()]
param(
    [string]$ProjectRef = 'ziaqrkagsvozhotremsx',
    [string]$PublicKeyFile = '.dart_tool/azure-full/migration-public.pem',
    [string]$OutputFile = '.dart_tool/azure-full/source-assets.sealed.json'
)
$ErrorActionPreference = 'Stop'
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
if (-not $env:SUPABASE_ACCESS_TOKEN) { throw 'Source Supabase management access is required.' }
& git check-ignore --quiet -- $OutputFile
if ($LASTEXITCODE -ne 0) { throw 'Encrypted snapshots must use a Git-ignored output path.' }
$managementHeaders = @{Authorization = ('Bearer ' + $env:SUPABASE_ACCESS_TOKEN)}
$exportStage = 'service credential lookup'
try {
    $keys = Invoke-RestMethod -Uri "https://api.supabase.com/v1/projects/$ProjectRef/api-keys" -Headers $managementHeaders
    $serviceKey = ($keys | Where-Object { $_.name -eq 'service_role' } | Select-Object -First 1).api_key
    if (-not $serviceKey) { throw 'Service credential unavailable.' }
    $exportStage = 'provider configuration'
    $providerConfig = Invoke-RestMethod -Uri "https://api.supabase.com/v1/projects/$ProjectRef/config/auth" -Headers $managementHeaders
    $exportStage = 'object metadata'
    $objectRows = Invoke-RestMethod -Method Post -Uri "https://api.supabase.com/v1/projects/$ProjectRef/database/query/read-only" -Headers $managementHeaders -ContentType 'application/json' -Body (@{query='select id,bucket_id,name,owner,metadata from storage.objects order by bucket_id,name'} | ConvertTo-Json)
    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    $client.DefaultRequestHeaders.Add('apikey', $serviceKey)
    $client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $serviceKey)
    $objects = @()
    $exportStage = 'private object download'
    foreach ($row in $objectRows) {
        if ([long]$row.metadata.size -gt 16777216) { throw 'Object exceeds the bounded snapshot limit.' }
        $encodedBucket = [Uri]::EscapeDataString($row.bucket_id)
        $encodedName = (($row.name -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
        $bytes = $client.GetByteArrayAsync("https://$ProjectRef.supabase.co/storage/v1/object/$encodedBucket/$encodedName").GetAwaiter().GetResult()
        if ($bytes.Length -gt 16777216) { throw 'Object exceeds the bounded snapshot limit.' }
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        $digest = ([BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
        $hasher.Dispose()
        $objects += @{id=$row.id;bucket_id=$row.bucket_id;name=$row.name;owner=$row.owner;metadata=$row.metadata;sha256=$digest;bytes_base64=[Convert]::ToBase64String($bytes)}
    }
    $snapshot = @{version=1;captured_at=[DateTimeOffset]::Now.ToString('o');project_ref=$ProjectRef;auth_config=$providerConfig;objects=$objects}
    $exportStage = 'snapshot encryption'
    $snapshot | ConvertTo-Json -Depth 30 -Compress | & node scripts/azure-full-seal.cjs $PublicKeyFile $OutputFile
    if ($LASTEXITCODE -ne 0) { throw 'Encryption did not complete.' }
    [pscustomobject]@{encrypted=$true;objects=$objects.Count;output=$OutputFile;database_export_included=$false} | ConvertTo-Json
} catch {
    throw "Source asset export failed at $exportStage ($($_.Exception.GetType().Name)). Credentials and object details were withheld."
} finally {
    if ($client) { $client.Dispose() }
    $serviceKey = $null
    $keys = $null
    $providerConfig = $null
    $snapshot = $null
    $objects = $null
}
