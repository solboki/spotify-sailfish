#!/bin/bash
#
# soloist-netwatch 1.1.0
#
# Relance Spotify Soloist quand le téléphone change de réseau ou retrouve
# internet après une coupure. Soloist ne rétablit pas lui-même sa connexion
# aux serveurs de Spotify : sans relance, il disparaît de la liste des
# appareils (Hutspot, applications Spotify) jusqu'au prochain redémarrage.
#
# Trois signaux déclenchent une relance :
#   1. la route par défaut change (Wi-Fi <-> données mobiles, autre Wi-Fi) ;
#   2. internet revient après une coupure (petite connexion TCP de test) ;
#   3. Soloist n'a plus aucune connexion ouverte vers internet.
# La relance n'a lieu qu'une fois le réseau stable depuis STABLE_DELAY
# secondes, et jamais plus d'une fois toutes les MIN_GAP secondes.
#
# Réglages possibles dans ~/.config/soloist/netwatch.conf (voir plus bas).

# --- Réglages par défaut ---------------------------------------------------
STABLE_DELAY=10        # secondes de réseau stable avant de relancer
MIN_GAP=30             # secondes minimum entre deux relances
PROBE_ONLINE=30        # test d'internet toutes les N s quand tout va bien
PROBE_OFFLINE=5        # test toutes les N s quand internet est coupé
NO_SOCKET_DELAY=60     # relance si Soloist n'a plus de connexion depuis N s
PROBE_HOST="apresolve.spotify.com"
PROBE_PORT=443
SERVICE="soloist"
LOG="$HOME/.cache/soloist-netwatch.log"

CONF="$HOME/.config/soloist/netwatch.conf"
# shellcheck source=/dev/null
[ -f "$CONF" ] && . "$CONF"

# --- Outils ------------------------------------------------------------------
log() {
    mkdir -p "$(dirname "$LOG")"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
    # garde les 300 dernières lignes
    if [ "$(wc -l < "$LOG")" -gt 400 ]; then
        tail -n 300 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    fi
    echo "$*"
}

now() { date +%s; }

# Route(s) par défaut IPv4 et IPv6 : interface et passerelle.
network_signature() {
    local v4 v6
    v4=$(awk '$2=="00000000" && $8=="00000000" {print $1":"$3}' /proc/net/route 2>/dev/null | sort | tr '\n' ' ')
    v6=$(awk '$1=="00000000000000000000000000000000" && $2=="00" {print $10":"$5}' /proc/net/ipv6_route 2>/dev/null | sort -u | tr '\n' ' ')
    echo "v4[$v4] v6[$v6]"
}

# Internet joignable ? Une simple ouverture de connexion TCP, sans échange
# de données (quelques centaines d'octets).
internet_ok() {
    timeout 5 bash -c "exec 3<>/dev/tcp/$PROBE_HOST/$PROBE_PORT" 2>/dev/null
}

# PID principal de Soloist (le programme lui-même, pas son gestionnaire de
# plantages, qui porte le même nom avec l'option --type=, ni les commandes
# « soloist ctl » lancées par soloist-audiores).
soloist_pid() {
    local d uid
    uid=$(id -u)
    for d in /proc/[0-9]*; do
        [ "$(cat "$d/comm" 2>/dev/null)" = "soloist" ] || continue
        [ "$(stat -c %u "$d" 2>/dev/null)" = "$uid" ] || continue
        # ignore aussi les commandes « soloist ctl ... » du lanceur
        tr '\0' ' ' < "$d/cmdline" 2>/dev/null | grep -qE -- '--type=| ctl ' && continue
        echo "${d#/proc/}"
        return
    done
}

# Nombre de connexions TCP établies de Soloist vers internet.
soloist_connections() {
    local pid="$1" inodes
    [ -n "$pid" ] || { echo 0; return; }
    inodes=$(ls -l "/proc/$pid/fd" 2>/dev/null | sed -n 's/.*socket:\[\([0-9]*\)\].*/\1/p' | sort -u | tr '\n' ' ')
    [ -n "$inodes" ] || { echo 0; return; }
    # état 01 = ESTABLISHED ; on exclut les adresses locales (127.x, ::1)
    cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | awk -v list=" $inodes " '
        NR > 0 && $4 == "01" {
            split($3, r, ":")
            if (r[1] == "0100007F" || r[1] == "00000000000000000000000001000000") next
            if (index(list, " " $10 " ") > 0) n++
        }
        END { print n + 0 }'
}

restart_soloist() {
    log "Relance de Soloist ($1)"
    systemctl --user restart "$SERVICE"
    last_restart=$(now)
    pending=""
    no_socket_since=""
    seen_connected=0
}

# --- Boucle principale -------------------------------------------------------
log "Démarrage de la surveillance du réseau"
last_sig=$(network_signature)
online=1
last_probe=0
last_restart=$(now)
seen_connected=0
pending=""           # raison d'une relance en attente
pending_since=0
no_socket_since=""

while true; do
    t=$(now)

    # 1. changement de réseau
    sig=$(network_signature)
    if [ "$sig" != "$last_sig" ]; then
        log "Réseau modifié : $sig"
        last_sig="$sig"
        pending="changement de réseau"
        pending_since=$t
        last_probe=0            # tester internet tout de suite
    fi

    # 2. internet coupé / revenu
    interval=$PROBE_ONLINE
    [ "$online" = 0 ] && interval=$PROBE_OFFLINE
    [ -n "$pending" ] && interval=$PROBE_OFFLINE
    if [ $((t - last_probe)) -ge "$interval" ]; then
        last_probe=$t
        if internet_ok; then
            if [ "$online" = 0 ]; then
                log "Internet revenu"
                online=1
                pending="retour d'internet"
                pending_since=$t
            fi
        else
            if [ "$online" = 1 ]; then
                log "Internet coupé"
                online=0
            fi
            # tant qu'internet manque, on repousse la relance
            [ -n "$pending" ] && pending_since=$t
        fi
    fi

    # 3. Soloist sans aucune connexion vers internet. Ce contrôle ne
    #    s'active qu'après avoir vu Soloist connecté au moins une fois, pour
    #    ne jamais boucler si Soloist fonctionne sans connexion permanente.
    if [ "$online" = 1 ] && [ -z "$pending" ]; then
        pid=$(soloist_pid)
        conns=0
        [ -n "$pid" ] && conns=$(soloist_connections "$pid")
        if [ "$conns" -gt 0 ]; then
            seen_connected=1
            no_socket_since=""
        elif [ -n "$pid" ] && [ "$seen_connected" = 1 ]; then
            [ -z "$no_socket_since" ] && no_socket_since=$t
            if [ $((t - no_socket_since)) -ge "$NO_SOCKET_DELAY" ]; then
                pending="Soloist sans connexion"
                pending_since=$((t - STABLE_DELAY))
            fi
        fi
    fi

    # relance différée : réseau stable et internet présent
    if [ -n "$pending" ] && [ "$online" = 1 ] \
       && [ $((t - pending_since)) -ge "$STABLE_DELAY" ]; then
        if [ $((t - last_restart)) -ge "$MIN_GAP" ]; then
            restart_soloist "$pending"
        else
            pending_since=$((last_restart + MIN_GAP - STABLE_DELAY))
        fi
    fi

    sleep 2
done
