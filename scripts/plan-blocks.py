#!/usr/bin/env python3
# List or apply the code blocks of one task of a plan, so an executor copies the plan's code exactly.
#   plan-blocks.py WORKSPACE TASK              list the blocks: index, kind, target path
#   plan-blocks.py WORKSPACE TASK N [N ...]    apply those blocks to <root>/<repo>, in order:
#                                              a whole file is written to its path, a diff is applied
#                                              with `git apply` (it fails loudly if it doesn't fit)
# WORKSPACE is the plan's SDD workspace (see plan-lib.sh): it names the plan and the root that holds the
# component repos. TASK is an id such as v0-T039, and the repo comes from the task's
# "**Files (in `repo`):**" line. A file block goes to the last `path` named in backticks before it.
# Bash and output blocks are listed but never applied: run the commands yourself. Run it as `python3 -I`.
import os
import re
import subprocess
import sys

block = re.compile(r'^(`{3,4})(\w*)\n(.*?)\n\1$', re.M | re.S)


def task_starts(text):
    """Offsets of the lines "### Task ..." that are headings, not text inside a code fence."""
    starts, fence, pos = [], 0, 0
    for line in text.splitlines(keepends=True):
        s = line.rstrip('\n')
        ticks = len(s) - len(s.lstrip('`'))
        if fence:
            if ticks >= fence and s.strip('`') == '':
                fence = 0
        elif ticks >= 3:
            fence = ticks
        elif s.startswith('### Task '):
            starts.append(pos)
        pos += len(line)
    return starts


def load(workspace):
    ws = os.path.realpath(workspace)
    marker = os.path.join(ws, 'plan-path')
    if not os.path.isfile(marker):
        sys.exit(f'{ws} is not an SDD workspace: it has no plan-path file')
    root = os.path.dirname(os.path.dirname(os.path.dirname(ws)))
    named = open(marker).read().strip()
    plan = named if os.path.isabs(named) else os.path.join(root, named)
    if not os.path.isfile(plan):
        sys.exit(f'the plan {plan}, named by {marker}, does not exist')
    return root, plan


def main(argv):
    if len(argv) < 3:
        sys.exit('usage: plan-blocks.py WORKSPACE TASK [N ...]')
    root, plan = load(argv[1])
    tid = argv[2]
    text = open(plan).read()
    starts = task_starts(text) + [len(text)]
    sec = None
    for a, b in zip(starts, starts[1:]):
        if re.match(r'### Task ' + re.escape(tid) + ':', text[a:b]):
            sec = text[a:b]
            break
    if sec is None:
        sys.exit(f'no task {tid} in the plan')
    repo_m = re.search(r'\*\*Files \(in `([\w.-]+)`\):\*\*', sec)
    repo = repo_m.group(1) if repo_m else None
    blocks, pos = [], 0
    for b in block.finditer(sec):
        lang, body = b.group(2), b.group(3)
        before = sec[pos:b.start()]
        pos = b.end()
        if lang == 'diff':
            target = re.search(r'^\+\+\+ b/(\S+)', body, re.M).group(1)
            kind = 'diff'
        elif lang in ('bash', 'output'):
            target, kind = '-', lang
        else:
            target, kind = re.findall(r'`([^`\s]+)`', before)[-1], 'file'
        blocks.append((kind, target, body, bool(re.search(r'`\s*\(executable\):?\s*$', before))))

    if len(argv) == 3:
        print(f'{tid} in {repo}:')
        for i, (kind, target, body, _) in enumerate(blocks):
            print(f'  {i}: {kind:4} {target} ({body.count(chr(10)) + 1} lines)')
        return

    if not repo:
        sys.exit(f'{tid} changes no component repo')
    dest = os.path.join(root, repo)
    for n in map(int, argv[3:]):
        kind, target, body, exe = blocks[n]
        if kind in ('bash', 'output'):
            sys.exit(f'block {n} is a {kind} block: run it yourself')
        if kind == 'diff':
            r = subprocess.run(['git', '-C', dest, 'apply', '-'], input=body + '\n', text=True, capture_output=True)
            if r.returncode:
                sys.exit(f'block {n} ({target}) did not apply: {r.stderr}')
        else:
            path = os.path.join(dest, target)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, 'w').write(body + '\n')
            if exe:
                os.chmod(path, 0o755)
        print(f'applied block {n}: {kind} {target}')


main(sys.argv)
