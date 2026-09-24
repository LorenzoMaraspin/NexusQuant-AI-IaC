# Shared helpers for the NexusQuant MT5 runtime scripts (dot-sourced).
# Caller must set $LogName before dot-sourcing.
$script:Cfg = Get-Content -Path 'C:\nexusquant\bin\config.json' -Raw | ConvertFrom-Json
$script:AwsCli = if (Test-Path 'C:\Program Files\Amazon\AWSCLIV2\aws.exe') { 'C:\Program Files\Amazon\AWSCLIV2\aws.exe' } else { 'aws' }

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $stamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    $line = $stamp + ' | ' + $Level.PadRight(7) + ' | ' + $script:LogName + ' | ' + $Message
    try { Add-Content -Path ('C:\nexusquant\logs\' + $script:LogName + '.log') -Value $line } catch { }
}

function Invoke-Retry {
    # Retries $Action with capped exponential backoff. MaxSeconds = 0 means forever.
    param([scriptblock]$Action, [string]$What, [int]$MaxSeconds = 0)
    $delay = 2
    $start = Get-Date
    while ($true) {
        try { return (& $Action) }
        catch {
            Write-Log ($What + ' failed: ' + $_.Exception.Message) 'WARN'
            if ($MaxSeconds -gt 0 -and ((Get-Date) - $start).TotalSeconds -gt $MaxSeconds) { throw }
            Start-Sleep -Seconds $delay
            $delay = [Math]::Min($delay * 2, 60)
        }
    }
}

function Get-AwsSecrets {
    $json = & $script:AwsCli secretsmanager get-secret-value --secret-id $script:Cfg.SecretName --region $script:Cfg.Region --query SecretString --output text
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) { throw ('secretsmanager exit code ' + $LASTEXITCODE) }
    return ($json | ConvertFrom-Json)
}

function Get-SsmParams {
    $json = & $script:AwsCli ssm get-parameters-by-path --path $script:Cfg.SsmPrefix --region $script:Cfg.Region --query 'Parameters[*].{Name:Name,Value:Value}' --output json
    if ($LASTEXITCODE -ne 0) { throw ('ssm get-parameters-by-path exit code ' + $LASTEXITCODE) }
    return @($json | ConvertFrom-Json)
}

function Get-SsmValue {
    param($Params, [string]$Name)
    $hit = $Params | Where-Object { $_.Name.Split('/')[-1] -eq $Name } | Select-Object -First 1
    if ($null -eq $hit) { return $null }
    return $hit.Value
}

function Stop-StrayAdapter {
    # Kills any leftover adapter python process so a new one can bind port 8100.
    Get-CimInstance -ClassName Win32_Process -Filter "Name = 'python.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*presentation.main*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}
