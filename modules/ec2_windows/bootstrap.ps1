<powershell>
#Requires -Version 5.1
###############################################################################
# NexusQuant MT5 Adapter — EC2 Windows Bootstrap (User Data)
# Runs ONCE at first boot. Idempotent: safe to re-run.
# Template vars (Terraform templatefile()): project_name, environment,
# aws_region, ssm_prefix, secret_name, github_repo_url, repo_branch,
# mt5_installer_url.
# NOTE: EC2 User Data has a hard 16384-byte limit (decoded). Keep this file
# lean - prefer one-line comments over banner blocks and reuse helper
# functions instead of duplicating logic (see README "Post-Installazione").
###############################################################################

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Logging helper - appends to a local file and echoes to host; the file is
# uploaded to CloudWatch (/nexusquant/ec2-bootstrap) as step 10 below.
$LogFile = "C:\bootstrap.log"
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts  = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $line = "[$ts][$Level] $Message"
    Add-Content -Path $LogFile -Value $line
    Write-Host $line
}

# Shared retry-download helper (used by steps 3 and 9).
function Get-FileWithRetry {
    param([string]$Url, [string]$OutFile, [int]$Attempts = 3)
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
            return $true
        } catch {
            Write-Log "Download attempt $i/$Attempts failed ($Url): $_" "WARN"
            Start-Sleep -Seconds 10
        }
    }
    return $false
}

# EC2Launch executes User Data from a temp location; keep a copy for
# troubleshooting and manual re-runs.
$BootstrapPath = "C:\nexusquant\bootstrap.ps1"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $BootstrapPath) | Out-Null
if (-not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path) -and
    $MyInvocation.MyCommand.Path -ne $BootstrapPath) {
    Copy-Item -LiteralPath $MyInvocation.MyCommand.Path -Destination $BootstrapPath -Force
}

Write-Log "=== NexusQuant MT5 Adapter Bootstrap START ==="
Write-Log "Project: ${project_name} | Env: ${environment} | Region: ${aws_region}"

# 1. Install Chocolatey (package manager)
Write-Log "Installing Chocolatey..."
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    $env:PATH += ";C:\ProgramData\chocolatey\bin"
    Write-Log "Chocolatey installed."
} else {
    Write-Log "Chocolatey already present, skipping."
}

# 2. Install Python 3.12, Git, AWS CLI v2, NSSM
Write-Log "Installing Python 3.12..."
choco install python312 --yes --no-progress 2>&1 | ForEach-Object { Write-Log $_ }

Write-Log "Installing Git..."
choco install git --yes --no-progress 2>&1 | ForEach-Object { Write-Log $_ }

Write-Log "Installing NSSM..."
choco install nssm --yes --no-progress 2>&1 | ForEach-Object { Write-Log $_ }

Write-Log "Installing AWS CLI v2..."
choco install awscli --yes --no-progress 2>&1 | ForEach-Object { Write-Log $_ }

$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("PATH", "User")

Write-Log "Tool versions:"
python --version 2>&1 | ForEach-Object { Write-Log "  python: $_" }
git    --version 2>&1 | ForEach-Object { Write-Log "  git:    $_" }
aws    --version 2>&1 | ForEach-Object { Write-Log "  aws:    $_" }

# 3. Install MetaTrader 5 terminal (silent, /auto) - installs to the
# standard path, matching mt5_terminal_path read by the Python connector.
$Mt5InstallerPath = "C:\nexusquant\mt5setup.exe"
$Mt5TerminalExe = "C:\Program Files\MetaTrader 5\terminal64.exe"

if (Test-Path $Mt5TerminalExe) {
    Write-Log "MetaTrader 5 terminal already installed, skipping."
} else {
    Write-Log "Downloading MetaTrader 5 installer from ${mt5_installer_url}..."
    if (-not (Get-FileWithRetry -Url "${mt5_installer_url}" -OutFile $Mt5InstallerPath)) {
        throw "Failed to download MetaTrader 5 installer from ${mt5_installer_url} after 3 attempts."
    }
    Write-Log "Installing MetaTrader 5 (silent, /auto)..."
    Start-Process -FilePath $Mt5InstallerPath -ArgumentList "/auto" -Wait -NoNewWindow

    # /auto exiting doesn't strictly guarantee every file is on disk yet.
    $waited = 0
    while ((-not (Test-Path $Mt5TerminalExe)) -and ($waited -lt 180)) {
        Start-Sleep -Seconds 5
        $waited += 5
    }
    if (-not (Test-Path $Mt5TerminalExe)) {
        throw "MetaTrader 5 installation did not produce $Mt5TerminalExe within 180s - aborting, the adapter cannot run without it."
    }
    Write-Log "MetaTrader 5 installed at $Mt5TerminalExe."

    # The installer may auto-launch the terminal; the NSSM service (step 7)
    # drives it at runtime, not this leftover process.
    Get-Process -Name "terminal64" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# 4. Clone repository
$RepoDir = "C:\nexusquant\NexusQuant-MT5-Connector"

if (-not (Test-Path $RepoDir)) {
    Write-Log "Cloning repository from ${github_repo_url} (branch: ${repo_branch})..."
    New-Item -ItemType Directory -Force -Path "C:\nexusquant" | Out-Null
    git clone --branch "${repo_branch}" "${github_repo_url}" $RepoDir 2>&1 |
        ForEach-Object { Write-Log $_ }
} else {
    Write-Log "Repository already cloned, pulling latest..."
    Push-Location $RepoDir
    git pull origin "${repo_branch}" 2>&1 | ForEach-Object { Write-Log $_ }
    Pop-Location
}

# 5. Create Python virtual environment and install dependencies
Write-Log "Creating Python virtual environment..."
Push-Location $RepoDir

if (-not (Test-Path ".venv")) {
    python -m venv .venv
}

Write-Log "Installing Python dependencies..."
& ".\.venv\Scripts\pip.exe" install --upgrade pip 2>&1 | ForEach-Object { Write-Log $_ }
& ".\.venv\Scripts\pip.exe" install -e "." 2>&1 | ForEach-Object { Write-Log $_ }

Pop-Location

# 6. Create runtime environment loader script (fetch_secrets.ps1) - called
# by the NSSM service on every start. Reads Secrets Manager + SSM, sets env
# vars, then launches the app. No .env file is written to disk.
Write-Log "Writing fetch_secrets.ps1 runtime launcher..."

$FetchSecretsScript = @'
#Requires -Version 5.1
# fetch_secrets.ps1 - runtime secret loader for MT5 Adapter, called by NSSM
# on every start. No .env file is written to disk.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Region = "AWS_REGION_PLACEHOLDER"
$SecretName = "SECRET_NAME_PLACEHOLDER"
$SsmPrefix = "SSM_PREFIX_PLACEHOLDER"
$RepoDir = "C:\nexusquant\NexusQuant-MT5-Connector"

function Set-EnvVar { param([string]$Name, [string]$Value)
    [System.Environment]::SetEnvironmentVariable($Name, $Value, "Process")
}

try {
    $SecretJson = aws secretsmanager get-secret-value `
        --secret-id $SecretName `
        --region $Region `
        --query SecretString `
        --output text
    $Secrets = $SecretJson | ConvertFrom-Json

    Set-EnvVar "ADAPTER_API_KEY" $Secrets.ADAPTER_API_KEY
    Set-EnvVar "MT5_PASSWORD"    $Secrets.MT5_PASSWORD
    Set-EnvVar "POSTGRES_URL"    $Secrets.POSTGRES_URL
    Write-Host "[fetch_secrets] Secrets Manager values loaded."
} catch {
    Write-Host "[fetch_secrets][ERROR] Failed to load secrets: $_"
    exit 1
}

try {
    $SsmParams = aws ssm get-parameters-by-path `
        --path $SsmPrefix `
        --region $Region `
        --query "Parameters[*].{Name:Name,Value:Value}" `
        --output json | ConvertFrom-Json

    foreach ($param in $SsmParams) {
        $key = $param.Name.Split("/")[-1]
        Set-EnvVar $key $param.Value
    }
    Write-Host "[fetch_secrets] SSM parameters loaded ($($SsmParams.Count) params)."
} catch {
    Write-Host "[fetch_secrets][ERROR] Failed to load SSM parameters: $_"
    exit 1
}

Set-EnvVar "AWS_EXECUTION_ENV" "true"

$env:PYTHONPATH = "$RepoDir\src"
Set-Location $RepoDir
Write-Host "[fetch_secrets] Starting MT5 adapter..."
& "$RepoDir\.venv\Scripts\python.exe" -m presentation.main
'@

$FetchSecretsScript = $FetchSecretsScript `
    -replace "AWS_REGION_PLACEHOLDER",    "${aws_region}" `
    -replace "SECRET_NAME_PLACEHOLDER",   "${secret_name}" `
    -replace "SSM_PREFIX_PLACEHOLDER",    "${ssm_prefix}"

$LauncherPath = "$RepoDir\fetch_secrets.ps1"
Set-Content -Path $LauncherPath -Value $FetchSecretsScript -Encoding UTF8
Write-Log "fetch_secrets.ps1 written to $LauncherPath"

# 7. Install Windows Service via NSSM
Write-Log "Installing MT5Adapter Windows service via NSSM..."

$NssmExe = "C:\ProgramData\chocolatey\bin\nssm.exe"
$ServiceName = "MT5Adapter"
$PsExe = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
$ServiceArgs = "-ExecutionPolicy Bypass -NonInteractive -File `"$LauncherPath`""

$existing = & $NssmExe status $ServiceName 2>&1
if ($existing -notmatch "The specified service does not exist") {
    Write-Log "Removing existing $ServiceName service..."
    & $NssmExe remove $ServiceName confirm 2>&1 | ForEach-Object { Write-Log $_ }
}

& $NssmExe install $ServiceName $PsExe $ServiceArgs
& $NssmExe set $ServiceName DisplayName "NexusQuant MT5 Adapter"
& $NssmExe set $ServiceName Description "FastAPI bridge exposing MetaTrader 5 over REST for NexusQuant AI"
& $NssmExe set $ServiceName Start SERVICE_AUTO_START
& $NssmExe set $ServiceName AppStdout "C:\nexusquant\logs\mt5_adapter_stdout.log"
& $NssmExe set $ServiceName AppStderr "C:\nexusquant\logs\mt5_adapter_stderr.log"
& $NssmExe set $ServiceName AppRotateFiles 1
& $NssmExe set $ServiceName AppRotateBytes 10485760   # rotate at 10MB
& $NssmExe set $ServiceName AppRestartDelay 5000       # wait 5s before restart

Write-Log "Service $ServiceName installed."

# 8. Create log directories and start service
New-Item -ItemType Directory -Force -Path "C:\nexusquant\logs" | Out-Null
New-Item -ItemType Directory -Force -Path "$RepoDir\logs"      | Out-Null
New-Item -ItemType Directory -Force -Path "$RepoDir\data"      | Out-Null

Write-Log "Starting service..."
& $NssmExe start $ServiceName 2>&1 | ForEach-Object { Write-Log $_ }

# 9. Install & configure Amazon CloudWatch Agent - tails the adapter's
# stdout/stderr (written by NSSM, step 7) into the pre-existing
# /nexusquant/mt5-adapter log group. No new IAM needed (already granted on
# /nexusquant/* for the bootstrap log group, step 10).
Write-Log "Installing Amazon CloudWatch Agent..."

$CwaInstallerPath = "C:\nexusquant\amazon-cloudwatch-agent.msi"
$CwaCtl = "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1"

if (-not (Test-Path $CwaCtl)) {
    if (Get-FileWithRetry -Url "https://amazoncloudwatch-agent.s3.amazonaws.com/windows/amd64/latest/amazon-cloudwatch-agent.msi" -OutFile $CwaInstallerPath) {
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$CwaInstallerPath`" /qn /norestart" -Wait -NoNewWindow
        Write-Log "CloudWatch Agent installed."
    } else {
        Write-Log "WARNING: CloudWatch Agent download failed after 3 attempts - adapter logs stay local-only at C:\nexusquant\logs\." "WARN"
    }
} else {
    Write-Log "CloudWatch Agent already installed, skipping."
}

if (Test-Path $CwaCtl) {
    # Log-only config; no metrics, no per-stream retention override (the
    # log group's own 90-day retention, set in Terraform, stays authoritative).
    $CwaConfig = @{
        logs = @{
            logs_collected = @{
                files = @{
                    collect_list = @(
                        @{ file_path = "C:\nexusquant\logs\mt5_adapter_stdout.log"; log_group_name = "/nexusquant/mt5-adapter"; log_stream_name = "{instance_id}-stdout"; timestamp_format = "%Y-%m-%dT%H:%M:%S%z" },
                        @{ file_path = "C:\nexusquant\logs\mt5_adapter_stderr.log"; log_group_name = "/nexusquant/mt5-adapter"; log_stream_name = "{instance_id}-stderr"; timestamp_format = "%Y-%m-%dT%H:%M:%S%z" }
                    )
                }
            }
        }
    }
    $CwaConfigPath = "C:\nexusquant\cloudwatch-agent-config.json"
    ($CwaConfig | ConvertTo-Json -Depth 6) | Set-Content -Path $CwaConfigPath -Encoding UTF8
    Write-Log "CloudWatch Agent config written to $CwaConfigPath"

    Write-Log "Applying CloudWatch Agent config and starting agent..."
    & powershell -ExecutionPolicy Bypass -File $CwaCtl -a fetch-config -m ec2 -c "file:$CwaConfigPath" -s 2>&1 |
        ForEach-Object { Write-Log $_ }
    & powershell -ExecutionPolicy Bypass -File $CwaCtl -a status -m ec2 2>&1 | ForEach-Object { Write-Log $_ }
} else {
    Write-Log "CloudWatch Agent ctl script not found at $CwaCtl - skipping config, adapter logs remain local-only." "WARN"
}

# 10. Send bootstrap log to CloudWatch Logs
Write-Log "Sending bootstrap log to CloudWatch..."
try {
    $LogGroupName  = "/nexusquant/ec2-bootstrap"
    $LogStreamName = "$(hostname)-$(Get-Date -Format 'yyyyMMdd')"

    aws logs create-log-stream `
        --log-group-name $LogGroupName `
        --log-stream-name $LogStreamName `
        --region "${aws_region}" 2>&1 | Out-Null

    $LogContent = Get-Content $LogFile -Raw
    $Events = @(@{
        timestamp = [long](([datetime]::UtcNow - [datetime]"1970-01-01").TotalMilliseconds)
        message   = $LogContent
    })

    aws logs put-log-events `
        --log-group-name $LogGroupName `
        --log-stream-name $LogStreamName `
        --log-events ($Events | ConvertTo-Json -Compress) `
        --region "${aws_region}" 2>&1 | Out-Null

    Write-Log "Bootstrap log uploaded to CloudWatch."
} catch {
    Write-Log "WARNING: could not upload bootstrap log to CloudWatch: $_" "WARN"
}

Write-Log "=== Bootstrap COMPLETE. MT5 terminal installed automatically - verify broker-server login/EULA acceptance via RDP/SSM if the adapter service does not connect on first start. ==="
</powershell>
