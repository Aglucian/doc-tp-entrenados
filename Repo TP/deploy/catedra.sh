#!/usr/bin/env bash
# Corre escenarios de la suite de la cátedra (entrenados-pruebas) en los servidores.
#
# Uso: deploy/catedra.sh <checkpoint_N|entregas_finales> <escenario|todos> [opciones]
#   ej: deploy/catedra.sh checkpoint_3 04_mini_lru
#       deploy/catedra.sh checkpoint_2 05_multiprogramacion/grado_1
#       deploy/catedra.sh entregas_finales 01_planificacion/HRRN     (prueba/variante)
#       deploy/catedra.sh checkpoint_3 todos
#
# Opciones:
#   --preparar         Antes de correr, despliega origin/develop en los servidores.
#   --preparar-local   Antes de correr, despliega este checkout (cambios sin pushear incluidos).
#   --timeout <s>      Máximo de espera por escenario (por defecto 600).
#   --rapido           Pasada rápida que sugiere la guía de CP2: RETARDO_MEMORIA=10 y, en RR,
#                      RR_QUANTUM=20 (con 500 ms por FETCH, cada escenario 02–05 ronda 12 minutos).
#   --job <script>     Job inicial distinto del README, relativo a scripts/ del checkpoint.
#                      En checkpoint_2/01_instrucciones, sin --job se corren los nueve
#                      scripts de scripts/individuales/ de a uno, como pide la prueba.
#   --cores "<ids>"    Cores que se arrancan al principio (por defecto, todos los core-N.config).
#                      Los demás quedan configurados para levantarlos después con --accion.
#   --solo-iniciar     Prepara y levanta todo, y termina: no espera a los Jobs ni detiene nada.
#   --conservar-storage  No borra el volumen ni el journal del escenario (corridas encadenadas).
#   --valgrind "<mods>"  Corre esos módulos (storage, placa, planificador, core) bajo valgrind
#                      --leak-check=full; el reporte queda en valgrind.<pid>.txt de cada módulo.
#
# Acciones sobre un escenario ya iniciado (para armar secuencias como las de entregas_finales):
#   --accion esperar-log <módulo> <texto> [s]  espera a que el texto aparezca en el log
#   --accion matar <módulo>                    kill -9 (storage, placa, planificador, core-N)
#   --accion parar <módulo>                    finalización normal (Ctrl-C)
#   --accion cortar-durante <módulo> <ERE> [s] Ctrl-C apenas la última línea del log coincide
#   --accion levantar <módulo> [script]        lo vuelve a arrancar (al Planificador, con otro script)
#   --accion consola <módulo> <comando>        escribe un comando en la consola (Storage o Placa)
#   --accion esperar-fin [s]                   espera a que terminen todos los Jobs creados
#   --accion detener                           corta todos los módulos
#   --accion limpiar-storage                   borra el volumen y el journal del escenario
#   --accion resultados                        trae logs y reportes a deploy/resultados/
#   --accion cpu [s]                           % de CPU de cada proceso del TP durante s segundos
#
# Al terminar, compara con los resultados esperados (deploy/verificar_catedra.py):
#   checkpoint_2: finalización por EXIT, registros finales y secuencia de FETCH;
#   checkpoint_3: cómo finaliza cada Job y la secuencia de REPORT.
#
# Usa las configs del escenario tal como vienen: solo cambia 127.0.0.1 por la IP de cada
# servidor (deploy/catedra.conf) y pasa las rutas relativas a absolutas dentro del clon de
# entrenados-pruebas de cada servidor. Las respuestas al Labeler y los comandos de consola
# del Storage después de reiniciarlo salen de deploy/catedra_entradas.conf.
#
# Cada módulo corre en una sesión de tmux (tp-placa, tp-storage, tp-planificador, tp-core-<id>).
# Los resultados quedan en deploy/resultados/catedra-<checkpoint>-<escenario>-<fecha>/.

set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8)

uso() {
    awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"
    exit 1
}

[ $# -ge 2 ] || uso

# shellcheck source=servidores.conf
source "$RAIZ/deploy/servidores.conf"
# shellcheck source=catedra.conf
source "$RAIZ/deploy/catedra.conf"

CP="$1"
ESCENARIO_PEDIDO="$2"
shift 2

PREPARAR=""
TIMEOUT=600
JOB_PEDIDO=""
RAPIDO=false
CORES_PEDIDOS=""
SOLO_INICIAR=false
CONSERVAR_STORAGE=false
ACCION=""
ACCION_ARGS=()
VALGRIND_MODS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --preparar)       PREPARAR=remoto; shift ;;
        --preparar-local) PREPARAR=local; shift ;;
        --timeout)        TIMEOUT="$2"; shift 2 ;;
        --job)            JOB_PEDIDO="$2"; shift 2 ;;
        --rapido)         RAPIDO=true; shift ;;
        --cores)          CORES_PEDIDOS="$2"; shift 2 ;;
        --solo-iniciar)   SOLO_INICIAR=true; shift ;;
        --conservar-storage) CONSERVAR_STORAGE=true; shift ;;
        --valgrind)       VALGRIND_MODS="$2"; shift 2 ;;
        --accion)         ACCION="$2"; shift 2; ACCION_ARGS=("$@"); break ;;
        *)                uso ;;
    esac
done

SRC="$BASE_REMOTA/src"
# Las pruebas de los checkpoints están en checkpoints/<cp>; las finales, en entregas_finales/.
if [ "$CP" = entregas_finales ]; then
    CP_LOCAL="$PRUEBAS_LOCAL/entregas_finales"
    CP_REMOTO="$PRUEBAS_REMOTO/entregas_finales"
else
    CP_LOCAL="$PRUEBAS_LOCAL/checkpoints/$CP"
    CP_REMOTO="$PRUEBAS_REMOTO/checkpoints/$CP"
fi
ENTRADAS="$RAIZ/deploy/catedra_entradas.conf"
read -r -a HOSTS_CORES <<< "$CORES_HOSTS"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
aviso() { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
falla() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

remoto() {
    local host="$1"
    shift
    ssh -n "${SSH_OPTS[@]}" "$USUARIO@$host" "$@"   # -n: si no, se come el stdin de los loops que lo llaman
}

[ -d "$CP_LOCAL" ] || falla "No existe $CP_LOCAL (¿está clonado entrenados-pruebas en $PRUEBAS_LOCAL?)"

# --- configs ---

valor() { { grep -E "^$2=" "$1" || true; } | head -1 | cut -d= -f2-; }

# Pisa CLAVE=VALOR en un config.
fijar() { sed -i "s|^$2=.*|$2=$3|" "$1"; }

# Rutas "./algo" -> "<clon remoto>/checkpoints/<cp>/algo".
absolutizar() {
    local archivo="$1" clave valor_actual
    for clave in PATH_INSTRUCCIONES PATH_OFFLOAD PATH_DATOS PATH_REPORTES PATH_STORAGE; do
        valor_actual=$(valor "$archivo" "$clave")
        case "$valor_actual" in
            ./*) fijar "$archivo" "$clave" "$CP_REMOTO/${valor_actual#./}" ;;
        esac
    done
}

# Directorios de salida que tiene que haber antes de arrancar (los que apuntan a runtime/).
directorios_runtime() {
    local archivo clave valor_actual
    for archivo in "$@"; do
        for clave in PATH_OFFLOAD PATH_REPORTES; do
            valor_actual=$(valor "$archivo" "$clave")
            [ -n "$valor_actual" ] && dirname "$valor_actual"
        done
        for clave in PATH_STORAGE PATH_DATOS; do
            valor_actual=$(valor "$archivo" "$clave")
            case "$valor_actual" in */runtime/*) echo "${valor_actual%/}" ;; esac
        done
    done | sort -u
}

# --- tmux ---

# La sesión arranca un shell, engancha la salida a salida.txt y recién ahí hace exec del módulo,
# así no se pierde nada y el módulo conserva una terminal (readline, Labeler).
# preparar compila en cada servidor solo lo que le toca en su reparto: con otro reparto
# puede faltar el binario de un módulo, y se compila en el momento.
asegurar_binario() {
    local host="$1" modulo="$2"
    remoto "$host" "test -x '$SRC/$modulo/bin/$modulo' || { echo '    compilando $modulo en $host'; make -s -C '$SRC/$modulo' >/dev/null 2>&1; }
        test -x '$SRC/$modulo/bin/$modulo'" || falla "No se pudo compilar $modulo en $host"
}

lanzar() {
    local host="$1" sesion="$2" dir="$3" comando="$4"

    local modulo="${sesion#tp-}"
    asegurar_binario "$host" "${modulo%%-*}"   # tp-core-2 -> core

    if [[ " $VALGRIND_MODS " == *" ${modulo%%-*} "* ]]; then
        comando="valgrind --leak-check=full --show-leak-kinds=definite,indirect --log-file=valgrind.%p.txt $comando"
    fi

    remoto "$host" "tmux kill-session -t '$sesion' 2>/dev/null || true
        mkdir -p '$dir'
        tmux new-session -d -s '$sesion' -c '$dir' -x 200 -y 50
        tmux pipe-pane -o -t '$sesion' 'cat >> $dir/salida.txt'
        tmux send-keys -t '$sesion' 'exec $comando' Enter"
}

esperar_puerto() {
    local host="$1" puerto="$2" nombre="$3"

    remoto "$host" "for i in \$(seq 1 50); do ss -ltn | grep -q ':$puerto ' && exit 0; sleep 0.2; done; exit 1" ||
        falla "$nombre no abrió el puerto $puerto en $host"
}

detener_todo() {
    local host
    for host in $(echo "$PLACA $STORAGE $PLANIFICADOR $CORES_HOSTS" | tr ' ' '\n' | sort -u); do
        remoto "$host" "for s in \$(tmux ls -F '#S' 2>/dev/null | grep '^tp-'); do tmux send-keys -t \"\$s\" C-c; done
            for i in \$(seq 1 600); do tmux ls -F '#S' 2>/dev/null | grep -q '^tp-' || break; sleep 0.1; done
            for s in \$(tmux ls -F '#S' 2>/dev/null | grep '^tp-'); do tmux kill-session -t \"\$s\"; done" || true
    done
}

escribir_en() {
    local host="$1" sesion="$2" texto="$3"
    remoto "$host" "tmux send-keys -t '$sesion' -l '$texto' && tmux send-keys -t '$sesion' Enter"
}

# --- un escenario ---

# Un escenario es una carpeta con configs/, o "<prueba>/<variante>" con configs/<variante>/
# (entregas_finales): ahí los core-N.config se comparten desde configs/.
resolver_escenario() {
    local esc="$1"
    ESC_DIR="$CP_LOCAL/escenarios/$esc"
    CONFIG_DIR="$ESC_DIR/configs"
    VARIANTE=""
    if [ ! -d "$CONFIG_DIR" ] && [ -d "$CP_LOCAL/escenarios/$(dirname "$esc")/configs/$(basename "$esc")" ]; then
        VARIANTE="$(basename "$esc")"
        ESC_DIR="$CP_LOCAL/escenarios/$(dirname "$esc")"
        CONFIG_DIR="$ESC_DIR/configs/$VARIANTE"
    fi
    [ -d "$CONFIG_DIR" ] || falla "No existe el escenario $CP/$esc"
}

# El Job inicial, tal como lo pasa el README al Planificador (con o sin comillas).
job_del_readme() {
    local readme="$1" config="$2"
    grep -oE "${config}\" \"?[^\" ]+" "$readme" | head -1 | sed -E 's/.*" "?//'
}

correr_escenario() {
    local esc="$1"
    resolver_escenario "$esc"
    local esc_local="$ESC_DIR"
    local run="$BASE_REMOTA/catedra/$CP/$esc"
    local tmp
    tmp=$(mktemp -d)

    JOBS_MAPA=""   # lo completa correr_con_jobs; los escenarios de consola no tienen Jobs

    printf '\n\033[1;35m### %s / %s\033[0m\n' "$CP" "$esc"

    detener_todo

    # Configs: IPs de los servidores y rutas absolutas.
    local cfg
    for cfg in "$CONFIG_DIR"/*.config; do
        cp "$cfg" "$tmp/"
    done
    if [ -n "$VARIANTE" ]; then
        for cfg in "$ESC_DIR"/configs/core-*.config; do
            [ -f "$cfg" ] && cp "$cfg" "$tmp/"
        done
    fi
    for cfg in "$tmp"/*.config; do
        absolutizar "$cfg"
    done
    if $RAPIDO && [ -f "$tmp/placa.config" ]; then
        fijar "$tmp/placa.config" RETARDO_MEMORIA 10
        [ "$(valor "$tmp/planificador.config" ALGORITMO_PLANIFICACION)" = RR ] && fijar "$tmp/planificador.config" RR_QUANTUM 20
        aviso "Modo rápido: RETARDO_MEMORIA=10 y RR_QUANTUM=20 (si es RR)"
    fi
    if [ -f "$tmp/planificador.config" ]; then
        fijar "$tmp/planificador.config" IP_PLACA "$PLACA"
        fijar "$tmp/planificador.config" IP_STORAGE "$STORAGE"
    fi
    for cfg in "$tmp"/core-*.config; do
        [ -f "$cfg" ] || continue
        fijar "$cfg" IP_PLANIFICADOR "$PLANIFICADOR"
        fijar "$cfg" IP_PLACA "$PLACA"
    done

    RUNTIME_ESC="$(dirname "$(valor "$tmp/storage.config" PATH_STORAGE)")"

    # Salidas limpias en cada servidor (la evidencia se trae a esta máquina al final).
    # Con --conservar-storage, el volumen y el journal del escenario no se tocan.
    local dirs host storage_dir
    storage_dir="$(valor "$tmp/storage.config" PATH_STORAGE)"
    dirs=$(directorios_runtime "$tmp"/*.config | tr '\n' ' ')
    for host in $(echo "$PLACA $STORAGE $PLANIFICADOR $CORES_HOSTS" | tr ' ' '\n' | sort -u); do
        remoto "$host" "rm -rf '$run' && mkdir -p '$run'; for d in $dirs; do
            if $CONSERVAR_STORAGE && [ \"\$d\" = '${storage_dir%/}' ]; then mkdir -p \"\$d\"; continue; fi
            rm -rf \"\$d\"; mkdir -p \"\$d\"; done"
    done

    subir() { rsync -a -e "ssh ${SSH_OPTS[*]}" "$2" "$USUARIO@$1:$3"; }

    remoto "$STORAGE" "mkdir -p '$run/storage'"
    subir "$STORAGE" "$tmp/storage.config" "$run/storage/storage.config"

    local puerto_storage
    puerto_storage=$(valor "$tmp/storage.config" PUERTO_ESCUCHA)

    if [ ! -f "$tmp/planificador.config" ]; then
        correr_consola_storage "$esc" "$esc_local" "$run" "$puerto_storage"
    else
        correr_con_jobs "$esc" "$esc_local" "$run" "$tmp" "$puerto_storage"
    fi

    if $SOLO_INICIAR; then
        remoto "$PLANIFICADOR" "printf '%s' '$JOBS_MAPA' > '$run/jobs.txt'" || true
        rm -rf "$tmp"
        return
    fi

    detener_todo
    traer_resultados "$esc" "$run"
    rm -rf "$tmp"
}

contar_reemplazos() {
    remoto "$PLACA" "grep -c 'Reemplazo' '$1/placa/placa.log' 2>/dev/null || true"
}

correr_con_jobs() {
    local esc="$1" esc_local="$2" run="$3" tmp="$4" puerto_storage="$5"

    # Job inicial: el que pasa el README al Planificador ("$PWD" es la carpeta del checkpoint).
    local job
    if [ -n "$JOB_ACTUAL" ]; then
        job="$CP_REMOTO/scripts/$JOB_ACTUAL"
    else
        local referencia="configs/planificador.config"
        [ -n "$VARIANTE" ] && referencia="configs/$VARIANTE/planificador.config"
        job=$(job_del_readme "$esc_local/README.md" "$referencia")
        [ -n "$job" ] || falla "No encontré el Job inicial en el README de $esc"
        job="${job//\$PWD/$CP_REMOTO}"
    fi

    remoto "$PLACA" "mkdir -p '$run/placa'"
    subir "$PLACA" "$tmp/placa.config" "$run/placa/placa.config"
    remoto "$PLANIFICADOR" "mkdir -p '$run/planificador'"
    subir "$PLANIFICADOR" "$tmp/planificador.config" "$run/planificador/planificador.config"

    local cores=() cfg id host
    for cfg in "$tmp"/core-*.config; do
        [ -f "$cfg" ] || continue
        id=$(basename "$cfg" .config)
        id=${id#core-}
        host=${HOSTS_CORES[$(( (id - 1) % ${#HOSTS_CORES[@]} ))]}
        remoto "$host" "mkdir -p '$run/core-$id'"
        subir "$host" "$cfg" "$run/core-$id/core.config"
        if [ -z "$CORES_PEDIDOS" ] || [[ " $CORES_PEDIDOS " == *" $id "* ]]; then
            cores+=("$id@$host")
        fi
    done

    log "Storage $STORAGE · Placa $PLACA · Planificador $PLANIFICADOR · Cores ${cores[*]} · Job inicial $(basename "$job")"

    lanzar "$STORAGE" tp-storage "$run/storage" "$SRC/storage/bin/storage storage.config"
    lanzar "$PLACA" tp-placa "$run/placa" "$SRC/placa/bin/placa placa.config"
    esperar_puerto "$STORAGE" "$puerto_storage" storage
    esperar_puerto "$PLACA" "$(valor "$tmp/placa.config" PUERTO_ESCUCHA)" placa

    lanzar "$PLANIFICADOR" tp-planificador "$run/planificador" "$SRC/planificador/bin/planificador planificador.config '$job'"
    esperar_puerto "$PLANIFICADOR" "$(valor "$tmp/planificador.config" PUERTO_ESCUCHA)" planificador

    local core
    for core in "${cores[@]}"; do
        lanzar "${core#*@}" "tp-core-${core%@*}" "$run/core-${core%@*}" "$SRC/core/bin/core core.config ${core%@*}"
    done

    # JID -> script: el 0 es el inicial y los demás salen en el orden de sus INIT_JOB.
    local scripts=()
    scripts+=("$(basename "$job")")
    local script_inicial="$CP_LOCAL/scripts/${job#"$CP_REMOTO"/scripts/}"
    if [ -f "$script_inicial" ]; then
        while read -r _ hijo; do
            scripts+=("$(basename "$hijo")")
        done < <(grep -E '^INIT_JOB ' "$script_inicial")
    fi
    JOBS_MAPA=""
    local i
    for i in "${!scripts[@]}"; do
        JOBS_MAPA+="$i ${scripts[$i]}"$'\n'
    done

    if $SOLO_INICIAR; then
        log "Iniciado: el escenario sigue corriendo (usar --accion para seguir)"
        return
    fi

    log "Esperando a que terminen los Jobs (máximo ${TIEMPO_ESCENARIO}s)"

    declare -A respondido=() visto=() reemplazos_base=() loader_base=() texto_de=()
    local respuestas_dadas=0
    local inicio=$SECONDS contenido creados finalizados linea jid cantidad script texto espera
    while [ $((SECONDS - inicio)) -lt "$TIEMPO_ESCENARIO" ]; do
        contenido=$(remoto "$PLANIFICADOR" "cat '$run/planificador/planificador.log' 2>/dev/null" || true)
        creados=$(grep -c "Se crea el Job" <<< "$contenido" || true)
        finalizados=$(grep -c "finalizó su ejecución" <<< "$contenido" || true)

        # Labeler: se responde según el script del Job, después de la espera configurada.
        while read -r linea; do
            [ -n "$linea" ] || continue
            jid=$(sed -E 's/.*## \(([0-9]+)\) - Ingrese ([0-9]+) caracteres.*/\1/' <<< "$linea")
            cantidad=$(sed -E 's/.*## \(([0-9]+)\) - Ingrese ([0-9]+) caracteres.*/\2/' <<< "$linea")
            [ -n "${respondido[$jid]:-}" ] && continue

            script="${scripts[$jid]:-?}"
            texto="" espera=""
            if [ -n "${texto_de[$jid]:-}" ]; then
                read -r texto espera <<< "${texto_de[$jid]}"
            else
                # read devuelve 1 si no hay línea: sin el || true, set -e corta el script
                read -r texto espera < <(awk -v c="$CP" -v e="$esc" -v s="$script" '$1==c && $2==e && $3==s {print $4, $5}' "$ENTRADAS") || true
                if [ -z "${texto:-}" ]; then
                    # "*": textos que se responden en orden, a medida que el Labeler los pide
                    local secuencia
                    read -r secuencia espera < <(awk -v c="$CP" -v e="$esc" '$1==c && $2==e && $3=="*" {print $4, $5}' "$ENTRADAS") || true
                    if [ -n "${secuencia:-}" ]; then
                        IFS=',' read -r -a lista <<< "$secuencia"
                        texto="${lista[$respuestas_dadas]:-}"
                    fi
                fi
                [ -n "${texto:-}" ] && texto_de[$jid]="$texto ${espera:-0}"
            fi
            if [ -z "${texto:-}" ]; then
                texto=$(printf 'X%.0s' $(seq 1 "$cantidad"))
                espera=0
                aviso "LABEL del Job $jid ($script) sin respuesta configurada: se responde $texto"
            fi

            # La espera es en segundos, "R<n>": hasta que la Placa haga n reemplazos más,
            # o "L<n>": hasta que el Loader empiece a atender n peticiones más.
            if [ -z "${visto[$jid]:-}" ]; then
                visto[$jid]=$SECONDS
                loader_base[$jid]=$(grep -c "inicia Loader" <<< "$contenido" || true)
                if [[ "${espera:-0}" == L* ]]; then
                    log "Labeler pide $cantidad caracteres al Job $jid ($script): responde \"$texto\" cuando el Loader atienda a ${espera#L} Job(s) más"
                elif [[ "${espera:-0}" == R* ]]; then
                    reemplazos_base[$jid]=$(contar_reemplazos "$run")
                    log "Labeler pide $cantidad caracteres al Job $jid ($script): responde \"$texto\" después de ${espera#R} reemplazos"
                else
                    log "Labeler pide $cantidad caracteres al Job $jid ($script): responde \"$texto\" en ${espera:-0}s"
                fi
            fi

            local listo=false
            if [[ "${espera:-0}" == L* ]]; then
                # "esperar a que el Loader atienda a otro Job": vale si arrancó otra petición
                # desde el pedido, o si en este momento está atendiendo una (inicia > finalizó).
                # Si en 20 s no pasa ninguna de las dos, ya no quedan pedidos al Loader.
                local iniciados terminados
                iniciados=$(grep -c "inicia Loader" <<< "$contenido" || true)
                terminados=$(grep -c "finalizó Loader" <<< "$contenido" || true)
                if [ $((iniciados - ${loader_base[$jid]})) -ge "${espera#L}" ] || [ "$iniciados" -gt "$terminados" ] ||
                   [ $((SECONDS - ${visto[$jid]})) -ge 20 ]; then
                    listo=true
                fi
            elif [[ "${espera:-0}" == R* ]]; then
                [ $(( $(contar_reemplazos "$run") - ${reemplazos_base[$jid]} )) -ge "${espera#R}" ] && listo=true
            elif [ $((SECONDS - ${visto[$jid]})) -ge "${espera:-0}" ]; then
                listo=true
            fi

            if $listo; then
                log "Responde \"$texto\" al Job $jid después de $((SECONDS - ${visto[$jid]}))s"
                escribir_en "$PLANIFICADOR" tp-planificador "$texto"
                respondido[$jid]=1
                respuestas_dadas=$((respuestas_dadas + 1))
            fi
        done < <(grep -E "## \([0-9]+\) - Ingrese [0-9]+ caracteres" <<< "$contenido" || true)

        if [ "$creados" -gt 0 ] && [ "$finalizados" -ge "$creados" ]; then
            log "Terminaron $finalizados de $creados Job(s) en $((SECONDS - inicio))s"
            sleep 1
            return
        fi
        sleep 1
    done

    aviso "Timeout: terminaron ${finalizados:-0} de ${creados:-0} Job(s)"
}

correr_consola_storage() {
    local esc="$1" esc_local="$2" run="$3" puerto="$4"

    # La secuencia de comandos es el primer bloque de código de la sección "Secuencia".
    local comandos
    comandos=$(awk '/^## Secuencia/{s=1} s && /^```/{if (b) exit; b=1; next} b' "$esc_local/README.md")
    [ -n "$comandos" ] || falla "No encontré la secuencia de comandos en el README de $esc"

    log "Solo Storage en $STORAGE: $(wc -l <<< "$comandos") comandos por consola"
    lanzar "$STORAGE" tp-storage "$run/storage" "$SRC/storage/bin/storage storage.config"
    esperar_puerto "$STORAGE" "$puerto" storage

    local comando
    while read -r comando; do
        [ -n "$comando" ] || continue
        escribir_en "$STORAGE" tp-storage "$comando"
        sleep 1.5
    done <<< "$comandos"

    # Reinicio normal con la misma config: el volumen tiene que conservarse.
    local reinicio
    reinicio=$(awk -v c="$CP" -v e="$esc" '$1==c && $2==e && $3=="REINICIO" { $1=$2=$3=""; sub(/^ +/, ""); print }' "$ENTRADAS")
    if [ -n "$reinicio" ]; then
        log "Reinicio del Storage y comandos posteriores: $reinicio"
        remoto "$STORAGE" "tmux send-keys -t tp-storage C-c; sleep 1; echo '--- REINICIO ---' >> '$run/storage/salida.txt'"
        lanzar "$STORAGE" tp-storage "$run/storage" "$SRC/storage/bin/storage storage.config"
        esperar_puerto "$STORAGE" "$puerto" storage
        while read -r comando; do
            [ -n "$comando" ] || continue
            escribir_en "$STORAGE" tp-storage "$comando"
            sleep 1.5
        done < <(tr ';' '\n' <<< "$reinicio" | sed 's/^ *//')
    fi
}

traer_resultados() {
    local esc="$1" run="$2" host destino
    local sufijo=""
    [ -n "$JOB_ACTUAL" ] && sufijo="-$(basename "$JOB_ACTUAL" .asm)"
    destino="$RAIZ/deploy/resultados/catedra-$CP-${esc//\//-}$sufijo-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$destino/runtime"
    [ -n "${JOBS_MAPA:-}" ] && printf '%s' "$JOBS_MAPA" > "$destino/jobs.txt"

    for host in $(echo "$PLACA $STORAGE $PLANIFICADOR $CORES_HOSTS" | tr ' ' '\n' | sort -u); do
        rsync -a -e "ssh ${SSH_OPTS[*]}" "$USUARIO@$host:$run/" "$destino/" 2>/dev/null || true
    done
    # reportes.log, volumen y journal del escenario (están donde lo dicen sus configs).
    local runtime_dir="${RUNTIME_ESC:-$CP_REMOTO/runtime/$(basename "$esc")}"
    for host in $(echo "$PLANIFICADOR $STORAGE" | tr ' ' '\n' | sort -u); do
        rsync -a -e "ssh ${SSH_OPTS[*]}" --exclude 'offload.dat' "$USUARIO@$host:$runtime_dir/" "$destino/runtime/" 2>/dev/null || true
    done

    log "Resultados en ${destino#"$RAIZ"/}"
    local archivo
    for archivo in "$destino"/*/*.log; do
        [ -f "$archivo" ] || continue
        printf '    %-34s errores=%s warnings=%s\n' "${archivo#"$destino"/}" \
            "$(grep -c '\[ERROR\]' "$archivo" || true)" "$(grep -c '\[WARNING\]' "$archivo" || true)"
    done
    grep -h "finalizó su ejecución" "$destino"/planificador/planificador.log 2>/dev/null |
        sed -E 's/^\[[A-Z]+\] [0-9:]+ [^ ]+ /    /; s/\. Estadísticas:.*//' || true
    [ -f "$destino/runtime/reportes.log" ] && sed 's/^/    reporte: /' "$destino/runtime/reportes.log"
    RESULTADOS="$destino"

    if [ -f "$destino/jobs.txt" ]; then
        if [ "$CP" != entregas_finales ]; then
            python3 -I "$RAIZ/deploy/verificar_catedra.py" "$destino" "$CP_LOCAL" "$(basename "$esc")" || VERIFICACIONES_FALLIDAS=$((VERIFICACIONES_FALLIDAS + 1))
        fi
    fi
    true
}

# --- acciones sobre un escenario ya iniciado ---

datos_de() {
    local modulo="$1" run="$2"
    case "$modulo" in
        storage)      M_HOST=$STORAGE;      M_DIR=$run/storage;      M_LOG=storage.log
                      M_CMD="$SRC/storage/bin/storage storage.config"; M_CFG=storage.config ;;
        placa)        M_HOST=$PLACA;        M_DIR=$run/placa;        M_LOG=placa.log
                      M_CMD="$SRC/placa/bin/placa placa.config"; M_CFG=placa.config ;;
        planificador) M_HOST=$PLANIFICADOR; M_DIR=$run/planificador; M_LOG=planificador.log
                      M_CMD="$SRC/planificador/bin/planificador planificador.config"; M_CFG=planificador.config ;;
        core-*)       local id="${modulo#core-}"
                      M_HOST=${HOSTS_CORES[$(( (id - 1) % ${#HOSTS_CORES[@]} ))]}
                      M_DIR=$run/core-$id; M_LOG=core_$id.log
                      M_CMD="$SRC/core/bin/core core.config $id"; M_CFG=core.config ;;
        *) falla "Módulo desconocido: $modulo" ;;
    esac
    M_SESION="tp-$modulo"
}

accion() {
    local que="$1"
    shift
    local esc="$ESCENARIO_PEDIDO"
    local run="$BASE_REMOTA/catedra/$CP/$esc"
    resolver_escenario "$esc"
    RUNTIME_ESC="$(dirname "$(valor "$CONFIG_DIR/storage.config" PATH_STORAGE)")"
    RUNTIME_ESC="${RUNTIME_ESC/#./$CP_REMOTO}"

    case "$que" in
        esperar-log)
            datos_de "$1" "$run"
            local texto="$2" segundos="${3:-60}"
            remoto "$M_HOST" "for i in \$(seq 1 $((segundos * 10))); do grep -qF -- '$texto' '$M_DIR/$M_LOG' 2>/dev/null && exit 0; sleep 0.1; done; exit 1" ||
                falla "No apareció \"$texto\" en el log de $1 en ${segundos}s"
            log "$1: apareció \"$texto\"" ;;
        parar)
            # Finalización normal (Ctrl-C), no kill -9.
            datos_de "$1" "$run"
            # La sesión se cierra cuando termina el proceso (lanzar hace exec): bajo valgrind tarda más.
            remoto "$M_HOST" "tmux send-keys -t '$M_SESION' C-c 2>/dev/null
                for i in \$(seq 1 600); do tmux has-session -t '$M_SESION' 2>/dev/null || exit 0; sleep 0.1; done; exit 1" ||
                aviso "$1 no terminó con Ctrl-C"
            log "$1 en $M_HOST: finalizado (Ctrl-C)" ;;
        cortar-durante)
            # Finaliza el módulo apenas la última línea de su log coincide con el patrón (ERE).
            # Se vigila en el mismo servidor para no perder la ventana por la latencia de ssh.
            datos_de "$1" "$run"
            local patron="$2" segundos="${3:-300}"
            remoto "$M_HOST" "fin=\$((SECONDS + $segundos)); while [ \$SECONDS -lt \$fin ]; do
                    if tail -n 1 '$M_DIR/$M_LOG' 2>/dev/null | grep -qE -- '$patron'; then
                        tail -n 1 '$M_DIR/$M_LOG'; tmux send-keys -t '$M_SESION' C-c; exit 0
                    fi; sleep 0.01; done; exit 1" | sed 's/^/    última línea: /' ||
                falla "$1 no mostró \"$patron\" en ${segundos}s"
            log "$1 en $M_HOST: finalizado mientras ejecutaba lo indicado" ;;
        matar)
            datos_de "$1" "$run"
            remoto "$M_HOST" "pkill -9 -f '^$M_CMD' >/dev/null || echo '    ($1 no estaba corriendo)'"
            log "$1 en $M_HOST: kill -9" ;;
        levantar)
            datos_de "$1" "$run"
            local comando="$M_CMD"
            [ "$1" = planificador ] && comando="$M_CMD '$CP_REMOTO/scripts/${2:?Falta el script del Planificador}'"
            lanzar "$M_HOST" "$M_SESION" "$M_DIR" "$comando"
            local puerto
            puerto=$(remoto "$M_HOST" "grep -E '^PUERTO_ESCUCHA=' '$M_DIR/$M_CFG' | cut -d= -f2" || true)
            [ -n "$puerto" ] && esperar_puerto "$M_HOST" "$puerto" "$1"
            log "$1 levantado en $M_HOST${2:+ con $2}" ;;
        consola)
            datos_de "$1" "$run"
            escribir_en "$M_HOST" "$M_SESION" "$2"
            sleep "${3:-2}"
            log "$1: consola <- $2" ;;
        esperar-fin)
            local segundos="${1:-$TIMEOUT}" inicio=$SECONDS contenido creados finalizados
            while [ $((SECONDS - inicio)) -lt "$segundos" ]; do
                contenido=$(remoto "$PLANIFICADOR" "cat '$run/planificador/planificador.log' 2>/dev/null" || true)
                creados=$(grep -c "Se crea el Job" <<< "$contenido" || true)
                finalizados=$(grep -c "finalizó su ejecución" <<< "$contenido" || true)
                if [ "$creados" -gt 0 ] && [ "$finalizados" -ge "$creados" ]; then
                    log "Terminaron $finalizados de $creados Job(s)"
                    return 0
                fi
                sleep 1
            done
            aviso "Timeout: terminaron ${finalizados:-0} de ${creados:-0} Job(s)"
            return 1 ;;
        cpu)
            # utime + stime de /proc/<pid>/stat antes y después: % de un núcleo en el intervalo.
            local segundos="${1:-20}" host
            log "CPU de cada proceso del TP durante ${segundos}s (100 % = un núcleo entero):"
            for host in $(echo "$PLACA $STORAGE $PLANIFICADOR $CORES_HOSTS" | tr ' ' '\n' | sort -u); do
                remoto "$host" "tick=\$(getconf CLK_TCK)
                    tiempo() { awk '{print \$14 + \$15}' \"/proc/\$1/stat\" 2>/dev/null; }
                    declare -A antes
                    pids=\$(pgrep -f '$SRC/[a-z]*/bin/[a-z]* ' || true)
                    for p in \$pids; do antes[\$p]=\$(tiempo \$p); done
                    sleep $segundos
                    for p in \$pids; do
                        despues=\$(tiempo \$p); [ -n \"\$despues\" ] || continue
                        nombre=\$(tr '\\0' ' ' < /proc/\$p/cmdline | grep -oE 'bin/[a-z]+ [^ ]+( [0-9]+)?' | sed 's|bin/||')
                        printf '    %-14s %-28s %5.1f %%\\n' '$host' \"\$nombre\" \$(echo \"(\$despues - \${antes[\$p]}) * 100 / (\$tick * $segundos)\" | bc -l)
                    done" || true
            done ;;
        detener)
            detener_todo
            log "Módulos detenidos" ;;
        limpiar-storage)
            remoto "$STORAGE" "rm -rf '$RUNTIME_ESC/storage' && mkdir -p '$RUNTIME_ESC/storage'"
            log "Volumen y journal borrados ($RUNTIME_ESC/storage)" ;;
        resultados)
            JOBS_MAPA=$(remoto "$PLANIFICADOR" "cat '$run/jobs.txt' 2>/dev/null" || true)
            traer_resultados "$esc${1:+-$1}" "$run" ;;
        *) falla "Acción desconocida: $que" ;;
    esac
}

# --- main ---

TIEMPO_ESCENARIO="$TIMEOUT"
JOB_ACTUAL="$JOB_PEDIDO"
JOBS_MAPA=""
VERIFICACIONES_FALLIDAS=0

# En CP2/01 la prueba es correr cada script individual por separado.
correr() {
    local esc="$1"
    if [ "$CP" = checkpoint_2 ] && [ "$esc" = 01_instrucciones ] && [ -z "$JOB_PEDIDO" ]; then
        local script
        for script in "$CP_LOCAL"/scripts/individuales/*.asm; do
            JOB_ACTUAL="individuales/$(basename "$script")"
            correr_escenario "$esc"
        done
        JOB_ACTUAL=""
    else
        correr_escenario "$esc"
    fi
}

case "$PREPARAR" in
    remoto) "$RAIZ/deploy/desplegar.sh" "$RAIZ/deploy/pruebas/mini_entrenamiento" preparar ;;
    local)  "$RAIZ/deploy/desplegar.sh" "$RAIZ/deploy/pruebas/mini_entrenamiento" preparar --local ;;
esac

if [ -n "$ACCION" ]; then
    accion "$ACCION" "${ACCION_ARGS[@]}"
    exit $?
fi

if [ "$ESCENARIO_PEDIDO" = todos ]; then
    for dir in $(find "$CP_LOCAL/escenarios" -name configs -type d | sort); do
        esc="${dir%/configs}"
        variantes=$(find "$dir" -mindepth 2 -maxdepth 2 -name storage.config -printf '%h\n' | sort)
        if [ -n "$variantes" ]; then
            for v in $variantes; do correr "${esc#"$CP_LOCAL"/escenarios/}/$(basename "$v")"; done
        else
            correr "${esc#"$CP_LOCAL"/escenarios/}"
        fi
    done
else
    correr "$ESCENARIO_PEDIDO"
fi

if [ "$VERIFICACIONES_FALLIDAS" -gt 0 ]; then
    printf '\n\033[1;31m%s corrida(s) no coinciden con los resultados esperados\033[0m\n' "$VERIFICACIONES_FALLIDAS"
    exit 1
fi
