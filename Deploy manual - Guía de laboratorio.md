---
tags: [tp-so, entrenados, deploy, laboratorio]
actualizado: 2026-11-28
rama: deploy
---

# Deploy manual: guía de laboratorio

Volver a [[00 - Inicio]] · Ver también [[Despliegue distribuido]], [[Laboratorio manual 2026-11-27]], [[Pruebas finales 2026-11-28]]

Cada módulo se levanta **a mano en su VM**, desde la rama `deploy`. Objetivo: el ambiente listo en **menos de 10 minutos**.

## 0. Datos del día (completar)

| VM | IP | Módulos |
| --- | --- | --- |
| 1 | | Planificador |
| 2 | | Placa |
| 3 | | Storage |
| 4 | | Cores |
| 5 | | Cores |

En una sola máquina también funciona: `MÓDULOS : todos` y las tres IPs iguales.

## 1. Preparar cada VM (una sola vez)

**1.1 Clonar.** En la contraseña de GitHub va el **token**:
```bash
git clone https://github.com/sisoputnfrba/tp-2026-2c-requiemso.git ~/tp-2026-2c-requiemso
git clone https://github.com/sisoputnfrba/entrenados-pruebas ~/entrenados-pruebas
git config --global credential.helper 'cache --timeout=36000'
```
El `credential.helper` recuerda el token 10 horas, sin escribirlo en disco. Las commons ya están instaladas.

**1.2 Rama y compilación:**
```bash
cd ~/tp-2026-2c-requiemso && git switch deploy && git pull && ./preparar.sh
```
- `git switch` y **no** `git checkout`: en el repo hay una carpeta `deploy/` con el mismo nombre que la rama.
- Si `git pull` dice *There is no tracking information*: `git branch --set-upstream-to=origin/deploy deploy`.

**1.3 Respuestas de `preparar.sh`:**
- `MÓDULOS :` los de esa VM (`placa`, `core`, `planificador storage`, `todos`…)
- `IP PLANIFICADOR :` · `IP PLACA :` · `IP STORAGE :` — **las mismas tres IPs en todas las VMs**

El script limpia, recompila y deja los binarios en `~/tp-2026-2c-requiemso/bin/`. Volver a correrlo pide todo de nuevo.

## 2. Configs de la cátedra (IPs)

Las configs de `entrenados-pruebas` traen `127.0.0.1`. Hay que cambiarlo **en cada VM**, en las configs de los módulos que corren ahí:

| Config | Claves | En qué VM |
| --- | --- | --- |
| `planificador.config` | `IP_PLACA`, `IP_STORAGE` | La del Planificador |
| `core-N.config` | `IP_PLANIFICADOR`, `IP_PLACA` | Las de los Cores |
| `placa.config`, `storage.config` | ninguna (solo escuchan) | — |

Opcional: todas las configs de todas las pruebas en un solo comando (completar las IPs):
```bash
cd ~/entrenados-pruebas/entregas_finales && sed -i -e 's/^IP_PLANIFICADOR=.*/IP_PLANIFICADOR=X.X.X.X/' -e 's/^IP_PLACA=.*/IP_PLACA=Y.Y.Y.Y/' -e 's/^IP_STORAGE=.*/IP_STORAGE=Z.Z.Z.Z/' $(find escenarios -name '*.config')
```
Para volver al original: `git -C ~/entrenados-pruebas checkout -- .`

## 3. Antes de cada prueba (en cada VM)

```bash
cd ~/entrenados-pruebas/entregas_finales && rm -f *.log && mkdir -p ./runtime/<runtime>/storage
```
- **Todo se lanza desde `entregas_finales`**: las rutas de las configs son relativas a esa carpeta.
- `./runtime/<runtime>/` tiene que existir **en cada máquina que lo usa**: en la Placa (Offload), en el Storage (volumen) y en el Planificador (reportes). Si falta en la Placa, no arranca o el Job 0 no se crea.
- En la VM del Storage, además, empezar limpio: `rm -rf ./runtime/<runtime>` antes del `mkdir`, **salvo en la recuperación de la 05**.
- `rm -f *.log`: los logs se agregan al final de los anteriores. Sin esto, se mezclan las pruebas.

## 4. Orden de arranque

Cada uno en su terminal, esperando que el anterior muestre que está escuchando:

| # | Módulo | Comando |
| --- | --- | --- |
| 1 | Storage | `~/tp-2026-2c-requiemso/bin/storage "$PWD/escenarios/<prueba>/configs/<variante>/storage.config"` |
| 2 | Placa | `~/tp-2026-2c-requiemso/bin/placa "$PWD/escenarios/<prueba>/configs/<variante>/placa.config"` |
| 3 | Planificador | `~/tp-2026-2c-requiemso/bin/planificador "$PWD/escenarios/<prueba>/configs/<variante>/planificador.config" <script>` |
| 4 | Cores | `~/tp-2026-2c-requiemso/bin/core "$PWD/escenarios/<prueba>/configs/core-N.config" N` |

- Las pruebas 03 y 06 no tienen variante: las configs están directo en `configs/`.
- Cada Core con un **ID distinto**: un ID repetido se rechaza. Para un Core extra (5, 6…) se usa cualquier `core-K.config` con otro ID.
- **No correr dos pruebas a la vez**: comparten los puertos 8080, 8081 y 8082.

## 5. Las pruebas

| Prueba | Variante | Runtime | Script | Cores al inicio |
| --- | --- | --- | --- | --- |
| 01 Planificación | `FIFO` · `RR` · `HRRN` | `01_planificacion_fifo` · `_rr` · `_hrrn` | `PLANIFICACION.asm` | 1 |
| 02 Memoria | `LRU` · `CLOCK-M` | `02_memoria_lru` · `02_memoria_clockm` | `MEMORIA.asm` | 1 y 2 |
| 03 Servicios | — | `03_servicios` | `SERVICIOS.asm` | 1 y 2 |
| 04 Storage | `checkpoints` · `fs_lleno` | `04_storage_checkpoints` · `04_storage_fs_lleno` | `ST_ENTRENAR.asm` · `FS_A.asm` | 1 |
| 05 Journal | `A` · `B` | `05_journal_a` · `05_journal_b` | `JOURNAL.asm` | 1 |
| 06 Estabilidad | — | `06_estabilidad` | `ESTABILIDAD.asm` | 1 y 2 |

### Qué hacer durante cada una y qué mirar

**01 Planificación**
- Nada que tipear.
- Mirar en `planificador.log`:
  - FIFO: el Job largo hace su 2.ª ráfaga antes que los cortos;
  - RR: `Desalojado por fin de quantum`, y los cortos terminan primero;
  - HRRN: `Prioridad HRRN calculada`, y los cortos antes que el largo.
- Fin: 4 Jobs en `EXIT`.

**02 Memoria**
- Nada que tipear.
- Mirar en `placa.log`: `## Reemplazo` con víctimas de los dos Jobs, y `Bajada al Offload` solo de las modificadas. Los reportes son iguales con LRU y con CLOCK-M.

**03 Servicios**
- En la terminal del **Planificador**, cada vez que aparece `## (N) - Ingrese 8 caracteres:`, tipear en orden: `PERRO001`, `GATO0002` y `LORO0003`.
- Cada reporte es su lote seguido del texto.

**04 Storage**
- Al terminar la corrida, en la consola del **Storage**: `LS`. Después Ctrl-C, volver a levantar el Storage con la misma config (**sin** borrar `runtime/`) y `LS` otra vez: tiene que dar lo mismo.
- Esperado:
  - checkpoints: un Job carga lo que guardó otro; borrar un inexistente solo se informa; cargar un inexistente → `CHECKPOINT_INEXISTENTE`.
  - fs_lleno: `## ERROR - Directorio lleno…` y `## ERROR - Falta de espacio en FAT…` → `SIN_ESPACIO_STORAGE`.

**05 Journal**
1. Con todo corriendo, **en la VM del Storage** (otra terminal), mirar `storage.log` y matar con `pkill -9 -x storage`:
   - **A:** después de `## Asiento iniciado: 2` y antes de su COMMIT (hay unos 10 s);
   - **B:** después de `## Nueva marca en asiento: 2: - COMMIT` y antes de su APPLIED.
2. Ctrl-C en el resto de los módulos. **No borrar `runtime/`.**
3. Levantar **solo el Storage** con la misma config: tiene que loguear `## Recuperación - Asiento: …`. En su consola: `LS` y `CAT modelo 16`.
4. Ctrl-C y volver a levantarlo: `LS` y `CAT` dan lo mismo.
5. Con el Storage arriba, levantar Placa, Planificador y Core con el script `JOURNAL_VERIFICAR_A.asm` (o `_B`).
- Esperado:
  - A: asiento 2 `DESCARTADO`, `modelo` de 256 bytes con la versión anterior;
  - B: asiento 2 `APLICADO`, `modelo` de 512 bytes con la versión nueva.

**06 Estabilidad**
- Arrancar con los Cores 1 y 2. Durante la corrida:
  1. Conectar el **Core 3** (`core-3.config 3`) mientras haya Jobs en READY.
  2. Ctrl-C en un Core **mientras su log muestra** `Ejecutando: FORWARD` o `BACKWARD`.
  3. Volver a conectar ese Core (mismo comando, mismo ID).
  4. Conectar el **Core 4** (`core-4.config 4`).
- Al terminar: `INFO` en la consola de la **Placa** (0 frames lockeados, 0 Jobs) y `LS` en la del **Storage**.
- Esperado: 13 Jobs en `EXIT`. El Job del Core cortado vuelve a READY (`Deslockeo de páginas`) y termina en otro Core.

## 6. Entre pruebas
- **Ctrl-C** en este orden: Cores → Planificador → Placa → Storage.
- Volver al paso 3 con la siguiente prueba: limpiar los logs y crear su `runtime/` en cada máquina.

## 7. Dónde quedan los logs
En cada VM, en `~/entrenados-pruebas/entregas_finales/`: `planificador.log`, `placa.log`, `storage.log` y `core_N.log`. En `runtime/<runtime>/`: `reportes.log` (VM del Planificador), `offload.dat` (VM de la Placa), y `storage/volumen.dat` y `storage/journal.txt` (VM del Storage).

## 8. Problemas frecuentes

| Síntoma | Causa | Solución |
| --- | --- | --- |
| `No se pudo abrir el archivo de configuración` | Se lanzó fuera de `entregas_finales` | `cd ~/entrenados-pruebas/entregas_finales` |
| La Placa no arranca, o `El Job 0 no se pudo crear` | Falta `./runtime/<runtime>/` en la VM de la Placa | `mkdir -p ./runtime/<runtime>` |
| `No se pudo conectar a Placa` / `Storage` | IP mal en `planificador.config`, o el servidor no está levantado | Revisar las IPs y el orden de arranque |
| El Core no conecta | IP mal en `core-N.config`, o el Planificador no está arriba | Revisar las IPs; levantar el Planificador primero |
| `Ya hay un Core conectado con el ID N` | ID repetido | Lanzarlo con otro ID |
| `Address already in use` | Quedó un módulo de la prueba anterior | `pkill -x <módulo>` en esa VM |
| `'deploy' could be both a local file and a tracking branch` | `git checkout deploy` | `git switch deploy` |
| Se cae una VM | — | Ctrl-C en todo; en otra VM `./preparar.sh` con ese módulo; ajustar las IPs y repetir la prueba |
