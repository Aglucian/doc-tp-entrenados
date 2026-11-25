---
tags: [tp-so, entrenados, coloquio, teoria]
actualizado: 2026-11-24
---

# Teoría vs implementación

Volver a [[00 - Inicio]] · Ver también [[Concurrencia y sincronización]], [[Decisiones de diseño]]

El coloquio evalúa que la implementación **no contradiga la teoría**. Esta nota une cada concepto de la materia con dónde aparece en el TP, y lista preguntas probables.

## Procesos y planificación

| Concepto de la teoría | En el TP |
| --- | --- |
| Proceso y su PCB | El Job y su `t_proceso`: JID, estado, contexto (14 registros), estadísticas |
| Diagrama de 5 estados | NEW, READY, EXEC, BLOCKED, EXIT; cada transición se loguea |
| Planificador de largo plazo y grado de multiprogramación | Hilo de largo plazo + `sem_multiprogramacion`; al admitir un Job se crean sus estructuras en la Placa |
| Planificador de corto plazo | Hilo de corto plazo: elige de READY y despacha a un Core libre |
| Cambio de contexto | El Core devuelve `OP_DEVOLUCION {jid, motivo, contexto}`; el Planificador guarda el contexto y lo vuelve a mandar en el próximo despacho |
| FIFO | Sin desalojo; puede haber efecto convoy |
| Round Robin | FIFO + interrupción por quantum (`RR_QUANTUM`); el timer es un hilo por despacho |
| HRRN | No expropiativo; `RR = (W + S) / S` con S estimada por media exponencial (`α · R + (1 − α) · S`); favorece a los cortos sin inanición de los largos (*aging* implícito por W) |
| Interrupción | `OP_INTERRUPCION {jid, FIN_QUANTUM}`; el Core la atiende en el Check Interrupt, al final de cada instrucción |
| Syscall / modo kernel | Las instrucciones que el Core no resuelve (`ALLOC`, `LOAD_BATCH`, …) se piden al Planificador, que hace de kernel |
| E/S bloqueante | Los servicios (Loader, Labeler, Logger, Checkpoints) bloquean al Job; el Core queda libre para otro |
| Multiprocesador | N Cores ejecutando en paralelo; el Planificador los ve como CPUs |

**Preguntas probables**
- ¿HRRN es expropiativo? No: la estimación se recalcula al salir de EXEC y solo se usa para elegir en READY.
- ¿Puede haber inanición con HRRN? No: W crece mientras el Job espera, y su *response ratio* termina superando al de cualquier otro.
- ¿Qué pasa si vence el quantum justo cuando el Job ya volvió por una syscall? El número de despacho no coincide y la interrupción no se manda; si llega igual al Core, la descarta porque el JID no es el que ejecuta.

## Memoria

| Concepto de la teoría | En el TP |
| --- | --- |
| Paginación | Memoria de usuario dividida en marcos de `TAM_PAGINA`; cada Job tiene su tabla de páginas |
| Dirección lógica → física | MMU del Core: `pagina = dir / TAM`, `desplazamiento = dir % TAM`, `fisica = marco · TAM + desplazamiento` |
| Fragmentación interna | Sí: la última página de una reserva puede quedar a medias. Externa no |
| Memoria virtual / paginación bajo demanda | Las páginas reservadas arrancan no presentes; se cargan recién cuando se usan (page fault) |
| Page fault | El Core devuelve el Job con `PAGE_FAULT` sin avanzar el PC; el Planificador lo bloquea y pide la carga; al volver, la instrucción se reintenta |
| Área de swap | El **Offload**: un archivo con un espacio reservado por página |
| Reemplazo global | La víctima puede ser de cualquier Job (no hay marcos fijos por Job) |
| LRU | Contador global de accesos; víctima = menor `ultimo_acceso` |
| Clock mejorado (CLOCK-M) | Puntero circular; busca (u=0, m=0), después (u=0, m=1) apagando el bit de uso, hasta 4 vueltas |
| Bit de modificado | Solo se escribe en el Offload la víctima modificada (o la que nunca tuvo copia) |
| Bloqueo de páginas (*page locking*) | Las páginas de una instrucción o de un servicio quedan lockeadas y nunca son víctimas; como los buffers de E/S en la teoría |
| Thrashing | Si un rango necesita más páginas que marcos, el Job entra en un ciclo de page faults: es un límite documentado del TP (ver [[Bugs encontrados#Livelock con rangos más grandes que la memoria]]) |
| Memoria dinámica (heap) | `ALLOC`/`FREE` reservan y liberan en la Placa; la estadística guarda el máximo ocupado |

**Preguntas probables**
- ¿Por qué el PC no avanza en un page fault? Porque la instrucción no se ejecutó: se reintenta completa cuando la página está.
- ¿Por qué hay que lockear? Para que entre la traducción y el acceso la página no sea elegida como víctima.
- ¿Hay TLB? No, el enunciado no la pide: cada traducción le pregunta el marco a la Placa.

## Sistema de archivos

| Concepto de la teoría | En el TP |
| --- | --- |
| Asignación enlazada con tabla (FAT) | Cada entrada de la FAT apunta al bloque siguiente; `0` libre, `0x0FFFFFFF` fin, `0x0FFFFFFE` reservado |
| Superbloque | Bloque 0: firma `FAT32_TRAIN`, tamaño de bloque, cantidad de bloques y bloques de directorio |
| Directorio | Entradas de 32 bytes: estado, nombre (23), tamaño, bloque inicial |
| Acceso secuencial vs directo | Para llegar al bloque *n* de un checkpoint hay que recorrer la cadena de la FAT |
| Fragmentación | Interna en el último bloque; externa no (los bloques no necesitan ser contiguos) |
| Journaling (*write-ahead logging*) | El asiento se escribe y se sincroniza (`fsync`) **antes** de tocar el volumen; COMMIT y APPLIED marcan el avance |
| Recuperación ante fallas | Al arrancar: sin COMMIT se descarta, COMMIT sin APPLIED se re-aplica (*redo*) |
| Idempotencia | Las modificaciones guardan el valor final, así que aplicar dos veces da lo mismo |

**Preguntas probables**
- ¿Qué se pierde con un `kill -9` antes del COMMIT? La operación completa, pero el volumen queda consistente (estado anterior).
- ¿Por qué se puede re-aplicar un asiento que ya se había aplicado a medias? Porque es idempotente: cada OP lleva el valor final del bloque, de la entrada de la FAT o del directorio.
- ¿Por qué journaling de datos y no solo de metadatos? El enunciado pide asentar todas las modificaciones (`OP_WRITE` incluidas); así también los datos quedan consistentes.

## Comunicación y concurrencia

| Concepto de la teoría | En el TP |
| --- | --- |
| IPC por sockets, cliente-servidor | 4 procesos que solo se comunican por TCP; protocolo propio `op_code \| size \| payload` |
| Serialización | `t_buffer`: datos uno detrás de otro, se leen en el mismo orden |
| Hilos | Un hilo por conexión, hilos de planificación, de servicios y timers |
| Exclusión mutua | Mutex por recurso compartido (colas, sockets, memoria, volumen) |
| Productor-consumidor | Colas de NEW, READY y de cada servicio con su semáforo contador |
| Deadlock | Se evita con orden fijo de locks y sin locks anidados entre módulos |
| Espera activa | No hay: todo bloquea en semáforos, `accept`, `recv`, `getline` o `sigwait` |
| Señales | SIGINT/SIGTERM bloqueadas en todos los hilos y atendidas por un hilo con `sigwait()` |

Detalle en [[Concurrencia y sincronización]].
