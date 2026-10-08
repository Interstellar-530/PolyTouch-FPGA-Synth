#!/usr/bin/env python3
"""CLI wrapper for the local PDF <-> Markdown conversion pipeline."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from server import md_to_pdf_impl, pdf_pages_to_png_impl, pdf_to_md_impl


def main() -> int:
    parser = argparse.ArgumentParser(description="PDF <-> Markdown conversion")
    sub = parser.add_subparsers(dest="command", required=True)

    p2m = sub.add_parser("pdf-to-md", help="Convert PDF to Markdown")
    p2m.add_argument("input_pdf")
    p2m.add_argument("output_md", nargs="?")

    m2p = sub.add_parser("md-to-pdf", help="Convert Markdown to PDF")
    m2p.add_argument("input_md")
    m2p.add_argument("output_pdf")
    m2p.add_argument("--toc", action="store_true")
    m2p.add_argument("--engine", default="xelatex")
    m2p.add_argument("--cjk-font", default="Microsoft YaHei")

    png = sub.add_parser("pdf-to-png", help="Render PDF pages to PNG")
    png.add_argument("input_pdf")
    png.add_argument("output_dir", nargs="?")
    png.add_argument("--dpi", type=int, default=140)

    args = parser.parse_args()
    if args.command == "pdf-to-md":
        result = pdf_to_md_impl(args.input_pdf, args.output_md)
    elif args.command == "md-to-pdf":
        result = md_to_pdf_impl(
            args.input_md,
            args.output_pdf,
            pdf_engine=args.engine,
            cjk_font=args.cjk_font,
            toc=args.toc,
        )
    else:
        result = pdf_pages_to_png_impl(args.input_pdf, args.output_dir, args.dpi)
    print(Path(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
