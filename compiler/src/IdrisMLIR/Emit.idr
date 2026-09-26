||| First-order Core to `idr` contract text (docs/architecture/08-idr-dialect.md).
||| The only module that knows MLIR syntax.
module IdrisMLIR.Emit

import IdrisMLIR.Core

import Control.Monad.State
import Data.List
import Data.Maybe
import Data.SnocList
import Data.String

%default covering

------------------------------------------------------------------------------
-- Names, types, locations
------------------------------------------------------------------------------

||| IDR-FN-2: injective mangling into an MLIR bare identifier.
export
symbol : String -> String
symbol s = case unpack s of
  [] => "_"
  (c :: cs) => (if isAlpha c || c == '_' then "" else "_") ++ concatMap escape (c :: cs)
  where
    escape : Char -> String
    escape c = if isAlphaNum c || c == '_' || c == '.'
                  then singleton c
                  else "$" ++ show (ord c) ++ "$"

quoted : String -> String
quoted s = "\"" ++ concatMap esc (unpack s) ++ "\""
  where
    hex : Int -> String
    hex n = let digits = unpack "0123456789ABCDEF" in
            pack [ fromMaybe '0' (getAt (cast (n `div` 16)) digits)
                 , fromMaybe '0' (getAt (cast (n `mod` 16)) digits) ]
    esc : Char -> String
    esc '"' = "\\\""
    esc '\\' = "\\\\"
    esc c = if ord c < 32 || ord c == 127 then "\\" ++ hex (ord c) else singleton c

||| UTF-8 encoding of a string, as the bytes of an MLIR string attribute.
utf8 : String -> String
utf8 s = "\"" ++ concatMap enc (unpack s) ++ "\""
  where
    hex : Int -> String
    hex n = let digits = unpack "0123456789ABCDEF" in
            pack [ fromMaybe '0' (getAt (cast (n `div` 16)) digits)
                 , fromMaybe '0' (getAt (cast (n `mod` 16)) digits) ]
    byte : Int -> String
    byte b = if b >= 32 && b < 127 && b /= 34 && b /= 92
                then singleton (chr b) else "\\" ++ hex b
    enc : Char -> String
    enc c =
      let n = ord c in
      if n < 0x80 then byte n
      else if n < 0x800 then byte (0xC0 + n `div` 64) ++ byte (0x80 + n `mod` 64)
      else if n < 0x10000 then byte (0xE0 + n `div` 4096) ++ byte (0x80 + (n `div` 64) `mod` 64)
                                 ++ byte (0x80 + n `mod` 64)
      else byte (0xF0 + n `div` 262144) ++ byte (0x80 + (n `div` 4096) `mod` 64)
           ++ byte (0x80 + (n `div` 64) `mod` 64) ++ byte (0x80 + n `mod` 64)

intType : IntTy -> String
intType t = "i" ++ show (width t)

export
mlirType : Ty -> Either String String
mlirType (IntT t) = Right (intType t)
mlirType CharT = Right "i32"
mlirType StrT = Right "!idr.str"
mlirType WorldT = Right "!idr.world"
mlirType ErasedT = Right "!idr.erased"
mlirType (DataT n) = Right ("!idr.data<@" ++ symbol n ++ ">")
mlirType t = Left ("a value of type " ++ show t ++ " reached emission")

||| IDR-LOC-1: 1-based line and column.
location : Loc -> String
location l = if l.file == "" then "loc(unknown)"
             else "loc(" ++ quoted l.file ++ ":" ++ show (l.startLine + 1) ++ ":" ++
                  show (l.startCol + 1) ++ ")"

------------------------------------------------------------------------------
-- The emitter
------------------------------------------------------------------------------

record St where
  constructor MkSt
  next : Nat
  out : SnocList String
  depth : Nat

Emit : Type -> Type
Emit = StateT St (Either String)

line : String -> Emit ()
line s = do
  st <- get
  put ({ out := st.out :< (replicate (2 * st.depth) ' ' ++ s) } st)

||| A line one level deeper than the current one (a region terminator).
innerLine : String -> Emit ()
innerLine s = do
  st <- get
  put ({ out := st.out :< (replicate (2 * S st.depth) ' ' ++ s) } st)

fresh : Emit String
fresh = do
  st <- get
  put ({ next := S st.next } st)
  pure ("%" ++ show st.next)

lift' : Either String a -> Emit a
lift' = lift

||| Runs an emitter into a separate buffer, one level deeper, and returns the lines.
nested : Emit a -> Emit (a, List String)
nested act = do
  st <- get
  put ({ out := [<], depth := S st.depth } st)
  x <- act
  inner <- get
  put ({ out := st.out, depth := st.depth, next := inner.next } st)
  pure (x, inner.out <>> [])

emitLines : List String -> Emit ()
emitLines ls = modify { out $= (<>< ls) }

Env : Type
Env = List (Var, (String, Ty))

types : Env -> List (Var, Ty)
types = map (\(x, (_, t)) => (x, t))

constant : Loc -> String -> Ty -> Emit String
constant l value ty = do
  r <- fresh
  t <- lift' (mlirType ty)
  line (r ++ " = arith.constant " ++ value ++ " : " ++ t ++ " " ++ location l)
  pure r

||| Two's complement bit pattern of `n` in `w` bits, printed signed.
twos : Nat -> Integer -> Integer
twos w n = let m = pow 2 (cast w)
               r = n `mod` m
               r' = if r < 0 then r + m else r
           in if r' >= m `div` 2 then r' - m else r'
  where
    pow : Integer -> Integer -> Integer
    pow b e = if e <= 0 then 1 else b * pow b (e - 1)

cmpPredicate : String -> Ty -> String
cmpPredicate op (IntT t) = if op == "eq" then "eq" else (if signed t then "s" else "u") ++ op
cmpPredicate op _ = if op == "eq" then "eq" else "u" ++ op

||| IDR-MATCH-2: without a default, the last alternative is the default region.
splitDefault : Loc -> Maybe Expr -> List ConAlt ->
               (List (Either ConAlt Expr), Either ConAlt Expr)
splitDefault l (Just e) alts = (map Left alts, Right e)
splitDefault l Nothing alts = case reverse alts of
  (lastAlt :: rest) => (map Left (reverse rest), Left lastAlt)
  [] => ([], Right (EErased l))

mutual
  expr : Program -> Env -> Expr -> Emit (String, Ty)
  expr prog env (EVar l x) = case lookup x env of
    Just vt => pure vt
    Nothing => lift' (Left ("unbound variable %" ++ show x))
  expr prog env (ELit l (LInt t n)) = pure (!(constant l (show (twos (width t) n)) (IntT t)), IntT t)
  expr prog env (ELit l (LChar c)) = pure (!(constant l (show c) CharT), CharT)
  expr prog env (ELit l (LStr s)) = do
    r <- fresh
    line (r ++ " = idr.str.lit " ++ utf8 s ++ " : !idr.str " ++ location l)
    pure (r, StrT)
  expr prog env (EErased l) = do
    r <- fresh
    line (r ++ " = idr.erased : !idr.erased " ++ location l)
    pure (r, ErasedT)
  expr prog env (EWorld l) = lift' (Left "%MkWorld reached emission")
  expr prog env (EPrim l op args) = do
    vs <- traverse (expr prog env) args
    prim l op vs
  expr prog env (EIO l op args res) = do
    vs <- traverse (expr prog env) args
    io l op vs res
  expr prog env (ECall l f args) = do
    fn <- maybe (lift' (Left ("unknown function " ++ f))) pure (lookupFn f prog)
    vs <- traverse (expr prog env) args
    argTys <- lift' (traverse (mlirType . snd) vs)
    res <- lift' (mlirType fn.result)
    r <- fresh
    line (r ++ " = func.call @" ++ symbol f ++ "(" ++ joinBy ", " (map fst vs) ++ ") : (" ++
          joinBy ", " argTys ++ ") -> " ++ res ++ " " ++ location l)
    pure (r, fn.result)
  expr prog env (ECon l d c args) = do
    vs <- traverse (expr prog env) args
    argTys <- lift' (traverse (mlirType . snd) vs)
    res <- lift' (mlirType (DataT d))
    r <- fresh
    line (r ++ " = idr.con @" ++ symbol d ++ "::@" ++ symbol c ++ "(" ++
          joinBy ", " (map fst vs) ++ ") : (" ++ joinBy ", " argTys ++ ") -> " ++ res ++
          " " ++ location l)
    pure (r, DataT d)
  expr prog env (ELet l x q t val body) = do
    (v, vt) <- expr prog env val
    expr prog ((x, (v, vt)) :: env) body
  expr prog env (EMatchCon l x alts def) = do
    (scrut, DataT d) <- maybe (lift' (Left "unbound scrutinee")) pure (lookup x env)
      | _ => lift' (Left "constructor match on a non-data value")
    dt <- maybe (lift' (Left ("unknown data " ++ d))) pure (lookupData d prog)
    Just resTy <- pure (typeOf prog (types env) (EMatchCon l x alts def))
      | Nothing => lift' (Left "cannot type a match")
    res <- lift' (mlirType resTy)
    tag <- fresh
    line (tag ++ " = idr.tag " ++ scrut ++ " : !idr.data<@" ++ symbol d ++ "> " ++ location l)
    let (cases, deflt) = splitDefault l def alts
    caseRegions <- traverse (region prog env scrut dt) cases
    defRegion <- region prog env scrut dt deflt
    r <- fresh
    line (r ++ " = scf.index_switch " ++ tag ++ " -> " ++ res)
    for_ caseRegions $ \(tagNo, body) => do
      line ("case " ++ show tagNo ++ " {")
      emitLines body
      line "}"
    line "default {"
    emitLines (snd defRegion)
    line ("} " ++ location l)
    pure (r, resTy)
  expr prog env (EMatchLit l x alts def) = do
    (scrut, st) <- maybe (lift' (Left "unbound scrutinee")) pure (lookup x env)
    Just resTy <- pure (typeOf prog (types env) def)
      | Nothing => lift' (Left "cannot type a match")
    res <- lift' (mlirType resTy)
    chain scrut st res resTy alts
    where
      chain : String -> Ty -> String -> Ty -> List (Lit, Expr) -> Emit (String, Ty)
      chain scrut st res resTy [] = expr prog env def
      chain scrut st res resTy ((lit, body) :: rest) = do
        (k, _) <- expr prog env (ELit l lit)
        t <- lift' (mlirType st)
        c <- fresh
        line (c ++ " = arith.cmpi eq, " ++ scrut ++ ", " ++ k ++ " : " ++ t ++ " " ++ location l)
        ((thenV, _), thenLines) <- nested (expr prog env body)
        ((elseV, _), elseLines) <- nested (chain scrut st res resTy rest)
        r <- fresh
        line (r ++ " = scf.if " ++ c ++ " -> (" ++ res ++ ") {")
        emitLines thenLines
        innerLine ("scf.yield " ++ thenV ++ " : " ++ res)
        line "} else {"
        emitLines elseLines
        innerLine ("scf.yield " ++ elseV ++ " : " ++ res)
        line ("} " ++ location l)
        pure (r, resTy)
  expr prog env e = lift' (Left "a higher-order construct reached emission")

  ||| One region of a constructor switch: binds the fields, yields the body.
  region : Program -> Env -> String -> Data -> Either ConAlt Expr -> Emit (Nat, List String)
  region prog env scrut dt (Right e) = do
    ((v, t), body) <- nested $ do
      (v, t) <- expr prog env e
      res <- lift' (mlirType t)
      line ("scf.yield " ++ v ++ " : " ++ res)
      pure (v, t)
    pure (0, body)
  region prog env scrut dt (Left (MkConAlt c xs e)) = do
    con <- maybe (lift' (Left ("unknown constructor " ++ c))) pure (find (\k => k.name == c) dt.cons)
    (_, body) <- nested $ do
      bound <- traverse (field con) (zip [0 .. length xs] (zip xs con.fields))
      (v, t) <- expr prog (bound ++ env) e
      res <- lift' (mlirType t)
      line ("scf.yield " ++ v ++ " : " ++ res)
    pure (con.tag, body)
    where
      field : Con -> (Nat, (Var, Field)) -> Emit (Var, (String, Ty))
      field con (i, (x, f)) = do
        r <- fresh
        t <- lift' (mlirType f.type)
        line (r ++ " = idr.field " ++ scrut ++ "[@" ++ symbol con.name ++ ", " ++ show i ++
              "] : !idr.data<@" ++ symbol dt.name ++ "> -> " ++ t ++ " " ++ location con.loc)
        pure (x, (r, f.type))

  prim : Loc -> PrimOp -> List (String, Ty) -> Emit (String, Ty)
  prim l op vs = do
    let loc = location l
    r <- fresh
    case (op, vs) of
      (Add t, [(a, _), (b, _)]) => arith r "addi" a b (intType t) loc (IntT t)
      (Sub t, [(a, _), (b, _)]) => arith r "subi" a b (intType t) loc (IntT t)
      (Mul t, [(a, _), (b, _)]) => arith r "muli" a b (intType t) loc (IntT t)
      (And t, [(a, _), (b, _)]) => arith r "andi" a b (intType t) loc (IntT t)
      (Or t, [(a, _), (b, _)]) => arith r "ori" a b (intType t) loc (IntT t)
      (Xor t, [(a, _), (b, _)]) => arith r "xori" a b (intType t) loc (IntT t)
      (Div t, [(a, _), (b, _)]) => division r "div" t a b loc
      (Mod t, [(a, _), (b, _)]) => division r "mod" t a b loc
      (Lt t, [(a, _), (b, _)]) => compare r "lt" t a b loc
      (Lte t, [(a, _), (b, _)]) => compare r "le" t a b loc
      (Eq t, [(a, _), (b, _)]) => compare r "eq" t a b loc
      (Gte t, [(a, _), (b, _)]) => compare r "ge" t a b loc
      (Gt t, [(a, _), (b, _)]) => compare r "gt" t a b loc
      (Cast from to, [(a, _)]) => cast r from to a loc
      _ => lift' (Left ("primitive " ++ show op ++ " reached emission"))
    where
      arith : String -> String -> String -> String -> String -> String -> Ty -> Emit (String, Ty)
      arith r name a b t loc ty = do
        line (r ++ " = arith." ++ name ++ " " ++ a ++ ", " ++ b ++ " : " ++ t ++ " " ++ loc)
        pure (r, ty)
      division : String -> String -> IntTy -> String -> String -> String -> Emit (String, Ty)
      division r name t a b loc = do
        line (r ++ " = idr." ++ name ++ (if signed t then " signed " else " ") ++ a ++ ", " ++
              b ++ " : " ++ intType t ++ " " ++ loc)
        pure (r, IntT t)
      compare : String -> String -> Ty -> String -> String -> String -> Emit (String, Ty)
      compare r pred t a b loc = do
        ty <- lift' (mlirType t)
        line (r ++ " = arith.cmpi " ++ cmpPredicate pred t ++ ", " ++ a ++ ", " ++ b ++ " : " ++
              ty ++ " " ++ loc)
        w <- fresh
        line (w ++ " = arith.extui " ++ r ++ " : i1 to i64 " ++ loc)
        pure (w, IntT IdrisInt)
      -- SEM-INT-7, SEM-CHAR-3
      cast : String -> Ty -> Ty -> String -> String -> Emit (String, Ty)
      cast r (IntT f) (IntT t) a loc =
        if width f == width t then pure (a, IntT t)
        else if width f > width t
          then do line (r ++ " = arith.trunci " ++ a ++ " : " ++ intType f ++ " to " ++ intType t ++ " " ++ loc)
                  pure (r, IntT t)
          else do line (r ++ " = arith." ++ (if signed f then "extsi " else "extui ") ++ a ++ " : " ++
                        intType f ++ " to " ++ intType t ++ " " ++ loc)
                  pure (r, IntT t)
      cast r CharT (IntT t) a loc =
        if width t == 32 then pure (a, IntT t)
        else if width t < 32
          then do line (r ++ " = arith.trunci " ++ a ++ " : i32 to " ++ intType t ++ " " ++ loc)
                  pure (r, IntT t)
          else do line (r ++ " = arith.extui " ++ a ++ " : i32 to " ++ intType t ++ " " ++ loc)
                  pure (r, IntT t)
      cast r (IntT f) CharT a loc = do
        line (r ++ " = idr.to_char" ++ (if signed f then " signed " else " ") ++ a ++ " : " ++
              intType f ++ " " ++ loc)
        pure (r, CharT)
      cast r f t a loc = lift' (Left ("cast from " ++ show f ++ " to " ++ show t ++ " reached emission"))

  io : Loc -> IOOp -> List (String, Ty) -> String -> Emit (String, Ty)
  io l op vs res = do
    let loc = location l
    w <- fresh
    value <- case (op, vs) of
      (PutStr, [(s, _), (w0, _)]) => do
        line (w ++ " = idr.io.put_str " ++ s ++ ", " ++ w0 ++ " " ++ loc)
        unit
      (PutChar, [(c, _), (w0, _)]) => do
        line (w ++ " = idr.io.put_char " ++ c ++ ", " ++ w0 ++ " " ++ loc)
        unit
      (PutInt t, [(n, _), (w0, _)]) => do
        line (w ++ " = idr.io.put_int" ++ (if signed t then " signed " else " ") ++ n ++ ", " ++
              w0 ++ " : " ++ intType t ++ " " ++ loc)
        unit
      (Exit, [(n, _), (w0, _)]) => do
        line (w ++ " = idr.io.exit " ++ n ++ ", " ++ w0 ++ " " ++ loc)
        unit
      (GetChar, [(w0, _)]) => do
        c <- fresh
        line (c ++ ", " ++ w ++ " = idr.io.get_char " ++ w0 ++ " " ++ loc)
        pure (c, "i32")
      _ => lift' (Left ("IO primitive " ++ show op ++ " with wrong arguments"))
    r <- fresh
    let resT = "!idr.data<@" ++ symbol res ++ ">"
    line (r ++ " = idr.con @" ++ symbol res ++ "::@" ++ symbol "PrimIO.MkIORes" ++ "(" ++
          fst value ++ ", " ++ w ++ ") : (" ++ snd value ++ ", !idr.world) -> " ++ resT ++ " " ++ loc)
    pure (r, DataT res)
    where
      unit : Emit (String, String)
      unit = do
        u <- fresh
        let ut = "!idr.data<@" ++ symbol "Builtin.Unit" ++ ">"
        line (u ++ " = idr.con @" ++ symbol "Builtin.Unit" ++ "::@" ++ symbol "Builtin.MkUnit" ++
              "() : () -> " ++ ut ++ " " ++ location l)
        pure (u, ut)

------------------------------------------------------------------------------
-- Declarations
------------------------------------------------------------------------------

dataDecl : Data -> Either String (List String)
dataDecl d = do
  cons <- traverse con d.cons
  pure (["  idr.data @" ++ symbol d.name ++ " attributes {idr.name = " ++ quoted d.idrisName ++ "} {"]
        ++ cons ++ ["  } " ++ location d.loc])
  where
    con : Con -> Either String String
    con c = do
      tys <- traverse (mlirType . (.type)) c.fields
      pure ("    idr.ctor @" ++ symbol c.name ++ " tag " ++ show c.tag ++ " fields [" ++
            joinBy ", " tys ++ "] quantities [" ++
            joinBy ", " (map (quoted . show . (.quantity)) c.fields) ++ "] {idr.name = " ++
            quoted c.idrisName ++ "} " ++ location c.loc)

function : Program -> Fn -> Emit ()
function prog fn = do
  params <- lift' (traverse param fn.params)
  res <- lift' (mlirType fn.result)
  line ("func.func private @" ++ symbol fn.name ++ "(" ++ joinBy ", " (map fst params) ++ ") -> " ++
        res ++ " attributes {idr.name = " ++ quoted fn.idrisName ++ "} {")
  modify { depth := 2 }
  (v, _) <- expr prog (map snd params) fn.body
  line ("return " ++ v ++ " : " ++ res ++ " " ++ location fn.loc)
  modify { depth := 1 }
  line ("} " ++ location fn.loc)
  where
    param : Param -> Either String (String, (Var, (String, Ty)))
    param p = do
      t <- mlirType p.type
      let name = "%a" ++ show p.var
      pure (name ++ ": " ++ t ++ " {idr.quantity = " ++ quoted (show p.quantity) ++ "}",
            (p.var, (name, p.type)))

||| The contract text of a first-order program.
export
emit : Program -> Either String String
emit prog = do
  datas <- traverse dataDecl prog.datas
  let kind = case prog.entry of
               IntEntry => "int"
               IOEntry => "io"
  let header = "module attributes {idr.version = " ++ show prog.version ++ " : i64, idr.entry = @" ++
               symbol prog.root ++ ", idr.entry_kind = " ++ quoted kind ++ "} {"
  (st, _) <- runStateT (MkSt 0 [<] 1) (traverse_ (function prog) prog.fns)
  pure (unlines ([header] ++ concat datas ++ (st.out <>> []) ++ ["}"]))
