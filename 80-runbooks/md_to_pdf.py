#!/usr/bin/env python3
"""
md_to_pdf.py — render simple Markdown (headings, paragraphs, bullet and numbered
lists, pipe tables, fenced code, bold/italic/inline code, links, blockquotes)
to a clean letter-size PDF with ReportLab.

Usage: python3 md_to_pdf.py input.md output.pdf [--footer "text"]
Several inputs: python3 md_to_pdf.py a.md b.md c.md output.pdf   (page break between files)
"""
import re
import sys
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import (KeepTogether, PageBreak, Paragraph, Preformatted,
                                SimpleDocTemplate, Spacer, Table, TableStyle)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.fonts import addMapping
_F = "/usr/share/fonts/truetype/dejavu/"
pdfmetrics.registerFont(TTFont("DV", _F + "DejaVuSans.ttf"))
pdfmetrics.registerFont(TTFont("DV-Bold", _F + "DejaVuSans-Bold.ttf"))
pdfmetrics.registerFont(TTFont("DV-Oblique", _F + "DejaVuSans-Oblique.ttf"))
pdfmetrics.registerFont(TTFont("DV-BoldOblique", _F + "DejaVuSans-BoldOblique.ttf"))
pdfmetrics.registerFont(TTFont("DVMono", _F + "DejaVuSansMono.ttf"))
addMapping("DV", 0, 0, "DV"); addMapping("DV", 1, 0, "DV-Bold"); addMapping("DV", 0, 1, "DV-Oblique"); addMapping("DV", 1, 1, "DV-BoldOblique")

INK, MUTED, ACCENT = colors.HexColor("#1d1d1f"), colors.HexColor("#6e6e73"), colors.HexColor("#0b5cad")
RULE, HEAD_BG, CODE_BG = colors.HexColor("#d2d2d7"), colors.HexColor("#f2f4f7"), colors.HexColor("#f6f6f8")

S = {
    "h1": ParagraphStyle("h1", fontName="DV-Bold", fontSize=19, leading=23, textColor=INK, spaceBefore=4, spaceAfter=8),
    "h2": ParagraphStyle("h2", fontName="DV-Bold", fontSize=13.5, leading=17, textColor=ACCENT, spaceBefore=14, spaceAfter=6),
    "h3": ParagraphStyle("h3", fontName="DV-Bold", fontSize=10.8, leading=14, textColor=INK, spaceBefore=9, spaceAfter=3),
    "h4": ParagraphStyle("h4", fontName="DV-BoldOblique", fontSize=9.8, leading=13, textColor=INK, spaceBefore=6, spaceAfter=2),
    "p": ParagraphStyle("p", fontName="DV", fontSize=8.8, leading=12.4, textColor=INK, spaceAfter=5),
    "quote": ParagraphStyle("quote", fontName="DV-Oblique", fontSize=9.1, leading=12.4, textColor=MUTED, leftIndent=12, spaceAfter=4),
    "cell": ParagraphStyle("cell", fontName="DV", fontSize=7.6, leading=10.2, textColor=INK),
    "cellh": ParagraphStyle("cellh", fontName="DV-Bold", fontSize=7.6, leading=10.2, textColor=INK),
    "code": ParagraphStyle("code", fontName="DVMono", fontSize=6.6, leading=8.4, textColor=INK, backColor=CODE_BG,
                           borderPadding=5, leftIndent=4, spaceBefore=3, spaceAfter=8),
}
for lvl in range(4):
    S[f"li{lvl}"] = ParagraphStyle(f"li{lvl}", parent=S["p"], leftIndent=14 + 14 * lvl, bulletIndent=3 + 14 * lvl, spaceAfter=2)

INLINE_CODE = re.compile(r"`([^`]+)`")
BOLD = re.compile(r"\*\*(.+?)\*\*")
ITAL = re.compile(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])")
LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def inline(text):
    """Markdown inline → ReportLab mini-markup."""
    codes = []

    def stash(m):
        codes.append(m.group(1))
        return f"\x00{len(codes) - 1}\x00"

    text = INLINE_CODE.sub(stash, text)
    text = escape(text)
    text = LINK.sub(lambda m: f'<link href="{m.group(2)}"><u>{m.group(1)}</u></link>', text)
    text = BOLD.sub(r"<b>\1</b>", text)
    text = ITAL.sub(r"<i>\1</i>", text)
    text = text.replace("&lt;br&gt;", "<br/>")
    for i, c in enumerate(codes):
        text = text.replace(f"\x00{i}\x00", f'<font face="DVMono" size="7.6">{escape(c)}</font>')
    return text


def table_flowable(rows, width):
    ncol = max(len(r) for r in rows)
    rows = [r + [""] * (ncol - len(r)) for r in rows]
    # Weight columns by their longest cell, bounded so no column gets tiny.
    lens = [max(len(r[i]) for r in rows) for i in range(ncol)]
    lens = [min(max(l, 12), 60) for l in lens]
    total = sum(lens)
    widths = [width * l / total for l in lens]
    data = [[Paragraph(inline(c), S["cellh"]) for c in rows[0]]]
    data += [[Paragraph(inline(c), S["cell"]) for c in r] for r in rows[1:]]
    t = Table(data, colWidths=widths, repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), HEAD_BG),
        ("LINEBELOW", (0, 0), (-1, 0), 0.8, ACCENT),
        ("LINEBELOW", (0, 1), (-1, -1), 0.4, RULE),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 3.5), ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5),
        ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4),
    ]))
    return [t, Spacer(1, 7)]


def render(md, width):
    out, lines, i = [], md.splitlines(), 0
    para = []

    def flush():
        nonlocal para
        if para:
            out.append(Paragraph(inline(" ".join(para)), S["p"]))
            para = []

    while i < len(lines):
        ln = lines[i]
        st = ln.strip()
        if st.startswith("```"):
            flush()
            block, i = [], i + 1
            while i < len(lines) and not lines[i].strip().startswith("```"):
                block.append(lines[i]); i += 1
            wrapped = []
            for bl in block:
                while len(bl) > 118:
                    wrapped.append(bl[:118] + " \u21a9"); bl = "   " + bl[118:]
                wrapped.append(bl)
            out.append(Preformatted("\n".join(wrapped), S["code"]))
            i += 1
            continue
        if not st:
            flush(); i += 1; continue
        if st == "---":
            flush(); out.append(Spacer(1, 4)); i += 1; continue
        m = re.match(r"^(#{1,4})\s+(.*)$", st)
        if m:
            flush()
            lvl = len(m.group(1))
            out.append(Paragraph(inline(m.group(2)), S[f"h{lvl}"]))
            i += 1; continue
        if st.startswith("|"):
            flush()
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                if not all(re.fullmatch(r":?-{2,}:?", c) for c in cells if c):
                    rows.append(cells)
                i += 1
            if rows:
                out.extend(table_flowable(rows, width))
            continue
        if st.startswith(">"):
            flush()
            q = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                q.append(lines[i].strip()[1:].strip()); i += 1
            out.append(Paragraph(inline("<br>".join(q)), S["quote"]))
            continue
        m = re.match(r"^(\s*)([-*]|\d+[.)])\s+(.*)$", ln)
        if m:
            flush()
            lvl = min(len(m.group(1)) // 2, 3)
            marker = m.group(2)
            text = m.group(3)
            if text.startswith("[ ]"):
                text = "[  ] " + text[3:].strip()
            bullet = "•" if marker in "-*" else marker
            out.append(Paragraph(inline(text), S[f"li{lvl}"], bulletText=bullet))
            i += 1; continue
        para.append(st); i += 1
    flush()
    return out


def build(inputs, output, footer_text=""):
    doc = SimpleDocTemplate(output, pagesize=letter, leftMargin=0.75 * inch, rightMargin=0.75 * inch,
                            topMargin=0.7 * inch, bottomMargin=0.85 * inch)
    width = letter[0] - 1.5 * inch
    story = []
    for n, path in enumerate(inputs):
        with open(path, encoding="utf-8") as fh:
            md = fh.read()
        if n:
            story.append(PageBreak())
        story.extend(render(md, width))

    def footer(canvas, d):
        canvas.saveState()
        canvas.setFont("DV", 7.5); canvas.setFillColor(MUTED)
        canvas.drawString(0.75 * inch, 0.5 * inch, footer_text)
        canvas.drawRightString(letter[0] - 0.75 * inch, 0.5 * inch, f"Page {d.page}")
        canvas.setStrokeColor(RULE); canvas.line(0.75 * inch, 0.65 * inch, letter[0] - 0.75 * inch, 0.65 * inch)
        canvas.restoreState()

    doc.build(story, onFirstPage=footer, onLaterPages=footer)


if __name__ == "__main__":
    args = sys.argv[1:]
    footer_text = ""
    if "--footer" in args:
        k = args.index("--footer"); footer_text = args[k + 1]; del args[k:k + 2]
    if len(args) < 2:
        print(__doc__); sys.exit(1)
    build(args[:-1], args[-1], footer_text)
    print("wrote", args[-1])
