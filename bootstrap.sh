#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
convenience_ack=0
list_steps=0
show_help=0
requested_steps=""
skip_steps=""
bootstrap_base_url="${BOOTSTRAP_PUBLIC_BASE_URL:-https://raw.githubusercontent.com/abuttaro-conga/Bootstrap-Public/main}"
default_step_order="git ssh aqua task apm"

# ----------------------------------------
# Output helpers
# ----------------------------------------

say() {
  printf '%s\n' "$*"
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

download_to_stdout() {
  url=$1
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url"
    return
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO- "$url"
    return
  fi
  fail "curl or wget required"
}

# ----------------------------------------
# Validation and argument helpers
# ----------------------------------------

run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return
  fi
  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
    return
  fi
  fail "elevation required to install missing system packages"
}

require_cmd() {
  cmd_name=$1
  command -v "$cmd_name" >/dev/null 2>&1 || fail "$cmd_name is required"
}

is_valid_step_name() {
  case "$1" in
    git|ssh|aqua|task|apm)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

contains_token() {
  token=$1
  list=$2
  for item in $list; do
    [ "$item" = "$token" ] && return 0
  done
  return 1
}

add_unique_token() {
  list=$1
  token=$2
  if contains_token "$token" "$list"; then
    printf '%s' "$list"
    return
  fi
  if [ -n "$list" ]; then
    printf '%s %s' "$list" "$token"
  else
    printf '%s' "$token"
  fi
}

print_step_list() {
  printf '%s\n' git ssh aqua task apm
}

print_help() {
  cat <<'EOF'
Usage:
  ./bootstrap.sh [--convenience-ack] [--step <name> ... | --skip <name> ...] [--list-steps] [--help]

Behavior:
  - No step flags: runs full default flow (git -> ssh -> aqua -> task -> apm)
  - --step: run only specified steps, in provided order
  - --skip: run default flow except skipped steps

Options:
  --step <name>         Repeatable. Step names: git, ssh, aqua, task, apm
  --skip <name>         Repeatable. Step names: git, ssh, aqua, task, apm
  --list-steps          Print valid step names and exit
  --convenience-ack     Required when BOOTSTRAP_CONVENIENCE_MODE=1
  -h, --help            Show this help and exit

Examples:
  ./bootstrap.sh
  ./bootstrap.sh --step ssh
  ./bootstrap.sh --step git --step aqua --step task
  ./bootstrap.sh --skip ssh
EOF
}

# ----------------------------------------
# Tool path setup
# ----------------------------------------

ensure_aqua_path() {
  aqua_bin="${AQUA_ROOT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/aquaproj-aqua}/bin"
  PATH="$aqua_bin:$PATH"
  export PATH
}

ensure_local_bin_path() {
  PATH="$HOME/.local/bin:$PATH"
  export PATH
}

# ----------------------------------------
# Install steps
# ----------------------------------------

install_git() {
  if command -v git >/dev/null 2>&1; then
    say "git already installed"
    return
  fi

  say "Installing git"
  if command -v brew >/dev/null 2>&1; then
    brew install git
  elif command -v apt-get >/dev/null 2>&1; then
    run_as_root apt-get update
    run_as_root apt-get install -y git
  elif command -v dnf >/dev/null 2>&1; then
    run_as_root dnf install -y git
  elif command -v yum >/dev/null 2>&1; then
    run_as_root yum install -y git
  elif command -v zypper >/dev/null 2>&1; then
    run_as_root zypper --non-interactive install git
  elif command -v pacman >/dev/null 2>&1; then
    run_as_root pacman -Sy --noconfirm git
  elif command -v apk >/dev/null 2>&1; then
    run_as_root apk add git
  else
    fail "git not found and no supported package manager detected"
  fi

  command -v git >/dev/null 2>&1 || fail "git install failed"
}

install_aqua() {
  ensure_aqua_path
  if command -v aqua >/dev/null 2>&1; then
    say "aqua already installed"
    return
  fi
  command -v bash >/dev/null 2>&1 || fail "bash required to install aqua"
  say "Installing aqua"
  download_to_stdout "https://raw.githubusercontent.com/aquaproj/aqua-installer/v4.0.5/aqua-installer" | bash
  ensure_aqua_path
  command -v aqua >/dev/null 2>&1 || fail "aqua install failed"
}

install_task() {
  ensure_aqua_path
  if command -v task >/dev/null 2>&1; then
    say "task already installed"
    return
  fi
  if ! command -v aqua >/dev/null 2>&1; then
    fail "aqua is required before task; run with --step aqua --step task or no step flags"
  fi
  say "Installing task via aqua"

  aqua_config="$script_dir/aqua.yaml"
  cleanup_tmp=0
  if [ ! -f "$aqua_config" ]; then
    aqua_config=$(mktemp)
    cleanup_tmp=1
    download_to_stdout "$bootstrap_base_url/aqua.yaml" >"$aqua_config"
  fi

  AQUA_CONFIG="$aqua_config" aqua i

  if [ "$cleanup_tmp" -eq 1 ]; then
    rm -f "$aqua_config"
  fi

  ensure_aqua_path
  command -v task >/dev/null 2>&1 || fail "task install failed"
}

install_apm() {
  ensure_local_bin_path
  if command -v apm >/dev/null 2>&1; then
    say "apm already installed"
    return
  fi
  say "Installing apm"
  mkdir -p "$HOME/.local/bin"
  download_to_stdout "https://aka.ms/apm-unix" | APM_INSTALL_DIR="$HOME/.local/bin" sh
  ensure_local_bin_path
  command -v apm >/dev/null 2>&1 || fail "apm install failed"
}

# ----------------------------------------
# SSH setup step
# ----------------------------------------

run_github_ssh_setup() {
  prompt_text="Have you added this key to GitHub?"

  prompt_yes_no() {
    [ -r /dev/tty ] || fail "Interactive terminal required for SSH setup prompts"
    while :; do
      printf '%s [y/n]: ' "$prompt_text" >/dev/tty
      if ! IFS= read -r answer </dev/tty; then
        return 1
      fi
      case "$answer" in
        y|Y|yes|YES)
          return 0
          ;;
        n|N|no|NO)
          return 1
          ;;
        *)
          say "Please answer y or n."
          ;;
      esac
    done
  }

  pick_public_key() {
    if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
      printf '%s\n' "$HOME/.ssh/id_ed25519.pub"
      return
    fi
    if [ -f "$HOME/.ssh/id_rsa.pub" ]; then
      printf '%s\n' "$HOME/.ssh/id_rsa.pub"
      return
    fi
    printf '%s\n' ""
  }

  generate_ssh_key_if_needed() {
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    existing_key=$(pick_public_key)
    if [ -n "$existing_key" ]; then
      say "Found existing SSH public key: $existing_key"
      return
    fi

    [ -r /dev/tty ] || fail "No SSH key found and no interactive terminal available for key generation"

    say "No SSH key found. Creating a new Ed25519 key."
    default_user=${USER:-$(id -un 2>/dev/null || true)}
    if [ -z "$default_user" ]; then
      default_user=user
    fi
    default_email="${default_user}@conga.com"

    printf '%s' "Email for SSH key comment [$default_email]: " >/dev/tty
    IFS= read -r email </dev/tty
    if [ -z "$email" ]; then
      email=$default_email
    fi

    key_path="$HOME/.ssh/id_ed25519"
    ssh-keygen -t ed25519 -C "$email" -f "$key_path" -N ""
  }

  start_agent_and_add_key() {
    key_path=$1
    eval "$(ssh-agent -s)" >/dev/null
    ssh-add "$key_path" >/dev/null 2>&1 || fail "Failed to add SSH key to ssh-agent"
  }

  test_ssh_connection() {
    set +e
    ssh_output=$(ssh -T git@github.com 2>&1)
    ssh_status=$?
    set -e

    printf '%s\n' "$ssh_output"

    if printf '%s' "$ssh_output" | grep -qi "successfully authenticated"; then
      return
    fi

    if [ "$ssh_status" -eq 1 ] && printf '%s' "$ssh_output" | grep -qi "You've successfully authenticated"; then
      return
    fi

    fail "SSH test failed. Follow GitHub docs and rerun this script."
  }

  say "GitHub SSH setup helper"
  say "Guide: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/testing-your-ssh-connection"

  require_cmd git
  require_cmd ssh
  require_cmd ssh-keygen
  require_cmd ssh-agent
  require_cmd ssh-add

  generate_ssh_key_if_needed
  public_key=$(pick_public_key)
  [ -n "$public_key" ] || fail "No public SSH key available"
  private_key=${public_key%.pub}

  start_agent_and_add_key "$private_key"

  _distro=""
  if [ -f /etc/os-release ]; then
    _distro=$(. /etc/os-release && printf '%s-%s' "$NAME" "$VERSION_ID" | tr ' ' '-')
  fi
  if grep -qi microsoft /proc/version 2>/dev/null; then
    _suggested_title="bootstrap-generated-wsl-${_distro}-$(hostname)"
  else
    _suggested_title="bootstrap-generated-${_distro}-$(hostname)"
  fi

  say ""
  say "Suggested key title: $_suggested_title"
  say "Add this SSH public key to your GitHub account:"
  cat "$public_key"
  say ""
  say "GitHub key settings URL: https://github.com/settings/keys"

  if [ -r /dev/tty ]; then
    if prompt_yes_no; then
      :
    else
      fail "Add the SSH key in GitHub, then rerun this script"
    fi
  fi

  say "Running SSH test command: ssh -T git@github.com"
  test_ssh_connection
  say "GitHub SSH connection is ready."
}

# ----------------------------------------
# Step execution dispatcher
# ----------------------------------------

execute_step() {
  step_name=$1
  case "$step_name" in
    git)
      install_git
      ;;
    ssh)
      run_github_ssh_setup
      ;;
    aqua)
      install_aqua
      ;;
    task)
      install_task
      ;;
    apm)
      install_apm
      ;;
    *)
      fail "unknown step: $step_name"
      ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --step)
      [ $# -ge 2 ] || fail "--step requires a value"
      step_name=$2
      is_valid_step_name "$step_name" || fail "invalid step '$step_name'. Valid steps: git ssh aqua task apm"
      requested_steps=$(add_unique_token "$requested_steps" "$step_name")
      shift 2
      ;;
    --skip)
      [ $# -ge 2 ] || fail "--skip requires a value"
      step_name=$2
      is_valid_step_name "$step_name" || fail "invalid step '$step_name'. Valid steps: git ssh aqua task apm"
      skip_steps=$(add_unique_token "$skip_steps" "$step_name")
      shift 2
      ;;
    --list-steps)
      list_steps=1
      shift
      ;;
    -h|--help)
      show_help=1
      shift
      ;;
    --convenience-ack)
      convenience_ack=1
      shift
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

if [ "$show_help" -eq 1 ]; then
  print_help
  exit 0
fi

if [ "${BOOTSTRAP_CONVENIENCE_MODE:-0}" = "1" ]; then
  say "WARNING: convenience mode lowers transport integrity guarantees."
  say "Use pinned launcher download + checksum verification for strongest trust chain."
fi

if [ "${BOOTSTRAP_CONVENIENCE_MODE:-0}" = "1" ] && [ "$convenience_ack" -ne 1 ]; then
  fail "convenience mode requires --convenience-ack"
fi

if [ "$list_steps" -eq 1 ]; then
  print_step_list
  exit 0
fi

if [ -n "$requested_steps" ] && [ -n "$skip_steps" ]; then
  fail "--step and --skip cannot be used together"
fi

selected_steps=""
if [ -n "$requested_steps" ]; then
  selected_steps=$requested_steps
else
  for step_name in $default_step_order; do
    if ! contains_token "$step_name" "$skip_steps"; then
      selected_steps=$(add_unique_token "$selected_steps" "$step_name")
    fi
  done
fi

[ -n "$selected_steps" ] || fail "no steps selected"

for step_name in $selected_steps; do
  execute_step "$step_name"
done

say "Public bootstrap complete."
