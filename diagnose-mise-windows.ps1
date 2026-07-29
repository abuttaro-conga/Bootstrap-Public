#!/usr/bin/env pwsh
# Diagnostic script for mise PATH issues on Windows

Write-Host "=== Mise PATH Diagnostic ===" -ForegroundColor Cyan
Write-Host ""

# Check if mise is in current PATH
Write-Host "1. Checking if 'mise' is accessible in current session..."
if (Get-Command mise -ErrorAction SilentlyContinue) {
    Write-Host "   ✓ mise IS accessible" -ForegroundColor Green
    (Get-Command mise).Source
} else {
    Write-Host "   ✗ mise NOT accessible" -ForegroundColor Red
}

Write-Host ""
Write-Host "2. Checking winget for jdx.mise installation status..."
try {
    $wingetList = winget list --id jdx.mise 2>&1 | Out-String
    if ($wingetList -like "*jdx.mise*") {
        Write-Host "   ✓ jdx.mise is listed in winget packages" -ForegroundColor Green
        Write-Host "     $($wingetList | Select-String 'jdx.mise' | Select-Object -First 1)"
    } else {
        Write-Host "   ✗ jdx.mise not found in winget packages" -ForegroundColor Red
    }
} catch {
    Write-Host "   ! Could not query winget: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "3. Searching for mise.exe on this system (this may take a moment)..."
Write-Host "   Searching user directory first (fast search)..."

$userSearchPaths = @(
    "$env:LOCALAPPDATA\Programs",
    "$env:LOCALAPPDATA\mise",
    "$env:LOCALAPPDATA\scoop\apps",
    "$HOME\.local\bin"
)

$found = $false
foreach ($searchPath in $userSearchPaths) {
    if (-not (Test-Path $searchPath)) { continue }
    try {
        $result = Get-ChildItem -Path $searchPath -Filter 'mise.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($result) {
            Write-Host "   ✓ Found at: $($result.FullName)" -ForegroundColor Green
            $misePath = Split-Path $result.FullName
            $found = $true
            
            # Offer to add to PATH
            Write-Host ""
            Write-Host "4. Adding to user PATH..."
            $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
            if ($userPath -notlike "*$misePath*") {
                $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
                    $misePath
                } else {
                    "$userPath;$misePath"
                }
                [System.Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
                Write-Host "   ✓ Added to user PATH: $misePath" -ForegroundColor Green
            } else {
                Write-Host "   → Already in user PATH: $misePath" -ForegroundColor Yellow
            }
            break
        }
    } catch { }
}

if (-not $found) {
    Write-Host "   ! Not found in user paths, searching Program Files (slow)..."
    $sysSearchPaths = @(
        "$env:ProgramFiles",
        "${env:ProgramFiles(x86)}"
    )
    
    foreach ($searchPath in $sysSearchPaths) {
        if (-not (Test-Path $searchPath)) { continue }
        Write-Host "     Searching: $searchPath" -ForegroundColor DarkGray
        try {
            $result = Get-ChildItem -Path $searchPath -Filter 'mise.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($result) {
                Write-Host "   ✓ Found at: $($result.FullName)" -ForegroundColor Green
                $misePath = Split-Path $result.FullName
                $found = $true
                
                # Offer to add to PATH
                Write-Host ""
                Write-Host "4. Adding to user PATH..."
                $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
                if ($userPath -notlike "*$misePath*") {
                    $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
                        $misePath
                    } else {
                        "$userPath;$misePath"
                    }
                    [System.Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
                    Write-Host "   ✓ Added to user PATH: $misePath" -ForegroundColor Green
                } else {
                    Write-Host "   → Already in user PATH: $misePath" -ForegroundColor Yellow
                }
                break
            }
        } catch { }
    }
}

if (-not $found) {
    Write-Host "   ✗ mise.exe not found anywhere on this system" -ForegroundColor Red
    Write-Host ""
    Write-Host "   Attempting to reinstall mise..." -ForegroundColor Yellow
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "   Running: winget install --id jdx.mise -e"
        winget install --id jdx.mise -e --accept-package-agreements --accept-source-agreements
    } else {
        Write-Host "   ✗ winget not available. Please install mise manually:" -ForegroundColor Red
        Write-Host "   • Via winget: winget install jdx.mise"
        Write-Host "   • Via scoop: scoop install main/mise"
        Write-Host "   • Via choco: choco install mise"
        Write-Host "   • Manual: https://mise.jdx.dev/getting-started.html"
    }
}

Write-Host ""
Write-Host "5. Verifying after PATH update..."
# Reload PATH from environment variables
$machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path = "$machinePath;$userPath"

if (Get-Command mise -ErrorAction SilentlyContinue) {
    Write-Host "   ✓ mise is now accessible!" -ForegroundColor Green
    try {
        $version = & mise --version 2>&1
        Write-Host "   Version: $version"
    } catch { }
    Write-Host ""
    Write-Host "   NOTE: Close and reopen PowerShell for permanent access" -ForegroundColor Yellow
} else {
    Write-Host "   ✗ mise still not accessible. Try:" -ForegroundColor Red
    Write-Host "   1. Close and reopen PowerShell to reload PATH"
    Write-Host "   2. Run: refreshenv (requires Chocolatey)"
    Write-Host "   3. Report the problem with the findings above"
}
