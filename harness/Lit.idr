-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The dialect tests' `// RUN:` lines, run without lit and without Python,
||| as lit's internal shell ran them, and `%differential`, their oracle for
||| what a module means.
|||
||| In a RUN line, %s is the test's file, %t a path in the work directory,
||| %cc the pinned C compiler linking a program as the chain does, %runtime
||| the runtime object idris-mlir reads and every program links, `%status N
||| CMD` checks that CMD exits with status N, and `%differential BEFORE
||| AFTER` that two modules' programs mean the same on every input. A `%%`
||| stays as it is, never read as the start of one of these, so an awk
||| program's printf can write a `%` of the module it prints. A line fails
||| when any command of its pipelines fails (pipefail); a trailing \
||| continues it on the next RUN line. The lines run in order, and the first
||| that fails ends the test, as with lit: a later line reads what an earlier
||| one wrote, so it would check nothing, and is reported as not run. A
||| command that is to fail (`not CMD`, `%status 1 CMD`) must name the
||| failure it expects (unnamed), and then fails only that way (litFails).
||| Every idris-mlir-opt that is to succeed reads its input back from the
||| generic form and from bytecode before any pass (--verify-roundtrip) and
||| checks each pass's contracts as it runs (--idr-contracts); one that is
||| to fail does not, so that it fails for the reason its line names. The
||| rewritten line runs in the glue (lit_line, harness/lib/harness.sh),
||| whose functions are its commands.
module Lit

import Data.Buffer
import Data.List
import Data.List1
import Data.Maybe
import Data.String
import System
import System.File
import System.File.Buffer

import Files
import Harness
import Serve

%default covering

------------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------------

stripChars : List Char -> List Char -> Maybe (List Char)
stripChars [] cs = Just cs
stripChars (p :: ps) (c :: cs) = if p == c then stripChars ps cs else Nothing
stripChars _ [] = Nothing

||| Every occurrence of a text replaced by another, left to right.
replaceAll : (old, new : String) -> String -> String
replaceAll old new text = pack (go (unpack text))
  where
    go : List Char -> List Char
    go [] = []
    go cs@(c :: rest) = case stripChars (unpack old) cs of
      Just after => if old == "" then c :: go rest else unpack new ++ go after
      Nothing => c :: go rest

||| A comment line's text after `//`, spaces and a keyword (`RUN:`).
commented : (keyword : String) -> String -> Maybe (List Char)
commented keyword line = do
  rest <- stripChars ['/', '/'] (dropWhile isSpace (unpack line))
  stripChars (unpack keyword) (dropWhile isSpace rest)

||| The RUN lines of a dialect test: what follows `// RUN:` and spaces, its
||| trailing spaces and tabs gone, a line ending in `\` joined to the next.
runLines : String -> List String
runLines text = go "" (mapMaybe run (lines text))
  where
    run : String -> Maybe String
    run l = pack . dropWhile isSpace <$> commented "RUN:" l

    trimEnd : String -> String
    trimEnd = pack . reverse . dropWhile (\c => c == ' ' || c == '\t') . reverse . unpack

    go : String -> List String -> List String
    go joined [] = if joined == "" then [] else [joined]
    go joined (l :: ls) =
      let t = trimEnd l in
      if isSuffixOf "\\" t
         then go (joined ++ pack (reverse (drop 1 (reverse (unpack t))))) ls
         else (joined ++ t) :: go "" ls

------------------------------------------------------------------------------
-- A RUN line rewritten
------------------------------------------------------------------------------

separator : Char -> Bool
separator c = elem c (unpack "|&;(")

||| Each place a matcher matches, at the line's start or after one of
||| `|&;(` and any spaces, replaced by what it gives: sed's
||| `s/(^|[|&;(][[:space:]]*)OLD/\1NEW/g`.
afterSeparators : (List Char -> Maybe (List Char, List Char)) -> String -> String
afterSeparators matcher text = pack (start (unpack text))
  where
    scan : List Char -> List Char
    scan [] = []
    scan (c :: rest) =
      if separator c
         then let (spaces, more) = span isSpace rest in
              case matcher more of
                Just (new, after) => c :: spaces ++ new ++ scan after
                Nothing => c :: scan rest
         else c :: scan rest

    start : List Char -> List Char
    start cs = case matcher cs of
      Just (new, after) => new ++ scan after
      Nothing => scan cs

||| A literal replaced by another where it starts.
literal : (old, new : String) -> List Char -> Maybe (List Char, List Char)
literal old new cs = map (\after => (unpack new, after)) (stripChars (unpack old) cs)

checked : String
checked = "idris-mlir-opt --verify-roundtrip --idr-contracts "

||| `not diff`, `not cmp` and `not grep` made `%status 1`: their status 1 is
||| the answer no.
decision : List Char -> Maybe (List Char, List Char)
decision cs = do
  rest <- stripChars (unpack "not ") cs
  case mapMaybe (\w => map (\after => (w, after)) (stripChars (unpack (w ++ " ")) rest)) ["diff", "cmp", "grep"] of
    ((w, after) :: _) => Just (unpack ("%status 1 " ++ w ++ " "), after)
    [] => Nothing

||| `%status N idris-mlir-opt` not made to check its round trip and its
||| contracts: a command that is to fail fails for the reason its line
||| names.
statusUnchecked : String -> String
statusUnchecked text = pack (go (unpack text))
  where
    go : List Char -> List Char
    go [] = []
    go cs@(c :: rest) = case stripChars (unpack "%status ") cs of
      Just (d :: more) =>
        if d >= '1' && d <= '9'
           then case span isDigit more of
                  (ds, ' ' :: after) => case stripChars (unpack checked) after of
                    Just tool => unpack "%status " ++ d :: ds ++ unpack " idris-mlir-opt " ++ go tool
                    Nothing => c :: go rest
                  _ => c :: go rest
           else c :: go rest
      _ => c :: go rest

||| A pipeline's stages, each run by the glue's lit_stage: at the line's
||| start and after each `|` outside quotes, so a pipe inside a quoted
||| `sh -c` or awk program stays its own (and neither `||` nor `>|`).
staged : String -> String
staged text = "lit_stage " ++ pack (go Nothing Nothing (unpack text))
  where
    go : Maybe Char -> Maybe Char -> List Char -> List Char
    go _ _ [] = []
    go (Just q) before (c :: rest) = c :: go (if c == q then Nothing else Just q) (Just c) rest
    go Nothing before (c :: rest) =
      if c == '\'' || c == '"' then c :: go (Just c) (Just c) rest
      else if c == '|' && head' rest /= Just '|' && before /= Just '|' && before /= Just '>'
        then unpack "| lit_stage" ++ go Nothing (Just c) rest
      else c :: go Nothing (Just c) rest

||| A RUN line as the glue runs it: its substitutions made, a `%%` kept.
rewritten : (file, runtime, t : String) -> String -> String
rewritten file runtime t =
  staged
  . replaceAll "@LIT_PERCENT@" "%%"
  . replaceAll "%t" t
  . replaceAll "%s" file
  . replaceAll "%runtime" runtime
  . replaceAll "%cc" "lit_cc"
  . replaceAll "%differential" "lit_differential"
  . replaceAll "%status" "lit_status"
  . afterSeparators (literal "not " "lit_not ")
  . afterSeparators decision
  . statusUnchecked
  . afterSeparators (literal ("not " ++ checked) "not idris-mlir-opt ")
  . replaceAll "idris-mlir-opt " checked
  . replaceAll "%%" "@LIT_PERCENT@"

------------------------------------------------------------------------------
-- A failure named
------------------------------------------------------------------------------

||| A line split at its top-level `|`, `||`, `&&` and `;` outside quotes:
||| each command with the separator after it.
segments : String -> List (String, String)
segments line = go Nothing [<] (unpack line)
  where
    go : Maybe Char -> SnocList Char -> List Char -> List (String, String)
    go _ cur [] = [(pack (cur <>> []), "")]
    go (Just q) cur (c :: rest) = go (if c == q then Nothing else Just q) (cur :< c) rest
    go Nothing cur (c :: rest) =
      if c == '\'' || c == '"' then go (Just c) (cur :< c) rest
      else if c == '|' || c == ';' || (c == '&' && head' rest == Just '&') then
        case rest of
          (n :: more) => if c == '&' || n == '|'
                            then (pack (cur <>> []), pack [c, c]) :: go Nothing [<] more
                            else (pack (cur <>> []), singleton c) :: go Nothing [<] rest
          [] => (pack (cur <>> []), singleton c) :: go Nothing [<] []
      else go Nothing (cur :< c) rest

||| The files a command writes its stderr or a report to: after `2>` and
||| spaces, or after `--report=`, up to a space or `&`.
writtenFiles : String -> List String
writtenFiles s = go (unpack s)
  where
    file : List Char -> Maybe (String, List Char)
    file cs = case span (\c => c /= ' ' && c /= '&') cs of
      ([], _) => Nothing
      (f, after) => Just (pack f, after)

    go : List Char -> List String
    go [] = []
    go cs@(_ :: rest) =
      let found = (stripChars ['2', '>'] cs >>= file . dropWhile (== ' '))
                  <|> (stripChars (unpack "--report=") cs >>= file)
      in case found of
           Just (f, after) => f :: go after
           Nothing => go rest

||| How a RUN line asks a command to fail.
data Failing = ByNot | ByStatusOne

||| The command of the RUN line that is to fail (`not CMD`, `%status 1
||| CMD`) without naming the failure it expects, or nothing when every such
||| command names one. LATER is the text of the RUN lines after it. A
||| failure is named when the line checks which one it is: CMD is a
||| decision (diff, cmp, grep, test, ls: status 1 is the answer no); CMD is
||| idris-mlir under `%status` (its status is its verdict, by the driver's
||| one table of verdicts); CMD runs -verify-diagnostics; CMD asks
||| idr-expect for properties (a property must then fail); CMD's stderr is
||| piped on (`2>&1 |`); or CMD writes its stderr or a report (`2> FILE`,
||| `--report=FILE`) to a file the rest of the line or a later line reads.
||| Anything else would pass on any failure of CMD, a module that never
||| parsed included.
unnamed : (line, later : String) -> Maybe String
unnamed line later = go (segments line)
  where
    commandOf : List String -> Maybe (Failing, String)
    commandOf ("not" :: c :: _) = Just (ByNot, c)
    commandOf ("%status" :: "1" :: c :: _) = Just (ByStatusOne, c)
    commandOf _ = Nothing

    verdictOf : Failing -> String -> Bool
    verdictOf ByStatusOne cmd = cmd == "idris-mlir"
    verdictOf ByNot _ = False

    asksProperties : String -> Bool
    asksProperties s = isInfixOf "idr-expect=holds=" s || isInfixOf "idr-expect{holds=" s

    go : List (String, String) -> Maybe String
    go [] = Nothing
    go ((seg, sep) :: rest) = case commandOf (words seg) of
      Nothing => go rest
      Just (fails, path) =>
        let cmd = baseName path
            readsLater = \f => isInfixOf f (concatMap ((" " ++) . fst) rest ++ " " ++ later)
        in if elem cmd ["diff", "cmp", "grep", "test", "ls"]
              || verdictOf fails cmd
              || isInfixOf "-verify-diagnostics" seg
              || asksProperties seg
              || (isInfixOf "2>&1" seg && sep == "|")
              || any readsLater (writtenFiles seg)
              then go rest
              else Just (trim seg)

||| The idr-expect properties a command asks for, by name, from
||| `--idr-expect=holds=...` or `idr-expect{holds=...}` in its words (a pass
||| pipeline among them).
askedProperties : List String -> List String
askedProperties = concatMap (fromWord . unpack)
  where
    list : List Char -> (List Char, List Char)
    list = span (\c => c /= ' ' && c /= '}')

    fromWord : List Char -> List String
    fromWord [] = []
    fromWord cs@(_ :: rest) =
      case stripChars (unpack "idr-expect=holds=") cs <|> stripChars (unpack "idr-expect{holds=") cs of
        Just more =>
          let (requested, after) = list more in
          filter (/= "") (map (pack . takeWhile (/= '=') . unpack) (forget (split (== ',') (pack requested))))
          ++ fromWord after
        Nothing => fromWord rest

||| How a command that is to fail must fail: as `not` asks, any status from
||| 1 to 123 (a crash, a timeout, a command that could not run is no such
||| failure); or exactly the status `%status N` asks.
data Want = AnyFailure | Exactly Nat

||| `runtests --lit-fails WANT STATUS STDERR CMD...`: CMD, which ended with
||| STATUS and wrote STDERR, failed as WANT says: the line that says how it
||| did not, if it did not. A command that asks idr-expect for properties
||| and is to fail must fail by one of them: its stderr names `expected
||| <property>:` for one, so a module that never parsed, or a pass that
||| broke before the properties ran, is not the failure the line states.
export
litFails : (want : String) -> (status : Nat) -> (stderr : String) -> List String -> Maybe String
litFails wantText got errors command =
  let want = if wantText == "any" then AnyFailure else Exactly (fromMaybe 0 (parsePositive wantText))
      name = fromMaybe "" (head' command)
  in case want of
       AnyFailure =>
         if got == 0 || got > 123 then Just (name ++ " exited " ++ show got ++ ", expected a failure") else properties name
       Exactly n =>
         if got /= n then Just (name ++ " exited " ++ show got ++ ", expected " ++ show n)
         else if got == 0 then Nothing else properties name
  where
    properties : String -> Maybe String
    properties name = case askedProperties command of
      [] => Nothing
      asked => if any (\p => isInfixOf ("expected " ++ p ++ ":") errors) asked then Nothing
               else Just (name ++ " exited " ++ show got ++ ", but no property it asks for failed: " ++ unwords asked)

------------------------------------------------------------------------------
-- The RUN lines run
------------------------------------------------------------------------------

||| `lit FILE`: the RUN lines of a dialect test, run in order, a line each.
export
litLines : Env -> (file : String) -> IO (List String)
litLines e given = do
  let file = absolute e given
  text <- fromMaybe "" <$> readIfThere file
  -- The runtime is idris-mlir's (make build), asked for only by a test
  -- that names it.
  runtime <- if isInfixOf "%runtime" text
                then trailing . snd <$> captured e [e.tools.idrisMlir, "--print-runtime"] (Apart ToCaller)
                else pure ""
  case runLines text of
    [] => pure ["no RUN lines in " ++ baseName given]
    runs => go file runtime 1 Nothing runs
  where
    go : (file, runtime : String) -> Nat -> (failedAt : Maybe Nat) -> List String -> IO (List String)
    go _ _ _ _ [] = pure []
    go file runtime n (Just at) (_ :: rest) =
      (("RUN " ++ show n ++ ": not run, as RUN " ++ show at ++ " failed") ::) <$> go file runtime (S n) (Just at) rest
    go file runtime n Nothing (line :: rest) =
      case unnamed line (unlines rest) of
        Just command =>
          (\more => ("RUN " ++ show n ++ ": failed: " ++ line)
                    :: ("  | names no failure: `" ++ command ++ "` passes on any failure of its command")
                    :: more)
          <$> go file runtime (S n) (Just n) rest
        Nothing => do
          let failed = inWork e "lit.failed"
          let out = inWork e "lit.out"
          ignore (writeFile failed "")
          status <- run e.session (MkCommand LitLine [file, rewritten file runtime (inWork e "t") line]
                                             e.tools.work NoInput (ToFile out) WithOutput [])
          broken <- nonEmpty failed
          if succeeded status && not broken
             then (("RUN " ++ show n ++ ": ok") ::) <$> go file runtime (S n) Nothing rest
             else do
               shown <- firstLines 40 [failed, out]
               (\more => ("RUN " ++ show n ++ ": failed: " ++ line) :: indented shown ++ more)
                 <$> go file runtime (S n) (Just n) rest

||| Whether a transcript line says its RUN line held.
held : String -> Bool
held l = case stripChars (unpack "RUN ") (unpack l) of
  Just rest => case span isDigit rest of
    (_, cs) => cs == unpack ": ok"
  Nothing => False

||| `lit_fixture`: the dialect fixture the test's directory is, its one
||| .mlir file, its RUN lines run: one line when every one holds, else the
||| account of each line. Beside the module there is only what the runner
||| reads of any test (a suite or a targets file): a fixture is its module,
||| so anything else is a file no check reads.
export
litFixture : Env -> IO ()
litFixture e = do
  names <- globbed e.tools.here
  let modules = filter (isSuffixOf ".mlir") names
  let unread = filter (\n => not (isSuffixOf ".mlir" n || n == "suite" || n == "targets")) names
  case (unread, reverse modules) of
    (_ :: _, _) => tell e ("fixture: files no check reads:" ++ concatMap (" " ++) unread)
    ([], module' :: _) => do
      transcript <- litLines e module'
      if all held transcript then tell e "RUN lines: each holds" else tellAll e transcript
    ([], []) => litLines e "" >>= tellAll e

------------------------------------------------------------------------------
-- %differential
------------------------------------------------------------------------------

complain : String -> IO ()
complain line = ignore (fPutStrLn stderr line)

||| The bytes `printf '%b'` writes for a text: its escapes read (`\n`,
||| `\\`, `\0NNN` and the rest), a character above ASCII as its UTF-8.
printfBytes : List Char -> List Int
printfBytes [] = []
printfBytes ('\\' :: '\\' :: rest) = 92 :: printfBytes rest
printfBytes ('\\' :: 'a' :: rest) = 7 :: printfBytes rest
printfBytes ('\\' :: 'b' :: rest) = 8 :: printfBytes rest
printfBytes ('\\' :: 'c' :: _) = []
printfBytes ('\\' :: 'f' :: rest) = 12 :: printfBytes rest
printfBytes ('\\' :: 'n' :: rest) = 10 :: printfBytes rest
printfBytes ('\\' :: 'r' :: rest) = 13 :: printfBytes rest
printfBytes ('\\' :: 't' :: rest) = 9 :: printfBytes rest
printfBytes ('\\' :: 'v' :: rest) = 11 :: printfBytes rest
printfBytes ('\\' :: '0' :: rest) =
  let (ds, after) = octal 3 rest in
  mod (foldl (\n, d => n * 8 + (ord d - ord '0')) 0 ds) 256 :: printfBytes after
  where
    octal : Nat -> List Char -> (List Char, List Char)
    octal Z cs = ([], cs)
    octal (S k) (d :: cs) = if d >= '0' && d <= '7' then let (ds, after) = octal k cs in (d :: ds, after) else ([], d :: cs)
    octal (S k) [] = ([], [])
printfBytes (c :: rest) = utf8 (ord c) ++ printfBytes rest
  where
    utf8 : Int -> List Int
    utf8 n =
      if n < 0x80 then [n]
      else if n < 0x800 then [0xc0 + div n 64, 0x80 + mod n 64]
      else if n < 0x10000 then [0xe0 + div n 4096, 0x80 + mod (div n 64) 64, 0x80 + mod n 64]
      else [0xf0 + div n 262144, 0x80 + mod (div n 4096) 64, 0x80 + mod (div n 64) 64, 0x80 + mod n 64]

||| A file holding exactly the bytes.
writeBytes : String -> List Int -> IO ()
writeBytes path [] = ignore (writeFile path "")
writeBytes path bytes = do
  let size = cast {to = Int} (length bytes)
  Just buffer <- newBuffer size
    | Nothing => complain ("differential: no buffer for " ++ path)
  fill buffer 0 bytes
  ignore (writeBufferToFile path buffer size)
  where
    fill : Buffer -> Int -> List Int -> IO ()
    fill _ _ [] = pure ()
    fill b i (x :: xs) = do setBits8 b i (cast x); fill b (i + 1) xs

hex2 : Int -> String
hex2 n = pack [digit (div n 16), digit (mod n 16)]
  where
    digit : Int -> Char
    digit d = if d < 10 then chr (ord '0' + d) else chr (ord 'a' + d - 10)

||| The inputs %differential runs both programs on, a file each in DIR, and
||| each one's name with how a failure names it: the fixture's own, when it
||| declares them, one per `// STDIN: <text>` line, the input being <text>
||| with the escapes printf's %b reads (\n, \\, \0NNN); otherwise the empty
||| input and then every one-byte input, 0x00 to 0xff.
differentialInputs : (fixture, dir : String) -> IO (List (String, String))
differentialInputs fixture dir = do
  text <- fromMaybe "" <$> readIfThere fixture
  case mapMaybe (commented "STDIN:") (lines text) of
    [] => do
      writeBytes (dir ++ "/empty") []
      bytes <- for [0 .. 255] $ \b => do
        writeBytes (dir ++ "/" ++ hex2 b) [b]
        pure (hex2 b, "the byte 0x" ++ hex2 b)
      pure (("empty", "the empty input") :: bytes)
    declared => for (zip [1 .. length declared] declared) $ \(n, cs) => do
      let given = case cs of
                    (c :: rest) => if isSpace c then rest else cs
                    [] => []
      writeBytes (dir ++ "/" ++ show n) (printfBytes given)
      pure (show n, "'" ++ pack given ++ "'")

||| MODULE linked into the program `differential.NAME/prog` of the work
||| directory, as idris-mlir compiles a module from the stage its program
||| is at: the registered pipeline from that stage, which the tool reads
||| off the program (--idr-pipeline), then idris-mlir, which takes a module
||| of the LLVM dialect alone to LLVM as it is, compiled with the checked
||| runtime as the build prepared it and linked with it; COUNTER, MLIR's
||| debug counter over the actions the pipeline's passes take. The program,
||| or the lines that say why there is none.
lowered : Env -> (module', name : String) -> (counter : List String) -> IO (Either (List String) String)
lowered e module' name counter = do
  let dir = inWork e ("differential." ++ name)
  let log = inWork e "differential.log"
  made e dir
  lowering <- bounded e ([e.tools.idrisMlirOpt, "--mlir-disable-threading", module', "--idr-pipeline"]
                         ++ counter ++ ["-o", dir ++ "/lowered.mlir"]) (ToFile log) WithOutput
  if not (succeeded lowering)
     then failure log ("differential: " ++ baseName module' ++ " does not lower")
     else do
       object <- bounded e [e.tools.idrisMlir, "--num-threads=1", "--runtime=" ++ e.tools.checkedPrepared, "-c",
                            dir ++ "/lowered.mlir", "-o", dir ++ "/prog.o"]
                         (ToFile log) WithOutput
       linked <- if succeeded object
                    then linkProgram e [dir ++ "/prog.o", "-o", dir ++ "/prog", e.tools.checkedPrepared] (ToFile log) WithOutput
                    else pure object
       if succeeded linked then pure (Right (dir ++ "/prog"))
         else failure log ("differential: " ++ baseName module' ++ " does not compile")
  where
    failure : String -> String -> IO (Either (List String) String)
    failure log line = (\shown => Left (line :: indented shown)) <$> firstLines 40 [log]

||| The first 400 bytes of a run's output, a line each, prefixed.
excerpt : (lead, path : String) -> IO (List String)
excerpt lead path = map (lead ++) . lines . pack . take 400 . unpack <$> bytesIfThere path

||| `%differential BEFORE AFTER`: the programs of the modules BEFORE and
||| AFTER mean the same: on every input both end alike, the same status,
||| the same stdout and the same stderr, so two crashes of different causes
||| or sites differ, and a run that leaks a cell ends as the checked
||| runtime's internal error, which differs from a clean return. BEFORE is
||| lowered with every optimization's actions skipped (an optimization's
||| transforms only make code faster or smaller, so with all of them
||| skipped the program is the reference the optimized one must agree
||| with, sharing with it only the passes the pipeline needs); AFTER as the
||| pipeline lowers it. A pass that changes what the program does fails on
||| the first input where they differ, which is named on stderr with both
||| outcomes. Both programs are named `prog`, so the runtime's lines name
||| them alike. Its status: 0 when they agree, 2 when not given two
||| modules, 1 otherwise.
export
litDifferential : Env -> (fixture : String) -> List String -> IO Nat
litDifferential e fixture [before, after] = do
  let inputs = inWork e "differential.in"
  there <- isDirectory inputs
  when (not there) $ made e inputs
  list <- differentialInputs fixture inputs
  for_ ["before", "after"] $ \side => do
    removed e (inWork e ("differential." ++ side))
    removed e (inWork e ("differential." ++ side ++ ".runs"))
    made e (inWork e ("differential." ++ side ++ ".runs"))
  (status, tags) <- captured e [e.tools.idrisMlirOpt, "--idr-action-tags"] (Apart ToCaller)
  case (succeeded status, words tags) of
    (True, tagged@(_ :: _)) => do
      let counter = ["--mlir-debug-counter=" ++ joinBy "," (map (++ "-count=0") tagged)]
      Right reference <- lowered e before "before" counter
        | Left why => do traverse_ complain why; pure 1
      Right checkedProgram <- lowered e after "after" []
        | Left why => do traverse_ complain why; pure 1
      ended <- for [("before", reference), ("after", checkedProgram)] $ \(side, program) =>
        runAll side program inputs (map fst list)
      if not (all id ended)
         then do
           complain ("differential: the program of " ++ baseName before ++ " or " ++ baseName after ++ " did not end on every input")
           pure 1
         else compareRuns list
    _ => do complain "differential: idris-mlir-opt names no action tags"; pure 1
  where
    -- Each run of a program is a process of a few milliseconds, bounded;
    -- one that the bound ends ends them all.
    runAll : String -> String -> String -> List String -> IO Bool
    runAll _ _ _ [] = pure True
    runAll side program inputs (name :: rest) = do
      let runs = inWork e ("differential." ++ side ++ ".runs/" ++ name)
      status <- boundedOn e [program] (FromFile (inputs ++ "/" ++ name)) (ToFile (runs ++ ".out")) (Apart (ToFile (runs ++ ".err")))
      ignore (writeFile (runs ++ ".status") (show (raw status) ++ "\n"))
      if raw status == 124 then pure False else runAll side program inputs rest

    outcome : String -> String -> IO (List String)
    outcome runs module' = do
      status <- trailing . fromMaybe "" <$> readIfThere (runs ++ ".status")
      out <- excerpt "  |   " (runs ++ ".out")
      err <- excerpt "  |   ! " (runs ++ ".err")
      pure (("  | " ++ baseName module' ++ ": exit " ++ status ++ ", stdout and stderr:") :: out ++ err)

    compareRuns : List (String, String) -> IO Nat
    compareRuns [] = pure 0
    compareRuns ((name, what) :: rest) = do
      let b = inWork e ("differential.before.runs/" ++ name)
      let a = inWork e ("differential.after.runs/" ++ name)
      alike <- allM [sameBytes e (b ++ ".status") (a ++ ".status"), sameBytes e (b ++ ".out") (a ++ ".out"),
                     sameBytes e (b ++ ".err") (a ++ ".err")]
      if alike then compareRuns rest else do
        complain ("differential: " ++ baseName before ++ " and " ++ baseName after ++ " differ on " ++ what)
        traverse_ complain !(outcome b before)
        traverse_ complain !(outcome a after)
        pure 1
      where
        allM : List (IO Bool) -> IO Bool
        allM [] = pure True
        allM (m :: ms) = do
          ok <- m
          if ok then allM ms else pure False
litDifferential e _ modules = do
  complain ("differential: takes two modules, not " ++ show (length modules))
  pure 2
