#!/bin/bash
# Affiche l'état de Soloist : yes (connecté), no (à appairer), stopped.
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=soloist-common.sh
. "$HERE/soloist-common.sh"
soloist_login_state
