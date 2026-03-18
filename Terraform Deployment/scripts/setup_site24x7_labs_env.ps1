param(
    [Parameter(Mandatory=$true)]
    [string]${site24x7_server},

    [Parameter(Mandatory=$true)]
    [string]$EnvironmentName,

    [Parameter(Mandatory=$true)]
    [string]$Namespace,

    [Parameter(Mandatory=$false)]
    [string]$AdminEmail = "admin@site24x7labs.local",

    [Parameter(Mandatory=$false)]
    [string]$AdminPassword = "admin123",

    [Parameter(Mandatory=$false)]
    [int]$MaxRetries = 20,

    [Parameter(Mandatory=$false)]
    [int]$RetryDelaySec = 15
)

$ErrorActionPreference = "Stop"
$baseUrl = "http://${site24x7_server}"

# ----------------------------------------------
# 1. Wait for the API to be reachable
# ----------------------------------------------
Write-Host "Waiting for Site24x7 Labs API at $baseUrl ..." -ForegroundColor Cyan
Write-Host "  (This can take a few minutes while pods start and the LoadBalancer routes traffic)" -ForegroundColor Yellow

$loginBody = @{ email = $AdminEmail; password = $AdminPassword } | ConvertTo-Json

for ($i = 1; $i -le $MaxRetries; $i++) {
    try {
        $health = Invoke-RestMethod -Uri "$baseUrl/api/v1/auth/login" -Method POST `
            -ContentType "application/json" `
            -Body $loginBody `
            -TimeoutSec 10
        # If we get here without error the server is up
        Write-Host "  API is reachable! (attempt $i/$MaxRetries)" -ForegroundColor Green
        break
    } catch {
        if ($i -eq $MaxRetries) {
            Write-Host "" -ForegroundColor Red
            Write-Host "  Diagnostics -- checking pod status in namespace '$Namespace':" -ForegroundColor Yellow
            try { kubectl get pods -n $Namespace -o wide 2>&1 | Write-Host } catch {}
            Write-Host "" -ForegroundColor Red
            Write-Error "TIMEOUT: Site24x7 Labs API not reachable after $MaxRetries attempts (~$($MaxRetries * $RetryDelaySec)s). Check that the frontend pods are running and the LoadBalancer is healthy."
            exit 1
        }
        Write-Host "  Attempt $i/$MaxRetries failed, retrying in ${RetryDelaySec}s ..." -ForegroundColor Yellow
        Start-Sleep -Seconds $RetryDelaySec
    }
}

# ----------------------------------------------
# 2. Login and extract JWT token
# ----------------------------------------------
Write-Host "Logging in as $AdminEmail ..." -ForegroundColor Cyan
$loginResponse = Invoke-RestMethod -Uri "$baseUrl/api/v1/auth/login" `
    -Method POST `
    -ContentType "application/json" `
    -Body $loginBody

# The API returns: { "success": true, "data": { "access_token": "...", ... } }
$jwt = $loginResponse.data.access_token
if (-not $jwt) {
    $jwt = $loginResponse.token
}
if (-not $jwt) {
    $jwt = $loginResponse.access_token
}
if (-not $jwt) {
    Write-Error "Login succeeded but no token in response: $($loginResponse | ConvertTo-Json -Compress)"
    exit 1
}
Write-Host "  Login successful, JWT obtained." -ForegroundColor Green

# ----------------------------------------------
# 3. Create environment and get agent token
# ----------------------------------------------
Write-Host "Creating environment '$EnvironmentName' ..." -ForegroundColor Cyan
$envBody = @{ name = $EnvironmentName; type = "kubernetes" } | ConvertTo-Json
$headers = @{
    "Authorization" = "Bearer $jwt"
    "Content-Type"  = "application/json"
}

$envResponse = $null
try {
    $envResponse = Invoke-RestMethod -Uri "$baseUrl/api/v1/environments/" `
        -Method POST `
        -Headers $headers `
        -Body $envBody
    Write-Host "  Environment created." -ForegroundColor Green
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    Write-Host "  Create returned HTTP $statusCode -- environment may already exist, attempting to fetch it..." -ForegroundColor Yellow

    # List all environments and find the one matching our name
    $allEnvs = Invoke-RestMethod -Uri "$baseUrl/api/v1/environments/" `
        -Method GET `
        -Headers $headers

    # Handle both { data: [...] } and direct array responses
    $envList = $allEnvs
    if ($allEnvs.data) {
        $envList = $allEnvs.data
    }

    $envResponse = $envList | Where-Object { $_.name -eq $EnvironmentName } | Select-Object -First 1

    if (-not $envResponse) {
        Write-Error "Environment '$EnvironmentName' not found in existing environments and creation failed (HTTP $statusCode). Response: $($_.Exception.Message)"
        exit 1
    }
    Write-Host "  Found existing environment '$EnvironmentName'." -ForegroundColor Green
}

$agentToken = $envResponse.agent_token
if (-not $agentToken) {
    # Some API designs nest it differently -- try common alternatives
    $agentToken = $envResponse.data.agent_token
}
if (-not $agentToken) {
    Write-Error "Environment created/found but no agent_token in response: $($envResponse | ConvertTo-Json -Compress -Depth 5)"
    exit 1
}
Write-Host "  Agent token: $($agentToken.Substring(0,20))..." -ForegroundColor Green