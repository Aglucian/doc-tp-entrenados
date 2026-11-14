---
tags: [tp-so, entrenados, git]
actualizado: 2026-11-14
---

# Estado de ramas

Volver a [[00 - Inicio]] · Ver [[Plan de acción]]

Las ramas se comparan contra `origin/develop` (`713da07`, después del PR #19) después de un `git fetch` el **14/11**.

| Rama | Adelante / atrás de `develop` | Contenido | Acción |
| --- | --- | --- | --- |
| `develop` | — | Check 3 integrado: #12 core, #14 placa, #15 planificador, #17 y #19 (ALLOC/FREE del core) | base |
| `main` | 0 / −4 | Último merge: #16 (develop → main, 31/10). Le faltan #17 y #19 | mergear `develop` → `main` cuando se cierre el check |
| `origin/core` | 0 / −1 | Ya está en `develop` (#19) | — |
| `origin/placa` | 0 / −9 | Ya está en `develop` (#14) | — |
| `origin/planificador` | +1 / −2 | `18d367d` (despliegue, `deploy/`) todavía **no está en `develop`** | traer `develop` y abrir el PR del despliegue |
| `origin/storage` | 0 / −21 | Ya está en `develop` | traer `develop` antes del Check 4 |
| `utils` | 0 / −54 | Vieja | borrar o recrear desde `develop` |

No hay PRs abiertos.

> [!info] `planificador` tiene `18d367d` (despliegue distribuido, `deploy/`): pusheado, pero todavía no está en `develop`. Ver [[Despliegue distribuido]].

> [!info] Ramas locales
> El 14/11, después del #19, `develop` y `core` locales se actualizaron con un fast-forward a `713da07`. `planificador` necesita un merge de `develop`: no se puede hacer fast-forward porque tiene `18d367d`.

## Conflicto de `protocolo_entrenados.h` ✅ resuelto
`core` y `placa` agregaban los mismos opcodes (`OP_TAM_PAGINA`, `OP_DESLOCKEAR_PAGINAS`, `OP_RSP_DESLOCKEAR_PAGINAS`). En `develop` aparecen una sola vez (`0x68`–`0x6A`).

## Integración del Check 3 ✅
1. ~~`core` → `develop`~~ (#12, 26/10)
2. ~~`placa` → `develop`~~ (#14, 29/10)
3. ~~`planificador` → `develop`~~ (#15, 30/10)
4. ~~`develop` → `main`~~ (#16, 31/10)
5. ~~fix ALLOC/FREE del Core~~ (#17, 12/11 y #19, 14/11)
6. ~~Mini Entrenamiento con los módulos reales~~ ✅ ([[Mini Entrenamiento 2026-11-14]])

## Discrepancias detectadas
- En `doc/planificador.md` §5.1 del repo, la tabla dice que `OP_CREAR_JOB` no tiene respuesta y que `OP_DEVOLUCION` es `{motivo, jid, …}`. El código real usa `OP_RSP_CREAR_JOB {ok}` y `{jid, motivo, …}`. Hay que actualizar esa tabla (ver [[Protocolo]]).
- Esa misma sección dice que HRRN "todavía no está implementado", pero ya está (commit `85b58ff`).
