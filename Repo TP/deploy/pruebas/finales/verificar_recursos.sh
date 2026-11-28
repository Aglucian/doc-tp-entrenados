#!/usr/bin/env bash
# Prueba final 06, "no hay esperas activas ni memory leaks", con evidencia:
#   1. La 06 completa con los 4 módulos bajo valgrind (--leak-check=full) y las mismas
#      actividades de Cores; al final, CPU de cada proceso con todo en reposo.
#   2. La 03 con el Labeler esperando teclado (nadie responde): CPU de cada proceso mientras
#      los Jobs están bloqueados. Una espera activa se ve como ~100 % de un núcleo.
set -euo pipefail
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
C="$RAIZ/deploy/catedra.sh"
V=(--valgrind "storage placa planificador core")
E=06_estabilidad

printf '\n\033[1;35m### 06 bajo valgrind\033[0m\n'
"$C" entregas_finales "$E" "${V[@]}" --cores "1 2" --solo-iniciar
"$C" entregas_finales "$E" --accion esperar-log planificador "Pasa del estado NEW al estado READY" 300
sleep 5
"$C" entregas_finales "$E" "${V[@]}" --accion levantar core-3
sleep 15
"$C" entregas_finales "$E" --accion cpu 10
"$C" entregas_finales "$E" --accion cortar-durante core-1 "Ejecutando: (FORWARD|BACKWARD)" 600
sleep 10
"$C" entregas_finales "$E" "${V[@]}" --accion levantar core-1
sleep 10
"$C" entregas_finales "$E" "${V[@]}" --accion levantar core-4
"$C" entregas_finales "$E" --accion esperar-fin 3600 || true
"$C" entregas_finales "$E" --accion consola placa INFO 3
"$C" entregas_finales "$E" --accion consola storage LS
printf '\n\033[1;35m### CPU en reposo (todos los Jobs terminados)\033[0m\n'
"$C" entregas_finales "$E" --accion cpu 20
"$C" entregas_finales "$E" --accion detener
"$C" entregas_finales "$E" --accion resultados
R=$(ls -td "$RAIZ"/deploy/resultados/catedra-entregas_finales-06_estabilidad-* | head -1)

printf '\n\033[1;35m### Resumen de valgrind\033[0m\n'
for v in "$R"/*/valgrind.*.txt; do
    [ -f "$v" ] || continue
    printf '  %-32s definitely=%-10s indirectly=%-10s errores=%s\n' "${v#"$R"/}" \
        "$(grep -oP 'definitely lost: \K[0-9,]+ bytes' "$v" || echo '-')" \
        "$(grep -oP 'indirectly lost: \K[0-9,]+ bytes' "$v" || echo '-')" \
        "$(grep -oP 'ERROR SUMMARY: \K[0-9,]+' "$v" || echo '-')"
done

printf '\n\033[1;35m### CPU con el Labeler esperando teclado (03, sin responder)\033[0m\n'
"$C" entregas_finales 03_servicios --solo-iniciar
"$C" entregas_finales 03_servicios --accion esperar-log planificador "Ingrese 8 caracteres" 300
sleep 10
"$C" entregas_finales 03_servicios --accion cpu 20
"$C" entregas_finales 03_servicios --accion detener
