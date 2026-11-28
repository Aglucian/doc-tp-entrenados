---
tags: [tp-so, entrenados, moc]
aliases: [Inicio, Índice TP EntrenadOS]
actualizado: 2026-11-24
---

# TP EntrenadOS 2C2026: Inicio

Esta es la documentación de trabajo del TP **EntrenadOS** (grupo *RequiemSO*). Está fuera del repositorio `tp-2026-2c-requiemso`, para que sirva de planificación y consulta sin ensuciar el código.

> [!info] Fuente
> La documentación se armó a partir de la rama `develop` y de las ramas remotas sin mergear al **29/10/2026**. Se actualizó el **30/10** con el trabajo del Check 3 en la rama `planificador`, y el **14/11** con el Check 3 y el Check 4 integrados en `develop` (`03d9deb`) y la suite de la cátedra corrida completa. Cada función indica si está en `develop` o solo en su rama.

## Planificación
- [[Plan de acción]]: qué falta, en qué orden y para qué checkpoint
- [[Estado de ramas]]: qué tiene cada rama y cómo integrarlas
- [[Bugs encontrados]]: los bugs de cada rama, qué problema causaban y cuándo se corrigieron
- [[Despliegue distribuido]]: servidores de prueba y `deploy/desplegar.sh` (cómo correr pruebas en varias máquinas)
- [[Laboratorio manual 2026-11-27]]: práctica de la entrega en modo manual (cada módulo en su VM con `preparar.sh`): 01 FIFO en 4 máquinas ✅
- [[Pruebas finales 2026-11-24]]: las 6 pruebas oficiales de las entregas finales en los 5 servidores ✅
- [[Check 4 2026-11-14]]: checkpoints y journaling, con `kill -9` al Storage en los 5 servidores ✅
- [[Suite cátedra 2026-11-14]]: los escenarios oficiales de CP2 y CP3 (`entrenados-pruebas`) en los 5 servidores ✅
- [[Mini Entrenamiento 2026-11-14]]: primera prueba de punta a punta con los módulos reales (Check 3)
- [[Presentación - Funcionamiento del TP]]: diapositivas que explican el TP de punta a punta (abrir con *Slides: Start presentation*). En PDF, con los diagramas dibujados: `TP EntrenadOS - Presentación.pdf` (se genera con `herramientas/presentacion_pdf.py`)

## Módulos
| Módulo | Nota | Rol |
| --- | --- | --- |
| Planificador | [[Planificador]] · [[Planificador - Resumen\|Defensa]] | Colas de Jobs, corto/largo plazo, syscalls, servicios |
| Core | [[Core]] | Ciclo de instrucción, MMU, pedido de syscalls |
| Placa | [[Placa]] | Instrucciones, memoria paginada, offload, reemplazo |
| Storage | [[Storage]] | FS `FAT32_TRAIN`, checkpoints, consola |
| Utils | [[Utils]] | Sockets, serialización, config/logger compartidos |

- [[Protocolo]]: opcodes, payloads y enums compartidos (`protocolo_entrenados.h`)

## Coloquio
- [[Planificador - Resumen]]: defensa del Planificador para el coloquio (guion, teoría, trampas y preguntas probables)
- [[Teoría vs implementación]]: cada concepto de la materia con su lugar en el TP y preguntas probables
- [[Decisiones de diseño]]: lo que el enunciado deja al grupo, con su alternativa y justificación
- [[Concurrencia y sincronización]]: hilos, mutex y semáforos de cada módulo
- [[Prompts de audio]]: 10 audios de NotebookLM para estudiar el TP, con las fuentes de cada uno

## Arquitectura

```mermaid
flowchart LR
    C1[Core 1..N] -- syscalls / devoluciones --> P[Planificador]
    P -- EJECUTAR_JOB / INTERRUPCION --> C1
    C1 -- fetch / marco / R-W memoria --> PL[Placa]
    P -- crear/finalizar Job, ALLOC/FREE,<br/>carga de página, R-W, deslockeo --> PL
    P -- guardar/cargar/eliminar checkpoint --> S[Storage]
```

**Orden de arranque:** Placa y Storage → Planificador (se conecta a ambos y recién después abre su servidor) → Cores.

## Calendario
| Hito | Fecha | Contenido |
| --- | --- | --- |
| Check 1 | 12/09 | Conexiones y serialización ✅ |
| Check 2 | 10/10 | Planificación básica FIFO/RR ✅ (+ HRRN) |
| Check 3 | 31/10 | Memoria, paginación, syscalls, servicios, BLOCKED ✅ (integrado y probado el 14/11) |
| Check 4 | 14/11 | Storage y persistencia (checkpoints) ✅ (#21 y #22; [[Check 4 2026-11-14\|prueba con `kill -9`]] en 5 servidores; suite oficial sin publicar) |
| Entregas | 28/11 · 12/12 · 19/12 | Pruebas finales de la cátedra: [[Pruebas finales 2026-11-24\|las 6 pasan]] ✅ · coloquio |
