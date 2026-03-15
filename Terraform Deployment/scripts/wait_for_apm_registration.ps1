param(
    [Parameter(Mandatory=$true)]
    [string]$AppNamePrefix,

    [Parameter(Mandatory=$false)]
    [int]$ExpectedAppCount = 6,

    [Parameter(Mandatory=$false)]
    [int]$MaxAttempts = 10,

    [Parameter(Mandatory=$false)]
    [int]$DelaySec = 30
)

$ErrorActionPreference = "Stop"

# ── Validate environment variables ──
$requiredVars = @("SITE24X7_CLIENT_ID", "SITE24X7_CLIENT_SECRET", "SITE24X7_REFRESH_TOKEN")
foreach ($varName in $requiredVars) {
    $val = [System.Environment]::GetEnvironmentVariable($varName)
    if ([string]::IsNullOrWhiteSpace($val)) {
        Write-Error "ERROR: Environment variable '$varName' is not set. Set it before running terraform apply with APM enabled."
        exit 1
    }
}

# ── Refresh OAuth token ──
Write-Host "Refreshing Site24x7 OAuth token..." -ForegroundColor Cyan
$tokenBody = @{
    grant_type    = "refresh_token"
    client_id     = $env:SITE24X7_CLIENT_ID
    client_secret = $env:SITE24X7_CLIENT_SECRET
    refresh_token = $env:SITE24X7_REFRESH_TOKEN
}

try {
    $tokenResponse = Invoke-RestMethod -Uri "https://accounts.zoho.com/oauth/v2/token" -Method POST -Body $tokenBody
} catch {
    Write-Error "ERROR: OAuth token refresh request failed: $_"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($tokenResponse.access_token)) {
    Write-Error "ERROR: OAuth token refresh returned no access_token. Response: $($tokenResponse | ConvertTo-Json -Compress). Check that SITE24X7_CLIENT_ID, SITE24X7_CLIENT_SECRET, and SITE24X7_REFRESH_TOKEN are valid and not expired."
    exit 1
}

Write-Host "  OAuth token obtained successfully." -ForegroundColor Green

$headers = @{
    "Accept"        = "application/json; version=2.0"
    "Authorization" = "Zoho-oauthtoken $($tokenResponse.access_token)"
}

$matched = 0
for ($i = 1; $i -le $MaxAttempts; $i++) {
    Write-Host "Attempt $i of $MaxAttempts - Checking APM registrations..." -ForegroundColor Cyan
    try {
        $response = Invoke-RestMethod -Uri "https://www.site24x7.com/api/apminsight/app/H" -Method GET -Headers $headers
    } catch {
        Write-Host "  API request failed: $_" -ForegroundColor Red
        if ($i -lt $MaxAttempts) {
            Write-Host "  Waiting $DelaySec seconds before next check..." -ForegroundColor Yellow
            Start-Sleep -Seconds $DelaySec
        }
        continue
    }

    if ($response.code -eq 0 -and $response.data.Count -gt 0) {
        $matched = @($response.data | Where-Object {
            $_.application_info.application_name -like "$AppNamePrefix*"
        }).Count
        Write-Host "  Found $matched of $ExpectedAppCount expected apps" -ForegroundColor Yellow

        if ($matched -ge $ExpectedAppCount) {
            Write-Host "All $ExpectedAppCount expected APM apps registered!" -ForegroundColor Green
            exit 0
        }
    } else {
        Write-Host "  API returned code=$($response.code), data count=$($response.data.Count)" -ForegroundColor Yellow
    }

    if ($i -lt $MaxAttempts) {
        Write-Host "  Waiting $DelaySec seconds before next check..." -ForegroundColor Yellow
        Start-Sleep -Seconds $DelaySec
    }
}

Write-Error "TIMEOUT: Only found $matched of $ExpectedAppCount apps after $MaxAttempts attempts"
exit 1
