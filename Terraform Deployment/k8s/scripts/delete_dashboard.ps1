param(
    [Parameter(Mandatory=$true)]
    [string]$OutputFile,

    [Parameter(Mandatory=$false)]
    [string]$ZohoAccountsBase = "https://accounts.zoho.com",

    [Parameter(Mandatory=$false)]
    [string]$Site24x7ApiBase = "https://www.site24x7.com"
)

$ErrorActionPreference = "Stop"

# ----------------------------------------------
# 1. Read dashboard ID from output file
# ----------------------------------------------
if (-not (Test-Path $OutputFile)) {
    Write-Host "Output file '$OutputFile' not found -- dashboard may already be deleted. Skipping." -ForegroundColor Yellow
    exit 0
}

$outputData = Get-Content -Path $OutputFile -Raw | ConvertFrom-Json
$dashboardId = $outputData.dashboard_id

if (-not $dashboardId -or $dashboardId -eq "") {
    Write-Host "No dashboard_id found in output file. Skipping deletion." -ForegroundColor Yellow
    exit 0
}

# Override base URLs from output file if present (written by create_dashboard.ps1)
if ($outputData.zoho_accounts_base) { $ZohoAccountsBase = $outputData.zoho_accounts_base }
if ($outputData.site24x7_api_base)  { $Site24x7ApiBase  = $outputData.site24x7_api_base }

Write-Host "Dashboard to delete: $dashboardId ($($outputData.name))" -ForegroundColor Cyan

# ----------------------------------------------
# 2. Refresh OAuth Token
# ----------------------------------------------
Write-Host "Refreshing OAuth2 access token..." -ForegroundColor Cyan

$tokenBody = @{
    grant_type    = "refresh_token"
    client_id     = $env:SITE24X7_CLIENT_ID
    client_secret = $env:SITE24X7_CLIENT_SECRET
    refresh_token = $env:SITE24X7_REFRESH_TOKEN
}
$tokenResponse = Invoke-RestMethod -Uri "$ZohoAccountsBase/oauth/v2/token" -Method POST -Body $tokenBody -TimeoutSec 30
$accessToken   = $tokenResponse.access_token

if (-not $accessToken) {
    Write-Error "FAILED: Could not obtain access token from Zoho OAuth2"
    exit 1
}
Write-Host "  Access token obtained." -ForegroundColor Green

$headers = @{
    "Accept"        = "application/json; version=2.0"
    "Authorization" = "Zoho-oauthtoken $accessToken"
    "Content-Type"  = "application/json"
}

# ----------------------------------------------
# 3. Delete dashboard
# ----------------------------------------------
Write-Host "Deleting dashboard $dashboardId..." -ForegroundColor Cyan

try {
    $deleteUrl = "$Site24x7ApiBase/api/dashboards/$dashboardId"
    $response = Invoke-RestMethod -Uri $deleteUrl -Method DELETE -Headers $headers -TimeoutSec 30

    if ($response.code -eq 0) {
        Write-Host "  Dashboard deleted successfully." -ForegroundColor Green
    } else {
        Write-Host "  Delete response: $($response | ConvertTo-Json -Compress -Depth 5)" -ForegroundColor Yellow
    }
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 404) {
        Write-Host "  Dashboard $dashboardId not found (already deleted). Skipping." -ForegroundColor Yellow
    } else {
        Write-Host "  Warning: Could not delete dashboard: $($_.Exception.Message)" -ForegroundColor Yellow
        # Do not fail destroy -- best-effort cleanup
    }
}

# ----------------------------------------------
# 4. Clean up output file
# ----------------------------------------------
if (Test-Path $OutputFile) {
    Remove-Item -Path $OutputFile -Force
    Write-Host "  Output file removed." -ForegroundColor Gray
}

Write-Host "SUCCESS: Dashboard cleanup complete." -ForegroundColor Green
