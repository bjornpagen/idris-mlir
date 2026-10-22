<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# L04: data types as the inductive families Idris checked

*Lane L04 of the P0 verification swarm. HEAD `e96bb991` at the start
(2026-10-21T21:30Z) and at the finish (re-checked when the file was
complete). Design and review only: no code, build, test or git write.
Rulings in scope: D48 above all; D10, D12, D18, D24 (the `in_place`
kind), D43 (array fields in bodies). Claims are marked* read *(path:line
at HEAD),* measured *(the command given),* recalled, conjecture *or*
decision *(a ruling Dn or Cn). "P0" is `proposals/0000-mlir-native.md`;
D48 is its lines 787-836. Paths under `foreign/idr/` are written from
there; Idris paths from `compiler/src/IdrisMLIR/`; the fork from
`compiler/idris/src/`.*

Read in full before writing: the representation-first skill, AGENTS.md,
P0 whole, audits 01 whole, 14, 15, 17, synthesis A §5.7 and §5.8,
wave 1 §5.2 and §5.8, proposals 0012, 0018, 0019; the code below; the
siblings L05 and L16 where they had written (their seams are quoted in
§2.20, not decided for them).

## 1. Verification

### 1.1 D48, claim by claim

**V1. "A family is an attribute holding the declaration: its erased
indices; per constructor the index variables it binds, the index
equation it satisfies, and its fields, each with its quantity ...;
recursion as `self[...]` ...; a mutually recursive group as
`#idr.families<...>` with back-references by position."**
*Holds, with four corrections.*
- *Read*: today a data type is a `MutableType` named by a string whose
  body is sealed once (`IdrTypes.td:48-165`, `Types.cpp:45-97,
  199-225`), printed by name with the body once in `#idr.types`
  (`DataBody.cpp:114-135, 216-262`). No body holds an index, a binder or
  an equation (`IdrDialect.h` `Ctor` is `{name, fields, role}`); the
  frontend erases every index before it registers an instance
  (`Frontend/Translate/Types.idr:960-965, 711-712`).
- *Correction (structural incompleteness)*: a field type that refers
  back to the family must be a **type**, not syntax: a recursive field
  nests inside other types (`!idr.lin<self>` is LList's tail, a closure
  `!idr.fn<(self) -> i64>`, an array of the type). So `self` is a
  dialect type legal only inside a declaration (§2.3), and the check
  that no value has it is a scope check of the function verifier (§2.5).
- *Correction (integration mismatch with the frontend)*: a group is not
  an Idris `mutual` block. It is a strongly connected component of the
  *instances* the frontend registers: `data Rose a = MkRose a (List
  (Rose a))` makes `Rose Int` and `List (Rose Int)` one group though
  Idris declares no mutual block. The frontend already detects this
  recursion (`reentered`, `Translate/Types.idr:977-980`). The group's
  member order must be a function of the program (§2.3, I5).
- *Correction (one fact, one place)*: "each with its quantity (one or
  many)" is the field type's grade: `!idr.lin<T>` for one, the bare `T`
  for many, as every binder's quantity already is (`Emit/Index.idr:59`).
  A separate quantity beside the type would hold the fact twice. L16
  asks the same question and recommends the same answer
  (`L16-frontend.md:500`).
- *Correction (labels)*: the family's name and its constructors' names
  are part of the storage key (§2.3, I4). MLIR stores one instance per
  key; a label kept outside the key would print the first creator's
  name for every later equal declaration. "Labels are for readers and
  nothing looks them up" stays true: nothing looks them up; but two
  declarations that differ only in labels are two types.

**V2. "A data type is a family applied to index terms ... Identity is
content, shared by MLIR's uniquing ... no table and no name without a
body."** *Holds, with one correction.*
- *Read*: the name-alone state exists today: the parser and the
  bytecode reader make `!idr.data<"T">` with no body (`DataBody.cpp:
  125-135`), and the program verifier walks every op's attribute
  dictionary, result types and block-argument types after every pass
  to refuse one (`lib/IR/Func/Func.cpp:56-90`; 01 T59). Under D48 a
  type holds its declaration by pointer, so the state cannot be written
  and the walk goes.
- *Read (upstream)*: an attribute whose storage holds field types that
  name back-references by position is acyclic, so MLIR's
  `StorageUniquer` uniques it by content and the bytecode writer encodes
  it (the mutable-type text fallback, `BytecodeWriter.cpp:893-900` per
  §5.2 D2, no longer applies).
- *Correction (structural incompleteness)*: with no table, nothing
  lists a module's data types. Two readers need the list: the knot
  refusal (`Verify/Knots.cpp:1-22`, a question over the types arrays can
  reach) and the byte offsets of `Layouts`. Both get it from one walk of
  value types, once per analysis lifetime, cached in the analysis
  manager (§2.6). This is not the deleted walk: it runs when a pass asks
  for the analysis, never in a verifier.

**V3. "Every type comes from a declaration ..., so equal declarations
are equal types and no canonicalizing step exists."**
*Holds, with a correction.* A group's identity includes its member
order. Within one module each instance is registered once
(`TS.instances`, `Translate/Types.idr:971-975`), so no group is built
twice in two orders by the frontend. A pass that creates a cycle among
existing families (defunctionalization: `data T = MkT (Int -> T)` gets a
closure sum that captures a `T`) must form a new group; the step that
forms it is deterministic (I5), and it replaces DataRemap's content
names, not with a canonicalizer but with an order defined by the
declarations' old positions.

**V4. "Erased parameters share one binder: index variables and lifetime
variables ... quantity-0 parameters of a function or a region ...,
passed at calls at compile time only ..., checked by substitution."**
*Holds, with three corrections.*
- *Correction*: a variable's identity is its position, a de Bruijn
  **level** in the scope's telescope, not its name (I1). Levels, not
  indices, because MLIR values flow inward by dominance: a value defined
  before a match is used inside its cases with the same type object,
  which a de Bruijn index would have to renumber, and a value has one
  type. L05 reached the same conclusion for lifetimes
  (`L05-lifetimes.md:189-196, 321-323`).
- *Correction (integration mismatch with upstream)*: upstream's inliner
  assumes types are context-free. `inlineRegion` fails when a call
  operand's type differs from the callee's block-argument type
  (`InliningUtils.cpp:395-396`), and `inlineCall` asks the dialect for a
  cast (`:532-537`); a callee whose argument is `#Vect[v0]` (its own
  binder) called with `#Vect[3]` meets both. The correction is I14: an
  index-polymorphic callee is inlined through the one substitution
  utility, which clones the body under the call's substitution before
  upstream's `inlineCall` sees it. No patch of upstream is needed.
- *Correction*: "checked by substitution" is exact only with strict
  type equality after substitution; the case refinement that index
  matching needs is not a substitution of the call (V5).

**V5. "A match refines the index, and a case whose equation is false
does not exist (the verifier knows `head`'s `@Nil` is impossible at
`n + 1`)."** *Holds, with two corrections.*
- *Read (the language's rule)*: Idris decides an impossible constructor
  by matching the constructor's result type against the scrutinee's,
  collecting variable bindings, and finding a clash: distinct
  constructor tags, distinct type constructors, distinct primitive
  constants, or a variable occurring under constructors in the term it
  is bound to (`Core/Coverage.idr:22-135`, `conflict`); a type with no
  possible constructor is empty (`:137-151`, `isEmpty`). Our unifier
  restates that rule over the index language (§2.5); it is sound w.r.t.
  Idris and never finds a clash Idris's elaborator would not.
- *Correction (integration mismatch with MLIR)*: in `map<n>`'s `Cons`
  case the yielded `Cons<m>(y, ys)` has type `#Vect[m + 1]` and the
  match's result `#Vect[n]`; they are equal only under the case's
  refinement `n := m + 1`. MLIR's region-branch type check compares
  types with no region context (`areTypesCompatible`,
  `ControlFlowInterfaces.td:100`), and upstream folds that replace a
  match's results by yielded values need equal types. So refinement
  needs an explicit, verified cast (`idr.reindex`, I3). §5.8 B1 states
  the same rule for grades: every regrade is an op.
- *Correction*: "does not exist" is enforced for case regions (refused)
  but not for the empty default. Today an empty default means "no
  remaining constructor occurs", Idris's coverage proof
  (`Frontend/Translate/Cases.idr:93-97, 117, 210`); our unifier cannot
  always re-prove it (opaque terms), so the empty default keeps that
  meaning and exhaustiveness by index is a fact passes use, not a
  verifier requirement (§2.5, I9).

**V6. "A known index fixes the shape (`#Vect[3]` is three words inline,
no tag, no cell, no count)."** *Holds, with a correction the owner must
see (Q1).*
- *Derivation*: today's rule "a type on a containment cycle is held in
  a cell" (`Layout.h:224-233`, `Fit.cpp`) applied to family
  *applications* gives the claim: `#Vect[3]` holds `#Vect[2]` holds ...
  `#Vect[0]`, distinct applications with no cycle, each with one
  possible constructor, so three `i64` in place; `#Vect[n]` holds
  `#Vect[m]` with `m` unknown, which is the same node, so a cycle and a
  cell.
- *Correction (structural incompleteness)*: the rule needs (a) every
  application whose index holds a variable or an opaque term to be one
  node per family member (the "unknown" class), else `#Vect[n]` unfolds
  forever; and (b) a budget on how far closed applications unfold, else
  `data T : Nat -> Type where Mk : T (S n) -> T n` at `T 0` never ends
  and `#Vect[1000000]` is a million words inline (§2.6).
- *Correction (integration mismatch)*: functions are index-polymorphic
  (one `@sum<n>` for every `n`, D48's own example), so a call
  `@sum<3>(%v : #Vect[3])` passes an inline value to a body compiled
  for cells. D10 forbids paying for the fact at run time where it was
  known statically, so every call whose callee's signature changes
  layout class under the call's substitution must reach a callee
  specialized at that class (§2.7). Where an index becomes known only
  inside a function (a case refining `n := 3` while a `#Vect[n]` is
  live), the representation changes at that `idr.reindex`, a conversion
  whose size the budget bounds. That is a fact arriving late, not a
  known fact re-derived; but D48's sentence "none of it paid at run
  time" needs this qualification, which is the owner's (Q1).

**V7. "`Fin n` is one word below `n` (0018)."** *Holds, with a
correction.* A `Fin n` value can exceed 2^64: `lowBits 100 v : Fin
(power 2 100)` is one (0018 §7, *read* there). So one word holds only
where `n`'s class is closed and its bound fits a byte class; at an
unknown `n` the value is a natural (a big word), as today. Under D48 the
bound is in the type (`#Fin[n]`), so 0018's F1 and F2 become one
mechanism, the layout class (§2.12); 0018's D1 ("the frontend decides
... no dialect type") is superseded, since the frontend no longer knows
`n` inside an index-polymorphic function.

**V8. "A typed expression's impossible arms vanish under
specialization."** *Holds*, provided substitution has one
implementation that prunes every case the substitution makes impossible
in the same rewrite (§2.7). A clone that substitutes without pruning
leaves a refused case region: the verifier then catches it.

**V9. "Inline or in a cell is layout, a function of the type and its
lifetime computed once: a recursive field at an unknown index is a
cell, a value of a known index has a fixed size. `!idr.box` is no longer
a type."** *Holds, with three precisions.* A memo family is always a
cell (a force writes the shared cell: `Defunctionalize/Declare.cpp:
33-42`, "its value is always a box"); a numeral-shaped family is a
number, not a sum (§2.12); the lifetime chooses where a cell lives
(L05), never whether a value is a cell. The type-intrinsic part
(possible constructors, class, layout kind, what a value holds) is
computed when the type is made, in its storage, with no MLIR storage
created during the computation (I11); byte offsets stay a function of
the target in `Layouts`.

**V10. "The index language: constants, variables, successor and
constructor applications, `Nat` as a number; anything richer is an
opaque term, sound and refining nothing, until static normalization
(0010) grows it."** *Holds; made exact in §2.1.* Two precisions: an
opaque term carries nothing (I2's discussion: it cannot then be mistaken
for knowledge, and all opaque-indexed applications of a family are one
type, which is sound because no decision reads opaque equality); and a
runtime value in an index position (`replicate : (n : Nat) -> a -> Vect
n a`, `MkT : (n : Nat) -> T n`) is opaque under this language, which is
the owner's to extend (Q2).

**V11. "The specification is written the same way: index terms
well-scoped by `Fin s`, one equation per family index by `Vect s`, a
field's quantity a type with no erased case."** *Holds* (§2.3's Idris
types). The spec's `Quantity` has no erased case, generated to both
sides; in the IR it is the field's grade (V1).

**V12. "Deleted: the `#idr.types` table (`Idr_DataTableAttr`,
`DataBody.cpp`), `MutableType` and sealing, the content-named remakes
(`DataRemap`, `Symbols.h:139-236`), the name-alone state and the program
verifier's walk for it (01 T59), `!idr.box` as a type. The 147 readers
of a body read it from the type."** *Holds, with two corrections.*
- *Measured*: `grep -rnoE '\.(getCtors|getCtor|isMemo|isClosures|isAtom|getTags|getRunningTag|getForcedTag|getConsTag|getNilTag|getListElement)\('`
  over `lib tools unittests include`, excluding `Types.cpp`,
  `DataBody.cpp` and generated `.inc`: 149 matches in 58 files at HEAD
  (146 without `include/`; 01 counted 147 in 57). §2.17 adapts each.
- *Correction*: DataRemap's *names* go (identity is content), but the
  remake of families whose content a pass changes does not vanish:
  where the change creates a cycle among existing families
  (defunctionalization), new groups must be formed. That is one
  utility, `regroup` (I5), not a second copy of DataRemap; everywhere
  else upstream's `AttrTypeReplacer` remakes content by itself, through
  the attribute's `getReplaceImmediateSubElementsFn` (the mechanism
  `DataTableAttr` already uses, `IdrAttrs.td` extraClassDeclaration).
- *Read*: `Symbols.h:139-236` is `DataRemap` and its `Content` section;
  `Declarations` is `:88-137`, also deleted (§2.18).

### 1.2 The other rulings in scope

**D10 (no static fact paid at run time) as it bears here.** *Holds with
the costs named.* Run time: the possible-constructor set removes tag
tests where one constructor is possible; the class removes cells and
counts for closed shapes; the remaining run-time cost is the bounded
conversion at a class-changing `idr.reindex` (V6). Compile time: each
type's facts are computed once at its construction; a case's
refinement is recomputed by unification when the function verifier
checks it (O(size of the index terms) per case per verify), which is
the check of a stored fact (the block-argument types), MLIR's own
practice for inferred types (`verifyInferredResultTypes`); instantiating
a field type in a verifier looks a type up through the uniquer's
thread-local cache, as `TypesMatchWith` does today (01 §2.6).

**D12 (strict subset, never a contradiction).** *Holds.* The refusal of
a field whose representation depends on an erased *type* stays
(`walk`, `Translate/Types.idr:1060-1061`, rule `DependentField`); a
field over an erased *value* index is now carried instead of erased,
which accepts nothing upstream refuses and refuses nothing it accepted.
The frontend still monomorphizes type parameters (keys,
`Translate/Types.idr:956-965`), so index sorts never range over
representations.

**D18 (lossless representation).** *Holds with a stated loss.* D48
itself names the one loss (an index term outside the language becomes
opaque); the TT term is gone from the IR and static normalization
(0010) is where it returns. Layout loses nothing: the class rule reads
the type.

**D24 (the `in_place` kind).** *Holds, re-housed.* *Read*: the kind is
`SumKind::InPlace` (`IdrBase.td:121-127`), written by the frontend for
registry `InPlaceType` entries (`Registry/Recognized.idr:185-186`:
`Linear.List.LList`, `Linear.Nat.LNat`; `Emit/Index.idr:72`), read by
one pass (`Demand.cpp:56`, 01 T08), with the same body rules as `Plain`
(`DataBody.cpp:40-42`). Under D48 it is the family's promise (§2.13),
part of its identity. *Observation (optional simplification)*: `LNat`
is numeral-shaped, so its layout is a number and the promise holds
trivially (a number has no cell to rebuild).

**D43 (an array field is its buffer).** *Holds; the family verifier
carries it.* D43 says "the data-type verifier refuses a tensor in a
body"; under D48 that is a rule of the family declaration (§2.3, rule
F7). Whether an array's shape is an index term is L12's (§2.20).

### 1.3 Coordinator and synthesis items this area meets

| item | verdict | evidence | class |
| --- | --- | --- | --- |
| G DP-40 (frontend decides boxes; table refuses an in-place cycle) | **refuted by D48** for boxes | D48: "Inline or in a cell is layout ... `!idr.box` is no longer a type"; G's text, `synthesis/G-coordinator-decisions.md:222-232` | integration mismatch |
| G DP-37 (case binds `!idr.ctor<T, @C>`) | composes | the refined scrutinee's type is `!idr.ctor<!idr.data<#F[e]>, @C>`, `e` the constructor's equation at the case's binders (§2.5) | integration (unfixed until DP-37 is folded) |
| 01 C4 (body as one alternative per kind) | **holds, absorbed** | §2.3's family kinds are that sum | — |
| 01 C5 (recursive properties at construction) | **holds, absorbed** | §2.4's derived facts (I11) | — |
| 01 C9 (DataRemap keys from the printer) | **void** | DataRemap's keys go with D48 | — |
| 01 T26 (`replaceLabels` aborts on an in-place rename) | **void** | renaming a label makes a new family, by content (`Types.cpp:182-195` goes) | — |
| 01 T27 (DataRemap's key drops a lifetime) | **void** | the key goes | defect confirmed in source, deleted with its cause (C8) |
| 01 T58, NQ2 (who decides boxes) | **settled by D48** | layout | — |
| 15 NQ-1 (one-field collapse in the frontend) | **corrected** | a layout decision; moves to the layout (I8) | integration mismatch |
| 15 CS-4 (one crash default, not one arm per missing constructor) | **holds, required** | per-constructor arms would name constructors impossible by index (I9) | structural incompleteness |
| 0012 D1 (`!idr.packed<T>` wraps `T` as `!idr.box` does) | **holds with a reword** | packing is chosen per value, so it is a type; boxing was decided by the type, so it is not | integration (wording) |
| 0019 D2 (the layout decides niches from the body) | **holds, strengthened** | the possible set at the application removes a tag before any niche is sought | optional simplification |

## 2. Boundaries

The end state of this area, exact enough to implement. Every C++ type
named here is generated from the dialect's Idris specification (D16)
unless marked *hand C++* (one-source §9, L03's list).

### 2.1 The index term language

A term is one of six forms. Its **normal form** is the only form a type
holds; every constructor of a term normalizes.

```
term ::= nat N                  -- a natural, any size (N >= 0)
       | var k                  -- the level k of the scope (§2.2)
       | succ term N            -- term + N, N >= 1, term not itself succ or nat
       | lit c                  -- a constant: an integer, char, double or
                                --   string literal, or a type (`type i64`)
       | con F t (term*)        -- constructor t of family member F, applied
       | opaque                 -- an index outside the language
```

- *Normalization*: `succ (nat a) b` is `nat (a + b)`; `succ (succ t a)
  b` is `succ t (a + b)`; `con F t args` where `F` is numeral-shaped
  (§2.12) and `t` its zero is `nat 0`, its successor applied to `x` is
  `succ x 1` (so `Fin`'s and `Elem`'s indices are numbers too);
  Idris's `Z` and `S` read from its `ZERO`/`SUCC` flags (`Closed.natRole`)
  are `nat 0` and `succ _ 1`, never names.
- *Arguments of `con`*: the constructor's binders, then its fields, in
  declaration order, each a term of the sort that position has (§2.3).
- *`lit`*: two literals of one sort clash when unequal; a type literal
  is the MLIR type the frontend gives the Idris type (`TypeAttr`). Two
  Idris types with one MLIR type (`Int`, `Bits64` to `i64`) do not clash:
  a clash missed, never a clash invented (sound).
- *`opaque`*: carries nothing, equal to every other `opaque`. A decision
  that reads one learns nothing (§2.5).

**Sorts.** `sort ::= nat | lifetime | type | opaque | S | F` where `S`
is a scalar type (`i8` to `i64`, `i32` for `Char`, `f64`, `!idr.str`,
`!idr.big`) and `F` a family member (§2.3). A `nat` position takes
`nat`, `var`, `succ`, `opaque`; an `S` position `lit` of `S`, `var`,
`opaque`; an `F` position `con F ...`, `var`, `opaque`; a `type`
position `lit (type T)`, `var`, `opaque`; `lifetime` is L05's (§2.20); an
`opaque` position only `var` and `opaque`.

**C++ form** (*hand C++* for the storage, generated for the enum): a
term is a preorder array of nodes held inside the storage of whatever
holds it (a data type's indices, an equation), never an attribute per
subterm:

```cpp
enum class TermKind : uint8_t { Nat, Var, Succ, Lit, Con, Opaque };
struct TermNode {                 // 16 bytes
  TermKind kind;
  uint32_t member;                // Con: the member in its group
  uint32_t value;                 // Var: the level; Con: the tag; Succ: unused
  mlir::Attribute payload;        // Nat, Succ: #idr.big (the count); Lit: the constant;
                                  // Con: the FamiliesAttr; Var, Opaque: null
};
class IndexTerm;                  // a typed cursor over one term's nodes; one fold
```

The array is part of the storage key (hashed as an array of
(kind, member, value, payload pointer)); a `Con` node's arity is its
constructor's binders plus fields, so the preorder needs no length.
One fold over `TermKind` (D7: one fold over a closed sum).

### 2.2 The binder

One telescope of erased binders per scope, shared by index and lifetime
variables (D48, D39, D40):
- **Function**: `idr.func @f<v0 : nat, v1 : lifetime>(...)`, levels
  0..p-1, an inherent property listing each binder's sort.
- **Region binders**, each extending the telescope of its parent scope
  by its own binders at the next levels: a case region of `idr.match`
  (the constructor's binders, §2.5), a join point (`idr.join`, D19; its
  erased parameters, L09), `idr.lifetime` (one lifetime, L05). An
  `idr.assume` region binds nothing (§2.5).
- **A family declaration** is a scope of its own: each constructor's
  binders are levels 0..j-1 inside its equation and its field types.
- **Calls and jumps** pass erased arguments, terms in the caller's scope:
  `idr.call @f<nat 3, frame>(...)`, `idr.jump %k<var 2>(...)`. The call's
  operand and result types equal the callee's signature with
  `v_i := arg_i` substituted, exactly.
- **Scope rule** (function verifier, §2.5): every level in a value's type
  is below the depth of its scope, and the sort of the binder at that
  level is the sort of the position it occurs in.
- **One interface over binding ops** (L05 names it too,
  `L05-lifetimes.md:362-368`): `ErasedBinderOpInterface`, "the sorts this
  region binds", read by the scope check and the substitution utility.
  Implemented by `idr.func`, `idr.match` (per case), `idr.join`,
  `idr.lifetime`.
- **Printing**: a level prints `v<k>` in an index position (a bare
  keyword the dialect parser reads with `parseOptionalKeyword`). Types are
  printed with no context (MLIR's type printer sees none), so a type
  cannot print a binder's Idris name; names live in each binder's
  location (a `NameLoc`, as values' names do today,
  `Emit/Monad.idr:126-136`). How a lifetime position spells a level is
  L05's.

### 2.3 The family declaration: `#idr.families`

**Grammar** (the attribute's custom syntax; `family` is the printed form
of a group of one):

```
families    ::= '#idr.families' '<' '[' member (',' member)* ']' '>'
family      ::= '#idr.family' '<' member '>'           -- a group of one
member      ::= data-member | closures-member | memo-member
data-member ::= string-label promise? loc? '[' index-sorts? ']' '{' ctor* '}'
promise     ::= 'in_place'
loc         ::= 'loc' '(' location ')'
index-sorts ::= sort-binder (',' sort-binder)*
sort-binder ::= 'v' INT ':' sort                       -- names for readers: v0, v1, ...
ctor        ::= '@' label binders? equation? fields
binders     ::= '<' sort-binder (',' sort-binder)* '>'  -- the constructor's levels 0..j-1
equation    ::= 'where' term (',' term)*               -- one per family index, in order
fields      ::= '(' (type (',' type)*)? ')'            -- a field's grade is its quantity
closures-member ::= string-label 'closures' '[' index-sorts? ']' '{' label* '}'
memo-member     ::= string-label 'memo' '[' index-sorts? ']' '{' label* '}'
                    'forced' '(' type ')'
label       ::= '@' label binders? equation? 'fn' symbol-ref by-name? fields
by-name     ::= 'by_name'                              -- memo labels only
sort        ::= 'nat' | 'lifetime' | 'type' | 'opaque' | scalar-type | family-ref
family-ref  ::= attribute-value ('at' INT)?            -- a member of a group; 'at 0' omitted
self-type   ::= 'self' ('at' INT)? '[' terms? ']'      -- inside a declaration only
```

Terms print `3`, `v1`, `v1 + 2`, `@Cons(v0, v1)` (resolved against the
position's sort), `lit 7 : i64`, `lit type i64`, `_`.

D48's example, exact:

```mlir
#Vect = #idr.family<"Vect" loc("Data/Vect.idr":17:1) [v0 : nat] {
  @Nil  where 0
  @Cons <v0 : nat> where v0 + 1 (i64, self[v0])
}>
```

The constructor binder `v0` inside `@Cons` is level 0 of `@Cons`'s own
scope; the family's `[v0 : nat]` names the index for readers only (the
equation gives each index by position).

**Storage** (*hand C++*: the custom storage; the record schema generated):

```cpp
struct CtorDecl {                       // a constructor of a data member
  mlir::StringAttr label;
  llvm::ArrayRef<Sort> binders;         // levels 0..j-1 of this constructor
  llvm::ArrayRef<TermNode> equation;    // |indices| terms, preorder, concatenated
  llvm::ArrayRef<mlir::Type> fields;    // may hold !idr.self and levels < j
};
struct LabelDecl {                      // a label of a closure or memo member
  mlir::StringAttr label;
  mlir::FlatSymbolRefAttr fn;
  ByName byName;                        // enum {Always, Once}: Once for closures
  llvm::ArrayRef<Sort> binders;
  llvm::ArrayRef<TermNode> equation;
  llvm::ArrayRef<mlir::Type> fields;    // the captures
};
struct DataMember    { mlir::StringAttr label; mlir::LocationAttr loc; Promise promise;
                       llvm::ArrayRef<Sort> indices; llvm::ArrayRef<CtorDecl> ctors; };
struct ClosureMember { mlir::StringAttr label; llvm::ArrayRef<Sort> indices;
                       llvm::ArrayRef<LabelDecl> labels; };
struct MemoMember    { mlir::StringAttr label; llvm::ArrayRef<Sort> indices;
                       llvm::ArrayRef<LabelDecl> labels; mlir::Type forced; };
using Member = std::variant<DataMember, ClosureMember, MemoMember>;
struct FamiliesAttrStorage : mlir::AttributeStorage {
  using KeyTy = llvm::ArrayRef<Member>;   // every field above is key
  // Derived once in construct, never key: per member, the tags by label
  // (for `custom<CtorRef>`), and the group facts of §2.4 that need no
  // instantiation (recursive or not, numeral-shaped or not, Held at the
  // unknown class).
};
```

- A memo member's states are not declared constructors: `running` is
  tag `labels.size()`, `forced` is `labels.size() + 1`, with `forced`'s
  one field. Today's `KindRule`, `RoleOnce`, `ruleOf` and `roleTags`
  (`DataBody.cpp:29-53`, `Types.cpp:94`) have nothing left to check:
  a memo member has its states by construction.
- `Promise` is `{None, InPlace}`: a fact of the type that counting reads
  (D24), not a change of structure, so a data member carries it rather
  than a fourth alternative with an identical payload.
- Base's list is not a kind: the string ops read a **shape view**
  (`listShape()`: two constructors, one with no field, one with exactly
  an element and `self`), computed with the group facts (I6).
- A self reference is the type `!idr.self<member, indices>`, a dialect
  type whose storage is `(uint32 member, ArrayRef<TermNode>)`.

**Verifier** (`genVerifyDecl`, once per uniqued group, context-free):
- F1. At least one member; labels non-empty; within a member, labels
  unique; members' labels unique within the group.
- F2. A data member's index sorts are `nat`, `type`, `opaque`, a
  scalar, or a family-ref (no `lifetime`: a lifetime is never an index
  of a data type); closure and memo members' indices likewise.
- F3. Each constructor's (label's) equation has exactly one term per
  index, each well-scoped (levels < its binder count) and well-sorted
  (§2.1).
- F4. Each binder's sort is legal (F2's set) and each binder occurs in
  the equation or in a field type: a binder that occurs nowhere is an
  erased proof and does not exist (the frontend drops it, §2.10).
- F5. Each field type is a field type (`isFieldType`, `Grades.cpp:
  300-309`, made a value-facts method by 01 C6), its only grade
  `!idr.lin` (quantity one) or none (many): no permission or lifetime in
  a declaration; levels in it < the binder count.
- F6. Each `!idr.self<i, ts>` in a field has `i <` member count and
  `ts` fitting member `i`'s index sorts.
- F7. No field is a ranked tensor (D43: an array field is its buffer).
- F8. A memo member's `forced` type is a field type; by-name only on
  memo labels.

Context-dependent rules (a level's binder sort; no `!idr.self` in a
value type) are the function verifier's scope rule (§2.5).

**Bytecode** (`IdrBytecode.td`, generated): the group is one dialect
attribute record, `Families = (Array<Member>)`, each member a composite
whose first field is its alternative's code (BytecodeBase has no sum
composite, 01 T10; the reader builds the alternative once, by its code,
and no flag product is carried), its arrays of `CtorDecl`/`LabelDecl`
composites, field types as `Type` references, terms as
`Array<TermNode>` with `TermNode = (VarInt kind, VarInt member, VarInt
value, Idr_OptionalAttr payload)`. Nested groups and types are
references into the bytecode's attribute and type tables, which the
reader materializes lazily in dependency order; the structure is
acyclic, so no table must be read first (01 R2 dissolves).

**Printing with aliases**: `getAlias(Attribute)` gives a group the label
of its first member, shortened as today (`Asm.cpp:96-106`'s
`shortName`), `FinalAlias`; MLIR suffixes collisions. A data type prints
`!idr.data<#Vect[v0]>`, `!idr.data<#Tree_Forest at 1 [v0]>`. No alias for
a data type itself (its indices change per use). The table alias
`data_types` (`Asm.cpp:113-116`) goes.

### 2.4 The data type `!idr.data`

```
data-type ::= '!idr.data' '<' family-ref '[' (term (',' term)*)? ']' '>'
```

**Storage**: `(FamiliesAttr group, uint32 member, ArrayRef<TermNode>
indices)` is the key. Derived once in `construct`, from the key and the
already-uniqued storage it points to, creating no MLIR storage (the
computation runs on `TermNode` arrays in plain C++; *conjecture* that
this keeps construction free of nested uniquer calls under the shard
lock, to confirm against `StorageUniquer.cpp` when built):

| derived fact | what it is | how |
| --- | --- | --- |
| `possible` | the declared tags possible at these indices | unify the indices with each constructor's equation (§2.5); a clash removes the tag |
| `cls` | `Closed` (every index term closed, the unfolding within the budget) or `Unknown` | §2.6 |
| `layout` | `Number{width}`, `Number{natural}`, `InPlace`, or `Cell` | §2.6 |
| `held` | today's `Held` bits: references, labels, no component | at `Unknown`, the group's; at `Closed`, from the unfolding |
| `freeLevels` | the largest level in the indices, plus one | a scan |

- `possible` empty means the application is **uninhabited** (Idris's
  `isEmpty`, `Coverage.idr:137-151`), I12.
- Verifier (`genVerifyDecl`): `member < group size`; the indices fit the
  member's sorts. No context, so no level-sort check here (§2.5).
- `ValueFactsTypeInterface` answers from `held` and `layout`;
  `isCellPointer` is `layout == Cell`.

**Accessors that replace today's body reads** (the readers of §2.17):

```cpp
class DataType {
  Member decl() const;                              // the declaration (labels, kinds)
  llvm::ArrayRef<Tag> possibleTags() const;         // replaces getTags() where a reader branches
  uint32_t declaredCount() const;                   // the tag space (LLVM ranges, tag width)
  std::optional<MemoView> memo() const;             // replaces isMemo(), get{Running,Forced}Tag()
  std::optional<ClosuresView> closures() const;     // replaces isClosures(), role::Label reads
  std::optional<ListShape> listShape() const;       // replaces getNilTag/getConsTag/getListElement
  // The fields of constructor `tag` at this application when matching its
  // equation against the indices determines every binder its fields
  // mention; none otherwise (the reader then needs a case's binders).
  std::optional<llvm::SmallVector<mlir::Type>> determinedFields(Tag tag) const;
  // The fields with the binders given (a case's levels, a con's matching).
  llvm::SmallVector<mlir::Type> fieldsAt(Tag tag, llvm::ArrayRef<IndexTerm> binders) const;
  LayoutKind layout() const; Class cls() const; Held held() const;
};
```

`determinedFields` and `fieldsAt` create types (instantiation); they are
called by builders and verifiers, never on a worker's hot path: passes
read field types from the IR (block arguments, `idr.field` results,
`idr.con` operands), which hold them already.

### 2.5 The ops this area types

**`idr.con`**: `idr.con @C(%f...) : !idr.data<#F[ts]>`. No erased
arguments are written: the verifier finds the binders by one-way
matching (binders are the only unknowns) of `ts` against `C`'s equation
and of the operand types against `C`'s fields; a binder that neither
determines is one no field and no index reads, so its value is
irrelevant. Refused: `C` not in `possible` at `ts`; no matching.

**`idr.match`** (D19's region per case; today `IdrMatchOps.td:101-130`):

```mlir
%r = idr.match %xs : !idr.data<#Vect[v0]> -> !idr.data<#Vect[v0]> {
  case @Nil() { ... idr.yield %n0 : !idr.data<#Vect[v0]> }
  case @Cons<v1 : nat>(%x : i64, %tl : !idr.data<#Vect[v1]>) {
    ...
    %c = idr.con @Cons(%y, %ys) : !idr.data<#Vect[v1 + 1]>
    %c2 = idr.reindex %c : !idr.data<#Vect[v1 + 1]> to !idr.data<#Vect[v0]>
    idr.yield %c2 : !idr.data<#Vect[v0]>
  }
}
```

At a match of depth `d` (the scope's binder count) on `#F[ts]`, for case
`C` with binders `b_0..b_{j-1}`:
- R1. **Binders.** The case region binds exactly `C`'s binders at levels
  `d..d+j-1`, with `C`'s sorts (printed `<v1 : nat>`).
- R2. **Fields.** The region's block arguments are `C`'s fields with
  `b_i := var (d+i)`, unrefined (the frontend writes them by
  instantiation alone, with no unification on the Idris side), each at
  the scrutinee's quantity times the field's (`fieldType`,
  `Grades.cpp:253-260`).
- R3. **Refinement.** `σ_C = unify(ts, eq_C[b := var(d..)])` over the
  unknowns `{all levels < d+j}`: first-order unification with these
  rules, the restatement of Idris's `conflict` (`Coverage.idr:22-135`):
  `nat a ≐ nat b` clashes when `a ≠ b`; `nat a ≐ succ t k` clashes when
  `a < k`, else gives `t ≐ nat (a-k)`; `succ t a ≐ succ u b` gives
  `t ≐ succ u (b-a)` (a ≤ b); `con F t xs ≐ con F u ys` clashes when
  `t ≠ u`, else unifies the arguments; `lit c ≐ lit c'` clashes when
  `c ≠ c'`; `var k ≐ t` binds `k := t` unless `k` occurs in `t` under
  `con`/`succ`, which clashes (Idris's `findN`); anything against
  `opaque` gives nothing (no binding, no clash). The result is `Clash`
  or a most general substitution.
- R4. **Impossible cases.** `σ_C = Clash` refuses the case region (the
  verifier's error names the constructor and the index). No pass may
  leave one: substitution prunes in the same rewrite (§2.7).
- R5. **Default.** An empty default means no uncovered constructor
  occurs: Idris's coverage, or our `possible` set, or both. A non-empty
  default binds the scrutinee back at its type, as today. A non-empty
  default whose uncovered constructors are all outside `possible` is
  dead, and the match's canonicalizer erases it. The verifier demands
  no index-exhaustiveness beyond this (V5).
- R6. **One possible constructor** (`possible` a singleton, e.g.
  `#Vect[v0 + 1]` in `head`): the match has one case and no default;
  `idr.tag` of such a value folds to that tag; the lowering emits no
  tag test.
- R7. If DP-37 is taken, case `C` also binds the refined scrutinee at
  `!idr.ctor<!idr.data<#F[eq_C[b := var(d..)]]>, @C>`.

**`idr.reindex`** (new; pure, `NoMemoryEffect`, `Speculatable` only
when its two layouts are equal): `%y = idr.reindex %x : A to B`, `A` and
`B` any two types (grades, closures, tensors of them included) equal
after applying the scope's composite refinement `σ*` (every enclosing
case's `σ_C` and every enclosing `idr.assume`'s, outermost first). It
folds to its operand when `A == B`; a chain folds to one; it lowers to
nothing when `layout(A) == layout(B)` and to a conversion otherwise
(§2.6). Its verification reads `σ*`, which the function verifier's one
walk keeps on a stack as it enters and leaves binding regions, so no op
walks to its ancestors (01 C7(b)'s fused walk).

**`idr.assume`** (new): a region op entered once, `idr.assume <lhs =
rhs> { ... }`, with an equation of two index terms over the scope; its
region's `σ` is `unify(lhs, rhs)`; on `Clash` the region is unreachable
(Idris proved an impossible equality, so the code is dead) and the
canonicalizer replaces it by `ub.unreachable`. The frontend writes it
where checked TT uses an erased equality proof: `replace`,
`rewrite ... in`, a match on an erased `Refl` (§2.10). It is the one
place a fact enters the IR on Idris's word alone, which is parsing at
the boundary: inside it, every `idr.reindex` is checked like any other.

**`idr.field`**: reads field `i` of constructor `C` from a value whose
type determines `C` (DP-37's `!idr.ctor`, or `possible == {C}`) and
whose `determinedFields(C)` exists; its result type is that field.
Speculatable exactly when the type determines `C` (I10); today's rule
reads the box (`OpsConReads.cpp:24-28`).

**Scope rule** (the function verifier's walk, 01 C7(b)): each value
type's `freeLevels` ≤ the depth of its scope (O(1) per type for
`!idr.data`; for builtin types holding ours, a per-verify cache of
distinct types); each level's binder sort matches its position; no
`!idr.self` in a value type (the same cache).

### 2.6 Layout: a function of the type and its lifetime

**Classes.** An application's class is `Closed(ts)` when every index
term is closed (no `var`, no `opaque`) and its unfolding (below) stays
within the **shape budget** `B` (in runtime components); `Unknown`
otherwise. All `Unknown` applications of one member are one node.

**The rule**, per application `T = #F[ts]` at lifetime `ℓ`:
1. A memo member: `Cell`.
2. A numeral-shaped member (§2.12): `Number{w}` at `Closed`, `w` the
   smallest of `i8 i16 i32 i64` holding the bound; `Number{natural}` at
   `Unknown` or a bound past `2^64 - 1`.
3. At `Unknown`: `Cell` when the member is recursive (its group has a
   self reference: computed once per group), else `InPlace` over all
   declared constructors.
4. At `Closed(ts)`: unfold: each constructor in `possible`, its fields
   instantiated (their binders solved by `σ_C`; a binder left unsolved
   makes that field's application `Unknown`); a field application met
   again on the unfolding, or an unfolding past `B` components, makes
   `T` take the `Unknown` layout of its member. Otherwise `InPlace`
   over the `possible` constructors: no tag when one, a tag when more,
   no component when none (uninhabited).
5. `ℓ` chooses where a `Cell` lives (L05: counted heap, frame, a
   lexical lifetime's arena, static data). It never changes 1 to 4.

**The budget `B`** makes the class set finite, so the unfolding and
index specialization (§2.7) end by construction (AGENTS.md: a pass that
only makes code faster terminates by construction and may stop at a
budget, which never refuses). Its value is *debt*: measured (M3, M4)
before it is fixed, and written once in the specification.

**`Layouts`** (the analysis): byte offsets and sizes only, from the
module's data layout, keyed by type (a memo of a pure function of a
uniqued type, not per-node state). Built once per module from one
parallel walk of value types, cached and preserved by every pass that
creates no new application. Deletes the type-graph-driven build
(`Layouts.cpp:41-104`), `graph.boxed` (`:80`), the `DataLayout` per miss
(01 T53).

**Conversions.** A `idr.reindex` between two layouts (`Closed`
`InPlace` and `Unknown` `Cell`, or two `Number` widths) lowers to a
re-pack: read the source's components, write the target's. Its size is
bounded by `B`. No other op changes a value's layout.

**What it deletes**: `!idr.box` (`IdrTypes.td:167-181`), `layout::fit`
(`Fit.cpp`, `Layout.h:224-233`), its DataRemap of kind `box`, the
`BoxLayout`-by-`DataType` map (it is keyed by the `Cell`-layout type).

### 2.7 Substitution and specialization by class

**One substitution utility**, `substitute(region or function, Subst)`,
used by the specializer, the inliner (I14) and the canonicalizer of a
known case:
- maps every type under the region through one `AttrTypeReplacer` that
  replaces levels by terms and shifts the region's own binders to the
  new depth;
- normalizes every term (§2.1);
- recomputes each match's `σ_C` and **erases every case region whose
  constructor is now impossible**, and every default that is now dead;
- folds `idr.reindex` whose two types became equal.

**Index specialization** (L18's specializer; the rule is this area's):
a call `@f<ts>` whose callee's signature has a different layout under
`v := ts` than under `v` (some parameter or result changes class)
targets `f` cloned at the classes of `ts` (each closed term within the
budget is its own class, any other is `Unknown`). Classes are finite, so
the clones are (per function, at most the number of closed classes the
budget admits per index). Inside a clone, a refined recursive call
(`sum<3>` calling `sum<2>` through `Cons`'s `σ`) is specialized in turn;
an index that climbs leaves the budget and reaches the general `f`.
**Q1** asks the owner whether this is mandatory (the recommendation) or
whether boundaries convert.

### 2.8 Bytecode

§2.3's group record and §2.4's data type record
`Data = (Attribute group, VarInt member, Array<TermNode> indices)` and
`Self = (VarInt member, Array<TermNode> indices)`, generated encoders on
the Idris side (L03, D51). Deleted: `BoxType`, `TableCtor`,
`TableMember`, `DataTable` (`IdrBytecode.td:43-65`), the frontend's
`!idr.data` text entry (14 TD2's "data as a String name").

### 2.9 Printing with aliases

§2.3. A program's text holds each group once, at the top, as an alias;
every type names it. Without aliases a nested group prints inline at
each use, so its text grows with the tree; the canonical key text
(`canonicalText`, `Symbols.h:255-264`) is no longer needed for types,
whose identity is their pointer (§2.18).

### 2.10 Where the frontend reads each fact from checked TT

The family-side contract L16 implements (its table:
`L16-frontend.md:373, 387-391, 416`):

| fact | Idris source | today's reader |
| --- | --- | --- |
| the member (an instance) | `TCon` with its keyed parameters, the key as today | `dataInstanceIn` (`Translate/Types.idr:951-1009`) |
| index positions and their sorts | `TCon`'s `parampos` complement (`Core/Context/Context.idr:103-113`), patched by `dataParams` (`Translate/Types.idr:118`; the fork's bug, 17 FB-18, fixed in the fork under D44); each position's sort from the TCon's Pi binder types | `kinds`, `valueKind` (`:193-204`) |
| each constructor | `datacons`, each `DCon`'s `type` normalised (`:1029`) | `constructor` (`:1014-1040`) |
| a binder's quantity | the Pi binder's `RigCount` (`Core/TT/Binder.idr:96-114`), through `use` (`Frontend/Resolve.idr:204-205`) | `walk` (`:1046-1066`) |
| a constructor's binders | its `Rig0` Pi binders that occur in the result's index positions or in a kept field's index positions (`mentionsMarker`, `:165`) | none (erased today) |
| the equation | the normalised result type's arguments at the index positions, translated by §2.1 over the binders' markers (`marker`, `:50-62`) | none |
| a field | a `Rig1` or `RigW` binder that is no parameter and no implementation (`DictArg`), its type normalised; `!idr.lin<T>` for `Rig1` | `walk` |
| a self reference | a field type naming an instance of the group being registered | `reentered` (`:977-980`) |
| the group | the SCC of instances registered recursively, in registration order | `dataOrder` (`State.idr:360`) |
| the promise | the registry's `InPlaceType` hook (`Registry/Recognized.idr:185-186`) | `sumShapeOf` (`:814`) |
| the location | the TCon's `location` (`:989`) | `toLoc` |
| a function's index binders | erased Pi binders occurring in an index position of a runtime binder's or the result's type (L16's `Position.Index`) | dropped (`Translate/Terms.idr:443-452`) |
| a call's index arguments | the quantity-0 application arguments at those positions, translated by §2.1 | dropped |
| a case's constructor | `ConCase`'s tag (`Core/Case/CaseTree.idr:44`) | `Cases.idr` |
| an impossible leaf | `Impossible` (`CaseTree.idr:37`) | `Unreachable` (`Cases.idr:210`) |
| an erased equality | the type `x = y` of an erased proof argument of `replace`/`rewrite`, or of an erased `Refl` scrutinee | none (registry identity today) |

The frontend never unifies index terms: it instantiates declarations
(R2), writes the types Idris's terms have, and writes `idr.reindex`
wherever two types it writes differ syntactically (a yield against the
match's result, an argument against its parameter). Our verifier checks
each against `σ*`. For a partial definition's missing constructors it
writes **one** default with the crash (15 CS-4), never one arm per
constructor (`Cases.idr:298-306` today), so no arm ever names an
impossible constructor.

### 2.11 Families a pass declares

Defunctionalization declares a closure member per slot key and a memo
member per lazy key (L18's pass; today `Defunctionalize/Declare.cpp`).
Under D48:
- **Indices**: the carrier type's free levels (`!idr.fn<(i64) ->
  #Vect[v0]>` inside `map<v0>`) become the member's indices, sorts from
  their binders, so the sum's type at the use is `#Clo[v0]` and an
  application's result type `#Vect[v0]` stays expressible (I13).
- **Labels**: each label binds its lifted function's erased parameters
  as constructor binders, its equation relating them to the indices; its
  captures are fields over them. A binder no index determines is
  existential and is bound afresh by the dispatch's case.
- **Groups**: closure members and the program's families that hold them
  form new groups by `regroup` (I5); a memo member is always `Cell`.
- **Frames** (`Tail/FramesTypes.cpp`) today declare a stack data type;
  D31 rebuilds frames as typed stacks, which is L10's; if they stay
  families, they are data members declared the same way.

### 2.12 `Fin n` and every numeral

A member is **numeral-shaped** when it has exactly two declared
constructors, one with no field and one whose only field is `self`
(graded or not) at the same member, and its group has one member:
`Fin`, `Elem`, `LNat`, a user's Peano type. Detected from the declaration
(0018 D4: generically, never by name; 0019 D2: the layout decides from
the body). Layout: §2.6 rule 2, the bound computed arithmetically from
the descending index position (0018 §6.3), never by unrolling.
- `idr.con` of the zero is the number 0; of the successor, its operand
  plus 1 (zero-extended across a width); a match is a test of zero and
  binds the predecessor; all in the lowering, read off the layout.
- `Nat` itself (Idris's `Chain`, no index) stays `!idr.nat`
  (`IdrTypes.td:245-249`): its arithmetic is the runtime's big
  arithmetic.
- Converting between a numeral and `!idr.nat` (`finToNat`,
  `natToFinLT`): two ops, `idr.numeral.to_nat` and `idr.numeral.of_nat`
  (no range check: Idris proved the bound; 0018 D5), identity at
  `Number{natural}`, a widening or narrowing at `Number{w}`. Their names
  are L13's.
- Deleted: the frontend's mapping of every Numeral to `NatT` and its
  `FZ`/`FS` arithmetic (`Translate/Terms.idr`, `natCase` in `Cases.idr`
  for Numerals; `Chain` keeps it).

### 2.13 The `in_place` promise (D24)

- The promise is `DataMember.promise = InPlace`, part of the type's
  identity.
- D24's rule reads it from the family: "a function that takes apart a
  quantity-1 parameter of such a type and builds a value of that type
  from it rebuilds it" compares the **member** of the parameter's and
  the result's types, indices ignored (an indexed in-place family
  rebuilds `Cons` at `m + 1` from `Cons` at `n`).
- At `Closed` the value is in place or a number: no cell exists, so the
  rebuild is the construction itself; at `Unknown` it is a cell, and
  counting must recycle it (D24, C1).
- Deleted: `SumKind::InPlace` and `Demand.cpp`'s reading of it (with
  D24's deletion of `rebuilt`).

### 2.14 An array field (D43)

A field that is an array is a buffer (`memref`), never a tensor (F7).
Its dimensions are static where the frontend writes a literal and `?`
otherwise; an index term in a dimension is not representable in a
builtin `memref` type, and whether shapes become index terms is L12's.
At `Closed` applications an array field stays a buffer (a `Cell` of its
own), so the class rule needs no array case.

### 2.15 Constructor provenance

| fact | constructed by | who alone may |
| --- | --- | --- |
| a data member (Idris's) | the frontend's family table, from `TCon`/`DCon` (§2.10) | the frontend |
| a closure or memo member | idr-defunctionalize | that pass |
| a new group over changed members | `regroup` | the passes that change field types and create cycles (defunctionalization) |
| any other remake of a group's content | upstream's `AttrTypeReplacer` | any pass, through the replacer |
| index terms in types | the frontend (TT normal forms); the substitution utility | those two |
| a function's binders and a call's index arguments | the frontend; the specializer's clones | those two |
| a case's binders and fields | the match's builder (instantiation, R1-R2) | the builder; the frontend writes the same in bytecode |
| `σ_C`, `σ*` | the unifier (one implementation, `lib/IR/Unify.cpp`) | derived, never stored |
| `possible`, `cls`, `layout`, `held` | the data type's storage construction | construction only |
| byte offsets | `Layouts` | the analysis |
| the pruning of impossible cases | the substitution utility; the match canonicalizer (dead defaults) | those two |
| `idr.reindex` | the frontend; folded by canonicalization | the frontend adds; no pass adds one except substitution's renaming of an existing one |
| `idr.assume` | the frontend, from an erased equality's type | the frontend |
| the promise | the registry's `InPlaceType`, through the frontend | the registry |
| a lifetime binder | L05's inference | L05's pass |

### 2.16 Every consumer of `!idr.box`, adapted

*Measured*: `grep -rn 'BoxType\|isBoxed(\|Idr_BoxValue\|Idr_SumType\b\|Idr_SumValue\|Idr_SumView\|layouts\.box\|\.box(\|graph\.boxed\|\.boxed('`
over `foreign/idr/{lib,include,tools}`, and `grep -rn BoxType
compiler/src/IdrisMLIR`; fixtures `grep -rhoE '!idr\.box<'` over `tests
foreign compiler libs`: 3,144 occurrences in 104 files.

"Cell" below means `type.layout() == Cell` (§2.4), "possible" the set.

| consumer (read) | today | adapted |
| --- | --- | --- |
| `IdrTypes.td:167-181` `Idr_BoxType` | the type | deleted |
| `IdrTypes.td:311` `Idr_SumType` | data or box | deleted (unused, 01 T04) |
| `IdrTypes.td:334` `Idr_BoxValue` | a box at any grade | `Idr_CellValue`: a data type at any grade whose layout is `Cell` |
| `IdrTypes.td:338, 341-342` `Idr_SumValue`, `Idr_SumView` | data or box | a data type at any grade (one type) |
| `IdrTypes.td:347-351` `Idr_DestType` param | a box | a data type whose layout is `Cell` (D34's destination into a cell field) |
| `IdrOps.td:36` `Idr_SumRead` | data or box | a data type |
| `IdrOps.td:291` con result | `Idr_SumValue` | a data type |
| `IdrOwnershipOps.td:158-170` `!idr.cell<box, @C, ℓ>` | box param | `!idr.cell<!idr.data<...>, @C, ℓ>`; verify: `layout == Cell`, `C` possible, not an atom; declarative format with `custom<CtorRef>` (01 T13) |
| `IdrOwnershipOps.td:260` `cell.init` result | `Idr_BoxValue` | `Idr_CellValue` |
| `IdrClosureOps.td:165-170` `Idr_MemoCell` | a box of a memo | a data type with `memo()` |
| `IdrMatchOps.td:116` scrutinee `Idr_SumView` | data or box | a data type |
| `IdrBytecode.td:43-46` | `BoxType` record | deleted |
| `ValueFacts.cpp:136-140` | box answers | deleted; `!idr.data` answers from `held`, `layout` |
| `Symbols.cpp:22, 26`; `Symbols.h:35-38` | `dataTypeOf` through a box; `isBoxed` | `dataTypeOf` reads `!idr.data` through a grade; `isBoxed` deleted (its readers ask the layout) |
| `Grades.cpp:126` | box or data holds references | `!idr.data`'s `held` |
| `TypeGraph.cpp:43, 68` | box vs in place edges | §2.6 rule; `TypeGraph` keeps only the knot question, over groups and arrays |
| `DataBody.cpp:101` | list tail through a box | deleted with the file (`listShape()`) |
| `DataRemap.cpp:38, 100-103` | box remap | deleted with the file |
| `Layout.h:224-233`, `Fit.cpp:24-38` | `fit` | deleted |
| `Layouts.cpp:80` `graph.boxed` | cells only for boxed types | cells for `Cell`-layout types |
| `OpsCon.cpp:51-55` con effects | a box allocates | pure (C3; memory at `cell.new`) |
| `OpsCon.cpp:62-68` con speculatability | a box is not | not speculatable only when it takes an owned field (C3) |
| `OpsCon.cpp:136-150` `destOf` | hole field must be a box | hole field's type has layout `Cell` |
| `OpsConReads.cpp:24-28` field speculatability | box is not | the type determines the constructor (I10) |
| `OpsOwnership.cpp:22-24` `buildsCell` | box and not atom | `Cell` and not an atom at the application |
| `OpsOwnership.cpp:32-75` `CellType` parse, print, verify | box | as the cell row above |
| `Verify/Uses.cpp:143` | box: atoms reach nothing | `Cell` |
| `Verify/OwnedOps.cpp:128` | `isa<BoxType, DataType>` | `isa<DataType>` |
| `Verify/Program.cpp:110-111` recycle size | `layouts.box(...)` | `layouts.cell(type, tag)` (with 01 C3's typed token) |
| `IR/Tail.cpp:185` | a boxed operand ends a part path | `Cell` |
| `Canon/Feeds.cpp:187` | a con of a box feeds nothing | a con whose type is `Cell` |
| `Analysis/Ownership/Values.cpp:22-35` | `followed`, `isMemoCell` | `isa<DataType, TokenType>` owned; `memo()` |
| `Analysis/Ownership/Uses.cpp:172-185` | `onlyReads` on boxes | on `Cell` types |
| `Analysis/Ownership/Reuses.cpp:76, 114, 192, 213` | reuse of boxes; cell sizes | `Cell` types; `layouts.cell` |
| `Transforms/Stack/Stack.cpp:314` | cell size | `layouts.cell` |
| `Transforms/Ownership/Cells.cpp:41` | `CellType` of a box | of the data type |
| `Transforms/Tail/Trmc.cpp:219, 255` | result is a box; dest of the box | result's layout is `Cell`; dest of the data type |
| `Transforms/Tail/Frames.cpp:217, 277, 285`, `FramesTypes.cpp:28` | the stack below as a box | a self field (`self`), the layout makes it a cell; or L10's typed stacks |
| `Transforms/Defunctionalize/Declare.cpp:39-42` | memo values held as boxes | a memo member is `Cell` by rule 1 |
| `Transforms/Defunctionalize/Pass.cpp:153-156` | statistic of boxed closure sums | `layout == Cell` over closure members |
| `Conversion/Cells.cpp:32, 188, 226, 249-252` | box vs sum lowering of con, unpack, tag, field | dispatch on `layout()`: `Cell`, `InPlace`, `Number` |
| `Conversion/Counting.cpp:73`, `StaticData.cpp:164`, `MemoCells.cpp:70`, `RuntimeCells.cpp:64`, `Strings.cpp:64` | `layouts.box(data)` | `layouts.cell(type)` |
| Idris `Syntax/Idr.idr:480, 509, 525`; `Encoding/Idr.idr:51-56`; `MLIR/Bytecode.idr:425`; `SyntaxSamples.idr:100-114` | the generated box | deleted; regenerated from the spec |
| 104 fixture files, 3,144 occurrences | `!idr.box<...>` text | restated by behaviour or deleted (L19; §5 W11) |

### 2.17 The 149 body readers, adapted

By what each reads (the per-line list is the *measured* grep of V12):

| reads | files (count of matches) | adapted to |
| --- | --- | --- |
| a kind test (`isMemo`, `isClosures`) | Captures (3), IdentitiesRecord, Values, ExclusivityAnalyses, Effects, OpsGenerating, Symbols (4), Layouts, Verify/Program, Verify/Owned, Canon/Force, Specialize/Keys (5), Inline (2), Tail/FramesPlan, Defunctionalize/Pass, Converter (2), Expect/ByName, StaticNames, StaticData, `IdrClosureOps.td:169` | `memo()`, `closures()` views (01 C4) |
| a role's tag or payload (`getRunningTag`, `getForcedTag`, `role::Label`) | Captures:17, Owned:179, FlowEdges:52, OpsClosures:231, Inline:106, Defunctionalize/Patterns:78-82, MemoCells:63-91, Canon/PutList:49, Fold/Values:51 | the memo view's fixed positions (`running`, `forced`, labels); the closures view's labels |
| base list's shape (`getNilTag`, `getConsTag`, `getListElement`) | Strings:59-140, Fold/Strings:229, `IdrBase.td:341` | `listShape()` |
| field types of a constructor at a value | LabelSites:142, Reuses:124-240, Captures:31, FlowEdges:45, ConAttr:110, Constants:95, OpsCon:87-130, OpsOwnership:114, OpsConReads:42, FlowOps:50, Verify/Uses:147, Specialize/Patterns:40, Placement:314-341, Defunctionalize/Patterns:48, Counting:80, StaticData:106-226, Columns.h:54, unittests/Constants | the op's own types (block arguments, `idr.field` results, `con` operands), or `determinedFields(tag)` where no op holds them (constants: a constant's type is closed, so its fields are always determined) |
| field types of a declaration | Layouts:74-92, Components:38-111, Verify/Program:274, Specialize/Keys:118, Frames:231, FramesPlan:127, Columns/Records:42-79, Converter:58-78, Defunctionalize/Keys:165, Forces:54, Expect/Closures:75, Expect/ByName:43 | `decl()`'s raw fields (levels are the constructor's), or the class-instantiated fields of §2.6 |
| how many constructors / the tags | IdentitiesRebuilds:194, IdentitiesRecord:63-68, ConAttr:106-108, OpsCon:83-86, OpsOwnership:66-68,111-113, OpsConReads:181-190, Asm:129, Components:109, Canon/Eta:70, Frames:222, Defunctionalize/Pass:156, Converter:56-68, Defunctionalize/Patterns:101-110, Forces:86, Facts:54 | `possibleTags()` where the reader branches or asks "one constructor" (more precise: `#Vect[v0+1]` has one); `declaredCount()` for the tag space (`Facts.cpp:54`'s LLVM range at `Unknown`, the possible range at `Closed`) |
| an atom (`isAtom`) | Reuses:175, IdentitiesRecord:240, OpsOwnership:23, Verify/Uses:144 | `Cell` layout, no field at the application, not memo |
| a constructor's label | ConAttr:216, OpsOwnership:55-70, Asm:131-184, Verify/Program:115, ReusesEveryCell:25, ReusesInPlace:30 | `decl()`'s label |
| a whole body, to remake or encode | DataRemap (9), TypeGraph (2), Bytecode:72 | deleted with their files or rewritten (§2.6, §2.8) |

### 2.18 What this area deletes

- `include/idr/IR/IdrTypes.td`: `Idr_DataType` as a `MutableType` with
  its `Body`, `getKind`, `getCtors`, `getCtor`, `getTags`, `getTag`,
  `isMemo`, `isClosures`, `isAtom`, `get*Tag`, `getListElement`,
  `walkLabels`, `replaceLabels`, `seal`, `solveHeld`, `roleTag`,
  `verifyBody`, `getHeld`, `isDefined` (`:48-165`); `Idr_BoxType`
  (`:167-181`); `Idr_SumType` (`:311`).
- `include/idr/IR/IdrAttrs.td`: `Idr_DataTableAttr`; `#idr.instance` on
  bodies (the member's label replaces it; `idr.func`'s `instance` stays
  until 0003 B7 types it).
- `include/idr/IR/IdrBase.td`: `Idr_SumKind`, `Idr_CtorRole`,
  `Idr_BaseListOf` (a `listShape()` constraint replaces it).
- `include/idr/IR/IdrBytecode.td`: `BoxType`, `TableCtor`, `TableMember`,
  `DataTable`.
- `include/idr/IR/IdrDialect.h`: `namespace role`, `Role`, `kindOf`,
  `emptyRole`, `Ctor`, `TableCtor`, `TableMember`, `DataDefinition`.
- `include/idr/IR/Symbols.h`: `isBoxed`; `Declarations` (`:88-137`);
  `DataRemap` (`:139-236`); `canonicalText(Type)` and
  `canonicalHash(Type)` if no other reader remains (L18's keys).
- `lib/IR/DataBody.cpp` whole; `lib/IR/DataRemap.cpp` whole;
  `lib/IR/Layout/Fit.cpp` whole; `lib/IR/Types.cpp:25-268` (the storage,
  sealing, `define`, `~Declarations`).
- `lib/IR/Func/Func.cpp:47` (`declare`), `:56-90` (the walk); `idr.program`'s
  `types` property (`IdrOps.td:74-75`).
- `lib/IR/Bytecode.cpp`'s table rows; `lib/IR/Asm.cpp:96-106` (data type
  alias by name), `:113-116` (`data_types`).
- `lib/IR/TypeGraph.cpp`'s value walk, `boxed`, `inlined`, the
  self-containment rule (`Verify/Program.cpp:266-294`'s memo-in-place and
  self-containment parts).
- `lib/IR/ValueFacts.cpp:136-140` and the sealing-time `solveHeld`
  (moved to group construction).
- Idris: `Term.idr:98-124` `DataShape`'s three constructors (a member's
  kind replaces them); `Emit/Index.idr:65-85` the table; the generated
  `IdrSum`, `BoxType`, `DataType name`; `Translate/Types.idr:1000-1004`
  `Newtype` (I8); `Cases.idr:298-306` per-constructor crash arms (I9);
  the Numeral-to-`NatT` mapping (§2.12).

### 2.19 Distinctions that remain, essential

- An index (erased, compile time) and a field (run time).
- A field of quantity one (`!idr.lin<T>`) and of many.
- The three member kinds: Idris's data, a closure sum, a memo sum (their
  constructors carry different things).
- The `in_place` promise and none.
- `Closed` and `Unknown` classes; `Number`, `InPlace` and `Cell`.
- A case region (a run-time test justifies `σ`) and an `idr.assume`
  region (an erased proof justifies it).
- `opaque` (unknown) and every closed term.
- A declaration scope and a function scope (where levels start at 0).

### 2.20 Seams

| seam | declaration both sides write against | state |
| --- | --- | --- |
| L03 (the spec) | §2.1's term, sort and member types in `IdrisMLIR.Spec.Families` (C7's package), well-scoped by `Fin s`, equations by `Vect s`; the generated C++ enums `TermKind`, `Sort`, `Promise`, `ByName`; the hand storage of §2.3 named in one-source §9 | fixed here; placement L03's |
| L05 (lifetimes) | one telescope, levels, `ErasedBinderOpInterface`; `lifetime` a sort never an index of a data type; "same recursive group" is `group == group` of two data types; a `Cell`'s arena is the lifetime's | agreed in substance with `L05-lifetimes.md:187-197, 321-368, 590` |
| L07, L08 (counting, exclusivity) | `Cell`-layout types are the only counted cells; `Closed` in-place values have no cell (no count, no token); the in-place promise compares members | fixed here |
| L09 (control flow) | `idr.join` binds erased parameters at the next levels; `idr.jump` passes terms; `idr.assume` neither propagates breaks nor binds; a jump out of a case region crosses its `σ`, so jump arguments are typed in the target's scope | proposed here |
| L10 (frames) | if frame stacks stay families, they are data members with a `self` field | unfixed (D31's design) |
| L12 (arrays) | an array field is a buffer; dimensions literal or `?`; whether shapes become index terms | unfixed, L12's |
| L13 (ops) | the names of `idr.reindex`, `idr.assume`, `idr.numeral.to_nat/of_nat`; `idr.tag` folds on a singleton `possible` | proposed here |
| L16 (frontend) | §2.10's table; the frontend never unifies; one crash default; reindex where written types differ; field quantity as the grade (L16 recommends the same, `L16-frontend.md:500`) | agreed in substance |
| L18 (specializer, inliner, defunctionalization) | the substitution utility; specialization by class; inlining through substitution (I14); closure and memo members (§2.11); `regroup` | proposed here |
| L19 (tests) | the fixtures of W11 | proposed here |
| DP-37 (G) | the refined scrutinee's type (R7) | unfixed until folded |

## 3. QTT

**Quantity 0.**
- *Enters*: as `Rig0` Pi binders of constructors and functions, and
  `Rig0` application arguments (`Core/TT/Binder.idr:96-114`).
- *Kept*: a `Rig0` binder that occurs in an index position becomes an
  index variable, a level of a telescope (§2.2), in constructors (binders),
  functions (L16's `Position.Index`) and calls (index arguments); a `Rig0`
  binder occurring nowhere is a proof and is absent (F4); an erased field
  does not exist (no erased quantity in a declaration, V11); an erased
  equality proof becomes an `idr.assume` region, a refinement and not a
  value.
- *Read*: by the unifier (impossible cases, refinement, empty types), the
  class rule (fixed shapes, numeral widths), the substitution utility
  (specialization prunes), the in-place rule (no: it reads the member).
- *Lost*: at an index outside the language (`opaque`: the TT term); at
  the lowering, on purpose (types become layouts); at a runtime value in
  an index position (Q2).

**Quantity 1.**
- *Enters*: `Rig1` constructor fields and binders.
- *Kept*: a field's grade (`!idr.lin<T>`); a case binds a field at the
  scrutinee's quantity times the field's (R2, as `fieldType` does
  today).
- *Read*: the linearity verifier; D24's rule (a quantity-1 parameter of
  an `in_place` member rebuilt); counting's ABI.
- *Stronger with families*: a quantity-1 value of a `Closed` in-place
  family has no cell, so it is never counted and never shared (a copy is
  the value); exclusivity has no question about it, and reuse has no
  token to carry. The proof Idris made (used once) and the layout (no
  cell) together make every count operation on it unwritable: counting's
  ops take `Cell`-layout operands only (`Idr_CellValue`).

**Quantity ω.**
- *Enters*: `RigW` fields; the bare type.
- *Lost*: an ω binder that occurs in an index position (`replicate`'s
  `n`, a dependent pair's first component) is opaque there; the link
  between the value and the index is gone, and the class falls to
  `Unknown`. Q2 asks whether to keep it (DML-style singletons).

**Facts a quantity or index proves that the design should use, and does
(each a D10 item):**
- an impossible case costs no code and no test (R4);
- one possible constructor costs no tag test and no tag word (R6, §2.6);
- a closed shape costs no cell, no header, no count (§2.6);
- a closed numeral bound costs no big (§2.12);
- an uninhabited application makes the code that holds a value of it
  unreachable (I12; Idris's `isEmpty`);
- a field read whose constructor the type proves is speculatable (I10).

**Facts the design still pays for:**
- a class-changing `idr.reindex` (bounded by `B`, V6, Q1);
- a numeral at an unknown bound is a big, which is essential: the value
  can exceed 2^64 (0018 §7);
- a runtime index is opaque (Q2);
- the verifier's unification per case per verify (a compile-time check
  of stored types, D10 §1.2).

**Misuse made unwritable:**
- a field read of a constructor the type excludes (`possible`);
- an impossible case region (R4);
- a value type naming a binder out of scope, or a `self` outside a
  declaration (the scope rule);
- a tensor field (F7); an erased field (no erased quantity); a box of a
  type held in place (no box type exists);
- a count operation on a value with no cell (`Idr_CellValue`).

## 4. Improvements

Each improvement selects one correction. "Coordinator" means AGENTS.md,
the evidence or elegance settles it; "owner" means it changes a ruling's
stated property, a promise, scope or a contested core shape.

**I1. Index variables are de Bruijn levels of one telescope; a
declaration is a scope of its own.** *Coordinator.*
- *Evidence*: types print and unique with no context (MLIR); values flow
  inward by dominance; L05 independently chose levels
  (`L05-lifetimes.md:189-196`).
- *Counterexample*: with named variables, `@map<n>` and `@zip<n>` would
  have distinct types `#Vect[n@map]` and `#Vect[n@zip]` for one meaning,
  and inlining `zip` into `map` would merge two binders named `n` into
  one. With de Bruijn indices, a value of `#Vect[#0]` defined before a
  case and used inside it would need the type `#Vect[#1]` there, and a
  value has one type.
- *Root cause*: identity by text, or by a coordinate that moves with the
  use.
- *Correction*: levels, §2.2.
- *Deletes*: nothing existing; it forbids a name as a variable's
  identity.
- *Discriminated by*: a `test-unit` box that builds `#Vect[v0]` in two
  functions and asserts one type object; a fixture where a value crosses
  a case boundary and verifies.

**I2. Classes and a shape budget make the layout total and the fixed
shape compositional.** *Owner, through Q1* (it qualifies D48's "none of
it paid at run time"); the class rule itself is *coordinator*.
- *Evidence*: V6.
- *Counterexample*: `sum : Vect n Int -> Int` compiled once; `main`
  calls `sum [1, 2, 3]` with `#Vect[3]` inline (three words); the body
  reads its argument as a cell pointer and loads garbage. And `data T :
  Nat -> Type where Mk : T (S n) -> T n` makes the layout of `T 0`
  unfold forever.
- *Root cause*: a layout that depends on index knowledge, applied across
  code compiled for unknown indices; an unfolding with no measure.
- *Correction*: §2.6's classes and budget, and §2.7's specialization by
  class at every call whose layout changes; a bounded conversion only at
  a class-changing `idr.reindex`.
- *Deletes*: `layout::fit` and its remap; `!idr.box`.
- *Discriminated by*: a fixture calling an index-polymorphic `sum` at
  `[1,2,3]` and at a runtime-length vector, both printing the right sum,
  with an `idr-expect` property "every call's argument layouts equal its
  callee's parameter layouts" that fails if specialization is skipped;
  `T 0` compiling.

**I3. Refinement is a scoped substitution, and the one cast checks
against it; an erased equality is a scope too.** *Coordinator.*
- *Evidence*: V5; §5.8 B1 (strict type equality, every regrade an op);
  `ControlFlowInterfaces.td:100` (no region context in the type check);
  `InliningUtils.cpp:395-396`.
- *Counterexample*: `map`'s `Cons` case yields `#Vect[v1 + 1]` to a
  match whose result is `#Vect[v0]`; with no cast the verifier must
  compare types modulo the case's refinement, and upstream's fold of a
  one-case match replaces the result by a value of type `#Vect[v1 + 1]`
  outside the case, where `v1` is unbound. With a trusted (unchecked)
  cast instead, a pass that moves the cast out of its case leaves a
  false type no verifier sees.
- *Root cause*: a fact that holds only in a region (the refinement) with
  no representation of the region's fact.
- *Correction*: `σ_C` per case, `idr.assume` for an erased equality,
  `idr.reindex` checked against `σ*` (§2.5).
- *Deletes*: the registry's identity hooks for `replace`-shaped
  definitions, where they exist, replaced by `idr.assume`.
- *Discriminated by*: a verifier fixture where a `idr.reindex` hoisted
  out of its case is refused; `rewrite`-heavy fixtures (`plusZeroRightNeutral`
  style) compiling and running.

**I4. Labels are part of a family's identity.** *Coordinator.*
- *Evidence*: MLIR stores one storage per key; a field outside the key
  holds the first creator's value.
- *Counterexample*: `data Bool' = T | F` and `data Switch = On | Off`,
  keyed without labels, are one type; printing every `Switch` shows
  `@T` and `@F`, and an error message about `Switch` names `Bool'`.
- *Root cause*: a stored fact outside the identity.
- *Correction*: labels (member and constructors) in the key (§2.3).
- *Deletes*: nothing.
- *Discriminated by*: a `test-unit` box: two declarations equal but for
  labels are two attributes; equal with labels, one.

**I5. A group is an SCC of instances in a deterministic order, and one
`regroup` utility forms new groups where a pass creates a cycle.**
*Coordinator.*
- *Evidence*: V1, V3, V12; `Defunctionalize/Declare.cpp:1-13` ("sums hold
  sums, which the definitions of one another tie").
- *Counterexample*: `data T = MkT (Int -> T)`. Defunctionalization makes
  a closure sum `S` for the slot; a lambda capturing a `T` makes `S`
  hold `T`, and `T`'s field becomes `S`. An `AttrTypeReplacer` cannot
  build `T'` (it needs `S`) nor `S` (it needs `T'`).
- *Root cause*: a cycle created after the frontend, among declarations
  that are immutable.
- *Correction*: `regroup(members, replacements)`: Tarjan over the
  changed declarations' references, one group per SCC, members ordered
  by their old (group position, member) then new members by their key's
  order; returns the replacer from old types to new.
- *Deletes*: DataRemap's names, keys, `describe`, `remake`, `shapeAt`,
  its `leaf` callbacks (`DataRemap.cpp`), and the per-kind remaps of
  `fit`, deduplicate (a label rename is a replacer edit) and bufferize
  (D43 deletes that one).
- *Discriminated by*: the counterexample as a fixture; a determinism
  check (two runs, byte-identical bytecode, as D52's kind of check).

**I6. Member kinds are a closed sum of three; `list` and `numeral` are
shapes, not kinds.** *Coordinator.*
- *Evidence*: 01 T06, T08 (`KindRule`, `SumKind::InPlace` same rules as
  plain); 0019 D2 (the layout decides from the body).
- *Counterexample*: today a `list`-kind body with three constructors is
  refused at sealing by a hand table (`DataBody.cpp:43-45, 85-92`); a
  user list `data L = E | C Char L` passed to a string op is refused by
  `Idr_BaseListOf` though its layout is a list's.
- *Root cause*: a property of the body's shape spelled as a kind, held
  twice (kind and roles).
- *Correction*: `Member = variant<DataMember, ClosureMember, MemoMember>`
  (§2.3), `listShape()` and numeral shape derived once per group.
- *Deletes*: `Idr_SumKind`, `Idr_CtorRole`, `KindRule`, `RoleOnce`,
  `ruleOf`, `roleTags`, the role variant and its 18 `get_if` sites (01
  T09), the registry's `ListType` hook as a kind source.
- *Discriminated by*: a memo member cannot be built without its states
  (C++ type); the string fixtures still pass.

**I7. Numerals are families with a number layout; 0018's D1 is
superseded and its F1, F2 become the class rule.** *Coordinator* (0018
amended in the same change, as D43 amended 0009).
- *Evidence*: V7; 0018 §2 ("a data instance's key erases every index"),
  §6.2 (F2's classes).
- *Counterexample*: under D48 `@index<n>(%i : ?, %xs : #Vect[v0])` must
  type `%i`; if the frontend maps `Fin n` to `!idr.nat` the index is
  lost, `index`'s inner `Nil` case is no longer impossible, and after
  specialization at `n = 256` the word is still a big.
- *Root cause*: the frontend cannot decide a width it does not know.
- *Correction*: §2.12.
- *Deletes*: the Numeral branch of the frontend's `NatT` mapping, its
  `FZ`/`FS` arithmetic and `natCase` for Numerals.
- *Discriminated by*: 0018's F1 fixtures (`FS` across 256 and 65536, a
  `Fin (power 2 100)` staying a big) and an `idr-expect` property that a
  `Fin 256` field is an `i8` component.

**I8. The one-field collapse is a layout, not a frontend decision.**
*Coordinator*; seam L16 (which proposes the same, `L16-frontend.md:191-196`).
- *Evidence*: 15 NQ-1, TT-7; `Translate/Types.idr:1000-1004`.
- *Counterexample*: `data Wrap : Nat -> Type where MkWrap : Int -> Wrap
  (S n)` collapses to `Int`; a match on `Wrap 0` (impossible) cannot be
  known, and the family's equation never reaches the IR.
- *Root cause*: a representation choice made before the family is
  declared.
- *Correction*: declare the family; §2.6 gives a member with one
  possible constructor and one field the field's components (no tag, no
  wrapper), at both classes.
- *Deletes*: `Registered.Newtype`, `quantityTimes` through it
  (`Resolve.idr:217-219`), the newtype case of `Cases.idr`.
- *Discriminated by*: a fixture matching an indexed one-field type at an
  impossible index (refused case) and an `idr-expect` property that a
  one-field family has its field's components.

**I9. The empty default keeps Idris's coverage; impossible case regions
are refused; a dead non-empty default is erased; the frontend writes one
default.** *Coordinator.*
- *Evidence*: V5; `Cases.idr:93-97, 117, 210, 298-306`; 15 CS-4.
- *Counterexample*: a partial `f : Vect (S n) a -> Int` with clauses for
  `Cons` only, written partial for another reason, gets a crash arm for
  `Nil` today; under D48 that arm names an impossible constructor and the
  verifier refuses the module.
- *Root cause*: arms enumerated from the instance's constructors with
  indices erased.
- *Correction*: R4, R5; one crash default.
- *Deletes*: per-constructor crash arms.
- *Discriminated by*: the counterexample as a fixture (accepted,
  running); a verifier fixture with a hand-written impossible case
  (refused).

**I10. A field read is speculatable exactly when the type determines the
constructor.** *Coordinator.*
- *Evidence*: `OpsConReads.cpp:24-28` (box decides).
- *Counterexample*: `head<v0>`'s `#Vect[v0 + 1]` field read stays where
  it is today, though no value of the type can be anything but `Cons`.
- *Correction*: §2.5's `idr.field`.
- *Deletes*: the box test.
- *Discriminated by*: a hoisting fixture (`idr-expect`: the read is
  hoisted out of a loop where the type proves the constructor).

**I11. A data type's intrinsic facts are computed at its construction;
byte offsets stay in `Layouts`.** *Coordinator.*
- *Evidence*: 01 C5, §5.8 T7 (FIRRTL's `RecursiveTypeProperties`);
  98c6315c (the lazy fixpoint through `mutate` that queued workers).
- *Counterexample*: computing "is this a cell" lazily on first question
  through the uniquer is 98c6315c's wall again; computing it in an
  analysis leaves ODS constraints and type verifiers (`!idr.cell`,
  `Idr_MemoCell`) without it.
- *Correction*: §2.4's derived facts in storage.
- *Deletes*: `solveHeld` at sealing (moved), `holdsNoComponent`'s walk
  (01 T54), `TypeGraph` in verifiers.
- *Discriminated by*: a `test-unit` box asserting the facts of
  `#Vect[3]`, `#Vect[v0]`, `#Fin[256]` without a module.

**I12. An uninhabited application makes code that holds it
unreachable.** *Coordinator.*
- *Evidence*: `Coverage.idr:137-151` (Idris's `isEmpty`).
- *Counterexample*: after specializing `index<0>`, the body binds a
  `#Fin[0]` parameter; today it compiles the whole body.
- *Correction*: a function or region binding a value whose type has
  empty `possible` is `ub.unreachable` (a canonicalization).
- *Deletes*: nothing.
- *Discriminated by*: an `idr-expect` property that the specialized body
  is one `ub.unreachable`.

**I13. Pass-declared sums are indexed by their carrier's free levels.**
*Coordinator*; seam L18.
- *Evidence*: §2.11.
- *Counterexample*: a closure `\x => replicate' x xs` with `xs :
  #Vect[v0]` inside `map<v0>`: if the closure sum has no index, the
  dispatch's result type is `#Vect[b]` with `b` fresh per label and no
  verified cast relates it to `v0`.
- *Correction*: §2.11.
- *Deletes*: nothing.
- *Discriminated by*: the counterexample as a fixture verifying after
  defunctionalization.

**I14. An index-polymorphic callee is inlined through the substitution
utility.** *Coordinator*; seam L18.
- *Evidence*: `InliningUtils.cpp:395-396, 532-537`;
  `lib/IR/Func/Inliner.cpp:22-45` (our interface allows every inline).
- *Counterexample*: inlining `@sum<v0>` at `@sum<3>` today fails the
  argument type check, or materializes a cast to a type that names the
  callee's `v0` in the caller's scope.
- *Correction*: idr-inline clones the callee's body under the call's
  substitution (impossible cases pruned) and hands that region to
  upstream's `inlineCall`; types then match exactly.
- *Deletes*: nothing; no upstream patch.
- *Discriminated by*: a fixture inlining an index-polymorphic function
  at a closed index whose impossible case would be refused if kept.

**I15. A runtime value in an index position keeps its link.** *Owner*
(Q2): it changes what a type is.

## 5. Work units (draft, not dispatched)

**W1. The specification's families.** Writes
`compiler/spec/IdrisMLIR/Spec/Families.idr` (C7's place; L03 fixes the
module layout). Outcome: §2.1's `Term s` (well-scoped by `Fin s`),
`Sort`, `Member`, `CtorDecl` with `equation : Vect indices (Term
binders)`, `Promise`, `ByName`; generated `TermKind`, `Sort`, `Promise`,
`ByName` enums to C++ and Idris; the attribute and type records of
§2.3, §2.4, §2.8. Must not: write `.td` by hand; add a quantity beside a
field type. Acceptance: both hosts build it; a malformed equation
(wrong length) does not typecheck.

**W2. Families and data types in C++.** Writes `include/idr/IR/Families.h`,
`lib/IR/Families.cpp` (storage, parser, printer, verifier F1-F8),
`lib/IR/IndexTerms.cpp` (nodes, normalization, fold), the data and self
types' storage and derived facts. Deletes §2.18's C++ lines for the
table, the mutable type, sealing, `Declarations`, `DataRemap`,
`DataBody.cpp`, `Idr_BoxType`. Must not: create MLIR storage inside a
storage `construct`; keep a name-alone state. Acceptance: every fixture
of `tests/dialect-syntax` restated in the new syntax round-trips text
and bytecode; a module whose case names an impossible constructor is
refused.

**W3. The unifier and the substitution utility.** Writes
`lib/IR/Unify.cpp`, `lib/IR/Substitute.cpp`. Outcome: R3's unifier, one
implementation; `substitute` with pruning. Must not: be re-implemented
anywhere (verifier, specializer, inliner and layout call these).
Acceptance: a `test-unit` property over generated term pairs:
unification's answer is a most general unifier or a clash, and every
clash is one Idris's `conflict` rule also finds (the rules of
`Coverage.idr:22-135`, restated as the property's oracle-free statement).

**W4. The ops.** Writes `IdrMatchOps` (via the spec), `lib/IR/OpsMatch.cpp`,
`lib/IR/OpsCon.cpp`, `lib/IR/OpsConReads.cpp`, the new `reindex` and
`assume` op files, the function verifier's scope and refinement walk
(`lib/IR/Verify/Function.cpp`, with 01 C7(b)). Outcome: §2.5. Must not:
make any op walk to its ancestors. Acceptance: `map`, `zip`, `head`,
`index` over `Vect` and `Fin` verify with every refinement checked; a
hoisted `idr.reindex` is refused.

**W5. Layout.** Writes `include/idr/IR/Layout.h`, `lib/IR/Layout/*`,
`lib/IR/TypeGraph.cpp` (knots only). Outcome: §2.6; `Layouts` from one
walk. Deletes `Fit.cpp`, `graph.boxed`. Must not: read a module from a
type's fact. Acceptance: `#Vect[3]` of `Int` has three `i64` components
and no cell; `#Vect[v0]` is a cell; `T 0` of I2 compiles.

**W6. The box consumers.** Writes every file of §2.16's C++ rows.
Outcome: each row's adaptation. Must not: keep `isBoxed`. Acceptance:
`grep -rn 'BoxType\|isBoxed' foreign compiler` prints nothing; the
corpus passes on all four targets.

**W7. The body readers.** Writes every file of §2.17. Acceptance: no
reader calls `fieldsAt` on a worker's hot path (a review of the diff
against §2.4's rule); the corpus passes.

**W8. The frontend** (with L16). Writes `compiler/src/IdrisMLIR/Types.idr`
(`DataT` with index terms), `Term.idr`, `Frontend/Translate/{Types,Cases,Terms}.idr`,
`Emit/*`. Outcome: §2.10. Deletes `DataShape`, `Newtype`, per-constructor
crash arms, the Numeral mapping. Must not: unify index terms in Idris.
Acceptance: the self compile's families carry equations (M1); both hosts
build the frontend.

**W9. Specialization by class** (with L18). Writes
`lib/Transforms/Specialize/*`. Outcome: §2.7. Acceptance: the I2 fixture
passes with the call-layout property; no function has more clones than
the classes the budget admits (a property).

**W10. Defunctionalization's families and `regroup`** (with L18). Writes
`lib/Transforms/Defunctionalize/{Declare,Keys,Converter,Patterns,Forces}.cpp`,
`lib/IR/Regroup.cpp`. Outcome: §2.11, I5. Acceptance: I5's and I13's
fixtures; two runs byte-identical.

**W11. Tests** (with L19). Writes new fixtures: `tests/family-impossible-case`
(refused), `tests/family-refine` (`map`, `zip` run), `tests/family-fixed-shape`
(an `idr-expect` property `components=<type>:<n>`), `tests/family-fin-words`,
`tests/family-rewrite` (`idr.assume`), `tests/family-uninhabited`,
`tests/family-closure-index`, `tests/family-regroup`. Deletes or restates
the 104 files holding `!idr.box<` and the 332 holding `#idr.types<` by
behaviour (no op-sequence match). Acceptance: every new fixture fails
before W2-W10 and passes after.

**Measurements to take** (each needs a build; none is taken here):
- M1: count of indexed members and of constructors whose equation is not
  `var`, in the self module and the corpus (the frontend's Core dump
  after W8).
- M2: distinct `!idr.data` types and group bytes per module, against
  today's table.
- M3: clones per function under specialization by class, at budgets of
  4, 8, 16 and 32 components, self module and bench.
- M4: class-changing `idr.reindex` ops left after specialization (static
  count) and their dynamic count on the bench.
- M5: the function verifier's time with refinement checking, against
  today's, on the stage-1 module.

## 6. Owner questions

**Q1. Fixed shapes across index-polymorphic code.** D48 says a known
index fixes the shape and that none of it is paid at run time; functions
are compiled once for every index. Where they meet:
- **(a) Specialize by class** (recommended): every call whose callee's
  layout changes under the call's indices reaches a clone at that class;
  the class set is finite by a shape budget, so it ends by construction;
  a bounded conversion remains only where an index becomes known inside
  a function. *Costs*: code size (M3), a budget constant to fix (debt).
  *Buys*: `#Vect[3]` inline everywhere it is known; `Fin 256` a byte
  through calls; one mechanism with 0018's F2.
- **(b) Indices prune constructors only**: no layout depends on an
  index's value; `#Vect[3]` stays three cells without tags. *Costs*: the
  ruling's inline promise. *Buys*: no clones, no conversions.
- **(c) Convert at every boundary**: no clones; a `#Vect[3]` passed to
  `sum<n>` is re-packed into cells at each call. *Costs*: O(budget) per
  call, a static fact paid at run time (D10). *Buys*: smaller code.

**Q2. A runtime value in an index position.** `replicate : (n : Nat) ->
a -> Vect n a`, `MkT : (n : Nat) -> T n` and dependent pairs `(n ** Vect
n a)` put a quantity-ω value where D48's language has no term:
- **(a) Opaque** (D48 as written): sound; `replicate 3 x` is
  `#Vect[_]`, and a consumer at `#Vect[3]` pays a bounded conversion.
- **(b) Singleton link** (recommended, the Dependent ML form, *recalled*:
  Xi and Pfenning 1999): an ω binder that occurs in an index position is
  also an index binder, and its runtime value carries the link
  (`!idr.nat` indexed by the term, `nat` literals closed); a call passes
  the argument's term when known (a literal, or the caller's own linked
  binder) and `opaque` otherwise. *Costs*: `!idr.nat` gains an index
  parameter; every op producing a natural must say its result's term or
  `opaque`; the frontend's binder translation gains a case. *Buys*:
  `replicate 3 x` is `#Vect[3]`, specialized and inline; a dependent
  pair keeps the length its vector has; L16's open seam ("whether a
  runtime field may occur in an index term") closes.
