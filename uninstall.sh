#!/usr/bin/env sh
set -eu

say() {
  printf '%s\n' "$*"
}

prompt_no_default() {
  prompt_text=$1
  if [ ! -r /dev/tty ]; then
    say "Skipping (non-interactive): $prompt_text"
    return 1
  fi

  while :; do
    printf '%s [y/N]: ' "$prompt_text" >/dev/tty
    if ! IFS= read -r answer </dev/tty; then
      return 1
    fi
    case "$answer" in
      y|Y|yes|YES)
        return 0
        ;;
      ""|n|N|no|NO)
        return 1
        ;;
      *)
        say "Please answer y or n."
        ;;
    esac
  done
}

remove_marker_block() {
  file_path=$1
  block_name=$2
  marker_start="# bootstrap-public-${block_name}:start"
  marker_end="# bootstrap-public-${block_name}:end"

  [ -f "$file_path" ] || return 0
  grep -Fq "$marker_start" "$file_path" || return 0
  grep -Fq "$marker_end" "$file_path" || {
    say "Skipping ${block_name} block removal in $file_path (end marker missing)"
    return 0
  }

  tmp_file=$(mktemp "${TMPDIR:-/tmp}/bootstrap-uninstall.XXXXXX")
  if awk -v start="$marker_start" -v end="$marker_end" '
    BEGIN { in_block = 0 }
    {
      if ($0 == start) { in_block = 1; next }
      if (in_block == 1 && $0 == end) { in_block = 0; next }
      if (in_block == 0) { print }
    }
  ' "$file_path" >"$tmp_file"; then
    mv "$tmp_file" "$file_path"
  else
    rm -f "$tmp_file"
    return 1
  fi
  say "Removed ${block_name} block from $file_path"
}

remove_ssh_config_block() {
  ssh_config="$HOME/.ssh/config"
  marker="# bootstrap-managed: github.com"
  [ -f "$ssh_config" ] || return 0
  grep -Fq "$marker" "$ssh_config" || return 0

  tmp_file=$(mktemp "${TMPDIR:-/tmp}/bootstrap-uninstall.XXXXXX")
  awk -v marker="$marker" '
    BEGIN { skip = 0; in_managed_host = 0 }
    {
      if (skip == 0 && $0 == marker) { skip = 1; in_managed_host = 0; next }
      if (skip == 1) {
        if (in_managed_host == 0) {
          if ($0 ~ /^Host[[:space:]]+/) { in_managed_host = 1; next }
          if ($0 ~ /^[[:space:]]*$/) { next }
          skip = 0
        } else {
          if ($0 ~ /^[[:space:]]+/ || $0 ~ /^[[:space:]]*$/) { next }
          skip = 0
        }
      }
      print
    }
  ' "$ssh_config" >"$tmp_file"
  mv "$tmp_file" "$ssh_config"
  say "Removed bootstrap GitHub SSH block from $ssh_config"
}

remove_profile_token_lines() {
  profile_file="$HOME/.profile"
  [ -f "$profile_file" ] || return 0

  tmp_file=$(mktemp "${TMPDIR:-/tmp}/bootstrap-uninstall.XXXXXX")
  awk '
    /^# bootstrap-public: GitHub token for mise private asset downloads$/ { in_block = 1; next }
    in_block == 1 {
      if ($0 ~ /^export GH_TOKEN=/ || $0 ~ /^export GITHUB_TOKEN=/ || $0 ~ /^[[:space:]]*$/) { next }
      in_block = 0
    }
    { print }
  ' "$profile_file" >"$tmp_file"
  mv "$tmp_file" "$profile_file"
  say "Removed optional GitHub token persistence lines from $profile_file"
}

remove_mise_from_omz_plugins() {
  zshrc="$HOME/.zshrc"
  [ -f "$zshrc" ] || return 0
  grep -Eq '^plugins=\([^)]*\)$' "$zshrc" || return 0

  tmp_file=$(mktemp "${TMPDIR:-/tmp}/bootstrap-uninstall.XXXXXX")
  if awk '
    BEGIN { updated = 0 }
    /^plugins=\([^)]*\)$/ {
      original = $0
      gsub(/(^|[[:space:]])mise([[:space:]]|$)/, " ")
      gsub(/[[:space:]]+/, " ")
      gsub(/[ ]+\)/, ")")
      gsub(/\( /, "(")
      if ($0 != original) { updated = 1 }
    }
    { print }
    END {
      if (updated == 0) { exit 2 }
    }
  ' "$zshrc" >"$tmp_file"; then
    mv "$tmp_file" "$zshrc"
  else
    status=$?
    rm -f "$tmp_file"
    [ "$status" -eq 2 ] && return 0
    return "$status"
  fi
  say "Removed mise from oh-my-zsh plugins in $zshrc"
}

say "Bootstrap-Public uninstall (Linux/macOS/WSL)"
say "Each operation is prompted with default No."

if prompt_no_default "Remove bootstrap PATH blocks from shell profiles?"; then
  remove_marker_block "$HOME/.bashrc" "path"
  remove_marker_block "$HOME/.zshrc" "path"
  remove_marker_block "$HOME/.profile" "path"
  remove_marker_block "$HOME/.bash_profile" "path"
fi

if prompt_no_default "Remove bootstrap mise activation blocks from shell profiles?"; then
  remove_marker_block "$HOME/.bashrc" "mise-activate:bash"
  remove_marker_block "$HOME/.zshrc" "mise-activate:zsh"
fi

if prompt_no_default "Remove bootstrap ssh-agent blocks from shell profiles?"; then
  remove_marker_block "$HOME/.bashrc" "ssh-agent"
  remove_marker_block "$HOME/.zshrc" "ssh-agent"
fi

if prompt_no_default "Remove bootstrap GitHub SSH config block from ~/.ssh/config?"; then
  remove_ssh_config_block
fi

if prompt_no_default "Remove custom oh-my-zsh mise plugin file?"; then
  plugin_file="$HOME/.oh-my-zsh/custom/plugins/mise/mise.plugin.zsh"
  if [ -f "$plugin_file" ]; then
    rm -f "$plugin_file"
    say "Removed $plugin_file"
  fi
fi

if prompt_no_default "Remove 'mise' token from oh-my-zsh plugins list in ~/.zshrc?"; then
  remove_mise_from_omz_plugins
fi

if prompt_no_default "Remove optional persisted GitHub token lines from ~/.profile?"; then
  remove_profile_token_lines
fi

if prompt_no_default "Delete bootstrap SSH key files (~/.ssh/id_ed25519_bootstrap and .pub)?"; then
  rm -f "$HOME/.ssh/id_ed25519_bootstrap" "$HOME/.ssh/id_ed25519_bootstrap.pub"
  say "Deleted bootstrap SSH key files"
fi

say "Uninstall run complete."