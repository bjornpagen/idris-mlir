<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: the lifetime token at run time

**Status (2026-10-21):** research and design under D63; nothing here is
built, run or settled. The owner asked for the question pushed to its
ceiling before ruling ("the only thing up for debate is a better
representation for lifetimes, but it has to be weighed against the costs
of what mlir can do"), then ruled D63: a lifetime is an SSA value, a token
`idr.lifetime` yields and calls pass, "where a function allocates into the
lifetime, the token is the run-time arena handle; everywhere else it is
erased at the lowering" (`proposals/0000-mlir-native.md:1029-1053`). This
file is the ceiling of that token: what it lowers to, per lifetime, how
whole-program analysis decides, and what is still research. Which op or
type holds each fact named here is the owner's (AGENTS.md); where this
file names one, it is a recommendation.

**Grounds**: *read* (path:line at HEAD `e96bb991`, or a source named),
*recalled* (not in `sources/`), *conjecture*, *derivation* (follows from
the cited facts by the stated argument), *decision* (a ruling Dn or a
coordinator decision Cn). Nothing was built, run or measured.

**Read first, in full**: the representation-first skill, AGENTS.md,
`proposals/0000-mlir-native.md` (through D67), `audits/p0/verify/`
L05, L04 (layout classes, I2, Q1), L18 (specialization, the label solve),
L14, L10, L20, `review.md` (claims 1 and 2), L06's OQ1. Outside: the
MLKit manual (Tofte, Birkedal, Elsman, Hallenberg, Olesen, Sestoft,
*Programming with Regions in the MLKit*, revised for 4.7.16,
elsman.com/pdf/mlkit-4.7.16.pdf, text extracted and read); the OxCaml
stack-allocation reference (oxcaml.org/documentation/stack-allocation/reference/,
read); Gibbon's region passes (`sources/code/gibbon/`, read).

## 1. The answer

A lifetime never needs a run-time *identity*: which instance a put goes
to is always fixed by the program, once the analyses of §4 have run
(§2, *derivation*). What can need a run-time value is the *allocation
state* of an unbounded lifetime: where its next cell goes. So the token
lowers to one of five things, decided per lifetime site and per token
parameter by whole-program analysis over the program graph:

| class | when (decided by §4) | the token lowers to | cost at run time |
| --- | --- | --- | --- |
| 1. nothing | no allocation into it, anywhere its token reaches | no value; dropped from every signature | none |
| 2. a constant | one instance per shard, and every put function it reaches is reached by it alone | a thread-local home at a link-time offset | a thread-pointer read per function that puts; the bump in memory between calls |
| 3. a frame-relative address | the bytes put into it are a static total (multiplicity one per site per instance) | a block in the opener's frame, cells at constant offsets; a callee gets its sub-block's address, in only | none in the opener; one register at a call that puts |
| 4. a push and pop on the lifetime stack | unbounded, and nothing in its extent puts into an older lifetime on the same stack | the computation's lifetime-stack top, threaded as a linear value beside D31's frame top | open keeps the top as a mark; close resets it; one register through functions that use the stack |
| 5. a register-passed pointer | unbounded, and the stack's discipline fails, or the lifetime leaves its computation | its own chunk chain; the cursor in and out of each put call in a register | one register in and out per put call; a chunk from the shard's pool on first allocation |

The pinnacle is the table, not one row: every lifetime takes the
cheapest class its analyses certify, and the token is a real run-time
pointer only in class 5. Classes 3 to 5 share one cursor protocol (§3.6)
and one runtime type with D31's frame stacks (§3.7). Specialization is
only by the *mode* a callee sees (§4.7), never by lifetime, and ends by
construction.

## 2. What is static, and what is not

**Identity is static.** A put names its lifetime by a token, and the
token is an SSA operand (D63). Which `idr.lifetime` site a token comes
from, at every put and every call, is a fact of the closed program:
defunctionalization makes every call direct (D30), so a token parameter's
sources are a set the whole program fixes, computed callers first over
the program graph (§4.5). So nothing at run time is ever needed to say
*which* lifetime; D10 forbids paying for it, and nothing here does.

**The instance a put reaches is the newest one, unless the program says
otherwise.** A site inside a recursion has many live instances, one per
level. *Claim* (*derivation*): a put can reach an instance other than the
newest open instance on its stack only if some op or call inside the
younger lifetime's extent puts into the older lifetime's token. Proof:
let O be older and Y younger, both open, on one stack, and let a put
reach O while Y is open. Y is open, so the put runs inside Y's extent
(lifetimes are lexical: an instance is open exactly while its region
runs). The put names O by a token, so O's token is in scope at the put:
either the allocating op is inside Y's region with O's token as operand,
or a call inside Y's region passes O's token on, down to the put. Both
are visible in Y's region, given each callee's put set (§4.1). ∎

So the stack discipline (every put at the top) is a local check per
extent (§4.4), not a global property. L05's monomorphic recursion
(`L05-lifetimes.md:423-425`, *read*) made it always true; under D63 a
token is a value, so a recursive call may pass a fresh token, and
MLKit calls that "vital for achieving good memory management in
connection with recursion" (manual §6.4, *read*). Where the check fails,
class 5 keeps the program correct; research R2 (§9) keeps it on stacks.

**Allocation state is dynamic.** An unbounded lifetime's next free byte
depends on how much the program has put, which no compiler knows. It is a
value of the computation, and the cheapest home for a dynamic value that
changes on every allocation is a register (§3.6). That is the only thing
classes 4 and 5 carry at run time.

**Which computation is dynamic.** Under 0007 several tasks interleave on
one shard. A per-thread home for allocation state breaks there, as a
per-thread frame top does (`L20-qtt-end-to-end.md:743-760`, I10, *read*):
two tasks open the same site, wait, and resume over each other's cells.
So allocation state lives in SSA values (spilled into a task frame at a
wait like any live value) or in the computation's own record, never in a
slot two tasks share, except for a lifetime no task can reach (class 2's
condition).

## 3. The five lowerings

### 3.1 Nothing

- *When*: the token's put set is empty: no allocating op takes it, and
  every call that receives it has the parameter outside its put set
  (§4.1). This is every view-only lifetime: `lookup` returning a view of
  its argument's tree (D39's example).
- *Lowering*: the token's type converts to no value. MLIR's dialect
  conversion supports it: a 1-N conversion whose result list is empty
  removes the type, and a conversion that takes the `Value` may decide
  by the IR around it (`.toolchain/llvm-project/mlir/include/mlir/Transforms/DialectConversion.h:155-165`,
  *read*), so one token type lowers to nothing at a view-only parameter
  and to a pointer at a put parameter. The signature drops the argument
  (`remapInput`, `:99-101`, *read*). An `idr.lifetime` with no allocation
  lowers to its body.
- *Prior art*: MLKit's "dropping of regions", which the manual calls "the
  key reason why the MLKit takes the trouble to distinguish between put
  and get effects" (§6.3, *read*). L05 I2 and L06 I2 reach the same rule
  (*read*).

### 3.2 A compile-time constant

- *When*: (a) the site runs at most once per shard (its function is
  run once: §4.3); (b) no task, send or tail call can carry its token out
  of its computation (§4.3); (c) every put parameter its token reaches is
  reached by this site alone (§4.5). Then its allocation state has one
  home per shard for the whole run.
- *Lowering*: a thread-local global per such site, addressed through
  `llvm.intr.threadlocal.address`
  (`.toolchain/llvm-project/mlir/include/mlir/Dialect/LLVMIR/LLVMIntrinsicOps.td:929`,
  *read*); in our statically linked executables, local-exec TLS: the
  thread pointer plus a link-time offset (*recalled*). A put function
  reached only by that site loses the token parameter from its ABI and
  uses the constant. Within a function the cursor is loaded once and
  kept in a register until a call that may put into it (LLVM promotes a
  non-escaping cursor; *recalled*).
- *`static`*: under D63 `static` stays a grade constant, not a token
  (D63, `proposals/0000-mlir-native.md:1045-1046`, *read*), but its run-time
  allocations (a forced memo's value, L05 I9) lower exactly like this
  class: the shard's append-only static arena at a thread-local home.
  It is never closed, so tasks interleaving appends into it is harmless
  (*derivation*).
- *Against class 4*: where both are legal, the constant saves a register
  on every function between the opener and its puts, and pays a memory
  round trip of the cursor at each put call; the choice is the cost
  model's (D57), measured (M4).
- *Prior art*: Gibbon's "global" regions, "a lifetime equal to that of
  the whole program" (`sources/code/gibbon/gibbon-compiler/src/Gibbon/Passes/InferRegionScope.hs:35-40`,
  *read*).

### 3.3 A frame-relative address

- *When*: the total bytes put into one instance is a static number:
  every allocating site runs at most once per instance and is statically
  sized, and every callee given the token has a finite put total (§4.2).
  This is MLKit's finite region, multiplicity one ("Finite regions are
  always allocated on the runtime stack", manual §2.1, *read*), and
  L05's *count* proof (`L05-lifetimes.md:528`, *read*).
- *Lowering, in the opener*: one block of that many bytes in the frame,
  an entry-block `alloca` as `LowerCellStack` places slots today
  (`foreign/idr/lib/Conversion/Cells.cpp:76-101`, *read*); each cell at
  a constant offset assigned in program order. No cursor, no check, no
  register: the token is `sp + k`. D32's computed bound counts the block
  through code generation's frame sizes (`L10-tail-frames-stack.md:754-762`,
  *read*).
- *Lowering, at a call that puts*: the caller passes the address of the
  callee's sub-block, whose offset is static because the callee's put
  total is (§4.2). The callee writes its cells at constant offsets from
  it: in only, no check, nothing returned. This is the sret pointer LLVM
  already passes for a result in memory (`L10-tail-frames-stack.md:587-596`,
  *read*), and MLKit's region name for a finite region, "a pointer into
  the stack" (manual §2.1, *read*). Inlined, it is nothing.
- *When the extent spans a framed call* (the opener is on a cycle and
  D31/D32 split its continuation into a frame): the block is a group of
  fields of that frame kind, frame-relative on the frame stack. A frame
  kind already holds any statically sized value
  (`L10-tail-frames-stack.md:654-659`, *read*).
- *Close*: the drops of owned fields the block's cells hold, which are
  static; no memory action.

### 3.4 A push and pop on the lifetime stack

- *When*: unbounded, and the discipline holds (§4.4): nothing in the
  extent puts into another stack-class lifetime. Every per-iteration
  lifetime whose cells are unbounded falls here, and every per-level one
  whose recursion passes its outer tokens through unchanged.
- *The stack*: one per computation (the shard's main computation, or a
  task), a chunked bump stack, the runtime type of D31's frame stacks
  (§3.7). Its top is linear by type, so two allocations from one top are
  unwritable, and the linearity verifier checks it.
- *Lowering*: open keeps the current top as the mark (a value already
  live, so nothing is stored); each allocation bumps the top; close runs
  the drops of owned fields, then sets the top back to the mark, giving
  back chunks above the mark's chunk and keeping one spare. O(1) when the
  cells hold no owned field.
- *Threading*: the top is an SSA value threaded through the functions
  that use the stack, as L20 I10 threads the frame top
  (`L20-qtt-end-to-end.md:743-760`, *read*). A callee that puts into a
  stack-class token takes the top in and out; a callee that only opens
  and closes its own stack lifetimes takes it in only, as a base it gives
  back unchanged (every lifetime it opens is closed before it returns:
  lexical). At a computation's entry the top comes from its record; at a
  wait it is a live value, spilled into the task frame.
- *Per level*: a site inside a recursion that spans a framed call keeps
  its mark as one word of the D31 frame; level k+1 opens above level k
  and closes before level k resumes. This lifts L05's A6 for framed calls
  (`L05-lifetimes.md:533`, *read*), which sent every such cell to the
  counted heap; it is the case review.md says the most allocating code
  needs ("a parser, an evaluator, a tree builder, all on call cycles",
  `review.md:223-240`, *read*).
- *Per iteration*: a site inside a loop body resets to the same mark at
  each iteration's end: MLKit's `atbot` storage mode ("Reset region, then
  store value", manual §12.1, *read*), decided once per site instead of
  tested per allocation.
- *Prior art*: OxCaml's region stack: "a separately-allocated stack";
  "the runtime records the stack pointer when entering a new stack frame,
  and leaving that stack frame resets the stack pointer to that value";
  regions around function bodies and loop bodies; no run-time handle
  (OxCaml reference, *read*). OxCaml allows a put only into the top
  region (`exclave_` "can only appear at the tail position of a region",
  *read*); §4.4's check is that rule made a per-site decision with class
  5 as its fallback, instead of a refusal.

### 3.5 A register-passed pointer

- *When*: unbounded, and one of: the discipline fails (a put into an
  older stack-class token inside its extent, as in polymorphic
  recursion, or a function that keeps building its result in a caller's
  lifetime while its own temporary lifetime is open); its token leaves
  its computation (sent to a shard, captured by a task).
- *Memory*: its own chunk chain, the first chunk taken from the shard's
  pool on the first allocation, so a lifetime that allocates nothing
  touches nothing. MLKit's infinite region is the same shape: "Allocating
  an infinite region involves getting a page from the free list and
  pushing a region descriptor onto the runtime stack" (manual §2.1,
  *read*). Chunks lie in snmalloc's window aligned to 4 GiB, committed as
  used and counted by D36's limit (`L05-lifetimes.md:492-499`, *read*).
- *Lowering*: in the opener, a local cursor slot that LLVM promotes to
  registers; at a put call, the cursor goes in a register and comes back
  as an extra result. Gibbon does exactly this, and says why: after one
  call "might start using a new output chunk ... we have to thread these
  output regions, just like we do the output locations"
  (`sources/code/gibbon/gibbon-compiler/src/Gibbon/Passes/ThreadRegions2.hs:41-55`,
  *read*). Where the extra result does not fit the target's return
  registers (L10's through-memory rule, `L10-tail-frames-stack.md:591-595`,
  *read*), the callee takes a pointer to the opener's cursor slot instead,
  in only, loading at entry and storing before return: correct, slower,
  measured per target (M3).
- *Close*: the drop list (each store of an owned field appends its
  address, `L05-lifetimes.md:501-507`, *read*), then the chain back to
  the pool, O(chunks).
- *Shards*: a lifetime that moves whole is always this class; the send
  consumes its token and the receiver adopts the chain, freed there by
  snmalloc's remote free (`L05-lifetimes.md:543-550`, *read*).

### 3.6 The cursor protocol (classes 3 to 5)

- *One word*: chunks are a power of two in size and aligned to it, so a
  chunk's end is computed from the cursor, as D31's frame stack does
  (`L10-tail-frames-stack.md:705-711`, *read*); the cursor alone is the
  allocation state. Chunk headers link each chunk to the one before.
- *One check per run*: a straight-line run of allocations whose sizes sum
  to N takes one check that N bytes remain in the chunk, then N bytes of
  unchecked bumps, as GHC checks the heap once per block for the whole
  block's allocation (*recalled*). Cells in a lexical lifetime are
  statically sized (strings, big integers and arrays never are,
  `L05-lifetimes.md:530`, *read*), and the chunk size is at least the
  largest one, so no cell crosses a chunk (*derivation*).
- *The room is a fact*: after a check of N, or in class 3's block, the
  bytes left are static. Held as a refinement of the cursor's type, a
  callee given a cursor with enough room for its whole put total runs
  with no check at all (the room mode, §4.7). Its spelling is the
  lifetimes design's.
- *Header*: one word, count 0, info as today (`L05-lifetimes.md:93-103`,
  *read*), so a cell of a lifetime and a static cell share a layout.

### 3.7 One runtime type beside D31's frame stacks

D31's frame stack is a chunked bump stack with a one-register linear top,
one spare chunk, out-of-line grow and shrink, and memory exhaustion as
D23's ending (`L10-tail-frames-stack.md:705-719`, *read*). The lifetime
stack (class 4) and a chain (class 5) are the same structure: one runtime
type, three uses (frames; the computation's lifetime stack; a lifetime's
own chain). Each computation holds two stacks, frames and lifetimes,
whose tops are threaded the same way (L20 I10). They are two because a
put into a lifetime can happen while a framed callee's frames sit above
it, which a single stack could not take (*derivation*); R1 (§9) merges
them where that never happens.

## 4. The decision, per lifetime

Every analysis below is one pass over the program graph
(`L14-analyses.md:99-251`, *read*) or one walk per function; each ends by
construction (no count, no fixpoint that has to be reached), and none
keeps state sized by a product of two program quantities (L14's rule,
`:332-334`, *read*). They run in one decide step at counting's stage
(L14 §2.5's decide, apply, restructure, *read*), after the allocation step
has chosen which cells go into lifetimes (L05 §2.4.4) and before
idr-frames (which must know the marks, tops and blocks a frame holds,
`L10-tail-frames-stack.md:700-704`, *read*).

### 4.1 Put sets (class 1 or not)

Per function, one bit per token parameter: does the function, or a
callee it passes the token to, allocate into it. Callees first over the
SCCs, a monotone two-point marking: the solver layer's one template
(`L14-analyses.md:253-264`, *read*). O(functions + calls) bits. This is
MLKit's put effect; it is also a per-parameter fact of a function in the
shape of D61's per-parameter part of the row
(`proposals/0000-mlir-native.md:1010-1017`, *read*): derived from the
body, held on the function, carried on the call, verified per function.
Where it is held is the owner's; C2 R3 as amended calls the put an
operand, not an effect (`:1255-1257`, *read*), so it is not an atom of
the row. A site whose token is in no put set lowers to nothing.

### 4.2 Multiplicity (class 3 or not)

Per put parameter, `Finite bytes | Unbounded`, callees first: an
allocation inside a repetitive region (a loop, a recursive join point)
or reached through a call on a cycle is unbounded; otherwise the bytes
are the sum over sites and over calls, each callee's total read from its
summary. No iteration on numbers: a component with a put on a cycle is
`Unbounded` by its structure, and the acyclic part is one sum per
function. Bytes come from the data layout, after D48's `Layouts`
analysis (`L04-families.md:720-726`, *read*). MLKit's multiplicity
inference ("a statically determined upper bound on the number of times a
value is put into the region ... 0, 1 and ∞", manual §2.1, *read*) and
physical size inference, in one pass.

### 4.3 Instance shape (class 2, and where class 3 and 4 live)

Per site, from the program graph and the region nesting: *run once per
shard* (its function is run once: called from one site of a run-once
function, outside any repetitive region, and on no cycle; callers first,
from the shard's entry); *per call* (its function on no cycle, or its
extent spanning no call on its cycle); *per level* (its extent spans a
non-tail call on its function's cycle, which D32 frames); *per iteration*
(inside a repetitive region). And whether its token leaves its
computation: an operand of a send, a task spawn, or a tail call (§5.1).
O(functions + calls).

### 4.4 Stack discipline (class 4 or 5)

Per function, one walk with the stack of open stack-class sites: at each
allocating op and at each call, every token it puts into (directly, or
through the callee's put set) must be the innermost open stack-class
site's own token, or a token of class 1 to 3. A violation sends the
younger site to class 5 and the walk continues. A token parameter of
stack class counts as older than every site the function opens (its
lifetime was opened by a caller). O(ops × open depth) per function.

### 4.5 Sources of a token parameter (its mode)

Per token parameter, callers first over the SCCs: the classes of the
sites whose tokens reach it, and, for class 2, which site: a lattice
`none < site s < many` beside a set of classes, iterated inside an SCC
to its fixpoint, whose height is three per parameter, so it ends by
construction (*derivation*). O(functions + calls).

### 4.6 Tail groups

Tail calls demand equal result types between caller and callee
(`L10-tail-frames-stack.md:562-564`, *read*). A cursor that comes back
from a put call is a result, so functions joined by tail calls must
return the same cursors: one union-find over tail edges equalizes their
in-and-out cursor parameters. A function in the group that does not put
passes the cursor through, at no instruction when it stays in its
register (*conjecture*). The same closure L10 asks for the results
idr-returned-arguments drops (`L10-tail-frames-stack.md:642`, *read*).

### 4.7 Mode specialization

What a callee's code depends on is the mode of each put parameter, never
which lifetime: *room* (a class 3 sub-block or a cursor with enough
room: no check), *cursor* (classes 4 and 5 look the same to a callee: it
bumps what it is given and returns it), *constant* (class 2, one site),
and *counted* (the caller could not prove its D26 obligation for this
call, so the callee's copy builds counted cells, `L05-lifetimes.md:455-459`,
*read*). A function with k put parameters has at most 4^k copies, made on
demand. Copies do not climb: a recursive call passes a parameter through
(same mode) or one of its own sites (a fixed class), so the closure is
finite, linear in the program for bounded k, and ends without a budget
(*derivation*). This is D58's specialization by class with a mode set in
place of layout classes (`proposals/0000-mlir-native.md:973-986`, *read*),
on the one clone-and-key template (L18 §2.2, *read*). The counted copy is
the general one and always exists.

### 4.8 The rule

For each site, in order:
1. empty put set → class 1;
2. finite → class 3 (in the D31 frame when per level);
3. run once per shard, token never leaves its computation, and the only
   source of every put parameter it reaches → class 2;
4. unbounded, disciplined, token never leaves its computation → class 4;
5. otherwise → class 5.

Each later class is legal wherever an earlier one is (a finite lifetime
may live on the stack, a disciplined one in a chain), so D57's cost model
may pick a later class; it may never pick an earlier one the analyses
did not certify. The default order is cheapest first, with 2 against 4
measured (M4).

**Where the decision lives** (recommendation; the owner's to rule): one
op per source, as `memref.alloc`, `memref.alloca` and `memref.realloc`
are (the skill's rule): after the decide step, each `idr.lifetime`
becomes `idr.lifetime` (no allocation), `.frame` (with its byte size),
`.stack` (taking the stack top and giving it back), `.chain`, or
`.home` (class 2's thread-local home); and each put parameter's mode is
on the function, derived and verified per function like D61's part. The
lowering is then one pattern per op and one context-aware type
conversion per parameter, with no decision of its own.

## 5. Interactions

### 5.1 Tail calls (D30)

- *A lifetime ends before a tail call*: the region ends after the call's
  operands are computed and before control leaves, OxCaml's rule ("after
  the arguments to the tail call have been evaluated, but before control
  is transferred to the callee", so "tail-recursive loops use only
  constant space", OxCaml reference, *read*). Under D63 this is MLIR's
  own scoping: a call placed after the region cannot name the region's
  token, so no tail call can carry a value of a lifetime it outlives
  (*derivation*). L05's rule 8 (`L05-lifetimes.md:480-482`, *read*)
  becomes a placement fact checked by dominance.
- *An outer token passes through a tail call*, as OxCaml lets
  "outer-local" values (*read*); a cursor going out and coming back makes
  the tail group of §4.6.
- *MLKit gives up the tail call*: "a function call that looks like a tail
  call in the source program may end up as a non-tail call in the
  region-annotated program, because the function has to return to free
  memory" (manual §14.2, *read*). D30 forbids that here, so a tail call
  whose operands live in the closing lifetime keeps them counted (L05's
  A6), or hands the lifetime over (R3, research).

### 5.2 Frames and the static stack (D31, D32)

Class 3 blocks are native frame memory inside D32's computed bound, or
fields of a D31 frame. Classes 4 and 5 live in heap chunks; no
dynamically sized `alloca` exists (`L10-tail-frames-stack.md:742-746`,
*read*). A per-level lifetime adds one word, its mark, to the frame of
each framed call in its extent. The native stack holds only the
program's acyclic depth, as D32 says; a recursion's lifetimes ride its
heap frames' discipline.

### 5.3 Tail recursion modulo context (D34)

A TRMC loop building into a caller's lifetime carries the destination
and, for a class 4 or 5 lifetime, the cursor, both loop-carried
registers; the result's cells are reachable from their parent all along
(`L05-lifetimes.md:536-541`, *read*). D34's rule item 6 ("the
constructors on the path are fresh: counting makes each a heap cell ...
or ... recycles a token into it", `L10-tail-frames-stack.md:824-826`,
*read*) gains "or a cell of the caller's lifetime": a seam with L10.

### 5.4 In-place reuse (D24)

A parameter D24 rebuilds is exclusive and counted, so its cells never go
into a lifetime (`L05-lifetimes.md:218-227`, *read*). Where a callee's
counted copy would rebuild an exclusive argument in place (D24, or C1's
reuse), choosing the counted mode over a cursor saves the new memory
entirely; that is a choice for D57's cost model (§4.8). A cell of a
lifetime gives no reuse token (`L05-lifetimes.md:534`, *read*); R4.

### 5.5 Frame-limited (D26)

The class changes where memory comes from, never D26's obligations: a
finite lifetime is L05's *count* proof, an unbounded one needs *spine*
(`L05-lifetimes.md:526-534`, *read*). A per-level instance is held by an
active call, which D26 counts ("held by an active call (a native frame
or a heap continuation frame of `idr-frames`)", D26,
`proposals/0000-mlir-native.md:445-446`, *read*).

### 5.6 Shards and tasks (0007)

Tops and cursors are SSA values, so a coroutine split spills them into
the task frame as it spills any live value (L20 I10's argument for
frames). Each task has its own lifetime stack, as it has its own frame
chunks. A class 2 home is a per-shard slot, so §4.3 admits it only for a
lifetime no task can reach; `static` is append-only and never closed.
A lifetime that moves between shards is class 5.

## 6. Against MLKit, OxCaml, Gibbon, Cyclone

- **MLKit** passes a 64-bit "region name" for every region parameter that
  is put into: for a finite region "a pointer into the stack", for an
  infinite one "a pointer to the region descriptor" (manual §2.1,
  *read*). Classes 3 and 5 are those; classes 1, 2 and 4 are cheaper
  than anything MLKit has for an unbounded region. Two of its run-time
  facts are static here: at a `sat` allocation "the two least significant
  bits" of the region name hold "the atbot bit" and "the infinity bit",
  and the allocation tests them (manual §12.1, *read*). Finite or not is
  §4.2's per-site class and the mode copies of §4.7; reset or append is
  the lexical site of §3.4. Neither is ever tested at run time (D10).
- **OxCaml** has one region stack and no handle (*read*). It is class 4
  as the only class: a put is legal only into the innermost region. Ours
  makes that a per-site decision and keeps class 5 for the rest.
- **Gibbon** threads every output region's cursor through calls and
  returns it (*read*): class 5 for every region. Ours threads only
  where nothing cheaper is certified.
- **Cyclone** has region handles (`region_t<'r>`) only for dynamic
  regions, none for stack regions, and region names erased
  (Grossman, Morrisett, Jim, Hicks, Wang, Cheney, PLDI 2002, *recalled*):
  the split of an erased lifetime from a handle, which D63 merges into one
  value.
- **Upstream MLIR's** own scoped allocation is a region:
  `memref.alloca_scope`'s allocas "are going to be cleaned up
  automatically once the control-flow exits the nested region"
  (`MemRefOps.td:432-448`, *read*), lowered to `stacksave` and
  `stackrestore` (`MemRefToLLVM.cpp:427, 440`, *read*). That is class 3
  and 4's shape on the native stack, which D32 forbids for unbounded
  sizes. Upstream's ownership-based deallocation keeps ownership in SSA
  `i1` values, computed at run time where unknown
  (`docs/OwnershipBasedBufferDeallocation.md:80-83, 103`, *read*): facts
  in values, paid at run time when static, which is what this file never
  does.

## 7. What the ceiling needs from D63's token

D63 leaves to `audits/p0/design/lifetimes/` how a value's lifetime is
known and checked (`proposals/0000-mlir-native.md:1046-1050`, *read*).
This design reads, and needs:
1. Every op that allocates into a lifetime takes its token (D63's text),
   so the token's uses cover its cells and no dead-code pass can drop a
   token a live cell needs (*derivation*).
2. A call passes tokens as operands at parameters the callee's signature
   relates to its results, so §4.5's callers-first pass can read sources.
3. The put set per token parameter (§4.1), derived and verified.
4. The source ops of §4.8, or whatever holds the class decision, so the
   lowering decides nothing.

## 8. The design, its cost, what to measure

**The design.** The token is erased unless its lifetime is put into
(class 1); a put lifetime takes the cheapest of four forms the analyses
certify: a thread-local constant (2), a frame block (3), the
computation's lifetime stack (4), its own chain (5). Classes 3 to 5 share
one cursor protocol, room checked once per run, and the frame stack's
runtime type. A callee is specialized by mode, never by lifetime, at
most 4^k copies. The decision is made once, in one decide step, and held
in the IR.

**What it costs to build.** The six analyses of §4 (each a pass or a
walk, shapes S and L of L14); the source ops and their lowering
patterns; one context-aware type conversion for tokens; the mode clones
on L18's template; the runtime's chunked stack generalized from D31's to
three uses, and the shard's chunk pool; the per-level mark in D31 frame
kinds; the tail-group closure.

**What it costs to run.** Compile time: linear in the program for each
analysis, plus the mode clones. Run time: nothing for view-only
lifetimes; nothing for finite ones in their opener; a register per put
call otherwise, in and out for classes 4 and 5; one check per allocation
run; an O(1) close without owned fields. Against counting: no count word
operation, no free per cell (D26 permitting).

**Measurements owed** (each needs a build; none taken):
- M1: sites per class and put parameters per function (k) on the stage-1
  module and the suite.
- M2: mode copies made, against the 4^k bound.
- M3: functions whose results plus cursor exceed the return registers of
  `tailcc`, per target, four targets (the through-memory fallback).
- M4: class 2 against class 4 where both are legal: cycles per put call
  and register spills, on the bench.
- M5: chunk-pool traffic and peak lifetime-stack bytes per run.
- M6: cells moved from counted memory to lifetimes against today's
  `numStackCells` (L05 Q1's measurement), and count operations removed
  by per-level lifetimes (§3.4) before A6 is lifted.

## 9. Research, not promised

- **R1. Frames and lifetimes on one stack.** Where no framed callee puts
  into a per-level lifetime inside its extent, its cells could sit on the
  frame stack beside the frames, saving a stack and a top register per
  computation: a frame becomes a variable-size activation record.
  *Conjecture*: sound under that condition; the typing of the top's two
  views is not designed.
- **R2. Polymorphic recursion on d+1 stacks.** A recursion that puts into
  the lifetime one level up (depth 1) while its own is open fails §4.4
  and goes to class 5, a chain per level. With two stacks used by
  alternating levels, each level's put lands at the top of the other
  stack: *derivation* sketch: level k opens on stack (k mod 2), receives
  level k−1's cursor in and out and a base on the other stack, and the
  base is borrowed only while level k+1 runs, during which nothing puts
  into it. Static depth d needs d+1 stacks. Not proved in general;
  MLKit's claim that polymorphic recursion is vital (§6.4) says it is
  worth the proof.
- **R3. A lifetime handed over at a tail call.** A tail callee that takes
  the token and closes the lifetime makes its extent end in another
  function: not lexical, so not D63's `idr.lifetime` region. Known in the
  capability calculus (Walker, Crary, Morrisett, TOPLAS 2000, *recalled*)
  and in control-flow-sensitive regions (Henglein, Makholm, Niss, PPDP
  2001; Aiken, Fähndrich, Levien, PLDI 1995, *recalled*). A change to the
  ruling's shape: the owner's.
- **R4. In-place reuse inside a lifetime.** An exclusive cell of a
  lifetime could give a reuse token with no count read and no free,
  rebuilding in place inside the arena. It waits on how the grade's parts
  combine (D62) and L05's Q1.
- **R5. Overlaid constant homes.** Class 2 homes of sites never open
  together could share storage (the data overlay of non-reentrant
  functions in 8051 compilers, *recalled*). A memory saving, measured.

## 10. Against options A, B, C

- **A (an erased lifetime and a separate linear handle; L05, L06, L02,
  L20).** D63 merges the two into one value. This file is A at its
  ceiling: A's handle, "an ordinary word" (`L05-lifetimes.md:368-371`,
  *read*), exists only in class 5 and as the computation's stack top in
  class 4. As a word pointing at a record, A loads and stores the bump on
  every allocation, which the in-and-out cursor removes; its linearity
  survives in the stack top and in a shard send.
- **B (every lifetime a run-time value; D39 as written).** A register for
  every token parameter, view-only ones included: the dead register
  MLKit drops (§6.3) and D10 forbids. Dominated by class 1.
- **C (no handle).** Read as "no allocation into a caller's lifetime"
  (L06's (c)), it loses the largest win, a result built in its caller's
  lifetime. Read as "ambient state only" (OxCaml), it is sound only under
  §4.4's discipline and inside one computation: it covers classes 1 to 4
  with a per-thread top, breaks under interleaving tasks (L20 I10's
  counterexample, transposed), and has no form for class 5. The ceiling
  takes C's mechanism where it is sound, with the top threaded instead of
  ambient, and a pointer only where it is not.

## 11. Sources

- Tofte, Birkedal, Elsman, Hallenberg, Olesen, Sestoft, *Programming
  with Regions in the MLKit*, revised for 4.7.16 (elsman.com/pdf/mlkit-4.7.16.pdf):
  §2.1, §6.3, §6.4, §12.1, §12.2, §14.2, *read*.
- OxCaml, *Stack allocation: reference*
  (https://oxcaml.org/documentation/stack-allocation/reference/), *read*;
  Lorenzen, White, Dolan, Eisenberg, Lindley, *Oxidizing OCaml with Modal
  Memory Management*, ICFP 2024 (`sources/INDEX.md`, link only),
  *recalled*.
- Gibbon: `sources/code/gibbon/gibbon-compiler/src/Gibbon/Passes/ThreadRegions2.hs`,
  `InferRegionScope.hs`, *read*.
- Birkedal, Tofte, Vejlstrup, *From region inference to von Neumann
  machines via region representation inference*, POPL 1996; Tofte,
  Birkedal, *A region inference algorithm*, TOPLAS 1998: *recalled*,
  their analyses as the manual describes them.
- Grossman et al., *Region-based memory management in Cyclone*, PLDI
  2002; Walker, Crary, Morrisett, *Typed memory management via static
  capabilities*, TOPLAS 2000; Aiken, Fähndrich, Levien, *Better static
  memory management*, PLDI 1995; Henglein, Makholm, Niss, *A direct
  approach to control-flow sensitive region-based memory management*,
  PPDP 2001: *recalled*.
