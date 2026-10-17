-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.Termination.References

import Core.Binary
import Core.Context.Log
import Core.Directory

import Libraries.Data.NameMap

||| The definitions of every module the context's imports reach without
||| importing it, read now if a module is named and not read yet: each
||| module named, unless the context imports it, and every module it
||| imports in turn.
unimportedDefinitions : {auto c : Ref Ctxt Defs} -> Core (NameMap ContextEntry)
unimportedDefinitions
    = do defs <- get Ctxt
         case unimported defs of
              MkUnimported [] read => pure read
              MkUnimported unread read =>
                do ds <- readAll (map (\(_, (m, _, _)) => m) (allImported defs)) unread read
                   update Ctxt { unimported := MkUnimported [] ds }
                   pure ds
  where
    readAll : List ModuleIdent -> List ModuleIdent -> NameMap ContextEntry ->
              Core (NameMap ContextEntry)
    readAll seen [] ds = pure ds
    readAll seen (m :: ms) ds
        = if m `elem` seen
             then readAll seen ms ds
             else do Right fname <- nsToPath EmptyFC m
                       | Left err => throw err
                     (imps, ns, entries) <- readDefinitions fname
                     readAll (m :: seen) (imps ++ ms)
                             (mergeLeft ds (fromList (map (\(n, bin) => (n, Coded ns bin)) entries)))

||| The definition a module the context's imports reach holds under a full
||| name, read with the others the first time one is asked for. A name that
||| is not full is not a definition of another module, and reads nothing.
lookupUnimported : {auto c : Ref Ctxt Defs} -> Name -> Core (Maybe GlobalDef)
lookupUnimported n@(NS _ _)
    = do Just entry <- lookup n <$> unimportedDefinitions
           | Nothing => pure Nothing
         defs <- get Ctxt
         def <- decode (gamma defs) 0 False entry
         update Ctxt { unimported->unimportedDefs $= insert n (Decoded def) }
         pure (Just def)
lookupUnimported _ = pure Nothing

||| The definition of a name the termination check meets: the context's, or
||| one a module the context's imports reach holds. A module's definitions
||| name only what its own imports reach, so every definition a loaded
||| definition names is one of these. Nothing for a name that is no
||| definition: a variable a definition binds, which its references hold
||| beside the definitions it names.
export
lookupReached : {auto c : Ref Ctxt Defs} -> Name -> Core (Maybe GlobalDef)
lookupReached n
    = do defs <- get Ctxt
         Nothing <- lookupCtxtExact n (gamma defs)
           | Just def => pure (Just def)
         lookupUnimported n

||| Records whether a definition the check met terminates, where it is
||| held: in the context, or among the unimported definitions, for as long
||| as they are held.
export
setReachedTerminating : {auto c : Ref Ctxt Defs} ->
                        FC -> Name -> Terminating -> Core ()
setReachedTerminating loc n tot
    = do defs <- get Ctxt
         Nothing <- lookupCtxtExact n (gamma defs)
           | Just _ => setTerminating loc n tot
         Just def <- lookupUnimported n
           | Nothing => undefinedName loc n
         update Ctxt { unimported->unimportedDefs $=
                         insert n (Decoded ({ totality->isTerminating := tot } def)) }

-- Check that the names a function refers to are terminating
export
totRefs : {auto c : Ref Ctxt Defs} ->
          List Name -> Core Terminating
totRefs [] = pure IsTerminating
totRefs (n :: ns)
    = do rest <- totRefs ns
         -- A name that is no definition, a variable, has no totality.
         Just d <- lookupReached n
              | Nothing => pure rest
         case isTerminating (totality d) of
              IsTerminating => pure rest
              Unchecked => do
                logC "totality" 20 $ do pure $ "Totality unchecked for " ++ show !(toFullNames n)
                pure rest
              _ => case rest of
                          NotTerminating (BadCall ns)
                             => toFullNames $ NotTerminating (BadCall (n :: ns))
                          _ => toFullNames $ NotTerminating (BadCall [n])

export
totRefsIn : {auto c : Ref Ctxt Defs} ->
            Term vars -> Core Terminating
totRefsIn ty = totRefs (keys (getRefs (Resolved (-1)) ty))
