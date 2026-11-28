#!/usr/bin/env python3
"""Compara una corrida de catedra.sh con los resultados esperados de entrenados-pruebas.

Uso: deploy/verificar_catedra.py <carpeta de resultados> <carpeta del checkpoint> <escenario>

Necesita jobs.txt (JID -> script) en la carpeta de resultados, que lo escribe catedra.sh.
Checkpoint 2: por cada Job, una sola finalización por EXIT, registros finales
(log "Contexto final" del Planificador) y secuencia de FETCH concatenada entre Cores.
Checkpoint 3: por cada Job, cómo finaliza y la secuencia de REPORT en reportes.log
(resultados/memoria.md y los README de cada escenario).
"""
import glob
import os
import re
import sys

# resultados/memoria.md
PATRON_A = "3100000001000000640000000000000033000000"
PATRON_B = "6200000001000000C80000000000000066000000"
HOLA = "486F6C61"

# escenario -> script -> (finalización esperada, reportes en orden). "ERROR" = cualquier motivo que no sea EXIT.
ESPERADOS_CP3 = {
    "01_reserva_liberacion": {"reserva_liberacion.asm": ("EXIT", [HOLA])},
    "02_aritmetica": {"aritmetica.asm": ("EXIT", [PATRON_A])},
    "03_cruce_pagina": {"cruce_pagina.asm": ("EXIT", ["06000000"])},
    "04_mini_lru": {"mini_entrenamiento_a.asm": ("EXIT", [PATRON_A] * 8)},
    "05_mini_clock_m": {"mini_entrenamiento_a.asm": ("EXIT", [PATRON_A] * 8)},
    "06_page_locking": {"launcher_lock.asm": ("EXIT", []),
                        "label_lock.asm": ("EXIT", ["41424344"]),
                        "mini_entrenamiento_a.asm": ("EXIT", [PATRON_A] * 8)},
    "07_servicios_fifo": {"launcher_servicios.asm": ("EXIT", []),
                          "servicios_a.asm": ("EXIT", [HOLA, "41424344"]),
                          "servicios_b.asm": ("EXIT", ["54455354", "5758595A"])},
    "08_sin_offload": {"launcher_offload.asm": ("EXIT", []),
                       "sin_offload.asm": ("ERROR", []),
                       "recuperacion_offload.asm": ("EXIT", [HOLA])},
    "09_aislamiento": {"launcher_aislamiento.asm": ("EXIT", []),
                       "mini_entrenamiento_a.asm": ("EXIT", [PATRON_A] * 8),
                       "mini_entrenamiento_b.asm": ("EXIT", [PATRON_B] * 8)},
}

REGISTROS = ["AX", "BX", "CX", "DX", "P0", "P1", "P2", "P3", "P4", "P5", "E1", "E2", "E3"]


def esperados_cp2(path):
    """{script: {"registros": {...}, "fetch": [...]}} desde resultados/individuales.md."""
    esperados, actual, seccion = {}, None, None
    for linea in open(path, encoding="utf-8"):
        linea = linea.rstrip("\n")
        m = re.match(r"^## (\S+\.asm)$", linea)
        if m:
            actual = esperados.setdefault(m.group(1), {"registros": {}, "fetch": None})
            continue
        if actual is None:
            continue
        if linea.startswith("### Registros"):
            seccion = "registros"
        elif linea.startswith("### Secuencia de FETCH"):
            seccion = "fetch"
        elif seccion == "registros":
            m = re.match(r"^\| (\w\w) \| (\d+) \|$", linea)
            if m:
                actual["registros"][m.group(1)] = int(m.group(2))
        elif seccion == "fetch" and linea.startswith("`"):
            actual["fetch"] = [int(x) for x in re.findall(r"\d+", linea)]
            seccion = None
    return esperados


def hora(linea):
    m = re.search(r"\] (\d+):(\d+):(\d+):(\d+) ", linea)
    return tuple(int(x) for x in m.groups()) if m else (0, 0, 0, 0)


def verificar_cp3(resultados, escenario, jobs, plani):
    esperados = ESPERADOS_CP3.get(escenario)
    if esperados is None:
        print(f"  --    {escenario}: sin resultados esperados para comparar automáticamente")
        return 0

    reportes = {}
    path = os.path.join(resultados, "runtime", "reportes.log")
    if os.path.exists(path):
        for linea in open(path, encoding="utf-8", errors="replace"):
            m = re.match(r"## \((\d+)\) - ([0-9A-Fa-f]*)", linea.strip())
            if m:
                reportes.setdefault(int(m.group(1)), []).append(m.group(2).upper())

    fallas = 0
    for jid in sorted(jobs):
        script = jobs[jid]
        if script not in esperados:
            print(f"  --    JID {jid} ({script}): sin resultado esperado")
            continue
        final_esperado, reportes_esperados = esperados[script]
        problemas = []

        finales = re.findall(rf"## \({jid}\) finalizó su ejecución con motivo de (\w+)", plani)
        if len(finales) != 1:
            problemas.append(f"finalizó {len(finales)} veces")
        elif final_esperado == "EXIT" and finales[0] != "EXIT":
            problemas.append(f"motivo {finales[0]} (se esperaba EXIT)")
        elif final_esperado == "ERROR" and finales[0] == "EXIT":
            problemas.append("terminó con EXIT (se esperaba una finalización por error)")

        obtenidos = reportes.get(jid, [])
        if obtenidos != reportes_esperados:
            distintos = sum(1 for o, e in zip(obtenidos, reportes_esperados) if o != e)
            problemas.append(f"{len(obtenidos)} REPORT ({distintos} con otro contenido), "
                             f"se esperaban {len(reportes_esperados)}")

        motivo = finales[0] if finales else "?"
        if problemas:
            fallas += 1
            print(f"  FALLA JID {jid} ({script}): " + "; ".join(problemas))
        else:
            print(f"  OK    JID {jid} ({script}): {motivo}, {len(obtenidos)} REPORT como se esperaba")
    return fallas


def main():
    resultados, checkpoint, escenario = sys.argv[1], sys.argv[2], sys.argv[3]
    jobs = {}
    for linea in open(os.path.join(resultados, "jobs.txt"), encoding="utf-8"):
        jid, script = linea.split()
        jobs[int(jid)] = script

    plani = open(os.path.join(resultados, "planificador", "planificador.log"), encoding="utf-8", errors="replace").read()

    if os.path.basename(os.path.normpath(checkpoint)) == "checkpoint_3":
        sys.exit(1 if verificar_cp3(resultados, escenario, jobs, plani) else 0)

    # FETCH de todos los Cores, ordenados por hora y agrupados por JID.
    fetch = []
    for log in glob.glob(os.path.join(resultados, "core-*", "core_*.log")):
        for linea in open(log, encoding="utf-8", errors="replace"):
            m = re.search(r"## JID: (\d+) - FETCH - Program Counter: (\d+)", linea)
            if m:
                fetch.append((hora(linea), int(m.group(1)), int(m.group(2))))
    fetch.sort()
    por_jid = {}
    for _, jid, pc in fetch:
        por_jid.setdefault(jid, []).append(pc)

    esperados = esperados_cp2(os.path.join(checkpoint, "resultados", "individuales.md"))
    fallas = 0

    for jid in sorted(jobs):
        script = jobs[jid]
        if script not in esperados:
            print(f"  --    JID {jid} ({script}): sin resultado esperado (launcher)")
            continue
        esperado = esperados[script]
        problemas = []

        finales = re.findall(rf"## \({jid}\) finalizó su ejecución con motivo de (\w+)", plani)
        if finales != ["EXIT"]:
            problemas.append(f"finalizaciones {finales} (se esperaba una por EXIT)")

        m = re.search(rf"## \({jid}\) Contexto final: (.*)", plani)
        if m:
            obtenidos = dict((k, int(v)) for k, v in re.findall(r"(\w+)=(\d+)", m.group(1)))
            distintos = [f"{r}={obtenidos.get(r)} (esperado {v})" for r, v in esperado["registros"].items()
                         if obtenidos.get(r) != v]
            if distintos:
                problemas.append("registros " + ", ".join(distintos))
        else:
            problemas.append("no está el log de Contexto final")

        if esperado["fetch"] is not None and por_jid.get(jid, []) != esperado["fetch"]:
            obtenida = por_jid.get(jid, [])
            problemas.append(f"FETCH: {len(obtenida)} PCs, se esperaban {len(esperado['fetch'])}")

        if problemas:
            fallas += 1
            print(f"  FALLA JID {jid} ({script}): " + "; ".join(problemas))
        else:
            secuencia = (f"{len(esperado['fetch'])} FETCH" if esperado["fetch"] is not None
                         else f"{len(por_jid.get(jid, []))} FETCH (sin secuencia esperada para comparar)")
            print(f"  OK    JID {jid} ({script}): EXIT, {len(esperado['registros'])} registros y {secuencia}")

    sys.exit(1 if fallas else 0)


if __name__ == "__main__":
    main()
