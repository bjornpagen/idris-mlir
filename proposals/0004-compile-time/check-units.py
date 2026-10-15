#!/usr/bin/env python3
# Syntax-checks named C++ units of the typecheck build with their exact
# compile commands (dev warnings as errors), in parallel; safe to run from
# several lanes at once, since it writes nothing. A header is checked
# through the .cpp files that include it.
#   python3 proposals/0004-compile-time/check-units.py FILE.cpp...
import concurrent.futures as cf, json, os, shlex, subprocess, sys
root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
want = {os.path.abspath(f) for f in sys.argv[1:]}
db = json.load(open(os.path.join(root, 'build/typecheck/compile_commands.json')))
units = [e for e in db if os.path.abspath(e['file']) in want]
def run(e):
    args = e.get('arguments') or shlex.split(e['command'])
    out, skip = [], False
    for a in args:
        if skip: skip = False; continue
        if a == '-o': skip = True; continue
        if a == '-c': continue
        out.append(a)
    p = subprocess.run(out + ['-fsyntax-only'], cwd=e['directory'], capture_output=True, text=True)
    return e['file'], p.returncode, p.stderr
missing = want - {os.path.abspath(e['file']) for e in units}
bad = 0
with cf.ThreadPoolExecutor(8) as ex:
    for f, rc, err in ex.map(run, units):
        if rc:
            bad += 1
            print(f); print(err[:4000])
for m in sorted(missing):
    print(f'not in the typecheck build (new file: the coordinator adds it to its build list): {os.path.relpath(m, root)}')
print(f'{len(units)} unit(s) checked, {bad} failing, {len(missing)} not in the build')
sys.exit(1 if bad else 0)
