param(
    [Parameter(Mandatory=$true)]
    [string]$FrontendIP,

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
$baseUrl = "http://${FrontendIP}"

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

# ----------------------------------------------
# 4. Base64-encode token and patch K8s secret
# ----------------------------------------------
Write-Host "Patching K8s secret 'site24x7-labs-secrets' in namespace '$Namespace' ..." -ForegroundColor Cyan
$tokenBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($agentToken))

# Build the JSON patch payload and write to a temp file to avoid shell quoting issues
$patchJson = @{
    data = @{
        AGENT_TOKEN = $tokenBase64
    }
} | ConvertTo-Json -Compress

$patchFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $patchFile -Value $patchJson -Encoding UTF8

kubectl patch secret site24x7-labs-secrets `
    -n $Namespace `
    --type merge `
    --patch-file $patchFile

$patchExitCode = $LASTEXITCODE
Remove-Item -Path $patchFile -Force -ErrorAction SilentlyContinue

if ($patchExitCode -ne 0) {
    Write-Error "Failed to patch K8s secret (exit code $patchExitCode)"
    exit 1
}
Write-Host "  Secret patched successfully." -ForegroundColor Green

# ----------------------------------------------
# 5. Restart the agent DaemonSet
# ----------------------------------------------
Write-Host "Restarting DaemonSet 'site24x7-labs-agent' ..." -ForegroundColor Cyan
kubectl rollout restart daemonset/site24x7-labs-agent -n $Namespace

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to restart DaemonSet (exit code $LASTEXITCODE)"
    exit 1
}

Write-Host "Waiting for DaemonSet rollout to complete ..." -ForegroundColor Cyan
kubectl rollout status daemonset/site24x7-labs-agent -n $Namespace --timeout=120s

if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: DaemonSet rollout did not complete within 120s, but agent will eventually pick up the new token." -ForegroundColor Yellow
} else {
    Write-Host "  DaemonSet rollout complete." -ForegroundColor Green
}

Write-Host ""
Write-Host "Site24x7 Labs post-deployment setup complete!" -ForegroundColor Green
Write-Host "  Frontend URL : $baseUrl" -ForegroundColor White
Write-Host "  Environment  : $EnvironmentName" -ForegroundColor White
Write-Host "  Agent Token  : $($agentToken.Substring(0,20))..." -ForegroundColor White