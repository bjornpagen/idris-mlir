||| Loops as recursive join points (CORE-LOOP-1, SEM-RES-2).
|||
||| A self tail call is a jump back to the start of the function: the body
||| becomes a join point that the function enters once and that each self
||| tail call jumps to. This is where loops appear in first-order Core; the
||| memory plan's regions are these join points, and `Emit` writes them as
||| blocks that branch back to themselves.
|||
||| First, a join point whose body returns exactly its parameters is the
||| return itself: a jump to it is a return. That makes a call whose result
||| a match's alternatives pass straight out a tail call.
module IdrisMLIR.Code.Loops

import IdrisMLIR.Code
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Types

import Data.List
import Data.SortedMap

%default total

||| Jumps to a join point become returns.
returning : JoinId -> Code p -> Code p
returning j = transform $ \c => case c of
  Jump l k as => if k == j then Ret l as else c
  _ => c

||| Removes join points whose body returns exactly their parameters.
export
dropReturns : Code p -> Code p
dropReturns = transform $ \c => case c of
  Join _ j ps (Ret _ as) k => if as == map (AVar . (.var)) ps then returning j k else c
  _ => c

||| Is this a call of `f` whose results are returned unchanged?
tailCall : FnId -> Code p -> Maybe (Loc, List Atom)
tailCall f (Let l rs (OCall g as) (Ret _ out)) =
  if g == f && out == map (AVar . (.var)) rs then Just (l, as) else Nothing
tailCall _ _ = Nothing

||| Self tail calls become jumps to a join point.
jumps : FnId -> JoinId -> Code p -> Code p
jumps f j = transform $ \c => case tailCall f c of
  Just (l, as) => Jump l j as
  Nothing => c

hasTailCall : FnId -> Code p -> Bool
hasTailCall f = para alg
  where
    alg : CodeF q (Code q, Bool) -> Bool
    alg layer@(LetF l rs o (k, _)) = maybe False (const True) (tailCall f (Let l rs o k))
    alg other = any snd other

||| One more than every variable and join point a body and its parameters
||| use.
supply : List Param -> Code p -> Nat
supply ps body = S (foldl max 0 (map (.index) (map (.var) ps ++ binders body) ++
                                  map (.index) (joins body)))

||| A function whose body calls itself in tail position loops instead.
export
loop : CFn p -> CFn p
loop fn =
  let body = dropReturns fn.body in
  if not (hasTailCall fn.id body) then { body := body } fn else
    let next = supply fn.params body
        j = MkJoinId next
        fresh = zipWith (\i, p => { var := MkVarId (next + S i) } p) [0 .. length fn.params] fn.params
        names = the (SortedMap VarId VarId) (fromList (zip (map (.var) fn.params) (map (.var) fresh)))
        inner = jumps fn.id j (rename names body)
    in { body := Join fn.loc j fresh inner (Jump fn.loc j (map (AVar . (.var)) fn.params)) } fn

||| Every function of a program.
export
loopify : Target p -> Target p
loopify t = { fns $= map loop } t
