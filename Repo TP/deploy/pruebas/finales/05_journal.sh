#!/usr/bin/env bash
# Prueba final 05 · Journal (Documento de Pruebas Finales, v1.0).
#   A: kill -9 al Storage después del inicio del 2.º asiento de "modelo" y antes de su COMMIT.
#   B: kill -9 después del COMMIT del 2.º asiento y antes de su APPLIED.
#   En los dos: cortar el resto, levantar solo el Storage (recuperación) → LS + CAT modelo 16,
#   reiniciarlo → LS + CAT, y con el Storage arriba correr JOURNAL_VERIFICAR_<caso>.asm.
set -euo pipefail
C="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/deploy/catedra.sh"

for caso in A B; do
    E="05_journal/$caso"
    printf '\n\033[1;35m### 05 Journal · caso %s\033[0m\n' "$caso"
    "$C" entregas_finales "$E" --solo-iniciar
    if [ "$caso" = A ]; then
        # RETARDO_COMMIT=10000: hay ~10 s entre el inicio del asiento y su COMMIT.
        "$C" entregas_finales "$E" --accion esperar-log storage "## Asiento iniciado: 2" 300
        sleep 2
    else
        # RETARDO_ACCESO_BLOQUE=500: la aplicación de 8 bloques + FAT + directorio tarda varios segundos.
        "$C" entregas_finales "$E" --accion esperar-log storage "## Nueva marca en asiento: 2: - COMMIT" 300
        sleep 1
    fi
    "$C" entregas_finales "$E" --accion matar storage
    "$C" entregas_finales "$E" --accion detener

    "$C" entregas_finales "$E" --accion levantar storage
    "$C" entregas_finales "$E" --accion consola storage LS
    "$C" entregas_finales "$E" --accion consola storage "CAT modelo 16"
    "$C" entregas_finales "$E" --accion parar storage
    "$C" entregas_finales "$E" --accion levantar storage
    "$C" entregas_finales "$E" --accion consola storage LS
    "$C" entregas_finales "$E" --accion consola storage "CAT modelo 16"

    "$C" entregas_finales "$E" --accion levantar placa
    "$C" entregas_finales "$E" --accion levantar planificador "JOURNAL_VERIFICAR_$caso.asm"
    "$C" entregas_finales "$E" --accion levantar core-1
    "$C" entregas_finales "$E" --accion esperar-fin 600 || true
    "$C" entregas_finales "$E" --accion detener
    "$C" entregas_finales "$E" --accion resultados
done
