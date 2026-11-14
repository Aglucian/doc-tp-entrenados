---
tags: [tp-so, entrenados, git]
actualizado: 2026-11-14
---

# Estado de ramas

Volver a [[00 - Inicio]] · Ver [[Plan de acción]]

Las ramas se comparan contra `origin/develop` (`5922131`) después de un `git fetch` el **14/11**.

| Rama | Adelante / atrás de `develop` | Contenido | Acción |
| --- | --- | --- | --- |
| `develop` | — | Check 3 integrado: #12 core, #14 placa, #15 planificador, #17 fix ALLOC/FREE del core | base |
| `main` | 0 / −2 | Último merge: #16 (develop → main, 31/10). Le falta #17 | mergear `develop` → `main` cuando se cierre el check |
| `origin/core` | 0 / −1 | Ya está en `develop` (#17) | — |
| `origin/placa` | 0 / −9 | Ya está en `develop` (#14) | — |
| `origin/planificador` | 0 / −17 | Ya está en `develop` (#15) | traer `develop` antes de seguir con el Check 4 |
| `origin/storage` | 0 / −21 | Ya está en `develop` | traer `develop` antes del Check 4 |
| `utils` | 0 / −54 | Vieja | borrar o recrear desde `develop` |

No hay PRs abiertos.

> [!info] `planificador` tiene `18d367d` (despliegue distribuido, `deploy/`), todavía sin pushear ni en `develop`. Ver [[Despliegue distribuido]].

> [!info] Ramas locales
> El 14/11 todas se actualizaron a su remota con un fast-forward. La `planificador` local está en `5922131` (igual que `develop`), 17 commits adelante de `origin/planificador` (solo merges) y sin pushear.

## Conflicto de `protocolo_entrenados.h` ✅ resuelto
`core` y `placa` agregaban los mismos opcodes (`OP_TAM_PAGINA`, `OP_DESLOCKEAR_PAGINAS`, `OP_RSP_DESLOCKEAR_PAGINAS`). En `develop` aparecen una sola vez (`0x68`–`0x6A`).

## Integración del Check 3 ✅
1. ~~`core` → `develop`~~ (#12, 26/10)
2. ~~`placa` → `develop`~~ (#14, 29/10)
3. ~~`planificador` → `develop`~~ (#15, 30/10)
4. ~~`develop` → `main`~~ (#16, 31/10)
5. ~~fix ALLOC/FREE del Core~~ (#17, 12/11)
6. ~~Mini Entrenamiento con los módulos reales~~ ✅ ([[Mini Entrenamiento 2026-11-14]])

## Discrepancias detectadas
- En `doc/planificador.md` §5.1 del repo, la tabla dice que `OP_CREAR_JOB` no tiene respuesta y que `OP_DEVOLUCION` es `{motivo, jid, …}`. El código real usa `OP_RSP_CREAR_JOB {ok}` y `{jid, motivo, …}`. Hay que actualizar esa tabla (ver [[Protocolo]]).
- Esa misma sección dice que HRRN "todavía no está implementado", pero ya está (commit `85b58ff`).
