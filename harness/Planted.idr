-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The repository's rules (the `check` suite), each shown to catch what it
||| forbids and to pass what it allows, on files planted beside it; and a
||| frontend built with a module of a test's planted in place of the
||| repository's.
|||
||| A rule's check is a shell function of a tree's root, CHECK ROOT, that
||| prints its findings in the tree at ROOT, one per line, each starting
||| with the path of the file it is in, from ROOT, and a colon (`path:line:
||| what` or `path: what`), and nothing when the tree keeps the rule. The
||| test runs it on the repository and, through `planted`, on its own two
||| planted trees, each laid out as the repository is (the same paths from
||| its root, so the check walks it unchanged):
|||
|||     witness/    files that break the rule, one per way of breaking it
|||                 the rule names: each must be found
|||     near-miss/  files as close to breaking it as the rule allows (the
|||                 allowed spelling, the exception, the word in a comment):
|||                 none may be found
|||
||| So a rule that finds nothing fails on its witness, and one that finds
||| too much on its near miss. A check that walks the whole repository
||| leaves out every test's witness/ and near-miss/, and a planted file
||| carries the licence line its kind needs (tools/licenses.sh), as every
||| file of the tree does.
module Planted

import Data.List
import Data.Maybe
import Data.String
import System.File

import Files
import Harness
import Serve

%default covering

||| The files of a planted tree, by their paths from its root, sorted.
plantedFiles : String -> IO (List String)
plantedFiles tree = do
  files <- filesUnder tree
  let lead = tree ++ "/"
  pure (sort (map (\f => if isPrefixOf lead f then pack (drop (length lead) (unpack f)) else f) files))

||| A finding names a file when it starts with the file's path and a colon,
||| after any leading spaces.
names : List String -> String -> Bool
names findings file = any (\f => isPrefixOf (file ++ ":") (ltrim f)) findings

||| The rule's check, the run script's function CHECK, on the tree of the
||| test's directory `dir`, its findings in the work directory's
||| planted.<tree> and what it said on standard error in planted.err.
checked : Env -> (check, dir, tree : String) -> IO (List String)
checked e check dir tree = do
  let found = inWork e ("planted." ++ tree)
  _ <- run e.session (MkCommand (RuleCheck check) [dir ++ "/" ++ tree] e.tools.here NoInput
                                (ToFile found) (Apart (ToFile (inWork e "planted.err"))) [])
  lines . fromMaybe "" <$> readIfThere found

||| `planted CHECK DIR`: CHECK run on witness/ and near-miss/ of DIR, the
||| test's own directory, which the glue passes (`$here`, where one.sh
||| starts the script), since the script may have moved since, as one whose
||| rule walks the repository from its root does. One line for each: every
||| file of witness/ is named by a finding, and near-miss/ has none. A tree
||| missing is said, and fails.
export
planted : Env -> (check, dir : String) -> IO ()
planted e check dir = do
  missing <- filterM' (\t => not <$> isDirectory (dir ++ "/" ++ t)) ["witness", "near-miss"]
  case missing of
    (tree :: _) => tell e ("planted: no " ++ tree ++ "/ beside the check")
    [] => do
      findings <- checked e check dir "witness"
      files <- plantedFiles (dir ++ "/witness")
      case (files, filter (not . names findings) files) of
        ([], _) => tell e "witness: nothing planted"
        (_, []) => tell e "witness: each planted file is found"
        (_, missed) => do
          tell e "witness: planted files the check does not find:"
          tellAll e (map ("  " ++) missed)
          showIn e [inWork e "planted.err"]
      near <- checked e check dir "near-miss"
      nearFiles <- plantedFiles (dir ++ "/near-miss")
      case (nearFiles, near) of
        ([], _) => tell e "near miss: nothing planted"
        (_, []) => tell e "near miss: nothing found"
        _ => do
          tell e "near miss: found, though it keeps the rule:"
          showIn e [inWork e "planted.near-miss"]
  where
    filterM' : (String -> IO Bool) -> List String -> IO (List String)
    filterM' p [] = pure []
    filterM' p (x :: xs) = do
      keep <- p x
      if keep then (x ::) <$> filterM' p xs else filterM' p xs

||| `planted_frontend MODULE FILE`: a frontend built from the repository's
||| sources, compiler/src and its package, with MODULE (a path under
||| compiler/src) planted from FILE, as the shipped one is built: by the
||| pinned Idris against the checker, after a copy of the build's TTCs, so
||| only what MODULE reaches is built again. idris-mlir runs the frontend
||| beside its own executable, so the planted one runs beside a link of the
||| same idris-mlir: a hard link, whose path is its own, or a copy where the
||| work directory is on another file system. The frontend's path and that
||| idris-mlir's are written, a line each, to the work directory's
||| planted-frontend, for the glue to hand the script; it says so, or that
||| it is not built, with the build's output; status 0 when built.
export
plantedFrontend : Env -> (module', file : String) -> IO Nat
plantedFrontend e module' file = do
  let dir = inWork e "frontend"
  let src = e.tools.root ++ "/compiler/src"
  if not !(exists (src ++ "/" ++ module'))
     then do
       tell e ("the planted frontend: compiler/src/" ++ module' ++ " is no module of the frontend")
       pure 1
     else do
       made e dir
       copiedSources <- allSucceed
         [ bounded e ["cp", "-R", src, dir ++ "/src"] ToCaller (Apart ToCaller)
         , bounded e ["rm", "-rf", dir ++ "/src/build"] ToCaller (Apart ToCaller)
         , bounded e ["cp", e.tools.root ++ "/compiler/idris-mlir.ipkg", dir ++ "/"] ToCaller (Apart ToCaller) ]
       ttc <- isDirectory (e.tools.root ++ "/compiler/build/ttc")
       copiedTtc <- if not ttc then pure True else allSucceed
         [ bounded e ["mkdir", "-p", dir ++ "/build"] ToCaller (Apart ToCaller)
         , bounded e ["cp", "-R", e.tools.root ++ "/compiler/build/ttc", dir ++ "/build/ttc"] ToCaller (Apart ToCaller) ]
       placedModule <- if copiedSources && copiedTtc
                     then succeeded <$> bounded e ["cp", file, dir ++ "/src/" ++ module'] ToCaller (Apart ToCaller)
                     else pure False
       if not placedModule then pure 1 else do
         let packagesFile = sessionDir e.session ++ "/host-packages"
         _ <- boundedWith e [("IDRIS2_PREFIX", e.tools.hostPrefix)] e.tools.here [e.tools.idris2, "--libdir"]
                          (ToFile packagesFile) (Apart ToCaller)
         hostPackages <- trailing . fromMaybe "" <$> readIfThere packagesFile
         let front = dir ++ "/build/exec/idris-mlir-front"
         builtStatus <- pinnedIdrisIn e [("IDRIS2_PACKAGE_PATH", hostPackages)] dir ["--build", "idris-mlir.ipkg"]
                                      (ToFile (inWork e "frontend.out")) WithOutput
         runnable <- succeeded <$> bounded e ["test", "-x", front] (ToFile "/dev/null") (Apart (ToFile "/dev/null"))
         if not (succeeded builtStatus && runnable)
            then do
              tell e "the planted frontend: not built"
              showIn e [inWork e "frontend.out"]
              pure 1
            else do
              let bin = inWork e "bin"
              let compiler = bin ++ "/idris-mlir"
              linked <- allSucceed
                [ bounded e ["mkdir", "-p", bin] ToCaller (Apart ToCaller)
                , bounded e ["ln", "-s", front, bin ++ "/idris-mlir-front"] ToCaller (Apart ToCaller) ]
              hard <- succeeded <$> bounded e ["ln", e.tools.idrisMlir, compiler] (ToFile "/dev/null") (Apart (ToFile "/dev/null"))
              placed <- if hard then pure True
                        else succeeded <$> bounded e ["cp", e.tools.idrisMlir, compiler] ToCaller (Apart ToCaller)
              if not (linked && placed) then pure 1 else do
                ignore (writeFile (inWork e "planted-frontend") (unlines [front, compiler]))
                tell e "the planted frontend: built"
                pure 0
  where
    -- Each step runs only when the ones before it succeeded, as a shell's
    -- `&&` runs them.
    allSucceed : List (IO Status) -> IO Bool
    allSucceed [] = pure True
    allSucceed (step :: rest) = do
      status <- step
      if succeeded status then allSucceed rest else pure False
