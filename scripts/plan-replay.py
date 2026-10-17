#!/usr/bin/env python3
# Check that a plan reproduces its code: apply its code blocks, task by task, to fresh clones, as an
# executor would. Prints each task's result.
#   plan-replay.py PLAN WORKDIR
# WORKDIR holds a clone of each repo, in a folder of its repo's name. A task's repo comes from its
# "**Files (in `repo`):**" line; a task whose repo has no folder in WORKDIR is skipped. A file block is
# written to the last `path` named in backticks before it, a diff block is applied with `git apply`,
# and bash and output blocks (commands, and what a failing test prints) are left alone. Run it as
# `python3 -I`.
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


def main(argv):
    if len(argv) != 3:
        sys.exit('usage: plan-replay.py PLAN WORKDIR')
    plan, work = argv[1], argv[2]
    text = open(plan).read()
    starts = task_starts(text)
    for i, a in enumerate(starts):
        sec = text[a + len('### Task '):starts[i + 1] if i + 1 < len(starts) else len(text)]
        tid = sec.split(':', 1)[0].split()[0]
        m = re.search(r'\*\*Files \(in `([\w.-]+)`\):\*\*', sec)
        if not m or not os.path.isdir(os.path.join(work, m.group(1))):
            print(f'{tid}: skipped (its repo is not in {work})')
            continue
        repo = os.path.join(work, m.group(1))
        pos, applied = 0, 0
        for b in block.finditer(sec):
            lang, body = b.group(2), b.group(3)
            before = sec[pos:b.start()]
            pos = b.end()
            if lang in ('bash', 'output'):
                continue
            if lang == 'diff':
                r = subprocess.run(['git', '-C', repo, 'apply', '-'], input=body + '\n', text=True, capture_output=True)
                if r.returncode:
                    sys.exit(f'{tid}: a patch failed: {r.stderr}')
            else:
                path = re.findall(r'`([^`\s]+)`', before)[-1]
                full = os.path.join(repo, path)
                os.makedirs(os.path.dirname(full), exist_ok=True)
                open(full, 'w').write(body + '\n')
                if re.search(r'`\s*\(executable\):?\s*$', before):
                    os.chmod(full, 0o755)
            applied += 1
        print(f'{tid}: {applied} blocks applied to {m.group(1)}')


main(sys.argv)
