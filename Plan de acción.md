---
tags: [tp-so, entrenados, plan]
actualizado: 2026-11-14
proximo_hito: Entrega 1 (28/11)
---

# Plan de acción

Volver a [[00 - Inicio]] · Ver también [[Estado de ramas]], [[Protocolo]]

> [!warning] Situación al 14/11
> **Check 3 integrado.** Los PRs #12 (core), #14 (placa), #15 (planificador) y #17 (fix ALLOC/FREE del core) están en `develop`, y los 5 módulos compilan sin warnings.
> La [[Mini Entrenamiento 2026-11-14|Mini Entrenamiento]] con los módulos reales salió bien: 9 page faults, 5 reemplazos con Offload y 0 errores.
> El bug de `FREE`/`ALLOC` del Core se resolvió en el PR #19.
> **Check 4 integrado** (#21 Planificador y #22 Storage, con journaling) y probado con `kill -9` en los 5 servidores ([[Despliegue distribuido]]).
> **Suite de la cátedra:** CP2 y CP3 pasan completos ([[Suite cátedra 2026-11-14]]).

Roles (de `doc/distribucion-equipo.md`):
- **D1**: Planificador, planificación
- **D2**: Planificador, syscalls y servicios
- **D3**: Placa
- **D4**: Storage
- **D5**: Core y transversales

---

## Fase A: Integración ✅
Responsable: todos / D5

- [x] Mergear `origin/placa` → `develop` (PR #14)
- [x] Mergear `origin/core` → `develop` (PR #12), resolviendo el conflicto de `protocolo_entrenados.h` (ver [[Estado de ramas]], sección del conflicto)
- [x] Mergear `origin/storage` → `develop` (`764b9c3`)
- [x] `make` en los 5 módulos sin warnings (14/11)
- [x] PR `planificador` → `develop` (#15, mergeado el 30/10)
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

- [x] **[Core, D5]** `case INST_ALLOC` / `INST_FREE` en `ejecutar_instruccion` (`5ba1c3b`, PR #17)
- [x] **[Core, D5]** `FREE` con `ok=false` ya no desconecta al Core: loguea un warning y sigue (`69c087f`, PR #19)
- [x] **[Core, D5]** `ALLOC` con `ok=false` abandona el Job sin devolverlo (`EJEC_JOB_FINALIZADO`, `69c087f`, PR #19)
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

## Fase E: Validación del Check 3 🟡
Responsable: todos

- [x] Script *Mini Entrenamiento*: `ALLOC` + `LOAD_BATCH` + `FORWARD/BACKWARD/UPDATE` + `REPORT` → [[Mini Entrenamiento 2026-11-14]]
- [x] Revisar en los logs: page faults en varias páginas, Jobs que pasan por BLOCKED, reportes hex correctos
- [ ] Correr con `valgrind --leak-check=full` en Planificador y Placa (Planificador contra mocks: ✅ 0 bytes de fuga confirmada)
- [ ] Probar con LRU y con CLOCK-M en la Placa, y con FIFO, RR y HRRN en el Planificador (hecho: CLOCK-M + RR)
- [x] Prueba distribuida en 5 servidores (un módulo por máquina) → [[Despliegue distribuido#Primera corrida distribuida (14/11)]]
- [ ] Varios Jobs y varios Cores a la vez
- [ ] Decidir qué hacer con el livelock de rangos más grandes que la memoria (ver [[Mini Entrenamiento 2026-11-14#Hallazgos]])

---

## Fase F: Checkpoints (Check 4 · 14/11) ✅
Probado en los 5 servidores con `kill -9` al Storage → [[Check 4 2026-11-14]]

### Storage (D4) · PR #22
- [x] `GUARDAR`, `CARGAR` y `ELIMINAR_CHECKPOINT` sobre la FAT (la lógica de la consola pasó a `filesystem.c`)
- [x] Journaling y recuperación ante `kill -9`
- [x] Respetar `RETARDO_ACCESO_BLOQUE` y `RETARDO_COMMIT`
- [x] Cierre limpio con Ctrl-C / SIGTERM (`2a9b3b3`)

### Planificador (D2) · PR #21
- [x] `SAVE_CHECKPOINT`: leer por tramos → Storage → deslockeo → READY. Sin espacio: `SIN_ESPACIO_STORAGE`
- [x] `LOAD_CHECKPOINT`: Storage → escribir por tramos → deslockeo → READY. Si no existe: `CHECKPOINT_INEXISTENTE`
- [x] `DELETE_CHECKPOINT`: si no existe, **solo se informa**; no deslockea
- [x] Si se cae el Storage: log y el Job finaliza con `ERROR_STORAGE`, sin colgarse

### Pendiente
- [ ] Suite oficial del CP4 cuando la publique la cátedra

## Fase G: Cierre (28/11 → 19/12)
- [x] Estadísticas completas en el log de fin de Job (memoria dinámica máxima agregada en `e5fd060`)
- [ ] `SIGINT`/`SIGTERM` con cierre ordenado en los 4 módulos
- [ ] Helgrind/DRD en pruebas de stress
- [x] Scripts de deploy y configs por máquina → [[Despliegue distribuido]] (`deploy/desplegar.sh`, `18d367d`)
- [ ] Más pruebas distribuidas (ver [[Despliegue distribuido#Próximas pruebas]])
- [x] **[Storage, D4]** Manejar SIGINT/SIGTERM sin loguear errores al apagarse (`2a9b3b3`)
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
