# Bootstrap-Public

Bootstrap-Public performs one-time workstation bootstrap

It does the following in order:
1. Installs or verifies `git`
2. Runs GitHub SSH setup helper and validates with `ssh -T git@github.com`
3. Installs or verifies `aqua`
4. Installs or verifies `task` from `aqua.yaml`
5. Installs or verifies `apm` using the official installer path

Default behavior (no step flags) keeps one-line bootstrap flow and runs all steps in this order.

Available step names: `git`, `ssh`, `aqua`, `task`, `apm`

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

## Notes

- The SSH helper walks through GitHub SSH setup and tests connectivity using `ssh -T git@github.com`.
- For strongest integrity guarantees, prefer pinned launcher download plus checksum verification over convenience mode.
