#!/usr/bin/env bash
# Host side of the macOS VM on sh-forge: compose file, patched boot script, and the root key that
# `mac run`, `mac shell` and `mac proxy` use. Run as root on forge from this folder:
#   scp compose.yml host-setup.sh mac forge:/tmp/ && ssh forge 'cd /tmp && bash host-setup.sh'
# Idempotent. Applies the dockur/macos guidance and two known-issue fixes (checked 2026-11-12):
#   - dockur/macos#572: on Intel KVM hosts the guest can deadlock with every vCPU at 100% and frozen
#     block I/O unless the CPU exposes +invtsc. That hung the first install here. Fixed upstream in
#     qemus/qemu#1513 (2026-09-08), not yet in dockurr/macos 3.12, hence CPU_FLAGS in compose.yml.
#   - dockur/macos#583: QEMU's isa-applesmc rejects SMC get-key-by-index, so PerfPowerServices pins a
#     core. OpenCore already loads VirtualSMC, so boot.sh is regenerated from the pinned image with
#     that one device line commented out. Re-run this script after changing the image tag.
# The image tag is pinned in compose.yml because boot.sh is copied from that exact image.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
install -d /opt/macos /opt/macos/storage
install -m 644 "$here/compose.yml" /opt/macos/compose.yml
install -m 755 "$here/mac" /usr/local/bin/mac
image=$(sed -n 's/^\s*image:\s*//p' /opt/macos/compose.yml | head -1)
docker pull -q "$image" >/dev/null
docker run --rm --entrypoint cat "$image" /run/boot.sh > /opt/macos/boot.sh
if grep -q '^\s*BOOT_OPTS+=" -device isa-applesmc' /opt/macos/boot.sh; then
  sed -i 's|^\(\s*\)\(BOOT_OPTS+=" -device isa-applesmc,osk=\$osk"\)|\1# forge: dockur/macos#583, VirtualSMC in OpenCore supplies the OSK\n\1# \2|' /opt/macos/boot.sh
fi
grep -q '^\s*# BOOT_OPTS+=" -device isa-applesmc' /opt/macos/boot.sh || { echo "boot.sh layout changed in $image; review dockur/macos#583 before starting" >&2; exit 1; }
[ -f /root/.ssh/forge-mac ] || ssh-keygen -q -t ed25519 -N '' -C 'sh-forge root -> forge-mac guest' -f /root/.ssh/forge-mac
grep -q 'forge-mac guest' /root/.ssh/config 2>/dev/null || printf '\n# forge-mac guest (mac run / mac shell / mac proxy)\nHost 127.0.0.1\n  IdentityFile /root/.ssh/forge-mac\n' >> /root/.ssh/config
chmod 600 /root/.ssh/config
docker compose -f /opt/macos/compose.yml config -q
echo "host-setup: ok. Authorize /root/.ssh/forge-mac.pub in the guest (~maclab/.ssh/authorized_keys) once."
