# RAGFlow K8s Pod Resource Monitor Script
# Author: Claude Code
# Date: 2026-01-20

param(
    [Parameter(Position=0)]
    [ValidateSet('Basic', 'Full', 'Json', 'SortByCpu', 'SortByMemory')]
    [string]$Mode = 'Basic',

    [Parameter(Position=1)]
    [switch]$Watch = $false
)

# Set kubeconfig path
$KubeconfigPath = "E:\00_DATA_WORK_20250408\01_OTHER\20250420_Entrepreneuship\20250716_Ragflow\kubeconfig-sealos-ragflow-0.23.1.yaml"

# Check if kubeconfig exists
if (-not (Test-Path $KubeconfigPath)) {
    Write-Host "Error: kubeconfig file not found: $KubeconfigPath" -ForegroundColor Red
    exit 1
}

# Set environment variable
$env:KUBECONFIG = $KubeconfigPath

# Helper function to parse CPU string to cores
function Parse-Cpu {
    param([string]$cpuStr)
    if ($cpuStr -match '^\s*(\d+)m\s*$') {
        return [int]$Matches[1] / 1000
    } elseif ($cpuStr -match '^\s*(\d+(?:\.\d+)?)\s*$') {
        return [double]$Matches[1]
    }
    return 0
}

# Helper function to parse memory string to Gi
function Parse-Memory {
    param([string]$memStr)
    if ($memStr -match '^\s*(\d+(?:\.\d+)?)Mi\s*$') {
        return [double]$Matches[1] / 1024
    } elseif ($memStr -match '^\s*(\d+(?:\.\d+)?)Gi\s*$') {
        return [double]$Matches[1]
    } elseif ($memStr -match '^\s*(\d+(?:\.\d+)?)Ki\s*$') {
        return [double]$Matches[1] / 1024 / 1024
    }
    return 0
}

# Function: Get Pod resource information
function Get-PodResources {
    param([string]$PodName, [string]$Namespace)

    # Get pod details
    $podDetail = kubectl get pod $PodName -n $Namespace -o json 2>$null

    if ($null -eq $podDetail) {
        return $null
    }

    $pod = $podDetail | ConvertFrom-Json

    # Get resource limits and requests
    $container = $pod.spec.containers[0]
    $resources = $container.resources

    # Parse CPU values
    $cpuReqVal = Parse-Cpu $resources.requests.cpu
    $cpuLimVal = Parse-Cpu $resources.limits.cpu

    # Parse memory values
    $memReqVal = Parse-Memory $resources.requests.memory
    $memLimVal = Parse-Memory $resources.limits.memory

    # Get actual resource usage
    $metrics = kubectl top pod $PodName -n $Namespace --containers 2>&1 | Where-Object { $_ -notmatch "Warning" }
    $cpuUsed = 0.0
    $memUsed = 0.0

    if ($metrics) {
        $lines = $metrics -split "`r?`n"
        foreach ($line in $lines) {
            # Skip header and empty lines
            if ([string]::IsNullOrWhiteSpace($line) -or $line -match "POD" -or $line -match "NAME") {
                continue
            }
            # Split by whitespace using .NET split for better compatibility
            $lineParts = $line.Trim() -split "\s+"
            if ($lineParts.Count -ge 4 -and $lineParts[0] -eq $PodName) {
                # Format: POD NAME CPU(cores) MEMORY(bytes)
                # Parts: [0]=POD, [1]=container_name, [2]=CPU, [3]=MEMORY
                $cpuStr = $lineParts[2]
                $memStr = $lineParts[3]
                $cpuUsed = Parse-Cpu $cpuStr
                $memUsed = Parse-Memory $memStr
                break
            }
        }
    }

    # Calculate usage percentage
    $cpuUsage = if ($cpuLimVal -gt 0) { ($cpuUsed / $cpuLimVal) * 100 } else { 0 }
    $memUsage = if ($memLimVal -gt 0) { ($memUsed / $memLimVal) * 100 } else { 0 }

    # Get pod age
    $creationTs = kubectl get pod $PodName -n $Namespace -o jsonpath='{.metadata.creationTimestamp}' 2>$null
    $age = "unknown"
    if ($creationTs) {
        try {
            $created = [DateTime]::Parse($creationTs)
            $timeDiff = (Get-Date) - $created
            if ($timeDiff.Days -gt 0) {
                $age = "$($timeDiff.Days)d"
            } elseif ($timeDiff.Hours -gt 0) {
                $age = "$($timeDiff.Hours)h"
            } elseif ($timeDiff.Minutes -gt 0) {
                $age = "$($timeDiff.Minutes)m"
            } else {
                $age = "$($timeDiff.Seconds)s"
            }
        } catch {
            $age = "unknown"
        }
    }

    return [PSCustomObject]@{
        PodName = $PodName
        Namespace = $Namespace
        Status = $pod.status.phase
        CpuReq = [math]::Round($cpuReqVal, 2)
        CpuLim = [math]::Round($cpuLimVal, 2)
        CpuUsed = [math]::Round($cpuUsed, 3)
        CpuUsage = [math]::Round($cpuUsage, 1)
        MemReq = [math]::Round($memReqVal, 2)
        MemLim = [math]::Round($memLimVal, 2)
        MemUsed = [math]::Round($memUsed, 2)
        MemUsage = [math]::Round($memUsage, 1)
        Node = $pod.spec.nodeName
        Age = $age
    }
}

# Function: Get all pods
function Get-AllPods {
    $pods = kubectl get pods -o json 2>$null | ConvertFrom-Json
    $podList = @()

    foreach ($pod in $pods.items) {
        if ($pod.metadata.name -match 'ragflow' -or $pod.metadata.name -match 'web-visitor') {
            $podInfo = Get-PodResources -PodName $pod.metadata.name -Namespace $pod.metadata.namespace
            if ($podInfo) {
                $podList += $podInfo
            }
        }
    }

    return $podList
}

# Function: Output basic table
function Show-BasicTable {
    param([array]$PodList)

    Write-Host "`n=== RAGFlow Pods Resource Usage ===`n" -ForegroundColor Cyan

    $format = "{0,-25} {1,-8} {2,-8} {3,-6} {4,6} {5,6} {6,8} {7,7} {8,6} {9,7} {10,6}"
    Write-Host ($format -f "Pod Name", "Status", "Node", "Age", "CpuReq", "CpuLim", "CpuUsed", "Cpu%", "MemLim", "MemUsed", "Mem%") -ForegroundColor Yellow

    foreach ($pod in $PodList) {
        $nodeShort = if ($pod.Node.Length -gt 6) { $pod.Node.Substring($pod.Node.Length-6) } else { $pod.Node }

        Write-Host ($format -f $pod.PodName, $pod.Status, $nodeShort, $pod.Age,
            $pod.CpuReq, $pod.CpuLim, $pod.CpuUsed, "$($pod.CpuUsage)%",
            $pod.MemLim, $pod.MemUsed, "$($pod.MemUsage)%")
    }
    Write-Host ""
}

# Function: Output full table
function Show-FullTable {
    param([array]$PodList)

    Write-Host "`n=== RAGFlow Pods Full Resource Details ===`n" -ForegroundColor Cyan

    foreach ($pod in $PodList) {
        Write-Host "`n[$($pod.PodName)]" -ForegroundColor Cyan
        Write-Host "  Status: $($pod.Status) | Node: $($pod.Node) | Age: $($pod.Age)"
        Write-Host "  CPU: Request=$($pod.CpuReq) cores, Limit=$($pod.CpuLim) cores, Used=$($pod.CpuUsed) cores ($($pod.CpuUsage)%)"
        Write-Host "  Memory: Request=$($pod.MemReq)Gi, Limit=$($pod.MemLim)Gi, Used=$($pod.MemUsed)Gi ($($pod.MemUsage)%)"
    }
    Write-Host ""
}

# Function: Output JSON
function Show-JsonOutput {
    param([array]$PodList)

    $output = @{
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        cluster = "Sealos (bja.sealos.run:6443)"
        pods = @()
    }

    foreach ($pod in $PodList) {
        $output.pods += @{
            name = $pod.PodName
            namespace = $pod.Namespace
            status = $pod.Status
            node = $pod.Node
            age = $pod.Age
            cpu = @{
                request = $pod.CpuReq
                limit = $pod.CpuLim
                used = $pod.CpuUsed
                usage_percent = $pod.CpuUsage
            }
            memory = @{
                request = $pod.MemReq
                limit = $pod.MemLim
                used = $pod.MemUsed
                usage_percent = $pod.MemUsage
            }
        }
    }

    $output | ConvertTo-Json -Depth 10
}

# Function: Output sorted by resource usage
function Show-SortedOutput {
    param([array]$PodList, [string]$SortBy)

    Write-Host "`n=== RAGFlow Pods Resource Usage Sorted by $SortBy ===`n" -ForegroundColor Cyan

    if ($SortBy -eq "CPU") {
        $sorted = $PodList | Sort-Object -Property CpuUsage -Descending
    } else {
        $sorted = $PodList | Sort-Object -Property MemUsage -Descending
    }

    $format = "{0,-25} {1,10} {2,10} {3,12} {4,10} {5,10}"
    Write-Host ($format -f "Pod Name", "$SortBy Req", "$SortBy Lim", "$SortBy Used", "Usage", "Status") -ForegroundColor Yellow
    Write-Host ("-" * 85) -ForegroundColor Gray

    foreach ($pod in $sorted) {
        if ($SortBy -eq "CPU") {
            $req = "$($pod.CpuReq)C"
            $lim = "$($pod.CpuLim)C"
            $used = "$($pod.CpuUsed)C"
            $usage = "$($pod.CpuUsage)%"
        } else {
            $req = "$($pod.MemReq)Gi"
            $lim = "$($pod.MemLim)Gi"
            $used = "$($pod.MemUsed)Gi"
            $usage = "$($pod.MemUsage)%"
        }

        Write-Host ($format -f $pod.PodName, $req, $lim, $used, $usage, $pod.Status)
    }
    Write-Host ""
}

# Main program
try {
    if ($Watch) {
        Clear-Host
        Write-Host "Watch mode enabled (refresh every 5 seconds, press Ctrl+C to exit)" -ForegroundColor Green
        Write-Host "================================================`n" -ForegroundColor Gray

        while ($true) {
            Clear-Host
            $podList = Get-AllPods

            if ($podList.Count -eq 0) {
                Write-Host "Warning: No RAGFlow Pods found" -ForegroundColor Yellow
            } else {
                switch ($Mode) {
                    'Basic' { Show-BasicTable -PodList $podList }
                    'Full' { Show-FullTable -PodList $podList }
                    'Json' { Show-JsonOutput -PodList $podList }
                    'SortByCpu' { Show-SortedOutput -PodList $podList -SortBy "CPU" }
                    'SortByMemory' { Show-SortedOutput -PodList $podList -SortBy "Memory" }
                }
            }

            Write-Host "`nNext update: in 5 seconds... (press Ctrl+C to exit)" -ForegroundColor Gray
            Start-Sleep -Seconds 5
        }
    } else {
        $podList = Get-AllPods

        if ($podList.Count -eq 0) {
            Write-Host "`nWarning: No RAGFlow Pods found`n" -ForegroundColor Yellow
            exit 0
        }

        switch ($Mode) {
            'Basic' { Show-BasicTable -PodList $podList }
            'Full' { Show-FullTable -PodList $podList }
            'Json' { Show-JsonOutput -PodList $podList }
            'SortByCpu' { Show-SortedOutput -PodList $podList -SortBy "CPU" }
            'SortByMemory' { Show-SortedOutput -PodList $podList -SortBy "Memory" }
        }
    }
} catch {
    Write-Host "`nError: $_" -ForegroundColor Red
    exit 1
}
