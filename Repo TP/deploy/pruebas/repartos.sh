#!/usr/bin/env bash
# Corre los mismos escenarios de la cátedra con distintos repartos de módulos entre servidores.
# Uso: deploy/pruebas/repartos.sh
#
# Cada reparto: nombre | Placa | Storage | Planificador | Cores (separados por espacio).
# Los escenarios elegidos ejercitan planificación con 2 Cores (CP2 04 en modo rápido) y
# memoria + servicios + Labeler con 2 Cores (CP3 07).

set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
S=192.168.1

REPARTOS=(
    "todo junto|$S.25|$S.25|$S.25|$S.25 $S.25"
    "memoria aparte|$S.25|$S.25|$S.26|$S.26 $S.27"
    "Cores con la Placa|$S.25|$S.26|$S.26|$S.25 $S.25"
    "Cores separados|$S.27|$S.28|$S.29|$S.25 $S.26"
)

ESCENARIOS=(
    "checkpoint_2 04_rr_dos_cores --rapido"
    "checkpoint_3 07_servicios_fifo"
)

RESUMEN=()

for reparto in "${REPARTOS[@]}"; do
    IFS='|' read -r nombre placa storage planificador cores <<< "$reparto"
    printf '\n\033[1;36m######## Reparto: %s (Placa %s · Storage %s · Planificador %s · Cores %s)\033[0m\n' \
        "$nombre" "$placa" "$storage" "$planificador" "$cores"

    for escenario in "${ESCENARIOS[@]}"; do
        # shellcheck disable=SC2086
        if PLACA="$placa" STORAGE="$storage" PLANIFICADOR="$planificador" CORES_HOSTS="$cores" \
            "$RAIZ/deploy/catedra.sh" $escenario --timeout 600; then
            RESUMEN+=("OK    $nombre · ${escenario%% --*}")
        else
            RESUMEN+=("FALLA $nombre · ${escenario%% --*}")
        fi
    done
done

printf '\n\033[1mResumen\033[0m\n'
printf '  %s\n' "${RESUMEN[@]}"
printf '%s\n' "${RESUMEN[@]}" | grep -q '^FALLA' && exit 1 || exit 0
