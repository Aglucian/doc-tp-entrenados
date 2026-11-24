---
tags: [tp-so, entrenados, modulo, placa]
modulo: placa
rama: develop
responsables: [D3]
actualizado: 2026-11-24
---

# Placa

Volver a [[00 - Inicio]] · Depende de [[Utils]] y [[Protocolo]] · La usan el [[Planificador]] y los [[Core]] · Pruebas: [[Suite cátedra 2026-11-14]]

Es la memoria del sistema. Se ocupa de:
- guardar las instrucciones de cada Job (leídas de `PATH_INSTRUCCIONES`)
- administrar la memoria principal paginada (marcos de `TAM_PAGINA`)
- llevar las tablas de páginas por Job
- manejar el área de **offload** (swap en `PATH_OFFLOAD`) con reemplazo LRU o CLOCK-M
- lockear páginas mientras un Core o un servicio las usa

**Ejecución:** `./bin/placa [Archivo Config]`

## Estado
Todo en `develop`.

| Funcionalidad | Estado | Commit / PR |
| --- | --- | --- |
| Servidor multihilo (Planificador + N Cores) | ✅ | Check 1 |
| Crear / finalizar Job, fetch de instrucción; Job inicial **relativo o con ruta absoluta** | ✅ | Check 2 + `896a387` |
| Envío de `OP_TAM_PAGINA` al Core después del handshake | ✅ | #14 |
| Marcos, tablas de páginas, reservas (ALLOC/FREE) | ✅ | #14 |
| Obtener marco (page fault si no está presente) | ✅ | #14 |
| Carga de página con reemplazo LRU / CLOCK-M y offload | ✅ | #14 |
| Lectura y escritura física, deslockeo | ✅ | #14 |
| Retardos `RETARDO_MEMORIA` (también en cada FETCH) / `RETARDO_OFFLOAD` | ✅ | #14 |
| Consola local `INFO` (memoria y Offload ocupados, frames libres/lockeados, Jobs) y `TLS` (memoria por Job) | ✅ | `c2ce7fc` (#24) |

> [!success] Probado
> En la suite de la cátedra del CP3, el LRU elige las víctimas en el orden que espera el README (0→1→2→3). CLOCK-M, el aislamiento entre Jobs, el Offload lleno y el page locking del 06 también pasan: ninguna página del `LABEL` fue víctima. Ver [[Suite cátedra 2026-11-14]].

---

## `consola.c` / `consola.h` (#24)
Hilo de consola con `fgets` (no usa readline): `INFO` → `mostrar_info_memoria()` y `TLS` → `mostrar_jobs_memoria()`, las dos en `memoria.c`. La prueba final 06 pide `INFO` al terminar; ahí mostró 0 frames lockeados y 0 Jobs ([[Pruebas finales 2026-11-24]]).

## `main.c` / `main.h`
| Elemento | Descripción |
| --- | --- |
| `main(argc, argv)` | Carga el config en `t_config_placa`, inicializa las instrucciones y la memoria (`inicializar_memoria`) y arranca `iniciar_servidor_placa` |
| `t_config_placa` | `puerto_escucha, log_level, tam_memoria, tam_pagina, retardo_memoria, algoritmo_reemplazo, path_instrucciones, path_offload, tam_offload, retardo_offload` |
| globales | `logger`, `config`, `config_placa` |

## `conexiones.c` / `conexiones.h`
| Función | Descripción |
| --- | --- |
| `iniciar_servidor_placa()` | `crear_servidor` y loop de `accept`, con un hilo `atender_cliente` por conexión |
| `atender_cliente(void*)` | Handshake: loguea `## Módulo: CORE/PLANIFICADOR`. Al Core le envía `OP_TAM_PAGINA {uint32}`. Después llama a `atender_peticiones` |
| `atender_peticiones(socket, handshake)` | Loop `recibir_buffer` → `procesar_peticion_core` o `procesar_peticion_planificador` según quién se conectó. También maneja `OP_TEST` |
| `procesar_peticion_core(socket, op, buffer)` | `OP_FETCH_INSTRUCCION`, `OP_OBTENER_MARCO`, `OP_DESLOCKEAR_PAGINAS`, `OP_READ_MEM`, `OP_WRITE_MEM` |
| `procesar_peticion_planificador(socket, op, buffer)` | `OP_CREAR_JOB`, `OP_FINALIZAR_JOB`, `OP_ASIGNAR_ESPACIO`, `OP_LIBERAR_ESPACIO`, `OP_DESLOCKEO_PAGINAS`, `OP_CARGA_PAGINA`, `OP_LEER_DATOS`, `OP_ESCRIBIR_DATOS` |
| `atender_lectura(socket, buffer, op_rsp)` | `{jid, dir_fisica, tamaño}` → `{bool ok, bytes contenido}`. Lo usan el Core y el Planificador |
| `atender_escritura(socket, buffer, op_rsp)` | `{jid, dir_fisica, bytes contenido}` → `{bool ok}` |
| `aplicar_retardo_memoria()` *(static)* | `usleep(RETARDO_MEMORIA)` |

## `instrucciones.c` / `instrucciones.h`

> [!info] Rutas absolutas (`896a387`)
> El Job inicial (y cualquier `INIT_JOB`) puede ser relativo a `PATH_INSTRUCCIONES` o una ruta absoluta, que se usa tal cual. Lo exige la guía del CP2 de la cátedra. Ver [[Suite cátedra 2026-11-14]].
| Función | Descripción |
| --- | --- |
| `inicializar_instrucciones()` | Crea la lista de `t_job_instrucciones` |
| `crear_job(jid, nombre_archivo)` | Lee el script (`PATH_INSTRUCCIONES/<archivo>`, o la ruta tal cual si es absoluta, `armar_ruta`) línea por línea y lo guarda. Log `## JID: <j> - Job Creado`. Además llama a `crear_memoria_job` |
| `obtener_instruccion(jid, pc)` | Devuelve una copia de la línea `pc`. Log `## JID: … - Obtener instrucción: … - Instrucción: …` |
| `finalizar_job(jid)` | Libera las instrucciones y la memoria del Job (`finalizar_memoria_job`). Log `Job Finalizado` |
| `buscar_job`, `destruir_job`, `armar_ruta` | Helpers internos |
| `t_job_instrucciones` | `{jid, t_list* instrucciones (char*)}` |

## `memoria.c` / `memoria.h`

### Estructuras
```c
t_marco       { bool ocupado; uint32_t jid; uint32_t nro_pagina; }
t_pagina      { nro_pagina; presente; marco; posicion_offload; respaldo_valido;
                lockeada; uso; modificada; ultimo_acceso; }
t_reserva     { direccion_logica; tamanio_bytes; pagina_inicial; cantidad_paginas; }
t_job_memoria { jid; t_list* paginas; t_list* reservas; }
```

### Funciones
| Función | Descripción |
| --- | --- |
| `inicializar_memoria()` | Valida que el tamaño de página sea potencia de 2, reserva la memoria principal y la tabla de marcos, y llama a `inicializar_offload` |
| `inicializar_offload()` *(interna)* | Crea o trunca `PATH_OFFLOAD` de `TAM_OFFLOAD` y arma el arreglo de ocupación `espacios_offload` (una posición por página) |
| `crear_memoria_job(jid)` / `finalizar_memoria_job(jid)` | Alta y baja de `t_job_memoria`. La baja libera marcos y offload |
| `asignar_espacio(jid, tamaño, &dir_logica)` | ALLOC: calcula las páginas, busca un rango contiguo libre (`buscar_rango_libre`), reserva respaldo en offload y registra la `t_reserva` |
| `liberar_espacio(jid, dir_logica)` | FREE: busca la reserva y llama a `liberar_reserva` (marcos + offload) |
| `obtener_marco(jid, nro_pagina, &marco)` | Si la página está presente: lockea, marca uso/acceso y devuelve el marco. Si no: `false` (page fault) |
| `cargar_pagina(jid, nro_pagina)` | Resuelve el PF: busca un marco libre o elige una víctima (`seleccionar_victima`), escribe la víctima en offload si estaba modificada, trae la página de offload y aplica `RETARDO_OFFLOAD` |
| `deslockear_paginas(jid)` | Quita el lock de todas las páginas del Job |
| `leer_memoria(jid, dir_fisica, tam)` / `escribir_memoria(…)` | Acceso físico validado (`validar_acceso`: el marco tiene que pertenecer al Job y no cruzar páginas). La escritura marca la página como modificada |
| `seleccionar_victima()` | Despacha a `seleccionar_victima_lru` (menor `ultimo_acceso`) o `seleccionar_victima_clock_m` (pasadas sobre `uso`/`modificada`). **Saltea las páginas lockeadas** |
| `pagina_del_marco(marco)` | Búsqueda inversa marco → página |
| `leer_pagina_offload` / `escribir_pagina_offload` | E/S en el archivo de offload |
| `buscar_job_memoria`, `buscar_pagina`, `buscar_rango_libre`, `es_potencia_de_dos`, `validar_acceso` | Helpers |

> [!note] Contrato con el Planificador
> - `OP_CARGA_PAGINA` devuelve `false` si no hay marco libre ni víctima (todas las páginas lockeadas). El Planificador tiene que decidir si reintenta o finaliza el Job.
> - La dirección lógica que devuelve `OP_RSP_ASIGNAR` es la que el Core guarda en su registro.

## Configuración (`placa.config`)
| Clave | Ejemplo |
| --- | --- |
| `PUERTO_ESCUCHA` | 8081 |
| `LOG_LEVEL` | INFO |
| `TAM_MEMORIA` / `TAM_PAGINA` | 4096 / 64 |
| `RETARDO_MEMORIA` | 10 ms |
| `ALGORITMO_REEMPLAZO` | `LRU` \| `CLOCK-M` |
| `PATH_INSTRUCCIONES` | /home/utnso/scripts/ |
| `PATH_OFFLOAD` / `TAM_OFFLOAD` | /home/utnso/offload.dat / 65536 |
| `RETARDO_OFFLOAD` | 100 ms |
