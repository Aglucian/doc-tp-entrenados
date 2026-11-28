---
tags: [tp-so, entrenados, deploy, herramientas]
actualizado: 2026-11-28
---

# Uso de `deploy/` (herramientas de prueba por SSH)

Volver a [[00 - Inicio]] · Ver también [[Despliegue distribuido]], [[Pruebas finales 2026-11-28]], [[Deploy manual - Guía de laboratorio]]

`Repo TP/deploy/` tiene las herramientas que usamos para **correr las pruebas de forma automática desde una máquina de control**, lanzando cada módulo por SSH en las VMs. Con ellas se hicieron todas las baterías (24/11 y 28/11).

> [!important] No es parte de la entrega
> - El 28/11 se sacó del repo del TP: para el **despliegue manual** del laboratorio no hace falta. Ahí se usa solo `preparar.sh`, que está en la raíz del TP (ver [[Deploy manual - Guía de laboratorio]]).
> - El TP tiene `/deploy/` en su `.gitignore`, así que copiarlo adentro para usarlo **no ensucia el repo** ni se commitea por error.

## 1. Instalarlo (cada vez que se quiera usar)

Los scripts **tienen que estar dentro del repo del TP**: calculan la raíz del TP desde su propia ubicación, copian ese checkout a las VMs y guardan los resultados en `deploy/resultados/`.

```bash
cp -r ~/doc-tp-entrenados/"Repo TP"/deploy ~/tp-2026-2c-requiemso/
```

Para sacarlo después: `rm -rf ~/tp-2026-2c-requiemso/deploy`. Si se quieren guardar los resultados, antes se mueve `deploy/resultados/` a otro lado.

## 2. Requisitos
- **Máquina de control** con el TP clonado y `entrenados-pruebas` en `~/entrenados-pruebas`.
- **SSH con clave pública, sin contraseña**, a cada VM (`ssh-copy-id utnso@<ip>`), y `tmux` y `rsync` instalados en las VMs.
- En cada VM: so-commons instaladas, `~/entrenados-pruebas` clonado, y (solo para `--preparar` sin `--local`) el repo del TP en `~/tp-2026-2c-requiemso`.
- `valgrind` en las VMs, solo para `verificar_recursos.sh`.

## 3. Configuración

| Archivo | Qué define |
| --- | --- |
| `servidores.conf` | Usuario SSH (`utnso`), dónde está el clon del TP en cada VM, base remota (`~/tp-run`), `REF` a desplegar (por defecto `origin/develop`) y la lista de servidores |
| `catedra.conf` | Reparto para las pruebas de la cátedra: `PLACA`, `STORAGE`, `PLANIFICADOR`, `CORES_HOSTS` (core-1 al primero, core-2 al segundo, y se repite). **Se pisan desde el entorno** |
| `catedra_entradas.conf` | Respuestas al Labeler y comandos de consola del Storage que necesita cada escenario |
| `pruebas/*/prueba.conf` | Reparto y claves de config de las pruebas propias (Mini Entrenamiento, checkpoints) |

Con IPs nuevas hay que actualizar `servidores.conf`, `catedra.conf` y los `prueba.conf`. Para cambiar el reparto de una sola corrida alcanzan las variables de entorno:
```bash
PLACA=10.0.0.1 STORAGE=10.0.0.2 PLANIFICADOR=10.0.0.3 CORES_HOSTS="10.0.0.4 10.0.0.5" deploy/catedra.sh ...
```

## 4. Desplegar el código: `desplegar.sh`

```bash
deploy/desplegar.sh deploy/pruebas/mini_entrenamiento preparar --local
```
- `preparar --local` copia **este checkout** (con cambios sin commitear) a `~/tp-run/src` de cada VM y compila lo que corre ahí. Sin `--local`, hace `git fetch` + checkout de `REF` en el clon de cada VM.
- Otras acciones (sobre la prueba indicada): `iniciar`, `estado`, `detener`, `logs`, `ejecutar` (iniciar + esperar + detener + logs), `matar <módulo>`, `levantar <módulo>`, `esperar <módulo> <texto> [s]`.
- Cada módulo corre en una sesión de tmux de su VM: `tp-placa`, `tp-storage`, `tp-planificador`, `tp-core-<id>`. Para verla en vivo: `ssh -t utnso@<ip> tmux attach -t tp-planificador`.

## 5. Pruebas de la cátedra: `catedra.sh`

```bash
deploy/catedra.sh <checkpoint_2|checkpoint_3|entregas_finales> <escenario|todos> [opciones]
```

Ejemplos:
```bash
deploy/catedra.sh entregas_finales 01_planificacion/FIFO --preparar-local
deploy/catedra.sh entregas_finales 02_memoria/LRU
deploy/catedra.sh entregas_finales 03_servicios
deploy/catedra.sh checkpoint_3 todos
deploy/catedra.sh checkpoint_2 todos --rapido
```

**Opciones principales**

| Opción | Para qué |
| --- | --- |
| `--preparar` / `--preparar-local` | Despliega antes de correr (`REF` de git, o este checkout) |
| `--timeout <s>` | Máximo de espera por escenario (600 por defecto) |
| `--rapido` | En CP2: `RETARDO_MEMORIA=10` y, en RR, `RR_QUANTUM=20` |
| `--cores "1 2"` | Qué Cores arrancan al principio (los demás se levantan después) |
| `--solo-iniciar` | Levanta todo y termina, para seguir con `--accion` |
| `--conservar-storage` | No borra el volumen ni el journal |
| `--valgrind "<módulos>"` | Corre esos módulos bajo valgrind (`valgrind.<pid>.txt`) |

**Acciones sobre un escenario ya iniciado** (`--accion ...`): `esperar-log <módulo> <texto> [s]`, `matar <módulo>` (kill -9), `parar <módulo>` (Ctrl-C), `cortar-durante <módulo> <ERE> [s]`, `levantar <módulo> [script]`, `consola <módulo> <comando>`, `esperar-fin [s]`, `detener`, `limpiar-storage`, `resultados`, `cpu [s]`.

- Las configs se toman **del clon local de `entrenados-pruebas`** y se fijan las IPs por clave, así que las ediciones manuales en las VMs no afectan.
- En el CP2 y el CP3, al terminar se compara con lo esperado (`verificar_catedra.py`).

## 6. Secuencias de las pruebas finales

| Script | Qué hace |
| --- | --- |
| `pruebas/finales/04_storage.sh` | Corridas checkpoints y fs_lleno, `LS`, reinicio del Storage y `LS` |
| `pruebas/finales/05_journal.sh` | Casos A y B: `kill -9` al Storage en el momento indicado, recuperación, `LS` y `CAT`, reinicio y Job de verificación |
| `pruebas/finales/06_estabilidad.sh` | Cores 1 y 2; conecta el 3, corta el 1 durante `FORWARD`/`BACKWARD`, lo reconecta y conecta el 4; `INFO` y `LS` al final |
| `pruebas/finales/verificar_recursos.sh` | La 06 con los 4 módulos bajo valgrind y CPU en reposo; después la 03 con el Labeler esperando teclado y CPU |

La 01, la 02 y la 03 se corren directo con `catedra.sh` (sección 5).

## 7. Otras pruebas
- `pruebas/repartos.sh`: los mismos escenarios (CP2 04 rápido y CP3 07) con distintos repartos de módulos entre servidores.
- `pruebas/checkpoints/correr.sh [--local]`: prueba propia del Check 4 (guardar, restaurar desde otro Job, `kill -9` después del COMMIT y verificación).
- `pruebas/mini_entrenamiento/`: la primera prueba de punta a punta (`desplegar.sh deploy/pruebas/mini_entrenamiento ejecutar`).

## 8. Resultados
Cada corrida deja una carpeta en `deploy/resultados/` (por ejemplo `catedra-entregas_finales-06_estabilidad-<fecha>/`) con:
- una subcarpeta por módulo (`placa/`, `planificador/`, `storage/`, `core-N/`) con su log, su config y la salida de consola (`salida.txt`);
- `runtime/reportes.log`;
- `jobs.txt` (JID → script);
- y, si se usó `--valgrind`, los `valgrind.<pid>.txt`.

`resultados/` está en el `.gitignore` de `deploy/`.
