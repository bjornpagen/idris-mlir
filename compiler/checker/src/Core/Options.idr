-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.Options

import Core.Core
import public Core.Options.Log
import Core.TT

import Libraries.Utils.Path
import Idris.Package.Types
import Idris.Syntax.Pragmas

import Data.List
import Data.Maybe
import Data.String

%default total

%prefix_record_projections off

||| A package the build added: its name and version, as its directory names
||| them (a directory may name no version), and the directory.
public export
record PackageDir where
  constructor MkPackageDir
  name : String
  version : Maybe PkgVersion
  dir : String

||| Where the search found a module's TTC: the build directory, a package
||| the build added, or a directory named for imports. What a reader of a
||| module's origin needs, recorded when the TTC is found, so no reader
||| takes a path apart to learn it.
public export
data Found = InBuild | InPackage PackageDir | InExtraDir String

||| A package the build added as a reader is told it: the package, at the
||| version its directory names, and the directory.
export
Show PackageDir where
  show p = p.name ++ maybe "" (\v => "-" ++ show v) p.version ++ " at " ++ show p.dir

%prefix_record_projections on

public export
record Dirs where
  constructor MkDirs
  working_dir : String
  source_dir : Maybe String -- source directory, relative to working directory
  build_dir : String -- build directory, relative to working directory
  depends_dir : String -- local dependencies directory, relative to working directory
  output_dir : Maybe String -- output directory, relative to working directory
  prefix_dir : String -- installation prefix, for finding data files (e.g. run time support)
  extra_dirs : List String -- places to look for import files
  package_search_paths : List Path -- paths at which to look for packages
  package_dirs : List PackageDir -- the packages the build added, at the versions it required
  lib_dirs : List String -- places to look for libraries (for code generation)
  data_dirs : List String -- places to look for data file

public export
record PairNames where
  constructor MkPairNs
  pairType : Name
  fstName : Name
  sndName : Name

public export
record RewriteNames where
  constructor MkRewriteNs
  equalType : Name
  rewriteName : Name

public export
record PrimNames where
  constructor MkPrimNs
  fromIntegerName : Maybe Name
  fromStringName : Maybe Name
  fromCharName : Maybe Name
  fromDoubleName : Maybe Name
  fromTTImpName : Maybe Name
  fromNameName : Maybe Name
  fromDeclsName : Maybe Name

export
primNamesToList : PrimNames -> List Name
primNamesToList (MkPrimNs i s c d t n dl) = catMaybes [i,s,c,d,t,n,dl]

-- Other options relevant to the current session (so not to be saved in a TTC)
public export
record ElabDirectives where
  constructor MkElabDirectives
  lazyActive : Bool
  unboundImplicits : Bool
  totality : TotalReq
  nfThreshold : Nat
  --
  -- produce traditional (prefix) record projections,
  -- in addition to postfix (dot) projections
  -- default: yes
  prefixRecordProjections : Bool

public export
record Session where
  constructor MkSessionOpts
  noprelude : Bool
  totalReq : TotalReq
  ignoreMissingPkg : Bool -- fail silently on missing packages. This is because
          -- while we're bootstrapping, we find modules by a different route
          -- but we still want to have the dependencies listed properly

  -- Troubleshooting
  logEnabled : Bool -- do we check logging flags at all? This is 'False' until
                    -- any logging is enabled.
  logLevel : LogLevels
  logTimings : Maybe Nat -- log level, higher means more details

  -- Warnings
  warningsAsErrors : Bool
  showShadowingWarning : Bool

public export
record PPrinter where
  constructor MkPPOpts
  showImplicits : Bool
  showMachineNames : Bool
  showFullEnv : Bool
  fullNamespace : Bool

public export
record Options where
  constructor MkOptions
  dirs : Dirs
  printing : PPrinter
  session : Session
  elabDirectives : ElabDirectives
  pairnames : Maybe PairNames
  rewritenames : Maybe RewriteNames
  primnames : PrimNames
  extensions : List LangExt

defaultDirs : Dirs
defaultDirs = MkDirs "." Nothing "build" "depends" Nothing
                     "/usr/local" ["."] [] [] [] []

defaultPPrint : PPrinter
defaultPPrint = MkPPOpts
    { showImplicits = False
    , showMachineNames = False
    , showFullEnv = True
    , fullNamespace = False
    }

export
defaultSession : Session
defaultSession = MkSessionOpts False CoveringOnly False False
                               defaultLogLevel Nothing False True

export
defaultElab : ElabDirectives
defaultElab = MkElabDirectives True True CoveringOnly 25 True

export
defaults : Core Options
defaults
    = pure $ MkOptions
        defaultDirs defaultPPrint defaultSession defaultElab Nothing Nothing
        (MkPrimNs Nothing Nothing Nothing Nothing Nothing Nothing Nothing) []

-- Reset the options which are set by source files
export
clearNames : Options -> Options
clearNames = { pairnames := Nothing,
               rewritenames := Nothing,
               primnames := MkPrimNs Nothing Nothing Nothing Nothing Nothing Nothing Nothing,
               extensions := []
             }

export
setPair : (pairType : Name) -> (fstn : Name) -> (sndn : Name) ->
          Options -> Options
setPair ty f s = { pairnames := Just (MkPairNs ty f s) }

export
setRewrite : (eq : Name) -> (rwlemma : Name) -> Options -> Options
setRewrite eq rw = { rewritenames := Just (MkRewriteNs eq rw) }

export
setFromInteger : Name -> Options -> Options
setFromInteger n = { primnames->fromIntegerName := Just n }

export
setFromString : Name -> Options -> Options
setFromString n = { primnames->fromStringName := Just n }

export
setFromChar : Name -> Options -> Options
setFromChar n = { primnames->fromCharName := Just n }

export
setFromDouble : Name -> Options -> Options
setFromDouble n = { primnames->fromDoubleName := Just n }

export
setFromTTImp : Name -> Options -> Options
setFromTTImp n = { primnames->fromTTImpName := Just n }

export
setFromName : Name -> Options -> Options
setFromName n = { primnames->fromNameName := Just n }

export
setFromDecls : Name -> Options -> Options
setFromDecls n = { primnames->fromDeclsName := Just n }

export
setExtension : LangExt -> Options -> Options
setExtension e = { extensions $= (e ::) }
