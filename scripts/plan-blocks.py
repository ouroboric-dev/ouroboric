#!/usr/bin/env python3
# List or apply the code blocks of one task of a plan, so an executor copies the plan's code exactly.
#   plan-blocks.py WORKSPACE TASK              list the blocks: index, kind, target path
#   plan-blocks.py WORKSPACE TASK N [N ...]    apply those blocks to <root>/<repo>, in order:
#                                              a whole file is written to its path, a diff is applied
#                                              with `git apply` (it fails loudly if it doesn't fit)
# WORKSPACE is the plan's SDD workspace (see plan-lib.sh): it names the plan and the root that holds the
# component repos. TASK is an id such as v0-T039, and the repo comes from the task's
# "**Files (in `repo`):**" line. A file block goes to the last `path` named in backticks before it.
# Bash blocks are listed but never applied: run them yourself. Run it as `python3 -I`.
import os
import re
import subprocess
import sys

block = re.compile(r'^(`{3,4})(\w*)\n(.*?)\n\1$', re.M | re.S)


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
    m = re.search(r'^### Task ' + re.escape(tid) + r':.*?(?=^### Task |\Z)', text, re.M | re.S)
    if not m:
        sys.exit(f'no task {tid} in the plan')
    sec = m.group(0)
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
        elif lang == 'bash':
            target, kind = '-', 'bash'
        else:
            target, kind = re.findall(r'`([^`\s]+)`', before)[-1], 'file'
        blocks.append((kind, target, body))

    if len(argv) == 3:
        print(f'{tid} in {repo}:')
        for i, (kind, target, body) in enumerate(blocks):
            print(f'  {i}: {kind:4} {target} ({body.count(chr(10)) + 1} lines)')
        return

    if not repo:
        sys.exit(f'{tid} changes no component repo')
    dest = os.path.join(root, repo)
    for n in map(int, argv[3:]):
        kind, target, body = blocks[n]
        if kind == 'bash':
            sys.exit(f'block {n} is a bash block: run it yourself')
        if kind == 'diff':
            r = subprocess.run(['git', '-C', dest, 'apply', '-'], input=body + '\n', text=True, capture_output=True)
            if r.returncode:
                sys.exit(f'block {n} ({target}) did not apply: {r.stderr}')
        else:
            path = os.path.join(dest, target)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, 'w').write(body + '\n')
        print(f'applied block {n}: {kind} {target}')


main(sys.argv)
