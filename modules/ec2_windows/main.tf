###############################################################################
# Module: ec2_windows — EC2 Windows Server 2022, IAM Role, SSM Native Bootstrap
###############################################################################

# --- AMI: latest Windows Server 2022 English Full Base ---
data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  effective_key_pair_name  = var.key_pair_name != "" ? var.key_pair_name : "${var.project_name}-ec2-windows-${var.environment}"
  effective_log_group_name = var.cloudwatch_log_group_name != "" ? var.cloudwatch_log_group_name : "/${var.project_name}/${var.environment}/mt5-adapter"
  ssm_prefix               = "/${var.project_name}/${var.environment}"
}

resource "tls_private_key" "ec2_windows" {
  count     = var.key_pair_name == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2_windows" {
  count      = var.key_pair_name == "" ? 1 : 0
  key_name   = local.effective_key_pair_name
  public_key = tls_private_key.ec2_windows[0].public_key_openssh

  tags = {
    Name        = local.effective_key_pair_name
    Environment = var.environment
    Project     = var.project_name
  }
}

# --- IAM Role for the EC2 instance ---
resource "aws_iam_role" "ec2_windows" {
  name = "${var.project_name}-ec2-windows-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Policy attachments: SSM Managed Instance Core & CloudWatch Agent Server Policy
resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.ec2_windows.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_windows.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Inline policy: read Secrets Manager + SSM + CloudWatch
resource "aws_iam_role_policy" "ec2_windows_inline" {
  name = "mt5-adapter-access"
  role = aws_iam_role.ec2_windows.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [
          var.secret_arn,
          "${var.secret_arn}*",
          "arn:aws:secretsmanager:${var.aws_region}:*:secret:*",
        ]
      },
      {
        Sid    = "SSMParameterRead"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParametersByPath"]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:*:parameter/${var.project_name}/*",
          "arn:aws:ssm:${var.aws_region}:*:parameter/*",
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/${var.project_name}/*"
      },
      {
        Sid      = "CloudWatchMetrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_windows" {
  name = "${var.project_name}-ec2-windows-profile-${var.environment}"
  role = aws_iam_role.ec2_windows.name
}

# --- CloudWatch Log Group ---
resource "aws_cloudwatch_log_group" "adapter" {
  name              = local.effective_log_group_name
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.project_name}-mt5-adapter-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# --- CloudWatch Agent Configuration in SSM Parameter Store ---
resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  name        = "/${var.project_name}/${var.environment}/cloudwatch-agent-config"
  description = "CloudWatch Agent configuration for MT5 Connector EC2 Windows"
  type        = "String"

  value = jsonencode({
    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path        = "C:\\nexusquant\\logs\\mt5_adapter_stdout.log"
              log_group_name   = aws_cloudwatch_log_group.adapter.name
              log_stream_name  = "{instance_id}-stdout"
              timestamp_format = "%Y-%m-%dT%H:%M:%S%z"
            },
            {
              file_path        = "C:\\nexusquant\\logs\\mt5_adapter_stderr.log"
              log_group_name   = aws_cloudwatch_log_group.adapter.name
              log_stream_name  = "{instance_id}-stderr"
              timestamp_format = "%Y-%m-%dT%H:%M:%S%z"
            },
            {
              file_path       = "C:\\nexusquant\\logs\\mt5_adapter.log"
              log_group_name  = aws_cloudwatch_log_group.adapter.name
              log_stream_name = "{instance_id}-app"
            }
          ]
        }
      }
    }
  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# --- EC2 Instance (Zero UserData: SSM Agent handles provisioning) ---
resource "aws_instance" "mt5_adapter" {
  ami                         = data.aws_ami.windows_2022.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.sg_windows_adapter_id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_windows.name
  key_name                    = var.key_pair_name != "" ? var.key_pair_name : aws_key_pair.ec2_windows[0].key_name
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 enforced
    http_put_response_hop_limit = 2
  }

  tags = {
    Name        = "${var.project_name}-mt5-adapter-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
    Role        = "mt5-adapter"
  }

  depends_on = [
    aws_cloudwatch_log_group.adapter
  ]
}

# --- SSM Associations: Native CloudWatch Agent Install & Configure ---

resource "aws_ssm_association" "install_cloudwatch_agent" {
  name = "AWS-ConfigureAWSPackage"

  parameters = {
    action = "Install"
    name   = "AmazonCloudWatchAgent"
  }

  targets {
    key    = "InstanceIds"
    values = [aws_instance.mt5_adapter.id]
  }

  depends_on = [
    aws_instance.mt5_adapter
  ]
}

resource "aws_ssm_association" "configure_cloudwatch_agent" {
  name = "AmazonCloudWatch-ManageAgent"

  parameters = {
    action                        = "configure"
    mode                          = "ec2"
    optionalRestart               = "yes"
    optionalConfigurationSource   = "ssm"
    optionalConfigurationLocation = aws_ssm_parameter.cloudwatch_agent_config.name
  }

  targets {
    key    = "InstanceIds"
    values = [aws_instance.mt5_adapter.id]
  }

  depends_on = [
    aws_ssm_association.install_cloudwatch_agent,
    aws_ssm_parameter.cloudwatch_agent_config
  ]
}

# --- SSM Document: Structured Multi-Step Bootstrap for MT5 Connector ---

resource "aws_ssm_document" "bootstrap" {
  name            = "${var.project_name}-mt5-bootstrap-${var.environment}"
  document_type   = "Command"
  document_format = "YAML"

    content = yamlencode({
    schemaVersion = "2.2"
    description   = "Bootstrap NexusQuant MT5 Connector on Windows Server 2022"
    parameters = {
      GitHubRepoUrl = {
        type        = "String"
        description = "Git clone URL of the MT5 Connector repo"
        default     = var.github_repo_url
      }
      RepoBranch = {
        type        = "String"
        description = "Branch to checkout"
        default     = var.repo_branch
      }
      Mt5InstallerUrl = {
        type        = "String"
        description = "Download URL for MetaTrader 5 setup"
        default     = var.mt5_installer_url
      }
      SecretName = {
        type        = "String"
        description = "Secrets Manager secret name"
        default     = var.secret_name
      }
      SsmPrefix = {
        type        = "String"
        description = "Prefix for SSM parameters"
        default     = local.ssm_prefix
      }
      AwsRegion = {
        type        = "String"
        description = "AWS region"
        default     = var.aws_region
      }
    }
    mainSteps = [
      {
        action = "aws:runPowerShellScript"
        name   = "InstallPrerequisites"
        inputs = {
          runCommand = [
            "$ErrorActionPreference = 'Stop'",
            "Write-Host '=== Step 1: Installing Prerequisites ==='",
            "New-Item -ItemType Directory -Force -Path 'C:\\nexusquant', 'C:\\nexusquant\\logs' | Out-Null",
            "if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {",
            "    Set-ExecutionPolicy Bypass -Scope Process -Force",
            "    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12",
            "    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))",
            "    $env:PATH += ';C:\\ProgramData\\chocolatey\\bin'",
            "}",
            "choco install python312 git awscli --yes --no-progress",
            "$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'User')",
            "python --version",
            "git --version"
          ]
        }
      },
      {
        action = "aws:runPowerShellScript"
        name   = "InstallMetaTrader5Terminal"
        inputs = {
          runCommand = [
            "$ErrorActionPreference = 'Stop'",
            "Write-Host '=== Step 2: Installing MetaTrader 5 Terminal ==='",
            "$TerminalExe = 'C:\\Program Files\\MetaTrader 5\\terminal64.exe'",
            "if (Test-Path $TerminalExe) {",
            "    Write-Host 'MetaTrader 5 terminal already installed, skipping.'",
            "    exit 0",
            "}",
            "$InstallerPath = 'C:\\nexusquant\\mt5setup.exe'",
            "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12",
            "Invoke-WebRequest -Uri '{{ Mt5InstallerUrl }}' -OutFile $InstallerPath -UseBasicParsing",
            "Start-Process -FilePath $InstallerPath -ArgumentList '/auto' -Wait -NoNewWindow",
            "$waited = 0",
            "while ((-not (Test-Path $TerminalExe)) -and ($waited -lt 180)) {",
            "    Start-Sleep -Seconds 5",
            "    $waited += 5",
            "}",
            "if (-not (Test-Path $TerminalExe)) { throw 'MT5 installation did not produce terminal64.exe within 180s.' }",
            "Write-Host 'MetaTrader 5 installed successfully.'",
            "Get-Process -Name 'terminal64' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue"
          ]
        }
      },
      {
        action = "aws:runPowerShellScript"
        name   = "CloneOrUpdateRepository"
        inputs = {
          runCommand = [
            "$ErrorActionPreference = 'Stop'",
            "Write-Host '=== Step 3: Cloning/Updating MT5 Connector Repository ==='",
            "$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'User')",
            "$env:GIT_TERMINAL_PROMPT = '0'",
            "$RepoDir = 'C:\\nexusquant\\NexusQuant-MT5-Connector'",
            "try {",
            "    $SecretJson = aws secretsmanager get-secret-value --secret-id '{{ SecretName }}' --region '{{ AwsRegion }}' --query SecretString --output text",
            "    $Secrets = $SecretJson | ConvertFrom-Json",
            "    $GitHubToken = $Secrets.GITHUB_TOKEN",
            "} catch { Write-Host 'Notice: proceeding without GitHub token: ' $_ }",
            "$CloneUrl = '{{ GitHubRepoUrl }}'",
            "if ($GitHubToken) {",
            "    $CloneUrl = $CloneUrl -replace 'https://', ('https://x-access-token:' + $GitHubToken + '@')",
            "}",
            "if ((Test-Path $RepoDir) -and (-not (Test-Path \"$RepoDir\\.git\"))) {",
            "    Remove-Item -Path $RepoDir -Recurse -Force",
            "}",
            "if (-not (Test-Path \"$RepoDir\\.git\")) {",
            "    Write-Host 'Cloning repository...'",
            "    git clone --branch '{{ RepoBranch }}' $CloneUrl $RepoDir",
            "} else {",
            "    Write-Host 'Updating repository from origin {{ RepoBranch }}...'",
            "    Push-Location $RepoDir",
            "    git remote set-url origin $CloneUrl",
            "    git fetch origin '{{ RepoBranch }}'",
            "    git reset --hard \"origin/{{ RepoBranch }}\"",
            "    Pop-Location",
            "}",
            "Write-Host 'Repository ready at' $RepoDir"
          ]
        }
      },
      {
        action = "aws:runPowerShellScript"
        name   = "SetupPythonVirtualenv"
        inputs = {
          runCommand = [
            "$ErrorActionPreference = 'Stop'",
            "Write-Host '=== Step 4: Setting up Python Virtualenv ==='",
            "$RepoDir = 'C:\\nexusquant\\NexusQuant-MT5-Connector'",
            "Push-Location $RepoDir",
            "if (-not (Test-Path '.venv')) { python -m venv .venv }",
            "& '.\\.venv\\Scripts\\python.exe' -m pip install --upgrade pip",
            "& '.\\.venv\\Scripts\\python.exe' -m pip install -e .",
            "New-Item -ItemType Directory -Force -Path 'logs', 'data' | Out-Null",
            "Pop-Location",
            "Write-Host 'Virtualenv and dependencies ready.'"
          ]
        }
      },
      {
        action = "aws:runPowerShellScript"
        name   = "ConfigureFirewall"
        inputs = {
          runCommand = [
            "$ErrorActionPreference = 'Stop'",
            "Write-Host '=== Step 5: Configuring Firewall ==='",
            "if (-not (Get-NetFirewallRule -DisplayName 'NexusQuant MT5 Adapter (8100)' -ErrorAction SilentlyContinue)) {",
            "    New-NetFirewallRule -DisplayName 'NexusQuant MT5 Adapter (8100)' -Direction Inbound -Protocol TCP -LocalPort 8100 -Action Allow | Out-Null",
            "}",
            "Write-Host 'Firewall rule for TCP 8100 ensured (inbound access is still gated by the EC2 Security Group).'"
          ]
        }
      },
      {
        action = "aws:runPowerShellScript"
        name   = "WriteAdapterLauncherScript"
        inputs = {
          runCommand = [
            "$ErrorActionPreference = 'Stop'",
            "Write-Host '=== Step 6: Writing Adapter Launcher Script ==='",
            "$RepoDir = 'C:\\nexusquant\\NexusQuant-MT5-Connector'",
            "$LauncherPath = \"$RepoDir\\fetch_secrets.ps1\"",
            "$LauncherContent = @\"",
            "#Requires -Version 5.1",
            "Set-StrictMode -Version Latest",
            "`$ErrorActionPreference = 'Stop'",
            "`$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'User')",
            "`$AwsCli = if (Test-Path 'C:\\Program Files\\Amazon\\AWSCLIV2\\aws.exe') { 'C:\\Program Files\\Amazon\\AWSCLIV2\\aws.exe' } else { 'aws' }",
            "`$Region = '{{ AwsRegion }}'",
            "`$SecretName = '{{ SecretName }}'",
            "`$SsmPrefix = '{{ SsmPrefix }}'",
            "`$RepoDir = '$RepoDir'",
            "function Set-EnvVar { param([string]`$Name, [string]`$Value) [System.Environment]::SetEnvironmentVariable(`$Name, `$Value, 'Process') }",
            "try {",
            "    `$SecretJson = & `$AwsCli secretsmanager get-secret-value --secret-id `$SecretName --region `$Region --query SecretString --output text",
            "    `$Secrets = `$SecretJson | ConvertFrom-Json",
            "    Set-EnvVar 'ADAPTER_API_KEY' `$Secrets.ADAPTER_API_KEY",
            "    Set-EnvVar 'MT5_PASSWORD'    `$Secrets.MT5_PASSWORD",
            "    Set-EnvVar 'POSTGRES_URL'    `$Secrets.POSTGRES_URL",
            "    Set-EnvVar 'DATABASE_URL'    `$Secrets.POSTGRES_URL",
            "} catch { Write-Host 'Error loading secrets: ' `$_; exit 1 }",
            "try {",
            "    `$SsmParams = & `$AwsCli ssm get-parameters-by-path --path `$SsmPrefix --region `$Region --query 'Parameters[*].{Name:Name,Value:Value}' --output json | ConvertFrom-Json",
            "    foreach (`$p in `$SsmParams) { Set-EnvVar (`$p.Name.Split('/')[-1]) `$p.Value }",
            "} catch { Write-Host 'Error loading SSM params: ' `$_; exit 1 }",
            "Set-EnvVar 'AWS_EXECUTION_ENV' 'true'",
            "`$env:PYTHONPATH = \"`$RepoDir\\src\"",
            "Set-Location `$RepoDir",
            "& \"`$RepoDir\\.venv\\Scripts\\python.exe\" -m presentation.main *>> 'C:\\nexusquant\\logs\\mt5_adapter_stdout.log'",
            "\"@",
            "Set-Content -Path $LauncherPath -Value $LauncherContent -Encoding UTF8",
            "Write-Host 'Launcher script written to' $LauncherPath"
          ]
        }
      },
      {
        action = "aws:runPowerShellScript"
        name   = "ConfigureAutoLogonAndScheduledTasks"
        inputs = {
          runCommand = [
            "$ErrorActionPreference = 'Stop'",
            "Write-Host '=== Step 7: Configuring Interactive Auto-Logon and Scheduled Tasks (Session 0 fix) ==='",
            "$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'User')",
            "$RepoDir = 'C:\\nexusquant\\NexusQuant-MT5-Connector'",
            "$LauncherPath = \"$RepoDir\\fetch_secrets.ps1\"",
            "$PsExe = 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe'",
            "$NssmExe = 'C:\\ProgramData\\chocolatey\\bin\\nssm.exe'",
            "$existingSvc = Get-Service -Name 'MT5Adapter' -ErrorAction SilentlyContinue",
            "if ($existingSvc) {",
            "    Write-Host 'Removing legacy NSSM service...'",
            "    Stop-Service -Name 'MT5Adapter' -Force -ErrorAction SilentlyContinue",
            "    if (Test-Path $NssmExe) { & $NssmExe remove MT5Adapter confirm }",
            "}",
            "Get-Process -Name 'terminal64' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue",
            "Get-Process -Name 'powershell', 'python' -ErrorAction SilentlyContinue | Where-Object { $_.Path -like 'C:\\nexusquant\\*' } | Stop-Process -Force -ErrorAction SilentlyContinue",
            "Start-Sleep -Seconds 2",
            "try {",
            "    $SecretJson = aws secretsmanager get-secret-value --secret-id '{{ SecretName }}' --region '{{ AwsRegion }}' --query SecretString --output text",
            "    $Secrets = $SecretJson | ConvertFrom-Json",
            "    $WinUser = $Secrets.WINDOWS_ADMIN_USER",
            "    $WinPass = $Secrets.WINDOWS_ADMIN_PASSWORD",
            "} catch { Write-Host 'ERROR loading Windows admin credentials: ' $_; exit 1 }",
            "$WinLogonKey = 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon'",
            "Set-ItemProperty $WinLogonKey 'AutoAdminLogon' -Value '1'",
            "Set-ItemProperty $WinLogonKey 'DefaultUsername' -Value $WinUser",
            "Set-ItemProperty $WinLogonKey 'DefaultPassword' -Value $WinPass",
            "Set-ItemProperty $WinLogonKey 'DefaultDomainName' -Value $env:COMPUTERNAME",
            "$trigger = New-ScheduledTaskTrigger -AtLogOn -User $WinUser",
            "$principal = New-ScheduledTaskPrincipal -UserId $WinUser -LogonType Interactive -RunLevel Highest",
            "Unregister-ScheduledTask -TaskName 'MT5Terminal' -Confirm:$false -ErrorAction SilentlyContinue",
            "Unregister-ScheduledTask -TaskName 'MT5AdapterTask' -Confirm:$false -ErrorAction SilentlyContinue",
            "$settingsTerminal = New-ScheduledTaskSettingsSet -Hidden:$false -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries",
            "$actionTerminal = New-ScheduledTaskAction -Execute 'C:\\Program Files\\MetaTrader 5\\terminal64.exe'",
            "Register-ScheduledTask -TaskName 'MT5Terminal' -Action $actionTerminal -Trigger $trigger -Principal $principal -Settings $settingsTerminal | Out-Null",
            "$actionAdapter = New-ScheduledTaskAction -Execute $PsExe -Argument \"-ExecutionPolicy Bypass -NonInteractive -File `\"$LauncherPath`\"\"",
            "Register-ScheduledTask -TaskName 'MT5AdapterTask' -Action $actionAdapter -Trigger $trigger -Principal $principal | Out-Null",
            "Write-Host 'Auto-logon and Scheduled Tasks configured. Proceeding to reboot in the next step.'"
          ]
        }
      },
      {
        action = "aws:runPowerShellScript"
        name   = "RebootInstance"
        inputs = {
          runCommand = [
            "Write-Host '=== Step 8: Rebooting instance to activate Auto-Logon and Scheduled Tasks ==='",
            "Write-Host 'Exiting with code 3010: SSM Agent will reboot the instance and resume this document automatically after restart.'",
            "exit 3010"
          ]
        }
      },
      {
        action = "aws:runPowerShellScript"
        name   = "VerifyAdapterHealth"
        inputs = {
          runCommand = [
            "$ErrorActionPreference = 'Stop'",
            "Write-Host '=== Step 9: Verifying MT5 Terminal and Adapter After Reboot ==='",
            "$MaxWaitSeconds = 180",
            "$PollIntervalSeconds = 5",
            "$Elapsed = 0",
            "$TerminalUp = $false",
            "$PortListening = $false",
            "$HealthOk = $false",
            "while ($Elapsed -lt $MaxWaitSeconds) {",
            "    Start-Sleep -Seconds $PollIntervalSeconds",
            "    $Elapsed += $PollIntervalSeconds",
            "    if (-not $TerminalUp) {",
            "        if (Get-Process -Name 'terminal64' -ErrorAction SilentlyContinue) {",
            "            $TerminalUp = $true",
            "            Write-Host 'terminal64.exe process detected (running interactively via Scheduled Task).'",
            "        }",
            "    }",
            "    if (-not $PortListening) {",
            "        if (Get-NetTCPConnection -LocalPort 8100 -State Listen -ErrorAction SilentlyContinue) {",
            "            $PortListening = $true",
            "            Write-Host 'TCP port 8100 is listening.'",
            "        }",
            "    }",
            "    if ($PortListening -and (-not $HealthOk)) {",
            "        try {",
            "            $resp = Invoke-RestMethod -Uri 'http://localhost:8100/api/v1/health' -Method Get -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop",
            "            if ($resp.status -eq 'ok' -and $resp.mt5_connected -eq $true) {",
            "                Write-Host \"Health check verified: status=$($resp.status), mt5_connected=$($resp.mt5_connected)\"",
            "                $HealthOk = $true",
            "            } else {",
            "                Write-Host \"Health check pending: status=$($resp.status), mt5_connected=$($resp.mt5_connected)\"",
            "            }",
            "        } catch { Write-Host \"Waiting for HTTP health response: $($_.Exception.Message)\" }",
            "    }",
            "    if ($TerminalUp -and $HealthOk) { break }",
            "}",
            "if (-not $TerminalUp) { Write-Warning 'terminal64.exe was NOT detected running after reboot within timeout — check Scheduled Task MT5Terminal and the auto-logon registry keys.' }",
            "if (-not $PortListening) { Write-Warning 'Adapter did NOT bind to TCP port 8100 within timeout — check Scheduled Task MT5AdapterTask and C:\\nexusquant\\logs\\mt5_adapter_stdout.log.' }",
            "if (-not $HealthOk) {",
            "    Write-Warning 'mt5_connected was not confirmed true. NOTE: this reflects the terminal login/connection state, not the AutoTrading toggle — that still requires one manual click on the terminal after this first post-fix boot.'",
            "    Write-Host 'Recent adapter stdout log:'",
            "    Get-Content -Path 'C:\\nexusquant\\logs\\mt5_adapter_stdout.log' -Tail 30 -ErrorAction SilentlyContinue | Write-Host",
            "} else {",
            "    Write-Host 'SUCCESS: terminal64.exe running interactively, Adapter listening on 8100, MT5 connected. Remember: AutoTrading itself still needs one manual click on this first boot after the fix.'",
            "}"
          ]
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# --- SSM Association: Execute MT5 Bootstrap on EC2 Instance ---

resource "aws_ssm_association" "bootstrap" {
  name = aws_ssm_document.bootstrap.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.mt5_adapter.id]
  }

  parameters = {
    GitHubRepoUrl   = var.github_repo_url
    RepoBranch      = var.repo_branch
    Mt5InstallerUrl = var.mt5_installer_url
    SecretName      = var.secret_name
    SsmPrefix       = local.ssm_prefix
    AwsRegion       = var.aws_region
  }

  depends_on = [
    aws_instance.mt5_adapter,
    aws_ssm_association.configure_cloudwatch_agent
  ]
}
