<!-- SPDX-License-Identifier: BSD-3-Clause -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# compiler/checker

The type checker idris-mlir uses: Idris 2's checker, copied into this
tree from Idris 2's release 0.8.0 (commit 1c630e67c) with its
attribution, and ours to change from then on. It parses, elaborates and
type-checks Idris (totality and coverage checking, normalisation), reads
and writes TTC, builds and installs packages from `.ipkg` files (prelude,
base and the packages of `libs/`), and holds the checked definitions the
frontend translates. It is under Idris's BSD-3-Clause licence, in LICENSE
here: Edwin Brady and the Idris contributors keep their copyright line on
each file they wrote, and a file written here is ours under the same
licence; the rest of the repository is under its own licence. It tracks
no upstream: no pin is followed, nothing is merged from Idris, and no rule
keeps upstream's form or interface here, so its best form is ours,
written in the strict subset both hosts compile.

It is built as the package `idris-mlir-checker`, by the stock Idris 2 the
toolchain installs: `make checker` installs it for that Idris into the
checkout's `build/idris2-host`, where the frontend's build finds it
(`depends = idris-mlir-checker`). The frontend's driver,
`IdrisMLIR.Frontend.Driver`, replaces upstream's `Idris.Driver`; the TTCs
the checker writes are read by nothing else, so the frontend builds the
packages Idris ships itself, into `build/idris2` (`make prefix`).

It depends on prelude, base, `mlir-linear` and `mlir-array`, using only
the functions of the last two that have bodies, which both hosts run
(the term arena's frozen columns, the size-change composition and the
multiplicity fold, below); its growing context table is base's `IOArray`
behind an `IORef` (`Libraries.Data.Table`). Upstream's API package needs
`network` for the IDE mode's socket; nothing here does. A program over
the checker (the frontend compiled by itself) names it with `-p
idris-mlir-checker`.

To this compiler the checker is a trusted library of its own, as base is
(`Compiler` in `IdrisMLIR.Registry.Libraries`): a module whose TTC is
installed in the package `idris-mlir-checker` may be imported by a program
and is admitted whole, so the frontend compiles as a program over it. The
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
  are gone, and `Idris.Env` lists only the variables the checker's code and
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
  disabled. The checker decides by modification time only, and a TTC no
  longer carries a source hash.
- **The run-time case tree.** Upstream built, for every definition, a second
  tree for its back ends, with erasure, `%transform`s and `%spec`
  specialisation applied (`mkRunTime`, `compileRunTime`, `Core.Transform`'s
  use in elaboration, `TTImp.PartialEval`, the case builder's `RunTime`
  phase and its `-Xcase-tree-opt` heuristics), and the TTC dropped it; the
  namespace `TTImp.PartialEval` named its specialisations in
  (`partialEvalNS`), which every context made visible, went with it. The
  frontend translates the compile-time tree, so none is built: a `PMDef`
  holds that tree and, per clause, the patterns the case builder read, and
  references are what that tree refers to (`refersTo`). A `%transform`,
  which only a trusted library writes (a user module's is refused), is
  elaborated as upstream elaborates it, its right side checked against its
  left's type, and kept nowhere: no table holds the rules and a TTC writes
  none, and an implementation no longer makes a rule for each of its
  methods, since nothing reads one. `%spec` is still read, as a hint this
  compiler need not apply; a case block is no longer marked for inlining
  by the run-time tree's shape.
- **Counts, state and options nothing needs**, all gone: the search
  timer, never started and checked at every unfolding, with
  `%search_timeout`; `%foreign_impl`, stored and read by nothing;
  `--debug-elab-check`, a second conversion check behind a flag; the
  elaborator's `delayDepth`, counted and read by nothing;
  `processTTImpFile` with the raw TTImp parser (`TTImp.Parser`), which
  nothing called; and the counts that decided whether a program
  elaborates, `%ambiguity_depth` and `%auto_implicit_depth` with every
  depth of the automatic search (below).
  The parser no longer knows a removed pragma, so a module that writes one
  is refused where it writes it.
- **Windows's path grammar.** `Libraries.Utils.Path` read every path with
  Windows's grammar on every platform and asked the host's operating
  system at run time where it differed (`isWindows`): a backslash
  separated, a leading `x:` was a disk volume and the names ended at the
  first `:` or `?`. A path is now an optional root and the names after it,
  split at `/` alone; `Volume`, `dirSeparator`, `pathSeparator` and
  `pathLookup` are gone.
- **Shell scripts and executables in packages.** A package's `prebuild`,
  `postbuild`, `preinstall`, `postinstall`, `preclean` or `postclean` runs a
  shell command; the checker refuses such a package with an error naming the
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
  modules import it by this name; renaming it would change each of them
  and gain nothing.
- `Idris.REPL.Common`: trimmed to printing messages, warnings and errors,
  which `Idris.ModTree` and `Idris.Package` use.
- `Idris.IDEMode.Holes`, without the IDE protocol: how a hole is printed,
  which `Idris.Doc.Display` uses (`Idris.Error` → `Idris.Doc.String` →
  `Idris.Doc.Display`).
- `Protocol.Hex`: hexadecimal digits, which the lexer
  (`Parser.Lexer.Source`) uses.

### Honest code

This compiler compiles the checker, and refuses `%unsafe` definitions and
`%foreign` without a primitive, so the checker has none of them, and no
`idris_crash`. Where upstream coerced, the checker does what the coercion
claimed, with the same results (but for one upstream crash, below). An
`assert_total`, `assert_smaller`, `believe_me` or internal error of ours is
a missing type or a missing proof, wherever it is and whatever reaches it,
and the type or the proof replaces it; one stays only for a fact not known
until the checker runs (the bytes of a TTC, a file read, what a user
wrote), and says which fact. What the checker trusts beyond that is stated
in one place, `Idris.Host` (below): the operations whose termination
Idris's totality checker cannot follow, and the facts of the evaluator
that no proof can reach. The hosts' partial primitives are reached through
the prelude's own total functions and methods (`Core.Primitives.Host`), so
nothing is asserted of them, and a TTC's integer is written by a recursion
on Nat's arithmetic that ends by its own proof (`Core.Binary.Prims`).
Where the frontend calls the checker, the next section says what replaced
upstream's assertions.

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
  `IsDefined` hides the name of the variable it found; `extendEnv` reads
  the type's scope in the pattern's, its top variable labelled with the
  pattern's name (`compat`), since a variable is its position and its name
  a label; and the case builder
  groups clauses by comparing constructor names and tags, and constants
  as upstream's semi-decision did (never two doubles, and primitive types
  as `primTypeEq` relates them). `substName` compares.
- Base's `strM` view coerces its proof with `believe_me`, and its `ltrim`,
  `trim`, `parsePositive` and `parseInteger` see a string through it. The
  checker matches on `strUncons`, and trims and parses numbers with
  `trimStart`, `trimSpace`, `parseNatural` and `parseSigned`
  (`Libraries.Utils.String`), which see the characters and give base's
  results.
- A `with` clause's function is over the part of the environment its
  value, the value's type and the outer environment mention, closed under
  the binders of what they mention (`Core.Env`: `cover`, `closed`): each
  term is covered by the part of its scope it mentions and thinned into
  the whole part, and the part's environment is built as the part is, so
  nothing is strengthened into it and the function's type binds that
  environment as built (`bindReq`). Upstream strengthened the value, its
  type, the environment and each binder of it in turn, each able to fail
  ("With abstraction failure #1" to "#4"), and left the value's type out
  of the part, so a type that mentions more than its value could fail.
- Solving a hole uses the definition its caller found and checked to be a
  hole (`solveHole`), where upstream looked it up again and threw an
  internal error if it was not there.
- `%start` names the expression a REPL session runs first; this compiler
  runs no REPL, so the pragma is refused, as unsupported, where it is
  written. Upstream threw an internal error ("%start not implemented").

### Total where the frontend calls it

The frontend is total, and calls the checker; what it calls and Idris's
totality checker can follow is total here, by a structural or well-founded
argument the totality checker accepts, with no `assert_total` and no count
that makes a recursion stop. Upstream traversed a term's binders, a
metavariable's arguments and a case's alternatives through `map`,
`traverse` or an interface's own method, which the totality checker cannot
follow; here each kind of node that holds terms has a function of its own,
so that every recursive call is on a part of its argument:

- weakening, thinning and shrinking a term (`Core.TT.Term`: `insertNames`,
  `thinTerm`, `shrinkTerm`), stripping and restoring a namespace (`onRefs`,
  `onTreeTerms`), `substName`, `refsToLocals`, `getRefs`, `getMetas` and
  `addRefs` of a term and of a case tree, showing a term (`showTerm`), a
  case tree and an error (`showError`, which shows each error a list holds
  by a function of its own), and a term's hash (`hashTerm`), all with the
  output upstream's gave;
- a term's names made full or resolved (`HasNames` of a term, a case tree
  and an alternative, in `Core.Context`): one traversal each
  (`onNamesTerm`, `onNamesTree`), given what becomes of a name and of a
  metavariable (`OnNames`), where upstream wrote each twice. Resolving a
  type's definition leaves its constructors as a TTC holds them, by their
  full names, which is what upstream's `full` gave there; upstream's lookup
  there made decoding a definition able to look up, and so decode, another;
- decoding a TTC (`Core.TTC`): a name, a term and its parts, and a case
  tree and its alternatives are decoded by functions given the bytes left
  to read and their accessibility (`Control.WellFounded`), which each passes
  on to its parts once it has read its tag (`fewer`, `Core.Binary.Prims`):
  the bytes of the buffer are the measure. `fewer` decides with one
  comparison and keeps its proof erased, so no unary proof is built while
  decoding. Every other instance a
  definition is decoded through holds none of its own type, but an
  environment, decoded along its scope. A term and a case tree are also
  written by functions of their own (`encodeTerm`, `encodeTree`), since a
  decoder that names an instance reaches its writer too; the bytes are
  upstream's. (An `Integer`'s writer, reached that way and never run by a
  decoder, splits it into limbs by a `covering` recursion, which ends by
  the primitive shift's behaviour, a fact no type here states.) A
  decoded
  definition is resolved by `storeDecoded`, which looks up no
  definition, and a name is looked up
  by turning it into its index once (`lookupContextEntry`), where upstream's
  `lookupCtxtExactI` called itself on the index it found and
  `lookupCtxtExact` repeated it. So `decode` and `lookupCtxtExact` are
  total, and so are `lookupCtxtName`, `toFullNames` at a name and a term,
  and `isPairType`;
- the parser (`Libraries.Text.Parser.Core`), which is upstream's again: a
  `Grammar` is upstream's data type, read by `doParse`, and the
  combinators of `Libraries.Text.Parser` and the grammars over them are
  upstream's, guarded by the constructors `>>=`, `>>` and `<|>` stand for,
  with no assertion. `doParse` itself recurses on the grammar but for the
  grammar after one that consumed, which a function makes: there it
  recurses on the tokens left and their accessibility, and every result
  carries, erased, that it leaves fewer tokens than it was given if its
  grammar consumes and never more (`Leaves`), where upstream asserted
  both recursions total. What differs from upstream: the tokens are
  columns (`Tokens`, made by `columns`), a token at the number of tokens
  after it, so the parse's position is the count of tokens left and the
  next is read at one less; `parse` and `parseWith` take the columns and
  give back no tokens left, so a grammar that must read them all ends
  with `eof`; `parseWith` takes the state to begin with, which a grammar
  changes by `updateState` (the constructor `UpdateState`), a step that
  gives a value, where upstream's `act` appended to a monoid (a branch
  that fails drops its steps, as it drops its warnings); a sequence's and
  an alternative's consumption flags are erased, so `map` is one
  implementation for every grammar; `terminalAt` is `Position` then
  `Terminal`; the location of `failLoc`, `fatalLoc` and
  `mustWorkBecause` is a `Maybe Bounds`, as a result's bounds are; and
  `mapToken`, which nothing used, is gone. (`Idris.Parser` is total by
  its grammars' types; only `parseFile`, which reads a file, is
  `covering`.)
- `mkdirAll` (`Core.Directory`) is done at once when the directory exists,
  and otherwise creates the path's prefixes, outermost first, as a walk
  over its body, passing those that exist already;
- the checker's size-change decision (`loopsTerminate`), the one closure
  behind every verdict on whether a recursion ends: the frontend asks it of
  each component of its program, and the elaborator's termination check
  (`calcTerminating`) asks it of each component of the unchecked functions
  a checked one reaches, where upstream closed the graphs of every pair of
  them. A walk is a dense graph and the calls it makes, typed by the
  functions it starts and ends at (`Walk n from to`), so walks join only in
  path order (`andThen : Walk n a b -> Walk n b c -> Walk n a c`, the
  matrix product of the later graph by the earlier in the size-change
  semiring, `contract` of `mlir-array`, since a call's rows are the
  callee's arguments). Each function keeps only the weakest walks to it,
  and a walk back to the searched function is judged as it is found: its
  powers are taken until one repeats, and the one that goes round twice as
  it goes round once either decreases some argument or is the loop the
  answer names (`Loops`: `Decreasing`, or `Endless` with its calls, which a
  check's message lists). A check that finds such loops reports the
  greatest of their functions by name. The graphs' rows are a finite type
  (`Libraries.Data.List.Finite`), and each search keeps every graph, or
  pair of a function and a graph, it meets once, in a list without
  duplicates that the pigeonhole principle bounds by the type's values; the
  room left is the measure (`Control.WellFounded`).
  The repository's `tests/checker-loops-terminate` runs it on
  components whose verdicts flip if paths are joined the wrong way round.

The evaluator (`Core.Normalise`) and the elaborator are not total, and
cannot be: Idris's type theory is not strongly normalising, and checking a
program evaluates whatever its types compute. The frontend reaches them
through `normalise`, `normaliseTypes`, `normaliseHoles` and `buildMain`
(below), building packages, and the termination checker
(`checkTerminating`), which reads each definition through the evaluator.

`Idris.Host` is the checker's own module (no file of Idris's has it): the
one record of these operations, a field each, and its one value, `host`,
whose `assert_total` is the checker's statement that each returns. The
checker is a library this compiler trusts, so its own assertions are
admitted, where the same assertion in the frontend's modules, which are
the program's, would be refused; the frontend calls these operations only
through `host`.

`Idris.Host` also states the one fact of the evaluator's results no proof
of the frontend's can reach, of one context: `frozenFrom`, called once
the frontend's reading has read every definition the program can meet,
each decoded once by Idris's lookup where it was read, holds exactly those
definitions in an immutable map by entry (`Frozen`), which every statement
and normaliser is indexed by, so a definition the program cannot meet is
never decoded; what the reading holds at an entry is the map's definition
there (`IntMap.lookupMap`, `heldAt`). A name resolves to an entry (`Resolves`), a
definition is the one at its name's entry (`Defines`, read purely by
`definitionIn`), and `definedOnce` is proved, not trusted. A closed term's
normal form, as each of the four normalisers gives it, is a reduct of the
term by that normaliser's steps and normal for them (`Reduct`, its steps
and its normality at quantity 0); the steps are the evaluator's options
as each normaliser sets them (`Evaluation`: which definitions it unfolds,
whether it runs only holes, as every one does under a delay, whether it
keeps an as pattern). `Reduces` declares every step, blind to locations:
under every node, beta of a lambda, a definition's leaf (a projection's
among them), a solved unknown, and the rest the evaluator also does (a
`let`, a primitive from the evaluator's own table or `believe_me`, a
forced delay, an as pattern, a nullary type's name, what it does with a
head that is applied but takes no argument), so the statement is true of
every term. A case tree's alternatives are tried in order (`Picks`): a
constructor's alternative is the one whose name resolves to the
scrutinee's head's entry, and a default is taken only past alternatives
that miss. The other facts trusted are of the same kind: a definition's
type and tree, read through the context's accessors (`host.typeOf`,
`host.treeOf`), are the evaluator's, one each (`typeOnce`, `treeOnce`);
every term a term reduces to reduces on to its normal form
(`reachesNormalForm`), the confluence Idris's type checker rests on.
Reduction is closed under putting values in for bound names
(`substitutes`), which is proved.
Over the frozen context, making names full is a function (`fullNamesIn`),
so that it only renames is its definition. A frontend that proves its
readings sound against `Reduces` keeps no check, when it runs, that the
evaluator agreed with it.

### Changed from upstream's form

Each of these differs from upstream's form because ours states more, for
the reason given. Where upstream passes types around, ours states the
types it means: no type is held when the checker runs, no constructor
holds a field whose type it hides, and no type is computed from a value
known only when the checker runs.

- `Core.WithData`: a payload with metadata is a record of its own for each
  combination of metadata used (`WithFC`, `WithName`, `WithFCTyName`,
  `WithFCNameArity`, `WithRigName`, `WithFCRigName`, `WithNameOpts`,
  `WithRigMName`, `WithFCRigMName`, `WithDocFC`, `WithFCDocRigNames`,
  `WithNameRigTot`), each field at a fixed type, so a projection is the
  record's own (`.fc`, `.name`, `.rig`, `.val`) and an update is record
  syntax. Upstream's was one extensible record over a list of labels and
  types, which held the list at run time, computed each field's type from
  it, found a field by its label's text and passed a dictionary per field
  to write or compare one. `WithFC`'s constructor is `MkFCVal`, the
  reflected `WithFC`'s. Each combination is functorial in its payload, has
  a `traverse` in `Core` where one is traversed (`Core.Core`), and has a
  `TTC` where one is written: its fields in order, each after a 1, then a
  0, then the payload (`Core.TTC`, and `TTImp.TTImp.TTC` for
  `WithNameOpts`), the bytes upstream's record wrote.
- `Idris.CommandLine`: an option's argument is a case of `OptArg` that
  names the type its action is given (`Required` a `String`, `RequiredNat`
  a `Nat`, `AutoNat` a `Maybe Nat`, ...); every option takes at most one.
  Upstream's option held a list of argument descriptions and an action
  whose type that list computed (`ActType`).
- `Libraries.Data.Version` reads a token's text and converts it where it
  reads a number (`number`); upstream's token kind computed the type of a
  token's value from the kind (`TokenKind`'s `TokType`).
- `Idris.Syntax`: a directive (`Directive' tm`) is over what its `%start`
  expression holds: the parse tree's node while parsing (`Directive' (Id
  FTerm)`, in `Idris.Syntax.Tree`) and a `PTerm' Name` once decoded
  (`Directive`). Upstream's `StartExpr` held a term at a name type the
  constructor hid, so nothing could read it back at a known type; the
  parameter states it, and the parse tree and the decoded syntax share one
  declaration.
- `Parser.Rule.Source.decorationFromBounded`: a parser's semantic
  decoration holds no name, and `decorate`, `dependentDecorate` and
  `decorateKeywords` (`Idris.Parser`) take the type of what they decorate
  erased. Upstream's matched on that type at run time and kept the value
  when it was a `Name`, for the IDE's metadata, whose adders are no-ops
  here (Stubbed, above): the name had no reader, and the rules are
  parametric in what they decorate.
- `Idris.Syntax.Traversals` traverses a list of paired terms (`PList`,
  `PSnocList`, `PUsing`, `PInterface`, `PImplementation`) with `traverse`
  and `map` over the pair's second component, where upstream wrote
  `goPairedPTerms` and `goPairedSnocPTerms` by hand in each traversal.
- `convertMatches` (`Core.Normalise.Convert`) binds its scopes as `Scope`;
  upstream's `{vs, vs' : _}` made them lists of a type nothing fixed.
- `OperatorLHSInfo` (`Core.TT`) is a family over `Type`, as its
  constructors use it; upstream declared it over a value of an implicit
  type (`tm -> Type`), which every use instantiates at `Type`.
- `Libraries.Text.Lexer.Tokenizer.compose` is upstream's `Compose`, made
  `public export %tcinline` so that the totality checker sees the
  recursion of `rawTokens` and `stringTokens` (`Parser.Lexer.Source`)
  through it guarded by the constructor.

### Ours

- Every identifier is interned (`Core.Name.Ident`). A process holds one
  table of every text it has met as an identifier, each once at its own
  id, kept by the context across resets and backtracking
  (`Context.idents`), so two identifiers are equal exactly when their ids
  are: a name's leaves (`Basic`, `Field`, `MN`, `DN`, a namespace's parts)
  are identifiers, and comparing names compares ids, never text. The text
  is the identifier's own, held once, for printing. Text becomes an
  identifier only where it enters: between lexing and parsing, where the
  lexer's tokens (`RawToken`) become the parser's (`Token`); in a TTC's
  reader (`TTC Ident`, through the `TTC` interface's table); and where the
  elaborator makes a name from text (`Core.Context.intern`). A keyword, a
  reserved symbol and a pragma are no identifiers: the lexer gives each as
  its kind (`Parser.Lexer.Reserved`'s `Keyword` and `Reserved`, and
  `Parser.Lexer.Pragma`'s `KwPragma` with its tag in a TTC, printed by the
  same generator from their lists), so the parser compares kinds, and an
  identifier the grammar reads as a word (`as`, `on`, a fixity) by its id;
  upstream compared their text in every rule that read one. The
  identifiers the compiler's own code spells form a closed vocabulary
  (`Core.Name.Known`), each at an id the table holds before any other text,
  so a builtin name is a constant and never looked up. The vocabulary is
  one list of pairs, a constructor and its text (`known/Vocabulary.idr`),
  from which `knowngen` (`known/`) prints the module, so its constructors,
  texts and ordinals cannot disagree. Identifiers order by their text, so a map or a sort
  keyed by names, and everything written from one, is in the same order in
  every session; a TTC writes each identifier as its text, never an id.
  Upstream's leaves were strings, compared character by character by every
  equality and every map lookup.
- A definition read back from a TTC is stored (`Core.TT.Stored`): its
  terms are columns in preorder, one node per distinct subterm of the
  definition, children by position, with every occurrence's location in
  one more column, frozen as `mlir-array` arrays, so every read is a pure
  read of an immutable value. A term being elaborated stays a located
  tree, and a definition of the module being checked stays live until it
  is written, so a definition's terms are held by their lifetime
  (`Typed`, `Body`: live or stored), and every reader asks one accessor
  (`typeOf`, `treeOf`, `clausesOf`, `clausePatsOf`, `walkTree`), which
  decodes a stored term where upstream rebuilt the live one (`embed`).
  The evaluator walks a stored case tree along the path it takes and
  decodes only the right-hand side it reaches. Definitions name one
  another by interned name, never by position, so nothing is shared across
  definitions and no table grows under a read. A TTC still holds trees.
  What a read relies on (a child is a node of the arena, a node's slots
  are its own and its parts', its bound bounds its locals, a root's
  locations are in the column and its scope holds its locals) is decided
  once, where the columns are made (`seal`, `rootAt`), and carried,
  erased, by the arena and each root, so decoding a stored term, and
  reading what its type computes, check nothing and cannot fail. Freezing
  lays all of it; it is decided there rather than proved only because a
  type knows nothing of an `mlir-array` array element by element.
- The parser makes a flat parse tree (`Idris.Syntax.Tree`): a node for
  each form of the syntax it parses, made in the parse's state, so a
  branch that fails drops its nodes; children before parents, each node
  holding its location, its children's ids and how many nodes it unfolds
  to; a subtree the grammar writes twice (a data type's return type in its
  constructors, a tuple section's variable) is one node. Once the parse is
  done the nodes are frozen into columns and decoded into the `PTerm`s,
  clauses and declarations Desugar reads. What upstream's grammar read back
  from the terms it had built is read from the tree: a hole written as an
  argument is bracketed in the node made last, a `with` clause written
  `_` relocates its parent's left side in a node, the hole names are those
  of the hole nodes, and decoding groups neighbouring clauses into
  definitions (`collectDefs`) and decides whether a `let` in a `do` block
  binds a variable. Each form's child is decoded by a decoder of its own
  (`childTerm`, `childClause`, ...), at the type of the syntax that form
  is, so what a child decodes to is fixed by its form's type, never
  computed from a form passed as a value; a list of children is decoded
  with `traverse`, and the measure each descent rests on, that a child
  unfolds to fewer nodes than its parent, is decided in one place
  (`fewer`).
- A package the build adds is recorded with its name and version, as its
  directory names them (`PackageDir`, `addPkgDir`), and each TTC the
  session reads with where the search found it (`Loaded`, `Found`: the
  build directory, a package, an import directory), where upstream kept
  the directories as text and a reader took a TTC's path apart to learn
  its package.
- The elaborator keeps its own union-find (`Libraries.Data.UnionFind`:
  persistent, every member naming its root, the smaller class renamed on a
  merge; it merges and finds, and never searches) as the constraint
  store's index. Meta-to-meta unification makes an unknown solved as
  another's application one class with it (`mergeUnknowns`), and each
  class holds the searches waiting on it: a search that failed and changed
  nothing waits until an unknown its goal reaches is solved or made
  invertible (`wake`). The solver's first round retries every guess, as
  upstream's did; each later round, semi-naively, passes the searches that
  wait, where upstream retried every guess until none progressed. Only a
  search waits: its failed retry restores the state it ran in, so passing
  it changes nothing a TTC records, where a unification constraint's failed
  retry posts new constraints and names, and is retried as before.
- The context's definitions (`content` of `Core.Context.Context`) are a
  `Table` (`Libraries.Data.Table`): base's `IOArray` behind an `IORef`.
  Upstream's was an `IOArray` made with 10000 slots and moved to a copy
  10000 slots longer each time it filled. The table starts with room for
  as many and grows to at least twice its capacity, so claiming n slots
  copies fewer than 2n entries in all; every read and write is in place.
  Its size is the high-water mark of
  `nextEntry`: restoring a saved `Defs` lowers `nextEntry` and the table
  keeps its slots, as upstream's array did, so `newEntry` claims the slot
  past the last only for an index never handed out. A lookup outside the
  table, or of a slot not yet written, finds nothing, as upstream's
  `readArray` did. `getContent` and `setNextEntry`, which nothing called,
  are gone (the latter was the one way to raise `nextEntry` past the
  table). Decoding a definition from its TTC writes it into the table as
  it is when written; upstream wrote it into the array it had read before,
  where a write after a growth was lost and the definition decoded again
  on the next lookup. Resolving a decoded definition's names looks up no
  other definition (`storeDecoded`), so decoding one never decodes
  another.
- `normaliseTypes` (`Core.Normalise`, the evaluator's `evalTypes`) is the
  normal form this compiler's translator gives a type. It unfolds, besides
  what Idris's own normalisation unfolds, any definition that computes a
  type (its type is a universe after its arguments, seen through the names
  that type is written with, `VarSet : Scoped`, each followed once, so that
  an alias that leads back to itself computes no type), whatever its
  visibility,
  so that a private type-level function of another module reduces. It
  keeps an implementation as it is written, which is the value a type
  holds: unfolded, an implementation is a record of its methods, each
  quoting the implementations it is built of unfolded again, so the
  normal form multiplies at each level of nesting (`Ord (a, b)` over
  `Ord (List (Nat, List (Nat, Nat)))`). A match that takes an implementation
  apart unfolds it (`unfolded`, in `evalTree`), so a type computed from an
  implementation's method still reduces.
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
- The primitives are one table, each with its name (`allPrimitives`), so
  a name is known only for a primitive the table holds; upstream named any
  operation at any type (`opName`), `prim__add_String` among them.
- Where the evaluator does compute a primitive (`getOp`, `sharedOp` in
  `Core.Primitives`), it calls the primitive of the same name
  (`prim__add_Int`, `prim__cast_CharString`, ...), so the result is what
  the runtime that runs the compiler computes, not an Idris program
  written to agree with it: Chez's at stage 0, this compiler's runtime
  once idris-mlir compiles the checker. Upstream computes each with Idris
  code (`x + y`, `cast`, `show`); the two differ only for a Char's text,
  which upstream writes as `show`'s escape (`cast '\n'` is `"\\n"`).
  Which calls reduce is unchanged
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
  `delayElab` take is given it too, with the expected type, rather than
  capturing either: upstream's closures captured `Ref UST UState`, so the
  cell's type reached itself, and a glued type holds computations, which
  the pipeline's closure analysis merges with every computation of their
  type, those that read the cell among them. A retry is given the type's
  term, taken when the elaborator was delayed, evaluated again (`gnf`),
  as upstream's record and ambiguity elaborators recomputed it for their
  second attempt, where its case, delay and record check reused the
  glued type they were first given. Each
  elaborator is a function of its own (`checkCaseDelayed`,
  `checkUpdateDelayed`, `checkDefaultDelayed`, `checkAlternativeDelayed`,
  `checkRewriteDelayed`, `checkDelayDelayed`), and the stored closure
  sets the holes its elaborator may not solve through `withNoSolve`,
  because a local definition (a case, an `if`, a record update) is
  applied to everything its parent binds, and one in the closure would
  capture the parent's cell. For the same reason the function a nested
  name holds (`applyEnv` in `elabImplementation`) names no local
  definition. A pragma
  (`IPragma`) holds `Pragma` data (`TTImp.TTImp`), one constructor per
  action desugaring makes, with that action's arguments and no function,
  where upstream's held the action as a closure over the cells desugaring
  had. `process` interprets
  it through `processPragma`, declared in `TTImp.ProcessDecls` and
  defined in `Idris.Desugar`, above the interface and implementation
  elaborators, with every cell in hand, `Ref Syn SyntaxInfo` among them,
  which `TTImp.TTImp`, below `Idris.Syntax`, cannot name. A cell holds
  terms (the delayed elaborators do, and `SyntaxInfo` holds an
  interface's parents and default methods, `usingImpl` and `startExpr`)
  and a term's local block holds declarations, so no declaration holds a
  closure, and no cell's type reaches itself through one. `Pass`, which
  the implementation's action takes, lives in `TTImp.TTImp` for it. The other
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
  ten, so a TTC either one writes is refused by the other when read. A TTC
  holds its extra data as a blob of its own, so a reader that does not know
  its type reads the definitions past it (`readDefinitions`), as the
  termination check does for the modules a context's imports reach.
- `buildMain` (`Idris.ModTree`) builds a main file in a session of its
  own: it makes the unification state, the delayed elaborators and the
  metadata, resets the context to the main module's origin and runs
  `buildDeps`. A driver that only builds a program, as the frontend's,
  never holds the session's state, which holds the evaluator's values.
- The automatic search ends by construction, with no count. Before it takes
  up a goal that is a type constructor's application, it compares the goal
  with each earlier goal of its path of the same type constructor,
  argument by argument, by homeomorphic embedding (unknowns one symbol,
  the search's own locals one symbol, universes one symbol, an integer by
  its magnitude, a string as a subsequence, any other constant by
  equality): a goal convertible with one before it fails that step, as
  upstream's cycle check did; one that embeds an earlier goal ends the
  search with a growth, a case of the search's result (`Searched`: `Found`
  or `Grows`) beside its failures, so no combinator can catch it as a
  failed branch and let a sibling answer. A growth through unknowns waits
  for a later round, and at the last chance, as one with everything known,
  refuses the program (`GrowingSearch`). Kruskal's
  tree theorem makes every endless path meet such a pair. A program the
  stock Idris elaborates with a large enough `%auto_implicit_depth` is
  elaborated the same, but where its answer was the depth running out.
- Overloaded names are resolved with no count: every candidate elaborates
  smaller parts of the source, so resolution ends, and `%ambiguity_depth`
  only refused programs (`printLn (1, 2, 3, 4, 5, 6)`) or let a candidate
  win because another ran out. The syntax
  that writes a type and its value alike, `(l, r)`, `()` and `(x ** p)`,
  is one node (`ITypeOrValue`) holding its parts once, where upstream wrote
  a list of two candidates each elaborated in full, nested at each level of
  a tuple. Its reading is the expected type's sort (`Universe`, `Known`,
  `Unknown`): a universe takes the type, any other known type the value;
  under an unknown type a pair's parts are elaborated once, against fresh
  unknowns, and the site waits, retried with no new elaboration until its
  sort is known, and at the last chance takes upstream's rule (the reading
  that alone adds no constraint, else the value). Elaborating a tuple is
  linear in its size. Where its two readings are different terms (a
  dependent pair whose name is bound implicitly or substituted, an idiom
  bracket), it is the generic alternative of its two readings.
- A quote that follows stuck applications only so deep (`quoteWithin`)
  returns the term or `TooDeep`, and its callers choose another quote by
  matching, where upstream threw an internal error that each caller caught
  with every other error. The depths, `%nf_metavar_threshold` among them,
  decide only a stored term's form, never whether a program is accepted.
- A parser's result is `Irrelevant` (parsed from no input) or `Relevant`
  with its bounds, and a lexer's token is `Located`, always with its
  bounds: upstream kept a flag beside bounds that were junk when it was set,
  so mapping a result or sequencing it after `pure` changed its bounds.
- A case or with block's name holds its parent's full name and its ordinal
  among the parent's blocks (`CaseBlock`, `WithBlock`), where upstream
  held the parent's printed text and the session's machine-name counter;
  messages print the parent as upstream's did.
- A type's parameters are read off its constructors' types in normal form,
  so a constructor whose binders come through a definition
  (`a -@ LList a -@ LList a`) has them.
- `ZeroOneOmega` is public, so a reader matches on a quantity.
- A record update names the record it updates by the type it is expected
  to have, or, while that is not yet a type constructor's and the record
  is a variable, by the variable's type (`updatedRecord`); it is still
  checked against the type it is expected to have. Upstream waited for the
  expected type, so an update of a variable in a let without a signature,
  whose type only a later clause of a case fixes, was refused.
- No count bounds a recursion of the checker's own: the evaluator's `fuel`
  and per-name `reduceLimit` options, which nothing set, are gone; the
  size-change decision takes a loop graph's powers until one repeats,
  judging each as it comes, where it searched for the idempotent one for
  at most 1024 powers; and `normaliseTypes` follows each name once (above),
  where it stopped at a depth of 8.
- `processDecls` and `processTTImpDecls` (`TTImp.ProcessDecls`) return
  nothing: upstream's returned `True` whatever happened, an error being
  thrown.
- Whether a recursion is total depends on no count. `sizeCompare`
  (`Core.Termination.CallGraph`) compares each pair of subterms, named by
  its two paths of `Step`s, once (one memo per comparison of an argument
  with a parameter), which bounds the work by the product of the terms'
  sizes, where upstream looked under matching constructors only
  `%totality_depth` deep (default 5); an as pattern's sides are joined
  with `|+|`, where upstream kept the first known answer, so an answer
  could weaken with depth. The pragma is refused; every program upstream
  accepts is accepted.
- A binder's quantity is the sum of its uses in 0/1/ω, folded in one pass
  over the uses by `accumulate` of `mlir-array`, each use naming its
  binder, where upstream counted each binder's uses by a scan of the list
  (`count`); closing a binder's scope sums its own uses and keeps the
  others' (`Core.LinearCheck`: `Uses`, `usesOf`, `closeScope`).
- Bugs of upstream's code that the frontend met are fixed here: a `let`
  whose value applies an overloaded name to a linear variable elaborates
  at multiplicity one when exactly one candidate fits there
  (`misusesLinear`, `TTImp.Elab.Delayed`), where upstream refused it; an
  interface body holding a declaration it cannot hold (a data type with
  constructors, a record, a namespace, `parameters`, a nested interface)
  is refused where it is written (`Idris.Elab.Interface`), where upstream
  dropped it silently; a with application in a local block's definitions
  or a record update's fields is rewritten (`TTImp.WithClause`), where
  upstream refused it; a definition's erased positions are found again
  once its clauses are checked against its whole spine (`updateErasable`,
  `TTImp.ProcessDef`), where upstream fixed them where the type is
  declared, too few when the type reaches its binders through a
  definition declared before and defined after. The others are bugs the
  stock Idris still has: a primitive applied to constants and a Char's
  text (above), the size-change decision (above), a checked clause marks
  the arguments it leaves to unification, the termination check reads a
  callee its module does not import (above), a case tree splits what a
  clause leaves to unification after what it writes, a constructor's
  left-out implicit is marked, at quantity 0 a constant or type written on
  an erased argument splits, a case block where a delayed value is
  expected is delayed whole, its scrutinee with it, and a literal's
  conversion is folded only to a value, never to a stuck partial normal
  form. Others the stock Idris
  that bootstraps is patched for, and the checker has as its own code, so
  that both hosts accept the same definitions:
  104-coverage-repeated-split (the walk that proposes missing cases keeps,
  per variable of the tree's scope, what it stands for in the patterns
  built, a `Built` pattern looked up by the variable's index, so a split of
  a variable split further up binds its arguments to the first split's
  parts, and is taken only by that constructor's alternative),
  105-case-tree-fallthrough-copies (each copy of a fallthrough tree keeps,
  of its cases on the variable just split, only the alternatives that can
  still be taken there, `pruneCase`), 107-delayed-case-expected-type (a
  delayed elaborator runs at the type its hole was given, so a case block
  always has its type, and makes none of its own),
  108-case-split-pattern-fragment (a case function that splits a variable
  every clause splits, and that an unsolved metavariable after it is
  applied to, takes it twice, split and unsplit at quantity 0, the
  metavariables applied to the unsplit one, `Taking`),
  109-delayed-retry-doubling (a delayed elaborator that failed recoverably
  is not run again while every metavariable unsolved when its failing
  attempt began is still unsolved; its error stands for the run),
  110-coverage-erased-index-first (the tree an erased definition's coverage
  is checked by takes next, of the columns `arrange` splits now, the first
  one a run keeps, or else the last), 111-coverage-nested-empty-type (a
  type is empty also when each constructor that fits it takes an argument
  of an empty type, as it is or read under what the others hold: a type
  with one constructor holds the equations its constructor's return type
  holds of it and those its arguments' types hold, `Inhabitants`, and a
  fresh name an equation solves is put into the arguments' types that name
  it; each is looked into only while it has fewer nodes, a descent the
  search carries as the accessibility of the count, and the fresh names are
  numbered across the whole search, so putting one's term into a type
  captures no other), 112-do-local-definition-scope (a do block's bound,
  let-bound and locally defined names are bound for its later types, as
  its translation into lambdas and `let ... in` binds them),
  113-type-implicit-binding-order (a type matches the arguments of the
  applications its postponed constraints relate before its defaults and
  before an implicit still unsolved is bound as an argument of it, as a
  term's elaboration does; a left-hand side and the coverage check, where
  such an implicit becomes a pattern variable, keep their order,
  `checkBindHere`) and 114-let-delayed-elaborator-dropped (`runDelays`
  keeps aside the delayed elaborators it does not run and puts them back
  for the retries around it, so a let's value, which runs its case blocks
  first, loses no ambiguous name's). Each is checked by
  `tests/checker-<name>`, a program idris-mlir compiles. The cost
  106-size-change-call-paths removes was never the checker's: a walk's path
  joins its two parts as one node, and only a reported loop's calls are
  listed.

### What a TTC keeps

Every definition the frontend reads comes back through a TTC, a main
file's included (`buildMain` reads it back once built). Upstream's TTC
drops facts the elaborator had, and a frontend reading it can only guess
them again. The checker's TTC stops matching upstream's here, and only this
way (the owner, 2026-10-19: stop recomputing, without bugs from loose
representations):
- It keeps what Idris computed and decides nothing new: a type, a
  location, a clause's index, a block's parent is written and read back.
  An analysis of the frontend's stays in the frontend.
- It keeps exactly the fact, in Idris's own type: a `Name`, not its print;
  the index, not a count rebuilt; the `Term`, not an `Erased` placeholder.
  Nothing stands for "absent" (no `STerm 0`, `emptyFC` or `""`) and no
  `Maybe` holds what Idris always has. Where Idris itself holds a loose
  form (a case block's parent as `prettyName` text), the checker stores the
  typed form and prints the text from it where Idris shows it.
- Decoding is total and round-trips: `decode . encode` is the identity on
  every field kept, checked on the TTCs of prelude, base and the test
  programs, and `ttcVersion` moves with each change, so no reader meets a
  TTC of the old form.
- What a reader concluded from the fact's absence is moved to a
  representation of its own first (the frontend's `Erased _ Impossible`
  marker for a run-time value relies on the TTC losing Idris's
  `Impossible`); otherwise the kept fact silently changes the old reader's
  answer.
- Each kept fact deletes, in the same change, the frontend's
  reconstruction of it: the guess, its fallback, its `Maybe`. The facts
  still lost, and the reconstructions waiting on them, are the
  proposal "Each fact once".

Kept so far:
- A `let`'s, a `PLet`'s and a `PVTy`'s binder type; why a term is erased
  (`WhyErased`: a placeholder, impossible, or the term a dotted position
  equals); a case tree's scrutinee type and each leaf's clause index; per
  definition, each clause's patterns as the case builder read them; a
  block's typed parent.
- A term in a TTC keeps each node's location (`Core.TTC`), written after
  the node's tag against the location of the node it is part of, a few
  bytes each, where upstream's writes none and reads every node back at
  `emptyFC`. A main file is read back from its TTC once built, so without
  them no term of the program the frontend reads would say where it came
  from.
- Whether a `Delay` was written or inserted by the elaborator for a
  `Lazy` or `Inf` expected type (`Delaying` on `TDelay`, `NDelay` and
  `PDelay`; conversion and unification compare its laziness only): an
  inserted one stands for the whole expression the expected type delays,
  the `let`s placed around it included, which a reader with eager
  evaluation must tell from a written one.
- A module's imports, each with its location (`Import`, moved from
  `Idris.Syntax` to `Core.Context`), and the pragmas it writes, each with
  its location (`PragmaUse` of a `KwPragma`, one constructor per pragma
  the lexer gives as its kind; the parser's rules take the kind, not text, and
  record each use in the parse's state, which a failing branch drops).
  `readDefinitions` gives both with the definitions (`ModuleFile`), so a
  reader takes them from the TTC instead of scanning the source.
