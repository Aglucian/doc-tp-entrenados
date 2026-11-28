---
tags: [tp-so, entrenados, deploy, pruebas]
actualizado: 2026-11-14
script: deploy/desplegar.sh
commit: 18d367d
---

# Despliegue distribuido

Volver a [[00 - Inicio]] · Ver [[Plan de acción]] · Pruebas: [[Mini Entrenamiento 2026-11-14]]

El enunciado dice que la cantidad de computadoras y la distribución de los procesos "será definida en cada uno de los tests" y que puede cambiar en la evaluación. **Automatizar el despliegue es responsabilidad del grupo.** Para eso está `deploy/desplegar.sh`, en el repo del TP (commit `18d367d`, en `develop` desde el PR #20).

> [!info] Dónde está `deploy/`
> Desde el 28/11, `deploy/` no está en el repo del TP: se movió a este vault, en `Repo TP/deploy/`. Para usar las herramientas de esta nota hay que copiarlo de vuelta dentro del TP (ver [[Uso de deploy]]).

## Entrega: modo manual en cada VM (rama `main`)

> [!important] Así se va a correr en el laboratorio
> Cada módulo se levanta **a mano en su VM**, sin SSH entre máquinas. Las herramientas por SSH de esta nota (`desplegar.sh`, `catedra.sh`) quedan para nuestras pruebas. Práctica completa en [[Laboratorio manual 2026-11-27]].

En cada VM: clonar el TP una sola vez (con el token; queda en `main`), `so-commons-library` (instalada) y `entrenados-pruebas`. Después:
```bash
cd ~/tp-2026-2c-requiemso && ./preparar.sh
```

`preparar.sh`:
1. Pregunta `MÓDULOS :` qué corre en esa VM (uno o varios, o `todos`).
2. Pide `IP PLANIFICADOR :`, `IP PLACA :` e `IP STORAGE :` (solo la IP, sin valor por defecto) y las escribe en las configs del TP.
3. Limpia y recompila esos módulos.
4. Crea accesos en `bin/` para usar los comandos del README de cada prueba (`/ruta/al/tp/bin/...`).

Las configs de `entrenados-pruebas` se editan **a mano**: en el Planificador, `IP_PLACA` e `IP_STORAGE`; en cada Core, `IP_PLANIFICADOR` e `IP_PLACA`.

Reglas que salieron de la práctica:
- **Todo se lanza desde `~/entrenados-pruebas/entregas_finales`**: las rutas de las configs son relativas a esa carpeta.
- **`./runtime/<prueba>/` se crea en cada máquina** que lo use: Placa (Offload), Storage (volumen) y Planificador (reportes).
- **Orden:** Storage y Placa → Planificador → Cores. Los Cores pueden entrar y salir en cualquier momento, cada uno con un **ID distinto**. Para el Core N se usa cualquier `core-K.config` con otro ID.
- Funciona con 1 a 5 máquinas: en una sola, `MÓDULOS : todos` y las tres IPs iguales.

## Servidores de prueba
| IP | Uso habitual | Sistema |
| --- | --- | --- |
| `192.168.1.25` | Placa | Ubuntu 26.04 LTS x86_64 |
| `192.168.1.26` | Storage | ídem |
| `192.168.1.27` | Planificador | ídem |
| `192.168.1.28` | Core 1 | ídem |
| `192.168.1.29` | Core 2 | ídem |

- Usuario `utnso`, con **acceso por clave pública** (la `id_ed25519` de la VM de desarrollo, instalada con `ssh-copy-id`).
- Tienen instalados `gcc`, `make`, `git`, `valgrind`, `readline`, `rsync`, `tmux` y la **so-commons-library** (instalada el 14/11 en `/usr/lib` y `/usr/include`, como en la VM de la cátedra).
- Todos se ven entre sí y tienen salida a GitHub.
- Cada uno tiene un clon del repo en `~/tp-2026-2c-requiemso` con su propia clave de GitHub. El despliegue **no lo modifica**: trabaja en un *worktree* aparte.

> [!warning] Sin sudo
> El usuario `utnso` no tiene `sudo` sin contraseña. Cualquier instalación del sistema la tiene que correr alguien del grupo.

## Estructura en el repo
```
deploy/
├── desplegar.sh                 script principal
├── servidores.conf              usuario, rutas remotas, rama a desplegar (REF)
├── .gitignore                   ignora resultados/
├── resultados/                  logs que se traen de cada corrida (no se commitea)
└── pruebas/<prueba>/
    ├── prueba.conf              dónde corre cada módulo y qué claves de config se pisan
    ├── scripts/                 pseudocódigo de los Jobs → PATH_INSTRUCCIONES de la Placa
    └── datos/                   archivos del Loader → PATH_DATOS del Planificador
```

## En cada servidor
```
~/tp-run/
├── src/                         código desplegado (worktree de REF, o copia con --local)
└── <prueba>/                    se borra y se recrea en cada `iniciar`
    ├── placa/       placa.config, placa.log, offload.dat, salida.txt
    ├── scripts/     (en la Placa)
    ├── storage/     storage.config, storage.log, fs/volumen.dat
    ├── planificador/ planificador.config, planificador.log, reportes.log
    ├── datos/       (en el Planificador)
    └── core-<id>/   core.config, core_<id>.log
```

## Uso
```bash
deploy/desplegar.sh deploy/pruebas/<prueba> <acción>
```

| Acción | Qué hace |
| --- | --- |
| `preparar` | `git fetch` + checkout de `REF` (por defecto `origin/develop`) en `~/tp-run/src`, y compila **solo los módulos que corre cada servidor** |
| `preparar --local` | Igual, pero copia **este checkout con rsync** (sirve para probar cambios sin pushear) |
| `iniciar` | Genera los configs con las IPs, sube scripts y datos, y levanta los módulos **en orden**: Placa y Storage → Planificador → Cores. Antes de seguir, espera a que cada puerto esté abierto |
| `estado` | Muestra las sesiones `tp-*` que hay en cada servidor |
| `detener` | Manda Ctrl-C a cada módulo y cierra las sesiones |
| `logs` | Trae logs, configs y reportes a `deploy/resultados/<prueba>-<fecha>/`, con un resumen de errores y warnings |
| `ejecutar` | `iniciar` + esperar `JOBS_ESPERADOS` (máximo `TIEMPO_MAXIMO`) + `detener` + `logs` |
| `matar <módulo>` | `kill -9` solo del binario (`placa`, `storage`, `planificador`, `core-<id>`) |
| `levantar <módulo>` | Lo vuelve a arrancar con su config y sus datos, sin borrar nada |
| `esperar <módulo> <texto> [s]` | Espera a que `<texto>` aparezca en el log del módulo (sirve para sincronizar, por ejemplo matar después del COMMIT) |

Opciones de `iniciar` y `ejecutar`:
- `--job <script>`: otro script inicial.
- `--conservar-storage`: no borra el volumen ni el journal de la corrida anterior.

Las usa `deploy/pruebas/checkpoints/correr.sh` ([[Check 4 2026-11-14]]).

### Sesiones de tmux
Cada módulo corre en una sesión: `tp-placa`, `tp-storage`, `tp-planificador`, `tp-core-<id>`. Para el **Labeler** o la **consola del Storage**:

```bash
ssh -t utnso@192.168.1.27 tmux attach -t tp-planificador
```

Para salir sin cortar el módulo: `Ctrl-b` y después `d`.

## Cómo se arman los configs
1. Se parte del config base del repo (`placa/placa.config`, `storage/storage.config`, `planificador/planificador.config`, `core/core1.config`).
2. El despliegue completa **IPs, puertos de destino y rutas**: `IP_PLACA`, `IP_STORAGE`, `IP_PLANIFICADOR`, `PATH_INSTRUCCIONES`, `PATH_OFFLOAD`, `PATH_STORAGE`, `PATH_DATOS` y `PATH_REPORTES`.
3. Al final se aplican las claves de la prueba (`CONFIG_PLACA`, `CONFIG_STORAGE`, `CONFIG_PLANIFICADOR`, `CONFIG_CORE`).

Los puertos de escucha salen del config base, salvo que la prueba los cambie.

## `prueba.conf`
```bash
PLACA=192.168.1.25
STORAGE=192.168.1.26
PLANIFICADOR=192.168.1.27
CORES="1@192.168.1.28 2@192.168.1.29"     # id@ip, se pueden repetir IPs

JOB_INICIAL=mini                            # relativo a scripts/

CONFIG_PLACA="TAM_MEMORIA=256 TAM_PAGINA=64 ALGORITMO_REEMPLAZO=CLOCK-M RETARDO_MEMORIA=5 RETARDO_OFFLOAD=20"
CONFIG_STORAGE="RETARDO_ACCESO_BLOQUE=5 RETARDO_COMMIT=5"
CONFIG_PLANIFICADOR="ALGORITMO_PLANIFICACION=RR RR_QUANTUM=200 RETARDO_LOADER=100"
CONFIG_CORE=""

JOBS_ESPERADOS=1
TIEMPO_MAXIMO=60
```

Para una prueba nueva alcanza con copiar la carpeta y cambiar las IPs y las claves. Por ejemplo, para correr todo en una sola máquina se pone la misma IP en todos los módulos.

## Primera corrida distribuida (14/11)
`mini_entrenamiento` sobre `develop` (`5922131`), un módulo por servidor:

| Qué se validó | Resultado |
| --- | --- |
| Despliegue + compilación en los 5 servidores | ✅ sin warnings |
| Arranque en orden, esperando cada puerto | ✅ |
| Conexiones entre máquinas | ✅ La Placa recibió al Planificador y a 2 Cores, el Storage al Planificador y el Planificador a 2 Cores |
| Job | ✅ `EXIT` en unos 3 s: 9 page faults, 5 reemplazos, 512 bytes de memoria dinámica máxima |
| Reporte | ✅ el mismo que en la [[Mini Entrenamiento 2026-11-14\|prueba local]] |
| Errores | ✅ 0 (los 2 del Storage son del apagado) |

> [!note] Observaciones
> - ~~**El Storage loguea errores al apagarse**~~: resuelto en `2a9b3b3`. Al repetir la prueba distribuida dio 0 errores en los 6 logs ([[Storage]]).
> - **El Core 2 quedó sin trabajo:** con un solo Job, el Core 1 siempre está libre primero. Para usar los 2 Cores hace falta una prueba con varios Jobs.

## Suite de la cátedra: `deploy/catedra.sh`
Corre los escenarios de `entrenados-pruebas` (clonado en `~/entrenados-pruebas`) con sus propias configs y los verifica automáticamente. Detalle y resultados en [[Suite cátedra 2026-11-14]].

```bash
deploy/catedra.sh checkpoint_3 todos
deploy/catedra.sh checkpoint_2 todos --rapido
```

- `catedra.conf`: en qué servidor va cada módulo.
- `catedra_entradas.conf`: las respuestas al Labeler y los comandos de consola del Storage.
- `verificar_catedra.py`: la comparación con los resultados esperados.
- `pruebas/repartos.sh`: los mismos escenarios con 4 repartos de módulos distintos ([[Suite cátedra 2026-11-14#Repartos de módulos entre servidores]]).
- Cada servidor se puede pisar desde el entorno: `PLACA=… STORAGE=… PLANIFICADOR=… CORES_HOSTS="…" deploy/catedra.sh …`

## Pruebas finales (`entregas_finales`)
`catedra.sh` también corre la suite de las entregas finales, con variantes por carpeta:

```bash
deploy/catedra.sh entregas_finales 01_planificacion/HRRN
deploy/pruebas/finales/05_journal.sh      # secuencias: 04_storage.sh, 05_journal.sh, 06_estabilidad.sh
```

Para armar secuencias hay acciones sobre un escenario ya iniciado (`--solo-iniciar`):

| Acción | Qué hace |
| --- | --- |
| `esperar-log <módulo> <texto> [s]` | Espera a que el texto aparezca en el log |
| `matar` / `parar <módulo>` | `kill -9` / Ctrl-C |
| `levantar <módulo> [script]` | Lo vuelve a arrancar; el Planificador, con otro script |
| `consola <módulo> <comando>` | Escribe en la consola del Storage o de la Placa |
| `cortar-durante <módulo> <ERE> [s]` | Ctrl-C apenas la última línea del log coincide (por ejemplo, un Core durante `FORWARD`) |
| `esperar-fin [s]` · `detener` · `limpiar-storage` · `resultados` | Fin de los Jobs, cortar todo, borrar el volumen y traer los logs |

Opciones nuevas: `--cores "1 2"` (Cores que se arrancan al principio), `--conservar-storage` y `--valgrind "<módulos>"` (un `valgrind.<pid>.txt` por proceso). La acción `cpu [s]` mide el % de CPU de cada proceso del TP; las dos se usan en `deploy/pruebas/finales/verificar_recursos.sh`. Resultados en [[Pruebas finales 2026-11-24]].

## Próximas pruebas
- [x] Varios Jobs (con `INIT_JOB`) para que trabajen los 2 Cores (suite de la cátedra)
- [x] LRU contra CLOCK-M con el mismo script (CP3 04 y 05)
- [x] FIFO en el Planificador (CP2 02)
- [ ] HRRN con los módulos reales
- [ ] Desconexión de un Core en medio de la ejecución con los módulos reales (`deploy/desplegar.sh … matar core-2`); hasta ahora solo se probó con mocks
- [x] Todo en una sola máquina y distribuciones mixtas (4 repartos ✅)
- [x] Checkpoints (Check 4): `SAVE` en un Job y `LOAD` en otro, y Storage caído → [[Check 4 2026-11-14]]
