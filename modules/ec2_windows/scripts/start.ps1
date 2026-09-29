# One-shot manual starter for the NexusQuant MT5 Terminal + Adapter.
# Run this yourself after logging in via RDP. It loads the required secrets
# and SSM parameters, starts the MT5 terminal if it isn't already running,
# and then runs the adapter in the foreground. There is no supervision or
# auto-restart here: if the terminal or the adapter exits, just run this
# script again.
$ErrorActionPreference = 'Stop'
$LogName = 'start'
. 'C:\nexusquant\bin\common.ps1'

$RepoDir = 'C:\nexusquant\NexusQuant-MT5-Connector'
$Python = $RepoDir + '\.venv\Scripts\python.exe'
$TerminalExe = 'C:\Program Files\MetaTrader 5\terminal64.exe'
$IniPath = 'C:\nexusquant\mt5\startup.ini'
New-Item -ItemType Directory -Force -Path 'C:\nexusquant\mt5' | Out-Null

Write-Host 'Loading secrets and SSM parameters...'
$secrets = Invoke-Retry -What 'load secrets' -Action { Get-AwsSecrets }
$params = Invoke-Retry -What 'load SSM parameters' -Action { Get-SsmParams }

if (Get-Process -Name 'terminal64' -ErrorAction SilentlyContinue) {
    Write-Host 'terminal64 is already running, skipping terminal startup.'
}
else {
    $login = Get-SsmValue -Params $params -Name 'MT5_ACCOUNT_NUMBER'
    $server = Get-SsmValue -Params $params -Name 'MT5_SERVER'
    if (-not $login -or -not $server) { throw 'MT5_ACCOUNT_NUMBER or MT5_SERVER missing in SSM Parameter Store.' }
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
    Write-Host 'Starting MetaTrader 5 terminal...'
    Start-Process -FilePath $TerminalExe -ArgumentList ('/config:"' + $IniPath + '"')
    Start-Sleep -Seconds 20
    Remove-Item -Path $IniPath -Force -ErrorAction SilentlyContinue
}

Stop-StrayAdapter
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

Set-Location -Path $RepoDir
Write-Host 'Starting the adapter in the foreground (Ctrl+C to stop; re-run this script to restart it)...'
& $Python -m presentation.main
