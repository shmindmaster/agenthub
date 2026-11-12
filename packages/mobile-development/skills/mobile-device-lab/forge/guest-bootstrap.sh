#!/bin/zsh
# One-time toolchain for the macOS guest on sh-forge (user maclab). Needs no Apple ID.
#   scp forge/guest-bootstrap.sh forge-mac: && ssh forge-mac 'zsh guest-bootstrap.sh'
# The guest is Intel (dockur/macos under KVM). Homebrew refuses to install on Intel Macs
# ("only supported on Apple Silicon", seen 2026-11-12), so each tool comes from its own release:
# Node from nodejs.org, Ruby 3.4 from conda-forge (fastlane needs Ruby >= 3.3; the system Ruby is
# 2.6 and the ruby-builder tarballs are pinned to GitHub runner paths), and ccache and xcodes
# from their GitHub releases. Idempotent: an installed tool is skipped. Log: /tmp/forge-bootstrap.log
set -eux
exec > /tmp/forge-bootstrap.log 2>&1
NODE=v24.11.1
mkdir -p ~/.local/bin ~/.local/opt
if ! xcode-select -p >/dev/null 2>&1; then
  sudo -n touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  clt=$(softwareupdate -l 2>/dev/null | grep -E '\* Label: Command Line Tools' | sed 's/^.*Label: //' | sort -V | tail -1)
  sudo -n softwareupdate -i "$clt" --verbose
  sudo -n rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
fi
if [ ! -x ~/.local/opt/node/bin/node ]; then
  curl -fsSL "https://nodejs.org/dist/$NODE/node-$NODE-darwin-x64.tar.xz" -o /tmp/node.tar.xz
  mkdir -p ~/.local/opt/node && tar -xJf /tmp/node.tar.xz -C ~/.local/opt/node --strip-components 1
fi
if [ ! -x ~/.local/opt/ruby/bin/ruby ]; then
  [ -x ~/.local/bin/micromamba ] || { curl -fsSL https://micro.mamba.pm/api/micromamba/osx-64/latest | tar -xj -C /tmp bin/micromamba; mv /tmp/bin/micromamba ~/.local/bin/; }
  MAMBA_ROOT_PREFIX="$HOME/.local/mamba" ~/.local/bin/micromamba create -y -p ~/.local/opt/ruby -c conda-forge ruby=3.4 compilers make pkg-config libffi
fi
cat > ~/.zshenv <<'EOF'
# forge toolchain (no Homebrew on Intel): Node 24, Ruby 3.4 from conda-forge with its gems, ccache, xcodes.
export GEM_HOME="$HOME/.local/opt/ruby/share/rubygems"
export GEM_PATH="$GEM_HOME"
export PATH="$GEM_HOME/bin:$HOME/.local/opt/ruby/bin:$HOME/.local/opt/node/bin:$HOME/.local/bin:$PATH"
export LANG=en_US.UTF-8
EOF
# /etc/zprofile's path_helper would put the system Ruby first in login shells.
printf '%s\n' '# Runs after /etc/zprofile (path_helper), so the forge toolchain stays first.' 'source $HOME/.zshenv' > ~/.zprofile
source ~/.zshenv
command -v eas >/dev/null || npm i -g eas-cli@latest
command -v pod >/dev/null && command -v fastlane >/dev/null || gem install --no-document cocoapods fastlane
if ! command -v ccache >/dev/null; then
  url=$(curl -fsSL https://api.github.com/repos/ccache/ccache/releases/latest | grep -oE '"browser_download_url": "[^"]*darwin[^"]*\.tar\.gz"' | head -1 | cut -d'"' -f4)
  curl -fsSL "$url" -o /tmp/ccache.tgz && tar -xzf /tmp/ccache.tgz -C /tmp && cp /tmp/ccache-*/ccache ~/.local/bin/
fi
# The Rexa and ABACare guest builds read ccache at this path (CCACHE_BINARY).
sudo -n mkdir -p /usr/local/bin && sudo -n ln -sf ~/.local/bin/ccache /usr/local/bin/ccache
if ! command -v xcodes >/dev/null; then
  url=$(curl -fsSL https://api.github.com/repos/XcodesOrg/xcodes/releases/latest | grep -oE '"browser_download_url": "[^"]*xcodes\.zip"' | head -1 | cut -d'"' -f4)
  curl -fsSL "$url" -o /tmp/xcodes.zip && unzip -o -q /tmp/xcodes.zip -d ~/.local/bin && chmod +x ~/.local/bin/xcodes
fi
# A headless build host: never sleep, restart after a power loss, no automatic OS updates.
sudo -n pmset -a sleep 0 displaysleep 0 disksleep 0 standby 0 autorestart 1
sudo -n softwareupdate --schedule off || true
# Spotlight indexing takes most of a core after every boot; a build host needs no search index.
sudo -n mdutil -a -i off >/dev/null || true
for t in node eas ruby pod fastlane ccache xcodes; do printf '%s=%s\n' "$t" "$(command -v $t || echo MISSING)"; done
echo GUEST-BOOTSTRAP-DONE
