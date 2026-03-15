param(
    [Parameter(Mandatory=$true)]
    [string]$OutputFile,

    [Parameter(Mandatory=$false)]
    [string]$AppNamePrefix = "ZylkerKart",

    [Parameter(Mandatory=$false)]
    [int]$RetryCount = 5,

    [Parameter(Mandatory=$false)]
    [int]$RetryDelaySec = 30,

    [Parameter(Mandatory=$false)]
    [int]$ExpectedAppCount = 6
)

# 1. Refresh OAuth Token
$tokenBody = @{
    grant_type    = "refresh_token"
    client_id     = $env:SITE24X7_CLIENT_ID
    client_secret = $env:SITE24X7_CLIENT_SECRET
    refresh_token = $env:SITE24X7_REFRESH_TOKEN
}
$tokenResponse = Invoke-RestMethod -Uri "https://accounts.zoho.com/oauth/v2/token" -Method POST -Body $tokenBody
$accessToken   = $tokenResponse.access_token

$headers = @{
    "Accept"        = "application/json; version=2.0"
    "Authorization" = "Zoho-oauthtoken $accessToken"
}

# 2. Retry loop
$apmData = $null
for ($i = 1; $i -le $RetryCount; $i++) {
    Write-Host "Attempt $i of $RetryCount - Fetching APM applications..." -ForegroundColor Cyan

    $response = Invoke-RestMethod -Uri "https://www.site24x7.com/api/apminsight/app/H" -Method GET -Headers $headers

    if ($response.code -eq 0 -and $response.data.Count -gt 0) {
        $apmData = $response.data
        Write-Host "Found $($apmData.Count) total APM applications" -ForegroundColor Green

        # Check if all expected apps have registered
        if ($ExpectedAppCount -gt 0) {
            $currentMatches = @($apmData | Where-Object {
                $_.application_info.application_name -like "$AppNamePrefix*"
            }).Count

            if ($currentMatches -lt $ExpectedAppCount) {
                Write-Host "Matched $currentMatches of $ExpectedAppCount expected apps. Waiting for remaining..." -ForegroundColor Yellow
                if ($i -lt $RetryCount) { Start-Sleep -Seconds $RetryDelaySec }
                $apmData = $null
                continue
            }
            Write-Host "All $ExpectedAppCount expected apps found" -ForegroundColor Green
        }

        break
    }

    if ($i -lt $RetryCount) {
        Write-Host "No APM apps found yet. Waiting $RetryDelaySec seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds $RetryDelaySec
    }
}

if (-not $apmData) {
    Write-Host "WARNING: No APM applications found after $RetryCount attempts" -ForegroundColor Red
    $emptyOutput = @{
        filter       = $AppNamePrefix
        applications = @()
        instances    = @()
        captured_at  = (Get-Date -Format o)
    }
    $emptyOutput | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputFile -Encoding utf8
    exit 0
}

# 3. Filter by name prefix
$filteredApps = $apmData | Where-Object {
    $_.application_info.application_name -like "$AppNamePrefix*"
}

$skippedApps = $apmData | Where-Object {
    $_.application_info.application_name -notlike "$AppNamePrefix*"
}

Write-Host ""
Write-Host "=======================================" -ForegroundColor White
Write-Host " Filter: $AppNamePrefix*" -ForegroundColor White
Write-Host "=======================================" -ForegroundColor White

$matchCount = 0
if ($filteredApps) { $matchCount = @($filteredApps).Count }
$skipCount = 0
if ($skippedApps) { $skipCount = @($skippedApps).Count }

Write-Host "  Matched: $matchCount apps" -ForegroundColor Green
Write-Host "  Skipped: $skipCount apps" -ForegroundColor DarkGray

foreach ($app in @($filteredApps)) {
    Write-Host "    + $($app.application_info.application_name)" -ForegroundColor Green
}

foreach ($app in @($skippedApps)) {
    Write-Host "    - $($app.application_info.application_name) (skipped)" -ForegroundColor DarkGray
}

# 4. Build structured data from filtered apps only
$applications = @()
$instances    = @()

foreach ($app in @($filteredApps)) {
    $appInfo = @{
        application_id   = $app.application_info.application_id
        application_name = $app.application_info.application_name
        instance_count   = $app.application_info.instance_count
    }
    $applications += $appInfo

    foreach ($prop in $app.application_info.instances.PSObject.Properties) {
        $inst = $prop.Value
        $instances += @{
            application_id   = $app.application_info.application_id
            application_name = $app.application_info.application_name
            instance_id      = $inst.instance_id
            instance_name    = $inst.instance_name
            host             = $inst.host
            port             = $inst.port
            ins_type         = $inst.ins_type
        }
    }
}

# 5. Store to file
$output = @{
    filter       = $AppNamePrefix
    applications = $applications
    instances    = $instances
    captured_at  = (Get-Date -Format o)
}

$output | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputFile -Encoding utf8

Write-Host ""
Write-Host "Stored $($applications.Count) apps and $($instances.Count) instances to: $OutputFile" -ForegroundColor Green