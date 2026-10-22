-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What every check of the harness stands on: the tools and places a run
||| script names, read once from its environment; a test's output; the
||| files a fixture holds and a build leaves; and the tools started through
||| the glue (Serve.idr): a command bounded, a program compiled with the
||| compiler under test and its time recorded, a program linked, a C++
||| program built over the pinned MLIR.
module Harness

import Data.List
import Data.List1
import Data.Maybe
import Data.String
import System
import System.Clock
import System.Directory
import System.File

import Files
import Serve

%default covering

------------------------------------------------------------------------------
-- The tools and places
------------------------------------------------------------------------------

||| The tools and places of a run script, each passed by the glue under its
||| shell name (`serve`, harness/lib/harness.sh), as the script holds it
||| when it calls: a test may move its work directory or name another tool
||| before it does.
public export
record Tools where
  constructor MkTools
  root : String
  work : String
  here : String
  llvmPrefix : String
  llvmBin : String
  pinnedCc : String
  idrisMlir : String
  idrisMlirOpt : String
  idris2 : String
  idrisPrefix : String
  compileSh : String
  checkedRuntime : String
  devPrefix : String
  runtests : String
  parameter : String

||| A variable the glue passes, or the runner's death naming it: the glue
||| passes every one, so a missing one is a harness that does not match.
given : String -> IO String
given name = do
  Just value <- getEnv name
    | Nothing => die ("runtests: " ++ name ++ " is not passed; run the check through harness/lib/harness.sh")
  pure value

||| The tools and places, read once.
export
toolsOf : IO Tools
toolsOf = do
  Just here <- currentDir
    | Nothing => die "runtests: no current directory"
  [| MkTools (given "root") (given "work") (pure here) (given "llvm_prefix") (given "llvm_bin")
             (given "pinned_cc") (given "idris_mlir") (given "idris_mlir_opt") (given "idris2")
             (given "idris_prefix") (given "compile_sh") (given "checked_runtime") (given "dev_prefix")
             (given "runtests") (fromMaybe "" <$> getEnv "parameter") |]

||| A check's place to run: the tools, the session with the glue that
||| starts them, and what each line of its output starts with (nothing, or
||| the run it is part of, as a neighbour's `near: `).
public export
record Env where
  constructor MkEnv
  tools : Tools
  session : Session
  lead : String

||| The same check run inside another: in its own work directory, its
||| lines starting with `prefix` too.
export
nested : Env -> (work : String) -> (more : String) -> Env
nested e work more = { tools.work := work, lead $= (++ more) } e

||| A path in the work directory.
export
inWork : Env -> String -> String
inWork e name = e.tools.work ++ "/" ++ name

------------------------------------------------------------------------------
-- The test's output
------------------------------------------------------------------------------

||| Whether a check holds.
public export
data Holds = Held | Broken

export
both : Holds -> Holds -> Holds
both Held Held = Held
both _ _ = Broken

export
allHold : List Holds -> Holds
allHold = foldl both Held

||| One line of the test's output, printed as is.
export
say : String -> IO ()
say = putStrLn

||| The last character of a line read, when it is the line's end.
chomp : String -> String
chomp l = if isSuffixOf "\n" l then pack (init' (unpack l)) else l
  where
    init' : List Char -> List Char
    init' [] = []
    init' [_] = []
    init' (c :: cs) = c :: init' cs

||| The first `n` lines of the files, in order, a file that is not there
||| read as empty.
export
firstLines : Nat -> List String -> IO (List String)
firstLines Z _ = pure []
firstLines _ [] = pure []
firstLines n (path :: rest) = do
  Right h <- openFile path Read
    | Left _ => firstLines n rest
  ls <- go h n [<]
  closeFile h
  more <- firstLines (minus n (length ls)) rest
  pure (ls ++ more)
  where
    go : File -> Nat -> SnocList String -> IO (List String)
    go h Z acc = pure (acc <>> [])
    go h (S k) acc = do
      Right l <- fGetLine h
        | Left _ => pure (acc <>> [])
      if l == "" then pure (acc <>> []) else go h k (acc :< chomp l)

||| Lines a failure is about, indented as the files they come from are.
export
indented : List String -> List String
indented = map ("  | " ++)

||| The files a failure is about, their first forty lines, indented.
export
showFiles : List String -> IO ()
showFiles paths = firstLines 40 paths >>= traverse_ say . indented

||| One line of a check's output.
export
tell : Env -> String -> IO ()
tell e line = putStrLn (e.lead ++ line)

export
tellAll : Env -> List String -> IO ()
tellAll e = traverse_ (tell e)

||| The files a failure is about, in a check's output.
export
showIn : Env -> List String -> IO ()
showIn e paths = firstLines 40 paths >>= tellAll e . indented

||| Whether a file is there and holds at least one byte.
export
nonEmpty : String -> IO Bool
nonEmpty path = do
  Right h <- openFile path Read
    | Left _ => pure False
  size <- fileSize h
  closeFile h
  pure (either (const False) (> 0) size)

||| `empty NAME FILE`: one line saying whether FILE is empty, and what it
||| holds when it is not.
export
emptiness : (name : String) -> (path : String) -> IO ()
emptiness name path = do
  filled <- nonEmpty path
  if filled
     then do say (name ++ ": not empty"); showFiles [path]
     else say (name ++ ": empty")

------------------------------------------------------------------------------
-- Files and directories
------------------------------------------------------------------------------

export
isDirectory : String -> IO Bool
isDirectory path = do
  Right d <- openDir path
    | Left _ => pure False
  closeDir d
  pure True

||| The names in a directory, sorted, hidden ones among them, but `.`, `..`
||| and a name that starts with `..`, which no shell glob of the harness
||| ever named.
export
namesIn : String -> IO (List String)
namesIn dir = do
  Right names <- listDir dir
    | Left _ => pure []
  pure (sort (filter (not . isPrefixOf "..") (filter (/= ".") names)))

||| The visible names in a directory, sorted, as a shell's `*` names them.
export
visibleIn : String -> IO (List String)
visibleIn dir = filter (not . isPrefixOf ".") <$> namesIn dir

||| The names in a directory as `DIR/* DIR/.[!.]*` names them: the visible
||| ones sorted, then the hidden ones sorted.
export
globbed : String -> IO (List String)
globbed dir = do
  names <- namesIn dir
  pure (filter (not . isPrefixOf ".") names ++ filter (isPrefixOf ".") names)

||| The visible directories in a directory, sorted, as `DIR/*/` names them.
export
directoriesIn : String -> IO (List String)
directoriesIn dir = do
  names <- visibleIn dir
  map concat $ for names $ \n => do
    d <- isDirectory (dir ++ "/" ++ n)
    pure (if d then [n] else [])

||| Every file under a directory, by its path from the directory as given,
||| a directory's entries before the next of its siblings.
export
filesUnder : String -> IO (List String)
filesUnder dir = do
  names <- namesIn dir
  map concat $ for names $ \name => do
    let path = dir ++ "/" ++ name
    if !(isDirectory path) then filesUnder path
      else if !(exists path) then pure [path] else pure []

||| The last component of a path.
export
baseName : String -> String
baseName path = last (split (== '/') path)

||| A path without its last component.
export
dirName : String -> String
dirName path = case break (== '/') (reverse (unpack path)) of
  (_, '/' :: rest) => case reverse rest of
    [] => "/"
    d => pack d
  _ => "."

||| A path made absolute against the directory the run script runs in, as
||| `cd PATH && pwd` names it: its `.` components gone and each `..` taking
||| the component before it.
export
absolute : Env -> String -> String
absolute e path =
  let whole = if isPrefixOf "/" path then path else e.tools.here ++ "/" ++ path in
  "/" ++ joinBy "/" (resolve [<] (forget (split (== '/') whole)))
  where
    resolve : SnocList String -> List String -> List String
    resolve done [] = done <>> []
    resolve done ("" :: rest) = resolve done rest
    resolve done ("." :: rest) = resolve done rest
    resolve (done :< _) (".." :: rest) = resolve done rest
    resolve [<] (".." :: rest) = resolve [<] rest
    resolve done (c :: rest) = resolve (done :< c) rest

||| The first whitespace-separated word of a file, or none.
export
firstWord : String -> IO (Maybe String)
firstWord path = (\t => head' (words t)) . fromMaybe "" <$> readIfThere path

||| `-p PACKAGE` for each installed package a directory's `packages` file
||| names, as separate words; none without the file.
export
packageOptions : String -> IO (List String)
packageOptions dir = do
  text <- readIfThere (dir ++ "/packages")
  pure (concatMap (\p => ["-p", p]) (words (fromMaybe "" text)))

------------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------------

||| A tool with its words, bounded by the step limit, in the directory the
||| run script runs in, reading nothing.
export
bounded : Env -> List String -> (out : Output) -> (err : ErrorOutput) -> IO Status
bounded e ws out err = run e.session (MkCommand Bounded ws e.tools.here NoInput out err)

||| A tool with its words, bounded, reading its standard input from a file.
export
boundedOn : Env -> List String -> Input -> (out : Output) -> (err : ErrorOutput) -> IO Status
boundedOn e ws input out err = run e.session (MkCommand Bounded ws e.tools.here input out err)

||| The pinned Idris with its words, bounded, on its own prefix, whose
||| prelude and base it checked (the glue's pinned_idris), run in the work
||| directory.
export
pinnedIdris : Env -> List String -> Input -> (out : Output) -> (err : ErrorOutput) -> IO Status
pinnedIdris e ws input out err = run e.session (MkCommand PinnedIdris ws e.tools.work input out err)

||| A tool's standard output, its words bounded and its standard error
||| left to the file named: its status, and what it printed.
export
captured : Env -> List String -> (err : ErrorOutput) -> IO (Status, String)
captured e ws err = do
  let path = sessionDir e.session ++ "/captured"
  status <- bounded e ws (ToFile path) err
  text <- fromMaybe "" <$> readIfThere path
  pure (status, text)

||| A shell's `$(...)`: the text without its trailing line ends.
export
trailing : String -> String
trailing = pack . reverse . dropWhile (== '\n') . reverse . unpack

||| Whether two files hold the same bytes, as `cmp -s` says.
export
sameBytes : Env -> String -> String -> IO Bool
sameBytes e a b = succeeded <$> bounded e ["cmp", "-s", a, b] (ToFile "/dev/null") (Apart (ToFile "/dev/null"))

||| The first twenty lines of `diff A B`, indented, as a failure shows how
||| two outputs differ.
export
differences : Env -> String -> String -> IO (List String)
differences e a b = do
  let path = sessionDir e.session ++ "/diff"
  _ <- bounded e ["diff", a, b] (ToFile path) (Apart (ToFile "/dev/null"))
  indented <$> firstLines 20 [path]

||| A directory made, with the directories above it.
export
made : Env -> String -> IO ()
made e dir = ignore (bounded e ["mkdir", "-p", dir] (ToFile "/dev/null") (Apart ToCaller))

||| A path removed, whatever it holds.
export
removed : Env -> String -> IO ()
removed e path = ignore (bounded e ["rm", "-rf", path] (ToFile "/dev/null") (Apart ToCaller))

||| `copy_fixture FIXTURE DEST`: a fixture file, or the files and module
||| directories of a fixture directory but the golden test's own, a build
||| left in it, and the cases and the neighbour (`near/`) the harness reads
||| in place. A module in a namespace is a file in its directory.
export
copyFixture : Env -> (fixture : String) -> (dest : String) -> IO Status
copyFixture e fixture dest = do
  directory <- isDirectory fixture
  if directory
     then do
       names <- namesIn fixture
       kept <- filterM copied names
       case kept of
         [] => pure (Code 0)
         _ => bounded e (["cp", "-Rp"] ++ map (\n => fixture ++ "/" ++ n) kept ++ [dest ++ "/"]) ToCaller (Apart ToCaller)
     else bounded e ["cp", "-p", fixture, dest ++ "/"] ToCaller (Apart ToCaller)
  where
    own : String -> Bool
    own n = elem n ["run", "expected", "suite", "targets", "build", "cases", "near"] || isPrefixOf "expected." n

    filterM : (String -> IO Bool) -> List String -> IO (List String)
    filterM p [] = pure []
    filterM p (x :: xs) = do
      keep <- p x
      if keep then (x ::) <$> filterM p xs else filterM p xs

    copied : String -> IO Bool
    copied n =
      if own n then pure False else do
        let path = fixture ++ "/" ++ n
        directory <- isDirectory path
        if directory then pure True else exists path

------------------------------------------------------------------------------
-- The artifacts a build leaves
------------------------------------------------------------------------------

||| The artifacts a build leaves in its build directory, by kind, held here
||| once: the module the frontend hands the driver (bytecode, which every
||| tool reads by its magic), the one output a reader of the frontend's
||| work reads; the objects code generation writes, one per bin, each
||| <bin>.o in the directory NAME.objects; and the executable.
public export
data ArtifactKind = Module | Objects | Executable

export
artifactKinds : List ArtifactKind
artifactKinds = [Module, Objects, Executable]

export
kindName : ArtifactKind -> String
kindName Module = "module"
kindName Objects = "objects"
kindName Executable = "executable"

export
kindNamed : String -> Maybe ArtifactKind
kindNamed "module" = Just Module
kindNamed "objects" = Just Objects
kindNamed "executable" = Just Executable
kindNamed _ = Nothing

||| The build an artifact is of: one named, or any.
public export
data BuildName = Named String | AnyBuild

export
buildNamed : String -> BuildName
buildNamed "*" = AnyBuild
buildNamed n = Named n

||| Whether a path under a build directory is an artifact of the kind of
||| the build, as find's `-path` reads `*/NAME.mlirbc`, `*/NAME.objects/*.o`
||| and `*/NAME`: a `*` matches any characters, slashes among them.
isArtifact : ArtifactKind -> BuildName -> String -> Bool
isArtifact Module (Named n) p = isSuffixOf ("/" ++ n ++ ".mlirbc") p
isArtifact Module AnyBuild p = isSuffixOf ".mlirbc" p && isInfixOf "/" p
isArtifact Objects (Named n) p = isInfixOf ("/" ++ n ++ ".objects/") p && isSuffixOf ".o" p
isArtifact Objects AnyBuild p = isInfixOf ".objects/" p && isSuffixOf ".o" p
isArtifact Executable (Named n) p = isSuffixOf ("/" ++ n) p
isArtifact Executable AnyBuild p = isInfixOf "/" p

||| The files of the kind the build left under DIR/build, sorted.
export
artifactFiles : (dir : String) -> BuildName -> ArtifactKind -> IO (List String)
artifactFiles dir name kind = sort . nub . filter (isArtifact kind name) <$> filesUnder (dir ++ "/build")

||| The one file of the kind, or none.
export
artifactFile : (dir : String) -> BuildName -> ArtifactKind -> IO (Maybe String)
artifactFile dir name kind = head' <$> artifactFiles dir name kind

||| `artifacts DIR NAME`: the build left a non-empty file of every kind
||| under DIR/build. The line names the kinds, so it states what a
||| compilation leaves, not how the driver spells it.
export
artifactLines : (dir : String) -> (name : String) -> IO (List String)
artifactLines dir name = do
  found <- for artifactKinds $ \kind => do
    files <- artifactFiles dir (Named name) kind
    filled <- for files nonEmpty
    pure (kind, not (null files) && all id filled)
  let present = map fst (filter snd found)
  let missing = map fst (filter (not . snd) found)
  pure (("artifacts:" ++ concatMap ((" " ++) . kindName) present)
        :: (if null missing then [] else ["missing or empty:" ++ concatMap ((" " ++) . kindName) missing]))

||| `no_artifacts DIR`: no module or object of any build under DIR/build.
export
noArtifactsLine : (dir : String) -> IO String
noArtifactsLine dir = do
  left <- concat <$> for [Module, Objects] (artifactFiles dir AnyBuild)
  let lead = dir ++ "/"
  let named = sort (nub (map (\p => if isPrefixOf lead p then pack (drop (length lead) (unpack p)) else p) left))
  pure $ case named of
    [] => "artifacts: none"
    _ => "artifacts left after a rejection: " ++ concatMap (++ " ") named

------------------------------------------------------------------------------
-- Compiling with the compiler under test
------------------------------------------------------------------------------

||| What a compilation was asked, as the timing record names it: by the
||| options that change what is compiled, and there are none: not the
||| packages, nor the threads, nor what is printed where.
recordedWhat : List String -> String
recordedWhat = go "compile"
  where
    go : String -> List String -> String
    go acc [] = acc
    go acc ("-p" :: _ :: rest) = go acc rest
    go acc ("-p" :: []) = acc
    go acc (o :: rest) =
      if isPrefixOf "--num-threads=" o || isPrefixOf "--mlir-print-" o || isPrefixOf "--report=" o
         then go acc rest else go (acc ++ " " ++ o) rest

||| The timing record of the test: harness/build/timing/<the test's
||| directory under tests/, or its path outside it, each / as __, then
||| @<parameter> for one run of a parameterized test>.tsv.
timingId : Tools -> String
timingId t =
  let testsDir = t.root ++ "/tests/"
      path = if isPrefixOf testsDir t.here then pack (drop (length testsDir) (unpack t.here))
             else pack (dropWhile (== '/') (unpack t.here))
      stem = joinBy "__" (forget (split (== '/') path))
  in if t.parameter == "" then stem else stem ++ "@" ++ t.parameter

||| One line of the timing record, `<ms> TAB <exit> TAB <what> TAB
||| <module>`, where <module> is a copy of the module the frontend handed
||| the driver, kept beside the record (or -), so tools/compile-times.sh
||| can compile it again under --mlir-timing. The first compilation of a
||| work directory starts the record over; the record gates nothing.
recordTime : Env -> (ms : Integer) -> Status -> (options : List String) -> (source, output : String) -> IO ()
recordTime e ms status options source output = do
  let dir = e.tools.root ++ "/harness/build/timing"
  let stem = timingId e.tools
  let tsv = dir ++ "/" ++ stem ++ ".tsv"
  let counted = inWork e "timing.count"
  made e dir
  countText <- readIfThere counted
  let previous : Nat = fromMaybe 0 (countText >>= \t => parsePositive (trim t))
  when (previous == 0) $ do
    ignore (writeFile tsv "")
    old <- filter (keptBefore stem) <$> namesIn dir
    for_ old $ \n => removeFile (dir ++ "/" ++ n)
  let count = S previous
  ignore (writeFile counted (show count ++ "\n"))
  copied <- if raw status /= 0 then pure "-" else do
    found <- artifactFile (dirName source) (Named (baseName output)) Module
    case found of
      Nothing => pure "-"
      Just path => do
        let copy = dir ++ "/" ++ stem ++ "." ++ show count ++ "." ++ extension path
        st <- bounded e ["cp", path, copy] (ToFile "/dev/null") (Apart (ToFile "/dev/null"))
        pure (if succeeded st then copy else "-")
  ignore (appendFile tsv (joinBy "\t" [show ms, show (raw status), recordedWhat options, copied] ++ "\n"))
  where
    extension : String -> String
    extension p = last (split (== '.') p)

    -- A module an earlier run of the test kept: <stem>.<count>.<extension>.
    keptBefore : String -> String -> Bool
    keptBefore stem n =
      let lead = stem ++ "." in
      if not (isPrefixOf lead n) then False
      else case drop (length lead) (unpack n) of
        (d :: rest) => isDigit d && elem '.' rest
        [] => False

||| `compile_program [OPTION]... SOURCE OUTPUT`: SOURCE, an IO program,
||| compiled with idris-mlir's OPTIONs through tools/compile.sh, the one
||| copy of how idris-mlir runs; its output in the work directory's
||| compile.out and compile.err; its wall time recorded.
export
compileProgram : Env -> (options : List String) -> (source, output : String) -> IO Status
compileProgram e options source output = do
  started <- clockTime Monotonic
  status <- bounded e (e.tools.compileSh :: options ++ [source, output])
                    (ToFile (inWork e "compile.out")) (Apart (ToFile (inWork e "compile.err")))
  ended <- clockTime Monotonic
  recordTime e (div (toNano ended - toNano started) 1000000) status options source output
  pure status

||| The checked runtime, which every program a test runs links: a cell that
||| dies keeps its memory marked and is never reused, so a release of a
||| dead cell ends the run at the release, and a run that returns from main
||| with a cell still live ends as the runtime's internal error naming the
||| count. `compile_checked`: compileProgram, the program linked with it.
export
compileChecked : Env -> (options : List String) -> (source, output : String) -> IO Status
compileChecked e options = compileProgram e (("--runtime=" ++ e.tools.checkedRuntime) :: options)

||| The compiled program's run on a case: bounded, its standard input from a
||| file or none, its outputs in the work directory's NAME.out and NAME.err.
export
runProgram : Env -> (name : String) -> (exe : String) -> Input -> IO Status
runProgram e name exe input =
  boundedOn e [exe] input (ToFile (inWork e (name ++ ".out"))) (Apart (ToFile (inWork e (name ++ ".err"))))

||| `link_program ARG...`: the pinned C compiler with ARGs, then what links
||| a program for the target, one argument per line of idris-mlir
||| --print-link-flags, as idris-mlir links one; its outputs the caller's.
export
linkProgram : Env -> List String -> (out : Output) -> (err : ErrorOutput) -> IO Status
linkProgram e args out err = do
  (st, flags) <- captured e [e.tools.idrisMlir, "--print-link-flags"] (Apart ToCaller)
  if not (succeeded st) then pure (Code 1) else
    bounded e (e.tools.pinnedCc :: args ++ lines (trailing flags)) out err

||| One time and its share of a timing report's row, `<s> (<p>%)  `, at the
||| start of the characters: the time, and what follows.
timeAt : List Char -> Maybe (String, List Char)
timeAt cs =
  let (sign, cs1) = signed cs in
  case digits cs1 of
    Just (whole, '.' :: cs2) => case digits cs2 of
      Just (fraction, ' ' :: '(' :: cs3) =>
        case span (\c => isDigit c || c == '.') (snd (signed (dropWhile (== ' ') cs3))) of
          (_ :: _, '%' :: ')' :: ' ' :: ' ' :: after) => Just (pack (sign ++ whole ++ ['.'] ++ fraction), after)
          _ => Nothing
      _ => Nothing
    _ => Nothing
  where
    signed : List Char -> (List Char, List Char)
    signed ('-' :: r) = (['-'], r)
    signed r = ([], r)

    digits : List Char -> Maybe (List Char, List Char)
    digits r = case span isDigit r of
      ([], _) => Nothing
      found => Just found

||| The last time of a row, and what follows it.
lastTime : List Char -> Maybe (String, List Char)
lastTime = go Nothing
  where
    go : Maybe (String, List Char) -> List Char -> Maybe (String, List Char)
    go found [] = found
    go found cs@(_ :: rest) = case timeAt cs of
      Just (t, after) => go (Just (t, after)) after
      Nothing => go found rest

||| `timing_rows REPORT`: the rows of an execution time report (idris-mlir
||| --mlir-timing, MLIR's tree display), in order, each as `<depth> TAB
||| <seconds> TAB <name>`: depth 0 for a row of the report's own (the
||| parse, a step of the pipeline, LLVM, Rest, Total), one more for each
||| row it is nested in, two spaces each; seconds the wall time, the last
||| `<seconds> (<percent>%)` of the line.
export
timingRows : String -> List String
timingRows text = mapMaybe row (lines text)
  where
    row : String -> Maybe String
    row l = do
      (seconds, rest) <- lastTime (unpack l)
      let (spaces, name) = span (== ' ') rest
      pure (show (div (length spaces) 2) ++ "\t" ++ seconds ++ "\t" ++ pack name)

------------------------------------------------------------------------------
-- A C++ program over the pinned MLIR
------------------------------------------------------------------------------

||| The target the toolchain's CMake file names for its C++ compiler.
targetOf : String -> Maybe String
targetOf text = head' (mapMaybe line (lines text))
  where
    line : String -> Maybe String
    line l =
      let opening = "set(CMAKE_CXX_COMPILER_TARGET \""
          closing = "\")"
      in if isPrefixOf opening l && isSuffixOf closing l
            then Just (pack (take (minus (length l) (length opening + length closing)) (drop (length opening) (unpack l))))
            else Nothing

||| `mlir_program SOURCE OUTPUT`: SOURCE, a C++ program that calls the
||| pinned LLVM and MLIR as libraries (an upstream check that reaches code
||| no tool reaches alone: a walk mlir-opt's own parser would overflow
||| first), built for the toolchain's target, as its toolchain file names
||| it, with the flags those libraries were built with, and linked
||| statically with every MLIR and LLVM archive of the toolchain, of which
||| the linker takes what the program uses. The compiler's output is in
||| the work directory's cc.log.
export
mlirProgram : Env -> (source, output : String) -> IO Status
mlirProgram e source output = do
  cmake <- fromMaybe "" <$> readIfThere (e.tools.llvmPrefix ++ "/toolchain.cmake")
  let config = e.tools.llvmBin ++ "/llvm-config"
  (_, cxxflags) <- captured e [config, "--cxxflags"] (Apart ToCaller)
  (_, libs) <- captured e [config, "--ldflags", "--link-static", "--libs", "--system-libs"] (Apart ToCaller)
  archives <- sort . filter (\n => isPrefixOf "libMLIR" n && isSuffixOf ".a" n) <$> visibleIn (e.tools.llvmPrefix ++ "/lib")
  bounded e ([e.tools.llvmBin ++ "/clang++", "--target=" ++ fromMaybe "" (targetOf cmake), "-O1"]
             ++ words cxxflags ++ [source, "-o", output]
             ++ map (\a => e.tools.llvmPrefix ++ "/lib/" ++ a) archives ++ words libs)
          (ToFile (inWork e "cc.log")) WithOutput

||| `mlir_check WHAT SOURCE ARG...`: SOURCE built by mlirProgram and run with
||| ARGs; one line, WHAT, when it exits 0 having printed `ok` alone, which
||| is how such a program says each of its checks held; otherwise its build
||| log, or its status and what it printed.
export
mlirCheck : Env -> (what, source : String) -> List String -> IO ()
mlirCheck e what source args = do
  let name = let b = baseName source in
             if isSuffixOf ".cpp" b then pack (take (minus (length b) 4) (unpack b)) else b
  let program = inWork e name
  built <- mlirProgram e source program
  if not (succeeded built)
     then do tell e (name ++ ": does not build"); showIn e [inWork e "cc.log"]
     else do
       status <- bounded e (program :: args) (ToFile (inWork e "mlir-check.out")) (Apart (ToFile (inWork e "mlir-check.err")))
       out <- fromMaybe "" <$> readIfThere (inWork e "mlir-check.out")
       if succeeded status && trailing out == "ok"
          then tell e what
          else do
            tell e (name ++ ": exit " ++ show (raw status) ++ ", so not: " ++ what)
            showIn e [inWork e "mlir-check.out", inWork e "mlir-check.err"]

------------------------------------------------------------------------------
-- Properties a program states of its stages
------------------------------------------------------------------------------

||| `stage_options FIXTURE`: the compilation's options for the properties
||| FIXTURE states, `--idr-expect-at=<stage>:<property>,...` one each. An
||| mlir.expect file lists, a line each, `<stage>: <property>...`, the
||| properties that hold of the program at that stage of the pipeline (the
||| specification's stages, as the pipeline's table names them), checked
||| in the compilation itself after every pass of the stage and as the
||| program enters it; lines that start with `#` explain. No line names a
||| pass. The mark `heap-free` is the property no-heap-allocation at the
||| owned stage, the module that is lowered.
export
stageOptions : (fixture : String) -> IO (List String)
stageOptions fixture = do
  heapFree <- exists (fixture ++ "/heap-free")
  expect <- readIfThere (fixture ++ "/mlir.expect")
  pure ((if heapFree then ["--idr-expect-at=owned:no-heap-allocation"] else [])
        ++ mapMaybe option (lines (fromMaybe "" expect)))
  where
    option : String -> Maybe String
    option l =
      if l == "" || isPrefixOf "#" l then Nothing
      else case break (== ':') (unpack l) of
        (stage, ':' :: rest) => Just ("--idr-expect-at=" ++ pack stage ++ ":" ++ joinBy "," (words (pack rest)))
        (stage, _) => Just ("--idr-expect-at=" ++ pack stage ++ ":" ++ joinBy "," (words (pack stage)))
