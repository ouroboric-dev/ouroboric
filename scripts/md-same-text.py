#!/usr/bin/env python3
# Compare two versions of one Markdown file: print "same", "text" or "code". Used by md-same-text.sh.
#   md-same-text.py OLD NEW
# "code": the contents of the fenced code blocks differ by even one byte. Checked first, because code
#         is also part of the text.
# "text": the rendered text differs (tags stripped, entities decoded, whitespace collapsed).
# Run it as `python3 -I`, so nothing is imported from the current folder; md-same-text.sh does that
# through `uvx --with markdown-it-py==3.0.0`. It only reads the two paths.
import html
import re
import sys

from markdown_it import MarkdownIt


def parts(path):
    with open(path, encoding='utf-8', newline='') as f:
        src = f.read()
    md = MarkdownIt('commonmark').enable('table')
    text = html.unescape(re.sub(r'<[^>]*>', '', md.render(src)))
    code = [t.content for t in md.parse(src) if t.type == 'fence']
    return ' '.join(text.split()), code


if len(sys.argv) != 3:
    sys.exit('usage: md-same-text.py OLD NEW')
(old_text, old_code), (new_text, new_code) = parts(sys.argv[1]), parts(sys.argv[2])
print('code' if old_code != new_code else 'text' if old_text != new_text else 'same')
