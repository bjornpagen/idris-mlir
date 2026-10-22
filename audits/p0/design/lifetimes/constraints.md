<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: a lifetime as an SSA value, its IR form and its checks

**Status (2026-10-21):** design under D63, nothing built, run or
settled. The owner ruled D63 after weighing three representations
against what MLIR does for free: "lifetime as an ssa value seems by far
the best way to do this, can we hard cutover to it pls?"
(`proposals/0000-mlir-native.md` §2, D63). D63 leaves to this folder how
a value's lifetime is known, how a signature relates a result to an
argument's lifetime, and how the verifier checks it without following
def-use chains. This file is that design: the types, the ops, the
signatures, the verifier, what is left of the grade's lifetime, and the
rulings it meets. Its siblings: `static-handles.md` (what a lifetime
value lowers to, per lifetime: nothing, a constant, a frame block, a
stack, a chain) and `prior-art.md` (MLKit, Cyclone, Swift SIL, OxCaml and
the rest). Where this file names an op, a type or a name, it is a
recommendation; which op or type holds a fact is the owner's (AGENTS.md).

**Grounds** (proposals/README.md): *read* (path:line; HEAD `e96bb991`
with the working tree's P0 through D69; the toolchain pin `7208ba24c`
under `.toolchain/llvm-project`), *measured* (the command), *recalled*
(from memory, to be checked), *conjecture* (an argument from read facts,
nothing built), *decision* (a ruling Dn or a coordinator decision Cn).
What this file proposes is marked *proposed*. P0's line numbers move as
it is edited, so its rulings are cited by number.

**Read for it**: the representation-first skill, AGENTS.md, P0 whole
(D19, D24 to D26, D30 to D32, D39, D40, D48, D58 to D63, C1, C2, C21,
C45, C79, C83, C84, C86, C96, C97 closely); `audits/p0/verify/` L05,
L04, L07, L08, L09, L10, L11, L20, L02, L06 and `review.md`; 0007 §5 and
§7; `design/match-and-counting.md` §4, §7; the two siblings above.

Words: a **lifetime value** is an SSA value of type `!idr.lifetime` (D63's
"token"; this file says "lifetime value" because counting's reuse tokens
and the join points' tokens already use the word). A value is
**lexical** when its grade says it holds a reference that dies with a
lifetime value's scope. A value's **stated lifetime** is the lifetime
value its producer or binder names for it (§4). **Puts** and **gets** as
L05: a function that allocates into a lifetime puts into it.

## 0. The form in one page

- **One type**, `!idr.lifetime`, no parameters. Its values are bound in
  four places only: the entry argument of an `idr.lifetime` region, the
  entry argument of an `idr.borrow` region (C83), the result of
  `idr.frame` (this activation), and a function parameter. A lifetime
  value is never a result, never yielded, never stored, never a join
  parameter (§3).
- **The grade keeps the kind, the op says which.** `!idr.q<q, hold, T>`
  with hold `own | excl | borrow lexical | plain lexical | plain static |
  plain` (L05's quantity × hold, D62). A type cannot name an SSA value
  (§12), so the type says only that the value is lexical; the op that
  produces a lexical value names its lifetime value as an operand
  (`in %l`), and every binder of lexical block arguments names theirs.
  `counted` is implied by `own` and `excl`; `static` stays; `frame`
  leaves the grade and becomes `idr.frame`'s value (§2).
- **One hop.** A value's stated lifetime is an operand of the op that
  defines it, or a stated lifetime of the op that binds it; no check
  looks further (§4).
- **Outlives is dominance.** Lifetime value `a` outlives `b` when `a`'s
  binder encloses `b`'s; the function verifier's one walk keeps the open
  binders on a stack, so the test is a comparison of two depths (§4.4).
- **Signatures relate results to arguments by parameter.** `@lookup(%r :
  !idr.lifetime, %k : i64, %t : … lexical in %r) -> (… lexical in %r)`:
  the result lives as long as the tree argument because both name `%r`.
  `@map(%r, %s, %xs : … in %s) -> (… in %r)` puts into its caller's
  lifetime `%r`. Bounds between lifetime parameters are part of the
  signature (§5).
- **MLIR does the scoping.** A lexical value's producer takes a lifetime
  value that is visible only inside its binder's region, so the value
  cannot be used after that region, except through the region's results,
  whose stated lifetime is an operand from outside (LangRef value
  scoping, §6). The inliner remaps lifetime values as any operand; no
  lifetime is substituted (§8).
- **One value, both jobs** (D63): where a function puts into a lifetime,
  the value lowers to the run-time handle; elsewhere it is erased.
  Which, and to what, is `static-handles.md`'s per-lifetime decision.

## 1. What the form must meet

| # | constraint | source |
| --- | --- | --- |
| K1 | A lifetime is an SSA value; `idr.lifetime` opens a region and gives its value; functions take lifetimes as arguments, calls pass them; MLIR's scoping and dominance check that nothing of a lifetime outlives it; the inliner, CSE and dead code handle it with no substitution or inliner of ours; lifetime variables leave the type; the grade's lifetime keeps only what is not a lexical lifetime | decision, D63 |
| K2 | A value's lifetime is known by the op that makes a view or allocates taking the lifetime value; the verifier checks without following def-use chains | decision, D63; P0 §5.3 ("no verifier that follows def-use chains"); D39 deletes the owned walk |
| K3 | A callee can build its result in its caller's lifetime; a recursive `lookup` returns a view of its tree, counting nothing | decision, D39 |
| K4 | No fact known statically is paid at run time | decision, D10 |
| K5 | Every lifetime carries its D26 proof (count or spine), counting the fallback; no lifetime region holds a call in tail position or a call on its function's cycle | decision, D26, C84 |
| K6 | A parameter D24 rebuilds is `(1, excl)`, counted | decision, D24; L05 §2.1 |
| K7 | A call in tail position never grows the stack; no operand of a tail call has a lifetime that ends with the call | decision, D30, C97 |
| K8 | Recursion on a call cycle keeps its depth on typed, linear frame stacks after counting; the native stack is small and its size static | decision, D31, D32, C96, D66 |
| K9 | Regions per case; join points; no jump leaves an `idr.lifetime` or `idr.borrow` region | decision, D19, D25; read, `L09-control-flow.md:82, 396` |
| K10 | One fact, one place; a copy kept in step by a verifier is still a copy; a fact in a discardable attribute can be lost | AGENTS.md |
| K11 | Every slot is a static alloca: LLVM treats an alloca as static only in the entry block with a constant size | read, `llvm/lib/IR/Instructions.cpp:1324-1331` |
| K12 | A lifetime moves whole between shards; lending is a lifetime region whose end joins | decision, D39, D62; L20 I8 |
| K13 | Index variables keep D48's binder, its substitution and the clone-under-substitution inlining of index-polymorphic callees | decision, D48 as amended by D63, C79 |

## 2. The type and the grade

### 2.1 `!idr.lifetime`

- One type with no parameters (*proposed*). Its spelling follows D40's
  name for the concept; the op `idr.lifetime` and the type
  `!idr.lifetime` live in MLIR's separate op and type namespaces.
- It is our type, not upstream's builtin `token`: the builtin token
  "carries no runtime data and cannot be forwarded", and only an op with
  `TokenProducerTrait` defines one (read,
  `mlir/include/mlir/IR/BuiltinTypes.td:1264-1280`), so it cannot be a
  function argument naming the caller's lifetime (K1). The escape the
  builtin token's rule forbids is forbidden here by §3's binders and
  MLIR's value scoping instead.
- Quantity many, no grade. Not linear: it is never consumed, never
  returned and never threaded, so no op makes a new one from an old one
  (§3.6). The cursor that some lifetimes lower to may be threaded at the
  lowering (`static-handles.md` §3.5, §4.6); that is the lowered form's
  convention, not the IR value's.
- Lowered to nothing, or to the handle of `static-handles.md`'s class 2
  to 5 (§7).

### 2.2 The grade after D63

The grade is `!idr.q<q, hold, T>`, L05 §2.1's quantity × hold, which D62
left to the lifetime research to confirm and this file keeps
(*proposed*), with the lifetime position reduced to a kind:

| hold | lifetime kind | meaning | `dup` | `drop` |
| --- | --- | --- | --- | --- |
| `own` | counted, implied, unwritten | one counted reference | n/a | decrements |
| `excl` | counted, implied | the only reference to everything it reaches | n/a | frees, reads no count |
| `borrow lexical` | a lifetime value, stated by the producer or binder | a view of counted memory valid while that lifetime lasts | increments | none |
| `plain lexical` | a lifetime value, stated likewise | a reference into a lifetime's uncounted memory (a slot, an arena) | ill-typed | none |
| `plain static` | the whole run | static data | emits nothing | none |
| `plain` | none | reaches no cell, or undecided before counting | n/a | n/a |

- **`frame` leaves the grade** (*proposed*, following D63's "keeps only
  what is not a lexical lifetime"; L05 defines frame as a lexical
  lifetime, `L05-lifetimes.md:19-20`, read). This activation's lifetime is
  the value of `idr.frame` (§3.3). Kept as a constant, `frame` would be a
  second mechanism for a lexical lifetime beside the values, with its own
  rules (never returned, never across a back edge, never at a tail call,
  `foreign/idr/include/idr/IR/Lifetimes.h:11-28`, read), and the meet of
  two lifetime parameters, which is this activation, would have no value
  to state. Considered and set aside for that reason.
- **`counted`** stays the implied lifetime of `own` and `excl`, as D40
  left it unwritten. A view at `counted` is still unrepresentable (L05
  §2.1).
- **`lexical`** is a name to settle (*proposed*: L05 already defines the
  word for exactly this set, frame or a lifetime variable). It is a kind
  in the type, never an identity; the identity is the operand. The type
  needs it because type constraints read it with no op in hand: `idr.dup`
  refuses `plain lexical`, a counted cell's field refuses any lexical
  value, placement's domain is counted or lexical (L07 §2.2).
- **Printed**: `!idr.q<many, borrow, !idr.data<#Tree[]>, lexical>`;
  `!idr.lin<T>`, `!idr.own<T>`, `!idr.excl<T>` stay as spellings.
- **Unrepresentable by the sum**, as L05 §2.1 has it: an owned or
  exclusive value at a lexical lifetime (L05 Q1's counted shell, §10); a
  view at `counted`; a lifetime on a value that reaches no cell.

### 2.3 What D63 deletes here

Lifetime variables in types and their de Bruijn levels (C79's lifetime
half); `lifetime` as a sort of `ErasedBinderOpInterface`, which keeps
`idr.func` and `idr.match` for index variables, and loses `idr.lifetime`
and `idr.borrow` (C79 restated); the substitution of lifetimes (the
utility stays for index terms, D48, D58, D59); the outlives order over
type-level variables (L05 §2.2; C21's partial order becomes §4.4's
dominance test); D40's `!idr.q<1, own, T, ρ>` printing; `!idr.arena<ℓ>`
of the earlier lane drafts (`L05-lifetimes.md:368-371`), whose job the
lifetime value does; the `frame` constant (above).

## 3. Where lifetime values come from

A lifetime value has exactly one binder. Each is listed with its scope,
which is MLIR's: the value is visible only where its binder's region or
block reaches (read, `mlir/docs/LangRef.md:474-482`: "values defined in
a region don't escape to the enclosing region").

### 3.1 `idr.lifetime`

```mlir
%r:2 = idr.lifetime -> (i64, !idr.q<many, plain, !idr.data<#Expr[]>, lexical>) in %outer {
^bb0(%l : !idr.lifetime):
  ...
  idr.yield %n, %e : i64, !idr.q<many, plain, !idr.data<#Expr[]>, lexical>
}
```

- One region, one block; its only entry argument is `%l`, its lifetime
  value, a *non-forwarded* argument: the op produces it, no operand
  feeds it, as `scf.for`'s induction variable is not among its
  successor inputs (read, `mlir/lib/Dialect/SCF/IR/SCF.cpp:722-725`).
  D63's "yields a token" is this argument: a result would be visible
  after the region and outlive it.
- `in %outer`: the stated lifetime of its lexical results, an operand,
  present exactly when a result is lexical. Being an operand, it is
  defined outside the region, so no value of `%l` can be yielded (§6).
- `RegionBranchOpInterface`: entry to the region once, the region to the
  parent. `RecursiveMemoryEffects`. Not `PropagateControlFlowBreak`: no
  jump leaves it (D25, `L09-control-flow.md:82`).
- **Not an `AutomaticAllocationScope`** (*proposed*; corrects
  `L05-lifetimes.md:375-377`). Today's slot lowering puts a slot at the
  entry of the nearest op with that trait (read,
  `foreign/idr/lib/Conversion/Cells.cpp:93-95`). With the trait on
  `idr.lifetime`, a slot inside one would become an alloca in the
  region's block, which after `convert-scf-to-cf` is not the function's
  entry block, so LLVM no longer counts it static (K11) and D32's
  computed bound breaks. Every slot stays an entry-block alloca, one per
  op, rewritten each run of its lifetime, as today (read, `Cells.cpp:76-78`).
- Its end releases the lifetime's chunks, declared `Free` on `idr.heap`
  (reporting only, D23), so a function's row is never told `nofree`
  wrongly. Because `Free` keeps upstream's trivial-dead test from
  deleting it (an op is trivially dead only if its effects are reads or
  allocations of its own results, read,
  `mlir/lib/Interfaces/SideEffectInterfaces.cpp:69-95`), one fold of
  ours inlines an `idr.lifetime` whose value has no use (*proposed*).
- One op serves an allocation extent and a lend (D62, L20 I8): whether
  the lifetime has memory is whether its value has an allocating use,
  read off the IR, never a flag.
- After `static-handles.md` §4.8's decide step it becomes one op per
  lowering (`.frame`, `.stack`, `.chain`, `.home`, or itself with no
  memory), the members of one family; every rule here holds of each.

### 3.2 `idr.borrow` (C83, with its lifetime value)

```mlir
%o2, %n = idr.borrow %o -> (i64) {
^bb0(%b : !idr.lifetime, %v : !idr.q<many, borrow, !idr.data<#Toks[]>, lexical>):
  ...
  idr.yield %x : i64
}
```

C83's region op, unchanged but for its binder: arg 0 is the loan's
lifetime value, arg 1 the view, whose stated lifetime is arg 0 by the
op's definition (a fixed position of a non-forwarded argument, not a
list upstream's argument rewrites can shift). The owner comes back as
result 0 (C83). A borrow's lifetime may also take allocations of
temporaries that die with the loan, which makes it an allocation extent
like §3.1's.

### 3.3 `idr.frame`: this activation's lifetime

```mlir
%f = idr.frame
```

- *Proposed.* The lifetime of the rest of its enclosing region; at the
  top of a function body, the activation. It replaces the `frame`
  constant (§2.2).
- Used by slots (`idr.cell.stack in %f`) and passed as the lifetime of a
  callee's parameters that live for one call (§5.1); never returned and
  never a tail-call operand (§6, V6, V8); never an arena
  (`cell.arena in %f` is refused, V9): a slot's memory outlives every
  region it may sit in, an arena's would not survive inlining (below).
- Declares `Allocate` on `idr.identity` of its result (C3's fresh
  identity), so CSE never merges two and LICM never hoists one, and
  upstream's dead code deletes it when unused
  (`SideEffectInterfaces.cpp:77-90`, read).
- *Under inlining*: the callee's `idr.frame` lands where the call was,
  and its value then lives for the rest of that region. Its slots are
  the caller's entry-block allocas, which outlive that region, so the
  memory is safe; its values cannot leave that region (§6). Inlined into
  a loop body, it is a per-iteration lifetime and its values cannot cross
  the back edge (§6, the merge rule). Nothing is rewritten.

### 3.4 Function parameters

A parameter of type `!idr.lifetime` names a lifetime the caller owns. It
outlives the activation and every lifetime the function binds, and is
incomparable with another lifetime parameter unless the signature
declares a bound (§5.1). Lifetime parameters arise only where a
signature needs one (a result related to an argument, a put into the
caller's lifetime, or arguments that live for one call), written by
counting's passes, never by the frontend (§5.5).

### 3.5 Frame kinds, after `idr-frames`

D31's frames hold a recursion's continuations (C96). A put function on a
call cycle, or a function holding views of a caller's lifetime across a
member call, keeps its lifetime parameter and its lexical values live
across the call, so a frame kind holds them: a field of type
`!idr.lifetime` (zero bytes where erased, the handle where not), each
lexical field stating a sibling lifetime field, fixed by the frames pass
per kind (*proposed*; seam with C96 and L10 §2.3, whose families admit
no lifetime field today, `L04-families.md:503-515`). The resume's pop
binds them, its lifetime fields acting as parameters. Sound because a
frame is popped before the lifetime's owner, which C84 keeps outside the
component, ends (*conjecture*, argued as L10 does for views,
`L10-tail-frames-stack.md:909-914`).

### 3.6 Nowhere else

A lifetime value is never: a result of any op or function; a yield,
return or jump operand; a field of a data family (frame kinds aside); a
block argument of a match case or a join region; an operand of an op
that does not declare a lifetime operand. Each is a type constraint on
the op (generated with the op from the specification, D16), checked
locally (V1). So a lifetime value cannot escape its binder's region:
the only way out of a region is its terminator, and no terminator takes
one.

*Join regions take no lifetime parameter* (*proposed*). Contification
(C95) turns a function with lifetime parameters into a join region only
where every jump passes the same lifetime value, which the join region
then uses from above; the usual case, since a recursion passes its
lifetime on. Where they differ, the call stays a call (a `musttail` one
in tail position, which D30 allows). This keeps every join region's
stated lifetime an operand of the join op, which upstream's
argument-deleting patterns cannot misalign (§4.3).

## 4. How a value's lifetime is known

### 4.1 The rule: one hop

The **stated lifetime** of a lexical value `v` is:
- if `v` is an op's result: that op's lifetime operand (one per op, for
  all its lexical results);
- if `v` is a block argument: the stated lifetime its binder declares
  for it: a function parameter's, in the signature (§5.1); a match
  case's arguments, the match's case lifetime operand; an `idr.borrow`
  view, its arg 0; a join region's parameter, the join op's lifetime
  operand for that region; a frame pop's field, its sibling lifetime
  field.

Every case is one pointer from `v`: `v.getDefiningOp()`'s operand, or
`v.getOwner()`'s declaration. No case recurses. This is how the verifier
meets K2: it never walks from a value to the op that took the lifetime;
the producer took it, so the producer says it.

The rule's price is that every op producing a lexical value carries an
operand naming the lifetime. That operand is the result type's missing
parameter, moved to an operand because a type cannot name a value: the
type says *lexical*, the operand says *which*, two halves of one fact,
neither a copy of the other. It is present exactly when a result is
lexical, a generated constraint, so it is no flag: it never changes what
the op does (K10, the skill's rule on flags).

### 4.2 The ops that state a lifetime

| op | lexical results | stated lifetime |
| --- | --- | --- |
| `idr.cell.arena in %l` | the uninitialized cell | `%l` (an allocation takes the value, D63) |
| `idr.cell.stack in %l` | the slot | `%l`, bound in this function (V9) |
| `idr.cell.init %c @C(…) in %l` | the built value (and D34's destination) | `%l`, equal to the cell's |
| `idr.con @C(…) in %l` | an inline value holding a lexical field | `%l` |
| `idr.field %x[i] in %l`, `idr.unpack %x @C in %l` | a field | `%l`, outlived by `%x`'s |
| an element view inside a borrow region (C85) | the element | the region's arg 0 |
| `idr.reindex`, the regrade casts | the same value at another type | `%l`, outlived by the operand's |
| `idr.match %x in %s -> (…) in %r` | case arguments in `%s`; results in `%r` | two operands, each present exactly when needed |
| `idr.join`, `idr.loop` | each region's lexical parameters; the op's lexical results | one lifetime operand per region, one for the results |
| `idr.lifetime`, `idr.borrow` | lexical results | one operand (§3.1) |
| `idr.call` | lexical results | per result, one of the call's lifetime operands (§5.2) |

`idr.cell.new`, `idr.cell.recycle` and `idr.cell.static` (C86's
never-freed memory, *proposed* as its own source, since `static` has no
value) take no lifetime: their cells are counted or static.

### 4.3 Merges state their lifetime

A value crosses a merge (a region op's results, a join region's
parameters) only into a lifetime the merge states, and the verifier
checks each incoming value against it (V5). This is the difference from
Swift's ownership SSA, where a scoped value flows through block
arguments with no stated scope and every check walks to find it
(`prior-art.md` §4, *read* there): here every merge carries the answer.
One stated lifetime per merge, not one per result or parameter, so no
positional map exists for upstream's patterns to misalign when they
delete a dead result or parameter (*proposed*). The cost: two lexical
results of one match in two incomparable lifetimes are both stated at
the inner of them, or at the activation; a precision loss, to count on
the suite (M5).

### 4.4 Outlives is dominance

`a` outlives `b`, for lifetime values in scope at one point:
- `a == b`; or
- `b` is bound by an `idr.lifetime`, `idr.borrow` or `idr.frame` nested
  inside `a`'s scope: `a` dominates `b`'s binder (MLIR's dominance); or
- `a` and `b` are lifetime parameters (or frame-pop fields) and the
  signature declares `a` outlives `b`.
Lifetime parameters outlive every lifetime the function binds. `static`
outlives everything; `counted` (`own`, `excl`) may be held by any
lexical cell and holds none.

The function verifier's one walk (01 C7(b)'s fused walk) keeps the open
binders on a stack and records each lifetime value's depth in a dense
array numbered once per walk; parameters sit at depth 0. Both operands
of a test are in scope where it is made, so both are on the stack and
the test is a comparison of depths, O(1), with no ancestor walk and no
query of the IR's order (perf-sources' warning, 101edbc5).

## 5. Signatures

### 5.1 A function's lifetimes

```mlir
idr.func @lookup(%r : !idr.lifetime, %k : i64,
                 %t : !idr.q<many, borrow, !idr.data<#Tree[]>, lexical> in %r)
    -> (!idr.q<many, borrow, !idr.data<#Maybe_V[]>, lexical> in %r)
```

- *Proposed.* An inherent property of `idr.func` (never a discardable
  attribute, K10) holds, for each lexical parameter and each lexical
  result, the index of the lifetime parameter it lives in; and a list of
  declared bounds, pairs (i, j) meaning parameter i outlives parameter j.
  Printed `in %r` after the type, `where %s >= %r` after the signature.
- Parameters that live for one call share one lifetime parameter; the
  caller passes its innermost lifetime (its `idr.frame` value, or a
  region's). Results never live in it (V6).
- **Bounds** (*proposed*, a gap L05 left: its order made two parameters
  incomparable, `L05-lifetimes.md:327-329`, read). A parser whose syntax
  tree holds views of its source needs the source's lifetime to outlive
  the tree's (`where %s >= %r`); without the bound the tree copies each
  token into a counted string. Inferred with the parameters, checked at
  each call by §4.4's test.
- The property is edited only by counting's passes and specialization,
  through the one clone-and-key template (L20 I7); upstream never
  rewrites our signatures (its `remove-dead-values` is not used, P0 §6),
  and the inliner removes the entry it describes.

### 5.2 Calls

```mlir
%m = idr.call @lookup(%b, %k, %tv)
    : (!idr.lifetime, i64, !idr.q<many, borrow, !idr.data<#Tree[]>, lexical>)
    -> (!idr.q<many, borrow, !idr.data<#Maybe_V[]>, lexical> in %b)
```

- The call passes lifetime values as operands (K1). Its lexical results
  state their lifetimes as indices of its own operands, an inherent
  property of the call, so a pass on the caller reads them with no symbol
  lookup (*proposed*). It is the call's statement of its callee's
  signature, as the call's operand types are, checked against the callee
  in `verifySymbolUses`; D22 put the row on the call for the same
  reason.
- The call carries the callee's put set (§5.3) the same way.

### 5.3 The put set

Per lifetime parameter, whether the function or a callee it passes the
value to allocates into it: one bit, callees first over the SCCs, a
monotone two-point marking that ends by construction
(`static-handles.md` §4.1). Held on the function, carried on the call,
verified per function, in the shape of D61's per-parameter part, never
an atom of the row (C2 R3 as amended calls the put an operand). It is
what decides "the token is the run-time arena handle" against "erased"
(D63). In the IR it is a fact about the function; the run-time cost
appears only at the lowering (§7).

### 5.4 The four examples

**A parser building its syntax tree in a request's lifetime.**

```mlir
idr.func @parseExpr(%r : !idr.lifetime, %s : !idr.lifetime,
                    %src : !idr.q<many, borrow, !idr.data<#Toks[]>, lexical> in %s,
                    %pos : i64)
    -> (!idr.q<many, plain, !idr.data<#Expr[]>, lexical> in %r, i64) {
  %t, %p1 = idr.call @parseTerm(%r, %s, %src, %pos) : (…) -> (… in %r, i64)
  %plus = …                                        // the next token is '+'
  %e, %p = idr.match_lit %plus -> (!idr.q<many, plain, !idr.data<#Expr[]>, lexical>, i64) in %r {
    case 1 {
      %u, %p2 = idr.call @parseExpr(%r, %s, %src, %p1) : (…) -> (… in %r, i64)
      %c = idr.cell.arena in %r : !idr.cell<!idr.data<#Expr[]>, @Add>
      %a = idr.cell.init %c @Add(%t, %u) in %r : !idr.q<many, plain, !idr.data<#Expr[]>, lexical>
      idr.yield %a, %p2
    }
    default { idr.yield %t, %p1 }
  }
  idr.return %e, %p
}

idr.func @serveOne(%toks : !idr.own<!idr.data<#Toks[]>>) -> i64 {
  %toks2, %n = idr.borrow %toks -> (i64) {
  ^bb0(%b : !idr.lifetime, %tv : !idr.q<many, borrow, !idr.data<#Toks[]>, lexical>):
    %v = idr.lifetime -> (i64) {
    ^bb1(%l : !idr.lifetime):
      %e, %p = idr.call @parseExpr(%l, %b, %tv, %c0)
          : (!idr.lifetime, !idr.lifetime, !idr.q<many, borrow, !idr.data<#Toks[]>, lexical>, i64)
          -> (!idr.q<many, plain, !idr.data<#Expr[]>, lexical> in %l, i64)
      %x = idr.call @eval(%l, %e) : (!idr.lifetime, !idr.q<many, plain, !idr.data<#Expr[]>, lexical>) -> i64
      idr.yield %x : i64
    }
    idr.yield %v : i64
  }
  idr.drop %toks2 : !idr.own<!idr.data<#Toks[]>>
  idr.return %n : i64
}
```

The checks: `%a`'s fields `%t` and `%u` live in `%r`, which outlives
`%r` (V4); the match's yields are in `%r`, its stated result lifetime
(V5); the return's result 0 is in `%r`, the signature's (V6). At the
call in `@serveOne`, `%tv` lives in `%b`, passed for `%s`, and the result
is stated in `%l`, passed for `%r` (V7); with the zero-copy bound `%s >=
%r`, `%b`'s binder encloses `%l`'s, so it holds (§4.4). `%e` cannot be
used after the `idr.lifetime` region, and `%x` is a word, so the yield is
legal. Put sets: `parseExpr` puts into `%r`, so `%l` is a handle at the
lowering; `%b` and `eval`'s lifetime parameter are erased. The recursive
call is on a cycle and not in tail position, so D32 frames it, and the
frame holds `%r`, `%s`, `%src` and `%t` (§3.5). The tree's cells hold
only words and references into `%l`, so the region frees in O(1) (L05
§2.6.1).

**A recursive `lookup` returning a view of its tree.**

```mlir
idr.func @lookup(%r : !idr.lifetime, %k : i64,
                 %t : !idr.q<many, borrow, !idr.data<#Tree[]>, lexical> in %r)
    -> (!idr.q<many, borrow, !idr.data<#Maybe_V[]>, lexical> in %r) {
  %m = idr.match %t in %r -> (!idr.q<many, borrow, !idr.data<#Maybe_V[]>, lexical>) in %r {
    case @Leaf() { %no = idr.con @Nothing() : !idr.data<#Maybe_V[]>; idr.yield %no }
    case @Node(%a : …, %key : i64, %v : …, %b : …) {
      %c = arith.cmpi slt, %k, %key : i64
      %w = idr.match_lit %c -> (…) in %r {
        case 1 { %x = idr.call tail @lookup(%r, %k, %a) : (…) -> (… in %r); idr.yield %x }
        default { %j = idr.con @Just(%v) in %r : …; idr.yield %j }
      }
      idr.yield %w
    }
  }
  idr.return %m
}
```

The case arguments `%a`, `%v`, `%b` live in `%r` (the match's case
lifetime); the tail call passes `%r`, a lifetime parameter, which V8
allows; `@Nothing` holds no reference and enters the lexical result by
subsumption. Put set empty, so `%r` is erased: at run time `lookup(k, t)`
takes no handle and counts nothing (K3, K4).

**`map` allocating into its caller's lifetime.** Before D34:

```mlir
idr.func @mapInc(%r : !idr.lifetime, %s : !idr.lifetime,
                 %xs : !idr.q<many, borrow, !idr.data<#List[]>, lexical> in %s)
    -> (!idr.q<many, plain, !idr.data<#List[]>, lexical> in %r) {
  %y = idr.match %xs in %s -> (!idr.q<many, plain, !idr.data<#List[]>, lexical>) in %r {
    case @Nil() { %n = idr.con @Nil() : !idr.data<#List[]>; idr.yield %n }
    case @Cons(%x : i64, %t : !idr.q<many, borrow, !idr.data<#List[]>, lexical>) {
      %x1 = arith.addi %x, %one : i64
      %rest = idr.call @mapInc(%r, %s, %t) : (…) -> (… in %r)
      %c = idr.cell.arena in %r : !idr.cell<!idr.data<#List[]>, @Cons>
      %l = idr.cell.init %c @Cons(%x1, %rest) in %r : !idr.q<many, plain, !idr.data<#List[]>, lexical>
      idr.yield %l
    }
  }
  idr.return %y
}
```

D34 then makes it a loop that builds each cell first and fills its tail
through a destination stated in `%r`; `%r` and `%s` are used from above
by the loop's join region, which takes no lifetime parameter (§3.6). The
put set holds `%r`; `%s` is erased. A caller with no lifetime for the
result (it escapes into counted memory) calls the counted copy, which has
no `%r` and builds `own` cells (C45; `static-handles.md` §4.7).

**A function polymorphic in a lifetime that never allocates.**

```mlir
idr.func @length(%s : !idr.lifetime,
                 %xs : !idr.q<many, borrow, !idr.data<#List[]>, lexical> in %s) -> i64
```

Its body matches `%xs in %s`. `%s` exists so its field reads can state
a lifetime; its put set is empty, so at run time `length` takes the list
alone, one body serving every lifetime (K4). Its lexical parameter could
be stated in `%f` of no function, since parameters precede the body;
that is why one-call parameters take a lifetime parameter instead
(§5.1).

### 5.5 Who writes what

| fact | written by | alone |
| --- | --- | --- |
| a function's lifetime parameters, their map and bounds | the borrow marking (C1 as amended: owned, or a view in a lifetime parameter) and the view-result inference (L05 §2.4.2), callees first over the SCCs | those, through the clone-and-key template |
| `idr.borrow` and its value | placement (C83) | placement |
| `idr.lifetime`, `idr.frame`, `cell.arena`, `cell.stack`, put parameters | the allocation step that replaces `idr-rc-stack` (L05 §2.4.4) | that step |
| the put set | §5.3's marking, verified | that marking |
| a lowering class | `static-handles.md` §4's decide step | that step |
| lifetime fields of frame kinds | `idr-frames` | that pass |
| nothing | the frontend: lifetimes are counting's inference; before counting no value is lexical (L05 §2.1) | — |

## 6. The verifier

Run in each function's region verifier after every pass, in the one
fused walk, in parallel per function (P0 §5.3). Each rule reads an op,
its operands' stated lifetimes (one hop each) and §4.4's depth test.

| # | rule | cost |
| --- | --- | --- |
| V1 | `!idr.lifetime` only where §3 binds it; never a result, a terminator operand, a field (frame kinds aside), a case or join-region argument | per op, generated type constraints |
| V2 | every lexical result has its op's lifetime operand; every lexical block argument has its binder's stated lifetime | per op, generated |
| V3 | an op deriving a lexical result from a lexical operand (field, unpack, case arguments, casts, element views): the operand's stated lifetime outlives the op's | O(1) per operand |
| V4 | holding: a constructor at stated lifetime `L` takes words, `plain static`, `own` or `excl` (dropped at `L`'s end, by an op that declares the count effect), or lexical fields whose lifetimes outlive `L`; a counted cell takes no lexical field (L05 §2.2) | O(fields) |
| V5 | merges: every yield's lexical operand outlives its region op's stated result lifetime; every jump's lexical argument outlives its target region's stated lifetime | O(operands) |
| V6 | returns: each lexical result's stated lifetime is the parameter the signature names | O(results) |
| V7 | calls: each lexical argument outlives the lifetime passed for its parameter's lifetime parameter; the passed lifetimes satisfy the callee's bounds; the call's stated result lifetimes and put set equal the callee's (`verifySymbolUses`) | O(operands) |
| V8 | tail calls (C97): every lifetime operand is a lifetime parameter of the caller; no lexical operand lives in an `idr.frame` value | O(operands) |
| V9 | sources: `cell.arena` never takes an `idr.frame` value; `cell.stack`'s lifetime is bound in this function, and no repeating region lies between the slot and that binder | O(1), the walk's stack |
| V10 | D26 (C84): each bound lifetime's count or spine proof, over its value's direct users; each put parameter's spine relative to the returns | O(users) |
| V11 | linearity, exact-once ownership and the holds, as L05 §2.5 rule 5 and C87 | unchanged |

**What MLIR's scoping makes automatic**, with no rule of ours:
- *A lexical value used after its lifetime*: its producer takes the
  lifetime value, which exists only inside the binder's region, so the
  value is defined there and is not visible after it
  (`LangRef.md:474-482`, read).
- *A region's own lifetime leaking through its results*: V5 compares
  with the stated result lifetime, an operand of the region op, defined
  outside it; the region's own value does not outlive it, so the yield
  fails. The same holds for a return (no bound lifetime is a parameter)
  and for a lifetime value itself (no terminator takes one, V1).
- *A tail call carrying a lifetime that ends with it*: no tail call lies
  inside an `idr.lifetime` region, since the tail-position walk passes no
  tail position into one (its end follows its region,
  `L10-tail-frames-stack.md:552-564`), so its value is not visible at any
  tail call; V8 is left with `idr.frame` and the caller's own parameters.
- *A back edge carrying a per-iteration lifetime*: a lifetime bound
  inside a loop's region does not outlive the join region's stated
  lifetime, defined above the loop, so V5 fails for it.
- *A jump out of a lifetime*: neither binding op propagates breaks
  (L09's jump verifier, `L09-control-flow.md:227-231`).

Nothing follows a def-use chain. What the deleted owned walk did by
following each view to its uses (`Owned.cpp:126-208`, cited at
`L05-lifetimes.md:135-139`) is now the producer's operand and MLIR's
visibility rule.

## 7. Lowering

What a lifetime value becomes is `static-handles.md`'s, per lifetime:
nothing (an empty put set), a thread-local constant, a block in the
opener's frame, a push and pop on a per-computation lifetime stack, or a
register-passed cursor over its own chunks. This form gives that design
what its §7 asks of D63's value: every allocation takes the value, so
its users cover its cells and no dead-code pass drops a value a live
cell needs; calls pass lifetime values at parameters the signature
relates to results; the put set is derived and verified (§5.3); the
class decision is held by the source op (§3.1's family), so the lowering
decides nothing. An erased lifetime parameter is dropped from the
function and from every call by our signature conversion: LLVM would
not drop it, since its dead-argument pass freezes every function with a
`musttail` call or caller, and the test meant to spare `tailcc`
functions is always true (`F.getCallingConv() != CallingConv::SwiftTail
|| F.getCallingConv() != CallingConv::Tail`, read,
`llvm/lib/Transforms/IPO/DeadArgumentElimination.cpp:640-641`; the
freezes at `:505-511`, `:531-537`). Under D30 every internal function is
`tailcc` and every tail call `musttail`, so no dead argument is ever
removed there: an upstream bug, for a patch of its own (AGENTS.md).

## 8. Upstream machinery

| machinery | what it does here | of ours |
| --- | --- | --- |
| value scoping, dominance | the scope check and the outlives order (§4.4, §6) | the depth stack in the existing walk |
| the inliner | maps the callee's lifetime parameters to the call's operands; every stated lifetime in the inlined body is an operand, remapped; types carry no lifetime, so they match | `materializeCallConversion` (read, `mlir/include/mlir/Transforms/DialectInlinerInterface.td:129-133`) for grade subsumption at a call, where `inlineRegion` demands equal types (read, `InliningUtils.cpp:394-396`) and `inlineCall` asks for a cast (`:531-536`) |
| CSE | merges two derivations of one value stating one lifetime; never merges allocations, `idr.frame` or lifetime regions (their effects) | none |
| dead code | deletes an unused `idr.frame` and unused derivations | the fold of §3.1 for an unused `idr.lifetime` |
| canonicalizer | our match and join folds keep the stated lifetime operands they carry; a known-case fold materializes fields stating the match's case lifetime | those folds, already ours |
| index-polymorphic inlining | unchanged by D63: C79's clone under substitution, then `inlineCall` | as C79 (index variables only) |

D63's "with no substitution or inliner of ours" holds for lifetimes;
index variables keep C79's utility and its inlining path (K13).

## 9. The rulings it meets

- **D24.** A rebuilt parameter is `(1, excl)`; no lexical value has that
  grade, so lifetime allocation cannot take a promised cell, read off the
  types before any optimization (L05 §2.1).
- **D26, C84.** Every bound lifetime and every put parameter carries its
  proof (V10); a cell without one stays `cell.new`. Allocation sites are
  the lifetime value's direct users, which MLIR's use lists give. C84's
  rule that no lifetime region holds a call on its function's cycle
  stands; `static-handles.md` §4.3 and §5.2 describe per-level lifetimes
  that would lift it, which needs the frame kinds of §3.5 and a ruling
  that reverses C84's clause on evidence (§13).
- **D30, C97.** §6: local lifetimes cannot reach a tail call; V8 keeps
  the activation's lifetime out; a lifetime parameter passes through a
  tail call, as a borrowed argument at a tail call must be the caller's
  own view (`L10-tail-frames-stack.md:629`).
- **D31, C96.** Lifetime values and lexical values are held in frames as
  fields (§3.5); frame tops and lifetime values are both SSA values, so a
  coroutine split spills them alike (L20 I10).
- **D32, D66.** Slots and frame blocks are entry-block allocas inside
  the computed bound (K11, §3.1); no dynamically sized alloca exists.
- **D19, D25.** Regions per case; join regions use lifetime values from
  above and state one lifetime for their parameters (§3.6, §4.3); no
  jump leaves a lifetime.
- **D48 as amended.** Index variables alone in the binder; lifetimes are
  operands (K13, §2.3).
- **C1.** The borrow marking's answer, "owned or a view in a lifetime
  parameter", is the signature property of §5.1.
- **C2 R3.** A put changes the calling convention only where the value is
  a handle; the parameter is in the function's signature either way.
- **D23.** `cell.arena` declares `Allocate` on `idr.heap`; the region's
  end declares `Free` (§3.1); neither orders anything.
- **D10.** Views, one-call lifetimes and `idr.frame` cost nothing at run
  time; a handle exists only where a put needs the arena's address, a
  fact not known until run time.
- **0007.** A lifetime that moves whole is sent as a value of a package
  type (an arena closed with its root, linear by type), made by a region
  op that ends the sender's lifetime and opened on the receiver by a
  region that binds a fresh lifetime value (*proposed*, for when 0007 is
  taken; names the owner's). A lend is an `idr.lifetime` (D62): a fork
  holding a view in it produces its join inside the region, so the join
  cannot outlive the loan by value scoping, and the region's end joins
  any fork the program dropped (L20 I8). `idr.fork` is isolated from
  above, so a lifetime it uses is one of its operands, a message
  (`proposals/0007-shards.md:401-413`).

## 10. Today's stack cells and the frame lifetime

Today a stack cell is a counted cell in a native slot with bit 31 set,
its fields released at count 0 and its memory kept (read,
`runtime/idris_rt.h:47-68`, `foreign/idr/lib/Conversion/Cells.cpp:76-101`);
`isExclusive` tests that bit on every uniqueness test (read,
`runtime/Rc/Rc.h:47-53`); `idr-rc-stack` decides by a whole-program
marking with byte budgets of 256 and 64 (read,
`foreign/idr/lib/Transforms/Stack/Stack.cpp:78-80`). Measured:
`grep -rh "idr.cell.stack" tests foreign | wc -l` gives 21 lines in 12
files; `grep -rn "IDRIS_RT_STACK_CELL\|isStack(" runtime | wc -l` gives 7
readers of the bit.

Under D63, with L05 Q1 answered "delete" (independent of D63, still the
owner's, §13): a slot is `cell.stack in %f` or `in %l`, uncounted (count
0 written once with the info), `plain lexical`; its owned fields are
dropped on every path at its lifetime's end; a cell without a proof goes
to the counted heap. The stack bit, its seven readers and `idr.share`'s
raise of a counted value into a frame position go. The `frame` constant
goes with D63 (§2.2); `idr.frame`'s value does its work, including the
rule that a frame value never crosses a member call on a cycle (it is
not visible in the resume, §3.5). Under Q1 "keep", a counted cell in a
lifetime's memory would need the bit's test wherever a value may be
either, now including arenas.

## 11. Run-time cost and what is unwritable

**Cost.** None for a view, a one-call lifetime, `idr.frame`, a lifetime
parameter with an empty put set, or the stated-lifetime operands (all
erased). A handle where a put needs one, lowered as `static-handles.md`
decides (no register at all for its classes 1 to 3 in the opener).
Compile time: lifetime operands and parameters in the IR, the put
marking, O(1) checks per op. To measure (M1 to M5).

**Unwritable**, each by the representation, not by a check after the
fact:
- a lexical value or a lifetime value used outside its lifetime's region
  (MLIR's value scoping);
- a lexical value whose lifetime nobody states (V2, generated);
- allocation into a lifetime without its value (`cell.arena` takes it);
- a view kept by counted memory (V4, by the grade);
- a lifetime returned, yielded, stored or passed through a join (V1);
- a value of a local lifetime at a tail call, a return or a back edge
  (not visible there);
- a lexical value where D24 promises an exclusive counted one (the
  grade);
- a lifetime substituted wrongly when inlined (no lifetime is
  substituted).

## 12. Why this form (record)

The owner weighed three representations against MLIR's costs and ruled
D63. In short:

| representation | MLIR gives | ours to build | D48's one binder |
| --- | --- | --- | --- |
| a type parameter with binders (D39, D40, D48 as written) | uniquing; `AttrTypeReplacer` (read, `mlir/include/mlir/IR/AttrTypeSubElements.h:235`) under the substitution; region scoping for the binder's results | the lifetime telescope on functions and regions, levels, lifetime substitution, inlining by clone under substitution for every lifetime-polymorphic callee (upstream's `inlineRegion` demands equal types), a scope check in the function verifier (a type's verifier sees no context) | kept |
| MLIR regions alone | value scoping, dominance, the inliner unmodified | at every yield, store and return, a walk to learn whether a value reaches the region's memory, the owned walk D39 deletes; no way to say across a call that a result lives as long as an argument; no callee allocating into a caller's region | indices still need binders |
| an SSA value (D63) | value scoping and dominance as the scope and outlives check; the inliner's value mapping; CSE, dead code and the canonicalizer as for any value | stated-lifetime operands on producers and merges, the signature property with bounds, the call's statement of it, one-hop verifier rules | lifetimes leave it; indices keep it |

A type cannot name an SSA value: MLIR types are uniqued with no context
(L04 V4), which is why the SSA form moves the identity to an operand
and keeps only the kind in the type (§2.2).

The run-time question that started this (D39's "a handle at run time"
against D48's compile-time binder; lanes L02 F13, L05 I2, L06 OQ1, L20
I5) is met by one value: (A) an erased lifetime plus a separate handle
for puts becomes the value, erased or a handle at the lowering; (B)
every lifetime parameter a run-time value is avoided by that erasure,
which LLVM would not do for us (§7); (C) lifetimes with no handle at all
would have lost D39's callee building in its caller's lifetime. An
implicit current arena (OxCaml's local stack) was also considered: it
allocates only into the innermost open lifetime and breaks when tasks
interleave on one shard (L20 I10's counterexample, transposed);
`prior-art.md` §3.3 and §7 reject it on the same grounds. The linear,
threaded handle the lanes named survives as a lowering
(`static-handles.md` class 5's cursor), not as the IR value: threaded in
the IR it would return the handle from every put call, the world's
threading D20 removed.

## 13. Open

**For the owner**, each in its turn (D11):
1. L05 Q1: does a counted cell in a lifetime's memory survive? This file
   recommends "delete" (§10), as L05 does; it is independent of D63.
2. Names (D40's discipline): `lexical` for the grade's kind, `idr.frame`
   for the activation's lifetime, `idr.cell.static`, and 0007's package
   when 0007 is taken.

**For the coordinator**, following from D63, AGENTS.md or the evidence,
each to be recorded with its reason:
- `frame` leaves the grade for `idr.frame`'s value (§2.2, D63's text).
- `idr.lifetime` is not an `AutomaticAllocationScope` (§3.1, K11).
- One stated lifetime per merge; join regions take no lifetime parameter
  (§3.6, §4.3).
- Bounds between lifetime parameters in the signature (§5.1).
- `borrow lexical` subsumes into `plain lexical` at a call, so one body
  of `eval` serves a counted tree and an arena tree; otherwise the hold is
  a specialization key (*proposed*; a gap found writing §5.4).
- Frame kinds hold lifetime fields (§3.5; C96, L10, L04 F2 to F5).
- Restate C79 (index variables only), C83 (the borrow binds a lifetime
  value), C21 (lifetime kind `static | lexical`, counted implied), C86
  (`idr.cell.static`), C97 (§6, V8).
- C84's cycle clause against `static-handles.md`'s per-level lifetimes:
  a reversal needs the owner's dated ruling on evidence (AGENTS.md).
- The dead-argument bug in the pinned LLVM (§7), for an
  `upstream/<bug>/` patch with its report, reproducer and test.

**Measurements to take** (none taken here; each needs a build):
- M1: lifetime parameters per function and handles after the lowering,
  on the suite and stage 1.
- M2: today's `numStackCells` against cells placed in lifetimes.
- M3: the function verifier's time with the depth stack and one-hop
  rules, against today's, on the stage-1 module.
- M4: a parser building a tree in a request's lifetime, arena against
  counted, on arm64 and x86_64.
- M5: merges whose results or parameters were weakened to one stated
  lifetime (§4.3), and calls left uncontified by §3.6.
