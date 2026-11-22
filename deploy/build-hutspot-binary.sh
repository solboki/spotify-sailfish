#!/bin/sh
# Compile le programme Hutspot (partie C++) sur le téléphone et remplace
# celui du paquet Chum. Nécessaire pour les corrections de la partie compilée
# (ex. requêtes réseau après un passage Wi-Fi / données mobiles).
# A lancer en utilisateur normal : sh build-hutspot-binary.sh
# (le mot de passe devel-su est demandé pour installer).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HOME/hutspot-build"

echo "1/4 Outils de compilation"
for p in gcc-c++ make qt5-qmake qt5-qtcore-devel qt5-qtnetwork-devel qt5-qtgui-devel \
         qt5-qtdeclarative-devel qt5-qtdeclarative-qtquick-devel libsailfishapp-devel \
         openssl-devel qt5-qttools-linguist; do
    if ! rpm -q "$p" >/dev/null 2>&1; then
        missing="$missing $p"
    fi
done
if [ -n "$missing" ]; then
    echo "Installation de :$missing"
    # shellcheck disable=SC2086
    devel-su pkcon -y install $missing
fi

echo "2/4 Préparation des sources"
rm -rf "$BUILD"
cp -a "$HERE/source" "$BUILD"
cd "$BUILD"

echo "3/4 Compilation (quelques minutes)"
QMAKE=$(command -v qmake || echo /usr/lib/qt5/bin/qmake)
$QMAKE CONFIG+=release hutspot.pro
make -j2

echo "4/4 Installation (mot de passe devel-su)"
devel-su sh -c "[ -f /usr/bin/hutspot.orig ] || cp /usr/bin/hutspot /usr/bin/hutspot.orig; \
install -m 755 '$BUILD/hutspot' /usr/bin/hutspot"
echo
echo "Programme installé. L'original est sauvegardé dans /usr/bin/hutspot.orig."
echo "Fermez puis relancez Hutspot."
