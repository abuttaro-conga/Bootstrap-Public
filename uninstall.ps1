param()

$ErrorActionPreference = "Stop"

function Prompt-NoDefault([string]$Prompt) {
  if (-not [Environment]::UserInteractive) {
    Write-Host "Skipping (non-interactive): $Prompt"
    return $false
  }

  while ($true) {
    $answer = Read-Host "$Prompt [y/N]"
    switch -Regex ($answer) {
      '^(y|yes)$' { return $true }
      '^$|^(n|no)$' { return $false }
      default { Write-Host "Please answer y or n." }
    }
  }
}

function Remove-BootstrapBlock([string]$ProfilePath, [string]$BlockName) {
  if (-not (Test-Path $ProfilePath)) {
    return
  }

  $markerStart = "# bootstrap-public-$BlockName`:start"
  $markerEnd = "# bootstrap-public-$BlockName`:end"
  $content = Get-Content -Raw -Path $ProfilePath -ErrorAction SilentlyContinue
  if ([string]::IsNullOrWhiteSpace($content) -or -not $content.Contains($markerStart)) {
    return
  }

  $lines = Get-Content -Path $ProfilePath
  $filtered = New-Object System.Collections.Generic.List[string]
  $inBlock = $false
  foreach ($line in $lines) {
    if ($line -eq $markerStart) { $inBlock = $true; continue }
    if ($inBlock -and $line -eq $markerEnd) { $inBlock = $false; continue }
    if (-not $inBlock) { $null = $filtered.Add($line) }
  }

  Set-Content -Path $ProfilePath -Value $filtered -Encoding utf8
  Write-Host "Removed $BlockName block from $ProfilePath"
}

function Remove-UserPathEntry([string]$EntryPath) {
  if ([string]::IsNullOrWhiteSpace($EntryPath)) {
    return
  }

  $normalizedTarget = [System.IO.Path]::GetFullPath($EntryPath).TrimEnd('\\')
  $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
  if ([string]::IsNullOrWhiteSpace($userPath)) {
    return
  }

  $segments = $userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  $kept = New-Object System.Collections.Generic.List[string]
  foreach ($segment in $segments) {
    $normalizedSegment = [System.IO.Path]::GetFullPath($segment).TrimEnd('\\')
    if (-not $normalizedSegment.Equals($normalizedTarget, [System.StringComparison]::OrdinalIgnoreCase)) {
      $null = $kept.Add($segment)
    }
  }

  [System.Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
}

function Remove-BootstrapSshConfigBlock {
  $sshConfig = Join-Path $HOME '.ssh\config'
  if (-not (Test-Path $sshConfig)) {
    return
  }

  $marker = '# bootstrap-managed: github.com'
  $lines = Get-Content -Path $sshConfig
  if (-not ($lines -contains $marker)) {
    return
  }

  $filtered = New-Object System.Collections.Generic.List[string]
  $skip = $false
  $inManagedHost = $false
  foreach ($line in $lines) {
    if (-not $skip -and $line -eq $marker) { $skip = $true; $inManagedHost = $false; continue }
    if ($skip) {
      if (-not $inManagedHost) {
        if ($line -match '^\s*Host\s+') { $inManagedHost = $true; continue }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $skip = $false
      } else {
        if ($line -match '^\s+' -or [string]::IsNullOrWhiteSpace($line)) { continue }
        $skip = $false
      }
    }
    $null = $filtered.Add($line)
  }

  Set-Content -Path $sshConfig -Value $filtered -Encoding utf8
  Write-Host "Removed bootstrap GitHub SSH block from $sshConfig"
}

Write-Host "Bootstrap-Public uninstall (Windows PowerShell)"
Write-Host "Each operation is prompted with default No."

$profilePath = $PROFILE.CurrentUserCurrentHost
$profilePromptTarget = if ([string]::IsNullOrWhiteSpace($profilePath)) { 'current PowerShell profile' } else { $profilePath }
$taskName = 'BootstrapPublic-SshAgentInit'
$fallbackDir = Join-Path $HOME '.bootstrap-public'
$candidatePaths = @(
  (Join-Path $env:LOCALAPPDATA 'Programs\mise\bin'),
  (Join-Path $HOME '.local\bin'),
  (Join-Path $env:LOCALAPPDATA 'mise\bin'),
  (Join-Path $env:LOCALAPPDATA 'mise\shims')
)

if (Prompt-NoDefault "Remove bootstrap mise activation block from $profilePromptTarget?") {
  Remove-BootstrapBlock -ProfilePath $profilePath -BlockName 'mise-activate:pwsh'
}

if (Prompt-NoDefault "Remove bootstrap ssh-agent block from $profilePromptTarget?") {
  Remove-BootstrapBlock -ProfilePath $profilePath -BlockName 'ssh-agent'
}

if (Prompt-NoDefault "Remove bootstrap Scheduled Task fallback ($taskName)?") {
  cmd.exe /c "schtasks /Delete /TN \"$taskName\" /F >nul 2>&1"
  Write-Host "Scheduled task delete attempted: $taskName"
}

if (Prompt-NoDefault "Remove bootstrap fallback directory $fallbackDir?") {
  if (Test-Path $fallbackDir) {
    Remove-Item -Recurse -Force $fallbackDir
    Write-Host "Removed $fallbackDir"
  }
}

if (Prompt-NoDefault "Remove bootstrap-added mise paths from Windows User PATH?") {
  foreach ($pathEntry in $candidatePaths) {
    Remove-UserPathEntry -EntryPath $pathEntry
  }
  Write-Host "User PATH cleanup completed."
}

if (Prompt-NoDefault "Clear User-scoped GH_TOKEN and GITHUB_TOKEN?") {
  [System.Environment]::SetEnvironmentVariable('GH_TOKEN', $null, 'User')
  [System.Environment]::SetEnvironmentVariable('GITHUB_TOKEN', $null, 'User')
  Write-Host "Cleared GH_TOKEN and GITHUB_TOKEN from User scope."
}

if (Prompt-NoDefault "Remove bootstrap GitHub SSH config block from ~/.ssh/config?") {
  Remove-BootstrapSshConfigBlock
}

if (Prompt-NoDefault "Delete bootstrap SSH key files (~/.ssh/id_ed25519_bootstrap and .pub)?") {
  Remove-Item -Force (Join-Path $HOME '.ssh\id_ed25519_bootstrap') -ErrorAction SilentlyContinue
  Remove-Item -Force (Join-Path $HOME '.ssh\id_ed25519_bootstrap.pub') -ErrorAction SilentlyContinue
  Write-Host "Deleted bootstrap SSH key files."
}

Write-Host "Uninstall run complete."