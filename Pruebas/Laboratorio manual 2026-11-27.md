---
tags: [tp-so, entrenados, pruebas, deploy]
fecha: 2026-11-27
rama: deploy
resultado: 01 FIFO OK en 4 máquinas
---

# Práctica del laboratorio: modo manual (27/11)

Volver a [[00 - Inicio]] · Ver también [[Despliegue distribuido]], [[Planificador - Resumen]]

Práctica de la entrega con el modo elegido: **cada módulo se levanta a mano en su VM**, sin SSH entre máquinas, con `./preparar.sh` de la rama `deploy`.

## Reparto
| Máquina | Módulo |
| --- | --- |
| 192.168.1.31 | Planificador |
| 192.168.1.18 | Placa |
| 192.168.1.26 | Storage |
| 192.168.1.25 | Core 1 |

## Resultado: prueba 01, variante FIFO ✅
- El Planificador se conectó a la Placa (.18) y al Storage (.26), y el Core 1 se conectó desde la .25.
- El Job 0 hizo 3 `INIT_JOB`. Los Jobs 1, 2 y 3 pasaron por:
  - `ALLOC`;
  - un page fault de la página 0 cada uno;
  - `LOAD_BATCH` (Loader);
  - dos `REPORT` (Logger);
  - `FREE`.
- **Los 4 Jobs terminaron en `EXIT`**, con sus estadísticas y su contexto final. Con FIFO no hubo desalojos.

## Lo que falló y cómo se resolvió
| Problema | Causa | Solución |
| --- | --- | --- |
| "El Job 0 no se pudo crear" / la Placa no arrancaba (intentos anteriores) | El README hace `mkdir -p ./runtime/<prueba>` una sola vez, pero la carpeta se usa en **tres máquinas**: Offload en la Placa, volumen en el Storage y reportes en el Planificador | Crear `./runtime/<prueba>/` en **cada** máquina antes de lanzar su módulo |
| `No se pudo abrir el archivo de configuración` en el Planificador | Se lanzó desde `~/tp-2026-2c-requiemso` o `~/entrenados-pruebas`, y `$PWD/escenarios/...` no existe ahí | Lanzar **todo** desde `~/entrenados-pruebas/entregas_finales` |
| `git checkout deploy` → `'deploy' could be both a local file and a tracking branch` | En el repo hay una **carpeta** `deploy/` y la rama no existía localmente | Usar `git switch deploy` |
| `git pull` → `There is no tracking information` | La rama local `deploy` no sigue a `origin/deploy` | `git branch --set-upstream-to=origin/deploy deploy` |
| Git pide usuario y token en cada `pull` (clon por HTTPS) | El token no queda guardado | `git config --global credential.helper 'cache --timeout=36000'`: lo recuerda 10 horas, sin escribirlo en disco |
| Warning `El path del Job inicial no es legible desde el Planificador` | El Planificador chequeaba un archivo que en realidad lee la Placa | Se sacó el warning (cambio en `deploy`) |
| En el Planificador, `EXEC → BLOCKED` sin decir por qué | No había log del page fault en el Planificador | Se agregó `## (N) - Page Fault - Página: P` (no es obligatorio) |

## Secuencia que funcionó
En cada VM (una sola vez):
```bash
cd ~/tp-2026-2c-requiemso && git switch deploy && git pull && ./preparar.sh
```
`MÓDULOS :` el de esa VM, y las tres IPs: `192.168.1.31`, `192.168.1.18` y `192.168.1.26`.

Configs de la cátedra, a mano: en el Planificador `IP_PLACA` e `IP_STORAGE`; en el Core `IP_PLANIFICADOR` e `IP_PLACA`.

Lanzar en orden, desde `~/entrenados-pruebas/entregas_finales`:
1. **Storage (.26):** `rm -rf ./runtime/01_planificacion_fifo && mkdir -p ./runtime/01_planificacion_fifo/storage`, y después `~/tp-2026-2c-requiemso/bin/storage "$PWD/escenarios/01_planificacion/configs/FIFO/storage.config"`
2. **Placa (.18):** `mkdir -p ./runtime/01_planificacion_fifo`, y después `~/tp-2026-2c-requiemso/bin/placa "$PWD/escenarios/01_planificacion/configs/FIFO/placa.config"`
3. **Planificador (.31):** `mkdir -p ./runtime/01_planificacion_fifo`, y después `~/tp-2026-2c-requiemso/bin/planificador "$PWD/escenarios/01_planificacion/configs/FIFO/planificador.config" PLANIFICACION.asm`
4. **Core (.25):** `~/tp-2026-2c-requiemso/bin/core "$PWD/escenarios/01_planificacion/configs/core-1.config" 1`

## Pendiente
- [ ] 01 RR y HRRN, 02 a 06 en este modo
- [ ] 06 Estabilidad: agregar y cortar Cores a mano durante la corrida
