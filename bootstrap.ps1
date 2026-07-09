param(
  [string[]]$Step,
  [string[]]$SkipStep,
  [switch]$ListSteps,
  [Alias('h')][switch]$Help,
  [switch]$ConvenienceAck
)

if ($env:BOOTSTRAP_CONVENIENCE_MODE -eq "1") {
  Write-Warning "Convenience mode lowers transport integrity guarantees. Prefer pinned download + verify."
}

$ErrorActionPreference = "Stop"

# ----------------------------------------
# Output and validation helpers
# ----------------------------------------

function Fail([string]$Message) {
  throw $Message
}

function Add-PathEntry([string]$PathEntry) {
  if ([string]::IsNullOrWhiteSpace($PathEntry)) {
    return
  }

  $entries = $env:Path -split ';'
  if ($entries -notcontains $PathEntry) {
    $env:Path = "$PathEntry;$env:Path"
  }
}

function Refresh-EnvPath {
  $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
  $userPath    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = "$machinePath;$userPath"
}

function Show-Help {
  @"
Usage:
  ./bootstrap.ps1 [-ConvenienceAck] [-Step <name[]> | -SkipStep <name[]>] [-ListSteps] [-Help]

Behavior:
  - No step parameters: runs full default flow (git -> ssh -> aqua -> task -> apm)
  - -Step: run only specified steps in provided order
  - -SkipStep: run default flow except skipped steps

Options:
  -Step <name[]>        Step names: git, ssh, aqua, task, apm
  -SkipStep <name[]>    Step names: git, ssh, aqua, task, apm
  -ListSteps            Print valid step names and exit
  -ConvenienceAck       Required when BOOTSTRAP_CONVENIENCE_MODE=1
  -Help, -h             Show this help and exit

Examples:
  ./bootstrap.ps1
  ./bootstrap.ps1 -Step ssh
  ./bootstrap.ps1 -Step git,aqua,task
  ./bootstrap.ps1 -SkipStep ssh
"@ | Write-Host
}

$DefaultSteps = @('git', 'ssh', 'aqua', 'task', 'apm')
$ValidSteps = @{}
foreach ($name in $DefaultSteps) {
  $ValidSteps[$name] = $true
}

function Normalize-StepList([string[]]$InputSteps, [string]$ParameterName) {
  $normalized = @()
  foreach ($raw in $InputSteps) {
    if ([string]::IsNullOrWhiteSpace($raw)) {
      continue
    }
    $stepName = $raw.Trim().ToLowerInvariant()
    if (-not $ValidSteps.ContainsKey($stepName)) {
      Fail "Invalid step '$raw' in $ParameterName. Valid steps: $($DefaultSteps -join ', ')"
    }
    if ($normalized -notcontains $stepName) {
      $normalized += $stepName
    }
  }
  return $normalized
}

$BootstrapBaseUrl = if ($env:BOOTSTRAP_PUBLIC_BASE_URL) {
  $env:BOOTSTRAP_PUBLIC_BASE_URL
} else {
  'https://raw.githubusercontent.com/abuttaro-conga/Bootstrap-Public/main'
}

# ----------------------------------------
# Install steps
# ----------------------------------------

function Ensure-Git {
  if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host "git already installed"
    return
  }

  Write-Host "Installing git"
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements
  } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
    choco install git -y
  } else {
    Fail "git not found and no supported installer detected"
  }

  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Fail "git install failed"
  }
}

function Ensure-Aqua {
  $aquaRoot = if ($env:AQUA_ROOT_DIR) { $env:AQUA_ROOT_DIR } else { Join-Path $env:LOCALAPPDATA 'aquaproj-aqua' }
  $aquaBin = Join-Path $aquaRoot 'bin'
  Add-PathEntry $aquaBin

  if (Get-Command aqua -ErrorAction SilentlyContinue) {
    Write-Host "aqua already installed"
    return
  }

  Write-Host "Installing aqua"
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install --id aquaproj.aqua -e --accept-package-agreements --accept-source-agreements
  } elseif (Get-Command scoop -ErrorAction SilentlyContinue) {
    scoop install main/aqua
  } else {
    Fail "aqua not found and no supported installer detected"
  }

  Refresh-EnvPath
  Add-PathEntry $aquaBin
  if (-not (Get-Command aqua -ErrorAction SilentlyContinue)) {
    Fail "aqua install failed"
  }
}

function Ensure-Task {
  if (Get-Command task -ErrorAction SilentlyContinue) {
    Write-Host "task already installed"
    return
  }

  if (-not (Get-Command aqua -ErrorAction SilentlyContinue)) {
    Fail "aqua is required before task; run with -Step aqua,task or no step flags"
  }

  Write-Host "Installing task via aqua"
  $aquaConfig = Join-Path $PSScriptRoot 'aqua.yaml'
  $cleanupTemp = $false
  if (-not (Test-Path $aquaConfig)) {
    $aquaConfig = [System.IO.Path]::GetTempFileName()
    Invoke-WebRequest -Uri "$BootstrapBaseUrl/aqua.yaml" -UseBasicParsing -OutFile $aquaConfig
    $cleanupTemp = $true
  }

  $env:AQUA_CONFIG = $aquaConfig
  & aqua i
  if ($cleanupTemp) {
    Remove-Item -Force $aquaConfig -ErrorAction SilentlyContinue
  }
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
  if (-not (Get-Command task -ErrorAction SilentlyContinue)) {
    Fail "task install failed"
  }
}

function Ensure-Apm {
  $apmBin = Join-Path $env:LOCALAPPDATA 'Programs\apm\bin'
  Add-PathEntry $apmBin

  if (Get-Command apm -ErrorAction SilentlyContinue) {
    Write-Host "apm already installed"
    return
  }

  Write-Host "Installing apm"
  $env:APM_INSTALL_DIR = $apmBin
  Invoke-Expression ((Invoke-WebRequest -Uri 'https://aka.ms/apm-windows' -UseBasicParsing).Content)
  Refresh-EnvPath
  Add-PathEntry $apmBin

  if (-not (Get-Command apm -ErrorAction SilentlyContinue)) {
    Fail "apm install failed"
  }
}

# ----------------------------------------
# SSH setup step
# ----------------------------------------

function Read-YesNo([string]$Prompt) {
  while ($true) {
    $answer = Read-Host "$Prompt [y/n]"
    switch -Regex ($answer) {
      '^(y|yes)$' { return $true }
      '^(n|no)$' { return $false }
      default { Write-Host "Please answer y or n." }
    }
  }
}

function Get-PublicKeyPath {
  $sshDir = Join-Path $HOME ".ssh"
  $bootstrapKey = Join-Path $sshDir "id_ed25519_bootstrap.pub"
  if (Test-Path $bootstrapKey) { return $bootstrapKey }

  return $null
}

function Get-SuggestedGitHubKeyTitle {
  $environmentId = ""
  if (-not [string]::IsNullOrWhiteSpace($env:WSL_DISTRO_NAME)) {
    $sanitizedDistro = ($env:WSL_DISTRO_NAME -replace '[^A-Za-z0-9._-]', '-')
    $environmentId = "wsl-$sanitizedDistro"
  } else {
    $osName = if ($IsWindows) { "windows" } else { "powershell" }
    $arch = if ([string]::IsNullOrWhiteSpace($env:PROCESSOR_ARCHITECTURE)) { "unknown-arch" } else { $env:PROCESSOR_ARCHITECTURE }
    $environmentId = "$($osName)-$($arch -replace '[^A-Za-z0-9._-]', '-')"
  }

  $hostName = if (-not [string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { $env:COMPUTERNAME } elseif (-not [string]::IsNullOrWhiteSpace($env:HOSTNAME)) { $env:HOSTNAME } else { "unknown-host" }
  $sanitizedHost = ($hostName -replace '[^A-Za-z0-9._-]', '-')

  return "bootstrap-generated-$environmentId-$sanitizedHost"
}

function Ensure-GitHubSshKey {
  $sshDir = Join-Path $HOME ".ssh"
  New-Item -ItemType Directory -Force -Path $sshDir | Out-Null

  $existing = Get-PublicKeyPath
  if ($existing) {
    Write-Host "Found existing SSH public key: $existing"
    return
  }

  if (-not [Environment]::UserInteractive) {
    Fail "No SSH key found and no interactive terminal available for key generation"
  }

  $defaultUser = if ($env:USERNAME) { $env:USERNAME } else { "user" }
  $defaultEmail = "$defaultUser@conga.com"
  $email = Read-Host "Email for SSH key comment [$defaultEmail]"
  if ([string]::IsNullOrWhiteSpace($email)) {
    $email = $defaultEmail
  }

  $keyPath = Join-Path $sshDir "id_ed25519_bootstrap"
  Write-Host "You must set a non-empty passphrase for this key when prompted."
  & ssh-keygen -t ed25519 -C $email -f $keyPath
  if ($LASTEXITCODE -ne 0) {
    Fail "Failed to generate SSH key"
  }

  # Reject empty-passphrase keys to enforce baseline key protection.
  & ssh-keygen -y -P '' -f $keyPath *> $null
  if ($LASTEXITCODE -eq 0) {
    Remove-Item -Force $keyPath -ErrorAction SilentlyContinue
    Remove-Item -Force ($keyPath + '.pub') -ErrorAction SilentlyContinue
    Fail "Empty passphrase is not allowed. Rerun and set a passphrase for $keyPath"
  }
}

function Ensure-SshAgentRunning {
  $agentService = Get-Service -Name ssh-agent -ErrorAction SilentlyContinue
  if ($agentService) {
    if ($agentService.StartType -eq 'Disabled') {
      Set-Service -Name ssh-agent -StartupType Manual
    }
    if ($agentService.Status -ne 'Running') {
      Start-Service ssh-agent
    }
  }
}

function Add-KeyToAgent([string]$PrivateKeyPath) {
  Ensure-SshAgentRunning
  $savedEAP = $ErrorActionPreference
  $ErrorActionPreference = 'SilentlyContinue'
  & ssh-add $PrivateKeyPath 2>&1 | Out-Null
  $ErrorActionPreference = $savedEAP
  if ($LASTEXITCODE -ne 0) {
    Fail "Failed to add SSH key to ssh-agent"
  }
}

function Test-GitHubSshConnection {
  $tmpErr = [System.IO.Path]::GetTempFileName()
  try {
    $proc = Start-Process ssh -ArgumentList '-T', 'git@github.com' `
      -NoNewWindow -Wait -PassThru -RedirectStandardError $tmpErr
    $status = $proc.ExitCode
    $outputText = (Get-Content -Raw $tmpErr -ErrorAction SilentlyContinue).TrimEnd()
  } finally {
    Remove-Item $tmpErr -Force -ErrorAction SilentlyContinue
  }

  if ($outputText) {
    Write-Host $outputText
  }

  if ($outputText -match 'successfully authenticated') {
    return
  }

  if ($status -eq 1 -and $outputText -match "You've successfully authenticated") {
    return
  }

  Fail "SSH test failed. Follow GitHub docs and rerun this script."
}

function Run-GitHubSshSetup {
  Write-Host "GitHub SSH setup helper"
  Write-Host "Guide: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/testing-your-ssh-connection"

  foreach ($cmd in @('git', 'ssh', 'ssh-keygen', 'ssh-agent', 'ssh-add')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
      Fail "$cmd is required"
    }
  }

  Ensure-GitHubSshKey
  $publicKeyPath = Get-PublicKeyPath
  if (-not $publicKeyPath) {
    Fail "No public SSH key available"
  }

  $privateKeyPath = $publicKeyPath -replace '\.pub$',''
  Add-KeyToAgent -PrivateKeyPath $privateKeyPath

  $suggestedTitle = "bootstrap-generated-windows-$env:COMPUTERNAME"
  Write-Host ""
  Write-Host "Suggested key title: $suggestedTitle"
  Write-Host "Add this SSH public key to your GitHub account:"
  Get-Content -Raw -Path $publicKeyPath | Write-Host
  Write-Host ""
  Write-Host "Suggested GitHub SSH key title (copy/paste):"
  Write-Host (Get-SuggestedGitHubKeyTitle)
  Write-Host ""
  Write-Host "GitHub key settings URL: https://github.com/settings/keys"

  if (-not (Read-YesNo "Have you added this key to GitHub?")) {
    Fail "Add the SSH key in GitHub, then rerun this script"
  }

  Write-Host "Running SSH test command: ssh -T git@github.com"
  Test-GitHubSshConnection
  Write-Host "GitHub SSH connection is ready."
}

# ----------------------------------------
# Step execution dispatcher
# ----------------------------------------

function Invoke-Step([string]$StepName) {
  switch ($StepName) {
    'git' { Ensure-Git; break }
    'ssh' { Run-GitHubSshSetup; break }
    'aqua' { Ensure-Aqua; break }
    'task' { Ensure-Task; break }
    'apm' { Ensure-Apm; break }
    default { Fail "Unknown step '$StepName'" }
  }
}

if ($Help) {
  Show-Help
  return
}

if ($ListSteps) {
  $DefaultSteps | ForEach-Object { Write-Host $_ }
  return
}

$RequestedSteps = Normalize-StepList -InputSteps $Step -ParameterName '-Step'
$SkippedSteps = Normalize-StepList -InputSteps $SkipStep -ParameterName '-SkipStep'

if ($RequestedSteps.Count -gt 0 -and $SkippedSteps.Count -gt 0) {
  Fail "-Step and -SkipStep cannot be used together"
}

if ($env:BOOTSTRAP_CONVENIENCE_MODE -eq '1' -and -not $ConvenienceAck) {
  Fail "convenience mode requires -ConvenienceAck"
}

$SelectedSteps = @()
if ($RequestedSteps.Count -gt 0) {
  $SelectedSteps = $RequestedSteps
} else {
  foreach ($stepName in $DefaultSteps) {
    if ($SkippedSteps -notcontains $stepName) {
      $SelectedSteps += $stepName
    }
  }
}

if ($SelectedSteps.Count -eq 0) {
  Fail "No steps selected"
}

foreach ($stepName in $SelectedSteps) {
  Invoke-Step -StepName $stepName
}

Write-Host "Public bootstrap complete."
Write-Host ""
Write-Host "NOTE: Open a new terminal window to use newly installed tools (aqua, apm, task)."
