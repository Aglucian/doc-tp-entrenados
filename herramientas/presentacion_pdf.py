"""Genera el PDF de la presentación (una diapositiva 16:9 por página) desde la nota de Obsidian.

Uso, desde la raíz de la bóveda:
    python3 herramientas/presentacion_pdf.py . "TP EntrenadOS - Presentación.pdf"

Reutiliza el renderer de Markdown de exportar_pdf.py. Cada diapositiva va separada por una
línea con ---. Una línea `<!-- dibujo: nombre -->` (invisible en Obsidian) se reemplaza por el
dibujo vectorial de DIBUJOS[nombre]; si la sigue un bloque de código (mermaid o texto), ese
bloque se omite porque el dibujo lo reemplaza.
"""
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import exportar_pdf as ep  # noqa: E402

from reportlab.graphics.shapes import Circle, Drawing, Line, Polygon, Rect, String  # noqa: E402
from reportlab.lib import colors  # noqa: E402
from reportlab.lib.enums import TA_CENTER  # noqa: E402
from reportlab.lib.styles import ParagraphStyle  # noqa: E402
from reportlab.lib.units import cm  # noqa: E402
from reportlab.pdfbase.pdfmetrics import stringWidth  # noqa: E402
from reportlab.platypus import (BaseDocTemplate, Frame, KeepInFrame, PageBreak, PageTemplate,  # noqa: E402
                                Paragraph, Spacer, Table, TableStyle)

ANCHO_PAG, ALTO_PAG = 33.867 * cm, 19.05 * cm  # 16:9
MARGEN = 1.3 * cm
ALTO_BANDA = 1.9 * cm
ANCHO = ANCHO_PAG - 2 * MARGEN
ALTO_CONTENIDO = ALTO_PAG - 2 * MARGEN - ALTO_BANDA - 0.9 * cm

AZUL = "#2F5D8A"
GRIS = "#666666"
COLOR = {  # fondo, borde de cada módulo
    "planificador": ("#E3F2FD", "#1565C0"),
    "core": ("#E8F5E9", "#2E7D32"),
    "placa": ("#FFF3E0", "#E65100"),
    "storage": ("#F3E5F5", "#6A1B9A"),
    "neutro": ("#F5F7F9", "#607D8B"),
    "alerta": ("#FFEBEE", "#C62828"),
    "ok": ("#E8F5E9", "#2E7D32"),
}

# --- estilos más grandes para diapositivas ---
ep.E["p"] = ParagraphStyle("p", fontName="Sans", fontSize=14.5, leading=20, spaceAfter=5)
ep.E["celda"] = ParagraphStyle("celda", fontName="Sans", fontSize=12.5, leading=16)
ep.E["celda_h"] = ParagraphStyle("celda_h", fontName="Sans-B", fontSize=12.5, leading=16, textColor=colors.white)
ep.E["codigo"] = ParagraphStyle("codigo", fontName="Mono", fontSize=12, leading=15.5)
ep.E["h3"] = ParagraphStyle("h3", fontName="Sans-B", fontSize=16, leading=21, spaceBefore=4, spaceAfter=3)
_inline = ep.inline
ep.inline = lambda t: _inline(t).replace('face="Mono" size="8"', 'face="Mono" size="12.5"')

FORMULA = ParagraphStyle("formula", fontName="Sans", fontSize=21, leading=29, alignment=TA_CENTER, spaceBefore=2, spaceAfter=2)


# --- primitivas de dibujo ---

def hx(c):
    return colors.HexColor(c)


def texto(d, x, y, s, tam=8.5, fuente="Sans", ancla="start", color="#1A1A1A"):
    d.add(String(x, y, s, fontName=fuente, fontSize=tam, textAnchor=ancla, fillColor=hx(color)))


def caja(d, x, y, w, h, lineas, modulo="neutro", tam=10, r=6, fondo=None, borde=None, mono=False):
    f, b = COLOR[modulo]
    d.add(Rect(x, y, w, h, rx=r, ry=r, fillColor=hx(fondo or f), strokeColor=hx(borde or b), strokeWidth=1.2))
    tams = [tam] + [tam - 1.8] * (len(lineas) - 1)
    alto = sum(t * 1.28 for t in tams)
    cy = y + h / 2 + alto / 2
    for i, (linea, t) in enumerate(zip(lineas, tams)):
        cy -= t * 1.28
        fuente = "Sans-B" if i == 0 else ("Mono" if mono else "Sans")
        texto(d, x + w / 2, cy + t * 0.3, linea, t, fuente, "middle", "#1A1A1A" if i == 0 else "#333333")


def flecha(d, x1, y1, x2, y2, color=AZUL, ancho=1.3, punta=7, discontinua=False, etiqueta=None, tam=9.5,
           dx=0, dy=5, en=0.5, doble=False):
    linea = Line(x1, y1, x2, y2, strokeColor=hx(color), strokeWidth=ancho)
    if discontinua:
        linea.strokeDashArray = [4, 3]
    d.add(linea)
    puntas = [(x2, y2, x1, y1)] + ([(x1, y1, x2, y2)] if doble else [])
    for px, py, ox, oy in puntas:
        ang = math.atan2(py - oy, px - ox)
        p1 = (px - punta * math.cos(ang - 0.4), py - punta * math.sin(ang - 0.4))
        p2 = (px - punta * math.cos(ang + 0.4), py - punta * math.sin(ang + 0.4))
        d.add(Polygon([px, py, p1[0], p1[1], p2[0], p2[1]], fillColor=hx(color), strokeColor=hx(color), strokeWidth=0.5))
    if etiqueta:
        mx, my = x1 + (x2 - x1) * en + dx, y1 + (y2 - y1) * en + dy
        w = stringWidth(etiqueta, "Sans", tam)
        d.add(Rect(mx - w / 2 - 2, my - 2.5, w + 4, tam + 3, fillColor=colors.white, strokeColor=None))
        texto(d, mx, my, etiqueta, tam, "Sans", "middle", "#333333")


def ajustar(d, ancho_max=ANCHO, alto_max=7.5 * cm):
    f = min(ancho_max / d.width, alto_max / d.height, 2.0)
    d.scale(f, f)
    d.width, d.height = d.width * f, d.height * f
    return d


# --- dibujos ---

def d_arquitectura():
    d = Drawing(820, 215)
    for i in (2, 1):
        d.add(Rect(20 + i * 5, 70 - i * 5, 160, 75, rx=6, ry=6, fillColor=hx(COLOR["core"][0]), strokeColor=hx(COLOR["core"][1]), strokeWidth=1))
    caja(d, 20, 70, 160, 75, ["Core 1..N", "ejecuta instrucciones", "se conecta y desconecta"], "core", 12)
    caja(d, 320, 135, 190, 70, ["Planificador", "escucha :8080", "Jobs, syscalls, servicios"], "planificador", 12)
    caja(d, 320, 10, 190, 70, ["Placa", "escucha :8081", "memoria + Offload"], "placa", 12)
    caja(d, 620, 135, 190, 70, ["Storage", "escucha :8082", "FAT32_TRAIN + journal"], "storage", 12)
    flecha(d, 180, 128, 320, 168, etiqueta="→ :8080  devoluciones, syscalls", en=0.5, dy=8)
    flecha(d, 180, 88, 320, 45, etiqueta="→ :8081  fetch, marcos, datos", en=0.5, dy=-14)
    flecha(d, 415, 135, 415, 80, etiqueta="→ :8081  Jobs, ALLOC/FREE, páginas", dx=72, dy=-4)
    flecha(d, 510, 170, 620, 170, etiqueta="→ :8082  checkpoints", dy=6)
    return d


def d_trama():
    d = Drawing(820, 140)
    y, h = 70, 50
    caja(d, 10, y, 120, h, ["op_code", "1 byte · uint8"], "planificador", 12, r=0)
    caja(d, 130, y, 190, h, ["size", "4 bytes · uint32 little endian"], "planificador", 12, r=0)
    caja(d, 320, y, 490, h, ["payload", "size bytes, armado con t_buffer"], "neutro", 12, r=0)
    texto(d, 10, y + h + 8, "Un mensaje en el socket", 10, "Sans-B", color=AZUL)
    texto(d, 320, 48, "Ejemplo, OP_EJECUTAR_JOB (0x40):", 9, "Sans-B")
    xs = [320, 400, 810]
    etiquetas = ["jid · 4 B", "contexto · 14 × uint32 = 56 B (PC, P0–P5, AX–DX, E1–E3)"]
    for i, e in enumerate(etiquetas):
        caja(d, xs[i], 8, xs[i + 1] - xs[i], 30, [e], "ok", 9, r=0)
    texto(d, 10, 30, "size = 60", 10, "Mono")
    texto(d, 10, 14, "→ el receptor lee 5 bytes y después exactamente size", 8.5, color=GRIS)
    return d


def d_hilos():
    d = Drawing(880, 220)
    izq = [("Largo plazo", "NEW → READY (multiprogramación)"), ("Corto plazo", "FIFO · RR · HRRN → despacha"),
           ("Timer de quantum", "uno por despacho (RR)")]
    der = [("Servidor de Cores", "1 hilo por Core conectado"), ("Page fault", "1 hilo por fault"),
           ("Servicios", "Loader · Labeler · Logger · Checkpoints")]
    ys = [160, 95, 30]
    for (t, s), y in zip(izq, ys):
        caja(d, 10, y, 210, 46, [t, s], "planificador", 11)
        flecha(d, 220, y + 23, 300, 115 + (y - 95) * 0.35)
    caja(d, 300, 60, 200, 110, ["Colas de Jobs", "NEW · READY · BLOCKED · EXIT", "mutex por cola + semáforos", "contexto y estadísticas"], "neutro", 11)
    for (t, s), y in zip(der, ys):
        caja(d, 560, y, 200, 46, [t, s], "planificador", 11)
        flecha(d, 560, y + 23, 500, 115 + (y - 95) * 0.35)
    caja(d, 795, 160, 80, 46, ["Cores", "1 socket c/u"], "core", 10)
    caja(d, 795, 95, 80, 46, ["Placa", ":8081"], "placa", 10)
    caja(d, 795, 30, 80, 46, ["Storage", ":8082"], "storage", 10)
    flecha(d, 760, 183, 795, 183, doble=True)
    flecha(d, 760, 118, 795, 118, doble=True)
    flecha(d, 760, 53, 795, 53, doble=True)
    return d


def d_estados():
    d = Drawing(840, 215)
    y, h = 120, 44
    estados = {"NEW": (10, "neutro"), "READY": (215, "planificador"), "EXEC": (450, "ok"), "EXIT": (700, "neutro")}
    for nombre, (x, m) in estados.items():
        caja(d, x, y, 120, h, [nombre], m, 13, r=20)
    caja(d, 450, 15, 120, h, ["BLOCKED"], "alerta", 13, r=20)
    flecha(d, 130, y + 22, 215, y + 22, etiqueta="hay lugar", dy=6)
    flecha(d, 335, y + 32, 450, y + 32, etiqueta="lo elige el corto plazo", dy=6)
    flecha(d, 450, y + 12, 335, y + 12, etiqueta="fin de quantum / se cae el Core", dy=-15)
    flecha(d, 570, y + 22, 700, y + 22, etiqueta="EXIT / error", dy=6)
    flecha(d, 510, y, 510, 15 + h, etiqueta="page fault / servicio", dx=62, dy=-4)
    flecha(d, 450, 37, 290, y, etiqueta="página cargada / servicio listo", dx=-70, dy=-14)
    flecha(d, 570, 37, 740, y, etiqueta="error del servicio", dx=48, dy=-16)
    return d


def d_secuencia(participantes, mensajes, ancho=820, alto=230):
    d = Drawing(ancho, alto)
    paso = (ancho - 160) / (len(participantes) - 1)
    xs = {}
    for i, (clave, nombre, modulo) in enumerate(participantes):
        x = 80 + i * paso
        xs[clave] = x
        caja(d, x - 70, alto - 34, 140, 30, [nombre], modulo, 11)
        linea = Line(x, alto - 34, x, 8, strokeColor=hx("#90A4AE"), strokeWidth=1)
        linea.strokeDashArray = [3, 3]
        d.add(linea)
    y = alto - 54
    salto = (alto - 70) / len(mensajes)
    for m in mensajes:
        if m[0] == "nota":
            x = xs[m[1]]
            w = max(stringWidth(m[2], "Sans-B", 9) + 16, 90)
            caja(d, x - w / 2, y - 9, w, 18, [m[2]], m[3] if len(m) > 3 else "alerta", 9, r=4)
        else:
            origen, destino, etiqueta = m[:3]
            respuesta = len(m) > 3 and m[3]
            flecha(d, xs[origen], y, xs[destino], y, discontinua=respuesta, etiqueta=etiqueta, tam=10, dy=4,
                   color="#455A64" if respuesta else AZUL)
        y -= salto
    return d


def d_page_fault():
    return d_secuencia(
        [("C", "Core", "core"), ("PL", "Placa", "placa"), ("P", "Planificador", "planificador")],
        [("C", "PL", "OBTENER_MARCO {jid, pág 3}"), ("PL", "C", "{ok = false}: no está presente", True),
         ("C", "PL", "DESLOCKEAR_PAGINAS {jid} (lo que ya tenía)"),
         ("C", "P", "DEVOLUCION {jid, PAGE_FAULT, contexto (PC sin avanzar), 3}"),
         ("nota", "P", "BLOCKED · page faults + 1"), ("P", "PL", "CARGA_PAGINA {jid, 3}"),
         ("nota", "PL", "víctima LRU / CLOCK-M · Offload", "placa"), ("PL", "P", "{ok}", True),
         ("nota", "P", "READY → reintenta la instrucción", "ok")], alto=250)


def d_ciclo():
    d = Drawing(840, 175)
    pasos = [("FETCH", "OP_FETCH_INSTRUCCION", "{jid, pc} → línea", "core"),
             ("DECODE", "operación + parámetros", "traduce con la MMU", "core"),
             ("EXECUTE", "registros / memoria", "o syscall", "core"),
             ("CHECK INTERRUPT", "¿hay OP_INTERRUPCION", "para este jid?", "planificador")]
    x = 10
    for i, (t, a, b, m) in enumerate(pasos):
        caja(d, x, 95, 170, 62, [t, a, b], m, 12)
        if i < 3:
            flecha(d, x + 170, 126, x + 215, 126)
        x += 215
    # vuelta al FETCH
    for seg in [(745, 95, 745, 62), (745, 62, 95, 62)]:
        d.add(Line(*seg, strokeColor=hx(AZUL), strokeWidth=1.3))
    flecha(d, 95, 62, 95, 95, etiqueta="no: PC + 1 (salvo JNZ / SET PC) y sigue", dx=230, dy=-42)
    caja(d, 500, 8, 330, 36, ["Sí: OP_DEVOLUCION {jid, FIN_QUANTUM, contexto}"], "alerta", 10)
    flecha(d, 800, 95, 800, 44)
    caja(d, 10, 8, 440, 36, ["EXECUTE también devuelve el Job: page fault · syscall que bloquea · EXIT"], "neutro", 10)
    return d


def d_mmu():
    d = Drawing(840, 215)
    escala = 2.0  # px por byte
    x0 = 60
    texto(d, 10, 195, "Espacio lógico del Job (TAM_PAGINA = 64)", 10, "Sans-B", color=AZUL)
    for pag in range(4):
        x = x0 + pag * 64 * escala
        d.add(Rect(x, 150, 64 * escala, 32, fillColor=hx("#FFFFFF"), strokeColor=hx("#90A4AE")))
        texto(d, x + 4, 186, f"pág {pag}  [{pag * 64}, {pag * 64 + 64})", 8, color=GRIS)
    # rango [100, 200)
    tramos = [(100, 128, 1, 5), (128, 192, 2, 2), (192, 200, 3, 6)]
    tonos = ["#90CAF9", "#A5D6A7", "#FFCC80"]
    for (a, b, pag, marco), tono in zip(tramos, tonos):
        d.add(Rect(x0 + a * escala, 152, (b - a) * escala, 28, fillColor=hx(tono), strokeColor=None))
    texto(d, x0 + 100 * escala, 140, "100", 8, "Mono", "middle")
    texto(d, x0 + 200 * escala, 140, "200", 8, "Mono", "middle")
    texto(d, x0 + 150 * escala, 162, "LOAD_BATCH P1=100 CX=100", 9, "Sans-B", "middle")
    # memoria física
    texto(d, 10, 92, "Memoria física (marcos)", 10, "Sans-B", color=AZUL)
    ancho_marco = 64
    for m in range(8):
        x = x0 + m * ancho_marco
        d.add(Rect(x, 40, ancho_marco, 40, fillColor=hx("#FFFFFF"), strokeColor=hx("#90A4AE")))
        texto(d, x + ancho_marco / 2, 28, f"marco {m}", 8, ancla="middle", color=GRIS)
    for (a, b, pag, marco), tono in zip(tramos, tonos):
        desp = a - pag * 64
        x = x0 + marco * ancho_marco + desp
        d.add(Rect(x, 42, b - a, 36, fillColor=hx(tono), strokeColor=None))
        flecha(d, x0 + (a + b) / 2 * escala, 150, x + (b - a) / 2, 80, color="#546E7A", ancho=1, punta=6)
    filas = ["tramo 1: pág 1 → marco 5  (5·64 + 36 = 356, 28 B)",
             "tramo 2: pág 2 → marco 2  (2·64 = 128, 64 B)",
             "tramo 3: pág 3 → marco 6  (6·64 = 384, 8 B)"]
    for i, (f, tono) in enumerate(zip(filas, tonos)):
        d.add(Rect(600, 165 - i * 26, 12, 12, fillColor=hx(tono), strokeColor=None))
        texto(d, 618, 167 - i * 26, f, 9, "Mono")
    texto(d, 600, 70, "Las 3 páginas quedan lockeadas hasta", 9)
    texto(d, 600, 56, "que termina la instrucción o el servicio.", 9)
    texto(d, 600, 36, "Si alguna no está: page fault.", 9, "Sans-B", color=COLOR["alerta"][1])
    return d


def d_clock():
    d = Drawing(860, 235)
    cx, cy, r = 150, 112, 82
    marcos = [("M0", 1, 0, False), ("M1", 1, 1, False), ("M2", 0, 1, False), ("M3", 0, 0, True), ("M4", 1, 0, False), ("M5", 1, 1, False)]
    texto(d, 10, 220, "CLOCK-M: estado antes de elegir víctima", 10, "Sans-B", color=AZUL)
    d.add(Circle(cx, cy, r, fillColor=None, strokeColor=hx("#CFD8DC"), strokeWidth=1))
    for i, (n, u, m, lock) in enumerate(marcos):
        ang = math.pi / 2 - i * 2 * math.pi / len(marcos)
        x, y = cx + r * math.cos(ang), cy + r * math.sin(ang)
        modulo = "alerta" if n == "M2" else ("neutro" if lock else "placa")
        etiqueta = [n, "lockeada" if lock else f"u={u} m={m}"]
        caja(d, x - 34, y - 19, 68, 38, etiqueta, modulo, 10)
    flecha(d, cx, cy, cx, cy + r - 22, color="#37474F", ancho=2, etiqueta="puntero", dx=26, dy=-24)
    pasos = [
        ("Vuelta 1 · busca (u=0, m=0) sin tocar bits", "M3 es (0,0) pero está lockeada → no hay víctima"),
        ("Vuelta 2 · busca (u=0, m=1) y apaga u al pasar", "M0 (1,0) → u=0 · M1 (1,1) → u=0 · M2 (0,1) → víctima ✔"),
        ("M2 está modificada", "→ se escribe en el Offload antes de pisar el marco"),
        ("El puntero queda en M3", "si no hubiera víctima: vueltas 3 y 4 repiten la búsqueda"),
    ]
    y = 200
    for t, s in pasos:
        texto(d, 300, y, t, 10, "Sans-B")
        texto(d, 300, y - 14, s, 9.5)
        y -= 40
    caja(d, 300, 8, 550, 34, ["LRU: víctima = menor ultimo_acceso (cada acceso suma un contador global)"], "neutro", 10)
    return d


def d_volumen():
    d = Drawing(860, 215)
    texto(d, 10, 200, "Ejemplo: TAM_BLOQUE = 64 · CANT_BLOQUES = 256 · BLOQUES_DIRECTORIO = 4", 10, "Sans-B", color=AZUL)
    x, y, w, h = 10, 140, 26, 34
    regiones = [("superbloque", 1, "neutro", "bloque 0"), ("FAT", 16, "planificador", "1 – 16 (256 × 4 B)"),
                ("directorio", 4, "storage", "17 – 20"), ("datos", 9, "ok", "21 – 255")]
    pos = {}
    for nombre, n, modulo, rango in regiones:
        f, b = COLOR[modulo]
        inicio = x
        for i in range(n):
            if nombre == "FAT" and 3 <= i < 13:
                if i == 3:  # la FAT completa no entra: se resume con "…"
                    texto(d, x + w / 2, y + 12, "…", 14, "Sans-B", "middle", b)
                    x += w
                continue
            d.add(Rect(x, y, w, h, fillColor=hx(f), strokeColor=hx(b), strokeWidth=0.8))
            x += w
        pos[nombre] = (inicio, x)
        texto(d, (inicio + x) / 2, y + h + 6, nombre, 10, "Sans-B", "middle")
        texto(d, (inicio + x) / 2, y - 12, rango, 8.5, ancla="middle", color=GRIS)
    texto(d, x + 8, y + 13, "…", 14, "Sans-B")
    # cadena de ejemplo
    texto(d, 10, 96, "Checkpoint \"modelo\" de 100 bytes → 2 bloques", 10, "Sans-B")
    caja(d, 10, 40, 220, 44, ["Directorio", "modelo · 100 B · inicial 21"], "storage", 10)
    caja(d, 290, 40, 150, 44, ["FAT[21] = 22", "bloque siguiente"], "planificador", 10)
    caja(d, 500, 40, 170, 44, ["FAT[22] = 0x0FFFFFFF", "fin del checkpoint"], "planificador", 10)
    flecha(d, 230, 62, 290, 62)
    flecha(d, 440, 62, 500, 62)
    texto(d, 690, 72, "FAT[0..20] = 0x0FFFFFFE", 9, "Mono")
    texto(d, 690, 58, "(reservados)", 8.5, color=GRIS)
    texto(d, 690, 40, "resto = 0 (libres)", 9, "Mono")
    texto(d, 10, 14, "Bloques 21 y 22: los datos (64 + 36 bytes). Sobre 32 bytes por entrada, 4 bloques de directorio = 8 checkpoints.", 9, color=GRIS)
    return d


def d_journal():
    d = Drawing(860, 215)
    pasos = [("RECORD_STARTED 2", "modelo", "neutro"), ("OP_DIR · OP_FAT · OP_WRITE", "valores finales", "planificador"),
             ("RECORD_COMMITED 2", "fsync · RETARDO_COMMIT", "ok"), ("se aplica", "en volumen.dat", "storage"),
             ("RECORD_APPLIED 2", "asiento cerrado", "ok")]
    x, y, w = 10, 130, 150
    for i, (t, s, m) in enumerate(pasos):
        caja(d, x, y, w, 50, [t, s], m, 10)
        if i < len(pasos) - 1:
            flecha(d, x + w, y + 25, x + w + 22, y + 25)
        x += w + 22
    texto(d, 10, 195, "Orden de escritura de un asiento en journal.txt (fwrite + fflush + fsync por línea)", 10, "Sans-B", color=AZUL)
    # marcas de kill -9
    for xk, letra, accion, modulo in [(250, "A", "sin COMMIT → se DESCARTA", "alerta"), (590, "B", "COMMIT sin APPLIED → se RE-APLICA", "placa")]:
        d.add(Line(xk, 120, xk, 92, strokeColor=hx(COLOR[modulo][1]), strokeWidth=2))
        caja(d, xk - 130, 48, 260, 44, [f"kill -9 en {letra} (prueba 05 {letra})", accion], modulo, 10)
    caja(d, 10, 2, 840, 34, ["Al arrancar se recorre el journal en orden · re-aplicar un asiento ya aplicado no cambia nada (idempotente)"], "neutro", 10)
    return d


def d_cierre():
    d = Drawing(860, 185)
    pasos = [("Ctrl-C / SIGTERM", "llega al proceso", "alerta"), ("hilo de cierre", "sigwait()", "planificador"),
             ("log", "\"Se recibió SIGINT: el", "planificador"), ("SIG_DFL + raise()", "acción por defecto", "planificador"),
             ("fin del proceso", "como un Ctrl-C común", "neutro")]
    x = 10
    for i, (t, s, m) in enumerate(pasos):
        lineas = [t, s] + (["módulo finaliza\""] if t == "log" else [])
        caja(d, x, 110, 150, 56, lineas, m, 10.5)
        if i < len(pasos) - 1:
            flecha(d, x + 150, 138, x + 172, 138)
        x += 172
    texto(d, 10, 86, "Los demás hilos heredan la señal bloqueada: nunca los interrumpe a mitad de camino", 10, "Sans-B", color=AZUL)
    otros = [("main", "accept() / recv()"), ("consola Placa", "fgets(stdin)"), ("Labeler", "getline(stdin)"),
             ("hilos de Cores", "recv()"), ("retardos", "usleep()")]
    x = 10
    for t, s in otros:
        caja(d, x, 22, 150, 46, [t, s], "neutro", 10, mono=True)
        x += 172
    return d


def d_servidores():
    d = Drawing(860, 230)
    caja(d, 10, 80, 220, 90, ["Máquina de control", "deploy/catedra.sh", "deploy/resultados/", "(logs y reportes juntos)"], "neutro", 11)
    servidores = [(".25", "Placa", "tp-placa", "placa"), (".26", "Storage", "tp-storage", "storage"),
                  (".27", "Planificador", "tp-planificador", "planificador"), (".28", "Core 1 (y 3)", "tp-core-1", "core"),
                  (".29", "Core 2 (y 4)", "tp-core-2", "core")]
    y = 186
    for ip, mod, sesion, m in servidores:
        caja(d, 430, y, 250, 38, [f"192.168.1{ip} · {mod}", f"tmux: {sesion} · ~/tp-run/"], m, 10)
        flecha(d, 230, 125, 430, y + 19, color="#546E7A", ancho=1, punta=6)
        y -= 45
    texto(d, 250, 205, "ssh (clave pública, sin contraseña)", 9, "Sans-B", color=AZUL)
    texto(d, 700, 170, "Reparto: deploy/catedra.conf", 10, "Sans-B")
    texto(d, 700, 154, "PLACA · STORAGE · PLANIFICADOR", 9, "Mono")
    texto(d, 700, 140, "CORES_HOSTS", 9, "Mono")
    texto(d, 700, 116, "Se pisa desde el entorno:", 10, "Sans-B")
    texto(d, 700, 100, "STORAGE=192.168.1.27 \\", 9, "Mono")
    texto(d, 700, 86, "  deploy/catedra.sh …", 9, "Mono")
    return d


DIBUJOS = {
    "arquitectura": (d_arquitectura, 6.8), "trama": (d_trama, 4.4), "hilos": (d_hilos, 6.0),
    "estados": (d_estados, 6.4), "page_fault": (d_page_fault, 6.6), "ciclo": (d_ciclo, 5.6),
    "mmu": (d_mmu, 6.6), "clock": (d_clock, 7.4), "volumen": (d_volumen, 6.4), "journal": (d_journal, 6.4),
    "cierre": (d_cierre, 5.2), "servidores": (d_servidores, 7.0),
}


# --- diapositivas ---

def fuera_de_codigo(lineas):
    """(índice, línea) de las líneas que no están dentro de un bloque ```."""
    en_codigo = False
    for j, l in enumerate(lineas):
        if l.strip().startswith("```"):
            en_codigo = not en_codigo
        elif not en_codigo:
            yield j, l


def tabla(filas, ancho):
    """Como ep.tabla, pero ninguna columna es más angosta que su palabra más larga."""
    celdas = [[c.strip() for c in re.split(r"(?<!\\)\|", f.strip().strip("|"))] for f in filas]
    celdas = [celdas[0]] + celdas[2:]
    columnas = max(len(f) for f in celdas)
    for f in celdas:
        f += [""] * (columnas - len(f))
    limpio = lambda t: re.sub(r"[`*\[\]]", "", t)
    largos = [max(min(len(limpio(f[i])), 60) for f in celdas) + 3 for i in range(columnas)]
    minimos = []
    for i in range(columnas):
        m = 0
        for r, f in enumerate(celdas):
            estilo = ep.E["celda_h"] if r == 0 else ep.E["celda"]
            for palabra in limpio(f[i]).split():
                m = max(m, stringWidth(palabra, estilo.fontName, estilo.fontSize))
        minimos.append(min(m + 10, ancho * 0.4))
    total = sum(largos)
    anchos = [max(ancho * l / total, m) for l, m in zip(largos, minimos)]
    escala = ancho / sum(anchos)
    anchos = [a * escala for a in anchos]
    datos = [[Paragraph(ep.inline(c), ep.E["celda_h"] if r == 0 else ep.E["celda"]) for c in fila] for r, fila in enumerate(celdas)]
    t = Table(datos, colWidths=anchos, repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), hx(AZUL)),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, hx("#F4F7FA")]),
        ("GRID", (0, 0), (-1, -1), 0.4, hx("#C5CED8")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 3), ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5),
        ("LEFTPADDING", (0, 0), (-1, -1), 4.5), ("RIGHTPADDING", (0, 0), (-1, -1), 4.5),
    ]))
    return [t, Spacer(1, 6)]


ep.tabla = tabla

ESTILO_BANDA = ParagraphStyle("banda", fontName="Sans-B", fontSize=20, leading=24, textColor=colors.white)
ESTILO_SECCION = ParagraphStyle("seccion", fontName="Sans-B", fontSize=26, leading=30, textColor=colors.white, alignment=TA_CENTER)


def banda(titulo):
    # el código del título va sin fondo claro (sobre la banda azul no se leería)
    marcado = re.sub(r' backColor="[^"]*"', "", ep.inline(titulo)).replace('size="12.5"', 'size="19"')
    t = Table([[Paragraph(marcado, ESTILO_BANDA)]], colWidths=[ANCHO], rowHeights=[ALTO_BANDA])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), hx(AZUL)), ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                           ("LEFTPADDING", (0, 0), (-1, -1), 14)]))
    return t


def contenido(lineas):
    salida, buf, i = [], [], 0

    def volcar():
        if buf:
            salida.extend(ep.bloques(buf, ANCHO))
            buf.clear()

    while i < len(lineas):
        s = lineas[i].strip()
        m = re.match(r"<!--\s*dibujo:\s*(\w+)\s*-->", s)
        if m:
            volcar()
            funcion, alto = DIBUJOS[m.group(1)]
            salida += [ajustar(funcion(), ANCHO, alto * 1.3 * cm), Spacer(1, 8)]
            i += 1
            while i < len(lineas) and not lineas[i].strip():
                i += 1
            if i < len(lineas) and lineas[i].strip().startswith("```"):
                i += 1
                while i < len(lineas) and not lineas[i].strip().startswith("```"):
                    i += 1
                i += 1
            continue
        f = re.match(r"^\$\$(.+)\$\$$", s)
        if f:
            volcar()
            salida.append(Paragraph(f.group(1).replace("&", "&amp;").replace("<", "&lt;"), FORMULA))
            i += 1
            continue
        buf.append(lineas[i])
        i += 1
    volcar()
    return salida


def portada(lineas, final=False):
    titulo = next(l[2:] for _, l in fuera_de_codigo(lineas) if l.startswith("# "))
    subtitulo = next((l[3:] for _, l in fuera_de_codigo(lineas) if l.startswith("## ")), "")
    resto = [l for _, l in fuera_de_codigo(lineas) if not l.startswith("#")]
    grande = ParagraphStyle("g", fontName="Sans-B", fontSize=44, leading=52, alignment=TA_CENTER, textColor=hx(AZUL))
    medio = ParagraphStyle("m", fontName="Sans", fontSize=22, leading=28, alignment=TA_CENTER)
    chico = ParagraphStyle("c", fontName="Sans", fontSize=13, leading=19, alignment=TA_CENTER, textColor=hx("#333333"))
    flow = [Spacer(1, 3.2 * cm if not final else 5 * cm), Paragraph(ep.inline(titulo), grande)]
    if subtitulo:
        flow += [Spacer(1, 0.3 * cm), Paragraph(ep.inline(subtitulo), medio)]
    flow.append(Spacer(1, 0.9 * cm))
    for l in resto:
        if l.strip():
            flow += [Paragraph(ep.inline(re.sub(r"^\d+\.\s+", "", l.strip()) if not l.strip()[0].isdigit() else l.strip()), chico), Spacer(1, 0.25 * cm)]
    return flow


class Presentacion(BaseDocTemplate):
    def __init__(self, ruta, total):
        super().__init__(ruta, pagesize=(ANCHO_PAG, ALTO_PAG), leftMargin=MARGEN, rightMargin=MARGEN,
                         topMargin=MARGEN, bottomMargin=MARGEN + 0.4 * cm,
                         title="EntrenadOS · Cómo funciona el TP", author="RequiemSO")
        self.total = total
        marco = Frame(MARGEN, MARGEN + 0.4 * cm, ANCHO, ALTO_PAG - 2 * MARGEN - 0.4 * cm, id="f",
                      leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
        self.addPageTemplates([PageTemplate(id="d", frames=marco, onPage=self.pie)])

    def pie(self, canvas, doc):
        canvas.saveState()
        canvas.setFont("Sans", 8.5)
        canvas.setFillColor(hx(GRIS))
        canvas.drawString(MARGEN, 0.75 * cm, "TP EntrenadOS 2C2026 · RequiemSO · Cómo funciona el TP")
        canvas.drawRightString(ANCHO_PAG - MARGEN, 0.75 * cm, f"{doc.page} / {self.total}")
        canvas.restoreState()


def main(boveda, salida):
    nota = os.path.join(boveda, "Presentación - Funcionamiento del TP.md")
    _, lineas = ep.leer_nota(nota)
    diapositivas, actual = [], []
    for l in lineas:
        if l.strip() == "---":
            diapositivas.append(actual)
            actual = []
        else:
            actual.append(l)
    diapositivas.append(actual)
    diapositivas = [d for d in diapositivas if any(x.strip() for x in d)]

    historia = []
    for n, d in enumerate(diapositivas):
        if any(l.startswith("# ") for _, l in fuera_de_codigo(d)):
            historia += portada(d, final=n == len(diapositivas) - 1)
        else:
            # el título es el primer "## " fuera de un bloque de código
            indice = next(j for j, l in fuera_de_codigo(d) if l.startswith("## "))
            titulo, cuerpo = d[indice][3:], d[:indice] + d[indice + 1:]
            historia += [banda(titulo), Spacer(1, 0.45 * cm),
                         KeepInFrame(ANCHO, ALTO_CONTENIDO, contenido(cuerpo), mode="shrink")]
        historia.append(PageBreak())
    historia.pop()

    Presentacion(salida, len(diapositivas)).build(historia)
    print("PDF generado:", salida, f"({len(diapositivas)} diapositivas)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
