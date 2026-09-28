# 08. The `idr` dialect: the contract

**Contract document.** Changes need the user's approval.

The `idr` dialect, together with a fixed set of upstream MLIR dialects, is
the only interface between the Idris code and the C++ code (`GOAL-P6`):
- the Idris side (`Emit`) produces it as MLIR text;
- the C++ side (`idris-mlir-opt`, `idris-mlir-cc`) consumes it.

Each side is tested against this document on its own ([14-testing](14-testing.md)).

The dialect is defined in ODS (`foreign/idr/include/idr/IdrOps.td`), with
real traits, folders and interfaces, so that upstream MLIR passes can
optimize it (D2). Every fact about an op is declared there once, and the
C++ of the dialect and of every pass derives from it.

*Revised at the cutover:* the contract is higher-order. Closures, recursive
data (boxes), `Integer` (bigs) and strings built at runtime are values of
the dialect, and control flow is regions. Abstraction is removed inside
MLIR, by upstream passes and ours ([09](09-optimization.md)), not before
it. The contract version, `idr.entry`, `idr.entry_kind` and the pass
`idr-check-input` are gone: what that pass checked is now op, type and
attribute verifiers, which MLIR runs when `idris-mlir-cc` parses a module
and after every pass. A verifier failure is an internal error
(`DIAG-ICE-1`).

## Module and functions

```mlir
module attributes {idr.program} {
  idr.data @Main.Shape { ... }                 // declarations first
  func.func @"$36$idris$45$mlir.root"(%w: !idr.world {idr.quantity = "1"})
      -> !idr.data<@PrimIO.IORes$91$Builtin.Unit$93$> attributes {idr.total} { ... }
  func.func private @Main.area(...) -> f64 attributes {idr.total} { ... }
}
```

- **IDR-MOD-1.** *Withdrawn at the cutover:* the module carried the
  contract version `idr.version`, the root `idr.entry` and its kind
  `idr.entry_kind`, which `idr-check-input` checked. There is no contract
  version any more (the profile version, `PROF-GEN-4`, is another thing).
  The module carries the unit attribute `idr.program`, the root is its only
  public function, and its type is its kind (`IDR-FN-1`).
- **IDR-MOD-2 (v1).** `Emit` writes every op in its custom syntax, as this
  document shows it, and upstream ops in theirs (`arith.cmpi slt, %a, %b :
  i64`), never in the generic form. *Revised at the cutover:* before, it
  wrote the generic form, with hand-written predicate integers and segment
  sizes; the ops' own printers and parsers now own them.
  - A symbol that is not a bare identifier (one that starts with a letter
    or `_`) is quoted: a constructor mangled as `$58$$58$` is written
    `@"$58$$58$"`, and the IO root `@"$36$idris$45$mlir.root"`.
  - A constructor of no fields is matched and declared with an empty list:
    `case @Nil() {`, `idr.ctor @Nil tag 0 () {quantities = []}`.
  - Every op, attribute and type parses in both forms and prints back the
    same.
  - Test: `tests/idr/verify/roundtrip.mlir`, `tests/e2e/v0/shapes/mlir.check`,
    and every e2e fixture (the C++ side parses what `Emit` writes)
- **IDR-FN-1 (v0).** The functions:
  - *Revised at the cutover:* the root is the only public `func.func`, and
    every other function is private. The root of a `main : Int` program is
    its `main` (`@Prog.main`), of type `() -> i64`. The root of an IO
    program is the function `$idris-mlir.root`, which `Frontend.Main`
    writes as `unsafePerformIO main` in world-passing form (`FE-ENTRY-4`),
    of type `(!idr.world) -> !idr.data<@IORes…>`. The module's attribute
    verifier checks that exactly one function is public and that its type
    is one of these two.
  - Each parameter of the Idris function is one argument, in Idris order,
    including erased parameters as `!idr.erased`. Every argument carries
    `idr.quantity = "0" | "1" | "w"`, and `"0"` exactly on `!idr.erased`.
  - A function has one or more results, of any contract type.
  - A lambda or a `Delay` is a private function whose leading parameters are
    its captures, then its own parameter (none for a `Delay`).
  - A function's body is one block; control flow is regions (`IDR-MATCH-5`,
    `IDR-MATCH-6`).
  - Function attributes: `idr.total` (unit) when Idris reports the function
    terminating (`SEM-EVAL-6`), and `no_inline` on a loop breaker
    (`OPT-PIPE-3`), both written by `Emit`; `idr.effect` and `idr.may_crash`
    (`IDR-FACT-1`), which only `idr-effects` writes. Any other `idr.*`
    attribute is rejected.
  - Check: the dialect's attribute verifiers of the module (`idr.program`),
    of each function and of each argument
  - Test: `tests/idr/verify/module.mlir`, `tests/idr/verify/function.mlir`,
    `tests/e2e/v0/shapes/mlir.check`
- **IDR-FN-2 (v0).** Symbol names are mangled from Idris full names:
  - characters outside `[A-Za-z0-9_.]`, including `$` itself, are written
    `$<decimal code point>$`, so the mapping is injective;
  - monomorphic instances are named `<name>[<arg>,…]` before mangling
    (`ELIM-MONO-4`);
  - every Idris full name has a namespace, so no mangled name can be
    `main`, which lowering creates (`LOW-ENTRY-1`).
- **IDR-FN-3 (v0).** Calls are `func.call` with every argument, including
  erased values in erased positions.
- **IDR-FACT-1 (v3).** The facts about a function:
  - `idr.total`: Idris's totality checker reports it terminating
    (`Core.Termination.checkTotal` gives `IsTerminating`). `Emit` writes it,
    and a clone made by `idr-specialize` has it when its origin and every
    function named in its constant arguments have it.
  - `idr.effect = "effectful"`: the function reaches an `idr.io` op,
    through calls or through the functions of the closures it creates
    (a closure counts where it is created); otherwise `"pure"`.
  - `idr.may_crash`: the function reaches an op that may crash
    (`IDR-EFF-1`), in the same sense.
  - A call of anything but a `func.func` with a body is effectful and may
    crash.

  `idr-effects` computes the last two over the call graph, and runs again
  whenever clones and evaluation change it (`OPT-PIPE-5`). Upstream passes
  keep function attributes, and a stale `idr.effect` can only be too
  pessimistic: clones and evaluation remove reachability, never add it.
  - Check: the pass `idr-effects`; the function attribute verifier
  - Test: `tests/idr/effects/idr-effects.mlir`, `tests/idr/canon/unused-call.mlir`,
    `tests/idr/verify/function.mlir`

## Types

| type | meaning |
| --- | --- |
| `i8`, `i16`, `i32`, `i64` | the fixed-width integers (`Char` is `i32`) |
| `f64` | `Double` |
| `i1` | a condition: results of comparisons, scrutinees of `idr.match_lit` |
| `!idr.data<@T>` | a value of the unboxed sum `@T` |
| `!idr.box<@T>` | a value of the boxed (recursive) type `@T` |
| `!idr.fn<(A...) -> (R...)>` | a closure; `Lazy a` and `Inf a` are `!idr.fn<() -> (a)>` |
| `!idr.str` | a string (UTF-8) |
| `!idr.big` | an `Integer`, or a `Nat`-like value (non-negative) |
| `!idr.world` | the IO world token |
| `!idr.erased` | a quantity-0 value |

- **IDR-TY-1 (v0).** `!idr.data<@T>` is a value of the data type declared
  by `idr.data @T` without `box`. Its parameter is a flat symbol reference,
  which MUST resolve to an `idr.data` op in the module.
- **IDR-TY-2 (v0).** `!idr.erased` is a quantity-0 value. It has no runtime
  representation (`LOW-ERASE-1`).
- **IDR-TY-3 (v0).** The builtin types allowed:
  - `i8`, `i16`, `i32`, `i64` for the integer types. MLIR integers are
    signless; signedness lives in the operations (`IDR-IN-3`).
    - `Int8`/`Bits8` → `i8`
    - `Int16`/`Bits16` → `i16`
    - `Int32`/`Bits32` → `i32`
    - `Int`/`Int64`/`Bits64` → `i64`
    - `Char` → `i32`, always holding a scalar value (v1)
  - `f64` for `Double` (v2);
  - `i1`, only as the result of a comparison (`arith.cmpi`, `arith.cmpf`,
    `idr.str.cmp`, `idr.big.cmp`) and where such a result is used: an
    `arith.extui` to `i64`, or the scrutinee of an `idr.match_lit`.
    *Revised in v3:* `index` is not allowed; `idr.tag` returns `i64`.
- **IDR-TY-4 (v1).** `!idr.str` is a string (`SEM-STR-1`): a sequence of
  scalar values, as UTF-8. *Revised at the cutover:* it is any string, not
  only a literal; a string built at runtime allocates (`IDR-STR-2`), and
  the heap-free profile limits where one may exist (`PROF-HEAP-3`).
- **IDR-TY-5 (v1).** `!idr.world` is the IO world token. It has no runtime
  representation, and it orders the `idr.io` ops that consume and produce it
  (`IDR-WORLD-1`).
- **IDR-TY-6 (v3).** `!idr.box<@T>` is a value of the data type declared by
  `idr.data @T box`. A value of a boxed type is `!idr.box`, and of any
  other `!idr.data`; the verifiers reject the wrong one.
  - Test: `tests/idr/verify/module.mlir`, `tests/idr/verify/roundtrip.mlir`
- **IDR-TY-7 (v3).** `!idr.fn<(A...) -> (R...)>` is a closure taking the
  arguments `A...` and returning the results `R...`. Both lists are always
  parenthesized. `Lazy a` and `Inf a` are `!idr.fn<() -> (a)>`: a closure of
  no arguments, forced by applying it (`SEM-LAZY-1`).
  - Test: `tests/idr/verify/roundtrip.mlir`
- **IDR-TY-8 (v3).** `!idr.big` is an integer of any size: `Integer`, or a
  `Nat`-like type (`IDR-IN-3`), whose values are non-negative.
  - Test: `tests/idr/verify/roundtrip.mlir`

## Data declarations

```mlir
idr.data @Main.Shape {
  idr.ctor @Circle tag 0 (f64) {quantities = ["w"]}
  idr.ctor @Rect tag 1 (f64, f64) {quantities = ["w", "w"]}
  idr.ctor @Proven tag 2 (!idr.erased, i64) {quantities = ["0", "1"]}
} loc("Main.Shape"("Main.idr":6:1))
idr.data @Prelude.Basics.List$91$Int$93$ box {
  idr.ctor @Nil tag 0 () {quantities = []}
  idr.ctor @"$58$$58$" tag 1 (i64, !idr.box<@Prelude.Basics.List$91$Int$93$>) {quantities = ["w", "w"]}
}
```

- **IDR-DATA-1 (v0).** `idr.data` declares a symbol and is a symbol table.
  - It is a direct child of the module, with one region of one block and no
    terminator.
  - It contains only `idr.ctor` ops.
  - It keeps the default public visibility, so `symbol-dce` never removes it.
    `idr-lower` erases it.
- **IDR-DATA-2 (v0).** `idr.ctor @C tag N (field types) {quantities = [...]}`
  declares a constructor:
  - Tags are `0..n-1`, in declaration order.
  - Constructor names are unique within their `idr.data`.
  - `quantities` has one entry per field (`"0"`, `"1"` or `"w"`). The entry
    is `"0"` exactly when the field type is `!idr.erased`.
- **IDR-DATA-3 (v0).** A field has any contract type but `i1`: the integer
  types, `!idr.data<@U>` and `!idr.erased`; from v1 also `!idr.str` and
  `!idr.world`; from v2 `f64`. *Revised at the cutover:* also
  `!idr.box<@U>`, `!idr.fn<...>` and `!idr.big`.
- **IDR-DATA-4 (v0).** *Revised at the cutover:* containment through
  unboxed sums is acyclic. In the graph with an edge T → U whenever a field
  of T has type `!idr.data<@U>`, there is no cycle; every cycle of the
  program's types passes through a `!idr.box`, whose value is a pointer.
  `Emit` declares a data instance `box` exactly when its containment is
  cyclic, so an unboxed sum has a finite layout (`LOW-DATA-1`).
  - Check: the module's attribute verifier (`idr.program`)
  - Test: `tests/idr/verify/module.mlir`, including a rejected cycle
- **IDR-DATA-5 (v0).** Every `idr.data`, `idr.ctor` and `func.func` is
  located by a `NameLoc` holding its Idris full name around its source
  location (`IDR-LOC-1`): `loc("Prog.Shape"("Prog.idr":6:1))`, or
  `loc("Builtin.Unit")` where Idris has no source for the module. *Revised
  after v3*, when the name was an `idr.name` attribute: names are debug
  information, which MLIR passes keep and diagnostics print. No attribute
  holds a name, so the C++ side never receives one as data and cannot
  compare it ([17-registry](17-registry.md)); no verifier reads locations.
  - Check: `Emit`, by construction
  - Test: `tests/e2e/v0/shapes/mlir.check`

A `Nat`-like type (one Idris flags `ZERO`/`SUCC`, `IDR-IN-3`) has no
declaration: its values are `!idr.big`.

## Constant attributes

| attribute | value |
| --- | --- |
| `#idr.con<@T::@C, [f1, f2]>` | a constructor of a sum or a box, with its fields as attributes, nested |
| `#idr.closure<@f, [c1, c2]>` | a closure of `@f` with its captures |
| `#idr.big<"-123">` | an integer of any size, in canonical decimal |
| `#idr.erased` | the erased value |
| `"bytes"` (`StringAttr`) | a string, as UTF-8 |
| `IntegerAttr`, `FloatAttr` | scalars |

- **IDR-CONST-1 (v3).** Values are attributes of these forms.
  - The dialect's attributes are untyped: a value's type is that of the
    `idr.constant` that holds it, or of the field or capture it fills.
  - A field or capture that is a scalar is an `IntegerAttr` or a
    `FloatAttr` of its type.
  - `#idr.big` holds canonical decimal: no leading zeros, no `+`, `-` only
    before a nonzero value, and `"0"` for zero. So equal integers are equal
    attributes.
  - A constructor's fields and a closure's captures agree in number and
    type with the declaration and the function, and every symbol resolves.
  - These are the values folders produce and consume, and the results of
    `idr-eval` (`ELIM-EVAL-1`). `#idr.hole` is internal to
    `idr-specialize`'s keys and never appears in a module.
  - Test: `tests/idr/verify/values.mlir`, `tests/idr/verify/generic.mlir`,
    `tests/idr/fold/data.mlir`, `tests/idr/fold/closure.mlir`
- **IDR-CONST-2 (v3).** `%v = idr.constant <value> : <type>` materializes a
  constructor, a closure, a string, a big or the erased value. It is
  `ConstantLike` and `Pure`, and it is the dialect's `materializeConstant`.
  It never holds an integer or a `Double`: those are `arith.constant`. It
  replaces `idr.str.lit` and `idr.erased`, so there is one constant op.
  - Test: `tests/idr/verify/values.mlir`, `tests/idr/verify/generic.mlir`,
    `tests/idr/fold/data.mlir`

## Operations

All `idr` ops have MLIR locations (`IDR-LOC-1`).

### Values

| Op | Syntax | Traits and effects | Folds |
| --- | --- | --- | --- |
| `idr.constant` | `%v = idr.constant #idr.con<@T::@C, [1, 2]> : !idr.data<@T>` | `Pure`, `ConstantLike` | always, to its value |
| `idr.con` | `%v = idr.con @T::@C(%a, %b) : (i64, f64) -> !idr.data<@T>` | `Pure`; allocates its result for a box | to a constant when every operand is one |
| `idr.field` | `%x = idr.field %v[@C, 1] : !idr.data<@T> -> f64` | `Pure` | to operand `i` of an `idr.con @T::@C`, or field `i` of a constant |
| `idr.tag` | `%t = idr.tag %v : !idr.data<@T>` (result `i64`) | `Pure` | to the tag of a known constructor; to `0` for a type of one constructor |

- **IDR-CON-1 (v0).** `idr.con @T::@C(operands)` builds constructor `C` of
  `T`. There is one operand per field, of that field's type, including
  `!idr.erased` operands. The result type is `!idr.data<@T>`, or, from the
  cutover, `!idr.box<@T>` for a boxed `T`. *Revised at the cutover:* a
  box's `idr.con` allocates its result (`MemAlloc`), so CSE never merges two
  cells; an unused one is still dead code, since MLIR ignores an op's
  allocation of its own result when deciding that.
  - Test: `tests/idr/verify/values.mlir`, `tests/idr/fold/data.mlir`,
    `tests/idr/effects/alloc.mlir`
- **IDR-TAG-1 (v0).** `idr.tag %v` returns the tag of `%v`'s constructor as
  an `i64` (*revised in v3*: it was an `index`), of a sum or a box.
- **IDR-FIELD-1 (v0).** `idr.field %v[@C, i]` returns field `i` of `%v`, of
  a sum or a box. Its result type is that field's type.
  - If `%v` was not built with `C`, the result is unspecified (like
    `ub.poison`), but the op never traps. So it is safe to speculate.

### Matches

```mlir
%r:2 = idr.match %v : !idr.data<@Main.Shape> -> (f64, !idr.world) {
case @Circle(%r: f64) {
  ...
  idr.yield %a, %w1 : f64, !idr.world
}
case @Rect(%w: f64, %h: f64) {
  ...
}
default {
  idr.crash "unhandled input for Main.f"
  ub.unreachable
}
}
%s = idr.match_lit %n : i64 -> (i64) {
case 0 { idr.yield %c1 : i64 }
case 1 { ... }
default { ... }
}
```

- **IDR-MATCH-1.** *Withdrawn at the cutover:* a constructor match was
  `idr.tag` and `cf.switch` over blocks. It is `idr.match` (`IDR-MATCH-5`),
  and `idr-lower` builds the switch (`LOW-MATCH-1`).
- **IDR-MATCH-2 (v0).** *Revised at the cutover:* alternatives Idris proved
  impossible (`FE-TR-4`) are left out, no default is invented for them, and
  none gets a region of its own. A match may therefore lack constructors
  and have no default: Idris proved the missing ones cannot occur
  (`SEM-DATA-2`). A case the definition does not cover is a region that
  crashes (`IDR-CRASH-1`).
  - Test: `tests/e2e/v0/absurd-body`, `tests/e2e/v0/enum-stepping`,
    `tests/e2e/v0/impossible-branch`
- **IDR-MATCH-3.** *Withdrawn at the cutover:* an integer-literal match was
  a chain of `arith.cmpi` and `cf.cond_br`. It is `idr.match_lit`
  (`IDR-MATCH-6`).
- **IDR-MATCH-4 (v0).** `let` binds an SSA value. A quantity-0 `let` binds
  an erased value (`idr.constant #idr.erased`).
- **IDR-MATCH-5 (v3).** `idr.match %v : T -> (R...) { case @C(%x: A, ...)
  {...} ... default {...} }` branches on the constructor of `%v`, a sum or
  a box.
  - There is one region per constructor it names, whose block arguments are
    that constructor's fields, in order, and an optional default region
    with no arguments. The constructors are distinct constructors of `T`.
  - Every region ends in `idr.yield` of the match's result types, or in
    `ub.unreachable` after `idr.crash`.
  - It implements `RegionBranchOpInterface` (control enters exactly one
    region, which returns to the match, as `scf.index_switch` does), and
    has `RecursiveMemoryEffects` and `RecursivelySpeculatable`.
    `idr.yield` is its `ReturnLike` terminator. So upstream `sccp`,
    `remove-dead-values`, `inline` and region simplification work on it.
  - Canonicalizations: a match whose taken region is known (the scrutinee
    is a constant or an `idr.con`, or one region is left) is replaced by
    that region; results no region needs are dropped; identical regions
    merge; and case-of-case moves a result's single consumer into every
    region when in one of them it meets a value it folds or canonicalizes
    against, moving nothing past an effect.
  - Test: `tests/idr/verify/match.mlir`, `tests/idr/verify/generic.mlir`,
    `tests/idr/canon/match-*.mlir`, `tests/idr/canon/case-of-case.mlir`
- **IDR-MATCH-6 (v3).** `idr.match_lit %n : T -> (R...) { case <key>
  {...} ... default {...} }` branches on the value of `%n`: an integer
  (`i1` to `i64`, characters as `i32`), a string or a big.
  - Keys are distinct literals of `T` (an `IntegerAttr` that fits, a
    `StringAttr`, an `#idr.big`), and a default region is required. Regions
    take no arguments. A literal match on `f64` is not allowed
    (`SEM-DBL-1`).
  - Its interfaces and canonicalizations are those of `idr.match`, plus: a
    string known not to be empty (`IDR-STR-2`) never takes the case `""`.
  - Test: `tests/idr/verify/match.mlir`, `tests/idr/canon/match-lit-string.mlir`,
    `tests/idr/canon/match-known.mlir`

### Closures

- **IDR-CLOS-1 (v3).** Closures:
  - `%c = idr.closure @f(%x, %y) : (i64, i64) -> !idr.fn<(i64) -> (i64)>`
    builds a closure of `@f` whose captures are its operands: they are
    `@f`'s leading parameters, and the rest of `@f`'s signature is the
    closure's type. It is `Pure`, and folds to an `#idr.closure` constant
    when every capture is a constant. A world is never captured: worlds
    pass only as arguments and results.
  - `%r = idr.apply %c(%a) : !idr.fn<(i64) -> (i64)>` applies a closure.
    It implements `CallOpInterface` with a value callee; its effects are
    unknown, so passes treat it as a call they cannot see into.
  - An `idr.apply` of an `idr.closure` or of a constant closure
    canonicalizes to `func.call @f(captures..., arguments...)`, as upstream
    turns `func.call_indirect` of a `func.constant` into a direct call;
    `inline` does the rest.
  - Test: `tests/idr/verify/closure.mlir`, `tests/idr/canon/apply.mlir`,
    `tests/idr/fold/closure.mlir`, `tests/idr/canon/upstream-passes.mlir`

### Crashes and loops

- **IDR-CRASH-1 (v3).** *Revised at the cutover:* `idr.crash "<message>"`
  ends the program with its message (`SEM-CRASH-2`), and is followed by
  `ub.unreachable`, which ends its region or function; it has no results.
  It may crash (`IDR-EFF-1`). A function whose body is a top-level crash is
  never inlined: the pinned inliner cannot handle the `ub.unreachable`
  after it (`PINS.md`: `inline-unreachable`).
  - Test: `tests/idr/lower/crash-op.mlir`, `tests/idr/effects/crash.mlir`,
    `tests/idr/canon/upstream-passes.mlir`
- `idr.may_loop` marks one iteration of a loop that may not terminate
  (`LOW-TAIL-4`). It writes the IO resource and a divergence resource of
  its own, so no pass deletes the loop or moves output across it. It is
  internal to the pipeline: `Emit` never writes it.

### Scalars

| Op | Syntax | Traits and effects | Folds |
| --- | --- | --- | --- |
| `idr.div` | `%q = idr.div signed %a, %b : i64` | see `IDR-EFF-1` | see `IDR-DIV-2` |
| `idr.mod` | `%r = idr.mod %a, %b : i8` (unsigned) | see `IDR-EFF-1` | see `IDR-DIV-2` |
| `idr.to_char` (v1) | `%c = idr.to_char signed %x : i64` (result `i32`) | `Pure` | when `%x` is a constant (`SEM-CHAR-3`) |
| `idr.to_int` (v2) | `%n = idr.to_int %x : i64` (operand `f64`) | see `IDR-EFF-1` | when `%x` is a finite constant (`SEM-DBL-4`) |
| `idr.double_head` (v3) | `%c = idr.double_head %x` (result `i32`) | `Pure` | on a constant, through the runtime |
| `idr.int_head` (v3) | `%c = idr.int_head signed %x : i64` (result `i32`) | `Pure` | on a constant, through the runtime |

The keyword `signed` says how an op reads its integer operand; its absence
means unsigned.

- **IDR-DIV-1 (v0).** `idr.div` and `idr.mod` implement `prim__div_T` and
  `prim__mod_T` exactly (`SEM-INT-3`, `SEM-INT-4`). The keyword selects the
  semantics. The operands and the result have the same integer type.
- **IDR-DIV-2 (v0).** `idr.div` and `idr.mod` fold only when:
  - both operands are constants and the divisor is not zero: the result is
    computed per `SEM-INT-3`;
  - the divisor is the constant 1: `div` gives the dividend, `mod` gives 0.
- **IDR-CHAR-1 (v1).** `idr.to_char` implements `prim__cast_TChar`: the
  integer's value if it is a scalar value, and `0` otherwise.
- **IDR-DBL-1 (v2).** `idr.to_int` implements `prim__cast_DoubleT`: it
  truncates toward zero and wraps to the width of its result, and crashes
  when the operand is NaN or infinite (`SEM-DBL-4`). The same op serves
  signed and unsigned `T`, because wrapping does not depend on signedness.
  - Test: `tests/idr/fold/to-int.mlir`, `tests/idr/effects/crash.mlir`
- **IDR-DBL-3 (v3).** `idr.double_head %x` is the first character of
  `prim__cast_DoubleString x` (`SEM-DBL-5`), as an `i32` scalar value:
  `-`, `+` (NaN and positive infinity), or a digit. `idr.int_head` is the
  same for the decimal text of an integer (`-` or a digit). Both are
  `Pure`, and are what `idr.str.head` of a shown number canonicalizes to.
  - Test: `tests/idr/lower/double-head.mlir`, `tests/idr/canon/head.mlir`

### Strings (`!idr.str`)

| Op | Result | Effects |
| --- | --- | --- |
| `idr.str.append %a, %b` | the concatenation | allocates |
| `idr.str.cons %c, %s` | `%c` before `%s` | allocates |
| `idr.str.from_char %c` | the one-character string | allocates |
| `idr.str.show signed %x : i64`, `idr.str.show %x : i8`, `idr.str.show %x : f64` | the text `prim__cast_TString` gives | allocates |
| `idr.str.substr %s, %start, %len` | at most `%len` characters from `%start` | allocates |
| `idr.str.reverse %s` | the characters in reverse order | allocates |
| `idr.str.tail %s` | `%s` without its first character | allocates; may crash (on `""`) |
| `idr.str.length %s` | the number of characters, `i64` | `Pure` |
| `idr.str.index %s, %i` | the character at `%i`, `i32` | may crash (out of range) |
| `idr.str.head %s` | the first character, `i32` | may crash (on `""`) |
| `idr.str.cmp lt %a, %b` (`eq`, `lt`, `lte`, `gt`, `gte`) | `i1` | `Pure` |
| `idr.str.to_int signed %s : i64` | the string read as an integer | `Pure` |
| `idr.str.to_double %s` | the string read as a `Double` | `Pure` |

- **IDR-STR-1 (v1).** *Revised at the cutover:* a string literal is an
  `idr.constant` holding a `StringAttr` of its UTF-8 bytes (the op
  `idr.str.lit` is gone). Two strings with equal bytes are equal values.
- **IDR-STR-2 (v3).** The string ops implement the `String` primitives
  (`SEM-STR-*`, `IDR-IN-3`), with the effects of the table:
  - every op that builds a new string allocates its result (`MemAlloc`),
    so it is never merged with another or speculated, and an unused one is
    dead code unless it may crash;
  - `idr.str.head`, `idr.str.tail` and `idr.str.index` may crash
    (`IDR-EFF-1`), except where the operands rule it out: `head` and
    `tail` of a string known not to be empty (a non-empty constant, the
    result of `cons`, `from_char`, `show` or `idr.big.show`, or an `append`
    with such a side), and `index` of a constant string at a constant
    index in range;
  - `idr.str.length` has a known range (`IDR-RANGE-1`);
  - canonicalizations: output fusion on `idr.io.put_str` (`IDR-IO-1`), and
    `idr.str.head` of `cons c s` is `c`, of a shown integer `idr.int_head`,
    and of a shown `Double` `idr.double_head`;
  - every op folds on constant operands, through the same runtime function
    it lowers to (`LOW-RT-1`), except where it would crash.
  - Test: `tests/idr/verify/ops.mlir`, `tests/idr/effects/alloc.mlir`,
    `tests/idr/effects/crash.mlir`, `tests/idr/canon/head.mlir`,
    `tests/idr/fold/range.mlir`

### Bigs (`!idr.big`)

| Op | Result | Effects |
| --- | --- | --- |
| `idr.big.add`, `sub`, `mul`, `and`, `or`, `xor` `%a, %b` | the arithmetic or bitwise result | allocates |
| `idr.big.div`, `idr.big.mod` `%a, %b` | `Integer`'s `div` and `mod` | allocates; may crash (divisor zero) |
| `idr.big.neg %a` | the negation | allocates |
| `idr.big.cmp lt %a, %b` | `i1` | `Pure` |
| `idr.big.from_int signed %x : i64` | the integer as a big | allocates |
| `idr.big.to_int %b : i32` | the big wrapped to the width | `Pure` |
| `idr.big.from_double %d` | the `Double` truncated | allocates; may crash (not finite) |
| `idr.big.to_double %b` | the nearest `Double` | `Pure` |
| `idr.big.show %b` | the decimal text, a `!idr.str` | allocates |
| `idr.big.from_str %s` | the string read as an integer | allocates |

- **IDR-BIG-1 (v3).** The big ops implement the `Integer` primitives and
  the casts between `Integer` and the other types (`IDR-IN-3`), with the
  effects of the table. `div` and `mod` cannot crash when the divisor is a
  nonzero constant, and `from_double` when its operand is a finite
  constant. Every op folds on constant operands, through the runtime
  function it lowers to, except where it would crash.
  - Test: `tests/idr/verify/ops.mlir`, `tests/idr/effects/alloc.mlir`,
    `tests/idr/effects/crash.mlir`, `tests/idr/verify/roundtrip.mlir`

`Nat`-like values are bigs: `Z` is `idr.constant #idr.big<"0">`, `S x` is
`idr.big.add %x, %one`, and a match on one is an `idr.match_lit` with
`case #idr.big<"0">` and a default that computes the predecessor with
`idr.big.sub`.

### IO

| Op | Syntax |
| --- | --- |
| `idr.io.put_str` (v1) | `%w1 = idr.io.put_str %s, %w0` |
| `idr.io.put_char` (v1) | `%w1 = idr.io.put_char %c, %w0` |
| `idr.io.put_int` (v1) | `%w1 = idr.io.put_int signed %n, %w0 : i64` |
| `idr.io.put_double` (v2) | `%w1 = idr.io.put_double %x, %w0` |
| `idr.io.get_char` (v1) | `%c, %w1 = idr.io.get_char %w0` |
| `idr.io.get_byte` (v3) | `%c, %w1 = idr.io.get_byte %w0` |
| `idr.io.exit` (v1) | `%w1 = idr.io.exit %code, %w0` |

- **IDR-IO-1 (v1).** The `idr.io` ops implement the IO primitives
  (`PROF-IO-4`), and `SEM-IO-*` fixes their meaning:
  - `put_str` and `put_char` are the Prelude's `prim__putStr` and
    `prim__putChar`;
  - `get_char` and `exit` are `SEM-IO-3` and `SEM-IO-5`. No source
    primitive has produced them since `PROF-IO-1` was withdrawn, and they
    stay in the dialect; `exit`'s `%w1` is never produced at runtime;
  - `put_int` writes the decimal representation of its operand
    (`SEM-STR-2`), as `signed` or `unsigned`;
  - *Revised at the cutover:* output fusion is `idr.io.put_str`'s
    canonicalization (`ELIM-G-7`): `put_str` of `append a b` writes `a`
    then `b`; of `cons c s`, `put_char c` then `s`; of `from_char c`,
    `put_char c`; of an integer shown, `put_int`; and of a `Double` shown,
    `put_double`. Each keeps the world chain's order.

  Each op consumes one world and produces the next.
  - Test: `tests/idr/canon/output-fusion.mlir`, `tests/idr/effects/io.mlir`
- **IDR-DBL-2 (v2).** `idr.io.put_double` writes its operand as
  `prim__cast_DoubleString` would (`SEM-DBL-5`).
  - Test: `tests/idr/lower/double.mlir`, `tests/idr/canon/output-fusion.mlir`
- **IDR-IO-2 (v3).** `%c, %w1 = idr.io.get_byte %w0` is the Prelude's
  `getChar` (`SEM-IO-7`): one byte as an `i32`, or `255` at the end of
  input.
  - Test: `tests/idr/lower/get-byte.mlir`, `tests/e2e/v3/prelude-input`

## Effects

- **IDR-EFF-1 (v0).** An op that may crash has a write effect on the
  dialect's crash resource (`idr::CrashResource`) and, from the cutover,
  on its IO resource too (`idr::IOResource`), and is not speculatable.
  It has no memory effects, and is speculatable, exactly when its operands
  rule the crash out:
  - `idr.div` and `idr.mod`: the divisor is a constant other than zero;
  - `idr.to_int` (v2): the operand is a finite constant;
  - from the cutover, `idr.crash` always may crash, and `idr.str.head`,
    `idr.str.tail`, `idr.str.index`, `idr.big.div`, `idr.big.mod` and
    `idr.big.from_double` as `IDR-STR-2` and `IDR-BIG-1` say.

  This is what makes upstream DCE, CSE and code motion respect
  `SEM-EVAL-4`. *Revised at the cutover:* MLIR orders effects only on the
  same resource, so a crash also writes the IO resource: no pass may then
  move a crash across output, or output across a crash (`OPT-SAFE-1`).
  - Test: `tests/idr/effects/div.mlir`, `tests/idr/effects/crash.mlir`,
    checking that a dead division by an unknown divisor survives
    `canonicalize` and `remove-dead-values`, and that a dead division by 7
    does not.
- **IDR-EFF-2 (v1).** Every `idr.io` op has read and write effects on the
  dialect's IO resource. So no upstream pass removes, duplicates, hoists or
  reorders them.
  - Test: `tests/idr/effects/io.mlir`
- **IDR-WORLD-1 (v1).** Every `!idr.world` value is used at most once on
  each path. *Revised at the cutover* for regions:
  - the regions of a match are separate paths, of which one runs;
  - a region that may run repeatedly (a loop's) counts its uses twice, so a
    world from outside a loop is never used inside it;
  - a closure never captures a world: worlds pass only as arguments,
    results and block arguments.
  - Check: the function's attribute verifier, and `idr.closure`'s verifier
  - Test: `tests/idr/world/*.mlir`, `tests/idr/verify/closure.mlir`
- **IDR-RANGE-1 (v3).** `idr.tag` (`[0, n-1]` for `n` constructors),
  `idr.to_char`, `idr.int_head`, `idr.double_head` (scalar values) and
  `idr.str.length` (non-negative) implement `InferIntRangeInterface`, so
  upstream's integer range analysis and `int-range-optimizations` use them.
  - Test: `tests/idr/fold/range.mlir`

## The input's other dialects

- **IDR-IN-1 (v0).** *Revised at the cutover:* besides `idr`, the input
  contains ops of `builtin`, `func`, `arith`, `math` and `ub` only
  (`ub.unreachable` after a crash). `Emit` writes the ops of `IDR-IN-3`'s
  mapping and no other.
  - Check: `idris-mlir-cc` parses with a registry of exactly these six
    dialects, so an op of any other dialect fails to parse, which is an
    internal error (`DIAG-ICE-1`); passes load the dialects they need
    afterwards. `idr-check-input` and its op list are gone.
  - Test: `tests/compiler/cc-contract`, `tests/e2e/v0/literal-match`
- **IDR-IN-2 (v0).** `arith` ops carry no overflow flags (`nsw`, `nuw`) and
  no `exact` flag. Wrapping is the semantics (`SEM-INT-2`). From v2,
  `arith` and `math` ops carry no fast-math flags (`SEM-DBL-2`).
  - Check: `Emit`, by construction; the Emit test (`TEST-EMIT-1`)
- **IDR-IN-3 (v0).** The primitives map as follows:

  | Primitive | Contract |
  | --- | --- |
  | `add`, `sub`, `mul`, `and`, `or`, `xor` | `arith.addi`, `subi`, `muli`, `andi`, `ori`, `xori` |
  | `div`, `mod` | `idr.div` / `idr.mod`, `signed` for `Int`/`IntN`, unsigned for `BitsN` |
  | `lt` … `gt` | `arith.cmpi` with `slt`/`sle`/`eq`/`sge`/`sgt` for signed types and `ult`/`ule`/`eq`/`uge`/`ugt` for unsigned types, then `arith.extui` to `i64` (`SEM-INT-6`) |
  | cast, same width | no op (the value is reused) |
  | cast, narrowing | `arith.trunci` |
  | cast, widening | `arith.extsi` if the source type is signed, `arith.extui` if it is unsigned (`SEM-INT-7`) |
  | literal | `arith.constant` with the two's complement bit pattern of the value |
  | `Char` comparison (v1) | `arith.cmpi` with an unsigned predicate on `i32`, then `arith.extui` to `i64` |
  | cast `Char` → `T` (v1) | `arith.extui` or `arith.trunci` from `i32` |
  | cast `T` → `Char` (v1) | `idr.to_char` |
  | string literal (v1) | `idr.constant "…" : !idr.str` |
  | `Double` literal (v2) | `arith.constant` of `f64`, written in Chez's shortest decimal, or as the hexadecimal bit pattern for NaN and the infinities |
  | `Double` `add` … `div`, `negate` (v2) | `arith.addf`, `subf`, `mulf`, `divf`, `negf` |
  | `Double` `lt` … `gt` (v2) | `arith.cmpf` with `olt`/`ole`/`oeq`/`oge`/`ogt`, then `arith.extui` to `i64` (`SEM-DBL-2`) |
  | `Double` functions (v2) | `math.exp`, `log`, `powf`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `sqrt`, `floor`, `ceil` |
  | cast `T` → `Double` (v2) | `arith.sitofp` if `T` is signed, `arith.uitofp` if it is unsigned |
  | cast `Double` → `T` (v2) | `idr.to_int` |
  | `%World` values (v1) | function arguments and results of type `!idr.world` |
  | `String` primitives (cutover) | `idr.str.*`; a comparison is `idr.str.cmp`, then `arith.extui` to `i64` |
  | `Integer` primitives and literals (cutover) | `idr.big.*`; `idr.constant #idr.big<…>`; casts between `Integer` and the other types are `idr.big.from_*` and `idr.big.to_*` |
  | `Nat`-like types (cutover) | bigs, as shown under Bigs |
  | lambda, `Delay` (cutover) | a lifted private function and `idr.closure` of it |
  | application, `Force` (cutover) | `idr.apply` |
  | missing case (cutover) | `idr.crash`, `ub.unreachable` |

  A `Nat`-like type is one whose constructors Idris flags `ZERO` and `SUCC`
  (its `ConInfo`, which `Frontend.Translate` reads; `FE-IN-2`). This covers
  `Nat`, `Fin` (Idris skips erased arguments when it sets the flags) and
  any user type of the same shape.
  - Test: `tests/e2e/v0/literal-match`, the `SEM-*` fixtures

## Locations

- **IDR-LOC-1 (v0).** Every op carries a `FileLineColLoc`: the Idris source
  file path as given to Idris, and the line and column of the `FC` start
  plus one, since Idris counts from 0 and MLIR from 1. A declaration of
  `IDR-DATA-5` carries it inside its `NameLoc`. *Revised at the cutover:*
  code from a library module whose diagnostics are reported at the caller
  (the registry's *Report at caller* column) is located by
  `loc(fused<"library">[...])` around its own location, so a diagnostic
  from the C++ side can find the innermost location in user code
  (`DIAG-LOC-1`).
  - Test: `tests/e2e/v0/locations` (FileCheck on `.mlir` with
    `--mlir-print-debuginfo`)

## Interfaces

- **IDR-IF-1 (v0).** The dialect implements `DialectInlinerInterface`:
  every `idr` op is legal to inline into any region, except an `idr.crash`
  that ends a function's body (`IDR-CRASH-1`). So the upstream `inline`
  pass works across our ops, regions included.
  - Test: `tests/idr/canon/upstream-passes.mlir`, `tests/idr/canon/apply.mlir`
- **IDR-IF-2 (v0).** `idr` ops implement `OpAsmOpInterface` result naming
  where useful. This is informative and has no semantic effect.

## Example (informative)

```idris
data Shape = Circle Int | Rect Int Int

area : Shape -> Int
area (Circle r) = prim__mul_Int 3 (prim__mul_Int r r)
area (Rect w h) = prim__mul_Int w h

keep : (0 witness : Int) -> Int -> Int
keep witness v = v

main : Int
main = keep 99 (area (Rect 6 7))
```

```mlir
module attributes {idr.program} {
  idr.data @Prog.Shape {
    idr.ctor @Circle tag 0 (i64) {quantities = ["w"]}
    idr.ctor @Rect tag 1 (i64, i64) {quantities = ["w", "w"]}
  }
  func.func private @Prog.area(%s: !idr.data<@Prog.Shape> {idr.quantity = "w"}) -> i64
      attributes {idr.total} {
    %r = idr.match %s : !idr.data<@Prog.Shape> -> (i64) {
    case @Circle(%x: i64) {
      %c3 = arith.constant 3 : i64
      %xx = arith.muli %x, %x : i64
      %a = arith.muli %c3, %xx : i64
      idr.yield %a : i64
    }
    case @Rect(%w: i64, %h: i64) {
      %b = arith.muli %w, %h : i64
      idr.yield %b : i64
    }
    }
    return %r : i64
  }
  func.func private @Prog.keep(%w: !idr.erased {idr.quantity = "0"},
                               %v: i64 {idr.quantity = "w"}) -> i64
      attributes {idr.total} {
    return %v : i64
  }
  func.func @Prog.main() -> i64 attributes {idr.total} {
    %e = idr.constant #idr.erased : !idr.erased
    %c6 = arith.constant 6 : i64
    %c7 = arith.constant 7 : i64
    %s = idr.con @Prog.Shape::@Rect(%c6, %c7) : (i64, i64) -> !idr.data<@Prog.Shape>
    %a = func.call @Prog.area(%s) : (!idr.data<@Prog.Shape>) -> i64
    %r = func.call @Prog.keep(%e, %a) : (!idr.erased, i64) -> i64
    return %r : i64
  }
}
```

In the simplify loop ([09](09-optimization.md)), `inline` takes `area` and
`keep` into `main`; the `idr.con` of constants folds to a constant, the
match on it is replaced by its `@Rect` region, and `main` returns `42`.

## Example: hello world (v1, informative)

```idris
module Main
import Prelude

greet : Int -> IO ()
greet n = putStrLn ("n = " ++ prim__cast_IntString n)

main : IO ()
main = do putStrLn "hello"
          greet 42
```

`Emit` writes the Prelude's `putStrLn`, `>>=` and `IO` as they are: lifted
functions, closures and applications. The simplify loop inlines them,
turns each application of a known closure into a call, evaluates
`putStrLn "hello"`'s append (`idr-eval`, or the folder), and fuses
`greet`'s output. What reaches `idr-lower` is:

```mlir
func.func private @Main.greet(%n: i64 {idr.quantity = "w"},
                              %w0: !idr.world {idr.quantity = "1"})
    -> !idr.data<@PrimIO.IORes$91$Builtin.Unit$93$> {
  %s = idr.constant "n = " : !idr.str
  %w1 = idr.io.put_str %s, %w0
  %w2 = idr.io.put_int signed %n, %w1 : i64
  %nl = idr.constant "\0A" : !idr.str
  %w3 = idr.io.put_str %nl, %w2
  %u = idr.constant #idr.con<@Builtin.Unit::@MkUnit, []> : !idr.data<@Builtin.Unit>
  %r = idr.con @PrimIO.IORes$91$Builtin.Unit$93$::@MkIORes(%u, %w3)
     : (!idr.data<@Builtin.Unit>, !idr.world) -> !idr.data<@PrimIO.IORes$91$Builtin.Unit$93$>
  return %r : !idr.data<@PrimIO.IORes$91$Builtin.Unit$93$>
}
```

`IORes ()` is an ordinary monomorphic data instance whose symbol is mangled
from `PrimIO.IORes[Builtin.Unit]` (`ELIM-MONO-4`, `IDR-FN-2`). Lowering
flattens it to nothing, because `()` and the world have no runtime
representation.
