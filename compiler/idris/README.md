# compiler/idris

Upstream Idris 2's compiler, forked at the commit third_party/Idris2's
gitlink pins (1c630e67c, release 0.8.0) and pruned to what this
repository's frontend needs: parsing, elaboration, totality and coverage
checking, normalisation, reading and writing TTC, and building and
installing packages from `.ipkg` files (prelude, base and
`libs/mlir-linear`). It is distributed under upstream's BSD-3 licence,
in LICENSE here; the rest of the repository is under its own licence.

It is built standalone, as the package `idris-compiler`, by the stock
Idris 2 the toolchain installs:

```sh
cd compiler/idris && idris2 --build idris-compiler.ipkg
```

`make fork` installs it for that Idris into the checkout's
`build/idris2-host`, where the frontend's build finds it (`depends =
idris-compiler`). The frontend's driver, `IdrisMLIR.Frontend.Driver`,
replaces upstream's `Idris.Driver`; the TTCs the fork writes are read by
nothing else, so the frontend builds the packages Idris ships itself, into
`build/idris2` (`make prefix`).

It depends on nothing but prelude and base. Upstream's API package needs
`network` for the IDE mode's socket; nothing here does.

## What was deleted, and why

- **The REPL, the IDE mode and every code generator but ours.** They are
  out of scope, so they are gone rather than switched off: `Idris.REPL`,
  `Idris.IDEMode.*` (but `Holes`, below), `Protocol.*` (but `Hex`),
  `TTImp.Interactive.*`, `Yaffle.*`, `Idris.Main`, `Idris.Driver` (our
  own driver replaces it), and `Compiler.Scheme`, `Compiler.ES`,
  `Compiler.RefC` and `Compiler.Interpreter`, with the Scheme evaluator
  (`Core.SchemeEval.*`, `Libraries.Utils.Scheme`) and a `GlobalDef`'s
  `schemeExpr`. The command line lost the options that only served them
  (`--repl`, `--ide-mode`, `--inc`, `--dumpcases` and the like), and so
  did a session's options; the REPL's command syntax went from
  `Idris.Syntax`, `Idris.Parser` and `TTImp` (Yaffle's). A code generator
  is only one a driver registers, known by its name (`CG` is `Other
  String`, and a session no longer carries a default one): `--cg` checks
  that it names one, `--directive` is the session's, and `--exec` is the
  driver's to run or refuse. The log topics only the deleted modules used
  are gone, and `Idris.Env` lists only the variables the fork's code and
  its driver read (not `IDRIS2_CG`, which named the default code
  generator). `Idris.Package` lost `--mkdoc`, `--init`, `--repl` and
  `--dump-ipkg-json` with the modules behind them.
- **The CExp pipeline.** The frontend consumes checked TT and its
  definition context, never CExp, so `Compiler.ANF`, `CaseOpts`,
  `CompileExpr`, `Inline`, `LambdaLift`, `NoMangle`, `Opts.*`,
  `Separate`, `VMCode`, `Generated` and `Common` are gone, and with them
  the `compexpr` and `namedcompexpr` of a `GlobalDef`, the compiled
  definitions in a TTC, the incremental code generators' data in a TTC and
  in `Defs`, and the "compile definitions" step after a module checks.
  `Core.CompileExpr` stays as a data module: a constructor's `ConInfo` is
  one of its flags, saved in TTC.
- **Source hashes.** Upstream could decide a rebuild by hashing a source
  file with an external `sha256sum` through `popen`; it shipped with that
  disabled. The fork decides by modification time only, and a TTC no longer
  carries a source hash.
- **Shell scripts and executables in packages.** A package's `prebuild`,
  `postbuild`, `preinstall`, `postinstall`, `preclean` or `postclean` runs a
  shell command; the fork refuses such a package with an error naming the
  field. An `executable` is refused the same way: building a package
  checks and installs modules, and programs come from this compiler's own
  back end. The refusal comes as soon as the package file is read, for
  every package command, before anything is built, installed or cleaned.

### Stubbed

`Core.Metadata` keeps its names and does nothing. Upstream records there
what the IDE mode reads back (the type and left-hand side at each source
span, semantic highlighting) and saves it beside each TTC as a `.ttm`
file. The elaborator threads `Ref MD Metadata` through about forty-five
modules and the parser produces decorations as it goes, so the type, its
`Decoration`s and every adder stay, empty: the adders are no-ops, and the
`.ttm` file is neither written nor read. A `%failing` block still saves
and restores it, harmlessly.

### Kept although out of scope

- `Idris.REPL.Opts`: `REPLOpts`, trimmed to what the elaborator and the
  build read (the main file, the verbosity, the source being elaborated
  for error messages, console width and colour). Some thirty elaborator
  modules import it by this name; renaming it would make each of them
  differ from upstream for nothing.
- `Idris.REPL.Common`: trimmed to printing messages, warnings and errors,
  which `Idris.ModTree` and `Idris.Package` use.
- `Idris.IDEMode.Holes`, without the IDE protocol: how a hole is printed,
  which `Idris.Doc.Display` uses (`Idris.Error` → `Idris.Doc.String` →
  `Idris.Doc.Display`).
- `Protocol.Hex`: hexadecimal digits, which the lexer
  (`Parser.Lexer.Source`) and `TTImp.PartialEval` use.
- `Libraries.Data.String.Iterator`, unchanged, with its `%foreign`
  declarations: the fork is Idris code that the stock Idris compiles and
  runs on Chez Scheme, and string iteration (`Core.Hash`) is a Chez
  primitive there. The declarations are the host's, not a language
  feature of this compiler.

### Ours

- `Core.Unify` declares `search` and `Core.AutoSearch` defines it, which
  nothing kept imported (upstream's driver reached it through the REPL):
  `Idris.ProcessIdr` imports it, so every program that elaborates links
  the definition rather than a hole.
- `clean` (`Idris.Package`) removes the package's TTCs. Upstream's looks
  for them under one `ttc` directory too many, and removes nothing.
- Elaboration leaves a primitive applied to constants, as it leaves a
  function applied (`evalDef` of a `Builtin`, `Core.Normalise.Eval`), but
  for `believe_me`, which computes nothing (`coercionOp`), and a literal's
  conversion runs only the primitives every backend computes alike,
  Integer's arithmetic and comparisons, the exact or wrapping casts from
  Integer and `believe_me` (`sharedOp` in `Core.Primitives`, the
  evaluator's `sharedPrimsOnly`, `normalisePrims` in `Core.Normalise`).
  Upstream folds any such call with its own implementation, which is
  Chez's meaning of the primitive, not the runtime's; the checked term now
  holds the call.
  A literal pattern whose conversion needs another primitive is refused,
  since the call left in it would match anything.
- `IdrisPaths`, which upstream's build generates, is written here: the
  version, tagged with the pinned commit. It has no install prefix; the
  driver passes one.
- `ttcVersion` (`Core.Binary`) has eleven digits where stock Idris's have
  ten, so a TTC either one writes is refused by the other when read.

### Rewritten so that this compiler can compile it

These keep upstream's interfaces where they can, so that a re-sync stays a
merge; each says what changed in its interface.

- `Libraries.Text.Parser.Core`: a `Grammar` is the parser itself, a
  function from the parser's input (the state, the warnings, whether the
  enclosing alternative has committed, the tokens left) to its result,
  boxed in a constructor (`noNewtype`, so that a grammar without arguments
  stays a constant built once). Upstream's was a deep embedding read by
  `doParse`, whose `SeqEat` and `SeqEmpty` hid the type of the first
  grammar's result and whose `Bounds`, `NextIs`, `EOF` and `Position` fixed
  the result type per constructor; here the result type is a parameter and
  a sequence's intermediate result lives in its closure. Each combinator
  is `doParse`'s clause for its constructor, so commits, backtracking,
  fatal errors, the merging of the errors of two failed alternatives and
  the bounds of every result are upstream's; `map` gives what upstream's
  structural `map` gave for every grammar over tokens that are not
  irrelevant (a lexer's never are). The combinators keep their names,
  types, operators and `Inf` and `Lazy` arguments, and the `consumes`
  index still decides where `>>=` and `>>` take an `Inf` continuation.
  Interface changes: `mapToken`, which nothing used and which a function
  cannot be mapped through, is gone; `>>` is `export %inline` rather than
  `public export %tcinline`, which only served the totality checker; and
  the combinators that build a closure are no longer `%inline`, since
  inlining one moves the building of its arguments into the closure, to be
  repeated each time it runs. The totality checker took a recursive
  grammar to be guarded because upstream's `>>=` and `>>` normalised to a
  constructor holding the `Inf` continuation; a function is not one. The
  recursions whose termination that hid are now marked: one call in each
  cycle of `some` and `many`, `count1` and `count`, `someTill` and
  `manyTill`, `afterSome` and `afterMany` (`Libraries.Text.Parser`) and
  `blockEntries` (`Parser.Rule.Source`) is `assert_total`, each after a
  grammar that consumes, as upstream's `doParse` asserted its own
  recursion. (`Idris.Parser` and `TTImp.Parser` are `covering`.)
- `Libraries.Text.Lexer.Tokenizer`: a composed tokenizer (`Compose`,
  `compose`) makes its middle tokenizer and its end lexer from the begin
  lexeme itself, a `String`. Upstream's took a `tagger` to a tag type the
  constructor hid; `Parser.Lexer.Source` now applies its taggers (the
  string's hashes) itself.

## tools/extract-idris.sh

`MODULES` lists the kept upstream files, relative to `src/`. The script
reads the commit from the superproject's staged gitlink of
third_party/Idris2 and the files from that commit (`git show`), never
from the checkout:

- `extract [--force] [PATH...]` copies the kept files (or the named ones)
  into `src/`. It refuses when any of them is already there, because the
  copies are ours once extracted; `--force` overwrites.
- `status` lists the fork's deviations: `M` for a kept file we changed,
  `D` for one missing, `A` for a file upstream does not have.
- `diff OLD NEW` prints upstream's diff between two Idris commits,
  restricted to the kept files, with full blob ids.

## Re-syncing with upstream

When third_party/Idris2's pin moves from OLD to NEW, the fork takes
upstream's changes to the files it keeps, merged three ways with ours:

```sh
git -C third_party/Idris2 fetch --depth=1 origin NEW   # the checkout is shallow
tools/extract-idris.sh diff OLD NEW |
  GIT_ALTERNATE_OBJECT_DIRECTORIES=$(git -C third_party/Idris2 rev-parse --path-format=absolute --git-path objects) \
  git apply --3way --directory=compiler/idris
```

The blobs a three-way apply needs are in the submodule's object store, not
the superproject's; the alternate directory lends them. Resolve the
conflicts it leaves, as in any merge. Then: a kept module that now imports
an upstream module the fork lacks gets that module added to `MODULES` and
copied with `tools/extract-idris.sh extract PATH`, unless the import is
part of what was deleted, which the fork then cuts again; update
`IdrisPaths`' tag; and bump `ttcVersion` if the TTC format changed. The
fork must build standalone again before the pin moves.

## Bugs in upstream code found here

The code here is ours, so a bug found in it is fixed here, in the fork,
where the fix is needed. It is also reported to Idris 2 upstream, and
recorded in PINS.md (what the bug is, where the report is, and when the
fix goes: when a re-sync brings upstream's own fix). The pinned checkout
third_party/Idris2 stays unmodified.
