---
tags: [tp-so, entrenados, modulo, storage]
modulo: storage
rama: develop + origin/storage
responsables: [D4]
actualizado: 2026-10-29
---

# Storage

Volver a [[00 - Inicio]] · Depende de [[Utils]] y [[Protocolo]] · Lo usa el [[Planificador]]

Persiste los **checkpoints** de los Jobs sobre un filesystem propio, `FAT32_TRAIN`, guardado en un archivo dentro de `PATH_STORAGE`. Tiene una consola interactiva para inspeccionar y modificar el volumen. Su único cliente es el Planificador.

**Ejecución:** `./bin/storage [Archivo Config]`

## Estado
| Funcionalidad | `develop` | `origin/storage` |
| --- | --- | --- |
| Servidor y handshake (solo acepta `MODULO_PLANIFICADOR`) | ✅ | ✅ |
| `GUARDAR` / `CARGAR` / `ELIMINAR_CHECKPOINT` | ❌ responden "no implementado" | ❌ sin cambios |
| Formateo y carga del volumen (superbloque, FAT, directorio) | ❌ | ✅ |
| Consola: `INFO`, `LS`, `CAT`, `WRITE`, `RM` | ❌ | ✅ |
| Journaling y recuperación | ❌ | ❌ |
| Retardos `RETARDO_ACCESO_BLOQUE` / `RETARDO_COMMIT` | ❌ | ? (revisar en `consola.c`) |

> [!warning] Apagado
> Cuando recibe Ctrl-C (SIGINT), loguea `[ERROR] Falló accept(): Interrupted system call` y `Error al aceptar conexión entrante`. Lo detectó la [[Despliegue distribuido|prueba distribuida]] del 14/11. Habría que manejar la señal y cerrar sin error.

> [!todo] Check 4
> La lógica de `WRITE`, `CAT` y `RM` de la consola es casi la misma que necesitan `GUARDAR`, `CARGAR` y `ELIMINAR_CHECKPOINT`. Conviene moverla a funciones de `filesystem.c` (`fs_escribir`, `fs_leer`, `fs_eliminar`) que usen tanto la consola como `operaciones.c`. Ver [[Plan de acción#Fase F: Checkpoints (Check 4 · 14/11)]].

## Layout del volumen `FAT32_TRAIN`

```
| Bloque 0     | Bloques FAT                 | Bloques de directorio   | Bloques de datos ... |
| superbloque  | CANT_BLOQUES × uint32       | BLOQUES_DIRECTORIO      |                      |
```

- **Superbloque** (`t_superbloque`, packed): `magic_number[11] = "FAT32_TRAIN"`, `block_size`, `blocks`, `dir_blocks`
- **Entrada de directorio** (`t_entrada_directorio`, 32 bytes, packed): `estado` (0 libre / 1 ocupada), `nombre[23]`, `tamanio`, `bloque_inicial`
- **FAT**: una entrada `uint32` por bloque, que encadena al bloque siguiente del checkpoint

---

## `main.c` / `main.h`
| Función | Descripción |
| --- | --- |
| `main(argc, argv)` | `inicializarLoggerConfig` → en la rama, `inicializar_filesystem` + hilo `iniciar_consola_interactiva` → `iniciar_servidor_storage` |
| `inicializarLoggerConfig(ruta)` | Crea los globales `logger` y `aConfig` |

## `comunicacion.c` / `comunicacion.h`
| Función | Descripción |
| --- | --- |
| `iniciar_servidor_storage(config, logger)` | `crear_servidor(PUERTO_ESCUCHA)` y loop de `accept`, con un hilo `gestionar_cliente_planificador` por conexión |
| `gestionar_cliente_planificador(void* t_args_conexion)` | Identifica al cliente y llama a `atender_operaciones_planificador` |
| `identificar_planificador(socket, logger)` *(static)* | `recibir_handshake`, rechaza si no es el Planificador, `responder_handshake(true)` y log `## Módulo: …` |
| `t_args_conexion` | `{socket_cliente, logger}` |

## `operaciones.c` / `operaciones.h`
| Función | Descripción |
| --- | --- |
| `atender_operaciones_planificador(socket, logger)` | Loop `recibir_buffer` → switch con `OP_GUARDAR/CARGAR/ELIMINAR_CHECKPOINT` |
| `responder_no_implementado(socket, op_rsp, logger, operacion)` *(static)* | Placeholder actual: loguea un warning y responde `{ok=false}` |

## `filesystem.c` / `filesystem.h` *(solo `origin/storage`)*
| Función | Descripción |
| --- | --- |
| `inicializar_filesystem(config, logger)` | Abre `PATH_STORAGE/<archivo>`. Si no existe, lo **formatea**: superbloque, FAT en 0, directorio vacío y relleno con ceros. Si existe, lo carga |

## `consola.c` / `consola.h` *(solo `origin/storage`)*
| Función | Descripción |
| --- | --- |
| `iniciar_consola_interactiva(void* t_args_consola)` | Loop `readline`: `INFO`, `LS`, `CAT <nombre> <bytes>`, `WRITE <nombre> <hex>`, `RM <nombre>` |
| `ejecutar_comando_info` *(static)* | Muestra el superbloque y el uso de bloques |
| `ejecutar_comando_ls` *(static)* | Lista las entradas ocupadas del directorio |
| `ejecutar_comando_cat` *(static)* | Sigue la cadena FAT desde `bloque_inicial` e imprime los bytes |
| `ejecutar_comando_write` *(static)* | Pasa el hex a bytes, reserva bloques libres en la FAT, escribe y crea la entrada |
| `ejecutar_comando_rm` *(static)* | Libera la cadena FAT y marca la entrada como libre |
| `calcular_offset_fat`, `calcular_offset_directorio`, `hex_string_a_bytes` *(static)* | Helpers |

## Configuración (`storage.config`)
| Clave | Ejemplo |
| --- | --- |
| `PUERTO_ESCUCHA` | 8082 |
| `LOG_LEVEL` | INFO |
| `PATH_STORAGE` | /home/utnso/storage/ |
| `CANT_BLOQUES` / `TAM_BLOQUE` | 1024 / 64 |
| `BLOQUES_DIRECTORIO` | 64 |
| `RETARDO_ACCESO_BLOQUE` / `RETARDO_COMMIT` | 100 / 100 ms |
