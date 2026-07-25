# Bootstrap-Public

One-time workstation bootstrap. Runs three steps in order:

1. Installs or verifies `git`
2. GitHub SSH setup — generates an Ed25519 key, walks through GitHub key registration, validates with `ssh -T git@github.com`
3. Installs or verifies `mise`

After steps complete, bootstrap automatically configures shells without further prompts:

**mise activation** (all platforms)
- Linux bash: `eval` activation written to `~/.bashrc`
- Linux zsh with oh-my-zsh (mise plugin present): adds `mise` to the plugins list
- Linux zsh with oh-my-zsh (no mise plugin): `eval` activation written to `~/.zshrc`; if oh-my-zsh is not yet installed and the session is interactive, bootstrap prompts to install it first
- Windows PowerShell: `(& mise activate pwsh) | Out-String | Invoke-Expression` written to `$PROFILE`

**SSH agent** (Linux): configures `~/.bashrc` and `~/.zshrc` to start `ssh-agent` automatically — your SSH key passphrase is prompted once per session, not on every `git` operation. Uses the systemd user service when available, falls back to a profile snippet.

**SSH agent** (Windows): adds a key-load snippet to `$PROFILE` so the passphrase is prompted once per terminal session.

Step names: `git`, `ssh`, `mise`

Argument format:
- Linux/macOS `bootstrap.sh`: `--step <name>` (repeatable), `--skip <name>` (repeatable), `--list-steps`
- Windows `bootstrap.ps1`: `-Step <name[]>`, `-SkipStep <name[]>`, `-ListSteps`

Rules: `--step` and `--skip` are mutually exclusive. With `--step`, only listed steps run in provided order. With `--skip`, all default steps run except the skipped ones.

## Usage

### Linux and macOS

Full bootstrap:

```sh
curl -fsSL https://raw.githubusercontent.com/abuttaro-conga/Bootstrap-Public/main/bootstrap.sh | sh
```

Run only selected steps:

```sh
curl -fsSL https://raw.githubusercontent.com/abuttaro-conga/Bootstrap-Public/main/bootstrap.sh | sh -s -- --step git --step mise
```

Skip a step:

```sh
curl -fsSL https://raw.githubusercontent.com/abuttaro-conga/Bootstrap-Public/main/bootstrap.sh | sh -s -- --skip ssh
```

### Windows (WSL2)

For Windows users who want a Linux environment via WSL 2. See [WSL.md](WSL.md) for first-time WSL install steps and general guidance.

The script below installs the named distro (if not already present), initializes it, and adds or updates a Windows Terminal profile for it. After it completes, open a terminal session in the new distro and follow the **Linux and macOS** steps above to bootstrap it.

Requires `-DistroName` (e.g. `Ubuntu-24.04`):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/abuttaro-conga/Bootstrap-Public/main/scripts/install-wsl-distro-and-terminal-profile.ps1))) -DistroName Ubuntu-24.04
```

### Windows (PowerShell)

For Windows users who want a native Windows developer environment.

Full bootstrap:

```powershell
irm https://raw.githubusercontent.com/abuttaro-conga/Bootstrap-Public/main/bootstrap.ps1 | iex
```

Run only selected steps:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/abuttaro-conga/Bootstrap-Public/main/bootstrap.ps1))) -Step git,mise
```

Skip a step:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/abuttaro-conga/Bootstrap-Public/main/bootstrap.ps1))) -SkipStep ssh
```

If running from a local copy, use `ExecutionPolicy Bypass`:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\bootstrap.ps1
```

## Optional Environment Variables

- `MISE_DATA_DIR` (Linux/macOS): Overrides the mise data directory. Bootstrap uses `$MISE_DATA_DIR/bin` (default: `~/.local/share/mise/bin`, or `$XDG_DATA_HOME/mise/bin` if `XDG_DATA_HOME` is set) when adding mise to PATH. Only needed if mise was installed with a non-default `MISE_DATA_DIR`.

## Notes

- The SSH helper walks through GitHub SSH setup and tests connectivity using `ssh -T git@github.com`.
- Bootstrap modifies only files in your home directory (`~/.bashrc`, `~/.zshrc`, `~/.oh-my-zsh/plugins`, `$PROFILE`). No system-wide changes.
- SSH key policy for bootstrap-generated keys:
  - Algorithm: `ed25519`
  - Filename: `~/.ssh/id_ed25519_bootstrap` (public: `~/.ssh/id_ed25519_bootstrap.pub`)
  - Suggested GitHub key title is generated from OS, architecture, and hostname (e.g. `bootstrap-generated-linux-x86_64-myhost`; on WSL, includes the distro name)
  - Passphrase: required and non-empty; bootstrap rejects empty passphrases and prompts again
  - SSH setup is interactive: you'll be prompted for an email address (for key comment) and to add the public key to GitHub
- All shell profile writes use idempotency markers — re-running bootstrap is safe and will skip steps that are already configured.
