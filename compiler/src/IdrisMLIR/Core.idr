||| The middle IR (docs/architecture/05-middle-ir.md). Full Core may contain
||| lambdas, `Delay`/`Force` and function values; first-order Core, produced by
||| `Simplify` and accepted by `HeapCheck`, contains none of them.
module IdrisMLIR.Core

import Data.List
import Data.String

%default total

------------------------------------------------------------------------------
-- Locations and diagnostics
------------------------------------------------------------------------------

||| Where a source file came from, so the frontend can rebuild Idris's `FC`.
public export
data Origin = FromModule (List String) | FromPackage String | Nowhere

public export
Eq Origin where
  FromModule a == FromModule b = a == b
  FromPackage a == FromPackage b = a == b
  Nowhere == Nowhere = True
  _ == _ = False

||| A source span, 0-based as in Idris.
public export
record Loc where
  constructor MkLoc
  origin : Origin
  file : String
  startLine : Int
  startCol : Int
  endLine : Int
  endCol : Int

export
noLoc : Loc
noLoc = MkLoc Nowhere "" 0 0 0 0

||| A user error (DIAG-FMT-1): the violated rule, the definition, the location.
public export
record Diag where
  constructor MkDiag
  rule : String
  owner : String
  loc : Loc
  message : String

export
diag : String -> String -> Loc -> String -> Diag
diag = MkDiag

------------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------------

public export
data Quantity = Q0 | Q1 | QW

public export
Eq Quantity where
  Q0 == Q0 = True
  Q1 == Q1 = True
  QW == QW = True
  _ == _ = False

export
Show Quantity where
  show Q0 = "0"
  show Q1 = "1"
  show QW = "w"

public export
data IntTy : Type where
  IdrisInt, SInt8, SInt16, SInt32, SInt64, UInt8, UInt16, UInt32, UInt64 : IntTy

public export
Eq IntTy where
  a == b = show' a == show' b
    where
      show' : IntTy -> Int
      show' IdrisInt = 0
      show' SInt8 = 1
      show' SInt16 = 2
      show' SInt32 = 3
      show' SInt64 = 4
      show' UInt8 = 5
      show' UInt16 = 6
      show' UInt32 = 7
      show' UInt64 = 8

export
Show IntTy where
  show IdrisInt = "Int"
  show SInt8 = "Int8"
  show SInt16 = "Int16"
  show SInt32 = "Int32"
  show SInt64 = "Int64"
  show UInt8 = "Bits8"
  show UInt16 = "Bits16"
  show UInt32 = "Bits32"
  show UInt64 = "Bits64"

export
width : IntTy -> Nat
width IdrisInt = 64
width SInt8 = 8
width SInt16 = 16
width SInt32 = 32
width SInt64 = 64
width UInt8 = 8
width UInt16 = 16
width UInt32 = 32
width UInt64 = 64

export
signed : IntTy -> Bool
signed t = case t of
  UInt8 => False
  UInt16 => False
  UInt32 => False
  UInt64 => False
  _ => True

||| Types after monomorphisation. `DataT` names a data *instance*.
public export
data Ty = IntT IntTy | CharT | StrT | WorldT | ErasedT
        | DataT String
        | FunT Quantity Ty Ty
        | LazyT Ty

public export
Eq Ty where
  IntT a == IntT b = a == b
  CharT == CharT = True
  StrT == StrT = True
  WorldT == WorldT = True
  ErasedT == ErasedT = True
  DataT a == DataT b = a == b
  FunT q a r == FunT q' a' r' = q == q' && a == a' && r == r'
  LazyT a == LazyT b = a == b
  _ == _ = False

export
Show Ty where
  show (IntT t) = show t
  show CharT = "Char"
  show StrT = "String"
  show WorldT = "%World"
  show ErasedT = "Erased"
  show (DataT n) = n
  show (FunT q a r) = "((" ++ show q ++ " _ : " ++ show a ++ ") -> " ++ show r ++ ")"
  show (LazyT a) = "Lazy (" ++ show a ++ ")"

export
firstOrder : Ty -> Bool
firstOrder (FunT {}) = False
firstOrder (LazyT _) = False
firstOrder _ = True

------------------------------------------------------------------------------
-- Terms
------------------------------------------------------------------------------

public export
data Lit = LInt IntTy Integer | LChar Integer | LStr String

export
Show Lit where
  show (LInt t n) = show n ++ ":" ++ show t
  show (LChar c) = "chr " ++ show c
  show (LStr s) = show s

public export
litTy : Lit -> Ty
litTy (LInt t _) = IntT t
litTy (LChar _) = CharT
litTy (LStr _) = StrT

||| Primitive operations. Integer ops carry their operand type.
public export
data PrimOp
  = Add IntTy | Sub IntTy | Mul IntTy | Div IntTy | Mod IntTy
  | And IntTy | Or IntTy | Xor IntTy
  | Lt Ty | Lte Ty | Eq Ty | Gte Ty | Gt Ty     -- on IntT or CharT; result Int
  | Cast Ty Ty                                  -- IntT/CharT/StrT combinations
  | StrAppend | StrCons | StrLength | StrHead | StrTail | StrIndex
  | StrReverse | StrSubstr | StrCompare String  -- string ops, eliminated in v1

export
Show PrimOp where
  show (Add t) = "add_" ++ show t
  show (Sub t) = "sub_" ++ show t
  show (Mul t) = "mul_" ++ show t
  show (Div t) = "div_" ++ show t
  show (Mod t) = "mod_" ++ show t
  show (And t) = "and_" ++ show t
  show (Or t) = "or_" ++ show t
  show (Xor t) = "xor_" ++ show t
  show (Lt t) = "lt_" ++ show t
  show (Lte t) = "lte_" ++ show t
  show (Eq t) = "eq_" ++ show t
  show (Gte t) = "gte_" ++ show t
  show (Gt t) = "gt_" ++ show t
  show (Cast a b) = "cast_" ++ show a ++ show b
  show StrAppend = "strAppend"
  show StrCons = "strCons"
  show StrLength = "strLength"
  show StrHead = "strHead"
  show StrTail = "strTail"
  show StrIndex = "strIndex"
  show StrReverse = "strReverse"
  show StrSubstr = "strSubstr"
  show (StrCompare op) = op ++ "_String"

export
primResult : PrimOp -> Ty
primResult (Add t) = IntT t
primResult (Sub t) = IntT t
primResult (Mul t) = IntT t
primResult (Div t) = IntT t
primResult (Mod t) = IntT t
primResult (And t) = IntT t
primResult (Or t) = IntT t
primResult (Xor t) = IntT t
primResult (Cast _ t) = t
primResult StrLength = IntT IdrisInt
primResult StrHead = CharT
primResult StrIndex = CharT
primResult StrAppend = StrT
primResult StrCons = StrT
primResult StrTail = StrT
primResult StrReverse = StrT
primResult StrSubstr = StrT
primResult _ = IntT IdrisInt

||| String-building primitives (PROF-HEAP-3).
export
buildsString : PrimOp -> Bool
buildsString StrAppend = True
buildsString StrCons = True
buildsString StrTail = True
buildsString StrReverse = True
buildsString StrSubstr = True
buildsString (Cast _ StrT) = True
buildsString _ = False

export
isStringOp : PrimOp -> Bool
isStringOp op = case op of
  StrLength => True
  StrHead => True
  StrIndex => True
  StrCompare _ => True
  Cast StrT _ => True
  _ => buildsString op

public export
data IOOp = PutStr | PutChar | GetChar | Exit | PutInt IntTy

export
Show IOOp where
  show PutStr = "putStr"
  show PutChar = "putChar"
  show GetChar = "getChar"
  show Exit = "exit"
  show (PutInt t) = "putInt_" ++ show t

public export
Var : Type
Var = Nat

mutual
  ||| Every node carries its source location.
  public export
  data Expr : Type where
    EVar : Loc -> Var -> Expr
    ELit : Loc -> Lit -> Expr
    EErased : Loc -> Expr
    EWorld : Loc -> Expr                          -- %MkWorld, root only
    EPrim : Loc -> PrimOp -> List Expr -> Expr
    ||| An IO primitive; its arguments end with the world. It returns the
    ||| `IORes` instance named by the last field: (value, next world).
    EIO : Loc -> IOOp -> List Expr -> String -> Expr
    ECall : Loc -> String -> List Expr -> Expr     -- saturated call
    ECon : Loc -> String -> String -> List Expr -> Expr   -- data instance, constructor
    ELet : Loc -> Var -> Quantity -> Ty -> Expr -> Expr -> Expr
    EMatchCon : Loc -> Var -> List ConAlt -> Maybe Expr -> Expr
    EMatchLit : Loc -> Var -> List (Lit, Expr) -> Expr -> Expr
    ELam : Loc -> Var -> Quantity -> Ty -> Expr -> Expr   -- full Core only
    EApp : Loc -> Expr -> Expr -> Expr                    -- full Core only
    EPartial : Loc -> String -> List Expr -> Expr         -- known function, too few args
    EDelay : Loc -> Expr -> Expr                          -- full Core only
    EForce : Loc -> Expr -> Expr                          -- full Core only

  public export
  data ConAlt = MkConAlt String (List Var) Expr

export
locOf : Expr -> Loc
locOf (EVar l _) = l
locOf (ELit l _) = l
locOf (EErased l) = l
locOf (EWorld l) = l
locOf (EPrim l _ _) = l
locOf (EIO l _ _ _) = l
locOf (ECall l _ _) = l
locOf (ECon l _ _ _) = l
locOf (ELet l _ _ _ _ _) = l
locOf (EMatchCon l _ _ _) = l
locOf (EMatchLit l _ _ _) = l
locOf (ELam l _ _ _ _) = l
locOf (EApp l _ _) = l
locOf (EPartial l _ _) = l
locOf (EDelay l _) = l
locOf (EForce l _) = l

------------------------------------------------------------------------------
-- Programs
------------------------------------------------------------------------------

public export
record Field where
  constructor MkField
  quantity : Quantity
  type : Ty

public export
record Con where
  constructor MkCon
  name : String        -- short constructor name, unique within its data type
  idrisName : String   -- the Idris full name
  tag : Nat
  fields : List Field
  loc : Loc

public export
record Data where
  constructor MkData
  name : String        -- instance name
  idrisName : String
  cons : List Con
  loc : Loc

public export
record Param where
  constructor MkParam
  var : Var
  quantity : Quantity
  type : Ty

public export
record Fn where
  constructor MkFn
  name : String
  idrisName : String
  params : List Param
  result : Ty
  body : Expr
  loc : Loc
  terminating : Bool   -- Idris's checker reports it total (ELIM-G-5)

public export
data EntryKind = IntEntry | IOEntry

public export
record Program where
  constructor MkProgram
  datas : List Data
  fns : List Fn
  root : String
  entry : EntryKind
  version : Nat        -- the contract version the program needs (IDR-MOD-1)

export
lookupFn : String -> Program -> Maybe Fn
lookupFn n prog = find (\f => f.name == n) prog.fns

export
lookupData : String -> Program -> Maybe Data
lookupData n prog = find (\d => d.name == n) prog.datas

export
lookupCon : String -> String -> Program -> Maybe Con
lookupCon d c prog = do
  dt <- lookupData d prog
  find (\k => k.name == c) dt.cons

------------------------------------------------------------------------------
-- Typing
------------------------------------------------------------------------------

||| The type of an expression, given the types of the variables in scope.
||| Nothing only for ill-formed Core.
export covering
typeOf : Program -> List (Var, Ty) -> Expr -> Maybe Ty
typeOf prog env e = case e of
  EVar _ x => lookup x env
  ELit _ l => Just (litTy l)
  EErased _ => Just ErasedT
  EWorld _ => Just WorldT
  EPrim _ op _ => Just (primResult op)
  EIO _ _ _ res => Just (DataT res)
  ECall _ f _ => (.result) <$> lookupFn f prog
  EPartial _ f args => do
    fn <- lookupFn f prog
    pure (foldr (\p, r => FunT p.quantity p.type r) fn.result (drop (length args) fn.params))
  ECon _ d _ _ => Just (DataT d)
  ELet _ x _ t _ body => typeOf prog ((x, t) :: env) body
  EMatchCon _ x alts def => case alts of
    (MkConAlt c xs body :: _) => do
      DataT d <- lookup x env
        | _ => Nothing
      con <- lookupCon d c prog
      typeOf prog (zip xs (map (.type) con.fields) ++ env) body
    [] => def >>= typeOf prog env
  EMatchLit _ _ _ def => typeOf prog env def
  ELam _ x q t body => FunT q t <$> typeOf prog ((x, t) :: env) body
  EApp _ f _ => case !(typeOf prog env f) of
    FunT _ _ r => Just r
    _ => Nothing
  EDelay _ x => LazyT <$> typeOf prog env x
  EForce _ x => case !(typeOf prog env x) of
    LazyT t => Just t
    _ => Nothing

------------------------------------------------------------------------------
-- Printing (CORE-DUMP-1)
------------------------------------------------------------------------------

indent : Nat -> String
indent n = replicate (n * 2) ' '

v : Var -> String
v n = "%" ++ show n

mutual
  export covering
  showExpr : Nat -> Expr -> String
  showExpr _ (EVar _ x) = v x
  showExpr _ (ELit _ l) = show l
  showExpr _ (EErased _) = "erased"
  showExpr _ (EWorld _) = "%MkWorld"
  showExpr d (EPrim _ op args) = show op ++ args' d args
  showExpr d (EIO _ op args _) = "io." ++ show op ++ args' d args
  showExpr d (ECall _ f args) = f ++ args' d args
  showExpr d (EPartial _ f args) = "partial " ++ f ++ args' d args
  showExpr d (ECon _ t c args) = t ++ "::" ++ c ++ args' d args
  showExpr d (ELet _ x q t val body) =
    "let " ++ v x ++ " : " ++ show q ++ " " ++ show t ++ " = " ++ showExpr (S d) val ++
    "\n" ++ indent d ++ showExpr d body
  showExpr d (EMatchCon _ x alts def) =
    "case " ++ v x ++ " of" ++ concatMap (conAlt (S d)) alts ++
    maybe "" (\e => "\n" ++ indent (S d) ++ "_ => " ++ showExpr (S (S d)) e) def
  showExpr d (EMatchLit _ x alts def) =
    "case " ++ v x ++ " of" ++
    concatMap (\(l, e) => "\n" ++ indent (S d) ++ show l ++ " => " ++ showExpr (S (S d)) e) alts ++
    "\n" ++ indent (S d) ++ "_ => " ++ showExpr (S (S d)) def
  showExpr d (ELam _ x q t body) =
    "\\(" ++ v x ++ " : " ++ show q ++ " " ++ show t ++ ") => " ++ showExpr d body
  showExpr d (EApp _ f a) = "(" ++ showExpr d f ++ " " ++ showExpr d a ++ ")"
  showExpr d (EDelay _ e) = "delay (" ++ showExpr d e ++ ")"
  showExpr d (EForce _ e) = "force (" ++ showExpr d e ++ ")"

  covering
  args' : Nat -> List Expr -> String
  args' d args = "(" ++ joinBy ", " (map (showExpr d) args) ++ ")"

  covering
  conAlt : Nat -> ConAlt -> String
  conAlt d (MkConAlt c xs e) =
    "\n" ++ indent d ++ c ++ "(" ++ joinBy ", " (map v xs) ++ ") => " ++ showExpr (S d) e

export covering
showProgram : Program -> String
showProgram prog = unlines (map showData prog.datas ++ map showFn prog.fns ++ ["root " ++ prog.root])
  where
    showCon : Con -> String
    showCon c = "  " ++ c.name ++ " tag " ++ show c.tag ++ " (" ++
                joinBy ", " (map (\f => show f.quantity ++ " " ++ show f.type) c.fields) ++ ")"
    showData : Data -> String
    showData d = unlines (("data " ++ d.name) :: map showCon d.cons)
    showParam : Param -> String
    showParam p = "(" ++ v p.var ++ " : " ++ show p.quantity ++ " " ++ show p.type ++ ")"
    showFn : Fn -> String
    showFn f = f.name ++ " " ++ unwords (map showParam f.params) ++ " : " ++ show f.result ++
               " =\n  " ++ showExpr 1 f.body ++ "\n"
