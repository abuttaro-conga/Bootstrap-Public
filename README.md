# Bootstrap-Public

One-time workstation bootstrap. Runs four steps in order:

1. Installs or verifies `git`
2. GitHub SSH setup — generates an Ed25519 key, walks through GitHub key registration, validates with `ssh -T git@github.com`
3. Installs or verifies `mise`
4. Installs `gh` CLI, authenticates with GitHub, and configures mise GitHub token settings

After steps complete, bootstrap automatically configures shells:

**mise activation** (all platforms)
- Linux bash: `eval` activation written to `~/.bashrc`
- Linux zsh: if missing, bootstrap offers to install `zsh` (prompt defaults to yes)
- Linux zsh: if installed but not your login shell, bootstrap offers to set zsh as default (prompt defaults to yes)
- Linux zsh with oh-my-zsh missing: bootstrap offers to install oh-my-zsh (prompt defaults to yes)
- Linux zsh with oh-my-zsh: bootstrap adds `mise` to the plugins list
- Linux zsh with oh-my-zsh but no built-in `mise` plugin: bootstrap installs a custom oh-my-zsh `mise` plugin and adds `mise` to the plugins list
- Linux zsh fallback: if zsh or oh-my-zsh install is declined, `eval` activation is written to `~/.zshrc`

**SSH agent** (Linux): configures `~/.bashrc` and `~/.zshrc` to start `ssh-agent` automatically — your SSH key passphrase is prompted once per session, not on every `git` operation. Uses the systemd user service when available, falls back to a profile snippet.

Step names: `git`, `ssh`, `mise`, `gh`

**gh step** (`gh`)
- Installs GitHub CLI globally via `mise use -g gh`
- **WSL2 only:** sets `mise config set env.BROWSER` to `powershell.exe /c start` so `gh auth login` opens the browser on the Windows host — prompted when interactive (defaults to yes), auto-applied when non-interactive; skipped if already configured
- Runs `gh auth login` if not already authenticated (interactive; emits an action-required reminder when no terminal is available)
- Applies recommended mise GitHub token settings:
  - `github.credential_command` (always): `gh auth token --hostname "$MISE_CREDENTIAL_HOST"` — used by mise to install tools from private GitHub repos
  - `github.use_git_credentials` (optional, prompted): keychain-backed fallback
- Verifies token resolution with `mise token github`

> **Note:** The `ssh` step and the `gh` step serve different purposes. `ssh` authenticates git transport (`git@github.com`). `gh` provides the OAuth token mise needs to download release assets from private repos. Both are needed.

Argument format:
- `--step <name>` (repeatable), `--skip <name>` (repeatable), `--list-steps`

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

## Uninstall

An uninstall script is provided for Linux/macOS/WSL.

Important behavior:
- Every uninstall operation is prompted individually.
- Prompt default is `N` (`No`) for every step.
- No changes are made unless you explicitly answer `y`.

Linux/macOS/WSL:

```sh
sh ./uninstall.sh
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
| Core | Ensure `git` is installed | `bootstrap.sh` | No | Runs in default `git` step |
| Core | GitHub SSH setup flow (key generation + test) | `bootstrap.sh` | No | Runs in default `ssh` step |
| SSH | Generate bootstrap SSH key (`id_ed25519_bootstrap`) if missing | `bootstrap.sh` | Conditional | Only when key does not already exist |
| SSH | Enforce non-empty passphrase for generated key | `bootstrap.sh` | No | Always enforced during key generation |
| SSH | Prompt to add public key to GitHub and confirm | `bootstrap.sh` | No | Interactive checkpoint in SSH flow |
| SSH | Write GitHub SSH host config | `bootstrap.sh` | Conditional | Skips if bootstrap marker already present |
| Core | Ensure `mise` is installed | `bootstrap.sh` | No | Runs in default `mise` step |
| gh | Install `gh` CLI globally via `mise use -g gh` | `bootstrap.sh` | Conditional | Skips if `gh` already available via mise |
| gh | Set WSL2 `BROWSER` for Windows host browser launch | `bootstrap.sh` | Conditional | Prompted when interactive (default Y), auto-applied when non-interactive; only when `$WSL_DISTRO_NAME` is set and not already configured |
| gh | Run `gh auth login` | `bootstrap.sh` | Conditional | Skips if already authenticated; emits action-required reminder when non-interactive |
| gh | Set `github.credential_command` in mise settings | `bootstrap.sh` | No | Applied after successful auth; skipped when `GITHUB_TOKEN` env var is set or when non-interactive auth was not possible |
| gh | Set `github.use_git_credentials` in mise settings | `bootstrap.sh` | Yes | Optional fallback; prompted when interactive, silently skipped when non-interactive |
| gh | Verify mise GitHub token with `mise token github` | `bootstrap.sh` | No | Emits action-required reminder on failure |
| PATH | Add mise-related paths to current process PATH | `bootstrap.sh` | No | Always applied during run |
| PATH | Persist PATH updates in shell/profile files | `bootstrap.sh` | Conditional | If missing and accepted (or non-interactive auto-persist) |
| Activation | Add `mise` activation to `~/.bashrc` | `bootstrap.sh` | No | Idempotent block write |
| Activation | Add `mise` activation to `~/.zshrc` | `bootstrap.sh` | Conditional | When zsh exists or zsh profile selected |
| Linux UX | Offer install of `zsh` | `bootstrap.sh` | Yes | Prompted when `zsh` is missing |
| Linux UX | Offer install of oh-my-zsh | `bootstrap.sh` | Yes | Prompted when oh-my-zsh is missing |
| Linux UX | Offer setting zsh as default login shell | `bootstrap.sh` | Yes | Prompted when login shell is not zsh |
| Linux UX | Add `mise` to oh-my-zsh plugins | `bootstrap.sh` | Conditional | When oh-my-zsh is present |
| Linux UX | Install custom oh-my-zsh `mise` plugin | `bootstrap.sh` | Conditional | When built-in plugin is absent |
| SSH Agent | Configure SSH agent via systemd user service | `bootstrap.sh` | Conditional | Preferred path when service exists and can be enabled |
| SSH Agent | Configure SSH agent via shell profile snippet | `bootstrap.sh` | Conditional | Fallback when systemd user service path is unavailable |
| Safety | Idempotent profile/config writes using markers | `bootstrap.sh` | No | Re-runs avoid duplicate blocks |
| Summary | Print action-required reminders (for manual follow-up) | `bootstrap.sh` | Conditional | Shown when automated shell change fails |

## Notes

- The SSH helper walks through GitHub SSH setup and tests connectivity using `ssh -T git@github.com`.
- Bootstrap modifies only user-scoped resources: home-directory files (`~/.bashrc`, `~/.zshrc`, `~/.oh-my-zsh/plugins`). No system-wide changes.
- SSH key policy for bootstrap-generated keys:
  - Algorithm: `ed25519`
  - Filename: `~/.ssh/id_ed25519_bootstrap` (public: `~/.ssh/id_ed25519_bootstrap.pub`)
  - Suggested GitHub key title is generated from OS, architecture, and hostname (e.g. `bootstrap-generated-linux-x86_64-myhost`; on WSL, includes the distro name)
  - Passphrase: required and non-empty; bootstrap rejects empty passphrases and prompts again
  - SSH setup is interactive: you'll be prompted for an email address (for key comment) and to add the public key to GitHub
- All shell profile writes use idempotency markers — re-running bootstrap is safe and will skip steps that are already configured.
