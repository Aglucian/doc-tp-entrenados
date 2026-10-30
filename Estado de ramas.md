---
tags: [tp-so, entrenados, git]
actualizado: 2026-10-30
---

# Estado de ramas

Volver a [[00 - Inicio]] · Ver [[Plan de acción]]

Las ramas se comparan contra `origin/develop` (`764b9c3`) después de un `git fetch` el **30/10**.

| Rama | Adelante / atrás de `develop` | Contenido | Acción |
| --- | --- | --- | --- |
| `develop` | — | Integración: Check 2 completo + storage (`764b9c3`, filesystem y consola) | base |
| `main` | +1 / 0 | Solo el merge del PR #11 | nada pendiente |
| `origin/core` | +2 / −1 | MMU, accesos entre páginas, page fault, FORWARD/BACKWARD/UPDATE, envío de syscalls (ALLOC/FREE sin conectar) | **PR #12** abierto |
| `origin/placa` | +7 / −1 | `memoria.c` (919 líneas): marcos, tablas de páginas, offload, LRU/CLOCK-M, ALLOC/FREE, R/W, deslockeo | **PR #14** abierto |
| `origin/storage` | igual | Ya está en `develop` | — |
| `planificador` | +4 / 0 | Check 3 del Planificador: page fault, ALLOC/FREE, servicios, deslockeo (`0871672`…`169c8a8`) | traer `develop` después de #12 y #14 → PR |
| `utils` | 0 / −33 | Ya está todo en `develop` | borrar o recrear desde `develop` |

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
3. ~~`storage` → `develop`~~ ✅ hecho (`764b9c3`).
4. Compilar los 5 módulos (`make` en cada uno) y correr la prueba del Check 2 para validar que no hay regresiones.
5. Traer `develop` a `planificador`, correr la *Mini Entrenamiento* con todos los módulos reales y abrir el PR `planificador` → `develop`.
6. Borrar `utils` remota o recrearla desde `develop`.

## Discrepancias detectadas
- En `doc/planificador.md` §5.1 del repo, la tabla dice que `OP_CREAR_JOB` no tiene respuesta y que `OP_DEVOLUCION` es `{motivo, jid, …}`. El código real usa `OP_RSP_CREAR_JOB {ok}` y `{jid, motivo, …}`. Hay que actualizar esa tabla (ver [[Protocolo]]).
- Esa misma sección dice que HRRN "todavía no está implementado", pero ya está (commit `85b58ff`).
