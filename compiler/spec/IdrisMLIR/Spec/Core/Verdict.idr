-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What a compilation comes to, each verdict worse than the one before, so
||| the worst one seen is the compilation's: accepted, no error; refused, an
||| error that names a rule, the program's; environment, a tool the
||| compilation runs could not run or did not finish, the installation's, so
||| the program was never judged; internal, any other error, the compiler's.
||| The driver writes a verdict into its report by its spelling and exits
||| with its status; the harness reads the spelling back into the case and
||| knows the status from the same row. Nothing compares a verdict as text.
module IdrisMLIR.Spec.Core.Verdict

import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Core.Cpp

import Data.List.Elem
import Data.List1

%default total

||| The Idris names carry the set's name, since the harness, which reads
||| them, has a verdict of its own and the runtime's endings an `Internal`.
public export
data CompilerVerdict = VerdictAccepted | VerdictRefused | VerdictEnvironment | VerdictInternal

public export
verdictClosed : Closed CompilerVerdict
verdictClosed = MkClosed
  { name = ident "Verdict"
  , shape = OneOf
  , every = VerdictAccepted ::: [VerdictRefused, VerdictEnvironment, VerdictInternal]
  , complete = \case
      VerdictAccepted => Here
      VerdictRefused => There Here
      VerdictEnvironment => There (There Here)
      VerdictInternal => There (There (There Here))
  , describe = \case
      VerdictAccepted => MkCase (ident "Accepted") (word "accepted" ::: []) (line "no error: the program compiled")
      VerdictRefused => MkCase (ident "Refused") (word "refused" ::: []) (line "an error that names a rule, the program's")
      VerdictEnvironment => MkCase (ident "Environment") (word "environment" ::: []) (line "a tool the compilation runs could not run or did not finish")
      VerdictInternal => MkCase (ident "Internal") (word "internal" ::: []) (line "any other error, the compiler's")
  , doc = brief (line "what a compilation comes to, each verdict worse than the one before")
  }

||| The status the compiler exits with on a verdict: a refusal's is the one
||| a program's error gives, and an error that is not the program's is the
||| compiler's failure, whichever tool it was.
public export
exitStatus : CompilerVerdict -> Nat
exitStatus VerdictAccepted = 0
exitStatus VerdictRefused = 3
exitStatus VerdictEnvironment = 1
exitStatus VerdictInternal = 1

||| The verdicts and their statuses, which the driver reads by load.
public export
verdictHeader : Header
verdictHeader = MkHeader (ident "Verdict")
  [ ( ident "idr" ::: [ident "driver"]
    , [ TableOf (table verdictClosed
          [ MkColumn (ident "exitStatus") Unsigned8 (\v => IntCell (natToInteger (exitStatus v)))
              (line "the status the compiler exits with") ]) ] ) ]
  (brief (line "what a compilation comes to, and the status it exits with"))
