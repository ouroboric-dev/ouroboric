#!/usr/bin/env python3
# Compare two versions of one Markdown file: print "same", "lintoff", "code", "links" or "text". Used by
# md-same-text.sh.
#   md-same-text.py OLD NEW
# Checked in this order, and the first that differs is printed:
#   "lintoff": NEW has more markdownlint-disable (-next-line, -line) or markdownlint-configure-file
#            comments than OLD. Turning a rule off is not a formatting fix.
#   "code":  the contents of fenced and indented code blocks differ by even one byte, or the blocks the plan
#            tools find (plan-blocks.py's regex, which CommonMark can read differently) differ.
#   "links": the link and image targets differ (href of links, src of images, href= and src= in raw HTML).
#            An autolink (<https://...>) is not counted: its target is its text.
#   "text":  the rendered text differs (tags stripped, entities decoded, whitespace collapsed). Raw HTML
#            stays in the text as its source, so `<issue>` and <issue> are the same text.
# Run it as `python3 -I`, so nothing is imported from the current folder; md-same-text.sh does that
# through `uvx --with markdown-it-py==3.0.0`. It only reads the two paths.
import html
import re
import sys

from markdown_it import MarkdownIt


# Copied from plan-blocks.py (its `block`): the plan tools extract code with this, not with CommonMark. They
# differ, for example, on a diff context line of one space and three backticks, which CommonMark takes as a
# closing fence. Compared as (info, body) pairs; see plan_same.
PLAN_BLOCK = re.compile(r'^(`{3,4})(\w*)\n(.*?)\n\1$', re.M | re.S)


def walk(tokens):
    for t in tokens:
        yield t
        yield from walk(t.children or [])


def parts(path):
    with open(path, encoding='utf-8', newline='') as f:
        src = f.read()
    md = MarkdownIt('commonmark').enable('table')
    # Raw HTML is rendered escaped, so stripping the tags keeps its source as text.
    for rule in ('html_inline', 'html_block'):
        md.add_render_rule(rule, lambda self, tokens, idx, options, env: html.escape(tokens[idx].content))
    text = html.unescape(re.sub(r'<[^>]*>', '', md.render(src)))
    toks = list(walk(md.parse(src)))
    code = [t.content for t in toks if t.type in ('fence', 'code_block')]
    plan = [(m.group(2), m.group(3)) for m in PLAN_BLOCK.finditer(src)]
    links = []
    for t in toks:
        # An autolink (<https://...>) shows its target as its text, which the text check compares.
        if t.type == 'link_open' and t.markup != 'autolink':
            links.append(t.attrGet('href'))
        elif t.type == 'image':
            links.append(t.attrGet('src'))
        elif t.type in ('html_block', 'html_inline'):
            links += re.findall(r'\b(?:href|src)\s*=\s*("[^"]*"|\'[^\']*\'|[^\s>]+)', t.content)
    lintoff = len(re.findall(r'<!--\s*markdownlint-(?:disable|configure-file)', src))
    return ' '.join(text.split()), code, links, lintoff, plan


if len(sys.argv) != 3:
    sys.exit('usage: md-same-text.py OLD NEW')
old, new = parts(sys.argv[1]), parts(sys.argv[2])


def plan_same(a, b):
    # The (info, body) pairs match byte for byte; the one allowed change is an info string given to a block
    # that had none (markdownlint MD040), which the CommonMark check above also lets through.
    return len(a) == len(b) and all(x[1] == y[1] and (x[0] == y[0] or x[0] == '') for x, y in zip(a, b))


if new[3] > old[3]:
    print('lintoff')
else:
    diff = {'code': old[1] != new[1] or not plan_same(old[4], new[4]), 'links': old[2] != new[2], 'text': old[0] != new[0]}
    print(next((n for n, d in diff.items() if d), 'same'))
