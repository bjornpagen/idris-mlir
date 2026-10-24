-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Idris.Package

import Core.Directory
import Core.Unify

import Data.Maybe
import Data.SortedMap
import Data.String

import Parser.Package
import System
import System.Directory
import System.File

import Libraries.Data.StringMap
import Libraries.Data.StringTrie
import Libraries.Data.WithDefault
import Libraries.Text.Parser
import Libraries.Utils.Path
import Libraries.Text.PrettyPrint.Prettyprinter.Render.String

import Idris.CommandLine
import Idris.Error
import Idris.ModTree
import Idris.Pretty
import Idris.ProcessIdr
import Idris.REPL.Common
import Idris.SetOptions
import Idris.Syntax
import Idris.Version

import public Idris.Package.Types

%default covering

installDir : PkgDesc -> String
installDir p = name p
            ++ "-"
            ++ show (fromMaybe (MkPkgVersion (0 ::: [])) (version p))

data DescField  : Type where
  PVersion      : FC -> PkgVersion -> DescField
  PLangVersions : FC -> PkgVersionBounds -> DescField
  PVersionDep   : FC -> String -> DescField
  -- A field that describes the package to a person (its authors, its
  -- licence, ...): read, since prelude's and base's packages write them,
  -- and its text dropped, since nothing here shows a package.
  PDescribes    : DescField
  PDepends      : List Depends -> DescField
  -- A module the package names, as written: `addField` interns it.
  PModules      : List (FC, List1 String) -> DescField
  PMainMod      : FC -> List1 String -> DescField
  PExec         : String -> DescField
  POpts         : FC -> String -> DescField
  PSourceDir    : FC -> String -> DescField
  PDataDir      : FC -> String -> DescField
  PBuildDir     : FC -> String -> DescField
  POutputDir    : FC -> String -> DescField
  PPrebuild     : FC -> String -> DescField
  PPostbuild    : FC -> String -> DescField
  PPreinstall   : FC -> String -> DescField
  PPostinstall  : FC -> String -> DescField
  PPreclean     : FC -> String -> DescField
  PPostclean    : FC -> String -> DescField

total
field : String -> Rule n r DescField
field fname
      = strField describes "authors"
    <|> strField describes "maintainers"
    <|> strField describes "license"
    <|> strField describes "brief"
    <|> strField describes "readme"
    <|> strField describes "homepage"
    <|> strField describes "sourceloc"
    <|> strField describes "bugtracker"
    <|> strField POpts "options"
    <|> strField POpts "opts"
    <|> strField PSourceDir "sourcedir"
    <|> strField PDataDir "datadir"
    <|> strField PBuildDir "builddir"
    <|> strField POutputDir "outputdir"
    <|> strField PPrebuild "prebuild"
    <|> strField PPostbuild "postbuild"
    <|> strField PPreinstall "preinstall"
    <|> strField PPostinstall "postinstall"
    <|> strField PPreclean "preclean"
    <|> strField PPostclean "postclean"
    <|> do start <- location
           ignore $ exactProperty "version"
           mustWork $ do
             equals
             vs <- stringLit <||> sepBy1 dot' integerLit
             end <- location
             the (EmptyRule _ _ _) $ case vs of
                Left v   => pure (PVersionDep (MkFC (PhysicalPkgSrc fname) start end) v)
                Right vs => pure (PVersion (MkFC (PhysicalPkgSrc fname) start end)
                                    (MkPkgVersion (fromInteger <$> vs)))
    <|> do start <- location
           ignore $ exactProperty "langversion"
           mustWork $ do
             lvs <- langversions
             end <- location
             pure (PLangVersions (MkFC (PhysicalPkgSrc fname) start end) lvs)
    <|> do start <- location
           ignore $ exactProperty "version"
           mustWork $ do
             equals
             v <- stringLit
             end <- location
             pure (PVersionDep (MkFC (PhysicalPkgSrc fname) start end) v)
    <|> do ignore $ exactProperty "depends"
           mustWork $ do
             equals
             ds <- sep depends
             pure (PDepends ds)
    <|> do ignore $ exactProperty "modules"
           mustWork $ do
             equals
             ms <- sep (do start <- location
                           m <- moduleIdent
                           end <- location
                           pure (MkFC (PhysicalPkgSrc fname) start end, m))
             pure (PModules ms)
    <|> do ignore $ exactProperty "main"
           mustWork $ do
             equals
             start <- location
             m <- moduleIdent
             end <- location
             pure (PMainMod (MkFC (PhysicalPkgSrc fname) start end) m)
    <|> do ignore $ exactProperty "executable"
           mustWork $ do
             equals
             e <- (stringLit <|> packageName)
             pure (PExec e)
  where
    data Bound = LT PkgVersion Bool | GT PkgVersion Bool

    -- Each bound, and the grammars made of bounds, read after a property's
    -- name, so below the field's bound.
    bound : Rule n True (List Bound)
    bound
        = do lte
             vs <- sepBy1 dot' integerLit
             pure [LT (MkPkgVersion (fromInteger <$> vs)) True]
      <|> do gte
             vs <- sepBy1 dot' integerLit
             pure [GT (MkPkgVersion (fromInteger <$> vs)) True]
      <|> do lt
             vs <- sepBy1 dot' integerLit
             pure [LT (MkPkgVersion (fromInteger <$> vs)) False]
      <|> do gt
             vs <- sepBy1 dot' integerLit
             pure [GT (MkPkgVersion (fromInteger <$> vs)) False]
      <|> do eqop
             vs <- sepBy1 dot' integerLit
             pure [LT (MkPkgVersion (fromInteger <$> vs)) True,
                   GT (MkPkgVersion (fromInteger <$> vs)) True]

    mkBound : List Bound -> PkgVersionBounds -> EmptyRule n True PkgVersionBounds
    mkBound (LT b i :: bs) pkgbs
        = maybe (mkBound bs ({ upperBound := Just b,
                               upperInclusive := i } pkgbs))
                (\_ => fail "Dependency already has an upper bound")
                pkgbs.upperBound
    mkBound (GT b i :: bs) pkgbs
        = maybe (mkBound bs ({ lowerBound := Just b,
                               lowerInclusive := i } pkgbs))
                (\_ => fail "Dependency already has a lower bound")
                pkgbs.lowerBound
    mkBound [] pkgbs = pure pkgbs

    langversions : EmptyRule n True PkgVersionBounds
    langversions
        = do bs <- sepBy andop bound
             mkBound (concat bs) anyBounds

    depends : Rule n True Depends
    depends
        = do name <- packageName
             bs <- sepBy andop bound
             pure (MkDepends name !(mkBound (concat bs) anyBounds))

    strField : {0 rd : Bool} -> (FC -> String -> DescField) -> String -> Rule n rd DescField
    strField fieldConstructor fieldName
        = do start <- location
             ignore $ exactProperty fieldName
             mustWork $ do
               equals
               str <- stringLit
               end <- location
               pure $ fieldConstructor (MkFC (PhysicalPkgSrc fname) start end) str

    describes : FC -> String -> DescField
    describes _ _ = PDescribes

total
parsePkgDesc : String -> Rule n r (String, List DescField)
parsePkgDesc fname
    = do ignore $ exactProperty "package"
         name <- packageName
         fields <- many (field fname)
         EndOfInput <- peek
            | DotSepIdent _ name => fail "Unrecognised property \{show name}"
            | tok => fail "Expected end of file"
         pure (name, fields)

data ParsedMods : Type where

data MainMod : Type where

-- A module's identifier becomes a name here, where the package description
-- is read: the grammar that met it cannot intern it.
internModule : {auto c : Ref Ctxt Defs} ->
               (FC, List1 String) -> Core (FC, ModuleIdent)
internModule (fc, parts)
    = do ids <- traverse intern (forget parts)
         pure (fc, nsAsModuleIdent (nsOf ids))

addField : {auto c : Ref Ctxt Defs} ->
           {auto s : Ref Syn SyntaxInfo} ->
           {auto o : Ref ROpts REPLOpts} ->
           {auto p : Ref ParsedMods (List (FC, ModuleIdent))} ->
           {auto m : Ref MainMod (Maybe (FC, ModuleIdent))} ->
           DescField -> PkgDesc -> Core PkgDesc
addField (PVersion fc n)       pkg = pure $ { version := Just n } pkg
addField (PLangVersions fc bs) pkg = pure $ { langversion := Just bs } pkg
addField (PVersionDep fc n)   pkg
    = do emitWarning (Deprecated fc "version numbers must now be of the form x.y.z" Nothing)
         pure pkg
addField PDescribes          pkg = pure pkg
addField (PDepends ds)       pkg = pure $ { depends := ds } pkg
-- we can't resolve source files for modules without knowing the source directory,
-- so we save them for the second pass
addField (PModules ms)       pkg = do put ParsedMods !(traverse internModule ms)
                                      pure pkg
addField (PMainMod loc n)    pkg = do put MainMod (Just !(internModule (loc, n)))
                                      pure pkg
addField (PExec e)           pkg = pure $ { executable := Just e } pkg
addField (POpts fc e)        pkg = pure $ { options := Just (fc, e) } pkg
addField (PSourceDir fc a)   pkg = pure $ { sourcedir := Just a } pkg
addField (PDataDir fc a)     pkg = pure $ { datadir := Just a } pkg
addField (PBuildDir fc a)    pkg = pure $ { builddir := Just a } pkg
addField (POutputDir fc a)   pkg = pure $ { outputdir := Just a } pkg
addField (PPrebuild fc e)    pkg = pure $ { prebuild := Just (fc, e) } pkg
addField (PPostbuild fc e)   pkg = pure $ { postbuild := Just (fc, e) } pkg
addField (PPreinstall fc e)  pkg = pure $ { preinstall := Just (fc, e) } pkg
addField (PPostinstall fc e) pkg = pure $ { postinstall := Just (fc, e) } pkg
addField (PPreclean fc e)    pkg = pure $ { preclean := Just (fc, e) } pkg
addField (PPostclean fc e)   pkg = pure $ { postclean := Just (fc, e) } pkg

addFields : {auto c : Ref Ctxt Defs} ->
            {auto s : Ref Syn SyntaxInfo} ->
            {auto o : Ref ROpts REPLOpts} ->
            (setSrc : Bool) ->
            List DescField -> PkgDesc -> Core PkgDesc
addFields setSrc xs desc = do
  p <- newRef ParsedMods []
  m <- newRef MainMod Nothing
  added <- go {p} {m} xs desc
  when setSrc $ setSourceDir (sourcedir added)
  ms <- get ParsedMods
  mmod <- get MainMod
  pure $
    { modules := !(traverse toSource ms)
    , mainmod := !(traverseOpt toSource mmod)
    } added
  where
    toSource : (FC, ModuleIdent) -> Core (ModuleIdent, String)
    toSource (loc, ns) = pure (ns, !(nsToSource loc ns))
    go : {auto p : Ref ParsedMods (List (FC, ModuleIdent))} ->
         {auto m : Ref MainMod (Maybe (FC, ModuleIdent))} ->
         List DescField -> PkgDesc -> Core PkgDesc
    go [] dsc = pure dsc
    go (x :: xs) dsc = go xs !(addField x dsc)

-- A package's scripts run shell commands around the build, and its
-- executable asks for a code generator; this compiler does neither when it
-- handles a package. A package that has any of them is refused, naming the
-- field, before anything is built, installed or cleaned, rather than
-- handled without it.
refuseUnsupported : PkgDesc -> Core ()
refuseUnsupported pkg
    = do traverse_ script
           [ ("prebuild", prebuild pkg), ("postbuild", postbuild pkg)
           , ("preinstall", preinstall pkg), ("postinstall", postinstall pkg)
           , ("preclean", preclean pkg), ("postclean", postclean pkg) ]
         whenJust (executable pkg) $ \exec =>
           throw (GenericMsg emptyFC "unsupported: the package field `executable` (\{exec}) asks for a code generator, which this compiler does not run for a package")
  where
    script : (String, Maybe (FC, String)) -> Core ()
    script (_, Nothing) = pure ()
    script (field, Just (fc, _))
        = throw (GenericMsg fc "unsupported: the package field `\{field}` runs a shell script, which this compiler does not run")

export
parsePkgFile : {auto c : Ref Ctxt Defs} ->
               {auto s : Ref Syn SyntaxInfo} ->
               {auto o : Ref ROpts REPLOpts} ->
               (setSrc : Bool) -> -- parse package file as a dependency
               String -> Core PkgDesc
parsePkgFile setSrc file = do
    Right (pname, fs) <- coreLift $ parseFile file (parsePkgDesc file)
        | Left err => do
              Right res <- coreLift (readFile file)
                | _ => throw err
              setCurrentElabSource res
              doc <- perror err
              throw (UserError (render doc))
    addFields setSrc fs (initPkgDesc pname)

--------------------------------------------------------------------------------
--          Dependency Resolution
--------------------------------------------------------------------------------

record Candidate where
  constructor MkCandidate
  name      : String
  version   : Maybe PkgVersion
  directory : String

toCandidate : (name : String) -> (String,Maybe PkgVersion) -> Candidate
toCandidate name (dir,v) = MkCandidate name v dir

record ResolutionError where
  constructor MkRE
  decisions : List Candidate
  depends   : Depends
  version   : Maybe PkgVersion

prepend : Candidate -> ResolutionError -> ResolutionError
prepend p = { decisions $= (p ::)}

reason : Maybe PkgVersion -> String
reason Nothing  = "no matching version is installed."
reason (Just x) = "only found version \{show x} which is out of bounds."

printResolutionError : ResolutionError -> String
printResolutionError (MkRE ds d v) = go [<] ds
  where go : SnocList String -> List Candidate -> String
        go ss []        =
          let pre        := "Required \{d.pkgname} \{show d.pkgbounds} but"
              failure    := "\{pre} \{reason v}"
              candidates := case ss of
                               [<] => ""
                               ss  => " Resolved transitive dependencies: " ++ (fastConcat $ intersperse "; " $ cast ss) ++ "."
           in failure ++ candidates
        go ss (c :: cs) =
          let v := fromMaybe defaultVersion c.version
           in go (ss :< "\{c.name}-\{show v}") cs

data ResolutionRes : Type where
  Resolved : List PackageDir -> ResolutionRes
  Failed   : List ResolutionError -> ResolutionRes

printErrs : (pkgDirs : List String) -> PkgDesc -> List ResolutionError -> String
printErrs pkgDirs x es =
  let errors := unlines $ "Failed to resolve the dependencies for \{x.name}:"
                          :: map (indent 2 . printResolutionError) es
      dirs   := unlines $ "Searched for packages in:"
                          :: map (indent 2) pkgDirs
  in """
     \{errors}
     \{dirs}
     For more details on what packages Idris2 can locate, run `idris2 --list-packages`
     """

-- try all possible resolution paths, keeping the first
-- that works
tryAll :  List Candidate
       -> (Candidate -> Core ResolutionRes)
       -> Core ResolutionRes
tryAll ps f = go [<] ps
  where go :  SnocList ResolutionError
           -> List Candidate
           -> Core ResolutionRes
        go se []        = pure (Failed $ se <>> [])
        go se (x :: xs) = do
          Failed errs <- f x | Resolved res => pure (Resolved res)
          go (se <>< map (prepend x) errs) xs

pkgDirs :
    {auto c : Ref Ctxt Defs} ->
    Core (List String)
pkgDirs = do
  localdir <- pkgLocalDirectory
  d <- getDirs
  pure (localdir ::  (show <$> d.package_search_paths))

||| Add all dependencies (transitively) from the given package file into the
||| context so modules from each is accessible during compilation.
addDeps :
    {auto c : Ref Ctxt Defs} ->
    {auto s : Ref Syn SyntaxInfo} ->
    {auto o : Ref ROpts REPLOpts} ->
    PkgDesc ->
    Core ()
addDeps pkg = do
  Resolved allPkgs <- getTransitiveDeps pkg.depends empty
    | Failed errs => throw $ GenericMsg EmptyFC (printErrs !pkgDirs pkg errs)
  log "package.depends" 10 $ "all depends: \{show allPkgs}"
  traverse_ addPackageDir allPkgs
  traverse_ addDataDir ((\pkg => pkg.dir </> "data") <$> allPkgs)
  where
    -- Note: findPkgDir throws an error if a package is not found
    -- *unless* --ignore-missing-ipkg is enabled
    -- therefore, if findPkgDir returns Nothing, skip the package
    --
    -- We use a backtracking algorithm here: If several versions of
    -- a package are installed, we must try all, which are are
    -- potentially in bounds, because their set of dependencies
    -- might be different across versions and not all of them
    -- might lead to a resolvable situation.
    getTransitiveDeps :
        List Depends ->
        (done : StringMap (Maybe PkgVersion)) ->
        Core ResolutionRes
    getTransitiveDeps [] done = do
      ms <- for (StringMap.toList done) $
        \(pkg, mv) => findPkgDir pkg (exactBounds mv)
      pure . Resolved $ catMaybes ms

    getTransitiveDeps (dep :: deps) done =
      case lookup dep.pkgname done of
        Just mv =>
          if inBounds mv dep.pkgbounds
            -- already resolved dependency is in bounds
            -- so we keep it and resolve remaining deps
            then getTransitiveDeps deps done
            -- the resolved dependency does not satisfy the
            -- current bounds. we return an error and backtrack
            else pure (Failed [MkRE [] dep $ mv <|> Just defaultVersion])
        Nothing => do
          log "package.depends" 50 "adding new dependency: \{dep.pkgname} (\{show dep.pkgbounds})"
          pkgDirs <- findPkgDirs dep.pkgname dep.pkgbounds
          let candidates := toCandidate dep.pkgname <$> pkgDirs

          case candidates of
            [] => do
              defs <- get Ctxt
              if defs.options.session.ignoreMissingPkg
                -- this corresponds to what `findPkgDir` does in
                -- case of `ignoreMissingPkg` being set to `True`
                then getTransitiveDeps deps done
                else pure (Failed [MkRE [] dep Nothing])

            _  => tryAll candidates $ \(MkCandidate name mv pkgDir) => do
              let pkgFile = pkgDir </> name <.> "ipkg"
              True <- coreLift $ exists pkgFile
                | False => getTransitiveDeps deps (insert name mv done)
              pkg <- parsePkgFile False pkgFile
              getTransitiveDeps
                (pkg.depends ++ deps)
                (insert pkg.name pkg.version done)

--------------------------------------------------------------------------------
--          Processing Options
--------------------------------------------------------------------------------

processOptions : {auto c : Ref Ctxt Defs} ->
                 Maybe (FC, String) -> Core ()
processOptions Nothing = pure ()
processOptions (Just (fc, opts))
    = do let Right clopts = getOpts (words opts)
                | Left err => throw (GenericMsg fc err)
         preOptions clopts

||| Emit captured warnings from inner scope and clear them
||| afterwards (to avoid emitting them in some unrelated
||| codepath later).
withWarnings : Ref Ctxt Defs =>
               Ref Syn SyntaxInfo =>
               Ref ROpts REPLOpts =>
               Core a -> Core a
withWarnings op = do o <- catch op $ \err =>
                           do emit
                              throw err
                     emit
                     pure o
  where
    emit : Core ()
    emit = do
      ignore emitWarnings
      update Ctxt { warnings := [] }

prepareCompilation : {auto c : Ref Ctxt Defs} ->
                     {auto s : Ref Syn SyntaxInfo} ->
                     {auto o : Ref ROpts REPLOpts} ->
                     PkgDesc ->
                     Core (List Error)
prepareCompilation pkg =
  do
    processOptions (options pkg)
    withWarnings $ addDeps pkg

    let toBuild = maybe (modules pkg) (:: modules pkg) (mainmod pkg)
    buildAll toBuild

assertIdrisCompatibility : PkgDesc -> Core ()
assertIdrisCompatibility pkg
    = do let Just requiredBounds = pkg.langversion
           | Nothing => pure ()
         unless (inBounds version requiredBounds) $
           throw (GenericMsg emptyFC "\{pkg.name} requires Idris2 \{show requiredBounds} but the installed version of Idris2 is \{show Version.version}.")

export
build : {auto c : Ref Ctxt Defs} ->
        {auto s : Ref Syn SyntaxInfo} ->
        {auto o : Ref ROpts REPLOpts} ->
        PkgDesc ->
        Core (List Error)
build pkg
    = do assertIdrisCompatibility pkg
         prepareCompilation pkg

installBuildArtifactFrom : String -> String -> String -> ModuleIdent -> Core ()

installBuildArtifactFrom file_extension builddir destdir ns
    = do let filename_trunk = ModuleIdent.toPath ns
         let filename = builddir </> filename_trunk <.> file_extension

         let modPath  = reverse $ map (.text) $ fromMaybe [] $ tail' $ unsafeUnfoldModuleIdent ns
         let destNest = joinPath modPath
         let destPath = destdir </> destNest
         let destFile = destdir </> filename_trunk <.> file_extension

         Right _ <- coreLift $ mkdirAll $ destPath
             | Left err => throw $ InternalError $ unlines
                             [ "Can't make directories " ++ show modPath
                             , show err ]
         coreLift $ putStrLn $ "Installing " ++ filename ++ " to " ++ destPath
         Right _ <- coreLift $ copyFile filename destFile
             | Left err => throw $ InternalError $ unlines
                             [ "Can't copy file " ++ filename ++ " to " ++ destPath
                             , show err ]

         pure ()

installFrom : {auto o : Ref ROpts REPLOpts} ->
              {auto c : Ref Ctxt Defs} ->
              String -> String -> ModuleIdent -> Core ()
installFrom builddir destdir ns = installBuildArtifactFrom "ttc" builddir destdir ns

absoluteInstallDir : (relativeInstallDir : String) -> Core String
absoluteInstallDir relativeInstallDir = do
  mdestdir <- coreLift $ getEnv "DESTDIR"
  let destdir = fromMaybe "" mdestdir
  pure $ destdir ++ relativeInstallDir

-- Install all the built modules in prefix/package/
-- We've already built and checked for success, so if any don't exist that's
-- an internal error.
install : {auto c : Ref Ctxt Defs} ->
          {auto o : Ref ROpts REPLOpts} ->
          PkgDesc ->
          Core ()
install pkg
    = do build <- ttcBuildDirectory
         let lib = installDir pkg
         libTargetDir <- absoluteInstallDir =<< libInstallDirectory lib
         ttcTargetDir <- absoluteInstallDir =<< ttcInstallDirectory lib

         let toInstall = maybe (modules pkg)
                               (:: modules pkg)
                               (mainmod pkg)
         wdir <- getWorkingDir
         -- Make the package installation directory
         Right _ <- coreLift $ mkdirAll libTargetDir
             | Left err => throw $ InternalError $ unlines
                             [ "Can't make directory " ++ libTargetDir
                             , show err ]

         traverse_ (installFrom (wdir </> build) ttcTargetDir . fst) toInstall

         -- install package file
         let pkgFile = libTargetDir </> pkg.name <.> "ipkg"
         coreLift $ putStrLn $ "Installing package file for \{pkg.name} to \{libTargetDir}"

         let pkgStr = String.renderString $ layoutUnbounded $ pretty $ savePkgMetadata pkg
         log "package.depends" 25 $ "  package file:\n\{pkgStr}"
         coreLift_ $ writeFile pkgFile pkgStr
  where
    savePkgMetadata : PkgDesc -> PkgDesc
    savePkgMetadata pkg =
      the (PkgDesc -> PkgDesc)
      { depends := pkg.depends
      , version := pkg.version
      } $ initPkgDesc pkg.name

clean : {auto c : Ref Ctxt Defs} ->
        PkgDesc ->
        Core ()
clean pkg
    = do let pkgmods = maybe
                         (map fst (modules pkg))
                         (\m => fst m :: map fst (modules pkg))
                         (mainmod pkg)
         let toClean : List (List String, String)
               = mapMaybe (artifact . unsafeUnfoldModuleIdent) pkgmods
         srcdir <- getWorkingDir
         -- ttcBuildDirectory is already where the TTCs are (build/ttc/<TTC
         -- version>); upstream appends another "ttc" and so removes nothing.
         bdir <- ttcBuildDirectory
         let builddir = srcdir </> bdir
         -- the usual pair syntax breaks with `No such variable a` here for some reason
         let pkgTrie : StringTrie (List String)
                     = foldl (\trie, ksv =>
                                let ks = Builtin.fst ksv
                                    v = Builtin.snd ksv
                                  in
                                insertWith (reverse ks) (maybe [v] (v::)) trie) empty toClean
         -- The fold takes its monad and monoid as one pair; Core's monad is
         -- named, so it is given, and unit's monoid found.
         foldWithKeysM @{(Monad.CORE, %search)} (deleteFolder builddir)
                       (\ks => map concat . traverse (deleteBin builddir ks))
                       pkgTrie
         deleteFolder builddir []
  where
    -- Where a module's build artifact is, as file path parts: the
    -- directories of its namespace, innermost first, and its own name.
    artifact : List Ident -> Maybe (List String, String)
    artifact [] = Nothing
    artifact (x :: xs) = Just (map (.text) xs, x.text)

    delete : String -> Core ()
    delete path = do Right () <- coreLift $ removeFile path
                       | Left err => pure ()
                     coreLift $ putStrLn $ "Removed: " ++ path

    deleteFolder : String -> List String -> Core ()
    deleteFolder builddir ns = delete $ builddir </> joinPath ns

    deleteBin : String -> List String -> String -> Core ()
    deleteBin builddir ns mod
        = do let ttFile = builddir </> joinPath ns </> mod
             delete $ ttFile <.> "ttc"
-- The package path given is no package file's.
notPackageFile : String -> Core a
notPackageFile file
    = do coreLift $ putStrLn ("Packages must have an '.ipkg' extension: " ++ show file ++ ".")
         coreLift (exitWith (ExitFailure 1))

||| A package command, on the package file given: building and checking a
||| package are one, since a package's modules are checked and nothing is
||| generated from them.
export
processPackage : {auto c : Ref Ctxt Defs} ->
                 {auto s : Ref Syn SyntaxInfo} ->
                 {auto o : Ref ROpts REPLOpts} ->
                 PkgCommand -> (file : String) -> Core ()
processPackage cmd file
    = withCtxt . withSyn . withROpts $
          do -- A path with no last part (empty, or a root) names no file,
             -- so no package file: it has no '.ipkg' extension either.
             let Just (dir, filename) = splitParent file
                 | Nothing => notPackageFile file
             let True = isSuffixOf ".ipkg" filename
                 | _ => notPackageFile file
             setWorkingDir dir
             pkg <- parsePkgFile True filename
             refuseUnsupported pkg
             whenJust (builddir pkg) setBuildDir
             whenJust (datadir pkg) addDataDir
             setOutputDir (outputdir pkg)
             case cmd of
                  Build => built pkg
                  Install => do built pkg
                                install pkg
                  Typecheck => built pkg
                  Clean => clean pkg
  where
    built : PkgDesc -> Core ()
    built pkg = do [] <- build pkg
                     | errs => coreLift (exitWith (ExitFailure 1))
                   pure ()
