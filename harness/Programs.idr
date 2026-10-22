-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The program tests: the end-to-end programs, compiled once and run on
||| each of their cases, each held to what its case says the run gives;
||| the generated semantics tests; the programs the compiler refuses, each
||| by one rule at the right line, and the nearest accepted neighbour of
||| each; and the registry's refusal of an entry whose definition is not
||| the one it names.
|||
||| Each program is compiled once, with the passes' contracts, the promises
||| every compiled program keeps and the properties it states of its stages
||| checked as the passes run, and everything else that holds of a
||| compilation is read off that one compilation (Universal.idr); then the
||| executable runs once per case.
module Programs

import Data.List
import Data.Maybe
import Data.String
import System
import System.File

import Covers
import Facts
import Files
import Harness
import Reject
import Sem
import Serve
import Universal


%default covering

------------------------------------------------------------------------------
-- A fixture's files
------------------------------------------------------------------------------

isFile : String -> IO Bool
isFile path = do
  directory <- isDirectory path
  if directory then pure False else exists path

filterIO : (a -> IO Bool) -> List a -> IO (List a)
filterIO p [] = pure []
filterIO p (x :: xs) = do
  keep <- p x
  if keep then (x ::) <$> filterIO p xs else filterIO p xs

||| Every file of FIXTURE is one a program test reads: the test's own (run,
||| expected, expected.<host>, suite, targets), an Idris module, or a mark
||| of its compilation (packages, mlir.expect, heap-free, covers);
||| otherwise a line naming the others. A misspelt mark, or one nothing
||| reads (an mlir.check: a property of a compiled module is stated by name
||| in mlir.expect; a stdin: what a run reads is a case's), would otherwise
||| be copied into the build and ignored, and its check would pass by never
||| running.
filesKnown : Env -> (fixture : String) -> IO Holds
filesKnown e fixture = do
  names <- globbed fixture
  files <- filterIO (\n => isFile (fixture ++ "/" ++ n)) names
  case filter (not . known) files of
    [] => pure Held
    unknown => do
      tell e ("fixture: files no check reads:" ++ concatMap (" " ++) unknown)
      pure Broken
  where
    known : String -> Bool
    known n = isSuffixOf ".idr" n || isPrefixOf "expected." n
              || elem n ["run", "expected", "suite", "targets", "packages", "mlir.expect", "heap-free", "covers"]

||| The files a case directory may hold, each a field of the one record a
||| case is: what the run reads, what it must give, and the marks of that
||| run.
caseFields : List String
caseFields = ["stdin", "expected-stdout", "expected-ending", "expected-stderr", "libm-lines"]

||| A case's name: letters, digits and dashes, not starting with a dash.
caseNamed : String -> Bool
caseNamed n = case unpack n of
  [] => False
  ('-' :: _) => False
  cs => all (\c => isAlphaNum c || c == '-') cs

||| FIXTURE's `cases`, when it has one, is a directory of at least one case,
||| each a directory named in letters, digits and dashes that holds only
||| the case's fields; otherwise a line naming each fault. A case is never
||| skipped: a file no field names, or a case that is no directory, would
||| otherwise pass by never being read.
casesKnown : Env -> (fixture : String) -> IO Holds
casesKnown e fixture = do
  let cases = fixture ++ "/cases"
  there <- exists cases
  directory <- isDirectory cases
  if not there then pure Held else
    if not directory
       then do tell e "cases: not a directory"; pure Broken
       else do
         names <- globbed cases
         found <- for names (fault cases)
         let faults = concatMap snd found
         let counted = length (filter fst found)
         case faults ++ (if counted == 0 then [" (no case)"] else []) of
           [] => pure Held
           listed => do tell e ("cases:" ++ concat listed); pure Broken
  where
    fieldFault : String -> String -> String -> IO (List String)
    fieldFault dir name file =
      if elem file caseFields
         then (\f => if f then [] else [" " ++ name ++ "/" ++ file ++ " (not a file)"]) <$> isFile (dir ++ "/" ++ file)
         else pure [" " ++ name ++ "/" ++ file ++ " (no field of a case)"]

    -- Whether the entry is a case, and its faults.
    fault : String -> String -> IO (Bool, List String)
    fault cases name =
      if not (caseNamed name) then pure (False, [" " ++ name ++ " (a name of letters, digits and dashes)"]) else do
        let dir = cases ++ "/" ++ name
        if not !(isDirectory dir) then pure (False, [" " ++ name ++ " (not a directory)"]) else do
          files <- globbed dir
          (\fs => (True, concat fs)) <$> for files (fieldFault dir name)

------------------------------------------------------------------------------
-- A run held to its case
------------------------------------------------------------------------------

||| How a run's output is compared with what its case expects: byte for
||| byte, or with the lines that hold libm results compared to a few units
||| in the last place.
data Tolerance = Exactly | LibmLines String

||| EXPECTED and OURS print the same text, except that the numbered lines
||| (one number per line of LINES) hold libm results, whose last places are
||| the platform libm's, not the program's: libm is not correctly rounded,
||| and the runtime calls the platform's, so a value recorded on one
||| platform may differ from another's by a few units in the last place
||| (four here). Every other line, and the number of lines, must agree
||| exactly.
withinAFewUlp : (expected, ours, numbered : String) -> Bool
withinAFewUlp expected ours numbered =
  let libm = mapMaybe (\l => the (Maybe Nat) (parsePositive l)) (lines numbered)
      es = lines expected
      os = lines ours
  in length es == length os && all (close libm) (zip3 [1 .. length es] es os)
  where
    magnitude : Double -> Double
    magnitude x = if x < 0 then negate x else x

    close : List Nat -> (Nat, String, String) -> Bool
    close libm (n, a, b) =
      a == b || (elem n libm &&
        let x = cast {to = Double} a
            y = cast {to = Double} b
        in magnitude (x - y) <= max (magnitude x) (magnitude y) * pow 2 (-50))

||| How an output of the run differs from the case's file of it, if it
||| does: a line naming it and the first lines of the difference.
compared : Env -> (dir, file, ours, name, stream : String) -> Tolerance -> IO (List String)
compared e dir file ours name stream tolerance = do
  let given = dir ++ "/" ++ file
  expected <- (\there => if there then given else "/dev/null") <$> exists given
  if !(sameBytes e expected ours) then pure [] else do
    near <- case tolerance of
      Exactly => pure False
      LibmLines numbered => do
        Just lineNumbers <- readIfThere numbered
          | Nothing => pure False
        pure (withinAFewUlp !(fromMaybe "" <$> readIfThere expected) !(fromMaybe "" <$> readIfThere ours) lineNumbers)
    if near then pure [] else
      (("case " ++ name ++ ": " ++ stream ++ " differs from " ++ file) ::) <$> differences e expected ours

||| The compiled program run on the case directory DIR:
|||
|||     stdin            the bytes on its standard input; none without it
|||     expected-stdout  the bytes it writes on its standard output; none
|||                      without it
|||     expected-ending  how the run ends, one line, the specification's
|||                      ending as Facts.idr writes it; `returned` without it
|||     expected-stderr  the bytes it writes on its standard error, the
|||                      runtime's line for its ending among them; none
|||                      without it
|||     libm-lines       the numbered output lines are libm results, whose
|||                      last places are the platform libm's and may differ
|||                      from expected-stdout's
|||
||| The status the run must end with, an exit code or a signal, is computed
||| from the ending, from the specification's table: no status is spelled
||| here. What the run gave is kept in the work directory's case-runs, for
||| the run of the same program compiled with actions skipped. Nothing when
||| the run gives what the case says, and a line per difference otherwise,
||| each naming the case.
e2eCase : Env -> (exe, dir, name : String) -> IO (List String)
e2eCase e exe dir name = do
  ending <- endingOf <$> readIfThere (dir ++ "/expected-ending")
  case ending of
    Left why => pure ["case " ++ name ++ ": its ending cannot be read", "  | " ++ why]
    Right expected => do
      let kept = inWork e ("case-runs/" ++ name)
      let stdin = dir ++ "/stdin"
      input <- (\there => if there then FromFile stdin else NoInput) <$> isFile stdin
      status <- boundedOn e [exe] input (ToFile (kept ++ ".out")) (Apart (ToFile (kept ++ ".err")))
      ignore (writeFile (kept ++ ".status") (show (raw status) ++ "\n"))
      let ended = if statusWords status == statusLine expected then []
                  else ["case " ++ name ++ ": ended by " ++ statusWords status ++ ", expected " ++ statusLine expected]
      libm <- (\there => if there then LibmLines (dir ++ "/libm-lines") else Exactly) <$> exists (dir ++ "/libm-lines")
      out <- compared e dir "expected-stdout" (kept ++ ".out") name "stdout" libm
      err <- compared e dir "expected-stderr" (kept ++ ".err") name "stderr" Exactly
      pure (ended ++ out ++ err)

||| The compiled program run once per case of its fixture's `cases`, in the
||| order of their names, each held to its own expected files. One line
||| when every case gives what it says, `cases: each as expected`;
||| otherwise the lines of each case that did not, and no such line. The
||| line does not count the cases, so a case added changes no transcript;
||| casesKnown has made sure that each case directory is read.
e2eCases : Env -> (fixture, exe : String) -> IO ()
e2eCases e fixture exe = do
  names <- directoriesIn (fixture ++ "/cases")
  made e (inWork e "case-runs")
  failed <- concat <$> for names (\n => e2eCase e exe (fixture ++ "/cases/" ++ n) n)
  case failed of
    [] => tell e "cases: each as expected"
    _ => tellAll e failed

------------------------------------------------------------------------------
-- A program test
------------------------------------------------------------------------------

||| `e2e_io FIXTURE`: an IO program, Main.idr and its other modules,
||| compiled once with the checked runtime, every pass's contracts and the
||| promises every compiled program keeps checked as it runs
||| (--idr-contracts), and the properties the fixture states of a stage
||| after every pass of that stage; run on each of its cases; and checked as
||| every compilation is (universal). A fixture with no `cases` directory is
||| compiled only (a program that never ends). `packages` names installed
||| packages it uses; `covers` a prelude module whose every export it uses.
export
e2eIo : Env -> (fixture : String) -> IO ()
e2eIo e given = do
  let fixture = absolute e given
  Held <- filesKnown e fixture
    | Broken => pure ()
  Held <- casesKnown e fixture
    | Broken => pure ()
  packages <- packageOptions fixture
  let ours = inWork e "ours"
  made e ours
  _ <- copyFixture e fixture ours
  -- The checks a compilation from the emitted module takes too
  -- (universal); the packages are the frontend's alone.
  options <- ("--idr-contracts" ::) <$> stageOptions fixture
  compiled <- compileChecked e (packages ++ options) (ours ++ "/Main.idr") "prog"
  tell e ("compile: exit " ++ show (raw compiled))
  if not (succeeded compiled) then showIn e [inWork e "compile.out", inWork e "compile.err"] else do
    tellAll e !(artifactLines ours "prog")
    when !(isDirectory (fixture ++ "/cases")) $ e2eCases e fixture (ours ++ "/build/exec/prog")
    emitted <- fromMaybe "" <$> artifactFile ours (Named "prog") Module
    objects <- artifactFiles ours (Named "prog") Objects
    ignore (universal e fixture emitted options objects)
    when !(exists (fixture ++ "/heap-free")) $ tell e "heap: nothing is allocated on the heap"
    when !(exists (fixture ++ "/mlir.expect")) $ tell e "mlir.expect: holds"
    when !(exists (fixture ++ "/covers")) $
      coversPrelude e (fromMaybe "" !(firstWord (fixture ++ "/covers"))) emitted fixture

||| The two programs' Main.idr of a semantics test: Main is partial, since
||| Prog.result may divide, and Idris does not hold a primitive division
||| covering, its divisor possibly 0.
semMain : Given -> String
semMain given = unlines
  [ "module Main", "", "import Prelude", "import Prog", "", "partial", "main : IO ()"
  , case given of
      InProgram => "main = printLn Prog.result"
      OnStdin => "main = Prog.result >>= printLn" ]

||| `sem_case NAME`: the generated semantics test NAME, one run of
||| tests/semantics, which runs once per test of Sem.idr's table: two
||| program tests built in the work directory, one table checked by two
||| programs, whose Prog.idr and cases are Sem's, which computes every
||| case's value from what the builtin means, and states once what a
||| program prints when all agree. In the first, every operand is written in
||| the program, so the compiler computes each case while it compiles; its
||| cases are comparisons of fixed-width integers, which never need a heap
||| cell (heap-free). In the second, every operand is read from the case's
||| stdin, so only the compiled program's arithmetic answers; it reads lines
||| into lists, which live on the heap. Its cases are the one of every pair
||| inside its builtin's guard, and one for each pair the guard stops, which
||| must end by the guard's crash. Its account is the first's form, each
||| line prefixed `stdin: `.
export
semCase : Env -> (name : String) -> IO ()
semCase e name = do
  let written = inWork e "sem"
  let read = inWork e "sem-stdin"
  made e (written ++ "/cases/no-input")
  made e (read ++ "/cases")
  let missing = "no semantics test " ++ name
  Just writtenProgram <- pure (programOf InProgram name)
    | Nothing => noProgram [missing]
  Just expected <- pure (expectedOf name)
    | Nothing => noProgram [missing]
  Just readProgram <- pure (programOf OnStdin name)
    | Nothing => noProgram [missing]
  Right () <- writeCases name (read ++ "/cases")
    | Left why => noProgram [why]
  ignore (writeFile (written ++ "/Prog.idr") writtenProgram)
  ignore (writeFile (written ++ "/cases/no-input/expected-stdout") expected)
  ignore (writeFile (read ++ "/Prog.idr") readProgram)
  ignore (writeFile (written ++ "/Main.idr") (semMain InProgram))
  ignore (writeFile (read ++ "/Main.idr") (semMain OnStdin))
  ignore (writeFile (written ++ "/heap-free") "")
  e2eIo e written
  let onStdin = inWork e "given-on-stdin"
  made e onStdin
  e2eIo (nested e onStdin "stdin: ") read
  where
    noProgram : List String -> IO ()
    noProgram why = do
      tell e ("no semantics program " ++ name)
      tellAll e (indented why)

||| Whether a program's first lines are a refused program's header naming
||| its rule: the lines of the form `-- expect: ...` or `-- message: ...`
||| that start it, one of them `expect`.
namesRule : String -> Bool
namesRule text = any (isPrefixOf "expect:") (map field (takeWhile headerLine (lines text)))
  where
    field : String -> String
    field l = ltrim (pack (drop 2 (unpack l)))

    headerLine : String -> Bool
    headerLine l = isPrefixOf "--" l && (isPrefixOf "expect:" (field l) || isPrefixOf "message:" (field l))

||| `near_neighbour FIXTURE`: a refused program's nearest accepted
||| neighbour, FIXTURE/near, when it has one: a program differing from the
||| refused one in the construct the rule refuses, which must compile and
||| give what its cases say, so the rule is pinned from both sides. It is a
||| program test's files (Main.idr, its modules, cases, marks) and none of
||| a test's own; each line of its account is prefixed `near: `.
export
nearNeighbour : Env -> (fixture : String) -> IO ()
nearNeighbour e given = do
  let near = absolute e given ++ "/near"
  when !(exists near) $ do
    own <- filterIO (\f => exists (near ++ "/" ++ f)) ["run", "expected", "suite", "targets"]
    case own of
      (f :: _) => tell e ("near: holds " ++ f ++ ", which is the refused test's own")
      [] => do
        Just main <- readIfThere (near ++ "/Main.idr")
          | Nothing => tell e "near: no Main.idr"
        if namesRule main
           then tell e "near: its Main.idr names a rule, but the neighbour is accepted"
           else do
             let work = inWork e "near"
             made e work
             e2eIo (nested e work "near: ") near

------------------------------------------------------------------------------
-- A refused program
------------------------------------------------------------------------------

||| `profile_reject FIXTURE`: a directory holding Main.idr and its other
||| modules, whose first line is `-- expect: <rule>, line <n>` (and then,
||| optionally, `-- message: <text>`, text the refusal holds anywhere in
||| it, whatever words surround it). It is refused, by that rule alone,
||| reported on line n, and leaves no artifact. The header and the
||| compilation's report are read once, each into its record, and compared
||| (Reject.idr): the rule one of the specification's, the report's every
||| error with its rule, Idris's own errors the rules of their category.
||| Nothing here reads the report's text. The module the frontend emitted,
||| which the compiler writes whatever its verdict (--emitted), is then
||| refused again with a drawn set of the optimizations' actions skipped:
||| a refusal is the program's, never the optimizer's.
export
profileReject : Env -> (fixture : String) -> IO ()
profileReject e given = do
  let fixture = absolute e given
  let copy = inWork e "fixture"
  made e copy
  _ <- copyFixture e fixture copy
  packages <- packageOptions copy
  compiled <- compileProgram e (packages ++ ["--report=" ++ inWork e "report", "--emitted=" ++ inWork e "emitted.mlirbc"])
                             (copy ++ "/Main.idr") "Main"
  tell e ("compile: exit " ++ show (raw compiled))
  let outputs = [inWork e "compile.out", inWork e "compile.err"]
  output <- concat <$> for outputs bytesIfThere
  (shown, holds) <- judged fixture (inWork e "report") output
  tellAll e shown
  when (not holds) $ showIn e outputs
  tell e !(noArtifactsLine copy)
  skipsRefuse e fixture (inWork e "emitted.mlirbc")

||| How the registry's validation is shown a definition it must refuse:
||| `shape` gives the definition's first declaration a leading argument
||| that every use fills by default, so the module still checks but the
||| definition has another shape; `gone` takes away the paragraph that holds
||| its last declaration (its documentation, modifiers and clauses, up to a
||| blank line), for an entry that names a definition and fixes no shape.
data Edit = Shape | Gone

editNamed : String -> Maybe Edit
editNamed "shape" = Just Shape
editNamed "gone" = Just Gone
editNamed _ = Nothing

blank : String -> Bool
blank = all isSpace . unpack

||| The source with the first declaration of NAME (or its `%extern`) given a
||| leading argument every use fills by default; none when NAME has none.
shaped : (name : String) -> List String -> Maybe (List String)
shaped name [] = Nothing
shaped name (l :: ls) =
  let marker = name ++ " : " in
  if declares (words l) && isInfixOf marker l
     then Just (insertAfter marker l :: ls)
     else (l ::) <$> shaped name ls
  where
    declares : List String -> Bool
    declares (w :: rest) = w == name || (w == "%extern" && head' rest == Just name)
    declares [] = False

    -- The argument goes after the first `NAME : ` of the line.
    insertAfter : String -> String -> String
    insertAfter marker line = go [<] (unpack line)
      where
        go : SnocList Char -> List Char -> String
        go before [] = pack (before <>> [])
        go before rest@(c :: cs) =
          if isPrefixOf (unpack marker) rest
             then pack (before <>> unpack marker) ++ "{default MkUnit shadowed : Unit} -> "
                  ++ pack (drop (length marker) rest)
             else go (before :< c) cs

||| The source without the paragraph that holds the last declaration of NAME
||| (`NAME :` its first two words): from the line after the last blank line
||| before it to the first blank line after it. A declaration with no blank
||| line before it is left in place. None when NAME has no declaration.
withoutLast : (name : String) -> List String -> Maybe (List String)
withoutLast name ls =
  let numbered = zip [1 .. length ls] ls
      (_, found) = foldl mark (Nothing, Nothing) numbered
  in map (\(from, at) => drop' from at numbered) found
  where
    mark : (Maybe Nat, Maybe (Maybe Nat, Nat)) -> (Nat, String) -> (Maybe Nat, Maybe (Maybe Nat, Nat))
    mark (start, found) (n, l) =
      let start' = if blank l then Just (S n) else start in
      case words l of
        (w :: ":" :: _) => if w == name then (start', Just (start', n)) else (start', found)
        _ => (start', found)

    drop' : Maybe Nat -> Nat -> List (Nat, String) -> List String
    drop' Nothing _ numbered = map snd numbered
    drop' (Just from) at numbered = go False numbered
      where
        go : Bool -> List (Nat, String) -> List String
        go _ [] = []
        go gone ((n, l) :: rest) =
          let gone' = (gone || n == from) && not (n > at && blank l) in
          if gone' then go gone' rest else l :: go gone' rest

||| Whether a line says what an entry expects and what was found.
expectsFound : String -> Bool
expectsFound l = case breakOn "expects " l of
  Just after => isInfixOf ", but found " after
  Nothing => False
  where
    breakOn : String -> String -> Maybe String
    breakOn needle hay = go (unpack hay)
      where
        go : List Char -> Maybe String
        go [] = Nothing
        go cs@(_ :: rest) = if isPrefixOf (unpack needle) cs then Just (pack (drop (length needle) cs)) else go rest

||| `registry_shadowed KEY CASE SOURCE MODULE NAME EDIT MAIN [OPTION...]`:
||| an input the registry's validation refuses, for its entry KEY. The
||| fixture CASE in the work directory holds MAIN as its Main.idr and, as
||| its own module MODULE (a path such as System/Clock.idr), the pinned
||| SOURCE (a path under the repository) with one edit to NAME, the
||| definition the entry resolves to. The validation reads only the loaded
||| context, so the fixture's own module is what it meets. Compiled with
||| the OPTIONs, the program must stop at the entry: refused by the hook
||| rule alone, as its report says (Reject.idr), with a message that names
||| the entry, what it expects and what was found, and leave no artifact.
export
registryShadowed : Env -> (key, caseName, source, moduleFile, name : String) -> Edit -> (main : String) -> List String -> IO ()
registryShadowed e key caseName source moduleFile name edit main options = do
  let dir = inWork e caseName
  let modulePath = dir ++ "/" ++ moduleFile
  made e (dirName modulePath)
  ignore (writeFile (dir ++ "/Main.idr") (main ++ "\n"))
  text <- fromMaybe "" <$> readIfThere (e.tools.root ++ "/" ++ source)
  let edited = case edit of
                 Shape => shaped name (lines text)
                 Gone => withoutLast name (lines text)
  case edited of
    Nothing => tell e (key ++ " broken: " ++ name ++ " not found in " ++ source)
    Just ls => do
      ignore (writeFile modulePath (unlines ls))
      let report = inWork e (caseName ++ ".report")
      compiled <- compileProgram e (options ++ ["--report=" ++ report]) (dir ++ "/Main.idr") "prog"
      tell e (key ++ " broken: exit " ++ show (raw compiled))
      let outputs = [inWork e "compile.out", inWork e "compile.err"]
      said <- concatMap lines <$> for outputs (\p => fromMaybe "" <$> readIfThere p)
      refused <- case ruleNamed "hook" of
        Just rule => refusedAs rule Anywhere report
        Nothing => do ignore (fPutStrLn stderr "hook is no rule's phrase"); pure False
      if refused && any (isInfixOf ("the registry's entry " ++ key ++ " (")) said && any expectsFound said
         then tell e (key ++ " broken: the error shows the entry, what it expects and what was found")
         else do
           tell e (key ++ " broken: no hook error for the entry")
           showIn e (report :: outputs)
      tell e !(noArtifactsLine dir)

||| `registry_shadowed`'s words, read: the edit named as one.
export
registryShadowedOf : Env -> List String -> Maybe (IO ())
registryShadowedOf e (key :: caseName :: source :: moduleFile :: name :: edit :: main :: options) =
  map (\ed => registryShadowed e key caseName source moduleFile name ed main options) (editNamed edit)
registryShadowedOf _ _ = Nothing
