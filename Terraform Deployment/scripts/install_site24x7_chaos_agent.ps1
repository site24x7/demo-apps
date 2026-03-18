# =============================================================================
# Site24x7 Labs — Universal Agent Installer (PowerShell)
# =============================================================================
# Usage:
#   irm http://<server>/api/v1/install.ps1 | iex
#   .\Install-Site24x7Agent.ps1 `
#     -Platform <kubernetes|docker|compose|windows> `
#     -Token "s24x7_at_..." `
#     -EnvironmentId "uuid" `
#     -Server "<ip-or-hostname>"
# =============================================================================

[CmdletBinding()]
param(
    [ValidateSet("kubernetes", "docker", "compose", "windows")]
    [string]$Platform,

    [string]$Token,

    [string]$EnvironmentId,

    [Alias("s")]
    [string]$Server,

    [string]$Namespace = "site24x7-labs",

    [string]$Image = "impazhani/site24x7-labs-agent:latest-vm",

    [string]$Name,

    [switch]$Uninstall,

    [switch]$Help
)

$ErrorActionPreference = "Stop"

# --- Colors / Logging ---
function Log-Info  { param([string]$Message) Write-Host "[INFO]  $Message" -ForegroundColor Green }
function Log-Warn  { param([string]$Message) Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Log-Error { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }
function Log-Step  { param([string]$Message) Write-Host "[STEP]  $Message" -ForegroundColor Blue }

# --- Usage ---
function Show-Usage {
    @"
Site24x7 Labs Agent Installer (PowerShell)

Usage:
  .\Install-Site24x7Agent.ps1 [OPTIONS]

Options:
  -Platform <kubernetes|docker|compose|windows>  Target platform (required)
  -Token <token>                                  Agent token (required)
  -EnvironmentId <uuid>                           Environment ID (required)
  -Server <ip-or-hostname>                        Server address (required)
  -Namespace <ns>                                 Kubernetes namespace (default: site24x7-labs)
  -Image <image>                                  Agent Docker image (default: impazhani/site24x7-labs-agent:latest-vm)
  -Name <name>                                    Agent name (default: hostname)
  -Uninstall                                      Remove agent instead of installing
  -Help                                           Show this help
"@
}

if ($Help) {
    Show-Usage
    return
}

# --- Validation ---
function Confirm-Parameters {
    if ([string]::IsNullOrWhiteSpace($Server)) {
        Log-Error "-Server is required (IP or hostname of the Site24x7 Labs server)"
        exit 1
    }

    $script:ServerAddress = "${Server}:9090"
    $script:HttpAddress   = "http://${Server}"

    if ([string]::IsNullOrWhiteSpace($Platform)) {
        Log-Error "-Platform is required (kubernetes|docker|compose|windows)"
        exit 1
    }
    if ([string]::IsNullOrWhiteSpace($Token)) {
        Log-Error "-Token is required"
        exit 1
    }
    if ([string]::IsNullOrWhiteSpace($EnvironmentId)) {
        Log-Error "-EnvironmentId is required"
        exit 1
    }
    if ($Platform -notin @("kubernetes", "docker", "compose", "windows")) {
        Log-Error "Invalid platform: $Platform (must be kubernetes|docker|compose|windows)"
        exit 1
    }
}

# =============================================================================
# KUBERNETES
# =============================================================================
function Install-Kubernetes {
    Log-Step "Installing Site24x7 Labs agent on Kubernetes..."

    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Log-Error "kubectl is not installed or not in PATH"
        exit 1
    }

    Log-Info "Namespace: $Namespace"
    Log-Info "Server:    $script:ServerAddress"
    Log-Info "Image:     $Image"

    $manifest = @"
---
apiVersion: v1
kind: Namespace
metadata:
  name: $Namespace
  labels:
    app.kubernetes.io/part-of: site24x7-labs
---
apiVersion: v1
kind: Secret
metadata:
  name: site24x7-labs-agent-secret
  namespace: $Namespace
type: Opaque
stringData:
  AGENT_TOKEN: "$Token"
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: site24x7-labs-agent
  namespace: $Namespace
  labels:
    app.kubernetes.io/component: agent
    app.kubernetes.io/part-of: site24x7-labs
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: site24x7-labs-agent
  labels:
    app.kubernetes.io/component: agent
    app.kubernetes.io/part-of: site24x7-labs
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch", "delete", "deletecollection"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get"]
  - apiGroups: [""]
    resources: ["services", "endpoints", "nodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets", "daemonsets", "replicasets"]
    verbs: ["get", "list", "watch", "update", "patch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["networkpolicies"]
    verbs: ["get", "list", "create", "update", "delete"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get", "list", "watch", "create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: site24x7-labs-agent
  labels:
    app.kubernetes.io/component: agent
    app.kubernetes.io/part-of: site24x7-labs
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: site24x7-labs-agent
subjects:
  - kind: ServiceAccount
    name: site24x7-labs-agent
    namespace: $Namespace
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: site24x7-labs-agent
  namespace: $Namespace
  labels:
    app.kubernetes.io/component: agent
    app.kubernetes.io/part-of: site24x7-labs
spec:
  selector:
    matchLabels:
      app.kubernetes.io/component: agent
      app.kubernetes.io/part-of: site24x7-labs
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  template:
    metadata:
      labels:
        app.kubernetes.io/component: agent
        app.kubernetes.io/part-of: site24x7-labs
    spec:
      serviceAccountName: site24x7-labs-agent
      hostPID: true
      initContainers:
        - name: fix-permissions
          image: busybox:1.36
          command: ["sh", "-c", "mkdir -p /var/site24x7-labs/faults && chmod 777 /var/site24x7-labs/faults"]
          volumeMounts:
            - name: chaos-config
              mountPath: /var/site24x7-labs/faults
          securityContext:
            runAsUser: 0
      containers:
        - name: agent
          image: $Image
          imagePullPolicy: Always
          env:
            - name: SERVER_ADDRESS
              value: "$($script:ServerAddress)"
            - name: AGENT_TOKEN
              valueFrom:
                secretKeyRef:
                  name: site24x7-labs-agent-secret
                  key: AGENT_TOKEN
            - name: AGENT_ENVIRONMENT
              value: "$EnvironmentId"
            - name: AGENT_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: ENABLE_KUBERNETES
              value: "true"
            - name: ENABLE_DOCKER
              value: "false"
            - name: ENABLE_HOST
              value: "true"
            - name: CHAOS_CONFIG_DIR
              value: "/var/site24x7-labs/faults"
            - name: LOG_LEVEL
              value: "info"
            - name: LOG_FORMAT
              value: "json"
          securityContext:
            privileged: true
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 256Mi
          volumeMounts:
            - name: proc
              mountPath: /host/proc
              readOnly: true
            - name: sys
              mountPath: /host/sys
              readOnly: true
            - name: cgroup
              mountPath: /host/cgroup
              readOnly: true
            - name: chaos-config
              mountPath: /var/site24x7-labs/faults
          livenessProbe:
            exec:
              command: ["/bin/sh", "-c", "pgrep -f site24x7-labs-agent"]
            initialDelaySeconds: 10
            periodSeconds: 30
            timeoutSeconds: 5
          readinessProbe:
            exec:
              command: ["/bin/sh", "-c", "pgrep -f site24x7-labs-agent"]
            initialDelaySeconds: 5
            periodSeconds: 10
            timeoutSeconds: 3
      volumes:
        - name: proc
          hostPath:
            path: /proc
        - name: sys
          hostPath:
            path: /sys
        - name: cgroup
          hostPath:
            path: /sys/fs/cgroup
        - name: chaos-config
          hostPath:
            path: /var/site24x7-labs/faults
            type: DirectoryOrCreate
      tolerations:
        - operator: Exists
"@

    $manifest | kubectl apply -f -
    if ($LASTEXITCODE -ne 0) {
        Log-Error "kubectl apply failed"
        exit 1
    }

    Log-Info "Kubernetes agent installed successfully!"
    Log-Info "Check status: kubectl -n $Namespace get pods -l app.kubernetes.io/component=agent"
}

function Uninstall-Kubernetes {
    Log-Step "Uninstalling Site24x7 Labs agent from Kubernetes..."

    kubectl delete daemonset site24x7-labs-agent -n $Namespace --ignore-not-found 2>$null
    kubectl delete clusterrolebinding site24x7-labs-agent --ignore-not-found 2>$null
    kubectl delete clusterrole site24x7-labs-agent --ignore-not-found 2>$null
    kubectl delete serviceaccount site24x7-labs-agent -n $Namespace --ignore-not-found 2>$null
    kubectl delete secret site24x7-labs-agent-secret -n $Namespace --ignore-not-found 2>$null
    kubectl delete namespace $Namespace --ignore-not-found 2>$null

    Log-Info "Kubernetes agent uninstalled successfully!"
}

# =============================================================================
# DOCKER
# =============================================================================
function Install-Docker {
    Log-Step "Installing Site24x7 Labs agent via Docker..."

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Log-Error "docker is not installed or not in PATH"
        exit 1
    }

    $containerName = if ([string]::IsNullOrWhiteSpace($Name)) { "site24x7-labs-agent" } else { $Name }

    # Stop existing container if running
    docker rm -f $containerName 2>$null | Out-Null

    docker run -d `
        --name $containerName `
        --restart unless-stopped `
        --privileged `
        --pid=host `
        -v /proc:/host/proc:ro `
        -v /sys:/host/sys:ro `
        -v /sys/fs/cgroup:/host/cgroup:ro `
        -v /var/run/docker.sock:/var/run/docker.sock:ro `
        -v /var/site24x7-labs/faults:/var/site24x7-labs/faults `
        -e "SERVER_ADDRESS=$($script:ServerAddress)" `
        -e "AGENT_TOKEN=$Token" `
        -e "AGENT_ENVIRONMENT=$EnvironmentId" `
        -e "AGENT_NAME=$containerName" `
        -e "ENABLE_KUBERNETES=false" `
        -e "ENABLE_DOCKER=true" `
        -e "ENABLE_HOST=true" `
        -e "CHAOS_CONFIG_DIR=/var/site24x7-labs/faults" `
        -e "LOG_LEVEL=info" `
        -e "LOG_FORMAT=json" `
        $Image

    if ($LASTEXITCODE -ne 0) {
        Log-Error "docker run failed"
        exit 1
    }

    Log-Info "Docker agent started successfully!"
    Log-Info "Check status: docker logs $containerName"
}

function Uninstall-Docker {
    Log-Step "Uninstalling Site24x7 Labs agent from Docker..."

    $containerName = if ([string]::IsNullOrWhiteSpace($Name)) { "site24x7-labs-agent" } else { $Name }
    docker rm -f $containerName 2>$null | Out-Null

    Log-Info "Docker agent removed successfully!"
}

# =============================================================================
# DOCKER COMPOSE
# =============================================================================
function Install-Compose {
    Log-Step "Installing Site24x7 Labs agent via Docker Compose..."

    $composeFile = $null
    if (Test-Path "docker-compose.yml") {
        $composeFile = "docker-compose.yml"
    }
    elseif (Test-Path "docker-compose.yaml") {
        $composeFile = "docker-compose.yaml"
    }
    else {
        Log-Error "No docker-compose.yml or docker-compose.yaml found in current directory"
        exit 1
    }

    $markerStart = "# --- site24x7-labs-agent-start ---"
    $markerEnd   = "# --- site24x7-labs-agent-end ---"

    $content = Get-Content -Path $composeFile -Raw

    # Remove existing agent block if present
    if ($content -match [regex]::Escape($markerStart)) {
        Log-Warn "Existing agent configuration found — replacing..."
        $pattern = "(?s)" + [regex]::Escape($markerStart) + ".*?" + [regex]::Escape($markerEnd) + "\r?\n?"
        $content = [regex]::Replace($content, $pattern, "")
        Set-Content -Path $composeFile -Value $content -NoNewline
    }

    $agentBlock = @"

  $markerStart
  site24x7-labs-agent:
    image: $Image
    container_name: site24x7-labs-agent
    restart: unless-stopped
    privileged: true
    pid: host
    environment:
      - SERVER_ADDRESS=$($script:ServerAddress)
      - AGENT_TOKEN=$Token
      - AGENT_ENVIRONMENT=$EnvironmentId
      - AGENT_NAME=site24x7-labs-agent
      - ENABLE_KUBERNETES=false
      - ENABLE_DOCKER=true
      - ENABLE_HOST=true
      - CHAOS_CONFIG_DIR=/var/site24x7-labs/faults
      - LOG_LEVEL=info
      - LOG_FORMAT=json
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /sys/fs/cgroup:/host/cgroup:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /var/site24x7-labs/faults:/var/site24x7-labs/faults
  $markerEnd
"@

    Add-Content -Path $composeFile -Value $agentBlock

    Log-Info "Agent service appended to $composeFile"
    Log-Info "Starting agent..."

    docker compose up -d site24x7-labs-agent
    if ($LASTEXITCODE -ne 0) {
        Log-Error "docker compose up failed"
        exit 1
    }

    Log-Info "Docker Compose agent started successfully!"
    Log-Info "Check status: docker compose logs site24x7-labs-agent"
}

function Uninstall-Compose {
    Log-Step "Uninstalling Site24x7 Labs agent from Docker Compose..."

    docker compose stop site24x7-labs-agent 2>$null | Out-Null
    docker compose rm -f site24x7-labs-agent 2>$null | Out-Null

    $composeFile = $null
    if (Test-Path "docker-compose.yml") {
        $composeFile = "docker-compose.yml"
    }
    elseif (Test-Path "docker-compose.yaml") {
        $composeFile = "docker-compose.yaml"
    }

    if ($composeFile -and (Test-Path $composeFile)) {
        $content    = Get-Content -Path $composeFile -Raw
        $markerStart = "# --- site24x7-labs-agent-start ---"
        $markerEnd   = "# --- site24x7-labs-agent-end ---"

        if ($content -match [regex]::Escape($markerStart)) {
            $pattern = "(?s)" + [regex]::Escape($markerStart) + ".*?" + [regex]::Escape($markerEnd) + "\r?\n?"
            $content = [regex]::Replace($content, $pattern, "")
            Set-Content -Path $composeFile -Value $content -NoNewline
            Log-Info "Agent block removed from $composeFile"
        }
    }

    Log-Info "Docker Compose agent uninstalled successfully!"
}

# =============================================================================
# WINDOWS (bare metal / VM) — replaces 'linux' platform
# =============================================================================
function Install-Windows {
    Log-Step "Installing Site24x7 Labs agent on Windows..."

    if ($env:OS -ne "Windows_NT") {
        Log-Error "This platform installer only works on Windows"
        exit 1
    }

    # Check for admin privileges
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Log-Error "Windows installation requires Administrator privileges. Run as Administrator."
        exit 1
    }

    $binaryDir   = "$env:ProgramFiles\Site24x7Labs"
    $binaryPath  = Join-Path $binaryDir "site24x7-labs-agent.exe"
    $configDir   = "$env:ProgramData\Site24x7Labs\faults"
    $serviceName = "Site24x7LabsAgent"
    $downloadUrl = "$($script:HttpAddress)/api/v1/agent/download?os=windows"

    # Create directories
    New-Item -ItemType Directory -Force -Path $binaryDir  | Out-Null
    New-Item -ItemType Directory -Force -Path $configDir  | Out-Null

    # Download binary
    Log-Info "Downloading agent binary from $downloadUrl ..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $binaryPath -UseBasicParsing
    }
    catch {
        Log-Error "Failed to download agent binary: $_"
        exit 1
    }

    Log-Info "Agent binary installed at $binaryPath"

    $agentName = if ([string]::IsNullOrWhiteSpace($Name)) { $env:COMPUTERNAME } else { $Name }

    # Remove existing service if present
    $existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($existingService) {
        Log-Warn "Existing service found — stopping and removing..."
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        sc.exe delete $serviceName | Out-Null
        Start-Sleep -Seconds 2
    }

    # Create the Windows service using sc.exe
    # The agent binary should support running as a Windows service,
    # or wrap it with a service wrapper. We pass env vars via registry or config.
    # For simplicity, we create a wrapper script approach using NSSM or native sc.exe.

    # Set environment variables at machine level for the agent
    [System.Environment]::SetEnvironmentVariable("SERVER_ADDRESS",    $script:ServerAddress, "Machine")
    [System.Environment]::SetEnvironmentVariable("AGENT_TOKEN",       $Token,                "Machine")
    [System.Environment]::SetEnvironmentVariable("AGENT_ENVIRONMENT", $EnvironmentId,        "Machine")
    [System.Environment]::SetEnvironmentVariable("AGENT_NAME",        $agentName,            "Machine")
    [System.Environment]::SetEnvironmentVariable("ENABLE_KUBERNETES", "false",               "Machine")
    [System.Environment]::SetEnvironmentVariable("ENABLE_DOCKER",     "false",               "Machine")
    [System.Environment]::SetEnvironmentVariable("ENABLE_HOST",       "true",                "Machine")
    [System.Environment]::SetEnvironmentVariable("CHAOS_CONFIG_DIR",  $configDir,            "Machine")
    [System.Environment]::SetEnvironmentVariable("LOG_LEVEL",         "info",                "Machine")
    [System.Environment]::SetEnvironmentVariable("LOG_FORMAT",        "json",                "Machine")

    # Create the Windows service
    $scResult = sc.exe create $serviceName `
        binPath= "`"$binaryPath`"" `
        start= auto `
        DisplayName= "Site24x7 Labs Chaos Engineering Agent"

    if ($LASTEXITCODE -ne 0) {
        Log-Error "Failed to create Windows service: $scResult"
        exit 1
    }

    # Set service description
    sc.exe description $serviceName "Site24x7 Labs Chaos Engineering Agent" | Out-Null

    # Set service recovery: restart on failure
    sc.exe failure $serviceName reset= 86400 actions= restart/10000/restart/10000/restart/10000 | Out-Null

    # Start the service
    Start-Service -Name $serviceName

    Log-Info "Windows agent installed and started successfully!"
    Log-Info "Check status: Get-Service -Name $serviceName"
    Log-Info "View logs:    Get-EventLog -LogName Application -Source $serviceName"
}

function Uninstall-Windows {
    Log-Step "Uninstalling Site24x7 Labs agent from Windows..."

    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Log-Error "Windows uninstallation requires Administrator privileges. Run as Administrator."
        exit 1
    }

    $serviceName = "Site24x7LabsAgent"
    $binaryDir   = "$env:ProgramFiles\Site24x7Labs"
    $binaryPath  = Join-Path $binaryDir "site24x7-labs-agent.exe"

    # Stop and remove service
    $existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($existingService) {
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        sc.exe delete $serviceName | Out-Null
        Log-Info "Service '$serviceName' removed."
    }

    # Remove binary
    if (Test-Path $binaryPath) {
        Remove-Item -Path $binaryPath -Force
        Log-Info "Agent binary removed."
    }

    # Clean up environment variables
    $envVars = @(
        "SERVER_ADDRESS", "AGENT_TOKEN", "AGENT_ENVIRONMENT", "AGENT_NAME",
        "ENABLE_KUBERNETES", "ENABLE_DOCKER", "ENABLE_HOST",
        "CHAOS_CONFIG_DIR", "LOG_LEVEL", "LOG_FORMAT"
    )
    foreach ($var in $envVars) {
        [System.Environment]::SetEnvironmentVariable($var, $null, "Machine")
    }

    Log-Info "Windows agent uninstalled successfully!"
}

# =============================================================================
# MAIN
# =============================================================================
function Main {
    Write-Host ""
    Write-Host "============================================"
    Write-Host "  Site24x7 Labs — Agent Installer"
    Write-Host "============================================"
    Write-Host ""

    Confirm-Parameters

    if ($Uninstall) {
        switch ($Platform) {
            "kubernetes" { Uninstall-Kubernetes }
            "docker"     { Uninstall-Docker }
            "compose"    { Uninstall-Compose }
            "windows"    { Uninstall-Windows }
        }
    }
    else {
        switch ($Platform) {
            "kubernetes" { Install-Kubernetes }
            "docker"     { Install-Docker }
            "compose"    { Install-Compose }
            "windows"    { Install-Windows }
        }
    }

    Write-Host ""
    Log-Info "Done!"
}

Main