# MT5 terminal supervisor. Runs in the interactive (auto-logon) session via the MT5Terminal
# Scheduled Task. Launches terminal64.exe with a startup config that logs in and enables
# algorithmic trading, and relaunches it whenever it exits.
$ErrorActionPreference = 'Stop'
$LogName = 'terminal-supervisor'
. 'C:\nexusquant\bin\common.ps1'

$TerminalExe = 'C:\Program Files\MetaTrader 5\terminal64.exe'
$IniPath = 'C:\nexusquant\mt5\startup.ini'
New-Item -ItemType Directory -Force -Path 'C:\nexusquant\mt5' | Out-Null

function New-StartupIni {
    $secrets = Invoke-Retry -What 'load secrets' -Action { Get-AwsSecrets }
    $params = Invoke-Retry -What 'load SSM parameters' -Action { Get-SsmParams }
    $login = Get-SsmValue -Params $params -Name 'MT5_ACCOUNT_NUMBER'
    $server = Get-SsmValue -Params $params -Name 'MT5_SERVER'
    if (-not $login -or -not $server) { throw 'MT5_ACCOUNT_NUMBER or MT5_SERVER missing in SSM' }
    $ini = @(
        '[Common]',
        ('Login=' + $login),
        ('Password=' + $secrets.MT5_PASSWORD),
        ('Server=' + $server),
        'KeepPrivate=1',
        '',
        '[Experts]',
        'Enabled=1',
        'AllowLiveTrading=1',
        'AllowDllImport=0'
    )
    Set-Content -Path $IniPath -Value $ini -Encoding ASCII
}

Write-Log 'terminal supervisor started'
while ($true) {
    try {
        $existing = @(Get-Process -Name 'terminal64' -ErrorAction SilentlyContinue)
        if ($existing.Count -gt 0) {
            Write-Log ('terminal64 already running (pid ' + $existing[0].Id + '), waiting for it to exit')
            $existing | Wait-Process
            Write-Log 'terminal64 exited' 'WARN'
        }
        else {
            New-StartupIni
            $p = Start-Process -FilePath $TerminalExe -ArgumentList ('/config:"' + $IniPath + '"') -PassThru
            Write-Log ('terminal64 started, pid ' + $p.Id)
            Start-Sleep -Seconds 30
            # Do not leave the broker password on disk.
            Remove-Item -Path $IniPath -Force -ErrorAction SilentlyContinue
            $p | Wait-Process
            Write-Log ('terminal64 exited, code ' + $p.ExitCode) 'WARN'
        }
    }
    catch {
        Write-Log ('terminal supervisor error: ' + $_.Exception.Message) 'ERROR'
        Remove-Item -Path $IniPath -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 5
}
