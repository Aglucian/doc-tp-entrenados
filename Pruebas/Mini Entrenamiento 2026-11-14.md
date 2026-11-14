---
tags: [tp-so, entrenados, pruebas, check-3]
fecha: 2026-11-14
rama: develop (5922131)
resultado: ok
---

# Mini Entrenamiento: 14/11/2026

Volver a [[00 - Inicio]] · Ver [[Plan de acción]] · Módulos: [[Planificador]], [[Core]], [[Placa]], [[Storage]]

Es la primera corrida de punta a punta con **los 4 módulos reales** de `develop` (`5922131`, después de los merges #12, #14, #15 y #17). Valida lo que pide el Check 3: ALLOC, LOAD_BATCH, instrucciones de entrenamiento, page faults, reemplazo con Offload y Jobs pasando por BLOCKED.

> [!success] Resultado
> El Job terminó con `EXIT`. Hubo **9 page faults**, **5 reemplazos con bajada al Offload**, **11 pasos por BLOCKED** y el reporte en hexadecimal salió correcto. Ningún módulo registró errores.

## Configuración
Para forzar page faults y reemplazos, la memoria es chica a propósito.

| Módulo | Parámetros |
| --- | --- |
| Placa | `TAM_MEMORIA=256`, `TAM_PAGINA=64` (**4 marcos**), `ALGORITMO_REEMPLAZO=CLOCK-M`, `RETARDO_MEMORIA=5`, `RETARDO_OFFLOAD=20` |
| Planificador | `ALGORITMO_PLANIFICACION=RR`, `RR_QUANTUM=200`, `GRADO_MULTIPROGRAMACION=4` |
| Storage | `RETARDO_ACCESO_BLOQUE=5`, `RETARDO_COMMIT=5` |
| Core | 1 instancia (`id 1`) |

Los puertos fueron 28080–28082 para no chocar con otras corridas. El archivo `lote1` contiene 128 enteros `uint32`, del 0 al 127, en little-endian.

## Script (`mini`)
```
0  SET CX 512
1  ALLOC P3 CX              ; 8 páginas, solo en el Offload
2  SET DX 128
3  LOAD_BATCH lote1 P3 DX   ; 2 páginas
4  SET P0 P3
5  SET P1 P3
6  SUM P1 256
7  SET P2 P3
8  SUM P2 480
9  SET AX 4
10 FORWARD P0 P1 P2 BX
11 BACKWARD P0 P1 P2 BX
12 UPDATE P2 P1 P0
13 SUM P0 64                ; avanza una página por vuelta
14 SUM P1 64
15 SUB AX 1
16 JNZ AX 10
17 SET DX 32
18 REPORT P3 DX
19 FREE P3
20 EXIT
```

`P0` recorre las páginas 0 a 3, `P1` las páginas 4 a 7 y `P2` siempre la 7. En total el recorrido usa 8 páginas con solo 4 marcos, lo que obliga a reemplazar.

## Resultados
| Qué se validó | Resultado |
| --- | --- |
| `ALLOC` / `FREE` | ✅ Memoria dinámica máxima: **512 bytes** |
| Page faults | ✅ **9**, en el Core y en el Planificador |
| Jobs que pasan por BLOCKED | ✅ **11** (9 page faults + Loader + Logger) |
| Reemplazo + Offload | ✅ **5** `Reemplazo` + **5** `Bajada al Offload` con CLOCK-M |
| Loader | ✅ 128 bytes en 2 tramos (`dir 0` y `dir 64`) + deslockeo |
| Logger | ✅ Ver el reporte abajo |
| Errores en los logs | ✅ 0 en los 4 módulos |

**Reporte** (`PATH_REPORTES`):
```
## (0) - 0000000001000000020000000300000004000000050000000600000007000000
```
Son los enteros 0 a 7 de `lote1` en little-endian, es decir, los primeros 32 bytes del rango.

**Estadísticas del Job:**
```
## (0) finalizó su ejecución con motivo de EXIT. Estadísticas:
Tiempo total de ejecución: 2780 ms - Tiempo para ingresar (NEW): 6 ms -
Espera en READY: 1002 ms - Memoria dinámica máxima: 512 bytes -
Syscalls: 4 - Page faults: 9 - Transiciones READY=>EXEC: 12
```

**Extracto del log del Planificador:**
```
## (0) - Solicitó syscall: LOAD_BATCH
## (0) inicia Loader
## (0) - Escritura - Dirección Física: 0 - Tamaño: 64
## (0) - Escritura - Dirección Física: 64 - Tamaño: 64
## (0) - Deslockeo de páginas
## (0) finalizó Loader y pasa a READY
...
## (0) inicia Logger
## (0) - Lectura - Dirección Física: 128 - Tamaño: 32
## (0) - Deslockeo de páginas
## (0) finalizó Logger y pasa a READY
```

**Extracto del log de la Placa:**
```
## JID: 0 - Bajada al Offload - Página: 0
## Reemplazo - Marco: 0 - JID Víctima: 0 - Página Víctima: 0
## JID: 0 - Bajada al Offload - Página: 4
## Reemplazo - Marco: 2 - JID Víctima: 0 - Página Víctima: 4
```

El único warning fue `El path del Job inicial no es legible desde el Planificador: mini`. Es lo esperable: el script lo lee la Placa, no el Planificador.

## Hallazgos

> [!bug] Livelock si el rango de una syscall es más grande que la memoria
> El primer intento usó `LOAD_BATCH` sobre 512 bytes (8 páginas) con 4 marcos, y el Job quedó en un ciclo infinito: PF → carga → PF → …
> - Para mandar la syscall, el Core necesita **todas** las páginas del rango residentes al mismo tiempo.
> - Ante cada PF, deslockea las páginas que ya tenía y devuelve el Job.
> - La carga siguiente desaloja justamente una de esas páginas.
>
> Con la config del enunciado (`TAM_MEMORIA=4096`) no debería pasar. Igual conviene decidirlo en grupo: o se detecta y se finaliza el Job con error, o se documenta como límite.

> [!warning] Restricción de configuración
> La Placa exige que `TAM_MEMORIA` y `TAM_PAGINA` sean potencias de 2 (con 384 no arranca).

> [!bug] Pendiente en el Core: `FREE` con `ok=false`
> En esta prueba no apareció porque todos los `FREE` fueron válidos. En el código, el Core hace `goto error` → `EJEC_ERROR` y **se desconecta** del Planificador. Ver [[Core]].

## Qué falta probar
- [ ] La misma prueba con `ALGORITMO_REEMPLAZO=LRU`
- [ ] Con FIFO y con HRRN en el Planificador
- [ ] Varios Jobs y varios Cores a la vez, compitiendo por los marcos
- [ ] `LABEL` con entrada por teclado
- [ ] Con valgrind en la Placa y en el Planificador
- [ ] Con la config del enunciado (`TAM_MEMORIA=4096`)
