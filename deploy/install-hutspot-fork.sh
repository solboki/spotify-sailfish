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

# 2 bis. Traduction française
if [ -f "$HERE/translations/hutspot-fr.qm" ]; then
    mkdir -p /usr/share/hutspot/translations
    cp "$HERE/translations/hutspot-fr.qm" /usr/share/hutspot/translations/
    echo "Traduction française installée."
fi

# 3. Fichier .desktop du fork : bac à sable SailJail désactivé (sinon la
#    connexion est oubliée), catégorie « lecteur audio » et déclaration
#    Sailplay (écran de la voiture). L'original est sauvegardé une fois.
if [ ! -f "$DESKTOP.orig" ]; then
    cp "$DESKTOP" "$DESKTOP.orig"
fi
cp "$HERE/hutspot.desktop" "$DESKTOP"
echo "Fichier .desktop installé."

# 3 bis. Voiture (Sailplay) : service « Parcourir » et démarrage par D-Bus
mkdir -p /usr/share/hutspot/python /usr/share/dbus-1/services
cp "$HERE/python/sailplay_service.py" /usr/share/hutspot/python/
cp "$HERE/dbus/org.solboki.Hutspot.service" "$HERE/dbus/org.solboki.hutspot.service" \
   /usr/share/dbus-1/services/
echo "Service Sailplay installé."

# 3 ter. Scripts Soloist (réappairage, nouvelle clé), utilisés par les Réglages
mkdir -p /usr/share/hutspot/scripts
cp "$HERE"/scripts/soloist-*.sh /usr/share/hutspot/scripts/
chmod 755 /usr/share/hutspot/scripts/soloist-*.sh
echo "Scripts Soloist installés."

echo
echo "Terminé."
echo "  Fermez puis relancez Hutspot."
