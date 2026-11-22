# Réglages communs aux scripts Soloist de Hutspot (fichier inclus, pas lancé).
SOLOIST="${SOLOIST:-$HOME/soloist/soloist}"
SOLOIST_ENV="${SOLOIST_ENV:-$HOME/.config/soloist/env}"
DEVICE_NAME="${DEVICE_NAME:-JollaPhone}"

# Affiche « yes », « no » ou « stopped » (Soloist arrêté ou absent).
soloist_login_state() {
    local out
    out=$("$SOLOIST" ctl status 2>/dev/null) || { echo stopped; return; }
    case "$out" in
        *"logged in: yes"*) echo yes ;;
        *"running"*) echo no ;;
        *) echo stopped ;;
    esac
}

# Attend jusqu'à $1 secondes que Soloist soit connecté au compte.
wait_logged_in() {
    local i
    for i in $(seq 1 "$1"); do
        [ "$(soloist_login_state)" = yes ] && return 0
        sleep 1
    done
    return 1
}
