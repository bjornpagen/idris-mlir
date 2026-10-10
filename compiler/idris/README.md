# compiler/idris

Upstream Idris 2's compiler, forked at the commit third_party/Idris2's
gitlink pins (1c630e67c, release 0.8.0) and pruned to what this
repository's frontend needs: parsing, elaboration, totality and coverage
checking, normalisation, reading and writing TTC, and building and
installing packages from `.ipkg` files (prelude, base and
`libs/mlir-linear`). It is distributed under upstream's BSD-3 licence,
in LICENSE here; the rest of the repository is under its own licence.

It is built as the package `idris-compiler`, by the stock Idris 2 the
toolchain installs, once that Idris has `libs/mlir-linear` (below):
`make fork` installs `mlir-linear` (`make host-libs`) and then the fork
for that Idris into the checkout's `build/idris2-host`, where the
frontend's build finds it (`depends = idris-compiler`). The frontend's
driver, `IdrisMLIR.Frontend.Driver`, replaces upstream's `Idris.Driver`;
the TTCs the fork writes are read by nothing else, so the frontend builds
the packages Idris ships itself, into `build/idris2` (`make prefix`).

It depends on prelude, base and `mlir-linear`, this compiler's own
package of linear data (`libs/`), for its growing tables. Upstream's API
package needs `network` for the IDE mode's socket; nothing here does.
Built by this compiler's frontend, the fork finds `mlir-linear` in the
frontend's prefix, which `make libs` installs it into; a program over the
fork (the frontend compiled by itself) names both packages, `-p
mlir-linear -p idris-compiler`, since `-p` adds the package it names and
not the packages that one depends on, as in Idris.

To this compiler the fork is a trusted library of its own, as base is
(`Compiler` in `IdrisMLIR.Registry.Libraries`): a module whose TTC is
installed in the package `idris-compiler` may be imported by a program and
is admitted whole, so the frontend compiles as a program over it. The
frontend's own modules (`IdrisMLIR.*`) are the program's, user code under
the same profile as any other.

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
  tree's stored variable name must equal the scope's name at its index,
  which the tree then takes, or the TTC is corrupt.
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
  strings the distance is upstream's. `Parser.Unlit` drops the empty
  string before each candidate extension's leading dot rather than
  crashing on its absence.
- Unused and not expressible honestly, deleted: `VarSet.unsafeToList` and
  `Libraries.System.Directory.Tree`'s `Tree.toRelative`.
- Names, constants and scopes are compared as values. Upstream decided
  their equality with proofs (`nameEq`, `namesEq`, `userNameEq`,
  `scopeEq`, `constantEq`, `Namespace`'s `DecEq`) built on base's `DecEq`
  for strings and integers, which coerces with `believe_me`; all are gone,
  with `Libraries.Decidable.Equality`, which only they used. Where a proof
  retyped a term, the term is built at the type it needs: `isVar` finds a
  variable by `==` (`isNVar`, whose one use forgot the name, is gone);
  `IsDefined` hides the name of the variable it found; `extendEnv` renames the type's top variable to the
  pattern's, which has the same name (`compat`); the compile-time tree of
  a definition is renamed into the runtime tree's scope, whose names are
  the same (`compatCaseTree`, over `renamedVarAt`); and the case builder
  groups clauses by comparing constructor names and tags, and constants
  as upstream's semi-decision did (never two doubles, and primitive types
  as `primTypeEq` relates them). `substName` compares.
- Base's `strM` view coerces its proof with `believe_me`, and its `ltrim`,
  `trim`, `parsePositive` and `parseInteger` see a string through it. The
  fork matches on `strUncons`, and trims and parses numbers with
  `trimStart`, `trimSpace`, `parseNatural` and `parseSigned`
  (`Libraries.Utils.String`), which see the characters and give base's
  results.

### Rewritten so that this compiler can compile it

These keep upstream's interfaces where they can, so that a re-sync stays a
merge; each says what changed in its interface.

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
- `Libraries.Text.Lexer.Tokenizer`: the `Compose` constructor makes its
  middle tokenizer and its end lexer from the begin lexeme itself, a
  `String`; upstream's held a `tagger` to a tag type the constructor hid.
  `compose` keeps upstream's type, tagger included, and applies the tagger
  before building the constructor, so its callers (`Parser.Lexer.Source`)
  are upstream's. It is `public export %tcinline` rather than `export`
  (upstream's was `Compose` itself, point-free), so that the totality
  checker still sees the recursion of `rawTokens` and `stringTokens`
  through it guarded by the constructor.

- **Recursion at the types it is given.** This compiler makes an instance
  of a definition for each type and implementation it is given, so a
  group of definitions that call each other passes those on only as it
  got them. Where upstream's did not: each `map` of `TTImp.TTImp.Functor`
  is a function of its own (`mapRawImp`, `mapClause`, `mapDecl`, ...),
  which its `Functor` implementation is, where upstream's methods called
  `map` through the implementation, which applies them to types it binds
  itself; `Idris.Syntax.Traversals` traverses a list of paired terms
  (`PList`, `PUsing`, ...) with a function on the pair, where upstream's
  `goPairedPTerms` took the first component's type from each use;
  `Idris.Parser`'s rules that take the bounds of where they start take a
  `WithBounds ()` (`ignore` where the bounds hold a value), not any
  `WithBounds t`; `localHelper` (`TTImp.Elab.Local`) returns its one
  use's result, a term and its type; `Core.Context`'s `HasNames` for a
  `NameMap` is at `NameMap Bool`, a definition's references, the one map
  whose names are resolved; and `convertMatches` in
  `Core.Normalise.Convert` binds its scopes as `Scope`, where upstream's
  `_` made them lists of any type.
- `OperatorLHSInfo` (`Core.TT`) is a family over `Type`, as its
  constructors use it. Upstream declared it over a value of an implicit
  type (`tm -> Type`), which this compiler reads as a parameter that is a
  value, not a type, on which its fields' types then depend.

### Ours

- The context's definitions (`content` of `Core.Context.Context`) are a
  `Table` (`Libraries.Data.Table`) on `mlir-linear`'s growable
  `Linear.Array`, the one module that imports it. Upstream's was base's
  `IOArray`, made with 10000 slots and moved to a copy 10000 slots longer
  each time it filled. The table starts with room for as many, grows to
  at least twice its capacity, and is threaded through its `Ref` as one
  object (`threadRef` in `Core.Core`: moved out, used once, put back), so
  every read and write is in place. Its size is the high-water mark of
  `nextEntry`: restoring a saved `Defs` lowers `nextEntry` and the table
  keeps its slots, as upstream's array did, so `newEntry` claims the slot
  past the last only for an index never handed out. A lookup outside the
  table, or of a slot not yet written, finds nothing, as upstream's
  `readArray` did. `getContent` and `setNextEntry`, which nothing called,
  are gone (the latter was the one way to raise `nextEntry` past the
  table). Decoding a definition from its TTC writes it into the table as
  it is after resolving the definition's names, which may grow it;
  upstream wrote it into the array it had read before, where a write
  after a growth was lost and the definition decoded again on the next
  lookup.
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
- Where the evaluator does compute a primitive (`getOp`, `sharedOp` in
  `Core.Primitives`), it calls the primitive of the same name
  (`prim__add_Int`, `prim__cast_CharString`, ...), so the result is what
  the runtime that runs the compiler computes, not an Idris program
  written to agree with it: Chez's at stage 0, this compiler's runtime
  once the fork compiles itself. Upstream computes each with Idris code
  (`x + y`, `cast`, `show`); the two differ only for a Char's text,
  which upstream writes as `show`'s escape (`cast '\n'` is `"\\n"`,
  upstream/20-evaluator-char-text). Which calls reduce is unchanged
  (a division by zero, an empty string's head and the casts to a
  fixed-width integer from a Double, Char or String still stay applied),
  but for two: a fixed-width integer's negation stays applied, since
  Chez's `prim__negate_Bits8` does not wrap and this compiler's runtime
  has no such primitive (base negates by subtraction, which upstream's
  evaluator used for it), and the cases for adding and subtracting Chars,
  which no primitive has, are gone.
- `IdrisPaths`, which upstream's build generates, is written here: the
  version, tagged with the pinned commit. It has no install prefix; the
  driver passes one.
- The delayed elaborators are not a field of `UState`: they live in a
  cell of their own, `Ref DLY DelayedElabs` (`Core.UnifyState`), which
  every elaborator that may delay one is given beside `Ref UST UState`,
  made where a unification state is made and saved and restored wherever
  one is around elaboration (`tryError`, `successful`, `checkTermSub`,
  `processFailing`, `resetContext`, and `tryUnifyElab` and
  `handleUnifyElab`, the variants of `tryUnify` and `handleUnify` for what
  elaborates). A delayed elaborator (`DelayedElab`) is a function given
  that cell when it is retried, and the elaborator `delayOnFailure` and
  `delayElab` take is given it too, rather than capturing the cell of its
  caller: upstream's closures captured `Ref UST UState`, so the cell's
  type reached itself. The case block's delayed part is
  `checkCaseDelayed`, a function of its own, because a local definition
  is applied to everything its parent binds, and one used in the lambda
  would capture the parent's cell. A pragma's action (`IPragma`) is given
  the cell too, when `process` runs it: a delayed elaborator holds terms,
  a term's local block holds declarations, and the actions desugaring
  makes for interfaces, implementations and `%foreign_impl` elaborate, so
  one that captured the cell would let it reach itself. Desugaring itself
  is not given the cell, and cannot change it. `SyntaxInfo` still reaches
  itself that way: it holds terms (an interface's parents and default
  methods, `usingImpl`, `startExpr`), and the interface, implementation,
  `%foreign_impl` and `%hide` fixity actions capture `Ref Syn
  SyntaxInfo`, which `TTImp.TTImp`, below `Idris.Syntax`, cannot name to
  give it. The other
  cells (`Defs`, `EState`, `Metadata`, `REPLOpts`, `PostSession`) hold no
  closure that reaches them.
- `Core` is a function of the world (`PrimIO`), not a record over IO, and
  only its combinators in `Core.Core` see the world. Two computations in
  sequence go through the prelude's `io_bind`, which the stock compiler
  inlines with the incoming world: a world matched out of an `IORes` is
  erased in its generated code, and an action applied to it is a closed
  term that common subexpression elimination hoists to the top level,
  where it runs once, at load time.
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
