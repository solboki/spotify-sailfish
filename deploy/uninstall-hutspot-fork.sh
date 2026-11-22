#!/bin/sh
# Remet les fichiers QML d'origine de Hutspot. A lancer avec devel-su.
set -e
[ -d /usr/share/hutspot/qml.orig ] || { echo "Pas de sauvegarde trouvée."; exit 1; }
rm -rf /usr/share/hutspot/qml
cp -a /usr/share/hutspot/qml.orig /usr/share/hutspot/qml
rm -f /usr/share/hutspot/translations/hutspot-fr.qm
if [ -f /usr/share/applications/hutspot.desktop.orig ]; then
    cp /usr/share/applications/hutspot.desktop.orig /usr/share/applications/hutspot.desktop
fi
rm -rf /usr/share/hutspot/python
rm -f /usr/share/dbus-1/services/org.solboki.Hutspot.service /usr/share/dbus-1/services/org.solboki.hutspot.service
echo "Fichiers d'origine restaurés."
