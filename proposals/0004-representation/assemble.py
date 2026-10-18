#!/usr/bin/env python3
# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
# Assembles each lane's dispatch from parts/ and findings/, so the shared
# text is written once: the owner's representation-first guideline, the
# lane's body, the findings it owns (verbatim from findings/), the §4
# contracts it supplies or consumes (verbatim from README.md), the consumer
# adaptations other lanes' findings ask of its files, the common
# obligations and the six binding rules. It also renders README §3 and §6
# from ownership.json. dispatch/ and the tables are output; edit parts/,
# findings/, README.md's prose and ownership.json instead.
import fnmatch
import json
import os
import re
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.normpath(os.path.join(here, "..", ".."))
LANE = "<!-- lane -->"
HEAD = "<!-- SPDX-License-Identifier: 0BSD -->\n<!-- Copyright (c) 2026 Bjorn Pagen -->\n"
HEADING = re.compile(r"^(#{2,3}) (?:(?P<code>[A-Z]\d+)\.|(?P<id>[a-z]+(?:-[a-z]+)*-\d+)(?: \([^)]*\))?:)\s*(?P<title>.*)$", re.M)


def body(text):
    lines = text.split("\n")
    while lines and (lines[0].startswith("<!-- SPDX-License-Identifier:") or lines[0].startswith("<!-- Copyright")):
        lines.pop(0)
    return "\n".join(lines).rstrip("\n") + "\n"


def read(*path):
    with open(os.path.join(here, *path), encoding="utf-8") as f:
        return f.read()


def findings():
    """Every finding's ID, area, title and verbatim block, from findings/."""
    out = {}
    for name in sorted(os.listdir(os.path.join(here, "findings"))):
        area = name[:-3]
        text = body(read("findings", name))
        heads = list(HEADING.finditer(text))
        for i, h in enumerate(heads):
            fid = area + "-" + h.group("code") if h.group("code") else h.group("id")
            end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
            tail = re.search(r"^## (?![a-z]+(?:-[a-z]+)*-\d+)", text[h.end():end], re.M)
            if tail:
                end = h.end() + tail.start()
            block = text[h.start():end].strip()
            out[fid] = {"area": area, "title": h.group("title").strip(), "block": block}
    return out


def field(block, name):
    m = re.search(r"^\|\s*\**" + name + r"\**\s*\|\s*(.*?)\s*\|\s*$", block, re.M)
    if m:
        return m.group(1)
    m = re.search(r"^\*\*" + name + r"[^*]*\*\*:?\s*(.*?)(?=^\*\*[A-Z]|\Z)", block, re.M | re.S)
    if m:
        return m.group(1).strip()
    # driver-runtime.md writes each field as a bullet, "- **Name:** text", the
    # text running on over indented lines to the next bullet.
    m = re.search(r"^- \*\*" + name + r":\*\*\s*(.*?)(?=^- \*\*[A-Z]|^#{2,3} |\Z)", block, re.M | re.S)
    return re.sub(r"\s*\n\s*", " ", m.group(1)).strip() if m else ""


def expand(token):
    m = re.search(r"\{([^{}]*)\}", token)
    if not m:
        return [token]
    return [x for alt in m.group(1).split(",") for x in expand(token[:m.start()] + alt.strip() + token[m.end():])]


def repo_files():
    out = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True, text=True).stdout.split()
    return out


def covers(pattern, path):
    if pattern.endswith("/**"):
        return path.startswith(pattern[:-3] + "/")
    return pattern == path


def lane_of(owners, path):
    for lane, entry in owners.items():
        if any(covers(p, path) for p in entry["writes"]) and not any(covers(e, path) for e in entry.get("excludes", [])):
            return lane
    return None


def consumer_files(text, files, ambiguous=None):
    """What a finding's Consumers text names: repo files (backticked, braces
    expanded, matched by path suffix, `*` globs included; a bare file name
    only when unique) and directories (a token ending in `/`, reported once
    as the directory). A bare name that matches several files of ours is
    never a hit; its candidates go to `ambiguous` (a set), so that a lane
    can be told a finding may name its file."""
    mine = [f for f in files if not f.startswith(("compiler/idris/", "third_party/"))]
    hits = set()
    for tok in re.findall(r"`([^`]+)`", text):
        tok = tok.strip().split(":")[0].split(" ")[0]
        for t in expand(tok):
            t = t.strip().lstrip("/")
            if t.endswith("/"):
                inside = [f for f in files if f.startswith(t) or ("/" + t) in ("/" + f)]
                if inside:
                    d = inside[0][:inside[0].find(t) + len(t)] if t in inside[0] else t
                    hits.add(d)
                continue
            if not re.search(r"\.(cpp|h|td|idr|sh|mlir|c)$", t):
                continue
            if "/" not in t:
                named = [f for f in mine if f.split("/")[-1] == t]
                if len(named) == 1:
                    hits.add(named[0])
                elif ambiguous is not None:
                    ambiguous.update(named)
                continue
            if "*" in t:
                hits.update(f for f in files if fnmatch.fnmatch(f, "*/" + t) or fnmatch.fnmatch(f, t))
                continue
            for f in files:
                if f == t or f.endswith("/" + t):
                    hits.add(f)
    return hits


def lane_of_path(owners, path):
    """The lane writing a file, or, for a directory, the lane writing its first file."""
    if path.endswith("/"):
        files = [f for f in repo_files() if f.startswith(path)]
        return lane_of(owners, files[0]) if files else None
    return lane_of(owners, path)


def contracts():
    """README §4's contracts: id -> (text, owner lanes, consumer lanes)."""
    readme = read("README.md")
    sec = readme.split("## 4. Shared contracts", 1)[1].split("## 5.", 1)[0]
    out = {}
    for m in re.finditer(r"^\*\*(S\d+)\. (.*?)(?=^\*\*S\d+\. |\Z)", sec, re.M | re.S):
        text = m.group(0).strip()
        lanes = set(re.findall(r"\bL\d\d\b", text))
        cons = set()
        cm = re.search(r"Consumers?:([^.]*(?:\.[^A-Z\n][^.]*)*)", text)
        if cm:
            cons = set(re.findall(r"\bL\d\d\b", cm.group(1)))
        out[m.group(1)] = (text, lanes, cons)
    return out


def owned_block(fs, merged, fid):
    """A finding's block as its owner is given it. A merged finding keeps its
    evidence and loses its Correction, Deletion and Consumers, which are its
    primary's: two corrections for one root cause would contradict."""
    block = fs[fid]["block"]
    if fid not in merged:
        return block
    kept = []
    skipping = False
    for line in block.split("\n"):
        if re.match(r"^\|\s*\**(Correction|Deletion|Consumers)\**\s*\|", line) or re.match(
                r"^- \*\*(Correction|Deletion|Consumers):\*\*", line):
            skipping = True
            continue
        if skipping and (line.startswith("  ") or not line.strip()) and not line.startswith("|"):
            continue
        skipping = False
        kept.append(line)
    return (f"(Finding `{fid}`.)\n" + "\n".join(kept).rstrip() + f"\n\nMerged into `{merged[fid]}`: apply that finding's correction; "
            "this one's own is dropped, and its consumers are listed under the primary.")


def writes_text(entry):
    """What a lane may write, as ownership.json says, and what it never does."""
    lines = ["- " + "\n- ".join("`" + w + "`" for w in entry["writes"])]
    if entry.get("excludes"):
        lines.append("Not: " + ", ".join("`" + x + "`" for x in entry["excludes"]) + ".")
    lines.append("Everything else is another lane's or the coordinator's: a hub file, a generated module, "
                 "`IdrDialect.h` and `IdrBytecode.td` (README S28: put your hunk in your handoff).")
    return "\n".join(lines)


def render_tables(owners, fs):
    readme = read("README.md")
    owner_of = {f: lane for lane, e in owners.items() for f in e.get("findings", [])}
    merged = {f: p for e in owners.values() for f, p in e.get("merged", {}).items()}
    rows = ["| ID | Finding | Owner | Merged into |", "|---|---|---|---|"]
    for fid in sorted(fs, key=lambda k: (fs[k]["area"], int(re.sub(r"\D", "", k.split("-")[-1]) or 0), k)):
        title = fs[fid]["title"].replace("|", "\\|")
        rows.append(f"| {fid} | {title} | {owner_of.get(fid, '')} | {merged.get(fid, '')} |")
    table = "\n".join(rows)
    readme = re.sub(r"<!-- findings-table -->.*?<!-- /findings-table -->",
                    "<!-- findings-table -->\n" + table.replace("\\", "\\\\") + "\n<!-- /findings-table -->", readme, flags=re.S)
    rows = ["| Lane | Outcome | Exclusive writes | Findings |", "|---|---|---|---|"]
    for lane, e in owners.items():
        if lane == "coordinator":
            continue
        writes = ", ".join("`" + w + "`" for w in e["writes"])
        if e.get("excludes"):
            writes += "; not " + ", ".join("`" + x + "`" for x in e["excludes"])
        rows.append(f"| {lane} | {e['title']} | {writes} | {', '.join(e['findings'])} |")
    table = "\n".join(rows)
    readme = re.sub(r"<!-- lanes-table -->.*?<!-- /lanes-table -->",
                    "<!-- lanes-table -->\n" + table.replace("\\", "\\\\") + "\n<!-- /lanes-table -->", readme, flags=re.S)
    with open(os.path.join(here, "README.md"), "w", encoding="utf-8") as f:
        f.write(readme)


def main():
    owners = json.load(open(os.path.join(here, "ownership.json"), encoding="utf-8"))
    fs = findings()
    render_tables(owners, fs)
    cs = contracts()
    files = repo_files()
    owner_of = {f: lane for lane, e in owners.items() for f in e.get("findings", [])}
    # Consumer adaptations: a finding's named files that another lane owns. A
    # merged finding shares its primary's correction (README §3), so its files
    # are listed under the primary, with the primary's text.
    merged = {f: p for e in owners.values() for f, p in e.get("merged", {}).items()}
    adapt = {lane: [] for lane in owners}
    maybe = {lane: [] for lane in owners}
    for fid, f in fs.items():
        owner = owner_of.get(fid)
        key = merged.get(fid, fid)
        unsure = set()
        text = field(f["block"], "Consumers") or f["block"]
        for path in sorted(consumer_files(text, files, unsure)):
            lane = lane_of_path(owners, path)
            if lane and lane != owner and lane != "coordinator":
                adapt[lane].append((key, path))
        for path in sorted(unsure):
            lane = lane_of_path(owners, path)
            if lane and lane != owner and lane != "coordinator":
                maybe[lane].append((key, path))
    common = body(read("parts", "common.md"))
    rules = body(read("parts", "rules.md"))
    representation = body(read("parts", "representation.md"))
    os.makedirs(os.path.join(here, "dispatch"), exist_ok=True)
    missing = []
    for lane, entry in owners.items():
        if lane == "coordinator":
            continue
        path = os.path.join(here, "parts", "lanes", lane + ".md")
        if not os.path.exists(path):
            missing.append(lane)
            continue
        lane_body = body(read("parts", "lanes", lane + ".md"))
        owned = "\n\n".join(owned_block(fs, merged, fid) for fid in entry["findings"])
        mine = [cid for cid, (_, lanes, _) in cs.items() if lane in lanes]
        contract_text = "\n\n".join(cs[cid][0] for cid in mine) or "(none)"
        by_finding = {}
        for fid, p in adapt[lane]:
            by_finding.setdefault(fid, [])
            if p not in by_finding[fid]:
                by_finding[fid].append(p)
        perhaps = {}
        for fid, p in maybe[lane]:
            perhaps.setdefault(fid, [])
            if p not in perhaps[fid]:
                perhaps[fid].append(p)
        adapt_text = []
        for fid, paths in sorted(by_finding.items()):
            f = fs[fid]
            primary = None
            adapt_text.append(
                f"- **{fid}** (owner {owner_of.get(fid)}; its merged findings: {', '.join(m for m, p in merged.items() if p == fid) or 'none'}): "
                f"{f['title']}\n  - Your files it names: {', '.join('`' + p + '`' for p in paths)}\n"
                f"  - Correction: {field(f['block'], 'Correction') or field(f['block'], 'Selected correction') or 'see findings/' + f['area'] + '.md'}\n"
                f"  - Deletion: {field(f['block'], 'Deletion') or 'see findings/' + f['area'] + '.md'}")
        for fid, paths in sorted(perhaps.items()):
            f = fs[fid]
            adapt_text.append(
                f"- **{fid}** (owner {owner_of.get(fid)}) names a bare file name that matches several files, "
                f"of which these are yours: {', '.join('`' + p + '`' for p in paths)}. Read the finding "
                f"(findings/{f['area']}.md) and adapt the one it means; if it is not yours, say so in your handoff.")
        header = HEAD + (
            f"<!-- Generated by proposals/0004-representation/assemble.py; edit parts/, findings/, README.md and ownership.json. -->\n"
            f"# Dispatch: lane {lane} of the representation wave (0004): {entry['title']}\n\n"
            "This file is your whole assignment. The packet it quotes is "
            "`proposals/0004-representation/README.md`. Read the owner's guideline below in full "
            "before anything else: every hunk you write is judged by it.\n\n")
        text = (header + representation + "\n" + LANE + "\n" + lane_body + "\n"
                "## Your exclusive writes (generated from ownership.json; this list decides)\n\n"
                + writes_text(entry) + "\n\n"
                "## Findings you own (verbatim from the surveys; a merged finding's own correction is "
                "superseded by its primary's)\n\n" + owned + "\n\n"
                "## Contracts you supply or consume (verbatim from README §4)\n\n" + contract_text + "\n\n"
                "## Consumer adaptations (other lanes' findings that name your files)\n\n"
                "Adapt each named file of yours to the owning lane's correction, against its §4 contract "
                "where one exists; never bridge the old form. If a listing below is a false match (the "
                "finding does not touch that file), say so in your handoff.\n\n"
                + ("\n".join(adapt_text) if adapt_text else "(none)") + "\n\n" + common + "\n" + rules)
        with open(os.path.join(here, "dispatch", lane + ".md"), "w", encoding="utf-8") as f:
            f.write(text)
    if missing:
        print("no lane body for: " + ", ".join(missing))
    print(f"findings: {len(fs)}; dispatches: {len(owners) - 1 - len(missing)}; adaptations: "
          + ", ".join(f"{l}={len(v)}" for l, v in adapt.items() if v))
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
