param(
    [Parameter(Mandatory=$true)]
    [string]$DashboardName,

    [Parameter(Mandatory=$false)]
    [int]$Theme = 1,

    [Parameter(Mandatory=$false)]
    [int]$Size = 10,

    [Parameter(Mandatory=$false)]
    [string]$Version = "2.1",

    [Parameter(Mandatory=$false)]
    [string]$Description = "",

    [Parameter(Mandatory=$false)]
    [string]$WidgetsJson = "",

    [Parameter(Mandatory=$false)]
    [string]$WidgetsFile = "",

    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "",

    [Parameter(Mandatory=$false)]
    [string]$ZohoAccountsBase = "https://accounts.zoho.com",

    [Parameter(Mandatory=$false)]
    [string]$Site24x7ApiBase = "https://www.site24x7.com"
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
$tokenResponse = Invoke-RestMethod -Uri "$ZohoAccountsBase/oauth/v2/token" -Method POST -Body $tokenBody
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

# ──────────────────────────────────────────────
# 2. Check if dashboard already exists
#    Uses OutputFile from a previous run to find the dashboard_id,
#    then verifies it still exists via GET /api/dashboards/<id>
# ──────────────────────────────────────────────
Write-Host "Checking for existing dashboard '$DashboardName'..." -ForegroundColor Cyan

$existingDashboardId = $null
if ($OutputFile -ne "" -and (Test-Path $OutputFile)) {
    try {
        $prevOutput = Get-Content -Path $OutputFile -Raw | ConvertFrom-Json
        $prevId = $prevOutput.dashboard_id
        if ($prevId -and $prevId -ne "") {
            Write-Host "  Found previous dashboard_id in output file: $prevId" -ForegroundColor Cyan
            # Verify it still exists via GET /api/dashboards/<id>
            try {
                $checkResponse = Invoke-RestMethod `
                    -Uri "$Site24x7ApiBase/api/dashboards/$prevId" `
                    -Method GET -Headers $headers -TimeoutSec 30

                if ($checkResponse.code -eq 0 -and $checkResponse.data) {
                    $existingDashboardId = $prevId
                    Write-Host "  Dashboard still exists: $existingDashboardId" -ForegroundColor Yellow
                }
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
                if ($statusCode -eq 404) {
                    Write-Host "  Previous dashboard $prevId no longer exists (404). Will create new." -ForegroundColor Yellow
                } else {
                    Write-Host "  Could not verify dashboard $prevId (non-fatal): $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
    } catch {
        Write-Host "  Could not read output file (non-fatal): $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  No previous output file found. Will create new dashboard." -ForegroundColor Cyan
}

# ──────────────────────────────────────────────
# 3. Build request body
# ──────────────────────────────────────────────
$body = @{
    name    = $DashboardName
    size    = $Size
    theme   = $Theme
    version = $Version
}

if ($Description -ne "") {
    $body["description"] = $Description
}

# Load raw widgets JSON string (file takes precedence over inline JSON).
# IMPORTANT: We keep widgets as a raw JSON string and splice it into the
# final payload manually. This avoids a PowerShell 5.x bug where
# ConvertFrom-Json wraps arrays in a PSCustomObject with a .value property,
# causing ConvertTo-Json to emit {"value":[...]} instead of [...].
$rawWidgetsJson = ""
if ($WidgetsFile -ne "" -and (Test-Path $WidgetsFile)) {
    try {
        $rawWidgetsJson = (Get-Content -Path $WidgetsFile -Raw).Trim()
        # Quick sanity check: must start with '[' (JSON array)
        if (-not $rawWidgetsJson.StartsWith("[")) {
            Write-Host "  Warning: Widgets file does not contain a JSON array. Ignoring." -ForegroundColor Yellow
            $rawWidgetsJson = ""
        } else {
            # Count widgets by parsing temporarily (just for the log message)
            $tempWidgets = $rawWidgetsJson | ConvertFrom-Json
            $widgetCountLoaded = @($tempWidgets).Count
            Write-Host "  Loaded $widgetCountLoaded widget(s) from file: $WidgetsFile" -ForegroundColor Green
        }
    } catch {
        Write-Host "  Warning: Could not read widgets file '$WidgetsFile': $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  Creating dashboard without widgets" -ForegroundColor Yellow
        $rawWidgetsJson = ""
    }
} elseif ($WidgetsJson -ne "") {
    $rawWidgetsJson = $WidgetsJson.Trim()
    if (-not $rawWidgetsJson.StartsWith("[")) {
        Write-Host "  Warning: WidgetsJson does not contain a JSON array. Ignoring." -ForegroundColor Yellow
        $rawWidgetsJson = ""
    }
}

# Serialize the body (without widgets) then splice raw widgets JSON in.
# This guarantees the widgets array is sent exactly as authored, with no
# PowerShell object-model mangling.
$jsonBody = $body | ConvertTo-Json -Depth 20 -Compress
if ($rawWidgetsJson -ne "") {
    # Strip the closing '}' from $jsonBody, append ,"widgets":<raw array>}
    $jsonBody = $jsonBody.TrimEnd('}') + ',"widgets":' + $rawWidgetsJson + '}'
}

# ──────────────────────────────────────────────
# 4. Create or Update
# ──────────────────────────────────────────────
$resultDashboardId = $null

# Debug: log payload size and first 2000 chars
$payloadLen = $jsonBody.Length
Write-Host "  Payload size: $payloadLen bytes" -ForegroundColor Gray
if ($payloadLen -le 2000) {
    Write-Host "  Payload: $jsonBody" -ForegroundColor DarkGray
} else {
    Write-Host "  Payload (first 2000 chars): $($jsonBody.Substring(0, 2000))..." -ForegroundColor DarkGray
}

if ($existingDashboardId) {
    # UPDATE existing dashboard
    Write-Host "Updating dashboard $existingDashboardId..." -ForegroundColor Cyan

    $updateUrl = "$Site24x7ApiBase/api/dashboards/$existingDashboardId"
    try {
        $response = Invoke-RestMethod -Uri $updateUrl -Method PUT -Headers $headers `
            -Body $jsonBody -TimeoutSec 30
    } catch {
        $errMsg = $_.Exception.Message
        Write-Host "  HTTP Error: $errMsg" -ForegroundColor Red
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $reader.BaseStream.Position = 0
            $errBody = $reader.ReadToEnd()
            Write-Host "  Response Body: $errBody" -ForegroundColor Red
        } catch {
            Write-Host "  (Could not read error response body)" -ForegroundColor DarkYellow
        }
        Write-Error "FAILED: Dashboard update request failed"
        exit 1
    }

    if ($response.code -eq 0 -and $response.data) {
        $resultDashboardId = $response.data.dashboard_id
        Write-Host "  Dashboard updated successfully: $resultDashboardId" -ForegroundColor Green
    } else {
        Write-Error "FAILED: Update returned unexpected response: $($response | ConvertTo-Json -Compress -Depth 5)"
        exit 1
    }
} else {
    # CREATE new dashboard
    Write-Host "Creating dashboard '$DashboardName'..." -ForegroundColor Cyan

    try {
        $response = Invoke-RestMethod -Uri "$Site24x7ApiBase/api/dashboards" `
            -Method POST -Headers $headers -Body $jsonBody -TimeoutSec 30
    } catch {
        $errMsg = $_.Exception.Message
        Write-Host "  HTTP Error: $errMsg" -ForegroundColor Red
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $reader.BaseStream.Position = 0
            $errBody = $reader.ReadToEnd()
            Write-Host "  Response Body: $errBody" -ForegroundColor Red
        } catch {
            Write-Host "  (Could not read error response body)" -ForegroundColor DarkYellow
        }
        Write-Error "FAILED: Dashboard create request failed"
        exit 1
    }

    if ($response.code -eq 0 -and $response.data) {
        $resultDashboardId = $response.data.dashboard_id
        Write-Host "  Dashboard created successfully: $resultDashboardId" -ForegroundColor Green
    } else {
        Write-Error "FAILED: Create returned unexpected response: $($response | ConvertTo-Json -Compress -Depth 5)"
        exit 1
    }
}

# ──────────────────────────────────────────────
# 5. Verify dashboard
# ──────────────────────────────────────────────
Write-Host "Verifying dashboard..." -ForegroundColor Cyan

$widgetCount = 0
$dashData    = $null
$verifyUrl   = "$Site24x7ApiBase/api/dashboards/$resultDashboardId"
$verifyResponse = Invoke-RestMethod -Uri $verifyUrl -Method GET -Headers $headers -TimeoutSec 30

if ($verifyResponse.code -eq 0 -and $verifyResponse.data) {
    $dashData = $verifyResponse.data
    Write-Host "  Dashboard '$($dashData.name)' verified (ID: $resultDashboardId)" -ForegroundColor Green
    if ($dashData.widgets) {
        $widgetCount = @($dashData.widgets).Count
    }
    Write-Host "  Widgets: $widgetCount | Theme: $($dashData.theme) | Version: $($dashData.version)" -ForegroundColor Gray
    if ($dashData.permalink) {
        Write-Host "  Permalink: $($dashData.permalink)" -ForegroundColor Cyan
    }
} else {
    Write-Host "  Warning: Could not verify dashboard" -ForegroundColor Yellow
}

# ──────────────────────────────────────────────
# 6. Write output file (if requested)
# ──────────────────────────────────────────────
if ($OutputFile -ne "") {
    $outputObj = @{
        dashboard_id       = "$resultDashboardId"
        name               = $DashboardName
        theme              = $Theme
        size               = $Size
        version            = $Version
        widget_count       = $widgetCount
        zoho_accounts_base = $ZohoAccountsBase
        site24x7_api_base  = $Site24x7ApiBase
    }

    # Include permalink if available from verify response
    if ($dashData -and $dashData.permalink) {
        $outputObj["permalink"] = $dashData.permalink
    }

    $output = $outputObj | ConvertTo-Json -Depth 5
    $output | Set-Content -Path $OutputFile -Force
    Write-Host "Output written to $OutputFile" -ForegroundColor Green
}

Write-Host "SUCCESS: Dashboard '$DashboardName' (ID: $resultDashboardId) is ready." -ForegroundColor Green
