#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [Alias('d')]
    [string]$DistroName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info {
    param([string]$Message)
    Write-Host $Message
}

function Write-Warn {
    param([string]$Message)
    Write-Warning $Message
}

function Write-Fail {
    param([string]$Message)
    throw $Message
}

function Prompt-YesNo {
    param(
        [string]$Prompt,
        [bool]$DefaultYes = $true
    )

    while ($true) {
        $suffix = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
        $response = Read-Host "$Prompt $suffix"

        if ([string]::IsNullOrWhiteSpace($response)) {
            return $DefaultYes
        }

        switch -Regex ($response.Trim()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$' { return $false }
            default { Write-Warn "Please answer y or n." }
        }
    }
}

function Test-DefenderPluginProbeFailure {
    param([string]$ProbeText)

    if ([string]::IsNullOrWhiteSpace($ProbeText)) {
        return $false
    }

    return ($ProbeText -match 'DefenderforEndpointPlug-in' -or $ProbeText -match 'Wsl/Service/CreateInstance/Plugin/E_UNEXPECTED')
}

function Invoke-WslStartupProbe {
    param([string]$Distro)

    $probeOutput = & wsl.exe -d $Distro --exec /bin/true 2>&1
    $probeExitCode = $LASTEXITCODE
    $probeText = ($probeOutput | ForEach-Object { $_.ToString().TrimEnd() } | Where-Object { $_ } | Out-String).Trim()

    [pscustomobject]@{
        Success = ($probeExitCode -eq 0)
        ExitCode = $probeExitCode
        ProbeText = $probeText
        IsDefenderPluginFailure = (Test-DefenderPluginProbeFailure -ProbeText $probeText)
    }
}

function Get-WslInstalledDistros {
    $distros = @()
    $output = & wsl.exe --list --quiet 2>$null
    foreach ($line in $output) {
        $name = $line.Trim()
        if ($name) {
            $distros += $name
        }
    }

    return $distros
}

function Get-WindowsTerminalSettingsPaths {
    $localAppData = [string]$env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        return @()
    }

    $candidates = @(
        [System.IO.Path]::Combine($localAppData, 'Packages', 'Microsoft.WindowsTerminal_8wekyb3d8bbwe', 'LocalState', 'settings.json'),
        [System.IO.Path]::Combine($localAppData, 'Packages', 'Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe', 'LocalState', 'settings.json'),
        [System.IO.Path]::Combine($localAppData, 'Microsoft', 'Windows Terminal', 'settings.json'),
        [System.IO.Path]::Combine($localAppData, 'Microsoft', 'Windows Terminal Preview', 'settings.json')
    )

    $paths = @()
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            $paths += $candidate
        }
    }

    return $paths
}

function Remove-JsonComments {
    param([string]$Text)

    $builder = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false
    $inLineComment = $false
    $inBlockComment = $false

    for ($index = 0; $index -lt $Text.Length; $index++) {
        $character = $Text[$index]
        $nextCharacter = if ($index + 1 -lt $Text.Length) { $Text[$index + 1] } else { [char]0 }

        if ($inLineComment) {
            if ($character -eq "`n") {
                $inLineComment = $false
                [void]$builder.Append($character)
            }

            continue
        }

        if ($inBlockComment) {
            if ($character -eq '*' -and $nextCharacter -eq '/') {
                $inBlockComment = $false
                $index++
            }

            continue
        }

        if ($inString) {
            [void]$builder.Append($character)

            if ($escaped) {
                $escaped = $false
                continue
            }

            if ($character -eq '\\') {
                $escaped = $true
                continue
            }

            if ($character -eq '"') {
                $inString = $false
            }

            continue
        }

        if ($character -eq '"') {
            $inString = $true
            [void]$builder.Append($character)
            continue
        }

        if ($character -eq '/' -and $nextCharacter -eq '/') {
            $inLineComment = $true
            $index++
            continue
        }

        if ($character -eq '/' -and $nextCharacter -eq '*') {
            $inBlockComment = $true
            $index++
            continue
        }

        [void]$builder.Append($character)
    }

    return $builder.ToString()
}

function Remove-TrailingCommas {
    param([string]$Text)

    $cleaned = $Text
    do {
        $previous = $cleaned
        $cleaned = $cleaned -replace ',(\s*[}\]])', '$1'
    } while ($cleaned -ne $previous)

    return $cleaned
}

function Read-JsonFile {
    param([string]$Path)

    $raw = Get-Content -LiteralPath $Path -Raw
    $sanitized = Remove-TrailingCommas (Remove-JsonComments $raw)
    return $sanitized | ConvertFrom-Json
}

function Write-JsonFile {
    param(
        [string]$Path,
        $InputObject
    )

    $json = $InputObject | ConvertTo-Json -Depth 32
    Set-Content -LiteralPath $Path -Value $json -Encoding utf8
}

function Ensure-ArrayValue {
    param($Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [System.Array]) {
        return @($Value)
    }

    return @($Value)
}

function Add-OrUpdate-WindowsTerminalProfile {
    param(
        [string]$SettingsPath,
        [string]$ProfileName,
        [string]$CommandLine
    )

    $settings = Read-JsonFile -Path $SettingsPath

    if (-not $settings.profiles) {
        $settings | Add-Member -MemberType NoteProperty -Name profiles -Value ([pscustomobject]@{ list = @() })
    }

    if (-not $settings.profiles.list) {
        $settings.profiles | Add-Member -MemberType NoteProperty -Name list -Value @() -Force
    }

    $profiles = Ensure-ArrayValue $settings.profiles.list
    $customMatchIndexes = @()
    $wslSourceMatchIndexes = @()

    for ($index = 0; $index -lt $profiles.Count; $index++) {
        $profile = $profiles[$index]
        if ($profile.name -ne $ProfileName) {
            continue
        }

        $source = ''
        if ($profile.PSObject.Properties.Match('source').Count -gt 0 -and $null -ne $profile.source) {
            $source = [string]$profile.source
        }

        if ($source -eq 'Windows.Terminal.Wsl') {
            $wslSourceMatchIndexes += $index
        } else {
            $customMatchIndexes += $index
        }
    }

    if ($wslSourceMatchIndexes.Count -gt 0) {
        if ($customMatchIndexes.Count -gt 0) {
            $removeSet = [System.Collections.Generic.HashSet[int]]::new()
            foreach ($idx in $customMatchIndexes) {
                [void]$removeSet.Add([int]$idx)
            }

            $deduped = @()
            for ($i = 0; $i -lt $profiles.Count; $i++) {
                if (-not $removeSet.Contains($i)) {
                    $deduped += $profiles[$i]
                }
            }

            $profiles = @($deduped)
            Write-Info "Removed $($customMatchIndexes.Count) duplicate custom profile(s) for '$ProfileName' in '$SettingsPath' because a WSL-generated profile already exists."
        } else {
            Write-Info "WSL-generated profile '$ProfileName' already exists in '$SettingsPath'."
        }
    } elseif ($customMatchIndexes.Count -gt 0) {
        $primaryIndex = $customMatchIndexes[0]
        $profiles[$primaryIndex].name = $ProfileName
        $profiles[$primaryIndex].commandline = $CommandLine
        $profiles[$primaryIndex].hidden = $false

        if ($customMatchIndexes.Count -gt 1) {
            $removeSet = [System.Collections.Generic.HashSet[int]]::new()
            foreach ($idx in $customMatchIndexes[1..($customMatchIndexes.Count - 1)]) {
                [void]$removeSet.Add([int]$idx)
            }

            $deduped = @()
            for ($i = 0; $i -lt $profiles.Count; $i++) {
                if (-not $removeSet.Contains($i)) {
                    $deduped += $profiles[$i]
                }
            }

            $profiles = @($deduped)
            Write-Info "Updated profile '$ProfileName' and removed $($customMatchIndexes.Count - 1) duplicate custom profile(s) in '$SettingsPath'."
        } else {
            Write-Info "Updated existing Windows Terminal profile '$ProfileName' in '$SettingsPath'."
        }
    } else {
        $profiles += [pscustomobject]@{
            guid        = "{$([guid]::NewGuid().ToString())}"
            name        = $ProfileName
            commandline = $CommandLine
            hidden      = $false
        }

        Write-Info "Added Windows Terminal profile '$ProfileName' to '$SettingsPath'."
    }

    $settings.profiles.list = @($profiles)

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $backupPath = "$SettingsPath.bak.$timestamp"
    Copy-Item -LiteralPath $SettingsPath -Destination $backupPath
    Write-Info "Backup written to '$backupPath'."

    Write-JsonFile -Path $SettingsPath -InputObject $settings
}

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    Write-Fail 'This script must run on Windows.'
}

Write-Info "Checking WSL distro '$DistroName'."
$installedDistros = @(Get-WslInstalledDistros)

if ($installedDistros -notcontains $DistroName) {
    Write-Info "Installing WSL distro '$DistroName'."
    & wsl.exe --install --no-launch -d $DistroName
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "wsl --install -d $DistroName failed with exit code $LASTEXITCODE."
    }
} else {
    Write-Info "WSL distro '$DistroName' is already installed."
}

Write-Info "Starting WSL distro '$DistroName'."
$probeResult = Invoke-WslStartupProbe -Distro $DistroName
if (-not $probeResult.Success) {
    if ($probeResult.IsDefenderPluginFailure) {
        Write-Warn "WSL startup probe failed due to Defender for Endpoint plugin. Distro install succeeded and can still be valid."
    } else {
        Write-Warn "WSL startup probe could not complete (exit code: $($probeResult.ExitCode))."
    }

    if ($probeResult.ProbeText) {
        Write-Warn "WSL probe output:`n$($probeResult.ProbeText)"
    }

    if ($probeResult.IsDefenderPluginFailure -and [System.Environment]::UserInteractive) {
        $restartWsl = Prompt-YesNo -Prompt "Run 'wsl --shutdown' and retry startup probe now?"
        if ($restartWsl) {
            Write-Info 'Running wsl --shutdown.'
            & wsl.exe --shutdown
            if ($LASTEXITCODE -eq 0) {
                Write-Info "Retrying WSL startup probe for '$DistroName'."
                $retryProbeResult = Invoke-WslStartupProbe -Distro $DistroName
                if ($retryProbeResult.Success) {
                    Write-Info 'WSL startup probe succeeded after shutdown/retry.'
                } else {
                    Write-Warn "WSL startup probe still failed (exit code: $($retryProbeResult.ExitCode))."
                    if ($retryProbeResult.ProbeText) {
                        Write-Warn "Retry probe output:`n$($retryProbeResult.ProbeText)"
                    }
                    Write-Warn "You can retry manually with: wsl --shutdown; wsl.exe -d $DistroName"
                }
            } else {
                Write-Warn "wsl --shutdown failed with exit code $LASTEXITCODE."
                Write-Warn "Retry manually with: wsl --shutdown; wsl.exe -d $DistroName"
            }
        } else {
            Write-Warn "Continuing without restart. If first launch fails, run: wsl --shutdown; wsl.exe -d $DistroName"
        }
    } else {
        Write-Warn "Continuing because the distro is installed. If first launch fails, run: wsl --shutdown; wsl.exe -d $DistroName"
    }
}

$settingsPaths = @(Get-WindowsTerminalSettingsPaths)
if ($settingsPaths.Count -eq 0) {
    Write-Fail 'Windows Terminal settings.json was not found in any known location.'
}

$commandLine = "wsl.exe -d $DistroName --cd ~"
foreach ($settingsPath in $settingsPaths) {
    Add-OrUpdate-WindowsTerminalProfile -SettingsPath $settingsPath -ProfileName $DistroName -CommandLine $commandLine
}

Write-Info 'Done.'