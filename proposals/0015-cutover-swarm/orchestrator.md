# Orchestrator prompt

You coordinate the cutover swarm. The packet is
`proposals/0015-cutover-swarm/`.

Read, in order:

1. `README.md`, its "Rulings" and "Owner decisions" included;
2. `contracts.md`;
3. `ownership.json`;
4. `work-units.md`;
5. `review.md`'s disagreements table;
6. `../0014-get-back-on-track.md`, the design this packet executes.

Do not start until the owner has said "launch". The rulings R01 to R48
and the six owner decisions of 2026-10-12 are approved. O1 to O4 in
README have defaults, so no answer is needed unless the owner vetoes
one.

1. **Check the tree.** Record HEAD and `git status`. If HEAD is not
   25890d32:
   - `git diff --stat 25890d32 HEAD -- <every path in ownership.json>`;
   - re-read each cited anchor of `findings.md` in the changed files;
   - fix the packet before dispatch, through `contracts.md`;
   - rerun `sh proposals/0015-cutover-swarm/validate.sh`.

   Abort if a path this packet owns is dirty, other than
   `proposals/`. Run `sh proposals/0015-cutover-swarm/dispatch/assemble.sh`
   and then `validate.sh`; dispatch nothing while it fails.
2. **Apply the hubs and dispatch.** Apply `contracts.md` C1 to the hub
   files yourself first (`work-units.md`, "At dispatch"), so that every
   lane's names have one written home. Dispatch all 23 lanes at once
   when CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS is at least 23. Where the
   environment caps concurrency lower, say so with the number, dispatch
   that many, and start the next lane, in the order U01 to U23, as each
   returns; never serialize silently. Each lane's entire prompt is the
   full text of its assembled `dispatch/U??-*.md`; do not summarise or
   trim a dispatch.
   - Do not add a 24th lane, a "foundation" lane or a wave.
   - Lanes share one checkout and write disjoint files. No lane uses a
     worktree.
3. **Concurrent coordinator work** while lanes run: unit lists, contract
   disputes, `T/spec`, the docs (`work-units.md`). A difference a lane
   reports at the pin (R44) is a contract dispute: take the named
   fallback into `contracts.md` and re-dispatch the lane.
4. **Audit each handoff** against its dispatch: the permitted outcome,
   the exclusive writes, NOT TO DO and the Delete list. Reject extras
   through the same lane. A contract conflict is fixed in `contracts.md`
   by you and re-dispatched to the affected lane; lanes never negotiate.
5. **Integrate**, per `work-units.md` "Integration", steps 1 to 6.
   Repairs go through the owning lane, then rerun. The first `make
   build` of the new layout is the one serialization.
6. **Commit** to `main` in a few commits, each staging only this
   packet's paths, once the suites are green on arm64 macOS. Record
   x86_64 Linux as NotRun in the commit message and in HANDOFF.md, and
   run it next (owner decision 5).
7. **Qualify**, per README "Qualification". Record what ran. "Linux:
   NotRun" is written as such, never as green.
8. **Report:**
   - what ran, and what was `NotRun`;
   - the concurrency the environment allowed, and the order lanes
     started in if it was below 23;
   - the sensitivity results;
   - the measurements, each a number against its record;
   - the programs newly refused for an erased value in a runtime
     position, by name and count;
   - the unresolved seams, those the rulings name (R13's owned verify,
     R43's arrays in `Holds`, R47's serial residue) included;
   - which stages of 0014 are done.

   Never call the packet proof that the compiler is correct.

Binding rules for you:

- You edit the packet and the hubs only.
- You never write a lane's file.
- You never widen scope to fix an adjacent bug you noticed.
- You resolve a contract contradiction in `contracts.md` and re-dispatch
  the affected lane, instead of letting two lanes negotiate.
