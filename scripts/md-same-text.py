#!/usr/bin/env python3
# Compare two versions of one Markdown file: print "same", "text" or "code". Used by md-same-text.sh.
#   md-same-text.py OLD NEW
# Checked in this order, and the first that differs is printed:
#   "code":  the contents of fenced and indented code blocks differ by even one byte.
#   "links": the link and image targets differ (href of links, src of images, href= and src= in raw HTML).
#   "text":  the rendered text differs (tags stripped, entities decoded, whitespace collapsed).
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
    text = html.unescape(re.sub(r'<[^>]*>', '', md.render(src)))
    toks = list(walk(md.parse(src)))
    code = [t.content for t in toks if t.type in ('fence', 'code_block')]
    links = []
    for t in toks:
        if t.type == 'link_open':
            links.append(t.attrGet('href'))
        elif t.type == 'image':
            links.append(t.attrGet('src'))
        elif t.type in ('html_block', 'html_inline'):
            links += re.findall(r'\b(?:href|src)\s*=\s*("[^"]*"|\'[^\']*\'|[^\s>]+)', t.content)
    return ' '.join(text.split()), code, links


if len(sys.argv) != 3:
    sys.exit('usage: md-same-text.py OLD NEW')
old, new = parts(sys.argv[1]), parts(sys.argv[2])
print(next((n for n, i in (('code', 1), ('links', 2), ('text', 0)) if old[i] != new[i]), 'same'))
