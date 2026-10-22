-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.Directory

import Core.Binary
import Core.Context.Log
import Core.Options

import Idris.Version

import Parser.Unlit

import Libraries.Data.Version
import Libraries.Utils.Path

import Data.SnocList

import System.Directory

%default total

------------------------------------------------------------------------
-- Package directories

export
pkgGlobalDirectory : {auto c : Ref Ctxt Defs} -> Core String
pkgGlobalDirectory =
  do d <- getDirs
     pure (prefix_dir d </> "idris2-" ++ showVersion False version)

export
pkgLocalDirectory : {auto c : Ref Ctxt Defs} -> Core String
pkgLocalDirectory =
  do d <- getDirs
     Just srcdir <- coreLift currentDir
       | Nothing => throw (InternalError "Can't get current directory")
     pure $ srcdir </> depends_dir d

------------------------------------------------------------------------
-- TTC directories

export
ttcBuildDirectory : {auto c : Ref Ctxt Defs} -> Core String
ttcBuildDirectory =
  do d <- getDirs
     pure (build_dir d </> "ttc" </> show ttcVersion)

export
libInstallDirectory : {auto c : Ref Ctxt Defs} -> String -> Core String
libInstallDirectory lib =
  do gbdir <- pkgGlobalDirectory
     pure (gbdir </> lib)

export
ttcInstallDirectory : {auto c : Ref Ctxt Defs} -> String -> Core String
ttcInstallDirectory lib =
  do libDir <- libInstallDirectory lib
     pure (libDir </> show ttcVersion)

export
srcInstallDirectory : {auto c : Ref Ctxt Defs} -> String -> Core String
srcInstallDirectory = libInstallDirectory

-- The directories a TTC is searched for in after the build directory, each
-- with what finding one there says of it.
extraSearchDirectories : {auto c : Ref Ctxt Defs} -> Core (List (String, Found))
extraSearchDirectories =
  do d <- getDirs
     pure (map (\x => (x </> show ttcVersion, InExtraDir x)) (extra_dirs d)
           ++ map (\p => (p.dir </> show ttcVersion, InPackage p)) (package_dirs d))

------------------------------------------------------------------------

public export
data IdrSrcExt = E_idr | E_lidr | E_yaff | E_org | E_md

public export
Eq IdrSrcExt where
  E_idr  == E_idr  = True
  E_lidr == E_lidr = True
  E_yaff == E_yaff = True
  E_org  == E_org  = True
  E_md   == E_md   = True
  _      == _      = False

public export
Show IdrSrcExt where
  show E_idr  = "idr"
  show E_lidr = "lidr"
  show E_yaff = "yaff"
  show E_org  = "org"
  show E_md   = "md"

||| This does not include the complete set of literate extensions as supported by Idris.
public export
listOfExtensions : List IdrSrcExt
listOfExtensions = [E_idr, E_lidr, E_yaff, E_org, E_md]

||| List of valid extensions in Idris as strings.
|||
||| Extensions have a leading "." separator *and* may include multiple extensions to support literate mode extensions for the form ".org.idr".
|||
public export
listOfExtensionsStr : List String
listOfExtensionsStr = listOfExtensionsLiterate ++ [".yaff", ".idr"]

||| Applies the following properties of relative directory construction:
||| X / .  = X
||| X / .. = .    where X =/= ..
collapseSpecialDirs : SnocList Body -> SnocList Body
collapseSpecialDirs path@(xs :< ParentDir) =
  case collapseSpecialDirs xs of
    xs :< CurDir   => xs
    xs :< Normal _ => xs
    _ => path
collapseSpecialDirs (xs :< CurDir) = collapseSpecialDirs xs
collapseSpecialDirs (xs :< Normal n) = collapseSpecialDirs xs :< Normal n
collapseSpecialDirs [<] = [<]

||| Given a path, removes trailing separators and current directory identifiers, '.'.
cleanPath : String -> String
cleanPath = show . the (Path -> Path) { hasTrailSep := False, body $= cast . collapseSpecialDirs . cast } . parse

||| Return the basename and extension used *if* given filename is a valid idris filename.
|||
||| Extensions are returned with a leading "." separator.
export
splitIdrisFileName : String -> Maybe (String, String)
splitIdrisFileName fname
    = hasLitFileExt fname <|> isPureCode

  where
    isPureCode : Maybe (String, String)
    isPureCode
      = let (bname, ext) = splitFileName fname in
        do guard (ext == "idr")
           pure (bname, ".idr")


-- Return the name of the first file available in the list
-- Used in LSP.
export
firstAvailable : {auto c : Ref Ctxt Defs} ->
                 List String -> Core (Maybe String)
firstAvailable [] = pure Nothing
firstAvailable (f :: fs)
    = do log "import.file" 30 $ "Attempting to read " ++ f
         Right ok <- coreLift $ openFile f Read
               | Left err => firstAvailable fs
         coreLift $ closeFile ok
         pure (Just f)

export
covering
findDataFile : {auto c : Ref Ctxt Defs} ->
               String -> Core String
findDataFile fname
    = do d <- getDirs
         let fs = map (\p => cleanPath $ p </> fname) (data_dirs d)
         Just f <- firstAvailable fs
            | Nothing => throw (InternalError ("Can't find data file " ++ fname ++
                                               " in any of " ++ show fs))
         pure f

export
covering
readDataFile : {auto c : Ref Ctxt Defs} ->
               String -> Core String
readDataFile fname
    = do f <- findDataFile fname
         Right d <- coreLift $ readFile f
            | Left err => throw (FileErr f err)
         pure d

%prefix_record_projections off

||| A module's TTC as the search found it: its path, and where it was.
public export
record CheckedFile where
  constructor MkCheckedFile
  path : String
  foundIn : Found

%prefix_record_projections on

-- Given a namespace, return the checked module, looking first in the build
-- directory then in the extra directories and the packages
export
nsToPath : {auto c : Ref Ctxt Defs} ->
           FC -> ModuleIdent -> Core (Either Error CheckedFile)
nsToPath loc ns
    = do bdir <- ttcBuildDirectory
         ttcs <- extraSearchDirectories
         let fnameBase = ModuleIdent.toPath ns
         Just f <- firstFound (map (\(p, w) => (cleanPath $ p </> fnameBase <.> "ttc", w))
                                   ((bdir, InBuild) :: ttcs))
            | Nothing => pure (Left (ModuleNotFound loc ns))
         pure (Right f)
  where
    firstFound : List (String, Found) -> Core (Maybe CheckedFile)
    firstFound [] = pure Nothing
    firstFound ((f, w) :: fs)
        = do Just _ <- firstAvailable [f]
               | Nothing => firstFound fs
             pure (Just (MkCheckedFile f w))

-- Given a namespace, return the path to the source module relative
-- to the working directory, if the module exists.
export
nsToSource : {auto c : Ref Ctxt Defs} ->
             FC -> ModuleIdent -> Core String
nsToSource loc ns
    = do d <- getDirs
         let fnameOrig = ModuleIdent.toPath ns
         let fnameBase = cleanPath $ maybe fnameOrig (\srcdir => srcdir </> fnameOrig) (source_dir d)
         let fs = map ((fnameBase ++)) listOfExtensionsStr
         Just f <- firstAvailable fs
            | Nothing => throw (ModuleNotFound loc ns)
         pure f


-- Given a filename in the working directory + source directory, return the correct
-- namespace for it. Its parts are a file's path, so they become identifiers
-- here, where the path enters the compiler.
export
mbPathToNS : {auto c : Ref Ctxt Defs} ->
             String -> Maybe String -> String -> Core (Maybe ModuleIdent)
mbPathToNS wdir sdir fname =
  let
    sdir = fromMaybe "" sdir
    base = if isAbsolute fname then wdir </> sdir else sdir
  in
    case (Path.dropBase `on` cleanPath) base fname of
         Nothing => pure Nothing
         Just rel => do parts <- traverse intern (splitPath (Path.dropExtensions rel))
                        pure (Just (nsAsModuleIdent (nsOf parts)))

export
corePathToNS : {auto c : Ref Ctxt Defs} ->
               String -> Maybe String -> String -> Core ModuleIdent
corePathToNS wdir sdir fname = do
  let err = UserError $
          "Source file "
       ++ show (cleanPath fname)
       ++ " is not in the source directory "
       ++ show (cleanPath (wdir </> fromMaybe "" sdir))
  Just ns <- mbPathToNS wdir sdir fname
    | Nothing => throw err
  pure ns

export
ctxtPathToNS : {auto c : Ref Ctxt Defs} -> String -> Core ModuleIdent
ctxtPathToNS fname = do
  defs <- get Ctxt
  let wdir = defs.options.dirs.working_dir
  let sdir = defs.options.dirs.source_dir
  corePathToNS wdir sdir fname

dirExists : String -> IO Bool
dirExists dir = do Right d <- openDir dir
                       | Left _ => pure False
                   closeDir d
                   pure True

-- Create a directory and each one it is in that does not exist. A
-- directory that exists is done at once. Otherwise each prefix of the
-- path's body is created, outermost first, and one that exists already
-- (`FileExists`) is passed: creating asks nothing of a directory but that
-- it can be searched, where testing that one exists would need it to be
-- readable. The walk is over the body.
export
mkdirAll : String -> IO (Either FileError ())
mkdirAll dir = if !(dirExists dir) then pure (Right ()) else createFrom [] path.body
  where
    path : Path
    path = parse dir

    createFrom : List Body -> List Body -> IO (Either FileError ())
    createFrom done [] = pure (Right ())
    createFrom done (b :: bs)
        = do let here = done ++ [b]
             Right () <- createDir (show (MkPath path.hasRoot here False))
               | Left FileExists => createFrom here bs
               | Left err => pure (Left err)
             createFrom here bs

-- Given a namespace (i.e. a module name), make the build directory for the
-- corresponding ttc file
export
covering
makeBuildDirectory : {auto c : Ref Ctxt Defs} ->
                     ModuleIdent -> Core ()
makeBuildDirectory ns
    = do bdir <- ttcBuildDirectory
         let ns = reverse $ fromMaybe [] $ tail' $ unsafeUnfoldModuleIdent ns -- first item is file name
         let ndir = joinPath (map (.text) ns)
         Right _ <- coreLift $ mkdirAll (bdir </> ndir)
            | Left err => throw (FileErr (bdir </> ndir) err)
         pure ()

export
covering
ensureDirectoryExists : String -> Core ()
ensureDirectoryExists dir
    = do Right _ <- coreLift $ mkdirAll dir
            | Left err => throw (FileErr dir err)
         pure ()

-- Given a source file, return the name of the ttc file to generate
export
getTTCFileName : {auto c : Ref Ctxt Defs} ->
                 String -> String -> Core String
getTTCFileName inp ext
    = do -- Get its namespace from the file relative to the working directory
         -- and generate the ttc file from that
         ns <- ctxtPathToNS inp
         let fname = ModuleIdent.toPath ns <.> ext
         bdir <- ttcBuildDirectory
         pure $ bdir </> fname

-- Given a source file, return the name of the corresponding object file.
-- As above, but without the build directory
export
getObjFileName : {auto c : Ref Ctxt Defs} ->
                 String -> String -> Core String
getObjFileName inp ext
    = do -- Get its namespace from the file relative to the working directory
         -- and generate the ttc file from that
         ns <- ctxtPathToNS inp
         let fname = ModuleIdent.toPath ns <.> ext
         pure $ fname

-- Given a root executable name, return the name in the build directory
export
getExecFileName : {auto c : Ref Ctxt Defs} -> String -> Core String
getExecFileName efile
    = do d <- getDirs
         pure $ build_dir d </> efile

-- Find an ipkg file in any of the directories above this one
-- returns the directory, the ipkg file name, and the directories we've
-- gone up
export
covering
findIpkgFile : IO (Maybe (String, String, String))
findIpkgFile
    = do Just dir <- currentDir
              | Nothing => pure Nothing
         res <- findIpkgFile' dir ""
         pure res
  where
    covering
    findIpkgFile' : String -> String -> IO (Maybe (String, String, String))
    findIpkgFile' dir up
        = do Right files <- listDir dir
                 | Left err => pure Nothing
             let Just f = find (\f => extension f == Just "ipkg") files
                 | Nothing => case splitParent dir of
                                   Just (parent, end) => findIpkgFile' parent (end </> up)
                                   Nothing => pure Nothing
             pure $ Just (dir, f, up)
