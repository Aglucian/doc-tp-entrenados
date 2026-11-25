"""Exporta la bóveda de Obsidian del TP a un único PDF (portada, índice y todas las notas).

Uso, desde la raíz de la bóveda:
    python3 herramientas/exportar_pdf.py . "TP EntrenadOS - Documentación completa.pdf"

Necesita reportlab (pip install reportlab, que trae pillow) y las fuentes DejaVu
(/usr/share/fonts/truetype/dejavu/, incluidas en Ubuntu). Si se agrega una nota nueva,
hay que sumarla a la lista NOTAS, en el orden en que tiene que aparecer.
Los diagramas mermaid salen como código: dibujarlos requiere mermaid-cli (Node).
"""
import datetime
import os
import re
import sys

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import cm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, CondPageBreak, Frame, KeepTogether, PageBreak, PageTemplate,
                                Paragraph, Preformatted, Spacer, Table, TableStyle)
from reportlab.platypus.tableofcontents import TableOfContents

FUENTES = "/usr/share/fonts/truetype/dejavu/"
pdfmetrics.registerFont(TTFont("Sans", FUENTES + "DejaVuSans.ttf"))
pdfmetrics.registerFont(TTFont("Sans-B", FUENTES + "DejaVuSans-Bold.ttf"))
pdfmetrics.registerFont(TTFont("Sans-I", FUENTES + "DejaVuSans-Oblique.ttf"))
pdfmetrics.registerFont(TTFont("Sans-BI", FUENTES + "DejaVuSans-BoldOblique.ttf"))
pdfmetrics.registerFont(TTFont("Mono", FUENTES + "DejaVuSansMono.ttf"))
pdfmetrics.registerFontFamily("Sans", normal="Sans", bold="Sans-B", italic="Sans-I", boldItalic="Sans-BI")

# Orden de lectura, el mismo de "00 - Inicio".
NOTAS = [
    ("00 - Inicio.md", "Inicio"),
    ("Plan de acción.md", "Planificación"),
    ("Estado de ramas.md", "Planificación"),
    ("Bugs encontrados.md", "Planificación"),
    ("Despliegue distribuido.md", "Planificación"),
    ("Módulos/Planificador.md", "Módulos"),
    ("Módulos/Core.md", "Módulos"),
    ("Módulos/Placa.md", "Módulos"),
    ("Módulos/Storage.md", "Módulos"),
    ("Módulos/Utils.md", "Módulos"),
    ("Módulos/Protocolo.md", "Módulos"),
    ("Pruebas/Mini Entrenamiento 2026-11-14.md", "Pruebas"),
    ("Pruebas/Suite cátedra 2026-11-14.md", "Pruebas"),
    ("Pruebas/Check 4 2026-11-14.md", "Pruebas"),
    ("Pruebas/Pruebas finales 2026-11-24.md", "Pruebas"),
    ("Coloquio/Teoría vs implementación.md", "Coloquio"),
    ("Coloquio/Decisiones de diseño.md", "Coloquio"),
    ("Coloquio/Concurrencia y sincronización.md", "Coloquio"),
    ("NotebookLM/Prompts de audio.md", "Coloquio"),
    ("Presentación - Funcionamiento del TP.md", "Presentación"),
]

ANCHO = A4[0] - 3.6 * cm
AZUL = colors.HexColor("#2F5D8A")
GRIS = colors.HexColor("#666666")

CALLOUTS = {  # tipo -> (fondo, borde, ícono)
    "success": ("#E8F5E9", "#2E7D32", "✔"), "info": ("#E3F2FD", "#1565C0", "ℹ"), "note": ("#E3F2FD", "#1565C0", "✎"),
    "tip": ("#E0F7FA", "#00838F", "★"), "warning": ("#FFF8E1", "#F57F17", "⚠"), "danger": ("#FFEBEE", "#C62828", "⚠"),
    "bug": ("#FFEBEE", "#C62828", "✘"), "important": ("#F3E5F5", "#6A1B9A", "!"), "todo": ("#EDE7F6", "#4527A0", "☐"),
}

base = dict(fontName="Sans", fontSize=9.2, leading=12.6)
E = {
    "p": ParagraphStyle("p", **base, spaceAfter=4),
    "celda": ParagraphStyle("celda", fontName="Sans", fontSize=7.6, leading=9.6),
    "celda_h": ParagraphStyle("celda_h", fontName="Sans-B", fontSize=7.6, leading=9.6, textColor=colors.white),
    "h1": ParagraphStyle("h1", fontName="Sans-B", fontSize=19, leading=24, textColor=AZUL, spaceAfter=6),
    "h2": ParagraphStyle("h2", fontName="Sans-B", fontSize=13.5, leading=18, textColor=AZUL, spaceBefore=10, spaceAfter=4),
    "h3": ParagraphStyle("h3", fontName="Sans-B", fontSize=11, leading=15, spaceBefore=7, spaceAfter=3),
    "h4": ParagraphStyle("h4", fontName="Sans-B", fontSize=9.6, leading=13, spaceBefore=5, spaceAfter=2),
    "meta": ParagraphStyle("meta", fontName="Sans", fontSize=7.5, leading=10, textColor=GRIS, spaceAfter=6),
    "seccion": ParagraphStyle("seccion", fontName="Sans-B", fontSize=8, leading=10, textColor=GRIS),
    "codigo": ParagraphStyle("codigo", fontName="Mono", fontSize=7.2, leading=9.2),
    "nota_mermaid": ParagraphStyle("nm", fontName="Sans-I", fontSize=7.5, leading=10, textColor=GRIS),
}


def es_dark(c):
    return colors.HexColor(c)


# --- inline ---

def inline(texto):
    """Markdown en línea -> mini-markup de reportlab."""
    texto = texto.replace("️", "")
    guardados = []

    def guardar(html):
        guardados.append(html)
        return f"\x00{len(guardados) - 1}\x00"

    # los emojis sin glifo en DejaVu se cambian por símbolos que sí tiene (ya como markup)
    texto = texto.replace("✅", guardar('<font color="#2E7D32">✔</font>'))
    texto = texto.replace("🟡", guardar('<font color="#F57F17">◐</font>'))

    def escapar(t):
        return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

    # código en línea primero: su contenido no se interpreta
    texto = re.sub(r"`([^`]+)`", lambda m: guardar(f'<font face="Mono" size="8" backColor="#EEF1F5">{escapar(m.group(1))}</font>'), texto)
    # enlaces de Obsidian: [[nota#sección|alias]]
    def wiki(m):
        destino, _, alias = m.group(1).partition("|")
        mostrar = alias or destino.split("#")[0] or destino
        return guardar(f'<font color="#2F5D8A"><b>{escapar(mostrar.replace(chr(92), ""))}</b></font>')
    texto = re.sub(r"\[\[([^\]]+)\]\]", wiki, texto)
    texto = re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", lambda m: guardar(f'<link href="{m.group(2)}" color="#2F5D8A"><u>{escapar(m.group(1))}</u></link>'), texto)
    texto = re.sub(r"\$\$([^$]+)\$\$", lambda m: guardar(f'<font face="Mono" size="8">{escapar(m.group(1))}</font>'), texto)
    # \| dentro de tablas y otros escapes de Markdown
    texto = texto.replace("\\|", "|").replace("\\_", "_").replace("\\*", "*")
    texto = escapar(texto)
    texto = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", texto)
    texto = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<i>\1</i>", texto)
    texto = re.sub(r"~~(.+?)~~", r"<strike>\1</strike>", texto)
    # puede haber marcadores dentro de lo guardado (código dentro del alias de un enlace)
    while "\x00" in texto:
        texto = re.sub(r"\x00(\d+)\x00", lambda m: guardados[int(m.group(1))], texto)
    return texto


# --- bloques ---

def tabla(filas, ancho):
    celdas = [[c.strip() for c in re.split(r"(?<!\\)\|", f.strip().strip("|"))] for f in filas]
    celdas = [celdas[0]] + [f for f in celdas[2:]]
    columnas = max(len(f) for f in celdas)
    for f in celdas:
        f += [""] * (columnas - len(f))
    # ancho de cada columna según el largo de su contenido (con mínimo y máximo)
    largos = [max(min(len(re.sub(r"[`*\[\]]", "", f[i])), 60) for f in celdas) + 3 for i in range(columnas)]
    total = sum(largos)
    anchos = [max(ancho * l / total, 1.4 * cm) for l in largos]
    escala = ancho / sum(anchos)
    anchos = [a * escala for a in anchos]
    datos = [[Paragraph(inline(c), E["celda_h"] if r == 0 else E["celda"]) for c in fila] for r, fila in enumerate(celdas)]
    t = Table(datos, colWidths=anchos, repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), AZUL),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F4F7FA")]),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#C5CED8")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 2.5), ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5),
        ("LEFTPADDING", (0, 0), (-1, -1), 3.5), ("RIGHTPADDING", (0, 0), (-1, -1), 3.5),
    ]))
    return [t, Spacer(1, 5)]


def codigo(lineas, lenguaje, ancho):
    caracteres = max(int(ancho / (7.2 * 0.6)) - 2, 40)
    texto = "\n".join(lineas) or " "
    pre = Preformatted(texto, E["codigo"], maxLineLength=caracteres, newLineChars="↪ ")
    contenido = [pre]
    if lenguaje == "mermaid":
        contenido = [Paragraph("Diagrama (mermaid). Se ve dibujado en Obsidian.", E["nota_mermaid"]), pre]
    t = Table([[contenido]], colWidths=[ancho])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#F5F7F9")),
        ("BOX", (0, 0), (-1, -1), 0.4, colors.HexColor("#D5DCE3")),
        ("LEFTPADDING", (0, 0), (-1, -1), 6), ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]))
    return [t, Spacer(1, 5)]


def recuadro(lineas, ancho):
    """Callout de Obsidian (> [!tipo] Título) o cita común."""
    m = re.match(r"\[!(\w+)\]-?\s*(.*)", lineas[0].strip()) if lineas else None
    tipo, titulo = (m.group(1).lower(), m.group(2)) if m else ("quote", "")
    cuerpo = lineas[1:] if m else lineas
    fondo, borde, icono = CALLOUTS.get(tipo, ("#F5F5F5", "#9E9E9E", "❝"))
    contenido = []
    if m:
        etiqueta = titulo or tipo.capitalize()
        contenido.append(Paragraph(f'<font color="{borde}"><b>{icono} {inline(etiqueta)}</b></font>', E["p"]))
    contenido += bloques(cuerpo, ancho - 14)
    t = Table([[contenido]], colWidths=[ancho])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor(fondo)),
        ("LINEBEFORE", (0, 0), (0, -1), 3, colors.HexColor(borde)),
        ("LEFTPADDING", (0, 0), (-1, -1), 8), ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
    ]))
    return [t, Spacer(1, 6)]


RE_ITEM = re.compile(r"^(\s*)([-*+]|\d+\.)\s+(.*)$")


def item_lista(linea):
    m = RE_ITEM.match(linea)
    sangria, marca, texto = len(m.group(1).replace("\t", "  ")), m.group(2), m.group(3)
    nivel = sangria // 2
    # La viñeta se dibuja aparte del párrafo: no admite markup, así que el color va en el estilo
    # y la fuente tiene que ser DejaVu (la de por defecto, Helvetica, no tiene ☐ ni ☑).
    color = colors.black
    if texto.startswith("[ ] "):
        vineta, texto = "☐", texto[4:]
    elif texto[:4].lower() == "[x] ":
        vineta, texto, color = "☑", texto[4:], colors.HexColor("#2E7D32")
    elif marca[0].isdigit():
        vineta = marca
    else:
        vineta = "•" if nivel == 0 else ("◦" if nivel == 1 else "▪")
    estilo = ParagraphStyle("li", parent=E["p"], leftIndent=12 + nivel * 12, bulletIndent=2 + nivel * 12, spaceAfter=1.5,
                            bulletFontName="Sans", bulletFontSize=E["p"].fontSize, bulletColor=color)
    return Paragraph(inline(texto), estilo, bulletText=vineta)


def bloques(lineas, ancho, toc_nota=None):
    salida, i = [], 0
    while i < len(lineas):
        linea = lineas[i]
        s = linea.strip()
        if not s or (s.startswith("<!--") and s.endswith("-->")):  # vacías y comentarios HTML (marcas de dibujo)
            i += 1
            continue
        if s.startswith("```"):
            lenguaje, buf = s[3:].strip(), []
            i += 1
            while i < len(lineas) and not lineas[i].strip().startswith("```"):
                buf.append(lineas[i])
                i += 1
            salida += codigo(buf, lenguaje, ancho)
            i += 1
            continue
        m = re.match(r"^(#{1,6})\s+(.*)", s)
        if m:
            nivel = min(len(m.group(1)), 4)
            p = Paragraph(inline(m.group(2)), E[f"h{nivel}"])
            if nivel == 2 and toc_nota is not None:
                p._toc = (1, re.sub(r"<[^>]+>", "", inline(m.group(2))))
            salida += [CondPageBreak(2.5 * cm), p] if nivel <= 2 else [p]
            i += 1
            continue
        if s.startswith(">"):
            buf = []
            while i < len(lineas) and lineas[i].strip().startswith(">"):
                buf.append(re.sub(r"^\s*> ?", "", lineas[i]))
                i += 1
            salida += recuadro(buf, ancho)
            continue
        if s.startswith("|"):
            buf = []
            while i < len(lineas) and lineas[i].strip().startswith("|"):
                buf.append(lineas[i])
                i += 1
            if len(buf) >= 2 and re.match(r"^\|?\s*:?-{2,}", buf[1].strip()):
                salida += tabla(buf, ancho)
            else:
                salida += [Paragraph(inline(" ".join(buf)), E["p"])]
            continue
        if re.match(r"^(-{3,}|\*{3,})$", s):
            linea_hr = Table([[""]], colWidths=[ancho], rowHeights=[4])
            linea_hr.setStyle(TableStyle([("LINEBELOW", (0, 0), (-1, -1), 0.6, colors.HexColor("#C5CED8"))]))
            salida += [linea_hr, Spacer(1, 4)]
            i += 1
            continue
        if RE_ITEM.match(linea):
            while i < len(lineas) and lineas[i].strip():
                if RE_ITEM.match(lineas[i]):
                    texto = lineas[i]
                    i += 1
                    # continuaciones del mismo ítem (líneas sangradas que no son otro ítem)
                    while i < len(lineas) and lineas[i].strip() and not RE_ITEM.match(lineas[i]) and lineas[i].startswith("  "):
                        texto += " " + lineas[i].strip()
                        i += 1
                    salida.append(item_lista(texto))
                elif lineas[i].strip().startswith("```"):
                    break
                else:
                    break
            salida.append(Spacer(1, 3))
            continue
        # párrafo
        buf = []
        while i < len(lineas) and lineas[i].strip() and not re.match(r"^\s*(#{1,6}\s|```|>|\||[-*+]\s|\d+\.\s)", lineas[i]):
            buf.append(lineas[i].strip())
            i += 1
        if not buf:
            buf.append(s)
            i += 1
        salida.append(Paragraph(inline(" ".join(buf)), E["p"]))
    return salida


# --- documento ---

class Documento(BaseDocTemplate):
    def __init__(self, ruta, **kw):
        super().__init__(ruta, pagesize=A4, leftMargin=1.8 * cm, rightMargin=1.8 * cm, topMargin=1.7 * cm,
                         bottomMargin=1.6 * cm, title="TP EntrenadOS 2C2026 — Documentación", author="RequiemSO", **kw)
        marco = Frame(self.leftMargin, self.bottomMargin, self.width, self.height, id="normal")
        self.addPageTemplates([PageTemplate(id="portada", frames=marco),
                               PageTemplate(id="normal", frames=marco, onPage=self.pie)])
        self.nota_actual = ""

    def pie(self, canvas, doc):
        canvas.saveState()
        canvas.setFont("Sans", 7.5)
        canvas.setFillColor(GRIS)
        canvas.drawString(self.leftMargin, 0.9 * cm, f"TP EntrenadOS 2C2026 · {self.nota_actual}")
        canvas.drawRightString(A4[0] - self.rightMargin, 0.9 * cm, f"{doc.page}")
        canvas.setStrokeColor(colors.HexColor("#D5DCE3"))
        canvas.line(self.leftMargin, 1.25 * cm, A4[0] - self.rightMargin, 1.25 * cm)
        canvas.restoreState()

    def afterFlowable(self, f):
        nota = getattr(f, "_nota", None)
        if nota:
            self.nota_actual = nota
        toc = getattr(f, "_toc", None)
        if toc:
            clave = f"t{id(f)}"
            self.canv.bookmarkPage(clave)
            self.canv.addOutlineEntry(toc[1], clave, level=toc[0], closed=toc[0] > 0)
            self.notify("TOCEntry", (toc[0], toc[1], self.page, clave))


def leer_nota(ruta):
    texto = open(ruta, encoding="utf-8").read()
    meta = {}
    if texto.startswith("---\n"):
        fin = texto.index("\n---", 4)
        for linea in texto[4:fin].splitlines():
            if ":" in linea:
                k, v = linea.split(":", 1)
                meta[k.strip()] = v.strip()
        texto = texto[fin + 4:]
    return meta, texto.splitlines()


def main():
    historia = []
    hoy = datetime.date.today().strftime("%d/%m/%Y")

    # portada
    historia += [Spacer(1, 6 * cm),
                 Paragraph("TP EntrenadOS 2C2026", ParagraphStyle("t", fontName="Sans-B", fontSize=30, leading=36, alignment=TA_CENTER, textColor=AZUL)),
                 Spacer(1, 0.4 * cm),
                 Paragraph("Documentación del grupo RequiemSO", ParagraphStyle("st", fontName="Sans", fontSize=15, leading=20, alignment=TA_CENTER)),
                 Spacer(1, 0.3 * cm),
                 Paragraph("Exportación completa de la bóveda de Obsidian <i>doc-tp-entrenados</i>",
                           ParagraphStyle("st2", fontName="Sans", fontSize=10, leading=14, alignment=TA_CENTER, textColor=GRIS)),
                 Spacer(1, 5 * cm),
                 Paragraph(f"Sistemas Operativos · UTN FRBA · Generado el {hoy}",
                           ParagraphStyle("pie", fontName="Sans", fontSize=9, alignment=TA_CENTER, textColor=GRIS)),
                 PageBreak()]

    from reportlab.platypus.doctemplate import NextPageTemplate
    historia.insert(0, NextPageTemplate("normal"))

    toc = TableOfContents()
    toc.levelStyles = [
        ParagraphStyle("toc0", fontName="Sans-B", fontSize=10, leading=14, leftIndent=0, firstLineIndent=0, spaceBefore=4),
        ParagraphStyle("toc1", fontName="Sans", fontSize=8.5, leading=11, leftIndent=14, firstLineIndent=0, textColor=GRIS),
    ]
    historia += [Paragraph("Índice", E["h1"]), toc, PageBreak()]

    seccion_anterior = None
    for archivo, seccion in NOTAS:
        ruta = os.path.join(BOVEDA, archivo)
        meta, lineas = leer_nota(ruta)
        titulo = next((re.sub(r"^#\s+", "", l) for l in lineas if l.startswith("# ")), os.path.splitext(os.path.basename(archivo))[0])
        if lineas and any(l.startswith("# ") for l in lineas):
            primero = next(i for i, l in enumerate(lineas) if l.startswith("# "))
            lineas = lineas[:primero] + lineas[primero + 1:]

        marca = Paragraph(seccion.upper() if seccion != seccion_anterior else seccion.upper(), E["seccion"])
        marca._nota = titulo
        h1 = Paragraph(inline(titulo), E["h1"])
        h1._toc = (0, re.sub(r"<[^>]+>", "", inline(titulo)))
        h1._nota = titulo
        detalles = [f"{k}: {v}" for k, v in meta.items() if k in ("actualizado", "fecha", "rama", "commit", "resultado")]
        cabecera = [marca, h1]
        if detalles:
            cabecera.append(Paragraph(inline(" · ".join(detalles)), E["meta"]))
        historia.append(KeepTogether(cabecera))

        if archivo.startswith("Presentación"):
            # cada diapositiva va separada por una línea con ---
            diapositivas, actual = [], []
            for l in lineas:
                if l.strip() == "---":
                    diapositivas.append(actual)
                    actual = []
                else:
                    actual.append(l)
            diapositivas.append(actual)
            for n, d in enumerate(diapositivas, 1):
                historia.append(Paragraph(f"Diapositiva {n}", E["meta"]))
                historia += bloques(d, ANCHO)
                historia.append(Spacer(1, 8))
        else:
            historia += bloques(lineas, ANCHO, toc_nota=titulo)
        historia.append(PageBreak())
        seccion_anterior = seccion

    doc = Documento(SALIDA)
    doc.multiBuild(historia)
    print("PDF generado:", SALIDA)


if __name__ == "__main__":
    BOVEDA, SALIDA = sys.argv[1], sys.argv[2]
    main()
