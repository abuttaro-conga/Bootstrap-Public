#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
original_path=$PATH
convenience_ack=0
list_steps=0
show_help=0
requested_steps=""
skip_steps=""
preferred_profile=""
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

prompt_yes_no_tty() {
  prompt_text=$1
  [ -r /dev/tty ] || return 1
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

path_contains_dir() {
  path_value=$1
  dir_value=$2
  case ":$path_value:" in
    *":$dir_value:"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

current_login_shell_path() {
  user_name=$(id -un)
  shell_path=""

  if command -v getent >/dev/null 2>&1; then
    shell_path=$(getent passwd "$user_name" | cut -d: -f7)
  fi

  if [ -z "$shell_path" ]; then
    shell_path=${SHELL:-}
  fi

  printf '%s\n' "$shell_path"
}

command_on_path() {
  cmd_name=$1
  path_value=$2
  (PATH="$path_value"; command -v "$cmd_name" >/dev/null 2>&1)
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

print_path_guidance() {
  aqua_bin="${AQUA_ROOT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/aquaproj-aqua}/bin"
  local_bin="$HOME/.local/bin"
  missing_dirs=""
  path_export_line='export PATH="$HOME/.local/bin:${AQUA_ROOT_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/aquaproj-aqua}/bin:$PATH"'

  if ! path_contains_dir "$original_path" "$local_bin"; then
    missing_dirs=$(add_unique_token "$missing_dirs" "$local_bin")
  fi

  if ! path_contains_dir "$original_path" "$aqua_bin"; then
    missing_dirs=$(add_unique_token "$missing_dirs" "$aqua_bin")
  fi

  if [ -z "$missing_dirs" ]; then
    return 0
  fi

  detect_profile_target() {
    if [ -n "$preferred_profile" ]; then
      printf '%s\n' "$preferred_profile"
      return
    fi

    login_shell_path=$(current_login_shell_path)
    shell_name=$(basename "$login_shell_path")
    case "$shell_name" in
      zsh)
        printf '%s\n' "$HOME/.zshrc"
        ;;
      *)
        printf '%s\n' "$HOME/.profile"
        ;;
    esac
  }

  persist_path_to_profile() {
    profile_file=$1
    profile_dir=$(dirname "$profile_file")
    [ -d "$profile_dir" ] || mkdir -p "$profile_dir"
    [ -f "$profile_file" ] || touch "$profile_file"

    if grep -Fqx "$path_export_line" "$profile_file"; then
      say "PATH already configured in $profile_file"
      return 0
    fi

    printf '\n%s\n' "$path_export_line" >>"$profile_file"
    say "Added bootstrap PATH export to $profile_file"
  }

  say ""
  say "Tools installed for this run may not be on your current shell PATH."
  say "Detected shell: ${SHELL:-unknown}"

  profile_target=$(detect_profile_target)
  if [ -r /dev/tty ] && prompt_yes_no_tty "Add bootstrap PATH to $profile_target for future shells?"; then
    persist_path_to_profile "$profile_target"
  else
    say "To use aqua/task/apm directly after bootstrap, add this to your shell profile:"
    say "  $path_export_line"
  fi
}

prompt_switch_default_shell_to_zsh() {
  [ -r /dev/tty ] || return 0

  login_shell_path=$(current_login_shell_path)
  shell_name=$(basename "$login_shell_path")
  [ -n "$shell_name" ] || shell_name="unknown"

  if [ "$shell_name" = "zsh" ]; then
    preferred_profile="$HOME/.zshrc"
    return 0
  fi

  if ! prompt_yes_no_tty "Default login shell is $shell_name. Switch default shell to zsh?"; then
    return 0
  fi

  if ! command -v zsh >/dev/null 2>&1; then
    if prompt_yes_no_tty "zsh is not installed. Install zsh now?"; then
      install_zsh
    else
      say "Skipping zsh default-shell change because zsh is not installed."
      return 0
    fi
  fi

  zsh_path=$(command -v zsh)
  [ -n "$zsh_path" ] || fail "zsh executable not found"

  if ! command -v chsh >/dev/null 2>&1; then
    say "chsh not available. To switch manually, run: chsh -s $zsh_path"
    return 0
  fi

  user_name=$(id -un)
  say "Changing default shell to zsh for $user_name (you may be prompted for password)."
  if chsh -s "$zsh_path" "$user_name"; then
    preferred_profile="$HOME/.zshrc"
    say "Default shell updated to zsh. Open a new terminal session to use it."
  else
    say "Could not change default shell automatically."
    say "Common fix: set/update your Linux password, then retry:"
    say "  passwd"
    say "  chsh -s $zsh_path"
    if [ -r /proc/version ] && grep -qi microsoft /proc/version; then
      say "WSL note: after successful chsh, close and reopen your terminal (or run: exec zsh -l)."
    fi
  fi
}

prompt_install_oh_my_zsh() {
  [ -r /dev/tty ] || return 0

  if ! command -v zsh >/dev/null 2>&1; then
    return 0
  fi

  if [ -d "$HOME/.oh-my-zsh" ]; then
    say "oh-my-zsh already installed"
    return 0
  fi

  if ! prompt_yes_no_tty "Install oh-my-zsh now?"; then
    return 0
  fi

  say "Installing oh-my-zsh"
  ohmyzsh_url="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
  if download_to_stdout "$ohmyzsh_url" | RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh; then
    say "oh-my-zsh installation complete"
  else
    say "oh-my-zsh installation failed"
    say "Manual install docs: https://ohmyz.sh/#install"
  fi
}

# ----------------------------------------
# Install steps
# ----------------------------------------

install_git() {
  if command_on_path git "$original_path"; then
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

install_zsh() {
  if command -v zsh >/dev/null 2>&1; then
    return
  fi

  say "Installing zsh"
  if command -v brew >/dev/null 2>&1; then
    brew install zsh
  elif command -v apt-get >/dev/null 2>&1; then
    run_as_root apt-get update
    run_as_root apt-get install -y zsh
  elif command -v dnf >/dev/null 2>&1; then
    run_as_root dnf install -y zsh
  elif command -v yum >/dev/null 2>&1; then
    run_as_root yum install -y zsh
  elif command -v zypper >/dev/null 2>&1; then
    run_as_root zypper --non-interactive install zsh
  elif command -v pacman >/dev/null 2>&1; then
    run_as_root pacman -Sy --noconfirm zsh
  elif command -v apk >/dev/null 2>&1; then
    run_as_root apk add zsh
  else
    fail "zsh not found and no supported package manager detected"
  fi

  command -v zsh >/dev/null 2>&1 || fail "zsh install failed"
}

install_aqua() {
  if command_on_path aqua "$original_path"; then
    say "aqua already installed"
    return
  fi

  ensure_aqua_path
  if command -v aqua >/dev/null 2>&1; then
    say "aqua available via bootstrap tool path"
    return
  fi
  command -v bash >/dev/null 2>&1 || fail "bash required to install aqua"
  say "Installing aqua"
  download_to_stdout "https://raw.githubusercontent.com/aquaproj/aqua-installer/v4.0.5/aqua-installer" | bash
  ensure_aqua_path
  command -v aqua >/dev/null 2>&1 || fail "aqua install failed"
}

install_task() {
  if command_on_path task "$original_path"; then
    say "task already installed"
    return
  fi

  ensure_aqua_path
  if command -v task >/dev/null 2>&1; then
    say "task available via bootstrap tool path"
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
  if command_on_path apm "$original_path"; then
    say "apm already installed"
    return
  fi

  ensure_local_bin_path
  if command -v apm >/dev/null 2>&1; then
    say "apm available via bootstrap tool path"
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

  say ""
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

prompt_switch_default_shell_to_zsh
prompt_install_oh_my_zsh

print_path_guidance

say "Public bootstrap complete."
