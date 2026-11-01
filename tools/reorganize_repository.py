"""Reproducible, byte-audited chronological repository migration (2026-11-01).

Run --plan first, then --apply. Never pushes, changes refs, or deletes old builds.
The fixed baseline prevents accidental application to a different checkout.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import io
import json
import os
from pathlib import Path
import posixpath
import re
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "efd76ea14bab93521604819756410898eb0bc8af"
OLD_SOURCE = "output/handoff_milestone2_20261008/source"
AUDIT = ROOT / "archive/FPGA-20261101-v0.1"
REPORT = ROOT / "evidence/2026/11/FPGA-20261101-reorganization-v0.1"
ZONE = dt.timezone(dt.timedelta(hours=8))


def git(*args: str, binary: bool = False):
    out = subprocess.check_output(["git", "-c", "core.quotepath=false", "-c", "core.autocrlf=false", *args], cwd=ROOT)
    return out if binary else out.decode("utf-8").strip()


def sha(path: Path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write(path: Path, content: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")


def json_write(path: Path, value):
    write(path, json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def dated(path: str):
    m = re.search(r"(?<!\d)(2026\d{4})(?!\d)", path)
    if m:
        return m[1]
    timestamp = git("log", "--diff-filter=A", "--format=%aI", "--", path).splitlines()
    if timestamp:
        return dt.datetime.fromisoformat(timestamp[-1]).astimezone(ZONE).strftime("%Y%m%d")
    return "undated"


def date_dir(date: str):
    return date[:4] + "/" + date[4:6] if date != "undated" else "undated"


def refs():
    result = []
    for tag in git("tag").splitlines():
        commit = git("rev-parse", tag + "^{commit}")
        stamp = git("show", "-s", "--format=%cI", commit)
        date = dt.datetime.fromisoformat(stamp).astimezone(ZONE).strftime("%Y%m%d")
        result.append(dict(tag=tag, commit=commit, timestamp=stamp, date=date))
    result.sort(key=lambda r: (r["date"], r["timestamp"], r["tag"]))
    sequence = {}
    for row in result:
        sequence[row["date"]] = sequence.get(row["date"], 0) + 1
        row["directory"] = f"releases/{date_dir(row['date'])}/FPGA-{row['date']}-v0.{sequence[row['date']]}"
    return result


def migration_plan(tracked, untracked, versions):
    destinations = {v["tag"]: v["directory"] for v in versions}
    mapping = {}
    evidence_groups = {}
    for old in tracked + untracked:
        if old.startswith("docs/evidence/"):
            group = old.split("/")[2]
            if group not in evidence_groups:
                evidence_groups[group] = f"evidence/{date_dir(dated('docs/evidence/' + group))}/{group}"
    for old in tracked + untracked:
        new = old
        if old.startswith(OLD_SOURCE + "/"):
            new = "source/" + old[len(OLD_SOURCE) + 1:]
            if old not in tracked:
                new = "media/previews/undated/" + Path(old).name
        elif old.startswith(("rtl/", "sim/", "constraints/", "build/")):
            new = "experiments/2026/10/FPGA-20261027-hdmi-import-v0.1/source/" + old
        elif old.startswith("docs/evidence/"):
            group = old.split("/")[2]
            new = evidence_groups[group] + old[len("docs/evidence/" + group):]
        elif old.startswith("archive/PolyTouch-FPGA-Synth-20261027-v0.3/"):
            new = old.replace("archive/PolyTouch-FPGA-Synth-20261027-v0.3", "experiments/2026/10/FPGA-20261027-hid-review-v0.1", 1)
        elif old.startswith("releases/FPGA-20261030-v0.1/"):
            new = old.replace("releases/FPGA-20261030-v0.1", destinations["final-20261030"] + "/original-delivery", 1)
        elif old.startswith("releases/v1.0.0/"):
            new = old.replace("releases/v1.0.0", destinations["v1.0.0"] + "/target", 1)
        elif old.startswith("releases/v2.1.0/"):
            new = old.replace("releases/v2.1.0", destinations["v2.1.0"] + "/original-delivery", 1)
        elif old.startswith("docs/releases/"):
            new = old.replace("docs/releases/", "docs/history/release-notes/", 1)
        elif old.startswith("docs/logs/"):
            new = "docs/history/logs/" + date_dir(dated(old)) + "/" + old[len("docs/logs/"):]
        elif old.startswith("docs/minimum_design/"):
            new = old.replace("docs/minimum_design/", "docs/design/minimum_design/", 1)
        elif old.startswith("docs/research/"):
            new = old.replace("docs/research/", "docs/references/research/", 1)
        elif old.startswith("board_docs/"):
            new = old.replace("board_docs/", "docs/references/boards/", 1)
        elif old.startswith("output/pdf/"):
            new = old.replace("output/pdf/", "docs/exports/pdf/", 1)
        elif old.startswith("output/reports/"):
            new = "docs/history/reports/" + old[len("output/reports/"):]
        elif old.startswith("output/handoff_milestone2_20261008/reference/"):
            new = old.replace("output/handoff_milestone2_20261008/reference/", "docs/references/handoff-20261008/", 1)
        elif old.startswith("output/handoff_milestone2_20261008/artifacts/"):
            base = old[len("output/handoff_milestone2_20261008/artifacts/"):]
            if Path(old).suffix.lower() in (".wav", ".png"):
                new = "media/previews/" + ("20261008/" if old in tracked else "undated/") + base
            else:
                new = "evidence/2026/10/FPGA-20261008-handoff/artifacts/" + base
        elif old.startswith("output/handoff_milestone2_20261008/"):
            new = old.replace("output/handoff_milestone2_20261008/", "docs/history/handoff-20261008/", 1)
        elif old == "电子乐器项目规划.md":
            new = "docs/planning/电子乐器项目规划.md"
        elif old == "CLEANUP_REPORT.md":
            new = "docs/history/CLEANUP_REPORT-20261007.md"
        elif old.startswith("docs/") and "/" not in old[5:]:
            new = "docs/history/" + old[5:]
        mapping[old] = new
    if len(mapping.values()) != len(set(mapping.values())):
        raise RuntimeError("Destination collision")
    for old, new in mapping.items():
        if old != new and (ROOT / new).exists():
            raise RuntimeError("Destination already exists: " + new)
    return mapping, evidence_groups


def immutable(path):
    return path.startswith(("evidence/", "releases/", "experiments/", "archive/", "legacy/"))


def apply_replacements(data, replacements):
    variants = {}
    for old, new in replacements.items():
        variants[old] = new
        variants.setdefault(old.replace("/", "\\"), new.replace("/", "\\"))
        variants.setdefault(old.replace("/", "\\\\"), new.replace("/", "\\\\"))
    pattern = "|".join(re.escape(k) for k in sorted(variants, key=len, reverse=True))
    return re.sub(pattern, lambda m: variants[m[0]], data)


def apply(mapping, versions, evidence_groups, tracked):
    originals = []
    AUDIT.mkdir(parents=True, exist_ok=False)
    REPORT.mkdir(parents=True, exist_ok=False)
    for old, new in mapping.items():
        p = ROOT / old
        if not p.is_file():
            raise RuntimeError("Missing original: " + old)
        originals.append(dict(old=old, new=new, sha256=sha(p), size=p.stat().st_size, tracked=old in tracked))
    json_write(REPORT / "original-files.json", originals)
    json_write(REPORT / "versions.json", versions)
    json_write(REPORT / "path-map.json", mapping)
    with zipfile.ZipFile(AUDIT / "before-files.zip", "w", compression=zipfile.ZIP_DEFLATED, compresslevel=1) as backup:
        for row in originals:
            backup.write(ROOT / row["old"], row["old"])
    subprocess.run(["git", "bundle", "create", str(AUDIT / "before-history.bundle"), "--all"], cwd=ROOT, check=True)
    shutil.copyfile(ROOT / ".git/config", AUDIT / "git-config-before.txt")
    write(AUDIT / "HEAD-before.txt", git("rev-parse", "HEAD") + "\n")
    # Move one explicit file at a time; generated/ignored environments remain in place.
    for old, new in mapping.items():
        if old != new:
            dest = ROOT / new
            dest.parent.mkdir(parents=True, exist_ok=True)
            (ROOT / old).rename(dest)
    replacements = {
        OLD_SOURCE: "source",
        "docs/minimum_design": "docs/design/minimum_design",
        "board_docs": "docs/references/boards",
        "output/pdf": "docs/exports/pdf",
        "docs/releases": "docs/history/release-notes",
        "docs/research": "docs/references/research",
        "output/handoff_milestone2_20261008/reference": "docs/references/handoff-20261008",
        "output/handoff_milestone2_20261008": "docs/history/handoff-20261008",
        "电子乐器项目规划.md": "docs/planning/电子乐器项目规划.md",
    }
    replacements.update({old: new for old, new in mapping.items() if old != new and not old.startswith(('rtl/','sim/','build/','constraints/'))})
    replacements.update({"docs/evidence/" + old: new for old, new in evidence_groups.items()})
    for version in versions:
        if version["tag"] in ("v1.0.0", "v2.1.0"):
            replacements["releases/" + version["tag"]] = version["directory"] + ("/target" if version["tag"] == "v1.0.0" else "/original-delivery")
        if version["tag"] == "final-20261030":
            replacements["releases/FPGA-20261030-v0.1"] = version["directory"]
    # Replace paths in maintained scripts/docs only. Raw evidence and releases are immutable.
    edits = []
    for row in originals:
        new, old = row["new"], row["old"]
        path = ROOT / new
        if immutable(new) or path.suffix.lower() not in (".md", ".txt", ".py", ".ps1", ".tcl", ".json", ".code-workspace"):
            continue
        # Hand-off JSON files and old release receipts are original records.
        if new.startswith("docs/history/") and path.suffix.lower() in (".json", ".txt"):
            continue
        raw = path.read_bytes()
        try:
            text = raw.decode("utf-8-sig")
        except UnicodeDecodeError:
            continue
        updated = text
        links = []
        if path.suffix.lower() == ".md":
            # Resolve original relative Markdown links before changing prose paths.
            def link(match):
                label, target = match.group(1), match.group(2)
                if re.match(r"[a-zA-Z][\w+.-]*:", target) or target.startswith(("#", "/")):
                    return match.group(0)
                clean = target.strip("<>")
                base, sep, fragment = clean.partition("#")
                resolved = posixpath.normpath(posixpath.join(posixpath.dirname(old), base))
                mapped = mapping.get(resolved)
                if mapped:
                    relative = posixpath.relpath(mapped, posixpath.dirname(new) or ".")
                    result = "[" + label + "](" + relative + (sep + fragment if sep else "") + ")"
                else:
                    result = match.group(0)
                links.append(result)
                return "REORGANIZE_LINK_" + str(len(links) - 1) + "_END"
            updated = re.sub(r"\[([^\]]*)\]\(([^)]+)\)", link, updated)
        updated = apply_replacements(updated, replacements)
        for index, value in enumerate(links):
            updated = updated.replace("REORGANIZE_LINK_" + str(index) + "_END", value)
        # Path expressions split across Python Path / segments.
        updated = updated.replace(' / "output" / "handoff_milestone2_20261008" / "source"', ' / "source"')
        if new == "source/sim/run_simulation.ps1":
            updated = updated.replace("'..\\..\\..\\tmp'", "'..\\tmp'")
            updated = updated.replace("$sourceRoot '..\\..\\..'", "$sourceRoot '..'")
        if updated != text:
            # Preserve BOM and original newline convention for minimal code diffs.
            encoded = updated.encode("utf-8")
            if raw.startswith(b"\xef\xbb\xbf"):
                encoded = b"\xef\xbb\xbf" + encoded
            path.write_bytes(encoded)
            edits.append(new)
    json_write(REPORT / "path-edits.json", edits)
    # Preserve complete original source trees from each tagged commit, with git-archive.
    release_rows = []
    for version in versions:
        base = ROOT / version["directory"]
        snapshot = base / "source/original-tree"
        snapshot.mkdir(parents=True, exist_ok=True)
        tree = git("ls-tree", "-r", "--name-only", version["commit"], "--", OLD_SOURCE + "/").splitlines()
        packed = subprocess.check_output(["git", "-c", "core.autocrlf=false", "archive", "--format=zip", version["commit"], OLD_SOURCE], cwd=ROOT)
        with zipfile.ZipFile(io.BytesIO(packed)) as archive:
            for name in tree:
                target = snapshot / name[len(OLD_SOURCE) + 1:]
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(name))
        # Keep all existing byte-bound delivery files unchanged; new archive metadata is separate.
        meta = base / "catalog"
        write(meta / "README.md", f"# {version['date']} / {version['tag']}\n\n归档编号：{base.name}。原版本名：`{version['tag']}`。\n\n来源提交：`{version['commit']}`；提交时间：{version['timestamp']}（按北京时间归类）。\n\n`source/original-tree/` 为标签提交中原生产源码的逐字节快照，保持原目录内部结构。既有交付文件保留原字节；旧绝对路径通过仓库路径映射追溯。\n\n本次只验证保存完整性，不新增历史仿真、构建或硬件通过结论。\n")
        write(meta / "REPRODUCE.md", f"# 复现\n\n完整历史工程：`git worktree add --detach <单独目录> {version['commit']}`。\n\n按原版 README 与工具版本构建；旧生产入口为 `{OLD_SOURCE}`。本目录源码快照可用于阅读和比对，完整构建若依赖仓库工具或旧路径，使用独立历史工作树。\n\n`git archive --format=zip --output=<导出文件.zip> {version['commit']} {OLD_SOURCE}` 可重新导出原生产源码。\n\n目标位流仅收录已存在且来源可核对的文件；未附位流表示未收录，不代表该版本已经通过构建。\n")
        write(meta / "CHANGES.md", f"# 归档变更\n\n2026-11-01：按日期重新分类，原标签 `{version['tag']}` 保留，未重写历史。\n\n原提交说明：{git('show', '-s', '--format=%s', version['commit'])}\n")
        files = sorted(p for p in base.rglob("*") if p.is_file() and p != meta / "checksums.sha256")
        write(meta / "MANIFEST.md", "# 文件清单\n\n" + "\n".join("- `" + p.relative_to(base).as_posix() + "`" for p in files if p != meta / "MANIFEST.md") + "\n")
        files = sorted(p for p in base.rglob("*") if p.is_file() and p != meta / "checksums.sha256")
        write(meta / "checksums.sha256", "".join(sha(p) + "  " + p.relative_to(base).as_posix() + "\n" for p in files))
        release_rows.append(dict(**version, source_files=len(tree), files=len(files)))
    json_write(REPORT / "release-inventory.json", release_rows)
    branch_inventory = []
    for ref in git("for-each-ref", "--format=%(refname:short)", "refs/remotes/origin").splitlines():
        if ref == "origin":
            continue
        commit = git("rev-parse", ref)
        unique = git("rev-list", "--reverse", BASELINE + ".." + ref).splitlines()
        stamp = git("show", "-s", "--format=%cI", ref)
        row = dict(ref=ref, commit=commit, timestamp=stamp, unique_commits=unique)
        branch_inventory.append(row)
        if unique:
            date = dt.datetime.fromisoformat(stamp).astimezone(ZONE).strftime("%Y%m%d")
            slug = ref.split("/")[-1]
            base = ROOT / f"experiments/{date_dir(date)}/FPGA-{date}-{slug}-v0.1"
            write(base / "README.md", f"# {date} / {slug}\n\n来源 `{ref}`，提交 `{commit}`。相对最终基线有 {len(unique)} 个独有提交；属于历史分支候选，未按日期机械合入当前工程。\n\n完整版本可运行 `git worktree add --detach <独立目录> {commit}`。`source.zip` 保留该提交的源码快照（含原路径）。`changes.patch` 仅展示独有提交相对最终基线的共同祖先以来差异。\n")
            archive = subprocess.check_output(["git", "-c", "core.autocrlf=false", "archive", "--format=zip", commit, OLD_SOURCE], cwd=ROOT)
            (base / "source.zip").write_bytes(archive)
            ancestor = git("merge-base", BASELINE, commit)
            (base / "changes.patch").write_bytes(git("diff", "--binary", ancestor, commit, binary=True))
            json_write(base / "provenance.json", row)
            write(base / "checksums.sha256", "".join(sha(p) + "  " + p.name + "\n" for p in sorted(base.iterdir()) if p.is_file() and p.name != "checksums.sha256"))
    json_write(REPORT / "branch-inventory.json", branch_inventory)
    local = []
    for base in sorted((ROOT / "archive").iterdir(), key=lambda p: tuple(int(v) if v.isdigit() else v for v in re.split(r"(\d+)", p.name))):
        if base.is_dir() and base != AUDIT:
            local.append(dict(directory=base.relative_to(ROOT).as_posix(), manifest=(base / "MANIFEST.md").is_file(), checksums=(base / "checksums.sha256").is_file()))
    json_write(REPORT / "local-archives.json", local)
    write(ROOT / "docs/history/VERSIONS.md", "# 版本时间线\n\n日期按北京时间排列。同日 v0.N 为归档序号，原项目版本名和标签保留。\n\n| 日期 | 原版本名 | 日期归档 | 来源提交 |\n|---|---|---|---|\n" + "".join(f"| {v['date']} | {v['tag']} | [{Path(v['directory']).name}](../../{v['directory']}/catalog/README.md) | `{v['commit'][:12]}` |\n" for v in versions) + "\n未标记正式版本的变更保留在 Git 历史；独有分支候选见 experiments 及 [分支清单](../../evidence/2026/11/FPGA-20261101-reorganization-v0.1/branch-inventory.json)。本机过程归档见 [本机归档清单](../../evidence/2026/11/FPGA-20261101-reorganization-v0.1/local-archives.json)。\n")
    write(ROOT / "docs/history/PATHS.md", "# 路径迁移\n\n完整旧路径、新路径与迁移前 SHA256 见 [原始文件清单](../../evidence/2026/11/FPGA-20261101-reorganization-v0.1/original-files.json)，[路径映射](../../evidence/2026/11/FPGA-20261101-reorganization-v0.1/path-map.json)。\n\n证据、发布包、历史实验的原字节和原绝对路径保持不变，历史命令在原提交的独立工作树中执行。当前命令使用根目录 source。原路径下忽略的 Gowin 实现目录、构建收据和工具环境留在本机，不作为当前构建凭据复用。新构建必须在新路径生成新的收据；本次不烧录、不修改 FPGA。\n")
    write(ROOT / "docs/history/README-before-20261101.md", zipfile.ZipFile(AUDIT / "before-files.zip").read("README.md").decode("utf-8-sig"))
    # Byte preservation report accounts for every pre-existing tracked/untracked file.
    verified = []
    for row in originals:
        current = sha(ROOT / row["new"])
        verified.append(dict(old=row["old"], new=row["new"], original_sha256=row["sha256"], current_sha256=current, unchanged=current == row["sha256"]))
    json_write(REPORT / "preservation.json", verified)
    print(json.dumps(dict(moved=sum(a != b for a, b in mapping.items()), originals=len(originals), path_edits=len(edits), releases=len(versions), historical_branch_candidates=sum(bool(r['unique_commits']) for r in branch_inventory)), indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", action="store_true")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if git("rev-parse", "HEAD") != BASELINE:
        raise RuntimeError("Unexpected HEAD; inspect baseline first")
    if git("diff", "--name-only") or git("diff", "--cached", "--name-only"):
        raise RuntimeError("Tracked changes must be reviewed before migration")
    tracked = git("ls-files", "-z", binary=True).decode("utf-8").strip("\0").split("\0")
    # Only existing project content, never this newly introduced reproducible script.
    untracked = [p for p in git("ls-files", "--others", "--exclude-standard", "-z", binary=True).decode("utf-8").strip("\0").split("\0") if p and not p.startswith("tools/reorganize_")]
    versions = refs()
    mapping, groups = migration_plan(tracked, untracked, versions)
    if args.apply:
        apply(mapping, versions, groups, tracked)
    else:
        print(json.dumps(dict(baseline=BASELINE, tracked=len(tracked), untracked=len(untracked), moves=sum(k != v for k, v in mapping.items()), versions=versions, examples=list(mapping.items())[:16]), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
