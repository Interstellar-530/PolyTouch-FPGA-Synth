---
name: "pdf-md"
description: "Markdown-first PDF workflow for this FPGA project: convert PDF to Markdown before reading, and write Markdown before exporting to PDF. Use for any PDF reading, PDF creation, technical documentation, or layout-checking task where the local docconvert pipeline is available."
---

# PDF-Markdown Workflow

Use this skill whenever a PDF is part of the task. The default intermediate representation is Markdown.

## Reading PDFs

1. Convert the PDF to Markdown first:

```powershell
& 'E:\Working Space\FPGA\tools\.venv-docconvert\Scripts\python.exe' `
  'E:\Working Space\FPGA\tools\docconvert_mcp\convert.py' `
  pdf-to-md '<input.pdf>' '<output.md>'
```

2. The pipeline tries MarkItDown first, then Poppler `pdftotext -layout`, then Tesseract OCR for image-only PDFs. Tesseract uses the project-local `chi_sim+eng` language data.
3. Read the Markdown for content and structure. For schematics, forms, charts, exact pin tables, or scanned pages, render pages to PNG and verify the OCR output visually:

```powershell
& 'E:\Working Space\FPGA\tools\.venv-docconvert\Scripts\python.exe' `
  'E:\Working Space\FPGA\tools\docconvert_mcp\convert.py' `
  pdf-to-png '<input.pdf>' '<output_dir>'
```

4. Never trust OCR alone for exact numeric values, pin names, component values, or table cells.

## Creating PDFs

1. Write or edit the source Markdown first. Include a title, headings, tables, code blocks, and any citations in the Markdown.
2. Convert Markdown to PDF with Pandoc and XeLaTeX:

```powershell
& 'E:\Working Space\FPGA\tools\.venv-docconvert\Scripts\python.exe' `
  'E:\Working Space\FPGA\tools\docconvert_mcp\convert.py' `
  md-to-pdf '<input.md>' '<output.pdf>' --toc
```

3. The converter uses `Microsoft YaHei` for CJK text and a 2.2 cm margin. Re-render the output PDF to PNG and inspect the layout before delivery.

## MCP Equivalents

When available, the local `docconvert` MCP exposes:

- `docconvert.pdf_to_md`
- `docconvert.md_to_pdf`
- `docconvert.pdf_pages_to_png`

If the MCP tools are not visible in the current session, use the CLI commands above. They call the same implementation.

## Project Paths

- Conversion environment: `E:\Working Space\FPGA\tools\.venv-docconvert`
- Conversion script: `E:\Working Space\FPGA\tools\docconvert_mcp\convert.py`
- MCP server: `E:\Working Space\FPGA\tools\docconvert_mcp\server.py`
- Tesseract language data: `E:\Working Space\FPGA\tools\tessdata`
- MCP smoke evidence: `E:\Working Space\FPGA\evidence\2026\10\docconvert-mcp-smoke.json`
