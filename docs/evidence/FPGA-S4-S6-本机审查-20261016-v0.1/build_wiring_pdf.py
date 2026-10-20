"""Render the reviewed Markdown wiring plan through Pandoc + XeLaTeX."""
from pathlib import Path
import argparse
import pypandoc


def main():
    p=argparse.ArgumentParser()
    p.add_argument('markdown', type=Path)
    p.add_argument('pdf', type=Path)
    a=p.parse_args();a.pdf.parent.mkdir(parents=True,exist_ok=True)
    header=Path(__file__).with_name('wiring-layout.tex')
    header.write_text(r'''\usepackage{needspace}
\usepackage{fancyhdr}
\usepackage{etoolbox}
\usepackage{xcolor}
\definecolor{wireblue}{HTML}{244660}
\setlength{\emergencystretch}{3em}
\setlength{\tabcolsep}{4pt}
\renewcommand{\arraystretch}{1.08}
\AtBeginEnvironment{longtable}{\small}
\pretocmd{\section}{\Needspace{5\baselineskip}}{}{}
\pretocmd{\subsection}{\Needspace{4\baselineskip}}{}{}
\setlength{\headheight}{15pt}
\pagestyle{fancy}
\fancyhf{}
\fancyhead[L]{\small\color{wireblue} PolyTouch FPGA / 完整接线方案}
\fancyhead[R]{\small 2026-10-16 / v0.1}
\fancyfoot[C]{\small\thepage}
\renewcommand{\headrulewidth}{0.3pt}
''',encoding='utf-8')
    pypandoc.convert_file(str(a.markdown.resolve()),'pdf',format='markdown+raw_tex',
        outputfile=str(a.pdf.resolve()),extra_args=[
        '--pdf-engine=xelatex','--standalone','--include-in-header='+str(header.resolve()),
        '-V','mainfont=Microsoft YaHei','-V','CJKmainfont=Microsoft YaHei',
        '-V','monofont=Consolas','-V','CJKmonofont=Microsoft YaHei',
        '-V','geometry:a4paper,margin=1.8cm','-V','linestretch=1.05'])
    print(a.pdf.resolve())


if __name__=='__main__':main()
