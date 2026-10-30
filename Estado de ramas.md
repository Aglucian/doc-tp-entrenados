---
tags: [tp-so, entrenados, git]
actualizado: 2026-10-29
---

# Estado de ramas

Volver a [[00 - Inicio]] · Ver [[Plan de acción]]

Las ramas se comparan contra `develop` (`6f198c6`) después de un `git fetch`.

| Rama | Adelante / atrás de `develop` | Contenido | Acción |
| --- | --- | --- | --- |
| `develop` | — | Integración. Planificador con FIFO/RR/HRRN, Core/Placa/Storage del Check 2 | base |
| `main` | +1 / 0 | Solo el merge del PR #11 | nada pendiente |
| `origin/core` | +2 / 0 | MMU, accesos entre páginas, page fault, FORWARD/BACKWARD/UPDATE, syscalls ALLOC/FREE/INIT_JOB | **mergear** |
| `origin/placa` | +7 / 0 | `memoria.c` (919 líneas): marcos, tablas de páginas, offload, LRU/CLOCK-M, ALLOC/FREE, R/W, deslockeo | **mergear** |
| `origin/storage` | +1 / 0 | `filesystem.c` (superbloque/directorio) y `consola.c` (INFO/LS/CAT/WRITE/RM) | **mergear** |
| `planificador` | 0 / −21 | Ya está todo en `develop` | borrar o recrear desde `develop` |
| `utils` | 0 / −32 | Ya está todo en `develop` | borrar o recrear desde `develop` |

> [!warning] Ramas locales atrasadas
> Las copias locales de `core`, `main`, `placa` y `storage` están detrás de `origin`. Antes de trabajar en cualquiera: `git checkout <rama> && git pull`.

## Conflicto previsto: `protocolo_entrenados.h`

`core` y `placa` agregan **los mismos tres opcodes**, con formato distinto:

```c
OP_TAM_PAGINA             = 0x68,
OP_DESLOCKEAR_PAGINAS     = 0x69,  // {jid}
OP_RSP_DESLOCKEAR_PAGINAS = 0x6A,  // {ok}
```

El segundo PR que entre a `develop` va a tener un conflicto de texto. Se resuelve quedándose con una sola copia (los valores coinciden). Además, `core` corrige el comentario de `OP_DEVOLUCION` a `{jid, motivo, contexto[, nro_pagina]}`, que es el orden que ya usa el [[Planificador]].

## Orden de integración sugerido
1. `placa` → `develop` (no toca código de otros módulos, salvo el header).
2. `core` → `develop`, resolviendo el conflicto del header.
3. `storage` → `develop` (no hay conflicto).
4. Compilar los 5 módulos (`make` en cada uno) y correr la prueba del Check 2 para validar que no hay regresiones.
5. Borrar `planificador` y `utils` remotas, o recrearlas desde `develop`.

## Discrepancias detectadas
- En `doc/planificador.md` §5.1 del repo, la tabla dice que `OP_CREAR_JOB` no tiene respuesta y que `OP_DEVOLUCION` es `{motivo, jid, …}`. El código real usa `OP_RSP_CREAR_JOB {ok}` y `{jid, motivo, …}`. Hay que actualizar esa tabla (ver [[Protocolo]]).
- Esa misma sección dice que HRRN "todavía no está implementado", pero ya está (commit `85b58ff`).
