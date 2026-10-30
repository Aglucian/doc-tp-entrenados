---
tags: [tp-so, entrenados, protocolo]
archivo: utils/src/utils/protocolo_entrenados.h
version: 1
actualizado: 2026-10-29
---

# Protocolo

Volver a [[00 - Inicio]] · Implementación: [[Utils]]

`protocolo_entrenados.h` es la **única fuente de verdad** de la mensajería. Si falta un mensaje, se agrega ahí. Ninguna struct compartida se duplica en un módulo.

**Convenciones de payload:**
- `uint32`: `buffer_agregar_uint32`
- `uint8`: `buffer_agregar_uint8`
- `bool`: `buffer_agregar_bool`
- `string`: `uint32 largo` + bytes con `\0`
- `bytes`: `uint32 tam` + bytes
- `contexto`: 14 × `uint32`

## Handshake
`OP_HANDSHAKE {t_modulo modulo, uint32 id_core}` → `OP_HANDSHAKE_OK` | `OP_HANDSHAKE_ERROR`
- `t_modulo`: `PLANIFICADOR=0`, `CORE=1`, `PLACA=2`, `STORAGE=3`
- `id_core` se usa solo si el que se conecta es un Core
- Prueba del Check 1: `OP_TEST` → `OP_TEST_OK`
- *(rama `placa`/`core`)*: después del handshake de un Core, la Placa envía `OP_TAM_PAGINA {uint32 tam_pagina}`

## Opcodes

### Planificador → Placa (`0x10`–`0x2F`)
| Opcode | Valor | Pedido | Respuesta |
| --- | --- | --- | --- |
| `OP_CREAR_JOB` | 0x10 | `jid, string path` | `OP_RSP_CREAR_JOB` (0x1F) `{bool ok}` |
| `OP_ASIGNAR_ESPACIO` | 0x11 | `jid, tamaño` | `OP_RSP_ASIGNAR` (0x12) `{bool ok, uint32 dir_logica}` |
| `OP_LIBERAR_ESPACIO` | 0x13 | `jid, dir_logica` | `OP_RSP_LIBERAR` (0x14) `{bool ok}` |
| `OP_CARGA_PAGINA` | 0x15 | `jid, nro_pagina` | `OP_RSP_CARGA_PAGINA` (0x16) `{bool ok}` |
| `OP_LEER_DATOS` | 0x17 | `jid, dir_fisica, tamaño` | `OP_RSP_LEER_DATOS` (0x18) `{bool ok, bytes contenido}` |
| `OP_ESCRIBIR_DATOS` | 0x19 | `jid, dir_fisica, bytes contenido` | `OP_RSP_ESCRIBIR` (0x1A) `{bool ok}` |
| `OP_DESLOCKEO_PAGINAS` | 0x1B | `jid` | `OP_RSP_DESLOCKEO` (0x1C) `{bool ok}` |
| `OP_FINALIZAR_JOB` | 0x1D | `jid` | `OP_RSP_FINALIZAR` (0x1E) `{bool ok}` |

### Planificador → Storage (`0x30`–`0x3F`)
| Opcode | Valor | Pedido | Respuesta |
| --- | --- | --- | --- |
| `OP_GUARDAR_CHECKPOINT` | 0x30 | `string nombre, bytes contenido` | 0x31 `{bool ok}` (`false` = sin espacio) |
| `OP_CARGAR_CHECKPOINT` | 0x32 | `string nombre` | 0x33 `{bool ok, bytes contenido}` (`false` = no existe) |
| `OP_ELIMINAR_CHECKPOINT` | 0x34 | `string nombre` | 0x35 `{bool ok}` (`false` = no existe) |

### Planificador ↔ Core (`0x40`–`0x5F`)
| Opcode | Valor | Sentido | Payload |
| --- | --- | --- | --- |
| `OP_EJECUTAR_JOB` | 0x40 | P → C | `jid, contexto` |
| `OP_INTERRUPCION` | 0x41 | P → C | `uint32 jid, uint32 motivo` (el Core descarta las que no son del Job que ejecuta) |
| `OP_RSP_SYSCALL` | 0x42 | P → C | `bool ok, uint32 valor` |
| `OP_DEVOLUCION` | 0x43 | C → P | `uint32 jid, uint8 motivo, contexto[, uint32 nro_pagina si es PAGE_FAULT]` |
| `OP_SYSCALL` | 0x44 | C → P | `uint32 id_syscall, uint32 jid, contexto, parámetros…` |

### Core → Placa (`0x60`–`0x6F`)
| Opcode | Valor | Pedido | Respuesta |
| --- | --- | --- | --- |
| `OP_FETCH_INSTRUCCION` | 0x60 | `jid, pc` | 0x61 `{bool ok, string instruccion}` |
| `OP_OBTENER_MARCO` | 0x62 | `jid, nro_pagina` | 0x63 `{bool ok, uint32 marco}` (`false` = page fault; si da `true` lockea la página) |
| `OP_READ_MEM` | 0x64 | `jid, dir_fisica, tamaño` | 0x65 `{bool ok, bytes contenido}` |
| `OP_WRITE_MEM` | 0x66 | `jid, dir_fisica, bytes contenido` | 0x67 `{bool ok}` |
| `OP_TAM_PAGINA` *(rama)* | 0x68 | Placa → Core después del handshake | `uint32 tam_pagina` |
| `OP_DESLOCKEAR_PAGINAS` *(rama)* | 0x69 | `jid` | 0x6A `{bool ok}` |

> [!warning] Dos opcodes de deslockeo
> `OP_DESLOCKEO_PAGINAS` (0x1B) lo usa el Planificador y `OP_DESLOCKEAR_PAGINAS` (0x69) lo usa el Core. Hacen lo mismo, pero cada uno queda en el rango de opcodes de su emisor. Mantenerlos así y no confundirlos.

## Payloads Core → Planificador
Detalle de `OP_SYSCALL` según `origin/core`. Todas empiezan con `{uint32 id, uint32 jid, contexto}`, y el contexto ya viene con el `pc` avanzado.

| Syscall | Id | Parámetros extra | ¿Bloquea? | Qué espera el Core |
| --- | --- | --- | --- | --- |
| `INIT_JOB` | 0 | `string archivo` | no | `OP_RSP_SYSCALL {ok, jid_nuevo}` |
| `ALLOC` | 1 | `uint32 tamaño` | no | `OP_RSP_SYSCALL {ok, dir_logica}` ⚠️ falta el `case` en el Core |
| `FREE` | 2 | `uint32 dir_logica` | no | `OP_RSP_SYSCALL {ok, 0}` ⚠️ falta el `case` en el Core |
| `LOAD_BATCH` | 3 | `string archivo, uint32 tamaño, uint32 n, (dir_fisica, tam)×n` | **sí** | nada: el Core suelta el Job |
| `LABEL` | 4 | `uint32 tamaño, uint32 n, (dir_fisica, tam)×n` | **sí** | nada |
| `REPORT` | 5 | `uint32 tamaño, uint32 n, (dir_fisica, tam)×n` | **sí** | nada |
| `SAVE_CHECKPOINT` | 6 | `string nombre, uint32 tamaño, uint32 n, (dir_fisica, tam)×n` | **sí** | nada |
| `LOAD_CHECKPOINT` | 7 | `string nombre, uint32 tamaño, uint32 n, (dir_fisica, tam)×n` | **sí** | nada |
| `DELETE_CHECKPOINT` | 8 | `string nombre` | **sí** | nada |
| `EXIT` | 9 | — | — | nada (en la práctica el Core usa `OP_DEVOLUCION` con `EXIT`) |

> [!important] Páginas lockeadas
> En las syscalls con tramos, el Core ya tradujo las direcciones y **las páginas quedan lockeadas** en la Placa. El Planificador tiene que mandar `OP_DESLOCKEO_PAGINAS {jid}` cuando termina el servicio, también si hubo un error.

## Enums

### `t_motivo_devolucion`
`FIN_QUANTUM=0`, `PAGE_FAULT=1`, `SYSCALL=2`, `EXIT=3`

### `t_motivo_interrupcion`
`FIN_QUANTUM=0`

### `t_syscall`
`INIT_JOB=0`, `ALLOC=1`, `FREE=2`, `LOAD_BATCH=3`, `LABEL=4`, `REPORT=5`, `SAVE_CHECKPOINT=6`, `LOAD_CHECKPOINT=7`, `DELETE_CHECKPOINT=8`, `EXIT=9`

## Contexto de ejecución
```c
typedef struct {
    uint32_t pc;
    uint32_t p0, p1, p2, p3, p4, p5;
    uint32_t ax, bx, cx, dx;
    uint32_t e1, e2, e3;
} t_contexto;   // CANT_REGISTROS = 14, todos en 0 al crear el Job
```

## Constantes
- `PROTOCOLO_ENTRENADOS_VERSION = 1`
- `MAX_PAYLOAD_SIZE = 16 MiB`
- `CANT_REGISTROS = 14`
