-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the harness reads of the dialect's specification's closed sets,
||| the one source the runtime, the compiler and the tests share: how a run
||| ends (the runtime's endings, the status a parent reads of each, and a
||| crash's cause and phrase), what a compilation comes to, and the rules a
||| refusal names. The rest of the harness asks it for these, and copies
||| none of them.
module Facts

import Data.Fin
import Data.List
import Data.List1
import Data.String

import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Verdict
import IdrisMLIR.Spec.Runtime.Endings

%default total

------------------------------------------------------------------------------
-- Endings
------------------------------------------------------------------------------

||| The words a closed set's case is written with.
caseWords : Closed a -> a -> String
caseWords set x = spellingText (set.describe x)

||| The case of a closed set written as `text`.
caseOf : Closed a -> String -> Maybe a
caseOf set text = find (\x => caseWords set x == text) (forget set.every)

||| An exit status, written as its number.
statusOf : String -> Maybe (Fin 256)
statusOf "0" = Just 0
statusOf n = parsePositive {a = Nat} n >>= \k => natToFin k 256

||| An ending as a case's `expected-ending` writes it, one line: the
||| specification's words for each ending that has them (the fixed
||| statuses', the causes', the reasons a machine cannot run a program, the
||| internal errors', the signals'), and a number for an exit:
|||
|||     returned | exited <n> | crashed <cause> | crashed said
|||     | crashed unreportable | out_of_memory | cannot_run <reason>
|||     | broken_pipe | internal_error <internal>
|||
||| An ending names no site: a crash's site is in the runtime's line on
||| stderr, which the case commits whole (`expected-stderr`).
export
readEnding : String -> Maybe Ending
readEnding text = case words text of
  ["exited", n] => Exited <$> statusOf n
  [w] => case caseOf fixedClosed w of
    Just ReturnedStatus => Just Returned
    Just OutOfMemoryStatus => Just OutOfMemory
    _ => case caseOf signalClosed w of
      Just BrokenPipe => Just Piped
      _ => Nothing
  [w, x] => case caseOf fixedClosed w of
    Just CrashedStatus =>
      if x == "said" then Just (Crashed Said)
      else if x == "unreportable" then Just (Crashed Unreportable)
      else Crashed . Failed <$> caseOf causeClosed x
    Just CannotRunStatus => CannotRun <$> caseOf unrunnableClosed x
    _ => if w == "internal_error" then InternalError <$> caseOf internalClosed x else Nothing
  _ => Nothing

||| The ending a case's `expected-ending` states; a missing file is a run
||| that returns.
export
endingOf : (text : Maybe String) -> Either String Ending
endingOf Nothing = Right Returned
endingOf (Just text) =
  let line = trim text in
  maybe (Left ("expected-ending: not an ending: " ++ line)) Right (readEnding line)

||| A crash of a cause, as a case's `expected-ending` writes it: what
||| `readEnding` reads back as the same crash.
export
crashedText : Cause -> String
crashedText c = caseWords fixedClosed CrashedStatus ++ " " ++ caseWords causeClosed c

||| What the runtime's message says of a cause after its site: its phrase,
||| from the table the runtime is printed.
export
causePhraseOf : Cause -> String
causePhraseOf c = lineText (causeClosed.describe c).doc

||| The signal POSIX names for an ending's signal, as the shell's `kill -l`
||| names the signal of a status above 128: the one fact of the platform
||| the harness states, the same on every target.
posixName : Signal -> String
posixName Abort = "ABRT"
posixName BrokenPipe = "PIPE"

||| How a parent saw a run end: by a status an ending gives (an exit
||| status, or a signal an ending raises), the specification's, compared by
||| value; or by a signal no ending raises, which no case expects (a fault
||| of the program), named as the host names it, for the message alone.
public export
data Seen = Saw Status | SawUnraised String

||| How a parent sees a run that ends with `e` end.
export
seenAs : Ending -> Seen
seenAs e = Saw (status e)

||| How a parent saw a run end that exited with status N.
export
sawExit : Fin 256 -> Seen
sawExit n = Saw (Code n)

||| How a parent saw a run end that the host reports ended by the signal it
||| names NAME: the signal of an ending POSIX names so, or another. The one
||| place the host's name for a signal is read.
export
sawSignal : (name : String) -> Seen
sawSignal name =
  maybe (SawUnraised name) (Saw . Raised) (find (\s => posixName s == name) (forget signalClosed.every))

||| Two statuses are one: the same exit status, or the same signal, a
||| signal known by its place in the specification's set of them.
sameStatus : Status -> Status -> Bool
sameStatus (Code m) (Code n) = m == n
sameStatus (Raised a) (Raised b) = position signalClosed a == position signalClosed b
sameStatus _ _ = False

||| Whether a run seen to end as SEEN ended as a run that ends with `e`
||| does.
export
sawEnding : (seen : Seen) -> (e : Ending) -> Bool
sawEnding (Saw s) e = sameStatus s (status e)
sawEnding (SawUnraised _) _ = False

||| A status as a message and a script write it: `code <n>`, or
||| `signal <name>`, the signal by the name POSIX gives it.
statusText : Status -> String
statusText (Code n) = "code " ++ show (finToNat n)
statusText (Raised s) = "signal " ++ posixName s

||| How a parent saw a run end, as a message writes it.
export
seenText : Seen -> String
seenText (Saw s) = statusText s
seenText (SawUnraised name) = "signal " ++ name

||| The status a run that ends with `e` ends with, as a message writes it.
export
statusLine : Ending -> String
statusLine e = statusText (status e)

||| The status a run that ends as TEXT says ends with, as `statusLine`
||| writes it (`runtests --ending-status`); none for text that is no
||| ending. So a script that tells an ending by its status reads the
||| status from the specification's table.
export
endingStatus : (text : String) -> Maybe String
endingStatus text = statusLine <$> readEnding text

------------------------------------------------------------------------------
-- Verdicts
------------------------------------------------------------------------------

||| A compilation's verdict as its report writes it, read by the
||| specification's spelling of each.
export
readVerdict : String -> Maybe CompilerVerdict
readVerdict text = caseOf verdictClosed (trim text)

||| A verdict as a report writes it.
export
verdictWords : CompilerVerdict -> String
verdictWords = caseWords verdictClosed

------------------------------------------------------------------------------
-- Rules
------------------------------------------------------------------------------

||| Who judges a refusal by a rule: this compiler's rules, or Idris's own
||| errors, which the report carries under the rules of their category.
public export
data Judge = Ours | Idris

||| A rule's phrase, as a refusal and a test's header write it.
export
phraseOf : SomeRule -> String
phraseOf (Refusal r) = joinBy " " (map wordText (forget (phrase r)))

||| The rule whose phrase is `p`.
export
ruleNamed : String -> Maybe SomeRule
ruleNamed p = find (\r => phraseOf r == p) (forget everyRule)

||| The rule the report writes as `field`: its phrase, each space a dash.
export
ruleOfField : String -> Maybe SomeRule
ruleOfField field = ruleNamed (pack (map (\c => if c == '-' then ' ' else c) (unpack field)))

export
judge : SomeRule -> Judge
judge r = case category r of
  UserError => Idris
  _ => Ours

||| Every rule's line for the scripts that read the rules (`runtests
||| --rules`): its phrase, a tab, and its category's words: a construct
||| whose choices no compile-time analysis bounds, what the language this
||| compiler implements does not have, or a program Idris itself rejects,
||| whose refusal carries Idris's own message.
export
ruleLines : List String
ruleLines = map (\r => phraseOf r ++ "\t" ++ caseWords categoryClosed (category r)) (forget everyRule)

||| `runtests --rule-phrases [CATEGORY]`: the phrase of every rule, or of
||| every rule of the category its words name.
export
rulePhrases : Maybe String -> List String
rulePhrases wanted =
  map phraseOf (filter (\r => maybe True (== caseWords categoryClosed (category r)) wanted) (forget everyRule))

||| `runtests --rule-category PHRASE`: the words of the category of the rule
||| whose phrase is PHRASE, if a rule has it.
export
categoryOfPhrase : String -> Maybe String
categoryOfPhrase p = caseWords categoryClosed . category <$> ruleNamed p

||| The rule a call the in-place promise binds is refused by when its
||| argument is not exclusive, as the linear generator predicts it.
export
uniqueness : SomeRule
uniqueness = Refusal Uniqueness
