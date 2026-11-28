#!/usr/bin/env bash
# Despliegue distribuido del TP EntrenadOS.
#
# Uso: deploy/desplegar.sh <carpeta de prueba> <acción> [opciones]
#
# Acciones:
#   preparar [--local]   Lleva el código a cada servidor de la prueba y compila lo que corre ahí.
#                        Sin --local: git fetch + checkout de $REF (por defecto origin/develop).
#                        Con --local: copia este checkout con rsync (sirve para cambios sin pushear).
#   iniciar              Genera los configs, copia scripts y datos y levanta los módulos en orden:
#                        Placa y Storage -> Planificador -> Cores.
#   estado               Muestra qué sesiones del TP están corriendo en cada servidor.
#   detener              Corta todos los módulos de la prueba.
#   logs                 Trae logs, configs y reportes a deploy/resultados/<prueba>-<fecha>/.
#   ejecutar             iniciar + esperar a que terminen los Jobs + detener + logs.
#   matar <módulo>       kill -9 del módulo (placa, storage, planificador, core-<id>).
#   levantar <módulo>    Lo vuelve a arrancar con su config y sus datos (no borra nada).
#   esperar <módulo> <texto> [segundos]
#                        Espera a que <texto> aparezca en el log del módulo (por defecto 30s).
#
# Opciones de iniciar y ejecutar:
#   --job <script>         Script inicial distinto del JOB_INICIAL de prueba.conf.
#   --conservar-storage    No borra el volumen ni el journal del Storage (para cargar lo que
#                          guardó una corrida anterior).
#
# Cada módulo corre en una sesión de tmux (tp-placa, tp-storage, tp-planificador, tp-core-<id>).
# Para el Labeler o la consola del Storage:  ssh -t utnso@<ip> tmux attach -t tp-planificador
#
# La prueba es una carpeta con:
#   prueba.conf   dónde corre cada módulo y qué claves de config se pisan (ver pruebas/mini_entrenamiento)
#   scripts/      pseudocódigo de los Jobs (va a PATH_INSTRUCCIONES de la Placa)
#   datos/        archivos para el Loader (van a PATH_DATOS del Planificador)

set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8)

uso() {
    # El encabezado de comentarios, hasta la primera línea que no lo es.
    awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"
    exit 1
}

[ $# -ge 2 ] || uso

PRUEBA_DIR="$(cd "$1" && pwd)"
ACCION="$2"
shift 2

PRUEBA="$(basename "$PRUEBA_DIR")"

# Valores por defecto de la prueba (prueba.conf los pisa).
PLACA="" STORAGE="" PLANIFICADOR="" CORES=""
JOB_INICIAL=""
CONFIG_PLACA="" CONFIG_STORAGE="" CONFIG_PLANIFICADOR="" CONFIG_CORE=""
JOBS_ESPERADOS=1
TIEMPO_MAXIMO=120

# shellcheck source=servidores.conf
source "$RAIZ/deploy/servidores.conf"
# shellcheck disable=SC1091
source "$PRUEBA_DIR/prueba.conf"

[ -n "$PLACA" ] && [ -n "$STORAGE" ] && [ -n "$PLANIFICADOR" ] && [ -n "$CORES" ] && [ -n "$JOB_INICIAL" ] || {
    echo "prueba.conf tiene que definir PLACA, STORAGE, PLANIFICADOR, CORES y JOB_INICIAL" >&2
    exit 1
}

RUN="$BASE_REMOTA/$PRUEBA"
SRC="$BASE_REMOTA/src"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
falla() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

remoto() {
    local host="$1"
    shift
    ssh "${SSH_OPTS[@]}" "$USUARIO@$host" "$@"
}

# Puertos que escucha cada módulo, según los configs base (o lo que pise la prueba).
valor_config() {
    local archivo="$1" clave="$2" overrides="$3"
    local par

    for par in $overrides; do
        if [ "${par%%=*}" = "$clave" ]; then
            echo "${par#*=}"
            return
        fi
    done

    grep -E "^$clave=" "$archivo" | head -1 | cut -d= -f2-
}

PUERTO_PLACA=$(valor_config "$RAIZ/placa/placa.config" PUERTO_ESCUCHA "$CONFIG_PLACA")
PUERTO_STORAGE=$(valor_config "$RAIZ/storage/storage.config" PUERTO_ESCUCHA "$CONFIG_STORAGE")
PUERTO_PLANIFICADOR=$(valor_config "$RAIZ/planificador/planificador.config" PUERTO_ESCUCHA "$CONFIG_PLANIFICADOR")

# "id@ip" -> ip
host_de_core() { echo "${1#*@}"; }
id_de_core() { echo "${1%@*}"; }

# Servidores distintos de la prueba y qué módulos corre cada uno.
declare -A MODULOS_DE
agregar_modulo() { MODULOS_DE[$1]="${MODULOS_DE[$1]:-} $2"; }
agregar_modulo "$PLACA" placa
agregar_modulo "$STORAGE" storage
agregar_modulo "$PLANIFICADOR" planificador
for core in $CORES; do
    agregar_modulo "$(host_de_core "$core")" core
done
HOSTS="${!MODULOS_DE[*]}"

# --- preparar ---

preparar() {
    local local_=false
    [ "${1:-}" = "--local" ] && local_=true

    for host in $HOSTS; do
        local modulos
        modulos=$(echo "${MODULOS_DE[$host]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')

        if $local_; then
            log "$host: copiando este checkout ($(git -C "$RAIZ" log -1 --format=%h) + cambios sin commitear)"
            remoto "$host" "mkdir -p '$BASE_REMOTA' && rm -rf '$SRC' && mkdir -p '$SRC'"
            rsync -a --delete -e "ssh ${SSH_OPTS[*]}" \
                --exclude .git --exclude bin/ --exclude obj/ --exclude lib/ --exclude '*.log' --exclude deploy/resultados/ \
                "$RAIZ/" "$USUARIO@$host:$SRC/"
        else
            log "$host: git fetch + checkout de $REF"
            remoto "$host" "set -e
                mkdir -p '$BASE_REMOTA'
                cd '$REPO_REMOTO' && git fetch -q origin
                if [ -e '$SRC/.git' ]; then
                    git -C '$SRC' checkout -q --detach '$REF'
                else
                    rm -rf '$SRC'
                    git worktree prune
                    git worktree add -q --detach '$SRC' '$REF'
                fi
                git -C '$SRC' log -1 --format='    en %h %s'"
        fi

        log "$host: compilando$modulos"
        for modulo in $modulos; do
            remoto "$host" "make -s -C '$SRC/$modulo' 2>&1 | grep -E 'warning:|error' || true; test -x '$SRC/$modulo/bin/$modulo'" ||
                falla "$host: no compiló $modulo"
        done
    done

    log "Listo: código preparado en $(echo "$HOSTS" | wc -w) servidores"
}

# --- configs ---

# Pisa (o agrega) CLAVE=VALOR en un config.
fijar() {
    local archivo="$1" clave="$2" valor="$3"

    if grep -qE "^$clave=" "$archivo"; then
        sed -i "s|^$clave=.*|$clave=$valor|" "$archivo"
    else
        echo "$clave=$valor" >> "$archivo"
    fi
}

generar_config() {
    local base="$1" destino="$2" overrides="$3"
    shift 3

    cp "$base" "$destino"
    # Primero lo que define el despliegue (IPs y rutas), después lo que pide la prueba.
    while [ $# -gt 0 ]; do
        fijar "$destino" "${1%%=*}" "${1#*=}"
        shift
    done

    local par
    for par in $overrides; do
        fijar "$destino" "${par%%=*}" "${par#*=}"
    done
}

subir() {
    local host="$1" origen="$2" destino="$3"
    rsync -a -e "ssh ${SSH_OPTS[*]}" "$origen" "$USUARIO@$host:$destino"
}

# --- iniciar / detener ---

lanzar() {
    local host="$1" sesion="$2" dir="$3"
    shift 3
    local comando="$*"

    remoto "$host" "tmux kill-session -t '$sesion' 2>/dev/null || true
        cd '$dir' && tmux new-session -d -s '$sesion' \"$comando 2>&1 | tee salida.txt\""
}

esperar_puerto() {
    local host="$1" puerto="$2" nombre="$3"

    remoto "$host" "for i in \$(seq 1 50); do ss -ltn | grep -q ':$puerto ' && exit 0; sleep 0.2; done; exit 1" ||
        falla "$nombre no abrió el puerto $puerto en $host (ver: ssh $USUARIO@$host cat $RUN/$nombre/salida.txt)"

    log "$nombre escuchando en $host:$puerto"
}

TMP_CONFIGS=""
trap '[ -n "$TMP_CONFIGS" ] && rm -rf "$TMP_CONFIGS"' EXIT

CONSERVAR_STORAGE=false

leer_opciones() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --job) JOB_INICIAL="$2"; shift 2 ;;
            --conservar-storage) CONSERVAR_STORAGE=true; shift ;;
            *) falla "Opción desconocida: $1" ;;
        esac
    done
}

# Datos de cada módulo: servidor, sesión de tmux, directorio, binario y log.
datos_modulo() {
    local modulo="$1"

    case "$modulo" in
        placa)        M_HOST=$PLACA;        M_SESION=tp-placa;        M_DIR=$RUN/placa;        M_LOG=placa.log
                      M_CMD="$SRC/placa/bin/placa placa.config";                                M_PUERTO=$PUERTO_PLACA
                      M_PATRON="^$SRC/placa/bin/placa " ;;
        storage)      M_HOST=$STORAGE;      M_SESION=tp-storage;      M_DIR=$RUN/storage;      M_LOG=storage.log
                      M_CMD="$SRC/storage/bin/storage storage.config";                          M_PUERTO=$PUERTO_STORAGE
                      M_PATRON="^$SRC/storage/bin/storage " ;;
        planificador) M_HOST=$PLANIFICADOR; M_SESION=tp-planificador; M_DIR=$RUN/planificador; M_LOG=planificador.log
                      M_CMD="$SRC/planificador/bin/planificador planificador.config $JOB_INICIAL"; M_PUERTO=$PUERTO_PLANIFICADOR
                      M_PATRON="^$SRC/planificador/bin/planificador " ;;
        core-*)
            local id="${modulo#core-}" core
            M_HOST=""
            for core in $CORES; do
                [ "$(id_de_core "$core")" = "$id" ] && M_HOST=$(host_de_core "$core")
            done
            [ -n "$M_HOST" ] || falla "No hay un Core con id $id en la prueba"
            M_SESION=tp-core-$id; M_DIR=$RUN/core-$id; M_LOG=core_$id.log
            M_CMD="$SRC/core/bin/core core.config $id"; M_PUERTO=""
            M_PATRON="^$SRC/core/bin/core core.config $id\$" ;;
        *) falla "Módulo desconocido: $modulo (placa, storage, planificador, core-<id>)" ;;
    esac
}

matar() {
    datos_modulo "${1:-}"
    # Solo el binario: la sesión de tmux queda, como si el proceso se hubiera caído.
    remoto "$M_HOST" "pkill -9 -f '$M_PATRON' >/dev/null || echo '    (no estaba corriendo)'"
    log "$1 en $M_HOST: kill -9"
}

levantar() {
    datos_modulo "${1:-}"
    lanzar "$M_HOST" "$M_SESION" "$M_DIR" "$M_CMD"
    [ -n "$M_PUERTO" ] && esperar_puerto "$M_HOST" "$M_PUERTO" "$1"
    log "$1 levantado en $M_HOST"
}

esperar() {
    datos_modulo "${1:-}"
    local texto="${2:?Falta el texto a esperar}" segundos="${3:-30}"

    remoto "$M_HOST" "for i in \$(seq 1 $((segundos * 10))); do grep -qF -- '$texto' '$M_DIR/$M_LOG' 2>/dev/null && exit 0; sleep 0.1; done; exit 1" ||
        falla "No apareció \"$texto\" en el log de $1 en ${segundos}s"

    log "$1: apareció \"$texto\""
}

iniciar() {
    leer_opciones "$@"

    TMP_CONFIGS=$(mktemp -d)
    local tmp="$TMP_CONFIGS"

    detener >/dev/null 2>&1 || true

    log "Generando configs (Placa $PLACA, Storage $STORAGE, Planificador $PLANIFICADOR, Cores: $CORES)"

    generar_config "$RAIZ/placa/placa.config" "$tmp/placa.config" "$CONFIG_PLACA" \
        "PATH_INSTRUCCIONES=$RUN/scripts/" "PATH_OFFLOAD=$RUN/placa/offload.dat"

    generar_config "$RAIZ/storage/storage.config" "$tmp/storage.config" "$CONFIG_STORAGE" \
        "PATH_STORAGE=$RUN/storage/fs/"

    generar_config "$RAIZ/planificador/planificador.config" "$tmp/planificador.config" "$CONFIG_PLANIFICADOR" \
        "IP_PLACA=$PLACA" "PUERTO_PLACA=$PUERTO_PLACA" "IP_STORAGE=$STORAGE" "PUERTO_STORAGE=$PUERTO_STORAGE" \
        "PATH_DATOS=$RUN/datos/" "PATH_REPORTES=$RUN/planificador/reportes.log"

    generar_config "$RAIZ/core/core1.config" "$tmp/core.config" "$CONFIG_CORE" \
        "IP_PLANIFICADOR=$PLANIFICADOR" "PUERTO_PLANIFICADOR=$PUERTO_PLANIFICADOR" \
        "IP_PLACA=$PLACA" "PUERTO_PLACA=$PUERTO_PLACA"

    # Directorios limpios en cada servidor: cada corrida arranca de cero (offload, FS, logs).
    # Con --conservar-storage, el volumen y el journal sobreviven.
    for host in $HOSTS; do
        if $CONSERVAR_STORAGE && [ "$host" = "$STORAGE" ]; then
            remoto "$host" "rm -rf '$BASE_REMOTA/.fs-conservado'
                [ -d '$RUN/storage/fs' ] && mv '$RUN/storage/fs' '$BASE_REMOTA/.fs-conservado'
                rm -rf '$RUN' && mkdir -p '$RUN/storage'
                [ -d '$BASE_REMOTA/.fs-conservado' ] && mv '$BASE_REMOTA/.fs-conservado' '$RUN/storage/fs' || true"
        else
            remoto "$host" "rm -rf '$RUN' && mkdir -p '$RUN'"
        fi
    done
    $CONSERVAR_STORAGE && log "Se conserva el volumen del Storage de la corrida anterior"

    remoto "$PLACA" "mkdir -p '$RUN/placa' '$RUN/scripts'"
    subir "$PLACA" "$tmp/placa.config" "$RUN/placa/placa.config"
    [ -d "$PRUEBA_DIR/scripts" ] && subir "$PLACA" "$PRUEBA_DIR/scripts/" "$RUN/scripts/"

    remoto "$STORAGE" "mkdir -p '$RUN/storage/fs'"
    subir "$STORAGE" "$tmp/storage.config" "$RUN/storage/storage.config"

    remoto "$PLANIFICADOR" "mkdir -p '$RUN/planificador' '$RUN/datos'"
    subir "$PLANIFICADOR" "$tmp/planificador.config" "$RUN/planificador/planificador.config"
    [ -d "$PRUEBA_DIR/datos" ] && subir "$PLANIFICADOR" "$PRUEBA_DIR/datos/" "$RUN/datos/"

    for core in $CORES; do
        local id host
        id=$(id_de_core "$core")
        host=$(host_de_core "$core")
        remoto "$host" "mkdir -p '$RUN/core-$id'"
        subir "$host" "$tmp/core.config" "$RUN/core-$id/core.config"
    done

    log "Levantando Placa y Storage"
    lanzar "$PLACA" tp-placa "$RUN/placa" "$SRC/placa/bin/placa placa.config"
    lanzar "$STORAGE" tp-storage "$RUN/storage" "$SRC/storage/bin/storage storage.config"
    esperar_puerto "$PLACA" "$PUERTO_PLACA" placa
    esperar_puerto "$STORAGE" "$PUERTO_STORAGE" storage

    log "Levantando Planificador (Job inicial: $JOB_INICIAL)"
    lanzar "$PLANIFICADOR" tp-planificador "$RUN/planificador" "$SRC/planificador/bin/planificador planificador.config $JOB_INICIAL"
    esperar_puerto "$PLANIFICADOR" "$PUERTO_PLANIFICADOR" planificador

    for core in $CORES; do
        local id host
        id=$(id_de_core "$core")
        host=$(host_de_core "$core")
        log "Levantando Core $id en $host"
        lanzar "$host" "tp-core-$id" "$RUN/core-$id" "$SRC/core/bin/core core.config $id"
    done

    log "Todo arriba. Para el Labeler: ssh -t $USUARIO@$PLANIFICADOR tmux attach -t tp-planificador"
}

detener() {
    for host in $HOSTS; do
        remoto "$host" "for s in \$(tmux ls -F '#S' 2>/dev/null | grep '^tp-'); do tmux send-keys -t \"\$s\" C-c; done
            sleep 0.5
            for s in \$(tmux ls -F '#S' 2>/dev/null | grep '^tp-'); do tmux kill-session -t \"\$s\"; done" || true
        log "$host: detenido"
    done
}

estado() {
    for host in $HOSTS; do
        printf '%s:%s -> ' "$host" "${MODULOS_DE[$host]}"
        remoto "$host" "tmux ls -F '#S' 2>/dev/null | grep '^tp-' | tr '\n' ' ' || true"
        echo
    done
}

# --- logs ---

traer_logs() {
    local destino
    destino="$RAIZ/deploy/resultados/$PRUEBA-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$destino"

    for host in $HOSTS; do
        rsync -a -e "ssh ${SSH_OPTS[*]}" --exclude 'fs/' --exclude 'offload.dat' --exclude 'scripts/' --exclude 'datos/' \
            "$USUARIO@$host:$RUN/" "$destino/" 2>/dev/null || true
    done

    log "Resultados en ${destino#"$RAIZ"/}"
    for log_modulo in "$destino"/*/*.log; do
        [ -f "$log_modulo" ] || continue
        printf '    %-40s errores=%s warnings=%s\n' "${log_modulo#"$destino"/}" \
            "$(grep -c '\[ERROR\]' "$log_modulo" || true)" "$(grep -c '\[WARNING\]' "$log_modulo" || true)"
    done

    RESULTADOS="$destino"
}

ejecutar() {
    iniciar "$@"

    log "Esperando a que terminen $JOBS_ESPERADOS Job(s) (máximo ${TIEMPO_MAXIMO}s)"
    local terminados=0 inicio=$SECONDS
    while [ $((SECONDS - inicio)) -lt "$TIEMPO_MAXIMO" ]; do
        terminados=$(remoto "$PLANIFICADOR" "grep -c 'finalizó su ejecución' '$RUN/planificador/planificador.log' 2>/dev/null || true")
        [ "${terminados:-0}" -ge "$JOBS_ESPERADOS" ] && break
        sleep 1
    done

    if [ "${terminados:-0}" -ge "$JOBS_ESPERADOS" ]; then
        log "Terminaron $terminados Job(s) en $((SECONDS - inicio))s"
    else
        echo "Timeout: terminaron ${terminados:-0} de $JOBS_ESPERADOS Job(s)" >&2
    fi

    sleep 1
    detener
    traer_logs

    # Saca el prefijo "[INFO] hh:mm:ss:ms PLANIFICADOR/(pid:tid): " del logger.
    grep -h "finalizó su ejecución" "$RESULTADOS"/planificador/planificador.log 2>/dev/null |
        sed -E 's/^\[[A-Z]+\] [0-9:]+ [^ ]+ /    /' || true
}

case "$ACCION" in
    preparar) preparar "$@" ;;
    iniciar)  iniciar "$@" ;;
    estado)   estado ;;
    detener)  detener ;;
    logs)     traer_logs ;;
    ejecutar) ejecutar "$@" ;;
    matar)    matar "$@" ;;
    levantar) levantar "$@" ;;
    esperar)  esperar "$@" ;;
    *)        uso ;;
esac
