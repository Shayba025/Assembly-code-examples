#!/usr/bin/env python3
"""Align every inline comment in a NASM source file to one column.

Full-line comments that already start in column 0 (the ;;; banner blocks) are
left exactly as they are. Every other line that carries a `;` comment -- whether
it also carries code, or is a wrapped continuation of the comment above it -- is
padded so that all the semicolons in the file line up underneath each other.

Tabs in the code part are expanded to spaces so the alignment survives whatever
tab width the reader's editor happens to use.

    tools/align-comments.py FILE...          rewrite the files in place
    tools/align-comments.py --check FILE...  report misaligned files, write none
"""

import sys

TABSTOP = 8
MIN_COLUMN = 40          # comments never start before this column
PAD_AFTER_CODE = 2       # at least this many spaces between code and `;`


def split_comment(line):
    """Return (code, comment) where comment includes the leading `;`.

    Quote-aware: a `;` inside a NASM string literal ('...', "...", `...`) is
    data, not the start of a comment.
    """
    quote = None
    i = 0
    while i < len(line):
        ch = line[i]
        if quote:
            # inside a backquoted string, a backslash escapes the next character
            if quote == '`' and ch == '\\':
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "'\"`":
            quote = ch
        elif ch == ';':
            return line[:i], line[i:]
        i += 1
    return line, None


def code_width(code):
    """Width of the code part once tabs are expanded, trailing space removed."""
    return len(code.expandtabs(TABSTOP).rstrip())


def target_column(lines):
    """The single column this file's comments should all start at."""
    widest = 0
    for line in lines:
        code, comment = split_comment(line)
        if comment is None:
            continue
        if not code.strip():
            continue                      # continuation line: imposes no width
        if line.lstrip().startswith(';'):
            continue                      # a full-line comment
        widest = max(widest, code_width(code))
    return max(MIN_COLUMN, widest + PAD_AFTER_CODE)


def align(text):
    lines = text.split('\n')
    column = target_column(lines)
    out = []
    for line in lines:
        code, comment = split_comment(line)

        if comment is None:                       # pure code, or a blank line
            out.append(line.expandtabs(TABSTOP).rstrip() if line.strip() else '')
            continue

        if line.startswith(';'):                  # banner block: never touched
            out.append(line.rstrip())
            continue

        if not code.strip():                      # wrapped continuation line
            out.append(' ' * column + comment.rstrip())
            continue

        code = code.expandtabs(TABSTOP).rstrip()
        if len(code) + PAD_AFTER_CODE <= column:
            out.append(code.ljust(column) + comment.rstrip())
        else:                                     # code overruns the column
            out.append(code + ' ' * PAD_AFTER_CODE + comment.rstrip())
    return '\n'.join(out)


def main(argv):
    check = '--check' in argv
    paths = [a for a in argv if not a.startswith('--')]
    if not paths:
        print(__doc__)
        return 2

    changed = []
    for path in paths:
        with open(path, encoding='utf-8') as fh:
            before = fh.read()
        after = align(before)
        if after != before:
            changed.append(path)
            if not check:
                with open(path, 'w', encoding='utf-8') as fh:
                    fh.write(after)

    if check:
        for path in changed:
            print('would reformat:', path)
        return 1 if changed else 0

    print(f'aligned {len(changed)} file(s)')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
