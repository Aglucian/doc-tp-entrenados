---
tags: [tp-so, entrenados, plan]
actualizado: 2026-10-30
proximo_hito: Check 3 (31/10)
---

# Plan de acción

Volver a [[00 - Inicio]] · Ver también [[Estado de ramas]], [[Protocolo]]

> [!warning] Situación al 30/10
> El [[Planificador]] tiene **todo lo del Check 3**: page fault/BLOCKED, ALLOC/FREE, los 3 servicios y el deslockeo al caerse un Core. Está en la rama `planificador` (4 commits, pusheada) y probado contra módulos simulados.
> Lo que bloquea la prueba real:
> - mergear los PRs de [[Core]] (#12) y [[Placa]] (#14) a `develop`
> - conectar `ALLOC`/`FREE` en el Core
> - después, traer `develop` a `planificador` y abrir su PR

Roles (de `doc/distribucion-equipo.md`):
- **D1**: Planificador, planificación
- **D2**: Planificador, syscalls y servicios
- **D3**: Placa
- **D4**: Storage
- **D5**: Core y transversales

---

## Fase A: Integración (bloqueante para probar el Check 3)
Responsable: todos / D5

- [ ] Mergear `origin/placa` → `develop` (PR #14)
- [ ] Mergear `origin/core` → `develop` (PR #12), resolviendo el conflicto de `protocolo_entrenados.h` (ver [[Estado de ramas]], sección del conflicto)
- [x] Mergear `origin/storage` → `develop` (`764b9c3`)
- [ ] `make` en los 5 módulos sin warnings
- [ ] Traer `develop` a `planificador` y abrir el PR `planificador` → `develop`
- [ ] Repetir la prueba del Check 2 (FIFO/RR/HRRN con NOOP/SET/SUM/SUB/JNZ) para descartar regresiones
- [ ] Actualizar la tabla §5.1 de `doc/planificador.md` con los payloads reales (ver [[Protocolo#Payloads Core → Planificador]])

## Fase B: Planificador, page fault y BLOCKED (Check 3) ✅
Responsable: D1 · Commits `0871672`, `169c8a8`

- [x] `bloquear_proceso` / `desbloquear_proceso` en `planificacion.c`
- [x] Recalcular la estimación HRRN al salir de EXEC: `cambiar_estado` ya lo hace para cualquier destino, BLOCKED incluido
- [x] `case DEVOLUCION_PAGE_FAULT` en `recibir_devolucion`:
  - lee el `nro_pagina` y hace `cantidad_page_faults++`
  - pasa a BLOCKED y lanza el hilo `resolver_page_fault`
  - pide `OP_CARGA_PAGINA`; si da ok → READY, si da error → `ERROR_PAGE_FAULT`
- [x] Helper `pedir_a_placa` / `pedir_confirmacion_a_placa`: pedido y respuesta bajo `mutex_placa`
- [x] Desconexión de un Core con un Job en EXEC: `OP_DESLOCKEO_PAGINAS {jid}` → READY

## Fase C: Planificador, syscalls no bloqueantes (Check 3) ✅
Responsable: D2 · Commit `e5fd060`

El Core espera `OP_RSP_SYSCALL {bool ok, uint32 valor}`:

- [ ] **[Core, D5]** En `origin/core`, agregar los `case INST_ALLOC` / `INST_FREE` en `ejecutar_instruccion`, usando `solicitar_syscall_con_parametro` (hoy caen en "Instrucción no reconocida"). Ver [[Core]]
  - Contrato: si `ALLOC` responde `ok=false`, el Job **ya fue finalizado** → el Core lo abandona sin `OP_DEVOLUCION`
- [x] `SYSCALL_ALLOC` → `OP_ASIGNAR_ESPACIO` → responde la dirección lógica. Sin espacio: `{false}` y finaliza con `OUT_OF_MEMORY`
- [x] `SYSCALL_FREE` → `OP_LIBERAR_ESPACIO`. Dirección inválida: `{false}` y el Job sigue
- [x] `t_proceso` tiene `memoria_dinamica_actual` y `reservas` (`dir → tamaño`); el máximo sale en las estadísticas
- [x] Log `## (<JID>) - Solicitó syscall: <NOMBRE>` (lo emite `registrar_syscall`)

## Fase D: Planificador, servicios bloqueantes (Check 3) ✅
Responsable: D2 · Commit `42d562c` · Código en `servicios.c`

En las syscalls bloqueantes **el Core no espera respuesta**: suelta el Job.

Payload: `{id, jid, contexto, [string nombre], uint32 tamaño, uint32 cant_tramos, (uint32 dir_fisica, uint32 tam) × cant_tramos}`

- [x] Parser `leer_peticion`: valida que la suma de los tramos sea igual al tamaño
- [x] Un hilo + cola FIFO + semáforo + mutex por servicio
- [x] **Loader**: lee de `PATH_DATOS` (si el archivo es corto, completa con ceros) → `RETARDO_LOADER` → escribe por tramos
- [x] **Labeler**: `Ingrese N caracteres:` → `getline` de stdin → escribe por tramos
- [x] **Logger**: lee por tramos → hexadecimal en mayúsculas → agrega al final de `PATH_REPORTES`
- [x] Logs de inicio y fin de servicio, de acceso a memoria y de deslockeo
- [x] Deslockeo **siempre**, incluso si el servicio falló (después finaliza con `ERROR_<SERVICIO>`)

## Fase E: Validación del Check 3
Responsable: todos

- [ ] Script *Mini Entrenamiento*: `ALLOC` + `LOAD_BATCH` + `FORWARD/BACKWARD/UPDATE` + `REPORT`
- [ ] Revisar en los logs: page faults en varias páginas, Jobs que pasan por BLOCKED, reportes hex correctos
- [ ] Correr con `valgrind --leak-check=full` en Planificador y Placa (Planificador contra mocks: ✅ 0 bytes de fuga confirmada)
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
- [x] Estadísticas completas en el log de fin de Job (memoria dinámica máxima agregada en `e5fd060`)
- [ ] `SIGINT`/`SIGTERM` con cierre ordenado en los 4 módulos
- [ ] Helgrind/DRD en pruebas de stress
- [ ] Scripts de deploy y configs por máquina
- [ ] Cada integrante debe poder explicar cualquier módulo en el coloquio

## Checklist de logs obligatorios del Planificador
| Log | Estado |
| --- | --- |
| `## Módulo: <NOMBRE>` | ✅ |
| `## (<JID>) Se crea el Job - Estado: NEW` | ✅ |
| `## (<JID>) Pasa del estado <A> al estado <B>` | ✅ (BLOCKED incluido) |
| `## (<JID>) - Desalojado por fin de quantum` | ✅ |
| `## (<JID>) - Prioridad HRRN calculada: … - Estimación próxima ráfaga: …` | ✅ |
| `## (<JID>) - Solicitó syscall: <NOMBRE>` | ✅ |
| `## (<JID>) inicia <SERVICIO>` / `finalizó <SERVICIO> y pasa a READY` | ✅ |
| `## (<JID>) - <Lectura/Escritura> - Dirección Física: … - Tamaño: …` | ✅ |
| `## (<JID>) - Deslockeo de páginas` | ✅ |
| `## (<JID>) - Ingrese <N> caracteres:` | ✅ |
| `## (<JID>) - <CONTENIDO>` (reportes) | ✅ |
| `## (<JID>) finalizó su ejecución con motivo de <M>. Estadísticas: …` | ✅ (con memoria dinámica máxima) |
