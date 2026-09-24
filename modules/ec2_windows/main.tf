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

  # Runtime PowerShell scripts deployed to C:\nexusquant\bin by the bootstrap document.
  # CRs are stripped so the here-string embedding is identical regardless of the checkout EOL.
  runtime_scripts = {
    "common.ps1"         = replace(file("${path.module}/scripts/common.ps1"), "\r", "")
    "start-terminal.ps1" = replace(file("${path.module}/scripts/start-terminal.ps1"), "\r", "")
    "run-adapter.ps1"    = replace(file("${path.module}/scripts/run-adapter.ps1"), "\r", "")
    "watchdog.ps1"       = replace(file("${path.module}/scripts/watchdog.ps1"), "\r", "")
  }
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
        Resource = [var.secret_arn]
      },
      {
        Sid    = "SSMParameterRead"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParametersByPath"]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:*:parameter${local.ssm_prefix}",
          "arn:aws:ssm:${var.aws_region}:*:parameter${local.ssm_prefix}/*",
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
        Condition = {
          StringEquals = { "cloudwatch:namespace" = "NexusQuant/MT5" }
        }
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
            },
            {
              file_path       = "C:\\nexusquant\\logs\\terminal-supervisor.log"
              log_group_name  = aws_cloudwatch_log_group.adapter.name
              log_stream_name = "{instance_id}-terminal-supervisor"
            },
            {
              file_path       = "C:\\nexusquant\\logs\\adapter-supervisor.log"
              log_group_name  = aws_cloudwatch_log_group.adapter.name
              log_stream_name = "{instance_id}-adapter-supervisor"
            },
            {
              file_path       = "C:\\nexusquant\\logs\\watchdog.log"
              log_group_name  = aws_cloudwatch_log_group.adapter.name
              log_stream_name = "{instance_id}-watchdog"
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
    volume_size           = var.root_volume_size_gb
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

  # A newer "most_recent" Windows AMI must never trigger a replacement of a configured instance
  # (installed terminal, broker login, scheduled tasks). Patch the OS in place instead.
  lifecycle {
    ignore_changes = [ami]
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
            "try { $max = (Get-PartitionSupportedSize -DriveLetter C).SizeMax; Resize-Partition -DriveLetter C -Size $max -ErrorAction Stop; Write-Host 'C: extended to the full volume size.' } catch { Write-Host 'C: resize skipped (already at max size or not needed).' }",
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
        name   = "WriteRuntimeScripts"
        inputs = {
          runCommand = concat(
            [
              "$ErrorActionPreference = 'Stop'",
              "Write-Host '=== Step 6: Writing runtime scripts (terminal supervisor, adapter supervisor, watchdog) ==='",
              "New-Item -ItemType Directory -Force -Path 'C:\\nexusquant\\bin', 'C:\\nexusquant\\logs', 'C:\\nexusquant\\mt5' | Out-Null",
              "$cfg = ConvertTo-Json -InputObject @{ Region = '{{ AwsRegion }}'; SecretName = '{{ SecretName }}'; SsmPrefix = '{{ SsmPrefix }}'; Environment = '${var.environment}'; Project = '${var.project_name}' }",
              "Set-Content -Path 'C:\\nexusquant\\bin\\config.json' -Value $cfg -Encoding ASCII",
            ],
            flatten([
              for script_name, script_body in local.runtime_scripts : concat(
                ["$body = @'"],
                split("\n", script_body),
                ["'@", "Set-Content -Path 'C:\\nexusquant\\bin\\${script_name}' -Value $body -Encoding UTF8"]
              )
            ]),
            [
              "Remove-Item -Path 'C:\\nexusquant\\NexusQuant-MT5-Connector\\fetch_secrets.ps1' -Force -ErrorAction SilentlyContinue",
              "Write-Host 'Runtime scripts written to C:\\nexusquant\\bin'"
            ]
          )
        }
      },
      {
        action = "aws:runPowerShellScript"
        name   = "ConfigureAutoLogonAndScheduledTasks"
        inputs = {
          runCommand = [
            "$ErrorActionPreference = 'Stop'",
            "Write-Host '=== Step 7: Auto-logon and supervised Scheduled Tasks (terminal, adapter, watchdog) ==='",
            "$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'User')",
            "$PsExe = 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe'",
            "$NssmExe = 'C:\\ProgramData\\chocolatey\\bin\\nssm.exe'",
            "if (Get-Service -Name 'MT5Adapter' -ErrorAction SilentlyContinue) {",
            "    Write-Host 'Removing legacy NSSM service...'",
            "    Stop-Service -Name 'MT5Adapter' -Force -ErrorAction SilentlyContinue",
            "    if (Test-Path $NssmExe) { & $NssmExe remove MT5Adapter confirm }",
            "}",
            "foreach ($t in 'MT5Watchdog', 'MT5AdapterTask', 'MT5Terminal') { Stop-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue }",
            "Get-Process -Name 'terminal64' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue",
            "Get-CimInstance -ClassName Win32_Process -Filter \"Name = 'python.exe'\" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*presentation.main*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }",
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
            "# Interactive tasks: no execution time limit (the default is 72h), automatic restart on failure.",
            "$logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $WinUser",
            "$userPrincipal = New-ScheduledTaskPrincipal -UserId $WinUser -LogonType Interactive -RunLevel Highest",
            "$userSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)",
            "foreach ($t in 'MT5Terminal', 'MT5AdapterTask', 'MT5Watchdog') { Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue }",
            "$terminalAction = New-ScheduledTaskAction -Execute $PsExe -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\\nexusquant\\bin\\start-terminal.ps1\"'",
            "Register-ScheduledTask -TaskName 'MT5Terminal' -Action $terminalAction -Trigger $logonTrigger -Principal $userPrincipal -Settings $userSettings | Out-Null",
            "$adapterAction = New-ScheduledTaskAction -Execute $PsExe -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\\nexusquant\\bin\\run-adapter.ps1\"'",
            "Register-ScheduledTask -TaskName 'MT5AdapterTask' -Action $adapterAction -Trigger $logonTrigger -Principal $userPrincipal -Settings $userSettings | Out-Null",
            "# Watchdog: every minute as SYSTEM (independent of the interactive session).",
            "$watchdogTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)",
            "$watchdogPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest",
            "$watchdogSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)",
            "$watchdogAction = New-ScheduledTaskAction -Execute $PsExe -Argument '-NoProfile -ExecutionPolicy Bypass -File \"C:\\nexusquant\\bin\\watchdog.ps1\"'",
            "Register-ScheduledTask -TaskName 'MT5Watchdog' -Action $watchdogAction -Trigger $watchdogTrigger -Principal $watchdogPrincipal -Settings $watchdogSettings | Out-Null",
            "Write-Host 'Auto-logon and Scheduled Tasks (MT5Terminal, MT5AdapterTask, MT5Watchdog) configured.'"
          ]
        }
      },
      {
        action = "aws:runPowerShellScript"
        name   = "StartOrRebootInstance"
        inputs = {
          runCommand = [
            "$ErrorActionPreference = 'Stop'",
            "Write-Host '=== Step 8: Start tasks now if the interactive session exists, otherwise reboot once ==='",
            "$WinLogonKey = 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon'",
            "$WinUser = (Get-ItemProperty $WinLogonKey).DefaultUsername",
            "$hasSession = [bool](quser 2>$null | Select-String -SimpleMatch $WinUser)",
            "if ($hasSession) {",
            "    Write-Host 'Interactive session already present: starting tasks without a reboot (no reboot loop on association re-runs).'",
            "    Start-ScheduledTask -TaskName 'MT5Terminal'",
            "    Start-ScheduledTask -TaskName 'MT5AdapterTask'",
            "    Start-ScheduledTask -TaskName 'MT5Watchdog'",
            "    exit 0",
            "}",
            "Write-Host 'No interactive session yet: exiting with code 3010 so SSM Agent reboots the instance and resumes this document after restart.'",
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
            "if (-not $TerminalUp) { Write-Warning 'terminal64.exe was NOT detected running after reboot within timeout — check Scheduled Task MT5Terminal, terminal-supervisor.log and the auto-logon registry keys.' }",
            "if (-not $PortListening) { Write-Warning 'Adapter did NOT bind to TCP port 8100 within timeout — check Scheduled Task MT5AdapterTask and C:\\nexusquant\\logs\\mt5_adapter_stdout.log.' }",
            "if (-not $HealthOk) {",
            "    Write-Warning 'mt5_connected was not confirmed true. AutoTrading is enabled by the startup config (see C:\\nexusquant\\logs\\terminal-supervisor.log and the watchdog log).'",
            "    Write-Host 'Recent adapter stdout log:'",
            "    Get-Content -Path 'C:\\nexusquant\\logs\\mt5_adapter_stdout.log' -Tail 30 -ErrorAction SilentlyContinue | Write-Host",
            "} else {",
            "    Write-Host 'SUCCESS: terminal64.exe running interactively, Adapter listening on 8100, MT5 connected.'",
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

resource "aws_ssm_document" "reboot_verify" {
  name            = "${var.project_name}-mt5-reboot-verify-${var.environment}"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "ONE-OFF: reboot the MT5 Adapter EC2 instance and verify Terminal + Adapter come up interactively. Invoke manually via 'aws ssm send-command'. Do NOT create an aws_ssm_association for this document — Associations re-apply on every SSM Agent restart (i.e. every reboot), and since this document itself reboots the instance, an association would cause an infinite reboot loop."
    parameters    = {}
    mainSteps = [
      {
        action = "aws:runPowerShellScript"
        name   = "RebootInstance"
        inputs = {
          runCommand = [
            "Write-Host '=== Rebooting instance to activate Auto-Logon and Scheduled Tasks ==='",
            "Write-Host 'Exiting with code 3010: SSM Agent will reboot the instance and resume this SAME command invocation automatically after restart.'",
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
            "Write-Host '=== Verifying MT5 Terminal and Adapter After Reboot ==='",
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
            "if (-not $TerminalUp) { Write-Warning 'terminal64.exe was NOT detected running after reboot within timeout.' }",
            "if (-not $PortListening) { Write-Warning 'Adapter did NOT bind to TCP port 8100 within timeout.' }",
            "if (-not $HealthOk) {",
            "    Write-Warning 'mt5_connected was not confirmed true. AutoTrading is enabled by the startup config (check terminal-supervisor.log).'",
            "    Get-Content -Path 'C:\\nexusquant\\logs\\mt5_adapter_stdout.log' -Tail 30 -ErrorAction SilentlyContinue | Write-Host",
            "} else {",
            "    Write-Host 'SUCCESS: terminal64.exe running interactively, Adapter listening on 8100, MT5 connected.'",
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
