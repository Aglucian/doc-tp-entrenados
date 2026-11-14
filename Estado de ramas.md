---
tags: [tp-so, entrenados, git]
actualizado: 2026-11-14
---

# Estado de ramas

Volver a [[00 - Inicio]] · Ver [[Plan de acción]]

Las ramas se comparan contra `origin/develop` (`3a0e4c3`) después de un `git fetch` el **14/11**.

| Rama | Adelante / atrás de `develop` | Contenido | Acción |
| --- | --- | --- | --- |
| `develop` | — | Checks 2, 3 y 4 completos: #12 core, #14 placa, #15 planificador, #17/#19 ALLOC/FREE del core, #20 despliegue, #21/#22 checkpoints y journaling. Commits directos: `2a9b3b3` señales del Storage, `5282eb3` prueba de checkpoints, `896a387` Placa con rutas absolutas y log de contexto, `03d9deb` runner de la cátedra, `3a0e4c3` repartos | base |
| `main` | 0 / −15 | Último merge: #16 (develop → main, 31/10). **Le falta todo el Check 4** | **mergear `develop` → `main` antes de la entrega** |
| `origin/core` | 0 / −12 | Ya está en `develop` (#19) | — |
| `origin/placa` | 0 / −22 | Ya está en `develop` (#14) | — |
| `origin/planificador` | 0 / −7 | Ya está en `develop` (#21) | — |
| `origin/storage` | 0 / −7 | Ya está en `develop` (#22) | — |
| `utils` | 0 / −67 | Vieja | borrar o recrear desde `develop` |

No hay PRs abiertos. Ninguna rama tiene commits que no estén en `develop`.

> [!info] El despliegue distribuido (`deploy/`) está en `develop` desde el PR #20. Ver [[Despliegue distribuido]].

> [!info] Ramas locales
> En esta máquina se trabaja sobre `develop` (`3a0e4c3`, igual al remoto). Las ramas de cada módulo quedaron como estaban después de sus PRs.

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
