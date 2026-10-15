---
name: compile-swarm-proposal
description: Prepare, replace or harden a proposal folder, fanout packet or swarm handoff. Use only when the user explicitly invokes or requests this skill; not permission to launch agents or implement the proposal.
disable-model-invocation: true
---

# Compile architecture into executable work

The deliverable is a finite implementation contract, not a collection of aspirations. A worker with limited context must be able to implement its assigned scope without inventing architecture. The coordinator must be able to reject a superficial completion without rereading every conversation.

Treat the packet like a compiler output:

`intent → invariants → source counterexamples → selected representations → owned work units → integrated discriminators → qualified handoff`

Deliver a small final system through genuinely broad parallel work, not inflated task counts or reporting. Use the user's requested folder and process constraints, and the repository's own instructions (its agent guide, contribution rules and verification policy). Do not import this skill's examples as new product requirements.

## Swarm means at least twelve concurrent execution workers

In this skill, a **swarm** is **at least 12 execution agents working concurrently**, not counting the orchestrator. This is a scheduling requirement, not a claim that twelve is an empirically optimal number. None of these meets it:

- twelve tasks completed one after another;
- twelve agents in total over the whole run;
- twelve agents all waiting on one prerequisite.

Design the proposal for that execution profile from the outset:

- Every lane starts at dispatch, all at once. There is no serial foundation cut, no prerequisite wave and no ready queue.
- The packet fixes every shared declaration by name and shape. Consumers write against the packet while the declaration's owner writes the file.
- The final integration and qualification tail may naturally narrow.
- Do not manufacture work, empty reviewers, duplicate ownership or needless files to keep up a headcount.

The target orchestrator must support this concurrency. If the current environment cannot run twelve workers, report the capacity mismatch and prepare the handoff for an environment that can. Do not silently redefine a swarm as three or four workers, or evade tool limits. If the real task cannot yield twelve useful lanes even after representation and ownership analysis, say so explicitly rather than padding the proposal. A request to edit this skill or write a proposal does not by itself authorize launching the swarm.

## Compile for cheap, instruction-following workers

Assume execution workers are deliberately inexpensive. They are good at bounded edits and literal instructions. They are unreliable at:

- recovering unstated architecture;
- choosing abstractions;
- resolving trade-offs across layers;
- noticing consumers nobody named.

The architect or orchestrator makes those decisions **before dispatch** and owns integration judgment. Do not make a lane depend on its worker rediscovering the design.

Give every lane a self-contained dispatch prompt containing:

- **End state:** the exact end state, the fixed representation, and its constructor and transition rules.
- **Where to work:** current paths and symbols to read, exclusive write paths, explicit exclusions, and the named consumer adaptations.
- **Recipe:** the implementation recipe at the level of actual modules, types and callers, including the relevant boundary, failure, retry and cleanup behavior.
- **Contracts:** the exact input and output contracts, fixed in the packet, and who receives each output.
- **Deletions and limits:** the deletion list, forbidden half-fixes, and concrete examples of correct and incorrect behavior.
- **Verification:** what to verify, when it may run, and the evidence required for acceptance, under the repository's verification policy (see "Verification, commits and resumption").
- **Escalation:** report the conflicting evidence and the proposed contract change to the coordinator. Do not invent a shim, weaken an invariant, expand write ownership, or choose another architecture independently.

Required contract excerpts may be quoted verbatim for the worker's context, labelled with their canonical source; they do not become a second editable authority. Link only the relevant supporting sections. "Read the whole repo and make it elegant", "refactor as appropriate" and "wire it up" are not executable lane instructions.

Workers may solve local implementation details within the frozen contract. They may not:

- declare a missing consumer optional;
- replace an acceptance condition with an easier one;
- introduce an authoritative duplicate to avoid coordination.

The orchestrator reviews the delivered source against the exact lane contract, not against the confidence or polish of the completion message.

## Make every lane's scope ceiling explicit

An exclusive write directory grants file ownership, not permission to improve everything inside it. Every initial and repair dispatch must contain three concrete bounds:

- **Permitted outcome:** the finite behavior, named outputs and necessary consumer adaptations this lane must deliver. Separate mandatory outcomes from optional evidence and later work.
- **NOT TO DO:** lane-specific exclusions naming the tempting adjacent features, data populations, mechanisms and shared files the lane must not add or change. A generic "stay in scope" sentence is not enough. Screenshots, earlier brainstorming and retained future requirements are context, not authorization to implement every visible control or idea.
- **Stop and return:** the completed deliverable and checks that end the assignment, and the exact missing operand or ownership conflict to return to the coordinator. Report an unresolved seam and keep working on everything else. Finishing does not authorize roaming into a sibling lane or polishing unrelated code.

Before adding a file, dependency, abstraction, source family, configuration change or incidental repair, the worker must be able to name two things:

1. the required outcome that fails without it;
2. the write ownership that grants it.

If either is missing, the worker returns the concrete proposal to the coordinator without implementing it. This is a scope check, not a new approval process or reporting system: use the existing handoff and the existing owner authorization for necessary in-scope integration. Local implementation choices remain the worker's responsibility.

The coordinator audits delivered diffs against both the permitted outcome and the explicit exclusions:

- Passing checks does not excuse extra features.
- Correct attributable overreach through its current writer before integration, and preserve unrelated work.
- Scope takes precedence over the desired worker count. Unavailable or finished lanes do not justify optional projects, duplicate implementations or busywork to keep the swarm busy.

## Exact scope; duplication is cheaper than false dependencies

The proposal is a scope ceiling, not an invitation to improve adjacent systems. Include these binding rules in the proposal, and append them to **every worker dispatch**, repair dispatches included:

1. Do exactly the assigned obligations and the necessary consumer adaptations within the exclusive write set. Every changed hunk, new file, dependency or abstraction must map to a named obligation. If the contract cannot be completed within those writes, report the exact missing seam; do not silently widen scope.
2. Add no unsolicited features, frameworks, generic helpers, configuration knobs, retries, telemetry, documentation, dependencies, formatting sweeps or neighboring cleanup. Elegance means completing the selected representation and deleting its named predecessor, not opening another project.
3. Do not be afraid to duplicate reading, investigation, reasoning or small, packet-local, non-authoritative glue. Do not wait for a sibling just to avoid that duplication, and do not introduce a shared helper that creates a false dependency. Reuse repairs that have already landed; duplicated investigation does not mean rebuilding working mechanisms.
4. Authoritative schemas, vocabularies, identities and business facts still have exactly one owner. Never duplicate them, create competing implementations or write concurrently to another owner's file. Duplicate effort is allowed; duplicate authority and overlapping writes are not.
5. Finish the bounded deliverable, report changed paths against obligations, the checks actually run and any unresolved seams, then return control. Do not roam into another packet, manufacture work to keep up the headcount, or build a reporting or coordination platform.
6. User steering goes through the coordinator, into the affected packet only. The coordinator corrects an architectural contradiction in the canonical contract and re-dispatches the affected lane. No lane stops for it.

At integration, audit scope as well as correctness:

- Reject unrequested additions, and remove only the swarm's attributable extras, through their current writer. Preserve unrelated concurrent work.
- A proposed improvement outside the contract is at most a short note to the owner, never an implementation.
- Keep handoffs compact. No per-wave journals, slop ledgers or speculative backlog are needed.

## Establish the engagement contract

Before changing anything, distinguish **review or proposal**, **implementation** and **qualification**:

- A request for an implementation prompt does not authorize implementing it.
- A review does not authorize interrupting another worker, editing sibling repositories, publishing, or touching live data.

Record:

- the actual checkout and branch;
- dirty tracked and untracked work;
- the relevant repository instructions;
- current writer ownership;
- the time at which you observed the source.

An old commit or an agent's summary is not the current implementation. If code is moving, use a copy of the source outside the repo where useful, and label it a best-effort snapshot rather than an atomic Git revision. Recheck important anchors against the live tree before handoff, and qualify any findings that have changed.

Separate the user's choices from the engineer's. State explicitly:

- API and format compatibility;
- supported targets;
- verification timing;
- commit and push policy;
- allowed deletions;
- release prerequisites.

If the user permits breaking changes, distinguish removing obsolete code from destroying real user data.

## Read for mechanisms, not reassuring names

For each important claim, trace a full chain from caller to owner:

- Authoring or input → parse or compile → admitted internal value → execution → persistence or publication → decoding or delivery → cleanup.
- Allocation → admission → capacity growth → transfer → retention → reclamation.
- Authoritative request → dispatch → uncertainty → evidence → local application → response or finalization.
- An optimization's premise → its witness constructor → the actual optimized branch → the fallback or reference comparison.

Read the callers, constructors, consumers, failure paths and retained state. Names can reassure without being true:

- A new type with no production users is not an implementation.
- A counter that reports memory is not the owner that bounds it.
- A recorded phase is not proof if a later conversion drops it.
- Two independent fields can recreate the invalid combinations a new enum was meant to remove.

Credit genuine improvements, and do not prescribe rebuilding components that are already repaired. Classify each observation as one of:

- a defect confirmed in the source;
- structural incompleteness;
- an integration mismatch;
- unverified behavior;
- an optional simplification.

Do not claim a reproduction without running it, and do not infer that a bug is absent because the code compiles.

## Settle external capabilities before gating on them

A gate that says "investigate whether the provider supports X" is an architecture-shaped TODO, not a decision. Before writing any capability gate, read the vendor's current primary documentation and the installed SDK source, and record the answer: either the exact event, field or API that supplies the fact, or the exact statement that no such surface exists. If the API settles the question, the packet decides. Only a genuine product ruling may remain open, phrased as the exact choice the owner must make and the consequence of each option.

Keep a **constructor provenance table**. Every admitted value the design depends on names the source event or owned operation that constructs it: which message, which field, which clock. A value with no constructor is a defect in the design, not a task for a worker. Distinguish the different things a value can prove: syntactic validity, an authenticated claim, source association, processing acknowledgment, generated output, delivery, physical effect, and closure. For each value, say which of these it proves and which it cannot.

When the required fact does not exist, change the unit of work before adding a signal. Ask whether a different coordinate makes the missing fact unnecessary: the provider's own timeline instead of arrival order, a run of consecutive steps instead of a single step, an interval instead of a point. A timer, a model-behavior signal, or an "unknown" state that leaves the user stuck is not a repair.

Verify the tree you are reading:

- Record HEAD and status at the start and at the end, and re-diff every cited anchor if HEAD moves.
- List concurrent design documents (sibling proposal folders, plans, packets) that bear on the same code. Where two disagree, do not resolve it silently: name the disagreement, both sides' evidence, and which document the owner must choose.
- Name concurrent modules that consume the seams you change as protected consumers. Breakage there is routed to the coordinator, never fixed by a lane.

## Select the representation before splitting the work

For every architectural commitment, answer:

1. Which invalid state, repeated interpretation or ownership split causes the problem?
2. Which representation carries the checked fact or the ownership from then on?
3. Where is that representation constructed, and who alone can construct it?
4. Which consumers use it, including error, retry, spill and cleanup paths?
5. What old representation or mechanism disappears in the same change?
6. Which essential distinctions must remain?

Choose the smallest representation that closes the real counterexamples. A concrete struct or enum often beats a generic policy framework. Keep hot loops compact and batch work at the boundary. Do not turn a desire for fewer branches into per-item boxing, virtual dispatch, extra concurrency primitives, or repeated shape discovery.

Do not flatten semantically different cases just to reduce line count. These may be necessary:

- independent reference implementations;
- exact collision verification;
- parsing at a trust boundary;
- separating resource errors from domain errors;
- genuinely different publication points.

Physical strategies can share a contract without being legacy twins.

Write each binding decision once. Findings supply evidence, interface contracts specify seams, and work units reference both. Avoid four subtly different normative descriptions of the same outcome or budget.

**Library first.** Before selecting any mechanism (transport, retry, state, receipts, schema transform, runtime, UI binding, storage):

- inventory the installed platform library's modules and any agent documentation it ships;
- verify the exact signatures you will cite;
- write a table mapping every responsibility to the module that owns it and the invention that disappears.

A mechanism with no library owner needs a sentence saying why none fits. An adoption that changes a recorded ruling, a wire format or the dependency set is an owner decision, listed with its exact trade-off, not silently taken or silently skipped.

**A library supplies a mechanism, never a fact.** Before wrapping a value in a library type, ask whether the system actually possesses the fact the type asserts: an association, a completion, a bound. For example:

- a promise or deferred resolving does not prove that a remote used the context it acknowledged;
- a bounded queue of values does not bound bytes;
- an interruptible task does not bound spend.

State such facts as observations with explicit uncertainty, and route the acting policy to an owner gate.

**No lane waits** on a gate, a producer or a sibling. A lane that would wait is a packet defect: fix the missing contract in the packet so both sides write against it. Name the integration lane as such. If honest lanes fall short of the required concurrency, say so; never split placeholder jobs to reach the number.

**Identities are derived, not minted.** Prefer the provider's or the codebase's existing identifiers: command IDs, event IDs, session-timeline coordinates, existing branded IDs. A new nominal type needs a sole constructor, a consumer that could not work without it, and a reason an existing identity cannot carry the fact. Otherwise it is a renaming, and it is deleted.

**Every number needs authority.** This includes retries, deadlines, poll intervals, caps and budgets:

- A number cites a published configurable default, a measurement, or a stated derivation; otherwise it is debt and labelled as such.
- A retry count is a literal without authority, and so is "zero retries" chosen as protocol. Recurrence is a schedule (exponential backoff with jitter), bounded by interruption of the owning scope: revocation, supersession or the end of the attempt.
- A deadline that stands in for a missing fact is deleted, not retuned. The state it tried to end becomes an explicit arm, such as `pending` until the real terminal event, which the UI shows.
- Never delete an existing protective capacity cap without authority; keep it, labelled as debt.

**Decisions live in the packet, not in a lane.** A sentence of the form "Ux declares/decides/freezes X", where X is not already fixed in the architecture document, is a defect: fix X in the packet.

## Make findings implementable

A useful finding contains:

| Field | Required content |
| --- | --- |
| Evidence | Current path, named symbol, relevant line and observed source identity |
| Counterexample | Small concrete input or event schedule and the wrong observable result |
| Root cause | The representation or ownership fact that was lost |
| Selected correction | One chosen contract, not several designs left to the worker |
| Deletion | Exact obsolete path, API, adapter, flag, helper or duplicate interpretation |
| Discriminator | What must fail against the defective behavior and pass after correction |
| Ownership | One implementing unit, seam producers/consumers and integrating owner |
| Confidence | Source observation versus executed evidence and remaining uncertainty |

Use stable local IDs for cross-references where useful, but do not create a new issue namespace for each wave. Merge several symptoms that share one root correction, and keep independent counterexamples apart. Carry inherited requirements forward by explicit mapping, not by copying all the old reports or blindly keeping every old check.

## Partition by exclusive writes and complete behavior

An accountability domain is not a serial phase. Core, adapters, SDKs and tooling begin together, because the packet already states every shared contract:

- The packet fixes each declaration or schema by name, fields and semantics before dispatch.
- The owner writes it while consumers implement against the packet text. Nobody waits for the file to land.
- Integration checks the real composed path, not just matching signatures.
- Verification runs according to the user's timing policy.

A seam the packet has not fixed is the coordinator's to decide in the packet, never a reason for lanes to wait on each other. Do not freeze an incorrect interface just to avoid coordination.

Assign one writer per implementation file, so patches cannot conflict semantically:

- This is ownership, not a lock on the packet documents. The coordinator and the reviewer edit the packet at the same time with targeted edits, re-reading after a failed match, and neither pauses the other.
- Prefix ownership must name its exclusions: nested modules, generated files, manifests, lock files, and export or ABI hubs.
- If separate worktrees are used, assign semantic ownership anyway: separate checkouts do not prevent conflicting patches.
- Use whatever transport fits the user's commit policy. Do not invent worker commits when interim commits are forbidden.

Prove the twelve-worker frontier in a table in the packet: name the twelve or more lanes, their disjoint write sets, and the packet contracts each consumes. A list of twelve labels is not enough if shared files or hidden dependencies make them serial. Split broad accountability domains into concrete producer, consumer, lifecycle, adapter or tooling lanes, each with a substantial owned outcome, and keep the final integration owner separate.

The coordinator has implementation and review work of its own: shared hubs, contract disputes, invariants that cross layers, integration, and final qualification. It is not merely a dispatcher relaying completion messages.

## Work-unit template

Use a compact block or a standalone Markdown chapter for each substantial unit. Avoid one file per trivial change.

```markdown
## Ux — Outcome-oriented title

Owner / exclusive writes: actual paths; explicit exclusions.
Read first: authoritative contract sections, findings, selected source symbols.
Permitted outcome / scope ceiling: finite externally observable behavior and
named consumer adaptations; separate mandatory, optional and later obligations.
Fixed decisions: selected types, transitions and invariants; no open alternatives.
Inputs: the packet contracts it consumes (never a sibling's body).
Outputs: actual declaration/schema and named consumer units.

Implement:
- Selected representation and its constructor/ownership rule.
- Real production paths and failure/cleanup cases to adapt.
- Specific performance-sensitive invariants to preserve.

Delete: named replaced APIs, wrappers, modes, helpers and their consumers.
NOT TO DO: specific adjacent features, populations, mechanisms and shared files
excluded from this lane, as well as tempting incomplete implementations.
Stop and return: exact completed deliverable/checks; missing operands or ownership
conflicts reported without stopping other work. No self-assigned follow-on work.

Acceptance:
- Exact input/event schedule → exact outcome/resource assertion.
- Required production/native/backend path; independent oracle if applicable.
- Boundary/overflow/interruption variant where relevant.
- Source/deletion review condition not established by compilation.

Escalate if: a named contract or ownership boundary conflicts with live source;
report exact evidence to the coordinator instead of redesigning independently.
Dispatch prompt: complete task instructions usable without prior conversation;
include the relevant fixed contracts, forbidden shortcuts and the exact-scope /
allowed-duplication rules above, including for later repair dispatches.
Handoff: changed paths; contracts supplied; consumer adaptations; permitted
verification work authored; verification actually run or NotRun; unresolved seams.
```

A unit is too vague if a cheap worker must rediscover its counterexample, choose a product contract, infer which files it may edit, or guess how a shared seam is used. It is too granular if its only outcome is a declaration or a renamed helper, with no owned consumer integration. Refine the decomposition until there are at least twelve useful concurrent lanes: not twelve vague subsystem essays, and not hundreds of microtasks.

## Strict acceptance for fast, shallow implementations

Use a conjunction, not a checklist of substitutes:

`implemented producer ∧ adapted consumers ∧ deleted predecessor ∧ discriminating evidence ∧ bounded scope ∧ integrated qualification`

Explicitly reject the failure modes seen in swarm refactors:

| Superficial result | Required acceptance instead |
| --- | --- |
| A charged-buffer type exists | Its production growth refuses before allocation, and retained capacity cannot outlive its charge |
| A guard can be split from the payload | Only borrowing or whole-owner transfer is available; an ordinary extraction cannot release the charge early |
| An outcome gains a phase field | Impossible outcome/phase combinations cannot be constructed internally; all post-dispatch failures preserve evidence |
| An enum adds a disk-backed arm | Every relevant downstream consumer accepts it without whole-memory conversion; small inputs retain the intended fast path |
| A cache gains a generation counter | Actual retained images/tokens carry generation ownership; eviction and old readers cannot alias |
| A hand-built input yields a desired result | A real producer is driven through the triggering fault on the real path; the public consumer preserves that result |
| An import succeeds | Native loading is absent under an isolated, intentionally unavailable-native setup when purity is the claim |
| A manifest contains required IDs | Exact source/artifact/backend evidence validates; empty, stale, malformed or duplicate evidence refuses |
| All workers say complete | The coordinator traces the composed source and closes every unresolved seam |

For each important fix, describe a **tempting partial solution** and why its acceptance case rejects it. This helps weaker implementers more than repeatedly saying "be thorough".

Keep these four kinds of evidence separate; none substitutes for another:

- source review;
- behavioral verification;
- performance qualification;
- platform or backend evidence.

Require observable invariants, not preferred wording or incidental private function names. Avoid universal timing gates on shared hosts: use deterministic budgets and counters for ordinary regressions, and controlled measurements for performance claims.

A discriminator must actually discriminate:

- A type discriminates when the known defective construction no longer compiles or admits.
- A test or observation discriminates when the known defect was visible before the change and is absent after it, on the path the repository's verification policy names.
- Do not keep a legacy production engine just to show the defect.

## Remove code by responsibility, not quota

Measure how code is distributed before asserting that most of it is pointless. Distinguish production paths, examples, benchmark machinery and tooling, and state the limits of the count.

For each deletion candidate, identify its current consumer, the behavior it supplies, and the surviving owner of that behavior. Good targets:

- unused wrappers;
- redundant interpretive layers;
- compatibility twins;
- opaque status machinery;
- stale token or wording gates;
- harnesses the repository's verification policy does not call for.

A large independent oracle or a necessary fault schedule is not slop just because it is long.

Do not make source look simpler by hiding complexity in flags, config, a generic framework, ignored failures, or another folder. Do not delete a mismatching oracle to make a check pass, and preserve size where the behavior depends on scale.

## Verification, commits and resumption

**Follow the repository's verification policy.** It decides what counts as evidence: test suites, type-level guarantees, static analysis, staging or production observation, or a mix. Where the repository prefers making failures impossible through types, sole constructors and runtime admission, say so in each acceptance condition. Where it uses tests, each must discriminate the named defect.

Use the user's chosen verification cadence. If requested, explicitly prohibit builds, typechecks and package hooks during the swarm, and explain that the barrier is reviewed source completeness, not an earlier green build. Final verification is a phase with repairs and reruns, not one attempt.

No workstream may declare an open mandatory seam "deferred" on its own. Mark it incomplete and keep an owner. Source done, integrated, executed and qualified are different states. One short live status note may help. Avoid per-wave journals, empty evidence dumps, and percentages computed from task labels.

On resumption:

- Inspect the source, the dirty changes and that note.
- Assign the exact remaining owned work. Do not repeat a whole architectural wave because a worker stopped responding.
- Stop uncontrolled edits before final measurement.
- Rerun evidence affected by changed inputs, and finish the required final matrix.

If exactly one final commit is required, do not create a circular dependency on its not-yet-existing hash. Reuse an existing mechanism to identify the captured inputs before committing. Where a content digest is needed, bind:

- paths;
- file kinds and modes;
- contents or symlink targets;
- intended additions and deletions;
- lock files and generated inputs;
- permanent contracts.

Validate membership, not just a caller-supplied list, and verify the staged or committed inputs against the qualified candidate afterwards. Exclude only declared non-input outputs, and avoid evidence that hashes itself. This is a small provenance requirement, not permission to build a platform.

Missing credentials, hardware or required artifacts mean unqualified, not green. Finish the independent safe work, then report the precise prerequisite. Committing, pushing, publishing and live-data actions follow the explicit engagement contract, not an assumed meaning of "finish".

## Packet shape

Use the requested packet location.

A swarm packet adds:

- **Work units:** the `Ux` template above, with the twelve-lane ready frontier proved in a table, and an `ownership.json` of exclusive write sets.
- **Orchestrator prompt:** a short executable instruction pointing at the complete packet.

A large packet may separate semantics, performance and subsystem chapters; a small one need not. Raw execution output and CI artifacts stay outside the packet.

Each finding has exactly one accountable lane in `ownership.json`. Supporting producers and consumers are named inside the row and the dispatch, never as additional owners. A finding listed under several lanes has no owner.

Assemble every dispatch as one self-contained file:

- the lane body;
- a common-obligations block (the numbers rule, the verification policy, preserving concurrent work, the handoff shape);
- the six binding rules, verbatim.

Generate the assembly from parts so the shared text cannot drift. Do not link to a shared rules file in place of the text.

## Final packet review

Before handoff, walk at least three work units as if each were the worker's only context: one core or ownership lane, one cross-network lane, and one custody or telemetry lane. Each must resolve:

- what to build;
- what not to build;
- where to write;
- which seam to request;
- how acceptance fails;
- what to delete.

Write down every operand a literal worker would have to guess, and fix the dispatch, not the worker.

Run a document validation script and record its numbers in the packet. It checks:

- every local link resolves;
- every finding ID appears exactly once in the finding map, with the owner column equal to `ownership.json`;
- no two writers intersect, exactly or by prefix, the coordinator included;
- every dispatch contains the permitted outcome, exclusive writes, implement, delete, NOT TO DO, acceptance, stop-and-return, the common obligations, and exactly six binding rules;
- each dispatch's mandatory findings equal its ownership entry and name every owned path;
- no lane waits on a foundation, gate or sibling;
- no retired mechanism (a deleted file, withdrawn storage, replaced signal, retired literal) is still prescribed anywhere.

A packet that claims these properties without running the script has not checked them.

Run an adversarial review concurrently with packet authoring, never as a gate on it:

- Prefer a different model.
- Its prompt names the load-bearing claims to attack, requires a concrete schedule or data example for each criticism, grants write access to the packet for corrections the evidence determines, and forbids implementation.
- The reviewer edits the packet in place while the coordinator keeps editing.
- It leaves one review file with one of three verdicts: executable as specified; executable after named concrete prerequisites; or materially under-specified.
- The coordinator folds findings in as they arrive, without waiting for the review to finish.
- Keep the packet's claims and the owner's decisions separate: a table of disagreements with both sides' evidence, never a verdict the reviewer had no authority to give.

Label evidence by time: historical incident, confirmed in the source at commit X, or current at the end of the review. Re-query current telemetry at the end of the review, not only at the start, and say whether the counterexample recurred.

Document-only checks are not product qualification. Return a short verdict, the link to the packet and prompt, the decisive remaining risks, and what was actually checked. Never describe a proposal as proof of release readiness, or as a guarantee that every bug has been found.
