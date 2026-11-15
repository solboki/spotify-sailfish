#!/bin/sh
# Compile le RPM de Hutspot sur le téléphone.
# Usage : sh build-rpm.sh   (en utilisateur normal, dans le dossier de l'archive)
set -e
V=0.9.0
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "1/3 Outils de compilation (mot de passe devel-su demandé)"
devel-su pkcon -y install rpm-build qt5-qmake qt5-qtdeclarative-devel \
    libsailfishapp-devel openssl-devel qt5-qttools-linguist desktop-file-utils

echo "2/3 Préparation"
mkdir -p ~/rpmbuild/SOURCES ~/rpmbuild/SPECS
cp "$HERE/hutspot-$V.tar.bz2" ~/rpmbuild/SOURCES/
cp "$HERE/hutspot.spec" ~/rpmbuild/SPECS/

echo "3/3 Compilation (quelques minutes)"
rpmbuild -bb ~/rpmbuild/SPECS/hutspot.spec

echo
echo "RPM prêt :"
ls ~/rpmbuild/RPMS/*/hutspot-$V-*.rpm
