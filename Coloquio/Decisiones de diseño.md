---
tags: [tp-so, entrenados, coloquio, diseño]
actualizado: 2026-11-24
---

# Decisiones de diseño

Volver a [[00 - Inicio]] · Ver también [[Bugs encontrados]], [[Teoría vs implementación]], [[Concurrencia y sincronización]]

El enunciado deja varios puntos a criterio del grupo, y "las justificaciones deberán ser expuestas en el coloquio". Cada decisión va con su alternativa y por qué se eligió.

## Planificador

| Decisión | Alternativa | Por qué |
| --- | --- | --- |
| Si un Core se cae con un Job en EXEC, el Job vuelve a **READY** con el último contexto guardado y se deslockean sus páginas | Finalizar el Job con error | Un Core que se desconecta no es un error del Job; las pruebas de estabilidad conectan y desconectan Cores con Jobs en curso |
| Un solo socket con la Placa, y pedido + respuesta bajo `mutex_placa` | Un socket por hilo | Más simple y suficiente: la Placa responde rápido y el costo real son sus retardos. Evita respuestas cruzadas |
| El timer de quantum es un hilo por despacho y guarda `id_core` + número de despacho | Un único hilo reloj | Validar el número de despacho hace inofensiva una interrupción tardía |
| HRRN recalcula la estimación cada vez que el Job sale de EXEC (por cualquier motivo) | Solo al bloquearse | Toda ráfaga terminada aporta información sobre la próxima |
| Un hilo y una cola FIFO por servicio, más uno para Checkpoints | Un hilo por petición | El enunciado pide atender de a una petición por servicio; los distintos servicios sí corren en paralelo |
| El deslockeo se hace siempre, aunque el servicio falle, y después se finaliza el Job | Finalizar sin deslockear | Las páginas lockeadas nunca serían víctimas y los marcos quedarían perdidos |
| `ALLOC` sin espacio responde `{false}` y finaliza el Job (`OUT_OF_MEMORY`); `FREE` inválido responde `{false}` y el Job sigue | Finalizar en los dos casos | Un `FREE` de una dirección inválida no compromete la memoria del Job; quedarse sin Offload sí |
| `DELETE_CHECKPOINT` de uno inexistente solo se informa | Finalizar el Job | Lo pide el enunciado |
| Directorio lleno y falta de espacio terminan los dos en `SIN_ESPACIO_STORAGE` | Un motivo por causa | El protocolo devuelve solo `ok`; el Storage sí loguea cada causa por separado, que es lo que pide el enunciado |
| No hay reconexión automática al Storage | Reintentar la conexión | Si el Storage se cae, el Job en curso termina con `ERROR_STORAGE` sin colgar al Planificador; para seguir se repite el escenario |

## Core

| Decisión | Alternativa | Por qué |
| --- | --- | --- |
| Todas las traducciones de una instrucción se resuelven antes de ejecutarla | Traducir a medida que se accede | Lo pide el enunciado: si hay page fault, no quedó nada a medio escribir y la instrucción se reintenta entera |
| En un page fault se deslockean las páginas que ya se habían obtenido antes de devolver el Job | Dejarlas lockeadas | Mientras el Job está bloqueado, esas páginas pueden reemplazarse sin problema |
| La interrupción que llega mientras se espera la respuesta de una syscall se guarda y se atiende en el próximo Check Interrupt | Descartarla | Si se descartara, el Job no se desalojaría al vencer su quantum |
| Con `ALLOC` rechazado, el Core abandona el Job sin devolverlo | Devolverlo con `EXIT` | El Planificador ya lo finalizó: devolverlo sería mandar un Job inexistente |

## Placa

| Decisión | Alternativa | Por qué |
| --- | --- | --- |
| Reemplazo **global**: la víctima puede ser de cualquier Job | Asignación fija de marcos por Job | El enunciado no define marcos por Job, y así se aprovecha toda la memoria |
| CLOCK-M con hasta 4 vueltas: (0,0) sin tocar bits, (0,1) apagando el bit de uso, y repite | Variantes de 2 vueltas | Es el algoritmo de clock mejorado de la teoría; la tercera y cuarta vuelta cubren el caso en que todas tenían el bit de uso |
| Al hacer `ALLOC` se reserva el lugar de cada página en el Offload | Reservar recién al bajarla | Garantiza que una página siempre se pueda bajar; si no hay lugar, se rechaza el `ALLOC` (y el Job termina con `OUT_OF_MEMORY`) |
| Se escribe en el Offload la víctima modificada **o la que nunca tuvo copia** | Solo las modificadas | Una página que nunca se respaldó no tiene contenido en el Offload |
| Un solo `mutex_memoria` para toda la memoria | Un lock por marco o por Job | Las operaciones son cortas y el reemplazo toca estructuras de varios Jobs a la vez |
| `RETARDO_MEMORIA` fuera del mutex | Dentro | Un pedido esperando su retardo no frena a los demás Cores |
| Acepta rutas absolutas para el Job inicial | Solo relativas a `PATH_INSTRUCCIONES` | La guía de pruebas pasa el Job inicial con `$PWD/scripts/…` |

## Storage

| Decisión | Alternativa | Por qué |
| --- | --- | --- |
| Al guardar sobre un checkpoint existente se reutilizan sus bloques en orden, se piden los que faltan y se liberan los que sobran | Liberar todo y volver a asignar | Menos escrituras en la FAT y lo pide el enunciado ("liberar aquellos que dejen de ser necesarios") |
| Journal de texto con el **valor final** de cada modificación (`OP_DIR`, `OP_FAT`, `OP_WRITE` con el bloque en hexadecimal) | Guardar diferencias | Hace que re-aplicar sea idempotente |
| `fwrite` + `fflush` + `fsync` por línea del asiento | Solo al COMMIT | Lo pide el enunciado para el primer paso |
| Un único `fs.mutex` para todo el filesystem | Locks por región | Los asientos no se pueden intercalar y las operaciones cruzan superbloque, FAT, directorio y datos |
| El volumen se mapea en memoria y los retardos se aplican por bloque accedido | `read`/`write` por bloque | Acceso simple a cualquier región; `RETARDO_ACCESO_BLOQUE` respeta cada acceso |
| Volumen inexistente → se formatea al arrancar | Fallar | Lo pide el enunciado |

## Transversales

| Decisión | Alternativa | Por qué |
| --- | --- | --- |
| Un solo header de protocolo (`protocolo_entrenados.h`) para todos | Structs por módulo | En el TP anterior la duplicación causó incompatibilidades; ver [[Bugs encontrados]] |
| `t_buffer` que se marca inválido si una lectura se pasa del final | Confiar en el tamaño | Un mensaje truncado se descarta en lugar de leer basura |
| Ctrl-C: señales bloqueadas en todos los hilos y un hilo con `sigwait()` que loguea y re-envía la señal | `exit()` en un handler | `exit()` se colgaba con un hilo bloqueado en `stdin`, y `_exit()` no terminaba bajo valgrind (ver [[Utils#`cierre.c` / `cierre.h`: Ctrl-C y SIGTERM]]) |

## Límites aceptados

| Límite | Alternativa | Por qué se acepta |
| --- | --- | --- |
| Si una instrucción o syscall necesita a la vez más páginas que marcos, el Job queda en un ciclo de page faults (livelock) | Que el Core conozca la cantidad de marcos y devuelva el Job con error | Es una precondición del modelo (no se puede fijar en memoria más que la memoria física) y un caso extremo de thrashing. La cátedra dijo que no lo testea ([#5328](https://github.com/sisoputnfrba/foro/issues/5328)), las pruebas tienen como mínimo 16 marcos, y corregirlo cambiando las reglas del enunciado sería *hold and wait*. Detalle en [[Bugs encontrados#Livelock con rangos más grandes que la memoria]] |
