param(
  [string[]]$Step,
  [string[]]$SkipStep,
  [switch]$ListSteps,
  [Alias('h')][switch]$Help
)

$ErrorActionPreference = "Stop"

$script:ProfileScriptingChecked = $false
$script:ProfileScriptingAllowed = $true

# ----------------------------------------
# Output and validation helpers
# ----------------------------------------

function Fail([string]$Message) {
  throw $Message
}

function Test-ProfileScriptingAllowed {
  if ($script:ProfileScriptingChecked) {
    return $script:ProfileScriptingAllowed
  }

  $script:ProfileScriptingChecked = $true
  $effectivePolicy = Get-ExecutionPolicy

  if ($effectivePolicy -in @('AllSigned', 'Restricted')) {
    $script:ProfileScriptingAllowed = $false
    Write-Warning "PowerShell execution policy '$effectivePolicy' blocks unsigned profile scripts."
    Write-Host "Skipping profile updates to avoid startup failures."
    Write-Host "To allow bootstrap profile snippets for current user, run:"
    Write-Host "  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
    Write-Host "Check policy precedence with:"
    Write-Host "  Get-ExecutionPolicy -List"
    return $false
  }

  return $true
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

function Add-PathEntryToUserPath([string]$PathEntry) {
  if ([string]::IsNullOrWhiteSpace($PathEntry)) {
    return
  }

  $normalizedEntry = [System.IO.Path]::GetFullPath($PathEntry).TrimEnd('\\')
  $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
  $segments = @()
  if (-not [string]::IsNullOrWhiteSpace($userPath)) {
    $segments = $userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  }

  $exists = $false
  foreach ($segment in $segments) {
    $normalizedSegment = [System.IO.Path]::GetFullPath($segment).TrimEnd('\\')
    if ($normalizedSegment.Equals($normalizedEntry, [System.StringComparison]::OrdinalIgnoreCase)) {
      $exists = $true
      break
    }
  }

  if (-not $exists) {
    $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
      $normalizedEntry
    } else {
      "$userPath;$normalizedEntry"
    }
    [System.Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Host "Added to user PATH: $normalizedEntry"
  }
}

function Get-MisePathCandidates {
  $miseDataDir = if (-not [string]::IsNullOrWhiteSpace($env:MISE_DATA_DIR)) {
    $env:MISE_DATA_DIR
  } else {
    Join-Path $env:LOCALAPPDATA 'mise'
  }

  return @(
    (Join-Path $env:LOCALAPPDATA 'Programs\\mise\\bin'),
    (Join-Path $HOME '.local\\bin'),
    (Join-Path $miseDataDir 'bin'),
    (Join-Path $miseDataDir 'shims')
  )
}

function Refresh-EnvPath {
  $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
  $userPath    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = "$machinePath;$userPath"
}

function Find-MiseInstallation {
  # First, try using 'where.exe' to find mise in system PATH or common locations
  $whereResult = $null
  try {
    $whereResult = where.exe mise.exe 2>$null | Select-Object -First 1
    if ($whereResult) {
      Write-Host "Found via where.exe: $whereResult" -ForegroundColor Green
      return (Split-Path $whereResult)
    }
  } catch { }

  # Check WinGet packages folder structure
  $wingetPackagesDir = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
  if (Test-Path $wingetPackagesDir) {
    Write-Host "Checking WinGet packages folder..." -ForegroundColor Yellow
    try {
      $misePackages = Get-ChildItem -Path $wingetPackagesDir -Directory -Filter '*mise*' -ErrorAction SilentlyContinue
      foreach ($pkg in $misePackages) {
        $misePath = Join-Path $pkg.FullName 'mise.exe'
        if (Test-Path $misePath) {
          $foundPath = Split-Path $misePath
          Write-Host "Found in WinGet packages: $foundPath" -ForegroundColor Green
          return $foundPath
        }
        # Also check in bin subdirectory
        $binPath = Join-Path $pkg.FullName 'bin\mise.exe'
        if (Test-Path $binPath) {
          $foundPath = Split-Path $binPath
          Write-Host "Found in WinGet packages: $foundPath" -ForegroundColor Green
          return $foundPath
        }
      }
    } catch { }
  }

  # If winget is available, query it for jdx.mise install info
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    try {
      Write-Host "Querying winget show for jdx.mise install location..." -ForegroundColor Yellow
      $wingetInfo = winget show --id jdx.mise 2>&1 | Out-String
      # Try to extract Install Folder or Version/Location info
      if ($wingetInfo -match 'Install\s+(?:Folder|Path|Location)[:\s]+([C-Z]:\\[^\r\n]+)') {
        $installPath = $matches[1].Trim()
        if (Test-Path $installPath) {
          Write-Host "Found via winget info: $installPath" -ForegroundColor Green
          return $installPath
        }
      }
    } catch { }
  }

  # Search common installation locations for mise executable
  $searchPaths = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\jdx.mise\bin'),
    (Join-Path $env:ProgramFiles 'jdx.mise\bin'),
    (Join-Path $env:LOCALAPPDATA 'Programs\mise\bin'),
    (Join-Path $env:ProgramFiles 'mise\bin'),
    (Join-Path ${env:ProgramFiles(x86)} 'mise\bin'),
    (Join-Path $env:LOCALAPPDATA 'mise\bin'),
    (Join-Path $env:LOCALAPPDATA 'mise'),
    (Join-Path $HOME '.local\bin'),
    (Join-Path $env:LOCALAPPDATA 'scoop\apps\mise\current\bin')
  )

  Write-Host "Searching standard installation locations..." -ForegroundColor Yellow
  foreach ($searchPath in $searchPaths) {
    if ([string]::IsNullOrWhiteSpace($searchPath)) { continue }
    $misePath = Join-Path $searchPath 'mise.exe'
    if (Test-Path $misePath -ErrorAction SilentlyContinue) {
      Write-Host "Found at: $searchPath" -ForegroundColor Green
      return $searchPath
    }
  }

  # Last resort: perform targeted recursive search (limit depth to avoid excessive searching)
  Write-Host "Performing targeted search in common locations..." -ForegroundColor Yellow
  
  $searchRoots = @(
    $env:LOCALAPPDATA,
    $env:ProgramFiles,
    ${env:ProgramFiles(x86)}
  )

  foreach ($root in $searchRoots) {
    if (-not (Test-Path $root)) { continue }
    try {
      Write-Host "  Searching: $root" -ForegroundColor DarkGray
      $found = Get-ChildItem -Path $root -Filter 'mise.exe' -Recurse -ErrorAction SilentlyContinue -Depth 4 | Select-Object -First 1
      if ($found) {
        $foundPath = Split-Path $found.FullPath
        Write-Host "Found via deep search: $foundPath" -ForegroundColor Green
        return $foundPath
      }
    } catch { }
  }

  Write-Host "mise.exe not found in any standard location" -ForegroundColor Red
  return $null
}

function Ensure-MiseInPath {
  # Check if mise is already accessible
  if (Get-Command mise -ErrorAction SilentlyContinue) {
    return $true
  }

  # Try to find mise installation
  $miseInstallPath = Find-MiseInstallation
  if (-not $miseInstallPath) {
    return $false
  }

  Write-Host "Found mise at: $miseInstallPath"
  Add-PathEntry $miseInstallPath
  Add-PathEntryToUserPath $miseInstallPath
  Refresh-EnvPath

  if (Get-Command mise -ErrorAction SilentlyContinue) {
    Write-Host "mise is now accessible"
    return $true
  }

  return $false
}

function Repair-MiseWingetPackage {
  <#
  .SYNOPSIS
    Repairs corrupted/phantom winget package (installed in registry but files missing)
  .DESCRIPTION
    When winget reports jdx.mise is installed but mise.exe doesn't exist anywhere,
    this performs a forced uninstall and clean reinstall.
    
    IMPORTANT: This only works from non-admin PowerShell if package is in user scope.
    
    Manual cleanup (if needed without bootstrap, run from REGULAR terminal, not admin):
      winget uninstall --id jdx.mise -e
      winget install --id jdx.mise -e --accept-package-agreements --accept-source-agreements
      Close and reopen PowerShell
  #>
  # This handles the case where winget reports a package is installed but files are missing
  Write-Host "  → Attempting to repair corrupted winget package..." -ForegroundColor Yellow
  
  # Try to uninstall first
  Write-Host "    Uninstalling jdx.mise..." -ForegroundColor DarkGray
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  
  winget uninstall --id jdx.mise -e 2>&1 | ForEach-Object {
    if ($_ -like "*cannot be uninstalled when running with administrator*") {
      Write-Host "      ✗ Package is in user scope but running as admin" -ForegroundColor Red
      Write-Host "      Close this terminal and run from a regular (non-admin) PowerShell" -ForegroundColor Yellow
      return $false
    }
    if ($_ -notlike "*Finding package*") {
      Write-Host "      $_" -ForegroundColor DarkGray
    }
  }
  
  $ErrorActionPreference = $previousErrorActionPreference
  
  Start-Sleep -Seconds 2
  
  # Now reinstall
  Write-Host "    Reinstalling jdx.mise..." -ForegroundColor DarkGray
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  
  winget install --id jdx.mise -e --accept-package-agreements --accept-source-agreements 2>&1 | ForEach-Object {
    if ($_ -notlike "*Finding package*") {
      Write-Host "      $_" -ForegroundColor DarkGray
    }
  }
  
  $ErrorActionPreference = $previousErrorActionPreference
  
  Start-Sleep -Seconds 2
  
  # Verify
  if (Get-Command mise -ErrorAction SilentlyContinue) {
    Write-Host "    ✓ Repair successful" -ForegroundColor Green
    return $true
  }
  
  # Try to find it again after reinstall
  if (Ensure-MiseInPath) {
    Write-Host "    ✓ Repair successful (found and added to PATH)" -ForegroundColor Green
    return $true
  }
  
  Write-Host "    ✗ Repair failed" -ForegroundColor Red
  return $false
}

function Show-Help {
  @"
Usage:
  ./bootstrap.ps1 [-Step <name[]> | -SkipStep <name[]>] [-ListSteps] [-Help] [-AggressiveCleanup]

Behavior:
  - No step parameters: runs full default flow (git -> ssh -> mise)
  - -Step: run only specified steps in provided order
  - -SkipStep: run default flow except skipped steps
  - -AggressiveCleanup: forces uninstall/reinstall of packages (debug option)

Options:
  -Step <name[]>           Step names: git, ssh, mise
  -SkipStep <name[]>       Step names: git, ssh, mise
  -ListSteps               Print valid step names and exit
  -AggressiveCleanup       (DEBUG) Force package reinstall even if not broken
  -Help, -h                Show this help and exit

Debug / Manual Cleanup:
  If mise is stuck in a phantom package state (winget reports installed
  but files missing), you can manually clean it up before running bootstrap:

  IMPORTANT: Run PowerShell WITHOUT administrator privileges for user-scope packages.
  (If installed in user scope, admin-privileged winget cannot uninstall it.)

  PowerShell (as regular user, NOT admin):
    winget uninstall --id jdx.mise -e
    winget install --id jdx.mise -e --accept-package-agreements --accept-source-agreements
    Close and reopen PowerShell

  Or run bootstrap with automatic cleanup (off by default):
    ./bootstrap.ps1 -Step mise -AggressiveCleanup

  Note: If running bootstrap as admin and the package is in user scope,
  close admin PowerShell and run bootstrap from a regular (non-admin) terminal.

Examples:
  ./bootstrap.ps1
  ./bootstrap.ps1 -Step ssh
  ./bootstrap.ps1 -Step git,mise
  ./bootstrap.ps1 -SkipStep ssh
  ./bootstrap.ps1 -Step mise -AggressiveCleanup
"@ | Write-Host
}

$DefaultSteps = @('git', 'ssh', 'mise')

function Normalize-StepList([string[]]$InputSteps, [string]$ParameterName) {
  $normalized = @()
  foreach ($raw in $InputSteps) {
    if ([string]::IsNullOrWhiteSpace($raw)) {
      continue
    }
    $stepName = $raw.Trim().ToLowerInvariant()
    if ($DefaultSteps -notcontains $stepName) {
      Fail "Invalid step '$raw' in $ParameterName. Valid steps: $($DefaultSteps -join ', ')"
    }
    if ($normalized -notcontains $stepName) {
      $normalized += $stepName
    }
  }
  return $normalized
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

  Refresh-EnvPath

  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Fail "git install failed"
  }
}

function Ensure-Mise {
  Write-Host ""
  Write-Host "=== Mise Setup ===" -ForegroundColor Cyan
  
  # First, try to find mise if already installed but not in PATH
  Write-Host "Step 1: Checking if mise is accessible in current session..."
  if (Ensure-MiseInPath) {
    Write-Host "✓ mise already installed and accessible" -ForegroundColor Green
    return
  }
  Write-Host "  (Not found in current PATH)" -ForegroundColor Yellow

  $candidateBins = Get-MisePathCandidates
  Write-Host "Step 2: Adding candidate paths to current session and user PATH..."
  foreach ($bin in $candidateBins) {
    Write-Host "  Adding: $bin" -ForegroundColor DarkGray
    Add-PathEntry $bin
    Add-PathEntryToUserPath $bin
  }

  if (Get-Command mise -ErrorAction SilentlyContinue) {
    Write-Host "✓ mise accessible after adding candidates" -ForegroundColor Green
    return
  }

  Write-Host "Step 3: Installing mise via package manager..."
  
  # If AggressiveCleanup is enabled, force a clean reinstall
  if ($AggressiveCleanup) {
    Write-Host "  → AggressiveCleanup enabled: forcing clean reinstall..." -ForegroundColor Yellow
    if (Repair-MiseWingetPackage) {
      Write-Host "✓ mise reinstalled successfully" -ForegroundColor Green
      Write-Host ""
      Write-Host "NOTE: Close and reopen PowerShell for permanent PATH access" -ForegroundColor Yellow
      return
    }
    Write-Host "  ⚠ Aggressive cleanup did not resolve the issue" -ForegroundColor Yellow
  }
  
  $installAttempted = $false
  $packageAlreadyExists = $false
  $installOutput = @()
  
  # Check if winget is available, with fallback to full path
  $wingetCmd = $null
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    $wingetCmd = "winget"
  } else {
    # Try full path for winget
    $wingetPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
    if (Test-Path $wingetPath) {
      $wingetCmd = $wingetPath
    }
  }
  
  if ($wingetCmd) {
    Write-Host "  → Attempting install via winget..." -ForegroundColor Yellow
    $installAttempted = $true
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    
    $output = @()
    & $wingetCmd install --id jdx.mise -e --accept-package-agreements --accept-source-agreements 2>&1 | Tee-Object -Variable output | ForEach-Object {
      if ($_ -like "*already installed*" -or $_ -like "*No available upgrade*") {
        Write-Host "    → mise package already present" -ForegroundColor Yellow
        $packageAlreadyExists = $true
      } elseif ($_ -like "*Successfully installed*") {
        Write-Host "    → Successfully installed" -ForegroundColor Green
      } else {
        Write-Host "    $($_)" -ForegroundColor DarkGray
      }
    }
    $installOutput = $output
    $ErrorActionPreference = $previousErrorActionPreference
  } elseif (-not $wingetCmd) {
    Write-Host "  ⚠ winget not available in PATH" -ForegroundColor Yellow
    Write-Host "    Checking for scoop or chocolatey..." -ForegroundColor DarkGray
  }
  
  if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Host "  → Attempting install via scoop..." -ForegroundColor Yellow
    $installAttempted = $true
    scoop install main/mise 2>&1 | Tee-Object -Variable installOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
  }
  
  if (-not $installAttempted -and (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "  → Attempting install via choco..." -ForegroundColor Yellow
    $installAttempted = $true
    choco install mise -y 2>&1 | Tee-Object -Variable installOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
  }
  
  if (-not $installAttempted) {
    Fail "mise: no supported installer detected (need winget, scoop, or chocolatey)"
  }

  Write-Host "Step 4: Refreshing environment PATH..."
  Refresh-EnvPath
  
  # Try standard candidate paths first
  foreach ($bin in $candidateBins) {
    Add-PathEntry $bin
    Add-PathEntryToUserPath $bin
  }

  # Check if accessible now
  if (Get-Command mise -ErrorAction SilentlyContinue) {
    Write-Host "✓ mise is now accessible" -ForegroundColor Green
    return
  }

  # If not found in standard locations, search for it (this is the key fix)
  Write-Host "Step 5: Searching for mise installation..."
  $misePath = Find-MiseInstallation
  if ($misePath) {
    Write-Host "✓ Found mise at: $misePath" -ForegroundColor Green
    Add-PathEntry $misePath
    Add-PathEntryToUserPath $misePath
    Refresh-EnvPath
    
    if (Get-Command mise -ErrorAction SilentlyContinue) {
      Write-Host "✓ mise is now accessible" -ForegroundColor Green
      Write-Host ""
      Write-Host "NOTE: Close and reopen PowerShell for permanent PATH access" -ForegroundColor Yellow
      return
    }
  }

  # CRITICAL: If winget says it's installed but we can't find it, the package is corrupted
  if ($packageAlreadyExists -and -not (Get-Command mise -ErrorAction SilentlyContinue)) {
    Write-Host "Step 6: Winget reports package is installed but files not found - attempting repair..."
    if (Repair-MiseWingetPackage) {
      Write-Host "✓ mise is now accessible" -ForegroundColor Green
      Write-Host ""
      Write-Host "NOTE: Close and reopen PowerShell for permanent PATH access" -ForegroundColor Yellow
      return
    }
  }

  # Detailed failure information
  Write-Host ""
  Write-Host "✗ MISE INSTALLATION FAILED" -ForegroundColor Red
  Write-Host ""
  Write-Host "Diagnostic Information:" -ForegroundColor Cyan
  Write-Host "  - Installer attempted: $(if ($installAttempted) { 'Yes' } else { 'No' })"
  Write-Host "  - winget available: $(if ($wingetCmd) { 'Yes' } else { 'No' })"
  Write-Host "  - Package already exists (per winget): $(if ($packageAlreadyExists) { 'Yes' } else { 'No' })"
  if ($installOutput.Count -gt 0) {
    Write-Host "  - Installer output:"
    $installOutput | ForEach-Object { Write-Host "      $_" }
  }
  Write-Host ""
  Write-Host "Troubleshooting Steps:" -ForegroundColor Yellow
  
  if (-not $wingetCmd) {
    Write-Host "  STEP 1: winget is not available (required for mise installation)"
    Write-Host "  Options:"
    Write-Host "    A) Install App Installer from Microsoft Store:"
    Write-Host "       https://www.microsoft.com/store/productId/9NBLGGH4NNS1"
    Write-Host "    B) Enable App Installer if already installed:"
    Write-Host "       Settings → Apps → Apps & features → (search 'App Installer')"
    Write-Host "    C) Use scoop or chocolatey instead (if available)"
    Write-Host ""
    Write-Host "  After installing App Installer:"
    Write-Host "    - Close this PowerShell window"
    Write-Host "    - Open a NEW PowerShell (non-admin recommended)"
    Write-Host "    - Rerun: ./bootstrap.ps1 -Step mise"
    Write-Host ""
  } else {
    Write-Host "  1. Check if running as admin: If yes and package is in user scope,"
    Write-Host "     close this terminal and run from regular (non-admin) PowerShell"
    Write-Host ""
    Write-Host "  2. Open a NEW PowerShell window (non-admin if needed)"
    Write-Host "  3. Try this command:"
    Write-Host "     Get-ChildItem -Path 'C:\' -Recurse -Filter 'mise.exe' -ErrorAction SilentlyContinue 2>/dev/null | Select-Object -First 1"
    Write-Host "  4. This will show if/where mise.exe exists"
    Write-Host "  5. If found, add its directory to your user PATH environment variable"
    Write-Host ""
    Write-Host "  If not found (run from non-admin terminal):"
    Write-Host "    - winget uninstall --id jdx.mise -e"
    Write-Host "    - winget install --id jdx.mise -e --accept-package-agreements --accept-source-agreements"
    Write-Host "    - Close and reopen PowerShell"
    Write-Host ""
    Write-Host "  Bootstrap with aggressive cleanup (run from non-admin terminal):"
    Write-Host "    - ./bootstrap.ps1 -Step mise -AggressiveCleanup"
    Write-Host ""
  }
  
  Fail "mise install failed - could not locate mise executable after installation attempt"
}

function Ensure-GitHubTokenForMise {
  function Test-GhAuthStatus {
    param(
      [switch]$Quiet
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    $hadNativePreference = Test-Path Variable:PSNativeCommandUseErrorActionPreference
    if ($hadNativePreference) {
      $previousNativePreference = $PSNativeCommandUseErrorActionPreference
      $PSNativeCommandUseErrorActionPreference = $false
    }

    try {
      if ($Quiet) {
        & gh auth status --hostname github.com *> $null
      } else {
        & gh auth status --hostname github.com
      }
      return $LASTEXITCODE -eq 0
    }
    finally {
      $ErrorActionPreference = $previousErrorActionPreference
      if ($hadNativePreference) {
        $PSNativeCommandUseErrorActionPreference = $previousNativePreference
      }
    }
  }

  function Show-GhAuthRecoveryInstructions {
    Write-Warning "Stopping GitHub token setup for this run."
    Write-Host "Run: gh auth status --hostname github.com"
    Write-Host "If not logged in, run: gh auth login --hostname github.com"
    Write-Host "Then rerun bootstrap (or rerun only the mise step)."
  }

  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    return
  }

  $existingGhToken = [System.Environment]::GetEnvironmentVariable('GH_TOKEN', 'User')
  $existingGithubToken = [System.Environment]::GetEnvironmentVariable('GITHUB_TOKEN', 'User')
  if (-not [string]::IsNullOrWhiteSpace($existingGhToken) -or -not [string]::IsNullOrWhiteSpace($existingGithubToken)) {
    return
  }

  if (-not (Test-GhAuthStatus -Quiet)) {
    Write-Host "GitHub CLI is not authenticated for github.com."
    if (-not [Environment]::UserInteractive) {
      Show-GhAuthRecoveryInstructions
      return
    }

    if (-not (Read-YesNo "Run 'gh auth login --hostname github.com' now?")) {
      Write-Host "Skipping GitHub CLI login."
      if (Read-YesNo "Run 'gh auth status --hostname github.com' now for details?") {
        $null = Test-GhAuthStatus
      }
      Show-GhAuthRecoveryInstructions
      return
    }

    & gh auth login --hostname github.com
    if ($LASTEXITCODE -ne 0) {
      Write-Host "GitHub CLI login did not complete successfully."
      if (Read-YesNo "Run 'gh auth status --hostname github.com' now for details?") {
        $null = Test-GhAuthStatus
      }
      Show-GhAuthRecoveryInstructions
      return
    }

    if (-not (Test-GhAuthStatus -Quiet)) {
      Write-Host "GitHub CLI is still not authenticated for github.com."
      if (Read-YesNo "Run 'gh auth status --hostname github.com' now for details?") {
        $null = Test-GhAuthStatus
      }
      Show-GhAuthRecoveryInstructions
      return
    }
  }

  if (-not [Environment]::UserInteractive) {
    Write-Host "GitHub auth detected, but session is non-interactive."
    Write-Host "Set GH_TOKEN/GITHUB_TOKEN manually if mise private GitHub downloads fail in new terminals."
    return
  }

  if (-not (Read-YesNo "Persist GH_TOKEN and GITHUB_TOKEN from gh auth for new terminals (needed for private GitHub release downloads by mise)?")) {
    Write-Host "Skipping GitHub token persistence."
    Write-Host "If needed per session: `$env:GITHUB_TOKEN = gh auth token"
    return
  }

  $token = (& gh auth token --hostname github.com 2>$null)
  if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Host "Could not read token from gh auth."
    if ([Environment]::UserInteractive -and (Read-YesNo "Run 'gh auth status --hostname github.com' now for details?")) {
      $null = Test-GhAuthStatus
    }
    Show-GhAuthRecoveryInstructions
    return
  }

  [System.Environment]::SetEnvironmentVariable('GH_TOKEN', $token, 'User')
  [System.Environment]::SetEnvironmentVariable('GITHUB_TOKEN', $token, 'User')
  Write-Host "Persisted GH_TOKEN and GITHUB_TOKEN at User scope for new terminals."
}

function Ensure-MiseActivationProfile {
  if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
    return
  }

  if (-not (Test-ProfileScriptingAllowed)) {
    return
  }

  $profilePath = $PROFILE.CurrentUserCurrentHost
  $profileDir = Split-Path -Parent $profilePath
  $activationLine = '(& mise activate pwsh) | Out-String | Invoke-Expression'
  $markerStart = '# bootstrap-public-mise-activate:pwsh:start'
  $markerEnd = '# bootstrap-public-mise-activate:pwsh:end'

  if (-not [string]::IsNullOrWhiteSpace($profileDir) -and -not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
  }

  if (-not (Test-Path $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
  }

  $profileContent = Get-Content -Raw -Path $profilePath -ErrorAction SilentlyContinue
  if ($profileContent -and ($profileContent.Contains($activationLine) -or ($profileContent.Contains($markerStart) -and $profileContent.Contains($markerEnd)))) {
    Write-Host "mise activation already configured in $profilePath"
    return
  }

  Add-Content -Path $profilePath -Value "`n$markerStart`n$activationLine`n$markerEnd"
  Write-Host "Added mise activation to $profilePath"
  Write-Host "To apply now in this shell run: $activationLine"
}

# ----------------------------------------
# SSH setup step
# ----------------------------------------

function Ensure-SshAgentProfile {
  if (-not (Test-ProfileScriptingAllowed)) {
    Ensure-SshAgentScheduledTaskFallback
    return
  }

  $keyPath = Join-Path $HOME '.ssh\id_ed25519_bootstrap'
  $profilePath = $PROFILE.CurrentUserCurrentHost
  $profileDir = Split-Path -Parent $profilePath
  $markerStart = '# bootstrap-public-ssh-agent:start'
  $markerEnd = '# bootstrap-public-ssh-agent:end'

  $escapedPath = $keyPath -replace "'", "''"
  $block = @"
`$_bsKeyPath = '$escapedPath'
if (Test-Path `$_bsKeyPath) {
    `$_bsPubPath = "`$(`$_bsKeyPath).pub"
    `$_bsPubKey = if (Test-Path `$_bsPubPath) { (Get-Content -Raw `$_bsPubPath).Trim() } else { '' }
  `$null = Get-Service ssh-agent -ErrorAction SilentlyContinue |
    Where-Object { `$_.Status -ne 'Running' } |
    ForEach-Object { Start-Service `$_ }
    `$_loadedKeys = ssh-add -L 2>`$null
    if (-not `$_bsPubKey -or -not (`$_loadedKeys | Select-String -SimpleMatch `$_bsPubKey)) {
    ssh-add `$_bsKeyPath
  }
}
  Remove-Variable _bsKeyPath -ErrorAction SilentlyContinue
  Remove-Variable _bsPubPath -ErrorAction SilentlyContinue
  Remove-Variable _bsPubKey -ErrorAction SilentlyContinue
  Remove-Variable _loadedKeys -ErrorAction SilentlyContinue
"@

  if (-not [string]::IsNullOrWhiteSpace($profileDir) -and -not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
  }

  if (-not (Test-Path $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
  }

  $profileContent = Get-Content -Raw -Path $profilePath -ErrorAction SilentlyContinue
  if ($profileContent -and $profileContent.Contains($markerStart) -and $profileContent.Contains($markerEnd)) {
    Write-Host "SSH agent already configured in $profilePath"
    return
  }

  Add-Content -Path $profilePath -Value "`n$markerStart`n$block`n$markerEnd"
  Write-Host "Added SSH agent key-load to $profilePath"
  Write-Host "Your SSH key passphrase will be prompted once per terminal session."
}

function Read-YesNo([string]$Prompt) {
  while ($true) {
    $answer = Read-Host "$Prompt [Y/n]"
    if ([string]::IsNullOrWhiteSpace($answer)) {
      return $true
    }
    switch -Regex ($answer) {
      '^(y|yes)$' { return $true }
      '^(n|no)$' { return $false }
      default { Write-Host "Please answer y or n." }
    }
  }
}

function Test-ScheduledTaskExists([string]$TaskName) {
  if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
    return $null -ne (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
  }

  cmd.exe /c "schtasks /Query /TN \"$TaskName\" >nul 2>&1"
  return $LASTEXITCODE -eq 0
}

function Ensure-SshAgentScheduledTaskFallback {
  $taskName = 'BootstrapPublic-SshAgentInit'
  $keyPath = Join-Path $HOME '.ssh\id_ed25519_bootstrap'
  $keyPathEscaped = $keyPath -replace "'", "''"
  $scriptDir = Join-Path $HOME '.bootstrap-public'
  $scriptPath = Join-Path $scriptDir 'ssh-agent-logon.ps1'

  if (-not (Get-Command schtasks.exe -ErrorAction SilentlyContinue)) {
    Write-Host "Task Scheduler CLI not available."
    Write-Host "Manual fallback: run 'ssh-add $keyPath' once after opening a new terminal."
    return
  }

  if (Test-ScheduledTaskExists -TaskName $taskName) {
    Write-Host "Scheduled task already configured: $taskName"
    return
  }

  $shouldCreate = $false
  if ([Environment]::UserInteractive) {
    $shouldCreate = Read-YesNo "Profile scripts are blocked. Create a user logon task to start ssh-agent and load your bootstrap key?"
  } else {
    Write-Host "Profile scripts are blocked and session is non-interactive."
    Write-Host "Skipping scheduled task creation."
  }

  if (-not $shouldCreate) {
    Write-Host "Skipping scheduled task fallback."
    Write-Host "Manual fallback: run 'ssh-add $keyPath' once after opening a new terminal."
    return
  }

  New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null

  $taskScript = @"
`$ErrorActionPreference = 'SilentlyContinue'
`$keyPath = '$keyPathEscaped'
`$pubPath = "`$(`$keyPath).pub"

`$agentService = Get-Service -Name ssh-agent -ErrorAction SilentlyContinue
if (`$agentService) {
  if (`$agentService.StartType -eq 'Disabled') {
    Set-Service -Name ssh-agent -StartupType Manual
  }
  if (`$agentService.Status -ne 'Running') {
    Start-Service ssh-agent
  }
}

if (Test-Path `$keyPath) {
  `$pubKey = if (Test-Path `$pubPath) { (Get-Content -Raw `$pubPath).Trim() } else { '' }
  `$loadedKeys = ssh-add -L 2>`$null
  if (-not `$pubKey -or -not (`$loadedKeys | Select-String -SimpleMatch `$pubKey)) {
    ssh-add `$keyPath 2>`$null | Out-Null
  }
}
"@

  Set-Content -Path $scriptPath -Value $taskScript -Encoding utf8

  $taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
  & schtasks.exe /Create /TN $taskName /SC ONLOGON /TR $taskCommand /F | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to create scheduled task fallback: $taskName"
    Write-Host "Manual fallback: run 'ssh-add $keyPath' once after opening a new terminal."
    return
  }

  & schtasks.exe /Run /TN $taskName *> $null
  Write-Host "Created scheduled task fallback: $taskName"
  Write-Host "Task script path: $scriptPath"
  Write-Host "Remove task later with: schtasks /Delete /TN $taskName /F"
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
  # Use Start-Process so the empty string for -P is preserved in the argument list.
  # (PowerShell drops '' when invoking native executables with &, causing "Too many arguments".)
  $proc = Start-Process -FilePath (Get-Command ssh-keygen -ErrorAction Stop).Source `
    -ArgumentList @('-y', '-P', [string]::Empty, '-f', $keyPath) `
    -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput 'NUL' -RedirectStandardError 'NUL'
  if ($proc.ExitCode -eq 0) {
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

function Write-SshConfig([string]$PrivateKeyPath) {
  $sshDir = Join-Path $HOME ".ssh"
  $configPath = Join-Path $sshDir "config"

  # Normalize to forward-slash form that OpenSSH on Windows expects in config files.
  $identityValue = $PrivateKeyPath -replace '\\', '/'

  $marker = "# bootstrap-managed: github.com"
  if ((Test-Path $configPath) -and ((Get-Content -Raw $configPath) -match [regex]::Escape($marker))) {
    return  # already written
  }

  $block = @"
$marker
Host github.com
  IdentityFile $identityValue
  AddKeysToAgent yes
"@
  Add-Content -Path $configPath -Value $block -Encoding utf8
  Write-Host "Wrote SSH config for github.com -> $identityValue"
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

  Write-Host ""
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
  Write-SshConfig -PrivateKeyPath $privateKeyPath
  Write-Host "GitHub SSH connection is ready."
}

# ----------------------------------------
# Step execution dispatcher
# ----------------------------------------

function Invoke-Step([string]$StepName) {
  switch ($StepName) {
    'git' { Ensure-Git; break }
    'ssh' { Run-GitHubSshSetup; break }
    'mise' { Ensure-Mise; break }
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

Ensure-MiseActivationProfile
Ensure-SshAgentProfile
Ensure-GitHubTokenForMise

Write-Host "Public bootstrap complete."
Write-Host ""
Write-Host "NOTE: Open a new terminal window to use newly installed tools (mise)."
