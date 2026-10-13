"""Render a saved Markdown report with the project's Pandoc/XeLaTeX layout."""
from pathlib import Path
import argparse
import json
import pypandoc


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("markdown", type=Path)
    parser.add_argument("pdf", type=Path)
    args = parser.parse_args()
    source = args.markdown.resolve()
    output = args.pdf.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    header = output.with_name(output.stem + "-layout.tex")
    header.write_text(r"""\usepackage{needspace}
\usepackage{fancyhdr}
\usepackage{etoolbox}
\setlength{\emergencystretch}{3em}
\setlength{\tabcolsep}{4pt}
\setlength{\headheight}{15pt}
\AtBeginEnvironment{longtable}{\small}
\apptocmd{\tableofcontents}{\clearpage}{}{}
\pretocmd{\section}{\Needspace{6\baselineskip}}{}{}
\pretocmd{\subsection}{\Needspace{5\baselineskip}}{}{}
\pagestyle{fancy}
\fancyhf{}
\fancyhead[L]{\small PolyTouch FPGA 竞赛差距与执行计划}
\fancyhead[R]{\small 2026-10-13}
\fancyfoot[C]{\thepage}
\renewcommand{\headrulewidth}{0.3pt}
""", encoding="utf-8")
    pypandoc.convert_file(str(source), "pdf", format="markdown+raw_tex", outputfile=str(output), extra_args=[
        "--pdf-engine=xelatex", "--standalone", "--toc", "--toc-depth=1",
        "--include-in-header=" + str(header),
        "-V", "mainfont=Microsoft YaHei", "-V", "CJKmainfont=Microsoft YaHei",
        "-V", "monofont=Consolas", "-V", "CJKmonofont=Microsoft YaHei",
        "-V", "geometry:a4paper,margin=2.2cm",
    ])
    print(json.dumps({"source": str(source), "pdf": str(output), "layout": str(header)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
