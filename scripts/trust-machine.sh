#!/usr/bin/env bash
# Let a new machine SSH into mini1 and mini2.
#
# Run this on a machine the minis already trust (the MacBook). It reads the
# new machine's public key over SSH and appends it to each mini's
# authorized_keys, once. scripts/arch.sh generates that key on the new machine
# and prints the command to run here.
#
#   trust-machine.sh [ssh options] user@host
#   trust-machine.sh -o HostKeyAlias=thinkpad-omarchy joseph@192.168.219.189
#
# The minis are reached over Tailscale; the same addresses as in zshrc.
set -euo pipefail

MINIS=(michaelkang@100.122.37.52 josephjun@100.119.210.87)

if (( $# == 0 )); then
  echo "usage: $(basename "$0") [ssh options] user@host" >&2
  exit 2
fi

key="$(ssh -o ConnectTimeout=15 "$@" 'cat ~/.ssh/id_ed25519.pub')"
if ! [[ "$key" =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+(\ [^[:cntrl:]]*)?$ ]]; then
  echo "that machine's ~/.ssh/id_ed25519.pub is not a single ed25519 public key" >&2
  exit 1
fi
echo "key: $key"

failed=0
for mini in "${MINIS[@]}"; do
  if printf '%s\n' "$key" | ssh -o IdentitiesOnly=yes -i "$HOME/.ssh/id_ed25519" -o ConnectTimeout=15 "$mini" '
      key=$(cat)
      mkdir -p ~/.ssh && chmod 700 ~/.ssh
      touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
      if grep -qxF "$key" ~/.ssh/authorized_keys; then
        echo "already trusted"
      else
        printf "%s\n" "$key" >> ~/.ssh/authorized_keys && echo "added"
      fi'; then
    echo "  ^ $mini"
  else
    echo "could not reach $mini" >&2
    failed=1
  fi
done
exit "$failed"
