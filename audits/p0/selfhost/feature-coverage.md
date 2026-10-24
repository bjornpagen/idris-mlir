<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Self-host feature coverage (2026-10-23/24)

The question: which Idris constructs and library facilities our own
programs use (the frontend `compiler/src`, the checker `compiler/checker`,
the specification `compiler/spec` with specgen, the runner `harness/`,
knowngen `compiler/checker/known`) that no test under `tests/` exercises
through the frontend, and which of those the frontend does not compile, so
that self-hosting meets them only once INT-24's roots (S-1, S-2, R-UNIFY,
R-META, R-SPEC, R-PRAGMA, R-ESC-FIN) are gone.

HEAD at start 2c5007948 (`/tmp/selfhost-coverage/HEAD-start`); at finish
98cabc496. 140 commits landed in between; where one bears on a finding it
is named, and each finding says which build measured it.

## How

- Inventory (measured, `scripts/inventory.py`): every `.idr` of each
  program at 2c500794, block, line and doc comments and string contents
  removed, scanned for 120 forms (pragmas, declaration, clause and term
  forms, interfaces, records, laziness, IO and library names); imports
  listed per program; every prelude/base export our code names checked by
  name against the tests. Name matches are leads (the checker's own
  `strengthen`, `split`, `free` share base's names); each gap below was
  read at its use sites.
- Coverage: a test exercises a construct through the frontend when its
  source holds it and the test compiles it: `tests/*/` with a `Main.idr`
  and no `-- expect:` header, their `near/`, and scripted tests' compiled
  sources (`e2e_io`). Refusal tests are counted apart.
- Verdict: read from `Frontend/Profile.idr` and `Registry/`, then measured.
  Each probe is a minimal program written in the form our code uses
  (named in its header), type-checked by the stock Idris first, then run
  through `idris-mlir-front` (no flags but `--prefix`, `-o`) under `ulimit
  -t 3600`; `scripts/probe.sh` reads a refused module with INT-24's
  `refusals.py` (rule order checked against HEAD's `everyRule`).
- Builds. Start build (measured): a `git archive` export of 2c500794 at
  `/tmp/selfhost-coverage/src` (`.toolchain`, `third_party/{Idris2,
  fast_float,gmp,ryu,snmalloc}` linked; Idris2 at its gitlink 89ba32eb,
  clean), `make frontend PINS=: NCPU=6` (stock Idris: checker 208, spec,
  frontend, syntax-samples; status 0, 9312 s wall, 2155 s user, load 28 to
  48 throughout), `make prefix libs` (the frontend's prelude, base, linear,
  network, contrib, test and libs/; status 0, 187 s wall, 57 s user), and
  the checker into that prefix by the self-checker recipe by hand
  (`scripts/self-checker.sh`, status 0). Near-HEAD rerun (measured, not my
  build): the frontend binary L18aj built at 12:14 in `/tmp/l18aj/src`,
  whose `compiler/src` and `compiler/checker` sources equal 98cabc49 but
  four generated dialect files, and which predates 9a577ab1 (its
  `Profile.idr` and `Recognized.idr` were updated after the binary), over a
  prelude and base it installed into `/tmp/selfhost-coverage/prefix-near-
  head`. Probe CPU is rusage user+sys; every probe took 1.2 to 14.6 s and
  under 420 MiB.
- Limits: frontend only. "Compiles" means `idris-mlir-front` exited 0 and
  wrote a module holding no refusal; no module went through the C++
  pipeline (LLVM is not built here), none ran, and the C++ side's refusals
  (cycles, the in-place promise) are unseen.

## The gaps that would block self-hosting, ranked

Internal errors first, then refusals by the uses they cover.

### G1. Internal error: the growth check on a labelled reference in a world-passing monad

- Uses: the checker's context references, `data Ref : (l : label) -> Type
  -> Type` with `[search l]` (`compiler/checker/src/Core/Context/
  Context.idr:30-33`), read and written by `get`/`put`/`update`/`wrapRef`
  in the `Core` record over `PrimIO` (`Core/Core.idr:643-760`,
  `1069-1102`): 1910 `{auto _ : Ref ...}` parameters and about 894 `get/
  put/update <Label>` calls in the checker, 562 and about 28 in compiler/src (the
  frontend's own `Ref TState TS`: `Frontend/Translate/Errors.idr:123-124`
  `updateState f = core (update TState f)`, `Frontend/Profile.idr:132`).
  Every checker entry the frontend calls takes one.
- Reproducer: `/tmp/selfhost-coverage/min/ref-core-small/Main.idr` (49
  lines, below). First error, start build and near-HEAD alike (measured):
  `INTERNAL ERROR: Main:41:17--41:20: internal error: the growth check is
  unsound: Main.put[Int, Type, Main.Ctxt], requested in Main.update, has no
  bound at its argument 3` (status 1, 1.3 s).
- Narrowed (measured, both builds): the same reference over IO alone,
  `put` requested through a function that takes it on (`min/ref-plain-
  io`): compiles. With the probe's full Core (`probes/core-monad/
  Core.idr`): `update` alone (`min/ref-core-update`, `min/ref-no-wrap`),
  `wrapRef` without `catch` (`min/ref-wrap-no-catch`), with it
  (`runs/ref-auto`): the same internal error. The `Core` monad by itself,
  with `Catchable` and its named implementations, compiles
  (`runs/core-monad`).
- Reached in the real checker: by reading (the reproducer is
  `Core/Core.idr:1075-1086` and the record cut down). The package probe
  `probes-checker/checker-core` (`import Core.Core`, `-p
  idris-mlir-checker`) stops first at R-META `{P:w:3415}` on the start
  build, and the near-HEAD binary predates R-META's fix, so neither shows
  it.
- Tests: none (auto-runtime-argument passes an auto record and a
  `[uniqueSearch]` type in plain code; no test has a labelled reference or
  a reference read inside a user monad).
- Owner L16 (`Frontend/Growth/`); frontend fix, and a test of the shape.

```idris
module Main
import Data.IORef

record Core t where
  constructor MkCore
  runCore : PrimIO (Either String t)

coreLift : IO a -> Core a
coreLift op = MkCore (\w => case toPrim op w of
                              MkIORes a w' => MkIORes (Right a) w')

(>>=) : Core a -> (a -> Core b) -> Core b
(>>=) (MkCore act) f
    = MkCore (toPrim (io_bind (fromPrim act) (\r => fromPrim (case r of
                                                                 Left e => \w => MkIORes (Left e) w
                                                                 Right v => runCore (f v)))))

(>>) : Core () -> Core a -> Core a
ma >> mb = ma >>= const mb

coreRun : Core a -> (String -> IO b) -> (a -> IO b) -> IO b
coreRun (MkCore act) err ok = fromPrim (toPrim (io_bind (fromPrim act) (either err ok)))

data Ref : (l : label) -> Type -> Type where
  [search l]
  MkRef : IORef a -> Ref x a

get : (0 x : label) -> {auto ref : Ref x a} -> Core a
get x {ref = MkRef io} = coreLift (readIORef io)

put : (0 x : label) -> {auto ref : Ref x a} -> a -> Core ()
put x {ref = MkRef io} val = coreLift (writeIORef io val)

update : (0 x : label) -> {auto ref : Ref x a} -> (a -> a) -> Core ()
update x f = do v <- get x
                put x (f v)

data Ctxt : Type where

main : IO ()
main = do
  io <- newIORef (the Int 1)
  let c = MkRef {x = Ctxt} io
  coreRun (do update Ctxt (+ 1); get Ctxt) putStrLn printLn
```

### G2. Internal error in Emit (start build): a delayed field at a constructor-bound index, forced in a case block

- Uses: the checker's recognisers, `SeqEat : Recognise True -> Inf
  (Recognise e) -> Recognise True` (`compiler/checker/src/Libraries/Text/
  Lexer/Core.idr:31`), scanned by `scanFrom`'s `case scanFrom r1 ... of
  ... scanFrom r2 ...` (`:120-125`); 66 uses of `andThen`/`<+>`/`SeqEat` in
  the checker's lexers. The frontend reaches it through `Parser.Lexer.
  Source.lex`, which `Frontend/Profile.idr` (`checkSpelled`) runs on every
  user module, and the checker's parser on every source.
- Reproducer: `/tmp/selfhost-coverage/min/inf-case-capture/Main.idr` (21
  lines, below). First error on the start build (measured): `INTERNAL
  ERROR: Main.idr:16:19: internal error: Emit: a value of type Lazy (data
  family 4[v1]) where Lazy (data family 4[_]) is expected` (status 1, 1.3
  s). `Lazy` in place of `Inf` gives the same (`min/lazy-case-capture`); a
  strict field compiles (`min/strict-case-capture`); the delayed field
  forced outside a case block (`min/inf-index-existential`,
  `min/inf-fields-d`), at a fixed index (`min/inf-index-fixed`), at a
  parameter as the Tokenizer's `MkGroup` (`min/inf-param`), or built
  through the eta-reduced `andThen = SeqEat` (`min/inf-alias`): each
  compiles.
- Near-HEAD (measured): every one of these compiles, `runs/inf-fields`
  (the lexer's shape whole) too. By reading, 00e722e14 (L16ey, after the
  start) is the change: Emit no longer checks a value's fit to its slot
  and writes the coercion the slot's type calls for, "a closure's and a
  suspension's included", a reindex where index terms differ. So the
  frontend gap is closed at HEAD; whether the reindex of a suspension from
  a constructor-bound index verifies past the frontend is unrun (no LLVM).
- Tests: none at the start (the laziness tests' delayed fields are at
  parameters: lazy-elements, lazy-list-*, memo-shared-stream).
- Owner L16 (`Emit/`); at HEAD a test only (the reproducer), and the C++
  verifier's view of it once LLVM is at hand.

```idris
module Main

data R : Bool -> Type where
  P : R True
  E : R False
  Seq : R True -> Inf (R e) -> R True

covering
count : R c -> Maybe Nat
count P = Just 1
count E = Just 0
count (Seq a b) = case count a of
  Nothing => Nothing
  Just n => map (+ n) (count b)

covering
main : IO ()
main = printLn (count (Seq P (Seq P E)))
```

### G3. Refusal, escape hatch: base's decidable equality of a primitive type

- Uses: the frontend decides equality on `Int` three times:
  `Frontend/Growth/Template.idr:306` `anotherEntry (DataHead t) tag = case
  decEq t tag of` (`t`, `tag : Int`, `Translate/Readings.idr:811`), and
  `lookupPrecise` on its two `SortedDMap Int` tables, which asks `DecEq
  Int` (`Translate/State.idr:1336`, `:1478`; `Translate/Boundary.idr:239`,
  `:972`). Of the 79 `decEq`/`DecEq` uses in our programs the rest are on
  `Nat`, `Fin` and our own types where read, which compile
  (`min/deceq-user`, `bisect/deceqNat`).
- Reproducer: `/tmp/selfhost-coverage/bisect/deceqInt/Main.idr`:

  ```idris
  module Main
  import Decidable.Equality
  import Decidable.Decidable
  main : IO ()
  main = printLn (isYes (decEq (the Int 3) 4))
  ```

  First error, start build and near-HEAD alike (measured): `Main.idr:8:1
  escape hatch: Main.main: the escape hatch Builtin.believe_me (reached
  through Main.main)` (status 3). The same for `String` and `Char`
  (`bisect/deceqString`, `bisect/deceqChar`). The frontend's own table
  shape, an indexed family at an `Int` key (`min/sorted-dmap-family`), is
  refused by this alone (`Main.solutionIn ... reached through Main.main ->
  Main.solutionIn`).
- Why (read): base's `[FromEq] Eq a => DecEq a` (`third_party/Idris2/libs/
  base/Decidable/Equality.idr:138-145`) proves `Yes` by `believe_me (Refl
  {x})` and `No` by `believe_me {b = Void} ()`, and every primitive type's
  `DecEq` is `decEq @{FromEq}`; the walk refuses `believe_me` wherever it is
  reached, a trusted library's too (`Frontend/Profile.idr:405-407`). At
  true HEAD, by reading: 9a577ab1 (L16ev) makes library code's walk skip
  arguments the callee's `eraseArgs` erases, but `Yes`'s and `No`'s fields
  are not erased, so the refusal stands.
- Tests: none (no accepted test decides equality on anything).
- Owner L16 (`Registry/`, `Frontend/Profile.idr`): a frontend fix, as
  9a577ab1 gave `strM` a contract (the test `==` decides the `Yes`; its
  `Refl` carries nothing at run time, and the `No` function never runs).
  Not a change to our code: `decEq` on `Int` is base's, inside the subset.

### G4. Refusal, escape hatch: base's `strM` (start build and near-HEAD; fixed at HEAD by 9a577ab1)

- Uses: the runner only (by grep, nothing else of ours calls these):
  `parsePositive` 16, `parseInteger` 9, `trim` 10, `ltrim` 2, each reaching
  `strM` (`base/Data/String.idr:141-146`, `strM x = assert_total $
  believe_me $ StrCons ...`) through `asList` (`:158`, `ltrim` `:164`),
  `parsePosTrimmed` (`:279`) or `parseIntTrimmed` (`:301`); `parseDouble`
  and `rtrim` too.
- Reproducer: `/tmp/selfhost-coverage/bisect/parsePositive/Main.idr`,
  `main = printLn (parsePositive {a = Nat} "42")`; first error (measured,
  both binaries): `Main.idr:8:1 escape hatch: the escape hatch
  Builtin.believe_me (reached through Main.main)`. The same for
  `parseInteger`, `parseDouble`, `trim`, `ltrim`. The committed test
  `tests/checker-case-scrutinee-postponed-constraints` (suite
  test-mlir-tools, expected `compile: exit 0`) calls `parseInteger` and is
  refused by both binaries (`min/scrutinee-test`: escape hatch at 20:1,
  `Main.seed`, and 26:1, `Main.parse`).
- At HEAD (read): 9a577ab1 (L16ev) gives `strM` a `StringView` contract
  hook, adds `tests/string-view` (`strM`, `trim`, `parseInteger`) and
  reports that test compiling. Neither binary here holds it, so this is
  unmeasured. Owner L16; nothing left but the rerun.

### Already routed, not re-measured here

S-1, S-2 (tools/self.sh, L06; 1f225b6b9 says self.sh now runs stage 1 as
the driver would), R-UNIFY (L17; 8180a8c4e), R-META (L16ev, 9a577ab1; it
hides everything on the start build: both package probes stop at
`{P:w:3415}`), R-SPEC and R-PRAGMA (1f225b6b9, "an elaboration-only pragma
is admitted (C287)": the `%hint` probe, refused as a pragma on the start
build, compiles near-HEAD), R-ESC-FIN, specgen and the runner's later stops
(L16ey, L16ev, C308). Not measured on this audit's builds.

## Refused, but no program of ours reaches it (no action)

Each measured on both builds, the reach by reading.

| probe | refusal | why ours does not reach it |
| --- | --- | --- |
| `runs/sorted-dmap`: `SortedDMap` whose value type differs by key (`Value KInt = Int`, `Value KStr = String`) | polymorphism, 8, at `lookupPrecise` ("passes v through its type family v to Maybe, and nothing bounds what it computes") | our two tables hold an indexed family at the key (`Solution fz`, `Unfrozen`), which passes the growth check (`min/sorted-dmap-family`: only G3) |
| `runs/tap-search`: the checker's `Tap Core` with its Functor found by `%search` from `Functor.CORE` (`Core/Core.idr:1148-1166`) | polymorphism, 3 ("map{Functor (Tap m)} ... growing it by 1 each round") | nothing in compiler/checker calls `Search.traverse`, `Search.filter` or `functor`; `Tap IO` with its anonymous Functor compiles (`runs/tap-io`) |
| `runs/list-surface`: base's `Data.Fin.strengthen` | match on the erased `{e:1}` | our code calls only the checker's own `strengthen` (`Core/Name/Scoped.idr:245`); the probe without it compiles (`min/list-surface-b`) |
| `runs/hint-pragma`: `%hint` in a user module (start build) | pragma | only the checker, a library whose pragmas the profile does not read, writes it; admitted near-HEAD anyway |

## Used by our programs, compiles, and no test exercises it (a test only)

Measured on both builds unless said; ranked by our uses. Owner of the new
tests: L19 (`tests/`).

| construct (probe) | our uses (library names counted by name, so shared names inflate them) | form our code uses |
| --- | --- | --- |
| auto implicits holding runtime values beyond plain records (`runs/core-monad` for the monad; the labelled reference is G1) | 2559 (checker 1910, frontend 579, spec 61) | `{auto c : Ref Ctxt Defs}` |
| the checker's world-passing `Core` record over `PrimIO`, its named Functor/Applicative/Monad with `using`, `Catchable` (`runs/core-monad`) | Core 2959 names (checker 2344, frontend 415) | `MkCore (\w => case prog w of MkIORes r w' => ...)`, `Core/Core.idr:643-820` |
| `\case` (`runs/lambda-case`) | 286 (spec 170, checker 73, frontend 43) | `map (\case ...)` |
| nested record update `{ a.b := v, c $= f }` (`runs/nested-update`) | 51 (checker 45, frontend 5, harness 1) | `harness/Harness.idr:87` |
| default implicits (`runs/default-implicit`) | 93 (frontend 76) | `{default Nothing binder : Maybe Binding}`, `Emit/Tensors.idr:69` |
| multi-line strings, one interpolating; raw strings (`runs/multiline-raw-string`) | 90 + 3 (spec 54, checker 34+3) | `"""` ... `\{name}` |
| `%hide` in a user module (`runs/hide-pragma`) | 85 (frontend 40, checker 40, harness 5) | `%hide Lib.close` over an imported name |
| `with (e) proof eq` (`runs/with-proof`) | 29 (frontend 25) | `Term.idr:1806`, `Proof/Bound.idr:899` |
| `let p = e \| alt => ...` (`runs/let-alternative`) | 22 (checker 12, harness 8) | only scripted growth-check has one |
| mutual parameterized data with a record in one block (`runs/mutual-param`) | the checker's TTImp block (`TTImp/TTImp.idr:60-560`), Idris.Syntax | `data RawImp' : Type -> Type` ... `record ImpRecordData nm` |
| data declared ahead in a namespace, held through `Maybe` and a carrier of both (`runs/mutual-nested`) | `MLIR.idr:62-110` (MlirType/MlirAttr), `State.idr:1625-1630` | identity-weakening has only an indexed Tree/Forest pair |
| indexed families declared ahead (`runs/mutual-indexed`) | `Translate/Closed.idr:707-722` | Phase/IsNormal/IsBeta |
| decidable equality on `Nat`, `Fin`, our own types, named (`min/deceq-user`, `bisect/deceqNat`) | 79 less G3's 3 | `Proof/Forms.idr:84`, `Growth/Heads.idr:289`, `Spec/Effects/Resource.idr:278` |
| an interface with a determining parameter (`runs/determining-param`) | 3 (checker) | `Catchable m t \| m`, `Backtrack mark state \| state` |
| `rewrite prf in v` where `v` is the runtime result (`runs/rewrite-runtime`; INT-25's older binary refused it) | 367 (frontend 259, checker 100); tests: every-builtin-export, registry-identity-hook, on proofs | `Translate/Closed.idr:750` |
| base IO with no test (`runs/io-surface`, one program, 14.6 s): `readFile`, `writeFile`, `appendFile`, `exists`, `fileModifiedTime`, `fGetChar`, `fPoll`, `fileError`, `createBufferFromFile`, `writeBufferToFile`, `copyFile`, `fflush`, `currentDir`, `listDir`, `changeDir`, `clockTime` with `toNano`/`seconds`/`nanoseconds`, `getTermCols`, `newArrayCopy`, `writeSTRef`, `time`, `die`, `exitFailure`, `exitSuccess`, `sleep`, `usleep` | harness 122 file names, checker 37+20 directory names; `exists` 61, `writeFile` 44, `readFile` 16 | `Frontend/Profile.idr:160-162` (`createBufferFromFile`), `Core/Directory.idr`, `harness/Files.idr` |
| `Data.String` with no test (`bisect/*`): `isInfixOf`, `isSuffixOf`, `split`, `padLeft`, `stringToNatOrZ`, `strSubstr`, `words`, `lines`, `unwords`, `unlines`, `joinBy`, `indent`, `toUpper`, `toLower`, `singleton`, `fastConcat` | harness 27 `isInfixOf`, 26 `isSuffixOf`; `split` 92 | |
| base lists, vectors, maps with no test (`min/list-surface-b`): `find`, `findIndex`, `group(By)`, `nub(By)`, `sortBy`, `partition`, `inits`, `tails`, `intercalate`, `splitOn`, `catMaybes`, `iterateN`, `intersectAll`, `init'`, `lefts`/`rights`/`partitionEithers`, `getRight`, `fromJust`, `toMaybe`, `natToFin`, `weakenN`, `isLTE`/`isLT`, `fromThis`/`fromThat`, `isElem`, `hasLength`, `Vect.allFins`/`elemIndex`/`snoc`, `SortedMap.mergeWith`/`mergeLeft`/`insertFrom` | `group` 237, `maximum` 91, `snoc` 41, `find` 42, `nub` 32, `mergeWith` 20 | |

## Every construct

Uses are counts at 2c500794 over the programs that hold them (fe frontend,
ss syntax-samples, ch checker, sp spec, sg specgen, ha harness, kg
knowngen, li libs/). Tests: accepted programs holding it (+ scripted).
Verdict ground: m measured (probe named), r read, t covered by a passing
test's expectation (not rerun here).

| construct | uses (programs) | tests | verdict |
| --- | --- | --- | --- |
| `%default total` / `covering` | 329 / 108 (all; covering ch, ha) | 36+6 / 2+1 | compiles (t; every probe) |
| `%hint` | 8 (ch) | none | ch: a library's pragmas are not read (r, `Frontend/Program.idr:228-236` checks user modules only); in a user module refused at the start, admitted near-HEAD (m `runs/hint-pragma`; `meaning KwHint = Elaboration` at 98cabc49) |
| `%inline`, `%tcinline`, `%name` | 87, 1, 46 (ch; `%name` li 1) | refusal test pragma-default-with-inline | ch, li: not read (r); at 98cabc49 `%tcinline` and `%name` are admitted in a user module and `%inline` refused (`Frontend/Profile.idr:128-180`, r); no user module of ours writes one |
| `%prefix_record_projections` | 67 (fe 54, ch 13) | none | fe: R-PRAGMA (INT-24); admitted since 1f225b6b9, `meaning KwPrefixRecordProjections = Elaboration` (r) |
| `%hide` | 85 (fe, ch, ha) | none | compiles (m `runs/hide-pragma`) |
| `%extern` | 15 (li) | linarray-*, arrays-* | compiles (t) |
| `%search` as a term | 7 (fe, ch) | checker-quoted-search | compiles (t, m `runs/tap-search` past it) |
| `mutual` functions | 349 blocks (all) | 10 | compiles (t) |
| mutual data, parameterized, with records | ch TTImp, Idris.Syntax | none | compiles (m `runs/mutual-param`) |
| data declared ahead | 7 (fe 6, sp 1) | none | compiles (m `runs/mutual-nested`, `runs/mutual-indexed`) |
| `namespace` | 89 | 3 | compiles (t; m `runs/core-monad`) |
| `parameters` | 8 (ch) | checker-parameters-block-parent | compiles (t) |
| records, data (both forms) | 545, 1115 | 34, 95 | compiles (t) |
| `interface`, superclass, `implementation` keyword | 23, 2, 4 (ch) | 21, 5, 1 | compiles (t) |
| determining parameter `\| m` | 3 (ch) | none | compiles (m `runs/determining-param`) |
| named implementation, `@{..}`, constrained, `using` | 40, 50, 100 | 10, 26, 10 | compiles (t; m `runs/core-monad`) |
| fixity declarations | 18 (ch, li) | nbody | compiles (t) |
| totality annotations | 184 | 43 | compiles (t) |
| `where` | 3229 | 155 | compiles (t) |
| `impossible` clauses | 371 (fe 295) | 4+1 | compiles (t) |
| `with` / `with ... proof` | 71 / 29 | 4 / none | compiles (t / m `runs/with-proof`) |
| `rewrite ... in` | 367 | 2 | compiles (t; m `runs/rewrite-runtime`) |
| `case`, `\case` | 2883, 286 | 44, none | compiles (t, m `runs/lambda-case`) |
| pattern-matching lambda | 337 | 3+2 | compiles (t) |
| `let` with alternatives | 22 | 0+1 | compiles (m `runs/let-alternative`) |
| `do` bind with alternatives, `do`, `!` | 595, 4181, 1987 | 17, 311, 19 | compiles (t) |
| idiom brackets, list comprehensions, ranges | 45, 55, 73 | 1, 1, 3 | compiles (t) |
| string interpolation | 135 (ch 134) | 2 | compiles (t; m `runs/multiline-raw-string`) |
| multi-line strings, raw strings | 90, 3 | none | compiles (m `runs/multiline-raw-string`) |
| record update `:=`, `$=`, nested | 367, 257, 51 | 6, 1, none | compiles (t, m `runs/nested-update`) |
| postfix projections, `(.f)` sections | 8001, 286 | 11+5, 1 | compiles (t) |
| as-patterns, `**`, operator sections, backticks, `if` | 549, 1304, 406, 389, 820 | 2, 11, 41, 39, 134 | compiles (t) |
| `{auto ...}` runtime arguments | 2559 | 2 | plain records compile (t); a labelled `Ref` in `Core`: G1 |
| `{default ...}` | 93 | none | compiles (m `runs/default-implicit`) |
| quantities 0 and 1, `(1 _ : ...)` | 2160, 195, 80 | 42, 25, 13 | compiles (t) |
| `Lazy`, `Force` | 108, 38 | 21, 2 | compiles (t); a delayed field at a constructor-bound index forced in a case block: G2 |
| `Inf` fields | 3 (ch) | Stream only (memo-shared-stream) | G2 at the start; compiles near-HEAD (m `runs/inf-fields`) |
| `believe_me`, `assert_total` | 2, 24 (ch) | refusal tests | ch: quantity-0 believe_me and a library's assertions are not walked (r, INT-24) |
| `unsafePerformIO` | 4 (li) | world-unsafe-perform (refusal) | li: trusted, the rule forbids only user code naming it (r) |
| `Dec`, `So`, `Uninhabited` | 453, 156, 360 | 3, 4, 7 | compiles (t) |
| `DecEq` / `decEq` | 79 | none | own types, Nat, Fin compile (m `min/deceq-user`); Int, String, Char: G3 |
| literals, Bits*, Int*, Double, Integer, Char | many | many | compiles (t) |
| matching string literals | 202 (ch 164) | 2 | compiles (t) |
| `IORef` | 57 | 8 | compiles (t) |
| `Buffer`; to and from files | 40; 2 | 5; none | compiles (t; m `runs/io-surface`) |
| `SortedMap`, `SortedSet` | 364, 145 | 6, 2 | compiles (t; m `min/list-surface-b`) |
| `SortedDMap` | 3 (fe) | none | at `Int` keys: G3 (m `min/sorted-dmap-family`) |
| `IOArray`, `newArrayCopy` | 8 | 19 | compiles (t; m `runs/io-surface`) |
| System.File | 185 (ha 122) | 8+1 | compiles (t; m `runs/io-surface`) |
| System.Directory | 30 (ch 20) | 0+1 (directory-listing) | compiles (t; m `runs/io-surface`) |
| System (args, env, exit, time, sleep) | 283 | 19+2 | compiles (t; m `runs/io-surface`) |
| System.Clock | 44 | 1 | compiles (t; m `runs/io-surface`) |
| System.Term `getTermCols` | 1 (ch) | none | compiles (m `runs/io-surface`) |
| `State`, `EitherT`, `ST` | 69, 50, 13 | 4, 1, 1 | compiles (t; m `runs/io-surface` for `writeSTRef`) |
| `Tap` | ch 1 type | none | `Tap IO` compiles (m `runs/tap-io`); `Tap Core` refused, unreached |
| Data.String | many | some | 16 functions compile (m `bisect/*`); `parsePositive`, `parseInteger`, `parseDouble`, `trim`, `ltrim`: G4 |
| base list/vector/map surface | many | some | compiles (m `min/list-surface-b`); `Data.Fin.strengthen` refused, unreached |
| contrib, linear, network, test | none of ours imports one | | |

## Files

`/tmp/selfhost-coverage/`: `HEAD-start`; `scripts/` (`inventory.py`,
`probe.sh`, `refusals.py` from INT-24, `build.sh`, `self-checker.sh`,
`near-head-prefix.sh`); `inventory.tsv`, `inventory.json`; `probes/` (the
probes as written, each with the stock check's log), `runs/`, `bisect/`,
`min/` (start build: each probe's `run/result`, `run/out.log` and module),
`near/` (the same probes, near-HEAD binary), `probes-checker/` (the
package probes); `logs/` (the builds).
