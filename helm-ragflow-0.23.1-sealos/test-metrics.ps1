$env:KUBECONFIG="E:\00_DATA_WORK_20250408\01_OTHER\20250420_Entrepreneuship\20250716_Ragflow\kubeconfig-sealos-ragflow-0.23.1.yaml"
$PodName = "ragflow01-75858747b4-88zwf"
$Namespace = "ns-h8lwh4iu"

$metrics = kubectl top pod $PodName -n $Namespace --containers 2>&1 | Where-Object { $_ -notmatch "Warning" }

Write-Host "=== METRICS OUTPUT ==="
Write-Host $metrics
Write-Host ""
Write-Host "=== PARSING ==="
$lines = $metrics -split "`n"
Write-Host "Line count: $($lines.Count)"

foreach ($line in $lines) {
    Write-Host "Line: '$line'"
    if ($line -match "POD" -or $line -match "NAME") {
        Write-Host "  -> Skipping (header)"
        continue
    }
    $lineParts = $line -split '\s+', 0, "SimpleMatch"
    Write-Host "  Parts count: $($lineParts.Count)"
    if ($lineParts.Count -gt 0) {
        Write-Host "  First part: '$($lineParts[0])'"
        Write-Host "  PodName: '$PodName'"
        if ($lineParts[0] -eq $PodName) {
            Write-Host "  -> MATCH!"
            Write-Host "  CPU: '$($lineParts[2])'"
            Write-Host "  Mem: '$($lineParts[3])'"
        }
    }
}
