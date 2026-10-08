#!/usr/bin/env python3
"""Local MCP server for PDF <-> Markdown conversion.

Design:
- PDF -> Markdown: MarkItDown first; if the text layer is empty or too short,
  fall back to Poppler pdftotext -layout, which handles fonts whose Unicode
  mapping defeats pdfminer/PyMuPDF.
- Markdown -> PDF: Pandoc + XeLaTeX, with CJK font and margin defaults.
- Page rendering: Poppler pdftoppm for visual QA when layout matters.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from fastmcp import FastMCP
from markitdown import MarkItDown
import pypandoc

mcp = FastMCP("Document Conversion (PDF <-> Markdown)")

SPACE_ROOT = Path(os.environ.get("DOCUMENT_WORKSPACE", r"E:\Working Space\FPGA"))
TMP_ROOT = SPACE_ROOT / "tmp" / "docconvert"
TESSDATA_DIR = Path(os.environ.get("DOCUMENT_TESSDATA", str(SPACE_ROOT / "tools" / "tessdata")))


def _ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def _find_poppler_tool(name: str) -> str | None:
    candidates = [
        Path(r"C:\Users\ROG\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\poppler\Library\bin") / f"{name}.exe",
        Path(r"E:\texlive\2024\bin\windows") / f"{name}.exe",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)
    found = shutil.which(name)
    return found


def _pdf_to_text_poppler(input_pdf: Path) -> str:
    pdftotext = _find_poppler_tool("pdftotext")
    if not pdftotext:
        raise RuntimeError("pdftotext not found; install Poppler or use the bundled runtime")
    with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as tmp:
        tmp_path = Path(tmp.name)
    try:
        subprocess.run(
            [pdftotext, "-layout", "-enc", "UTF-8", str(input_pdf), str(tmp_path)],
            check=True,
            capture_output=True,
            text=True,
            errors="replace",
        )
        return tmp_path.read_text(encoding="utf-8", errors="replace")
    finally:
        tmp_path.unlink(missing_ok=True)


def _text_to_markdown(text: str, source_name: str) -> str:
    pages = text.split("\f")
    lines = [
        f"# {source_name}",
        "",
        "> Extracted by the local docconvert Poppler fallback. "
        "Use page rendering for visual/layout-critical checks.",
        "",
    ]
    for index, page in enumerate(pages, start=1):
        body = page.strip("\n")
        if not body:
            continue
        lines.extend([f"## Page {index}", "", body, ""])
    return "\n".join(lines).rstrip() + "\n"


def _markitdown_text(input_path: Path) -> str:
    converter = MarkItDown(enable_plugins=False)
    result = converter.convert(str(input_path))
    return result.text_content or ""


def _find_tesseract() -> str | None:
    candidates = [
        Path(r"C:\Program Files\Tesseract-OCR\tesseract.exe"),
        Path(r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe"),
    ]
    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)
    return shutil.which("tesseract")


def _ocr_pdf_to_text(input_pdf: Path, lang: str = "chi_sim+eng", dpi: int = 250) -> str:
    tesseract = _find_tesseract()
    pdftoppm = _find_poppler_tool("pdftoppm")
    if not tesseract:
        raise RuntimeError("tesseract not found; install Tesseract OCR")
    if not pdftoppm:
        raise RuntimeError("pdftoppm not found; install Poppler")
    with tempfile.TemporaryDirectory(prefix="docconvert_ocr_") as tmp:
        tmp_dir = Path(tmp)
        subprocess.run(
            [pdftoppm, "-png", "-r", str(dpi), str(input_pdf), str(tmp_dir / "page")],
            check=True,
            capture_output=True,
            text=True,
            errors="replace",
        )
        pages: list[str] = []
        for image in sorted(tmp_dir.glob("page*.png")):
            command = [tesseract, str(image), "stdout", "-l", lang]
            if TESSDATA_DIR.is_dir():
                command.extend(["--tessdata-dir", str(TESSDATA_DIR)])
            result = subprocess.run(
                command,
                check=True,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            pages.append(result.stdout)
        return "\f".join(pages)


def pdf_to_md_impl(
    input_pdf: str,
    output_md: str | None = None,
    min_chars: int = 200,
    use_ocr: bool = True,
) -> str:
    """Convert a PDF to Markdown. Returns the output path when output_md is set."""
    source = Path(input_pdf).expanduser().resolve()
    if not source.is_file():
        raise FileNotFoundError(source)

    text = ""
    engine = "markitdown"
    try:
        text = _markitdown_text(source)
    except Exception as exc:  # noqa: BLE001 - report engine failure to caller
        text = ""
        engine = f"markitdown failed: {exc}"

    if len(text.strip()) < min_chars:
        fallback = _pdf_to_text_poppler(source)
        if len(fallback.strip()) > len(text.strip()):
            text = _text_to_markdown(fallback, source.stem)
            engine = "poppler-pdftotext-layout"

    if use_ocr and len(text.strip()) < min_chars:
        ocr_text = _ocr_pdf_to_text(source)
        if len(ocr_text.strip()) > len(text.strip()):
            text = _text_to_markdown(ocr_text, source.stem)
            engine = "tesseract-ocr"

    if not text.strip():
        text = (
            f"# {source.stem}\n\n"
            "> No text layer and OCR unavailable. Render the PDF pages to PNG "
            "and read them with a multimodal model, then write the Markdown manually.\n"
        )

    if output_md:
        target = Path(output_md).expanduser().resolve()
        _ensure_parent(target)
        target.write_text(text, encoding="utf-8")
        return str(target)

    default_target = TMP_ROOT / f"{source.stem}.md"
    _ensure_parent(default_target)
    default_target.write_text(text, encoding="utf-8")
    return str(default_target)


def md_to_pdf_impl(
    input_md: str,
    output_pdf: str,
    pdf_engine: str = "xelatex",
    cjk_font: str = "Microsoft YaHei",
    toc: bool = False,
    margin: str = "2.2cm",
) -> str:
    """Convert Markdown to PDF with Pandoc and a CJK-capable LaTeX engine."""
    source = Path(input_md).expanduser().resolve()
    if not source.is_file():
        raise FileNotFoundError(source)
    target = Path(output_pdf).expanduser().resolve()
    _ensure_parent(target)

    extra_args = [
        f"--pdf-engine={pdf_engine}",
        "--standalone",
        "-V",
        f"mainfont={cjk_font}",
        "-V",
        f"CJKmainfont={cjk_font}",
        "-V",
        "monofont=Consolas",
        "-V",
        f"geometry:a4paper,margin={margin}",
    ]
    if toc:
        extra_args.extend(["--toc", "--toc-depth=3"])

    pypandoc.convert_file(
        str(source),
        "pdf",
        format="markdown-raw_tex",
        outputfile=str(target),
        extra_args=extra_args,
    )
    return str(target)


def pdf_pages_to_png_impl(input_pdf: str, output_dir: str | None = None, dpi: int = 140) -> str:
    """Render PDF pages to PNG for visual/layout inspection."""
    source = Path(input_pdf).expanduser().resolve()
    if not source.is_file():
        raise FileNotFoundError(source)
    target_dir = Path(output_dir).expanduser().resolve() if output_dir else TMP_ROOT / f"{source.stem}_pages"
    target_dir.mkdir(parents=True, exist_ok=True)
    pdftoppm = _find_poppler_tool("pdftoppm")
    if not pdftoppm:
        raise RuntimeError("pdftoppm not found")
    subprocess.run(
        [pdftoppm, "-png", "-r", str(dpi), str(source), str(target_dir / "page")],
        check=True,
        capture_output=True,
        text=True,
        errors="replace",
    )
    return str(target_dir)


@mcp.tool()
def pdf_to_md(
    input_pdf: str,
    output_md: str | None = None,
    min_chars: int = 200,
    use_ocr: bool = True,
) -> str:
    """Convert a PDF to Markdown using MarkItDown with a Poppler fallback."""
    return pdf_to_md_impl(input_pdf, output_md, min_chars, use_ocr)


@mcp.tool()
def md_to_pdf(
    input_md: str,
    output_pdf: str,
    pdf_engine: str = "xelatex",
    cjk_font: str = "Microsoft YaHei",
    toc: bool = False,
    margin: str = "2.2cm",
) -> str:
    """Convert Markdown to PDF with Pandoc and XeLaTeX."""
    return md_to_pdf_impl(input_md, output_pdf, pdf_engine, cjk_font, toc, margin)


@mcp.tool()
def pdf_pages_to_png(input_pdf: str, output_dir: str | None = None, dpi: int = 140) -> str:
    """Render PDF pages to PNG for visual/layout inspection."""
    return pdf_pages_to_png_impl(input_pdf, output_dir, dpi)


if __name__ == "__main__":
    mcp.run(transport="stdio")
