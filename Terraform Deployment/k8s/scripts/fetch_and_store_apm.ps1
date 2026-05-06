param(
    [Parameter(Mandatory=$true)]
    [string]$OutputFile,

    [Parameter(Mandatory=$false)]
    [string]$AppNamePrefix = "ZylkerKart",

    [Parameter(Mandatory=$false)]
    [int]$RetryCount = 10,

    [Parameter(Mandatory=$false)]
    [int]$RetryDelaySec = 60,

    [Parameter(Mandatory=$false)]
    [int]$ExpectedAppCount = 6,

    [Parameter(Mandatory=$false)]
    [string]$ClusterName = "",

    [Parameter(Mandatory=$false)]
    [string]$ZohoAccountsBase = "https://accounts.zoho.com",

    [Parameter(Mandatory=$false)]
    [string]$Site24x7ApiBase = "https://www.site24x7.com"
)

# 1. Refresh OAuth Token
$tokenBody = @{
    grant_type    = "refresh_token"
    client_id     = $env:SITE24X7_CLIENT_ID
    client_secret = $env:SITE24X7_CLIENT_SECRET
    refresh_token = $env:SITE24X7_REFRESH_TOKEN
}
$tokenResponse = Invoke-RestMethod -Uri "$ZohoAccountsBase/oauth/v2/token" -Method POST -Body $tokenBody
$accessToken   = $tokenResponse.access_token

$headers = @{
    "Accept"        = "application/json; version=2.0"
    "Authorization" = "Zoho-oauthtoken $accessToken"
}

# 2. Retry loop
$apmData = $null
for ($i = 1; $i -le $RetryCount; $i++) {
    Write-Host "Attempt $i of $RetryCount - Fetching APM applications..." -ForegroundColor Cyan

    $response = Invoke-RestMethod -Uri "$Site24x7ApiBase/api/apminsight/app/H" -Method GET -Headers $headers

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
        filter              = $AppNamePrefix
        applications        = @()
        instances           = @()
        kubernetes_clusters = @()
        cluster_name_filter = $ClusterName
        zoho_accounts_base  = $ZohoAccountsBase
        site24x7_api_base   = $Site24x7ApiBase
        captured_at         = (Get-Date -Format o)
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

# 5. Fetch Kubernetes Cluster Monitors
$kubernetesClusters = @()

if ($ClusterName -ne "") {
    Write-Host ""
    Write-Host "=======================================" -ForegroundColor White
    Write-Host " Kubernetes Cluster Monitors" -ForegroundColor White
    Write-Host "=======================================" -ForegroundColor White
    Write-Host "  Filter: *$ClusterName*" -ForegroundColor Cyan

    try {
        $k8sResponse = Invoke-RestMethod `
            -Uri "$Site24x7ApiBase/app/api/server/dashboard/kubernetes?show_child=false" `
            -Method GET `
            -Headers $headers

        $k8sData = @()
        if ($k8sResponse.code -eq 0 -and $k8sResponse.data) {
            $k8sData = @($k8sResponse.data)
        }

        Write-Host "  Found $($k8sData.Count) total K8s cluster monitors" -ForegroundColor Cyan

        # Debug: log the field names from the first entry to help identify correct fields
        if ($k8sData.Count -gt 0) {
            $firstEntry = $k8sData[0]
            $fieldNames = $firstEntry.PSObject.Properties.Name -join ", "
            Write-Host "  API response fields: $fieldNames" -ForegroundColor DarkGray
        }

        foreach ($cluster in $k8sData) {
            # Discover cluster ID — try common field names
            $clusterId = ""
            foreach ($idField in @("cluster_id", "monitor_id", "resource_id", "id")) {
                $val = $cluster.PSObject.Properties[$idField]
                if ($val -and $val.Value) {
                    $clusterId = [string]$val.Value
                    break
                }
            }

            # Discover display name — try common field names
            $displayName = ""
            foreach ($nameField in @("display_name", "name", "cluster_name", "monitor_name")) {
                $val = $cluster.PSObject.Properties[$nameField]
                if ($val -and $val.Value) {
                    $displayName = [string]$val.Value
                    break
                }
            }

            # Filter by cluster name (case-insensitive contains)
            if ($displayName -and $displayName.ToLower().Contains($ClusterName.ToLower())) {
                Write-Host "    + $displayName (ID: $clusterId)" -ForegroundColor Green
                $kubernetesClusters += @{
                    cluster_id   = $clusterId
                    display_name = $displayName
                }
            } else {
                Write-Host "    - $displayName (ID: $clusterId) (skipped)" -ForegroundColor DarkGray
            }
        }

        Write-Host "  Matched: $($kubernetesClusters.Count) K8s clusters" -ForegroundColor Green
    }
    catch {
        Write-Host "  WARNING: Failed to fetch K8s monitors: $_" -ForegroundColor Yellow
        Write-Host "  Continuing with APM monitors only." -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "No ClusterName specified - skipping K8s monitor fetch." -ForegroundColor DarkGray
}

# 6. Store to file
$output = @{
    filter              = $AppNamePrefix
    applications        = $applications
    instances           = $instances
    kubernetes_clusters = $kubernetesClusters
    cluster_name_filter = $ClusterName
    zoho_accounts_base  = $ZohoAccountsBase
    site24x7_api_base   = $Site24x7ApiBase
    captured_at         = (Get-Date -Format o)
}

$output | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputFile -Encoding utf8

Write-Host ""
Write-Host "Stored $($applications.Count) apps, $($instances.Count) instances, and $($kubernetesClusters.Count) K8s clusters to: $OutputFile" -ForegroundColor Green