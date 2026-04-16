param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile,

    [Parameter(Mandatory=$false)]
    [string]$AppNamePrefix = "ZylkerKart",

    [Parameter(Mandatory=$false)]
    [string]$ClusterName = "",

    [Parameter(Mandatory=$false)]
    [string]$ZohoAccountsBase = "https://accounts.zoho.com",

    [Parameter(Mandatory=$false)]
    [string]$Site24x7ApiBase = "https://www.site24x7.com"
)

# 1. Check if stored file exists
if (-not (Test-Path $InputFile)) {
    Write-Host "No APM monitor file found at: $InputFile" -ForegroundColor Yellow
    Write-Host "Nothing to delete. Exiting." -ForegroundColor Yellow
    exit 0
}

# 2. Read stored data
$storedData = Get-Content -Path $InputFile -Raw | ConvertFrom-Json

# Override base URLs from state file if present (written by fetch_and_store_apm.ps1)
if ($storedData.zoho_accounts_base) { $ZohoAccountsBase = $storedData.zoho_accounts_base }
if ($storedData.site24x7_api_base)  { $Site24x7ApiBase  = $storedData.site24x7_api_base }

$k8sClusters = @()
if ($storedData.kubernetes_clusters) {
    $k8sClusters = @($storedData.kubernetes_clusters)
}

if ($storedData.applications.Count -eq 0 -and $k8sClusters.Count -eq 0) {
    Write-Host "No APM applications or K8s clusters stored. Nothing to delete." -ForegroundColor Yellow
    exit 0
}

Write-Host "=======================================" -ForegroundColor White
Write-Host " APM & Kubernetes Monitor Cleanup" -ForegroundColor White
Write-Host "=======================================" -ForegroundColor White
Write-Host "  Filter:      $($storedData.filter)*" -ForegroundColor Cyan
Write-Host "  Captured at: $($storedData.captured_at)" -ForegroundColor Cyan
Write-Host "  Apps:        $($storedData.applications.Count)" -ForegroundColor Cyan
Write-Host "  Instances:   $($storedData.instances.Count)" -ForegroundColor Cyan
Write-Host "  K8s Clusters: $($k8sClusters.Count)" -ForegroundColor Cyan
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

if ($appsToDelete.Count -eq 0 -and $k8sClusters.Count -eq 0) {
    Write-Host "No apps match prefix and no K8s clusters. Nothing to delete." -ForegroundColor Yellow
    exit 0
}

if ($appsToDelete.Count -gt 0) {
    Write-Host "Deleting $($appsToDelete.Count) apps matching: $AppNamePrefix*" -ForegroundColor Cyan
    foreach ($app in $appsToDelete) {
        Write-Host "  > $($app.application_name) (ID: $($app.application_id))" -ForegroundColor White
    }
    Write-Host ""
} else {
    Write-Host "No APM apps match prefix. Skipping APM deletion." -ForegroundColor DarkGray
    Write-Host ""
}

# 4. Refresh OAuth Token
$tokenBody = @{
    grant_type    = "refresh_token"
    client_id     = $env:SITE24X7_CLIENT_ID
    client_secret = $env:SITE24X7_CLIENT_SECRET
    refresh_token = $env:SITE24X7_REFRESH_TOKEN
}
$tokenResponse = Invoke-RestMethod -Uri "$ZohoAccountsBase/oauth/v2/token" -Method POST -Body $tokenBody -TimeoutSec 30
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
            -Uri "$Site24x7ApiBase/api/monitors/$appId" `
            -Method DELETE `
            -Headers $headers `
            -TimeoutSec 30

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

# 6. Delete Kubernetes Cluster Monitors
$k8sSuccessCount = 0
$k8sFailCount    = 0

if ($k8sClusters.Count -gt 0) {
    Write-Host ""
    Write-Host "---------------------------------------" -ForegroundColor White
    Write-Host " Kubernetes Cluster Monitor Cleanup" -ForegroundColor White
    Write-Host "---------------------------------------" -ForegroundColor White
    Write-Host "Deleting $($k8sClusters.Count) K8s cluster monitors..." -ForegroundColor Cyan

    foreach ($cluster in $k8sClusters) {
        $clusterId   = $cluster.cluster_id
        $displayName = $cluster.display_name

        Write-Host "[$displayName] (ID: $clusterId)" -ForegroundColor Yellow

        try {
            $deleteResponse = Invoke-RestMethod `
                -Uri "$Site24x7ApiBase/app/api/monitors/${clusterId}?deleteIntegrartedMonitors=false" `
                -Method DELETE `
                -Headers $headers `
                -TimeoutSec 30

            if ($deleteResponse.code -eq 0) {
                Write-Host "  OK - Deleted successfully" -ForegroundColor Green
                $k8sSuccessCount++
            } else {
                Write-Host "  FAIL - $($deleteResponse.message)" -ForegroundColor Red
                $k8sFailCount++
            }
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($statusCode -eq 404) {
                Write-Host "  SKIP - Already deleted (404)" -ForegroundColor DarkYellow
                $k8sSuccessCount++
            } else {
                Write-Host "  ERROR - $_" -ForegroundColor Red
                $k8sFailCount++
            }
        }

        Start-Sleep -Milliseconds 500
    }
} else {
    Write-Host ""
    Write-Host "No K8s cluster monitors to delete." -ForegroundColor DarkGray
}

$totalSuccess = $successCount + $k8sSuccessCount
$totalFail    = $failCount + $k8sFailCount

# 7. Summary
Write-Host ""
Write-Host "=======================================" -ForegroundColor White
Write-Host " Cleanup Summary" -ForegroundColor White
Write-Host "=======================================" -ForegroundColor White
Write-Host "  APM Filter:    $AppNamePrefix*" -ForegroundColor Cyan
Write-Host "  APM Succeeded: $successCount" -ForegroundColor Green
if ($failCount -gt 0) {
    Write-Host "  APM Failed:    $failCount" -ForegroundColor Red
} else {
    Write-Host "  APM Failed:    0" -ForegroundColor Green
}
Write-Host "  K8s Succeeded: $k8sSuccessCount" -ForegroundColor Green
if ($k8sFailCount -gt 0) {
    Write-Host "  K8s Failed:    $k8sFailCount" -ForegroundColor Red
} else {
    Write-Host "  K8s Failed:    0" -ForegroundColor Green
}
Write-Host "  ---------------------" -ForegroundColor White
Write-Host "  Total OK:      $totalSuccess" -ForegroundColor Green
if ($totalFail -gt 0) {
    Write-Host "  Total Failed:  $totalFail" -ForegroundColor Red
} else {
    Write-Host "  Total Failed:  0" -ForegroundColor Green
}
Write-Host ""

# 8. Remove stored file on full success
if ($totalFail -eq 0) {
    Remove-Item -Path $InputFile -Force
    Write-Host "Removed state file: $InputFile" -ForegroundColor Gray
} else {
    Write-Host "Kept state file (some deletes failed): $InputFile" -ForegroundColor Yellow
}