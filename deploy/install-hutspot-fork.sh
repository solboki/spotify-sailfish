#!/bin/sh
# Installe le fork de Hutspot (fichiers QML) par-dessus le paquet Chum.
# A lancer avec : devel-su sh install-hutspot-fork.sh
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST=/usr/share/hutspot/qml
DESKTOP=/usr/share/applications/hutspot.desktop

if [ "$(id -u)" != "0" ]; then
    echo "Lancez ce script avec devel-su."; exit 1
fi
if [ ! -d "$DEST" ]; then
    echo "Hutspot n'est pas installé ($DEST introuvable)."; exit 1
fi

# 1. Sauvegarde des fichiers d'origine (une seule fois)
if [ ! -d /usr/share/hutspot/qml.orig ]; then
    cp -a "$DEST" /usr/share/hutspot/qml.orig
    echo "Sauvegarde : /usr/share/hutspot/qml.orig"
fi

# 2. Copie des fichiers QML du fork
cp -a "$HERE/qml/." "$DEST/"
echo "Fichiers QML du fork installés."

# 3. Bac à sable SailJail désactivé, sinon Hutspot ne peut pas
#    enregistrer son jeton de connexion (~/.config/wdehoog/hutspot.conf)
if ! grep -q "^Sandboxing=Disabled" "$DESKTOP"; then
    if grep -q "^\[X-Sailjail\]" "$DESKTOP"; then
        sed -i '/^\[X-Sailjail\]/a Sandboxing=Disabled' "$DESKTOP"
    else
        printf '\n[X-Sailjail]\nSandboxing=Disabled\n' >> "$DESKTOP"
    fi
    echo "SailJail désactivé pour Hutspot."
fi

# 4. Soloist classé comme lecteur de musique pour PulseAudio :
#    les boutons de volume du téléphone règlent alors son son.
mkdir -p /etc/pulse/xpolicy.conf.d
cat > /etc/pulse/xpolicy.conf.d/soloist.conf <<'POL'
[stream]
exe      = soloist
group    = player
POL
echo "Règle PulseAudio pour Soloist installée."

echo
echo "Terminé. En tant qu'utilisateur normal (sans devel-su), lancez :"
echo "  systemctl --user restart pulseaudio && systemctl --user restart soloist"
