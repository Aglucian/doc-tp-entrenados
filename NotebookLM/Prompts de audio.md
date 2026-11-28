---
tags: [tp-so, entrenados, notebooklm, coloquio]
actualizado: 2026-11-24
---

# Prompts para audios de NotebookLM

Volver a [[00 - Inicio]] · Ver también [[Presentación - Funcionamiento del TP]], [[Teoría vs implementación]]

Diez audios (*Audio Overview*) para estudiar el TP y preparar el coloquio. Cada uno indica qué fuentes cargar, qué formato y largo elegir, y el texto para **Personalizar**.

## Cómo armarlo

1. Crear **un solo cuaderno** en NotebookLM y subir todas las fuentes de la tabla de abajo (los `.md` y los `.pdf` se suben tal cual).
2. En **Configuración → Idioma de salida**, elegir **Español**.
3. Para cada audio: en el panel de fuentes **tildar solo las fuentes de ese audio** y destildar el resto. Después, en *Resumen de audio* → **Personalizar**: elegir formato y duración, pegar el prompt y generar.
4. Escuchar en orden: del 1 al 7 se aprende el TP; el 8, el 9 y el 10 son para el coloquio y el día de la entrega.

### Fuentes

| Id | Archivo | Dónde está |
| --- | --- | --- |
| **ENUNCIADO** | `Repo TP/doc/TP 2C2026 - EntrenadOS.md` | este vault |
| **PRESENTACION** | `TP EntrenadOS - Presentación.pdf` | raíz de este vault |
| **INICIO** | `00 - Inicio.md` | raíz de este vault |
| **PROTOCOLO** | `Módulos/Protocolo.md` | este vault |
| **UTILS** | `Módulos/Utils.md` | este vault |
| **PLANIFICADOR** | `Módulos/Planificador.md` | este vault |
| **CORE** | `Módulos/Core.md` | este vault |
| **PLACA** | `Módulos/Placa.md` | este vault |
| **STORAGE** | `Módulos/Storage.md` | este vault |
| **CONCURRENCIA** | `Coloquio/Concurrencia y sincronización.md` | este vault |
| **TEORIA** | `Coloquio/Teoría vs implementación.md` | este vault |
| **DECISIONES** | `Coloquio/Decisiones de diseño.md` | este vault |
| **BUGS** | `Bugs encontrados.md` | este vault |
| **DESPLIEGUE** | `Despliegue distribuido.md` | este vault |
| **FINALES** | `Pruebas/Pruebas finales 2026-11-24.md` | este vault |
| **CHECK4** | `Pruebas/Check 4 2026-11-14.md` | este vault |
| **MINI** | `Pruebas/Mini Entrenamiento 2026-11-14.md` | este vault |

> [!tip] Si el audio se va por las ramas
> Con menos fuentes tildadas, el audio es más preciso. El **ENUNCIADO** completo es largo: solo va en los audios donde importa contrastar con lo que pide la cátedra.

---

## 1 · El TP en una mirada
- **Fuentes:** PRESENTACION, INICIO, ENUNCIADO
- **Formato:** Análisis en profundidad · **Duración:** predeterminada

```
Explicá el TP EntrenadOS a un estudiante del grupo que tiene que defenderlo en un coloquio. Empezá por qué simula (un cluster que entrena modelos con Jobs) y por qué el diseño necesita paginación con Offload y checkpoints persistentes. Presentá los 4 módulos (Planificador, Core, Placa, Storage) con una analogía con un sistema operativo real, cómo se conectan (quién es cliente y quién servidor, puertos 8080, 8081 y 8082) y el orden de arranque. Recorré el ciclo de vida completo de un Job desde que se crea hasta que finaliza, nombrando qué módulo interviene en cada paso. Usá los nombres reales de los mensajes y de los logs, no inventes funcionalidades que no estén en las fuentes y terminá con un resumen de 5 ideas clave.
```

## 2 · Protocolo y conexiones
- **Fuentes:** PROTOCOLO, UTILS, PRESENTACION
- **Formato:** Resumen breve · **Duración:** más corta

```
Explicá cómo se comunican los módulos del TP. Detallá el formato de cada mensaje en el socket (op_code de 1 byte, size de 4 bytes, payload), cómo t_buffer serializa y deserializa los datos y qué pasa cuando un mensaje llega truncado. Explicá el handshake y por qué la Placa le manda el tamaño de página al Core. Mencioná los rangos de opcodes por par de módulos y por qué hay un único header de protocolo compartido. Cerrá con dos errores típicos de serialización que el diseño evita.
```

## 3 · Planificador
- **Fuentes:** PLANIFICADOR, CONCURRENCIA, PRESENTACION, ENUNCIADO
- **Formato:** Análisis en profundidad · **Duración:** más larga

```
Explicá a fondo el módulo Planificador del TP. Cubrí: los hilos que tiene y qué hace cada uno; el diagrama de estados NEW, READY, EXEC, BLOCKED y EXIT con cada transición; el largo plazo y el grado de multiprogramación; el corto plazo con FIFO, Round Robin y HRRN, incluyendo la fórmula del response ratio y la de la estimación exponencial con alfa, y un ejemplo numérico; cómo se resuelve un page fault; las syscalls que bloquean y las que no; los servicios Loader, Labeler y Logger; los checkpoints contra el Storage; y las estadísticas al finalizar. Explicá por qué el timer de quantum usa un número de despacho y por qué pedido y respuesta a la Placa van bajo el mismo mutex. Citá los logs obligatorios cuando corresponda.
```

## 4 · Core y MMU
- **Fuentes:** CORE, PROTOCOLO, PRESENTACION, ENUNCIADO
- **Formato:** Análisis en profundidad · **Duración:** predeterminada

```
Explicá el módulo Core del TP como si fuera una CPU. Recorré el ciclo fetch, decode, execute y check interrupt. Explicá la MMU con la fórmula de número de página y desplazamiento y un ejemplo de un acceso que cruza tres páginas y se parte en tramos. Explicá por qué todas las traducciones se resuelven antes de ejecutar, qué hace el Core ante un page fault y por qué el program counter no avanza. Describí las instrucciones básicas, las de entrenamiento (FORWARD, BACKWARD, UPDATE con sus fórmulas) y las syscalls, separando las que esperan respuesta de las que sueltan el Job. Terminá con cómo se atiende la interrupción por fin de quantum, incluso si llega mientras se espera la respuesta de una syscall.
```

## 5 · Placa: memoria y reemplazo
- **Fuentes:** PLACA, TEORIA, PRESENTACION, ENUNCIADO
- **Formato:** Análisis en profundidad · **Duración:** predeterminada

```
Explicá el módulo Placa del TP y relacionalo con la teoría de memoria virtual. Cubrí la memoria de instrucciones, la memoria de usuario dividida en marcos, la tabla de páginas de cada Job con sus campos (presente, marco, uso, modificada, lockeada, posición en el Offload) y el Offload como área de swap. Explicá ALLOC y FREE, la carga de una página y cuándo se escribe la víctima en el Offload. Explicá LRU y CLOCK-M paso a paso con un ejemplo de marcos con bits de uso y modificado, incluida una página lockeada que se saltea. Explicá por qué existe el lockeo de páginas y qué pasa si no se deslockean. Mencioná la consola con INFO y TLS y los logs obligatorios de la Placa.
```

## 6 · Storage: FAT32_TRAIN y journaling
- **Fuentes:** STORAGE, CHECK4, FINALES, PRESENTACION, ENUNCIADO
- **Formato:** Análisis en profundidad · **Duración:** predeterminada

```
Explicá el módulo Storage del TP. Describí el layout del volumen FAT32_TRAIN (superbloque, tabla FAT, directorio y datos) con un ejemplo de tamaños, los valores especiales de la FAT y cómo se encadena un checkpoint de dos bloques. Explicá guardar, cargar y eliminar checkpoint y sus errores (directorio lleno, falta de espacio, inexistente). Después dedicá la mitad del audio al journaling: qué es un asiento, las marcas STARTED, COMMIT y APPLIED, por qué se usa fsync antes de tocar el volumen, cómo se recupera al arrancar y por qué re-aplicar es idempotente. Usá los dos casos de la prueba final 05: kill -9 antes del commit y entre el commit y el applied, y qué se ve en el log en cada uno.
```

## 7 · Concurrencia y sincronización
- **Fuentes:** CONCURRENCIA, PLANIFICADOR, UTILS, BUGS
- **Formato:** Análisis en profundidad · **Duración:** predeterminada

```
Explicá la concurrencia del TP módulo por módulo: qué hilos hay, qué recursos comparten y con qué mutex o semáforo se protege cada uno. Explicá el patrón productor-consumidor de las colas NEW, READY y de los servicios, y por qué el corto plazo espera a la vez un Job en READY y un Core libre. Contá los problemas de concurrencia reales que aparecieron y cómo se resolvieron: respuestas cruzadas en un socket compartido, la interrupción tardía del quantum, las páginas lockeadas huérfanas y la interrupción que llega durante una syscall. Explicá cómo se evitan deadlock, inanición y espera activa, y cómo funciona el cierre con Ctrl-C con sigwait.
```

## 8 · Teoría que van a preguntar
- **Fuentes:** TEORIA, ENUNCIADO
- **Formato:** Debate · **Duración:** predeterminada

```
Armá un debate entre un docente que toma el coloquio y un estudiante del grupo. El docente pregunta cómo se relaciona cada parte del TP con la teoría de Sistemas Operativos (planificación FIFO, RR y HRRN, inanición, cambio de contexto, paginación bajo demanda, page fault, reemplazo LRU y clock mejorado, fragmentación, swap, bloqueo de páginas, asignación enlazada con FAT, journaling y recuperación, sockets y sincronización). El estudiante responde con precisión usando lo que hace el TP y el docente repregunta cuando la respuesta es vaga o contradice la teoría. Incluí al menos las preguntas probables que aparecen en las fuentes.
```

## 9 · Decisiones de diseño y bugs
- **Fuentes:** DECISIONES, BUGS, MINI
- **Formato:** Crítica · **Duración:** predeterminada

```
Analizá críticamente las decisiones de diseño del TP como lo haría un docente exigente: para cada decisión importante (qué pasa cuando se cae un Core, un solo socket con la Placa, reemplazo global, reserva del Offload en ALLOC, journal con valores finales, un único mutex en el Storage, cierre con Ctrl-C) explicá la alternativa, por qué se eligió esta y qué costo tiene. Después recorré los bugs más importantes que se encontraron, qué problema causaban y cómo se corrigieron. Terminá con los límites conocidos: el livelock con rangos más grandes que la memoria, que se documentó como límite con su justificación teórica, y que el Planificador no se reconecta al Storage. Explicá cómo defenderlos en el coloquio.
```

## 10 · El día de la entrega
- **Fuentes:** DESPLIEGUE, FINALES, PRESENTACION
- **Formato:** Resumen breve · **Duración:** predeterminada

```
Explicá paso a paso cómo desplegar y correr el TP el día de la entrega en el laboratorio, con el objetivo de tenerlo andando en menos de 10 minutos. Cubrí qué hay que instalar en cada máquina, cómo se configura qué módulo corre en cada servidor (catedra.conf y las variables de entorno), cómo se corre cada una de las 6 pruebas finales y qué se verifica en cada una, dónde quedan los logs y qué hacer si se cae una máquina virtual en medio de una prueba. Mencioná los comandos exactos que aparecen en las fuentes y terminá con un checklist corto para repetir antes de empezar.
```

---

## Material agregado para estos audios
Estas notas se escribieron porque la información no estaba en el vault:
- [[Concurrencia y sincronización]]: hilos, mutex y semáforos de cada módulo, y cómo se evitan deadlock, inanición y espera activa
- [[Teoría vs implementación]]: cada concepto de la materia con su lugar en el TP y preguntas probables del coloquio
- [[Decisiones de diseño]]: las decisiones que el enunciado deja al grupo, con su alternativa y justificación
