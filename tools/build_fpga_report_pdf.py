"""Build the print PDF from the two verified Markdown reports (Pandoc/XeLaTeX)."""
from pathlib import Path
import json
import re

import pypandoc

ROOT = Path(__file__).resolve().parents[1]
NAME = "FPGA-硬件连接与软件调研-20261013-v0.1"
OUTPUT = ROOT / "output" / "pdf"
HARDWARE = ROOT / "docs" / "hardware" / "FPGA-硬件连接与演奏操作-20261013-v0.1.md"
RESEARCH = ROOT / "docs" / "research" / "FPGA-算法与开源参考-20261013-v0.1.md"


def cells(line):
    return [part.strip() for part in line.strip().strip("|").split("|")]


def printable_hardware(text):
    text = re.sub(r"^# .*$", "# 硬件连接与手动演奏", text, count=1, flags=re.M)
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if line.startswith("| 电脑键 |"):
            keys, notes, midi = cells(line)[1:], cells(lines[index + 2])[1:], cells(lines[index + 3])[1:]
            if not (len(keys) == len(notes) == len(midi) == 13):
                raise ValueError("Keyboard mapping table changed; review export")
            table = ["| 电脑键 | 音符 | MIDI 编号 |", "| --- | --- | --- |"]
            table += [f"| {key} | {note} | {number} |" for key, note, number in zip(keys, notes, midi)]
            lines[index:index + 4] = table
            break
    else:
        raise ValueError("Keyboard mapping table missing")
    text = "\n".join(lines)
    text = text.replace("[3714 原理图](../references/Tang_Primer_20K_Dock_3714_Schematics.pdf)", "3714 原理图（工作区原文件）")
    text = text.replace("[核心板引脚/电源图](../references/Tang_Primer_20K_SOM-3961_Schematic.pdf)", "核心板引脚/电源图（工作区原文件）")
    return text


def printable_research(text):
    text = re.sub(r"^# .*$", "# 算法调研与软件实施", text, count=1, flags=re.M)
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if line.startswith("| 来源 |"):
            end = index + 2
            sections = []
            while end < len(lines) and lines[end].startswith("|"):
                source, scope, adaptation = cells(lines[end])
                sections += ["### " + source, "", "内容、许可与依赖：" + scope, "", "本地化用途：" + adaptation, ""]
                end += 1
            if len(sections) // 6 != 7:
                raise ValueError("Reference table changed; review export")
            lines[index:end] = sections
            break
    else:
        raise ValueError("Reference table missing")
    return "\n".join(lines)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    src = OUTPUT / (NAME + ".md")
    pdf = OUTPUT / (NAME + ".pdf")
    layout = OUTPUT / (NAME + "-layout.tex")
    metadata = """---
title: "FPGA 电子乐器：硬件连接与软件调研"
subtitle: "电脑手动演奏、GPIO 琴键及外设接线、论文与开源参考"
date: "2026 年 10 月 13 日 · v0.1 · 依据源码 5186020"
lang: zh-CN
fontsize: 11pt
toc-title: "阅读导航"
colorlinks: true
linkcolor: blue
urlcolor: blue
---

"""
    text = metadata + printable_hardware(HARDWARE.read_text(encoding="utf-8"))
    text += "\n\n\\clearpage\n\n" + printable_research(RESEARCH.read_text(encoding="utf-8")) + "\n"
    for old in ("\u2011", "\u2013", "\u2014"):
        text = text.replace(old, "-")
    # The installed CJK font lacks the musical sharp glyph; ASCII # preserves
    # the same pitch notation and renders correctly on every exported page.
    text = text.replace("♯", "#")
    # Let URL/path typesetting break at separators without adding a hyphen.
    reference_path = "archive/FPGA-20261013-v0.2/evidence/references/"
    text = text.replace("`" + reference_path + "`", r"\path{" + reference_path + "}")
    src.write_text(text, encoding="utf-8")
    layout.write_text(r"""\usepackage{needspace}
\usepackage{fancyhdr}
\usepackage{etoolbox}
\setlength{\emergencystretch}{3em}
\setlength{\tabcolsep}{4pt}
\setlength{\headheight}{15pt}
\AtBeginEnvironment{longtable}{\small}
\apptocmd{\tableofcontents}{\clearpage}{}{}
\pretocmd{\section}{\Needspace{6\baselineskip}}{}{}
\pretocmd{\subsection}{\Needspace{5\baselineskip}}{}{}
\pretocmd{\subsubsection}{\Needspace{5\baselineskip}}{}{}
\pagestyle{fancy}
\fancyhf{}
\fancyhead[L]{\small FPGA 硬件连接与软件调研}
\fancyhead[R]{\small 2026-10-13}
\fancyfoot[C]{\thepage}
\renewcommand{\headrulewidth}{0.3pt}
""", encoding="utf-8")
    pypandoc.convert_file(str(src), "pdf", format="markdown+raw_tex", outputfile=str(pdf), extra_args=[
        "--pdf-engine=xelatex", "--standalone", "--toc", "--toc-depth=2",
        "--include-in-header=" + str(layout),
        "-V", "mainfont=Microsoft YaHei", "-V", "CJKmainfont=Microsoft YaHei",
        "-V", "monofont=Consolas", "-V", "CJKmonofont=Microsoft YaHei",
        "-V", "geometry:a4paper,margin=2.2cm",
    ])
    print(json.dumps({"pdf": str(pdf), "markdown": str(src), "layout": str(layout)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
