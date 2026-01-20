# RAGFlow K8s Pod Resource Chart Script
# Author: Claude Code
# Date: 2026-01-20

param(
    [Parameter(Position=0)]
    [ValidateSet('Chart', 'HtmlChart')]
    [string]$Mode = 'Chart',

    [Parameter(Position=1)]
    [int]$DataPoints = 30,

    [Parameter(Position=2)]
    [int]$RefreshInterval = 5,

    [Parameter(Position=3)]
    [string]$PodFilter = "",

    [Parameter(Position=4)]
    [ValidateSet('all', 'cpu', 'memory')]
    [string]$ResourceType = "all",

    [Parameter(Position=5)]
    [string]$OutputFile = "ragflow-resource-chart.html"
)

# Set kubeconfig path
$KubeconfigPath = "E:\00_DATA_WORK_20250408\01_OTHER\20250420_Entrepreneuship\20250716_Ragflow\kubeconfig-sealos-ragflow-0.23.1.yaml"
$env:KUBECONFIG = $KubeconfigPath

# Function: Get all RAGFlow pods resource usage
function Get-PodResources {
    $pods = kubectl get pods -o json 2>$null | ConvertFrom-Json
    $podList = @()

    foreach ($pod in $pods.items) {
        if ($pod.metadata.name -match 'ragflow' -or $pod.metadata.name -match 'web-visitor') {
            $metrics = kubectl top pod $pod.metadata.name -n $pod.metadata.namespace --containers 2>&1 | Where-Object { $_ -notmatch "Warning" }

            $cpuUsed = 0
            $memUsed = 0

            if ($metrics) {
                $lines = $metrics -split "`r?`n"
                foreach ($line in $lines) {
                    if ([string]::IsNullOrWhiteSpace($line) -or $line -match "POD" -or $line -match "NAME") {
                        continue
                    }
                    $lineParts = $line.Trim() -split "\s+"
                    if ($lineParts.Count -ge 4 -and $lineParts[0] -eq $pod.metadata.name) {
                        $cpuStr = $lineParts[2]
                        $memStr = $lineParts[3]

                        # Parse CPU
                        if ($cpuStr -match 'm$') {
                            $cpuUsed = [int]$cpuStr.TrimEnd('m') / 1000
                        } else {
                            $cpuUsed = [double]$cpuStr
                        }

                        # Parse memory
                        if ($memStr -match 'Mi$') {
                            $memUsed = [int]$memStr.TrimEnd('Mi') / 1024
                        } elseif ($memStr -match 'Gi$') {
                            $memUsed = [double]$memStr.TrimEnd('Gi')
                        }
                        break
                    }
                }
            }

            # Get limits for usage percentage
            $cpuLim = 0
            $memLim = 0
            $resources = $pod.spec.containers[0].resources

            if ($resources.limits.cpu) {
                if ($resources.limits.cpu -match 'm$') {
                    $cpuLim = [int]$resources.limits.cpu.TrimEnd('m') / 1000
                } else {
                    $cpuLim = [double]$resources.limits.cpu
                }
            }

            if ($resources.limits.memory) {
                if ($resources.limits.memory -match 'Mi$') {
                    $memLim = [int]$resources.limits.memory.TrimEnd('Mi') / 1024
                } elseif ($resources.limits.memory -match 'Gi$') {
                    $memLim = [double]$resources.limits.memory.TrimEnd('Gi')
                }
            }

            $cpuUsage = if ($cpuLim -gt 0) { ($cpuUsed / $cpuLim) * 100 } else { 0 }
            $memUsage = if ($memLim -gt 0) { ($memUsed / $memLim) * 100 } else { 0 }

            $podList += [PSCustomObject]@{
                PodName = $pod.metadata.name
                CpuUsage = $cpuUsage
                MemUsage = $memUsage
            }
        }
    }

    return $podList
}

# Function: Show ASCII chart
function Show-AsciiChart {
    param([array]$history, [string]$resourceType)

    if ($history.Count -eq 0) {
        Write-Host "`nNo data available yet.`n" -ForegroundColor Yellow
        return
    }

    $podNames = ($history | Select-Object -ExpandProperty PodName | Get-Unique)
    if ($podFilter) {
        $podNames = $podNames | Where-Object { $_ -like $podFilter }
    }

    if ($podNames.Count -eq 0) {
        Write-Host "`nNo pods found matching filter.`n" -ForegroundColor Yellow
        return
    }

    Write-Host "`n=== RAGFlow Resource Usage Chart ===`n" -ForegroundColor Cyan
    Write-Host "Time points: $timePoints/$DataPoints | Pods: $($podNames.Count) | Resource: $resourceType | Last updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n" -ForegroundColor Gray

    if ($timePoints -lt 2) {
        Write-Host "Collecting data... ($timePoints time point(s) collected)`n" -ForegroundColor Yellow
    }

    # Unicode block characters for 8 levels
    $blocks = @('_', [char]0x2581, [char]0x2582, [char]0x2583, [char]0x2584, [char]0x2585, [char]0x2586, [char]0x2587)

    # Group data by pod - each pod has a series of data points
    $dataByPod = @{}
    $timePoints = 0

    foreach ($pod in $podNames) {
        $podSeries = $history | Where-Object { $_.PodName -eq $pod }
        $dataByPod[$pod] = $podSeries
        if ($podSeries.Count -gt $timePoints) {
            $timePoints = $podSeries.Count
        }
    }

    # Show CPU chart
    if ($resourceType -eq 'all' -or $resourceType -eq 'cpu') {
        Write-Host "CPU Usage (%):`n" -ForegroundColor Yellow

        for ($level = 10; $level -ge 0; $level--) {
            $line = "{0,4}" -f "$($level * 10)%"

            for ($i = 0; $i -lt $timePoints; $i++) {
                $maxValForColumn = 0
                foreach ($pod in $podNames) {
                    $podSeries = $dataByPod[$pod]
                    if ($i -lt $podSeries.Count) {
                        $val = $podSeries[$i].CpuUsage
                        if ($val -gt $maxValForColumn) {
                            $maxValForColumn = $val
                        }
                    }
                }

                $blockIdx = [Math]::Min(7, [Math]::Max(0, [Math]::Floor(($maxValForColumn / 100) * 8)))
                $line += $blocks[$blockIdx]
            }

            $dashCount = if ($timePoints -gt 10) { 40 } else { [Math]::Max(0, $timePoints - 1) }
            if ($level -eq 10) {
                $line += " " + ("-" * $dashCount)
            } elseif ($level -eq 0) {
                $line += " " + ("-" * $dashCount) + "->"
            }

            Write-Host $line
        }
        Write-Host ""
    }

    # Show Memory chart
    if ($resourceType -eq 'all' -or $resourceType -eq 'memory') {
        Write-Host "Memory Usage (%):`n" -ForegroundColor Yellow

        for ($level = 10; $level -ge 0; $level--) {
            $line = "{0,4}" -f "$($level * 10)%"

            for ($i = 0; $i -lt $timePoints; $i++) {
                $maxValForColumn = 0
                foreach ($pod in $podNames) {
                    $podSeries = $dataByPod[$pod]
                    if ($i -lt $podSeries.Count) {
                        $val = $podSeries[$i].MemUsage
                        if ($val -gt $maxValForColumn) {
                            $maxValForColumn = $val
                        }
                    }
                }

                $blockIdx = [Math]::Min(7, [Math]::Max(0, [Math]::Floor(($maxValForColumn / 100) * 8)))
                $line += $blocks[$blockIdx]
            }

            $dashCount = if ($timePoints -gt 10) { 40 } else { [Math]::Max(0, $timePoints - 1) }
            if ($level -eq 10) {
                $line += " " + ("-" * $dashCount)
            } elseif ($level -eq 0) {
                $line += " " + ("-" * $dashCount) + "->"
            }

            Write-Host $line
        }
        Write-Host ""
    }

    # Show legend
    Write-Host "Legend (current values):`n" -ForegroundColor Yellow
    foreach ($pod in $podNames) {
        $series = $dataByPod[$pod]
        if ($series.Count -gt 0) {
            $last = $series[-1]
            $name = if ($pod.Length -gt 20) { $pod.Substring(0, 20) } else { $pod }
            Write-Host "  [$name] CPU: $($last.CpuUsage.ToString('F1'))% | Memory: $($last.MemUsage.ToString('F1'))%"
        }
    }
    Write-Host ""
}

# Main program
# History structure: array of hashtables, where each entry represents one time point
# Entry format: @{ Timestamp = [DateTime]; Pods = @{ podName = @{CpuUsage=...; MemUsage=...} } }
$history = @()

Write-Host "Collecting resource usage data... (Press Ctrl+C to stop)" -ForegroundColor Green
Write-Host "=================================================`n" -ForegroundColor Gray

$iteration = 0
while ($true) {
    Clear-Host

    # Get current resources
    $currentData = Get-PodResources

    # Create new time entry
    $timeEntry = @{
        Timestamp = Get-Date
        Pods = @{}
    }

    # Add current pod data to this time entry
    foreach ($item in $currentData) {
        $timeEntry.Pods[$item.PodName] = @{
            CpuUsage = $item.CpuUsage
            MemUsage = $item.MemUsage
        }
    }

    # Add to history
    $history += $timeEntry

    # Keep only last N data points
    if ($history.Count -gt $DataPoints) {
        $history = $history | Select-Object -Last $DataPoints
    }

    # Rebuild history as flat array for chart function
    # Each pod gets its own series
    $flatHistory = @()
    $podNames = @()

    # Collect all unique pod names from history
    foreach ($entry in $history) {
        foreach ($podName in $entry.Pods.Keys) {
            if ($podNames -notcontains $podName) {
                $podNames += $podName
            }
        }
    }

    # Build flat history - one entry per (time, pod) combination
    foreach ($podName in $podNames) {
        foreach ($entry in $history) {
            if ($entry.Pods.ContainsKey($podName)) {
                $flatHistory += [PSCustomObject]@{
                    PodName = $podName
                    CpuUsage = $entry.Pods[$podName].CpuUsage
                    MemUsage = $entry.Pods[$podName].MemUsage
                }
            } else {
                # Pod didn't exist at this time point, add placeholder
                $flatHistory += [PSCustomObject]@{
                    PodName = $podName
                    CpuUsage = 0
                    MemUsage = 0
                }
            }
        }
    }

    if ($Mode -eq 'Chart') {
        Show-AsciiChart -history $flatHistory -resourceType $ResourceType
    } else {
        Write-Host "`nHtmlChart mode not yet implemented. Use Chart mode instead.`n" -ForegroundColor Yellow
    }

    $iteration++
    Write-Host "`nNext update: in $RefreshInterval seconds... (press Ctrl+C to exit)" -ForegroundColor Gray
    Start-Sleep -Seconds $RefreshInterval
}
