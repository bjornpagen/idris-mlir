#!/usr/bin/env python3
# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# Checks the packet's own claims: links resolve; every finding has exactly
# one owner and the README agrees with ownership.json; no two writers
# overlap, exactly or by prefix; every dispatch carries the template's
# sections, the owner's guideline, the common obligations and exactly six
# binding rules, names its
# findings and every path it owns; no dispatch tells a lane to wait; no
# retired mechanism is prescribed outside a Delete section.
import json
import os
import re
import sys

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.normpath(os.path.join(here, "..", ".."))
problems = []
counts = {}

SECTIONS = ["Findings:", "Owner / exclusive writes:", "Read first:", "Permitted outcome:",
            "Fixed decisions:", "Inputs:", "Outputs:", "Implement:", "Delete:", "NOT TO DO:",
            "Stop and return:", "Acceptance:", "Tempting partial solution:", "Escalate if:",
            "Handoff:"]
WAITING = re.compile(r"\b(wait (for|until|on)|once [A-Z][A-Za-z0-9]* (lands|has landed|is done)|"
                     r"after [A-Z][A-Za-z0-9]* (lands|finishes)|blocked on)\b")
RETIRED = ["registerCanonicalizerPass", "chainGrows", "passesEnd", "worklistEnds", "kSinkBudget",
           "Holds.cpp", "noPath", "OnUnfolded"]


def text(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def part(path):
    """A part as assemble.py copies it: without its licence lines."""
    lines = text(path).split("\n")
    while lines and (lines[0].startswith("<!-- SPDX-License-Identifier:") or lines[0].startswith("<!-- Copyright")):
        lines.pop(0)
    return "\n".join(lines).strip()


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
    return p[:-2] if p.endswith("/**") else None


def covers(pattern, path):
    pre = prefix(pattern)
    if pre is None:
        return pattern == path
    other = prefix(path)
    target = other if other is not None else path
    return target == pre or target.startswith(pre + "/")


def overlaps(a, b):
    return covers(a, b) or covers(b, a)


def excluded(entry, path):
    return any(covers(e, path) for e in entry.get("excludes", []))


def main():
    owners = json.load(open(os.path.join(here, "ownership.json"), encoding="utf-8"))
    readme = os.path.join(here, "README.md")
    links = check_links(readme)
    for name in sorted(os.listdir(os.path.join(here, "parts", "lanes"))) if os.path.isdir(
            os.path.join(here, "parts", "lanes")) else []:
        links += check_links(os.path.join(here, "parts", "lanes", name))
    counts["links checked"] = links

    # Findings: one row each in README §3, owner equals ownership.json.
    rows = re.findall(r"^\| (F\d\d) \|.*\| ([A-Z][A-Z0-9]*) \|$", text(readme), re.M)
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
    for fid in sorted(set(seen) | set(owned)):
        if seen.get(fid) != owned.get(fid):
            problems.append(f"finding {fid}: README says {seen.get(fid)}, ownership.json says {owned.get(fid)}")
    counts["findings"] = len(seen)

    # Writers: pairwise disjoint after exclusions.
    lanes = list(owners)
    pairs = 0
    for i, a in enumerate(lanes):
        for b in lanes[i + 1:]:
            for pa in owners[a]["writes"]:
                for pb in owners[b]["writes"]:
                    pairs += 1
                    if not overlaps(pa, pb):
                        continue
                    # The narrower path must be excluded from the wider one.
                    if covers(pa, pb) and pa != pb and excluded(owners[a], pb):
                        continue
                    if covers(pb, pa) and pa != pb and excluded(owners[b], pa):
                        continue
                    problems.append(f"write overlap: {a} {pa} / {b} {pb}")
    counts["write pairs compared"] = pairs

    # Dispatches.
    ddir = os.path.join(here, "dispatch")
    common = part(os.path.join(here, "parts", "common.md"))
    representation = part(os.path.join(here, "parts", "representation.md"))
    dispatched = 0
    for lane, entry in owners.items():
        if lane == "coordinator":
            continue
        path = os.path.join(ddir, lane + ".md")
        if not os.path.exists(path):
            problems.append(f"no dispatch for {lane} (run assemble.py)")
            continue
        dispatched += 1
        d = text(path)
        for s in SECTIONS:
            if s not in d:
                problems.append(f"dispatch {lane}: missing section {s}")
        if not d.split("<!-- lane -->", 1)[0].rstrip().endswith(representation):
            problems.append(f"dispatch {lane}: the owner's guideline is not verbatim before the lane")
        if common not in d:
            problems.append(f"dispatch {lane}: the common obligations are not verbatim")
        rules = re.findall(r"^[1-6]\. ", d.split("## Binding rules", 1)[-1], re.M)
        if len(rules) != 6:
            problems.append(f"dispatch {lane}: {len(rules)} binding rules, expected 6")
        m = re.search(r"^Findings: (.*)$", d, re.M)
        listed = set(re.findall(r"F\d\d", m.group(1))) if m else set()
        if listed != set(entry.get("findings", [])):
            problems.append(f"dispatch {lane}: findings {sorted(listed)} != ownership {entry.get('findings', [])}")
        for p in entry["writes"]:
            if p.replace("/**", "") not in d:
                problems.append(f"dispatch {lane}: does not name owned path {p}")
        lane_text = d.split("<!-- lane -->", 1)[-1].split("## Common obligations", 1)[0]
        for m in WAITING.finditer(lane_text):
            problems.append(f"dispatch {lane}: waiting language: {m.group(0)!r}")
        body = lane_text
        parts = re.split(r"^(Delete:)", body, flags=re.M)
        outside = parts[0] + "".join(parts[2:]) if len(parts) > 1 else body
        # Text after Delete: up to the next section heading is the Delete section.
        if len(parts) > 2:
            after = parts[2]
            nxt = re.search(r"^(NOT TO DO:|Stop and return:)", after, re.M)
            outside = parts[0] + (after[nxt.start():] if nxt else "")
        for term in RETIRED:
            if term in outside and "Delete" not in outside[max(0, outside.find(term) - 200):outside.find(term)]:
                problems.append(f"dispatch {lane}: prescribes retired {term}")
    counts["dispatches checked"] = dispatched

    for k, v in counts.items():
        print(f"{k}: {v}")
    for p in problems:
        print("PROBLEM: " + p)
    print(f"problems: {len(problems)}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
