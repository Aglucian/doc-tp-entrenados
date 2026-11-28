"""Exporta una sola nota de la bóveda a un PDF A4 vertical.

Uso, desde la raíz de la bóveda:
    python3 herramientas/nota_pdf.py . "Deploy manual - Guía de laboratorio.md" "TP EntrenadOS - Deploy manual.pdf"

Reutiliza el renderer de Markdown de exportar_pdf.py (mismos estilos, tablas, callouts y código).
"""
import datetime
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import exportar_pdf as ep  # noqa: E402

from reportlab.lib.pagesizes import A4  # noqa: E402
from reportlab.lib.units import cm  # noqa: E402
from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate, Paragraph  # noqa: E402
from reportlab.lib.styles import ParagraphStyle  # noqa: E402

# Un poco más compacto que el PDF completo: la guía se imprime y conviene que entre en pocas hojas
ep.E["p"] = ParagraphStyle("p", fontName="Sans", fontSize=9, leading=11.8, spaceAfter=3)
ep.E["h2"] = ParagraphStyle("h2", fontName="Sans-B", fontSize=13, leading=16, textColor=ep.AZUL, spaceBefore=7, spaceAfter=3)


class Nota(BaseDocTemplate):
    def __init__(self, ruta, titulo):
        super().__init__(ruta, pagesize=A4, leftMargin=1.8 * cm, rightMargin=1.8 * cm, topMargin=1.6 * cm,
                         bottomMargin=1.6 * cm, title=titulo, author="RequiemSO")
        self.titulo = titulo
        marco = Frame(self.leftMargin, self.bottomMargin, self.width, self.height, id="f")
        self.addPageTemplates([PageTemplate(id="p", frames=marco, onPage=self.pie)])

    def pie(self, canvas, doc):
        canvas.saveState()
        canvas.setFont("Sans", 7.5)
        canvas.setFillColor(ep.GRIS)
        hoy = datetime.date.today().strftime("%d/%m/%Y")
        canvas.drawString(self.leftMargin, 0.9 * cm, f"TP EntrenadOS 2C2026 · RequiemSO · {self.titulo} · {hoy}")
        canvas.drawRightString(A4[0] - self.rightMargin, 0.9 * cm, f"{doc.page}")
        canvas.restoreState()


def main(boveda, nota, salida):
    _, lineas = ep.leer_nota(os.path.join(boveda, nota))
    titulo = next((re.sub(r"^#\s+", "", l) for l in lineas if l.startswith("# ")), os.path.splitext(nota)[0])
    lineas = [l for l in lineas if not l.startswith("# ")]
    # La línea de navegación de Obsidian ("Volver a [[00 - Inicio]] · ...") no sirve en papel
    lineas = [l for l in lineas if not l.startswith("Volver a [[")]
    historia = [Paragraph(ep.inline(titulo), ep.E["h1"])] + ep.bloques(lineas, ep.ANCHO)
    Nota(salida, titulo).build(historia)
    print("PDF generado:", salida)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
