# Cull audit: the type checker (`compiler/checker/`)

- HEAD at start: `d378e120ee0813b9c170fa5b85c294bc49a45b6d`.
- HEAD at finish: `f1d14600b52ca2b3a7888cfd443201d1c354cfcf`. No commit between
  the two touches `compiler/checker/` (`git diff --stat d378e120 f1d14600 --
  compiler/checker` is empty). The frontend (`compiler/src`) did change; the
  measured candidate (1) was re-run against the finish frontend (below).
- Line numbers are at d378e120, which is f1d14600 for every checker file.
  The working tree differs where other lanes are editing.
- Owner of every path here: **L17** (`audits/p0/verify/ownership.json`:
  `"L17": ["compiler/checker/", ...]`). Where a deletion also touches the
  frontend (`compiler/src/IdrisMLIR/Frontend/`), that half is **L16**'s.
- Read-only audit. Nothing in the checkout was edited. Every number below
  says how it was got; the searches and the commands are written out so the
  evidence stays with the claim. The trimmed build ran on a `git archive`
  export under `/tmp/checker-cull/`. No candidate touches `sources/`.
- Size of the area at d378e120: 208 modules, 76,504 lines of Idris
  (`find compiler/checker/src -name '*.idr' | xargs cat | wc -l` on the
  export). The working tree had 76,720, because other lanes are editing it.
- The 29 files of the area modified in the working tree at finish (`git
  status --short compiler/checker`). A deletion that touches one of these waits on
  the lane holding it: `README.md`, `Core/AutoSearch.idr`,
  `Core/Binary.idr`, `Core/Context.idr`, `Core/Core.idr`,
  `Core/LinearCheck.idr`, `Core/Name/Ident.idr`, `Core/Name/Namespace.idr`,
  `Core/Normalise/Quote.idr`, `Core/Primitives/Host.idr`, `Core/TTC.idr`,
  `Core/Termination/CallGraph.idr`, `Core/Unify.idr`, `Idris/Desugar.idr`,
  `Idris/Error.idr`, `Idris/Host.idr` (−658/+23: D133/C288 in progress),
  `Idris/ModTree.idr`, `Idris/Package.idr`, `Idris/ProcessIdr.idr`,
  `Idris/Syntax/TTC.idr`, `Libraries/Utils/Shunting.idr`,
  `TTImp/Elab/Term.idr`, `TTImp/ProcessBuiltin.idr`, `TTImp/ProcessData.idr`,
  `TTImp/ProcessDef.idr`, `TTImp/ProcessRecord.idr`, `TTImp/Reflect.idr`,
  `TTImp/TTImp/TTC.idr`, `TTImp/WithClause.idr`. On the frontend side,
  `compiler/src/IdrisMLIR/Frontend/Profile.idr` is modified too (L16).

## What reaches the checker

- The checker has no executable. `idris-mlir-checker.ipkg` has no `main`.
  Measured: `grep -n '^main\|^executable' compiler/checker/idris-mlir-checker.ipkg`
  gives nothing.
- Every module of ours that imports a checker module:
  - the frontend, `compiler/src/IdrisMLIR/**` (45 files; the entry point is
    `IdrisMLIR.Frontend.Driver.main`, and `IdrisMLIR.SyntaxSamples` imports
    it too);
  - `tests/checker-loops-terminate/Loops.idr`;
  - `tests/probe-names/Names.idr`.
  - Measured: every `import` of a checker module across `git ls-files '*.idr'`
    outside `compiler/checker/` and `third_party/`. The 35 files under
    `sources/code/` that also match are snapshots and are never built, so
    they are not entry points.
- The test runner (`harness/`) and the stock Idris import nothing of the
  checker.
- Module-level reach: 206 of the 208 modules are reachable by import from
  those entry points. The two that are not are
  `Libraries.Data.List.Quantifiers.Extra` and
  `Libraries.Text.PrettyPrint.Prettyprinter.SimpleDocTree`. Measured: the
  import closure (`/tmp/checker-cull/scripts/closure.pl`) seeded with the
  46 checker modules those files import.
- Module-level reach decides almost nothing here. `Idris.ModTree` imports
  `Idris.ProcessIdr`, which imports every elaborator. So the cull below works
  on functions and features:
  - What the frontend's driver actually runs: `host.buildMain`,
    `host.processPackageOpts [Package cmd (Just file)]` with `cmd` one of
    Build, Install, Typecheck or Clean, `host.emitError`, `addPkgDir`,
    `pkgGlobalDirectory`, `setPrefix`, `setColor False` and
    `setConsoleWidth (Just 0)`. Read: `compiler/src/IdrisMLIR/Frontend/Driver.idr:242-435`.
  - What user code may reach once the frontend's profile has refused
    every pragma outside `discharged`. Read: `Frontend/Profile.idr:110-117,
    140-142`.
  - What the packages the checker builds (`make prefix`, `make libs`) write.

## Method

1. A name-level reachability closure over every top-level definition of the
   checker (`/tmp/checker-cull/scripts/global.pl`):
   - The roots are every name that occurs in the entry-point files, plus
     every block that is not a plain function: instances, data, records,
     interfaces, operators, `%hint`s, and definitions whose type is an
     interface. Rooting all of these is conservative.
   - An edge is a name occurring in a definition's body. Comments and doc
     lines are stripped.
   - Because the closure works by name, a name defined twice keeps both
     definitions alive. So it errs towards keeping code. A use the scan
     cannot see, such as an implicit instance, could still be called dead;
     the trimmed build in (2) is the check against that.
2. Measured: every definition the closure left unreached was cut from an
   export of d378e120 (`/tmp/checker-cull/scripts/cut.pl`), and the two
   unreached modules were removed. The trimmed checker then typechecked with
   the pinned stock Idris (`.toolchain/idris2`, 0.8.0-89ba32eb5):
   `idris2 --typecheck idris-mlir-checker.ipkg`, with mlir-linear and
   mlir-array installed into a scratch prefix. Result: 206/206 modules, 0
   errors, exit 0, wall 3034 s on a shared machine. Log:
   `/tmp/checker-cull/trim-build.log`. Diff: `/tmp/checker-cull/trim.diff`.
3. Feature-level candidates were read from the code, searched, and traced
   to their readers. Each one is marked read, measured or conjecture.

---

## 1. Top-level definitions nothing reaches, and the two unreached modules — DELETE

- **The part.** 293 top-level definitions in 90 files, plus the modules
  `Libraries/Data/List/Quantifiers/Extra.idr` (17 lines) and
  `Libraries/Text/PrettyPrint/Prettyprinter/SimpleDocTree.idr` (133). The
  full list, file by file, as `name:startLine+lines` at d378e120, is the
  appendix. `Idris/Host.idr` is left out here and is candidate 8.
- **The fact it supplies.** None. No reader: the closure in Method (1),
  seeded by every name of the frontend and the two checker tests. Re-run at
  finish with the f1d14600 frontend as seeds: the same set, plus one more
  dead definition (`TTImp.Utils.unique`, 12 lines). Nothing became live.
- **Rule that once required it.** None. These are what was left behind by
  deletions the README records: the REPL, the IDE mode, `--mkdoc`, the code
  generators and the CExp pipeline. By family:
  - 845 lines of printing: `Idris.Doc.*`'s `getDocs*`, `Idris.IDEMode.Holes`,
    and the unused combinators of `Prettyprinter.Doc` and `Control.ANSI.CSI`;
  - 201 of command line and package (`getCmdOpts`, `findNearMatchOpt`,
    `findIpkg`, `findIpkgFile`, `findDataFile`, `cssFiles`, ...);
  - 147 of unused algebraic laws (`Algebra.ZeroOneOmega`'s
    `rig*Associative`/`Commutative`, `Algebra.SizeChange`'s `sc*`);
  - 96 of unused logging helpers;
  - 77 of literate helpers (`relit`, `embedCode`, `isLitLine`, ...);
  - 1,393 of other helpers. The largest are `TTImp.Utils.getArgName` and
    `getArgNames`, `Core.TT.Primitive.primFnEq`, `primFnCmp` and
    `primTypeTag`, `Core.Context.getUserHoles`, `getDirectives` and
    `dumpStaging`, `Core.Env.uniqifyEnv`, `Core.Name.Scoped.mkFresh` and
    `freshStem`, `Core.UnifyState.mkConstantAppArgs*`, `Core.LinearCheck.updateHoleUsagePats`,
    `TTImp.ProcessDecls.processTTImpDecls` and `Idris.ProcessIdr.readPrelude`.
- **Readers.** None: the closure. The trimmed build proves the checker needs
  none of them.
- **The exact deletion.**
  - The spans in the appendix, and the two modules with their
    `idris-mlir-checker.ipkg` entries.
  - Lines removed, measured: the exported tree goes from 76,504 to 73,438
    lines. That is 3,066 in all, 212 of them candidate 8's, so **2,854**
    here.
  - The README sentences that name a deleted function go too. "`isNVar`,
    whose one use forgot the name, is gone" and its like stay, as accounts
    of deletions (C251).
  - No test exercises any of them. `tests/checker-loops-terminate` and
    `tests/probe-names` were seeds.
- **Verdict: DELETE.** Measured: the trimmed checker typechecks. The
  frontend was not rebuilt against it, but every name the frontend writes was
  a root.
- **Owner: L17.** Of the modified checker files listed at the top, the cut
  touches ten: `Core/Context.idr`, `Core/Core.idr`, `Core/LinearCheck.idr`,
  `Core/Name/Namespace.idr`, `Core/Primitives/Host.idr`, `Core/Unify.idr`,
  `Idris/Error.idr`, `Idris/Package.idr`, `Idris/ProcessIdr.idr` and
  `TTImp/ProcessBuiltin.idr`. It waits on those, and has to be recomputed on
  the tree those lanes land; the scripts take a tree and re-derive the list.

## 2. The elaborator-script runner (`%runElab`, `%macro`, and every `Reify` instance) — DELETE

- **The part.**
  - `TTImp/Elab/RunElab.idr` (396 lines, whole) and
    `TTImp/ProcessRunElab.idr` (43, whole).
  - `Core/Reflect.idr`: the `Reify` interface (`:17-21`), its 39 instances
    (443 lines, starting at `:92`), and the `Reflect (IsVar ..)` and
    `Reflect (Term vs)` instances (`:905-991`). Its own comment on them
    says "TODO: Do we need this?".
  - `TTImp/Reflect.idr`: `Reify BindMode`, `Reify UseSide` and
    `Reify DotReason` (`:21-33`, `:46-54`, `:62-75`), and the mutual
    `Reify RawImp ...` block (`:94-489`).
  - The hooks:
    - `IRunElab` and `IRunElabDecl`, with their cases in `TTImp.TTImp`
      (`:127,239,576,611,742,780,1024,1041`), `TTImp.TTImp.Functor`,
      `TTImp.TTImp.Traversals`, `TTImp.TTImp.TTC` (`:80,175,411,445`),
      `TTImp.Utils` (`:138,270`) and `TTImp.Reflect` (`:639,847`);
    - `checkTerm`'s case (`TTImp/Elab/Term.idr:209-210`) and `process`'s
      case (`TTImp/ProcessDecls.idr:140-141`);
    - `PRunElab` and `PRunElabDecl` in `Idris.Syntax`, `Desugar`
      (`:512-513,1410-1412`), `Resugar`, `Pretty`, `Syntax.Traversals` and
      `Syntax.Tree` (`:854,948`);
    - the parser's `%runElab` and `%macro` rules (`Idris/Parser.idr:1441-1442`
      and the `KwRunElab` rules);
    - the `Macro` flag: `FnOpt` `Macro`, `Context.Macro`, `processFnOpt`
      (`TTImp/ProcessFnOpt.idr:77-78`), `TTImp/Elab/Ambiguity.idr:144-147`,
      and their TTC tags (`Core/TTC.idr:1355,1368`,
      `TTImp/TTImp/TTC.idr:356,375`);
    - the `RunElabFail` error (`Core/Core.idr:180,396,518,609`,
      `Core/Context.idr:1021,1121`, `Idris/Error.idr:111,653`);
    - `defsStack` and `withDefStacked` (`Core/Context.idr:1332,1377,2021-2027`,
      whose one reader is `RunElab.idr:325`; `TTImp/ProcessDef.idr:787`
      writes it);
    - the vocabulary's `reflection` list (`compiler/checker/known/Vocabulary.idr:352-389`,
      37 entries) and its generated lines in `Core/Name/Known.idr`.
- **The fact it supplies.** It runs an `Elab` script at elaboration time:
  it reads a script's normal form back into checker values (`reify`) and
  performs `Check`, `Declare`, `ReadFile`, `WriteFile`, `GenSym` and the
  rest.
- **Rule that once required it.** Upstream's language has `%runElab` and
  `%macro`. Under AGENTS.md's strict subset ("The compiler may refuse a
  program upstream accepts"), no part of our pipeline reaches them:
  - A user module's `%runElab`, `%macro` and `%language` are refused, since
    the frontend admits only `discharged` pragmas (read:
    `Frontend/Profile.idr:110-117,140-142`).
  - No trusted library runs a script. Measured: `grep -rl '%runElab'` gives
    0 in prelude, base, linear, network, contrib, test and `libs/`, and
    `grep -rl '%macro'` gives 0. The 6 hits in base are doc comments
    (`||| treeShow = %runElab derive`).
  - No test writes one: `grep -rln '%runElab\|%macro\|ElabReflection' tests`
    gives 0.
  - Today a user's `%runElab` script runs, `ReadFile` and `WriteFile`
    included, before the frontend refuses the pragma. That is the opposite
    of "never miscompile silently".
- **Readers.** `reify` is called only from `RunElab.idr`. Measured: `grep
  -rnw 'reify\|cantReify'` outside the two `Reflect` modules finds only
  `TTImp/Elab/RunElab.idr` (27 hits).
- **What stays.**
  - Quotation stays. `` `( ) ``, `` `{ } `` and `` `[ ] `` are the
    `Reflect` direction, and user code and base use them
    (`tests/checker-quoted-search`; base's `Deriving.*` and
    `Language.Reflection.search`).
  - `Core.Reflect`'s `getCon` and `appCon` stay; `TTImp/Elab/Ambiguity.idr`
    uses them for pairs.
  - The `ElabReflection` language extension stays parseable, because base's
    `Deriving.*` write `%language ElabReflection`. It then gates nothing.
- **The exact deletion.**
  - The two files and the ipkg entries `TTImp.Elab.RunElab` and
    `TTImp.ProcessRunElab`.
  - The `Reify` instances and the interface listed above.
  - Each hook listed. `%runElab` and `%macro` become parse-time refusals
    "unsupported: ...", as `%start` is (D112.2).
  - The vocabulary entries, then `knowngen` regenerates
    `Core/Name/Known.idr` and `make check`'s manifest.
  - The README gains a bullet under "What was deleted".
  - No test is deleted. A new refused-program test for `%runElab` names the
    refusal.
  - About **1,690** lines: 396 + 43 + 448 + 87 + 432 + ~110 of hooks
    (conjecture) + 37 vocabulary lines + ~140 generated lines (~3.7 per
    entry, measured as 3,079 generated lines over 839 entries).
- **Verdict: DELETE.** Read; the hook count is conjecture.
- **Owner: L17.** Waits on these modified files: `TTImp/Elab/Term.idr`,
  `TTImp/Reflect.idr`, `TTImp/TTImp/TTC.idr`, `Core/Context.idr`,
  `Core/Core.idr`, `Core/TTC.idr`, `Idris/Desugar.idr` and `Idris/Error.idr`.

## 3. Interface hashing for incremental rebuilds (`Core.Hash`, `ifaceHash`, `importHashes`) — DELETE

- **The part.**
  - `Core/Hash.idr` (326 lines, whole).
  - In `Core/Context.idr`: `ifaceHash` (`:1304,1365`), `addHash` and
    `initHash` (`:1590-1599`), and `addHashWithNames` (`:1897-1899`).
  - In `Core/Binary.idr`: `ifaceHash` and `importHashes` in `TTCFile`
    (`:51-52`) and their TTC writes and reads (`:214-215,249-250`),
    `getImportHashes`, `readHashes` and `readImportHashes` (`:607-651`), and
    the `ifaceHash` of `readFromTTC`'s results (`:540,568`).
  - In `Idris/ProcessIdr.idr`: `readImportMeta` (`:137-143`), the
    hash-comparing skip (`:282-301`) and `:358`.
  - The `addHashWithNames` calls in `ProcessType.idr:217-219`,
    `ProcessDef.idr:456-458` and `ProcessData.idr:123-125,442-444,526-528`.
- **The fact it supplies.** It lets a module skip its rebuild when its
  source is unchanged and its imports' interface hashes are unchanged. This
  is an optimization of the checker's own run time.
- **Rule that once required it.** None.
  - `ModTree.needsBuilding` already decides a rebuild by modification time:
    a TTC older than its source or than any import's TTC is rebuilt (read:
    `Idris/ModTree.idr:156-196`). The hash only overrides that decision
    towards not rebuilding.
  - The README says rebuilds are decided "by modification time only". That
    is true of source hashes, not of interface hashes.
  - Every package the frontend installs is built from nothing in a fresh
    copy (Makefile `install`, "built from nothing in a copy beside the
    prefix"). So the skip never fires in `make prefix` or `make libs`.
  - AGENTS.md's "Delete before you optimize" applies directly.
- **Readers.** Only the skip itself. Measured: `grep -rn
  'addHash\|hashWithSalt\|readHashes\|readImportHashes\|ifaceHash'`.
- **The exact deletion.** As listed, with `ttcVersion` moving. About
  **450** lines. No test.
- **Verdict: DELETE.** Read.
- **Owner: L17.** Waits on these modified files: `Core/Binary.idr`,
  `Core/Context.idr`, `Idris/ProcessIdr.idr`, `TTImp/ProcessData.idr` and
  `TTImp/ProcessDef.idr`.

## 4. `Core.Metadata`, stubbed, and the parser's semantic decorations — DELETE

- **The part.**
  - `Core/Metadata.idr` (142 lines): `Decoration`, `Metadata = MkMetadata`,
    and adders that are all `pure ()`.
  - 141 lines that take or pass `Ref MD Metadata`, and 19 that make, read or
    write `MD`.
  - 36 calls to the no-op adders (`addLHS`, `addNameType`, `addTyDecl`,
    `addNameLoc`, `setHoleLHS`, `addSemanticDecorations`, ...).
  - The parser's decoration trail: `Parser/Rule/Source.idr:20-99,155-166`
    (`decorated`, `decorating`, `actD`, `decorationFromBounded`), the
    `decorate*` wrappers (`Idris/Parser.idr:38-95`), and
    `MkState decor ...` in `Idris/ProcessIdr.idr:303,323`.
  - Measured: `grep -rn 'Ref MD'`, `grep -rnE
    '\b(addLHS|addNameType|addTyDecl|addNameLoc|setHoleLHS|addSemanticDecorations|...)\b'`.
- **The fact it supplies.** None. The README: "`Core.Metadata` keeps its
  names and does nothing ... the `.ttm` file is neither written nor read".
  The parser still builds a trail of decorations for every keyword, symbol
  and name it reads. Its one consumer is `addSemanticDecorations decor`
  (`ProcessIdr.idr:323`), which is `pure ()` (`Core/Metadata.idr:139-142`).
- **Rule that once required it.** The IDE mode, deleted. The README kept the
  stub only to spare edits to about forty-five modules. That is a reason of
  convenience, which AGENTS.md's hard cutover rules out.
- **Readers.** None: the adders are no-ops.
- **The exact deletion.**
  - `Core/Metadata.idr` and its ipkg entry.
  - Every `Ref MD` parameter, every `newRef MD`, `put MD` and `get MD`, and
    every adder call.
  - The decoration trail. The `decorated*` wrappers become their plain
    rules, which simplifies about 285 call sites in `Idris/Parser.idr`
    without deleting them.
  - `import Core.Metadata` in `Frontend/Driver.idr:41` (L16).
  - The README's "Stubbed" section.
  - About **420** lines deleted, plus about 285 lines simplified. Read.
- **Verdict: DELETE.** Read.
- **Owner: L17, and L16 for the Driver import.** Touches most modified
  checker files.

## 5. Command-line and session remnants that only a package's `opts` can reach — DELETE

- **The part.**
  - In `Idris/CommandLine.idr`:
    - `PkgCommand`'s `InstallWithSrc` and `DumpInstallDir`, `DirCommand`,
      `HelpTopic` and `recogniseHelpTopic`;
    - the `CLOpt` constructors `CheckOnly`, `OutputFile`, `ExecFn`,
      `SetCG`, `Directive`, `Version`, `TTCVersion`, `Help`, `NoBanner`,
      `Quiet`, `Verbose`, `ShowImplicits`, `ShowMachineNames`,
      `ShowNamespaces`, `ConsoleWidth`, `Color`, `ListPackages`,
      `Directory`, `InputFile`, `FindIPKG` and `AltErrorCount`, with their
      `options` entries;
    - `showDefault`, `optShow`, `firstColumnWidth`,
      `makeTextFromOptionsOrEnvs`, `optsUsage`, `envsUsage`, `versionMsg`
      and `usage` (`:277-335`);
    - `getCmdOpts`, `findNearMatchOpt`, `nearMatchOptSuggestion` and
      `optionFlags` (`:386-421`).
  - `Idris/Env.idr` (43 lines, whole). Its one reader is `usage`'s text.
  - In `Idris/SetOptions.idr`: `visiblePackages`, `findPackages`,
    `listPackages` (`:199-257`) and `dirOption` (`:259-274`), and
    `preOptions`' cases for the options above.
  - In `Core/Options.idr`: `PostSession` and `PostS` (`:141-156`), and
    `Session`'s `nobanner`, `findipkg` and `logErrorCount`.
- **The fact it supplies.** Upstream's command line. The frontend parses its
  own (`Driver.idr:77-213`), and the checker's `getOpts` has exactly two
  readers. Measured: `grep -rnw 'getOpts\|preOptions'`.
  - One is a package's `opts` field (`Idris/Package.idr:481-483`). The only
    values in tree are `--ignore-missing-ipkg`, `-Wno-shadowing` and
    `--no-prelude` (measured: `grep -rn '^opts'` over all ipkgs).
  - The other is `prepareCompilation` (`:515`), given only
    `[Package cmd (Just file)]` by the driver.
- **Rule that once required it.** Upstream's `Idris.Main` and the REPL, both
  deleted (README). `PostSession`'s fields `outputFile` and `checkOnly` are
  written by `preOptions` and read by nothing. Measured: `grep -rnw
  'checkOnly\|outputFile\|nobanner\|findipkg'` finds only the writers.
- **The exact deletion.**
  - As listed. The `{auto p : Ref PostS PostSession}` of
    `host.processPackageOpts` goes (`Idris/Host.idr:3601-3602`), and so do
    `newRef PostS defaultPost` (`Driver.idr:379`, L16) and `PkgCommand`'s
    two extra cases in `Idris/Package.idr:763-785`.
  - What survives: `NoPrelude`, `SourceDir`, `BuildDir`, `OutputDir`,
    `PkgPath`, `Package`, `IgnoreMissingIPKG`, `Timing`, `Logging`
    (logging is kept, see "Examined and kept"), `WarningsAsErrors`,
    `IgnoreShadowingWarnings`, `Total`, and the option parser.
  - About **400** lines, after the 45 already in candidate 1. Read.
- **Verdict: DELETE.** Read.
- **Owner: L17, and L16 for `Driver.idr:379`.** Waits on
  `Idris/Package.idr` (modified) and `Idris/Host.idr` (modified).

## 6. Colour and console width — DELETE

- **The part.**
  - `Libraries/Control/ANSI.idr`, `ANSI/CSI.idr` and `ANSI/SGR.idr`
    (220 lines).
  - The styling half of `Libraries/Text/PrettyPrint/Prettyprinter/Render/Terminal.idr`.
  - `Idris.Pretty`'s `colorAnn` and `syntaxAnn`, and
    `Idris.Doc.Annotations.styleAnn`.
  - `REPLOpts`' `color` and `consoleWidth`, with `getColor`, `setColor`,
    `getConsoleWidth` and `setConsoleWidth` (`Idris/REPL/Opts.idr:76-89`).
  - `getPageWidth`'s terminal query (`Idris/Pretty/Render.idr:16-24`, which
    calls base's `getTermCols`, a C call the frontend's registry has to map:
    `Registry/Primitives.idr:306`).
  - The `Color` and `ConsoleWidth` options.
- **The fact it supplies.** ANSI colour, and a page width read from the
  terminal.
- **Rule that once required it.** The REPL. Neither is ever on.
  - The driver sets `setColor False` and `setConsoleWidth (Just 0)` on
    every run (`Driver.idr:403-404`), and nothing else sets them.
  - Measured: `grep -rn 'setColor\|setConsoleWidth'` finds the driver and
    `SetOptions`' options, whose only source would be a package's `opts`
    (candidate 5).
- **The exact deletion.** As listed. Rendering is unannotated at an
  unbounded width, always. The two driver lines go (L16). About **240**
  lines, after the CSI and SGR functions already in candidate 1. Read.
- **Verdict: DELETE.** Read.
- **Owner: L17, and L16 for `Driver.idr:403-404`.**

## 7. Two renderers of one `Error` — MERGE (which one survives is the owner's decision)

- **The part.**
  - `Core.Core`'s `Show Warning` and `showError` (`Core/Core.idr:233-453`,
    221 lines).
  - `Idris.Error`'s `pwarningRaw`, `perrorRaw`, `perror`, `display` and
    `displayWarning` (873 lines), with what only they reach: `Idris.Resugar`
    (640), `Idris.Pretty`'s `PTerm` printer (about 330 of 459),
    `Idris.Doc.*`, `Idris.IDEMode.Holes`, `Idris.Pretty.Render`, and most of
    `Idris.Syntax.Traversals` (781; the parse tree needs only `substFC`).
- **The fact it supplies.** Each renders the same ~100 constructors of
  `Error` and `Warning`. One sum is held under two switches, so every new
  error costs a case in each. That is AGENTS.md's "A switch on a tag is a
  polymorphism not yet named" and "one fact, one representation".
- **Readers.**
  - `show err` writes every refusal message of a compiled program:
    `refusalOf` and `unnamed` (`Driver.idr:282-284,321-330`), which
    idris-mlir reports to users.
  - `perror`, through `host.emitError` and `Idris.REPL.Common.emitError`,
    prints `--check`, the package commands, and internal errors.
  - `perror` also backs `checkError`, which decides a `failing "msg"`
    block (`TTImp/ProcessDecls.idr:79,87`, `Idris/Desugar.idr:1382`).
    `failing` is syntax, not a pragma, so user code reaches it.
  - `tools/upstream-idris/as-idris` compares `--check` output against
    upstream's expected files. It is not in `make`.
- **Rule that once required it.** Upstream had both, `show` for debugging
  and `perror` for the REPL. Neither rule holds here: we need one renderer,
  and a choice of which.
- **The two ways to merge, each with what it costs.**
  - (a) Keep `showError`, which compiled programs' refusals already print,
    and delete the `perror` chain: about **3,000** more lines, after
    candidates 1, 6 and 9.
    - `failing "msg"` then matches `show`'s text. A program written against
      upstream's text may be refused, which the subset permits. A `show`
      text that contains `msg` where upstream's would not is the
      contradiction case.
    - `--check` and package builds lose upstream's source excerpts.
    - `as-idris` comparisons of error text stop matching.
  - (b) Keep `perror` and route the frontend's refusals through the host
    (`host.emitError` is already the stated trust). This deletes the 221
    lines of `showError`.
    - Refusal texts change. The 16 tests with `-- expect: elaboration` and a
      `-- message:` header need their substrings rechecked (measured: `grep
      -rl '^-- expect: elaboration' tests`).
- **The exact deletion.** (a) or (b) above. The totals below count (b),
  **221**, the smaller of the two.
- **Verdict: MERGE.** Read. Which renderer survives is an owner decision:
  the text of error messages and `failing`'s matching are promises to users.
- **Owner: L17, and L16 for the Driver.** Waits on these modified files:
  `Idris/Error.idr`, `Core/Core.idr` and `Idris/Desugar.idr`.

## 8. `Idris.Host` statements nobody reads, three `believe_me` trusts among them — DELETE

- **The part.** 25 definitions, 212 lines at d378e120:
  - `definedOnce`, `entryOf` and `putInMarker`;
  - the `mentionsNone` family (`boundCountsNone`, `mentionsNone*`,
    `treeMentionsNone`, `altsMentionNone`, `altMentionsNone`);
  - `freshNone`, `reducesStrengthened`, `strengthenedOnce`,
    `normalisesThrough` and `probesFresh`;
  - the full-name chain: `oneEntryPerName`, `fullNameUnresolved`,
    `resolvedInjective`, `entryFullName`, `definedFullName`,
    `resolvedDefinedFullName`, `sameByFullName`, `sameEntryFullName` and
    `fullNameSameEntry`.
  - Positions are in the appendix.
- **The fact it supplies.** Three of them are postulates:
  `probesFresh _ = trusted` (`:3130`), `oneEntryPerName _ _ _ = trusted`
  (`:3435`) and `fullNameUnresolved _ _ = trusted` (`:3439`), where
  `trusted = believe_me ()` (`:108-109`). Nothing uses any of them, or
  anything built on them.
- **Rule that once required it.** D68, and the README's account of "the
  context makes one entry for each full name". D133 (the owner, today: "we
  should not have any believe me in our own codebase") and C288 supersede
  D68's mechanism. A trust with no reader is the cheapest one to meet:
  deleting it makes it unnecessary.
- **Readers.** None.
  - The in-file closure (`/tmp/checker-cull/scripts/fileclosure.pl`),
    seeded by every name the frontend and the checker's other modules
    write.
  - The global closure agrees.
  - Measured at finish: `grep -rnw` of each of the three trusts over
    `compiler/src` and `tests` gives 0.
- **The exact deletion.**
  - The 25 definitions, cut in the measured trimmed build.
  - The README paragraph naming `oneEntryPerName`, `fullNameUnresolved`,
    `sameEntryFullName` and `fullNameSameEntry` (README `:376-382` at f1d14600).
  - **212** lines. Measured: they are in the trimmed tree that typechecks.
- **Verdict: DELETE.** Measured.
- **Owner: L17.** In flight: the working tree's `Idris/Host.idr` is being
  rewritten for D133/C288 (−658/+23 lines, uncommitted at finish), and it
  already lacks `putInMarker`, `probesFresh` and the full-name chain. The
  rest needs rechecking once that lands.

## 9. Docstrings recorded and saved for one warning — DELETE

- **The part.**
  - `SyntaxInfo`'s `modDocstrings`, `modDocexports`, `saveDocstrings` and
    `defDocstrings` (`Idris/Syntax.idr`), with their TTC writes and reads
    (`Idris/Syntax/TTC.idr:85-112`).
  - Desugar's merge of them (`Idris/Desugar.idr:95-113`).
  - `addDocString` and `addDocStringNS` (`Idris/Doc/String.idr:40-63`) and
    their calls (7 + 2; for example `Idris/Desugar.idr:935,1025,1035`).
  - `getDocsForName` and `justUserDoc`, whose one reader is the
    deprecation warning (`Idris/Error.idr:312-316`).
  - Measured: `grep -rnw 'modDocstrings|defDocstrings|...'`, and a count of
    external uses of each `Idris.Doc.String` name.
- **The fact it supplies.** The `|||` text of each definition and module.
  Its one reader appends a deprecated name's docstring to the "Deprecation
  warning" (`%deprecate`: 6 uses in prelude and base). That warning is
  printed by `--check` and package builds, never on a compiled program's
  path.
- **Rule that once required it.** `:doc` (the REPL) and `--mkdoc`, both
  deleted.
- **The exact deletion.**
  - The four fields and their TTC (`ttcVersion` moves), the merge, the
    adders, and `getDocsForName`.
  - The `Deprecated` warning prints its message and location. `%deprecate`
    still warns where upstream warns; only the docstring appended to the
    text is lost.
  - The parser keeps reading `|||`. Whether the `doc` fields of the parse
    tree's declarations go too is a further cut, to check.
  - About **200** lines, after candidate 1's 287 in `Idris/Doc/String.idr`.
    Read.
- **Verdict: DELETE.** Read.
- **Owner: L17.** Waits on `Idris/Desugar.idr`, `Idris/Syntax/TTC.idr` and
  `Idris/Error.idr` (all modified).

## 10. Code-generator remnants: `CG`, directives, `%export`, `schemeEvalLoaded` — DELETE

- **The part.**
  - `Core/Options.idr`: `CG` (`:87-97`), `additionalCGs`, `availableCGs`,
    `getCG` and `Session.directives`.
  - `Core/Context.idr`: `cgdirectives` (`:1317`) and `addDirective`
    (`:2286-2305`, no caller: measured, `grep -rnw addDirective` gives only
    its definition); `schemeEvalLoaded` (`:1328`, written once at
    initialisation and never read); `foreignExports` (`:1329`).
  - `Core/Binary.idr`: the TTC sections for `cgdirectives` and
    `foreignExports` (`:66-67,232-233,405-406,488-499,560`).
  - `TTImp`: the `ForeignExport` `FnOpt` with `initDef`'s case
    (`TTImp/ProcessType.idr:75-79`) and `processFnOpt`'s case
    (`TTImp/ProcessFnOpt.idr:70`).
  - `SetOptions`' `SetCG` and `Directive` cases.
  - `NoForeignCC`'s list of backends (`Idris/Error.idr:784-791`).
- **The fact it supplies.** None. "Ours registers none and reads none of
  these options" (README). `foreignExports` maps names to C export symbols,
  and its only reader is the TTC round trip. Measured: `grep -rnw
  foreignExports` finds the writer, the TTC and initialisation.
- **Rule that once required it.** Upstream's back ends. AGENTS.md: "Do not
  implement ... `%extern` as a C export". No trusted library writes
  `%export` (measured: 0 in prelude, base and `libs/`), and a user's is
  refused by the frontend.
- **The exact deletion.** As listed, with the TTC sections (`ttcVersion`
  moves). About **110** lines, after candidate 1's `addCG`, `getDirectives`
  and `dumpStaging`. Read.
- **Verdict: DELETE.** Read.
- **Owner: L17.** Waits on `Core/Context.idr`, `Core/Binary.idr`,
  `Idris/Error.idr` and `TTImp/TTImp/TTC.idr` (modified).

## 11. Package commands the driver never gives, and package metadata nobody reads — DELETE

- **The part.**
  - `installSrcFrom` (`Idris/Package.idr:569-604`) and `install`'s
    `installSrc` flag, with the cases for `InstallWithSrc` and
    `DumpInstallDir` (`:769-790`).
  - `PkgDesc`'s `authors`, `maintainers`, `license`, `brief`, `readme`,
    `homepage`, `sourceloc` and `bugtracker`. Each is stored and shown,
    never read (measured: `grep -rnw` of each over `Idris/Package*.idr`
    finds the parser, the record and `Show PkgDesc`).
- **The fact it supplies.** None to us. The driver sends only `Build`,
  `Install`, `Typecheck` and `Clean` (`Driver.idr:136-141`).
- **Rule that once required it.** Upstream's CLI and `--dump-ipkg-json`,
  deleted.
- **The exact deletion.** The functions and cases. The metadata fields stay
  accepted by the ipkg parser, since prelude's and base's ipkgs write some,
  but their values are dropped. About **80** lines. Read.
- **Verdict: DELETE.** Read.
- **Owner: L17.** Waits on `Idris/Package.idr` (modified).

## 12. Hole bookkeeping for the IDE: `userHoles`, `externalDecl`, `holeNames`, `bracketholes` — DELETE

- **The part.**
  - `Defs.userHoles` (`Core/Context.idr:1320`) with `addUserHole` and
    `clearUserHole` (`:1602-1610`), their callers
    (`TTImp/ProcessType.idr:60`, `TTImp/Elab/Hole.idr:56,74`), and the TTC
    section (`Core/Binary.idr:54,222,393,545`).
  - `PMDefInfo.externalDecl` (`Core/Context/Context.idr:46`, written at
    `TTImp/ProcessDef.idr:826-829` and in TTC at `Core/TTC.idr:1240`, never
    read).
  - `SyntaxInfo.holeNames` and `bracketholes`, with their TTC.
- **The fact it supplies.** None.
  - `userHoles`' readers are `externalDecl`'s writer and `getUserHoles`
    (dead, candidate 1).
  - `holeNames`' one reader is `uniqueHoleNames` (dead).
  - `bracketholes` is only ever written.
  - Measured: `grep -rnw` of each.
- **Rule that once required it.** The REPL's `:metavars`, case-split
  naming, and upstream's code generator.
- **The exact deletion.** As listed, with the TTC sections. About **50**
  lines. Read.
- **Verdict: DELETE.** Read.
- **Owner: L17.** Waits on `Core/Context.idr`, `Core/Binary.idr`,
  `Core/TTC.idr`, `TTImp/ProcessDef.idr` and `Idris/Syntax/TTC.idr`
  (modified).

## 13. `%name` hints stored for no reader (`namedirectives`) — DELETE

- **The part.**
  - `Defs.namedirectives` (`Core/Context.idr:1303,1364`) and the store at
    `:2644`.
  - Its TTC section (`Core/Binary.idr:65,113,157,231,404,480-487,558`).
- **The fact it supplies.** The names `%name T a, b` suggests for variables
  of type `T`. The one reader is `TTImp.Utils.getArgName`'s `namesFor`
  (`:866`), and `getArgName` is dead (candidate 1).
- **Rule that once required it.** The REPL's case split.
- **The exact deletion.** The field, the store and the TTC section.
  `%name` stays parsed, since prelude and base write it 36 times (measured),
  and is dropped at desugar. About **35** lines. Read.
- **Verdict: DELETE.** Read.
- **Owner: L17.** Waits on `Core/Context.idr` and `Core/Binary.idr`
  (modified).

## 14. `%start`'s parse path and `startExpr` in every TTC — DELETE

- **The part.**
  - `StartExpr` and the type parameter of `Directive' tm`
    (`Idris/Syntax.idr:447,601`).
  - The parser's rule (`Idris/Parser.idr:1726-1729`) and the parse tree's
    case (`Idris/Syntax/Tree.idr:810`).
  - Desugar's refusal (`Idris/Desugar.idr:1440`).
  - `SyntaxInfo.startExpr` (`Idris/Syntax.idr:907`), set to `main` at
    initialisation (`:975`) and written and read in every TTC
    (`Idris/Syntax/TTC.idr:97,107`). Nothing reads it (measured: `grep -rn
    startExpr`).
- **The fact it supplies.** None. `%start` is refused (D112.2), yet its
  expression is parsed, held in the tree, decoded and desugared before the
  refusal, and every TTC carries a constant `main`.
- **Rule that once required it.** The REPL.
- **The exact deletion.**
  - The parser refuses `%start` where it reads the keyword, with the same
    message. `tests/checker-start-refused`'s header (elaboration, line 10,
    `%start`) stays satisfied.
  - The constructor, the parameter, the field and its TTC go
    (`ttcVersion` moves), with the README bullet on `Directive' tm`.
  - About **25** lines. Read.
- **Verdict: DELETE.** Read.
- **Owner: L17.** Waits on `Idris/Desugar.idr` and `Idris/Syntax/TTC.idr`
  (modified).

---

## Examined and kept

- **`%transform` elaboration** (`TTImp/ProcessTransform.idr`, 49 lines) —
  **KEEP** (C271, 2026-10-23, for the owner's review).
  - The rule: "a wrong rule is refused as upstream refuses it".
  - Its unique fact: prelude's and base's 16 rules type-check.
  - The owner may want to weigh this: the check can fire only on the pinned
    prelude and base, which upstream already checks.
- **Topic logging** (`log`, `logC`, `logTerm*`, `%logging`, `--log`) —
  **KEEP**, under C287.
  - The part:
    - 354 statements, 554 lines with their continuations. Measured on the
      export: lines matching
      `^\s+(log|logC|logTerm|logTermNF|logGlue|logNF|logEnv|logDepth|...)\s+"`,
      plus the more-indented lines after each.
    - `Core/Options/Log.idr` (329 lines) and the topic half of
      `Core/Context/Log.idr` (197).
    - Session `logEnabled` and `logLevel`.
  - Its unique fact: elaboration traces for whoever debugs the checker.
  - What requires it:
    - C287 (2026-10-23, for the owner's review) admits a pragma "whose whole
      meaning is the checker's elaboration ... in user code with upstream's
      meaning, which our checker implements".
    - L16's working-tree `Frontend/Profile.idr` classes `%logging` that way
      (`meaning KwLogging = Elaboration`, `:134`, uncommitted). So a user's
      `%logging` must log.
  - Weighing against it:
    - Nothing in the tree enables a topic. Measured: no `%logging` in
      `tests`, `libs`, prelude or base outside base's docs, and no `--log` in
      any ipkg's `opts`.
    - The topics are strings proved members of a table
      (`IsJust (lookup s knownTopics)`), the "string that names a thing"
      AGENTS.md calls a missing type.
  - Deleting it, about 900 lines after candidate 1's 96, would take the
    owner's word refusing `%logging`. Not counted.
  - The timing half (`logTime`, `logTimeWhen`) stays either way: the
    driver's `--timing` reads it (`Driver.idr:382`).
- **Literate sources** (`Parser.Unlit` 122 lines and `Libraries.Text.Literate`
  246, so 368, less candidate 1's 77: 291) — **KEEP until the owner rules on scope.**
  - No `.lidr` or `.org` file is in the tree (measured: `git ls-files |
    grep -E '\.(lidr|org)$'` gives 0).
  - Upstream's language accepts literate files, and refusing them is a
    change to what user programs may be (§"What the compiler accepts", the
    owner's).
  - Not counted.
- **`failing` blocks** (`processFailing`, `checkError`) — **KEEP.**
  - User code reaches them: `failing` is syntax, not a pragma.
  - Whichever renderer candidate 7 keeps decides their matching.
- **D118's attribution** — **KEEP.**
  - `compiler/checker/LICENSE`, every file's SPDX and copyright line, the
    README's first paragraph, and the README's account of deletions (C251)
    stay through every cut above.
  - A module deleted whole takes its header with it. A file written here
    keeps ours.
- **The elaborator, unifier, coverage, termination (`Core.Termination.*`,
  size-change), case builder, TTC, and the parser** — **KEEP.** Essential:
  the frontend reads the checked TT and TTC they produce (`host.buildMain`,
  `readDefinitions`, `loopsTerminate`).
- **`Idris.REPL.Opts` and `Idris.REPL.Common` as names** — kept as the
  README says, for now. What they hold shrinks with candidates 5, 6 and 7.

## Table

| # | Candidate | Verdict | Lines deleted | Ground | Owner | Waits on |
|---|---|---|---|---|---|---|
| 1 | Top-level definitions nothing reaches; 2 unreached modules | DELETE | 2,854 | measured (trimmed checker typechecks) | L17 | the 10 modified files it touches; recompute on landing |
| 2 | Elaborator-script runner (`%runElab`, `%macro`, `Reify`) | DELETE | ~1,690 | read (hooks: conjecture) | L17 | `Elab/Term`, `Reflect`, `TTImp/TTC`, `Context`, `Core`, `TTC`, `Desugar`, `Error` |
| 3 | Interface hashing (`Core.Hash`, `ifaceHash`) | DELETE | ~450 | read | L17 | `Binary`, `Context`, `ProcessIdr`, `ProcessData`, `ProcessDef` |
| 4 | `Core.Metadata` stub and parser decorations | DELETE | ~420 (+~285 simplified) | read | L17, L16 (Driver import) | most modified files |
| 5 | Command-line and session remnants (`PostSession`, `Idris.Env`, ...) | DELETE | ~400 | read | L17, L16 (`Driver:379`) | `Package`, `Host` |
| 6 | Colour and console width | DELETE | ~240 | read | L17, L16 (`Driver:403-404`) | — |
| 7 | Two renderers of one `Error` | MERGE (owner picks: (a) `show`, (b) `perror`) | 221 counted (b); (a) ~3,000 | read | L17, L16 | `Error`, `Core`, `Desugar` |
| 8 | `Idris.Host` statements unread, 3 `believe_me` trusts | DELETE | 212 | measured | L17 | `Idris/Host.idr` rewrite in flight (D133/C288) |
| 9 | Docstrings kept for one warning | DELETE | ~200 | read | L17 | `Desugar`, `Syntax/TTC`, `Error` |
| 10 | Code-generator remnants (`CG`, directives, `%export`) | DELETE | ~110 | read | L17 | `Context`, `Binary`, `Error`, `TTImp/TTC` |
| 11 | Package commands never given; metadata unread | DELETE | ~80 | read | L17 | `Package` |
| 12 | Hole bookkeeping (`userHoles`, `externalDecl`, ...) | DELETE | ~50 | read | L17 | `Context`, `Binary`, `TTC`, `ProcessDef`, `Syntax/TTC` |
| 13 | `%name` hints with no reader | DELETE | ~35 | read | L17 | `Context`, `Binary` |
| 14 | `%start` parse path and `startExpr` in every TTC | DELETE | ~25 | read | L17 | `Desugar`, `Syntax/TTC` |
| — | Topic logging (`log*`, `%logging`, `--log`) | KEEP (C287; deleting it needs the owner to refuse `%logging`) | 0 (~900 at stake) | read; conjecture on count | L17, L16 | — |
| — | `%transform` elaboration | KEEP (C271) | 0 | read | L17 | — |
| — | Literate sources | KEEP until the owner rules | 0 (~291 at stake) | measured (no literate file) | L17 | — |
| — | `failing` blocks; D118 attribution; elaborator core | KEEP | 0 | read | L17 | — |

**Totals.**
- DELETE and MERGE together remove about **6,990 lines** of the checker's
  76,504 (9.1%). This counts candidate 7 at its smaller form (b).
  - Measured: 3,066 of them, candidates 1 and 8, cut and typechecked.
  - Read: about 3,920, of which ~110 (candidate 2's hooks) is conjecture.
- With candidate 7 merged as (a), the total is about **9,800** (12.8%).
- Neither figure counts:
  - the ~285 parser call sites candidate 4 simplifies;
  - the generated lines of `Core/Name/Known.idr` beyond candidate 2's;
  - the KEEPs that are open to the owner: logging, about 900 lines;
    literate sources, about 291; `%transform`, 49.

## Appendix: candidate 1's spans (d378e120; `name:startLine+lines`)

- `Libraries/Data/List/Quantifiers/Extra.idr` (17): the whole module.
- `Libraries/Text/PrettyPrint/Prettyprinter/SimpleDocTree.idr` (133): the
  whole module.
- Every other file follows, the same list as `/tmp/checker-cull/dead_by_file.txt`.

- `Idris/Doc/String.idr` (287): getHintsForPrimitive:130+13, getDocsForPrimitive:144+47, shortNamesConfig:220+7, getDocsForImplementation:481+67, getDocsForPTerm:549+103, getDocs:653+12, summarise:666+14, getContents:679+24
- `Core/Context.idr` (158): namesResolvedAs:44+6, liveOnce:553+2, storedOnce:556+2, liveNotStored:559+2, typeOnce:562+9, treeOnce:572+6, allNames:1209+4, internModuleIdent:1419+4, canonicalName:1559+12, getUserHoles:1612+20, dumpStaging:1780+8, setTotality:1966+8, getSizeChange:2002+8, dropOpenHint:2216+5, getDirectives:2296+15, getVisible:2360+10, setAllPublic:2367+7, addExtraDir:2450+3, addLibDir:2469+3, setDependsDir:2477+3, setExtraDirs:2504+3, setLogLevel:2767+4, stopLogging:2772+3, getTime:2813+11
- `TTImp/Utils.idr` (144): nameNum:696+6, nextNameNum:703+2, unNameNum:706+3, uniqueBasicName:783+18, uniqueHoleName:802+7, uniqueHoleNames:810+15, getArgName:839+81, getArgNames:921+12
- `Core/TT/Primitive.idr` (140): primTypeTag:289+18, intKind:332+13, precision:346+6, primFnEq:485+42, primFnCmp:528+61
- `Libraries/Text/PrettyPrint/Prettyprinter/Doc.idr` (130): softline':148+5, fillBreak:224+8, fillCat:272+5, plural:291+3, unAnnotate:343+4, tupled:440+6, prettyList1:451+3, prettyMaybe:464+3, internalError:478+3, alterAnnotationsS:484+17, dropWhileEnd:548+2, removeTrailingWhitespace:551+42, displaySpans:714+29
- `Core/Name/Scoped.idr` (105): freshStem:68+19, familyAfter:93+5, familyMember:99+6, familyIndex:102+10, leastFreeFrom:111+8, nameAfter:120+5, mkFresh:126+17, invertExt:149+4, extendCompats:154+12, decCompatibleVars:167+8, areCompatibleVars:176+11
- `Core/TT/Var.idr` (88): isLater:169+4, mkVar:179+3, isLater:223+4, mkNVar:236+3, mkNVarChiply:240+5, dropNVar:256+6, weakenNVar:287+4, insertNVar:296+7, insertNVarChiply:304+12, removeNVar:328+8, insertVar:337+5, weakenVar:343+2, removeVar:349+9, shiftUnderNs:484+16
- `Algebra/SizeChange.idr` (88): scPlusNeutralLeft:72+3, scPlusNeutralRight:76+4, scPlusCommutative:81+8, scPlusAssoc:90+8, scMultNeutralLeft:99+2, scMultNeutralRight:102+4, scMultZeroLeft:107+2, scMultZeroRight:110+4, scMultAssociative:115+19, scMultCommutative:135+12, scPlusIdempotent:148+4, scMultPlusDist:153+18
- `Idris/Doc/Brackets.idr` (83): getDocsForBracket:11+83
- `Idris/Doc/Display.idr` (81): displayType:18+15, displayTerm:33+8, displayClause:42+14, displayPats:57+12, displayImpl:70+32
- `Libraries/Control/ANSI/CSI.idr` (75): cursorUp:7+5, cursorUp1:13+3, cursorDown:17+5, cursorDown1:23+3, cursorForward:27+5, cursorForward1:33+3, cursorBack:37+5, cursorBack1:43+3, cursorNextLine:47+5, cursorNextLine1:53+3, cursorPrevLine:57+5, cursorPrevLine1:63+3, cursorMove:67+5, eraseScreen:81+4, eraseLine:86+4, scrollUp:91+4, scrollUp1:96+3, scrollDown:100+4, scrollDown1:105+3
- `Core/Context/Log.idr` (75): logString':24+6, logging':31+6, log':62+6, logTimeOver:117+13, logTimeRecord':148+18, logTimeRecord:164+15, showTimeRecord:180+11
- `Core/Directory.idr` (74): listOfExtensions:94+4, splitIdrisFileName:124+18, findDataFile:153+11, readDataFile:165+9, getExecFileName:320+10, findIpkgFile:327+22
- `Core/UnifyState.idr` (70): setConstraint:349+4, mkConstantAppArgsSub:406+18, mkConstantAppArgsOthers:425+18, applyToSub:458+7, applyToOthers:466+13, checkUserHoles:735+5, checkNoGuards:741+5
- `Core/Env.idr` (70): lengthNoLet:42+5, lengthExplicitPi:48+5, namesNoLet:54+5, abstractEnv:158+12, closeUsed:223+12, findUsedLocs:236+8, uniqifyEnv:378+23
- `Algebra/ZeroOneOmega.idr` (56): rigPlusAssociative:81+17, rigPlusCommutative:99+11, rigMultAssociative:111+17, rigMultCommutative:129+11
- `Libraries/Text/Literate.idr` (40): isLiterateLine:205+12, embedCode:218+20, relit:239+8
- `Libraries/Utils/Path.idr` (38): isBaseOf:331+16, fileStem:376+11, setFileName:412+7, dropExtension:469+4
- `Parser/Unlit.idr` (37): hasLitFileExt:64+19, isLitLine:99+14, relit:119+4
- `Libraries/Text/PrettyPrint/Prettyprinter/SimpleDocTree.idr` (36): alterAnnotationsST:23+9, alterEach:33+3, reAnnotateST:37+4, unAnnotateST:42+4, fromStream:118+16
- `Libraries/Data/Version.idr` (35): versionTokens:69+7, lexVersion:77+5, versionParser:85+9, parseVersion:95+14
- `TTImp/ProcessDecls.idr` (34): processTTImpDecls:162+34
- `Idris/IDEMode/Holes.idr` (34): getUserHolesData:139+19, showHole:159+15
- `Core/Primitives/Host.idr` (34): charEqualitySound:50+15, stringEqualitySound:61+19
- `Idris/CommandLine.idr` (31): getCmdOpts:388+5, findNearMatchOpt:394+12, nearMatchOptSuggestion:407+10, optionFlags:418+4
- `Idris/Pretty.idr` (30): syntaxToDecoration:22+9, annToDecoration:57+4, renderWithDecorations:442+10, prettyImport:453+7
- `Core/LinearCheck.idr` (30): updateHoleUsagePats:103+30
- `Idris/Package.idr` (26): findIpkg:845+26
- `Core/Name/Namespace.idr` (26): mkModuleIdent:69+8, isInPathOf:176+9, eqOrdNS:285+3, ioNS:293+3, natNS:313+3
- `Idris/ProcessIdr.idr` (25): addImport:126+10, readPrelude:149+15
- `Idris/Syntax/Views.idr` (23): unArg:16+5, underPis:42+9, underLams:52+9
- `Core/Case/CaseTree.idr` (23): eqTree:260+10, eqAlt:271+13
- `Libraries/Data/NatSet.idr` (21): allLessThanSpecEmpty:174+2, allLessThanSpecNonEmpty:177+2, popNs:212+17
- `Idris/Package/Types.idr` (21): inBoundsBecauseOfTag:133+7, outOfBoundsBecauseOfTag:139+8, cssFiles:329+6
- `Core/Options/Log.idr` (21): helpTopics:182+11, mkLogLevel:237+5, withVerbosity:259+5
- `Idris/Syntax.idr` (20): applyArgs:335+4, applyWithArgs:340+4, getPDataDeclLoc:392+4, getPClauseLoc:421+5, getPDeclLoc:567+3
- `Protocol/Hex.idr` (18): asHex:29+12, leftPad:42+6
- `Idris/Doc/Annotations.idr` (17): docToDecoration:23+5, styleAnn:29+9, tCon:39+3
- `Idris/Pretty/Render.idr` (16): renderWithoutColor:43+7, renderWithSpans:51+9
- `Core/Normalise/Eval.idr` (16): evalClosureWithOpts:634+8, gnfOpts:664+8
- `TTImp/Elab/Check.idr` (15): bindingPiInfo:105+6, mustBePoly:297+9
- `Libraries/Text/PrettyPrint/Prettyprinter/Render/Terminal.idr` (15): bgColor:21+3, underline:33+3, strike:37+3, renderIO:94+3, putDoc:98+3
- `Libraries/Text/PrettyPrint/Prettyprinter/Render/String.idr` (14): renderIO:19+10, putDoc:30+4
- `Libraries/Data/List/Extra.idr` (14): diffBy:43+14
- `Core/Options.idr` (14): execBuildDir:60+3, docsPPrint:222+8, addCG:301+3
- `Parser/Support/Escaping.idr` (13): dec:32+13
- `TTImp/BindImplicits.idr` (12): piBindNames:214+12
- `Parser/Rule/Source.idr` (12): onOffLit:181+12
- `Libraries/Data/WithDefault.idr` (12): specifyValue:18+4, replaceSpecified:23+4, isSpecified:59+4
- `Libraries/Data/String/Extra.idr` (12): takeLast:49+8, indentLines:96+4
- `Libraries/Data/List/Thin.idr` (12): fromNatSet:35+12
- `Libraries/Control/ANSI.idr` (12): background:24+3, bolden:28+3, italicize:32+3, underline:36+3
- `Core/FC.idr` (12): replFC:113+3, onLine:181+9
- `TTImp/Elab/Case.idr` (11): extendNeeded:123+11
- `Libraries/System/Directory/Tree.idr` (11): toRelative:32+3, depthFirst:106+8
- `Core/TT/Term.idr` (10): applySpineWithFC:492+7, linFnType:509+3
- `TTImp/Elab/ImplicitBind.idr` (9): normaliseHolesScope:279+9
- `Libraries/Data/NameMap.idr` (9): treeMapWithKey:296+5, mapWithKey:302+4
- `Core/TT/Traversals.idr` (9): unBinds:18+6, allConstants:103+3
- `Core/Coverage.idr` (9): showK:481+9
- `Core/Core.idr` (9): traverseVect:868+4, condC:1108+5
- `Libraries/Data/StringMap.idr` (8): sharedSupport:280+8
- `Idris/Resugar.idr` (8): resugarNoPatvars:627+8
- `Core/TT/Binder.idr` (8): setType:178+8
- `Core/Normalise.idr` (8): normaliseLHS:67+8
- `TTImp/ProcessBuiltin.idr` (7): getTypeArgs:51+7
- `Libraries/Data/SnocList/SizeOf.idr` (7): theList:27+3, sucL:47+4
- `Idris/REPL/Opts.idr` (7): getVerbosity:56+3, setMainFile:60+4
- `Libraries/Utils/Binary.idr` (6): fromBuffer:47+6
- `Idris/REPL/Common.idr` (6): printError:58+6
- `Core/Value.idr` (6): cbn:95+3, cbv:99+3
- `TTImp/TTImp.idr` (5): unIArg:1066+5
- `Libraries/Text/Lexer.idr` (5): alphaNum:152+5
- `Libraries/Text/PrettyPrint/Prettyprinter/Util.idr` (4): putDocW:37+4
- `Libraries/Text/Lexer/Tokenizer.idr` (4): tokenKinds:73+4
- `Libraries/Data/SnocList/HasLength.idr` (4): sucL:30+4
- `Libraries/Data/List/LengthMatch.idr` (4): lengthsMatch:20+4
- `Libraries/Data/ANameMap.idr` (4): toAmbiguousList:89+4
- `Core/Name.idr` (4): isField:172+4
- `Parser/Lexer/Common.idr` (3): isIdentNormal:115+3
- `Libraries/Data/VarSet/Core.idr` (3): dropInner:65+3
- `Libraries/Data/List/SizeOf.idr` (3): theList:17+3
- `Idris/Syntax/Pragmas.idr` (3): allLangExts:21+3
- `Idris/Syntax/Builtin.idr` (3): heqName:41+3
- `Idris/Error.idr` (3): prettyMaybeLoc:855+3
- `Core/Unify.idr` (3): inSearch:51+3
- `Core/TT.idr` (3): funKindedName:43+3
- `Core/Reflect.idr` (3): primio:65+3
- `Algebra/Semiring.idr` (3): branchOne:54+3
- `Idris/Parser.idr` (2): peq:101+2


Candidate 9's spans in `Idris/Host.idr`:

definedOnce:226+5, entryOf:232+4, putInMarker:1497+10, boundCountsNone:2767+8, mentionsNone:2777+18, mentionsNoneAll:2796+3, mentionsNoneBinder:2800+7, mentionsNonePi:2808+5, treeMentionsNone:2815+5, altsMentionNone:2821+3, altMentionsNone:2825+7, freshNone:2831+3, reducesStrengthened:2835+7, strengthenedOnce:2843+11, normalisesThrough:3080+21, probesFresh:3117+14, oneEntryPerName:3424+12, fullNameUnresolved:3437+9, resolvedInjective:3465+2, entryFullName:3468+6, definedFullName:3475+6, resolvedDefinedFullName:3482+10, sameByFullName:3488+11, sameEntryFullName:3500+8, fullNameSameEntry:3509+17

Tools (outside the tree, under `/tmp/checker-cull/scripts/`):
- `closure.pl` and `dropout.pl`: module import closures.
- `global.pl`: the name-level closure.
- `fileclosure.pl`: `Idris.Host`'s in-file closure.
- `cut.pl` and `retrim.sh`: cut and re-export.
- `build.sh` and `build2.sh`: the typecheck of an export.
