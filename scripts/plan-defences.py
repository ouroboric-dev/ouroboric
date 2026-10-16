#!/usr/bin/env python3
# Show that a plan's safety tests can fail: remove one defence at a time from the code, run the test that
# is meant to catch it, and put the code back.
#   plan-defences.py WORKSPACE ROWS [TASK...]
# WORKSPACE holds one git clone per repo (a plan's reference workspace, or an executor's). ROWS is a JSON
# file: a list of objects with "task", "repo", "file" (relative to the repo), "old" (the text of the
# defence, which must be in the file), "new" (what replaces its first occurrence), "dir" (the package to
# test, "." by default), "run" (the -run pattern of the test that should fail) and "what" (a few words on
# the defence). With TASK arguments only those tasks' rows run. For each row it prints a line of a
# markdown table: the task, what was removed, and the tests that failed. A row passes only if the test
# run reached a test and a test failed: a mutation that doesn't compile, or a run that times out, shows
# that the mutation was bad, not that the defence is tested. It exits 1 if any row didn't pass, and
# refuses to touch a file with changes that aren't committed. The file is restored in every case. It
# needs go on PATH, and uses the go.work or GOWORK of the environment. Run it as `python3 -I`.
import json
import os
import re
import subprocess
import sys


def main(argv):
    if len(argv) < 3:
        sys.exit('usage: plan-defences.py WORKSPACE ROWS [TASK...]')
    work, rows_file, only = argv[1], argv[2], set(argv[3:])
    with open(rows_file) as f:
        rows = json.load(f)
    ok = True
    print('| Task | Defence removed | Test that fails |')
    print('|---|---|---|')
    for row in rows:
        if only and row['task'] not in only:
            continue
        passed, shown = one(work, row)
        ok = ok and passed
        print(f"| {row['task']} | {row['what']} | {shown} |")
    sys.exit(0 if ok else 1)


def one(work, row):
    repo = os.path.join(work, row['repo'])
    path = os.path.join(repo, row['file'])
    dirty = subprocess.run(['git', '-C', repo, 'diff', '--quiet', 'HEAD', '--', row['file']])
    if dirty.returncode != 0:
        sys.exit(f"{row['task']}: {row['file']} has changes that aren't committed; commit or stash them first")
    with open(path) as f:
        src = f.read()
    if row['old'] not in src:
        print(f"!! {row['task']}: the text to remove is not in {row['repo']}/{row['file']}: {row['old'][:60]!r}", file=sys.stderr)
        return False, 'NOT RUN (the text to remove is not there)'
    try:
        with open(path, 'w') as f:
            f.write(src.replace(row['old'], row['new'], 1))
        try:
            r = subprocess.run(['go', 'test', '-count=1', '-timeout', '60s', '-run', row.get('run', '.'), row.get('dir', '.')],
                               cwd=repo, capture_output=True, text=True, timeout=300)
            out = r.stdout + r.stderr
        except subprocess.TimeoutExpired:
            out, r = '', None
    finally:
        with open(path, 'w') as f:
            f.write(src)
    names = sorted({m.group(1) for m in re.finditer(r'^--- FAIL: (\S+)', out, re.M)})
    if names:
        return True, ', '.join(f'`{n}`' for n in names)
    print(f"!! {row['task']}: {row['what']}: no test failed ({'timed out' if r is None else 'the run did not reach a test: does the mutation compile?'})", file=sys.stderr)
    return False, 'NOT FAILED'


main(sys.argv)
