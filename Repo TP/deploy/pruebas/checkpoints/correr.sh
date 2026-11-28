#!/usr/bin/env bash
# Prueba del Check 4 en los servidores. Uso: deploy/pruebas/checkpoints/correr.sh [--local]
#   1. entrenar          guarda modelo7 (Storage recién formateado)
#   2. restaurar         script independiente: carga modelo7 y lo reporta (volumen conservado)
#   3. guardar_grande    guarda 2 KB y se hace kill -9 al Storage después del COMMIT;
#                        al levantarlo, el journal tiene que re-aplicar el asiento
#   4. verificar_grande  carga "grande" y el reporte tiene que coincidir con lo guardado

set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(cd "$AQUI/../../.." && pwd)"
D="$RAIZ/deploy/desplegar.sh"
FALLAS=0

paso() { printf '\n\033[1;35m### %s\033[0m\n' "$*"; }
chequear() {
    if [ "$2" = ok ]; then printf '  \033[32mOK\033[0m    %s\n' "$1"; else printf '  \033[31mFALLA\033[0m %s\n' "$1"; FALLAS=$((FALLAS + 1)); fi
}
ultimo_resultado() { ls -td "$RAIZ"/deploy/resultados/checkpoints-* | head -1; }
hexa() { od -An -v -tx1 "$1" | tr -d ' \n' | tr 'a-f' 'A-F'; }
reporte() { sed -E 's/^## \([0-9]+\) - //' "$(ultimo_resultado)/planificador/reportes.log" 2>/dev/null | head -1; }

[ "${1:-}" = "--local" ] && "$D" "$AQUI" preparar --local

paso "1. entrenar: SAVE_CHECKPOINT modelo7"
"$D" "$AQUI" ejecutar --job entrenar
R=$(ultimo_resultado)
grep -q "motivo de EXIT" "$R/planificador/planificador.log" && c=ok || c=x; chequear "el Job terminó con EXIT" $c
grep -q "## Guardado Checkpoint: modelo7 - Tamaño: 256 completada" "$R/storage/storage.log" && c=ok || c=x; chequear "el Storage guardó modelo7 (256 bytes)" $c

paso "2. restaurar (script independiente): LOAD_CHECKPOINT modelo7"
"$D" "$AQUI" ejecutar --job restaurar --conservar-storage
R=$(ultimo_resultado)
esperado=$(hexa "$AQUI/datos/lote1" | cut -c1-64)
[ "$(reporte)" = "$esperado" ] && c=ok || c=x; chequear "el reporte coincide con lo que guardó entrenar" $c
grep -q "El Checkpoint temporal no existe" "$R/planificador/planificador.log" && grep -q "motivo de EXIT" "$R/planificador/planificador.log" && c=ok || c=x
chequear "DELETE de un Checkpoint inexistente: solo se informa y el Job termina con EXIT" $c

paso "3. guardar_grande + kill -9 al Storage en medio de la aplicación"
"$D" "$AQUI" iniciar --job guardar_grande --conservar-storage
"$D" "$AQUI" esperar storage "Nueva marca en asiento: 1: - COMMIT" 60
# Primero se aplican el directorio y las 32 entradas de la FAT (~1,7 s): así el kill cae con bloques a medio escribir.
sleep 2.3
"$D" "$AQUI" matar storage
"$D" "$AQUI" levantar storage
"$D" "$AQUI" esperar storage "## Recuperación - Asiento" 30
sleep 1
"$D" "$AQUI" detener
"$D" "$AQUI" logs
R=$(ultimo_resultado)
grep -q "Recuperación - Asiento: 1 - APLICADO" "$R/storage/storage.log" && c=ok || c=x; chequear "el journal re-aplicó el asiento del guardado interrumpido" $c
# El Storage reiniciado escribe en el mismo log: se cuenta solo hasta el reinicio.
antes=$(awk '/Nueva marca en asiento: 1: - COMMIT/{f=1;next} f && /Filesystem existente detectado/{exit} f && /Acceso Bloque - Checkpoint: grande/' "$R/storage/storage.log" | wc -l)
echo "        (antes del kill -9 se habían escrito $antes de 32 bloques)"

paso "4. verificar_grande: LOAD_CHECKPOINT grande"
"$D" "$AQUI" ejecutar --job verificar_grande --conservar-storage
[ "$(reporte)" = "$(hexa "$AQUI/datos/lote_grande")" ] && c=ok || c=x; chequear "los 2048 bytes recuperados son exactamente los que se guardaron" $c

echo
[ "$FALLAS" -eq 0 ] && printf '\033[1;32mTODO OK\033[0m\n' || { printf '\033[1;31m%s FALLAS\033[0m\n' "$FALLAS"; exit 1; }
