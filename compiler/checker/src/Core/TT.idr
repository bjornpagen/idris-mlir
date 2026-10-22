-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.TT

import public Core.FC
import public Core.Name
import public Core.Name.Scoped

import Data.Maybe
import Data.Nat

import Libraries.Data.NameMap
import Libraries.Text.PrettyPrint.Prettyprinter
import Libraries.Text.PrettyPrint.Prettyprinter.Util

import Libraries.Data.List.SizeOf
import Libraries.Data.SnocList.SizeOf

import public Algebra

import public Core.TT.Binder
import public Core.TT.Primitive
import public Core.TT.Subst
import public Core.TT.Term
import public Core.TT.Term.Subst
import public Core.TT.Var

%default covering

public export
record KindedName where
  constructor MkKindedName
  nameKind : Maybe NameType
  fullName : Name -- fully qualified name
  rawName  : Name

%name KindedName kn

export
defaultKindedName : Name -> KindedName
defaultKindedName nm = MkKindedName Nothing nm nm

export
funKindedName : Name -> KindedName
funKindedName nm = MkKindedName (Just Func) nm nm

export
Show KindedName where show = show . rawName

export
covering
[Raw] Show KindedName where
  showPrec d (MkKindedName nm fn rn) =
    showCon d "MkKindedName" $ showArg nm ++ showArg @{Raw} fn ++ showArg @{Raw} rn

namespace CList
  -- A list correspoding to another list
  public export
  data CList : List a -> Type -> Type where
       Nil : CList [] ty
       (::) : (x : ty) -> CList cs ty -> CList (c :: cs) ty


public export
data Visibility = Private | Export | Public
%name Visibility vis

export
Show Visibility where
  show Private = "private"
  show Export = "export"
  show Public = "public export"

export
Pretty Void Visibility where
  pretty Private = pretty "private"
  pretty Export = pretty "export"
  pretty Public = pretty "public" <++> pretty "export"

export
Eq Visibility where
  Private == Private = True
  Export == Export = True
  Public == Public = True
  _ == _ = False

export
Ord Visibility where
  compare Private Export = LT
  compare Private Public = LT
  compare Export Public = LT

  compare Private Private = EQ
  compare Export Export = EQ
  compare Public Public = EQ

  compare Export Private = GT
  compare Public Private = GT
  compare Public Export = GT

public export
data DataOpt : Type where
     SearchBy : List1 Name -> DataOpt -- determining arguments
     NoHints : DataOpt -- Don't generate search hints for constructors
     UniqueSearch : DataOpt -- auto implicit search must check result is unique
     External : DataOpt -- implemented externally
     NoNewtype : DataOpt -- don't apply newtype optimisation
%name DataOpt dopt

export
Eq DataOpt where
  (==) (SearchBy xs) (SearchBy ys) = xs == ys
  (==) NoHints NoHints = True
  (==) UniqueSearch UniqueSearch = True
  (==) External External = True
  (==) NoNewtype NoNewtype = True
  (==) _ _ = False

public export
data Fixity = InfixL | InfixR | Infix | Prefix

export
Show Fixity where
  show InfixL = "infixl"
  show InfixR = "infixr"
  show Infix  = "infix"
  show Prefix = "prefix"

export
Interpolation Fixity where
  interpolate = show

export
Eq Fixity where
  InfixL == InfixL = True
  InfixR == InfixR = True
  Infix == Infix = True
  Prefix == Prefix = True
  _ == _ = False


public export
data BindingModifier = NotBinding | Autobind | Typebind

export
Eq BindingModifier where
  NotBinding == NotBinding = True
  Autobind == Autobind = True
  Typebind == Typebind = True
  _ == _ = False

export
Show BindingModifier where
  show NotBinding = "regular"
  show Typebind = "typebind"
  show Autobind = "autobind"

export
Interpolation BindingModifier where
  interpolate = show

-- A record to hold all the information about a fixity
public export
record FixityInfo where
  constructor MkFixityInfo
  fc : FC
  vis : Visibility
  bindingInfo : BindingModifier
  fix : Fixity
  precedence : Nat

export
Show FixityInfo where
  show fx = "fc: \{show fx.fc}, visibility: \{show fx.vis}, binding: \{show fx.bindingInfo}, fixity: \{show fx.fix}, precedence: \{show fx.precedence}"


export
Eq FixityInfo where
  x == y = x.fc == y.fc
        && x.vis == y.vis
        && x.bindingInfo == y.bindingInfo
        && x.fix == y.fix
        && x.precedence == y.precedence

||| Whenever we read an operator from the parser, we don't know if it's a backticked expression with no fixity
||| declaration, or if it has a fixity declaration. If it does not have a declaration, we represent this state
||| with `UndeclaredFixity`.
||| Note that a backticked expression can have a fixity declaration, in which case it is represented with
||| `DeclaredFixity`.
public export
data FixityDeclarationInfo = UndeclaredFixity | DeclaredFixity FixityInfo

-- Left-hand-side information for operators, carries autobind information
-- an operator can either be
-- - not autobind, a regular operator
-- - binding types, such that `(nm : ty) =@ fn nm` desugars into `(=@) ty (\(nm : ty) => fn nm)`
-- - binding expressing with an inferred type such that
--   `(nm := exp) =@ fn nm` desugars into `(=@) exp (\(nm : ?) => fn nm)`
-- - binding both types and expression such that
--   `(nm : ty := exp) =@ fn nm` desugars into `(=@) exp (\(nm : ty) => fn nm)`
public export
data OperatorLHSInfo : Type -> Type where
  -- Traditional operator wihtout binding, carries the lhs
  NoBinder : (lhs : tm) -> OperatorLHSInfo tm
  -- (nm : ty) =@ fn x
  BindType : (name : tm) -> (ty : tm) -> OperatorLHSInfo tm
  -- (nm := exp) =@ fn nm
  BindExpr : (name : tm) -> (expr : tm) -> OperatorLHSInfo tm
  -- (nm : ty := exp) =@ fn nm
  BindExplicitType : (name : tm) ->  (type, expr : tm) -> OperatorLHSInfo tm

export
Show (OperatorLHSInfo tm) where
  show (NoBinder lhs)                    = "regular"
  show (BindType name ty)                = "type-binding (typebind)"
  show (BindExpr name expr)              = "automatically-binding (autobind)"
  show (BindExplicitType name type expr) = "automatically-binding (autobind)"

%name OperatorLHSInfo opInfo

export
Functor OperatorLHSInfo where
  map f (NoBinder lhs) = NoBinder $ f lhs
  map f (BindType nm lhs) = BindType (f nm) (f lhs)
  map f (BindExpr nm lhs) = BindExpr (f nm) (f lhs)
  map f (BindExplicitType nm ty lhs) = BindExplicitType (f nm) (f ty) (f lhs)

export
(.getLhs) : OperatorLHSInfo tm -> tm
(.getLhs) (NoBinder lhs) = lhs
(.getLhs) (BindExpr _ lhs) = lhs
(.getLhs) (BindType _ lhs) = lhs
(.getLhs) (BindExplicitType _ _ lhs) = lhs

export
(.getBoundPat) : OperatorLHSInfo tm -> Maybe tm
(.getBoundPat) (NoBinder lhs) = Nothing
(.getBoundPat) (BindType name ty) = Just name
(.getBoundPat) (BindExpr name expr) = Just name
(.getBoundPat) (BindExplicitType name type expr) = Just name

export
(.getBinder) : OperatorLHSInfo tm -> BindingModifier
(.getBinder) (NoBinder lhs) = NotBinding
(.getBinder) (BindType name ty) = Typebind
(.getBinder) (BindExpr name expr) = Autobind
(.getBinder) (BindExplicitType name type expr) = Autobind

public export
data TotalReq = Total | CoveringOnly | PartialOK
%name TotalReq treq

export
Eq TotalReq where
    (==) Total Total = True
    (==) CoveringOnly CoveringOnly = True
    (==) PartialOK PartialOK = True
    (==) _ _ = False

||| Bigger means more requirements
||| So if a definition was checked at b, it can be accepted at a <= b.
export
Ord TotalReq where
  PartialOK <= _ = True
  _ <= Total = True
  a <= b = a == b

  a < b = a <= b && a /= b

export
Show TotalReq where
    show Total = "total"
    show CoveringOnly = "covering"
    show PartialOK = "partial"


public export
data PartialReason
       = NotStrictlyPositive
       | BadCall (List Name)
       -- sequence of mutually-recursive function calls leading to a non-terminating function
       | BadPath (List (FC, Name)) Name
       | RecPath (List (FC, Name))

export
Show PartialReason where
  show NotStrictlyPositive = "not strictly positive"
  show (BadCall [n])
      = "possibly not terminating due to call to " ++ show n
  show (BadCall ns)
      = "possibly not terminating due to calls to " ++ showSep ", " (map show ns)
  show (BadPath [_] n)
      = "possibly not terminating due to call to " ++ show n
  show (BadPath init n)
      = "possibly not terminating due to function " ++ show n ++ " being reachable via " ++ showSep " -> " (map show init)
  show (RecPath loop)
      = "possibly not terminating due to recursive path " ++ showSep " -> " (map (show . snd) loop)

export
Pretty Void PartialReason where
  pretty NotStrictlyPositive = reflow "not strictly positive"
  pretty (BadCall [n])
    = reflow "possibly not terminating due to call to" <++> pretty n
  pretty (BadCall ns)
    = reflow "possibly not terminating due to calls to" <++> concatWith (surround (comma <+> space)) (pretty <$> ns)
  pretty (BadPath [_] n)
    = reflow "possibly not terminating due to call to" <++> pretty n
  pretty (BadPath init n)
    = reflow "possibly not terminating due to function" <++> pretty n
      <++> reflow "being reachable via"
      <++> concatWith (surround (pretty " -> ")) (pretty <$> map snd init)
  pretty (RecPath loop)
    = reflow "possibly not terminating due to recursive path" <++> concatWith (surround (pretty " -> ")) (pretty <$> map snd loop)

public export
data Terminating
       = Unchecked
       | IsTerminating
       | NotTerminating PartialReason

export
Show Terminating where
  show Unchecked = "not yet checked"
  show IsTerminating = "terminating"
  show (NotTerminating p) = show p

export
Pretty Void Terminating where
  pretty Unchecked = reflow "not yet checked"
  pretty IsTerminating = pretty "terminating"
  pretty (NotTerminating p) = pretty p

public export
data Covering
       = IsCovering
       | MissingCases (List ClosedTerm)
       | NonCoveringCall (List Name)

export
Show Covering where
  show IsCovering = "covering"
  show (MissingCases c) = "not covering all cases"
  show (NonCoveringCall [f])
     = "not covering due to call to function " ++ show f
  show (NonCoveringCall cs)
     = "not covering due to calls to functions " ++ showSep ", " (map show cs)

export
Pretty Void Covering where
  pretty IsCovering = pretty "covering"
  pretty (MissingCases c) = reflow "not covering all cases"
  pretty (NonCoveringCall [f])
     = reflow "not covering due to call to function" <++> pretty f
  pretty (NonCoveringCall cs)
     = reflow "not covering due to calls to functions" <++> concatWith (surround (comma <+> space)) (pretty <$> cs)

-- Totality status of a definition. We separate termination checking from
-- coverage checking.
public export
record Totality where
     constructor MkTotality
     isTerminating : Terminating
     isCovering : Covering

export
Show Totality where
  show tot
    = let t = isTerminating tot
          c = isCovering tot in
        showTot t c
    where
      showTot : Terminating -> Covering -> String
      showTot IsTerminating IsCovering = "total"
      showTot IsTerminating c = show c
      showTot t IsCovering = show t
      showTot t c = show c ++ "; " ++ show t

export
Pretty Void Totality where
  pretty (MkTotality IsTerminating IsCovering) = pretty "total"
  pretty (MkTotality IsTerminating c) = pretty c
  pretty (MkTotality t IsCovering) = pretty t
  pretty (MkTotality t c) = pretty c <+> semi <++> pretty t

export
unchecked : Totality
unchecked = MkTotality Unchecked IsCovering

export
isTotal : Totality
isTotal = MkTotality Unchecked IsCovering

export
notCovering : Totality
notCovering = MkTotality Unchecked (MissingCases [])

namespace Bounds
  public export
  data Bounds : Scoped where
       None : Bounds Scope.empty
       Add : (x : Name) -> Name -> Bounds xs -> Bounds (x :: xs)
       -- TODO add diagonal constructor

  export
  sizeOf : Bounds xs -> SizeOf xs
  sizeOf None        = zero
  sizeOf (Add _ _ b) = suc (sizeOf b)

export
addVars : SizeOf outer -> Bounds bound ->
          NVar name (outer ++ vars) ->
          NVar name (outer ++ (bound ++ vars))
addVars p = insertNVarNames p . sizeOf

-- The variable a name stands for, by the first bound that replaces it,
-- and after comparing it with one bound's name, its variable or the
-- search past that bound: a function of the comparison, so that a proof
-- follows it. Public, so that a proof reads off which variable a name
-- becomes.
mutual
  public export
  resolveRef : SizeOf outer ->
               SizeOf done ->
               Bounds bound -> FC -> Name ->
               Maybe (Var (outer ++ (done <>> (bound ++ vars))))
  resolveRef _ _ None _ _ = Nothing
  resolveRef {vars} p q (Add new old bs) fc n = matchedIf {new} {vars} (n == old) p q bs fc n

  public export
  matchedIf : {0 new : Name} -> Bool -> SizeOf outer -> SizeOf done -> Bounds xs -> FC -> Name ->
              Maybe (Var (outer ++ (done <>> (new :: (xs ++ vars)))))
  matchedIf True p q bs fc n = Just (weakenNs p (mkVarChiply q))
  matchedIf {vars} False p q bs fc n = resolveRef {vars} p (q :< new) bs fc n

%default total

||| A name at a bound, and at none before it: the first bound that
||| replaces it, as `resolveRef` searches by Idris's equality of names.
public export
data FirstAt : Bounds bound -> Var bound -> Name -> Type where
  AtHere : (0 _ : (n == old) = True) -> FirstAt (Add new old bs) (MkVar First) n
  AtLater : (0 _ : (n == old) = False) -> FirstAt bs (MkVar v) n ->
            FirstAt (Add new old bs) (MkVar (Later v)) n

||| A name no bound replaces, by Idris's equality of names.
public export
data NoneAt : Bounds bound -> Name -> Type where
  NoneHere : NoneAt None n
  NotThis : (0 _ : (n == old) = False) -> NoneAt bs n -> NoneAt (Add new old bs) n

||| What `resolveRef` gives, at an index.
public export
data ResolvedAt : Nat -> Maybe (Var vs) -> Type where
  ResolvedHere : (0 _ : varIdx v = k) -> ResolvedAt k (Just v)

-- The scopes are stated here and below: `outer` is sized as a list and
-- `done` as a snoc-list, and only their types say which `SizeOf` and
-- which `size` each is.
0 resolvedAtIdx : {0 vs : Scope} -> {0 m : Maybe (Var vs)} -> k = k' -> ResolvedAt k m -> ResolvedAt k' m
resolvedAtIdx Refl r = r

0 matchedHere : {0 outer : Scope} -> {0 done : SnocList Name} -> {0 xs, vars : Scope} ->
                (p : SizeOf outer) -> (q : SizeOf done) -> (rest : Bounds xs) -> (b : Bool) -> b = True ->
                ResolvedAt (size p + size q) (matchedIf {vars} {new} b p q rest fc n)
matchedHere p q rest True Refl
    = ResolvedHere (trans (weakenVarIdx p (mkVarChiply q)) (cong (size p +) (mkVarChiplyIdx q)))

0 matchedPast : {0 outer : Scope} -> {0 done : SnocList Name} -> {0 xs, vars : Scope} ->
                (p : SizeOf outer) -> (q : SizeOf done) -> (rest : Bounds xs) -> (b : Bool) -> b = False ->
                ResolvedAt k (resolveRef {vars} p (q :< new) rest fc n) ->
                ResolvedAt k (matchedIf {vars} {new} b p q rest fc n)
matchedPast p q rest False Refl r = r

0 matchedOff : {0 outer : Scope} -> {0 done : SnocList Name} -> {0 xs, vars : Scope} ->
               (p : SizeOf outer) -> (q : SizeOf done) -> (rest : Bounds xs) -> (b : Bool) -> b = False ->
               matchedIf {vars} {new} b p q rest fc n = resolveRef {vars} p (q :< new) rest fc n
matchedOff p q rest False Refl = Refl

-- The evidence alone is matched: it fixes which variable `w` is, so a
-- match on `w` as well would only add branches the evidence rules out.
||| A name at the first bound that replaces it resolves to that bound's
||| variable, past `outer` and the bounds `done` before.
export
0 resolvesAt : {0 outer : Scope} -> {0 done : SnocList Name} -> {0 bound, vars : Scope} ->
               (p : SizeOf outer) -> (q : SizeOf done) -> (bs : Bounds bound) -> (w : Var bound) ->
               FirstAt bs w n -> ResolvedAt (size p + (size q + varIdx w)) (resolveRef {vars} p q bs fc n)
resolvesAt p q (Add new old rest) _ (AtHere same)
    = resolvedAtIdx (cong (size p +) (sym (plusZeroRightNeutral (size q))))
                    (matchedHere p q rest (n == old) same)
resolvesAt p (MkSizeOf qn qh) (Add new old rest) _ (AtLater {v} differs first)
    = matchedPast p (MkSizeOf qn qh) rest (n == old) differs
        (resolvedAtIdx (cong (size p +) (plusSuccRightSucc qn (varIdx (MkVar v))))
                       (resolvesAt p (MkSizeOf qn qh :< new) rest (MkVar v) first))

||| A name no bound replaces resolves to nothing.
export
0 resolveMisses : {0 outer : Scope} -> {0 done : SnocList Name} -> {0 bound, vars : Scope} ->
                  (p : SizeOf outer) -> (q : SizeOf done) -> (bs : Bounds bound) -> NoneAt bs n ->
                  resolveRef {vars} p q bs fc n = Nothing
resolveMisses p q None NoneHere = Refl
resolveMisses p q (Add new old rest) (NotThis differs none)
    = trans (matchedOff p q rest (n == old) differs) (resolveMisses p (q :< new) rest none)

%default covering

||| A name that resolves to a variable is the local at it; one that
||| resolves to none stays as it was.
public export
resolvedOr : Lazy (Term vars) -> FC -> Maybe (Var vars) -> Term vars
resolvedOr t fc Nothing = t
resolvedOr t fc (Just (MkVar p)) = Local fc Nothing _ p

-- Each kind of node that holds terms is traversed by a function of its
-- own, so that every recursive call is on a part of its argument; each
-- public, so that a proof over a term whose names are turned into
-- variables reads off what each node becomes.
mutual
  public export
  mkLocalsPi : SizeOf outer -> Bounds bound ->
               PiInfo (Term (outer ++ vars)) -> PiInfo (Term (outer ++ (bound ++ vars)))
  mkLocalsPi outer bs Implicit = Implicit
  mkLocalsPi outer bs Explicit = Explicit
  mkLocalsPi outer bs AutoImplicit = AutoImplicit
  mkLocalsPi outer bs (DefImplicit t) = DefImplicit (mkLocals outer bs t)

  public export
  mkLocalsBinder : SizeOf outer -> Bounds bound ->
                   Binder (Term (outer ++ vars)) -> Binder (Term (outer ++ (bound ++ vars)))
  mkLocalsBinder outer bs (Lam fc c p ty)
      = Lam fc c (mkLocalsPi outer bs p) (mkLocals outer bs ty)
  mkLocalsBinder outer bs (Let fc c val ty)
      = Let fc c (mkLocals outer bs val) (mkLocals outer bs ty)
  mkLocalsBinder outer bs (Pi fc c p ty)
      = Pi fc c (mkLocalsPi outer bs p) (mkLocals outer bs ty)
  mkLocalsBinder outer bs (PVar fc c p ty)
      = PVar fc c (mkLocalsPi outer bs p) (mkLocals outer bs ty)
  mkLocalsBinder outer bs (PLet fc c val ty)
      = PLet fc c (mkLocals outer bs val) (mkLocals outer bs ty)
  mkLocalsBinder outer bs (PVTy fc c ty) = PVTy fc c (mkLocals outer bs ty)

  public export
  mkLocalsTerms : SizeOf outer -> Bounds bound ->
                  List (Term (outer ++ vars)) -> List (Term (outer ++ (bound ++ vars)))
  mkLocalsTerms outer bs [] = []
  mkLocalsTerms outer bs (t :: ts) = mkLocals outer bs t :: mkLocalsTerms outer bs ts

  public export
  mkLocals : SizeOf outer -> Bounds bound ->
             Term (outer ++ vars) -> Term (outer ++ (bound ++ vars))
  mkLocals outer bs (Local fc r idx p)
      = localAt fc r (addVars outer bs (MkNVar p))
  mkLocals outer bs (Ref fc Bound name)
      = resolvedOr (Ref fc Bound name) fc (resolveRef outer [<] bs fc name)
  mkLocals outer bs (Ref fc nt name)
      = Ref fc nt name
  mkLocals outer bs (Meta fc name y xs)
      = resolvedOr (Meta fc name y (mkLocalsTerms outer bs xs)) fc (resolveRef outer [<] bs fc name)
  mkLocals outer bs (Bind fc x b scope)
      = Bind fc x (mkLocalsBinder outer bs b)
             (mkLocals (suc outer) bs scope)
  mkLocals outer bs (App fc fn arg)
      = App fc (mkLocals outer bs fn) (mkLocals outer bs arg)
  mkLocals outer bs (As fc s as tm)
      = As fc s (mkLocals outer bs as) (mkLocals outer bs tm)
  mkLocals outer bs (TDelayed fc x y)
      = TDelayed fc x (mkLocals outer bs y)
  mkLocals outer bs (TDelay fc x t y)
      = TDelay fc x (mkLocals outer bs t) (mkLocals outer bs y)
  mkLocals outer bs (TForce fc r x)
      = TForce fc r (mkLocals outer bs x)
  mkLocals outer bs (PrimVal fc c) = PrimVal fc c
  mkLocals outer bs (Erased fc Impossible) = Erased fc Impossible
  mkLocals outer bs (Erased fc Placeholder) = Erased fc Placeholder
  mkLocals outer bs (Erased fc (Dotted t)) = Erased fc (Dotted (mkLocals outer bs t))
  mkLocals outer bs (TType fc u) = TType fc u

public export total
refsToLocals : Bounds bound -> Term vars -> Term (bound ++ vars)
refsToLocals None y = y
refsToLocals bs y = mkLocals zero  bs y

%default total

0 resolvedLocal : (m : Maybe (Var vs)) -> ResolvedAt k m -> LocalAt fc Nothing k (resolvedOr t fc m)
resolvedLocal (Just (MkVar q)) (ResolvedHere same)
    = replace {p = \x => LocalAt fc Nothing x (Local fc Nothing _ q)} same IsLocalAt

||| A bound reference to a name at the first bound that replaces it becomes
||| the local of that bound, past the binders `mkLocals` is under.
export
0 mkLocalsMarker : {0 outer, bound, vars : Scope} ->
                   (o : SizeOf outer) -> (bs : Bounds bound) -> (w : Var bound) -> FirstAt bs w n ->
                   LocalAt fc Nothing (size o + varIdx w) (mkLocals {vars} o bs (Ref fc Bound n))
mkLocalsMarker o bs w first = resolvedLocal (resolveRef o [<] bs fc n) (resolvesAt o [<] bs w first)

||| A bound reference to a name no bound replaces stays as it was.
export
0 mkLocalsUnreplaced : {0 outer, bound, vars : Scope} ->
                       (o : SizeOf outer) -> (bs : Bounds bound) -> NoneAt bs n ->
                       mkLocals {vars} o bs (Ref fc Bound n) = Ref fc Bound n
mkLocalsUnreplaced o bs none = cong (resolvedOr (Ref fc Bound n) fc) (resolveMisses o [<] bs none)

||| An unknown of a name no bound replaces stays an unknown, its arguments
||| turned in turn.
export
0 mkLocalsUnknown : {0 outer, bound, vars : Scope} -> {0 args : List (Term (outer ++ vars))} ->
                    (o : SizeOf outer) -> (bs : Bounds bound) -> NoneAt bs m ->
                    mkLocals {vars} o bs (Meta fc m k args) = Meta fc m k (mkLocalsTerms {vars} o bs args)
mkLocalsUnknown o bs none
    = cong (resolvedOr (Meta fc m k (mkLocalsTerms {vars} o bs args)) fc) (resolveMisses o [<] bs none)

||| A local below the binders `mkLocals` is under is kept.
export
0 mkLocalsBelow : {0 outer, bound, vars : Scope} ->
                  (o : SizeOf outer) -> (bs : Bounds bound) -> (0 p : IsVar nm i (outer ++ vars)) ->
                  Nat.LT i (size o) -> LocalAt fc r i (mkLocals {vars} o bs (Local fc r i p))
mkLocalsBelow o bs p lt = case insertNVarNamesIdx {outer = vars} o (sizeOf bs) (MkNVar p) of
  Left (_, same) =>
    replace {p = \k => LocalAt fc r k (mkLocals {vars} o bs (Local fc r i p))} same
            (localAtIdx (addVars o bs (MkNVar p)))
  Right (atLeast, _) => void (LTEImpliesNotGT atLeast lt)

||| A local past the binders `mkLocals` is under moves past the variables
||| it makes.
export
0 mkLocalsPast : {0 outer, bound, vars : Scope} ->
                 (o : SizeOf outer) -> (bs : Bounds bound) -> (0 p : IsVar nm i (outer ++ vars)) ->
                 Nat.LTE (size o) i -> LocalAt fc r (size (sizeOf bs) + i) (mkLocals {vars} o bs (Local fc r i p))
mkLocalsPast o bs p atLeast = case insertNVarNamesIdx {outer = vars} o (sizeOf bs) (MkNVar p) of
  Left (lt, _) => void (LTEImpliesNotGT atLeast lt)
  Right (_, same) =>
    replace {p = \k => LocalAt fc r k (mkLocals {vars} o bs (Local fc r i p))} same
            (localAtIdx (addVars o bs (MkNVar p)))

%default covering

-- Replace any reference to 'x' with a locally bound name 'new'
export
refToLocal : (x : Name) -> (new : Name) -> Term vars -> Term (new :: vars)
refToLocal x new tm = refsToLocals (Add new x None) tm

-- Replace an explicit name with a term
-- ASSUMPTION: When we substitute under binders, the name has always been
-- resolved to a Local, so no need to check that x isn't shadowing
mutual
  substNamePi : Name -> Term vars -> PiInfo (Term vars) -> PiInfo (Term vars)
  substNamePi x new (DefImplicit t) = DefImplicit (substName x new t)
  substNamePi x new p = p

  substNameBinder : Name -> Term vars -> Binder (Term vars) -> Binder (Term vars)
  substNameBinder x new (Lam fc c p ty)
      = Lam fc c (substNamePi x new p) (substName x new ty)
  substNameBinder x new (Let fc c val ty)
      = Let fc c (substName x new val) (substName x new ty)
  substNameBinder x new (Pi fc c p ty)
      = Pi fc c (substNamePi x new p) (substName x new ty)
  substNameBinder x new (PVar fc c p ty)
      = PVar fc c (substNamePi x new p) (substName x new ty)
  substNameBinder x new (PLet fc c val ty)
      = PLet fc c (substName x new val) (substName x new ty)
  substNameBinder x new (PVTy fc c ty) = PVTy fc c (substName x new ty)

  substNameTerms : Name -> Term vars -> List (Term vars) -> List (Term vars)
  substNameTerms x new [] = []
  substNameTerms x new (t :: ts) = substName x new t :: substNameTerms x new ts

  export total
  substName : Name -> Term vars -> Term vars -> Term vars
  substName x new (Ref fc nt name)
      = if x == name then new else Ref fc nt name
  substName x new (Meta fc n i xs)
      = Meta fc n i (substNameTerms x new xs)
  substName x new (Bind fc y b scope)
      = Bind fc y (substNameBinder x new b) (substName x (weaken new) scope)
  substName x new (App fc fn arg)
      = App fc (substName x new fn) (substName x new arg)
  substName x new (As fc s as pat)
      = As fc s as (substName x new pat)
  substName x new (TDelayed fc y z)
      = TDelayed fc y (substName x new z)
  substName x new (TDelay fc y t z)
      = TDelay fc y (substName x new t) (substName x new z)
  substName x new (TForce fc r y)
      = TForce fc r (substName x new y)
  substName x new tm = tm

-- A binder is visited by its type, and a let's by its value too.
mutual
  addMetasArgs : (usingResolved : Bool) -> NameMap Bool -> List (Term vars) -> NameMap Bool
  addMetasArgs res ns [] = ns
  addMetasArgs res ns (t :: ts) = addMetasArgs res (addMetas res ns t) ts

  export total
  addMetas : (usingResolved : Bool) -> NameMap Bool -> Term vars -> NameMap Bool
  addMetas res ns (Local fc x idx y) = ns
  addMetas res ns (Ref fc x name) = ns
  addMetas res ns (Meta fc n i xs)
    = addMetasArgs res (insert (ifThenElse res (Resolved i) n) False ns) xs
  addMetas res ns (Bind fc x (Let _ c val ty) scope)
      = addMetas res (addMetas res (addMetas res ns val) ty) scope
  addMetas res ns (Bind fc x (Lam _ _ _ ty) scope)
      = addMetas res (addMetas res ns ty) scope
  addMetas res ns (Bind fc x (Pi _ _ _ ty) scope)
      = addMetas res (addMetas res ns ty) scope
  addMetas res ns (Bind fc x (PVar _ _ _ ty) scope)
      = addMetas res (addMetas res ns ty) scope
  addMetas res ns (Bind fc x (PLet _ _ _ ty) scope)
      = addMetas res (addMetas res ns ty) scope
  addMetas res ns (Bind fc x (PVTy _ _ ty) scope)
      = addMetas res (addMetas res ns ty) scope
  addMetas res ns (App fc fn arg)
      = addMetas res (addMetas res ns fn) arg
  addMetas res ns (As fc s as tm) = addMetas res ns tm
  addMetas res ns (TDelayed fc x y) = addMetas res ns y
  addMetas res ns (TDelay fc x t y)
      = addMetas res (addMetas res ns t) y
  addMetas res ns (TForce fc r x) = addMetas res ns x
  addMetas res ns (PrimVal fc c) = ns
  addMetas res ns (Erased fc (Dotted t)) = addMetas res ns t
  addMetas res ns (Erased fc _) = ns
  addMetas res ns (TType fc u) = ns

-- Get the metavariable names in a term
export total
getMetas : Term vars -> NameMap Bool
getMetas tm = addMetas False empty tm

mutual
  addRefsArgs : (underAssert : Bool) -> (aTotal : Name) ->
                NameMap Bool -> List (Term vars) -> NameMap Bool
  addRefsArgs ua at ns [] = ns
  addRefsArgs ua at ns (t :: ts) = addRefsArgs ua at (addRefs ua at ns t) ts

  export total
  addRefs : (underAssert : Bool) -> (aTotal : Name) ->
            NameMap Bool -> Term vars -> NameMap Bool
  addRefs ua at ns (Local fc x idx y) = ns
  addRefs ua at ns (Ref fc x name) = insert name ua ns
  addRefs ua at ns (Meta fc n i xs) = addRefsArgs ua at ns xs
  addRefs ua at ns (Bind fc x (Let _ c val ty) scope)
      = addRefs ua at (addRefs ua at (addRefs ua at ns val) ty) scope
  addRefs ua at ns (Bind fc x (Lam _ _ _ ty) scope)
      = addRefs ua at (addRefs ua at ns ty) scope
  addRefs ua at ns (Bind fc x (Pi _ _ _ ty) scope)
      = addRefs ua at (addRefs ua at ns ty) scope
  addRefs ua at ns (Bind fc x (PVar _ _ _ ty) scope)
      = addRefs ua at (addRefs ua at ns ty) scope
  addRefs ua at ns (Bind fc x (PLet _ _ _ ty) scope)
      = addRefs ua at (addRefs ua at ns ty) scope
  addRefs ua at ns (Bind fc x (PVTy _ _ ty) scope)
      = addRefs ua at (addRefs ua at ns ty) scope
  addRefs ua at ns (App _ (App _ (Ref fc _ name) x) y)
      = if name == at
           then addRefs True at (insert name True ns) y
           else addRefs ua at (addRefs ua at (insert name ua ns) x) y
  addRefs ua at ns (App fc fn arg)
      = addRefs ua at (addRefs ua at ns fn) arg
  addRefs ua at ns (As fc s as tm) = addRefs ua at ns tm
  addRefs ua at ns (TDelayed fc x y) = addRefs ua at ns y
  addRefs ua at ns (TDelay fc x t y)
      = addRefs ua at (addRefs ua at ns t) y
  addRefs ua at ns (TForce fc r x) = addRefs ua at ns x
  addRefs ua at ns (PrimVal fc c) = ns
  addRefs ua at ns (Erased fc (Dotted t)) = addRefs ua at ns t
  addRefs ua at ns (Erased fc _) = ns
  addRefs ua at ns (TType fc u) = ns

-- As above, but for references. Also flag whether a name is under an
-- 'assert_total' because we may need to know that in coverage/totality
-- checking
export total
getRefs : (aTotal : Name) -> Term vars -> NameMap Bool
getRefs at tm = addRefs False at empty tm
