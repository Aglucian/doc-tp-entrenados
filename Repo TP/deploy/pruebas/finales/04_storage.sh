#!/usr/bin/env bash
# Prueba final 04 · Storage (Documento de Pruebas Finales, v1.0).
#   Corrida 1: ST_ENTRENAR.asm → LS → reiniciar el Storage → LS.
#   Corrida 2 (Storage vacío, configs de fs_lleno): FS_A.asm → LS → reiniciar el Storage → LS.
set -euo pipefail
C="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/deploy/catedra.sh"

for corrida in checkpoints fs_lleno; do
    E="04_storage/$corrida"
    printf '\n\033[1;35m### 04 Storage · %s\033[0m\n' "$corrida"
    "$C" entregas_finales "$E" --solo-iniciar
    "$C" entregas_finales "$E" --accion esperar-fin 900 || true
    "$C" entregas_finales "$E" --accion consola storage LS
    "$C" entregas_finales "$E" --accion parar storage
    "$C" entregas_finales "$E" --accion levantar storage
    "$C" entregas_finales "$E" --accion consola storage LS
    "$C" entregas_finales "$E" --accion detener
    "$C" entregas_finales "$E" --accion resultados
done
