||| Print erased IR as MLIR text using upstream dialects (func, arith, scf).
module IdrisMLIR.Emit

import IdrisMLIR.IR

import Control.Monad.State
import Data.List
import Data.SortedMap
import Data.String

%default covering

record St where
  constructor MkSt
  next : Nat
  out : SnocList String

Emit : Type -> Type
Emit = StateT St (Either String)

Sigs : Type
Sigs = SortedMap String (List IntTy, IntTy)

Env : Type
Env = SortedMap Nat (String, IntTy)

failWith : String -> Emit a
failWith = lift . Left

fresh : Emit String
fresh = do
  st <- get
  put ({ next $= S } st)
  pure ("%t" ++ show st.next)

line : Nat -> String -> Emit ()
line depth text = modify { out $= (:< (pack (replicate (2 * depth) ' ') ++ text)) }

mlirType : IntTy -> String
mlirType t = "i" ++ show (width t)

||| MLIR bare identifiers are [A-Za-z_][A-Za-z0-9_$.]*.
export
symbol : String -> String
symbol name = "@" ++ start (concatMap escape (unpack name))
  where
    escape : Char -> String
    escape c = if isAlphaNum c || c == '_' || c == '.'
                  then singleton c
                  else "$" ++ show (ord c) ++ "$"

    start : String -> String
    start s = case unpack s of
      (c :: _) => if isAlpha c || c == '_' then s else "_" ++ s
      [] => "_"

||| Two's-complement value of `n` at the type's width, as arith.constant expects.
literal : IntTy -> Integer -> Integer
literal t n =
  let size = pow 2 (width t)
      m = n `mod` size
  in if m >= size `div` 2 then m - size else m
  where
    pow : Integer -> Nat -> Integer
    pow b Z = 1
    pow b (S k) = b * pow b k

predicate : PrimOp -> Bool -> String
predicate Lt s = if s then "slt" else "ult"
predicate Lte s = if s then "sle" else "ule"
predicate Gte s = if s then "sge" else "uge"
predicate Gt s = if s then "sgt" else "ugt"
predicate _ _ = "eq"

arithOp : PrimOp -> String
arithOp Add = "arith.addi"
arithOp Sub = "arith.subi"
arithOp _ = "arith.muli"

typeOf : Sigs -> SortedMap Nat IntTy -> Expr -> Either String IntTy
typeOf _ env (Var v) = maybe (Left ("unbound variable %" ++ show v)) Right (lookup v env)
typeOf _ _ (Lit t _) = Right t
typeOf _ _ (Prim op t _ _) = Right (if isComparison op then IdrisInt else t)
typeOf _ _ (Cast _ to _) = Right to
typeOf sigs _ (Call fn _) = maybe (Left ("unknown function " ++ fn)) (Right . snd) (lookup fn sigs)
typeOf sigs env (Let v _ e body) = do
  t <- typeOf sigs env e
  typeOf sigs (insert v t env) body
typeOf sigs env (Switch _ _ _ def) = typeOf sigs env def
typeOf _ _ CompileTime = Left "compile-time-only value after erasure"

expr : Sigs -> Nat -> Env -> Expr -> Emit (String, IntTy)
expr _ _ env (Var v) = case lookup v env of
  Just r => pure r
  Nothing => failWith ("unbound variable %" ++ show v)
expr _ depth _ (Lit t n) = do
  r <- fresh
  line depth (r ++ " = arith.constant " ++ show (literal t n) ++ " : " ++ mlirType t)
  pure (r, t)
expr sigs depth env (Prim op t a b) = do
  (x, _) <- expr sigs depth env a
  (y, _) <- expr sigs depth env b
  let operands = x ++ ", " ++ y ++ " : " ++ mlirType t
  if isComparison op
     then do
       c <- fresh
       line depth (c ++ " = arith.cmpi " ++ predicate op (signed t) ++ ", " ++ operands)
       r <- fresh
       line depth (r ++ " = arith.extui " ++ c ++ " : i1 to i64")
       pure (r, IdrisInt)
     else do
       r <- fresh
       line depth (r ++ " = " ++ arithOp op ++ " " ++ operands)
       pure (r, t)
expr sigs depth env (Cast from to e) = do
  (x, _) <- expr sigs depth env e
  if width from == width to
     then pure (x, to)
     else do
       let op = if width from > width to then "arith.trunci"
                else if signed from then "arith.extsi" else "arith.extui"
       r <- fresh
       line depth (r ++ " = " ++ op ++ " " ++ x ++ " : " ++ mlirType from ++ " to " ++ mlirType to)
       pure (r, to)
expr sigs depth env (Call fn args) = do
  xs <- traverse (expr sigs depth env) args
  let Just (params, result) = lookup fn sigs
    | Nothing => failWith ("unknown function " ++ fn)
  r <- fresh
  line depth (r ++ " = func.call " ++ symbol fn ++ "(" ++ joinBy ", " (map fst xs) ++ ") : ("
              ++ joinBy ", " (map mlirType params) ++ ") -> " ++ mlirType result)
  pure (r, result)
expr sigs depth env (Let v _ e body) = do
  x <- expr sigs depth env e
  expr sigs depth (insert v x env) body
expr sigs depth env (Switch t scrutinee alts def) = do
  (s, _) <- expr sigs depth env scrutinee
  result <- lift (typeOf sigs (map snd env) def)
  switch s result depth alts
  where
    switch : String -> IntTy -> Nat -> List (Integer, Expr) -> Emit (String, IntTy)
    switch _ _ depth [] = expr sigs depth env def
    switch s result depth ((n, rhs) :: rest) = do
      k <- fresh
      line depth (k ++ " = arith.constant " ++ show (literal t n) ++ " : " ++ mlirType t)
      c <- fresh
      line depth (c ++ " = arith.cmpi eq, " ++ s ++ ", " ++ k ++ " : " ++ mlirType t)
      r <- fresh
      line depth (r ++ " = scf.if " ++ c ++ " -> (" ++ mlirType result ++ ") {")
      (x, _) <- expr sigs (S depth) env rhs
      line (S depth) ("scf.yield " ++ x ++ " : " ++ mlirType result)
      line depth "} else {"
      (y, _) <- switch s result (S depth) rest
      line (S depth) ("scf.yield " ++ y ++ " : " ++ mlirType result)
      line depth "}"
      pure (r, result)
expr _ _ _ CompileTime = failWith "compile-time-only value after erasure"

function : Sigs -> Fn -> Emit ()
function sigs fn = do
  let Just (types, _) = lookup fn.name sigs
    | Nothing => failWith ("unknown function " ++ fn.name)
  let params = zipWith (\p, t => ("%a" ++ show p.var, t)) fn.params types
  line 1 ("func.func " ++ symbol fn.name ++ "("
          ++ joinBy ", " [name ++ ": " ++ mlirType t | (name, t) <- params]
          ++ ") -> " ++ mlirType fn.result ++ " {")
  (r, _) <- expr sigs 2 (fromList (zip (map (.var) fn.params) params)) fn.body
  line 2 ("return " ++ r ++ " : " ++ mlirType fn.result)
  line 1 "}"

||| C `main` returning the Idris entry's value as the exit status.
entryPoint : Sigs -> String -> Emit ()
entryPoint sigs fn = do
  let Just ([], result) = lookup fn sigs
    | _ => failWith ("entry " ++ fn ++ " must take no runtime arguments")
  line 1 "func.func @main() -> i32 {"
  (r, _) <- expr sigs 2 empty (Cast result SInt32 (Call fn []))
  line 2 ("return " ++ r ++ " : i32")
  line 1 "}"

export
emit : Program -> Either String String
emit prog = do
  sigs <- signatures prog.functions
  (st, ()) <- runStateT (MkSt 0 [<]) $ do
    line 0 "module {"
    traverse_ (function sigs) prog.functions
    traverse_ (entryPoint sigs) prog.entry
    line 0 "}"
  pure (unlines (st.out <>> []))
  where
    runtime : Param -> Either String IntTy
    runtime (MkParam _ _ (IntT t)) = Right t
    runtime (MkParam v _ Irrelevant) = Left ("parameter %" ++ show v ++ " was not erased")

    signature : Fn -> Either String (String, List IntTy, IntTy)
    signature fn = do
      params <- traverse runtime fn.params
      pure (fn.name, params, fn.result)

    signatures : List Fn -> Either String Sigs
    signatures fns = fromList <$> traverse signature fns
