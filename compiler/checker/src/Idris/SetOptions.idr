-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Idris.SetOptions

import Core.Binary
import Core.Directory
import Core.Unify
import Libraries.Utils.Path
import Libraries.Data.List.Extra

import Idris.CommandLine
import Idris.Package.Types
import Idris.Parser
import Idris.Pretty
import Idris.ProcessIdr
import Idris.REPL.Common
import Idris.Syntax
import Idris.Version

import Data.List1
import Data.String
import Libraries.Utils.String

import System
import System.Directory

%default covering

||| Dissected information about a package directory
record PkgDir where
  constructor MkPkgDir
  ||| Directory name. Example "contrib-0.3.0"
  dirName : String
  ||| Package name. Example "contrib"
  pkgName : String
  ||| Package version. Example `Just $ MkPkgVersion (0 ::: [3,0])`
  version : Maybe PkgVersion
  ||| Versions of binary TTC format supported by library
  ttcVersions : List Int

-- dissects a directory name, trying to extract
-- the corresponding package name and -version
pkgDir : (dirName : String) -> (ttcDirs : List Int) -> PkgDir
pkgDir dirName ttcDirs =
   -- Split the dir name into parts concatenated by "-"
   -- treating the last part as the version number
   -- and the initial parts as the package name.
   -- For reasons of backwards compatibility, we also
   -- accept hyphenated directory names without a part
   -- corresponding to a version number.
   case unsnoc $ split (== '-') dirName of
     (Nil, last) => MkPkgDir dirName last Nothing ttcDirs
     (init,last) =>
       case toVersion last of
         Just v  => MkPkgDir dirName (concat $ intersperse "-" init) (Just v) ttcDirs
         Nothing => MkPkgDir dirName dirName Nothing ttcDirs
  where
    toVersion : String -> Maybe PkgVersion
    toVersion = map MkPkgVersion
              . traverse parseNatural
              . split (== '.')

listDirOrEmpty : String -> IO (List String)
listDirOrEmpty dir = either (const []) id <$> listDir dir

getPackageDirs : String -> IO (List PkgDir)
getPackageDirs dname = do
  packageDirNames <- listDirOrEmpty dname
  traverse (\d => pkgDir d <$> ttcVersions d) packageDirNames
  where
    ttcVersions : String -> IO (List Int)
    ttcVersions dir = catMaybes . map parseNatural <$> listDirOrEmpty (dname </> dir)

||| Get a list of all the candidate directories that match a package spec
||| in a given path. Return an empty list on file error (e.g. path not existing)
|||
||| Only package's with build artifacts for the correct TTC version for the
||| compiler will be considered.
export
candidateDirs :
    Ref Ctxt Defs =>
    String -> String -> PkgVersionBounds ->
    Core (List (String, Maybe PkgVersion))
candidateDirs dname pkgName bounds = do
  dirs <- coreLift (getPackageDirs dname)
  checkedDirs <- traverse check dirs
  pure (catMaybes checkedDirs)

  where
    data CandidateError = OutOfBounds | TTCMismatch

    checkNameAndBounds : PkgDir -> Either CandidateError PkgDir
    checkNameAndBounds pkg =
      if pkg.pkgName == pkgName && inBounds pkg.version bounds
         then Right pkg
         else Left OutOfBounds

    checkTTCVersion : PkgDir -> Either CandidateError PkgDir
    checkTTCVersion pkg =
      if ttcVersion `elem` pkg.ttcVersions
         then Right pkg
         else Left TTCMismatch

    unpack : PkgDir -> (String, Maybe PkgVersion)
    unpack (MkPkgDir dirName pkgName ver _) =
      ((dname </> dirName), ver)

    check : PkgDir -> Core (Maybe (String, Maybe PkgVersion))
    check pkg =
      let checkedPkg = checkNameAndBounds pkg >>= checkTTCVersion
      in
      case checkedPkg of
        Right pkg'       => pure . Just $ unpack pkg'
        Left OutOfBounds => pure Nothing
        Left TTCMismatch => do
          let pkgVersion = maybe "unversioned" (\v => "version \{show v} of") pkg.version
          recordWarning $ GenericWarn EmptyFC $
                 """
                 Found \{pkgVersion} package \{pkg.pkgName} installed with no compatible binaries for the current Idris2 compiler.

                 Reinstall \{pkg.pkgName} with the current Idris2 compiler to resolve the issue.
                 """
          pure Nothing

||| Find all package directories (plus version) matching
||| the given package name and version bounds. Results
||| will be sorted with the latest package version first.
|||
||| All package _search paths_ will be searched for package
||| _directories_ that fit the requested critera.
|||
||| Only packages with build artifacts for the correct TTC version for the
||| compiler will be considered.
export
findPkgDirs :
    Ref Ctxt Defs =>
    String ->
    PkgVersionBounds ->
    Core (List (String, Maybe PkgVersion))
findPkgDirs p bounds = do
  localdir <- pkgLocalDirectory

  -- Get candidate directories from the local package directory
  locFiles <- candidateDirs localdir p bounds
  -- Look in all the package paths too
  d <- getDirs
  pkgFiles <- traverse (\d => candidateDirs (show d) p bounds) d.package_search_paths

  -- If there's anything locally, use that and ignore the global ones
  let allFiles = if isNil locFiles
                    then concat pkgFiles
                    else locFiles
  -- Sort in reverse order of version number
  pure $ sortBy (\x, y => compare (snd y) (snd x)) allFiles

||| The package of the given name, at the highest version within the bounds
||| that is installed, with the directory it is in: what the build records
||| of a package it adds.
export
findPkgDir :
    Ref Ctxt Defs =>
    String ->
    PkgVersionBounds ->
    Core (Maybe PackageDir)
findPkgDir p bounds = do
  defs <- get Ctxt
  [] <- findPkgDirs p bounds
    | ((dir, version) :: _) => pure (Just (MkPackageDir p version dir))

  -- From what remains, pick the one with the highest version number.
  -- If there's none, report it
  -- (TODO: Can't do this quite yet due to idris2 build system...)
  if defs.options.session.ignoreMissingPkg
     then pure Nothing
     else throw (CantFindPackage (p ++ " (" ++ show bounds ++ ")"))

||| Attempt to find and add a package with the given name and bounds
||| in one of the known package paths.
export
addPkgDir : {auto c : Ref Ctxt Defs} ->
            String -> PkgVersionBounds -> Core ()
addPkgDir p bounds = do
    Just pkg <- findPkgDir p bounds
        | Nothing => pure ()
    addPackageDir pkg

--------------------------------------------------------------------------------
--          Processing Options
--------------------------------------------------------------------------------

||| A package's options, each set in the session before its modules are
||| checked.
export
preOptions : {auto c : Ref Ctxt Defs} -> List CLOpt -> Core ()
preOptions [] = pure ()
preOptions (NoPrelude :: opts)
    = do setSession ({ noprelude := True } !getSession)
         preOptions opts
preOptions (PkgPath p :: opts)
    = do addPkgDir p anyBounds
         preOptions opts
preOptions (SourceDir d :: opts)
    = do setSourceDir (Just d)
         preOptions opts
preOptions (BuildDir d :: opts)
    = do setBuildDir d
         preOptions opts
preOptions (OutputDir d :: opts)
    = do setOutputDir (Just d)
         preOptions opts
preOptions (Timing tm :: opts)
    = do setLogTimings (fromMaybe 10 tm)
         preOptions opts
preOptions (IgnoreMissingIPKG :: opts)
    = do setSession ({ ignoreMissingPkg := True } !getSession)
         preOptions opts
preOptions (Logging n :: opts)
    = do setSession ({ logEnabled := True,
                       logLevel $= insertLogLevel n } !getSession)
         preOptions opts
preOptions (WarningsAsErrors :: opts)
    = do updateSession ({ warningsAsErrors := True })
         preOptions opts
preOptions (IgnoreShadowingWarnings :: opts)
    = do updateSession ({ showShadowingWarning := False })
         preOptions opts
preOptions (Total :: opts)
    = do updateSession ({ totalReq := Total })
         preOptions opts
