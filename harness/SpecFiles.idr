-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The specification's generated files, as the tests of them see them:
||| specgen (compiler/spec, IdrisMLIR.Spec.Generator.Main) writes each
||| output and the one committed manifest, or checks that the committed ones
||| are what it would write. The manifest is the list of the outputs, so no
||| test lists them again: its first two lines are the specification's and
||| the generator's fingerprints, and every line after them an output's
||| fingerprint and its path from the root.
module SpecFiles

import Data.List
import Data.Maybe
import Data.String
import System.File

import Files
import Harness
import Serve

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Generator.Manifest

%default covering

||| The manifest's path from a tree's root, the generator's own.
export
specManifest : String
specManifest = pathText manifestPath

||| `spec_outputs ROOT`: the path of each output the manifest of the tree at
||| ROOT names, one a line, in the manifest's order.
export
specOutputs : (root : String) -> IO (List String)
specOutputs root = do
  text <- fromMaybe "" <$> readIfThere (root ++ "/" ++ specManifest)
  pure (mapMaybe output (drop 2 (lines text)))
  where
    hexDigit : Char -> Bool
    hexDigit c = isDigit c || (c >= 'a' && c <= 'f')

    output : String -> Maybe String
    output l = case span hexDigit (unpack l) of
      (_ :: _, ' ' :: path) => Just (pack path)
      _ => Nothing

||| Each step run only when the ones before it succeeded, as a shell's `&&`
||| runs them; the first failure's status, or success.
steps : List (IO Status) -> IO Status
steps [] = pure (Code 0)
steps (step :: rest) = do
  status <- step
  if succeeded status then steps rest else pure status

||| `spec_sources ROOT DEST`: the specification's sources of the tree at ROOT
||| copied to DEST/compiler/spec, without a build left in them.
export
specSources : Env -> (root, dest : String) -> IO Status
specSources e root dest = steps
  [ bounded e ["mkdir", "-p", dest ++ "/compiler"] ToCaller (Apart ToCaller)
  , bounded e ["cp", "-R", root ++ "/compiler/spec", dest ++ "/compiler/spec"] ToCaller (Apart ToCaller)
  , bounded e ["rm", "-rf", dest ++ "/compiler/spec/build"] ToCaller (Apart ToCaller) ]

||| `spec_tree ROOT DEST`: what specgen reads and writes of the tree at ROOT,
||| copied to DEST: the specification's sources, and every output and the
||| manifest at its path.
export
specTree : Env -> (root, dest : String) -> IO Status
specTree e root dest = do
  outputs <- specOutputs root
  steps (specSources e root dest :: concatMap copied (outputs ++ [specManifest]))
  where
    copied : String -> List (IO Status)
    copied path =
      [ bounded e ["mkdir", "-p", dirName (dest ++ "/" ++ path)] ToCaller (Apart ToCaller)
      , bounded e ["cp", root ++ "/" ++ path, dest ++ "/" ++ path] ToCaller (Apart ToCaller) ]

||| `spec_check SPECGEN ROOT`: `SPECGEN check ROOT`, which writes nothing;
||| its status, and the paths it names as differing from the
||| specification, from ROOT, one a line, in the work directory's
||| spec-named. Anything else it says is in spec-check.out.
export
specCheck : Env -> (specgen, root : String) -> IO Status
specCheck e specgen root = do
  let out = inWork e "spec-check.out"
  status <- bounded e [specgen, "check", root] (ToFile out) WithOutput
  said <- lines . fromMaybe "" <$> readIfThere out
  let differing = "specgen: differs from the specification: " ++ root ++ "/"
  let named = mapMaybe (\l => if isPrefixOf differing l then Just (pack (drop (length differing) (unpack l))) else Nothing) said
  ignore (writeFile (inWork e "spec-named") (concatMap (++ "\n") named))
  pure status

||| The paths as a transcript says them: the manifest by that name, an output
||| as `an output`, so a transcript holds no path of the generated tree,
||| which the specification's areas decide.
naming : List String -> String
naming [] = "nothing"
naming paths = joinBy " and " (map (\p => if p == specManifest then "the manifest" else "an output") paths)

||| `spec_named WHAT EXPECTED...`, after spec_check, whose status is STATUS:
||| one line: WHAT, that status, and whether the paths it named are exactly
||| EXPECTED (in any order); the paths otherwise, and what specgen said.
export
specNamed : (work, status, what : String) -> (expected : List String) -> IO ()
specNamed work status what expected = do
  got <- lines . fromMaybe "" <$> readIfThere (work ++ "/spec-named")
  if sort expected == sort got
     then putStrLn (what ++ ": exit " ++ status ++ ", naming " ++ naming expected)
     else do
       putStrLn (what ++ ": exit " ++ status ++ ", naming otherwise")
       showFiles [work ++ "/spec-check.out"]

||| `spec_written SPECGEN ROOT`: SPECGEN writes every output into a tree
||| that holds the specification of ROOT and none of its outputs, and each
||| file it writes is byte for byte the one ROOT holds; one line. A file
||| written that ROOT's manifest does not name, or one it names and SPECGEN
||| did not write, is said too.
export
specWritten : Env -> (specgen, root : String) -> IO ()
specWritten e specgen root = do
  let tree = inWork e "written"
  removed e tree
  copied <- specSources e root tree
  if not (succeeded copied) then tell e "written into an empty tree: the sources not copied" else do
    outputs <- specOutputs root
    let paths = outputs ++ [specManifest]
    for_ paths $ \p => made e (dirName (tree ++ "/" ++ p))
    wrote <- bounded e [specgen, "write", tree] (ToFile (inWork e "spec-write.out")) WithOutput
    if not (succeeded wrote)
       then do
         tell e "written into an empty tree: specgen write failed"
         showIn e [inWork e "spec-write.out"]
       else do
         faults <- concat <$> for paths (\p => do
           there <- exists (tree ++ "/" ++ p)
           if not there then pure ["  not written: " ++ p] else do
             same <- sameBytes e (root ++ "/" ++ p) (tree ++ "/" ++ p)
             pure (if same then [] else ["  not the committed bytes: " ++ p]))
         written <- filesUnder tree
         let lead = tree ++ "/"
         let relative = map (\f => if isPrefixOf lead f then pack (drop (length lead) (unpack f)) else f) written
         let unnamed = [ "  written, and named by no committed manifest: " ++ p
                       | p <- relative, not (isPrefixOf "compiler/spec/" p), p /= specManifest, not (elem p outputs) ]
         case faults ++ unnamed of
           [] => tell e "written into an empty tree: each file byte for byte the committed one"
           listed => do
             tell e "written into an empty tree: otherwise than committed"
             tellAll e listed
