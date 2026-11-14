---
tags: [tp-so, entrenados, modulo, utils]
modulo: utils
rama: develop
responsables: [D5]
actualizado: 2026-11-14
---

# Utils

Volver a [[00 - Inicio]] · La usan [[Planificador]], [[Core]], [[Placa]] y [[Storage]] · Mensajería: [[Protocolo]]

Es una biblioteca estática (`utils/lib/libutils.a`) que linkean los 4 módulos con `-lutils`. Se incluye como `#include <utils/xxx.h>`. Junta el transporte (sockets y framing), la serialización y el arranque común (config y logger).

Al hacer `make` en cualquier módulo, primero se recompila `utils`.

## `conexiones.c` / `conexiones.h`: sockets y framing

**Framing en el cable:** `op_code (uint8) | payload_size (uint32 little-endian) | payload`, todo en un solo `send`. Un payload mayor a `MAX_PAYLOAD_SIZE` (16 MiB) se toma como corrupción del stream.

### Sockets (devuelven -1 ante error)
| Función | Descripción |
| --- | --- |
| `crear_servidor(puerto, logger)` | `getaddrinfo` + `socket` + `SO_REUSEADDR` + `bind` + `listen` |
| `esperar_cliente(socket_servidor, logger)` | `accept`. Si lo interrumpe una señal (`EINTR`) no lo loguea como error y deja que decida quien llama, por ejemplo para cerrar el módulo (`2a9b3b3`) |
| `crear_conexion(ip, puerto, logger)` | `connect` al servidor |
| `cerrar_conexion(socket)` | `close` si es distinto de -1 |

### Envío y recepción
| Función | Descripción |
| --- | --- |
| `enviar_todo(socket, datos, tam)` / `recibir_todo(…)` | Loop de `send`/`recv` hasta completar (cubre envíos y lecturas parciales) |
| `enviar_paquete(socket, op, payload, size)` | Arma el framing y lo envía |
| `recibir_paquete(socket, &op, &payload, &size)` | Recibe el framing. `*payload` queda con `malloc` y lo libera el caller |
| `enviar_codigo` / `recibir_codigo` | Envía o recibe solo el op_code, sin payload |
| `enviar_buffer(socket, op, buffer)` | Envía un `t_buffer` y **lo destruye** |
| `recibir_buffer(socket, &op, &buffer)` | Recibe y **crea** un `t_buffer` que el caller destruye |

### Handshake
| Función | Descripción |
| --- | --- |
| `handshake_cliente(socket, modulo, id_core, logger)` | Lado cliente completo: envía `OP_HANDSHAKE {modulo, id_core}` y espera `OP_HANDSHAKE_OK` |
| `enviar_handshake(socket, modulo, id_core)` | Solo el envío |
| `recibir_handshake(socket, &handshake_msg)` | Lado servidor: lee la identificación |
| `responder_handshake(socket, aceptado)` | `OP_HANDSHAKE_OK` u `OP_HANDSHAKE_ERROR` |

## `serializacion.c` / `serializacion.h`: buffer dinámico

```c
typedef struct {
    uint32_t size;      // bytes usados
    uint32_t capacidad; // bytes reservados (crece por realloc)
    uint32_t offset;    // posición de lectura
    bool valido;        // pasa a false si una lectura se pasa del final
    void* stream;
} t_buffer;
```

| Función | Descripción |
| --- | --- |
| `buffer_crear()` / `buffer_destruir(b)` | Ciclo de vida |
| `buffer_desde_payload(payload, size)` | Crea un buffer con una **copia** del payload (el original lo sigue liberando el caller) |
| `buffer_es_valido(b)` | Se chequea **una sola vez al final** de una secuencia de lecturas |
| `buffer_agregar_uint8/uint32/bool/double` | Escriben primitivos |
| `buffer_agregar_string(b, s)` | `uint32 largo` + bytes incluyendo el `\0` (si `s` es NULL, solo largo 0) |
| `buffer_agregar_bytes(b, datos, tam)` | `uint32 tam` + bytes |
| `buffer_agregar_contexto(b, ctx)` | Los 14 registros `uint32` en el orden de `t_contexto` |
| `buffer_leer_uint8/uint32/bool/double` | Leen primitivos. Si no hay datos devuelven 0 y marcan `valido=false` |
| `buffer_leer_string(b)` | Devuelve un `char*` que libera el caller |
| `buffer_leer_bytes(b, &tam)` | Devuelve un `void*` que libera el caller |
| `buffer_leer_contexto(b, &ctx)` | Llena el `t_contexto` |

> [!tip] Patrón de uso
> Leer todos los campos y después hacer un único `if (!buffer_es_valido(b))`. Si una lectura falla, las siguientes no rompen: devuelven 0 o `NULL`.

## `herramientas.c` / `herramientas.h`: arranque común
| Función | Descripción |
| --- | --- |
| `iniciar_config(path)` | `config_create`. Devuelve `NULL` ante error |
| `iniciar_logger(archivo, nombre, en_consola, nivel)` | `log_create` |
| `config_tiene_claves(config, claves[], logger)` | `claves` termina en `NULL`. Loguea cada clave faltante |
| `terminar_programa(logger, config)` | Destruye ambos |

## `protocolo_entrenados.c` / `.h`
Es la única fuente de verdad de la mensajería. Está documentada en [[Protocolo]].
| Función | Descripción |
| --- | --- |
| `nombre_modulo(t_modulo)` | `"PLANIFICADOR"`, `"CORE"`, `"PLACA"`, `"STORAGE"` |
| `nombre_syscall(t_syscall)` | `"INIT_JOB"` … `"EXIT"` |

## `hello.c` / `hello.h`
| Función | Descripción |
| --- | --- |
| `saludar(quien)` | Ejemplo de la plantilla de la cátedra (no se usa) |
