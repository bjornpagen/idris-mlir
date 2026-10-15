-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A closed term read under its binders, each binder given a value.
|||
||| Reading a telescope one binder at a time by substituting its value into
||| the rest gives a term the totality checker cannot see is smaller. So a
||| reader walks the scope as it is, open in the binders passed, and keeps
||| their values: the term a binder's type or the result stands for is the
||| scope's term with every value substituted at once, which is the term the
||| substitutions one at a time would have given.
module IdrisMLIR.Frontend.Translate.Given

import Core.Name.Scoped
import Core.TT
import Core.TT.Subst
import Core.TT.Term.Subst
import Libraries.Data.List.SizeOf

import Data.List

%default total

||| The values of the binders a reader has passed, the innermost first.
export
record Given (vars : Scope) where
  constructor MkGiven
  size : SizeOf vars
  values : SubstEnv vars Scope.empty

||| No binder passed yet.
export
none : Given Scope.empty
none = MkGiven zero []

||| One more binder passed, with its value.
export
give : ClosedTerm -> Given vars -> Given (Scope.bind vars x)
give v (MkGiven s vs) = MkGiven (suc s) (v :: vs)

||| The closed term a term in the scope stands for.
export
close : {0 vars : Scope} -> Given vars -> Term vars -> ClosedTerm
close (MkGiven s vs) t = substs s vs (rewrite appendNilRightNeutral vars in t)
