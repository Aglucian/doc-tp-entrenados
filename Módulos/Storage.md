---
tags: [tp-so, entrenados, modulo, storage]
modulo: storage
rama: develop
responsables: [D4]
actualizado: 2026-11-14
---

# Storage

Volver a [[00 - Inicio]] · Depende de [[Utils]] y [[Protocolo]] · Lo usa el [[Planificador]] · Pruebas: [[Check 4 2026-11-14]], [[Suite cátedra 2026-11-14]]

Persiste los **checkpoints** de los Jobs sobre un filesystem propio, `FAT32_TRAIN`, guardado en `PATH_STORAGE/volumen.dat`. Antes de aplicar cada modificación la registra en un **journal** (`PATH_STORAGE/journal.txt`), así puede recuperarse de una finalización abrupta. Tiene una consola interactiva para inspeccionar y modificar el volumen. Su único cliente es el Planificador.

**Ejecución:** `./bin/storage [Archivo Config]`

## Estado
Todo en `develop`.

| Funcionalidad | Estado | Commit |
| --- | --- | --- |
| Servidor y handshake (solo acepta `MODULO_PLANIFICADOR`) | ✅ | Check 1 |
| Formateo automático si no existe el volumen; validación de la firma si ya existe | ✅ | `a2c6b63` (#22) |
| Guardar, Cargar y Eliminar Checkpoint para el Planificador | ✅ | `a2c6b63` (#22) |
| Journal: asientos con COMMIT y APPLIED, `fsync` y recuperación al iniciar | ✅ | `a2c6b63` (#22) |
| Consola `INFO`, `LS`, `CAT`, `WRITE`, `RM` (`WRITE` y `RM` pasan por el journal) | ✅ | `764b9c3` + `a2c6b63` |
| Retardos `RETARDO_ACCESO_BLOQUE` (por cada acceso a bloque) y `RETARDO_COMMIT` (antes de cada COMMIT) | ✅ | `a2c6b63` |
| Cierre limpio con Ctrl-C / SIGTERM | ✅ | `2a9b3b3` |
| Logs obligatorios: solicitud, completada, errores, FAT, bloques, journal y recuperación | ✅ | `a2c6b63` |

> [!success] Probado
> - [[Check 4 2026-11-14]]: guardar y cargar entre scripts independientes y `kill -9` a mitad de un guardado, en los 5 servidores.
> - [[Suite cátedra 2026-11-14]]: los escenarios 10 y 11 de la cátedra (consola, directorio lleno, bloques agotados y persistencia).
> - Valgrind: 0 errores y 0 bytes perdidos.

## Layout del volumen `FAT32_TRAIN`

```
| Bloque 0     | Bloques FAT                 | Bloques de directorio   | Bloques de datos ... |
| superbloque  | CANT_BLOQUES × uint32       | BLOQUES_DIRECTORIO      |                      |
```

- **Superbloque** (`t_superbloque`, packed): `magic_number[11] = "FAT32_TRAIN"`, `block_size`, `blocks`, `dir_blocks`. El resto del bloque 0 va en cero.
- **FAT:** una entrada `uint32` por bloque. De esos 32 bits, solo los 28 menos significativos son el número de bloque.
  - `0` = libre
  - `0x0FFFFFFF` = fin de la cadena
  - `0x0FFFFFFE` = reservado (superbloque, FAT y directorio)
- **Entrada de directorio** (`t_entrada_directorio`, 32 bytes, packed): `estado` (0 libre / 1 ocupada), `nombre[23]`, `tamanio`, `bloque_inicial`. Un checkpoint vacío tiene `bloque_inicial = 0x0FFFFFFF`.
- **Regiones:** `bloques_fat = ceil(CANT_BLOQUES × 4 / TAM_BLOQUE)`; el primer bloque de datos es `1 + bloques_fat + BLOQUES_DIRECTORIO`.

Si el volumen ya existe, mandan los valores de **su superbloque**, no los del config.

## Journal (`journal.txt`)
Es un archivo de texto con una línea por marca o por modificación. Cada modificación guarda el **valor final** que tiene que quedar en el volumen, así que aplicarla dos veces da el mismo resultado (idempotencia).

```
RECORD_STARTED 7 modelo7
OP_DIR 2 1 modelo7 60 0x0000000F
OP_FAT 0x0000000F 0x00000010
OP_FAT 0x00000010 0x0FFFFFFF
OP_WRITE 0x0000000F <TAM_BLOQUE bytes en hexadecimal>
OP_WRITE 0x00000010 <...>
RECORD_COMMITED 7
RECORD_APPLIED 7
```

**Procedimiento para Guardar y Eliminar** (lo hace `registrar_y_aplicar`):
1. Escribe el asiento completo con `fwrite` + `fflush` + `fsync`.
2. Espera `RETARDO_COMMIT` y escribe `RECORD_COMMITED`, también con `fsync`.
3. Aplica las modificaciones en el volumen. Cada acceso a un bloque espera `RETARDO_ACCESO_BLOQUE`.
4. Escribe `RECORD_APPLIED`.

**Recuperación al iniciar:** recorre el journal en orden.
- Un asiento con COMMIT y sin APPLIED se **vuelve a aplicar** (log `## Recuperación - Asiento: N - APLICADO`).
- El resto se descarta (`DESCARTADO`). Una línea cortada por un `kill -9` invalida su asiento.
- Al terminar, el journal queda vacío.

> [!note] fsync al aplicar
> Por defecto, aplicar un asiento en el volumen no hace `fsync`. Se puede activar con `SINCRONIZAR_APLICACION=1`, una clave opcional que agregamos porque el enunciado pide que, si se usa, se pueda desactivar por configuración.

---

## `main.c` / `main.h`
| Función | Descripción |
| --- | --- |
| `main(argc, argv)` | `inicializarLoggerConfig` → `inicializar_filesystem` (si falla, aborta) → señales (`rl_catch_signals = 0`, `instalar_manejo_de_senales`) → hilo de la consola sin señales → `iniciar_servidor_storage` → al salir: `rl_cleanup_after_signal`, `finalizar_filesystem` y log `Storage finalizado` |
| `inicializarLoggerConfig(ruta)` | Crea los globales `logger` y `aConfig` respetando `LOG_LEVEL` |

## `filesystem.c` / `filesystem.h`
El volumen se mapea completo en memoria (`mmap` con `MAP_SHARED`) y todas las operaciones pasan por un mutex.

### API
| Función | Descripción |
| --- | --- |
| `inicializar_filesystem(config, logger)` | Abre el volumen o lo formatea, y llama a `journal_iniciar`, que recupera lo pendiente. Después sincroniza el volumen. Devuelve `bool` |
| `finalizar_filesystem()` | Cierra el journal, sincroniza y desmapea el volumen |
| `fs_guardar(nombre, contenido, tamaño)` | Si el checkpoint ya existe, reutiliza sus bloques en orden, pide los que faltan y libera los que sobran. Arma el asiento (entrada de directorio, FAT, bloques con relleno de ceros) y llama a `registrar_y_aplicar` |
| `fs_cargar(nombre, &contenido, &tamaño)` | Recorre la cadena de la FAT y devuelve los `tamaño` bytes (con `malloc`) |
| `fs_eliminar(nombre, &tamaño)` | Asiento con la entrada de directorio libre y la cadena en `FAT_LIBRE` |
| `fs_mostrar_superbloque()` / `fs_listar()` | Salida legible para `INFO` y `LS` de la consola |

Devuelven `t_resultado_fs`: `FS_OK`, `FS_NO_EXISTE`, `FS_SIN_ESPACIO`, `FS_DIRECTORIO_LLENO`, `FS_NOMBRE_INVALIDO` (más de 22 caracteres o con espacios) o `FS_ERROR` (falló el journal).

### Internas
| Función | Descripción |
| --- | --- |
| `acceder_bloque` | `usleep(RETARDO_ACCESO_BLOQUE)` |
| `superbloque`, `fat`, `directorio`, `bloque_de_datos`, `es_bloque_de_datos` | Punteros a cada región dentro del mapeo |
| `leer_fat` / `escribir_fat` | Acceso a una entrada, con retardo y log `## Acceso FAT - Entrada: N - Valor: 0x…` |
| `buscar_en_directorio(nombre, &libre)` | Devuelve el índice de la entrada (o -1) y la primera entrada libre, con un retardo por bloque de directorio |
| `leer_cadena(inicial)` | Lista de los bloques de un checkpoint, con un límite para que una FAT corrupta no genere un ciclo |
| `buscar_bloques_libres(n)` | `n` bloques con `FAT_LIBRE`, o `NULL` si no alcanzan |
| `aplicar_asiento(asiento)` | Aplica `MOD_DIR`, `MOD_FAT` y `MOD_WRITE` (log `## Acceso Bloque - Checkpoint: X - Bloque: N`). También lo usa la recuperación |
| `registrar_y_aplicar(asiento)` | journal (COMMIT) → `aplicar_asiento` → APPLIED |
| `formatear` / `abrir_existente` | Crea el volumen con `ftruncate` y marca los reservados, o lo abre y valida la firma y el tamaño |
| `calcular_regiones`, `mapear`, `ruta_en`, `nombre_valido`, `bloque_en`, `sincronizar_volumen` | Helpers |

## `journal.c` / `journal.h`
| Elemento | Descripción |
| --- | --- |
| `t_modificacion` | `{tipo: MOD_DIR / MOD_FAT / MOD_WRITE, numero, valor, entrada, contenido}` |
| `t_asiento` | `{id, nombre del checkpoint, modificaciones}` |
| `asiento_crear` / `asiento_destruir` | Ciclo de vida |
| `asiento_agregar_dir` / `_fat` / `_bloque` | Agregan las modificaciones con su valor final |
| `journal_registrar(asiento)` | Asigna el id, loguea `## Asiento iniciado` y `## Asiento: N - Modificacion: …`, escribe todo con `fsync`, espera `RETARDO_COMMIT` y marca COMMIT (`## Nueva marca en asiento: N: - COMMIT`) |
| `journal_marcar_aplicado(asiento)` | Escribe `RECORD_APPLIED` (`- APPLIED`) |
| `journal_iniciar(path, logger, retardo, tam_bloque, aplicar)` | Recupera los asientos (`leer_journal` + `recuperar`) y deja el journal vacío |
| `journal_cerrar()` | Cierra el archivo |
| internas | `a_hexa`/`desde_hexa`, `escribir_en_disco` (fwrite + fflush + fsync), `describir_modificacion` (para los logs), `linea_de_modificacion`, `leer_modificacion`, `buscar_leido` |

## `operaciones.c` / `operaciones.h`
| Función | Descripción |
| --- | --- |
| `atender_operaciones_planificador(socket, logger)` | Loop `recibir_buffer` → `guardar` / `cargar` / `eliminar` |
| `guardar` *(static)* | `{string nombre, bytes contenido}` → `fs_guardar` → `OP_RSP_GUARDAR_CHECKPOINT {ok}` |
| `cargar` *(static)* | `{string nombre}` → `fs_cargar` → `OP_RSP_CARGAR_CHECKPOINT {ok, bytes}` |
| `eliminar` *(static)* | `{string nombre}` → `fs_eliminar` → `OP_RSP_ELIMINAR_CHECKPOINT {ok}` |
| `responder` *(static)* | Arma un `{bool ok}` |

Logs: `## Solicitud [Guardar|Cargar|Eliminacion] Checkpoint: X` y `## [Guardado|Carga|Eliminacion] Checkpoint: X - Tamaño: T completada`. Los errores `## ERROR - Directorio lleno…` y `## ERROR - Falta de espacio en FAT…` los emite `fs_guardar`.

## `comunicacion.c` / `comunicacion.h`
| Función | Descripción |
| --- | --- |
| `iniciar_servidor_storage(config, logger)` | `crear_servidor` y loop de `accept`, con un hilo por conexión (creado con `crear_hilo_sin_senales`). Cuando llega una señal de cierre, sale del loop y cierra el socket |
| `gestionar_cliente_planificador(void*)` | Identifica al cliente y atiende sus operaciones |
| `identificar_planificador` *(static)* | Handshake: rechaza a cualquier módulo que no sea el Planificador y loguea `## Módulo: …` |

## `senales.c` / `senales.h`
| Función | Descripción |
| --- | --- |
| `instalar_manejo_de_senales()` | SIGINT/SIGTERM marcan el cierre, sin `SA_RESTART`, así el `accept()` vuelve |
| `storage_terminando()` | Indica si llegó una señal de cierre |
| `crear_hilo_sin_senales(hilo, fn, arg)` | Crea el hilo con SIGINT/SIGTERM bloqueadas, así la señal la recibe el hilo principal |

## `consola.c` / `consola.h`
| Función | Descripción |
| --- | --- |
| `iniciar_consola_interactiva(void*)` | Loop de `readline`: `INFO` → `fs_mostrar_superbloque`, `LS` → `fs_listar`, `CAT <nombre> <bytes>`, `WRITE <nombre> <hex>`, `RM <nombre>` |
| `ejecutar_comando_cat` *(static)* | `fs_cargar` → hasta `<bytes>` bytes en hexadecimal, 16 por línea |
| `ejecutar_comando_write` *(static)* | Hasta **20 bytes** en hexadecimal → `fs_guardar`, pasando por el journal |
| `ejecutar_comando_rm` *(static)* | `fs_eliminar`, pasando por el journal |
| `hexa_a_bytes` *(static)* | Convierte y valida el hexadecimal |

## Configuración (`storage.config`)
| Clave | Ejemplo |
| --- | --- |
| `PUERTO_ESCUCHA` | 8082 |
| `LOG_LEVEL` | INFO |
| `PATH_STORAGE` | /home/utnso/storage/ (volumen y journal) |
| `CANT_BLOQUES` / `TAM_BLOQUE` | 1024 / 64 (`TAM_BLOQUE`: potencia de 2, mínimo 32) |
| `BLOQUES_DIRECTORIO` | 64 |
| `RETARDO_ACCESO_BLOQUE` / `RETARDO_COMMIT` | 100 / 100 ms |
| `SINCRONIZAR_APLICACION` *(opcional, nuestra)* | 0 (por defecto) · 1 = `msync` después de aplicar cada asiento |
