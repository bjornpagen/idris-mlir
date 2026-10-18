<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Orchestrator: the representation wave (0004)

You are the coordinator. The packet is `README.md`, `ownership.json` and
`dispatch/<lane>.md`. You write the hubs, the generated modules and the
records, and you integrate and qualify; you are not a relay.

1. **Before dispatch.**
   - Confirm the base: the checker's integration commit is HEAD, the tree is
     clean apart from this packet, and `python3 assemble.py` then
     `python3 validate.py` report no problem.
   - Get the owner's rulings on §9 D1 and D2. If D1 is declined, delete
     idris-frontend-1 and S25 from the packet (and its consumers' lines) and
     reassemble; if D2 is declined, S6 becomes an attribute-backed
     `DefaultValuedAttr` and the risk line goes.
2. **Dispatch** all 24 lanes at once, each with its `dispatch/<lane>.md` as
   the whole prompt. Keep a one-line note per lane (agent, state). L25, L26
   and L27 (added 2026-10-18, base 1e5a8a8e) dispatch together with L23,
   whose dispatch they share seams with (README §6, §9 A9 to A12, E1 to
   E10).
3. **While lanes run.** Answer escalations by correcting the packet (README
   §4, a lane body) and re-dispatching only the affected lane; never let a
   lane widen its writes. Apply hub text from handoffs: CMake (new sources,
   `Analysis/CallCycles.cpp`, `InitIdr.h`), ipkg, `tests/spec/**` (S27's
   spec test), `PINS.md`.
4. **Integrate** when every lane has handed off:
   - Review each lane's diff against its dispatch: representation built,
     predecessor deleted (grep each name in its Delete section across the
     tree), consumers adapted, nothing outside its writes, nothing extra.
     Send attributable overreach back to its writer.
   - Regenerate the Idris modules: `tools/dialects.sh generate typecheck`.
   - `make typecheck` (every part). Route each C++ error to the lane owning
     the file as a repair dispatch with the error text; rerun until green.
   - `make check`.
   - Idris on Chez: build the frontend, run `tests/programs`, `tests/accept`,
     `tests/reject` against the base frontend (status, stdout, stderr, Core;
     Core differences only where a lane's handoff names them), and the self
     compile's frontend step (exit 0).
   - The runtime's property programs with host clang.
   - `tests/ACCEPTANCE.md` regenerated from the tree's marks.
5. **Record and commit.** Update `proposals/README.md` and `HANDOFF.md`
   (what the owner's build must run, both targets); delete this packet's
   done parts as the proposals rule says; one commit; push.
6. **Owner's build** qualifies: `make build`, `make test`, `make test-idr`,
   `make test-unit`, `make test-mlir-tools` on both targets.
