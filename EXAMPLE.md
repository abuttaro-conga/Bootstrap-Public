
# Example Bootstrap Outputs

## Creating a new WSL Distro

```powershell
 PS C:\src> & ([scriptblock]::Create((irm https://raw.githubusercontent.com/abuttaro-conga/Bootstrap-Public/main/scripts/install-wsl-distro-and-terminal-profile.ps1))) -DistroName Ubuntu-24.04
Checking WSL distro 'Ubuntu-24.04'.
Installing WSL distro 'Ubuntu-24.04'.
Downloading: Ubuntu 24.04 LTS

Installing: Ubuntu 24.04 LTS

Distribution successfully installed. It can be launched via 'wsl.exe -d Ubuntu-24.04'


Starting WSL distro 'Ubuntu-24.04'.
Updated WSL source profile override 'Ubuntu-24.04' in 'C:\Users\youruser\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'.
Kept one WSL source profile 'Ubuntu-24.04' and removed 1 duplicate profile(s) from 'C:\Users\youruser\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'.
Backup written to 'C:\Users\youruser\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json.bak.20260812-090452-823'.
Done.
```

Launch the new Distro from Terminal
```sh
Provisioning the new WSL instance Ubuntu-24.04
This might take a while...
Create a default Unix user account: youruser
New password:
Retype new password:
passwd: password updated successfully
To run a command as administrator (user "root"), use "sudo <command>".
See "man sudo_root" for details.

youruser@XXXXXXXXX:~$
```

## Running bootstrap.sh

The script will run with prompts with choices for optional setup. All options default to Y and are recommended.

The prompts are separated below for clarity with explanation, but the script will run sequentially through completion.

Execute the script:
```sh
$ curl -fsSL https://raw.githubusercontent.com/abuttaro-conga/Bootstrap-Public/main/bootstrap.sh | sh
git already installed
```

### Step 1: GitHub SSH Key Setup

Optional, but recommended and should be used as best practice.

First, the SSH key will be created. 
```sh
Set up GitHub SSH key (recommended for git over SSH)? [Y/n]: Y
GitHub SSH setup helper
Guide: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/testing-your-ssh-connection
No bootstrap SSH key found. Creating a new Ed25519 key.
Email for SSH key comment [youruser@conga.com]:
You must set a non-empty passphrase for this key.
Generating public/private ed25519 key pair.
Enter passphrase (empty for no passphrase):
Enter same passphrase again:
Your identification has been saved in /home/youruser/.ssh/id_ed25519_bootstrap
Your public key has been saved in /home/youruser/.ssh/id_ed25519_bootstrap.pub
The key fingerprint is:
SHA256:<your-key-fingerprint> youruser@conga.com
The key's randomart image is:
+--[ED25519 256]--+
|   [randomart]   |
+----[SHA256]-----+
```

You will be prompted for your passphrase a third time to add the key to ssh-agent:
```sh
Adding key to ssh-agent (enter passphrase one final time):
Enter passphrase for /home/youruser/.ssh/id_ed25519_bootstrap:
```

You will then be required to add your SSH public key to github
*  ctrl+click the url, https://github.com/settings/keys
* New SSH Key
* Copy suggested key title
* Copy the public key contents
* Add SSH key
* Y after key is successfully added (After returning to the GitHub keys settings page displaying the message: "You have successfully added the key 'bootstrap-generated-wsl-Ubuntu-24.04-HOSTNAME'.")
```sh

Add this SSH public key to your GitHub account:
ssh-ed25519 AAAA...<your public key>... youruser@conga.com

Suggested GitHub SSH key title (copy/paste):
bootstrap-generated-wsl-Ubuntu-24.04-HOSTNAME

GitHub key settings URL: https://github.com/settings/keys
Have you added this key to GitHub? [Y/n]:
```

The key will be tested and you will be prompted to permanently add 'github.com' to your list of known hosts
```sh
Running SSH test command: ssh -T git@github.com
The authenticity of host 'github.com (140.82.113.4)' can't be established.
ED25519 key fingerprint is SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU.
This key is not known by any other names.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added 'github.com' (ED25519) to the list of known hosts.
Hi abuttaro-conga! You've successfully authenticated, but GitHub does not provide shell access.
Wrote SSH config for github.com -> /home/youruser/.ssh/id_ed25519_bootstrap
GitHub SSH connection is ready.
```

### Step 2: mise install

Next, mise is installed
```sh
Installing mise
mise: installing mise...
######################################################################## 100.0%
mise: installed successfully to /home/youruser/.local/bin/mise
mise: run the following to activate mise in your shell:
echo "eval \"\$(/home/youruser/.local/bin/mise activate bash)\"" >> ~/.bashrc

mise: run `mise doctor` to verify this is set up correctly
```

mise must be able to authenticate to GitHub to pull from private repositories.
The script will install gh cli using mise to enable seamless authentication.
```sh
Installing gh via mise
gh@2.97.0       extract gh_2.97.0_linux_amd64.tar.gz                                                                                      ✔
mise ~/.config/mise/config.toml tools: gh@2.97.0
```

On WSL2, github login is not able to open a browser by default.
This can be fixed optionally by setting mise env.BROWSER.
```sh
WSL2 detected. Set BROWSER so gh auth opens on Windows? [Y/n]: Y
Set mise env.BROWSER for WSL2
```

mise will attempt to authenticate using gh cli
```sh
Authenticating with GitHub CLI
? Authenticate Git with your GitHub credentials? Yes

! First copy your one-time code: E74B-3725
Press Enter to open https://github.com/login/device in your browser...
✓ Authentication complete.
- gh config set -h github.com git_protocol https
✓ Configured git protocol
! Authentication credentials saved in plain text
✓ Logged in as abuttaro-conga
github.com
  ✓ Logged in to github.com account abuttaro-conga (/home/youruser/.config/gh/hosts.yml)
  - Active account: true
  - Git operations protocol: https
  - Token: gho_************************************
  - Token scopes: 'gist', 'read:org', 'repo', 'workflow'
Set mise github.credential_command
```

Optionally, github.use_git_credentials can be set for mise to fall back to git's credential helper chain (keychain, credential-manager, etc.) when credential_command using gh cli fails or returns empty.
```sh
Enable mise git credential fallback (use_git_credentials)? [Y/n]:
Set mise github.use_git_credentials
```

The script will verify mise gh authentication
```sh
Verifying mise GitHub token resolution
github.com: gho_**** (source: gh CLI (hosts.yml))
mise GitHub token OK
```

### Step 3: Shell setup

Shells must be setup to activate mise by default. 
It is recommended to do this for all shells so mise will work properly in new terminals.

```sh
Tools installed for this run may not be on your current shell PATH.
Detected shell: /bin/bash
Add bootstrap PATH to /home/youruser/.bashrc for future shells? [Y/n]:
Added bootstrap PATH export to /home/youruser/.bashrc
To apply PATH in your current shell now, run:
  . /home/youruser/.bashrc
Add bootstrap PATH to /home/youruser/.profile for future shells? [Y/n]:
Added bootstrap PATH export to /home/youruser/.profile
To apply PATH in your current shell now, run:
  . /home/youruser/.profile
Added mise-activate:bash to /home/youruser/.bashrc
```

If zsh is not present (it is not on a new Distro), it can be installed
```sh
zsh not detected. Install zsh now? [Y/n]:
Installing zsh
[sudo] password for youruser:
Hit:1 http://archive.ubuntu.com/ubuntu noble InRelease
Get:2 http://security.ubuntu.com/ubuntu noble-security InRelease [126 kB]
Get:3 http://archive.ubuntu.com/ubuntu noble-updates InRelease [126 kB]
Get:4 http://archive.ubuntu.com/ubuntu noble-backports InRelease [126 kB]
Get:5 http://archive.ubuntu.com/ubuntu noble/universe amd64 Packages [15.0 MB]
Get:6 http://security.ubuntu.com/ubuntu noble-security/main amd64 Packages [930 kB]
Get:7 http://security.ubuntu.com/ubuntu noble-security/main Translation-en [201 kB]
Get:8 http://security.ubuntu.com/ubuntu noble-security/main amd64 Components [46.3 kB]
Get:9 http://security.ubuntu.com/ubuntu noble-security/main amd64 c-n-f Metadata [11.9 kB]
Get:10 http://security.ubuntu.com/ubuntu noble-security/universe amd64 Packages [1200 kB]
Get:11 http://archive.ubuntu.com/ubuntu noble/universe Translation-en [5982 kB]
Get:12 http://security.ubuntu.com/ubuntu noble-security/universe Translation-en [239 kB]
Get:13 http://security.ubuntu.com/ubuntu noble-security/universe amd64 Components [76.3 kB]
Get:14 http://security.ubuntu.com/ubuntu noble-security/universe amd64 c-n-f Metadata [24.2 kB]
Get:15 http://security.ubuntu.com/ubuntu noble-security/restricted amd64 Packages [1320 kB]
Get:16 http://security.ubuntu.com/ubuntu noble-security/restricted Translation-en [302 kB]
Get:17 http://security.ubuntu.com/ubuntu noble-security/restricted amd64 Components [212 B]
Get:18 http://security.ubuntu.com/ubuntu noble-security/restricted amd64 c-n-f Metadata [444 B]
Get:19 http://security.ubuntu.com/ubuntu noble-security/multiverse amd64 Packages [40.3 kB]
Get:20 http://security.ubuntu.com/ubuntu noble-security/multiverse Translation-en [10.6 kB]
Get:21 http://archive.ubuntu.com/ubuntu noble/universe amd64 Components [3871 kB]
Get:22 http://archive.ubuntu.com/ubuntu noble/universe amd64 c-n-f Metadata [301 kB]
Get:23 http://archive.ubuntu.com/ubuntu noble/multiverse amd64 Packages [269 kB]
Get:24 http://archive.ubuntu.com/ubuntu noble/multiverse Translation-en [118 kB]
Get:25 http://archive.ubuntu.com/ubuntu noble/multiverse amd64 Components [35.0 kB]
Get:26 http://archive.ubuntu.com/ubuntu noble/multiverse amd64 c-n-f Metadata [8328 B]
Get:27 http://archive.ubuntu.com/ubuntu noble-updates/main amd64 Packages [1190 kB]
Get:28 http://archive.ubuntu.com/ubuntu noble-updates/main Translation-en [282 kB]
Get:29 http://archive.ubuntu.com/ubuntu noble-updates/main amd64 Components [181 kB]
Get:30 http://security.ubuntu.com/ubuntu noble-security/multiverse amd64 Components [208 B]
Get:31 http://security.ubuntu.com/ubuntu noble-security/multiverse amd64 c-n-f Metadata [468 B]
Get:32 http://archive.ubuntu.com/ubuntu noble-updates/main amd64 c-n-f Metadata [17.7 kB]
Get:33 http://archive.ubuntu.com/ubuntu noble-updates/universe amd64 Packages [1683 kB]
Get:34 http://archive.ubuntu.com/ubuntu noble-updates/universe Translation-en [335 kB]
Get:35 http://archive.ubuntu.com/ubuntu noble-updates/universe amd64 Components [388 kB]
Get:36 http://archive.ubuntu.com/ubuntu noble-updates/universe amd64 c-n-f Metadata [34.9 kB]
Get:37 http://archive.ubuntu.com/ubuntu noble-updates/restricted amd64 Packages [1424 kB]
Get:38 http://archive.ubuntu.com/ubuntu noble-updates/restricted Translation-en [323 kB]
Get:39 http://archive.ubuntu.com/ubuntu noble-updates/restricted amd64 Components [212 B]
Get:40 http://archive.ubuntu.com/ubuntu noble-updates/restricted amd64 c-n-f Metadata [456 B]
Get:41 http://archive.ubuntu.com/ubuntu noble-updates/multiverse amd64 Packages [45.4 kB]
Get:42 http://archive.ubuntu.com/ubuntu noble-updates/multiverse Translation-en [12.6 kB]
Get:43 http://archive.ubuntu.com/ubuntu noble-updates/multiverse amd64 Components [940 B]
Get:44 http://archive.ubuntu.com/ubuntu noble-updates/multiverse amd64 c-n-f Metadata [656 B]
Get:45 http://archive.ubuntu.com/ubuntu noble-backports/main amd64 Packages [40.6 kB]
Get:46 http://archive.ubuntu.com/ubuntu noble-backports/main Translation-en [9172 B]
Get:47 http://archive.ubuntu.com/ubuntu noble-backports/main amd64 Components [5776 B]
Get:48 http://archive.ubuntu.com/ubuntu noble-backports/main amd64 c-n-f Metadata [368 B]
Get:49 http://archive.ubuntu.com/ubuntu noble-backports/universe amd64 Packages [31.0 kB]
Get:50 http://archive.ubuntu.com/ubuntu noble-backports/universe Translation-en [18.6 kB]
Get:51 http://archive.ubuntu.com/ubuntu noble-backports/universe amd64 Components [12.6 kB]
Get:52 http://archive.ubuntu.com/ubuntu noble-backports/universe amd64 c-n-f Metadata [1588 B]
Get:53 http://archive.ubuntu.com/ubuntu noble-backports/restricted amd64 Components [212 B]
Get:54 http://archive.ubuntu.com/ubuntu noble-backports/restricted amd64 c-n-f Metadata [116 B]
Get:55 http://archive.ubuntu.com/ubuntu noble-backports/multiverse amd64 Packages [748 B]
Get:56 http://archive.ubuntu.com/ubuntu noble-backports/multiverse Translation-en [340 B]
Get:57 http://archive.ubuntu.com/ubuntu noble-backports/multiverse amd64 Components [212 B]
Get:58 http://archive.ubuntu.com/ubuntu noble-backports/multiverse amd64 c-n-f Metadata [116 B]
Fetched 36.4 MB in 4s (9081 kB/s)
Reading package lists... Done
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
The following additional packages will be installed:
  zsh-common
Suggested packages:
  zsh-doc
The following NEW packages will be installed:
  zsh zsh-common
0 upgraded, 2 newly installed, 0 to remove and 157 not upgraded.
Need to get 4985 kB of archives.
After this operation, 19.1 MB of additional disk space will be used.
Get:1 http://archive.ubuntu.com/ubuntu noble/main amd64 zsh-common all 5.9-6ubuntu2 [4173 kB]
Get:2 http://archive.ubuntu.com/ubuntu noble/main amd64 zsh amd64 5.9-6ubuntu2 [812 kB]
Fetched 4985 kB in 1s (5150 kB/s)
Selecting previously unselected package zsh-common.
(Reading database ... 40805 files and directories currently installed.)
Preparing to unpack .../zsh-common_5.9-6ubuntu2_all.deb ...
Unpacking zsh-common (5.9-6ubuntu2) ...
Selecting previously unselected package zsh.
Preparing to unpack .../zsh_5.9-6ubuntu2_amd64.deb ...
Unpacking zsh (5.9-6ubuntu2) ...
Setting up zsh-common (5.9-6ubuntu2) ...
Setting up zsh (5.9-6ubuntu2) ...
Processing triggers for debianutils (5.17build1) ...
Processing triggers for man-db (2.12.0-4build2) ...
```

Optionally, oh-my-zsh can be installed:
```sh
oh-my-zsh not detected. Install oh-my-zsh now? [Y/n]: Y
Installing oh-my-zsh
Cloning Oh My Zsh...
remote: Enumerating objects: 1610, done.
remote: Counting objects: 100% (1610/1610), done.
remote: Compressing objects: 100% (1509/1509), done.
remote: Total 1610 (delta 132), reused 1433 (delta 71), pack-reused 0 (from 0)
Receiving objects: 100% (1610/1610), 3.35 MiB | 10.29 MiB/s, done.
Resolving deltas: 100% (132/132), done.
From https://github.com/ohmyzsh/ohmyzsh
 * [new branch]      add-docker-compose-config                    -> origin/add-docker-compose-config
 * [new branch]      copilot/fix-per-directory-history-regression -> origin/copilot/fix-per-directory-history-regression
 * [new branch]      master                                       -> origin/master
 * [new branch]      rr-13813-introduce-cooldown-feature          -> origin/rr-13813-introduce-cooldown-feature
branch 'master' set up to track 'origin/master'.
Already on 'master'
/home/youruser

Looking for an existing zsh config...
Using the Oh My Zsh template file and adding it to /home/youruser/.zshrc.

         __                                     __
  ____  / /_     ____ ___  __  __   ____  _____/ /_
 / __ \/ __ \   / __ `__ \/ / / /  /_  / / ___/ __ \
/ /_/ / / / /  / / / / / / /_/ /    / /_(__  ) / / /
\____/_/ /_/  /_/ /_/ /_/\__, /    /___/____/_/ /_/
                        /____/                       ....is now installed!


Before you scream Oh My Zsh! look over the `.zshrc` file to select plugins, themes, and options.

• Follow us on X: @ohmyzsh
• Join our Discord community: Discord server
• Get stickers, t-shirts, coffee mugs and more: CommitGoods Shop

Run zsh to try it out.
oh-my-zsh installed
```

zsh is commonly set as default login shell. (This will likely fail, see next "ACTION REQUIRED")
```sh
Set zsh as your default login shell? [Y/n]: Y
Password: chsh: PAM: Authentication failure

IMPORTANT: default login shell was NOT changed
Reason: automatic chsh update failed (commonly authentication/policy)
Run manually: chsh -s /usr/bin/zsh
Then sign out and sign back in for shell change to apply

Added mise to oh-my-zsh plugins in /home/youruser/.zshrc
Added path to /home/youruser/.zshrc (before source $ZSH/oh-my-zsh.sh)
Added mise-activate:zsh to /home/youruser/.zshrc (before source $ZSH/oh-my-zsh.sh)
To apply mise activation now, open a new shell or run:
  eval "$(mise activate bash)"
Added ssh-agent to /home/youruser/.bashrc
Added ssh-agent to /home/youruser/.zshrc
SSH agent configured via systemd user service
Public bootstrap complete.
```

chsh uses PAM (Pluggable Authentication Modules) to authorize the shell change. In WSL, the PAM configuration for chsh often requires password authentication that doesn't work correctly because:

- **WSL users are often passwordless** — the default WSL Ubuntu setup creates your user without a traditional shadow password entry, or with a locked password. PAM's `pam_unix` module can't verify what isn't there.
- **Corporate/AD environments** — if the machine is domain-joined or uses LDAP/SSSD for auth, PAM tries to validate against a directory service that isn't reachable from inside WSL.
- **WSL's `chsh`** — some WSL distro configs require `pam_shells` or `pam_rootok` checks that fail for non-root users even with a valid password.

**Why it says "Authentication failure" even if you typed the right password:** PAM doesn't just check your password — it runs a stack of modules. Any module in the stack can fail the whole auth. In WSL, the failure is usually at the account/session validation layer, not the password check itself.
```sh
================ ACTION REQUIRED ================
Default shell still not zsh. Run: chsh -s /usr/bin/zsh
After changing shell, sign out and sign back in.
================================================
```

Run chsh, entering your system password once
```sh
$  chsh -s /usr/bin/zsh
Password:
```

If you installed zsh, switch to zsh and you are ready to go
```sh
$ zsh
➜  ~ mise --version
              _                                        __
   ____ ___  (_)_______        ___  ____        ____  / /___ _________
  / __ `__ \/ / ___/ _ \______/ _ \/ __ \______/ __ \/ / __ `/ ___/ _ \
 / / / / / / (__  )  __/_____/  __/ / / /_____/ /_/ / / /_/ / /__/  __/
/_/ /_/ /_/_/____/\___/      \___/_/ /_/     / .___/_/\__,_/\___/\___/
                                            /_/                 by @jdx
2026.8.5 linux-x64 (2026-08-12)
```

If you are in bash, source .bashrc or open a new terminal
```sh
$ source ~/.bashrc
youruser@HOSTNAME:~$ mise --version
              _                                        __
   ____ ___  (_)_______        ___  ____        ____  / /___ _________
  / __ `__ \/ / ___/ _ \______/ _ \/ __ \______/ __ \/ / __ `/ ___/ _ \
 / / / / / / (__  )  __/_____/  __/ / / /_____/ /_/ / / /_/ / /__/  __/
/_/ /_/ /_/_/____/\___/      \___/_/ /_/     / .___/_/\__,_/\___/\___/
                                            /_/                 by @jdx
2026.8.5 linux-x64 (2026-08-12)
```

Your environment is all set up to clone using SSH and use mise as the foundation for any development setup.
