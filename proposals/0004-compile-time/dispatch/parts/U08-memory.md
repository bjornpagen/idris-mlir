# U08 — Memory: counting the buffers bufferization leaves, the stack as a property, the in-place promise as a type fact

## Permitted outcome
1. **Mandatory.** idr-stack decides every `idr.con` of the module on each
   run and writes the decision into the con's inherent `stack` property
   (C14 §1) through the generated `setStack`. No file of U08 reads or
   writes a discardable attribute.
2. **Mandatory.** Every reader of the stack fact in U08's files reads
   `ConOp::getStack()`: Reuses (a stack box is not reusable, a stack con
   gets no taken cell), Exclusivity (a stack con's value is shared). The
   reuse rewrite copies no attribute dictionary from a con to its reuse.
3. **Mandatory.** idr-rc has no options and one behaviour: the reuse
   rewrite and the sinking of consumers always run. `createRcPlace()`
   takes no argument; Borrows always reads Reuses.
4. **Mandatory.** The exclusive copies: each round of idr-rc's step 4
   reads the solve, gathers the grade contexts its live calls present as
   a key set before anything changes, makes each new key's copy once,
   named from the key (C14 §4, C21), and redirects the calls. The rounds
   end when a round redirects no call. No round counter, no "did not
   settle" error, no name the symbol table renamed.
5. **Mandatory.** idr-demand always runs its one check: the in-place
   promise of every type whose body carries it (C14 §2). A failure is a
   refusal whose rule is `uniqueness`, given as data (C04), with today's
   text after the rule.
6. **Mandatory.** idr-rc counts the buffers bufferization leaves (C14
   §3): scf.for and linalg ops on buffers are loops; a linalg op whose
   payload reads or writes a counted element becomes its scf.for loops
   first; a counted element read from a buffer takes a reference of its
   own where it is read; an `idr.own.adopt` takes over each
   `memref.alloc`'s reference and an `idr.own.give` hands each counted
   `memref.store` its value (C14 §3); `memref.copy` borrows both
   operands.
7. **Mandatory.** U08's files read every data type through its
   identified type (C01): no `lookupData`, `lookupCtor`, `declarationOf`,
   `constructorOf`, symbol-table lookup of a data type, or `CtorOp` is left
   in them, and `Counted` holds no symbol table.
8. **Mandatory.** The `isExternal()` tests of U08's files are deleted (a
   function always has a body, C03), and so are their cases for
   `idr.closure`, `idr.suspend`, `idr.apply` and `#idr.closure`, which no
   module holds after idr-defunctionalize (C06).
9. **Mandatory.** U08 supplies contract C14.

Consumer adaptations U08 makes: none outside its writes. The lines other
lanes write for it are listed under Outputs.

## Owner / exclusive writes
Every path of ownership.json's U08 entry (roots: `IDR` is
`foreign/idr/lib`, `INC` is `foreign/idr/include/idr`):
- `IDR/Transforms/Ownership` (`foreign/idr/lib/Transforms/Ownership`):
  `Classes.cpp`, `Commit.cpp`, `Place.cpp`, `Placement.cpp`, `Rc.cpp`,
  `Reshape.cpp`, `Reuse.cpp`, `Share.cpp`, `Signatures.cpp`,
  `Specialize.cpp`, `Take.cpp`. No file is added or deleted.
- `INC/Transforms/Ownership.h` (`foreign/idr/include/idr/Transforms/Ownership.h`).
- `IDR/Transforms/Stack` (`foreign/idr/lib/Transforms/Stack`): `Stack.cpp`.
- `INC/Transforms/Stack.h` (`foreign/idr/include/idr/Transforms/Stack.h`).
- `IDR/Transforms/Demand` (`foreign/idr/lib/Transforms/Demand`): `Demand.cpp`.
- `INC/Transforms/Demand.h` (`foreign/idr/include/idr/Transforms/Demand.h`).
- `IDR/Analysis/Ownership` (`foreign/idr/lib/Analysis/Ownership`):
  `Borrows.cpp`, `Exclusivity.cpp`, `Reuses.cpp`, `Uses.cpp`, `Values.cpp`.
- `INC/Analysis/Ownership.h` (`foreign/idr/include/idr/Analysis/Ownership.h`).
- `IDR/Analysis/Escapes.cpp`, `IDR/Analysis/EscapesCycles.cpp`
  (`foreign/idr/lib/Analysis/Escapes.cpp`, `EscapesCycles.cpp`).
- `INC/Analysis/Escapes.h` (`foreign/idr/include/idr/Analysis/Escapes.h`).

**Excluded:**
- `include/idr/IR/IdrOps.td` (the `stack` property's ODS, the con's
  verifier), `IdrBase.td`, `include/idr/IR/Ownership.h` and
  `lib/IR/Verify/Uses.cpp` (`isIndexLoop`, `readFrom`, `useOf`,
  `reachesOnlyAtoms`), `lib/IR/Effects.cpp` (`consumes`),
  `lib/IR/Verify/` (the owned stage's verifier, `Attributes.cpp`),
  `lib/IR/OpsCon.cpp` (`ConOp::getEffects`), `include/idr/IR/Symbols.h`,
  `Grades.h`, `Layout.h` and the generated `compiler/src/IdrisMLIR/Dialect/`:
  U01.
- `include/idr/IR/IdrArrayOps.td`, `lib/IR/OpsArrays.cpp`: U11.
- `lib/Transforms/Bufferize/` (`allocationFn`, `memCpyFn`, the links'
  `mustBufferizeInPlace`): U12.
- `include/idr/Transforms/Passes.td`, `lib/Transforms/Pipeline.cpp`,
  `include/idr/Transforms/Pipeline.h`, the driver: U06.
- `lib/Conversion/` (`Cells.cpp`'s stack cell, the lowering of a counted
  `memref.load` and `memref.store`, of `idr.dup`/`idr.drop` on a buffer):
  U10.
- `include/idr/Analysis/Holds.h`, `include/idr/Support/Scc.h`: U03.
  `include/idr/Analysis/Tail.h`, `lib/Transforms/Tail/` (`.acc`, `.trmc`):
  U09.
- `compiler/src/IdrisMLIR/Registry/` and `Frontend/` (which types carry the
  promise): U14; `Emit/` (writing it into the body): U15.
- `tests/idr/` (the rc, stack, ownership fixtures): U17. `tests/reject/`,
  `tests/programs/`, `tests/lib/` (the promise's fixture files): U18.
- `runtime/`: U19. Every `CMakeLists.txt`: the coordinator.

## Read first
- `contracts.md` C01, C02, C03, C04, C06, C11, C12, C14, C15, C16, C21
  (C14 is this lane's own).
- 0004 (`proposals/0004-compile-time/README.md`): §4 stages 10 and 11
  (`:972-989`); §6's rows for `idr.stack` (`:1259`), `idr-rc{reuse,sink}`
  (`:1253`), the demand option (`:1256`), the exclusivity loop (`:1268`),
  names from counters (`:1265`), the `CloneAttr` (`:1247`); §6's "Kept"
  (`:1310-1328`: the stack thresholds 256/1024/64 stay); §9 (`:1432-1436`);
  D7, D18, D19, D28, D29, D42 (`:1546-1840`); §2.7 "Passes lose their
  closure cases" (`:385-389`); §2.9's row on the promise (`:467`).
- 0003 (`proposals/0003-typed-apl/README.md`): §7 (`:957-1040`), §8
  (`:1125-1259`, the in-place promise at `:1202-1226`), §4.5 (`:791-846`),
  §13 (`:1463-1483`), D17, D18, D33, D42, D43 (`:1787-1953`), §21 item 2.
- The lane's sources, whole: `lib/Transforms/Ownership/*.cpp`
  (`Rc.cpp:45-107` the five steps and the loop at `:75-99`;
  `Specialize.cpp:43-104` the copies; `Reshape.cpp:30-46` the region check,
  `:328-342` the order; `Placement.cpp:157-224` loops; `Place.cpp:23-66`;
  `Commit.cpp:51-125`; `Reuse.cpp:36-44`), `lib/Analysis/Ownership/*.cpp`
  (`Reuses.cpp:156-212`, `Exclusivity.cpp:103-170`, `Borrows.cpp:56-131,
  236-261`, `Uses.cpp:53-101`, `Values.cpp:18-32`), `lib/Analysis/Escapes.cpp`
  (`:1-43` the rules, `:159-176` loopsAround, `:322-347` calls),
  `EscapesCycles.cpp:21-71`, `lib/Transforms/Stack/Stack.cpp:44-102`,
  `lib/Transforms/Demand/Demand.cpp:28-133`, and the three headers.
- Their neighbours, read only: `include/idr/IR/Ownership.h:17-56`,
  `lib/IR/Verify/Uses.cpp:22-118`, `lib/IR/Effects.cpp:17-42`,
  `include/idr/IR/Symbols.h:18-81`, `include/idr/IR/Grades.h:95-101`
  (`sameElement`), `include/idr/IR/IdrOps.td:203-216` (`idr.con`),
  `IdrBase.td:49-58`, `lib/IR/Verify/Attributes.cpp:30-35`,
  `lib/IR/Verify/Owned.cpp:195-215`, `lib/Conversion/Cells.cpp:40-70`,
  `include/idr/IR/IdrArrayOps.td` (the world-ordered ops), `Passes.td:529-554,
  626-700`, `lib/Transforms/Pipeline.cpp:110-125`.
- Upstream: `.toolchain/build/llvm-project/mlir/include/mlir/Dialect/Linalg/Transforms/Transforms.h:1018-1020`
  (`linalgOpToLoops`, which leaves the op for the caller to erase:
  `lib/Dialect/Linalg/Transforms/Loops.cpp:191-238`),
  `include/mlir/Interfaces/DestinationStyleOpInterface.td:175`
  (`hasPureBufferSemantics`), `include/mlir/Dialect/MemRef/IR/MemRefOps.td`
  (`memref.load`'s and `memref.store`'s type rules: an element is the
  memref's element type, so no grade), and `AllocLikeOp`'s `AnyMemRef`
  result there.

## Fixed decisions
- **The stack fact is the con's own** (C14 §1). idr-stack sets
  `con.setStack(decision)` on every `idr.con` it walks, through
  `RewriterBase::modifyOpInPlace`, true or false, and changes nothing else.
  The thresholds stay: a cell of at most 256 bytes, 1024 bytes a frame, 64
  for a function on a cycle of calls (0004 §6 "Kept").
- **One idr-rc.** The pass has no option; `ownership::createRcPlace()` and
  `ownership::reshape(rewriter, fn, counted, classes)` take no flag; the
  reuse rewrite and `sinkConsumers` always run; `Borrows` reads
  `am.getAnalysis<Reuses>()`.
- **Grade contexts as keys** (C14 §4). The key of a copy is (the original
  function, its exclusive context): the ascending positions of the
  original's followed parameters. One function has at most one key, so
  one copy. A round: (1) solve; (2) for every private function that is
  no copy and whose callers the solve sees, gather the key when some live
  call `improves` and some other live call does not, into a `MapVector`
  in module order; (3) make the copy of each key not yet made, named by
  C21 from the key, inserted right after its original; (4) redirect every
  improving call. A call is redirected at most once and each key is made
  once, so a round that redirects nothing is the last.
- **The promise's check** (C14 §2): a parameter is promised when it is an
  entry argument at quantity one, its type's identified data type carries
  the in-place fact (C01's accessor), and an `idr.reuse` of the function
  takes its token from an `idr.take` of it, seen through `lin.enter`,
  `lin.use`, `idr.borrow` and a match's default region (`itself`, kept).
  Every `idr.call` of the function passes `!idr.excl<...>` there. The
  report rule is today's: the calls whose argument an `idr.dup` shared are
  the errors, and the others only when none is.
- **Buffers are cells, their elements are mutable** (C14 §3). `Classes`
  gives an element read from a buffer (the result of a counted
  `memref.load`, which `readFrom` reads from its memref) the class
  `Owned`, never `Borrowed`: a buffer's element may be written while a
  view of it would still be read, which a cell's field never is. So
  `Reshape::ownFields` gives every counted `memref.load` its `idr.dup`
  right after it. A view of a buffer (a subview, a cast, a reshape) is
  classed as any value read from another is.
- **The buffer forms come first.** idr-rc's step 1, right after it
  refuses a module in the owned stage and before Reuses and Borrows read
  the module, runs `ownership::bufferForms(fn)` on every function in
  parallel (`failableParallelForEach`): every linalg op with pure buffer
  semantics one of whose payload arguments holds references becomes its
  loops (`linalg::linalgOpToLoops`, then `rewriter.eraseOp`); then an
  `idr.own.adopt` goes right after every `memref.alloc`, every other use of
  the allocation reading the adopt, and an `idr.own.give` right before
  every `memref.store` whose value holds references, the store's operand 0
  becoming the give. So reset/reuse and borrow inference read the loads,
  stores and consuming uses placement counts. Reshape then runs `check`
  and today's selects, takes, sinking and fields, in today's order.
  `memref.alloc`, `memref.store` and `memref.copy` keep their ops.
- **Boundary values are untracked.** `Classes::classOf` gives the result
  of a `memref.alloc` and of an `idr.own.give` the class `Untracked`: their
  one use, the adopt or the store, moves their reference. The adopt's
  result is placed as any owned value; the give's operand is a consuming
  use. The commit has no case for either.
- **The regions idr-rc counts:** `idr.match`, `idr.match_lit`, and
  `ownership::isIndexLoop` (C14 §3: `scf.for`, a linalg op with pure
  buffer semantics). Any other op with a region, or a region of more than
  one block, is idr-rc's internal error, text: "idr-rc: internal error:
  counts matches, scf.for and linalg ops on buffers, each of one block".
- **No closure case and no external function** in U08's files (C03,
  C06). `Escapes::findCycles` keeps only calls; `Borrows` keeps the public
  root's parameters owned and no others for being named.
- **A refusal is data** (C04): idr-demand emits rule `uniqueness` through
  C04's one function, with the message `@<caller> passes a shared <name>
  to @<callee>, which rebuilds it in place` and the note `shared here`;
  `<name>` is the identified type's name as C01 prints it.

## Inputs
- **C01:** `idr::DataType` and `idr::Ctor` (a constructor is its data
  type and its tag: `getCtor(tag)`, `getTag(name)`, `Ctor::fields`),
  `dataTypeOf(Type)`, `isBoxed(Type)`, `holdsReferences(Type)` with no
  callback, `SumKind::InPlace`, `DataType::getName()`, and
  `Layouts::box(DataType, unsigned tag)`; `reachesOnlyAtoms(Value)` with no
  declaration callback (U01's `include/idr/IR/Ownership.h`).
- **C02:** `idr.con`'s `UnitAttr:$stack` (C02 §2), with
  `getStack`/`setStack`, and the con's verifier holding C14 §1's
  invariant; `getDataType()` and `getTag()` on `idr.con`, `idr.field`,
  `idr.reuse`, `idr.take`, and `MatchOp::getCaseTag(unsigned)`; constructor
  references as `FlatSymbolRefAttr` names within the type (C02 §1).
- **C03:** every `idr.func` has a body; the root is the one public one.
- **C04:** `idr::refuse(mlir::Operation *, Rule)` and `Rule::Uniqueness`.
- **C06:** after idr-defunctionalize no closure, suspension, apply,
  lambda, delay or `#idr.closure` exists, and no value has a closure or
  lazy type.
- **C11:** the world-ordered array ops, counted as today; no buffer op of
  ours.
- **C02:** also `idr::OwnAdoptOp` and `idr::OwnGiveOp` exactly as C14 §3
  gives their ODS (U01 declares them).
- **C12:** `IdrRc` and `IdrDemand` without options, `idr::createIdrRc()`,
  `idr::createIdrDemand()`, `idr::createIdrStack()` at rows 11 to 14.
- **C15:** §7: no tensor and no `bufferization` op at stage 11, every
  allocation a `memref.alloc` without `alignment`, every copy a
  `memref.copy`, views upstream's.
- **C16:** the lowering C14 §3 states for buffers.
- **C21:** the C++ names-from-content helper.

## Outputs
- **C14** (`contracts/C14-memory-facts.md`): the `stack` property, the
  in-place promise and its check, counting over buffers, the exclusive
  copies' keys and names.
- The declarations U08's headers keep for other lanes:
  `idr::Escapes` (`mayEscape(ConOp)`, `recursive(FuncOp)`, `solved()`),
  `idr::Borrows`, `idr::Reuses`, `idr::Exclusivity` and
  `idr::ownership::Counted` in `include/idr/Analysis/Ownership.h` and
  `Escapes.h`, with `CtorOp` replaced by the identified type's
  constructor handle and no `SymbolTable` in `Counted`.
- Lines for U06 (its registry already holds the first two): `Passes.td`'s `IdrRc` without
  `reuse` and `sink`, `IdrDemand` without `in-place`, and these
  descriptions: `IdrStack` "Sets the `stack` property of an `idr.con` of
  a box ..."; `IdrDemand` "Refuses a program that breaks the in-place
  promise of a type that carries it: ... every call passes it exclusive
  ... `unsupported (uniqueness)` ..."; `IdrRc` naming scf.for and linalg
  ops on buffers and the copies "named from their key" instead of
  "`<f>.excl`".
- Lines for U01, U10, U11, U12 are C14's, listed there by lane.

## Implement
- `Stack.cpp`: drop `StackAttrHelper`; the walk computes `marked` as
  today, reading the box's size through C01's constructor of `con`; a
  change is `con.getStack() != marked`; the rewrite is
  `modifyOpInPlace(con, [&]{ con.setStack(marked); })`. Header comment:
  "the con's `stack` property", "every con is decided again".
- `Reuses.cpp`: `reusable` and `fits` read `con.getStack()`; the `Decider`
  loses its `StackAttrHelper` and `SymbolTable`; `Site::ctor` is C01's
  handle; constructors come from the scrutinee's or the read's type
  (C01), sizes from `Layouts::box`. `Reuses::Reuses` walks every function
  (no external test). `isArrayLoop` becomes `isIndexLoop`.
- `Exclusivity.cpp`: the con and reuse rule reads `con && con.getStack()`;
  `reachesOnlyAtoms(dup.getValue())` with no callback; the analysis holds
  no symbol table.
- `Reuse.cpp`: delete the line that copies the con's discardable
  attributes to the reuse.
- `Rc.cpp`: no options; Layouts checked and Reuses computed always; the
  `removeCloneAttr` loop goes (C09 makes no self-referencing clone fact);
  step 4 is `specializeOnGrade`'s rounds as Fixed decisions says, ending
  when it reports no redirect; `runNested(createRcPlace())`.
- `Specialize.cpp`: `Copies` keeps `of` (original to copy, a `MapVector`)
  and `copies`; `gather` builds the round's keys first, then `copyOf`
  makes each new one: `fn.clone()`, `setSymName(<C21 name>)`,
  `setPrivate()`, inserted after the original through the table, which
  must not rename it (a renamed insert is C21's collision, an internal
  error); then the redirects. No `isExternal`, no `removeCloneAttr`.
- `Signatures.cpp`, `Commit.cpp`, `Place.cpp`: delete the external
  tests; `Commit.cpp` loses the `SuspendOp` case; `Place.cpp` runs the
  reuse rewrite always and calls `reshape` without `sink`.
- `Reshape.cpp`: the order and region rule of Fixed decisions; the
  `lookupData`/`lookupCtor` reads in `takeApart`, `takeReadSums` and
  `takeReadBoxes` become C01's constructor of the value's type by name;
  `sinkConsumers` always runs. New: `bufferForms(FuncOp)`, declared in
  `include/idr/Transforms/Ownership.h`, over the file-local
  `loopCountedElements` and `boundaries`.
- `Classes.cpp`: in `classOf`, the result of a `memref.alloc` or an
  `idr.own.give` is `Untracked`, the result of a `memref.load` is `Owned`;
  the rest as today.
- `Take.cpp`, `include/idr/Transforms/Ownership.h`,
  `include/idr/Analysis/Ownership.h`, `Uses.cpp`: `CtorOp` parameters
  become C01's handle; `eachField` compares the read's constructor name
  with the handle's; `isArrayLoop` becomes `isIndexLoop`; `createRcPlace()`
  and `reshape(...)` lose their flags.
- `Values.cpp`: `Counted()` with no table; `operator()` memoizes
  `holdsReferences(type)` (C01).
- `Borrows.cpp`: Reuses read always; the `ClosureOp`, `SuspendOp`,
  `ApplyOp` and `ClosureAttr` cases and the `named` set go (only the
  public root is fixed); no external test.
- `Escapes.cpp`, `EscapesCycles.cpp`, `Escapes.h`: no external test, no
  `labels`, no `applies`; the header's and the file's comments lose
  "captured by a closure, applied (idr.apply)" and "an idr.apply may call
  any function whose address is taken".
- `Demand.cpp`, `Demand.h`: no option; `checkInPlace` always; `rebuilt`
  keeps a parameter only when its type carries the promise (C01); the
  report through C04. Comments: "the promise a type makes", never "when
  it is asked to".
- Failure paths: an exclusivity solve that fails stays idr-rc's internal
  error; a meeting of the solver and the commit that disagree stays
  `Commit.cpp`'s internal error; the escape solve's failure stays
  idr-stack's internal error. None of them is a refusal.

## Delete
- The discardable `idr.stack`: every `IdrDialect::StackAttrHelper` in U08's
  files (`Stack.cpp:62`, `Reuses.cpp:67, 253, 275`, `Exclusivity.cpp:169`),
  `isAttrPresent`/`setAttr`/`removeAttr` on it, and
  `reuse->setDiscardableAttrs(...)` (`Reuse.cpp:40`).
- `idr-rc{reuse,sink}`: `IdrRc`'s `reuse` and `sink` reads (`Rc.cpp:55-59, 66`),
  `RcPlace`'s two members and constructor arguments (`Place.cpp:26, 44,
  53, 58-59`), `reshape`'s `sink` parameter (`Reshape.cpp:329, 338`),
  `createRcPlace(bool, bool)`, and Borrows' "without reuse" path
  (`Borrows.cpp:281-283`).
- `idr-demand{in-place}`, the option `--demand-in-place` reaches: the
  `inPlace` read (`Demand.cpp:129`) and every comment that says the check
  runs when asked.
- `idr-rc`'s exclusivity loop's counter and its error: `calls`,
  `round == calls`, "specializing on exclusivity did not settle"
  (`Rc.cpp:75-99`), and the `.excl` suffix named by insertion order
  (`Specialize.cpp:51`).
- The self-referencing `CloneAttr`'s special cases in U08: `fn.removeCloneAttr()`
  (`Rc.cpp:70-73`, `Specialize.cpp:53`).
- `fn.isExternal()` and `callee.isExternal()` in `Commit.cpp:113`,
  `Place.cpp:35`, `Signatures.cpp:24, 46`, `Demand.cpp:93`,
  `Specialize.cpp:67`, `Reuses.cpp:278`, `Borrows.cpp:75`,
  `EscapesCycles.cpp:24, 34, 48`, `Escapes.cpp:324`.
- The closure cases: `Borrows.cpp:122-131, 248-253` (`ClosureOp`,
  `SuspendOp`, `ApplyOp`, `ClosureAttr`, `named`), `Commit.cpp:80-85`
  (`SuspendOp`), `EscapesCycles.cpp:27-35, 44, 52-55` (`labels`,
  `applies`).
- Every `lookupData`, `lookupCtor` and `SymbolTable` read of a data type
  in U08's files (`Reshape.cpp:92, 102, 240, 272`, `Reuses.cpp:78, 80, 105,
  195`, `Stack.cpp:74`, `Exclusivity.cpp:126`, `Values.cpp:28`), and every
  `CtorOp` in U08's headers and files.
- `ownership::isArrayLoop` calls (`Reshape.cpp:39`, `Placement.cpp:166,
  186, 221`, `Uses.cpp:66, 94`, `Reuses.cpp:202`).

## NOT TO DO
- Do not declare the `stack` property, `isIndexLoop`, `readFrom`'s new
  cases, `consumes`, the owned-stage verifier's rules, or
  `holdsReferences`: U01 writes them from C14. Do not declare
  any array or buffer op (U11; the ruling is that none exists), nor
  `idr.own.adopt` or `idr.own.give` (U01). Do not touch `Passes.td` or
  `Pipeline.cpp` (U06), `Conversion/` (U10), `Bufferize/` (U12).
- Do not add a pass option, a mode, a flag on `createRcPlace`, or a
  second check path in idr-demand; no `--demand-in-place` in any form, no
  `idr.demand_in_place` attribute, no attribute of any kind.
- Do not make the in-place check read `LArray` or a tensor: that promise
  is U12's `mustBufferizeInPlace` on the links (0003 D33).
- Do not write move-out for buffers, and do not rewrite `memref.alloc`,
  `memref.store` or `memref.copy` into another op.
- Do not change the stack's thresholds, the escape rules, `loopsAround`
  or the frame budget order; do not add scf.for to `loopsAround`.
- Do not share Escapes' or Borrows' cycle computation with another lane's
  graph, and do not touch `Support/Scc.h` (U03) or `Analysis/Tail` (U09).
- Do not edit a test (U17, U18), even the ones whose expected `.excl`
  name changes.
- Do not let a counter, a symbol-table rename or module order decide a
  copy's name.

## Tempting partial solutions
- **Keep the round loop and only drop the counter.** Rejected by C14 §4's
  acceptance: the keys of a round are gathered before any copy is made,
  and a copy's name is its key's (the edit fixture: renaming one function
  leaves every other copy's name unchanged).
- **Rename the `.excl` copy with a hash of the body.** A body changes
  with every unrelated rewrite; the key is (original, context), and the
  original's name already names the body.
- **Treat a counted `memref.load`'s result as `Borrowed` when the buffer is
  alive.** Rejected by a fixture that reads an element, writes the same
  element, then uses what it read: the view would read a released cell.
- **Rewrite `memref.alloc` or a counted `memref.store` into an op of
  ours so that its value can be graded.** The ruling keeps upstream's
  ops and puts the grade's boundary beside them (C14 §3); a second
  allocation or store op is a second representation.
- **Retype `memref.alloc`'s result, or give `memref.store` an owned
  value.** Their own verifiers refuse `!idr.own<T>` there; the adopt and
  the give exist for exactly that.
- **Count inside a linalg payload whose arguments hold references.** Its
  block arguments must have the element type, which an owned grade breaks,
  and a named op's region is rebuilt on parse; hence the loops first.
- **Keep `idr-demand{in-place}` with a default of true.** Still an option
  that selects behaviour (0004 D2); C12 forbids every option but
  idr-expect's.
- **Check the promise on every linear parameter rebuilt in place,
  whatever its type.** That is the old command-line language; the promise
  is the type's, so a user type that does not carry it is not refused.
- **Guard `isExternal()` "just in case".** The verifier refuses a
  bodiless function (C03); a guard for an unrepresentable state is the
  casework this cutover deletes.

## Acceptance
- **Stack.** `idris-mlir-opt --idr-stack` on a module whose box never
  leaves its frame prints the con with the `stack` keyword (C14 §1), and
  on a second run prints the same; a module where it is returned prints
  none; `tests/idr/stack/*.mlir` restated by U17 hold. No `idr.stack`
  attribute appears in any output.
- **Exclusivity copies.** `tests/idr/rc/exclusive.mlir`'s module, run
  with `--idr-rc`: the calls with fresh lists go to one private copy of
  `@bump2`, whose name is C21's name for (`bump2`, its context), and the
  same input gives the same name at 1, 2 and 8 threads; `idr-expect`
  `holds=tests-nothing` holds on that copy, found by structure (C24).
- **Promise.** `tests/reject/uniqueness-shared-rebuild` with no
  `demand-in-place` file and no option is refused with rule `uniqueness`
  and text "which rebuilds it in place", exit 3; the ten
  `tests/programs/linear/leet-*` programs compile with no option and keep
  their outputs; a program whose own linear list type does not carry the
  promise is accepted when it shares one (U17/U18 own these fixtures).
- **Buffers.** A dialect fixture after bufferization with a `scf.for`
  that reads a box element of a buffer, writes it back rebuilt, and folds
  a counted accumulator: after `--idr-rc` the module verifies in the
  owned stage, every counted `memref.load` is followed by its `idr.dup`,
  every `memref.alloc` by its `idr.own.adopt`, every counted
  `memref.store` takes an `idr.own.give`'s result, a linalg op over box
  elements is gone into `scf.for` loops, and one over words is kept.
- **Source review.** `grep -rn 'StackAttrHelper\|isExternal\|lookupData\|lookupCtor\|CtorOp\|isArrayLoop\|removeCloneAttr\|ClosureOp\|ApplyOp\|SuspendOp\|ClosureAttr\|inPlace\|reuse,\|bool sink\|\.excl"' `
  over U08's files prints nothing. `Rc.cpp` has no `round` counter.
- **Checks.** `python3 proposals/0004-compile-time/check-units.py` over
  every `.cpp` of U08's writes reports 0 failing, or fails only on a
  declaration C01, C02, C04, C21 or C14 §3's vocabulary (U01) that is not
  in the tree yet, each listed in the handoff with its contract.

## Stop and return
Stop when every Mandatory outcome is in U08's files and C14 is written,
and return the handoff the common obligations define. Report without
stopping: a C01 accessor, the `stack` property (C02), `isIndexLoop` or
`readFrom` (C14 §3, U01), C04's refusal function or C21's
helper that the tree does not have, each with the file and line of U08
that calls it; any live caller outside U08 of a declaration U08 changes
(`createRcPlace`, `reshape`, `Counted`, `Reuses::Site::ctor`,
`eachField`, `takeAt`), with its path and owner.
