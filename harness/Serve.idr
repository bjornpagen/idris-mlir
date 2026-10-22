-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The runner's one way of running a tool. The runner creates no process:
||| it builds and runs under both hosts, and idris-mlir refuses process
||| creation. So a check that needs a tool runs as a session with the glue
||| that starts it (`serve`, harness/lib/harness.sh):
|||
|||     runtests --serve <dir> <mode> <argument>...
|||
||| <dir> holds two channels the glue made, `ask` and `answer`. For each
||| command, the runner writes its words into <dir>/argv, one a line, and on
||| `ask` a line naming the directory it runs in, its standard input and
||| its two outputs, each a path or `-` for the stream the glue's caller
||| gave it (and `&` for a standard error that joins the standard output);
||| the glue starts it and answers on `answer` with its status
||| and, for a process a signal ended, the signal's name as the host names
||| it. A command's first word is a function of the glue: `bounded`, for a
||| tool, which ends it and everything it starts at the test's step limit,
||| so a hang is a failure and never a wait; or `lit_line`, for a RUN
||| line, whose stages bound each tool they start. Commands run one at a time,
||| each answered before the next is asked, so one argv file serves them
||| all.
module Serve

import Data.List
import Data.List1
import Data.String
import System
import System.File

%default covering

||| Where a command reads its standard input from: a file, or nothing.
public export
data Input = FromFile String | NoInput

||| Where an output of a command goes: a file, or the stream the glue's
||| caller gave it (the test's transcript, for standard output).
public export
data Output = ToFile String | ToCaller

||| Where a command's standard error goes: apart from its standard output,
||| or with it, interleaved as written (a shell's `2>&1`).
public export
data ErrorOutput = Apart Output | WithOutput

||| The function of the glue that starts what a command runs: `bounded`,
||| for a tool; `pinned_idris`, for the pinned Idris on its own prefix,
||| bounded; or `lit_line`, for a RUN line of a dialect test, a line of
||| shell run where the glue's functions are its commands, whose stages
||| bound each tool they start.
public export
data Glue = Bounded | PinnedIdris | LitLine

glueWord : Glue -> String
glueWord Bounded = "bounded"
glueWord PinnedIdris = "pinned_idris"
glueWord LitLine = "lit_line"

||| A command: the glue that starts it and its words, the directory it runs
||| in, its input and its two outputs.
public export
record Command where
  constructor MkCommand
  glue : Glue
  arguments : List String
  cwd : String
  input : Input
  out : Output
  err : ErrorOutput

||| How a command ended, as the shell reports it: its exit code, or the
||| signal that ended it, named as the host names it, with the status the
||| shell gives such a process (128 and the signal's number). A command the
||| step limit ended exits 124, as `bounded` reports it, having said so on
||| its standard error.
public export
data Status = Code Nat | Signal Nat String

||| The status as the shell's number.
export
raw : Status -> Nat
raw (Code n) = n
raw (Signal n _) = n

||| Whether the command exited 0.
export
succeeded : Status -> Bool
succeeded (Code Z) = True
succeeded _ = False

||| The status as a case's ending is compared with it (Facts.statusLine):
||| `code <n>`, or `signal <name>`.
export
statusWords : Status -> String
statusWords (Code n) = "code " ++ show n
statusWords (Signal _ name) = "signal " ++ name

||| A session with the glue: its directory and its two channels.
export
record Session where
  constructor MkSession
  dir : String
  ask : File
  answer : File

inputPath : Input -> String
inputPath (FromFile p) = p
inputPath NoInput = "/dev/null"

outputPath : Output -> String
outputPath (ToFile p) = p
outputPath ToCaller = "-"

errorPath : ErrorOutput -> String
errorPath (Apart o) = outputPath o
errorPath WithOutput = "&"

||| The directory of a session, where the runner keeps what a command
||| leaves for it to read.
export
sessionDir : Session -> String
sessionDir s = s.dir

||| What the channel can carry: a word of the argv file holds no line's
||| end, and a field of the request line no tab either. Paths and
||| arguments are the harness's own, so meeting one that breaks this is the
||| harness's fault, said and fatal.
carriedWord : String -> Bool
carriedWord w = not (elem '\n' (unpack w))

carriedField : String -> Bool
carriedField w = carriedWord w && not (elem '\t' (unpack w))

statusOf : String -> Maybe Status
statusOf line = case words line of
  [n, "-"] => Code <$> parsePositive n
  [n, name] => (\k => Signal k name) <$> parsePositive n
  _ => Nothing

||| Runs a command through the glue, and how it ended.
export
run : Session -> Command -> IO Status
run s c = do
  let fields = [c.cwd, inputPath c.input, outputPath c.out, errorPath c.err]
  let argv = glueWord c.glue :: c.arguments
  when (not (all carriedWord argv && all carriedField fields)) $
    die ("serve: a command the channel cannot carry: " ++ unwords argv)
  Right () <- writeFile (s.dir ++ "/argv") (unlines argv)
    | Left err => die ("serve: " ++ s.dir ++ "/argv: " ++ show err)
  -- What the runner printed goes before what the command prints, when both
  -- write to the caller's stream.
  fflush stdout
  Right () <- fPutStrLn s.ask (joinBy "\t" fields)
    | Left err => die ("serve: the channel: " ++ show err)
  fflush s.ask
  Right line <- fGetLine s.answer
    | Left err => die ("serve: the channel: " ++ show err)
  maybe (die ("serve: not a status: " ++ line)) pure (statusOf (trim line))

||| A session over the channels in `dir`, opened in the order the glue opens
||| them (`ask`, then `answer`), so neither waits on the other forever.
export
withSession : (dir : String) -> (Session -> IO a) -> IO a
withSession dir act = do
  Right ask <- openFile (dir ++ "/ask") WriteTruncate
    | Left err => die ("serve: " ++ dir ++ "/ask: " ++ show err)
  Right answer <- openFile (dir ++ "/answer") Read
    | Left err => die ("serve: " ++ dir ++ "/answer: " ++ show err)
  result <- act (MkSession dir ask answer)
  closeFile ask
  closeFile answer
  pure result
