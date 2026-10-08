"""Exercise the installed Gowin server through real MCP stdio, without hardware I/O."""
import asyncio
import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "tools/vendor/gowin_mcp_server/gowin_mcp_server.py"
GOWIN = "E:/Gowin/Gowin_V1.9.11.03_Education_x64/IDE/bin/gw_sh.exe"


async def main(build=False):
    env = dict(os.environ, GOWIN_PATH=GOWIN, PYTHONUTF8="1", FASTMCP_CHECK_FOR_UPDATES="off")
    params = StdioServerParameters(command=sys.executable, args=[str(SERVER)], env=env, cwd=str(ROOT))
    report = {"checked_at": datetime.now(timezone.utc).isoformat(), "gowin_path": GOWIN, "checks": {}}
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            init = await session.initialize()
            report["server"] = init.serverInfo.model_dump()
            listed = await session.list_tools()
            report["tools"] = [t.name for t in listed.tools]
            calls = [
                ("start_gowin", {}),
                ("get_process_status", {}),
                ("send_tcl_command", {"command": 'puts "CODEX_GOWIN_SMOKE_[expr {6*7}]"', "timeout": 10.0}),
            ]
            if build:
                script = (ROOT / "tools/smoke_design/build.tcl").as_posix()
                calls.append(("send_tcl_command", {"command": 'source {' + script + '}', "timeout": 300.0}))
            calls.append(("stop_gowin", {}))
            for index, (name, args) in enumerate(calls):
                result = await session.call_tool(name, args)
                output = "\n".join(getattr(c, "text", "") for c in result.content)
                key = "build" if build and index == 3 else name
                report["checks"][key] = {"is_error": result.isError, "output": output}
                print(name + ": " + output, flush=True)
    check = report["checks"]["send_tcl_command"]
    report["passed"] = not check["is_error"] and "CODEX_GOWIN_SMOKE_42" in check["output"] and "timeout" not in check["output"].lower()
    if build:
        bitstream = ROOT / "tmp/gowin_smoke/impl/pnr/mcp_smoke.fs"
        report["build_bitstream_exists"] = bitstream.is_file()
        report["passed"] = report["passed"] and bitstream.is_file() and "ERROR" not in report["checks"]["build"]["output"]
    out = ROOT / "docs/evidence/gowin-mcp-smoke.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if not report["passed"]:
        raise SystemExit("Gowin MCP smoke check failed; inspect docs/evidence/gowin-mcp-smoke.json")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--build", action="store_true")
    asyncio.run(main(parser.parse_args().build))
