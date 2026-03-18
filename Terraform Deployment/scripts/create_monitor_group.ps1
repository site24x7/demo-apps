param(
    [Parameter(Mandatory=$true)]
    [string]$GroupName,

    [Parameter(Mandatory=$true)]
    [string]$MonitorIds,

    [Parameter(Mandatory=$false)]
    [string]$Description = "Monitor group for ZylkerKart APM applications (managed by Terraform)",

    [Parameter(Mandatory=$false)]
    [int]$HealthThresholdCount = 0,

    [Parameter(Mandatory=$false)]
    [string]$OutputFile = ""
)

$ErrorActionPreference = "Stop"

# ──────────────────────────────────────────────
# 1. Refresh OAuth Token
# ──────────────────────────────────────────────
Write-Host "Refreshing OAuth2 access token..." -ForegroundColor Cyan

$tokenBody = @{
    grant_type    = "refresh_token"
    client_id     = $env:SITE24X7_CLIENT_ID
    client_secret = $env:SITE24X7_CLIENT_SECRET
    refresh_token = $env:SITE24X7_REFRESH_TOKEN
}
$tokenResponse = Invoke-RestMethod -Uri "https://accounts.zoho.com/oauth/v2/token" -Method POST -Body $tokenBody
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

# Parse monitor IDs from comma-separated string
$monitorIdList = @($MonitorIds -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
Write-Host "  Monitor IDs to add: $($monitorIdList -join ', ')" -ForegroundColor Cyan

if ($monitorIdList.Count -eq 0) {
    Write-Error "FAILED: No monitor IDs provided"
    exit 1
}

# ──────────────────────────────────────────────
# 2. Check if monitor group already exists
# ──────────────────────────────────────────────
Write-Host "Checking for existing monitor group '$GroupName'..." -ForegroundColor Cyan

$existingGroupId = $null
try {
    $allGroups = Invoke-RestMethod -Uri "https://www.site24x7.com/api/monitor_groups" `
        -Method GET -Headers $headers -TimeoutSec 30

    if ($allGroups.code -eq 0 -and $allGroups.data) {
        $match = $allGroups.data | Where-Object { $_.display_name -eq $GroupName } | Select-Object -First 1
        if ($match) {
            $existingGroupId = $match.group_id
            Write-Host "  Found existing group: $existingGroupId" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "  Could not list groups (non-fatal): $($_.Exception.Message)" -ForegroundColor Yellow
}

# ──────────────────────────────────────────────
# 3. Build request body
# ──────────────────────────────────────────────
$body = @{
    display_name           = $GroupName
    description            = $Description
    health_threshold_count = $HealthThresholdCount
    monitors               = $monitorIdList
    suppress_alert         = $false
}

$jsonBody = $body | ConvertTo-Json -Depth 5 -Compress

# ──────────────────────────────────────────────
# 4. Create or Update
# ──────────────────────────────────────────────
$resultGroupId = $null

if ($existingGroupId) {
    # UPDATE existing group
    Write-Host "Updating monitor group $existingGroupId..." -ForegroundColor Cyan

    $updateUrl = "https://www.site24x7.com/api/monitor_groups/$existingGroupId"
    $response = Invoke-RestMethod -Uri $updateUrl -Method PUT -Headers $headers `
        -Body $jsonBody -TimeoutSec 30

    if ($response.code -eq 0 -and $response.data) {
        $resultGroupId = $response.data.group_id
        Write-Host "  Monitor group updated successfully: $resultGroupId" -ForegroundColor Green
    } else {
        Write-Error "FAILED: Update returned unexpected response: $($response | ConvertTo-Json -Compress -Depth 5)"
        exit 1
    }
} else {
    # CREATE new group
    Write-Host "Creating monitor group '$GroupName'..." -ForegroundColor Cyan

    $response = Invoke-RestMethod -Uri "https://www.site24x7.com/api/monitor_groups" `
        -Method POST -Headers $headers -Body $jsonBody -TimeoutSec 30

    if ($response.code -eq 0 -and $response.data) {
        $resultGroupId = $response.data.group_id
        Write-Host "  Monitor group created successfully: $resultGroupId" -ForegroundColor Green
    } else {
        Write-Error "FAILED: Create returned unexpected response: $($response | ConvertTo-Json -Compress -Depth 5)"
        exit 1
    }
}

# ──────────────────────────────────────────────
# 5. Verify membership
# ──────────────────────────────────────────────
Write-Host "Verifying monitor group membership..." -ForegroundColor Cyan

$verifyUrl = "https://www.site24x7.com/api/monitor_groups/$resultGroupId"
$verifyResponse = Invoke-RestMethod -Uri $verifyUrl -Method GET -Headers $headers -TimeoutSec 30

if ($verifyResponse.code -eq 0 -and $verifyResponse.data) {
    $memberMonitors = @($verifyResponse.data.monitors)
    Write-Host "  Group '$GroupName' has $($memberMonitors.Count) monitor(s):" -ForegroundColor Green
    foreach ($m in $memberMonitors) {
        Write-Host "    - $m" -ForegroundColor Gray
    }
} else {
    Write-Host "  Warning: Could not verify group membership" -ForegroundColor Yellow
}

# ──────────────────────────────────────────────
# 6. Write output file (if requested)
# ──────────────────────────────────────────────
if ($OutputFile -ne "") {
    $output = @{
        group_id     = $resultGroupId
        display_name = $GroupName
        monitors     = $monitorIdList
    } | ConvertTo-Json -Depth 5

    $output | Set-Content -Path $OutputFile -Force
    Write-Host "Output written to $OutputFile" -ForegroundColor Green
}

Write-Host "SUCCESS: Monitor group '$GroupName' (ID: $resultGroupId) is ready with $($monitorIdList.Count) monitors." -ForegroundColor Green
