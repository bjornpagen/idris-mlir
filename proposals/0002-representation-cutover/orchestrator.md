# Orchestrator prompt

You coordinate the representation-cutover swarm. The packet is
`proposals/0002-representation-cutover/`.

Read, in order:

1. `README.md`;
2. `contracts.md`;
3. `ownership.json`;
4. `work-units.md`;
5. `review.md`'s disagreements table (its Chez readings are the record,
   L25; README O3 is the live text).

Do not start until the owner has said "launch". O1 to O6 in README have
defaults, so no answer is needed unless the owner vetoes one.

1. **Check the tree.** Record HEAD and `git status`. The launch base is
   ccc3e1dc (README, Engagement contract): 1677b8cb, phase 1b's
   08a065e4 and ccc3e1dc. The packet was re-diffed from ee4ce8e to
   1677b8cb, then from 1677b8cb to ccc3e1dc, at launch, and the anchors
   phase 1b moved are given at ccc3e1dc (README "Rulings at launch",
   L49 to L54). If HEAD is past ccc3e1dc:
   - `git diff --stat ccc3e1dc HEAD -- <every path in ownership.json>`;
   - re-read each cited anchor of `findings.md` in the changed files;
   - fix the packet before dispatch, through `contracts.md`, and add a
     row to "Rulings at launch" for each change;
   - rerun `sh proposals/0002-representation-cutover/validate.sh`;
   - record that HEAD as the launch base, in place of ccc3e1dc.

   Abort if a path this packet owns is dirty, except
   `proposals/0002-representation-cutover/` itself, whose launch edits
   are committed at integration. Dispatch on the launch base. Before
   applying the hubs, at the launch base:
   - `make build`, then `make test`, and copy `tests/build/timing`,
     which `tests/compile-times.sh --against` reads;
   - keep a copy of the build, `build/dev-darwin` and
     `compiler/build/exec`, for the sensitivity runs and the launch
     base's bench record (`work-units.md` "Integration", between steps 4
     and 5): after the toolchain rebuild, `tools/verify-pins.sh` refuses
     the new toolchain for a tree without U01's patch.

   **Done at launch.** This ordering is satisfied: after a green
   `make test` at ccc3e1dc, and before the hubs were applied, the
   coordinator kept the launch base's `build/dev-darwin`,
   `compiler/build/exec` and `tests/build/timing` (with the generated
   `Frontend/Paths.idr` and the `HEAD` they were built at) in
   `/private/tmp/claude-501/-Users-bjorn-Documents-idris-mlir/5885df12-b5c5-432d-ad84-4829b14959f5/scratchpad/launch-base`.
   The launch base's `bench/run.sh` record is not made here: the
   coordinator makes it at integration with that kept build swapped in,
   as the sensitivity runs are (`work-units.md` "Integration", between
   steps 4 and 5).
2. **Apply the hubs and dispatch.** Apply `contracts.md` C1 to the hub
   files yourself first (`work-units.md`, "At dispatch"). That way every
   lane's names have one written home. Then dispatch all 23 lanes at
   once. Each lane's entire prompt is the full text of its assembled
   `dispatch/U??-*.md`; do not summarise or trim a dispatch.
   - Do not add a 24th lane, a "foundation" lane or a wave.
   - If the environment cannot run 23 agents concurrently, say so, with
     the number it can run. Do not quietly serialize.
   - Lanes share one checkout and write disjoint files. No lane uses a
     worktree, by the owner's standing preference.
3. **Concurrent coordinator work** while lanes run: exports, unit lines,
   contract disputes (`work-units.md`).
4. **Audit each handoff** against its dispatch: the permitted outcome,
   the exclusive writes, NOT TO DO and the Delete list. Reject extras
   through the same lane. A contract conflict is fixed in `contracts.md`
   by you and re-dispatched to the affected lane; lanes never negotiate.
5. **Integrate**, per `work-units.md` "Integration", steps 1 to 5,
   with the sensitivity and compile-time runs between steps 4 and 5.
   Repairs go through the owning lane, then rerun. The toolchain rebuild
   is the one serialization.
6. **Commit** to `main` in a few commits, each staging only this
   packet's paths. U01's group, its `PINS.md` text, C1.2's
   `idr-dead-values` lines and the sentences of 02's and 06's READMEs
   go in one commit (C1.8). Before pushing, `git fetch` and rebase onto
   `origin/main`: another agent pushes `upstream/README.md`, the
   `upstream/NN` READMEs and `PINS.md`. Push `main`, and force the
   session branch to it.
7. **Qualify**, per README "Qualification". Record what ran.
   "x86_64 Linux: NotRun" is written as such, never as green.
8. **Report:**
   - what ran, and what was `NotRun`;
   - the sensitivity results;
   - the measurements;
   - the unresolved seams.

   Never call the packet proof that the compiler is correct.

Binding rules for you:

- You edit the packet and the hubs only.
- You never write a lane's file.
- You never widen scope to fix an adjacent bug you noticed.
- You resolve a contract contradiction in `contracts.md` and re-dispatch
  the affected lane, instead of letting two lanes negotiate.
