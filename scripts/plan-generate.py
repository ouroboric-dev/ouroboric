#!/usr/bin/env python3
# Build a plan from template parts and the task commits of a reference workspace, so the plan's code is
# the code that was run.
#   plan-generate.py REFERENCE OUT PART...
# REFERENCE holds one git clone per repo and a tasks.map with a line "<repo> <commit> <task id>" for each
# task, and may hold red.txt, the output of plan-red.sh. The parts are concatenated, and these
# directives, each alone on a line, are expanded:
#   @@file <task id> <path> <lang>@@   the file as that task's commit leaves it, fenced as <lang>
#   @@diff <task id> <path>@@          that commit's change to the file, as a git patch
#   @@files <task id>@@                the task's "**Files (in `repo`):**" list: what the commit creates and changes
#   @@size <task id>@@                 inline: "S (n)" or "M (n)", n being the commit's insertions (lock files excepted: go.sum and package-lock.json); an
#                                      L task (over 400) is refused, because it must be split
#   @@steps <task id>@@                the task's steps: the test files first, then the first failure red.txt
#                                      shows for them (a task whose tests pass at once says so), then the other files,
#                                      then the passing run and the commit
# A file the commit makes executable is written as "Write `path` (executable):", and plan-blocks.py and plan-replay.py
# set the mode. Test files are those that match $PLAN_TEST_FILES, as in plan-red.sh. It refuses a plan that leaves out
# any file a task commit changes (lock files excepted: go.sum and package-lock.json), and writes nothing in that case. Run it as
# `python3 -I`.
import os
import re
import subprocess
import sys

TEST_FILES = re.compile(os.environ.get('PLAN_TEST_FILES', r'_test\.go$|\.(test|spec)\.tsx?$|/[a-z]*test/|^testdata/'))
LANGS = {'.go': 'go', '.json': 'json', '.yaml': 'yaml', '.yml': 'yaml', '.sh': 'sh', '.md': 'md', '.toml': 'toml', '.mod': 'text',
         '.ts': 'ts', '.tsx': 'tsx', '.js': 'js', '.mjs': 'js', '.css': 'css', '.html': 'html', '.sql': 'sql'}


def is_lock(path):
    """A file the executor generates and a plan leaves out: go.sum, and npm's package-lock.json."""
    return os.path.basename(path) in ('go.sum', 'package-lock.json')


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

    def red(tid):
        """The first lines red.txt shows for the task, without its header: '' when its tests passed
        before the code (it printed nothing), None when red.txt has no entry for the task."""
        try:
            text = open(ref + '/red.txt').read()
        except FileNotFoundError:
            return None
        for block in re.split(r'^== ', text, flags=re.M)[1:]:
            head, _, body = block.partition('\n')
            if head.split()[0] == tid:
                return body.strip('\n')
        return None

    def changes(tid):
        repo, sha = tasks[tid]
        out = []
        for line in git(repo, 'show', '--no-renames', '--name-status', '--format=', sha).splitlines():
            status, path = line.split('\t', 1)
            if status == 'D':
                sys.exit(f'{tid} deletes {path}: a plan can\'t show a deletion yet')
            if not is_lock(path):
                out.append((status, path))
        return out

    def block_for(tid, status, path):
        repo, sha = tasks[tid]
        used.add((tid, path))
        if status == 'A':
            lang = LANGS.get(os.path.splitext(path)[1], 'text')
            exe = git(repo, 'ls-tree', sha, '--', path).startswith('100755')
            return f'Write `{path}`' + (' (executable)' if exe else '') + ':\n\n' + fence(lang, git(repo, 'show', f'{sha}:{path}'))
        return f'Apply to `{path}`:\n\n' + fence('diff', git(repo, 'show', '--format=', sha, '--', path))

    def expand_more(m):
        kind, tid = m.group(1), m.group(2)
        if tid not in tasks:
            sys.exit(f'unknown task {tid}: it is not in {ref}/tasks.map')
        repo, sha = tasks[tid]
        ch = changes(tid)
        if kind == 'files':
            made = ', '.join(f'`{p}`' for s, p in ch if s == 'A')
            edited = ', '.join(f'`{p}`' for s, p in ch if s == 'M')
            lines = [f'**Files (in `{repo}`):**', '']
            if made:
                lines.append(f'- Create: {made}')
            if edited:
                lines.append(f'- Modify: {edited}')
            return '\n'.join(lines)
        if kind == 'size':
            n = 0
            for line in git(repo, 'show', '--numstat', '--format=', sha).splitlines():
                add, _, path = line.split('\t')
                if not is_lock(path) and add != '-':
                    n += int(add)
            if n >= 400 + 1:
                sys.exit(f'{tid} adds {n} lines: that is an L task, and it must be split')
            return f'{"S" if n < 100 else "M"} ({n})'
        tests = [(s, p) for s, p in ch if TEST_FILES.search(p)]
        code = [(s, p) for s, p in ch if not TEST_FILES.search(p)]
        out, n = [], 0

        def step(text):
            nonlocal n
            n += 1
            return f'- [ ] **Step {n}:** {text}'
        if tests:
            out.append(step('write the tests.') + '\n\n' + '\n\n'.join(block_for(tid, s, p) for s, p in tests))
            first = red(tid)
            if first == '':
                out.append(step('run the named test. It passes at once, because the code or data it needs is already there '
                                '(or the test is skipped without its build tag): expect `ok`.'))
            else:
                out.append(step('run the named test. Expect it to fail' + (', first like this:' if first else '.')) +
                           (('\n\n' + fence('output', first)) if first else ''))
        if code:
            out.append(step('write the code.') + '\n\n' + '\n\n'.join(block_for(tid, s, p) for s, p in code))
        out.append(step('run the named test. Expect `ok`.'))
        out.append(step('commit (see "How each task lands").'))
        return '\n\n'.join(out)

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
    text = re.sub(r'^@@(files|steps) (\S+-T\d+)@@$', expand_more, text, flags=re.M)
    text = re.sub(r'@@(size) (\S+-T\d+)@@', expand_more, text)  # inline: "**Size:** @@size v0-T001@@"
    text = re.sub(r'^@@(file|diff) (\S+-T\d+) (\S+)(?: (\S+))?@@$', expand, text, flags=re.M)
    left = re.search(r'^@@(file|diff) .*$', text, flags=re.M)
    if left:
        sys.exit('a directive was left unexpanded: ' + left.group(0))
    # Every file every task commit touches must appear in the plan.
    missing = []
    for tid, (repo, sha) in tasks.items():
        for path in git(repo, 'show', '--name-only', '--format=', sha).split():
            if (tid, path) not in used and not is_lock(path):
                missing.append(f'{tid} {path}')
    if missing:
        sys.exit('files missing from the plan:\n  ' + '\n  '.join(missing))
    open(out, 'w').write(text)
    print(f'wrote {out}: {text.count(chr(10))} lines')


main(sys.argv)
