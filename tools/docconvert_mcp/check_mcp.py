#!/usr/bin/env python3
"""Smoke-test the local docconvert MCP over real stdio."""

from __future__ import annotations

import asyncio
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parents[2]
SERVER = ROOT / "tools" / "docconvert_mcp" / "server.py"


async def main() -> None:
    env = dict(os.environ, PYTHONUTF8="1", DOCUMENT_WORKSPACE=str(ROOT))
    params = StdioServerParameters(command=sys.executable, args=[str(SERVER)], env=env, cwd=str(ROOT))
    report = {"checked_at": datetime.now(timezone.utc).isoformat(), "tools": [], "checks": {}}

    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            init = await session.initialize()
            report["server"] = init.serverInfo.model_dump()
            listed = await session.list_tools()
            report["tools"] = [tool.name for tool in listed.tools]

            with tempfile.TemporaryDirectory(prefix="docconvert_mcp_check_") as tmp:
                work = Path(tmp)
                source_md = work / "source.md"
                source_md.write_text(
                    "# 转换测试\n\n"
                    "这是一个中文段落，用于验证 Markdown 与 PDF 的双向转换。\n\n"
                    "| 项目 | 数值 |\n| --- | ---: |\n| 采样率 | 48 kHz |\n| 复音数 | 4 |\n",
                    encoding="utf-8",
                )
                source_pdf = work / "source.pdf"
                md_path = work / "sample_from_mcp.md"
                pdf_path = work / "sample_roundtrip.pdf"

                result = await session.call_tool(
                    "md_to_pdf",
                    {"input_md": str(source_md), "output_pdf": str(source_pdf), "pdf_engine": "xelatex"},
                )
                report["checks"]["md_to_pdf_seed"] = {
                    "is_error": result.isError,
                    "output": "\n".join(getattr(c, "text", "") for c in result.content),
                }

                result = await session.call_tool(
                    "pdf_to_md",
                    {"input_pdf": str(source_pdf), "output_md": str(md_path), "min_chars": 20, "use_ocr": True},
                )
                report["checks"]["pdf_to_md"] = {
                    "is_error": result.isError,
                    "output": "\n".join(getattr(c, "text", "") for c in result.content),
                }

                result = await session.call_tool(
                    "md_to_pdf",
                    {"input_md": str(md_path), "output_pdf": str(pdf_path), "pdf_engine": "xelatex"},
                )
                report["checks"]["md_to_pdf_roundtrip"] = {
                    "is_error": result.isError,
                    "output": "\n".join(getattr(c, "text", "") for c in result.content),
                }
                report["passed"] = (
                    source_pdf.is_file()
                    and source_pdf.stat().st_size > 1000
                    and md_path.is_file()
                    and md_path.stat().st_size > 50
                    and pdf_path.is_file()
                    and pdf_path.stat().st_size > 1000
                )

    evidence = ROOT / "docs" / "evidence" / "docconvert-mcp-smoke.json"
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    asyncio.run(main())
