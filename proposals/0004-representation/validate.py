#!/usr/bin/env python3
# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# Checks the packet's own claims: links resolve; every finding of findings/
# has exactly one owner and README §3 agrees with ownership.json; a merged
# finding shares its primary's owner; no two writers overlap, exactly or by
# prefix (the coordinator included), and every tracked source file the wave
# can touch has one writer; every dispatch carries the template's sections,
# the owner's guideline verbatim, its findings verbatim, the common
# obligations and exactly six binding rules, names its findings and every
# path it owns; no dispatch tells a lane to wait; every §4 contract names an
# owner lane that exists; no retired mechanism is prescribed outside a
# Delete section. Run assemble.py first.
import importlib.util
import json
import os
import re
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.normpath(os.path.join(here, "..", ".."))
spec = importlib.util.spec_from_file_location("assemble", os.path.join(here, "assemble.py"))
assemble = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assemble)

SECTIONS = ["Findings:", "Owner / exclusive writes:", "Read first:", "Permitted outcome:",
            "Fixed decisions:", "Inputs:", "Outputs:", "Implement:", "Delete:", "NOT TO DO:",
            "Stop and return:", "Acceptance:", "Tempting partial solution:", "Escalate if:",
            "Handoff:"]
WAITING = re.compile(r"\b(wait (for|until|on)|once L\d\d (lands|has landed|is done)|"
                     r"after L\d\d (lands|finishes)|blocked on)\b")
# Mechanisms this wave deletes: prescribing one outside a Delete section is a defect.
RETIRED = ["ReuseOp", "MatchLike", "rebuildMatch(", "scrutineeOf", "removeEffectsAttr",
           "callGraphComponents", "world_carrier", "holdsClosure", "Decreasing", "Bounded",
           "CalleeEffects", "PureCalls", "LowerReuse", "addStageCheck", "S22_ADMIT", "emit_patch"]
SCOPE = ["foreign/idr", "runtime", "compiler/src", "tests/idr", "tests/compiler", "tests/lib", "tests/runner"]
problems = []
counts = {}


def text(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def check_links(path):
    n = 0
    for m in re.finditer(r"\]\(([^)#\s]+)(#[^)]*)?\)", text(path)):
        target = m.group(1)
        if re.match(r"[a-z]+:", target):
            continue
        n += 1
        if not os.path.exists(os.path.normpath(os.path.join(os.path.dirname(path), target))):
            problems.append(f"{os.path.relpath(path, root)}: link to {target} does not resolve")
    return n


def prefix(p):
    return p[:-3] if p.endswith("/**") else None


def overlaps(a, b):
    pa, pb = prefix(a), prefix(b)
    if pa is None and pb is None:
        return a == b
    if pa is not None and pb is None:
        return b.startswith(pa + "/")
    if pb is not None and pa is None:
        return a.startswith(pb + "/")
    return pa == pb or pa.startswith(pb + "/") or pb.startswith(pa + "/")


def excluded(entry, path):
    return any(assemble.covers(e, path) or e == path for e in entry.get("excludes", []))


def main():
    owners = json.load(open(os.path.join(here, "ownership.json"), encoding="utf-8"))
    readme_path = os.path.join(here, "README.md")
    readme = text(readme_path)
    counts["links checked"] = check_links(readme_path) + sum(
        check_links(os.path.join(here, "parts", "lanes", n)) for n in sorted(os.listdir(os.path.join(here, "parts", "lanes"))))

    fs = assemble.findings()
    counts["findings in findings/"] = len(fs)
    rows = re.findall(r"^\| ([a-z]+(?:-[a-zA-Z]+)*-[A-Z]?\d+) \|.*\| (L\d\d)? \|[^|]*\|$", readme, re.M)
    seen = {}
    for fid, lane in rows:
        if fid in seen:
            problems.append(f"finding {fid} appears twice in README §3")
        seen[fid] = lane
    owned = {}
    for lane, entry in owners.items():
        for fid in entry.get("findings", []):
            if fid in owned:
                problems.append(f"finding {fid} owned by {owned[fid]} and {lane}")
            owned[fid] = lane
    for fid in sorted(set(fs) | set(seen) | set(owned)):
        if fid not in fs:
            problems.append(f"finding {fid} is not in findings/")
        if seen.get(fid) != owned.get(fid):
            problems.append(f"finding {fid}: README §3 says {seen.get(fid)}, ownership.json says {owned.get(fid)}")
    for lane, entry in owners.items():
        for fid, primary in entry.get("merged", {}).items():
            if owned.get(primary) != lane:
                problems.append(f"merged {fid} -> {primary}: primary owned by {owned.get(primary)}, not {lane}")
    counts["findings owned"] = len(owned)

    lanes = list(owners)
    pairs = 0
    for i, a in enumerate(lanes):
        for b in lanes[i + 1:]:
            for pa in owners[a]["writes"]:
                for pb in owners[b]["writes"]:
                    pairs += 1
                    if not overlaps(pa, pb):
                        continue
                    if pa != pb and (excluded(owners[a], pb) or excluded(owners[b], pa)):
                        continue
                    problems.append(f"write overlap: {a} {pa} / {b} {pb}")
    counts["write pairs compared"] = pairs
    files = subprocess.run(["git", "ls-files"] + SCOPE, cwd=root, capture_output=True, text=True).stdout.split()
    files += ["tests/" + n for n in os.listdir(os.path.join(root, "tests")) if n.endswith(".idr")]
    unowned = sorted(f for f in set(files) if assemble.lane_of(owners, f) is None)
    for f in unowned:
        problems.append(f"no writer for {f}")
    counts["source files with one writer"] = len(set(files)) - len(unowned)

    cs = assemble.contracts()
    for cid, (body, lanes_named, _) in cs.items():
        for l in lanes_named:
            if l not in owners:
                problems.append(f"contract {cid} names unknown lane {l}")
    counts["contracts"] = len(cs)

    common = assemble.body(text(os.path.join(here, "parts", "common.md"))).strip()
    representation = assemble.body(text(os.path.join(here, "parts", "representation.md"))).strip()
    dispatched = 0
    for lane, entry in owners.items():
        if lane == "coordinator":
            continue
        path = os.path.join(here, "dispatch", lane + ".md")
        if not os.path.exists(path):
            problems.append(f"no dispatch for {lane} (write parts/lanes/{lane}.md, run assemble.py)")
            continue
        dispatched += 1
        d = text(path)
        for s in SECTIONS:
            if not re.search(r"^\**" + re.escape(s), d, re.M):
                problems.append(f"dispatch {lane}: missing section {s}")
        if not d.split("<!-- lane -->", 1)[0].rstrip().endswith(representation):
            problems.append(f"dispatch {lane}: the owner's guideline is not verbatim before the lane")
        if common not in d:
            problems.append(f"dispatch {lane}: the common obligations are not verbatim")
        merged = entry.get("merged", {})
        for fid in entry["findings"]:
            if fid in merged:
                # assemble.py lists a merged finding under its primary, without the
                # correction the primary replaces; its heading must still be there.
                if fid not in d.split("## Findings you own", 1)[-1]:
                    problems.append(f"dispatch {lane}: merged finding {fid} not listed")
            elif fs.get(fid, {}).get("block", "\0") not in d:
                problems.append(f"dispatch {lane}: finding {fid} not quoted verbatim")
        rules = re.findall(r"^[1-6]\. ", d.split("## Binding rules", 1)[-1], re.M)
        if len(rules) != 6:
            problems.append(f"dispatch {lane}: {len(rules)} binding rules, expected 6")
        m = re.search(r"^\**Findings:\**\s*(.*)$", d, re.M)
        listed = set(re.findall(r"[a-z]+(?:-[a-zA-Z]+)*-[A-Z]?\d+", m.group(1))) if m else set()
        if listed != set(entry["findings"]):
            problems.append(f"dispatch {lane}: Findings line {sorted(listed)} != ownership {sorted(entry['findings'])}")
        for p in entry["writes"]:
            if p.replace("/**", "") not in d:
                problems.append(f"dispatch {lane}: does not name owned path {p}")
        lane_text = d.split("<!-- lane -->", 1)[-1].split("## Findings you own", 1)[0]
        for w in WAITING.finditer(lane_text):
            problems.append(f"dispatch {lane}: waiting language: {w.group(0)!r}")
        # A retired name is prescribed only where the lane is told what to build:
        # its Implement and Outputs sections (Read first, Delete, NOT TO DO and
        # Acceptance name old mechanisms on purpose).
        outside = "".join(m.group(0) for m in re.finditer(
            r"^\**(Implement|Outputs):.*?(?=^\**(Delete|NOT TO DO|Stop and return|Acceptance|Inputs|Outputs|Implement|Tempting partial solution|Escalate if|Handoff):|\Z)",
            lane_text, flags=re.S | re.M))
        for term in RETIRED:
            for hit in re.finditer(r"(?<![A-Za-z0-9_])" + re.escape(term) + r"(?![A-Za-z0-9_])", outside):
                ctx = outside[max(0, hit.start() - 320):hit.end() + 80]
                if not re.search(r"(delet|remov|gone|goes|replac|no longer|instead of|never|old|predecessor|retir|\bno |drop|lose|withdraw|not yours|instead|fixture|parse|before|base|loses|every |read first)", ctx, re.I):
                    problems.append(f"dispatch {lane}: prescribes retired {term}")
                    break
    counts["dispatches checked"] = dispatched

    for k, v in counts.items():
        print(f"{k}: {v}")
    for p in problems:
        print("PROBLEM: " + p)
    print(f"problems: {len(problems)}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
