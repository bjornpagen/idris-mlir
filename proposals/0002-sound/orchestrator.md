<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Orchestrator prompt: proposal 0002

You coordinate proposal 0002 (`proposals/0002-sound/README.md`) in
`/Users/bjorn/Documents/idris-mlir`, branch `main`.

1. Re-read the README, `ownership.json`, `review.md` and the owner's
   guideline (`parts/representation.md`), which judges every hunk. Run
   `python3 proposals/0002-sound/assemble.py` and
   `python3 proposals/0002-sound/validate.py`; dispatch nothing while it
   reports a problem.
2. Dispatch all eighteen lanes at once, each with its `dispatch/<lane>.md` as
   the whole assignment, read in full, the guideline first. Where a workflow
   would cap concurrency below eighteen, spawn the lanes as direct background
   subagents instead. No lane waits on another; none is held back.
3. While they run: answer seams; apply hub requests (`*.ipkg`,
   `CMakeLists.txt`, `Makefile`, `PINS.md`, `upstream/README.md`,
   `tools/policies.txt`) as lanes report them; settle contract disputes in
   the README and re-dispatch only the affected lane. A quiet lane gets a
   message, never a stop.
4. Audit each handoff against its lane's contract and exclusions, not its
   tone: every changed hunk maps to an obligation; each obligation's
   representation line names the state made unrepresentable or the branch
   deleted, and the diff shows it; deletions happened; nothing outside the
   write set changed. Send overreach, or a branch where a representation was
   available, back to its writer.
5. Cross-review (README §6): each lane's diff read by its named reviewer lane
   before integration, the guideline the first lens; fold findings back
   through the writer.
6. Integrate, in this order: the hub texts (K2's two CMake lines, I's two
   `.ipkg` lines, B's unittests, the `tools/policies.txt` lines of T, Q and
   I, with Q's outcome deciding `translateIOProgram`'s and Driver's
   `covering`); one `tools/dialects.sh generate typecheck` after F, P and K2
   are final; X1's A10 fixture repairs with F's verifier; a diff of the three
   copies of §4.6 (I, T, Q) and of E's and N's `folded=@f`; then
   `tools/licenses.sh --apply`, `make typecheck`, `make check`, repairs and
   reruns until green; the record (`proposals/**`, `HANDOFF.md`); one commit,
   pushed. Behavioural qualification of the compiler is the owner's build.
