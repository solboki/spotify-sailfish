#!/bin/bash
#
# Enregistre une nouvelle clé d'API Soloist et redémarre Soloist.
# La clé est lue sur l'entrée standard (jamais en argument, pour qu'elle
# n'apparaisse pas dans la liste des processus). Dans un terminal, elle est
# demandée sans être affichée.
#
# Sortie : lignes « STATE <yes|no|stopped> » puis « RESULT <code> » :
#   ok        clé enregistrée, Soloist connecté au compte
#   needpair  clé enregistrée, mais Soloist doit être appairé à nouveau
#   invalid   la clé ne ressemble pas à une clé Soloist (spak_...)
#   failed    Soloist n'a pas redémarré
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=soloist-common.sh
. "$HERE/soloist-common.sh"

if [ -t 0 ]; then
    read -rs -p "Nouvelle clé Soloist : " KEY
    echo
else
    read -r KEY
fi
KEY="$(printf '%s' "$KEY" | tr -d '[:space:]')"

if ! printf '%s' "$KEY" | grep -qE '^spak_[A-Za-z0-9_-]{16,}$'; then
    echo "La clé doit commencer par spak_ (copiez-la depuis Spotify for Developers)."
    echo "RESULT invalid"
    exit 2
fi

mkdir -p "$(dirname "$SOLOIST_ENV")"
umask 077
printf 'SOLOIST_API_KEY=%s\n' "$KEY" > "$SOLOIST_ENV.tmp" && mv "$SOLOIST_ENV.tmp" "$SOLOIST_ENV"
chmod 600 "$SOLOIST_ENV"
unset KEY
echo "Clé enregistrée."

systemctl --user restart soloist
if wait_logged_in 20; then
    echo "STATE yes"
    echo "RESULT ok"
    exit 0
fi
state="$(soloist_login_state)"
echo "STATE $state"
if [ "$state" = no ]; then
    echo "Soloist fonctionne mais n'est pas connecté : réappairez-le."
    echo "RESULT needpair"
    exit 0
fi
echo "Soloist n'a pas redémarré (systemctl --user status soloist)."
echo "RESULT failed"
exit 1
