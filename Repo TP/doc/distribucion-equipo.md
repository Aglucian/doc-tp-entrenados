# Distribución del equipo — TP EntrenadOS (SO 2C2026)

> Basado en el enunciado v1.0 (25/08/2026) archivado en la bóveda (`MiSegundoCerebro`).
> Grupo: 5 integrantes. Fecha de cierre de inscripciones: 05/09.

## Criterio

La carga del enunciado se reparte aproximadamente así: Planificador ~30%
del trabajo, Placa ~25%, Storage ~20%, Core ~10%, infraestructura y
testing ~15%. El Planificador concentra planificación, 10 syscalls,
3 servicios, estadísticas, 14 logs obligatorios y 14 parámetros de
configuración: por eso lleva dos personas.

## Propiedad por módulo

| Integrante | Responsable de | Carga |
|---|---|---|
| D1 | Planificador — planificación: colas, modelo de 5 estados, FIFO/RR/HRRN, contexto de ejecución, estadísticas | ~15% |
| D2 | Planificador — syscalls y servicios: atención de las 10 syscalls, Loader/Labeler/Logger, page faults, deslockeo de páginas | ~15% |
| D3 | Placa completa: tablas de páginas, paginación bajo demanda, offload, reemplazo LRU/CLOCK-M, ALLOC/FREE, INFO/TLS | ~25% |
| D4 | Storage completo: FAT32_TRAIN (superbloque/FAT/directorio), journaling y recuperación, comandos INFO/LS/CAT/WRITE/RM | ~20% |
| D5 | Core + MMU + transversales: ciclo de instrucción (Fetch/Decode/Execute/Check Interrupt), protocolo y serialización, deployment, scripts de test | ~25% |

D5 compensa el Core (el módulo más chico) con la infraestructura que
sostiene todos los checks: protocolo de mensajes, wrapper de logs,
scripts de despliegue automatizado.

## Picos por etapa

| Etapa (fecha) | Pico de carga | Los demás |
|---|---|---|
| Check 1 (12/09) | Todos: conectividad de su módulo; D5 lidera protocolo y handshakes | D4 adelanta el volumen FAT32_TRAIN |
| Check 2 (10/10) | D1, D2 y D5 (planificación + Core) | D3 hace memoria de instrucciones; D4 testa y adelanta superbloque/FAT/directorio |
| Check 3 (31/10) | D3 (paginación/offload/reemplazo) y D5 (MMU) | D1/D2 servicios; D4 cierra formateo + INFO/LS |
| Check 4 (14/11) | D4 (journaling y recuperación) | D1/D2 syscalls de checkpoint; D3 y D5 integración |
| Entregas (28/11, 12/12, 19/12) | Todos: pruebas distribuidas y auditoría de logs | — |

## Reglas para el coloquio

El enunciado es explícito: el trabajo equitativo no garantiza aprobar.
El coloquio es individual y no recuperable, y una implementación que
contradiga la teoría o el enunciado es motivo de desaprobación.

1. Cada integrante es dueño de los logs mínimos obligatorios y del
   archivo de configuración de su módulo: debe conocerlos al detalle.
2. Code review cruzada obligatoria: nada se integra sin que el dueño de
   otro módulo lo lea. Así todos ven todo el sistema.
3. Rotación en los ensayos de cada check: en cada simulacro, un
   integrante distinto maneja el deployment y explica los logs de un
   módulo ajeno.

## Referencias

- Enunciado: capturado en la bóveda (`.raw/captured/d8952c1f…`), página
  canónica `wiki/sources/tp-so-2c2026-entrenados.md`.
- Tablero Trello con 67 tarjetas por etapa: `EntrenadOS - Tablero Trello.json`
  (este mismo directorio).
- Normas del TP: https://docs.utnso.com.ar/primeros-pasos/normas-tp
- Consultas: foro https://github.com/sisoputnfrba/foro · inscripciones@utnso.com.ar
