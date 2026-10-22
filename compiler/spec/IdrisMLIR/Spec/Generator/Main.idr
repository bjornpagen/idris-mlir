-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| specgen: writes the specification's outputs under a checkout's root, or
||| checks that the committed ones are what it would write. The one module
||| that does IO; what it writes is `generate`'s, a pure function. Both modes
||| fingerprint the specification's and the generator's sources, read in the
||| order the package lists its modules, and the manifest holds them:
|||   specgen write <root>   rewrites each output whose bytes differ, and the manifest;
|||   specgen check <root>   writes nothing, and fails naming each file that differs.
module IdrisMLIR.Spec.Generator.Main

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Generator.Manifest
import IdrisMLIR.Spec.Generator.Outputs

import Data.List
import Data.List1
import Data.String
import System
import System.File

%default total

||| A path under the root.
export
under : String -> Path -> String
under root p = root ++ "/" ++ pathText p

||| The package's modules, in its order: the words after `modules =` up to
||| the next field, split at commas. The package file is the one list of
||| the specification's sources, so no directory is listed.
export
modulesOf : String -> List String
modulesOf ipkg = go False (lines ipkg)
  where
    field : String -> Bool
    field l = isInfixOf "=" l && not (isPrefixOf " " l) && not (isPrefixOf "," l)
    names : String -> List String
    names l = filter (/= "") (map trim (forget (split (== ',') l)))
    go : Bool -> List String -> List String
    go _ [] = []
    go inside (l :: ls) =
      if isPrefixOf "modules" (trim l) && isInfixOf "=" l
        then names (snd (break (== '=') l) `minusFirst` 1) ++ go True ls
        else if inside && not (field l) then names l ++ go True ls else go False ls
      where
        minusFirst : String -> Nat -> String
        minusFirst s n = pack (drop n (unpack s))

||| A module's source file under the specification's directory.
export
sourceOf : String -> String -> String
sourceOf root m = root ++ "/compiler/spec/" ++ pack (map (\c => if c == '.' then '/' else c) (unpack m)) ++ ".idr"

||| Whether a module is the generator's.
export
generatorModule : String -> Bool
generatorModule = isPrefixOf "IdrisMLIR.Spec.Generator."

||| The text of a file, or nothing where there is none.
export
readText : String -> IO (Maybe String)
readText path = do
  got <- readFile path
  case got of
    Right t => pure (Just t)
    Left _ => pure Nothing

||| The sources of `ms` as one text, each module's name before its text.
export
sourcesText : String -> List String -> IO String
sourcesText root [] = pure ""
sourcesText root (m :: ms) = do
  t <- readText (sourceOf root m)
  rest <- sourcesText root ms
  pure (m ++ "\n" ++ fromMaybe "" t ++ "\n" ++ rest)

||| The manifest's text for the outputs, fingerprinting the sources.
export
manifestText : String -> List (Path, String) -> IO (Either String String)
manifestText root outs = do
  Just ipkg <- readText (root ++ "/compiler/spec/spec.ipkg")
    | Nothing => pure (Left "no compiler/spec/spec.ipkg under the root")
  let ms = modulesOf ipkg
  spec <- sourcesText root (filter (not . generatorModule) ms)
  gen <- sourcesText root (filter generatorModule ms)
  pure (Right (manifest (fingerprint (ipkg ++ spec)) (fingerprint gen) outs))

||| Writes `text` at `path` unless the file already holds exactly it.
export
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

export
main : IO ()
main = do
  args <- getArgs
  case args of
    [_, mode, root] => do
      Right m <- manifestText root generate
        | Left e => do
            putStrLn ("specgen: " ++ e)
            exitWith (ExitFailure 1)
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
              report (map (\p => "specgen: differs from the specification: " ++ p) ps)
              exitWith (ExitFailure 1)
        _ => do
          putStrLn "specgen: write <root> | check <root>"
          exitWith (ExitFailure 2)
    _ => do
      putStrLn "specgen: write <root> | check <root>"
      exitWith (ExitFailure 2)
