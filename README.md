# Bootstrap-Public

Bootstrap-Public performs one-time workstation bootstrap

It does the following in order:
1. Installs or verifies `git`
2. Runs GitHub SSH setup helper and validates with `ssh -T git@github.com`
3. Installs or verifies `aqua`
4. Installs or verifies `task` from `aqua.yaml`
5. Installs or verifies `apm` using the official installer path
6. Linux only: optional default shell switch flow for `zsh`
7. Linux only: optional `oh-my-zsh` install flow

Default behavior (no step flags) keeps one-line bootstrap flow and runs all steps in this order.

Available step names: `git`, `ssh`, `aqua`, `task`, `apm`, `zsh`, `oh-my-zsh`

Argument format:
- Linux/macOS `bootstrap.sh`:
  - `--step <name>` repeatable
  - `--skip <name>` repeatable
  - `--list-steps`
- Windows `bootstrap.ps1`:
  - `-Step <name[]>`
  - `-SkipStep <name[]>`
  - `-ListSteps`

Rules:
- `step` and `skip` modes are mutually exclusive.
- With `step`, only listed steps execute (in provided order).
- With `skip`, default pipeline executes except skipped steps.
- On interactive Linux/macOS sessions, bootstrap can prompt to switch default shell to `zsh` and then persist PATH in `~/.zshrc`.

## Usage

### Linux and macOS

```sh
./bootstrap.sh
```

Example:

```sh
curl -fsSL https://raw.githubusercontent.com/abuttaro-conga/Bootstrap-Public/main/bootstrap.sh | sh
```

Run only selected steps:

```sh
./bootstrap.sh --step git --step aqua --step task
```

Run full pipeline except one step:

```sh
./bootstrap.sh --skip ssh
```

Linux-only shell customization step examples:

```sh
./bootstrap.sh --step zsh --step oh-my-zsh
./bootstrap.sh --skip zsh --skip oh-my-zsh
```

### GitHub SSH setup only (Linux/macOS)

```sh
./bootstrap.sh --step ssh
```

One-liner:

```sh
curl -fsSL https://raw.githubusercontent.com/abuttaro-conga/Bootstrap-Public/main/bootstrap.sh | sh -s -- --step ssh
```

### Windows PowerShell

```powershell
./bootstrap.ps1
```

If you copy scripts locally and run them from disk, use `ExecutionPolicy Bypass`:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\bootstrap.ps1
PowerShell -ExecutionPolicy Bypass -File .\install-wsl-distro-and-terminal-profile.ps1
```

Example:

```powershell
irm https://raw.githubusercontent.com/abuttaro-conga/Bootstrap-Public/main/bootstrap.ps1 | iex
```

Run only selected steps:

```powershell
./bootstrap.ps1 -Step git,aqua,task
```

Run full pipeline except one step:

```powershell
./bootstrap.ps1 -SkipStep ssh
```

### GitHub SSH setup only (Windows PowerShell)

```powershell
./bootstrap.ps1 -Step ssh
```

One-liner:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/abuttaro-conga/Bootstrap-Public/main/bootstrap.ps1))) -Step ssh
```

## Convenience Mode

If you run in convenience mode (`BOOTSTRAP_CONVENIENCE_MODE=1`), you must acknowledge it:

Linux/macOS:

```sh
BOOTSTRAP_CONVENIENCE_MODE=1 ./bootstrap.sh \
  --convenience-ack
```

PowerShell:

```powershell
$env:BOOTSTRAP_CONVENIENCE_MODE = "1"
./bootstrap.ps1 -ConvenienceAck
```

## Optional Environment Variables

- `BOOTSTRAP_PUBLIC_BASE_URL`: Override bootstrap asset download base URL
- `AQUA_ROOT_DIR`: Override aqua install root

## Bootstrap-Aware Paths

Bootstrap installs and resolves tools from these paths:

- Linux/macOS:
  - `~/.local/bin` (APM)
  - `${AQUA_ROOT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/aquaproj-aqua}/bin` (aqua and aqua-managed tools such as task)
- Windows PowerShell:
  - `$env:LOCALAPPDATA\Programs\apm\bin` (APM)
  - `${env:AQUA_ROOT_DIR:-$env:LOCALAPPDATA\aquaproj-aqua}\bin` (aqua and aqua-managed tools such as task)

To make tools available in all future shells, persist PATH updates.

Linux/macOS (bash/zsh):

```sh
echo 'export PATH="$HOME/.local/bin:${AQUA_ROOT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/aquaproj-aqua}/bin:$PATH"' >> ~/.profile
```

If you use zsh interactively, also add the same line to `~/.zshrc`.

Ubuntu note:
- Ubuntu commonly starts with `bash` as the default login shell.
- In that case bootstrap can switch default shell to `zsh` via `chsh`.
- If you keep `bash`, PATH persistence targets `~/.profile`.

PowerShell (current user profile):

```powershell
if (!(Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }
Add-Content $PROFILE '$aquaRoot = if ($env:AQUA_ROOT_DIR) { $env:AQUA_ROOT_DIR } else { Join-Path $env:LOCALAPPDATA "aquaproj-aqua" }'
Add-Content $PROFILE '$env:Path = "{0};{1};{2}" -f (Join-Path $env:LOCALAPPDATA "Programs\apm\bin"), (Join-Path $aquaRoot "bin"), $env:Path'
```

## Notes

- The SSH helper walks through GitHub SSH setup and tests connectivity using `ssh -T git@github.com`.
- SSH key policy for bootstrap-generated keys:
  - Key algorithm: `ed25519`.
  - Key filename: `~/.ssh/id_ed25519_bootstrap` (public key: `~/.ssh/id_ed25519_bootstrap.pub`).
  - Passphrase: required and must be non-empty.
  - If an empty passphrase is entered, bootstrap deletes the generated key pair and exits with remediation guidance.
- On Linux, `zsh` and `oh-my-zsh` are available as bootstrap steps.
- For strongest integrity guarantees, prefer pinned launcher download plus checksum verification over convenience mode.
