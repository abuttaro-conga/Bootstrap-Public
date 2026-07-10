#!/usr/bin/env sh
set -eu

original_path=$PATH
convenience_ack=0
list_steps=0
show_help=0
requested_steps=""
skip_steps=""
preferred_profile=""
zsh_switch_failed=0
zsh_switch_retry_shell_path=""
default_step_order="git ssh mise zsh oh-my-zsh"

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
    git|ssh|mise|zsh|oh-my-zsh)
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
  printf '%s\n' git ssh mise zsh oh-my-zsh
}

print_help() {
  cat <<'EOF'
Usage:
  ./bootstrap.sh [--convenience-ack] [--step <name> ... | --skip <name> ...] [--list-steps] [--help]

Behavior:
  - No step flags: runs full default flow (git -> ssh -> mise -> zsh -> oh-my-zsh)
  - --step: run only specified steps, in provided order
  - --skip: run default flow except skipped steps

Options:
  --step <name>         Repeatable. Step names: git, ssh, mise, zsh, oh-my-zsh
  --skip <name>         Repeatable. Step names: git, ssh, mise, zsh, oh-my-zsh
  --list-steps          Print valid step names, then exit
  --convenience-ack     Required when BOOTSTRAP_CONVENIENCE_MODE=1
  -h, --help            Show this help and exit

Examples:
  ./bootstrap.sh
  ./bootstrap.sh --step ssh
  ./bootstrap.sh --step git --step mise
  ./bootstrap.sh --step zsh --step oh-my-zsh
  ./bootstrap.sh --skip ssh
  ./bootstrap.sh --skip zsh --skip oh-my-zsh
EOF
}

is_linux() {
  [ "$(uname -s)" = "Linux" ]
}

# ----------------------------------------
# Tool path setup
# ----------------------------------------

ensure_mise_path() {
  mise_local_bin="$HOME/.local/bin"
  mise_data_bin="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/bin"
  PATH="$mise_local_bin:$mise_data_bin:$PATH"
  export PATH
}

print_path_guidance() {
  mise_data_bin="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/bin"
  local_bin="$HOME/.local/bin"
  missing_dirs=""
  need_mise_data_bin=0
  need_local_bin=0
  path_export_line='export PATH="$HOME/.local/bin:${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/bin:$PATH"'
  path_export_marker_start='# bootstrap-public-path:start'
  path_export_marker_end='# bootstrap-public-path:end'

  if ! path_contains_dir "$original_path" "$local_bin"; then
    need_local_bin=1
  fi

  if ! path_contains_dir "$original_path" "$mise_data_bin"; then
    need_mise_data_bin=1
  fi

  # Prompt when tools are available in this run but were not resolvable on the original PATH.
  if command -v mise >/dev/null 2>&1 && ! command_on_path mise "$original_path"; then
    need_local_bin=1
  fi

  if command -v mise >/dev/null 2>&1 && ! command_on_path mise "$original_path"; then
    need_mise_data_bin=1
  fi

  if [ "$need_local_bin" -eq 1 ]; then
    missing_dirs=$(add_unique_token "$missing_dirs" "$local_bin")
  fi

  if [ "$need_mise_data_bin" -eq 1 ]; then
    missing_dirs=$(add_unique_token "$missing_dirs" "$mise_data_bin")
  fi

  shell_profile_for_mode() {
    shell_name=$1
    mode=$2
    case "$shell_name:$mode" in
      zsh:active|zsh:login)
        printf '%s\n' "$HOME/.zshrc"
        ;;
      bash:active)
        printf '%s\n' "$HOME/.bashrc"
        ;;
      bash:login)
        if [ -f "$HOME/.bash_profile" ]; then
          printf '%s\n' "$HOME/.bash_profile"
        else
          printf '%s\n' "$HOME/.profile"
        fi
        ;;
      sh:active|sh:login)
        printf '%s\n' "$HOME/.profile"
        ;;
      *)
        printf '%s\n' "$HOME/.profile"
        ;;
    esac
  }

  detect_profile_targets() {
    profile_targets=""

    if [ -n "$preferred_profile" ]; then
      profile_targets=$(add_unique_token "$profile_targets" "$preferred_profile")
    fi

    # If zsh is installed, always ensure ~/.zshrc gets bootstrap PATH.
    if command -v zsh >/dev/null 2>&1; then
      profile_targets=$(add_unique_token "$profile_targets" "$HOME/.zshrc")
    fi

    active_shell_name=$(basename "${SHELL:-}")
    if [ -n "$active_shell_name" ]; then
      active_profile=$(shell_profile_for_mode "$active_shell_name" active)
      [ -n "$active_profile" ] && profile_targets=$(add_unique_token "$profile_targets" "$active_profile")
    fi

    login_shell_path=$(current_login_shell_path)
    login_shell_name=$(basename "$login_shell_path")
    if [ -n "$login_shell_name" ]; then
      login_profile=$(shell_profile_for_mode "$login_shell_name" login)
      [ -n "$login_profile" ] && profile_targets=$(add_unique_token "$profile_targets" "$login_profile")
    fi

    if [ -z "$profile_targets" ]; then
      profile_targets=$(add_unique_token "$profile_targets" "$HOME/.profile")
    fi

    printf '%s\n' "$profile_targets"
  }

  profile_has_bootstrap_path() {
    profile_file=$1
    [ -f "$profile_file" ] || return 1

    if grep -Fqx "$path_export_line" "$profile_file"; then
      return 0
    fi

    if grep -Fq "$path_export_marker_start" "$profile_file" && grep -Fq "$path_export_marker_end" "$profile_file"; then
      return 0
    fi

    if grep -Fq '$HOME/.local/bin:' "$profile_file" && grep -Fq '/mise}/bin:$PATH"' "$profile_file"; then
      return 0
    fi

    return 1
  }

  persist_path_to_profile() {
    profile_file=$1
    profile_dir=$(dirname "$profile_file")
    [ -d "$profile_dir" ] || mkdir -p "$profile_dir"
    [ -f "$profile_file" ] || touch "$profile_file"

    print_source_profile_guidance() {
      say "To apply PATH in your current shell now, run:"
      say "  . $profile_file"
    }

    if profile_has_bootstrap_path "$profile_file"; then
      say "PATH already configured in $profile_file"
      print_source_profile_guidance
      return 0
    fi

    printf '\n%s\n%s\n%s\n' "$path_export_marker_start" "$path_export_line" "$path_export_marker_end" >>"$profile_file"
    say "Added bootstrap PATH export to $profile_file"
    print_source_profile_guidance
  }

  profile_targets=$(detect_profile_targets)
  missing_profile_targets=""
  for profile_target in $profile_targets; do
    if ! profile_has_bootstrap_path "$profile_target"; then
      missing_profile_targets=$(add_unique_token "$missing_profile_targets" "$profile_target")
    fi
  done

  if [ -z "$missing_dirs" ] && [ -z "$missing_profile_targets" ]; then
    return 0
  fi

  persisted_any=0

  say ""
  if [ -n "$missing_dirs" ]; then
    say "Tools installed for this run may not be on your current shell PATH."
    say "Detected shell: ${SHELL:-unknown}"
  else
    say "Bootstrap PATH export not found in one or more shell profiles."
    say "Detected shell: ${SHELL:-unknown}"
  fi

  if [ -r /dev/tty ] && [ -n "$missing_profile_targets" ]; then
    for profile_target in $missing_profile_targets; do
      if prompt_yes_no_tty "Add bootstrap PATH to $profile_target for future shells?"; then
        persist_path_to_profile "$profile_target"
        persisted_any=1
      fi
    done
  fi

  if [ "$persisted_any" -eq 0 ] && [ -n "$missing_profile_targets" ]; then
    say "To use mise directly after bootstrap, add this to your shell profile:"
    say "  $path_export_line"
  fi

  if [ -z "$missing_profile_targets" ] && [ -n "$missing_dirs" ]; then
    source_profile_hint="$preferred_profile"
    if [ -z "$source_profile_hint" ]; then
      for profile_target in $profile_targets; do
        source_profile_hint=$profile_target
        break
      done
    fi
    if [ -n "$source_profile_hint" ]; then
      say "PATH already configured in shell profile(s). To apply in current shell now, run:"
      say "  . $source_profile_hint"
    fi
  fi
}

print_postflight_warnings() {
  if [ "$zsh_switch_failed" -eq 1 ]; then
    say ""
    say "IMPORTANT: zsh was installed, but default shell is still not zsh."
    say "Run this fix, then retry bootstrap shell switch:"
    say "  passwd"
    say "  chsh -s $zsh_switch_retry_shell_path"
    if [ -r /proc/version ] && grep -qi microsoft /proc/version; then
      say "WSL note: after successful chsh, close and reopen your terminal (or run: exec zsh -l)."
    fi
  fi
}

ensure_mise_activation() {
  if ! command -v mise >/dev/null 2>&1; then
    return 0
  fi

  ensure_activation_in_profile() {
    profile_file=$1
    shell_name=$2
    activation_line=$3
    marker_start="# bootstrap-public-mise-activate:${shell_name}:start"
    marker_end="# bootstrap-public-mise-activate:${shell_name}:end"
    profile_dir=$(dirname "$profile_file")

    [ -d "$profile_dir" ] || mkdir -p "$profile_dir"
    [ -f "$profile_file" ] || touch "$profile_file"

    if grep -Fqx "$activation_line" "$profile_file"; then
      say "mise activation already configured for $shell_name in $profile_file"
      return 0
    fi

    if grep -Fq "$marker_start" "$profile_file" && grep -Fq "$marker_end" "$profile_file"; then
      say "mise activation already configured for $shell_name in $profile_file"
      return 0
    fi

    printf '\n%s\n%s\n%s\n' "$marker_start" "$activation_line" "$marker_end" >>"$profile_file"
    say "Added mise activation for $shell_name to $profile_file"
  }

  ensure_activation_in_profile "$HOME/.bashrc" "bash" 'eval "$(~/.local/bin/mise activate bash)"'

  if command -v zsh >/dev/null 2>&1 || [ "$preferred_profile" = "$HOME/.zshrc" ]; then
    ensure_activation_in_profile "$HOME/.zshrc" "zsh" 'eval "$(~/.local/bin/mise activate zsh)"'
  fi

  active_shell_name=$(basename "${SHELL:-bash}")
  case "$active_shell_name" in
    zsh)
      say "To apply mise activation now, open a new shell or run:"
      say '  eval "$(~/.local/bin/mise activate zsh)"'
      ;;
    *)
      say "To apply mise activation now, open a new shell or run:"
      say '  eval "$(~/.local/bin/mise activate bash)"'
      ;;
  esac
}

prompt_switch_default_shell_to_zsh() {
  mode=${1:-prompt}

  if [ "$mode" = "never" ]; then
    say "Skipping zsh step."
    return 0
  fi

  login_shell_path=$(current_login_shell_path)
  shell_name=$(basename "$login_shell_path")
  [ -n "$shell_name" ] || shell_name="unknown"

  if [ "$shell_name" = "zsh" ]; then
    preferred_profile="$HOME/.zshrc"
    say "zsh already default login shell"
    return 0
  fi

  if [ "$mode" = "prompt" ] && [ ! -r /dev/tty ]; then
    if command -v zsh >/dev/null 2>&1; then
      say "zsh installed. Skipping default-shell switch (no interactive terminal)."
    else
      say "Skipping zsh step (no interactive terminal)."
    fi
    return 0
  fi

  if [ "$mode" = "prompt" ] && ! prompt_yes_no_tty "Default login shell is $shell_name. Switch default shell to zsh?"; then
    return 0
  fi

  if ! command -v zsh >/dev/null 2>&1; then
    if [ "$mode" = "always" ]; then
      install_zsh
    else
      if prompt_yes_no_tty "zsh is not installed. Install zsh now?"; then
        install_zsh
      else
        say "Skipping zsh default-shell change because zsh is not installed."
        return 0
      fi
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
    zsh_switch_failed=1
    zsh_switch_retry_shell_path=$zsh_path
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
  mode=${1:-prompt}

  if [ "$mode" = "never" ]; then
    return 0
  fi

  if [ "$mode" = "prompt" ] && [ ! -r /dev/tty ]; then
    return 0
  fi

  if ! command -v zsh >/dev/null 2>&1; then
    return 0
  fi

  if [ -d "$HOME/.oh-my-zsh" ]; then
    say "oh-my-zsh already installed"
    return 0
  fi

  if [ "$mode" = "prompt" ] && ! prompt_yes_no_tty "Install oh-my-zsh now?"; then
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
    say "zsh already installed"
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

install_mise() {
  if command_on_path mise "$original_path"; then
    say "mise already installed"
    return
  fi

  ensure_mise_path
  if command -v mise >/dev/null 2>&1; then
    say "mise available via bootstrap tool path"
    return
  fi
  command -v sh >/dev/null 2>&1 || fail "sh required to install mise"
  say "Installing mise"
  download_to_stdout "https://mise.run" | sh
  ensure_mise_path
  command -v mise >/dev/null 2>&1 || fail "mise install failed"
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

  sanitize_key_title_component() {
    printf '%s' "$1" | tr -cs 'A-Za-z0-9._-' '-'
  }

  github_key_title_suggestion() {
    if [ -n "${WSL_DISTRO_NAME:-}" ]; then
      env_id="wsl-$(sanitize_key_title_component "$WSL_DISTRO_NAME")"
    else
      os_name=$(uname -s 2>/dev/null || printf 'unknown-os')
      os_arch=$(uname -m 2>/dev/null || printf 'unknown-arch')
      env_id="$(sanitize_key_title_component "$os_name")-$(sanitize_key_title_component "$os_arch")"
    fi

    host_id=$(hostname 2>/dev/null || printf 'unknown-host')
    host_id=$(sanitize_key_title_component "$host_id")

    printf '%s\n' "bootstrap-generated-$env_id-$host_id"
  }

  pick_public_key() {
    if [ -f "$HOME/.ssh/id_ed25519_bootstrap.pub" ]; then
      printf '%s\n' "$HOME/.ssh/id_ed25519_bootstrap.pub"
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

    say "No bootstrap SSH key found. Creating a new Ed25519 key."
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

    key_path="$HOME/.ssh/id_ed25519_bootstrap"
    say "You must set a non-empty passphrase for this key."

    while :; do
      ssh-keygen -t ed25519 -C "$email" -f "$key_path" </dev/tty >/dev/tty

      # Reject empty-passphrase keys to enforce baseline key protection,
      # then retry key generation without aborting the whole bootstrap.
      if ssh-keygen -y -P "" -f "$key_path" >/dev/null 2>&1; then
        rm -f "$key_path" "$key_path.pub"
        say "Empty passphrase is not allowed. Please try again and set a passphrase."
        continue
      fi

      break
    done
  }

  start_agent_and_add_key() {
    key_path=$1
    eval "$(ssh-agent -s)" >/dev/null
    ssh-add "$key_path" </dev/tty >/dev/null 2>&1 || fail "Failed to add SSH key to ssh-agent"
  }

  write_ssh_config() {
    _key_path=$1
    _config="$HOME/.ssh/config"
    _marker="# bootstrap-managed: github.com"
    if [ -f "$_config" ] && grep -qF "$_marker" "$_config"; then
      return  # already written
    fi
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    printf '\n%s\nHost github.com\n  IdentityFile %s\n  AddKeysToAgent yes\n' \
      "$_marker" "$_key_path" >> "$_config"
    chmod 600 "$_config"
    say "Wrote SSH config for github.com -> $_key_path"
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
  say "Suggested GitHub SSH key title (copy/paste):"
  say "$(github_key_title_suggestion)"
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
  write_ssh_config "$private_key"
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
    mise)
      install_mise
      ;;
    zsh)
      if is_linux; then
        prompt_switch_default_shell_to_zsh prompt
      else
        say "Skipping zsh step: Linux only"
      fi
      ;;
    oh-my-zsh)
      if is_linux; then
        prompt_install_oh_my_zsh prompt
      else
        say "Skipping oh-my-zsh step: Linux only"
      fi
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
      is_valid_step_name "$step_name" || fail "invalid step '$step_name'. Valid steps: git ssh mise zsh oh-my-zsh"
      requested_steps=$(add_unique_token "$requested_steps" "$step_name")
      shift 2
      ;;
    --skip)
      [ $# -ge 2 ] || fail "--skip requires a value"
      step_name=$2
      is_valid_step_name "$step_name" || fail "invalid step '$step_name'. Valid steps: git ssh mise zsh oh-my-zsh"
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

print_path_guidance
ensure_mise_activation
print_postflight_warnings

say "Public bootstrap complete."
