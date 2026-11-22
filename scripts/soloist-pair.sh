#!/bin/bash
#
# Réappaire Soloist avec le compte Spotify.
# Arrête le service Soloist et la surveillance du réseau, lance Soloist en
# mode appairage (--pair) et attend qu'une application Spotify (ordinateur,
# autre téléphone) sur le même Wi-Fi sélectionne l'appareil. Les services
# sont toujours relancés à la fin, même en cas d'échec ou d'interruption.
#
# Usage : soloist-pair.sh [délai en secondes, 180 par défaut]
# Sortie : « WAITING » quand l'appareil est visible, puis « RESULT <code> » :
#   ok       appairage enregistré, Soloist connecté
#   timeout  personne n'a sélectionné l'appareil à temps
#   nokey    pas de clé Soloist enregistrée
#   failed   Soloist n'a pas pu être lancé
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=soloist-common.sh
. "$HERE/soloist-common.sh"
TIMEOUT="${1:-180}"

# shellcheck source=/dev/null
[ -f "$SOLOIST_ENV" ] && . "$SOLOIST_ENV"
if [ -z "$SOLOIST_API_KEY" ]; then
    echo "Aucune clé Soloist enregistrée."
    echo "RESULT nokey"
    exit 2
fi

had_netwatch=0
systemctl --user is-active --quiet soloist-netwatch && had_netwatch=1

restart_services() {
    systemctl --user start soloist
    [ "$had_netwatch" = 1 ] && systemctl --user start soloist-netwatch
}
trap restart_services EXIT

systemctl --user stop soloist-netwatch soloist 2>/dev/null
sleep 1

result=timeout
while IFS= read -r line; do
    case "$line" in
        *"pairing mode"*) echo "WAITING" ;;
        *"pairing complete"*) result=ok ;;
    esac
done < <(timeout "$TIMEOUT" "$SOLOIST" -n "$DEVICE_NAME" -k "$SOLOIST_API_KEY" --pair -v 2>&1)
wait $! 2>/dev/null
code=$?

if [ "$result" != ok ] && [ "$code" != 124 ] && [ "$code" != 0 ]; then
    result=failed
fi

restart_services
trap - EXIT
if [ "$result" = ok ]; then
    wait_logged_in 20 || true
fi
echo "STATE $(soloist_login_state)"
echo "RESULT $result"
[ "$result" = ok ]
