#!/bin/sh
# Compile et installe soloist-audiores 2.0.0. A lancer en utilisateur normal.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p ~/bin ~/lib ~/.config/systemd/user
gcc -O2 -o ~/bin/soloist-audiores "$HERE/soloist-audiores.c" \
    $(pkg-config --cflags --libs libresource-glib glib-2.0)
gcc -O2 -shared -fPIC -o ~/lib/libforcerole.so "$HERE/forcerole.c" -ldl
cp "$HERE/soloist.service" ~/.config/systemd/user/soloist.service
systemctl --user daemon-reload
systemctl --user restart soloist
sleep 3
systemctl --user is-active soloist
