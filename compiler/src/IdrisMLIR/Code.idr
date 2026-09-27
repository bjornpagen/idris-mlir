||| First-order Core (docs/architecture/05-middle-ir.md): what `Simplify`
||| produces and `Emit` consumes. It is A-normal form with join points, the
||| core of "Compiling without continuations" (Maurer, Downen, Ariola and
||| Peyton Jones, PLDI 2017) and of Lean's LCNF:
|||
||| * every argument is an atom, and every value is bound once, with its
|||   value type;
||| * a match is a terminator, and what follows a match is a join point: a
|||   block with parameters that the match's alternatives jump to;
||| * a join point whose body jumps to itself is a loop, so loops are
|||   syntax, and a self tail call is a jump;
||| * a binding and a result may hold several values (a constructed product
|||   result, or a function that returns several atoms).
|||
||| Join points are MLIR's blocks with arguments (Kelsey's correspondence
||| between CPS and SSA), and `Emit` writes them as such.
|||
||| `Code` is indexed by its phase, as Lean's LCNF is by its purity: `Pure`
||| is what `Simplify` produces, and `Mem` adds the region operations of the
||| memory plan (docs/research/refactor-and-memory.md). One type, one set of
||| traversals, and region operations cannot occur in pure code.
|||
||| Types are `VTy`, value types only, so a function, a `Lazy` value or static
||| data cannot occur here (PROF-HEAP-1, PROF-HEAP-2); string primitives are
||| not `Prim`s, so they cannot either (PROF-HEAP-3, CORE-INV-10). Every
||| traversal is a fold with an algebra over the base functor `CodeF`.
module IdrisMLIR.Code

import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Types

import Data.List
import Data.Maybe
import Data.SortedMap
import Data.SortedSet
import Data.String

%default total

------------------------------------------------------------------------------
-- The IR
------------------------------------------------------------------------------

||| A runtime operand: a variable, a literal, the erased value, or a value
||| of a type that is never read (a slot of a choice that its tag does not
||| select, ELIM-G-20).
public export
data Atom = AVar VarId | ALit Lit | AErased | AUndef VTy

export
Eq Atom where
  AVar a == AVar b = a == b
  ALit a == ALit b = a == b
  AErased == AErased = True
  AUndef s == AUndef t = s == t
  _ == _ = False

export
Show Atom where
  show (AVar x) = show x
  show (ALit l) = show l
  show AErased = "erased"
  show (AUndef t) = "undef:" ++ show t

||| A variable with its quantity and type: a parameter of a function or join
||| point, or a binding.
public export
record Param where
  constructor MkParam
  var : VarId
  quantity : Quantity
  type : VTy

||| A constructor alternative: the constructor, the variables bound to its
||| fields, and what the branch holds.
public export
record Branch r where
  constructor MkBranch
  con : ConId
  fields : List VarId
  body : r

||| An operation: what a `Let` binds. It has no branches; control is `Code`.
public export
data Op
  = OPrim Prim (List Atom)
  | OCall FnId (List Atom)
  | OCon ConId (List Atom)
  -- field i of a value of a single-constructor data type (IDR-FIELD-1)
  | OField Atom ConId Nat
  -- an IO primitive: its operands end with the world, and its result is a
  -- value of the IORes instance named here
  | OIO IOOp (List Atom) DataId

||| The phases of first-order Core: `Mem` adds the memory plan.
public export
data Phase = Pure | Mem

||| A function body.
public export
data Code : Phase -> Type where
  ||| Binds the results of an operation.
  Let : Loc -> List Param -> Op -> Code p -> Code p
  ||| A join point: its parameters and body, and the code that may jump to
  ||| it. The body may jump to it too, which makes it a loop.
  Join : Loc -> JoinId -> List Param -> (body : Code p) -> (rest : Code p) -> Code p
  Jump : Loc -> JoinId -> List Atom -> Code p
  Case : Loc -> Atom -> List (Branch (Code p)) -> Maybe (Code p) -> Code p
  CaseLit : Loc -> Atom -> List (Lit, Code p) -> Code p -> Code p
  Ret : Loc -> List Atom -> Code p
  ||| A crash with its cause (SEM-CRASH-2).
  Crash : Loc -> String -> Code p
  ||| A point that cannot be reached (an alternative Idris proved impossible).
  Absurd : Loc -> Code p
  ||| Records the top of the region stack in a variable.
  Mark : Loc -> VarId -> Code Mem -> Code Mem
  ||| Releases the region stack to a mark.
  Release : Loc -> VarId -> Code Mem -> Code Mem

||| The base functor of `Code`: one layer, with the recursive positions `r`.
public export
data CodeF : Phase -> Type -> Type where
  LetF : Loc -> List Param -> Op -> r -> CodeF p r
  JoinF : Loc -> JoinId -> List Param -> r -> r -> CodeF p r
  JumpF : Loc -> JoinId -> List Atom -> CodeF p r
  CaseF : Loc -> Atom -> List (Branch r) -> Maybe r -> CodeF p r
  CaseLitF : Loc -> Atom -> List (Lit, r) -> r -> CodeF p r
  RetF : Loc -> List Atom -> CodeF p r
  CrashF : Loc -> String -> CodeF p r
  AbsurdF : Loc -> CodeF p r
  MarkF : Loc -> VarId -> r -> CodeF Mem r
  ReleaseF : Loc -> VarId -> r -> CodeF Mem r

export
Functor Branch where
  map f b = { body $= f } b

export
Functor (CodeF p) where
  map f (LetF l ps o k) = LetF l ps o (f k)
  map f (JoinF l j ps b k) = JoinF l j ps (f b) (f k)
  map f (JumpF l j as) = JumpF l j as
  map f (CaseF l x bs d) = CaseF l x (map (map f) bs) (map f d)
  map f (CaseLitF l x as d) = CaseLitF l x (map (map f) as) (f d)
  map f (RetF l as) = RetF l as
  map f (CrashF l m) = CrashF l m
  map f (AbsurdF l) = AbsurdF l
  map f (MarkF l x k) = MarkF l x (f k)
  map f (ReleaseF l x k) = ReleaseF l x (f k)

export
Foldable (CodeF p) where
  foldr f z (LetF _ _ _ k) = f k z
  foldr f z (JoinF _ _ _ b k) = f b (f k z)
  foldr f z (CaseF _ _ bs d) = foldr (\b, acc => f b.body acc) (maybe z (\e => f e z) d) bs
  foldr f z (CaseLitF _ _ as d) = foldr (\(_, e), acc => f e acc) (f d z) as
  foldr f z (MarkF _ _ k) = f k z
  foldr f z (ReleaseF _ _ k) = f k z
  foldr f z _ = z

mutual
  ||| The catamorphism: folds a `Code` bottom-up with an algebra.
  export
  cata : (CodeF p a -> a) -> Code p -> a
  cata alg (Let l ps o k) = alg (LetF l ps o (cata alg k))
  cata alg (Join l j ps b k) = alg (JoinF l j ps (cata alg b) (cata alg k))
  cata alg (Jump l j as) = alg (JumpF l j as)
  cata alg (Case l x bs d) = alg (CaseF l x (cataBranches alg bs) (cataMaybe alg d))
  cata alg (CaseLit l x as d) = alg (CaseLitF l x (cataLits alg as) (cata alg d))
  cata alg (Ret l as) = alg (RetF l as)
  cata alg (Crash l m) = alg (CrashF l m)
  cata alg (Absurd l) = alg (AbsurdF l)
  cata alg (Mark l x k) = alg (MarkF l x (cata alg k))
  cata alg (Release l x k) = alg (ReleaseF l x (cata alg k))

  cataBranches : (CodeF p a -> a) -> List (Branch (Code p)) -> List (Branch a)
  cataBranches alg [] = []
  cataBranches alg (MkBranch c xs e :: bs) = MkBranch c xs (cata alg e) :: cataBranches alg bs

  cataMaybe : (CodeF p a -> a) -> Maybe (Code p) -> Maybe a
  cataMaybe alg Nothing = Nothing
  cataMaybe alg (Just e) = Just (cata alg e)

  cataLits : (CodeF p a -> a) -> List (Lit, Code p) -> List (Lit, a)
  cataLits alg [] = []
  cataLits alg ((k, e) :: as) = (k, cata alg e) :: cataLits alg as

||| One layer of `Code`.
export
project : Code p -> CodeF p (Code p)
project (Let l ps o k) = LetF l ps o k
project (Join l j ps b k) = JoinF l j ps b k
project (Jump l j as) = JumpF l j as
project (Case l x bs d) = CaseF l x bs d
project (CaseLit l x as d) = CaseLitF l x as d
project (Ret l as) = RetF l as
project (Crash l m) = CrashF l m
project (Absurd l) = AbsurdF l
project (Mark l x k) = MarkF l x k
project (Release l x k) = ReleaseF l x k

||| One layer back into `Code`.
export
embed : CodeF p (Code p) -> Code p
embed (LetF l ps o k) = Let l ps o k
embed (JoinF l j ps b k) = Join l j ps b k
embed (JumpF l j as) = Jump l j as
embed (CaseF l x bs d) = Case l x bs d
embed (CaseLitF l x as d) = CaseLit l x as d
embed (RetF l as) = Ret l as
embed (CrashF l m) = Crash l m
embed (AbsurdF l) = Absurd l
embed (MarkF l x k) = Mark l x k
embed (ReleaseF l x k) = Release l x k

||| The paramorphism: like `cata`, but the algebra also sees each part as it
||| was.
export
para : (CodeF p (Code p, a) -> a) -> Code p -> a
para alg = snd . cata (\layer => (embed (map fst layer), alg layer))

||| A bottom-up rewrite: `f` sees each layer with its parts already rewritten.
export
transform : (Code p -> Code p) -> Code p -> Code p
transform f = cata (f . embed)

||| Pure code is code of every phase.
export
relax : Code Pure -> Code p
relax = cata alg
  where
    alg : CodeF Pure (Code p) -> Code p
    alg (LetF l ps o k) = Let l ps o k
    alg (JoinF l j ps b k) = Join l j ps b k
    alg (JumpF l j as) = Jump l j as
    alg (CaseF l x bs d) = Case l x bs d
    alg (CaseLitF l x as d) = CaseLit l x as d
    alg (RetF l as) = Ret l as
    alg (CrashF l m) = Crash l m
    alg (AbsurdF l) = Absurd l

||| The code of a block that returns, placed where its value continues at a
||| join point: each of its returns jumps there instead.
export
returnTo : JoinId -> Code p -> Code p
returnTo j = transform $ \c => case c of
  Ret l as => Jump l j as
  _ => c

------------------------------------------------------------------------------
-- Operations and atoms
------------------------------------------------------------------------------

||| The atoms an operation reads.
export
operands : Op -> List Atom
operands (OPrim _ as) = as
operands (OCall _ as) = as
operands (OCon _ as) = as
operands (OField a _ _) = [a]
operands (OIO _ as _) = as

||| Renames an operation's atoms.
mapOp : (Atom -> Atom) -> Op -> Op
mapOp f (OPrim p as) = OPrim p (map f as)
mapOp f (OCall g as) = OCall g (map f as)
mapOp f (OCon c as) = OCon c (map f as)
mapOp f (OField a c i) = OField (f a) c i
mapOp f (OIO o as r) = OIO o (map f as) r

||| Renames every atom a body reads; binders are unchanged.
export
mapAtoms : (Atom -> Atom) -> Code p -> Code p
mapAtoms f = cata alg
  where
    alg : CodeF q (Code q) -> Code q
    alg (LetF l ps o k) = Let l ps (mapOp f o) k
    alg (JumpF l j as) = Jump l j (map f as)
    alg (CaseF l x bs d) = Case l (f x) bs d
    alg (CaseLitF l x as d) = CaseLit l (f x) as d
    alg (RetF l as) = Ret l (map f as)
    alg other = embed other

||| Renames variables.
export
rename : SortedMap VarId VarId -> Code p -> Code p
rename m = mapAtoms $ \a => case a of
  AVar x => AVar (fromMaybe x (lookup x m))
  _ => a

export
varsOf : List Atom -> List VarId
varsOf = mapMaybe var
  where
    var : Atom -> Maybe VarId
    var (AVar x) = Just x
    var _ = Nothing

------------------------------------------------------------------------------
-- Algebras
------------------------------------------------------------------------------

||| Every variable bound in a body, in order (CORE-INV-1: unique). Field
||| binders need the constructor, so they are listed separately.
export
binders : Code p -> List VarId
binders = cata alg
  where
    alg : CodeF q (List VarId) -> List VarId
    alg (LetF _ ps _ k) = map (.var) ps ++ k
    alg (JoinF _ _ ps b k) = map (.var) ps ++ b ++ k
    alg (CaseF _ _ bs d) = concatMap (\b => b.fields ++ b.body) bs ++ fromMaybe [] d
    alg (MarkF _ x k) = x :: k
    alg other = concat other

||| Every join point a body declares, in order.
export
joins : Code p -> List JoinId
joins = cata alg
  where
    alg : CodeF q (List JoinId) -> List JoinId
    alg (JoinF _ j _ b k) = j :: b ++ k
    alg other = concat other

||| The functions a body calls.
export
calls : Code p -> List FnId
calls = cata alg
  where
    alg : CodeF q (List FnId) -> List FnId
    alg (LetF _ _ (OCall f _) k) = f :: k
    alg other = concat other

||| The data instances a body mentions.
export
datasOf : Code p -> List DataId
datasOf = cata alg
  where
    ty : VTy -> List DataId
    ty (DataT d) = [d]
    ty _ = []
    here : Op -> List DataId
    here (OCon c _) = [c.dataId]
    here (OField _ c _) = [c.dataId]
    here (OIO _ _ r) = [r]
    here _ = []
    alg : CodeF q (List DataId) -> List DataId
    alg (LetF _ ps o k) = concatMap (ty . (.type)) ps ++ here o ++ k
    alg (JoinF _ _ ps b k) = concatMap (ty . (.type)) ps ++ b ++ k
    alg (CaseF _ _ bs d) = map (\b => b.con.dataId) bs ++ concatMap (.body) bs ++ fromMaybe [] d
    alg other = concat other

||| Does a body jump to a join point?
export
jumpsTo : JoinId -> Code p -> Bool
jumpsTo j = cata alg
  where
    alg : CodeF q Bool -> Bool
    alg (JumpF _ k _) = j == k
    alg other = any id other

||| The loops of a body: the join points whose body jumps to them.
export
loops : Code p -> List JoinId
loops = para alg
  where
    alg : CodeF q (Code q, List JoinId) -> List JoinId
    alg (JoinF _ j _ (b, lb) (_, lk)) = (if jumpsTo j b then [j] else []) ++ lb ++ lk
    alg other = concatMap snd other

sums : List (SortedMap VarId Nat) -> SortedMap VarId Nat
sums = foldl (mergeWith (+)) empty

maxes : List (SortedMap VarId Nat) -> SortedMap VarId Nat
maxes = foldl (mergeWith max) empty

count : List Atom -> SortedMap VarId Nat
count as = sums [singleton x 1 | x <- varsOf as]

||| How often each variable is used on the path that uses it most (CORE-INV-9).
|||
||| Uses add up along a path and take the maximum over alternatives. A jump
||| continues in its join point's body, so it counts that body's uses. A
||| loop's body runs any number of times: a variable it reads from outside
||| counts as used twice, while its own parameters and bindings are fresh in
||| each iteration.
export
uses : Code p -> SortedMap VarId Nat
uses c = cata alg c empty
  where
    Env : Type
    Env = SortedMap JoinId (SortedMap VarId Nat)
    alg : CodeF q (Env -> SortedMap VarId Nat) -> Env -> SortedMap VarId Nat
    alg (LetF _ _ o k) env = sums [count (operands o), k env]
    -- A jump back into a loop ends an iteration: it counts nothing more.
    alg (JoinF _ j ps b k) env = k (insert j (b (insert j empty env)) env)
    alg (JumpF _ j as) env = sums [count as, fromMaybe empty (lookup j env)]
    alg (CaseF _ x bs d) env = sums [count [x], maxes (map (\b => b.body env) bs ++ map (\e => e env) (toList d))]
    alg (CaseLitF _ x as d) env = sums [count [x], maxes (d env :: map (\(_, e) => e env) as)]
    alg (RetF _ as) _ = count as
    alg (MarkF _ _ k) env = k env
    alg (ReleaseF _ x k) env = sums [singleton x 1, k env]
    alg _ _ = empty

||| The variables of a loop body that come from outside it, used in it: each
||| is used again in every iteration (CORE-INV-9).
export
loopOuterUses : Code p -> List VarId
loopOuterUses = para alg
  where
    alg : CodeF q (Code q, List VarId) -> List VarId
    alg (JoinF _ j ps (b, ub) (_, uk)) =
      let local = the (SortedSet VarId) (fromList (map (.var) ps ++ binders b))
          here = if jumpsTo j b
                   then [x | (x, _) <- SortedMap.toList (uses b), not (contains x local)]
                   else []
      in here ++ ub ++ uk
    alg other = concatMap snd other

||| Whether an operation can crash or has an effect, given which callees are
||| safe: division by an unknown or zero divisor, IO, or an unsafe call.
export
safeOp : (FnId -> Bool) -> Op -> Bool
safeOp s (OPrim (IntOp Div _) [_, ALit (LInt _ n)]) = n /= 0
safeOp s (OPrim (IntOp Mod _) [_, ALit (LInt _ n)]) = n /= 0
safeOp s (OPrim (IntOp Div _) _) = False
safeOp s (OPrim (IntOp Mod _) _) = False
safeOp s (OIO {}) = False
safeOp s (OCall f _) = s f
safeOp s _ = True

||| Code that cannot crash, loop or act (ELIM-G-5, PROF-HEAP-5).
export
safeCode : (FnId -> Bool) -> Code p -> Bool
safeCode s c = cata alg c && null (loops c)
  where
    alg : CodeF q Bool -> Bool
    alg (LetF _ _ o k) = safeOp s o && k
    alg (CrashF _ _) = False
    alg other = all id other

------------------------------------------------------------------------------
-- Contract version (IDR-MOD-1): one join-semilattice fold
------------------------------------------------------------------------------

||| The contract version a value type needs.
export
typeLevel : VTy -> Nat
typeLevel CharT = 1
typeLevel StrT = 1
typeLevel WorldT = 1
typeLevel DoubleT = 2
typeLevel _ = 0

litLevel : Lit -> Nat
litLevel (LChar _) = 1
litLevel (LStr _) = 1
litLevel (LDouble _) = 2
litLevel _ = 0

atomLevel : Atom -> Nat
atomLevel (ALit l) = litLevel l
atomLevel _ = 0

scalarLevel : Scalar -> Nat
scalarLevel SChar = 1
scalarLevel SDouble = 2
scalarLevel _ = 0

opLevel : Op -> Nat
opLevel o = foldl max (here o) (map atomLevel (operands o))
  where
    here : Op -> Nat
    here (OPrim (FloatOp _) _) = 2
    here (OPrim Negate _) = 2
    here (OPrim (Math _) _) = 2
    here (OPrim DoubleHead _) = 3
    here (OPrim (Compare _ s) _) = scalarLevel s
    here (OPrim (Cast a b) _) = max (scalarLevel a) (scalarLevel b)
    here (OIO GetByte _ _) = 3
    here (OIO PutDouble _ _) = 2
    here (OIO _ _ _) = 1
    here _ = 0

||| The contract version a body needs: the maximum over what it contains.
export
level : Code p -> Nat
level = cata alg
  where
    params : List Param -> Nat
    params = foldl max 0 . map (typeLevel . (.type))
    alg : CodeF q Nat -> Nat
    alg (LetF _ ps o k) = foldl max k [params ps, opLevel o]
    alg (JoinF _ _ ps b k) = foldl max (params ps) [b, k]
    alg (JumpF _ _ as) = foldl max 0 (map atomLevel as)
    alg (CaseLitF _ x as d) = foldl max (max (atomLevel x) d) (map (\(k, e) => max (litLevel k) e) as)
    alg (RetF _ as) = foldl max 0 (map atomLevel as)
    alg (CrashF _ _) = 3
    alg other = foldr max 0 other

------------------------------------------------------------------------------
-- Programs
------------------------------------------------------------------------------

||| A field of a runtime constructor.
public export
record CField where
  constructor MkCField
  quantity : Quantity
  type : VTy

public export
record CCon where
  constructor MkCCon
  id : ConId
  tag : Nat
  fields : List CField
  loc : Loc

||| A runtime data instance.
public export
record CData where
  constructor MkCData
  id : DataId
  idrisName : String
  cons : List CCon
  loc : Loc

||| A function of first-order Core: an instance, or a specialization of one.
public export
record CFn (p : Phase) where
  constructor MkCFn
  id : FnId
  idrisName : String
  params : List Param
  results : List VTy
  body : Code p
  loc : Loc
  terminating : Bool
  ||| For a specialization, the instance and the static arguments it was
  ||| made for, printed in dumps (ELIM-G-3).
  specializes : Maybe String

||| A whole program in first-order Core.
public export
record Target (p : Phase) where
  constructor MkTarget
  datas : List CData
  fns : List (CFn p)
  root : FnId
  entry : EntryKind

||| A pure program is a program of every phase.
export
relaxTarget : Target Pure -> Target p
relaxTarget t = MkTarget t.datas (map (\f => { body := relax f.body } f) t.fns) t.root t.entry

||| Lookup tables of a program.
public export
record Index (p : Phase) where
  constructor MkIndex
  fns : SortedMap FnId (CFn p)
  datas : SortedMap DataId CData
  cons : SortedMap ConId CCon

export
index : Target p -> Index p
index t = MkIndex (fromList [(f.id, f) | f <- t.fns])
                  (fromList [(d.id, d) | d <- t.datas])
                  (fromList [(c.id, c) | d <- t.datas, c <- d.cons])

||| The contract version a program needs (IDR-MOD-1).
export
version : Target p -> Nat
version t = foldl max (entryLevel t.entry) (map fnLevel t.fns ++ map dataLevel t.datas)
  where
    entryLevel : EntryKind -> Nat
    entryLevel IOEntry = 1
    entryLevel IntEntry = 0
    dataLevel : CData -> Nat
    dataLevel d = foldl max 0 [typeLevel f.type | c <- d.cons, f <- c.fields]
    fnLevel : CFn p -> Nat
    fnLevel f = foldl max (level f.body) (map typeLevel (f.results ++ map (.type) f.params))

||| OPT-PIPE-3: the loop breakers of a program, as in GHC ("Secrets of the
||| Glasgow Haskell Compiler inliner", Peyton Jones and Marlow): enough
||| functions that every recursive cycle through two or more functions
||| contains one. Inlining everything else cannot unroll a loop, and each
||| breaker becomes self recursive once the rest of its cycle is inlined.
||| In each cycle, the breaker is the first function in program order that
||| is not from a library module, or the first function if all are.
export
loopBreakers : List (CFn p) -> SortedSet FnId
loopBreakers fns =
  -- `let`, not `where`: a `where` binding is recomputed at each use.
  let edges = the (SortedMap FnId (List FnId)) (fromList [(f.id, nub (calls f.body)) | f <- fns])
      library = the (SortedSet FnId) (fromList [f.id | f <- fns, isLibrary f.idrisName])
  in fromList (within edges library (length fns) (map (.id) fns))
  where
    isLibrary : String -> Bool
    isLibrary n = any (`isPrefixOf` n) ["Builtin.", "PrimIO.", "IdrisMLIR.IO."]
    -- The functions reachable from `f` in one or more calls inside `set`.
    reach : SortedMap FnId (List FnId) -> SortedSet FnId -> FnId -> SortedSet FnId
    reach edges set f = walk (length fns) empty (next f)
      where
        next : FnId -> List FnId
        next g = filter (`contains` set) (fromMaybe [] (lookup g edges))
        walk : Nat -> SortedSet FnId -> List FnId -> SortedSet FnId
        walk Z seen _ = seen
        walk _ seen [] = seen
        walk (S k) seen (g :: gs) =
          if contains g seen then walk (S k) seen gs
          else walk k (insert g seen) (next g ++ gs)
    split : (FnId -> FnId -> Bool) -> Nat -> List FnId -> List (List FnId)
    split r Z _ = []
    split r _ [] = []
    split r (S k) (f :: rest) =
      let (same, other) = partition (\g => r f g && r g f) rest
      in (f :: same) :: split r k other
    -- The strongly connected components of the call graph on `ns`, each in
    -- program order.
    components : SortedMap FnId (List FnId) -> List FnId -> List (List FnId)
    components edges ns =
      let set = fromList ns
          reaches = the (SortedMap FnId (SortedSet FnId)) (fromList [(f, reach edges set f) | f <- ns])
      in split (\a, b => maybe False (contains b) (lookup a reaches)) (length ns) ns
    -- The breakers among `ns`: in each component of two or more functions,
    -- one breaker, then the breakers of the rest of that component.
    within : SortedMap FnId (List FnId) -> SortedSet FnId -> Nat -> List FnId -> List FnId
    within edges library Z _ = []
    within edges library (S k) ns = concatMap cut (components edges ns)
      where
        cut : List FnId -> List FnId
        cut [_] = []
        cut c = case find (not . (`contains` library)) c <|> head' c of
          Just b => b :: within edges library k (delete b c)
          Nothing => []

------------------------------------------------------------------------------
-- Printing (CORE-DUMP-1)
------------------------------------------------------------------------------

indent : Nat -> String
indent d = replicate (2 * d) ' '

args : List Atom -> String
args as = "(" ++ joinBy ", " (map show as) ++ ")"

showParam : Param -> String
showParam p = show p.var ++ " : " ++ show p.quantity ++ " " ++ show p.type

showOp : Op -> String
showOp (OPrim p as) = show p ++ args as
showOp (OCall f as) = show f ++ args as
showOp (OCon c as) = show c.dataId ++ "::" ++ show c ++ args as
showOp (OField a c i) = show a ++ "." ++ show c ++ "#" ++ show i
showOp (OIO op as _) = "io." ++ show op ++ args as

||| A body, printed at an indentation depth: an algebra into `Nat -> String`.
export
showCode : Code p -> Nat -> String
showCode = cata alg
  where
    alg : CodeF q (Nat -> String) -> Nat -> String
    alg (LetF _ [p] o k) d = "let " ++ showParam p ++ " = " ++ showOp o ++ "\n" ++ indent d ++ k d
    alg (LetF _ ps o k) d =
      "let (" ++ joinBy ", " (map showParam ps) ++ ") = " ++ showOp o ++ "\n" ++ indent d ++ k d
    alg (JoinF _ j ps b k) d =
      "join " ++ show j ++ "(" ++ joinBy ", " (map showParam ps) ++ ") =\n" ++
      indent (S d) ++ b (S d) ++ "\n" ++ indent d ++ k d
    alg (JumpF _ j as) d = "jump " ++ show j ++ args as
    alg (CaseF _ x bs def) d =
      "case " ++ show x ++ " of" ++
      concatMap (\b => "\n" ++ indent (S d) ++ show b.con ++ "(" ++ joinBy ", " (map show b.fields) ++
                       ") => " ++ b.body (S (S d))) bs ++
      maybe "" (\e => "\n" ++ indent (S d) ++ "_ => " ++ e (S (S d))) def
    alg (CaseLitF _ x as def) d =
      "case " ++ show x ++ " of" ++
      concatMap (\(k, e) => "\n" ++ indent (S d) ++ show k ++ " => " ++ e (S (S d))) as ++
      "\n" ++ indent (S d) ++ "_ => " ++ def (S (S d))
    alg (RetF _ [a]) d = show a
    alg (RetF _ as) d = args as
    alg (CrashF _ m) d = "crash " ++ show m
    alg (AbsurdF _) d = "unreachable"
    alg (MarkF _ x k) d = "mark " ++ show x ++ "\n" ++ indent d ++ k d
    alg (ReleaseF _ x k) d = "release " ++ show x ++ "\n" ++ indent d ++ k d

export
showTarget : Target p -> String
showTarget t = unlines (map dataDecl t.datas ++ map fnDecl t.fns ++ ["root " ++ show t.root])
  where
    dataDecl : CData -> String
    dataDecl d = unlines (("data " ++ show d.id) ::
                   map (\c => "  " ++ show c.id ++ " tag " ++ show c.tag ++ " (" ++
                              joinBy ", " (map (\f => show f.quantity ++ " " ++ show f.type) c.fields) ++ ")")
                       d.cons)
    fnDecl : CFn p -> String
    fnDecl f = maybe "" (\s => "-- " ++ s ++ "\n") f.specializes ++
               show f.id ++ " " ++
               unwords (map (\p => "(" ++ showParam p ++ ")") f.params) ++
               " : " ++ joinBy ", " (map show f.results) ++ " =\n  " ++ showCode f.body 1 ++ "\n"
