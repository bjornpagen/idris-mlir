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

- **The REPL, the IDE mode and every code generator.** They are
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
  driver's to run or refuse. Ours registers none and reads none of these
  options: the frontend takes the checked definitions from the context
  Idris built. The log topics only the deleted modules used
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

### Honest code

This compiler compiles the fork, and refuses `believe_me`, `%unsafe`
definitions and `%foreign` without a primitive, so the fork has none of
them, and no `idris_crash`. Where upstream coerced, the fork does what the
coercion claimed, with the same results (but for one upstream crash,
below); `assert_total` and `assert_smaller` stay.

- A scope coercion is a traversal that rebuilds every node from the same
  fields, an identity once scopes are erased: `FreelyEmbeddable` has no
  default (`embed = believe_me`); `Term`'s is `embedTerm`, a functor's is
  `map embed`, and the unused instances for `CaseTree` and `CExp` are
  gone. `compatTerm` is the traversal upstream left in a comment, its
  proof erased.
- Reading a local variable from a TTC decides the `IsVar` proof from the
  scope (`isVarAt` in `Core.TTC`) instead of forging it (`mkPrf`); a case
  tree's stored variable name must be the scope's name at its index, or
  the TTC is corrupt.
- `Cast (Doc Void) (Doc ann)` rebuilds the document (`annotateVoid`), as
  `reAnnotate absurd` would.
- `OperatorBindingMismatch` holds its use site and right-hand side as the
  documents its message prints (`Doc ()`), not a value of a hidden type
  with its printer.
- The shunting yard (`Libraries.Utils.Shunting`) threads its output stack
  as a value; there is no mutable cell.
- `Core.Hash` hashes a string over `unpack` (the same characters in the
  same order, so the same hashes), and `Libraries.Data.String.Iterator`,
  with its `%foreign` declarations, is deleted.
- `Libraries.Text.Distance.Levenshtein` fills its table a row at a time
  in lists, so no lookup can miss, and `Libraries.Data.IOMatrix` is
  deleted. Upstream's `compute` crashed ("Badly initialised matrix")
  whenever either string was empty, because its loops over `[1..0]` count
  down; this one returns the other string's length. Between two non-empty
  strings the distance is upstream's. `Parser.Unlit` drops the empty string before each candidate
  extension's leading dot rather than crashing on its absence.
- Unused and not expressible honestly, deleted: `VarSet.unsafeToList` and
  `Libraries.System.Directory.Tree`'s `Tree.toRelative`.

### Rewritten so that this compiler can compile it

- **Metadata records.** Upstream attaches metadata to a payload with one
  extensible record, `WithData fields a` (`Libraries.Data.WithData`, over
  `Libraries.Data.Record`): `fields` is a list of labels paired with
  types, a `KeyVal` holds a `Type` at run time, each value's type is
  computed from that list, and building one takes the list at run time.
  This compiler refuses a `Type` stored at run time and a field whose type
  is computed from an index, so both modules are gone. `Core.WithData`
  instead declares one record per combination of metadata that is used,
  named by its fields in their order (`WithFC`, `WithName`,
  `WithFCTyName`, `WithFCNameArity`, `WithRigName`, `WithFCRigName`,
  `WithNameOpts`, `WithRigMName`, `WithFCRigMName`, `WithDocFC`,
  `WithDocRigNames`, `WithFCDocRigNames`, `WithNameRigTot`), each with
  fixed field types and a `Functor` on its payload. The fields keep
  upstream's projection names (`.fc`, `.val`, `.name`, `.rig`, `.doc`,
  `.names`, `.mName`, `.tyName`, `.arity`, `.opts`, `.totReq`), so
  `x.fc` and `{ val := v } x` read as upstream's do; they resolve by the
  record's type. `WithFC`'s constructor keeps upstream's `MkWithData`,
  which call sites match on, and `MkFCVal`, `NoFC`, `.withFC`, `setFC`,
  `.nameVal`, `:+`, `AddDef`, `distribData` and `Core.Core`'s
  `traverse` keep their names, at the types they are used. What changed
  at call sites: the type-level combinators (`AddFC`, `WithRig`,
  `WithDoc`, `AddMetadata`, ...) are replaced by the record they built
  (`Constructor'` is `WithFCNameArity`, `ImpTy'` is `WithFCTyName`,
  `ImpParameter'` is `WithRigName`, `IField'` is `WithFCRigName`,
  `RecordField'` is `WithDocRigNames`, `PField'` is
  `WithFCDocRigNames`, `Method` is `WithNameRigTot`); `Mk [x, y] v`
  becomes the record's constructor applied to `x y v`; `get "doc"`,
  `set "fc"` and `update "name"` become a projection or a record update;
  and `TTImp.Impossible` names `WithFC.val`, where fourteen records'
  `.val` exceed the elaborator's ambiguity depth. A TTC holds these
  records as upstream's extensible record wrote them (each metadata field
  after a 1, in order, then a 0, then the payload), so its bytes are
  unchanged; `Core.TTC` (and `TTImp.TTImp.TTC` for `WithNameOpts`, whose
  `DataOpt` is defined there) writes each one. Upstream's
  `DocBindFC`, `.bind`, `HasDefault`, `MkDef` and the generic
  `get`/`set`/`update`/`getAt`/`drop` had no use left and are gone, as are
  the public re-exports of `Data.List.Quantifiers`, `Data.List` and
  `Data.Maybe` that came with `Libraries.Data.WithData`
  (`Core.Normalise.Eval` imports `Data.List.Quantifiers` itself).

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
