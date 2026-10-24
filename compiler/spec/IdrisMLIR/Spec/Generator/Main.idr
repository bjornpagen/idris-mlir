-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| specgen: writes the specification's outputs under a checkout's root, or
||| checks that the committed ones are what it would write. The one module
||| that does IO; what it writes is `generate`'s, a pure function. Both modes
||| fingerprint the specification's printed value, every output in order,
||| so an edit that prints nothing new changes nothing, and the generator's
||| sources, read in the order the specification lists them
||| (`generatorSources`); the manifest holds both. Both first fail, writing
||| nothing, naming each thing the generator refuses and each module under
||| the specification's directory the package does not name, since Idris
||| installs only the modules a package names:
|||   specgen write <root>   rewrites each output whose bytes differ, and the manifest;
|||   specgen check <root>   writes nothing, and fails naming each file that differs.
module IdrisMLIR.Spec.Generator.Main

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Generator.Manifest
import IdrisMLIR.Spec.Generator.Outputs
import IdrisMLIR.Spec.Generator.Package

import Data.List
import Data.List1
import Data.Maybe
import Data.String
import System
import System.Directory
import System.File

%default total

||| A path under the root.
export
under : String -> Path -> String
under root p = root ++ "/" ++ pathText p

-- Covering, not total: a read runs to the file's end, which a file that
-- never ends never reaches; every reader below inherits it.
||| The text of a file, or nothing where there is none.
export
covering
readText : String -> IO (Maybe String)
readText path = do
  got <- readFile path
  case got of
    Right t => pure (Just t)
    Left _ => pure Nothing

||| The sources at `ps` as one text, each source's path before its text.
export
covering
sourcesText : String -> List Path -> IO String
sourcesText root [] = pure ""
sourcesText root (p :: ps) = do
  t <- readText (under root p)
  rest <- sourcesText root ps
  pure (pathText p ++ "\n" ++ fromMaybe "" t ++ "\n" ++ rest)

||| The specification's printed value: every output, each its path before
||| its text, in the outputs' order.
export
printedValue : List (Path, String) -> String
printedValue outs = concat (map (\(p, t) => pathText p ++ "\n" ++ t) outs)

||| The manifest's text for the outputs, fingerprinting the specification's
||| printed value and the generator's sources.
export
covering
manifestText : String -> List (Path, String) -> IO String
manifestText root outs = do
  gen <- sourcesText root (forget generatorSources)
  pure (manifest (fingerprint (printedValue outs)) (fingerprint gen) outs)

||| Writes `text` at `path` unless the file already holds exactly it.
export
covering
writeChanged : String -> String -> IO (Either String ())
writeChanged path text = do
  old <- readText path
  if old == Just text
    then pure (Right ())
    else do
      done <- writeFile path text
      case done of
        Right () => pure (Right ())
        Left _ => pure (Left ("cannot write " ++ path))

export
covering
writeAll : List (String, String) -> IO (List String)
writeAll [] = pure []
writeAll ((path, text) :: rest) = do
  r <- writeChanged path text
  more <- writeAll rest
  case r of
    Right () => pure more
    Left e => pure (e :: more)

||| The paths whose committed text differs from what would be written.
export
covering
differing : List (String, String) -> IO (List String)
differing [] = pure []
differing ((path, text) :: rest) = do
  old <- readText path
  more <- differing rest
  pure (if old == Just text then more else path :: more)

||| Every file with its text, the manifest last.
export
files : String -> String -> List (String, String)
files root m = map (\(p, t) => (under root p, t)) generate ++ [(under root manifestPath, m)]

export
report : List String -> IO ()
report [] = pure ()
report (l :: ls) = do
  putStrLn l
  report ls

||| A directory under the root, as its parts.
dirText : String -> List String -> String
dirText root dir = concat (intersperse "/" (root :: dir))

-- Covering, not total: a walk follows each directory it lists, which a
-- link back up the tree would never let end.
||| Each `.idr` file under the directory whose parts under the root are
||| `dir`, as its path under the root, in the order of its names; or the
||| first directory that cannot be listed. A hidden name is passed over:
||| no module's name starts with a dot, so an editor's file beside a module
||| is none.
export
covering
sourcesUnder : (root : String) -> (dir : List String) -> IO (Either String (List Path))
sourcesUnder root dir = do
  Right names <- listDir (dirText root dir)
    | Left _ => pure (Left (concat (intersperse "/" dir)))
  found <- traverse
    (\n => do
       Right d <- openDir (dirText root (dir ++ [n]))
         | Left _ => pure (Right (if Data.String.isSuffixOf ".idr" n then [lappend dir (singleton n)] else []))
       closeDir d
       sourcesUnder root (dir ++ [n]))
    (sort (filter (not . Data.String.isPrefixOf ".") names))
  pure (concat <$> sequence found)

||| Each module under the specification's directory the package does not
||| name, said for the one who wrote it; or that the directory cannot be
||| listed, which leaves its modules unchecked. The directory is the
||| package file's, which is its source directory too (`sourcedir` is
||| "."), so every module the package could name is a file under it.
export
covering
unnamedModules : String -> IO (List String)
unnamedModules root = do
  found <- sourcesUnder root (init packagePath)
  pure $ case found of
    Left dir => [dir ++ ": cannot be listed, so no module under it is checked against the package"]
    Right paths => map unnamed (filter (\p => not (elem p named)) paths)
  where
    named : List Path
    named = map moduleSource (forget packageModules)

    unnamed : Path -> String
    unnamed p = pathText p ++ ": a module the package does not name (IdrisMLIR.Spec.Generator.Package lists them)"

||| Fails, naming each thing the generator refuses, where there is any.
export
refuse : List String -> IO ()
refuse [] = pure ()
refuse rs = do
  report (map ("specgen: refused: " ++) rs)
  exitWith (ExitFailure 1)

export
covering
main : IO ()
main = do
  args <- getArgs
  case args of
    [_, mode, root] => do
      unnamed <- unnamedModules root
      refuse (refusals ++ unnamed)
      m <- manifestText root generate
      case mode of
        "write" => do
          errors <- writeAll (files root m)
          case errors of
            [] => pure ()
            es => do
              report (map ("specgen: " ++) es)
              exitWith (ExitFailure 1)
        "check" => do
          stale <- differing (files root m)
          case stale of
            [] => pure ()
            ps => do
              report (map differsLine ps)
              exitWith (ExitFailure 1)
        _ => do
          putStrLn "specgen: write <root> | check <root>"
          exitWith (ExitFailure 2)
    _ => do
      putStrLn "specgen: write <root> | check <root>"
      exitWith (ExitFailure 2)
