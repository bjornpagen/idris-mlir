# 08. The `idr` dialect: the contract

**Contract document.** Changes need the user's approval.

The `idr` dialect, together with a fixed set of upstream MLIR operations, is
the only interface between the Idris code and the C++ code (`GOAL-P6`):
- the Idris side (`Emit`) produces it as MLIR text;
- the C++ side (`idris-mlir-opt`, `idris-mlir-cc`) consumes it.

Each side is tested against this document on its own ([14-testing](14-testing.md)).

The dialect is defined in ODS (`foreign/idr/`), with real traits, folders and
interfaces, so that upstream MLIR passes can optimize it (D2).

## Module

- **IDR-MOD-1 (v0).** The input is one `builtin.module` with these
  attributes:
  - `idr.version = N : i64`: the contract version, which equals the profile
    version whose features the module uses (0, 1, 2 or 3). The C++ side
    rejects versions it does not implement.
  - `idr.entry = @<root>`: the symbol of the root function.
  - `idr.entry_kind = "int" | "io"`:
    - an `int` root takes no arguments and returns `i64` (`main : Int`);
    - an `io` root takes one `!idr.world` argument, and its result is
      discarded (`main : IO ()`, after arity raising).
  - Check: `idr-check-input`
  - Test: `tests/idr/check-input/*.mlir`
- **IDR-MOD-2 (v1).** `Emit` writes the input in MLIR's generic operation
  form (`"dialect.op"(operands) <{properties}> (regions) {attributes} :
  (types) -> types loc(...)`), which MLIR parses for every dialect. The
  custom syntax in this document is informative: it is how
  `idris-mlir-opt` prints the same operations. Every operation, attribute
  and type is as this document specifies, in either form.
  - Test: `tests/e2e/v0/shapes/mlir.check`, and every e2e fixture (the C++
    side parses what `Emit` writes)

## Types

- **IDR-TY-1 (v0).** `!idr.data<@T>` is a value of the data type declared by
  `idr.data @T`. Its parameter is a flat symbol reference. It MUST resolve to
  an `idr.data` op in the module.
- **IDR-TY-2 (v0).** `!idr.erased` is a quantity-0 value. It has no runtime
  representation (`LOW-ERASE-1`).
- **IDR-TY-4 (v1).** `!idr.str` is a static string (`SEM-STR-1`): a sequence
  of scalar values that lives in read-only data. Its only producer is
  `idr.str.lit`.
- **IDR-TY-5 (v1).** `!idr.world` is the IO world token. It has no runtime
  representation, and it orders the `idr.io` ops that consume and produce it
  (`IDR-WORLD-1`).
- **IDR-TY-3 (v0).** Builtin types allowed in the input:
  - `i8`, `i16`, `i32`, `i64` for the integer types. MLIR integers are
    signless; signedness lives in the operations (`IDR-IN-3`).
    - `Int8`/`Bits8` → `i8`
    - `Int16`/`Bits16` → `i16`
    - `Int32`/`Bits32` → `i32`
    - `Int`/`Int64`/`Bits64` → `i64`
    - `Char` → `i32`, always holding a scalar value (v1)
  - `f64` for `Double` (v2);
  - `i1`, only as the result of `arith.cmpi` or `arith.cmpf` and the
    condition of `cf.cond_br`. *Revised in v3:* `index` is no longer
    allowed; `idr.tag` returns `i64`.

## Data declarations

```mlir
idr.data @Prog.Shape {
  idr.ctor @Circle tag 0 (i64) {quantities = ["w"]}
  idr.ctor @Rect tag 1 (i64, i64) {quantities = ["w", "w"]}
  idr.ctor @Proven tag 2 (!idr.erased, i64) {quantities = ["0", "1"]}
} loc("Prog.Shape"("Prog.idr":6:1))
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
- **IDR-DATA-3 (v0).** Field types are `i8`–`i64`, `!idr.data<@U>` or
  `!idr.erased`, from v1 also `!idr.str` and `!idr.world`, and from v2
  `f64`.
- **IDR-DATA-4 (v0).** Runtime containment is acyclic. In the graph with an
  edge T → U whenever a field of T has type `!idr.data<@U>`, there is no
  cycle. This makes the heap-free property structural (`GOAL-P4`).
  - Check: the verifiers of `idr.data` and the module (`idr-check-input`)
  - Test: `tests/idr/verify/data-*.mlir`, including a rejected cycle
- **IDR-DATA-5 (v0).** Every `idr.data`, `idr.ctor` and `func.func` is
  located by a `NameLoc` holding its Idris full name around its source
  location (`IDR-LOC-1`): `loc("Prog.Shape"("Prog.idr":6:1))`, or
  `loc("Builtin.Unit")` where Idris has no source for the module. *Revised
  after v3*, when the name was an `idr.name` attribute: names are debug
  information, which MLIR passes keep and diagnostics print. No attribute
  holds a name, so the C++ side never receives one as data and cannot
  compare it ([17-registry](17-registry.md)); `idr-check-input` does not
  read locations.
  - Check: `Emit.dataDecl` and `Emit.function`, by construction
  - Test: `tests/e2e/v0/shapes/mlir.check`

## Operations

All `idr` ops have MLIR locations (`IDR-LOC-1`).

| Op | Syntax (informative) | Traits and effects | Folds |
| --- | --- | --- | --- |
| `idr.erased` | `%e = idr.erased : !idr.erased` | `Pure`, `ConstantLike` | always, to a unit attribute (so CSE merges them) |
| `idr.con` | `%v = idr.con @T::@C(%a, %b) : (i64, i64) -> !idr.data<@T>` | `Pure` | never |
| `idr.tag` | `%t = idr.tag %v : !idr.data<@T>` (result `i64`) | `Pure` | to `C`'s tag if `%v` comes from `idr.con @T::@C`; to `0` if `@T` has exactly one constructor |
| `idr.field` | `%x = idr.field %v[@C, 1] : !idr.data<@T> -> i64` | `Pure` | to operand `i` if `%v` comes from `idr.con @T::@C` |
| `idr.div` | `%q = idr.div signed %a, %b : i64` | see `IDR-EFF-1` | see `IDR-DIV-2` |
| `idr.mod` | `%r = idr.mod unsigned %a, %b : i8` | see `IDR-EFF-1` | see `IDR-DIV-2` |
| `idr.to_char` (v1) | `%c = idr.to_char signed %x : i64` (result `i32`) | `Pure` | when `%x` is a constant (`SEM-CHAR-3`) |
| `idr.to_int` (v2) | `%n = idr.to_int %x : i64` (operand `f64`) | see `IDR-EFF-1` | when `%x` is a finite constant (`SEM-DBL-4`) |
| `idr.double_head` (v3) | `%c = idr.double_head %x` (result `i32`) | `Pure` | never |
| `idr.crash` (v3) | `%v:2 = idr.crash "unhandled input for f" : T, U` | a write on the crash resource | never |
| `idr.str.lit` (v1) | `%s = idr.str.lit "hello\n" : !idr.str` | `Pure`, `ConstantLike` | always, to its string attribute |
| `idr.io.put_str` (v1) | `%w1 = idr.io.put_str %s, %w0` | `IDR-EFF-2` | never |
| `idr.io.put_char` (v1) | `%w1 = idr.io.put_char %c, %w0` | `IDR-EFF-2` | never |
| `idr.io.put_int` (v1) | `%w1 = idr.io.put_int signed %n, %w0 : i64` | `IDR-EFF-2` | never |
| `idr.io.put_double` (v2) | `%w1 = idr.io.put_double %x, %w0` | `IDR-EFF-2` | never |
| `idr.io.get_char` (v1) | `%c, %w1 = idr.io.get_char %w0` | `IDR-EFF-2` | never |
| `idr.io.get_byte` (v3) | `%c, %w1 = idr.io.get_byte %w0` | `IDR-EFF-2` | never |
| `idr.io.exit` (v1) | `%w1 = idr.io.exit %code, %w0` | `IDR-EFF-2` | never |

- **IDR-CON-1 (v0).** `idr.con @T::@C(operands)` builds constructor `C` of `T`.
  There is one operand per field, of that field's type, including
  `!idr.erased` operands. The result type is `!idr.data<@T>`.
- **IDR-TAG-1 (v0).** `idr.tag %v` returns the tag of `%v`'s constructor as an
  `i64` (*revised in v3*: it was an `index`, for `scf.index_switch`).
- **IDR-FIELD-1 (v0).** `idr.field %v[@C, i]` returns field `i` of `%v`. Its
  result type is that field's type.
  - If `%v` was not built with `C`, the result is unspecified (like
    `ub.poison`), but the op never traps. So it is safe to speculate.
- **IDR-DIV-1 (v0).** `idr.div` and `idr.mod` implement `prim__div_T` and
  `prim__mod_T` exactly (`SEM-INT-3`, `SEM-INT-4`). The keyword `signed` or
  `unsigned` selects the semantics. The operands and the result have the
  same integer type.
- **IDR-DIV-2 (v0).** `idr.div` and `idr.mod` fold only when:
  - both operands are constants and the divisor is not zero: the result is
    computed per `SEM-INT-3`;
  - the divisor is the constant 1: `div` gives the dividend, `mod` gives 0.
- **IDR-EFF-1 (v0).** `idr.div` and `idr.mod` have no memory effects exactly
  when the divisor is a constant other than zero. Otherwise they have a
  write effect on the dialect's crash resource (`idr::CrashResource`). They
  implement `ConditionallySpeculatable` the same way.
  - This is what makes upstream DCE, CSE and code motion respect
    `SEM-EVAL-4`.
  - From v2 the same holds for `idr.to_int`, with "a finite constant
    operand" in place of "a divisor other than zero".
  - Test: `tests/idr/effects/div-*.mlir`, checking that a dead division by
    an unknown divisor survives `canonicalize` and `remove-dead-values`, and
    that a dead division by 7 does not.

- **IDR-CHAR-1 (v1).** `idr.to_char` implements `prim__cast_TChar`: the
  integer's value if it is a scalar value, and `0` otherwise. The keyword
  says how to read the operand's bits (`signed` or `unsigned`).
- **IDR-DBL-1 (v2).** `idr.to_int` implements `prim__cast_DoubleT`: it
  truncates toward zero and wraps to the width of its result, and crashes
  when the operand is NaN or infinite (`SEM-DBL-4`). The same op serves
  signed and unsigned `T`, because wrapping does not depend on signedness.
  - Test: `tests/idr/fold/to-int.mlir`, `tests/idr/check-input/reject-v2.mlir`
- **IDR-DBL-2 (v2).** `idr.io.put_double` writes its operand as
  `prim__cast_DoubleString` would (`SEM-DBL-5`). It is the target of output
  fusion for `Double` (`ELIM-G-7`).
  - Test: `tests/idr/lower/double.mlir`
- **IDR-DBL-3 (v3).** `idr.double_head %x` is the first character of
  `prim__cast_DoubleString x` (`SEM-DBL-5`), as an `i32` scalar value:
  `-`, `+` (NaN and positive infinity), or a digit. It is `Pure`.
  - Test: `tests/idr/lower/double-head.mlir`
- **IDR-CRASH-1 (v3).** `idr.crash` ends the program with its message
  (`SEM-CRASH-2`). Its results, of any types, stand for the values that the
  `func.return` after it returns, so that the block is well typed; they are
  never produced.
  - Test: `tests/idr/lower/crash-op.mlir`, `tests/idr/check-input/reject-v3.mlir`
- **IDR-STR-1 (v1).** `idr.str.lit` holds its string as a `StringAttr` of UTF-8
  bytes. Two literals with equal bytes are equal values.
- **IDR-IO-1 (v1).** The `idr.io` ops implement the IO primitives
  (`PROF-IO-4`), and `SEM-IO-*` fixes their meaning:
  - `put_str` and `put_char` are the Prelude's `prim__putStr` and
    `prim__putChar`;
  - `get_char` and `exit` are `SEM-IO-3` and `SEM-IO-5`. No source
    primitive has produced them since `PROF-IO-1` was withdrawn, and they
    stay in the dialect; `exit`'s `%w1` is never produced at runtime;
  - `put_int` writes the decimal representation of its operand
    (`SEM-STR-2`), as `signed` or `unsigned`. It is the target of output
    fusion (`ELIM-G-7`).

  Each op consumes one world and produces the next.
- **IDR-IO-2 (v3).** `%c, %w1 = idr.io.get_byte %w0` is the Prelude's
  `getChar` (`SEM-IO-7`): one byte as an `i32`, or `255` at the end of
  input. It is an `idr.io` op (`IDR-EFF-2`).
  - Test: `tests/idr/lower/get-byte.mlir`, `tests/e2e/v3/prelude-input`
- **IDR-EFF-2 (v1).** Every `idr.io` op has read and write effects on the
  dialect's IO resource (`idr::IOResource`). So no upstream pass removes,
  duplicates, hoists or reorders them.
- **IDR-WORLD-1 (v1).** Every `!idr.world` value is used at most once on each
  control-flow path. A use is followed on its path by the rest of its block
  and by every block reachable from there without passing the world's
  definition, which defines a new world each time it is reached (a loop's
  block argument). The world passes between blocks only as block arguments,
  and between functions only as arguments and results. *Revised in v3* for
  control flow in blocks.
  - Check: the `idr-check-input` verifier
  - Test: `tests/idr/verify/world-*.mlir`

## Upstream operations in the input

- **IDR-IN-1 (v0).** Besides `idr` ops, the input contains only these ops:
  - `builtin.module`;
  - `func.func`, `func.call`, `func.return`;
  - `arith.constant` (integer and `index`), `arith.addi`, `arith.subi`,
    `arith.muli`, `arith.andi`, `arith.ori`, `arith.xori`, `arith.cmpi`,
    `arith.extsi`, `arith.extui`, `arith.trunci`;
  - `cf.br`, `cf.cond_br`, `cf.switch` (*revised in v3*: `scf.if`,
    `scf.index_switch` and `scf.yield` are no longer allowed; control flow
    is blocks, as first-order Core's join points are);
  - from v3: `ub.poison` of a runtime type, for an atom that an alternative
    passes to a join point on behalf of another alternative of a choice
    (`ELIM-G-20`). It is never used: every use of a choice dispatches on its
    tag first.
  - from v2: `arith.constant` of `f64`, `arith.addf`, `arith.subf`,
    `arith.mulf`, `arith.divf`, `arith.negf`, `arith.cmpf`, `arith.sitofp`,
    `arith.uitofp`, and `math.exp`, `math.log`, `math.powf`, `math.sin`,
    `math.cos`, `math.tan`, `math.asin`, `math.acos`, `math.atan`,
    `math.sqrt`, `math.floor`, `math.ceil`. An op on `f64` needs version 2.
  - Check: `idr-check-input`. Anything else is an internal error, because
    the frontend broke the contract. No symbol may be named `@main`, which
    `idr-lower` creates (`LOW-ENTRY-1`).
  - Test: `tests/idr/check-input/reject-*.mlir`
- **IDR-IN-2 (v0).** `arith` ops carry no overflow flags (`nsw`, `nuw`) and
  no `exact` flag. Wrapping is the semantics (`SEM-INT-2`). From v2, `arith`
  and `math` ops carry no fast-math flags (`SEM-DBL-2`).
- **IDR-IN-3 (v0).** The primitives map as follows:

  | Primitive | Contract |
  | --- | --- |
  | `add`, `sub`, `mul`, `and`, `or`, `xor` | `arith.addi`, `subi`, `muli`, `andi`, `ori`, `xori` |
  | `div`, `mod` | `idr.div` / `idr.mod`, `signed` for `Int`/`IntN`, `unsigned` for `BitsN` |
  | `lt` … `gt` | `arith.cmpi` with `slt`/`sle`/`eq`/`sge`/`sgt` for signed types and `ult`/`ule`/`eq`/`uge`/`ugt` for unsigned types, then `arith.extui` to `i64` (`SEM-INT-6`) |
  | cast, same width | no op (the value is reused) |
  | cast, narrowing | `arith.trunci` |
  | cast, widening | `arith.extsi` if the source type is signed, `arith.extui` if it is unsigned (`SEM-INT-7`) |
  | literal | `arith.constant` with the two's complement bit pattern of the value |
  | `Char` comparison (v1) | `arith.cmpi` with an unsigned predicate on `i32`, then `arith.extui` to `i64` |
  | cast `Char` → `T` (v1) | `arith.extui` or `arith.trunci` from `i32` |
  | cast `T` → `Char` (v1) | `idr.to_char` |
  | string literal (v1) | `idr.str.lit` |
  | `Double` literal (v2) | `arith.constant` of `f64`, written in Chez's shortest decimal, or as the hexadecimal bit pattern for NaN and the infinities |
  | `Double` `add` … `div`, `negate` (v2) | `arith.addf`, `subf`, `mulf`, `divf`, `negf` |
  | `Double` `lt` … `gt` (v2) | `arith.cmpf` with `olt`/`ole`/`oeq`/`oge`/`ogt`, then `arith.extui` to `i64` (`SEM-DBL-2`) |
  | `Double` functions (v2) | `math.exp`, `log`, `powf`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `sqrt`, `floor`, `ceil` |
  | cast `T` → `Double` (v2) | `arith.sitofp` if `T` is signed, `arith.uitofp` if it is unsigned |
  | cast `Double` → `T` (v2) | `idr.to_int` |
  | `%World` values (v1) | function arguments and results of type `!idr.world` |

## Functions

- **IDR-FN-1 (v0).** Each `Core` function becomes a `func.func private`, with:
  - one argument per Idris parameter, in Idris order, including erased
    parameters as `!idr.erased`;
  - on every argument, `idr.quantity = "0" | "1" | "w"`;
  - one or more results, of runtime types (*revised in v3*: exactly one
    before; a function may return several atoms, `CORE-INV-11`);
  - from v2, possibly `no_inline`, on a loop breaker (`OPT-PIPE-3`).
- **IDR-FN-2 (v0).** Symbol names are mangled from Idris full names:
  - characters outside `[A-Za-z0-9_.]`, including `$` itself, are written
    `$<decimal code point>$`, so the mapping is injective;
  - monomorphic instances are named `<name>[<arg>,…]` before mangling
    (`ELIM-MONO-4`);
  - every Idris full name has a namespace, so no mangled name can be `main`.

  No `func.func` in the input is public. The C entry point is created by
  lowering (`LOW-ENTRY-1`).
- **IDR-FN-3 (v0).** Calls are `func.call` with every argument, including
  `idr.erased` values in erased positions.

## Matching

- **IDR-MATCH-1 (v0).** A constructor match is `idr.tag` on the scrutinee,
  then `cf.switch` on the tag, with one case block per constructor
  alternative. In an alternative's block, fields are read with `idr.field`;
  only the fields the alternative uses need to be read. A match with one
  alternative that can be reached makes no switch: the alternative follows
  in the same block. What follows a match is a block the alternatives
  branch to, with the match's values as block arguments.
- **IDR-MATCH-2 (v0).** Alternatives Idris proved impossible (`Absurd` in
  `Core`, `CORE-INV-6`) are left out. If `Core` has a default alternative
  that is possible, it becomes the switch's default block. Otherwise the
  remaining alternatives cover every constructor that can occur, and the
  last one becomes the default block instead of a case. So no default
  block is ever unreachable, and no poison or `unreachable` is needed. A
  literal match (`IDR-MATCH-3`) is treated the same way.
- **IDR-MATCH-3 (v0).** An integer-literal match is a chain of `arith.cmpi eq`
  and `cf.cond_br`, in alternative order, ending in the default alternative.
- **IDR-MATCH-4 (v0).** `let` binds an SSA value. A quantity-0 `let` binds an
  `idr.erased` value.

## Locations

- **IDR-LOC-1 (v0).** Every op carries a `FileLineColLoc`: the Idris source
  file path as given to Idris, and the line and column of the `FC` start
  plus one, since Idris counts from 0 and MLIR from 1. A declaration of
  `IDR-DATA-5` carries it inside its `NameLoc`. Diagnostics from the C++
  side therefore point at Idris source.
  - Test: `tests/e2e/v0/locations` (FileCheck on `.mlir` with `--mlir-print-debuginfo`)

## Interfaces

- **IDR-IF-1 (v0).** The dialect implements `DialectInlinerInterface`: every
  `idr` op is legal to inline into any region. So the upstream `inline` pass
  works across our ops.
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
module attributes {idr.version = 0 : i64, idr.entry = @Prog.main} {
  idr.data @Prog.Shape {
    idr.ctor @Circle tag 0 (i64) {quantities = ["w"]}
    idr.ctor @Rect tag 1 (i64, i64) {quantities = ["w", "w"]}
  }
  func.func private @Prog.area(%s: !idr.data<@Prog.Shape> {idr.quantity = "w"}) -> i64 {
    %t = idr.tag %s : !idr.data<@Prog.Shape>
    cf.switch %t : i64, [default: ^rect, 0: ^circle]  // Rect: last alternative (IDR-MATCH-2)
  ^circle:
    %x = idr.field %s[@Circle, 0] : !idr.data<@Prog.Shape> -> i64
    %c3 = arith.constant 3 : i64
    %xx = arith.muli %x, %x : i64
    %a = arith.muli %c3, %xx : i64
    return %a : i64
  ^rect:
    %w = idr.field %s[@Rect, 0] : !idr.data<@Prog.Shape> -> i64
    %h = idr.field %s[@Rect, 1] : !idr.data<@Prog.Shape> -> i64
    %b = arith.muli %w, %h : i64
    return %b : i64
  }
  func.func private @Prog.keep(%w: !idr.erased {idr.quantity = "0"},
                               %v: i64 {idr.quantity = "w"}) -> i64 {
    return %v : i64
  }
  func.func private @Prog.main() -> i64 {
    %e = idr.erased : !idr.erased
    %c6 = arith.constant 6 : i64
    %c7 = arith.constant 7 : i64
    %s = idr.con @Prog.Shape::@Rect(%c6, %c7) : (i64, i64) -> !idr.data<@Prog.Shape>
    %a = func.call @Prog.area(%s) : (!idr.data<@Prog.Shape>) -> i64
    %r = func.call @Prog.keep(%e, %a) : (!idr.erased, i64) -> i64
    return %r : i64
  }
}
```

After `inline` and `canonicalize`:
1. `idr.tag` of the known `idr.con @Rect` folds to `1`.
2. The switch on a constant branches straight to its block, by upstream's
   `cf.switch` canonicalization.
3. The `idr.field` ops fold to `%c6` and `%c7`.
4. `main` becomes `return 42`.

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

After the guaranteed eliminations ([06](06-elimination.md)):
- `putStrLn "hello"` is folded at compile time to one literal, `"hello\n"`;
- `greet`'s append and cast are fused into three output ops;
- every lambda, `IO` wrapper and world-passing detail of `>>=` is gone.

The frontend emits the following. `IORes ()` is an ordinary monomorphic data
instance whose symbol is mangled from `PrimIO.IORes[Builtin.Unit]`
(`ELIM-MONO-4`, `IDR-FN-2`). Lowering flattens it to nothing, because `()`
and the world have no runtime representation.

```mlir
module attributes {idr.version = 1 : i64, idr.entry = @Main.main, idr.entry_kind = "io"} {
  idr.data @Builtin.Unit {
    idr.ctor @MkUnit tag 0 () {quantities = []}
  }
  idr.data @PrimIO.IORes$91$Builtin.Unit$93$ {
    idr.ctor @MkIORes tag 0 (!idr.data<@Builtin.Unit>, !idr.world) {quantities = ["w", "1"]}
  }
  func.func private @Main.greet(%n: i64 {idr.quantity = "w"},
                                %w0: !idr.world {idr.quantity = "1"})
      -> !idr.data<@PrimIO.IORes$91$Builtin.Unit$93$> {
    %s = idr.str.lit "n = " : !idr.str
    %w1 = idr.io.put_str %s, %w0
    %w2 = idr.io.put_int signed %n, %w1 : i64
    %nl = idr.str.lit "\n" : !idr.str
    %w3 = idr.io.put_str %nl, %w2
    %u = idr.con @Builtin.Unit::@MkUnit() : () -> !idr.data<@Builtin.Unit>
    %r = idr.con @PrimIO.IORes$91$Builtin.Unit$93$::@MkIORes(%u, %w3)
       : (!idr.data<@Builtin.Unit>, !idr.world) -> !idr.data<@PrimIO.IORes$91$Builtin.Unit$93$>
    return %r : !idr.data<@PrimIO.IORes$91$Builtin.Unit$93$>
  }
  func.func private @Main.main(%w0: !idr.world {idr.quantity = "1"})
      -> !idr.data<@PrimIO.IORes$91$Builtin.Unit$93$> {
    %s = idr.str.lit "hello\n" : !idr.str
    %w1 = idr.io.put_str %s, %w0
    %c42 = arith.constant 42 : i64
    %r = func.call @Main.greet(%c42, %w1)
       : (i64, !idr.world) -> !idr.data<@PrimIO.IORes$91$Builtin.Unit$93$>
    return %r : !idr.data<@PrimIO.IORes$91$Builtin.Unit$93$>
  }
}
```
