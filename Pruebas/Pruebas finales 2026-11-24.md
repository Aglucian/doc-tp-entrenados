---
tags: [tp-so, entrenados, pruebas, entregas-finales]
fecha: 2026-11-24
rama: develop (ea9ea8b, runner 6e367d1)
repo_pruebas: sisoputnfrba/entrenados-pruebas (e841d29)
resultado: ok
---

# Pruebas finales: 24/11/2026

Volver a [[00 - Inicio]] · Ver [[Despliegue distribuido]], [[Plan de acción]] · Anteriores: [[Suite cátedra 2026-11-14]], [[Check 4 2026-11-14]]

El **22/11** la cátedra publicó en `entrenados-pruebas/entregas_finales/` las 6 pruebas de las entregas finales (28/11, 12/12 y 19/12), junto con el **Documento de Pruebas Finales v1.0** (Google Doc, enlazado desde `faq.utnso.com.ar/entrenados-pruebas`). Las corrimos completas en los **5 servidores**, con el código de `develop` (`ea9ea8b`, que incluye la consola de la Placa del #24).

> [!success] Resultado
> **Las 6 pruebas pasan.** Cada resultado esperado del documento se verificó contra los logs, los reportes o el volumen del Storage.
> Lo único sin verificar: "no hay esperas activas ni memory leaks" del 06 (ver [[#Pendiente]]).

## Reglas de la evaluación (del documento)
- El TP tiene que correr **en varias máquinas**: si no, no se evalúa. Hay **10 minutos** para armar el ambiente.
- Hay una sola instancia por fecha: un error que no se pueda resolver en el momento desaprueba esa entrega.
- `LOG_LEVEL` **siempre en INFO**.
- Salvo que la prueba diga otra cosa, cada una arranca con un Storage vacío y un Offload nuevo.
- Las claves propias del grupo se agregan a las configs provistas y no deben alterar el resultado (por ejemplo, `SINCRONIZAR_APLICACION`).
- **Prohibido subir binarios o ejecutables al repo.** Verificamos que no hay ninguno: los únicos archivos binarios versionados son 3 archivos de datos de prueba.
- "Un resultado que difiera de lo esperado, aunque el sistema no falle, será considerado un error."

## Cómo se corren
```bash
deploy/catedra.sh entregas_finales 01_planificacion/FIFO     # también RR y HRRN
deploy/catedra.sh entregas_finales 02_memoria/LRU            # también CLOCK-M
deploy/catedra.sh entregas_finales 03_servicios
deploy/pruebas/finales/04_storage.sh
deploy/pruebas/finales/05_journal.sh
deploy/pruebas/finales/06_estabilidad.sh
```

- El 03 responde solo al Labeler (`PERRO001`, `GATO0002`, `LORO0003`), en orden y después de que el Loader atienda a otro Job (`catedra_entradas.conf`).
- El 04, el 05 y el 06 son secuencias que usan las acciones de `catedra.sh` (`--solo-iniciar`, `--accion esperar-log|matar|parar|levantar|consola|cortar-durante|esperar-fin|detener|resultados`). Ver [[Despliegue distribuido]].
- Los resultados quedan en `deploy/resultados/catedra-entregas_finales-*`.

## 01 · Planificación (1 Core)
| Variante | Esperado (documento) | Obtenido |
| --- | --- | --- |
| FIFO | Con los 3 primeros REPORT hechos, PLANI_LARGO ejecuta su 2.ª ráfaga antes que los cortos | ✅ el JID 1 reporta `F0000000` antes de la segunda ráfaga de los cortos |
| RR | PLANI_LARGO es desalojado por quantum y los cortos terminan antes | ✅ **13 desalojos** del JID 1; los JID 2 y 3 terminan primero |
| HRRN | Los cortos hacen su 2.ª ráfaga antes que PLANI_LARGO **aunque él volvió antes a READY**; estimaciones según la fórmula | ✅ el JID 1 volvió a READY a las 20:04:30.992, antes que los cortos (34.031 y 37.157), y ejecutó después. **28/28 estimaciones** = `0,5·R + 0,5·S` con `ESTIMACION_INICIAL=1000` |
| Las tres | Mismo contenido de los reportes | ✅ JID 1: `78`/`F0`, JID 2: `02`/`04`, JID 3: `06`/`0C`. Cambia solo el orden |

Duración: unos 85 s por variante.

## 02 · Memoria (2 Cores)
| Esperado | LRU | CLOCK-M |
| --- | --- | --- |
| Víctimas de ambos Jobs | ✅ 16 del JID 1 y 16 del JID 2 | ✅ 15 y 15 |
| Solo bajan al Offload las víctimas modificadas | ✅ 24 bajadas en 32 reemplazos | ✅ 22 en 30 |
| Mismos reportes con los dos algoritmos | ✅ (hash idéntico) | ✅ |
| Jobs | 3 `EXIT`, 0 errores | 3 `EXIT`, 0 errores |

## 03 · Servicios (2 Cores)
- **Cada reporte es exactamente su lote seguido del texto ingresado** (104 bytes): `LOTE-1-…PERRO001`, `LOTE-2-…GATO0002`, `LOTE-3-…LORO0003`. ✅
- **Mientras el Labeler esperaba, el Loader siguió atendiendo:** el Loader del Job 2 empezó antes de que el Job 1 entrara al Labeler y terminó después de que salió. Lo mismo con el Job 3 mientras el Job 2 estaba en el Labeler. ✅
- Cada servicio atiende una petición por vez, en orden FIFO, y ningún Job vuelve a READY antes de terminar su servicio. ✅

## 04 · Storage (1 Core)
| Corrida | Esperado | Obtenido |
| --- | --- | --- |
| 1 · `ST_ENTRENAR` | Un Job carga el Checkpoint que guardó otro ya finalizado | ✅ `ST_CONTINUAR` carga `modelo_st` y termina con `EXIT` |
| | Eliminar uno inexistente se informa sin finalizar | ✅ el 2.º `DELETE modelo_st` de `ST_LIMPIEZA` solo deja un warning |
| | Cargar uno inexistente finaliza al Job | ✅ `CHECKPOINT_INEXISTENTE` |
| 2 · `FS_A` | Directorio lleno: se informa y se finaliza | ✅ `## ERROR - Directorio lleno al intentar guardar: ck_5` → `SIN_ESPACIO_STORAGE` |
| | Falta de espacio: se informa y se finaliza | ✅ `## ERROR - Falta de espacio en FAT al intentar guardar: ck_enorme` → `SIN_ESPACIO_STORAGE` |
| | Sobrescribir con un tamaño menor libera bloques reutilizables | ✅ `ck_grande` pasa a 128 bytes y `ck_otro` (1472 bytes) entra en los bloques liberados; su reporte = `FS_1600.bin` |
| Las dos | `LS` igual después de reiniciar el Storage | ✅ idéntico (4 entradas en la corrida 2; 0 en la 1, porque `ST_LIMPIEZA` borra todo) |

> [!note] Mismo motivo para los dos errores
> El Planificador finaliza con `SIN_ESPACIO_STORAGE` tanto por directorio lleno como por falta de espacio, porque el protocolo solo devuelve `ok=false`. El Storage sí loguea los dos errores por separado, que es lo que pide el documento ("se informan"). Si se quiere distinguirlos también en el motivo del Job, habría que agregar un código de error a `OP_RSP_GUARDAR_CHECKPOINT`.

## 05 · Journal (1 Core)
| | Caso A | Caso B |
| --- | --- | --- |
| Momento del `kill -9` | Después de `## Asiento iniciado: 2` y antes de su COMMIT (`RETARDO_COMMIT=10000`) | Después de `## Nueva marca en asiento: 2: - COMMIT` y antes de su APPLIED |
| Recuperación | Asientos 1 y 2: `DESCARTADO` | Asiento 1: `DESCARTADO` · asiento 2: **`APLICADO`** (8,6 s por `RETARDO_ACCESO_BLOQUE=500`) |
| `LS` / `CAT modelo 16` | `modelo` de 256 bytes, `V1-BLOQUE-00-111`; igual después de reiniciar | `modelo` de 512 bytes, `V2-BLOQUE-00-222`; igual después de reiniciar |
| Volumen (revisado byte a byte) | 4 bloques ocupados, todos en la cadena, **0 huérfanos** | 8 bloques ocupados, **0 huérfanos** |
| `JOURNAL_VERIFICAR_*` | `56312D…313131` + `3131…31` = versión anterior ✅ | `56322D…323232` + `3232…32` = versión nueva completa ✅ |

El Job de la primera corrida termina con `ERROR_STORAGE`, como corresponde (se murió el Storage en medio de su pedido). El de verificación termina con `EXIT`.

## 06 · Estabilidad General (hasta 4 Cores)
Placa en .25, Storage en .26, Planificador en .27, Cores 1 y 3 en .28, Cores 2 y 4 en .29. HRRN + CLOCK-M.

| Actividad (documento) | Cómo se hizo | Resultado |
| --- | --- | --- |
| Conectar un Core con Jobs en READY | Core 3, apenas hubo Jobs en READY | ✅ |
| Finalizar un Core mientras ejecuta FORWARD o BACKWARD | Core 1, cortado **en la línea** `## JID: 4 - Ejecutando: FORWARD - P1 P2 P3 AX` | ✅ el Planificador: `El Core 1 se desconectó ejecutando el Job 4` → **deslockeo** → EXEC→READY. El Job 4 terminó después en otro Core |
| Volver a conectar un Core finalizado | Core 1 de nuevo | ✅ |
| Conectar otro Core | Core 4 | ✅ |
| Al final: `INFO` en la Placa y `LS` en el Storage | | ✅ Placa: memoria ocupada 0 %, Offload 0 %, **0 frames lockeados, 0 Jobs**. Storage: los checkpoints `est_*` |

**13/13 Jobs con `EXIT`**, 0 errores en los 8 logs. Cada Core atendió entre 9 y 12 Jobs distintos.

## Lo que hubo que cambiar en el runner
- Suite `entregas_finales` con variantes por carpeta y configs de los Cores compartidas, y el Job inicial sin comillas.
- Labeler con textos en orden (`*`) y espera `L<n>`.
- Dos errores del runner que aparecieron en el 03 y quedaron corregidos:
  - un `read` sin resultado cortaba el script por `set -e`
  - la condición del Loader esperaba un inicio *nuevo* y quedaba esperando para siempre cuando el Loader ya estaba atendiendo a otro Job
- Ninguna prueba requirió cambios en los módulos del TP.

## Pendiente
- [ ] **06: "no hay esperas activas ni memory leaks"**. Correr la prueba con valgrind en el Planificador y la Placa, y medir el uso de CPU de los módulos mientras esperan (por ejemplo, con el Labeler pendiente).
- [ ] Practicar el armado en el laboratorio en menos de 10 minutos: clonar, compilar e instalar la commons, y adaptar las IPs (`catedra.conf` / `desplegar.sh preparar`).
- [ ] Opcional: distinguir en el motivo del Job "directorio lleno" de "falta de espacio" (hoy los dos son `SIN_ESPACIO_STORAGE`).
