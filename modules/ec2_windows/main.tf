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
    "common.ps1" = replace(file("${path.module}/scripts/common.ps1"), "\r", "")
    "start.ps1"  = replace(file("${path.module}/scripts/start.ps1"), "\r", "")
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

# --- Secrets Manager: private key PEM for the auto-generated key pair ---
# Only created when Terraform manages the key pair itself (key_pair_name == "").
# recovery_window_in_days is controlled by var.private_key_secret_recovery_window_days
# so the secret can be force-deleted immediately when the key pair is recreated.
resource "aws_secretsmanager_secret" "ec2_windows_private_key" {
  count                   = var.key_pair_name == "" ? 1 : 0
  name                    = "/${var.project_name}/${var.environment}/ec2-windows/private-key"
  description             = "PEM private key for the auto-generated EC2 Windows (MT5 Adapter) key pair '${local.effective_key_pair_name}'."
  recovery_window_in_days = var.private_key_secret_recovery_window_days

  tags = {
    Name        = "${var.project_name}-ec2-windows-private-key-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_secretsmanager_secret_version" "ec2_windows_private_key" {
  count         = var.key_pair_name == "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.ec2_windows_private_key[0].id
  secret_string = tls_private_key.ec2_windows[0].private_key_pem
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
        Sid      = "SecretsManagerRead"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
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
              file_path       = "C:\\nexusquant\\logs\\start.log"
              log_group_name  = aws_cloudwatch_log_group.adapter.name
              log_stream_name = "{instance_id}-start"
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

  # Needed so Terraform can decrypt the EC2-generated local Administrator
  # password below (get_password_data exposes the encrypted blob; it stays
  # encrypted at rest in state — only the decrypted local value derived from
  # it is written out, into its own Secrets Manager secret).
  get_password_data = true

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

# --- Secrets Manager: decrypted local Administrator password ---
# EC2 assigns a fresh random Administrator password to every new Windows
# instance and only exposes it encrypted with the launch key pair's public
# key. Whenever this instance (or just the key pair) is recreated, that
# password changes and any previously stored value goes stale — which is
# exactly the failure mode of relying on a fixed tfvars password for
# AutoAdminLogon. Terraform decrypts it here with the private key it already
# holds in state (rsadecrypt), so the value used below is always the
# instance's real, current password with no manual "RDP in with the
# console-decrypted password and reset it by hand" step required.
locals {
  # AWS only starts returning GetPasswordData once EC2Launch has generated it
  # inside the guest, which can lag a few minutes behind instance creation.
  # It's also a known AWS-provider quirk that flipping get_password_data on
  # an ALREADY-EXISTING instance (rather than at Create time, which has its
  # own wait/retry loop) does not always refresh password_data within that
  # same apply — the attribute can still read back as "" once. Guard on that
  # here instead of feeding an empty string into rsadecrypt(), which fails
  # with an opaque "crypto/rsa: decryption error." Re-running `terraform
  # apply` a second time resolves it: by then the resource has been
  # refreshed and password_data is populated.
  windows_password_data_ready      = aws_instance.mt5_adapter.password_data != ""
  effective_windows_admin_password = var.key_pair_name == "" ? (
    local.windows_password_data_ready
    ? rsadecrypt(aws_instance.mt5_adapter.password_data, tls_private_key.ec2_windows[0].private_key_pem)
    : null
  ) : var.windows_admin_password_override
}

resource "aws_secretsmanager_secret" "windows_admin_password" {
  count                   = var.key_pair_name == "" ? 1 : 0
  name                    = "/${var.project_name}/${var.environment}/ec2-windows/admin-password"
  description             = "Current local Administrator password for the Windows EC2 instance, decrypted by Terraform from the instance's EC2-generated password data. Refreshes automatically whenever the instance or key pair is recreated."
  recovery_window_in_days = var.private_key_secret_recovery_window_days

  tags = {
    Name        = "${var.project_name}-ec2-windows-admin-password-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_secretsmanager_secret_version" "windows_admin_password" {
  count         = var.key_pair_name == "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.windows_admin_password[0].id
  secret_string = var.key_pair_name == "" ? coalesce(local.effective_windows_admin_password, "pending-terraform-apply") : var.windows_admin_password_override

  lifecycle {
    precondition {
      condition     = var.key_pair_name != "" || local.windows_password_data_ready
      error_message = "EC2 has not published the Windows password data for this instance yet (password_data is still empty) — this is normal for a minute or two after get_password_data is first enabled or after the instance is recreated. Re-run 'terraform apply' again; it resolves itself once AWS finishes generating it."
    }
  }
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

  # Retries on a fixed cadence rather than only once at creation. Terraform's
  # depends_on below only orders resource CREATION in the AWS API — it does not
  # wait for the SSM Agent to actually check in and finish installing the
  # package on a freshly launched instance, so the very first run of the
  # "configure" association below can race ahead of this one and fail with
  # "CloudWatch Agent not installed". The schedule makes both associations
  # self-heal on the next pass once the agent has had time to come online.
  schedule_expression = "rate(30 minutes)"

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

  # See the comment on install_cloudwatch_agent: this recurring schedule is
  # what actually recovers from the "ControlCloudWatchAgentWindows: CloudWatch
  # Agent not installed" failure seen right after a fresh instance boot — the
  # next scheduled run (at most 30 min later) succeeds once the package
  # install above has completed, no manual retry needed.
  schedule_expression = "rate(30 minutes)"

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
            "$env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'User')",
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
        name   = "RemoveLegacyAutomation"
        inputs = {
          runCommand = [
            "$ErrorActionPreference = 'Continue'",
            "Write-Host '=== Step 6: Removing legacy auto-logon / scheduled tasks / supervisor scripts, if present ==='",
            "foreach ($t in 'MT5Watchdog', 'MT5AdapterTask', 'MT5Terminal') { Stop-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue }",
            "Get-Process -Name 'terminal64' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue",
            "Get-CimInstance -ClassName Win32_Process -Filter \"Name = 'python.exe'\" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*presentation.main*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }",
            "$WinLogonKey = 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon'",
            "Remove-ItemProperty -Path $WinLogonKey -Name 'AutoAdminLogon' -ErrorAction SilentlyContinue",
            "Remove-ItemProperty -Path $WinLogonKey -Name 'DefaultPassword' -ErrorAction SilentlyContinue",
            "Remove-Item -Path 'C:\\nexusquant\\bin\\watchdog.ps1', 'C:\\nexusquant\\bin\\run-adapter.ps1', 'C:\\nexusquant\\bin\\start-terminal.ps1' -Force -ErrorAction SilentlyContinue",
            "Write-Host 'Legacy automation removed (if it was present). AutoAdminLogon disabled; the plaintext DefaultPassword registry value has been cleared.'"
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
              "Write-Host '=== Step 7: Writing runtime scripts (common.ps1, start.ps1) ==='",
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
        name   = "BootstrapComplete"
        inputs = {
          runCommand = [
            "Write-Host '=== Step 8: Bootstrap complete ==='",
            "Write-Host 'Python, git and the MetaTrader 5 terminal are installed; the connector repo and its virtualenv are ready at C:\\nexusquant\\NexusQuant-MT5-Connector.'",
            "Write-Host 'Nothing starts automatically. RDP into the instance and run C:\\nexusquant\\bin\\start.ps1 — it loads the required secrets/config and starts the MT5 terminal and the adapter for you.'"
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
    aws_ssm_association.configure_cloudwatch_agent,
    aws_secretsmanager_secret_version.windows_admin_password
  ]
}
