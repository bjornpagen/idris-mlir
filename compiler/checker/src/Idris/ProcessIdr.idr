-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Idris.ProcessIdr

-- Core.Unify declares `search` and Core.AutoSearch defines it, so a program
-- that elaborates must load Core.AutoSearch, which nothing else imports:
-- upstream's driver reached it through the REPL.
import Core.AutoSearch
import Core.Binary
import Core.Directory
import Core.Env
import Core.Hash
import Core.Metadata
import Core.Unify

import Parser.Unlit

import TTImp.Elab.Check
import TTImp.ProcessDecls
import TTImp.ProcessDecls.Totality
import TTImp.TTImp

import Idris.Desugar
import Idris.Desugar.Mutual
import Idris.Parser
import Idris.REPL.Common
import Idris.Syntax
import Idris.Syntax.Tree
import Idris.Syntax.TTC
import Idris.Pretty
import Idris.Doc.String

import Data.List
import Data.SortedMap
import Data.String

import System.File

%default covering

processDecls : {auto c : Ref Ctxt Defs} ->
               {auto u : Ref UST UState} ->
               {auto dl : Ref DLY DelayedElabs} ->
               {auto s : Ref Syn SyntaxInfo} ->
               {auto m : Ref MD Metadata} ->
               {auto o : Ref ROpts REPLOpts} ->
               List PDecl -> Core (List Error)

processDecl : {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              {auto dl : Ref DLY DelayedElabs} ->
              {auto s : Ref Syn SyntaxInfo} ->
              {auto m : Ref MD Metadata} ->
              {auto o : Ref ROpts REPLOpts} ->
              PDecl -> Core (List Error)

-- Special cases to avoid treating these big blocks as units
-- This should give us better error recovery (the whole block won't fail
-- as soon as one of the definitions fails)
processDecl (MkFCVal _ $ PNamespace ns ps)
    = withExtendedNS ns $ processDecls ps
processDecl (MkFCVal _ $ PMutual ps)
    = let (tys, defs) = splitMutual ps in
      processDecls (tys ++ defs)

processDecl decl
    = catch (do impdecls <- desugarDecl [] decl
                traverse_ (Check.processDecl [] (MkNested []) Env.empty) impdecls
                pure [])
            (\err => do giveUpConstraints -- or we'll keep trying...
                        pure [err])

processDecls decls
    = do errs <- concat <$> traverse processDecl decls
         Nothing <- checkDelayedHoles
             | Just err => pure (if null errs then [err] else errs)
         pure errs

-- Reads a module and what it imports, and gives the module as the session
-- read it, now or before, in the same way: an import of it is resolved
-- here, once, and its reader is handed the module rather than its name.
-- Each import of the module read in turn is recorded with the module it
-- was read as (`addImportRead`).
readModule : {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             {auto s : Ref Syn SyntaxInfo} ->
             (full : Bool) -> -- load everything transitively (needed for REPL and compiling)
             FC ->
             (visible : Bool) -> -- Is import visible to top level module?
             (imp : ModuleIdent) -> -- Module name to import
             (as : Namespace) -> -- Namespace to import into
             Core Loaded
readModule full loc vis imp as
    = do defs <- get Ctxt
         let Nothing = find (\l => l.ident == imp && l.reexported == vis && l.readAs == as)
                            (allImported defs)
             | Just before => do when vis (setVisible (miAsNamespace imp))
                                 pure before
         Right checked <- nsToPath loc imp
               | Left err => throw err
         let loading = MkLoaded checked.path checked.foundIn imp vis as
         Just (syn, hash, more) <- readFromTTC False {extra = SyntaxInfo} loc loading
              | Nothing => do when vis (setVisible (miAsNamespace imp)) -- already loaded, just set visibility
                              pure loading
         extendSyn syn

         defs <- get Ctxt
         modNS <- getNS
         when vis $ setVisible (miAsNamespace imp)
         traverse_ (\ mimp =>
                       if reexport mimp || full
                          then do importee <- readModule full loc (reexport mimp) (path mimp) (nameAs mimp)
                                  addImportRead (MkImportRead loading mimp importee)
                          else addUnimported (path mimp)) more
         setNS modNS
         pure loading

readImport : {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             {auto s : Ref Syn SyntaxInfo} ->
             Bool -> Import -> Core ()
readImport full imp
    = do ignore $ readModule full (loc imp) True (path imp) (nameAs imp)
         addImported imp

||| Adds new import to the namespace without changing the current top-level namespace
export
addImport : {auto c : Ref Ctxt Defs} ->
            {auto u : Ref UST UState} ->
            {auto s : Ref Syn SyntaxInfo} ->
            Import -> Core ()
addImport imp
    = do topNS <- getNS
         readImport True imp
         setNS topNS

readImportMeta : {auto c : Ref Ctxt Defs} ->
                 Import -> Core (Bool, (Namespace, Int))
readImportMeta imp
    = do Right checked <- nsToPath (loc imp) (path imp)
               | Left err => throw err
         interfaceHash <- readHashes checked.path
         pure (reexport imp, (nameAs imp, interfaceHash))

prelude : Import
prelude = MkImport (MkFC (Virtual Interactive) (0, 0) (0, 0)) False
                     (nsAsModuleIdent preludeNS) preludeNS

export
readPrelude : {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              {auto s : Ref Syn SyntaxInfo} ->
              Bool -> Core ()
readPrelude full
    = do readImport full prelude
         setNS mainNS

-- Import a TTC for use as the main file (e.g. at the REPL), and give the
-- module as the session read it. It is read under the module its path
-- names (`mainIdent`), which the locations of its terms name, as every
-- module the session reads is under the module its locations name; read
-- as its own namespace, its definitions are added under no alias, as when
-- it was read under no name.
export
readAsMain : {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             {auto s : Ref Syn SyntaxInfo} ->
             (mainIdent : ModuleIdent) -> (fname : String) -> Core Loaded
readAsMain mainIdent fname
    = do let loading = MkLoaded fname InBuild mainIdent True (miAsNamespace mainIdent)
         Just (syn, _, more) <- readFromTTC {extra = SyntaxInfo} True EmptyFC loading
              | Nothing => throw (InternalError "Already loaded")

         replNS <- getNS
         replNestedNS <- getNestedNS
         extendSyn syn

         -- Read the main file's top level imported modules, so we have access
         -- to their names (and any of their public imports)
         ustm <- get UST
         traverse_ (\ mimp =>
                       do importee <- readModule True emptyFC True (path mimp) (nameAs mimp)
                          addImportRead (MkImportRead loading mimp importee)
                          addImported ({ reexport := True } mimp)) more

         -- also load the prelude, if required, so that we have access to it
         -- at the REPL. Read for the session, it records no import: an
         -- import of the prelude the main module's TTC holds is among those
         -- above.
         when (not (noprelude !getSession)) $
              ignore $ readModule True emptyFC True (nsAsModuleIdent preludeNS) preludeNS

         -- We're in the namespace from the first TTC, so use the next name
         -- from that for the fresh metavariable name generation
         -- TODO: Maybe we should record this per namespace, since this is
         -- a little bit of a hack? Or maybe that will have too much overhead.
         update UST { nextName := nextName ustm }

         setNS replNS
         setNestedNS replNestedNS
         pure loading

addPrelude : List Import -> List Import
addPrelude imps
  = if not (nsAsModuleIdent preludeNS `elem` map path imps)
       then prelude :: imps
       else imps

export
readHeader : {auto c : Ref Ctxt Defs} ->
             {auto o : Ref ROpts REPLOpts} ->
             (path : String) -> (origin : ModuleIdent) -> Core Module
readHeader path origin
    = do Right res <- coreLift (readFile path)
            | Left err => throw (FileErr path err)
         -- Stop at the first :, that's definitely not part of the header, to
         -- save lexing the whole file unnecessarily
         setCurrentElabSource res -- for error printing purposes
         Right (ws, decor, mod) <-
             runParserTo (PhysicalIdrSrc origin)
                         (isLitFile path) (is ':') res
                         (progHdr (PhysicalIdrSrc origin))
            | Left err => throw err
         traverse_ recordWarning ws
         pure mod

export
addPublicHash : {auto c : Ref Ctxt Defs} ->
                (Bool, (Namespace, Int)) -> Core ()
addPublicHash (True, (mod, h)) = do addHash mod
                                    addHash h
                                    log "module.hash" 15 "Adding hash for a public import of \{show mod}"
addPublicHash _ = pure ()

||| Determine if the TTC is outdated based on any of the given
||| source or dependency source file names.
export
isTTCOutdated : {auto c : Ref Ctxt Defs} ->
                (ttcFile : String) ->
                (sourceFiles : List String) ->
                Core Bool
isTTCOutdated ttcFile sourceFiles
  = do ttcTime  <- modTime ttcFile
       srcTimes <- traverse modTime sourceFiles
       log "module.hash" 20 $
         unlines $
           "Checking whether source code mod times are newer than \{show ttcTime}; src times:"
           :: zipWith (\ src, tm => "\{src} : \{show tm}") sourceFiles srcTimes
       pure $ any (>= ttcTime) srcTimes

||| Process everything in the module; return the syntax information which
||| needs to be written to the TTC (e.g. exported infix operators)
||| Returns 'Nothing' if it didn't reload anything
processMod : {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             {auto dl : Ref DLY DelayedElabs} ->
             {auto s : Ref Syn SyntaxInfo} ->
             {auto m : Ref MD Metadata} ->
             {auto o : Ref ROpts REPLOpts} ->
             (sourceFileName : String) ->
             (ttcFileName : String) ->
             (msg : Doc IdrisAnn) ->
             (sourcecode : String) ->
             (origin : ModuleIdent) ->
             Core (Maybe (List Error))
processMod sourceFileName ttcFileName msg sourcecode origin
    = catch (do
        setCurrentElabSource sourcecode
        session <- getSession

        -- Just read the header to start with (this is to get the imports and
        -- see if we can avoid rebuilding if none have changed)
        moduleHeader <- readHeader sourceFileName origin
        let ns = moduleNS moduleHeader

        -- Add an implicit prelude import
        let allImports =
          if (session.noprelude || moduleNS moduleHeader == nsAsModuleIdent preludeNS)
             then imports moduleHeader
             else addPrelude $ imports moduleHeader

        importMetas <- traverse readImportMeta allImports
        let importInterfaceHashes = snd <$> importMetas

        defs <- get Ctxt
        log "module.hash" 5 $ "Interface hash of " ++ show ns ++ ": " ++ show (ifaceHash defs)
        log "module.hash" 5 $ "Import Interface hashes of " ++ show ns ++ " hashes:\n" ++
          show (sort importInterfaceHashes)
        storedImportInterfaceHashes <- readImportHashes ttcFileName
        log "module.hash" 5 $ "Stored interface hashes of " ++ ttcFileName ++ ":\n" ++
          show (sort storedImportInterfaceHashes)

        sourceUnchanged <- not <$> isTTCOutdated ttcFileName [sourceFileName]

        -- If neither the source nor the interface hashes of imports have changed then no rebuilding is needed
        if (sourceUnchanged && sort importInterfaceHashes == sort storedImportInterfaceHashes)
           then -- Hashes the same, source up to date, just set the ns
                -- for the REPL
                do setNS (miAsNamespace ns)
                   pure Nothing
           else -- needs rebuilding
             do iputStrLn msg
                Right (ws, MkState decor hnames uses, mod) <-
                    logTime 2 ("Parsing " ++ sourceFileName) $
                      runParser (PhysicalIdrSrc origin)
                                (isLitFile sourceFileName)
                                sourcecode
                                (do p <- prog (PhysicalIdrSrc origin); eoi; pure p)
                  | Left err => pure (Just [err])
                traverse_ recordWarning ws

                -- save the doc info for the current module
                log "doc.module" 10 $ unlines
                  [ "Recording doc", documentation moduleHeader
                  , "and imports " ++ show (imports moduleHeader)
                  , "for module " ++ show (moduleNS moduleHeader)
                  ]
                addModDocInfo
                  (moduleNS moduleHeader)
                  (documentation moduleHeader)
                  (filter reexport $ imports moduleHeader)

                addSemanticDecorations decor
                update Syn { holeNames := hnames }
                setPragmaUses uses

                initHash
                traverse_ addPublicHash (sort importMetas)
                resetNextVar
                when (ns /= nsAsModuleIdent mainNS) $
                      when (ns /= origin) $
                          throw (GenericMsg mod.headerLoc
                                   ("Module name " ++ show ns ++
                                    " does not match file name " ++ show sourceFileName))

                -- read import ttcs in full here
                -- Note: We should only import .ttc - assumption is that there's
                -- a phase before this which builds the dependency graph
                -- (also that we only build child dependencies if rebuilding
                -- changes the interface - will need to store a hash in .ttc!)
                logTime 2 "Reading imports" $
                   traverse_ (readImport False) allImports

                -- Before we process the source, make sure the "hide_everywhere"
                -- names are set to private (TODO, maybe if we want this?)
--                 defs <- get Ctxt
--                 traverse (\x => setVisibility emptyFC x Private) (hiddenNames defs)
                setNS (miAsNamespace ns)
                errs <- logTime 2 "Processing decls" $
                            processDecls (decls mod)
                totErrs <- logTime 3 ("Totality check overall")
                            getTotalityErrors
                let errs = errs ++ totErrs

                -- Save the import hashes for the imports we just read.
                -- If they haven't changed next time, and the source
                -- file hasn't changed, no need to rebuild.
                update Ctxt { importHashes := importInterfaceHashes }
                pure (Just errs))
          (\err => pure (Just [err]))

-- Process a file. Returns any errors, rather than throwing them, because there
-- might be lots of errors collected across a whole file.
export
process : {auto c : Ref Ctxt Defs} ->
          {auto m : Ref MD Metadata} ->
          {auto u : Ref UST UState} ->
          {auto dl : Ref DLY DelayedElabs} ->
          {auto s : Ref Syn SyntaxInfo} ->
          {auto o : Ref ROpts REPLOpts} ->
          (msgPrefix : Doc IdrisAnn) ->
          (buildMsg : Doc IdrisAnn) ->
          FileName ->
          (moduleIdent : ModuleIdent) ->
          Core (List Error)
process msgPrefix buildMsg sourceFileName ident
    = do Right res <- coreLift (readFile sourceFileName)
               | Left err => pure [FileErr sourceFileName err]
         catch (do ttcFileName <- getTTCFileName sourceFileName "ttc"
                   Just errs <- logTime 1 ("Elaborating " ++ sourceFileName) $
                                   processMod sourceFileName ttcFileName
                                              (msgPrefix <++> "Building" <++> buildMsg)
                                              res ident
                     | Nothing => do log "module" 10 $ show $ msgPrefix <++> "Skipping" <++> buildMsg
                                     pure [] -- skipped it
                   if isNil errs
                      then
                        do ns <- ctxtPathToNS sourceFileName
                           makeBuildDirectory ns
                           writeToTTC !(get Syn) sourceFileName ttcFileName
                           pure []
                      else do pure errs)
               (\err => pure [err])
