#!/usr/bin/env python3
# Compare two versions of one Markdown file: print "same", "lintoff", "code", "links" or "text". Used by
# md-same-text.sh.
#   md-same-text.py OLD NEW
# Checked in this order, and the first that differs is printed:
#   "lintoff": NEW has more markdownlint-disable (-next-line, -line) or markdownlint-configure-file
#            comments than OLD. Turning a rule off is not a formatting fix.
#   "code":  the contents of fenced and indented code blocks differ by even one byte.
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
    return ' '.join(text.split()), code, links, lintoff


if len(sys.argv) != 3:
    sys.exit('usage: md-same-text.py OLD NEW')
old, new = parts(sys.argv[1]), parts(sys.argv[2])
if new[3] > old[3]:
    print('lintoff')
else:
    print(next((n for n, i in (('code', 1), ('links', 2), ('text', 0)) if old[i] != new[i]), 'same'))
