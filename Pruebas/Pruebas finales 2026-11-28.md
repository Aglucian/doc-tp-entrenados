---
tags: [tp-so, entrenados, pruebas, entregas-finales, informe]
fecha: 2026-11-28
rama: deploy (158dc6f y 10c5c86); main (b65d18a) en la tercera batería
repo_pruebas: sisoputnfrba/entrenados-pruebas (e841d29)
resultado: ok
---

# Informe: pruebas finales del 28/11/2026

Volver a [[00 - Inicio]] · Corrida anterior: [[Pruebas finales 2026-11-24]] · Práctica manual: [[Laboratorio manual 2026-11-27]]

> [!success] Resultado
> **Las 6 pruebas finales pasan, en todas sus variantes** (10 corridas), con el código de la rama de entrega `deploy` (`158dc6f`).
> - 0 errores inesperados en los logs. Todos los `[ERROR]` que aparecen son los avisos esperados de las pruebas que fuerzan errores (04 y 05).
> - Cada resultado esperado del Documento de Pruebas se verificó contra los logs, los reportes y el `LS`/`CAT` del Storage.
> - Los resultados coinciden con los del 24/11. Solo cambian la cantidad de desalojos y de reemplazos, que dependen de los tiempos.
>
> La batería completa tardó **15 minutos** (00:45 → 01:00).
>
> **Segunda batería (02:14 → 03:28, con 5 VMs):** las 6 finales con **5 máquinas** (22/22 criterios OK) y con **todo en una sola máquina**, **valgrind y CPU** (0 bytes perdidos, 0 % de CPU en reposo), las **suites del CP2 y el CP3** (47/47 verificaciones automáticas OK) y **robustez** (Core con ID repetido, `kill -9` al Storage en plena ejecución). Ver la [[#7. Segunda batería (5 VMs)|sección 7]].
>
> **Tercera batería (06:59 → 07:51, 5 VMs, código de `main`):** búsqueda de **livelock y fugas** con los 4 módulos bajo valgrind en las 6 finales y en el CP3. **0 bytes perdidos en 104 reportes, 0 accesos inválidos, 93/93 Jobs terminados y ningún livelock.** Ver la [[#8. Tercera batería: livelock y fugas (código de main)|sección 8]].

## 1. Ambiente

| | |
| --- | --- |
| Código del TP | Rama `deploy`, commit `158dc6f` (incluye `preparar.sh`, el rechazo de Cores con ID repetido y el log del page fault) |
| Pruebas | `entrenados-pruebas` `e841d29`, configs de la cátedra sin cambios (solo las IPs) |
| Máquinas | **2 VMs** (2 CPU cada una): solo la .25 y la .26 estaban disponibles por SSH. La .27, la .28 y la .29 no respondían, y en la .18 y la .31 no hay clave |
| Reparto | **Placa en la .25** · **Storage y Planificador en la .26** · **Cores alternando**: el 1 y el 3 en la .25, el 2 y el 4 en la .26 |
| Cómo se corrió | `deploy/catedra.sh` (01, 02, 03) y las secuencias `deploy/pruebas/finales/04_storage.sh`, `05_journal.sh` y `06_estabilidad.sh`, con el reparto pisado por variables de entorno |
| `LOG_LEVEL` | INFO en todos los módulos |

Antes de correr se cortaron con SIGINT los módulos que quedaban de la práctica manual en la .25 y la .26, y se copió y compiló el código de `deploy` en las dos máquinas (los 4 módulos compilaron sin warnings).

## 2. Resumen

| Prueba | Variante | Duración | Jobs | Resultado |
| --- | --- | --- | --- | --- |
| 01 Planificación | FIFO | 1 min 8 s | 4/4 `EXIT` | ✅ |
| | RR | 1 min 8 s | 4/4 `EXIT` | ✅ |
| | HRRN | 1 min 7 s | 4/4 `EXIT` | ✅ |
| 02 Memoria | LRU | 1 min 8 s | 3/3 `EXIT` | ✅ |
| | CLOCK-M | 1 min 9 s | 3/3 `EXIT` | ✅ |
| 03 Servicios | — | 46 s | 4/4 `EXIT` | ✅ |
| 04 Storage | checkpoints + fs_lleno | 1 min 46 s | 6 Jobs: 3 `EXIT` y 3 finalizados por los errores que fuerza la prueba | ✅ |
| 05 Journal | A + B | 2 min 12 s | 4 Jobs: 2 `ERROR_STORAGE` (esperado) y 2 `EXIT` | ✅ |
| 06 Estabilidad | — | 4 min 35 s | 13/13 `EXIT` | ✅ |

## 3. Detalle por prueba

### 01 · Planificación (1 Core)

| Variante | Esperado | Obtenido |
| --- | --- | --- |
| FIFO | Con los 3 primeros `REPORT` hechos, `PLANI_LARGO` ejecuta su 2.ª ráfaga antes que los cortos | ✅ Orden de los reportes: `78` (JID 1), `02`, `06`, **`F0` (JID 1)**, `04`, `0C` |
| RR | `PLANI_LARGO` es desalojado por quantum y los cortos terminan antes | ✅ **10 desalojos** del JID 1 (15 transiciones READY→EXEC). Los JID 2 y 3 terminan primero (00:47:37 y 00:47:42) y el JID 1 al final (00:48:07) |
| HRRN | Los cortos hacen su 2.ª ráfaga antes que `PLANI_LARGO`, y las estimaciones siguen la fórmula | ✅ Reportes `78`, `02`, `06`, **`04`, `0C`**, `F0`. **28/28 estimaciones** = `0,5 · R + 0,5 · S` con `ESTIMACION_INICIAL = 1000` |
| Las tres | Mismo contenido de los reportes | ✅ JID 1: `78`/`F0` · JID 2: `02`/`04` · JID 3: `06`/`0C`. Cambia solo el orden |

En las tres variantes cada Job tuvo **un page fault** (la página de su `ALLOC`), que ahora se ve en el log del Planificador como `## (N) - Page Fault - Página: 0`. **Ya no aparece el warning del Job inicial.**

### 02 · Memoria (2 Cores)

| Esperado | LRU | CLOCK-M |
| --- | --- | --- |
| Víctimas de ambos Jobs | ✅ 16 del JID 1 y 16 del JID 2 | ✅ 18 y 17 |
| Solo bajan al Offload las víctimas modificadas | ✅ 24 bajadas en 32 reemplazos | ✅ 27 en 35 |
| Mismos reportes con los dos algoritmos | ✅ | ✅ idénticos a LRU **y a los del 24/11** |
| Jobs | 3 `EXIT` · 0 errores en 5 logs | 3 `EXIT` · 0 errores en 5 logs |

Los dos Cores atendieron a los dos Jobs. Con LRU, los números son los mismos que el 24/11. Con CLOCK-M cambian levemente (el 24/11 fueron 30 reemplazos), porque dependen de cómo se intercalan los dos Cores; lo que pide la prueba se cumple igual.

### 03 · Servicios (2 Cores)
- **Cada reporte es exactamente su lote seguido del texto ingresado:** `LOTE-1-…PERRO001`, `LOTE-2-…GATO0002` y `LOTE-3-…LORO0003`. ✅
- **El Loader siguió atendiendo mientras el Labeler esperaba:** el Loader del Job 2 empezó (00:51:48.463) antes de que el Job 1 entrara al Labeler (48.722) y terminó (52.723) después de que salió (49.456). Lo mismo con el Job 3 y el Labeler del Job 2. ✅
- Cada servicio atendió una petición por vez, en orden FIFO: 3 Loader, 3 Labeler y 3 Logger. ✅
- 4 Jobs en `EXIT`, 0 errores.

### 04 · Storage (1 Core)

| Corrida | Esperado | Obtenido |
| --- | --- | --- |
| 1 · `ST_ENTRENAR` | Un Job carga el Checkpoint que guardó otro ya finalizado | ✅ `ST_ENTRENAR` (JID 0) guarda `modelo_st` y termina. `ST_CONTINUAR` (JID 1) lo carga y termina en `EXIT`. El JID 2 también lo carga antes de borrarlo, y su reporte es idéntico al del JID 1 |
| | Eliminar uno inexistente se informa sin finalizar | ✅ Warning `El Checkpoint modelo_st no existe, no se eliminó nada (Job 2)` |
| | Cargar uno inexistente finaliza al Job | ✅ JID 2 → `CHECKPOINT_INEXISTENTE` |
| | `LS` igual después de reiniciar el Storage | ✅ `0 entradas ocupadas, 2 libres` antes y después |
| 2 · `FS_A` | Directorio lleno: se informa y se finaliza | ✅ `## ERROR - Directorio lleno al intentar guardar: ck_5` → `SIN_ESPACIO_STORAGE` |
| | Falta de espacio: se informa y se finaliza | ✅ `## ERROR - Falta de espacio en FAT al intentar guardar: ck_enorme` → `SIN_ESPACIO_STORAGE` |
| | Sobrescribir con un tamaño menor libera bloques reutilizables | ✅ `ck_grande` queda en 128 bytes y `ck_otro` (1472 bytes) entra. El reporte (`00070E15…`) es idéntico al del 24/11 |
| | `LS` igual después de reiniciar el Storage | ✅ Las mismas 4 entradas (`ck_1`, `ck_grande`, `ck_otro`, `ck_4`) antes y después |

Los dos `## ERROR` del Storage ahora salen en nivel INFO (`b93dfdd`), como pide el enunciado para los logs obligatorios.

### 05 · Journal (1 Core)

| | Caso A | Caso B |
| --- | --- | --- |
| Momento del `kill -9` | Después de `## Asiento iniciado: 2` y antes de su COMMIT | Después de `## Nueva marca en asiento: 2: - COMMIT` y antes de su APPLIED |
| Recuperación | Asientos 1 y 2: `DESCARTADO` | Asiento 1: `DESCARTADO` · asiento 2: **`APLICADO`** |
| `LS` / `CAT modelo 16` | `modelo` de 256 bytes, `V1-BLOQUE-00-111` (versión anterior), igual después de reiniciar | `modelo` de 512 bytes, `V2-BLOQUE-00-222` (versión nueva), igual después de reiniciar |
| `JOURNAL_VERIFICAR_*` | `56312D…313131` + `3131…31` = versión anterior ✅ | `56322D…323232` + `3232…32` = versión nueva completa ✅ |

En los dos casos, el Job de la primera corrida termina con `ERROR_STORAGE` (se mató al Storage en medio de su pedido) y el de verificación con `EXIT`. En esta corrida no se repitió la revisión byte a byte de bloques huérfanos del 24/11 (había dado 0).

### 06 · Estabilidad General (hasta 4 Cores · HRRN + CLOCK-M)

| Actividad (documento) | Cuándo | Resultado |
| --- | --- | --- |
| Arrancar con los Cores 1 y 2 | 00:56:26 / 00:56:27 | ✅ |
| Conectar un Core con Jobs en READY | Core 3, 00:56:33 | ✅ |
| Finalizar un Core mientras ejecuta FORWARD o BACKWARD | Core 1, cortado **en la línea** `## JID: 3 - Ejecutando: FORWARD - P1 P2 P3 AX` (00:56:44) | ✅ El Planificador: `El Core 1 se desconectó ejecutando el Job 3` → `## (3) - Deslockeo de páginas` → EXEC→READY. El Job 3 terminó en `EXIT` a las 00:58:04 en otro Core |
| Volver a conectar el Core finalizado | Core 1, 00:56:54 (mismo ID, aceptado) | ✅ |
| Conectar otro Core | Core 4, 00:57:05 | ✅ |
| Al final: `INFO` en la Placa y `LS` en el Storage | | ✅ Placa: memoria 0 %, Offload 0 %, **64 frames libres, 0 lockeados, 0 Jobs**. Storage: 6 checkpoints `est_*` |

- **13/13 Jobs en `EXIT`**. 0 errores en los 7 logs; el único warning es el de la desconexión del Core 1, que es parte de la prueba.
- Los 4 Cores atendieron entre 9 y 10 Jobs distintos cada uno.
- **HRRN: 670/670 estimaciones** coinciden con `0,5 · R + 0,5 · S` (`ESTIMACION_INICIAL = 500`).
- Memoria: 566 subidas, 354 reemplazos con víctimas de los 12 Jobs, y 225 bajadas al Offload.

## 4. Práctica manual (27 y 28/11)
Además del runner, se corrió a mano como en el laboratorio, con `./preparar.sh` en cada VM (ver [[Laboratorio manual 2026-11-27]]):

| Prueba | Reparto | Resultado |
| --- | --- | --- |
| 01 FIFO | Planificador .31 · Placa .18 · Storage .26 · Core 1 en la .25 | ✅ 4/4 `EXIT` |
| 01 RR | El mismo, con 2 Cores en la .25 | ✅ El Job largo con 14 transiciones READY→EXEC (desalojado por quantum) y `EXIT` |

## 5. Comparación con el 24/11

| | 24/11 | 28/11 |
| --- | --- | --- |
| Código | `develop` (`ea9ea8b`) | `deploy` (`158dc6f`) |
| Máquinas | 5 | 2 |
| Resultado | 6/6 ✅ | 6/6 ✅ |
| Reportes 01, 02, 03 y 04 | — | Mismo contenido |
| Journal (05) | A descarta, B re-aplica | Igual |
| Estabilidad (06) | 13/13 `EXIT` | 13/13 `EXIT` |
| Warning del Job inicial | Aparecía en todas las corridas | Ya no aparece |
| Log de page fault en el Planificador | No había | `## (N) - Page Fault - Página: P` |

**Diferencias esperables:** la cantidad de desalojos en RR (13 → 10) y de reemplazos en CLOCK-M (30 → 35). Dependen de cuánto tarda cada mensaje entre máquinas y de cómo se intercalan los Cores. Lo que verifica cada prueba (quién termina primero, víctimas de ambos Jobs, bajadas solo de modificadas, contenido de los reportes) es igual.

## 6. Observaciones
- **Recursos:** en la primera batería no se repitió valgrind; se hizo en la segunda (sección 7 C), con 0 fugas y 0 % de CPU en reposo.
- **Al loguearse en la .26, el shell imprime la salida de `ifconfig`** (lo agrega el `.bashrc` de esa VM). Aparece en las salidas de consola de los módulos pero no afecta nada.
- **En el laboratorio**, las pruebas se corren a mano; este informe usa el runner para cubrir las 10 corridas con los mismos criterios. El modo manual ya se validó con la 01 (sección 4).

## 7. Segunda batería (5 VMs)
Con las 5 VMs disponibles (.25 a .29) y el código de `deploy` en `10c5c86`, desplegado y compilado en las cinco. Para cada fase se verificaron los criterios del documento con un script (orden de los reportes, desalojos, víctimas y bajadas, lote + texto, `LS` antes y después de reiniciar, `CAT` de la 05, corte de Core en la 06).

### A · Las 6 finales con 5 máquinas
Placa en la .25, Storage en la .26, Planificador en la .27, Cores 1 y 3 en la .28, Cores 2 y 4 en la .29.

| Prueba | Resultado |
| --- | --- |
| 01 FIFO / RR / HRRN | ✅ Orden esperado en las tres · RR: 10 desalojos, los cortos terminan antes · HRRN: 28/28 estimaciones |
| 02 LRU / CLOCK-M | ✅ Víctimas de los dos Jobs · 24 bajadas en 32 reemplazos y 27 en 35 · reportes idénticos al 24/11 |
| 03 | ✅ Lote + texto en los 3 reportes · Loader concurrente con el Labeler |
| 04 checkpoints / fs_lleno | ✅ `LS` igual antes y después del reinicio (0 y 4 entradas) · motivos esperados |
| 05 A / B | ✅ Asiento 2 `DESCARTADO` / `APLICADO` · `modelo` de 256 / 512 B · `CAT` con la versión anterior / nueva |
| 06 | ✅ 13/13 `EXIT` · Core 1 cortado con deslockeo · `INFO` final: 0 lockeados, 0 Jobs · HRRN 675/675 |

**11/11 criterios OK.** Además, el volumen de la 05 revisado byte a byte (superbloque, FAT y directorio): **0 bloques huérfanos** y cadenas del tamaño correcto (A: 4 bloques; B: 8 bloques).

### B · Las 6 finales con todo en una sola máquina (.27)
Los 4 módulos y los 4 Cores en la misma VM de 2 CPU: el otro extremo del reparto.

**11/11 criterios OK**, con los mismos resultados que en la fase A: RR con 10 desalojos, CLOCK-M con 28 bajadas en 37 reemplazos y la 06 con 13/13 `EXIT` y 705/705 estimaciones HRRN. El volumen de la 05 también da 0 huérfanos.

### C · Esperas activas y memory leaks
`verificar_recursos.sh`: la 06 completa con los 4 módulos bajo valgrind (`--leak-check=full`) y las mismas actividades de Cores, más la medición de CPU.

| | Placa | Planificador | Storage | Cores (5 procesos) |
| --- | --- | --- | --- | --- |
| Fugas confirmadas (definitely + indirectly) | 0 | 0 | 0 | 0 |
| Accesos inválidos o sin inicializar | 0 | 0 | 0 | 0 |
| Possibly lost | 7 × 272 B | 7 errores | 2 errores | 1 × 272 B cada uno |
| CPU en reposo (20 s) | 0,0 % | 0,0 % | 0,0 % | 0,0 % |
| CPU con el Labeler esperando teclado (03) | 0,0 % | 0,0 % | 0,0 % | 0,0 % |

- Las "possibly lost" son las estructuras de 272 B de hilos que siguen vivos cuando el proceso termina por la señal. En los Cores aparece una desde que se agregó el hilo de cierre (`9793672`); el 24/11 los Cores daban 0.
- Bajo valgrind, la 06 terminó igual con 13/13 `EXIT`.

### D · Regresión con las suites de los checkpoints
| Suite | Verificación automática |
| --- | --- |
| CP3 (`checkpoint_3 todos`) | ✅ **19/19 OK** en los escenarios 01 a 09; el 10 y el 11 (consola del Storage) con 0 errores |
| CP2 (`checkpoint_2 todos --rapido`) | ✅ **28/28 OK**: 01_instrucciones 9/9, 02 3/3, 03 4/4, 04 4/4, 05 grado 1 y 2 4/4 |

### E · Robustez (escenario 06, 5 máquinas)
| Caso | Qué se hizo | Resultado |
| --- | --- | --- |
| Core con ID repetido | Con el Core 1 conectado, se lanzó otro Core con ID 1 desde la .29 | ✅ Planificador: `Ya hay un Core conectado con el ID 1: se rechaza la conexión nueva`. El Core nuevo terminó con `Handshake rechazado`; el original siguió ejecutando |
| `kill -9` al Storage en plena ejecución | Apenas llegó el primer `Solicitud Guardar Checkpoint` | ✅ El Planificador no se colgó: 6 Jobs terminaron con `ERROR_STORAGE` (sus checkpoints fallaron) y 2 con `EXIT`. Todos los Jobs creados finalizaron |
| Storage levantado de nuevo | Con el mismo volumen | ✅ Recuperación: asientos 1 y 2 `DESCARTADO` (no tenían COMMIT) |
| Estado final | `INFO` en la Placa | ✅ Memoria 0 %, **0 frames lockeados**, 0 Jobs: ninguna falla dejó páginas lockeadas |

- Se crearon 8 Jobs en lugar de 13, porque los que terminaron en `ERROR_STORAGE` ya no crearon los suyos.
- Como el Planificador no se reconecta al Storage (límite conocido), los checkpoints posteriores al reinicio también fallan.

**Observación:** el Core abre las conexiones al Planificador y a la Placa **antes** de hacer los handshakes. Cuando el Planificador rechaza un ID repetido, el Core termina con la conexión a la Placa abierta y sin handshake. La Placa loguea `No se pudo recibir el handshake` y descarta la conexión. No afecta a nada. Se podría mejorar haciendo el handshake con el Planificador antes de conectarse a la Placa.

## 8. Tercera batería: livelock y fugas (código de main)
Corrida después del merge de `deploy` a `main` (PR #25), con el mismo código (`b65d18a`), un módulo por VM (Placa .25, Storage .26, Planificador .27, Cores .28 y .29). Duró **52 minutos** (06:59 → 07:51) y todas las corridas terminaron con código 0.

| Fase | Qué se corrió | Resultado |
| --- | --- | --- |
| V | Las 6 finales (9 corridas: 01 FIFO/RR/HRRN, 02 LRU/CLOCK-M, 03, 04 checkpoints y fs_lleno, 05 A y B) con **los 4 módulos bajo valgrind** | ✅ Todos los Jobs con el motivo esperado. 05: asiento 2 `DESCARTADO` en A y `APLICADO` en B |
| R | La 06 bajo valgrind (entra el Core 3, se corta el 1 durante `FORWARD`/`BACKWARD`, vuelve y entra el 4) y CPU | ✅ 13/13 Jobs, 0 frames lockeados, **0,0 % de CPU** en reposo y con el Labeler esperando teclado |
| L | Suite del CP3 con valgrind y del CP2 (`--rapido`) | ✅ CP3 **19/19** y CP2 **28/28** |

En la 05 el Storage de la primera corrida no va bajo valgrind: la acción `matar` busca el binario al principio de la línea de comando y un proceso muerto con `kill -9` no deja reporte. Los reinicios del Storage sí corren bajo valgrind.

### Fugas de memoria
- **104 reportes de valgrind**: `definitely lost` e `indirectly lost` en **0 bytes** en todos.
- **0 accesos inválidos** (lecturas o escrituras inválidas, memoria sin inicializar, parámetros de syscalls).
- Todo el `possibly lost` está en bloques de **exactamente 272 B**, el bloque TLS que reserva glibc en cada `pthread_create`. Son hilos todavía vivos cuando el Ctrl-C corta el proceso; no son fugas del TP. Se verificó en cada reporte (bytes = 272 × bloques).

### Livelock
El livelock conocido ([[Bugs encontrados#Livelock con rangos más grandes que la memoria|límite documentado]]) es un Job que reintenta la misma instrucción para siempre: page fault → carga → page fault. Se buscó en los logs con tres señales:

| Señal | Cómo se mide | Resultado |
| --- | --- | --- |
| Jobs que no terminan | Jobs creados contra `finalizó su ejecución` | **93/93** terminados |
| Re-subida en una misma instrucción | En la Placa, dentro de una racha de fetch del mismo PC, la misma página subida dos veces o más | Solo 1 o 2 veces seguidas (06 y 02 CLOCK-M): otro Job desaloja la página entre el page fault y el reintento, y después la instrucción termina. La alerta (3 o más) no saltó nunca |
| Espera activa | CPU de cada proceso en reposo y con Jobs bloqueados | 0,0 % en todos |

La racha más larga de reintentos es de 26 fetch seguidos, un `LOAD_BATCH` de 1600 bytes en fs_lleno: se reintenta una vez por cada página del rango que falta y termina.

**Observación para el coloquio:** en la recuperación, un asiento que ya tenía `APPLIED` se loguea `DESCARTADO`. El enunciado solo define `APLICADO / DESCARTADO`, y todo lo que no se vuelve a aplicar se informa como `DESCARTADO` (ver [[Storage]]).

## 9. Conclusión
El TP (rama `deploy`, mergeada a `main`) cumple **las 6 pruebas finales** del documento de la cátedra:
- distribuido en **5 máquinas**, en **2** y en **1**;
- con Cores que entran, salen y se rechazan si repiten el ID;
- sin fugas de memoria ni esperas activas;
- sin regresiones en las suites del CP2 y el CP3;
- sin livelock en ninguna de las pruebas (93/93 Jobs terminados);
- sin colgarse ante la caída del Storage.

`deploy` ya está en `main` (PR #25): la entrega se clona de `main`.

Resultados completos en `tp-2026-2c-requiemso/deploy/resultados/catedra-entregas_finales-*-20261128-*` (no se versionan).
