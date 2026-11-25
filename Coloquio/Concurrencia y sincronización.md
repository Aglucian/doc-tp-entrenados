---
tags: [tp-so, entrenados, coloquio, concurrencia]
actualizado: 2026-11-24
---

# Concurrencia y sincronización

Volver a [[00 - Inicio]] · Ver también [[Planificador]], [[Placa]], [[Storage]], [[Core]], [[Decisiones de diseño]]

Qué hilos tiene cada módulo, qué comparten y con qué se protege. Todo sale del código de `develop`.

## Resumen por módulo

| Módulo | Hilos | Recursos compartidos | Protección |
| --- | --- | --- | --- |
| Planificador | largo plazo, corto plazo, servidor de Cores, 1 por Core, 1 por page fault, 1 timer por despacho (RR), 4 de servicios, cierre | colas de estados, lista de Cores, socket de la Placa, socket del Storage, socket de cada Core, colas de servicios | 8 mutex + 5 tipos de semáforo (abajo) |
| Placa | principal (`accept`), 1 por conexión (Planificador y cada Core), consola, cierre | marcos, tablas de páginas, bitmap del Offload, archivo de Offload, lista de instrucciones | `mutex_memoria`, `mutex_offload`, `mutex_jobs` |
| Core | principal (un solo hilo de ejecución) y cierre | nada: ejecuta un Job por vez | no necesita mutex |
| Storage | principal (`accept`), 1 por conexión del Planificador, consola | volumen (superbloque, FAT, directorio, datos) y journal | un único `fs.mutex` |

## Planificador

### Semáforos
| Semáforo | Cuenta | `wait` | `post` |
| --- | --- | --- | --- |
| `sem_new` | Jobs en NEW | largo plazo | al crear un Job |
| `sem_multiprogramacion` | lugares libres (arranca en `GRADO_MULTIPROGRAMACION`) | largo plazo, antes de pasar un Job a READY | al finalizar un Job |
| `sem_ready` | Jobs en READY | corto plazo | cada vez que un Job entra a READY |
| `sem_cores_libres` | Cores sin Job | corto plazo (`esperar_core_libre`) | al conectarse un Core o al liberarse |
| `pendientes` (uno por servicio) | peticiones en la cola del servicio | el hilo del servicio | al encolar una syscall bloqueante |

El corto plazo hace `sem_wait(sem_ready)` y después `esperar_core_libre()`: **solo despacha cuando hay un Job y un Core**, sin espera activa.

### Mutex
| Mutex | Protege |
| --- | --- |
| `mutex_new`, `mutex_ready` | Las colas de NEW y READY |
| `mutex_procesos` | La lista de todos los Jobs (búsqueda por JID) |
| `mutex_cores` | La lista de Cores, su `jid_asignado` y su `numero_despacho` |
| `mutex_socket` (uno por Core) | Los envíos a ese Core: despacho, interrupción y respuesta de syscall pueden venir de hilos distintos |
| `mutex_placa` | **Pedido y respuesta** a la Placa como una unidad: hay un solo socket y lo usan el largo plazo, los page faults y los servicios |
| `mutex_storage` | Lo mismo con el socket del Storage |
| `mutex_cola` (uno por servicio) | La cola FIFO del servicio |

### Problemas de concurrencia que se resolvieron
- **Respuestas cruzadas en un socket compartido:** si dos hilos mandan pedidos a la Placa y después leen, cada uno puede leer la respuesta del otro. Por eso pedido y respuesta van juntos bajo `mutex_placa`.
- **Interrupción tardía (race del quantum):** el timer de RR guarda `id_core` + `numero_despacho`, no un puntero al Job. Antes de interrumpir verifica, bajo `mutex_cores`, que el Core siga en **el mismo despacho**. Si el Job ya volvió por otro motivo, la interrupción no se manda.
- **Contexto perdido:** el contexto se guarda apenas llega la devolución, antes de reaccionar al motivo.
- **Páginas lockeadas huérfanas:** todo camino de salida de un servicio deslockea, también los errores; si un Core se cae con un Job en EXEC, el hilo de ese Core deslockea y devuelve el Job a READY.
- **stdin:** solo lo lee el hilo del Labeler, y atiende una petición por vez (cola FIFO).

## Placa
- `mutex_memoria`: marcos, tablas de páginas, bits de uso y modificado, contador de LRU y puntero de CLOCK-M. Toda operación de memoria (obtener marco, cargar página, leer, escribir, deslockear, asignar, liberar) lo toma completa.
- `mutex_offload`: el archivo de Offload (`fseek` + `fread`/`fwrite`). Se toma **dentro** de `mutex_memoria` cuando una carga de página baja una víctima o sube una página. Orden fijo: primero memoria, después Offload → no hay espera circular.
- `mutex_jobs`: la lista de instrucciones de cada Job (crear, buscar para FETCH, finalizar).
- `RETARDO_MEMORIA` se aplica en el hilo de la conexión **fuera** del mutex: un Core esperando su retardo no frena a los demás. `RETARDO_OFFLOAD` se aplica con `mutex_offload` tomado.

## Storage
- Un único `fs.mutex` serializa todas las operaciones: guardar, cargar, eliminar y también los comandos de consola (`WRITE`, `RM`, `LS`, …).
- El asiento del journal se escribe y se aplica dentro de la misma sección crítica: nunca hay dos asientos intercalados.
- `RETARDO_ACCESO_BLOQUE` y `RETARDO_COMMIT` se aplican con el mutex tomado: las operaciones son lentas pero atómicas respecto de las demás.

## Core
- Un solo hilo ejecuta el ciclo de instrucción: no hay datos compartidos entre hilos.
- Lo único asincrónico es la interrupción, que llega por el socket del Planificador. Se consulta en el Check Interrupt con `recv(MSG_PEEK | MSG_DONTWAIT)`, que no bloquea. Si llega mientras se espera la respuesta de una syscall, se guarda en `interrupcion_guardada`.

## Señales (todos los módulos)
- SIGINT/SIGTERM se bloquean en el `main` antes de crear hilos, y un hilo dedicado las espera con `sigwait()` (ver [[Utils#`cierre.c` / `cierre.h`: Ctrl-C y SIGTERM]]). Así ninguna señal corta un `accept()`, `recv()` o `usleep()` a mitad de camino.

## Deadlock, inanición y espera activa
- **Deadlock:** cada módulo toma los mutex en un orden fijo (Placa: memoria → Offload; Planificador: `mutex_cores` → `mutex_socket` del Core), y los pedidos a otros módulos no anidan locks de dos sockets.
- **Inanición:** FIFO y RR no tienen. HRRN tampoco, porque la espera `W` hace crecer el *response ratio* (*aging*). Los servicios atienden en orden FIFO.
- **Espera activa:** todos los hilos se bloquean en semáforos, `accept()`, `recv()`, `getline()` o `sigwait()`. Se verificó midiendo la CPU en reposo: 0,0 % en los 4 módulos (ver [[Pruebas finales 2026-11-24#06 · Esperas activas y memory leaks]]).
