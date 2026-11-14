---
tags: [tp-so, entrenados, pruebas, catedra]
fecha: 2026-11-14
rama: develop (03d9deb)
repo_pruebas: sisoputnfrba/entrenados-pruebas (65fcdcf)
resultado: ok
---

# Suite de la cátedra: 14/11/2026

Volver a [[00 - Inicio]] · Ver [[Despliegue distribuido]], [[Plan de acción]] · Prueba propia anterior: [[Mini Entrenamiento 2026-11-14]]

Primera corrida completa de **`entrenados-pruebas`**, la suite oficial con los escenarios de los checkpoints 2 y 3 (el CP4 todavía no se publicó), en los **5 servidores** y con un módulo por máquina. Se usaron las configs de cada escenario tal como vienen; solo se cambiaron las IPs y se pasaron las rutas a absolutas.

> [!success] Resultado
> **Todos los escenarios del CP2 y el CP3 pasan.**
> - **CP2:** 14 corridas en modo rápido.
> - **CP3:** 11 escenarios con los retardos reales.
>
> Los únicos `[ERROR]` en los logs son los que cada prueba busca provocar.

## Cómo se corre
```bash
deploy/catedra.sh checkpoint_3 todos                 # todos los escenarios de un checkpoint
deploy/catedra.sh checkpoint_3 06_page_locking       # uno solo
deploy/catedra.sh checkpoint_2 todos --rapido        # CP2 con RETARDO_MEMORIA=10 y RR_QUANTUM=20
deploy/catedra.sh checkpoint_3 todos --preparar      # despliega origin/develop antes de correr
```

- El clon de las pruebas tiene que estar en `~/entrenados-pruebas`, tanto en esta máquina como en cada servidor. Los servidores se definen en `deploy/catedra.conf`.
- Al terminar cada escenario, `deploy/verificar_catedra.py` lo compara con los resultados esperados:
  - **CP2:** `EXIT`, los 13 registros (log `Contexto final`) y la secuencia de FETCH concatenada entre Cores.
  - **CP3:** cómo finaliza cada Job y la secuencia de `REPORT` contra `resultados/memoria.md`.
- **LABEL:** el runner responde solo, según `deploy/catedra_entradas.conf`. La espera se puede dar en segundos o como `R<n>`, que significa "después de n reemplazos de la Placa".
- **Consola del Storage (10 y 11):** se mandan los comandos del README, se reinicia el Storage y se manda una segunda tanda de comandos.
- Los resultados quedan en `deploy/resultados/catedra-<checkpoint>-<escenario>-<fecha>/`.

> [!info] Tiempos
> Con `RETARDO_MEMORIA=500`, cada FETCH tarda 500 ms. Los escenarios 02 a 05 del CP2 tardan unos 12 minutos cada uno, como calcula la guía de la cátedra, y `--rapido` aplica la pasada rápida que sugiere esa misma guía. El CP3 con retardos reales tarda alrededor de 30 minutos: cada mini entrenamiento lleva unos 5.

## Checkpoint 2 (modo rápido)
| Escenario | Qué se validó | Resultado |
| --- | --- | --- |
| 01 instrucciones (9 scripts por separado) | `EXIT`, los 13 registros y la secuencia de FETCH de cada script | ✅ 9/9 |
| 02 FIFO, 1 Core | launcher + 3 hijos: registros y FETCH por JID | ✅ |
| 03 RR, 1 Core | ídem, con **521 desalojos por quantum** | ✅ |
| 04 RR, 2 Cores | ídem; los **dos Cores trabajan** (828 y 622 FETCH) | ✅ |
| 05 multiprogramación, grado 1 | **como máximo 1** Job admitido a la vez | ✅ |
| 05 multiprogramación, grado 2 | **como máximo 2** Jobs admitidos a la vez | ✅ |

`06_contexto_a` y `07_contexto_b` (814 y 614 instrucciones) no tienen la secuencia de FETCH escrita como lista en `individuales.md`. En esos dos se comparan solo los registros finales.

## Checkpoint 2 con los retardos reales
`RETARDO_MEMORIA=500` (cada FETCH tarda 500 ms) y `RR_QUANTUM=2000`, tal como vienen las configs. **Todo pasa, con 0 errores en los logs.**

| Escenario | Duración | Detalle |
| --- | ---: | --- |
| 01 instrucciones (9 scripts) | ~40 s | este escenario usa `RETARDO_MEMORIA=10`; 9/9 ✅ |
| 02 FIFO, 1 Core | 920 s | ✅ los 3 hijos con sus registros y FETCH |
| 03 RR, 1 Core | 869 s | ✅ **388 desalojos** (220 del Job A y 164 del B); unas **4 instrucciones por turno**, que es lo que da 2000 ms / 500 ms |
| 04 RR, 2 Cores | 443 s | ✅ la mitad del tiempo: los dos Cores en paralelo (823 y 627 FETCH), 365 desalojos |
| 05 grado 1 | 892 s | ✅ como máximo 1 Job admitido a la vez |
| 05 grado 2 | 869 s | ✅ como máximo 2 Jobs admitidos a la vez |

La guía estima unos 12 minutos por corrida (407 s para A y 307 s para B, sin contar red ni cambios de contexto). Las medidas dan entre 14 y 15 minutos con un Core, y la mitad con dos.

## Checkpoint 3 (retardos reales)
| Escenario | Esperado | Resultado |
| --- | --- | --- |
| 01 reserva y liberación | un `REPORT` `48 6F 6C 61` (Hola) | ✅ |
| 02 aritmética | `REPORT` del patrón A | ✅ |
| 03 cruce de página | `AX=6`, `REPORT` `06 00 00 00` | ✅ |
| 04 mini entrenamiento con LRU | 8 `REPORT` del patrón A; al cargar la página 4 las víctimas son 0, 1, 2 y 3; AX=0 y BX=0 | ✅ víctimas en el orden **0→1→2→3** (16 PF, 12 reemplazos, 8 bajadas al Offload) |
| 05 mini entrenamiento con CLOCK-M | 8 `REPORT` del patrón A | ✅ |
| 06 page locking | con el `LABEL` pendiente, el otro Job reemplaza páginas **sin tocar las del LABEL** | ✅ 3 reemplazos en 109 s (marcos 1 y 3), **0 víctimas del Job de LABEL**; `REPORT` `41 42 43 44` |
| 07 servicios FIFO | `servicios_a`: Hola → ABCD; `servicios_b`: TEST → WXYZ | ✅ |
| 08 sin Offload | el primer hijo termina con error; el segundo reporta Hola | ✅ `OUT_OF_MEMORY` + Hola |
| 09 aislamiento | 8 `REPORT` A del Job A y 8 `REPORT` B del Job B | ✅ |
| 10 consola: directorio lleno | geometría 64/32/1, sobrescritura, directorio lleno, persistencia al reiniciar | ✅ tal como la tabla del README |
| 11 consola: bloques agotados | el tercer `WRITE` falla por falta de espacio en la FAT, con entradas libres en el directorio | ✅ |

Patrones A y B, de `resultados/memoria.md`:
- A: `31 00 00 00 01 00 00 00 64 00 00 00 00 00 00 00 33 00 00 00`
- B: `62 00 00 00 01 00 00 00 C8 00 00 00 00 00 00 00 66 00 00 00`

## Repartos de módulos entre servidores
La evaluación puede cambiar en qué máquina corre cada módulo. Con `deploy/pruebas/repartos.sh` se corrieron dos escenarios con 4 repartos distintos:
- **CP2 04** (RR con 2 Cores, modo rápido)
- **CP3 07** (memoria, servicios y Labeler, con 2 Cores)

| Reparto | Placa | Storage | Planificador | Core 1 | Core 2 | CP2 04 | CP3 07 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Todo junto | .25 | .25 | .25 | .25 | .25 | ✅ | ✅ |
| Memoria aparte | .25 | .25 | .26 | .26 | .27 | ✅ | ✅ |
| Cores con la Placa | .25 | .26 | .26 | .25 | .25 | ✅ | ✅ |
| Cores separados | .27 | .28 | .29 | .25 | .26 | ✅ | ✅ |

Pasaron los 8, sin `[ERROR]` en los logs. Para probar otro reparto se pisan los servidores desde el entorno:

```bash
PLACA=192.168.1.25 STORAGE=192.168.1.25 PLANIFICADOR=192.168.1.25 CORES_HOSTS="192.168.1.25 192.168.1.25" \
  deploy/catedra.sh checkpoint_3 07_servicios_fifo
```

> [!note] Binarios por servidor
> `preparar` compila en cada servidor solo los módulos de su reparto fijo. Ahora `catedra.sh` compila en el momento el binario que falte antes de lanzar cada módulo, así cualquier reparto funciona sin preparar de nuevo.

## Cambios en el TP que salieron de la suite
> [!bug] Placa: Job inicial con ruta absoluta (`896a387`)
> La guía del CP2 pasa el Job inicial como `"$PWD/scripts/..."` y dice que "Placa debe aceptar esa ruta sin anteponer `PATH_INSTRUCCIONES`". La Placa la rechazaba (`se esperaba un archivo relativo…`) y el Job terminaba con `ERROR_PLACA`.
>
> Ahora `armar_ruta()` usa las rutas absolutas tal cual, y `crear_job()` dejó de rechazarlas.

> [!info] Planificador: log del contexto final (`896a387`)
> La guía pide validar los registros del contexto devuelto, y el formato de esa impresión es libre. Al finalizar cada Job ahora se loguea `## (<JID>) Contexto final: PC=… AX=… … E3=…`. No es un log obligatorio, y los obligatorios no cambiaron.

## Problemas del runner que aparecieron (ya resueltos)
- **El timeout de 300 s era corto:** con 500 ms por FETCH, el escenario 02 tarda 12 minutos. Se agregó `--rapido`.
- **El `LABEL` del 06 se respondía antes de tiempo:** con una espera fija de 25 s, el otro Job todavía no había empezado a reemplazar páginas (su primer reemplazo llega a los 2 minutos). Ahora la espera es `R3`: responder después de 3 reemplazos.
- **La consola del Storage recibía solo el primer comando:** `ssh` se quedaba con el resto de la entrada estándar del loop. Se arregló con `ssh -n`.
- **Mapa de JIDs:** los escenarios de consola usaban el del escenario anterior.

## Pendiente
- [x] CP2 con los retardos reales: ✅ (ver la tabla de arriba)
- [ ] CP4, cuando lo publiquen: se agrega a `catedra.sh` (los checkpoints ya están probados con `deploy/pruebas/checkpoints/correr.sh`)
- [x] Distribuciones mixtas de módulos entre servidores (4 repartos ✅)
