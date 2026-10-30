---
tags: [tp-so, entrenados, plan]
actualizado: 2026-10-29
proximo_hito: Check 3 (31/10)
---

# Plan de acción

Volver a [[00 - Inicio]] · Ver también [[Estado de ramas]], [[Protocolo]]

> [!danger] Situación al 29/10
> Faltan **2 días para el Check 3**. [[Core]] y [[Placa]] ya tienen lo suyo en sus ramas, pero sin mergear. El [[Planificador]] es el cuello de botella: ningún Job pasa a BLOCKED y responde "no soportado" a todas las syscalls salvo `INIT_JOB` y `EXIT`.

Roles (de `doc/distribucion-equipo.md`):
- **D1**: Planificador, planificación
- **D2**: Planificador, syscalls y servicios
- **D3**: Placa
- **D4**: Storage
- **D5**: Core y transversales

---

## Fase A: Integración (hoy, bloqueante)
Responsable: todos / D5

- [ ] Mergear `origin/placa` → `develop`
- [ ] Mergear `origin/core` → `develop`, resolviendo el conflicto de `protocolo_entrenados.h` (ver [[Estado de ramas]], sección del conflicto)
- [ ] Mergear `origin/storage` → `develop`
- [ ] `make` en los 5 módulos sin warnings
- [ ] Repetir la prueba del Check 2 (FIFO/RR/HRRN con NOOP/SET/SUM/SUB/JNZ) para descartar regresiones
- [ ] Actualizar la tabla §5.1 de `doc/planificador.md` con los payloads reales (ver [[Protocolo#Payloads Core → Planificador]])

## Fase B: Planificador, page fault y BLOCKED (Check 3)
Responsable: D1 · Archivos: `planificador/src/comunicacion.c`, `planificacion.c`

- [ ] Agregar en `planificacion.c` las funciones `bloquear_proceso(proceso)` (EXEC→BLOCKED con log de cambio de estado) y `desbloquear_proceso(proceso)` (BLOCKED→READY + `sem_post(sem_ready)`)
- [x] Recalcular la estimación HRRN al salir de EXEC: `cambiar_estado` ya lo hace para cualquier destino, BLOCKED incluido
- [ ] En `recibir_devolucion`, sumar el `case DEVOLUCION_PAGE_FAULT`:
  - leer el `uint32 nro_pagina` que viene después del contexto
  - `cantidad_page_faults++` y luego BLOCKED
  - `OP_CARGA_PAGINA {jid, nro_pagina}` a Placa (bajo `mutex_placa`) y esperar `OP_RSP_CARGA_PAGINA {ok}`
  - si da ok → READY; si da error → `finalizar_proceso(…, "ERROR_PAGINACION")`
  - La carga **no** puede bloquear el hilo del Core: hacerla en un hilo aparte o en una cola de "pedidos a Placa"
- [ ] Desconexión de Core con un Job en EXEC: además de volver a READY, mandar `OP_DESLOCKEO_PAGINAS {jid}`

## Fase C: Planificador, syscalls no bloqueantes (Check 3)
Responsable: D2

El Core espera `OP_RSP_SYSCALL {bool ok, uint32 valor}`:

- [ ] **[Core, D5]** En `origin/core`, agregar los `case INST_ALLOC` / `INST_FREE` en `ejecutar_instruccion`, usando `solicitar_syscall_con_parametro` (hoy caen en "Instrucción no reconocida"). Ver [[Core]]
- [ ] `SYSCALL_ALLOC`, parámetro `uint32 tamaño` → `OP_ASIGNAR_ESPACIO {jid, tamaño}` → `OP_RSP_ASIGNAR {ok, dir_logica}`
  - responder `valor = dir_logica`
  - mantener la memoria dinámica actual y actualizar `memoria_dinamica_maxima`
  - sin espacio → finalizar el Job (sin responder `ok=true`)
- [ ] `SYSCALL_FREE`, parámetro `uint32 dir_logica` → `OP_LIBERAR_ESPACIO {jid, dir}` → `OP_RSP_LIBERAR {ok}`
- [ ] Agregar a `t_proceso` la memoria dinámica actual y un mapa `dir → tamaño` para poder descontar en el FREE
- [ ] Log `## (<JID>) - Solicitó syscall: <NOMBRE>` en todas (verificar que `registrar_syscall` lo emite)

## Fase D: Planificador, servicios bloqueantes (Check 3)
Responsable: D2

En las syscalls bloqueantes **el Core no espera respuesta**: suelta el Job. Al recibirlas hay que llamar a `liberar_core` y pasar el Job a BLOCKED.

Payload: `{id, jid, contexto, [string nombre], uint32 tamaño, uint32 cant_tramos, (uint32 dir_fisica, uint32 tam) × cant_tramos}`

- [ ] Parser común `leer_tramos(buffer) → t_list*` de `{dir_fisica, tam}`
- [ ] Un hilo + cola FIFO + semáforo + mutex por servicio
- [ ] **Loader** (`LOAD_BATCH`, con `nombre` de archivo):
  - leer `tamaño` bytes de `PATH_DATOS/<archivo>`
  - `usleep(RETARDO_LOADER)`
  - `OP_ESCRIBIR_DATOS` por tramo, con log de acceso
  - deslockeo → READY
- [ ] **Labeler** (`LABEL`, sin nombre):
  - log `Ingrese <N> caracteres:`
  - `fgets` de stdin (solo este hilo toca stdin)
  - escribir por tramos → deslockeo → READY
- [ ] **Logger** (`REPORT`, sin nombre):
  - `OP_LEER_DATOS` por tramo
  - pasar a hex ASCII
  - append en `PATH_REPORTES` con formato `## (<JID>) - <HEX>`
  - deslockeo → READY
- [ ] Logs `## (<JID>) inicia <SERVICIO>` y `## (<JID>) finalizó <SERVICIO> y pasa a READY`
- [ ] Cualquier camino de error en un servicio debe **deslockear o finalizar** el Job, nunca dejar páginas lockeadas

> [!tip] Concurrencia con la Placa
> Hoy hay un solo `socket_placa` protegido por `mutex_placa`. Cada pedido y su respuesta tienen que hacerse dentro del mismo lock, como ya hacen `avisar_creacion_a_placa` y `avisar_finalizacion_a_placa`. Conviene un helper `pedir_a_placa(op, buffer, op_rsp_esperado, &respuesta)`.

## Fase E: Validación del Check 3
Responsable: todos

- [ ] Script *Mini Entrenamiento*: `ALLOC` + `LOAD_BATCH` + `FORWARD/BACKWARD/UPDATE` + `REPORT`
- [ ] Revisar en los logs: page faults en varias páginas, Jobs que pasan por BLOCKED, reportes hex correctos
- [ ] Correr con `valgrind --leak-check=full` en Planificador y Placa
- [ ] Probar con LRU y con CLOCK-M en la Placa, y con FIFO, RR y HRRN en el Planificador

---

## Fase F: Checkpoints (Check 4 · 14/11)

### Storage (D4)
- [ ] Implementar en `operaciones.c` las operaciones `GUARDAR`, `CARGAR` y `ELIMINAR_CHECKPOINT` sobre la FAT. Hoy responden `responder_no_implementado`.
  - Reutilizar la lógica de `consola.c` (WRITE/CAT/RM) moviéndola a `filesystem.c`
- [ ] Journaling y recuperación ante `kill -9`
- [ ] Respetar `RETARDO_ACCESO_BLOQUE` y `RETARDO_COMMIT`

### Planificador (D2)
- [ ] `SAVE_CHECKPOINT`:
  - BLOCKED → `LEER_DATOS` por tramos → `OP_GUARDAR_CHECKPOINT {nombre, contenido}`
  - sin espacio → finalizar
  - ok → deslockeo → READY
- [ ] `LOAD_CHECKPOINT`:
  - BLOCKED → `OP_CARGAR_CHECKPOINT {nombre}`
  - no existe → finalizar
  - ok → `ESCRIBIR_DATOS` → deslockeo → READY
- [ ] `DELETE_CHECKPOINT`:
  - BLOCKED → `OP_ELIMINAR_CHECKPOINT {nombre}`
  - si no existe, **solo loguear**
  - sin deslockeo → READY
- [ ] Si se cae Storage: log y finalización limpia, sin colgarse

## Fase G: Cierre (28/11 → 19/12)
- [ ] Estadísticas completas en el log de fin de Job (ya hay una base en `t_proceso`)
- [ ] `SIGINT`/`SIGTERM` con cierre ordenado en los 4 módulos
- [ ] Helgrind/DRD en pruebas de stress
- [ ] Scripts de deploy y configs por máquina
- [ ] Cada integrante debe poder explicar cualquier módulo en el coloquio

## Checklist de logs obligatorios del Planificador
| Log | Estado |
| --- | --- |
| `## Módulo: <NOMBRE>` | ✅ |
| `## (<JID>) Se crea el Job - Estado: NEW` | ✅ |
| `## (<JID>) Pasa del estado <A> al estado <B>` | ✅ (falta el camino a BLOCKED) |
| `## (<JID>) - Desalojado por fin de quantum` | ✅ |
| `## (<JID>) - Prioridad HRRN calculada: … - Estimación próxima ráfaga: …` | ✅ |
| `## (<JID>) - Solicitó syscall: <NOMBRE>` | ✅ (verificar) |
| `## (<JID>) inicia <SERVICIO>` / `finalizó <SERVICIO> y pasa a READY` | ❌ Fase D |
| `## (<JID>) - <Lectura/Escritura> - Dirección Física: … - Tamaño: …` | ❌ Fase D |
| `## (<JID>) - Deslockeo de páginas` | ❌ Fases B a D |
| `## (<JID>) - Ingrese <N> caracteres:` | ❌ Fase D |
| `## (<JID>) - <CONTENIDO>` (reportes) | ❌ Fase D |
| `## (<JID>) finalizó su ejecución con motivo de <M>. Estadísticas: …` | ✅ (completar campos) |
