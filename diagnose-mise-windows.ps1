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
Write-Host "2. Searching for mise executable in common locations..."

$searchPaths = @(
    "$env:LOCALAPPDATA\Programs\mise\bin",
    "$env:ProgramFiles\mise\bin",
    "${env:ProgramFiles(x86)}\mise\bin",
    "$env:LOCALAPPDATA\mise\bin",
    "$HOME\.local\bin",
    "$env:LOCALAPPDATA\mise",
    "$env:LOCALAPPDATA\scoop\apps\mise\current\bin",
    "C:\Program Files\mise\bin",
    "C:\Program Files (x86)\mise\bin"
)

$found = $false
foreach ($path in $searchPaths) {
    $misePath = Join-Path $path 'mise.exe'
    if (Test-Path $misePath) {
        Write-Host "   ✓ Found at: $misePath" -ForegroundColor Green
        $found = $true
        
        # Offer to add to PATH
        Write-Host ""
        Write-Host "3. Adding to user PATH..."
        $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
        if ($userPath -notlike "*$path*") {
            $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
                $path
            } else {
                "$userPath;$path"
            }
            [System.Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
            Write-Host "   ✓ Added to user PATH: $path" -ForegroundColor Green
        } else {
            Write-Host "   → Already in user PATH: $path" -ForegroundColor Yellow
        }
        break
    }
}

if (-not $found) {
    Write-Host "   ✗ mise executable not found in any standard location" -ForegroundColor Red
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
Write-Host "4. Verifying after PATH update..."
# Reload PATH from environment variables
$machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path = "$machinePath;$userPath"

if (Get-Command mise -ErrorAction SilentlyContinue) {
    Write-Host "   ✓ mise is now accessible!" -ForegroundColor Green
    Write-Host "   Version: $(mise --version)"
    Write-Host ""
    Write-Host "   NOTE: Close and reopen PowerShell for permanent access" -ForegroundColor Yellow
} else {
    Write-Host "   ✗ mise still not accessible. Try:" -ForegroundColor Red
    Write-Host "   1. Close and reopen PowerShell to reload PATH"
    Write-Host "   2. Run: refreshenv (requires Chocolatey)"
    Write-Host "   3. Manually verify mise was installed to a known location"
}
