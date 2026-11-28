#!/usr/bin/env bash
# Prueba final 06 · Estabilidad General (Documento de Pruebas Finales, v1.0).
# Arranca con los Cores 1 y 2 y, durante la corrida, hace al menos una vez cada actividad:
#   - conectar un Core con Jobs en READY            (Core 3)
#   - finalizar un Core mientras ejecuta FORWARD o BACKWARD de un Job (Core 1)
#   - volver a conectar un Core finalizado          (Core 1)
#   - conectar otro Core más                        (Core 4)
# Al final: INFO en la Placa y LS en el Storage.
set -euo pipefail
C="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/deploy/catedra.sh"
E=06_estabilidad

printf '\n\033[1;35m### 06 Estabilidad General\033[0m\n'
"$C" entregas_finales "$E" --cores "1 2" --solo-iniciar
"$C" entregas_finales "$E" --accion esperar-log planificador "Pasa del estado NEW al estado READY" 120
sleep 5
"$C" entregas_finales "$E" --accion levantar core-3
sleep 10
"$C" entregas_finales "$E" --accion cortar-durante core-1 "Ejecutando: (FORWARD|BACKWARD)" 300
sleep 10
"$C" entregas_finales "$E" --accion levantar core-1
sleep 10
"$C" entregas_finales "$E" --accion levantar core-4
"$C" entregas_finales "$E" --accion esperar-fin 1800 || true
"$C" entregas_finales "$E" --accion consola placa INFO 3
"$C" entregas_finales "$E" --accion consola storage LS
"$C" entregas_finales "$E" --accion detener
"$C" entregas_finales "$E" --accion resultados
