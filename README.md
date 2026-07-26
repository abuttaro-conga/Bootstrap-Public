# Bootstrap-Public

One-time workstation bootstrap. Runs three steps in order:

1. Installs or verifies `git`
2. GitHub SSH setup — generates an Ed25519 key, walks through GitHub key registration, validates with `ssh -T git@github.com`
3. Installs or verifies `mise`

After steps complete, bootstrap automatically configures shells:

**mise activation** (all platforms)
- Linux bash: `eval` activation written to `~/.bashrc`
- Linux zsh: if missing, bootstrap offers to install `zsh` (prompt defaults to yes)
- Linux zsh: if installed but not your login shell, bootstrap offers to set zsh as default (prompt defaults to yes)
- Linux zsh with oh-my-zsh missing: bootstrap offers to install oh-my-zsh (prompt defaults to yes)
- Linux zsh with oh-my-zsh: bootstrap adds `mise` to the plugins list
- Linux zsh with oh-my-zsh but no built-in `mise` plugin: bootstrap installs a custom oh-my-zsh `mise` plugin and adds `mise` to the plugins list
- Linux zsh fallback: if zsh or oh-my-zsh install is declined, `eval` activation is written to `~/.zshrc`
- Windows PowerShell: tries to write `(& mise activate pwsh) | Out-String | Invoke-Expression` to `$PROFILE`
- Windows PowerShell (restricted execution policy): skips profile writes, persists mise paths in User `PATH`, and continues without failing startup

**SSH agent** (Linux): configures `~/.bashrc` and `~/.zshrc` to start `ssh-agent` automatically — your SSH key passphrase is prompted once per session, not on every `git` operation. Uses the systemd user service when available, falls back to a profile snippet.

**SSH agent** (Windows): adds a key-load snippet to `$PROFILE` so the passphrase is prompted once per terminal session.

If Windows execution policy blocks unsigned profiles (`AllSigned` / `Restricted`), bootstrap can offer an opt-in user-level Scheduled Task fallback to start `ssh-agent` and load the bootstrap key at logon.

**GitHub auth token** (Windows): when `gh` is authenticated, bootstrap can offer to persist `GH_TOKEN` and `GITHUB_TOKEN` at User scope so `mise` can access private GitHub release assets in new terminals.

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


## Script Behavior Matrix

Legend:
- `No` = always part of default bootstrap behavior (unless user explicitly skips the step)
- `Conditional` = runs only when a condition is met
- `Yes` = optional by user choice (prompted opt-in/opt-out)

| Area | Action | Script(s) | Optional? | Condition / Notes |
|---|---|---|---|---|
| Core | Ensure `git` is installed | `bootstrap.sh`, `bootstrap.ps1` | No | Runs in default `git` step |
| Core | GitHub SSH setup flow (key generation + test) | `bootstrap.sh`, `bootstrap.ps1` | No | Runs in default `ssh` step |
| SSH | Generate bootstrap SSH key (`id_ed25519_bootstrap`) if missing | `bootstrap.sh`, `bootstrap.ps1` | Conditional | Only when key does not already exist |
| SSH | Enforce non-empty passphrase for generated key | `bootstrap.sh`, `bootstrap.ps1` | No | Always enforced during key generation |
| SSH | Prompt to add public key to GitHub and confirm | `bootstrap.sh`, `bootstrap.ps1` | No | Interactive checkpoint in SSH flow |
| SSH | Write GitHub SSH host config | `bootstrap.sh`, `bootstrap.ps1` | Conditional | Skips if bootstrap marker already present |
| Core | Ensure `mise` is installed | `bootstrap.sh`, `bootstrap.ps1` | No | Runs in default `mise` step |
| PATH | Add mise-related paths to current process PATH | `bootstrap.sh`, `bootstrap.ps1` | No | Always applied during run |
| PATH | Persist PATH updates in shell/profile files | `bootstrap.sh` | Conditional | If missing and accepted (or non-interactive auto-persist) |
| PATH | Persist PATH updates to Windows User PATH | `bootstrap.ps1` | No | Used so tools work in new terminals |
| Activation | Add `mise` activation to `~/.bashrc` | `bootstrap.sh` | No | Idempotent block write |
| Activation | Add `mise` activation to `~/.zshrc` | `bootstrap.sh` | Conditional | When zsh exists or zsh profile selected |
| Activation | Add `mise` activation to PowerShell `$PROFILE` | `bootstrap.ps1` | Conditional | Skipped when execution policy blocks unsigned profile scripts |
| Linux UX | Offer install of `zsh` | `bootstrap.sh` | Yes | Prompted when `zsh` is missing |
| Linux UX | Offer install of oh-my-zsh | `bootstrap.sh` | Yes | Prompted when oh-my-zsh is missing |
| Linux UX | Offer setting zsh as default login shell | `bootstrap.sh` | Yes | Prompted when login shell is not zsh |
| Linux UX | Add `mise` to oh-my-zsh plugins | `bootstrap.sh` | Conditional | When oh-my-zsh is present |
| Linux UX | Install custom oh-my-zsh `mise` plugin | `bootstrap.sh` | Conditional | When built-in plugin is absent |
| SSH Agent | Configure SSH agent via systemd user service | `bootstrap.sh` | Conditional | Preferred path when service exists and can be enabled |
| SSH Agent | Configure SSH agent via shell profile snippet | `bootstrap.sh` | Conditional | Fallback when systemd user service path is unavailable |
| SSH Agent | Configure SSH key-load snippet in PowerShell profile | `bootstrap.ps1` | Conditional | Skipped when policy blocks profile scripting |
| SSH Agent | Offer scheduled task fallback for SSH key load | `bootstrap.ps1` | Yes | Prompted only when profile scripting is blocked |
| GitHub Auth | Offer `gh auth login` if `gh` is unauthenticated | `bootstrap.ps1` | Yes | Interactive prompt before token persistence |
| GitHub Auth | Offer persisting `GH_TOKEN` / `GITHUB_TOKEN` (User scope) | `bootstrap.ps1` | Yes | Prompted when gh auth is available |
| Safety | Idempotent profile/config writes using markers | `bootstrap.sh`, `bootstrap.ps1` | No | Re-runs avoid duplicate blocks |
| Summary | Print action-required reminders (for manual follow-up) | `bootstrap.sh` | Conditional | Shown when automated shell change fails |

## Notes

- The SSH helper walks through GitHub SSH setup and tests connectivity using `ssh -T git@github.com`.
- Bootstrap modifies only user-scoped resources: home-directory files (`~/.bashrc`, `~/.zshrc`, `~/.oh-my-zsh/plugins`, `$PROFILE`), user environment variables (Windows User `PATH`, optional `GH_TOKEN`/`GITHUB_TOKEN`), and optional user-level Scheduled Task fallback. No system-wide changes.
- SSH key policy for bootstrap-generated keys:
  - Algorithm: `ed25519`
  - Filename: `~/.ssh/id_ed25519_bootstrap` (public: `~/.ssh/id_ed25519_bootstrap.pub`)
  - Suggested GitHub key title is generated from OS, architecture, and hostname (e.g. `bootstrap-generated-linux-x86_64-myhost`; on WSL, includes the distro name)
  - Passphrase: required and non-empty; bootstrap rejects empty passphrases and prompts again
  - SSH setup is interactive: you'll be prompted for an email address (for key comment) and to add the public key to GitHub
- All shell profile writes use idempotency markers — re-running bootstrap is safe and will skip steps that are already configured.
