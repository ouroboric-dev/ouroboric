#!/usr/bin/env python3
# Build a plan from template parts and the task commits of a reference workspace, so the plan's code is
# the code that was run.
#   plan-generate.py REFERENCE OUT PART...
# REFERENCE holds one git clone per repo and a tasks.map with a line "<repo> <commit> <task id>" for each
# task. The parts are concatenated, and these directives, each alone on a line, are expanded:
#   @@file <task id> <path> <lang>@@   the file as that task's commit leaves it, fenced as <lang>
#   @@diff <task id> <path>@@          that commit's change to the file, as a git patch
# It refuses a plan that leaves out any file a task commit changes (go.sum excepted), and writes
# nothing in that case. Run it as `python3 -I`.
import re
import subprocess
import sys


def main(argv):
    if len(argv) < 4:
        sys.exit('usage: plan-generate.py REFERENCE OUT PART...')
    ref, out, parts = argv[1], argv[2], argv[3:]
    tasks = {}
    for line in open(ref + '/tasks.map'):
        if line.strip():
            repo, sha, tid = line.split()[:3]
            tasks[tid] = (repo, sha)
    used = set()

    def git(repo, *args):
        return subprocess.run(['git', '-C', f'{ref}/{repo}', *args], capture_output=True, text=True, check=True).stdout

    def fence(lang, body):
        body = body.rstrip('\n')
        f = '````' if '```' in body else '```'  # a block that holds a fence gets a longer one
        if '````' in body:
            sys.exit('a code block holds a four-backtick fence')
        return f'{f}{lang}\n{body}\n{f}'

    def expand(m):
        kind, tid, path = m.group(1), m.group(2), m.group(3)
        if tid not in tasks:
            sys.exit(f'unknown task {tid}: it is not in {ref}/tasks.map')
        repo, sha = tasks[tid]
        used.add((tid, path))
        if kind == 'file':
            return fence(m.group(4) or '', git(repo, 'show', f'{sha}:{path}'))
        patch = git(repo, 'show', '--format=', sha, '--', path)
        if not patch.strip():
            sys.exit(f'{tid} does not change {path}')
        return fence('diff', patch)

    text = ''.join(open(p).read() for p in parts)
    text = re.sub(r'^@@(file|diff) (\S+-T\d+) (\S+)(?: (\S+))?@@$', expand, text, flags=re.M)
    left = re.search(r'^@@(file|diff) .*$', text, flags=re.M)
    if left:
        sys.exit('a directive was left unexpanded: ' + left.group(0))
    # Every file every task commit touches must appear in the plan.
    missing = []
    for tid, (repo, sha) in tasks.items():
        for path in git(repo, 'show', '--name-only', '--format=', sha).split():
            if (tid, path) not in used and not path.endswith('go.sum'):
                missing.append(f'{tid} {path}')
    if missing:
        sys.exit('files missing from the plan:\n  ' + '\n  '.join(missing))
    open(out, 'w').write(text)
    print(f'wrote {out}: {text.count(chr(10))} lines')


main(sys.argv)
