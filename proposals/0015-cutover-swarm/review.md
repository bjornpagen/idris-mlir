# Adversarial review: the cutover swarm

## Verdict: pending

Review against `main` at 25890d32, concurrent with the packet's
authoring. The reviewer edits this file and, for corrections the
evidence determines, `contracts.md` and `dispatch/parts/`, while the
coordinator keeps editing. Implementation is forbidden to the reviewer.

## Reviewer prompt

```
You review proposals/0015-cutover-swarm/ in github.com/bjornpagen/idris-mlir
at 25890d32. Read README.md, contracts.md, findings.md, work-units.md,
ownership.json and every dispatch/parts/U??-*.md. Attack these claims,
each with a concrete schedule, input or source excerpt:

1. That every rewrite can be a function pass under a nested pass manager
   (C1.3): name a pass whose rewrite reads or writes another function.
2. That linearity and the owned stage can be verified per function on
   idr.func's verifier without the module (C4).
3. That the erased grade can be deleted from the dialect (C6.1, C10):
   name a term the frontend cannot emit without an erased value.
4. That defunctionalization fits dialect conversion (C2.4): name a slot
   kind or a move between keys the TypeConverter cannot express.
5. That upstream's CompositeFixedPointPass converges with sccp in the
   round at the pinned LLVM with the carried patch (C3.1).
6. That the 23 lanes' write sets are disjoint and that no lane waits:
   name a file two lanes must both change, or a declaration a lane needs
   that contracts.md does not fix.
7. That the handoff diet (C6) does not change any program's behaviour.
8. That the Tracy layer (C8) costs nothing in the non-profile presets.

Write your findings here under "Findings" with the verdict "executable
as specified", "executable after named concrete prerequisites" or
"materially under-specified". Where the evidence determines a
correction, edit contracts.md or the dispatch part in place and list the
edit under "Packet edits made by the reviewer". Where you disagree with
a ruling the owner made (contracts.md C10, README "Rulings", "Owner
decisions"), add a row to "Disagreements for the owner" with both
sides' evidence; do not change the ruling. Do not implement anything.
Label every piece of evidence as read at 25890d32 or as current at the
end of your review.
```

## Packet edits made by the reviewer

(none yet)

## Findings

(in progress)

## Disagreements for the owner

| Topic | The packet's position | The reviewer's position | Evidence |
|---|---|---|---|

## What I checked, and what I did not
