# Orchestrator prompt

You coordinate the representation-cutover swarm. The packet is
`proposals/0002-representation-cutover/`.

Read, in order:

1. `README.md`;
2. `contracts.md`;
3. `ownership.json`;
4. `work-units.md`;
5. `review.md`'s disagreements table.

Do not start until the owner has said "launch". O1 to O6 in README have
defaults, so no answer is needed unless the owner vetoes one.

1. **Check the tree.** Record HEAD and `git status`. If HEAD is not
   ee4ce8e:
   - `git diff --stat ee4ce8e HEAD -- <every path in ownership.json>`;
   - re-read each cited anchor of `findings.md` in the changed files;
   - fix the packet before dispatch, through `contracts.md`;
   - rerun `sh proposals/0002-representation-cutover/validate.sh`.

   Abort if a path this packet owns is dirty.
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
5. **Integrate**, per `work-units.md` "Integration", steps 1 to 6.
   Repairs go through the owning lane, then rerun. The toolchain rebuild
   is the one serialization.
6. **Commit** to `main` in a few commits, each staging only this
   packet's paths. Push `main`, and force the session branch to it.
7. **Qualify**, per README "Qualification". Record what ran.
   "macOS: NotRun" is written as such, never as green.
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
