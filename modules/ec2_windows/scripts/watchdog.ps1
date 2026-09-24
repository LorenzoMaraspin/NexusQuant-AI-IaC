# MT5 watchdog. Runs every minute as SYSTEM (MT5Watchdog Scheduled Task).
# Checks terminal + adapter health, publishes CloudWatch metrics, restarts the failed
# component after 3 consecutive bad checks (5 min cooldown) and trims oversized logs.
$ErrorActionPreference = 'Continue'
$LogName = 'watchdog'
. 'C:\nexusquant\bin\common.ps1'

$StatePath = 'C:\nexusquant\bin\watchdog_state.json'
$MetricsPath = 'C:\nexusquant\bin\metrics.json'
$FailuresBeforeRestart = 3
$CooldownSeconds = 300
$MaxLogBytes = 200MB
$Now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

$state = [pscustomobject]@{ Failures = 0; TradeBlocked = 0; LastRestart = 0 }
if (Test-Path $StatePath) {
    try { $state = Get-Content -Path $StatePath -Raw | ConvertFrom-Json } catch { }
}

# --- Checks ---------------------------------------------------------------
$terminalRunning = [bool](Get-Process -Name 'terminal64' -ErrorAction SilentlyContinue)
$portListening = [bool](Get-NetTCPConnection -LocalPort 8100 -State Listen -ErrorAction SilentlyContinue)
$sessionActive = [bool](quser 2>$null | Select-String -Pattern 'Active|Disc')
$health = $null
$adapterAnswered503 = $false
if ($portListening) {
    try { $health = Invoke-RestMethod -Uri 'http://localhost:8100/api/v1/health' -Method Get -TimeoutSec 8 -UseBasicParsing -ErrorAction Stop }
    catch {
        # HTTP 503 = adapter is alive but reports MT5 unavailable (terminal problem, not adapter).
        if ($_.Exception.Response -and ([int]$_.Exception.Response.StatusCode -eq 503)) { $adapterAnswered503 = $true }
        Write-Log ('health request failed: ' + $_.Exception.Message) 'WARN'
    }
}
$adapterResponsive = ($null -ne $health) -or $adapterAnswered503
$mt5Connected = $adapterResponsive -and ($health.mt5_connected -eq $true)
$tradeAllowed = $null
if ($adapterResponsive -and ($health.PSObject.Properties.Name -contains 'trade_allowed')) { $tradeAllowed = [bool]$health.trade_allowed }
$healthy = $terminalRunning -and $mt5Connected

$bytesPerGb = 1GB
$kbPerMb = 1KB
$diskFreeGb = [Math]::Round((Get-PSDrive -Name C).Free / $bytesPerGb, 2)
$memAvailMb = [Math]::Round((Get-CimInstance -ClassName Win32_OperatingSystem).FreePhysicalMemory / $kbPerMb, 0)

# --- Metrics --------------------------------------------------------------
$dims = @(@{ Name = 'Environment'; Value = $script:Cfg.Environment })
$metrics = @(
    @{ MetricName = 'AdapterHealthy'; Value = [int]$healthy; Unit = 'Count'; Dimensions = $dims },
    @{ MetricName = 'TerminalRunning'; Value = [int]$terminalRunning; Unit = 'Count'; Dimensions = $dims },
    @{ MetricName = 'Mt5Connected'; Value = [int]$mt5Connected; Unit = 'Count'; Dimensions = $dims },
    @{ MetricName = 'InteractiveSession'; Value = [int]$sessionActive; Unit = 'Count'; Dimensions = $dims },
    @{ MetricName = 'DiskFreeGB'; Value = $diskFreeGb; Unit = 'Gigabytes'; Dimensions = $dims },
    @{ MetricName = 'MemAvailableMB'; Value = $memAvailMb; Unit = 'Megabytes'; Dimensions = $dims }
)
if ($null -ne $tradeAllowed) {
    $metrics += @{ MetricName = 'TradeAllowed'; Value = [int]$tradeAllowed; Unit = 'Count'; Dimensions = $dims }
}
try {
    ConvertTo-Json -InputObject $metrics -Depth 5 | Set-Content -Path $MetricsPath -Encoding ASCII
    & $script:AwsCli cloudwatch put-metric-data --namespace 'NexusQuant/MT5' --region $script:Cfg.Region --metric-data ('file://' + ($MetricsPath -replace '\\', '/')) 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Log ('put-metric-data exit code ' + $LASTEXITCODE) 'WARN' }
}
catch { Write-Log ('metrics publish failed: ' + $_.Exception.Message) 'WARN' }

# --- Recovery -------------------------------------------------------------
function Restart-Adapter {
    Write-Log 'restarting adapter task' 'WARN'
    Stop-ScheduledTask -TaskName 'MT5AdapterTask' -ErrorAction SilentlyContinue
    Stop-StrayAdapter
    Start-ScheduledTask -TaskName 'MT5AdapterTask'
}

function Restart-Terminal {
    Write-Log 'restarting terminal task (and adapter, to refresh its MT5 handle)' 'WARN'
    Stop-ScheduledTask -TaskName 'MT5Terminal' -ErrorAction SilentlyContinue
    Get-Process -Name 'terminal64' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-ScheduledTask -TaskName 'MT5Terminal'
    Restart-Adapter
}

if ($healthy) { $state.Failures = 0 } else { $state.Failures = [int]$state.Failures + 1 }
if ($null -ne $tradeAllowed -and -not $tradeAllowed) { $state.TradeBlocked = [int]$state.TradeBlocked + 1 } else { $state.TradeBlocked = 0 }

if (-not $healthy) {
    Write-Log ('unhealthy check ' + $state.Failures + ' | terminal=' + $terminalRunning + ' port8100=' + $portListening + ' responsive=' + $adapterResponsive + ' mt5Connected=' + $mt5Connected + ' session=' + $sessionActive) 'WARN'
}

$cooldownOk = (($Now - [int64]$state.LastRestart) -ge $CooldownSeconds)
if ($cooldownOk) {
    if (-not $sessionActive) {
        Write-Log 'no interactive session: auto-logon did not complete, tasks cannot run' 'ERROR'
    }
    elseif ($state.Failures -ge $FailuresBeforeRestart) {
        if (-not $terminalRunning -or ($adapterResponsive -and -not $mt5Connected)) { Restart-Terminal }
        else { Restart-Adapter }
        $state.LastRestart = $Now
        $state.Failures = 0
    }
    elseif ($state.TradeBlocked -ge $FailuresBeforeRestart) {
        Write-Log 'AutoTrading reported disabled: restarting terminal to re-apply startup config' 'WARN'
        Restart-Terminal
        $state.LastRestart = $Now
        $state.TradeBlocked = 0
    }
}

$state | ConvertTo-Json | Set-Content -Path $StatePath -Encoding ASCII

# --- Log trimming ---------------------------------------------------------
Get-ChildItem -Path 'C:\nexusquant\logs' -Filter '*.log' -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Length -gt $MaxLogBytes) {
        try {
            $fs = [System.IO.File]::Open($_.FullName, 'Open', 'Write', 'ReadWrite')
            $fs.SetLength(0)
            $fs.Close()
            Write-Log ('truncated oversized log ' + $_.Name) 'WARN'
        }
        catch { }
    }
}
