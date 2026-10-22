<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# L01: the effect tree, and every op's declaration

Lane L01 of the P0 verification swarm. HEAD `e96bb991` at start
(2026-10-21T21:30Z) and at finish (rechecked before handing off); the
llvm-project pin `7208ba24c`. Nothing was built or run. Claims are
marked *read* (path:line at HEAD; upstream paths under
`.toolchain/llvm-project/mlir/`), *measured* (method given),
*recalled*, *conjecture* or *decision* (a ruling Dn or Cn of
`proposals/0000-mlir-native.md`). "Vocabulary" is
`audits/p0/design/effect-vocabulary.md`, "effects.md" is
`audits/p0/design/effects.md`, "02 §s" and "03 §s" the wave-2 lanes.

*Measured*, once, for the whole file: TableGen's own reading of every op
record, `.toolchain/build/tblgen/bin/llvm-tblgen --dump-json -I
.toolchain/llvm-project/mlir/include -I foreign/idr/include
foreign/idr/include/idr/IR/IdrRuntime.td -o /tmp/l01-out/records.json`,
flattened by two `python3 -I` scripts kept outside the tree
(`/tmp/l01-scripts/ops.py`, `compact.py`): 189 `idr` ops (13 in
`IdrArrayOps.td`, 23 `IdrBigOps.td`, 8 `IdrCheckOps.td`, 6
`IdrClosureOps.td`, 18 `IdrIOOps.td`, 3 `IdrMatchOps.td`, 9 `IdrOps.td`,
14 `IdrOwnershipOps.td`, 59 `IdrPlatformOps.td`, 14 `IdrScalarOps.td`,
22 `IdrStringOps.td`); 51 carry an ODS value effect on upstream's root;
80 carry `Idr_PerformsIO`. Running a pinned, already-built TableGen over
the sources reads records and builds nothing.

## 1. Verification

### 1.1 The tree (D27) against upstream at the pin

**Holds, with one correction (the identity resource and alias
analysis).**

- *No addressable resource under an opaque one.* D27's opaque subtree is
  `io` and its four children (`runtime_state`, `exit`, `crash`,
  `divergence`); every addressable resource (`heap`, `contents`,
  `count`, `memo_state`, `identity`, upstream's frame) hangs from the
  addressable root (read: vocabulary §4.1, §5.2's table). Upstream checks
  this only under `EXPENSIVE_CHECKS` (read:
  `include/mlir/Interfaces/SideEffectInterfaces.h:139-143, 160-172`), so the
  specification's `Fits` (vocabulary §6, law L2) is the only check that
  runs in every build. Holds.
- *Conflict only between an ancestor and a descendant.* `isDisjointFrom`
  is "neither is an ancestor of the other" (read:
  `SideEffectInterfaces.h:151-153`). Every ordering the rulings ask is a
  chain: a crash under `io` (D21), `divergence` under `crash` (D13), and
  `exit` beside `crash` but always written with `io`, an ancestor of
  both (D14, law L8). The heap's subtree and `io`'s are siblings, so a
  heap access and a crash never conflict (D21). Holds. One reader trap
  follows from upstream's `classof`: `isa<X>(resource)` is true of every
  descendant of `X` (read: `SideEffectInterfaces.h:108-115`), so
  `isa<idr::effects::IO>` holds of a crash's resource too, and §5.2
  A8's "does this op do IO is one `isa`" stops being true the moment a
  crash sits under `io`. Today's readers already mix `isa<IOResource>`
  and `==` (02 §3.3 A3). The one
  query API (L02's) must compare `ResourceId` exactly, never upstream's
  `isa`, or "does IO" silently includes every crash. *Integration
  mismatch* with no current reader, recorded as a seam (§2.8).
- *A value effect only on an addressable resource.* Upstream aborts at
  run time (read: `SideEffectInterfaces.h:337-343`,
  `checkResourceAllowsValue`). Every value effect in the table of §2.3
  names an addressable resource; `io`'s subtree carries op-level effects
  only. Holds.
- *Correction: `Allocate` on `identity` reads as fresh memory to
  upstream's alias analysis.* `LocalAliasAnalysis::getAllocEffectFor`
  takes any `Allocate` on a value, whatever its resource, as a distinct
  allocation scoped to the function (read:
  `lib/Analysis/AliasAnalysis/LocalAliasAnalysis.cpp:240-292`), and an
  allocation in a function never aliases that function's entry
  arguments (read: `:403-421`). So `%l = idr.lin.enter %arg` with
  `%arg` an entry argument answers NoAlias though `%l` is `%arg`
  (`lin.enter` has no runtime form: `IdrOwnershipOps.td:388-399`, read).
  The vocabulary states the opposite premise: "`Allocate` names a fresh
  result no other access reaches" (vocabulary §4.2) and "a result may be
  declared allocated only if it is fresh" (§2.3). Upstream itself uses
  `Allocate` for a fresh identity that is no memory: the transform
  dialect's `producesHandle` puts `Allocate` and `Write` on each result
  handle on `TransformMappingResource` (read:
  `lib/Dialect/Transform/Interfaces/TransformInterfaces.cpp:1823-1830`).
  So the idiom is upstream's and the gap is the alias analysis's. No
  pass of ours runs `LocalAliasAnalysis` today (02 §3.2, read), so
  nothing reaches it: *unverified behaviour*, latent, and the same for
  today's `LinResource` (`IdrOwnershipOps.td:410, 422`;
  `Call.cpp:69-71`). Correction: improvement I5.

### 1.2 D27's placement: the heap carries Allocate and Free, its children the rest

**Holds, with a correction: three ops' count writes and frees fall
outside every declaration once the root is gone.**

Today the 51 ops with a value effect on the root (*measured*) are
ordered with everything, because the root is every resource's ancestor
(02 §3.7's third case). Named under D27, each effect lands on one
child, and an effect no declaration names becomes invisible across the
siblings. Read against each op's lowering and runtime function:

- `array.set` releases the old element: the write "releases the old
  element and moves the new one in" (read:
  `lib/Conversion/Arrays.cpp:211-223`), a decrement that may free the
  element's cell. The vocabulary declares only "`Read`, `Write` on
  `Contents` of the array" (vocabulary §3, row "arrays"). Under the
  tree a later `is_unique` of that element (`Read` on `count`) no longer
  conflicts with the set. *Defect confirmed in the source* (the
  design's declaration lacks what the lowering does).
- `array.new` takes a reference to its fill per element and gives up
  the fill's own (read: `Arrays.cpp:110-150`: `runtime.inc` in the
  loop, `runtime.dec(held)` after it, which frees the fill at count 0
  when no element took it). The vocabulary declares only `Allocate` on
  `heap` of the result. *Defect confirmed in the source.*
- `take` frees nothing (F3, confirmed below), but its lowering on a
  shared box increments the moving fields and decrements the box (read:
  `lib/Conversion/Counting.cpp:93-108`), count writes the vocabulary's
  `Read`, `Write`, `Free` on `count` of the box covers. Holds.

And three more ops name the root by hand, outside the 51 ODS records:
`con` (`OpsCon.cpp:51-54`, read), and `array.update` and
`element.update` through `updateEffects` (`OpsArrays.cpp:78-84`, read).
So the root is named by 54 ops, not 51 (proposal §5.1's "the root
resource on 51 ops"): *integration mismatch* in the count only; each of
the 54 gets a named resource in §2.3.

### 1.3 The world (D20)

**Holds.** The world produces no op-level effect today: IO ops declare
`IOResource` through their class, the ten world-ordered memory ops
declare value effects (02 §3.3 M1, read). After D20, each of the ten
(`array.new`, `array.get`, `array.set`, `array.update`, the five
`io.buffer_*`, `tabulate_io`) is ordered by `contents` effects on its
array or buffer value alone, which D27 provides (§2.3). The world's
readers and their replacements are in §2.6. D20's "exact where the
world was an upper bound" has consequences the vocabulary misses:
seven IO actions touch no outside state at all (§1.10 L9), and their
exact row is empty.

### 1.4 A crash, a divergence, an exit (D13, D14, D21, D23)

- **D13 holds**, with one defect. Every op that may crash declares a
  `Write` on `crash` and is not speculatable (no
  `ConditionallySpeculatable`); `may_loop` writes `divergence` once.
  *Defect confirmed in the source*: `handle.string` may crash
  (`idris_rt_handle_string` calls `idris_rt_crash` when the slot holds
  no string, read: `runtime/Io/Handles.cpp:235-243`) and declares no
  crash today (`IdrPlatformOps.td:365-367`: `Read` of `IOResource`
  only) nor in the design (vocabulary §3: `Read` on `RuntimeState`).
  An unused `handle.string` of a null handle is then trivially dead
  (a lone `Read` is droppable: `lib/Interfaces/SideEffectInterfaces.cpp:77-93`),
  and deleting it deletes a crash eager evaluation runs (D13).
  Correction in I3.
- **D14 holds with a correction.** `idris_rt_io_exit` flushes, releases
  the handle table, checks the status and ends the process (read:
  `runtime/Io/Ending.cpp:56-61`); a status outside 0 to 255 is today a
  crash with status 1 (read: `runtime/Start/Entry.cpp:88-107`). D37
  makes it an internal error (`SIGABRT`), outside every effect. So
  `io.exit`'s declaration (`Read`, `Write` on `io`, `Write` on `exit`,
  a terminator) is exact only once the runtime's ending table of D37
  lands: they land together, or `exit` keeps a `Write` on `crash`.
  *Integration mismatch* (landing order), seam with L11.
- **D21 holds.** The crash path is flush, message, `_exit` (read:
  `Ending.cpp:66-71`); nothing reads program memory after it. One
  precondition: the live-cell counter (`runtime/Alloc/Cells.cpp:157,
  190, 195, 205`, read) is written by every allocation and free and
  printed at main's return when `IDRIS_RT_LIVE=1`
  (`Ending.cpp:19-31, 45-49`, read). D23 makes allocations movable and
  deletable; with the counter kept, that report (standard error, an
  output) would change with the optimizer. The counter's deletion (D10;
  18 R-AL-5) must land no later than the tree.
- **D23 holds.** Allocation failure is the runtime's named ending
  (`Cells.cpp:163-181`; `Strings/Replacement.cpp:91`;
  `Big/Bitwise.cpp:40-41`, read), never an op's effect; no acquisition
  in §2.3 carries a crash.

### 1.5 D22, the op side

**Holds with corrections.** Every state a caller must order with is in
some op's declaration once §1.2's three fixes, §1.4's crash, F2 and the
widened scratch fact (§1.10 L8) land. Without them the derived row
(L02's) inherits the hole: an `array.set` in a callee would leave a
caller's `is_unique` free to move across the call. 02 §3.7's three
losses close by construction: `handle.string`'s read is on
`runtime_state` (atom `runtime_state`), `exit` writes `exit`, memo
writes are on `memo_state` (read: vocabulary §4.5; D29).

### 1.6 The names (D28) and the atoms (D29)

- **D28 holds.** The vocabulary's resource table (§5.2) prints exactly
  D28's names, keeps upstream's root and frame, and names the C++
  classes and the Idris constructors as D28 does. Two risks, neither
  refuting the ruling: (a) *unverified behaviour*: `Spec.Effects.Resource`
  has a constructor `IO` beside Prelude's type `IO`; Idris resolves
  overloaded names by type, so every module that imports the closed
  sets (D50) and writes `IO ()` elaborates an ambiguity. The measurement
  to take: elaborate a module importing such a constructor and `main :
  IO ()` under stock Idris and under idris-mlir, and time
  `%ambiguity_depth`'s search (D45). (b) the `classof` trap of §1.1.
- **D29 holds; two mismatches around it.** Proposal §5.1 still prints
  the row as `io runtime exit crash diverge read write count memo`
  ("A function's row"), the spellings D29 removed: *integration
  mismatch* in the proposal's text. And D29 names the atoms on
  `contents` and `heap` by kind (`read`, `write`, `alloc`, `free`),
  while the vocabulary's `Spec.Effects` declares `data Kind = Read |
  Write | Allocate | Free` in the same module (vocabulary §6): two data
  types with constructors `Read`, `Write`, `Free` in one namespace do
  not both elaborate. The printed spelling is generated, so the
  constructors may differ, but the module shape must say how: seam
  with L03.

### 1.7 C2's rules in this area (R2, R5)

- **R2 holds.** `heap` is where any cell's memory comes from; a buffer
  given back to the kernel is a `Free` on `heap`, ordered after every
  access below `heap` by ancestry. No op of today gives memory to the
  kernel. Holds as a declaration rule.
- **R5 holds as a rule, with no producer.** "A drop of a value whose
  type may reach a foreign cell writes `IO`" needs a type fact no type
  carries (no foreign cell exists before proposal 0020). *Unverified
  behaviour*: its condition must be computed once when the type is made
  (D48's family attribute), never by a walk at the drop. Seam with L04
  and L20.

### 1.8 C3, revised: building a value acquires nothing before counting

**Holds with corrections.** The principle (two equal immutable values
merge; an unused one goes; memory is acquired where counting
materializes a cell) is sound under D23, and the owner's word stands
behind the revision. Checked against every consumer of "acquires"
(read, each at the line):

| consumer | reads | under C3 |
| --- | --- | --- |
| upstream `wouldOpBeTriviallyDead` (`SideEffectInterfaces.cpp:43-110`) | every effect a `Read` or an effect on an allocated result | unchanged: a pure con and a con with `Allocate` on `identity` of its result are both dead when unused |
| upstream CSE (`lib/Transforms/Utils/CSE.cpp:264-280`) | merges memory-effect-free ops, and single-`Read` ops with no conflicting `Write` between | **changed, intended**: two equal unrestricted cons merge; an `identity` result never does |
| `onlyAllocates`/`classify` (`lib/IR/Effects.cpp:113-133`), callers `Canon/Sink.cpp:71, 79, 223`, `Canon/CaseOfCase.cpp:78, 117, 126`, `Analysis/IdentitiesRecord.cpp:308, 314`, `Bufferize/Bufferize.cpp:193`, `Expect/Facts.cpp:39` | no effect but an allocation of its own result | unchanged: pure and identity-only are both `Computes` |
| MoveOut's `doesOf` (`Canon/MoveOut.cpp:71-103`) | the same, by its own walk | unchanged in answer (its walk goes with D20, §2.6) |
| `Reshape::movable` (`Ownership/Reshape.cpp:291-306`) | `Allocate` on `LinResource`, `Free` on `ReferenceResource` | must read `Allocate` on `identity` and consumption on `count`: adapted, same answer |
| owned verifier's roles (`Verify/Owned.cpp:97-108`) | `hasEffect<Allocate>` on a result | unchanged: it runs on owned code, where a con's result is owned (`Idr_OwnType` first, `:102-103`) |
| `declaresSource` (`Verify/OwnedOps.cpp:225-226`) | `hasEffect<Allocate>` on an owned result | unchanged: C3 gives an owned con result `Allocate` on `identity` |
| `atMostCrashes` (`StructureLoops/Forms.cpp:46-63`) | an allocation of its own result | unchanged |
| **idr-expect `no-heap-allocation`** (`Expect/Allocation.cpp:26-44`) | any `Allocate` but on `LinResource` or the frame, plus `closure` and `suspend` by hand | **broken before counting.** Tests assert it fails on a box `con` at stages `first` and `higher`: `tests/canon-record-eta/canon-record-eta.mlir:11` (`@reindex`, a `idr.con !idr.box<!RB>`, stage `first` at `:41`), `tests/canon-head/canon-head.mlir:5`, `tests/canon-sink-into-regions/canon-sink-into-regions.mlir:5` (both stage `first`); 15 test files name the property (`grep -rln no-heap-allocation tests`). Under C3 a box con before counting declares nothing, so those assertions flip |
| **idr-expect `builds`, `builds-nothing`** (`Expect/Does.cpp:33-34`, `Expect/Placement.cpp:117`) | `Idr_BuildsValue` | **its designed replacement is void**: the vocabulary replaces `BuildsValue` by "`Allocate` on `Heap` of the result" (vocabulary §5.3, F4; effects.md 2.7), which C3 removes from every constructor |
| the `alloc` atom (L02's) | `Allocate` on `heap` | **C3's text is incomplete**: "memory is acquired where counting materializes a cell (`cell.new`), which is where the `alloc` atom comes from" omits the runtime builders (strings, bigs, `array.new`, `io.get_line`, `io.arg`), which allocate in the runtime call itself (vocabulary §2.2's table lists them) |
| **the in-place promise (D24)** | exclusivity at the call, proved after the optimizer | **a refusal CSE can add**: improvement I1 |

Corrections: (1) the `alloc` atom also comes from every runtime
function that allocates its result; (2) heap-freedom as a test fact is
anchored after counting, and before counting it is layout's question
(D48: "inline or in a cell is layout, a function of the type and its
lifetime computed once"), I6; (3) an `in_place` value takes its identity
at its producer, I1; (4) the same principle covers the runtime builders
of immutable values, I2. Stale against the revision, each an
*integration mismatch*: vocabulary §2.6 F4 ("DP-31's option B is
forced"), §3's rows "values" (`AcquiresCell result`) and "closures"
(`Allocate` on `idr.heap`), §8.2's "DP-31 (B): a closure acquires its
cell"; proposal §5.1's last bullet "A closure acquires its cell (C3)",
and §5.1's "Five forms" bullet, whose typed rules list `AcquiresCell`.

### 1.9 The vocabulary's four lying declarations

- **F1, a share declared as an allocation: confirmed, and wider.**
  Confirmed at the cited sites: `idris_rt_str_append` gives back the
  other string with one more reference when a side is empty
  (`Strings/Concat.cpp:28-35`); `idris_rt_str_reverse` of the empty
  string (`Strings/Scalars.cpp:115-119`) and `idris_rt_str_drop_bytes`
  at offset 0 (`:154-162`) give back their operand; `handle.string` is
  the slot's string with one more reference (`Io/Handles.cpp:241-242`).
  Not in the vocabulary (each read): `nat.from_big` never allocates at
  all, giving back its operand with one more reference when it is a
  large non-negative Integer and a small word otherwise
  (`Big/Arithmetic.cpp:64-69, 95-102`; `Big/Big.h:49-55`), yet declares
  `Allocate` on its result; `big.shl` and `big.shr` give back their
  operand by a shift of 0, and `big.shl` of 0 (`Big/Bitwise.cpp:29-33,
  48-53`). And every string builder returns the one static empty string
  for a result of no bytes (`Strings/Making.cpp:18-22`), which is
  benign: static data's header is never written ("Its header is never
  written", `:19`), so no access it aliases ever conflicts, and the
  `alloc` report over-approximates. *Defects confirmed in the source*
  (the counted shares).
- **F2, `memo.run`'s counts: confirmed.** `memo.run` lowers to a call of
  `idris_rt_persist_held` after the forced value is stored (read:
  `lib/Conversion/MemoCells.cpp:96-99`), which writes count 0 into every
  cell a static memo cell now reaches and grows a walk stack of runtime
  memory (read: `runtime/Rc/Freeing.cpp:161-188`); `memo.run` declares
  only `MemoStateResource` (`OpsClosures.cpp:258-265`, read).
- **F3, `take`'s free: confirmed, and one more case.** `take` gives back
  no memory: an exclusive box becomes the token, a shared one is
  decremented from at least two (read: `Counting.cpp:86-108`; F3's
  wording). The design's own `effects.md` 1.7 declares `MemFree<Idr_Heap>`
  on it and the vocabulary corrects it to `count`. The extra case: an
  exclusive take reads and writes no count at run time (`:87-92`: "its
  fields move out, and the cell is the token, with no test"), so its
  declaration under D10 is consumption alone (I4).
- **F4, closures' allocation: superseded.** Under C3 revised a closure
  of an unrestricted value is a value and declares no allocation
  (closures live only until defunctionalization, `Pipeline.cpp:66-71`,
  read, after which they are constructors under the same rule). Today's
  `Expect/Allocation.cpp:27-30` exceptions go with C3, not with F4.

### 1.10 Every other declaration that is not what its runtime function does

Read against the runtime functions and the lowering, op by op (§2.3
holds the full table):

- **L5. `handle.string` may crash**, undeclared (§1.4). *Defect.*
- **L6. `array.set` releases**, undeclared count write and free (§1.2).
  *Defect.*
- **L7. `array.new` counts its fill**, undeclared (§1.2). *Defect.*
- **L8. Memory the runtime's own state holds.** IO ops that grow the
  handle table (`newSlot` → `grow`, `Io/Handles.cpp:75-84, 180-191`:
  `io.file_open`, `io.dir_open`, `io.file_time`, `io.file_read_line`,
  `io.file_read_chars`, `io.dir_current`), refill a kept string
  (`keepString` releases the old one, `:199-203`: `io.env_get`,
  `io.env_pair`, `io.dir_entry`) or release a slot (`releaseSlot`,
  `:207-212`, and `fclose`'s libc buffer: `io.file_close`,
  `io.dir_close`, `io.handle_free`) acquire or give back memory that no
  value of the program names. The vocabulary's `Scratch` is "memory
  that never leaves" the runtime function, taken and given back "before
  it returns" (vocabulary §2.3, §6), which does not describe a table
  that keeps its growth. Without a fact for it, a function holding only
  these ops has no `free` and is lowered `nofree` (vocabulary §7.1:
  "without it, `nofree`"), a false promise to LLVM about memory that
  existed before the call. *Structural incompleteness*. Correction: the
  meaning's fact is "memory no value names, acquired or given back",
  whether it outlives the call or not (I3).
- **L9. Seven IO actions that observe nothing**, declared `Read` and
  `Write` on `IOResource` today, each paying an ordered, undeletable,
  unmergeable call for a fact known statically (D10): `io.clock_gc_cpu`
  and `io.clock_gc_real` return the constant -1 (`Io/Clock.cpp:54-58`);
  `io.clock_valid`, `io.clock_second`, `io.clock_nanosecond` are
  arithmetic on their operand (`:60-71`); `io.term_setup` is an empty
  function (`Io/Terminal.cpp:26-27`); `io.pid` is fixed for the run
  (`getpid`, `Io/Process.cpp:90`; no `fork` in the language,
  AGENTS.md). And `io.file_errno` reads only the saved errno
  (`Io/Errors.cpp:33-44`), the same state as `io.errno`, which the
  vocabulary moves to `runtime_state` while leaving `io.file_errno` an
  IO action. Not unsound; *optional simplification* that D20's exact
  row and D10 make due. 03 §5.3 reached the clock half (`clock.valid`
  and kin "`Pure`"; the GC kinds "fold to `-1`"); the runtime confirms
  it.
- **L10. `io.exit` may crash today** (§1.4). Closed by D37, landing
  with it.
- **L11. `array.yield` is `Pure` and moves its values into memory**
  (`IdrArrayOps.td:215`, read; synthesis A B19). `memo.run`'s region
  ends in it, and `memo.run` survives counting (it is lowered at
  idr-lower, `MemoCells.cpp:53`), so an owned value moves into the memo
  cell through an op that declares taking nothing. *Defect confirmed in
  the source*; `idr.yield` already declares consumption
  (`IdrMatchOps.td:163`).
- **L12. `own.adopt` is `Pure` and makes an owned value**
  (`IdrOwnershipOps.td:357`, read): under C3's rule ("an owned result
  takes a fresh identity") it takes one; today CSE may merge two adopts
  of one memref into one owned value used twice, which only its
  def-use verifier (synthesis A B13) catches. *Defect* of the same kind
  as C3 fixes for con.

Checked and exact (no change of meaning, only the resource named): the
output family (`Io/Output.cpp:134-176`: the static buffer and fds 1, 2),
the input family (`Io/Input.cpp:101-131`), file, directory, process,
environment, terminal and clock-reading families (`Io/Files.cpp:73-159`,
`Io/Directories.cpp`, `Io/Process.cpp`, `Io/Terminal.cpp`,
`Io/Clock.cpp:23-52`: each either touches the outside or saves errno,
which writes `runtime_state` and so must write `io`, law L9), the buffer
family (`Io/Buffer.cpp:9-33`, `Io/Bytes.cpp:20-42`: the buffer's bytes
only), the crash family (`Ending.cpp:66-76`), the big and string
functions (operands read in place, results new or small words:
`Big/Operands.cpp:29-45`, `Strings/Making.cpp:20-28`), `dup`, `drop`,
`cell.new`, `cell.stack`, `cell.recycle`, `cell.init`, `dest.write`
(`Counting.cpp:27-56`, `Conversion/Cells.cpp:66-180, 274-290`).

### 1.11 Proposal §5.1's counts

**Refuted in detail.** "Five forms of declaration, exactly one per op:
static (175 of 189 classes), typed rules read off operand types (14
ops...)". Under C3 revised and the corrections above, §2.3's table
gives (*measured* by counting its form column): 2 definitions, 2 that
run unknown code, 7 recursive (one of them, `match`, with a typed own
part), 57 typed (24 without improvement I2), 112 static, 9 deleted or
merged (three by D20, six by I3); and the typed rules read result
types as well as operand types (`NewIdentity`, `Acquires`). The vocabulary's own §3 already exceeds 14
(`cell.recycle`'s `IfMayBeNull`, `drop`'s exclusive case,
`handle.string`'s owned stage). *Integration mismatch.* The forms
themselves hold, with one gap: the specification's `Recursive : List
(Effect gs) -> Effects gs` (vocabulary §6) admits only static effects
of its own, so `match` (recursive, with `ReadsMemo` on its scrutinee)
has no form. Seam with L03 (§2.8).

### 1.12 What the design deletes

**Holds.** Each named deletion, its readers today and what replaces
each reading (read at the cited lines):

| deleted | readers today | replaced by |
| --- | --- | --- |
| `Idr_PerformsIO` (`IdrInterfaces.td:295-297`; `Traits.h:52-60`) | `tools/idris-mlir-tblgen.cpp:1481` (an IO primitive's Idris shape); 80 ops, the same 80 that take a world (02 F1) | Idris's sequencing is the primitive's Idris type, stated in the specification and imported by the frontend (D16, D50), never an effect (vocabulary §5.3) |
| `Idr_ObservableIO` (`:306-308`; `Traits.h:62-70`) | `lib/Analysis/Effects.cpp:66` (`observableRuns`: a memo label reaching one is `by_name`) | the row holds `io`; `io.strerror` (deliberately not observable, `IdrPlatformOps.td:311-313`) declares no `io` under D27, so the two sets agree |
| `Idr_MayCrashOpInterface`, `Idr_MayCrash` (`:105-117`) | `Func/Func.cpp:194` (the crash bit), `Forms.cpp:52`; `getCrashCause` called once, on a typed op (`Conversion/Bigs.cpp:44`) | a `Write` on `crash`; the cause stays the op's own accessor |
| `Idr_ReferenceResource` (`:91`) | `Effects.cpp:103` (writes it), `Reshape.cpp:304` | consumption on `count` (`Consumes`, §2.2) |
| `Idr_NoReturn` (`IdrCheckOps.td:19`; `Traits.h:42-50`) | `Expect/CrashSites.cpp:28`, `Expect/ComputesNothing.cpp:26`, tblgen `:950` (the C prototype's `noreturn`) | a terminator with no successor whose effects write `crash` or `exit` (law L7; D14; 03 R4) |
| `Idr_TakesReference` (`IdrBase.td:287`; `Traits.h:114-117`) | `Verify/OwnedOps.cpp:240` (the result holds a reference of its own) | a `Write` on `count` naming the value whose reference is new; **correction**: the design says "of the operand" (vocabulary §5.3), which misses `handle.string` and the forwarding `nat.from_big`, whose new reference is their result's (their operands are a handle and a borrowed big); the rule is "a `Write` on `count` of the result, or an `Allocate` on it" |
| `Idr_BuildsValue` (`IdrBase.td:293`) | `Expect/Does.cpp:34`, `Expect/Placement.cpp:117` (both test properties) | **void under C3** (§1.8); the property moves after counting or reads the constructor family (I6) |
| the double IO writes | `Idr_MayCrash` on 8 ops, `may_loop` (`IdrCheckOps.td:46-47`), `force` (`IdrClosureOps.td:101-103`), the call's `rows` (`Func.cpp:253-254`) | one write each: `crash` and `divergence` sit under `io` |
| the root on 54 ops | §1.2 | the resource each names, §2.3 |
| the world | `bodyEffect` (`Func.cpp:191, 196`), MoveOut (`MoveOut.cpp:105-115, 138-157`), `Specialize/Consumer.cpp:48`, `Analysis/Identities.cpp:30`, `Specialize/Keys.cpp:201`, `rootKind` (`Func.cpp:275-287`), tblgen (`:1446-1458`) | D20: the row's `io` (L02's); MoveOut's next write found by `contents` effects; an IO root is a function of no parameter whose row may hold `io` |

## 2. Boundaries

### 2.1 The tree

D27 and D28, as the generated C++ will hold it (vocabulary §5.2):

| resource | C++ | parent | reach | kinds admitted | holds |
| --- | --- | --- | --- | --- | --- |
| root | `mlir::SideEffects::DefaultResource` | — | addressable | any (upstream ops) | any memory |
| frame | `mlir::SideEffects::AutomaticAllocationScopeResource` | root | addressable | Allocate | stack cells |
| `idr.heap` | `idr::effects::Heap` | root | addressable | Allocate, Free | memory any cell lives in (C2 R2; D40: a lifetime's cells too) |
| `idr.contents` | `Contents` | heap | addressable | Read, Write | memory written in place |
| `idr.count` | `Count` | heap | addressable | Read, Write, Free | reference counts; Free is consumption |
| `idr.memo_state` | `MemoState` | heap | addressable | Read, Write | memo cells' state |
| `idr.identity` | `Identity` | root | addressable | Allocate | a fresh owned, linear or `in_place` value's identity (no memory) |
| `idr.io` | `IO` | root | opaque | Read, Write | the outside, one ordered state |
| `idr.runtime_state` | `RuntimeState` | io | opaque | Read | the handle table, the saved errno |
| `idr.exit` | `Exit` | io | opaque | Write | the run ending normally |
| `idr.crash` | `Crash` | io | opaque | Write | the run ending by a crash |
| `idr.divergence` | `Divergence` | crash | opaque | Write | the run never ending |

Invariants the op declarations rely on (vocabulary §6's laws, each a
type of the specification): L2 (no addressable under opaque), L3 (a
resource takes only its kinds; a value effect only on an addressable
one), L6 (an acquisition on `heap` names its result; memory no value
names is the meaning's fact), L7 (a terminator with no successor writes
`crash` or `exit`), L8 (whatever writes `exit` writes `io`), L9 (only
`io` writers change runtime state), L10 (an acquisition carries no
crash). No op of today needs a resource beyond the tree: the handle
table's own memory and the persist walk's stack are the meaning's fact,
the live-cell counter is deleted, terminal modes are `io`.

### 2.2 The forms of declaration and the typed rules

Exactly one form per op: **static** (a list of effects, possibly
empty), **typed** (rules, some unconditional), **recursive** (its
regions' effects plus its own, static or typed: the form needs that
correction, §1.11), **runs unknown code** (every ordering atom's call
effects: `force`, `apply`), **definition** (`func`, `program`).

The typed rules after C3 and this lane's corrections; each condition is
read off one value's own type, never off a producer or a use:

| rule | effect | on each value of the group whose type is | replaces |
| --- | --- | --- | --- |
| `Consumes g` | `Read` and `Free` on `count` (upstream's transform form) | owned (`own` or `excl`) | `consumedEffects` (`Effects.cpp:96-105`), `ConsumesOperands`, the call's and con's hand bodies |
| `NewIdentity g` | `Allocate` on `identity` | owned, linear (`!idr.lin`), or of an `in_place` data type | `LinResource` on `lin.enter`, `lin.use`, `Call.cpp:69-71`; con's identity under C3; I1 |
| `Acquires g` | `Allocate` on `heap` | owned (after counting); nothing on an unrestricted value | the builders' `MemAlloc` on the root (I2) |
| `ReadsMemo g` | `Read` on `memo_state` | a memo sum | `readsMemoState` (`Effects.cpp:79-84`) |
| `CountsIfShared g` | `Read` and `Write` on `count` | owned but not exclusive, and holding a count (no token) | `drop`'s and `take`'s unconditional count effects (D10, I4) |
| `Recycles` | `Allocate` on `identity` of the result when the token is exclusive, else on `heap` | the token's grade | the vocabulary's `IfMayBeNull`: a token may be null exactly when it is not exclusive (`Conversion/Cells.cpp:123-140`) |
| `Summarized` | each ordering atom of the call's row as its call effects | the call's row (L02's) | `rows` (`Func.cpp:250-256`) |
| `ReleasesForeign g` (C2 R5, no producer yet) | `Write` on `io` | may reach a foreign cell | — |

`Scratch` is renamed by what it is, the meaning's fact **`RuntimeMemory`**:
the runtime function may acquire or give back memory no value names,
during or beyond the call; it reports `alloc` and `free` and is never an
MLIR effect (L6).

### 2.3 Every op of today, declared

Legend: `R`/`W`/`A`/`F` are upstream's `Read`, `Write`, `Allocate`,
`Free`; a resource alone is an op-level effect, `contents(%v)` an
effect on the value `%v`; `+RM` marks the meaning's `RuntimeMemory`.
Form: `S` static, `T` typed, `Rc` recursive (`Rc+T` with a typed own
part), `U` runs unknown code, `D` definition, `del` deleted or folded
(with the ruling or improvement that removes it). "Today" gives the
current declaration only where it differs in more than the resource's
name. Evidence is the runtime function or the lowering; paths under
`runtime/` or `foreign/idr/lib/Conversion/`.

**Program, functions, values** (`IdrOps.td`, `IdrMatchOps.td`)

| op | form | declaration | today | runtime or lowering (read) |
| --- | --- | --- | --- | --- |
| `program` | D | none: never executed | none | — |
| `func` | D | none; its row is L02's | none | — |
| `call` | T | `Summarized`; `Consumes args`; `NewIdentity results` | hand body: bits, consumption, `LinResource` on linear results only (`Call.cpp:65-72`) | the callee |
| `return` | T | `Consumes operands` | `ConsumesOnly` | moves values out |
| `yield` | T | `Consumes results` | `ConsumesOnly` | moves values to the parent's results |
| `constant` | S | none; an `in_place` data type has no constant (I1) | `Pure` | static data, count 0 (`Cells.cpp:263-272`) |
| `con` | T | `Consumes fields`; `NewIdentity result`; not speculatable when a field is owned | `Allocate` on root for a box, by hand (`OpsCon.cpp:50-56`) | after idr-rc-cells only cell-less: an atom (static) or an unboxed sum (`Cells.cpp:181-199`); a box's cell is `cell.new` (`Transforms/Ownership/Cells.cpp:29-50`) |
| `field` | T | `ReadsMemo value`; speculation as today | hand body (`OpsConReads.cpp:35-38`) | a load, or a slot (`Cells.cpp:242-261`) |
| `tag` | T | `ReadsMemo value` | hand body (`:157-160`) | a header or slot load (`Cells.cpp:219-240`) |
| `match` | Rc+T | its regions; `ReadsMemo scrutinee` | hand body plus `RecursiveMemoryEffects` | — |
| `match_lit` | Rc | its regions | as today | — |
| `dest.write` | T | `W contents(%dest)`; `Consumes value` | `Write` on root, no consumption | one store (`Cells.cpp:274-286`) |

**Ownership and cells** (`IdrOwnershipOps.td`)

| op | form | declaration | today | runtime or lowering (read) |
| --- | --- | --- | --- | --- |
| `dup` | S | `R count(%value)`, `W count(%result)` | `R`, `W` on root (`:74`) | `idris_rt_inc`: reads the count to saturate (`Rc/Counting.cpp:43-45`; `Counting.cpp:27-36`) |
| `drop` | T | `CountsIfShared value`; `F heap(%value)` | `R`, `W`, `F` on root, always (`:89`) | `dec`, release at 0 (`Rc/Counting.cpp:47-53`); a token's: `idris_rt_free_cell`, no count (`Counting.cpp:42-56`, `Rc/Counting.cpp:67-74`) |
| `borrow` | S | none | `Pure` | no runtime form |
| `share` | T | `Consumes value` | `ConsumesOnly` | no runtime form |
| `cell.new` | S | `A heap(%cell)` | `A` root, full | `idris_rt_cell` (`Cells.cpp:66-82`) |
| `cell.stack` | S | `A frame(%cell)` | as today | a frame slot (`Cells.cpp:84-107`) |
| `cell.recycle` | T | `Consumes token`; `Recycles` | `F` root on the token, `A` root stage 1 | the token, or a new cell when null (`Cells.cpp:109-147`) |
| `cell.init` | T | `W contents(%cell)`; `Consumes fields` | `W` root, no consumption | stores the fields (`Cells.cpp:150-178`) |
| `take` | T | `Consumes value`; `CountsIfShared value` | `R`, `W`, `F` on root | exclusive: no test, no count of the box; shared: `is_unique`, `inc` fields, `dec` box (`Counting.cpp:65-110`) |
| `unpack` | T | `Consumes value` | `ConsumesOnly` | slots move out (`Cells.cpp:204-216`) |
| `own.adopt` | T | `NewIdentity result` (L12) | `Pure` | no runtime form |
| `own.give` | T | `Consumes value` | hand body (`OpsOwnership.cpp:232-235`) | no runtime form |
| `lin.enter` | S | `A identity(%result)` | `A` on `LinResource` | no runtime form |
| `lin.use` | S | `A identity(%result)` | `A` on `LinResource` | no runtime form |

**Closures and suspensions** (`IdrClosureOps.td`; legal before
idr-defunctionalize only, so before counting)

| op | form | declaration | today | runtime or lowering (read) |
| --- | --- | --- | --- | --- |
| `closure` | T | `Consumes captures`; `NewIdentity result` (fires only on a linear closure, `Idr_LinearWhenACaptureIs`, `:22`) | `ConsumesOnly`; no allocation (F4) | becomes a con of its sum |
| `suspend` | T | as `closure` | as `closure` | becomes a con of its memo sum |
| `delay` | T | `Consumes value`; `NewIdentity result` | as `closure` | as `suspend` |
| `force` | U | every ordering atom | `W` crash, divergence, IO; no `Read` (02 E31) | a call of its sum's dispatch |
| `apply` | U | every ordering atom | none (unknown) | a dispatch |
| `memo.run` | Rc | its region; `R memo_state(%cell)`, `W memo_state(%cell)`, `W count(%cell)` (F2); `+RM` | hand body: memo state only (`OpsClosures.cpp:258-265`) | loads captures, writes `Running` then `Forced`, then `idris_rt_persist_held` (`MemoCells.cpp:53-108`; `Rc/Counting.cpp:81-86`, `Rc/Freeing.cpp:161-188`) |

**Checks and program ends** (`IdrCheckOps.td`)

| op | form | declaration | today | runtime or lowering (read) |
| --- | --- | --- | --- | --- |
| `crash` | S | `W crash`; a terminator (03 R4; D38's `crash_at`) | `W` crash and IO, `NoReturn`, then `ub.unreachable` | flush, message, exit (`Io/Ending.cpp:66-71`) |
| `crash_str` | S | `W crash`; a terminator | as `crash` | the string's bytes (`Ending.cpp:73-76`) |
| `may_loop` | S | `W divergence` | `W` divergence and IO | `llvm.sideeffect` (`Runtime.cpp:205-210`) |
| `check.nonzero` | S | `W crash`; result the operand refined | `W` crash and IO | a test and a crash (`Conversion/Checks.cpp:104-130`) |
| `check.in_bounds` | S | as `check.nonzero` | as above | as above |
| `check.nonempty` | S | as `check.nonzero` | as above | as above |
| `check.finite` | S | as `check.nonzero` | as above | as above |
| `check.range` | S | as `check.nonzero` | as above | as above |

**Arrays** (`IdrArrayOps.td`)

| op | form | declaration | today | runtime or lowering (read) |
| --- | --- | --- | --- | --- |
| `tabulate` | Rc | its region (D43 adds its destination's `W contents`, L12's) | as today | — |
| `tabulate_io` | del | merged into `tabulate` (D20) | `PerformsIO`, world | — |
| `fold_last` | Rc | its region | as today | — |
| `scan_last` | Rc | its region | as today | — |
| `transpose` | S | none | `Pure` | — |
| `array.yield` | T | `Consumes values` (L11) | `Pure` | moves into the yield targets |
| `array.new` | T | `A heap(%array)`; `Consumes fill`; `W count(%fill)` (L7) | `A`, `W` on root of the result, world | `idris_rt_array_new`, an `inc` of the fill per element, one `dec` after (`Arrays.cpp:110-150`) |
| `array.get` | S | `R contents(%array)`; `W count(%value)` | `R` root, `TakesReference`, world | load, `inc` the element (`Arrays.cpp:198-210`) |
| `array.set` | T | `R contents(%array)`, `W contents(%array)`; `W count(%array)`, `F heap(%array)` (L6); `Consumes value` | `R`, `W` root, world | releases the old element (`Arrays.cpp:211-223`) |
| `array.update` | Rc | its region; `R contents(%array)`, `W contents(%array)` | hand body on root (`OpsArrays.cpp:78-84, 185-188`), world | the element moves out and back, no count (`Arrays.cpp:225-279`) |
| `element.update` | del | merged into `array.update` (D20) | hand body on root | as `array.update` |
| `nat.to_extent` | S | `W crash` | `W` crash and IO | "array too large" (`OpsArrays.cpp:242`) |
| `tie_shape` | S | none | `Pure` | no runtime form |

**Integers and naturals** (`IdrBigOps.td`; every result a small word or a
new bignum, `Big/Operands.cpp:29-45`; GMP temporaries through the
runtime's allocator, `Alloc/Gmp.cpp`, hence `+RM`)

| op | form | declaration | today | runtime (read) |
| --- | --- | --- | --- | --- |
| `big.add` | T | `Acquires result`; `+RM` | `A` root | `Big/Arithmetic.cpp:73-79` |
| `big.sub` | T | as `big.add` | `A` root | `:81-87` |
| `big.mul` | T | as `big.add` | `A` root | `:104-111` |
| `big.and` | T | as `big.add` | `A` root | `Big/Bitwise.cpp:99-104` |
| `big.or` | T | as `big.add` | `A` root | `:105-110` |
| `big.xor` | T | as `big.add` | `A` root | `:111-116` |
| `big.shl` | T | as `big.add`; the runtime copies at 0 (F1) | `A` root | shares by 0 (`:29-33`) |
| `big.shr` | T | as `big.shl` | `A` root | shares by 0 (`:48-53`) |
| `big.div` | T | as `big.add`; `GuardedOp` | `A` root | `Arithmetic.cpp:112-129` |
| `big.mod` | T | as `big.div` | `A` root | `:131-139` |
| `big.neg` | T | as `big.add` | `A` root | `:141-148` |
| `big.pred` | T | as `big.add` | `A` root | `:89-93` |
| `big.cmp` | S | none | `Pure` | `Big/Compare.cpp:28` |
| `nat.to_big` | T | `Consumes value` | `ConsumesOnly` | no runtime form |
| `nat.from_big` | T | `W count(%result)` when owned; no `Allocate` (F1) | `A` root | the operand with one more reference, or a small word (`Arithmetic.cpp:64-69, 95-102`) |
| `big.from_sint` | T | `Acquires result`; `+RM` | `A` root | `Big/Conversions.cpp:18-20` |
| `big.from_uint` | T | as `big.from_sint` | `A` root | `:28-32` |
| `big.small` | S | none | `Pure` | `Big/Words.cpp:30` |
| `big.to_int` | S | none | `Pure` | `Conversions.cpp:36-42` |
| `big.from_double` | T | `Acquires result`; `+RM`; `GuardedOp` | `A` root | `:46-52` |
| `big.to_double` | S | none | `Pure` | `:59-82` (a read-only view) |
| `big.show` | T | `Acquires result`; `+RM` | `A` root | `Big/Digits.cpp:35-48` |
| `big.from_str` | T | `Acquires result`; `+RM` | `A` root | `:54-67` (scratch text, `:19-30`) |

**Fixed-width integers and doubles** (`IdrScalarOps.td`; D41 keeps each
as an op of one meaning)

| op | form | declaration | today | runtime or lowering (read) |
| --- | --- | --- | --- | --- |
| `divs` | S | none; `GuardedOp` | as today | D41's template |
| `divu` | S | none; `GuardedOp` (03 §5.3 proposes `arith.divui`) | as today | inline |
| `mods` | S | none; `GuardedOp` | as today | D41's template |
| `modu` | S | none; `GuardedOp` (as `divu`) | as today | inline |
| `shls` | S | none | `Pure` | D41's template |
| `shlu` | S | none | `Pure` | D41's template |
| `shrs` | S | none | `Pure` | D41's template |
| `shru` | S | none | `Pure` | D41's template |
| `to_char_s` | S | none | `Pure` | D41's template |
| `to_char_u` | S | none | `Pure` | D41's template |
| `to_int` | S | none; `GuardedOp` | as today | `Doubles/Truncation.cpp:13` |
| `double_head` | S | none | `Pure` | `Doubles/Printing.cpp:112` |
| `int_head_s` | S | none | `Pure` | `Strings/Show.cpp:28` |
| `int_head_u` | S | none | `Pure` | `Strings/Show.cpp:33` |

**Strings** (`IdrStringOps.td`; a result of no bytes is the static
empty string, benign, `Strings/Making.cpp:18-22`)

| op | form | declaration | today | runtime (read) |
| --- | --- | --- | --- | --- |
| `str.append` | T | `Acquires result`; the runtime copies an empty side (F1) | `A` root | shares on an empty side (`Strings/Concat.cpp:28-41`) |
| `str.cons` | T | `Acquires result` | `A` root | `Concat.cpp:43-52` |
| `str.from_char` | T | `Acquires result` | `A` root | `:54-56` |
| `str.pack` | T | `Acquires result` | `A` root | `idris_rt_str_alloc`, puts (`Conversion/Strings.cpp:87-133`) |
| `str.concat` | T | `Acquires result` | `A` root | as `str.pack` |
| `io.put_list` | S | `R io`, `W io` | as today, `PerformsIO`, world | puts the list's text (`Conversion/Strings.cpp:135`) |
| `str.show_sint` | T | `Acquires result` | `A` root | `Strings/Show.cpp:12-17` |
| `str.show_uint` | T | `Acquires result` | `A` root | `:19-24` |
| `str.show_double` | T | `Acquires result` | `A` root | `Doubles/Printing.cpp:119` |
| `str.substr` | T | `Acquires result` | `A` root | always new or the static empty (`Strings/Scalars.cpp:63-71, 104-112`) |
| `str.reverse` | T | `Acquires result` | `A` root | the empty string shared, benign (`:115-119`) |
| `str.tail` | T | `Acquires result`; `GuardedOp` | `A` root | `:91-96` |
| `str.length` | S | none | `Pure` | `:75-78` |
| `str.bytes_length` | S | none | `Pure` | `Making.cpp:63-65` |
| `str.scalar_at` | S | none | `Pure` | `Scalars.cpp:142-146` |
| `str.drop_bytes` | T | `Acquires result`; the runtime copies at offset 0 (F1) | `A` root | shares at 0 (`:154-162`) |
| `str.scalar_bytes` | S | none | `Pure` | `:148-153` |
| `str.index` | S | none; `GuardedOp` | as today | `:80-84` |
| `str.head` | S | none; `GuardedOp` | as today | `:86-90` |
| `str.cmp` | S | none | `Pure` | `Strings/Order.cpp:15` |
| `str.to_int` | S | none | `Pure` | `Numerals/Machine.cpp:12` |
| `str.to_double` | S | none | `Pure` | `Doubles/Parsing.cpp:29` |

**IO and buffers** (`IdrIOOps.td`; every IO op loses its world, D20)

| op | form | declaration | today | runtime (read) |
| --- | --- | --- | --- | --- |
| `io.put_str` | S | `R io`, `W io` | as today | the output buffer (`Io/Output.cpp:142-144`) |
| `io.put_char` | S | `R io`, `W io` | as today | `:151-154` |
| `io.put_sint` | S | `R io`, `W io` | as today | `:158-163` |
| `io.put_uint` | S | `R io`, `W io` | as today | `:165-170` |
| `io.put_double` | S | `R io`, `W io` | as today | `:173-176` |
| `io.get_byte` | S | `R io`, `W io` | as today | the input buffer (`Io/Input.cpp:101-110`) |
| `io.get_line` | T | `R io`, `W io`; `Acquires str`; `+RM` | `A` root, IO | scratch line, a new string (`:117-131`) |
| `io.write_bytes` | S | `R io`, `W io`; `R contents(%buffer)` | `R` root on the buffer | `Io/Bytes.cpp:20-31` |
| `io.read_bytes` | S | `R io`, `W io`; `W contents(%buffer)` | `W` root on the buffer | `:33-42` |
| `io.eof` | S | `R io`, `W io` | as today | stream state; EBADF saved (`Io/Files.cpp:110-112`) |
| `io.n_processors` | S | `R io`, `W io` | as today | `Io/Processors.cpp:12` |
| `os` | S | none (folded from the target's entry, C8) | `Pure` | — |
| `io.buffer_load` | S | `R contents(%buffer)` | `R` root, `PerformsIO`, world | inline load |
| `io.buffer_store` | S | `W contents(%buffer)` | `W` root, world | inline store |
| `io.buffer_copy` | S | `R contents(%src)`, `W contents(%dst)` | root, world | `memmove` (`Io/Buffer.cpp:13-18`) |
| `io.buffer_set_string` | S | `W contents(%buffer)` | root, world | `memcpy` (`:20-24`) |
| `io.buffer_get_string` | T | `R contents(%buffer)`; `Acquires str` | `R`, `A` root, world | `:26-33` |
| `world.new` | del | `io.unsafe_run`, a recursive region op (D20) | `W` IO | no runtime form |

**The platform** (`IdrPlatformOps.td`; "IO" below is `R io`, `W io`)

| op | form | declaration | today | runtime (read) |
| --- | --- | --- | --- | --- |
| `io.file_open` | S | IO; `+RM` (path scratch, table growth) | IO | `Io/Files.cpp:79-93`; `Io/Handles.cpp:75-84, 180-191` |
| `io.file_close` | S | IO; `+RM` (slot release, `fclose`) | IO | `Files.cpp:99`, `Handles.cpp:207-212` |
| `io.file_error` | S | IO | IO | `Files.cpp:103-105` |
| `io.file_errno` | S | `R runtime_state` (L9) | IO | the saved errno only (`Io/Errors.cpp:33-44`) |
| `io.file_read_line` | S | IO; `+RM` (a string slot) | IO | `Io/Lines.cpp:31-43` |
| `io.file_read_chars` | S | IO; `+RM` | IO | `Lines.cpp:50-63` |
| `io.file_read_char` | S | IO | IO | `Lines.cpp:68-71` |
| `io.file_write_line` | S | IO | IO | `Lines.cpp:86-88` |
| `io.file_flush` | S | IO | IO | `Files.cpp:117-119` |
| `io.file_seek_line` | S | IO | IO | `Lines.cpp:75-81` |
| `io.file_remove` | S | IO; `+RM` | IO | `Files.cpp:122-128` |
| `io.file_size` | S | IO | IO | `Files.cpp:143-148` |
| `io.file_poll` | S | IO | IO | `Files.cpp:153` |
| `io.file_is_tty` | S | IO | IO | `Files.cpp:157-159` |
| `io.file_time` | S | IO; `+RM` (a times slot) | IO | `Io/FileTimes.cpp:32-44` |
| `io.file_atime_sec` | S | IO (reads a slot, saves EBADF: `runtime_state` written, so `io`, L9) | IO | `FileTimes.cpp:19-22, 48` |
| `io.file_atime_nsec` | S | as `io.file_atime_sec` | IO | `:49` |
| `io.file_mtime_sec` | S | as `io.file_atime_sec` | IO | `:50` |
| `io.file_mtime_nsec` | S | as `io.file_atime_sec` | IO | `:51` |
| `io.file_ctime_sec` | S | as `io.file_atime_sec` | IO | `:52` |
| `io.file_ctime_nsec` | S | as `io.file_atime_sec` | IO | `:53` |
| `io.file_chmod` | S | IO; `+RM` | IO | `Files.cpp:132-138` |
| `io.dir_current` | S | IO; `+RM` | IO | `Io/Directories.cpp:18-28` |
| `io.dir_change` | S | IO; `+RM` | IO | `:31-37` |
| `io.dir_create` | S | IO; `+RM` | IO | `:41-47` |
| `io.dir_remove` | S | IO; `+RM` | IO | `:51-55` |
| `io.dir_open` | S | IO; `+RM` | IO | `:60-72` |
| `io.dir_close` | S | IO; `+RM` | IO | `:76-79` |
| `io.dir_entry` | S | IO; `+RM` (the kept string refilled) | IO | `:87-97`, `Handles.cpp:199-203` |
| `io.arg_count` | S | none (argv fixed) | IO | `Io/Process.cpp:29`; `Start/Entry.cpp:109` |
| `io.arg` | T | `Acquires str` | `A` root, IO | a new string per call (`Entry.cpp:111-113`) |
| `io.env_get` | S | IO; `+RM` (the environment slot refilled) | IO | `Process.cpp:19-25, 39-42` |
| `io.env_pair` | S | IO; `+RM` | IO | `:46-48` |
| `io.env_set` | S | IO; `+RM` | IO | `:52-62` |
| `io.env_unset` | S | IO; `+RM` | IO | `:65-71` |
| `io.sleep` | S | IO | IO | `:75-78` |
| `io.usleep` | S | IO | IO | `:81-84` |
| `io.time` | S | IO | IO | `:87` |
| `io.pid` | S | none (fixed for the run, L9) | IO | `:90` |
| `io.exit` | S | IO; `W exit`; a terminator (D14) | IO, `NoReturn`, then `ub.unreachable` | flush, handles released, status checked (`Ending.cpp:56-61`) |
| `io.term_raw` | S | IO | IO | `Io/Terminal.cpp:12-21` |
| `io.term_reset` | S | IO | IO | `:24` |
| `io.term_setup` | del | nothing to declare: an empty function (L9) | IO | `:26-27` |
| `io.term_cols` | S | IO | IO | `:31-36` |
| `io.term_lines` | S | IO | IO | `:38-43` |
| `io.errno` | S | `R runtime_state` | IO | `Errors.cpp:27` |
| `io.strerror` | T | `Acquires str` (no world, no `io`) | IO, `A` root | the C library's text, a new string (`Errors.cpp:48-51`) |
| `io.clock_monotonic` | S | IO (time moves; errno saved on failure) | IO | `Io/Clock.cpp:23-41` |
| `io.clock_utc` | S | IO | IO | `:44` |
| `io.clock_process` | S | IO | IO | `:47-49` |
| `io.clock_thread` | S | IO | IO | `:52` |
| `io.clock_gc_cpu` | del | the constant -1 (L9) | IO | `:57` |
| `io.clock_gc_real` | del | the constant -1 (L9) | IO | `:58` |
| `io.clock_valid` | del | `arith` on the word (L9) | IO | `:61` |
| `io.clock_second` | del | `arith` on the word (L9) | IO | `:64-66` |
| `io.clock_nanosecond` | del | `arith` on the word (L9) | IO | `:69-71` |
| `handle.is_null` | S | none | `Pure` | `Handles.cpp:228-230` |
| `handle.string` | T | `R runtime_state`; `W crash` (L5); `W count(%str)` when owned (F1); no `Allocate` | `R` IO, `A` root | the slot's string with one more reference, or a crash (`Handles.cpp:235-243`) |
| `io.handle_free` | S | IO; `+RM` (the slot's string released) | IO | `Handles.cpp:248-263` |

### 2.4 Ops the design adds, and their declarations

| op | ruling | form | declaration |
| --- | --- | --- | --- |
| `io.unsafe_run` | D20 | Rc | its region (a trusted library's forged world: its IO in the demanding function's row) |
| one crash terminator, `idris_rt_crash_at` | D38, 03 R4 | S | `W crash` |
| `io.exit` as a terminator, no result | D14 | S | IO; `W exit` |
| `is_unique` | C §5.5 | T | `R count(%value)` unless exclusive, where it folds to true |
| `idr.join`, `idr.jump` | D25 | Rc; T | the join: its body; the jump: `Consumes` its arguments, a terminator |
| `idr.lifetime` | D40 | Rc | its region; giving the lifetime's cells back at its end is `RuntimeMemory`-like reporting of `free` (L05's) |
| `lin.cast` (`lin.enter` with `lin.use`) | 03 §5.3 | S | `A identity(%result)` |
| one `io.clock <kind>` | 03 §5.3 | S | IO |

### 2.5 Constructor provenance

| fact the declarations depend on | constructed by | who alone may |
| --- | --- | --- |
| the tree: resources, parents, reach, admitted kinds | `Spec.Effects` (D16, D27, D28) | the specification; the generated C++ classes are its output |
| each op's one declaration (form, effects, rules) | the op's entry in the specification | the specification; no hand `getEffects` (effects.md 1.10 (a)) |
| owned and exclusive grades (`Consumes`, `CountsIfShared`, `Recycles`, `Acquires`, `NewIdentity`) | idr-rc-grades, idr-rc-exclusive (`Pipeline.cpp:38-48`) | those steps; verified after every pass |
| linearity (`!idr.lin`, `NewIdentity`) | the frontend, from Idris's quantity 1 | the frontend; `lin.enter`/`lin.use` folds as today |
| `in_place` kind (`NewIdentity`, the constant rule) | the data type's kind, `SumKind::InPlace` (`IdrBase.td:121-125`), from the registry's `InPlaceType` (D24); under D48 the family attribute | the frontend; never inferred from use |
| memo sums (`ReadsMemo`) | idr-defunctionalize | that pass |
| tokens (`CountsIfShared`'s no-count case, `Recycles`) | `take` | idr-rc |
| a runtime function's behaviour | `runtime/` (its documented semantics are the meaning, AGENTS.md) | the runtime; the declaration restates it and `tests/runtime-effects` (effects.md 4.4 step 1) holds them together |
| `RuntimeMemory` | the op's meaning in the specification | the specification |

### 2.6 Consumers, failure paths, cleanup

- Upstream: DCE, CSE and the canonicalizer read the declarations as
  §1.8's table says; `LocalAliasAnalysis` must not be run on `idr` ops
  until I5's patch is carried.
- Ours, each through the one API (L02's): `Sink`, `CaseOfCase`,
  `IdentitiesRecord`, `Bufferize` (`onlyAllocates`), MoveOut (its next
  write found by `contents` effects of the same array, no world),
  `Reshape::movable` (consumption on `count`, `identity`), the owned
  verifier's roles and `declaresSource` (`Allocate` on any resource, or
  a `W count` on the result: §1.12), `atMostCrashes` (writes on `crash`
  only), `observableRuns` (the row's `io`), idr-expect (I6).
- Failure paths: a declaration that breaks a law does not build (the
  specification); a row that says less than its ops fails V1 after the
  pass that made it (L02's); a declaration that disagrees with its
  runtime function fails `tests/runtime-effects` on the four targets.
  A declaration that under-states what its function does and passes
  both is a miscompile only a program test finds: the trust point,
  stated in vocabulary §6.

### 2.7 What it deletes (the op side)

`IdrInterfaces.td:87-92` (six resources), `:103-117`
(`MayCrashOpInterface`, `MayCrash`), `:292-308` (`PerformsIO`,
`ObservableIO`), `:310-316` (`ConsumesOperands`, `ConsumesOnly`);
`IdrBase.td:282-293` (`TakesReference`, `BuildsValue`);
`IdrCheckOps.td:19` (`NoReturn`), `:46-47` (`may_loop`'s IO write),
`:37-39, 88-90` (`getCrashCause`); `IdrClosureOps.td:101-103`;
`IdrDialect.h:58-99` (resource structs); `Traits.h:42-70, 82-91,
114-123` (`NoReturn`, `PerformsIO`, `ObservableIO`, `ConsumesOperands`,
`TakesReference`, `BuildsValue`); the hand `getEffects` bodies (`OpsCon.cpp:50-56`,
`OpsConReads.cpp:35-38, 157-160`, `OpsMatch.cpp:135-138`,
`OpsOwnership.cpp:232-235`, `OpsClosures.cpp:258-265`,
`OpsArrays.cpp:78-84, 185-188, 229-232`); `Call.cpp:69-71`;
`lib/IR/Effects.cpp:79-105`; `Expect/Allocation.cpp:27-30`;
`Reshape.cpp:300-304`'s `TypeID` compares; `Forms.cpp:51-62`'s crash
and IO test; `world.new`, `tabulate_io` and `element.update` (D20), and six of
L9's seven (`io.clock_gc_cpu`, `io.clock_gc_real`, `io.clock_valid`,
`io.clock_second`, `io.clock_nanosecond`, `io.term_setup`; `io.pid` is
kept, effect-free, and `io.file_errno` kept on `runtime_state`); `runtime/Alloc/Cells.cpp:157, 190, 195,
205, 223` (the live counter, a precondition, §1.4).

Essential distinctions that remain: memory written in place, counts and
memo state as three siblings under the heap; an identity apart from
memory; ending normally, crashing and never ending as three states;
runtime state a read-only child of the outside; the frame apart from
the heap; mutable memory (arrays, buffers) acquired where it is made
against immutable values acquired when counted (I2); Idris's sequencing
(the frontend's) against MLIR's effects; consumption (a reference
moved, `count`) against release (memory given back, `heap`).

### 2.8 Seams with other lanes

- **L02** (rows, API, LLVM): compare `ResourceId`, never `isa` (§1.1);
  `RuntimeMemory` reports `alloc` and `free`; an op whose runtime
  function calls the C library (`fclose`, `closedir`) frees memory that
  existed before the call, so `io` alone must not yield `nofree` unless
  `free` is absent (§1.10 L8); the row's spellings are D29's.
- **L03** (specification shape): `Recursive` takes a typed own part
  (§1.11); `Kind`'s and `Atom`'s constructors collide in one namespace
  (§1.6); the constructor `IO` (§1.6).
- **L04** (families): the `in_place` kind and "may reach a foreign
  cell" are facts of the family attribute, computed when the type is
  made; `#idr.con` of an `in_place` family is unwritable (I1).
- **L05** (lifetimes): under D40 `dup` and `drop` of a `static` value
  touch no count and should not be written at all; `idr.lifetime`'s
  release.
- **L07** (counting): the exclusive `take` and `drop` lowered with no
  count read (I4); the token drop's run-time `isCounted` test
  (`Rc/Counting.cpp:72`) is a static fact.
- **L11** (runtime): copying on the share edges (F1), the live counter
  (§1.4), D37's exit status (§1.4), `persist_held`'s branch on count 0
  is a static fact once a memo cell's lifetime is typed.
- **L12** (arrays): `array.set` and `array.new` as declared here;
  `tabulate`'s destination effect.
- **L13** (ops, canonicalization): the L9 deletions; record eta and the
  constant fold off for `in_place` results (I1).
- **L19** (tests): `no-heap-allocation` and `builds` before counting
  (I6).

## 3. QTT

- **Quantity 0** enters no effect: an erased index, proof or field is
  no value (AGENTS.md), so no operand names it and no rule reads it.
  Every condition of §2.2 reads a grade or a kind, never an index (D48's
  indices refine matches, not effects).
- **Quantity 1** is the identity resource. Before counting a linear
  value is affine in the IR ("used at most once on every path",
  `Verify/Linearity.cpp:4`), so dropping its only use needs no effect:
  DCE may delete a dead consumer and then the dead `lin.enter`. After
  counting ownership is exact ("exactly once on every path",
  `Verify/Owned.cpp:4`) and `Consumes` keeps every consuming op alive.
  A quantity-1 operand's consumption is `Read` and `Free` on `count`:
  the `Free` alone keeps an op undeletable and unmerged
  (`SideEffectInterfaces.cpp:77-93`, `CSE.cpp:264-269`), and the `Read`
  claims a count read no take-over makes; kept as upstream's transform
  form, an *optional simplification* to drop. Uses of a value before its
  consumption are ordered by the owned verifier, not by resources: a
  `contents` access and a consumption are siblings, and a pass that
  moved the access past the consumption fails the owned verifier ("every
  use of it comes before the owner's consuming use on each path",
  `IdrOwnershipOps.td:93-96`).
- **ω**: an unrestricted value is a value, pure before counting (C3).
- **Exclusive** (`!idr.excl`, proved): what the type proves is no longer
  paid. An exclusive `drop` frees with no count read; an exclusive
  `take` reads and writes no count of the box; an exclusive token's
  recycle acquires nothing; `is_unique` folds (I4). Today only the drop
  reads the count against its type (12 CV-32) and the declarations of
  `take` and `recycle` claim count traffic the exclusive lowering never
  emits (`Counting.cpp:87-92`, `Conversion/Cells.cpp:123-127`).
- **Static lifetime** (D40): a static value holds count 0 and every
  count op on it is a run-time no-op today (`idris_rt_inc` and `dec` test
  it); once `static` is in the grade, a `dup` or `drop` of it is
  unwritable (L05's), so no declaration needs the case.
- **`in_place`** (the D24 kind): the promise reads exclusivity at the
  call, a fact the optimizer can falsify if it merges, folds or
  eta-reduces the value's producer. Its identity belongs to the producer
  (I1): the quantity-1 parameter is the callee's fact, the identity of
  the argument the caller's, and the type is where the caller's fact can
  be kept.
- **Lost today**: `lin.enter` and `lin.use` fold away "an entry used at
  once" (`IdrOwnershipOps.td:388-399`), by design: nothing ran in the
  linear position. The call's identity covers linear results only
  (`Call.cpp:69-71`), not owned ones; C3's rule covers both.
- **Misuse made unwritable** by this lane's corrections: an `in_place`
  constant (I1); a consumer that is `Pure` (L11, L12: the typed rule is
  the only way to say "takes over"); a runtime op whose declaration
  omits a crash its function makes (§2.5's provenance and the runtime
  test).

## 4. Improvements

### I1. An `in_place` value's identity is its producer's

- *Evidence.* D24: the promise binds "the program as the frontend wrote
  it", and a call "the exclusivity analysis cannot prove exclusive is
  `unsupported (uniqueness)`" (decision). Exclusivity is proved after
  the optimizer: CSE runs twice before idr-rc (`Pipeline.cpp:92-95,
  115-118`, read), then idr-rc-exclusive and idr-demand (`:47, 130`).
  CSE merges memory-effect-free ops (`CSE.cpp:264-280`). Today a call of
  a `total` callee declares nothing but linear results' identity
  (`Call.cpp:65-72`), so it is memory-effect-free; under C3 so is every
  con of an unrestricted value. `ConOp::fold` turns a con of constants
  into a constant and rebuilds a record from its own fields into the
  value (`OpsCon.cpp:106-120`, read); a constant is static data, count
  0, never exclusive.
- *Counterexample* (*conjecture*, unbuilt). `tests/uniqueness-shared-rebuild/near/Main.idr`
  with `build` made total by structural recursion on `Nat` (`build Z acc
  = acc; build (S k) acc = build k (MkBang (cast k) :: acc)`): both
  `build n []` calls are equal and pure, CSE merges them, `bump` and
  `sumL` share one list, and idr-demand refuses `bump`'s call (the
  message of the refused neighbour, `Main.idr:1-2`), though the program
  as written passes each list once. Equally, `bump [MkBang 1, MkBang 2]`
  folds to a static constant and is refused.
- *Root cause.* A fact of the program as written (each list a fresh
  value) is held nowhere the optimizer reads; the identity rule reads
  quantity and ownership but not the kind whose promise reads identity.
- *Correction.* `NewIdentity` fires on a value of an `in_place` data
  type (its kind is in its type, `IdrBase.td:121-125`); the `#idr.con`
  attribute of an `in_place` data type is unwritable, so the constant
  fold cannot produce one; record eta does not replace a con whose
  result is `in_place` (an essential case: the promise reads the
  identity eta would erase).
- *Deletes.* Nothing; it closes a refusal an optimization adds
  (AGENTS.md: "a refusal an optimization can add or remove").
- *Discriminated by* the two near cases above as tests of
  `tests/uniqueness-shared-rebuild/near`, each expected to compile (exit
  0) and print its sums; they fail before (refused) and pass after.
- *Coordinator* (AGENTS.md settles it: acceptance is a property of the
  program).

### I2. C3's principle for every immutable value a runtime function builds

- *Evidence.* C3's heading: "building a value acquires nothing before
  counting"; its reason, compile-time hash-consing of immutable values
  (decision). Strings and bigs are immutable and uncounted before
  counting exactly as boxes are (`Idr_StrValue`, `Idr_BigValue`:
  "plain before idr-rc and owned after it", `IdrTypes.td:321-329`,
  read). Today two equal `big.add %a, %b` never merge: `Allocate` on the
  result is not a `Read` (`CSE.cpp:264-269`).
- *Counterexample.* `f : Integer -> Integer -> Integer; f a b = (a + b)
  * (a + b)` keeps two `idr.big.add %a, %b` through both CSE runs, two
  GMP additions and, for large operands, two cells where one value is
  meant (*conjecture* for the module the frontend emits).
- *Root cause.* "Acquires" is declared per op class for builders and per
  stage for constructors: one fact, two rules.
- *Correction.* Every runtime function that builds an immutable value
  declares `Acquires result`: nothing while the result is unrestricted,
  `Allocate` on `heap` once it is owned. Mutable memory (`array.new`'s
  array, buffers) keeps `Allocate` where it is made: its identity is
  what later writes read (the Brooks line). At the lowering every result
  is owned, so each runtime call's LLVM facts stay a compile-time
  constant of its class at that stage.
- *Deletes.* The static `MemAlloc` on 33 builders' results; the
  asymmetry between §1.8's constructors and builders.
- *Discriminated by* a test property over the IR after canonicalize and
  CSE: one `idr.big.add` and one `idr.str.append` remain where two equal
  ones were written, and the program's output is unchanged.
- *Coordinator* (C3's own principle; the owner's "pinnacle of
  optimization").

### I3. Every declaration is what its runtime function does

- *Evidence.* §1.9, §1.10: `handle.string`'s crash, `array.set`'s
  release, `array.new`'s fill, `array.yield`'s and `own.adopt`'s
  take-over and identity, `nat.from_big`'s and the shifts' and string
  builders' shares, runtime-held memory, seven IO actions that observe
  nothing.
- *Counterexample.* `do let s = getString nullPtr; putStrLn "ok"`
  (trusted base code): `handle.string` is unused, a lone `Read`, so the
  canonicalizer deletes it and the program prints "ok" where eager
  evaluation crashes first (D13). And an `array.set` in a callee moves a
  caller's `is_unique` of the old element across the call once the root
  is gone.
- *Root cause.* Declarations were written against the root, which hid
  every omission; the runtime's behaviour was never read per op (02 §8,
  effects.md 4.4).
- *Correction.* §2.3's declarations; the shares made exact by the
  runtime copying on its edge cases (the vocabulary's choice, measured
  first), except `nat.from_big`, which is a forwarding op and declares
  the count write on its result; `RuntimeMemory` replacing `Scratch`
  with the scope "memory no value names"; the seven observing-nothing
  actions folded or made effect-free.
- *Deletes.* `io.term_setup`, `io.clock_gc_cpu`, `io.clock_gc_real`,
  `io.clock_valid`, `io.clock_second`, `io.clock_nanosecond` as ops; the
  `Pure` on `array.yield` and `own.adopt`.
- *Discriminated by* `tests/runtime-effects` (effects.md 4.4 step 1:
  each runtime symbol's inferred attributes against its declaration, on
  the four targets) and a program test that crashes on a null
  `getString` whose result is unused.
- *Coordinator.*

### I4. Exclusivity in the declarations of `take`, `drop`, `cell.recycle`

- *Evidence.* The exclusive lowering emits no count traffic
  (`Counting.cpp:87-92`, `Conversion/Cells.cpp:123-127`, read); the
  vocabulary makes only `drop` typed by it.
- *Counterexample.* An exclusive `take` declared `Read`, `Write` on
  `count` of its box conflicts with a `dup` of an unrelated owned value
  in the same block for every query that asks resources only (CSE's
  write scan is resource-level, `CSE.cpp:213-233`), so a read-only op
  (an `is_unique`) is not merged across it.
- *Root cause.* A fact the type proves (exclusive) was not read by the
  declaration.
- *Correction.* `CountsIfShared` on `drop` and `take`; `Recycles` on
  `cell.recycle`.
- *Deletes.* The unconditional count effects on the three ops.
- *Discriminated by* a property test: in a function whose takes are all
  exclusive, the row holds no `count` atom.
- *Coordinator* (D10).

### I5. The identity resource and upstream's alias analysis

- *Evidence.* §1.1's last item.
- *Counterexample.* `-test-alias-analysis` (upstream's test pass) over
  `idr.func @f(%a: !idr.box<!L>) { %l = idr.lin.enter %a ... }` answers
  NoAlias for `(%l, %a)` (*conjecture* from the code read).
- *Root cause.* Upstream reads every `Allocate` on a value as fresh
  memory, though its own transform dialect allocates handles that are
  no memory.
- *Correction.* The vocabulary's premise is restated: `Allocate` on
  `identity` names a fresh identity, not fresh memory. The first pass of
  ours that adopts `LocalAliasAnalysis` carries an upstream patch, with
  its report, reproducer, `tests/upstream-<bug>` and PINS.md entry,
  under which `getAllocEffectFor` takes an allocation as a distinct
  object only on a resource that holds memory (a `Resource` hook,
  default true; `identity` and the transform dialect's mapping answer
  false).
- *Deletes.* Nothing now.
- *Discriminated by* the upstream test above, failing before the patch
  and passing after.
- *Coordinator* (AGENTS.md: an upstream gap is patched upstream, when
  something reaches it).

### I6. Heap-freedom is a fact of the counted program

- *Evidence.* §1.8's table: `no-heap-allocation` and `builds` read
  constructors' acquisitions before counting, which C3 removes.
- *Counterexample.* `tests/canon-record-eta/canon-record-eta.mlir:11`
  expects `no-heap-allocation=@reindex` to fail on stage `first`; under
  C3 it holds, and the test flips.
- *Root cause.* A test property asked a layout question of the value
  level.
- *Correction.* The property holds over the counted program, where
  every acquisition is an op (`cell.new`, `Acquires` on an owned
  result, `array.new`) and the row's `alloc` atom answers it in O(1)
  (vocabulary §2.4 item 1); before counting the question is layout's
  (D48). `builds` reads the constructor family (a field of the op in the
  specification), never an effect.
- *Deletes.* The closure and suspension exceptions
  (`Expect/Allocation.cpp:27-30`); `Idr_BuildsValue`.
- *Discriminated by* the restated tests (L19 decides each one's fate
  under the testing guideline).
- *Coordinator.*

### I7. What must land with the tree

- *Evidence.* §1.4: the live counter and D37's exit status.
- *Counterexample.* With the counter kept, `IDRIS_RT_LIVE=1` prints a
  different count when an unused `cell.new` is deleted; with today's
  `checkStatus`, `exitWith (ExitFailure 300)` exits 1 (a crash) while
  its declaration says it only exits.
- *Root cause.* Two runtime behaviours the declarations assume away.
- *Correction.* Both land no later than the tree and the derived row
  (which already land together, 02 §8).
- *Deletes.* `runtime/Alloc/Cells.cpp`'s counter and
  `idris_rt_live_cells`; `checkStatus`'s crash.
- *Discriminated by* the exit-status tests of D37 and the absence of
  `IDRIS_RT_LIVE` from the runtime.
- *Coordinator.*

## 5. Work units

Drafts for the implementation swarm; none is dispatched here.

1. **The tree, generated.** Write set: the specification's effects
   module under `compiler/spec/` (C7), its generated
   `foreign/idr/include/idr/IR/` resource header, and the deletions of
   `IdrInterfaces.td:87-92`, `IdrDialect.h:58-99`. Outcome: twelve
   resources as §2.1. Must not: name a resource anywhere else.
   Acceptance: the specification refuses an addressable resource under
   an opaque one; every effect in the dialect names a generated class.
2. **Declarations by family.** Write set: the op entries of the
   specification and the generated `.td` files; the deletions of §2.7's
   TableGen and hand bodies. Outcome: §2.3. Must not: write a
   `getEffects` by hand. Acceptance: the five suites and the invariant
   set pass on the four targets; `tests/runtime-effects` holds.
3. **The typed rules.** Write set: `foreign/idr/include/idr/IR/Traits.h`
   (the one `TypedEffects` trait) and the generated rule tuples. Outcome:
   §2.2's rules, conditions read off one type. Must not: walk a producer
   or a use. Acceptance: I1's and I4's tests.
4. **Consumers of "acquires" and "consumption".** Write set:
   `Transforms/Ownership/Reshape.cpp`, `IR/Verify/Owned.cpp`,
   `IR/Verify/OwnedOps.cpp`, `Transforms/StructureLoops/Forms.cpp`,
   `IR/Canon/MoveOut.cpp` (through L02's API). Outcome: each reads §2.6's
   facts. Must not: compare a resource's `TypeID` or use `isa` on our
   resources. Acceptance: the owned and linearity verifiers pass after
   every pass on the suites.
5. **The runtime made exact.** Write set: `runtime/Strings/Concat.cpp`,
   `runtime/Strings/Scalars.cpp`, `runtime/Big/Bitwise.cpp`,
   `runtime/Alloc/Cells.cpp`, `runtime/Start/Entry.cpp` (with L11).
   Outcome: no counted share on a builder's path; no live counter; D37's
   exit. Must not: change a primitive's documented meaning. Acceptance:
   the copy's cost measured on the benchmarks before and after; the
   program suite's outputs unchanged.
6. **The `in_place` identity.** Write set: the `#idr.con` verifier
   (`lib/IR/ConAttr.cpp`), `canon::eta`'s caller in `lib/IR/OpsCon.cpp`,
   and the rule of unit 3. Outcome: I1. Must not: read the promise
   (idr-demand's) to decide it. Acceptance: I1's two tests.

## 6. Owner questions

None. Each finding is settled by AGENTS.md, a ruling or the evidence:
I1 by "acceptance is a property of the program"; I2 by C3's own
principle; I3 to I7 by D10, D13, D20, D23 and the upstream-patch rule.
No op needs a resource beyond D27's tree (§2.1).
