# MT5 Adapter supervisor. Runs in the interactive session via the MT5AdapterTask Scheduled Task.
# Waits for the terminal, loads secrets/config with retry (no dependence on boot-time network
# timing), runs the adapter and restarts it with backoff whenever it exits.
$ErrorActionPreference = 'Stop'
$LogName = 'adapter-supervisor'
. 'C:\nexusquant\bin\common.ps1'

$RepoDir = 'C:\nexusquant\NexusQuant-MT5-Connector'
$Python = $RepoDir + '\.venv\Scripts\python.exe'
$StdoutLog = 'C:\nexusquant\logs\mt5_adapter_stdout.log'
$MaxLogBytes = 100MB

function Wait-ForTerminal {
    param([int]$TimeoutSeconds = 180)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Get-Process -Name 'terminal64' -ErrorAction SilentlyContinue) { return $true }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Set-AdapterEnvironment {
    $secrets = Invoke-Retry -What 'load secrets' -Action { Get-AwsSecrets }
    $params = Invoke-Retry -What 'load SSM parameters' -Action { Get-SsmParams }
    [Environment]::SetEnvironmentVariable('ADAPTER_API_KEY', $secrets.ADAPTER_API_KEY, 'Process')
    [Environment]::SetEnvironmentVariable('MT5_PASSWORD', $secrets.MT5_PASSWORD, 'Process')
    [Environment]::SetEnvironmentVariable('POSTGRES_URL', $secrets.POSTGRES_URL, 'Process')
    [Environment]::SetEnvironmentVariable('DATABASE_URL', $secrets.POSTGRES_URL, 'Process')
    foreach ($p in $params) {
        $name = $p.Name.Split('/')[-1]
        if ($name -match '^[A-Za-z_][A-Za-z0-9_]*$') {
            [Environment]::SetEnvironmentVariable($name, $p.Value, 'Process')
        }
    }
    [Environment]::SetEnvironmentVariable('AWS_EXECUTION_ENV', 'true', 'Process')
    [Environment]::SetEnvironmentVariable('PYTHONPATH', ($RepoDir + '\src'), 'Process')
}

function Rotate-StdoutLog {
    if ((Test-Path $StdoutLog) -and ((Get-Item $StdoutLog).Length -gt $MaxLogBytes)) {
        Move-Item -Path $StdoutLog -Destination ($StdoutLog + '.old') -Force -ErrorAction SilentlyContinue
        Write-Log 'stdout log rotated'
    }
}

Write-Log 'adapter supervisor started'
$backoff = 5
while ($true) {
    try {
        if (Wait-ForTerminal) {
            Write-Log 'terminal64 detected, settling for 20s'
            Start-Sleep -Seconds 20
        }
        else {
            Write-Log 'terminal64 not detected after 180s, starting adapter anyway' 'WARN'
        }
        Stop-StrayAdapter
        Set-AdapterEnvironment
        Rotate-StdoutLog
        Set-Location -Path $RepoDir
        $started = Get-Date
        Write-Log 'starting adapter'
        # Native stderr must not become a terminating error while redirected.
        $ErrorActionPreference = 'Continue'
        & $Python -m presentation.main *>> $StdoutLog
        $code = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        Write-Log ('adapter exited, code ' + $code) 'WARN'
        if (((Get-Date) - $started).TotalSeconds -gt 300) { $backoff = 5 } else { $backoff = [Math]::Min($backoff * 2, 60) }
    }
    catch {
        $ErrorActionPreference = 'Stop'
        Write-Log ('adapter supervisor error: ' + $_.Exception.Message) 'ERROR'
        $backoff = [Math]::Min($backoff * 2, 60)
    }
    Start-Sleep -Seconds $backoff
}
