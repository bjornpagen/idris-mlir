||| PROF-HEAP-5 after the fact. Arity raising (ELIM-G-5) moves the code that
||| builds an IO action or function to where the action runs. That is sound
||| only for code that cannot crash, loop or act. `Simplify` specializes
||| optimistically and records what it moved; this pass checks it on the
||| finished program.
|||
||| Which functions are safe is a greatest fixpoint: assume every total
||| function is, and drop those whose code is not, until nothing changes.
||| Recursion between specializations is why it must be the greatest.
module IdrisMLIR.Simplify.Safety

import IdrisMLIR.Code
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Rule
import IdrisMLIR.Types

import Data.List
import Data.SortedMap
import Data.SortedSet

%default total

||| The functions that terminate and cannot crash or act.
export
safeFns : List CFn -> SortedSet FnId
safeFns fns = go (length fns) (fromList [f.id | f <- fns, f.terminating])
  where
    step : SortedSet FnId -> SortedSet FnId
    step s = fromList [f.id | f <- fns, contains f.id s, safeCode (`contains` s) f.body]
    go : Nat -> SortedSet FnId -> SortedSet FnId
    go Z s = s
    go (S k) s = let s' = step s in
                 if length (Prelude.toList s') == length (Prelude.toList s) then s else go k s'

||| DIAG-HEAP-1: what blocks arity raising.
blocking : SortedMap FnId CFn -> Op () -> String
blocking fns (OPrim (IntOp Div _) _) = "a division"
blocking fns (OPrim (IntOp Mod _) _) = "a modulus"
blocking fns (OCall f _) = "a call to " ++ maybe (show f) (.idrisName) (lookup f fns)
blocking fns (OIO op _ _) = "the IO operation " ++ show op
blocking fns (OCrash _) = "a missing case"
blocking fns _ = "an operation"

||| Checks the operations moved into prefixes, in the order they were made.
||| Moving is observable only if an effect happens between building an
||| action and running it: a raised function none of whose actions is run
||| after such an effect may move anything.
export
checkMoved : List CFn -> List (FnId, Loc, Op ()) -> List (FnId, Loc, Bool) -> Either Diag ()
checkMoved fns moved runs = do
  let safe = safeFns fns
  let byId = fromList [(f.id, f) | f <- fns]
  let delayed = fromList (map (\(f, _, _) => f) (filter (\(_, _, late) => late) runs))
  for_ moved $ \(owner, l, op) =>
    when (contains owner delayed && not (safeOp (`contains` safe) op)) $
      Left (MkDiag ProfHeap5 "Simplify" l
              ("arity raising is blocked by " ++ blocking byId op ++ ", which may crash or not " ++
               "terminate, and would move from where an IO action or function is built to " ++
               "where it runs (DIAG-HEAP-1)"))
