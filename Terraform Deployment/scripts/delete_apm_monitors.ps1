param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile,

    [Parameter(Mandatory=$false)]
    [string]$AppNamePrefix = "ZylkerKart"
)

# 1. Check if stored file exists
if (-not (Test-Path $InputFile)) {
    Write-Host "No APM monitor file found at: $InputFile" -ForegroundColor Yellow
    Write-Host "Nothing to delete. Exiting." -ForegroundColor Yellow
    exit 0
}

# 2. Read stored data
$storedData = Get-Content -Path $InputFile -Raw | ConvertFrom-Json

if ($storedData.applications.Count -eq 0) {
    Write-Host "No APM applications stored. Nothing to delete." -ForegroundColor Yellow
    exit 0
}

Write-Host "=======================================" -ForegroundColor White
Write-Host " APM Monitor Cleanup" -ForegroundColor White
Write-Host "=======================================" -ForegroundColor White
Write-Host "  Filter:      $($storedData.filter)*" -ForegroundColor Cyan
Write-Host "  Captured at: $($storedData.captured_at)" -ForegroundColor Cyan
Write-Host "  Apps:        $($storedData.applications.Count)" -ForegroundColor Cyan
Write-Host "  Instances:   $($storedData.instances.Count)" -ForegroundColor Cyan
Write-Host ""

# 3. Double-check: only delete apps matching the prefix
$appsToDelete = @($storedData.applications | Where-Object {
    $_.application_name -like "$AppNamePrefix*"
})

$appsSkipped = @($storedData.applications | Where-Object {
    $_.application_name -notlike "$AppNamePrefix*"
})

if ($appsSkipped.Count -gt 0) {
    Write-Host "WARNING: $($appsSkipped.Count) apps in file dont match prefix - skipping:" -ForegroundColor Yellow
    foreach ($app in $appsSkipped) {
        Write-Host "  - $($app.application_name)" -ForegroundColor Yellow
    }
    Write-Host ""
}

if ($appsToDelete.Count -eq 0) {
    Write-Host "No apps match prefix. Nothing to delete." -ForegroundColor Yellow
    exit 0
}

Write-Host "Deleting $($appsToDelete.Count) apps matching: $AppNamePrefix*" -ForegroundColor Cyan
foreach ($app in $appsToDelete) {
    Write-Host "  > $($app.application_name) (ID: $($app.application_id))" -ForegroundColor White
}
Write-Host ""

# 4. Refresh OAuth Token
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

# 5. Delete each matched application monitor
$successCount = 0
$failCount    = 0

foreach ($app in $appsToDelete) {
    $appId   = $app.application_id
    $appName = $app.application_name

    Write-Host "[$appName] (ID: $appId)" -ForegroundColor Yellow

    try {
        $deleteResponse = Invoke-RestMethod `
            -Uri "https://www.site24x7.com/api/monitors/$appId" `
            -Method DELETE `
            -Headers $headers

        if ($deleteResponse.code -eq 0) {
            Write-Host "  OK - Deleted successfully" -ForegroundColor Green
            $successCount++
        } else {
            Write-Host "  FAIL - $($deleteResponse.message)" -ForegroundColor Red
            $failCount++
        }
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 404) {
            Write-Host "  SKIP - Already deleted (404)" -ForegroundColor DarkYellow
            $successCount++
        } else {
            Write-Host "  ERROR - $_" -ForegroundColor Red
            $failCount++
        }
    }

    Start-Sleep -Milliseconds 500
}

# 6. Summary
Write-Host ""
Write-Host "=======================================" -ForegroundColor White
Write-Host " Cleanup Summary" -ForegroundColor White
Write-Host "=======================================" -ForegroundColor White
Write-Host "  Filter:    $AppNamePrefix*" -ForegroundColor Cyan
Write-Host "  Succeeded: $successCount" -ForegroundColor Green
if ($failCount -gt 0) {
    Write-Host "  Failed:    $failCount" -ForegroundColor Red
} else {
    Write-Host "  Failed:    0" -ForegroundColor Green
}
Write-Host ""

# 7. Remove stored file on full success
if ($failCount -eq 0) {
    Remove-Item -Path $InputFile -Force
    Write-Host "Removed state file: $InputFile" -ForegroundColor Gray
} else {
    Write-Host "Kept state file (some deletes failed): $InputFile" -ForegroundColor Yellow
}