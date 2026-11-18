#!/bin/sh
# Installe soloist-netwatch. A lancer en utilisateur normal (sans devel-su).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p ~/bin ~/.config/systemd/user
cp "$HERE/soloist-netwatch.sh" ~/bin/soloist-netwatch.sh
chmod +x ~/bin/soloist-netwatch.sh
cp "$HERE/soloist-netwatch.service" ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now soloist-netwatch
sleep 2
systemctl --user is-active soloist-netwatch
echo "Journal : ~/.cache/soloist-netwatch.log"
