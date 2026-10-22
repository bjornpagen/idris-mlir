<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: where a lifetime's lowering is decided, and who reads it

**Status (2026-10-21):** research and design for the owner's open
question 31, with 32, 33 and 35 folded in (`audits/p0/verify/status.md`,
the owner's queue). Nothing here is built, run or settled. Which op or
type holds a fact is the owner's (AGENTS.md); where this file names one,
it is a recommendation, and §10 lists the decisions it needs, one at a
time.

**Grounds** (proposals/README.md): *read* (path:line; HEAD `e96bb991`
with the working tree's P0 through D90; the toolchain pin `7208ba24c`,
paths under `mlir/` are `.toolchain/llvm-project/mlir/`), *measured* (the
command and its output), *recalled*, *conjecture*, *decision* (a ruling
Dn or a coordinator decision Cn). What this file proposes is marked
*proposed*. Names follow D90 (`!idr.lifetime`, `idr.lifetime`,
`idr.activation`, `idr.lend`, `scoped`); a name this file adds is a
placeholder for the naming scheme.

**Read for it**: the representation-first skill and AGENTS.md whole; P0's
D10, D26, D30 to D32, D39, D40, D48, D56 to D58, D61, D63, D78, D88 to
D90, C2, C28, C45, C64, C79, C83, C84, C96, C97, C140, C141;
`design/lifetimes/static-handles.md`, `constraints.md`, `prior-art.md`;
`verify/L05`, `L10`, `L14`, `L02` (Q2), `review.md` §3. Upstream at the
pin: `BuiltinTypes.td` (`MemRefType`), `MemRefOps.td`, `OpDefinition.h`
(`AutomaticAllocationScope`), `BufferizableOpInterface.h`, the GPU
dialect and its lowering, the LLVM and `ptr` dialects' pointer types, the
async dialect and its lowering, `DialectConversion.h`,
`AttrTypeSubElements.h`, `InliningUtils.cpp`, `SymbolTable.cpp`.

**Measured**: no `mlir-opt` is built under `.toolchain/` (`find .toolchain
-type f -perm -u+x -name '*-opt'` finds none); the pinned `mlir-tblgen`
is (`.toolchain/build/tblgen/bin/mlir-tblgen`). One run, in
`/tmp/lt-lowering`, is cited in §4.1.

## 0. The answer in one page

The question holds two facts, and upstream keeps them apart:

- **Where a lifetime's memory comes from** (nothing; a thread-local home;
  a block in the opener's frame; the computation's lifetime stack; its own
  chunk chain) is what opening and closing it do. That is the **opener
  op**, one op per memory source, as `memref.alloc` and `memref.alloca`
  are two ops (read, `mlir/include/mlir/Dialect/MemRef/IR/MemRefOps.td:227,
  377`) and as `gpu.func`'s workgroup and private attributions lower to a
  global and an `llvm.alloca` (read,
  `mlir/lib/Conversion/GPUCommon/GPUOpsLowering.cpp:190-212, 306-324`).
- **What a lifetime value is at run time** (no value; a pointer to a
  block of static size; a cursor that goes in and comes back; a constant
  home) is what every allocation into it, every callee given it, every
  frame holding it and the lowering must read. That is a **parameter of
  the value's type**, `!idr.lifetime<kind>`, as a memref's memory space
  is a parameter of `MemRefType` (read, `BuiltinTypes.td:963-968`) and a
  GPU attribution's address space is a parameter of its memref type
  (read, `GPUOps.td:360-420`'s example).

So, *proposed*:

| fact | home | read by | steps |
| --- | --- | --- | --- |
| the memory source (static-handles' five classes) | the opener op: `idr.lifetime` with no memory, `.home`, `.block`, `.stack`, `.chain` | the opener's own lowering (open, close) | 0: it is the op |
| the run-time convention (the mode) | the kind of `!idr.lifetime<kind>`: `view`, `home k`, `room`, `cursor`, fixed by the opener for its binder, written in signatures for parameters | `cell.arena`, callees, frames, the call verifier, the inliner, the lowering | 0: `value.getType()` |
| how much a function puts into each lifetime parameter | an inherent property of `idr.func`, per put parameter, beside D61's per-parameter part | the caller's layout of a `room` block, the decide step, D26's proof | 1: the callee, resolved once by the call's lowering |

A `view` parameter accepts a lifetime of any kind at a call, since
nothing happens at run time; every other kind is passed only to its own
kind. That makes the call verifier's type check the mode check, makes
callees specialized by mode alone (static-handles' at most 4^k), and
keeps one body for every view-only function. No lifetime variable and no
substitution exist (D63). The kind lowers by one context-free, cached
`TypeConverter` rule per kind; `view` and `home` convert to no value,
which drops them from every signature and call (C141's reason).

static-handles §4.8 recommended one op per class with each parameter's
mode a property of the function. This file keeps the first half and
moves the second into the type: the evidence is §3.

## 1. Who reads the decision

| reader | what it needs | today's design (static-handles §4.8, constraints §3.1) | this file |
| --- | --- | --- | --- |
| `cell.arena in %l` and its lowering | room offset, cursor bump or home slot | `%l`'s binder: an opener (its op) or a function (its property at the argument's position): two kinds of hop, a branch per binder kind | `%l`'s type |
| a callee | its parameters' modes | its property, positional | its signature |
| a caller | that it passes what the callee was compiled for | a rule of ours in `verifySymbolUses`, one hop per operand | the call's operand-type check, with `view` admitting any kind |
| the inliner | to map arguments | types all equal (parameterless) | equal for put parameters; `view` by one cast hook (§4.4) |
| specialization (C45, D58) | the key of a mode copy | a key structure beside the clone | the copy's `FunctionType` |
| frames (C96), TRMC, every clone | the mode of a lifetime held in a frame field or a copied parameter | a per-field annotation in the frame family, and every clone copying the positional property | field and parameter types, copied with them |
| a match case or frame pop binding a lifetime field | its mode | the family's field annotation | the field's type |
| the lowering of signatures and calls | which lifetime arguments exist at run time | a context-aware conversion, which upstream does not cache (read, `mlir/include/mlir/Transforms/DialectConversion.h:163-168, 584-592`) | a context-free conversion, cached |
| the caller's `room` layout | each put callee's byte total | the callee's property | the same (§4.5) |

## 2. Upstream precedents at the pin, for mechanism

- **`MemRefType`'s memory space.** A parameter of the type, any attribute,
  "target-specific" (read, `BuiltinTypes.td:896-899, 963-968`). Every op
  that produces or takes a memref sees it in the type; a function taking
  `memref<?xf32, 3>` takes nothing else. The LLVM lowering asks
  `getMemRefAddressSpace`, which converts the attribute through
  `addTypeAttributeConversion` and fails on an unknown one (read,
  `mlir/lib/Conversion/LLVMCommon/TypeConverter.cpp:269-271, 574-590`;
  `DialectConversion.h:225-256`; the patterns' failure at
  `mlir/lib/Conversion/MemRefToLLVM/MemRefToLLVM.cpp:604-611`). *Teaches*:
  the representation of a pointer is a type parameter, converted by a
  rule registered on the converter, with no context.
- **`memref.alloc` against `memref.alloca`.** One result type family, two
  ops, two resources (`DefaultResource` and
  `AutomaticAllocationScopeResource`), two lowerings (read,
  `MemRefOps.td:65-80, 227, 377`). The memory space is orthogonal: an
  `alloca` may be in any space. *Teaches*: the source of memory is the
  op; the kind of pointer is the type.
- **`AutomaticAllocationScope`.** A trait whose only check is that the
  op has a region (read, `mlir/include/mlir/IR/OpDefinition.h:1296-1310`);
  `memref.alloca_scope` has no verifier and memrefs carry no scope
  (prior-art §2.4). Not a model: C140 already keeps `idr.lifetime` off it
  (a slot inside would be a dynamic `alloca`, D32).
- **Bufferization's memory spaces.** The memory space is decided once,
  when tensors become memrefs, by `defaultMemorySpaceFn` or an
  `alloc_tensor`'s `memory_space` (read,
  `mlir/include/mlir/Dialect/Bufferization/IR/BufferizableOpInterface.h:278-280,
  375-376`; `BufferizationOps.td:52-54, 90`), and a mismatch at a merge
  fails bufferization (`:384-385`). *Teaches*: the kind is written into
  types by the step that decides it, and is never undecided after it.
- **The GPU dialect's address spaces.** `#gpu.address_space<workgroup |
  private | ...>`, a closed enum, as the memref memory space (read,
  `mlir/include/mlir/Dialect/GPU/IR/GPUBase.td:99-112`); `gpu.func` binds
  its workgroup and private buffers as entry arguments the op provides,
  typed with their space (read, `GPUOps.td:360-420`); the lowering turns a
  workgroup attribution into a global or an argument and a private one
  into an `llvm.alloca` (read, `GPUOpsLowering.cpp:135-212, 306-324`), and
  maps each enum case to a target's number by one registered conversion
  (read, `:834-843`). A callee that does not care about the space takes
  the generic one, reached by `memref.memory_space_cast`, whose own
  example is "Cast a GPU private memory attribution into a generic
  pointer" (read, `MemRefOps.td:1377-1410`); a pass moves such casts
  toward their users through interfaces (read,
  `mlir/include/mlir/Transforms/Passes.td:630-660`). **The closest
  model**: a binder op that provides a typed value (our opener's entry
  argument), the kind a closed enum in that type, the storage decided by
  the binder, a generic kind for code that does not care, and one
  conversion per kind.
- **LLVM's address spaces.** `!llvm.ptr<N>`, an integer parameter (read,
  `mlir/include/mlir/Dialect/LLVMIR/LLVMTypes.td:305`): the end of the
  memref chain. Ours ends earlier: every kind becomes `!llvm.ptr` or
  nothing.
- **The `ptr` dialect's memory space.** `!ptr.ptr<#space>` where the
  space implements `MemorySpaceAttrInterface`, whose methods each op asks
  (`isValidLoad`, `isValidStore`, ...) (read,
  `mlir/include/mlir/Dialect/Ptr/IR/PtrDialect.td:50-72`;
  `MemorySpaceInterfaces.td:23-125`). *Teaches*: the kind in the type
  answers an op's legality locally. Our kind set is closed, so a generated
  enum and one fold over it serve where an interface serves an open set
  (AGENTS.md's C++ rules).
- **The async dialect's tokens.** One `!async.token` type, every value a
  run-time object (read, `mlir/include/mlir/Dialect/Async/IR/AsyncTypes.td:28-34`;
  lowered to an opaque pointer, `mlir/lib/Conversion/AsyncToLLVM/AsyncToLLVM.cpp:294-296`),
  counted at run time by a pass (`AsyncRuntimeRefCounting.cpp`, prior-art
  §2.4). *The anti-model*: a uniform token needs no specialization because
  it pays at run time for what is static (D10). Its staged lowering
  (`async.execute` to `async.runtime.*` ops) is the one part that fits:
  a decision by stage is a change of op, as C28 holds stages.
- **`TypeConverter` with context.** A conversion taking a `Value` "can
  take into account IR when converting the type", is not cached, and
  makes every later conversion uncacheable (read,
  `DialectConversion.h:163-168, 584-592`). A 1-N conversion to no types
  removes the value from signatures and calls (read, `:157, 258-262`).
  *Teaches*: a convention read from IR around the value is a per-value
  question at the lowering; one read from the type is answered once per
  type.
- **`AttrTypeReplacer`.** Rewrites attributes and types recursively in an
  op (read, `mlir/include/mlir/IR/AttrTypeSubElements.h:146-151, 235-247`):
  the tool for substituting a type-level variable. This design has no
  kind variable, so it needs none (§3, candidate a').
- **Symbols in types.** Symbol uses are found in an op's attributes only,
  never in operand or block-argument types (read,
  `mlir/lib/IR/SymbolTable.cpp:536-555`). So a kind may not name a symbol:
  `symbol-dce` would not see it (§4.1, `home`).

## 3. The candidates

| | (a) kind in the type | (b) one op per kind | (c) a function property per lifetime parameter | (d) derived on demand |
| --- | --- | --- | --- | --- |
| constructs | the decide step: opener binders and signatures | the decide step: openers | the decide step: openers and the property | nobody |
| an allocation reads | its operand's type | its operand's binder op, if an opener; nothing for a parameter | binder op or the function's property, by binder kind | the program graph, per query |
| a callee reads | its signature | nothing | its property | the graph |
| crosses calls | the call's type check; `view` admits any kind | not at all | a rule of ours, one hop per operand | recomputed |
| specialization (4^k) | the copy's `FunctionType` is the key | n/a | a key beside the clone; the property copied | n/a |
| frames, case binders, clones | types carry it | lost | a per-field annotation; positional copies | recomputed |
| undecided form | a `undecided` kind with stages, or none (§4.8) | the undecided opener | an `Undecided` case per parameter | n/a |
| the lowering | context-free, cached conversion | per opener only | context-aware, uncached, or our own signature pattern | n/a |
| for free | uniquing, the call check, the inliner, clones, `TypeConverter` caching | the opener's patterns | the inliner (types equal) | — |

- **(a)**, taken naively, fails on one case: a function that does not
  allocate into a lifetime parameter is called with lifetimes of every
  kind (`eval` given a `cursor` lifetime by one caller and a `room` one by
  another), and with exact equality at calls each kind would need its own
  identical copy, which costs code for nothing. The fix is upstream's own:
  a generic kind, here `view`, which any kind may be passed as (§4.4). With
  it, (a) is the memref and GPU design exactly.
- **(a')**, the kind as an erased index variable of D48's binder
  (`idr.func @eval<k : kind>(%r : !idr.lifetime<k>)`), would also serve
  `eval` with one body, but brings C79's substitution, explicit erased
  arguments at every call that restate the operand's type, and
  `AttrTypeReplacer` for copies. D63 removed variables from lifetimes for
  their identity, not their kind, but the machinery is the same weight
  for a case a generic kind settles. Rejected (*proposed*).
- **(b)** is right for the memory source, and it is what static-handles
  recommends, but it reaches no callee: a parameter has no opener, and
  the source of an argument varies by caller.
- **(c)** reaches callees, and keeps the inliner trivial, but every
  reader then branches on what bound the value (an opener's op, a
  function's property at a position, a frame family's field annotation,
  a case binder's), every clone must carry a positional list in step, the
  lowering needs a context-aware conversion (uncached by design), and the
  call check is ours. That is a fact in an attribute beside the type it
  describes, which AGENTS.md's "one fact, one place" reads as a second
  copy wherever the type also travels (frames, copies).
- **(d)** is the per-query re-derivation D10 and L14 §2.4 forbid ("a fact
  is computed once and kept").

**Verdict** (*proposed*): (a) with a generic `view` kind for the
convention, (b) for the memory source, and (c) only for what is a fact
of the callee's body, the amount it puts (§4.5).

## 4. The design

### 4.1 The type

- `!idr.lifetime<kind>`, *proposed*, amending C140's "parameterless".
  The kind is a closed sum generated from the dialect's Idris
  specification (D16):

  | kind | meaning | bound by | lowers to |
  | --- | --- | --- | --- |
  | `view` | nothing allocates into it | `idr.lifetime` (no memory), `idr.lend`, `idr.activation`, any parameter the function does not put into | no value |
  | `room` | a block of static size; each cell at a constant offset; no check | `.block`, a parameter of a room copy | `!llvm.ptr`, in only |
  | `cursor` | an unbounded bump; the cursor goes in and comes back | `.stack`, `.chain`, a parameter of a cursor copy | `!llvm.ptr`, in and out (static-handles §3.6) |
  | `home k` | one instance per shard; k is the site's dense number | `.home`, a parameter of that site's copy | no value; allocations address slot k of one thread-local array |

- The kind is not an identity: two different lifetimes of one kind have
  one type, as D63 requires (identity is the SSA value). Printed
  `!idr.lifetime<cursor>`; `view` may print bare.
- `home k`'s payload is a number the decide step mints per class-2 site,
  never a symbol, since symbol walks do not see types (§2). The lowering
  sizes the thread-local array by one walk of the `.home` openers
  (*proposed*; a `DistinctAttr` would be the alternative identity, at the
  cost of a lookup per allocation). Class 2 stays the cost model's choice
  against class 4 (static-handles M4).
- `stack` and `chain` are not kinds: a callee bumps what it is given
  either way (static-handles §4.7), so the difference stays in the
  opener. §4.6 states what that costs the discipline check.
- **Generated, not written** (*measured*): with the pinned `mlir-tblgen`,
  a type with an enum parameter, an operand constraint "a lifetime that
  may be allocated into" (the kind is not `view`) and a region constraint
  "one block binding a cursor lifetime" generate both checks into the
  ops' generated verifiers (`mlir-tblgen -gen-op-defs` on
  `/tmp/lt-lowering/Lt.td`: exit 0; lines 29-31 and 49-52 of the output
  are the two checks). So every kind rule below is an ODS constraint the
  specification prints, never a hand `verify`.

### 4.2 The openers (the memory source)

One family generated from a list (C113), each its own op because opening
and closing differ (the skill's "each source is its own op"):

| op | binder kind | open | close | stages (C28) |
| --- | --- | --- | --- | --- |
| `idr.lifetime` | `view` | nothing | drops of owned fields only | any |
| `idr.lifetime.home` | `home k` | nothing (first chunk on first put) | chunks back, home reset | from the decide step |
| `idr.lifetime.block` | `room` | nothing (an entry-block `alloca` sized by its extent) | drops only | from the decide step |
| `idr.lifetime.stack` | `cursor` | keeps the stack top as its mark | drops, top back to the mark | from the decide step |
| `idr.lifetime.chain` | `cursor` | nothing (first chunk on first put) | drop list, chain to the pool | from the decide step |

- Each op fixes its binder's kind by a generated region constraint
  (§4.1); a binder of the wrong kind cannot be built.
- `idr.lend`'s and `idr.activation`'s lifetimes are `view`
  (*proposed*): a temporary that dies with a loan goes into an
  `idr.lifetime` nested in the lend's region, so the lend has one meaning
  and no family of its own (constraints §3.2 allowed allocation into a
  loan, which would have crossed the lend with five memory sources).
  `idr.activation` already takes slots only (`cell.stack`), never an arena
  (constraints V9).
- `.stack` takes the computation's lifetime-stack top and gives it back,
  a linear value threaded through the functions that use the stack as
  C96 threads the frame top (static-handles §3.4, §4.8).
- The block's byte size is not held on `.block`: it is a function of its
  extent, computed by the lowering's layout walk that also assigns every
  offset (§4.9), so no stored number can disagree with it.

### 4.3 Allocations

- `cell.arena in %l`: `%l` has kind `room`, `cursor` or `home k`
  (generated operand constraint). An allocation into a `view` lifetime
  cannot be written. Its lowering is one fold over the operand's kind.
- `cell.stack in %l`: `%l` of any kind, bound in this function
  (constraints V9 unchanged): the slot is this frame's, and `%l` is only
  its stated lifetime.

### 4.4 Calls and the inliner

- **The call rule** (`verifySymbolUses`, O(operands), *proposed*): each
  lifetime operand's kind equals the callee parameter's kind, or the
  parameter is `view`. That is the subsumption constraints §8 and §13
  already propose for grades at calls, applied to the one place where
  nothing happens at run time.
- **The inliner.** For a put parameter the types are equal, so upstream's
  `inlineCall` maps the argument directly. For a `view` parameter given a
  `cursor` value, `inlineCall` asks `materializeCallConversion` for a cast
  whose one result has the parameter's type (read,
  `mlir/lib/Transforms/Utils/InliningUtils.cpp:453-470, 527-536`); ours
  is `idr.lifetime.forget`, pure, its result a `view` of its operand's
  lifetime. The verifier's walk (constraints §4.4) gives the result its
  operand's depth and root when it meets the cast, so outlives stays one
  comparison. Since every user of a `view` value accepts any kind, a
  canonicalization replaces its uses by its operand and erases it
  (*conjecture* that no use is left between the inliner and the next
  canonicalize that the verifier cannot read; it can, by the walk).
  This amends C140's "never a result" by this one op, whose result
  cannot leave its operand's region (it is defined inside it, and no
  terminator takes a lifetime, constraints V1).
- **Room from a cursor** (optional, static-handles §3.6's room mode): a
  caller with a cursor calling a room copy writes
  `idr.lifetime.reserve %l, n` (one check of n bytes and a bump, `Allocate`
  on `heap` when a chunk is taken), an op of its own because it does
  something at run time; an implicit conversion at the call would hide an
  effect.

### 4.5 Functions: kinds in the signature, the amount beside D61 (Q32)

- A lifetime parameter's kind is in the function type: `view` when the
  function and its callees never allocate into it, a put kind otherwise.
  So static-handles' put set (§4.1 there) is the type, and "allocates
  into" cannot disagree with the body: an allocation or a put call takes
  no `view` value (§4.3, §4.4).
- **The amount** (*proposed*): per put parameter, `Finite n | Unbounded`
  (static-handles §4.2's multiplicity and size), an inherent property of
  `idr.func` in the same per-parameter record as D61's write part. Each
  part exists only for the parameters its type admits (D61's for an
  exclusive owned parameter, L02 Q2's "indexed by the parameter's grade";
  this one for a put-kind lifetime), so no part can sit on a parameter it
  does not describe; `room` requires `Finite`.
- It is a summary of the body, derived callees first, held on the
  function, checked per function as covering its body (the sizes of the
  parameter's direct allocating users, plus each call's callee amount),
  equal right after each re-derivation, as C64 holds rows. It is no
  effect (C2 R3 amended calls a put an operand) and no op-local interface
  needs it, so it is not copied onto calls (L14 I12); the caller's
  lowering resolves the callee once, as the call's own lowering does.

### 4.6 Specialization by mode

- A put callee's copy per mode tuple is the clone with its put
  parameters' kinds set, through the one clone-and-key template (L18,
  C45). The key is the copy's `FunctionType`: uniqued, compared by
  pointer, with no key structure of its own. Plus the counted copy, which
  has no such parameter (C45). At most 4^k copies for k put parameters
  (static-handles §4.7); recursion passes a parameter through (same type)
  or one of its own openers (a fixed kind), so the copies do not climb.
- View-only functions are never copied for a lifetime.
- **Discipline** (static-handles §4.4): the callee sees `cursor`, not
  stack or chain, so its own check treats every cursor parameter as
  possibly on the stack: inside a `.stack` region, a put targets only that
  region's lifetime or one opened inside it, else the region is `.chain`.
  Local and sound; conservative where a parameter is always
  chain-sourced (count the demoted regions, M3). Splitting the kind would
  restore that precision at the price of identical copies per source.

### 4.7 Frames, joins, tail groups

- A frame kind's lifetime field has a lifetime type; the push holds the
  value and the pop binds it with its kind (constraints §3.5, C96). No
  annotation beside the family.
- Join regions take no lifetime parameter (constraints §3.6).
- Tail groups (static-handles §4.6): a `tail` call's caller and callee
  must lower to equal return types (L10 §1 D30 item 8), and each `cursor`
  parameter returns its cursor, so tail-joined functions take the same
  cursor parameters, a function that does not put passing its own through.
  A local check on the `tail` call reads both signatures' kinds. M3 of
  static-handles decides in and out against through memory per target.

### 4.8 Before the decision

- *Preferred* (*proposed*): **born decided**. The allocation step (L05
  §2.4.4: which cells go into which lifetime, put parameters) and the
  class analyses (static-handles §4) are all callees-first or
  callers-first summaries and per-function walks over the same program
  graph, and the class reads nothing that placement writes. So one decide
  step computes both into tables, and one apply and restructure write
  every opener, binder kind, signature and mode copy at once. No
  undecided lifetime ever exists in the IR.
- *If the pipeline must split them*: an `undecided` kind, legal only
  between the allocation step and the decide step by the specification's
  stage data (C28, extended from op families to the cases of a type
  parameter, one generated trait), bound only by an undecided opener of
  its own (legal in the same stages). The `TypeConverter` has no rule
  for it, so it has no lowered form.

### 4.9 Lowering

| IR | lowered | rule |
| --- | --- | --- |
| `!idr.lifetime<view>`, `<home k>` | no value | 1-0 conversion (read, `DialectConversion.h:258-262`): dropped from signatures, calls and frames by the conversion, not by LLVM (C141) |
| `<room>` | `!llvm.ptr` | 1-1 |
| `<cursor>` | `!llvm.ptr`, and one more result of the function and of each call that passes it | a cursor slot per function, promoted by LLVM (static-handles §3.5); through memory where the results do not fit (L10 §2.1) |
| `cell.arena` | room: base plus the offset the layout walk gave; cursor: the one-check-per-run bump; home: the thread-local array's slot k | one fold over the kind |
| openers | their open and close (§4.2) | one pattern each |
| `idr.lifetime.forget` | nothing | its result converts to no value |

- The layout walk, once per `room` binder in one function: program
  order, a match's cases overlapping, each put call taking its callee's
  amount. It sizes `.block`'s `alloca` (an entry-block `alloca` of constant
  size, inside D32's bound) and gives every offset.
- Every rule is a context-free conversion, so upstream caches it (§2).

### 4.10 What upstream then does for free

Value scoping and dominance (D63, unchanged); type uniquing as the
specialization key; the call's operand-type check as the mode check; the
inliner, which maps put parameters directly and asks one hook for view
ones; every clone (TRMC, frames, copies) carrying kinds with types; CSE
and dead code untouched (kinds change no effect); dialect conversion's
cached type rules and its removal of zero-type values; ODS generating
every kind constraint (§4.1).

## 5. Handing a lifetime over at a tail call (Q33)

- D30 and C97: no lifetime region holds a tail call, since its end would
  follow the call. A hand-over makes the extent end in the tail callee,
  which is no region: the capability calculus's linear `cap ϱ`
  (prior-art §2.5), checked by an order on uses that MLIR's dominance does
  not give, the def-use verification D63 avoided (decision, D63; read,
  constraints §6).
- What it would buy is small (*conjecture*, review.md's `go` example,
  read at `audits/p0/verify/review.md:223-238`): `go n (step t)` keeps
  its accumulator in the dying lifetime only if the next iteration's
  cells may point into it, so the arenas chain up and nothing is freed
  until the loop ends; constant space comes from reuse instead (D24, C1;
  prior-art §7 item 3, "proved reuse replaces storage modes"), and an
  outer lifetime may pass through a tail call already (constraints V8).
- If a measurement asks for it (prior-art M5: sites A6 keeps counted
  because of a tail call), the lexical form exists: the caller's region
  ends by **packing** its lifetime into a linear value that owns its
  chunks and its root, the tail call takes the package (the region has
  ended, so D30 holds), and the callee opens it with a region binding a
  fresh lifetime value. That is the op pair constraints §9 proposes for
  0007's move between shards, built once for both. *Recommendation*:
  no non-lexical lifetimes; the pack and unpack pair when 0007 is taken
  or a measurement asks.

## 6. C84's cycle clause against per-level lifetimes (Q35)

- C84: no lifetime region holds a tail call or a call on its function's
  cycle. The second half exists because D32 frames every non-tail call on
  a cycle: its continuation becomes a frame and a resume, so a region
  spanning it would end in another function, after a `musttail` call
  (decision, C84, C96).
- The same pack and unpack pair splits such a region lexically, applied
  by idr-frames: the run's region ends before the push by packing, the
  frame holds the package (for `.stack`, the mark: one word; for
  `.chain`, the chain), and the resume opens a region binding a fresh
  lifetime value where the original region ended, its held values
  restated in it by the pop (constraints §3.5). Every region stays lexical
  in its function, the `musttail` stays valid, and the frame stack's
  linearity makes a second unpack unwritable (C96). This is
  static-handles §3.4's per-level lifetime in D63's form (*proposed*).
- A per-level lifetime is `.stack` or `.chain`, never `.block`: a block's
  cells cannot move into a frame without invalidating references to
  them, so the decide rule sends a finite per-level site to the stack
  (*proposed*; it removes static-handles §3.3's frame-relative case).
- D26 holds: a per-level instance is held by an active call, which D26
  counts (decision, D26), and each instance keeps its count or spine
  proof (C84).
- **For the owner**: reversing C84's cycle clause needs a dated ruling on
  evidence (AGENTS.md). The evidence: review.md §3 names the code that
  most wants arenas (a parser, an evaluator, a tree builder) as all on
  call cycles (read, `review.md:233-237`); the measurement is
  static-handles M6. C84's tail clause stays (C97, constraints V8).

## 7. Invariants and verifier rules

**Unwritable by construction**:
1. An allocation into a lifetime nothing may allocate into (`cell.arena`'s
   generated operand constraint).
2. A callee compiled for one mode called with another (the call's type
   check), and a dead register for a view-only lifetime (`view` converts
   to no value, with no context).
3. Two readers disagreeing on a lifetime's convention: there is one
   place, the binder's type; the opener fixes its binder's kind.
4. A mode lost by a clone, a frame or a case binder (types are copied).
5. A stack-versus-chain mismatch at a callee (callees see `cursor` only).
6. A lifetime reaching the lowering undecided (born decided; or the
   kind's stage data and no conversion rule).
7. A class-2 home without identity, or two sites sharing one in a copy
   (`home k`).
8. A non-lexical lifetime (§5); a second resume of a split lifetime (§6).

**Verifier rules**, each local, beside constraints V1 to V11:

| # | rule | where | cost |
| --- | --- | --- | --- |
| K1 | kind constraints: `cell.arena` takes put kinds; each opener fixes its binder's kind; `idr.lend` and `idr.activation` bind `view` | generated ODS constraints | per op |
| K2 | a lifetime operand's kind equals its parameter's, or the parameter is `view` | `idr.call::verifySymbolUses` | O(operands) |
| K3 | the per-parameter amount exists exactly for put-kind parameters, is `Finite` for `room`, and covers the body | `idr.func`'s region verifier, over each parameter's direct users | O(uses) |
| K4 | the opener family's memory forms are legal from the decide step on (and `undecided` before it, if it exists) | the one generated stage trait (C28) | per op |
| K5 | discipline: inside a `.stack` region, a put into a `cursor` value targets that region's lifetime or one opened inside it | the function's one walk, with its stack of open binders | O(ops × open depth) |
| K6 | tail groups: a `tail` call's caller and callee take the same number of `cursor` parameters | the call's verifier | O(parameters) |
| K7 | a `room` lifetime's region spans no frame push (after idr-frames, a framed call inside it is a `tail` call, already V8) | constraints V8 | — |

None follows a def-use chain: each reads a type, a binder one hop away,
or a value's direct users.

## 8. What it changes in the records

- C140: `!idr.lifetime` gains the kind parameter; `idr.lifetime.forget`
  is the one op with a lifetime result.
- static-handles §4.8: the mode moves from a function property to the
  parameter's type; the class stays the opener op.
- constraints §3.1 ("after the decide step it becomes one op per
  lowering"): kept; §3.2 (allocation into a borrow's lifetime): a loan's
  lifetime is `view`; §5.3 (the put set carried on the call): the put set
  is the type and the amount is not copied onto calls.
- C84's cycle clause, only by the owner's ruling (§6).
- static-handles §3.3's per-level block: gone (§6).

## 9. Measurements owed (none taken; each needs a build)

- M1: put parameters per function (k) and mode copies made, against
  4^k, on the suite and stage 1 (static-handles M1, M2).
- M2: `forget` casts made by the inliner and left after canonicalization
  (expected none).
- M3: `.stack` regions demoted to `.chain` by K5's conservative reading
  of cursor parameters, against the precision split kinds would give.
- M4: compile time of the lowering's type conversion with these rules
  against a context-aware one, on the stage-1 module.
- M5: sites kept counted by a tail call (prior-art M5), before §5's pair
  is built.
- M6: cells moved into per-level lifetimes by §6, against counted
  (static-handles M6).

## 10. Recommendation

**The design.** A lifetime's run-time convention is the kind in its
type, `!idr.lifetime<view | room | cursor | home k>`, read in zero steps
by every allocation, callee, frame and the lowering; its memory source is
its opener op, one per source; a function's per-parameter put amount sits
beside D61's part on `idr.func`. A view parameter accepts any kind; mode
copies are keyed by their function type; erased kinds convert to no value.

**Its upstream model.** The GPU dialect's address spaces: a closed enum in
the memref type, buffers bound by `gpu.func` as typed entry arguments and
stored by what binds them, a generic space reached by
`memref.memory_space_cast` for code that does not care, and one
registered conversion per kind. Beside it, `memref.alloc` against
`memref.alloca` for the opener family.

**The owner's decisions, one at a time, in this order**:
1. Q31: the convention in the lifetime's type (amending C140's
   parameterless type), the memory source in the opener op. Costs: a kind
   parameter, the `forget` cast, a subsumption rule at calls. Buys: one
   place read in zero steps everywhere, upstream's call check, inliner,
   clones and cached conversion doing the rest. The alternative is
   static-handles' function property.
2. Q32: the put amount as a per-parameter part on `idr.func`, in D61's
   record, not on calls; the "allocates into" bit is the kind.
3. Q35: reverse C84's cycle clause, with idr-frames splitting a region at
   a framed call by packing (§6); its evidence is review.md §3, its
   measurement M6.
4. Q33: no non-lexical lifetimes; the pack and unpack pair built once,
   for 0007 or a measured tail-call need (§5).

**For the coordinator**, following from AGENTS.md or the evidence, each to
be recorded with its reason: born decided (§4.8); a loan's and the
activation's lifetimes `view` (§4.2); `reserve` as its own op (§4.4); the
merged `cursor` kind with K5's conservative discipline (§4.6); a
per-level lifetime never `.block` (§6); `home k` a dense number, never a
symbol (§4.1).
