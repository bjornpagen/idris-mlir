<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
## N — One generator library and one primitive table, on both hosts, with no golden that records draw order

Findings: F15

Owner / exclusive writes: `harness/Gen.idr`, `harness/Prims.idr`, `harness/Fuzz.idr`, `harness/Sem.idr`, `harness/TwoLevels.idr`, `tests/fuzz/**`, `tests/two-levels/**`, `tests/programs/semantics/**`, `harness/lib/fuzz.sh`

Read first:
- Packet README §2 (all rules, above all "Two hosts, forever", "Brittle tests are deleted", "Encode the harness's invariants"), §3 F15, §4.7, §5 (Gen row), §6 (N row).
- `harness/Fuzz.idr` whole: `:57-91` (the type list, `Eq` by printed name, `intTys`, the bounds copy at `:83`), `:95` (the untyped `Expr`), `:117-141` (the LCG threaded through every case), `:150-234` (literal pools), `:255-265` (the libm list), `:267-445` (the generator; `TInt` listed twice in `oneOf TInt intTys` at `:312,372,406,438,474`), `:472-494` (a case's three renderings), `:531-559` (`program`, `programOf`). `:40-43` says the expected files depend on draw order.
- `harness/Sem.idr:28-120` (its `IntType`, the bounds copy at `:66`, the integer meaning: `pow2`, `modulo`, `wrap`, `euclid`, `quotient`, `remainder`, `bitwise`, `floorDiv`, `shifted`), `:152-166` (tables), `:199-215` (`tests`, `programOf`, `expectedOf`).
- `harness/TwoLevels.idr:52-67` (the bounds copy at `:59`), `:118-136` (the libm names), `:306-318`.
- `harness/Main.idr:200-216` (the four entry points you keep: `Sem.programOf`, `Sem.expectedOf`, `Fuzz.programOf`, `TwoLevels.programOf`; the file is X3's).
- `harness/lib/fuzz.sh` whole; `harness/lib/e2e.sh:30-100` (`e2e_io`) and `:131-157` (`sem_case`, the precedent for a fixture built in `$work` with a runner-made `expected-stdout`); `harness/lib/expect.sh:9-16` (`expect_holds`); `harness/lib/mlir.sh:37-41` (`dump_options`), `:103-119` (`step_module`); `harness/lib/compile.sh:13-18` (`compile_program`); `tools/compile.sh:42` (idris-mlir runs with `--no-prelude`).
- `tests/fuzz/seed-1/{run,expected,expected-runtime,expected-static}`, `tests/two-levels/terms/run`, `tests/programs/semantics/prim-int-arith-0/run`, `tests/programs/linear/leet-reverse-list/{mlir.expect,packages,expected}`.
- `third_party/Idris2/src/Core/Primitives.idr:660-736` (`allPrimitives`: the shape the table is generated in).
- `compiler/src/IdrisMLIR/Registry/Recognized.idr:61-83` (Nat `plus`, `minus`, `compareNat`, `lt`… are word operations in idris-mlir) and `:131-161` (`Data.Fin.natToFinLT` is the identity); `libs/mlir-array/Linear/Vec.idr:93-107` (the `choose`/`ltOpReflectsLT`/`natToFinLT` idiom both hosts compile in O(1)).
- `foreign/idr/include/idr/Transforms/Expect.h:137-162` (`reuses-in-place`, `counts-nothing`, `tests-nothing`).
- References to read, never copy (owner decision O1, clean room): Mojo `third_party/modular/Mojo/stdlib/std/testing/prop/random.mojo:31-49` (every draw a recorded word, shrinking on the history), matklad's "Generate All the Things" (the odometer), Hypothesis (shortlex shrinking on the choice sequence).

Permitted outcome:
- Mandatory: `harness/Gen.idr` and `harness/Prims.idr` as fixed below; Fuzz rebuilt on them (typed expression, explicit weights, swarm, per-case seeds, a fourth rendering from stdin, the thread count drawn per seed, the integer model, the folded check, shrinking of a failing case); the seed goldens deleted and replaced as fixed below; Sem and TwoLevels on Prims with byte-identical output; Sem's directories cross-checked against its tests; the `tests/fuzz-two-hosts/` test that compiles the five modules with idris-mlir and compares what both hosts generate.
- Optional: more compile-time `Refl` checks in Gen than the five fixed below, when they reduce.
- Later (do not start): the typed program generator over the subset (README §9); documented-crash cases in Fuzz (the `tests/programs/semantics/crash-*` fixtures hold them); the fate of `tests/two-levels/terms/expected-*` (report it, see Handoff).

Fixed decisions:
- Two hosts. Every one of the five modules must check with the stock Idris on Chez (the runner) and compile with idris-mlir (the `two-hosts` test). So each starts its imports with `import Prelude` (idris-mlir runs with `--no-prelude`, `tools/compile.sh:42`); imports only `base` modules (not `contrib`, not `test`, not `libs/`: the runner's prefix has no `mlir-linear`, `Makefile:267-275`, and every runtime primitive in `libs/` is a bodiless `%extern`, `libs/mlir-linear/Linear/String/Iterator.idr:36-37`, `libs/mlir-array/Array/Core.idr:121-247`, which Chez's code generator refuses to compile, `third_party/Idris2/src/Compiler/Scheme/Common.idr:659-660`, so a runner that reached one could not be built); reaches no `%extern` through any import; uses no `assert_total`, `assert_smaller`, `believe_me`, `really_believe_me`, `idris_crash`, `unsafePerformIO`, `%foreign`, `%extern`; does not call `Data.Fin.restrict` (its body is `believe_me`) or `Data.So.choose` where a `Refl` check must reduce (base exports it without its body). Linearity is `(1 _ : T)` binders and Builtin's `Res`/`(#)`; no `!*`. The tape is pure Idris linear data, the constructors of `Slots` and `Tape` below with quantity-1 fields, never `LArray`, `Array` or any other `%extern` buffer: the stock host runs it as ordinary data, and idris-mlir reuses its cells in place, which is where the linear performance comes from.
- `harness/Gen.idr`, `%default total`, exactly these exports (names, types, meanings are the contract §4.7 records):

```idris
module Gen
import Prelude
import Data.Bits
import Data.Fin
import Data.List
import Data.Nat
import Data.So
import Data.Vect

-- The tape: one linear buffer of slots, a slot per draw.
data Slots : Type where               -- private
  End : Slots
  Slot : (value : Nat) -> (bound : Nat) -> (1 rest : Slots) -> Slots
data Source = Seeded Bits64 | Replayed -- private
export
data Tape : Type where                -- abstract: MkTape is not exported
  MkTape : (source : Source) -> (1 done : Slots) -> (1 ahead : Slots) -> (overran : Bool) -> Tape

public export
record Gen a where
  constructor MkGen
  run : (1 _ : Tape) -> Res a (const Tape)
export Functor Gen
export Applicative Gen
export Monad Gen

export draw : (n : Nat) -> {auto 0 nonzero : IsSucc n} -> Gen (Fin n)
export oneOf : a -> List a -> Gen a            -- uniform over the head and the tail

public export weightSum : Vect n Nat -> Nat
public export
data Weights : Nat -> Type where
  MkWeights : (ws : Vect n Nat) -> {auto 0 nonzero : IsSucc (weightSum ws)} -> Weights n
export weightsOf : (ws : Vect n Nat) -> Maybe (Weights n)   -- Nothing when every weight is 0
export weighted : Weights n -> Gen (Fin n)
export swarm : Weights n -> Gen (Weights n)

public export gamma : Bits64                    -- 0x9E3779B97F4A7C15
public export mix : Bits64 -> Bits64            -- splitmix64's output function
public export caseSeed : Bits64 -> Nat -> Bits64

public export
record Drawn a where
  constructor MkDrawn
  value : a
  tape : List Nat        -- the values drawn, in order
  overran : Bool         -- a draw found no slot left
export seeded : (capacity : Nat) -> (seed : Bits64) -> Gen a -> Drawn a
export seededEach : (capacity : Nat) -> (seeds : List Bits64) -> Gen a -> List (a, Bool)
export replay : (tape : List Nat) -> Gen a -> Drawn a
public export
record Box a where
  constructor MkBox
  values : List a
  whole : Bool           -- every tape enumerated, within the limit, none overran
export exhaustive : (capacity : Nat) -> (limit : Nat) -> Gen a -> Box a

public export shortlex : List Nat -> List Nat -> Bool
export candidates : List Nat -> List (List Nat)
export shrink : (stillFails : List Nat -> Bool) -> List Nat -> List Nat

export checks : List (String, Bool)            -- Gen's own checks, run on both hosts
```

- A draw is one call of the private `step : (n : Nat) -> {auto 0 nonzero : IsSucc n} -> (1 _ : Tape) -> Res (Fin n) (const Tape)`; `draw n = MkGen (step n)`. `step` is not recursive: it matches `n` as `S k` (with `step Z {nonzero = ItIsSucc} _ impossible`) and the first slot ahead, moves that slot onto `done` with the value and `S k` written into it, and gives the tape back. Seeded: the state advances by `gamma`, the value is `integerToNat (mod (cast {to = Integer} (mix s')) (natToInteger (S k)))`. Replayed: the slot's own value, or `k` when that is not below `S k`. No slot ahead: `FZ`, and `overran` becomes `True`. The `Fin` is made by a private `belowSucc : (k : Nat) -> Nat -> Fin (S k)` as `case decide (v < S k) of Left below => natToFinLT v {prf = ltOpReflectsLT v (S k) below}; Right _ => natToFinLT k {prf = reflexive}`, with a private `decide : (b : Bool) -> Either (So b) (So (not b))` written in Gen (2 clauses). So a draw does O(1) work on both hosts and rebuilds exactly the cells it took apart.
- splitmix64 (Vigna 2015): `mix z = let z1 = xor z (shiftR z 30) * 0xBF58476D1CE4E5B9; z2 = xor z1 (shiftR z1 27) * 0x94D049BB133111EB in xor z2 (shiftR z2 31)`; a seeded tape's state starts at the seed and each draw adds `gamma` first. `caseSeed s i = mix (s + cast (S i) * gamma)`: output `i` of splitmix64 started at `s`, the same definition `harness/prop/prop.h` uses. Reference: from state 0 the first three outputs are `0xE220A8397B1DCDAF`, `0x6E789E6AA1B965F4`, `0x06C45D188009454F` (computed from the reference algorithm; a `checks` entry).
- One allocation per run: `seeded` makes `capacity` blank slots (`Slot 0 0`) once; `seededEach` makes them once and, between seeds, moves `done` back to `ahead` with one linear sweep (a private recursive `reverseOnto : (1 _ : Slots) -> (1 _ : Slots) -> Slots`) and resets `overran`; `replay` makes the slots from the list once; `exhaustive` makes `capacity` blank slots once and the odometer reuses them for every run.
- The odometer (`exhaustive`): run the generator on the slots in Replayed mode; then walk `done` from the last draw: a slot whose `value + 1` is not below its `bound` is zeroed (`Slot 0 0`) and kept aside; the first slot with `value + 1 < bound` is incremented; the next run's `ahead` is the older slots, the incremented one, the zeroed ones, then the unused ones, in draw order (linear sweeps only). When no slot can be incremented the enumeration is finished. The loop recurses on `limit` (structural); `whole = True` exactly when it finished within `limit` runs and no run overran.
- Weights: the floor is the type's nonzero total. `weighted (MkWeights ws)` draws `r` below `weightSum ws` and picks the option whose cumulative span holds `r` (a smaller draw picks an earlier option, so 0 picks the first option of nonzero weight); `weighted (MkWeights [] {nonzero = ItIsSucc}) impossible`. `swarm w`: first `keep <- weighted w`, then one `draw 2` per option; option `i` keeps its weight when `i == keep` or its draw is `FZ`, else 0; the result is built through `isItSucc (weightSum ws')` (`Yes` gives `MkWeights ws'`, `No` gives `w`, unreachable). So each weight is zeroed with probability ½, the kept option guarantees the floor, and the all-zero tape keeps every weight.
- Shrinking: `candidates t` are the passes in this order, each one left-to-right sweep over the positions: delete a span (span lengths: the powers of two from the largest not above `length t` down to 1), zero a span (same lengths; only spans holding a nonzero value), halve a draw (`v div 2`, for `v > 0`), decrement a draw (`v - 1`, for `v > 1`). Every candidate is strictly smaller than `t` in `shortlex` (length first, then lexicographic). `shrink stillFails t` keeps the first candidate that still fails and starts again from the first pass, until none does; it recurses on the structural bound `length t + sum t`, which every kept candidate lowers by at least 1, so the bound is a proof of termination and never the reason it stops: no pass budget.
- `checks` (each `(name, holds)`; both hosts print them, so they evaluate at run time): the three splitmix64 reference outputs; `replay` of a seeded case's tape gives the same value and tape (seeds 1, 2, 3, on a generator mixing `draw`, `weighted` and a bound that depends on an earlier draw); the odometer: `pair` gives 6 values and `whole`, `dep` gives `[0, 0, 1, 0, 1, 2]` and `whole`, `limit` 3 gives `whole = False`, capacity 1 gives `whole = False`; `weighted (MkWeights [2, 0, 1])` exhausted gives the options `[0, 0, 2]`; over `swarm (MkWeights [1, 1, 1])` exhausted, every option is zeroed in some result and kept in some; every candidate of three sample tapes is `shortlex`-smaller; `shrink (\t => sum t >= 10) [7, 0, 9, 4]` still fails and none of its candidates does; and `drawLoop`, a private recursive `drawLoop : (k : Nat) -> (n : Nat) -> {auto 0 _ : IsSucc n} -> Nat -> (1 _ : Tape) -> Res Nat (const Tape)` that sums `k` draws through `step`, gives the same sum seeded and replayed. `drawLoop` is the in-place witness the `two-hosts` test names.
- Compile-time checks in Gen (`0 name : … = …; name = Refl`), over the private generators `pair : Gen (Fin 3, Fin 2)` (`[| (draw 3, draw 2) |]`) and `dep : Gen Nat` (`do k <- draw 3; j <- draw (S (finToNat k)); pure (finToNat j)`), verified to reduce with the implementation above: `length (exhaustive 4 100 pair).values = 6`; `(exhaustive 4 100 dep).values = [0, 0, 1, 0, 1, 2]`; `(exhaustive 4 100 dep).whole = True`; `(exhaustive 4 3 dep).whole = False`; `(replay [7, 9] pair).value = (2, 1)` (both values past their bounds). Bits64 arithmetic and base's `div`, ranges and comprehensions do not reduce in types: those checks stay in `checks`.
- `harness/Prims.idr`, `%default total`, exactly these exports:

```idris
module Prims
import Prelude
import Data.Bits
import Data.List
import Data.String

public export
data Ty = TInt | TInt8 | TInt16 | TInt32 | TInt64 | TBits8 | TBits16 | TBits32 | TBits64
        | TInteger | TDouble | TChar | TString
public export tyName : Ty -> String            -- "Int", "Int8", ..., "Integer", "Double", "Char", "String"
public export tyIndex : Ty -> Nat              -- the position above
public export Eq Ty                            -- by tyIndex, never by printed name
public export fixedTys : List Ty               -- [TInt, TInt8, TInt16, TInt32, TInt64, TBits8, TBits16, TBits32, TBits64]
public export
record Width where
  constructor MkWidth
  bits : Nat
  signed : Bool
public export widthOf : Ty -> Maybe Width      -- Int: 64 bits, signed
public export bounds : Ty -> Maybe (Integer, Integer)   -- from widthOf; no table of numbers
public export
data IsInteger : Ty -> Type where              -- the ten integer types
  IInt : IsInteger TInt
  IInt8 : IsInteger TInt8
  IInt16 : IsInteger TInt16
  IInt32 : IsInteger TInt32
  IInt64 : IsInteger TInt64
  IBits8 : IsInteger TBits8
  IBits16 : IsInteger TBits16
  IBits32 : IsInteger TBits32
  IBits64 : IsInteger TBits64
  IInteger : IsInteger TInteger
-- The documented meaning of the integer primitives (moved here from Sem):
public export pow2 : Nat -> Integer
public export modulo : Integer -> Integer -> Integer
public export wrap : Width -> Integer -> Integer
public export euclid : Integer -> Integer -> (Integer, Integer)
public export quotient : Width -> Integer -> Integer -> Integer
public export remainder : Width -> Integer -> Integer -> Integer
public export bitwise : Width -> (Integer -> Integer -> Integer) -> Integer -> Integer -> Integer
public export floorDiv : Integer -> Integer -> Integer
public export shifted : Width -> (left : Bool) -> Integer -> Integer -> Integer
public export bigBitwise : (Integer -> Integer -> Integer) -> Integer -> Integer -> Integer
public export bigShifted : (left : Bool) -> Integer -> Integer -> Integer

public export
data Domain = Anything | NonZero | Finite | NonEmpty | IndexInto Nat | SmallShift
public export
data Family = Arith | Negate | DivMod | Bitwise | Shift | Compare | Cast | Text | DoubleFn
public export
record Prim where
  constructor MkPrim
  name : String             -- as a program writes it: "prim__add_Int", "prim__strLength", "prim__doubleExp"
  family : Family
  args : List (Ty, Domain)
  result : Ty
  host : Maybe String       -- why the value depends on the host: Just "libm", else Nothing
public export prims : List Prim
```

- `prims` is generated by comprehension in the order and shape of Idris's `allPrimitives` (`Core/Primitives.idr:680-736`), every primitive but `believe_me` and `crash`; no row is written by hand where a comprehension gives it. Domains are only documented preconditions, each named in a comment with the crash it avoids: `NonZero` for the divisor of `div`/`mod` on the ten integer types (idr-lower crashes on 0); `Finite` for the operand of a cast from Double to an integer type (idr-lower crashes on NaN and the infinities, `idris_rt.h:423-424,520-521`); `NonEmpty` for `prim__strHead`, `prim__strTail` and the string of `prim__strIndex`; `IndexInto 0` for `prim__strIndex`'s index (idr-lower checks `0 <= i < length`); `SmallShift` for the amount of `prim__shl_Integer`/`prim__shr_Integer` (a left shift past what any integer holds ends the process, `idris_rt.h:508-510`). Everything else is `Anything`: a cast from String is total (`idris_rt.h:469-483`), a cast to Char gives 0 for a non-scalar (`IdrScalarOps.td:74`), `prim__strSubstr` takes any `Int`s (`idris_rt.h:452-455`). `host = Just "libm"` for `prim__doubleExp`, `Log`, `Pow`, `Sin`, `Cos`, `Tan`, `ASin`, `ACos`, `ATan`; `Nothing` for every other, `Sqrt`, `Floor` and `Ceiling` included. `bigBitwise op a b` is two's complement: wrap both into `k` bits with `k` above both bit lengths plus 2, apply `op` to the non-negative representatives, read the result back as signed `k`-bit (the host's bitwise operations only ever see non-negative operands, Sem's precedent); `bigShifted` is Scheme's ash (`idris_rt.h:504-507`).
- Fuzz's typed expression (in `harness/Fuzz.idr`), well-typed by construction, its indices erased:

```idris
data Args : List (Ty, Domain) -> Type where
  Nil : Args []
  (::) : Expr t -> Args tds -> Args ((t, d) :: tds)
data Expr : Ty -> Type where
  IntLit : (t : Ty) -> {auto 0 isInt : IsInteger t} -> Integer -> Expr t   -- inside bounds t (TInteger: any)
  DoubleLit : (source : String) -> Expr TDouble    -- from the pool, e.g. "(-0.1)"
  CharLit : (source : String) -> Expr TChar        -- from the pool, e.g. "'\955'"
  StringLit : (source : String) -> Expr TString    -- from the pool, e.g. "\"h\233llo\""
  App : (p : Prim) -> Args p.args -> Expr p.result
  SData : (k : Expr TInt) -> Expr TInt -> Expr TDouble -> Expr TInt   -- the sdata helper
```
  In `SData`, `k` is always an `IntLit TInt` in [0, 2] (the existing `sdata` helper, `Fuzz.idr:336-339,509-510`). An argument whose domain is not `Anything` is a literal drawn from that domain's pool (generator invariant, as Fuzz has now). A leaf's stdin text is its value as a line: an integer in decimal without parentheses, a Double's source without parentheses, a Char's or a String's source unescaped (`\<decimal digits>` is one scalar; the pools never put a digit after an escape).
- Fuzz's command line, all through `Fuzz.programOf : List String -> Maybe String` (Main's call is unchanged):
  - `program SEED CASES PART FILE`, `FILE` one of `main` (Main.idr of cases 1 to CASES), `stdin` (the lines the program reads), `model` (one line `m<n> <value>` per modeled case); the cases are `seededEach caseCapacity (map (caseSeed seed) [1 .. CASES]) (genCase part)`, case `n` on `caseSeed seed n`, so each case is reproducible alone; `SEED` is any integer taken modulo 2^64.
  - `threads SEED`: one of 1, 3, 5, 13 (the thread counts of F20), drawn by `weighted (MkWeights [1, 1, 1, 1])` on `caseSeed seed 0`.
  - `tape SEED CASE PART`: case CASE's tape, values joined by `,`.
  - `replay TAPE PART FILE`: the one-case program (its case numbered 1) of a tape.
  - `shrink TAPE`: `Gen.candidates TAPE`, one per line, values joined by `,`.
  - `two-hosts`: `Fuzz.twoHosts`, below.
- Rendered program (Static and Runtime parts as now: Runtime's case types are `fixedTys ++ [TDouble, TChar, TString]`, no `TInteger` anywhere, a primitive is allowed when no argument or result is `TInteger` and its result is not `TString` unless it is `prim__strAppend`, `prim__strCons` or a cast to String from a fixed-width integer, Double or Char, and a `TString` argument of any other primitive is a literal; Static's case types are `[TInteger, TString, TInt, TDouble]`, every primitive). Per case `n`: the `c<n>` function (as now); `main` holds the case's `d<n>` line; a function `run<n> : IO ()` holds the `j<n>` line, the `r<n>` line (Runtime part only), then one `x<k> <- getLine` per leaf and the `s<n>` line, the expression with leaf `k` replaced by `x<k>` read through `prim__cast_String<T>` (integers, Double), `prim__strHead` (Char) or itself (String). `main` is the `d` lines, then `run1` … `run<CASES>`, then the barriers (as now). A case whose expression holds a primitive with `host /= Nothing` is labelled `L` (`jL<n>`, `rL<n>`, `sL<n>`) and has no `d` line and no model line. If any case overran its tape, the program's first line is `-- overran: case <n>`.
- Explicit weights, all in `harness/Fuzz.idr`, each with a comment saying why: uniform (all 1) over the case types of a part, the families of `Prims.Family` (per case `swarm` over them), the primitives eligible at a node, the thread counts, every literal pool; a node above the depth bound is a leaf with weight 1 against an application with weight 4 (the old generator's one in five, `Fuzz.idr:280-281`, kept); an integer literal is one of `lo`, `hi`, 0, 1, −1 (2 for an unsigned type), 7, ±100 with weight 1 each and a drawn value in `[lo, hi]` (one `draw` of `hi - lo + 1`) with weight 2 (`Fuzz.idr:153-167`, kept). No list repeats an element to weight it.
- `caseCapacity : Nat` is computed in Fuzz from its generator's own constants (the depth bound, the largest arity, the most draws one node makes, the draws a case makes before its expression), with the derivation in a comment; the overran line makes a wrong derivation a failure, never a silently distorted case.
- The model: a case whose every node is an integer literal, an integer arithmetic, negation, division (`NonZero` literal divisor), bitwise, shift, comparison (giving `Int` 1 or 0) or a cast between integer types is modeled by Prims' meaning (`wrap`, `quotient`/`remainder` on signed widths, `div`/`mod` on unsigned, `euclid` for Integer, `bitwise`/`bigBitwise`, `shifted`/`bigShifted`); nothing touching Double, Char, String or `SData` is modeled. The model line's value is printed as the program prints the case's type (decimal, `-` sign).
- The folded check: the property `folded=@Main.main` at step `idr-optimize` (`expect_holds` on `step_module idr-optimize`): no op left in any copy of `@Main.main` that has no memory effect, is not a call and is not a constant has only constants as operands. It is not in idr-expect today: E supplies it (Handoff). L cases have no `d` line, so no host-dependent op is in `main`; the `j`, `r`, `s` lines live in `run<n>`, whose operands come from calls and `getLine`.
- `fuzz SEED` (in `harness/lib/fuzz.sh`) prints exactly these lines per part, `runtime` then `static`, each `ok` or `failed` followed by its problems:
  `<part>: every build compiles, runs, exits 0 and writes nothing on stderr: ok`
  `<part>: each case prints one value, whoever computes it: ok`
  `<part>: every d line is folded: ok`
  `<part>: each case over integers prints its documented value: ok`
  The program is compiled with `--num-threads=<threads SEED>` and the dump options, run on its stdin file; agreement is over lines matching `^[djrs]L?[0-9]+ `; a `-- overran` first line is a compile-check problem. The first case that disagrees or misses its model is shrunk: `tape` gives its tape; loop: for each line of `shrink CURRENT`, build `replay CANDIDATE PART main|stdin|model`, compile (same thread count, no dumps), run, and if case 1 fails the same way, print `  | smaller failing tape: <candidate>`, make it current and start the candidate list again; when no candidate fails, print the current case's `c1` function and its lines. No attempt count: each kept candidate is strictly smaller (above), so the loop ends.
- The goldens: delete `tests/fuzz/seed-1/expected-runtime`, `expected-static`, `tests/fuzz/seed-2/expected-runtime`, `expected-static`. What replaces them is exactly the agreement of d/j/r/s, the folded check, and the integer model. Each seed's `expected` is the eight lines above after a first `NEEDS-ACCEPTANCE:` line: nothing in it depends on draw order. Both seed directories stay, `fuzz_cases=30` stays (its comment says it was the goldens' size, kept, the owner to confirm it compiles within the limits).
- Sem: `IntType` is replaced by `Ty` and `widthOf`; `types` by `fixedTys`; the meaning functions are imported from Prims. Every name and every byte of `Sem.programOf name` and `Sem.expectedOf name` stays as it is. New export `names : List String` (`map fst tests`). New test `tests/programs/semantics/sem-index/` (its name does not start with `prim-`): it compares `runtests --sem-names` (sorted) with the `prim-*` directories beside it (sorted) and says `every table chunk of harness/Sem.idr has a directory, and every prim- directory a chunk`, or the difference. The 72 directories are not touched.
- TwoLevels: `intTys`, `signed`, `bounds` and the libm list come from Prims (`map tyName fixedTys`, `widthOf`, `bounds`; the unary host-dependent Double primitives in `prims` order, which is Exp, Log, Sin, Cos, Tan, ASin, ACos, ATan; the reason `name ++ ": " ++ host`, so `"prim__doubleExp: libm"` as now; Sqrt, Floor, Ceiling as the non-host unary ones). Every byte `TwoLevels.programOf` prints stays as it is, so `tests/two-levels/terms/expected-*` stay valid.
- `tests/fuzz-two-hosts/`: `run`, `Main.idr` (`main = putStr Fuzz.twoHosts`, with `import Prelude`), `mlir.expect`, `packages` (`base`), `expected`. `Fuzz.twoHosts` is the lines `gen: <name>: ok` or `gen: <name>: failed` for each of `Gen.checks`, then sections, each a line `== <title>` and its text: `program 1 3 runtime main`, `program 1 3 runtime stdin`, `program 1 3 runtime model`, `program 1 3 static main`, `threads 1`, `tape 1 2 runtime`, `shrink <that tape>`, `sem prim-int-arith-0`, `two-levels primitives terms`, `two-levels prelude main`. The run builds `$work/two-hosts` from `Main.idr`, `mlir.expect`, `packages` and copies of `tests/{Gen,Prims,Fuzz,Sem,TwoLevels}.idr`, writes `runtests --fuzz-program two-hosts` into its `expected-stdout` (the stock host's text), says `stock host: Gen's checks: ok` (or `failed` with the failing `gen:` lines), then `e2e_io "$work/two-hosts"`, so idris-mlir compiles all five modules, and its program must print the stock host's text byte for byte. `mlir.expect`:
  `idr-rc: tests-nothing=@Gen.drawLoop counts-nothing=@Gen.drawLoop reuses-in-place=@Gen.drawLoop`
  `idr-rc: tests-nothing=@Gen.reverseOnto counts-nothing=@Gen.reverseOnto reuses-in-place=@Gen.reverseOnto`
  (a draw, and a tape's reset, take apart only exclusive cells, count nothing, and build every cell in the one they took: no copy). The run sets `step_limit=600` and `test_limit=900` before sourcing `testutils.sh`, each marked as debt to measure on the owner's build.

Inputs:
- README §4.7 and §2 as quoted above; owner decision O1 (clean room).
- Existing harness functions, called, never edited: `compile_program`, `run_ours`, `say`, `show`, `empty`, `dump_options`, `step_module`, `expect_holds`, `e2e_io`, `sem_case`, `$runtests`, `$work`, `$here`, `$root`.
- idr-expect properties `tests-nothing`, `counts-nothing`, `reuses-in-place` (exist, `Expect.h:137-152`) and `folded` (E supplies; declared in §4 by the coordinator).
- `harness/Main.idr`'s calls (X3's file): `Sem.programOf`, `Sem.expectedOf`, `Fuzz.programOf`, `TwoLevels.programOf`, and the new `Sem.names` behind `--sem-names`.

Outputs:
- `harness/Gen.idr` and `harness/Prims.idr` with the exports above: consumed by Fuzz, Sem, TwoLevels now and by README §9's generators later.
- `Fuzz.programOf` with the forms above: consumed by `harness/lib/fuzz.sh`, `tests/fuzz-two-hosts/run` and Main (X3). `Fuzz.twoHosts : String`: consumed by the two-hosts test.
- `Sem.names : List String`: consumed by Main's `--sem-names` (X3) and `sem-index/run`. `Sem.programOf`, `Sem.expectedOf`, `TwoLevels.programOf`: unchanged signatures and output, consumed by `sem_case` (X2) and `two_levels` (X3).

Implement:
1. Write `harness/Gen.idr` as fixed: the private `Slots`, `Source`, `decide`, `belowSucc`, `step`, `reverseOnto`, the odometer's advance, `drawLoop`; the exports; the five `Refl` checks; `checks`.
2. Write `harness/Prims.idr` as fixed; move the meaning functions from `Sem.idr:52-120` (same results), adding `bigBitwise` and `bigShifted`; generate `prims` by comprehension.
3. Rewrite `harness/Fuzz.idr` on Gen and Prims: `Expr`, `Args`; literal pools keyed by type and domain (the current pools, with negative, surrogate and past-U+10FFFF code points added to the pool of casts to Char, which give 0); the generator (per case: `swarm` over the families, the case type, the depth, then the expression; eligible primitives at a node are those of the node's type, the part, and a kept family, weighted through `weightsOf`, a leaf when none); renderings `d`, `j`, `r`, `s`; leaves and stdin text; the model; `caseCapacity`; `programOf` with every form; `twoHosts`.
4. Rewrite `harness/lib/fuzz.sh`: the thread count, the three generated files, compile with dumps, run on stdin, agreement, folded, model, the shrink loop, the eight report lines. Delete the expected-file comparison.
5. Delete the four goldens; rewrite both seeds' `expected` (first line `NEEDS-ACCEPTANCE: the goldens are gone; confirm the eight property lines hold for both seeds on both targets`); update the seeds' `run` comments.
6. Port `harness/Sem.idr` to Prims and add `names`; write `tests/programs/semantics/sem-index/{run,expected}`.
7. Port `harness/TwoLevels.idr` to Prims.
8. Write `tests/fuzz-two-hosts/{run,Main.idr,mlir.expect,packages,expected}`; `expected` is the run's lines: `stock host: Gen's checks: ok`, then the lines `e2e_io` prints for a fixture with an `mlir.expect` (as `tests/programs/linear/leet-reverse-list/expected` records them at HEAD), after a first `NEEDS-ACCEPTANCE:` line.
9. Check (this machine): copy the five modules, `harness/Main.idr`, and read-only copies of `harness/Lock.idr` and `harness/Runner.idr` (Main imports them) into a private directory and run `IDRIS2_PREFIX=$ROOT/.toolchain/idris2 $ROOT/.toolchain/idris2/bin/idris2 --build-dir <private>/build --check <Module>.idr` for each (Main last); grep the five modules for the forbidden names above (string literals in Fuzz, Sem and TwoLevels hold `prim__` text, which is fine).

Delete:
- `harness/Fuzz.idr:57-91` (its `Ty`, `tyName`, `Eq Ty` by name, `intTys`, `bounds`), `:95` (untyped `Expr`), `:117-141` (the LCG, `below`, `pick`, `oneOf` over `State Integer`), `:255-265` (`hostDependent`), and every `oneOf x (x :: …)` double listing.
- `harness/Sem.idr:28-70` (`IntType`, `types`, `int`, `pow2`, `modulo`, `wrap`, `bounds`) and the meaning functions now in Prims.
- `harness/TwoLevels.idr:52-67` and `:118-119`.
- `tests/fuzz/seed-1/expected-runtime`, `tests/fuzz/seed-1/expected-static`, `tests/fuzz/seed-2/expected-runtime`, `tests/fuzz/seed-2/expected-static`; `fuzz.sh`'s expected-file comparison.

NOT TO DO:
- Do not edit `harness/Main.idr`, `harness/harness.ipkg`, `harness/lib/two-levels.sh`, `harness/lib/e2e.sh`, `harness/lib/expect.sh`, `harness/lib/mlir.sh`, `harness/testutils.sh`, any `tests/programs/semantics/prim-*` directory, or idr-expect.
- Do not port idris2-hedgehog, Mojo's or Hypothesis's code; read them only.
- Do not import `Linear.Notation`, `Linear.List` or any `libs/` module, and do not use `Array`/`LArray` (`%extern` with no Chez implementation).
- Do not add the generated programs' text, a hash of it, or the drawn thread count to any `expected` file.
- Do not add an attempt count, time budget or retry to the shrink loop.
- Do not regenerate `tests/two-levels/terms/expected-*`, add crash cases to Fuzz, or merge the two parts.
- Do not test Gen with a C++ or shell reimplementation; Gen's checks are `checks` and the `Refl` checks.

Stop and return: when the five modules check on the stock host (step 9), the grep is clean, and every file above is written. Return the Handoff. If the `Refl` checks do not reduce with your implementation, move them into `checks` and say so; do not change the semantics to make them reduce.

Acceptance:
- `runtests --fuzz-program threads 1` prints one of `1`, `3`, `5`, `13`; `program 1 30 runtime main` printed twice is byte-identical; `tape 1 7 runtime` replayed with `replay <tape> runtime main` gives case 7's text as case 1.
- `tests/fuzz/seed-1` and `seed-2`: the transcript is exactly the eight lines (`expected` is those after its `NEEDS-ACCEPTANCE:` first line, which the owner removes on acceptance); no `expected-runtime`/`expected-static` remains.
- Discriminators (owner's build): a fold removed from one primitive's folder fails `every d line is folded`; a runtime operation giving a wrong integer fails the model line and prints a shrunk tape; a `Gen.step` that copies or allocates a slot fails `tests/fuzz-two-hosts`'s `mlir.expect` (a draw does not copy the tape); a construct idris-mlir refuses in any of the five modules fails its `compile: exit 0`; a host disagreement on Bits64 or on generation fails `stdout: as expected`; a 73rd Sem chunk without a directory fails `sem-index`.
- Gen imports nothing that reaches a `%extern`: the five modules import only `Prelude` and `base` modules, none of them `libs/` (reviewable by `grep -n '^import' tests/{Gen,Prims,Fuzz,Sem,TwoLevels}.idr`); the owner's `make runner` building `runtests` on Chez is the behavioural proof, since Chez refuses to compile an unknown external.
- Typecheck evidence on this machine: step 9 output for each module; the five `Refl` checks compile; `checks` and the `two-hosts` comparison are the owner's build.
- Only the owner's build shows: the fuzz, two-hosts, sem-index and 72 semantics tests passing, the two-levels test passing unchanged, and the run times behind `step_limit`/`test_limit`.

Tempting partial solution: a `State (List Nat)` generator that conses each draw onto an immutable list, or one LCG still threaded through all cases, with Prims reduced to a shared `bounds` function and the goldens re-recorded from a new build. It types, it runs, and it keeps the tests green, but acceptance rejects it: a draw then allocates (the `two-hosts` `mlir.expect` fails), cases are not reproducible alone (`replay` of `tape SEED CASE` would not give case CASE), a re-recorded golden still records draw order (rule §2), and nothing would show the `d` lines are folded.

Escalate if:
- E's handoff deletes `tests-nothing`, `counts-nothing` or `reuses-in-place`, or the coordinator does not give E the `folded` property (then the folded check has no mechanism inside N's writes).
- X3 changes `harness/Main.idr` so that any of the four entry points' types change, or `--sem-names` is not added.
- Idris's `allPrimitives` has a primitive whose meaning is not in `idris_rt.h` or the dialect's ODS (its domain cannot be stated): name it.
- A module cannot be both total and inside the subset without an escape hatch: name the function and the obligation.

Handoff: per parts/common.md (changed paths mapped to obligations, contracts supplied, consumer adaptations, hub text, checks run or NotRun, unresolved seams), plus:
- `harness/harness.ipkg` (coordinator): `modules = Fuzz, Gen, Lock, Prims, Runner, Sem, TwoLevels`.
- `harness/Main.idr` (X3, through the coordinator): add `["--sem-names"] => putStr (unlines Sem.names)` beside `--sem-program`; the usage lines for `--fuzz-program` become `runtests --fuzz-program program <seed> <cases> runtime|static main|stdin|model | threads <seed> | tape <seed> <case> runtime|static | replay <tape> runtime|static main|stdin|model | shrink <tape> | two-hosts`, and `runtests --sem-names`; the fuzz pool's description becomes "fuzz: closed expressions over every primitive, each written four ways, held to each other and to the integers' documented meaning; Gen and its users on both hosts".
- E (through the coordinator): the idr-expect property `folded=@f` as defined in Fixed decisions.
- The coordinator: `tests/fuzz-two-hosts/expected` records `e2e_io`'s universal lines as they are at HEAD; X3's collapse of those lines (O5) must rewrite it with the others. `tests/two-levels/terms/expected-*` are recorded program output, the class F15's goldens were in; no finding owns them.
