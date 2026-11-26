#!/usr/bin/env python3
"""Rough brace/paren balance check for Swift files (ignores strings and comments)."""
import sys, glob, re
bad = 0
for f in sys.argv[1:] or glob.glob("**/*.swift", recursive=True):
    s = open(f).read()
    s = re.sub(r'#"(?:[^"\\]|\\.)*?"#', '""', s)          # raw strings
    s = re.sub(r'"""[\s\S]*?"""', '""', s)                  # multiline strings
    s = re.sub(r'//[^\n]*', '', s)
    s = re.sub(r'/\*[\s\S]*?\*/', '', s)
    # strings with interpolation: strip simple ones iteratively
    out=[]; i=0; depth=0
    stack=[]
    in_str=False; interp=[]
    while i < len(s):
        c=s[i]
        if in_str:
            if c=='\\' and i+1<len(s) and s[i+1]=='(':
                interp.append(1); in_str=False; i+=2; stack.append('I'); continue
            if c=='\\': i+=2; continue
            if c=='"': in_str=False
            i+=1; continue
        if c=='"': in_str=True; i+=1; continue
        if c in '{([': stack.append(c)
        elif c in '})]':
            if not stack: print(f, 'unbalanced close', c, 'at', s[:i].count('\n')+1); bad+=1; break
            top=stack.pop()
            if top=='I' and c==')': in_str=True
            elif {'{':'}','(':')','[':']'}.get(top)!=c:
                print(f, 'mismatch', top, c, 'line', s[:i].count('\n')+1); bad+=1; break
        i+=1
    else:
        if stack: print(f, 'unclosed', stack[-3:]); bad+=1
print('files with problems:', bad)
