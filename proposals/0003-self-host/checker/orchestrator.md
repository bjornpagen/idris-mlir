<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Orchestrator prompt: the polymorphism checker (0003 S2.2)

You coordinate the checker (`proposals/0003-self-host/checker/README.md`)
in `/Users/bjorn/Documents/idris-mlir`, on branch `main`.

1. **Prepare.**
   - Re-read the README, `ownership.json`, `review.md` and the owner's
     guideline (`parts/representation.md`), which judges every hunk.
   - Run `python3 proposals/0003-self-host/checker/assemble.py`, then
     `validate.py`. Dispatch nothing while either reports a problem.
   - Check that D3 and D6 carry the owner's confirmation.
2. **Dispatch** all nineteen lanes at once.
   - Each lane gets its `dispatch/<lane>.md` as its whole assignment, read
     in full, the guideline first.
   - Where a workflow would cap concurrency below nineteen, spawn the lanes
     as direct background subagents instead.
   - No lane waits on another, and none is held back. Every lane writes
     against §4's fixed declarations, and stubs its siblings in its private
     copy.
3. **While they run:**
   - answer seams;
   - settle each contract dispute in the README's §4 and re-dispatch only
     the affected lanes;
   - apply hub requests as lanes report them: the module lines for
     `compiler/idris-mlir.ipkg`, and the `tools/policies.txt` lines;
   - send a quiet lane a message, never a stop.
4. **Audit each handoff** against its lane's contract and exclusions, not
   its tone:
   - every changed hunk maps to an obligation;
   - each obligation's representation line names the state made
     unrepresentable or the branch deleted, and the diff shows it;
   - the deletions happened;
   - nothing outside the write set changed;
   - no `assert_total`, `covering`, `believe_me` or postulate entered.

   Send overreach back to its writer, and so with a branch where a
   representation was available.
5. **Integrate**, in this order:
   1. **The ipkg.**
      - Add `Proof.Growth`, `Proof.Bound`, `Frontend.Growth` and its nine
        modules: Template, Sites, Implementations, Heads, Fields, Caps,
        Graph, Check, Potential.
      - Remove `Proof.AlmostFull`, and `git rm` its file, which P3 empties
        and hands over. `Proof.Generations` stays.
   2. **Profile:** export `answersForBody` (`Frontend/Profile.idr:70`),
      which Sites needs to typecheck.
   3. **`covering`:**
      - delete it from `translateIOProgram` (`Translate/Programs.idr`) and
        from Driver's `perform`, `frontend` and `main`, where
        `translateFrom`'s totality was the only reason for it;
      - delete Programs.idr:149's comment saying so.
   4. **`tools/policies.txt`:** delete the six `covering` lines, and with
      them the section header at :34-36, which they leave empty.
   5. **`tests/ACCEPTANCE.md`:** apply the lines from T1's, T2's and T3's
      handoffs, at the places they name.
   6. **Checks:** `tools/licenses.sh --apply`, `make typecheck`, `make
      check`, with repairs through each lane's writer and reruns until
      green.
6. **Qualify** on this machine, per README §7:
   1. build the integrated frontend and HEAD's in `/tmp/0003c-gate/`;
   2. run both over `tests/programs`, `tests/accept` and `tests/reject` on
      Chez and diff status, stdout, stderr and Core;
   3. run T3's box;
   4. run the self compile's frontend step unpatched, against the S1
      prefix `/tmp/0014-S2b/s1/pfx`, recording its refusals and the growth
      phase's time in `bench/profiles/`. A polymorphism refusal there goes
      to the owner with its cycle;
   5. run gate 5: typecheck `Proof/` and `Frontend/Growth/{Check,Potential}.idr`
      with totality enforced, and search for `assert_total`, `covering`,
      `believe_me` and `postulate` in `Proof/`, `Frontend/Growth*` and
      `Frontend/Finite.idr`.

   No gate uses a patched frontend (D2).
7. **Record.**
   - Delete the backdoor's scratch: `/tmp/0014-S2b/emit`,
     `/tmp/0014-S21C/self`, and the prototype's `S22_ADMIT` frontends under
     `/tmp/s22/proto`. Keep the S1 prefix.
   - Write the record in `proposals/0003-self-host/README.md` (S2.2 done,
     the self compile's next blocker) and in `HANDOFF.md`.
   - Make one commit and push it. The owner's build runs the
     `NEEDS-ACCEPTANCE` fixtures.
