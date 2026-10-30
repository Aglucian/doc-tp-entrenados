---
tags: [tp-so, entrenados, modulo, planificador]
modulo: planificador
rama: develop
responsables: [D1, D2]
actualizado: 2026-10-29
---

# Planificador

Volver a [[00 - Inicio]] · Depende de [[Utils]] y [[Protocolo]] · Habla con [[Core]], [[Placa]] y [[Storage]]

Administra la cola de Jobs del cluster. Se ocupa de:
- planificar a largo plazo (NEW→READY con grado de multiprogramación) y a corto plazo (FIFO, RR, HRRN)
- atender syscalls y page faults
- correr los servicios Loader/Labeler/Logger
- persistir checkpoints a través de Storage

**Ejecución:** `./bin/planificador [Archivo Config] [Path Job Inicial]`

## Estado
| Funcionalidad | Estado |
| --- | --- |
| Conexión y handshake con Placa y Storage | ✅ |
| Servidor multihilo de Cores (conexión y desconexión en runtime) | ✅ |
| Largo plazo con `GRADO_MULTIPROGRAMACION` | ✅ |
| FIFO / RR (timer de quantum con número de despacho) / HRRN | ✅ |
| Estadísticas por Job | ✅ (falta la memoria dinámica) |
| Syscalls `INIT_JOB`, `EXIT` | ✅ |
| Page fault / BLOCKED | ❌ Check 3 |
| Syscalls `ALLOC`, `FREE` | ❌ Check 3 |
| Servicios Loader / Labeler / Logger | ❌ Check 3 |
| Checkpoints | ❌ Check 4 |

Ver [[Plan de acción#Fase B: Planificador, page fault y BLOCKED (Check 3)]].

## Modelo de estados

```mermaid
stateDiagram-v2
    [*] --> NEW: crear_proceso
    NEW --> READY: largo plazo (avisar_creacion_a_placa OK)
    READY --> EXEC: corto plazo (despachar_en_core)
    EXEC --> READY: fin de quantum / Core desconectado
    EXEC --> BLOCKED: page fault / syscall bloqueante (pendiente)
    BLOCKED --> READY: servicio OK / página cargada (pendiente)
    EXEC --> EXIT: EXIT / error
    NEW --> EXIT: ERROR_PLACA
```

## Hilos
| Hilo | Función | Qué hace |
| --- | --- | --- |
| principal | `main` | Inicializa, conecta, crea el Job 0 y espera al servidor de Cores |
| largo plazo | `planificar_largo_plazo` | `sem_new` + `sem_multiprogramacion` → crea el Job en la Placa → READY |
| corto plazo | `planificar_corto_plazo` | `sem_ready` → espera un Core libre → elige un Job según el algoritmo → despacha → en RR lanza el timer |
| servidor Cores | `atender_conexiones_de_cores` | `accept` en loop; un hilo por conexión |
| conexión entrante | `hilo_conexion_entrante` | Handshake; si es Core lo registra y entra a `atender_core` |
| timer de quantum | `contar_quantum` | Duerme `RR_QUANTUM` ms e interrumpe si el despacho sigue vigente (detached) |

## Sincronización
- `mutex_procesos`, `mutex_new` y `mutex_ready` protegen la lista global y las colas
- `sem_new` y `sem_ready` cuentan los Jobs disponibles en cada cola
- `sem_multiprogramacion` se inicializa en `GRADO_MULTIPROGRAMACION`; se libera en `finalizar_proceso`
- `mutex_placa` hace atómico cada par pedido/respuesta sobre `socket_placa`
- `mutex_cores` protege la lista de Cores; `sem_cores_libres` cuenta los Cores sin Job (`esperar_core_libre`)
- `t_core.mutex_socket` serializa los envíos a un Core (despacho, interrupción, respuesta de syscall)

---

## `main.c`
| Función | Firma | Descripción |
| --- | --- | --- |
| `main` | `int main(int argc, char* argv[])` | Valida los args → `cargar_config` → `inicializar_planificador` → `conectar_a_modulos` → servidor de Cores → `crear_proceso(job_inicial)` → hilos → espera y limpia |
| `cargar_config` | `static bool cargar_config(void)` | Abre el config, crea el logger, exige las 14 claves y llena `t_planificador` |
| `validar_algoritmo` | `static bool validar_algoritmo(void)` | Acepta solo `FIFO`, `RR` o `HRRN` |

### `t_planificador` (`main.h`)
Es el estado global (`extern planificador`):
- args: `archivo_config`, `path_job_inicial`
- `config`, `logger`
- todas las claves del config tipadas
- sockets: `socket_placa`, `socket_storage`, `socket_servidor`

## `planificacion.c` / `planificacion.h`

### Tipos
- `t_estado`: `NEW`, `READY`, `EXEC`, `BLOCKED`, `EXIT`
- `t_proceso`:
  - identificación: `pid`, `estado`, `path`
  - `contexto`, `creado_en_placa`, `estimacion_rafaga`
  - tiempos: `tiempo_creacion`, `tiempo_entrada_estado`, `tiempo_acumulado_new/ready`
  - contadores: `transiciones_ready_exec`, `cantidad_syscalls`, `cantidad_page_faults`, `memoria_dinamica_maxima`
- `t_algoritmo` (privado): `FIFO`, `RR`, `HRRN`
- `t_quantum` (privado): `{id_core, numero_despacho}`

### Funciones públicas
| Función | Firma | Descripción |
| --- | --- | --- |
| `inicializar_planificador` | `bool (void)` | Lee el algoritmo, crea las listas y colas e inicializa los semáforos |
| `iniciar_hilos_planificador` | `bool (void)` | Lanza los hilos de largo y corto plazo |
| `finalizar_planificador` | `void (void)` | Destruye las colas, los procesos y los semáforos |
| `crear_proceso` | `t_proceso* (const char* path)` | Asigna el PID, estado NEW y estimación inicial; log de creación; encola en NEW |
| `buscar_proceso` | `t_proceso* (uint32_t pid)` | Búsqueda lineal bajo `mutex_procesos` |
| `desalojar_por_fin_de_quantum` | `void (t_proceso*)` | Log de desalojo + `devolver_a_ready` |
| `devolver_a_ready` | `void (t_proceso*)` | Cambia a READY y encola |
| `finalizar_proceso` | `void (t_proceso*, const char* motivo)` | EXIT → `avisar_finalizacion_a_placa` → log de estadísticas → libera → `sem_post(multiprogramación)` |
| `registrar_syscall` | `void (t_proceso*, t_syscall)` | `cantidad_syscalls++` y log `Solicitó syscall` |
| `nombre_estado` | `const char* (t_estado)` | Pasa el enum a texto |
| `capturar_tiempo` | `uint64_t (void)` | ms con `CLOCK_MONOTONIC` |

### Funciones internas
| Función | Descripción |
| --- | --- |
| `leer_algoritmo` | Pasa `ALGORITMO_PLANIFICACION` a `t_algoritmo` |
| `encolar_new` / `sacar_de_new` | FIFO sobre `cola_new` con mutex y semáforo |
| `encolar_ready` | Agrega a `cola_ready` + `sem_post(sem_ready)` |
| `calcular_prioridad_hrrn` | `(W + S) / S`, con W = espera en READY y S = estimación (mínimo 1) |
| `indice_mayor_prioridad_hrrn` | Recorre READY, loguea la prioridad de cada Job y elige el máximo (ante empate, el primero que llegó) |
| `sacar_de_ready` | Saca el índice 0 (FIFO/RR) o el de mayor prioridad (HRRN) |
| `cambiar_estado` | Acumula tiempos de NEW/READY, cuenta READY→EXEC, **recalcula la estimación al salir de EXEC** (`α·real + (1−α)·anterior`) y loguea el cambio |
| `liberar_proceso` | `free` del path y del struct |
| `planificar_largo_plazo` | Hilo: NEW → crear en Placa → READY (si falla: `ERROR_PLACA`) |
| `lanzar_timer_de_quantum` | Crea el hilo `contar_quantum` detached |
| `planificar_corto_plazo` | Hilo: espera Job y Core → EXEC → despacha (si el Core se cayó, vuelve a READY) → timer si es RR |
| `dormir_ms` | `nanosleep` que se reintenta si lo interrumpe una señal |
| `contar_quantum` | Duerme el quantum → `interrumpir_core_si_sigue_ocupado` |

## `comunicacion.c` / `comunicacion.h`

### `t_core`
```c
typedef struct {
    int socket;
    uint32_t id_core;            // informado en el handshake
    uint32_t jid_asignado;       // JID_LIBRE (UINT32_MAX) si está libre
    uint64_t numero_despacho;    // cambia en cada despacho y liberación
    pthread_t hilo;
    pthread_mutex_t mutex_socket;
} t_core;
```

### Cliente (Placa / Storage)
| Función | Descripción |
| --- | --- |
| `conectar_e_identificarse` *(static)* | `crear_conexion` + `handshake_cliente` como `MODULO_PLANIFICADOR` |
| `conectar_a_modulos` | Conecta a Placa y Storage; si falla, el `main` aborta |
| `desconectar_de_modulos` | Cierra ambos sockets |
| `avisar_creacion_a_placa` | `OP_CREAR_JOB {jid, path}` → espera `OP_RSP_CREAR_JOB {ok}` (bajo `mutex_placa`) |
| `avisar_finalizacion_a_placa` | `OP_FINALIZAR_JOB {jid}` → espera `OP_RSP_FINALIZAR {ok}` |

### Servidor de Cores
| Función | Descripción |
| --- | --- |
| `inicializar_cores` | Crea la lista de Cores e inicializa `sem_cores_libres` |
| `iniciar_servidor_cores` | `crear_servidor(PUERTO_ESCUCHA)` |
| `inicializar_hilo_servidor_cores` / `esperar_hilo_servidor_cores` | Lanzan el hilo de `accept` y lo esperan con join |
| `atender_conexiones_de_cores` *(static)* | Loop de `esperar_cliente` → hilo `hilo_conexion_entrante` |
| `hilo_conexion_entrante` *(static)* | Recibe el handshake, loguea `## Módulo: …`, rechaza si no es Core, registra y atiende |
| `atender_core` *(static)* | Loop `recibir_buffer`: `OP_TEST`, `OP_DEVOLUCION`, `OP_SYSCALL`; si el Core se desconecta, `eliminar_core` |
| `manejar_test` *(static)* | Eco de la prueba de serialización del Check 1 |
| `registrar_core` / `eliminar_core` *(static)* | Alta y baja en la lista. Al eliminar, si tenía un Job en EXEC lo devuelve a READY |
| `buscar_core` *(static)* | Por `id_core` |
| `liberar_core` *(static)* | Si el Core ejecuta ese `pid`: lo marca libre, cambia `numero_despacho` y hace `sem_post(sem_cores_libres)` |
| `core_esta_ejecutando` *(static)* | Verifica `jid_asignado == pid` |
| `esperar_core_libre` | Bloquea hasta que haya un Core con `JID_LIBRE` y devuelve su id |
| `despachar_en_core` | Asigna el Job, incrementa `numero_despacho` y envía `OP_EJECUTAR_JOB {jid, contexto}` |
| `interrumpir_core_si_sigue_ocupado` | Si el despacho es el mismo, envía `OP_INTERRUPCION {uint32 jid, uint32 motivo}` |
| `recibir_devolucion` *(static)* | Lee `{jid, motivo, contexto}`, guarda el contexto, libera el Core y actúa según el motivo: `FIN_QUANTUM`→READY, `EXIT`→EXIT, otro→`MOTIVO_NO_SOPORTADO` |
| `responder_syscall` *(static)* | `OP_RSP_SYSCALL {bool ok, uint32 valor}` |
| `crear_job_pedido` *(static)* | `INIT_JOB`: lee el `string path`, llama a `crear_proceso` y responde `valor = pid` |
| `recibir_syscall` *(static)* | Lee `{id, jid, contexto}`, valida que el Core ejecute ese Job, guarda el contexto y registra la syscall. Despacha `INIT_JOB` / `EXIT`; el resto devuelve "no soportada" |
| `cantidad_cores_conectados` | Tamaño de la lista |
| `destruir_cores` | Libera la lista y los mutex |

> [!warning] Pendiente en `recibir_devolucion` / `recibir_syscall`
> Falta `DEVOLUCION_PAGE_FAULT`, que trae además un `uint32 nro_pagina`. También faltan las syscalls `ALLOC`/`FREE` (con respuesta) y las bloqueantes (sin respuesta: hay que llamar a `liberar_core`). Los formatos están en [[Protocolo#Payloads Core → Planificador]].

## Configuración (`planificador.config`)
| Clave | Ejemplo | Uso |
| --- | --- | --- |
| `PUERTO_ESCUCHA` | 8080 | servidor de Cores |
| `IP_PLACA` / `PUERTO_PLACA` | 127.0.0.1 / 8081 | cliente |
| `IP_STORAGE` / `PUERTO_STORAGE` | 127.0.0.1 / 8082 | cliente |
| `LOG_LEVEL` | INFO | |
| `ALGORITMO_PLANIFICACION` | FIFO \| RR \| HRRN | |
| `RR_QUANTUM` | 1500 | ms |
| `ESTIMACION_INICIAL` | 10000 | ms (HRRN) |
| `HRRN_ALFA` | 0.5 | |
| `GRADO_MULTIPROGRAMACION` | 4 | |
| `PATH_DATOS` | /home/utnso/datos/ | Loader |
| `RETARDO_LOADER` | 500 | ms |
| `PATH_REPORTES` | /home/utnso/reportes.log | Logger (distinto del log del módulo) |
