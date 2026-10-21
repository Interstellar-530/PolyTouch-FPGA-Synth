"""Record remote-only commits and compare the old review with the current tree.

Run after git fetch origin --tags. This script never changes Git refs or sources.
"""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = next(p for p in Path(__file__).resolve().parents if (p / '.git').exists())
OUT = Path(__file__).resolve().parents[1]
SOURCE = 'output/handoff_milestone2_20261008/source/'


def git(*args):
    return subprocess.check_output(
        ['git', '-c', 'core.quotepath=false', *args], cwd=ROOT
    ).decode('utf-8').strip()


def blob(ref, path):
    result = subprocess.run(['git', 'rev-parse', f'{ref}:{path}'], cwd=ROOT,
                            capture_output=True)
    return result.stdout.decode().strip() if result.returncode == 0 else None


def main():
    baseline = git('rev-parse', 'HEAD')
    remotes = []
    for row in git('for-each-ref', '--format=%(refname:short)|%(objectname)|%(committerdate:iso8601)|%(subject)',
                   'refs/remotes/origin').splitlines():
        name, sha, date, subject = row.split('|', 3)
        if name in ('origin', 'origin/HEAD'):
            continue
        local_only, remote_only = map(int, git('rev-list', '--left-right', '--count',
                                               f'HEAD...{name}').split())
        remotes.append(dict(ref=name, sha=sha, date=date, subject=subject,
                            local_only=local_only, remote_only=remote_only))
    commits = []
    for sha in git('rev-list', '--remotes=origin', '--not', 'HEAD').splitlines():
        details = git('show', '-s', '--format=%H|%cI|%s', sha).split('|', 2)
        paths = git('diff-tree', '--no-commit-id', '--name-only', '-r', sha).splitlines()
        commits.append(dict(sha=details[0], committed=details[1], subject=details[2],
                            changed_paths=paths))
    review = []
    for path in git('diff-tree', '--no-commit-id', '--name-only', '-r', '908f9f5').splitlines():
        if not path.startswith(SOURCE):
            continue
        old, now = blob('origin/codex/s4-s6-review', path), blob('HEAD', path)
        review.append(dict(path=path, review_blob=old, local_blob=now,
                           status='absent' if now is None else 'identical' if old == now else 'later_changes'))
    hashes = {}
    for path in (ROOT / SOURCE).rglob('*'):
        if path.is_file() and path.suffix in ('.v', '.vh', '.hex') and 'build' not in path.relative_to(ROOT / SOURCE).parts:
            hashes[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    result = dict(baseline=baseline, remote_main_identical=(baseline == git('rev-parse', 'origin/main')),
                  remote_main_diff=git('diff', '--stat', 'HEAD', 'origin/main'),
                  branches=remotes, commits_outside_local_history=commits,
                  old_review_source_comparison=review, current_source_sha256=hashes)
    (OUT / 'git_audit.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(dict(main_identical=result['remote_main_identical'],
                          unique_remote_commits=len(commits),
                          review_identical=sum(x['status'] == 'identical' for x in review),
                          review_later_changes=sum(x['status'] == 'later_changes' for x in review)), indent=2))


if __name__ == '__main__':
    main()
