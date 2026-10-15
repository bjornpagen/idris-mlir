#!/bin/sh
# Document checks for the cutover swarm packet. Exits 1 on any violation and
# prints the counts. Needs python3.
# Run: sh proposals/0004-compile-time/validate.sh
#
# Checks: at least twelve lanes; no exact or prefix intersection between any
# two writers, the coordinator included; every lane has a part and an
# assembled dispatch; every part has the template's sections; every
# dispatch carries the common obligations, the guideline and exactly six
# binding rules; every part names every path its lane owns; every contract a
# part cites exists in contracts.md, and every contract has one producer
# lane that cites it under Outputs; no part says it waits on a sibling, the
# coordinator or a gate; no retired mechanism is named in a part outside
# Delete, NOT TO DO and Tempting partial solutions; every local link in the
# packet resolves.
set -u
here=$(cd "$(dirname "$0")" && pwd)
exec python3 - "$here" << 'PY'
import json, os, re, sys
here = sys.argv[1]
repo = os.path.abspath(os.path.join(here, '..', '..'))
own = json.load(open(os.path.join(here, 'ownership.json')))
roots = own['roots']; lanes = own['lanes']
fails = []
def ex(p):
    for k, v in roots.items():
        if p == k or p.startswith(k + '/'):
            return v + p[len(k):]
    return p
work = [l for l in lanes if l != 'coordinator']
if len(work) < 12: fails.append(f'only {len(work)} lanes')
paths = [(ex(p), l) for l, v in lanes.items() for p in v['writes']]
for i, (a, la) in enumerate(paths):
    for b, lb in paths[i + 1:]:
        if la != lb and (a == b or a.startswith(b + '/') or b.startswith(a + '/')):
            fails.append(f'writers intersect: {a} ({la}) and {b} ({lb})')
parts_dir = os.path.join(here, 'dispatch', 'parts')
heads = ['## Permitted outcome', '## Owner / exclusive writes', '## Read first', '## Fixed decisions',
         '## Inputs', '## Outputs', '## Implement', '## Delete', '## NOT TO DO',
         '## Tempting partial solutions', '## Acceptance', '## Stop and return']
retired = ['scc-pipeline', 'max-rounds', 'buildSimplifyRound', 'RoundFacts', 'LoopBreakers', 'break_last',
           'OperationFingerPrint', 'idr.inlined', '--without', '--dump-dir', '--demand-in-place',
           '--break-shape', 'compile-time budget', 'instanceBudget', 'LabelSet::top', 'isFollowed',
           'unifySuspensions', 'labelsFor', 'idr-isolate', 'Linear.Array', 'IArray', 'idr-in-bounds',
           'idr-vectorize', 'ArrayLoops', 'ArrayLoopReads', 'ArrayView', 'prim__index', 'prim__arraySize',
           'Prof.idr', '$world']
allowed_sections = ('## Delete', '## NOT TO DO', '## Tempting partial solutions')
waiting = re.compile(r'\b(wait(s|ing)? (for|on|until)|blocked (by|on)|after U\d\d|once U\d\d (lands|is done|finishes)|depends on U\d\d)', re.I)
contracts_path = os.path.join(here, 'contracts.md')
contracts = open(contracts_path).read() if os.path.exists(contracts_path) else ''
defined = set(re.findall(r'^## (C\d\d)\b', contracts, re.M))
if not contracts: fails.append('contracts.md missing')
producers = {}
for lane in work:
    found = [f for f in os.listdir(parts_dir) if re.match(lane + r'-.*\.md$', f)]
    if len(found) != 1:
        fails.append(f'{lane}: {len(found)} parts'); continue
    part = open(os.path.join(parts_dir, found[0])).read()
    for h in heads:
        if h not in part: fails.append(f'{lane}: missing section {h}')
    for p in lanes[lane]['writes']:
        if p not in part and ex(p) not in part:
            fails.append(f'{lane}: part does not name owned path {p}')
    if waiting.search(part): fails.append(f'{lane}: waiting phrase "{waiting.search(part).group(0)}"')
    sections = re.split(r'(?m)^(?=## )', part)
    for s in sections:
        if s.startswith(allowed_sections): continue
        for r in retired:
            if r in s: fails.append(f'{lane}: retired "{r}" outside Delete/NOT TO DO/Tempting')
    cited = set(re.findall(r'\bC\d\d\b', part))
    for c in cited - defined: fails.append(f'{lane}: cites {c}, not in contracts.md')
    outs = re.search(r'(?ms)^## Outputs\n(.*?)(?=^## )', part)
    for c in set(re.findall(r'\bC\d\d\b', outs.group(1) if outs else '')):
        producers.setdefault(c, []).append(lane)
    d = os.path.join(here, 'dispatch', found[0])
    if not os.path.exists(d): fails.append(f'{lane}: not assembled'); continue
    dt = open(d).read()
    if '## Common obligations' not in dt: fails.append(f'{lane}: dispatch lacks common obligations')
    if "## The owner's guideline: representation first" not in dt: fails.append(f'{lane}: dispatch lacks the guideline')
    br = dt.split('## Binding rules', 1)
    n = len(re.findall(r'(?m)^[1-9]\. ', br[1])) if len(br) == 2 else 0
    if n != 6: fails.append(f'{lane}: {n} binding rules')
for c in sorted(defined):
    if c not in producers: fails.append(f'{c}: no lane lists it under Outputs')
for md in [os.path.join(dp, f) for dp, _, fs in os.walk(here) for f in fs if f.endswith('.md')]:
    text = re.sub(r'```.*?```', '', open(md).read(), flags=re.S)
    for link in re.findall(r'\]\(([^)#\s]+)', text):
        if '://' in link: continue
        if not os.path.exists(os.path.normpath(os.path.join(os.path.dirname(md), link))):
            fails.append(f'{os.path.relpath(md, here)}: broken link {link}')
print(json.dumps({'lanes': len(work), 'paths': len(paths), 'contracts': len(defined), 'failures': len(fails)}))
for f in fails: print(f)
sys.exit(1 if fails else 0)
PY
