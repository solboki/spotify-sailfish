#!/bin/sh
# Remet les fichiers QML d'origine de Hutspot. A lancer avec devel-su.
set -e
[ -d /usr/share/hutspot/qml.orig ] || { echo "Pas de sauvegarde trouvée."; exit 1; }
rm -rf /usr/share/hutspot/qml
cp -a /usr/share/hutspot/qml.orig /usr/share/hutspot/qml
rm -f /usr/share/hutspot/translations/hutspot-fr.qm
echo "Fichiers d'origine restaurés."
