-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the harness reads of the dialect's specification, the one source
||| of the closed sets the runtime, the compiler and the tests share: how a
||| run ends (the runtime's endings and the status a parent reads of each)
||| and the rules a refusal names. This is the one module of the harness
||| that names the specification's declarations; the rest of the harness
||| asks it, and copies none of them.
module Facts

import Data.Fin
import Data.List
import Data.List1
import Data.String

import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Core.Text
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

||| The signal POSIX names for an ending's signal, as the shell's `kill -l`
||| names the signal of a status above 128: the one fact of the platform
||| the harness states, the same on every target.
posixName : Signal -> String
posixName Abort = "ABRT"
posixName BrokenPipe = "PIPE"

||| How a run that ends with `e` must end, as lib/e2e.sh compares it with
||| what the shell reported: `code <n>`, or `signal <name>`.
export
statusLine : Ending -> String
statusLine e = case status e of
  Code n => "code " ++ show (finToNat n)
  Raised s => "signal " ++ posixName s

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

||| Every rule's line for the scripts that read the rules (lib/rules.sh,
||| `runtests --rules`): its phrase, a tab, and its category's words.
export
ruleLines : List String
ruleLines = map (\r => phraseOf r ++ "\t" ++ caseWords categoryClosed (category r)) (forget everyRule)
