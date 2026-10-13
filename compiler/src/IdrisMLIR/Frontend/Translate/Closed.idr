||| Terms as closed values: types and implementations are compile-time
||| values, closed TT terms, which the translation substitutes, normalises
||| and reduces to their constructors.
module IdrisMLIR.Frontend.Translate.Closed

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.Env
import Core.Normalise
import Core.Options
import Core.TT
import Libraries.Data.List.SizeOf

import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Rule
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.Fin
import Data.List

%default covering

||| Idris's terms and binders; `Term` and `Binder` are Core's own.
public export
TT : Scope -> Type
TT = Core.TT.Term.Term

public export
TTBinder : Type -> Type
TTBinder = Core.TT.Binder.Binder

||| What a TT variable stands for: a Core variable (with its Core type, when a
||| match may need it, its closed Idris type where it is known, which says
||| which arguments a function-typed value takes at runtime, and the shape
||| of its value when that is known), a compile-time value, or an
||| implementation's value. Types and implementations are compile-time
||| values, closed TT terms, and so is a variable of quantity 0, which is
||| `TypeValue` of `Erased`: none is a Core variable. An implementation is
||| used by translating it where it is needed. An implementation that
||| closes over runtime values holds markers for them (`holeMarker`), with
||| the variable that holds them and what it holds (`Holes`).
public export
data VarInfo : Type -> Type where
  Runtime : a -> Maybe Ty -> Maybe ClosedTerm -> VarInfo a
  ||| A runtime value whose shape is known: the constructors every call of
  ||| the instance built its argument with (`Instances.classify`), or a
  ||| constructor's field of such a value. The shape stands for the value
  ||| in types, and a match on the value takes only the alternatives a
  ||| value of that shape can. Its Idris type is the one before the shape.
  Shaped : a -> Ty -> ClosedTerm -> ClosedTerm -> VarInfo a
  TypeValue : ClosedTerm -> VarInfo a
  Static : ClosedTerm -> Maybe (a, Holes) -> VarInfo a

export
Functor VarInfo where
  map f (Runtime x t i) = Runtime (f x) t i
  map f (Shaped x t i s) = Shaped (f x) t i s
  map f (TypeValue t) = TypeValue t
  map f (Static t h) = Static t (map (\(x, hs) => (f x, hs)) h)

||| An environment under a binder of `k` variables, which come first.
export
under : {k : Nat} -> List (VarInfo (Fin (Under k n))) -> List (VarInfo (Fin n)) ->
        List (VarInfo (Fin (Under k n)))
under bound env = bound ++ map (map (Free {k})) env

||| Does a subterm satisfy the test: the term, its binders' types and
||| values, an application's parts, a pattern's value, what a delay holds,
||| a metavariable's arguments?
export
mentions : ({0 vs : Scope} -> TT vs -> Bool) -> TT vars -> Bool
mentions p tm = p tm || case tm of
  Bind _ _ b sc => mentions p (binderType b) || binderVal b || mentions p sc
  App _ f a => mentions p f || mentions p a
  As _ _ _ pat => mentions p pat
  TDelayed _ _ t => mentions p t
  TDelay _ _ t a => mentions p t || mentions p a
  TForce _ _ t => mentions p t
  Meta _ _ _ args => any (mentions p) args
  _ => False
  where
    binderVal : TTBinder (TT vs) -> Bool
    binderVal (Let _ _ v _) = mentions p v
    binderVal (PLet _ _ v _) = mentions p v
    binderVal _ = False

||| Does the term mention `Erased` (a placeholder for an unknown value)?
export
anyErased : TT vars -> Bool
anyErased = mentions erasedTerm
  where
    erasedTerm : TT vs -> Bool
    erasedTerm (Erased _ _) = True
    erasedTerm _ = False

||| Abstracts every variable in scope with a lambda, giving a closed term whose
||| outermost lambda binds the last variable of `vars`.
wrapLams : {vars : Scope} -> FC -> TT vars -> ClosedTerm
wrapLams {vars = []} fc tm = tm
wrapLams {vars = x :: rest} fc tm =
  wrapLams {vars = rest} fc (Bind fc x (Lam fc top Explicit (Erased fc Placeholder)) tm)

||| A closed term in any scope.
export
embedClosed : {vars : Scope} -> ClosedTerm -> TT vars
embedClosed t = embed {outer = vars} t

||| Beta-reduces a closed lambda with its arguments, by substitution.
betaAll : ClosedTerm -> List ClosedTerm -> ClosedTerm
betaAll (Bind _ _ (Lam _ _ _ _) sc) (v :: vs) = betaAll (subst v sc) vs
betaAll tm vs = foldl (App EmptyFC) tm vs

||| Substitutes the outer `let`s of a closed term. Idris elaborates a record
||| update to a `let` of the record around its fields, so an implementation
||| resolved inside it is written under a `let` it does not use.
zeta : ClosedTerm -> ClosedTerm
zeta (Bind _ _ (Let _ _ v _) sc) = zeta (subst v sc)
zeta tm = tm

||| `let`s around a `Delay`, moved into it: the location of the `Delay` and
||| the `let`s around its argument. Idris elaborates `a; let x = v; b` in a
||| `do` block to `a >> (let x = v in Delay b)`. A `let` of TT has no
||| evaluation time of its own: Idris's evaluator and its inliner substitute
||| it, and the stock backend, which inlines `>>`, computes `v` where `b` is
||| forced, after `a` has run. Computed where the `Delay` is built, `v` would
||| run before `a`'s effects, and a `v` that crashes or never returns would
||| hide them. Every use of `x` is inside the `Delay`, so the `let` can move
||| there.
export
delayedLets : TT vars -> Maybe (FC, TT vars)
delayedLets (TDelay fc _ _ arg) = Just (fc, arg)
delayedLets (Bind fc x b@(Let {}) sc) = map (Bind fc x b) <$> delayedLets sc
delayedLets _ = Nothing

||| A term in scope as a closed term, with compile-time values substituted
||| and not normalised, so that an implementation keeps its written form. A
||| runtime variable becomes `Erased` with reason `Impossible`, which
||| `runtimeDependent` detects.
export
closeWritten : {vars : Scope} -> FC -> List (VarInfo a) -> TT vars -> ClosedTerm
closeWritten fc env tm = zeta (betaAll (wrapLams fc tm) (reverse (map value env)))
  where
    value : VarInfo a -> ClosedTerm
    value (TypeValue t) = t
    value (Static t _) = t
    -- A shape is what is known of the value at compile time; its holes
    -- are the runtime parts (`skeleton`).
    value (Shaped _ _ _ s) = s
    value (Runtime {}) = Erased fc Impossible

||| Does a term mention a metavariable? Idris can leave a solved one in an
||| elaborated term (the implementation for the inner pair of a triple).
hasMeta : TT vars -> Bool
hasMeta = mentions metaTerm
  where
    metaTerm : TT vs -> Bool
    metaTerm (Meta {}) = True
    metaTerm _ = False

||| A written form with the solutions of its metavariables filled in, and
||| nothing else evaluated.
export
solved : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core ClosedTerm
solved tm =
  if hasMeta tm
     then do
       defs <- get Ctxt
       normaliseHoles defs [] tm
     else pure tm

||| A metavariable applied to its arguments, as the solution the type checker
||| gave it, which Idris's evaluator and its compilers follow too. Idris
||| leaves a solved one in a checked term when it solved it after the term
||| was elaborated (a lambda postponed until its type was known). The
||| solution is a closed term: lambdas over the scope the metavariable was
||| made in, the arguments, and `let`s for that scope's `let`s; both are
||| substituted. `Nothing` for a metavariable without a solution, a hole.
export
solution : {auto c : Ref Ctxt Defs} -> {vars : Scope} ->
           FC -> Name -> List (TT vars) -> Core (Maybe (TT vars))
solution fc n args = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => internal fc ("the metavariable " ++ show n ++ " is not in the context")
  case definition def of
    PMDef _ [] (STerm _ tm) _ _ => pure (Just (apply (embedClosed tm) args zero Subst.empty))
    PMDef {} => internal fc ("the solution of " ++ show n ++ " is not a term")
    _ => pure Nothing
  where
    apply : {drop, vs : Scope} -> TT (drop ++ vs) -> List (TT vs) -> SizeOf drop -> SubstEnv drop vs -> TT vs
    apply (Bind _ _ (Lam {}) sc) (a :: as) drop env = apply sc as (suc drop) (a :: env)
    apply (Bind _ _ (Let _ _ val _) sc) as drop env = apply (subst val sc) as drop env
    apply tm as drop env = foldl (App fc) (substs drop env tm) as

||| The quantities of a definition's parameters, as its type binds them.
quantities : {auto c : Ref Ctxt Defs} -> Name -> Core (List RigCount)
quantities n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => pure []
  pure (go (type def))
  where
    go : TT vs -> List RigCount
    go (Bind _ _ (Pi _ rig _ _) sc) = rig :: go sc
    go _ = []

||| Does a written implementation depend on a runtime value: does a part
||| that stands for one (`Erased` with reason `Impossible`: a runtime
||| variable, or a part of a runtime value its shape does not say; or
||| `holeMarker`, the value an implementation closes over) stand
||| where a value exists at runtime? A type does not (a binder's type, a
||| type constructor's arguments), nor does an argument a definition or a
||| constructor takes with quantity 0, which Idris has checked is never
||| used at runtime: `Foldable (Vect n)` does not depend on the length
||| `n`, while `MkBox {v = n}` holds `n` itself.
export
runtimeDependent : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core Bool
runtimeDependent = go
  where
    anyM : List (TT vs) -> (TT vs -> Core Bool) -> Core Bool
    anyM [] f = pure False
    anyM (x :: xs) f = if !(f x) then pure True else anyM xs f

    mutual
      go : TT vs -> Core Bool
      go (Erased _ Impossible) = pure True
      go (Ref _ _ (MN "idris-mlir-hole" _)) = pure True
      go (Erased _ (Dotted t)) = go t
      go (Bind _ _ (Pi {}) _) = pure False
      go (Bind _ _ (Let _ _ v _) sc) = if !(go v) then pure True else go sc
      go (Bind _ _ (PLet _ _ v _) sc) = if !(go v) then pure True else go sc
      go (Bind _ _ _ sc) = go sc
      go (TDelay _ _ _ arg) = go arg
      go (TForce _ _ t) = go t
      go (As _ _ _ p) = go p
      go (Meta _ _ _ args) = anyM args go
      go tm@(App {}) = applied (getFnArgs tm)
      go _ = pure False

      applied : (TT vs, List (TT vs)) -> Core Bool
      applied (Ref _ (TyCon _) _, _) = pure False
      applied (Ref _ _ n, args) = do
        qs <- quantities n
        arguments (map isErased qs) args
      applied (f, args) = anyM (f :: args) go

      -- An argument past the parameters the type shows is taken as runtime.
      arguments : List Bool -> List (TT vs) -> Core Bool
      arguments _ [] = pure False
      arguments (True :: es) (_ :: as) = arguments es as
      arguments es (a :: as) = if !(go a) then pure True else arguments (drop 1 es) as

||| The normal form of a closed term, its definitions unfolded as in
||| `closeNormalise`.
export
normaliseClosed : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core ClosedTerm
normaliseClosed tm = do
  defs <- get Ctxt
  normaliseTypes defs [] tm

||| A projection: a definition that matches one of its parameters against
||| one constructor and returns one of that constructor's arguments, as
||| `fst` and an interface's parents and methods do. Its arity, the
||| position of the parameter, the constructor, and the position of the
||| argument.
export
projection : {auto c : Ref Ctxt Defs} -> Name -> Core (Maybe (Nat, Nat, Name, Nat))
projection n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => pure Nothing
  pure (case definition def of
          PMDef _ pargs (Case idx _ _ [ConCase cn _ cargs (STerm _ (Local _ _ k _))]) _ _ =>
            if k < length cargs then Just (length pargs, idx, cn, k) else Nothing
          _ => Nothing)

mutual
  ||| The constructor a compile-time value reduces to, with its arguments.
  ||| An implementation is a definition with one right-hand side, so it is
  ||| unfolded by substituting its arguments, keeping the rest as written,
  ||| whatever its visibility: one its module exports without its
  ||| definition is a module boundary, not a value. Anything else goes to
  ||| Idris's normaliser, which stops at such an implementation: a
  ||| projection it leaves takes its field from the constructor the record
  ||| reduces to here.
  export
  whnf : {auto c : Ref Ctxt Defs} -> Nat -> ClosedTerm -> Core (Maybe (Name, List ClosedTerm))
  whnf Z tm = pure Nothing
  whnf (S fuel) tm = case spineC tm [] of
    (Ref _ (DataCon _ _) n, args) => pure (Just (n, args))
    (Ref _ _ n, args) => do
      defs <- get Ctxt
      Just def <- lookupCtxtExact n (gamma defs)
        | Nothing => pure Nothing
      case definition def of
        PMDef _ pargs (STerm _ body) _ _ =>
          if length args < length pargs then pure Nothing
          else whnf fuel (betaAll (betaAll (wrapLams EmptyFC body) (reverse (take (length pargs) args)))
                                  (drop (length pargs) args))
        _ => do
          Nothing <- normalised
            | found => pure found
          Just field <- projected fuel n args
            | Nothing => pure Nothing
          whnf fuel field
    (Bind _ _ (Lam _ _ _ _) sc, a :: as) => whnf fuel (betaAll (subst a sc) as)
    (Bind _ _ (Let _ _ v _) sc, []) => whnf fuel (subst v sc)
    _ => normalised
    where
      spineC : ClosedTerm -> List ClosedTerm -> (ClosedTerm, List ClosedTerm)
      spineC (App _ f a) as = spineC f (a :: as)
      spineC f as = (f, as)
      normalised : Core (Maybe (Name, List ClosedTerm))
      normalised = do
        defs <- get Ctxt
        tm' <- normalise defs [] tm
        pure (case spineC tm' [] of
                (Ref _ (DataCon _ _) n, args) => Just (n, args)
                _ => Nothing)

  ||| A projection applied to arguments, when it applies to all of them: the
  ||| field it takes from the constructor its record reduces to, applied to
  ||| the arguments past the projection's own.
  export
  projected : {auto c : Ref Ctxt Defs} -> Nat -> Name -> List ClosedTerm -> Core (Maybe ClosedTerm)
  projected fuel n args = do
    Just (arity, idx, cn, k) <- projection n
      | Nothing => pure Nothing
    let True = length args >= arity
      | False => pure Nothing
    let Just whole = getAt idx args
      | Nothing => pure Nothing
    Just (built, fields) <- whnf fuel whole
      | Nothing => pure Nothing
    let Just field = getAt k fields
      | Nothing => pure Nothing
    if !(toFullNames built) /= !(toFullNames cn)
       then pure Nothing
       else pure (Just (foldl (App EmptyFC) field (drop arity args)))

||| The implementation a written one stands for, so that two are compared
||| by what they are: the name of an implementation applied to its
||| arguments, each of them an implementation reduced in turn, once what
||| leads to it is reduced: a projection of a constructor's argument (an
||| implementation's constraints, which Idris passes as one tuple, taken
||| apart with `fst` and `snd`; a parent taken from an implementation), a
||| `let`, an applied lambda. The implementation itself is not unfolded.
export
implementationOf : {auto c : Ref Ctxt Defs} -> Nat -> ClosedTerm -> Core ClosedTerm
implementationOf Z tm = pure tm
implementationOf (S fuel) tm = case getFnArgs tm of
  (Bind _ _ (Lam {}) sc, a :: as) => implementationOf fuel (betaAll (subst a sc) as)
  (Bind fc _ (Let _ _ v _) sc, as) => implementationOf fuel (foldl (App fc) (subst v sc) as)
  (f@(Ref fc _ n), args) => do
    Just field <- projected fuel n args
      | Nothing => foldl (App fc) f <$> traverse (implementationOf fuel) args
    implementationOf fuel field
  _ => pure tm

||| Which arguments of a constructor are erased, by position.
export
erasedArgs : {auto c : Ref Ctxt Defs} -> Name -> Core (List Bool)
erasedArgs n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => pure []
  pure (go (type def))
  where
    go : TT vs -> List Bool
    go (Bind _ _ (Pi _ rig _ _) sc) = isErased rig :: go sc
    go _ = []

||| A term as a message shows it, every name full: a name Idris has
||| resolved to its place in the context prints as `$resolved359`, which
||| says nothing to the reader.
export
showTT : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core String
showTT tm = show <$> toFullNames tm

||| What a shape says a value was built with: a constructor, with the
||| shapes of its arguments. A shape that is no constructor application (an
||| erased part) says nothing of the value.
export
shapeHead : ClosedTerm -> Maybe (Name, List ClosedTerm)
shapeHead tm = case getFnArgs tm of
  (Ref _ (DataCon _ _) n, args) => Just (n, args)
  _ => Nothing

||| The shape of a term as written: the constructors it is built with,
||| everything else erased, and nothing when its head is no constructor.
||| Nothing is evaluated: a constant, a variable or a call says nothing.
||| What the shape does not say is a part of a runtime value, so a hole
||| has the reason `Impossible`, as a runtime variable has in the written
||| form: `runtimeDependent` refuses it wherever a value is needed.
export
skeleton : ClosedTerm -> Maybe ClosedTerm
skeleton tm = case getFnArgs tm of
  (con@(Ref fc (DataCon _ _) _), args) =>
    Just (foldl (App fc) con (map (\a => fromMaybe (Erased fc Impossible) (skeleton a)) args))
  _ => Nothing

||| A runtime value of a type with what its shape says, if anything.
export
shaped : a -> Ty -> ClosedTerm -> ClosedTerm -> VarInfo a
shaped x t ity s = if isJust (shapeHead s) then Shaped x t ity s else Runtime x (Just t) (Just ity)

||| How many constructors deep a shape says what the value was built with.
export
shapeDepth : ClosedTerm -> Nat
shapeDepth tm = case shapeHead tm of
  Just (_, args) => S (foldl (\d, a => max d (shapeDepth a)) 0 args)
  Nothing => Z

||| A shape cut at a depth: every part below it, and every part the shape
||| does not say, is `hole`.
export
cutShape : ClosedTerm -> Nat -> ClosedTerm -> ClosedTerm
cutShape hole Z _ = hole
cutShape hole (S d) tm = case getFnArgs tm of
  (con@(Ref fc (DataCon _ _) _), args) => foldl (App fc) con (map (cutShape hole d) args)
  _ => hole

||| What a shape leaves unknown of a runtime value, where a type is asked
||| whether it needs it: a reference to a definition that does not exist,
||| at which reduction stops exactly where it would need the value. Idris's
||| quotation gives such a function back as it was, where it would take a
||| bound machine name for one of the binders it makes, by its number.
export
unknownPart : ClosedTerm
unknownPart = Ref EmptyFC Func (MN "idris-mlir-unknown" 0)

||| A runtime value an implementation closes over, where its compile-time
||| form stands (`PKind.DictParam`, `VarInfo.Static`), by its number among
||| the values (`Holes`): a bound name that no binder binds, which
||| reduction treats as the variable it stands for, and which a translation
||| of the implementation replaces with the value (`Terms.term`).
export
holeMarker : Nat -> ClosedTerm
holeMarker i = Ref EmptyFC Bound (MN "idris-mlir-hole" (cast i))

||| Replaces each marker of the values an implementation closes over with
||| the term for its value, by number.
export
fillHoles : List ClosedTerm -> ClosedTerm -> ClosedTerm
fillHoles values tm = foldl fill tm (zip [0 .. length values] values)
  where
    fill : ClosedTerm -> (Nat, ClosedTerm) -> ClosedTerm
    fill t (i, v) = substName (MN "idris-mlir-hole" (cast i)) v t

||| A reference to a definition, as Idris writes one: with its kind.
export
refTo : {auto c : Ref Ctxt Defs} -> FC -> Name -> Core ClosedTerm
refTo fc n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => throw (InternalError ("no definition of " ++ show n))
  pure (Ref fc (kind (definition def)) (fullname def))
  where
    kind : Def -> NameType
    kind (DCon tag arity _) = DataCon tag arity
    kind (TCon arity _ _ _ _ _ _) = TyCon arity
    kind _ = Func

||| The pair Idris's `%pair` names: its type, its projections.
export
pairNames : {auto c : Ref Ctxt Defs} -> Core (Name, Name, Name)
pairNames = do
  defs <- get Ctxt
  let Just ns = pairnames (options defs)
    | Nothing => throw (InternalError "no pair type")
  pure (pairType ns, fstName ns, sndName ns)

||| The type of the one value that holds the values an implementation closes
||| over: the one type, or a pair of the first and the rest.
export
packedType : {auto c : Ref Ctxt Defs} -> List ClosedTerm -> Core ClosedTerm
packedType [t] = pure t
packedType (t :: ts) = do
  (pair, _, _) <- pairNames
  p <- refTo EmptyFC pair
  pure (App EmptyFC (App EmptyFC p t) !(packedType ts))
packedType [] = throw (InternalError "no value to hold")

||| The values the one value holds (`packedType`), as projections of it.
export
unpacked : {auto c : Ref Ctxt Defs} -> List ClosedTerm -> ClosedTerm -> Core (List ClosedTerm)
unpacked [_] v = pure [v]
unpacked (t :: ts) v = do
  (_, first, second) <- pairNames
  f <- refTo EmptyFC first
  s <- refTo EmptyFC second
  rest <- packedType ts
  let proj = \p => App EmptyFC (App EmptyFC (App EmptyFC p t) rest) v
  (proj f ::) <$> unpacked ts (proj s)
unpacked [] _ = pure []

||| Does a term mention `holeMarker`?
export
mentionsHole : TT vars -> Bool
mentionsHole = mentions hole
  where
    hole : TT vs -> Bool
    hole (Ref _ _ (MN "idris-mlir-hole" _)) = True
    hole _ = False

||| Does a term mention `unknownPart`?
export
mentionsUnknown : TT vars -> Bool
mentionsUnknown = mentions unknownRef
  where
    unknownRef : TT vs -> Bool
    unknownRef (Ref _ _ (MN "idris-mlir-unknown" _)) = True
    unknownRef _ = False

||| A type-level parameter: its type is a universe, possibly after Pi binders.
export
isTypeLike : TT vars -> Bool
isTypeLike (TType _ _) = True
isTypeLike (Bind _ _ (Pi _ _ _ _) sc) = typeLikeScope sc
  where
    typeLikeScope : TT vs -> Bool
    typeLikeScope (TType _ _) = True
    typeLikeScope (Bind _ _ (Pi _ _ _ _) s) = typeLikeScope s
    typeLikeScope _ = False
isTypeLike _ = False

export
lookupDef : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            FC -> String -> Name -> Core GlobalDef
lookupDef fc owner n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => reject fc owner CompiledModule ("missing definition " ++ show n)
  pure def

||| Does a definition compute a type: is its type, normalised, a universe
||| after its arguments? Normalised, since a type may be written with a
||| name for one: `VarSet : Scoped` is `Scope -> Type`.
export
computesType : {auto c : Ref Ctxt Defs} -> GlobalDef -> Core Bool
computesType def = do
  defs <- get Ctxt
  pure (isTypeLike !(normaliseTypes defs [] (type def)))

||| A type argument as data instances compare them. A type-level function
||| and the lambda of its one clause are the same argument: elaboration
||| leaves the name in one type and the clause in another (`Printed`, and
||| `\n => (Fin n -> Nat) -> Nat -> String`), including where the name is
||| an argument of another type (`List (AltF Printed _)`). The clause is
||| inlined where the name stands, when that clause is a function type.
||| An applied name is left to normalisation, and so is an alias of a
||| data type: normalisation has already made those one type.
export
canonicalTypeArg : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core ClosedTerm
canonicalTypeArg tm = walk False [] tm
  where
    -- Reduced to a name, rather than staying a lambda over its clause.
    etaContracted : {vars : _} -> TT vars -> Bool
    etaContracted (Bind _ _ (Lam {}) sc) = etaContracted sc
    etaContracted (Ref _ Func _) = True
    etaContracted _ = False

    -- A function type, under the lambdas of the clause. `Printed n` is
    -- `(Fin n -> Nat) -> Nat -> String`. An alias of a data type
    -- (`Scopeable a = List a`) is already that data type once normalised.
    hasPi : {vars : _} -> TT vars -> Bool
    hasPi (Bind _ _ (Pi {}) _) = True
    hasPi (Bind _ _ (Lam {}) sc) = hasPi sc
    hasPi (App _ f a) = hasPi f || hasPi a
    hasPi _ = False

    normaliseClause : {vs : _} -> FC -> TT vs -> Core (Maybe ClosedTerm)
    normaliseClause fc body = do
      defs <- get Ctxt
      let written = wrapLams fc body
      -- A name with no argument (`Scope = List Name`) is already reduced
      -- by ordinary normalisation wherever it is applied. Inlining it
      -- here turns a parameter into a value at one site only.
      case written of
        Bind _ _ (Lam {}) _ => do
          nf <- normaliseTypes defs [] written
          -- Quoting can put the name back; the clause is kept as written.
          let chosen = if etaContracted nf then written else nf
          pure (if hasPi chosen then Just chosen else Nothing)
        _ => pure Nothing

    -- The lambda of a type-level function's one clause, or nothing when
    -- the name is not such a function.
    clause : FC -> Name -> Core (Maybe ClosedTerm)
    clause fc n = do
      defs <- get Ctxt
      Just gdef <- lookupCtxtExact n (gamma defs)
        | Nothing => pure Nothing
      -- The type as written is enough for `Nat -> Type`. A name for one
      -- (`VarSet : Scoped`) needs the normalised type, and that lookup is
      -- the uncommon case.
      yes <- if isTypeLike (type gdef) then pure True else computesType gdef
      if yes then case definition gdef of
             PMDef _ _ _ _ [(_ ** (_, _, body))] => normaliseClause fc body
             PMDef _ _ (STerm _ body) _ _ => normaliseClause fc body
             _ => pure Nothing
        else pure Nothing

    -- The names whose clauses are being inlined. A clause that mentions
    -- its own name stays a name there: inlining it again would not end.
    -- `head` is the function of an application: that name is left to
    -- normalisation, and only its arguments are inlined. Replacing an
    -- applied name with its clause and not reducing the application is
    -- a different type than the reduced one.
    walk : {vars : _} -> Bool -> List Name -> TT vars -> Core (TT vars)
    walk head stack (Ref fc Func n) =
      if head || elem n stack then pure (Ref fc Func n) else do
        -- The clause is already the form elaboration uses. Walking it
        -- would inline the names it mentions into types that were left
        -- as names, and a call would no longer match its function.
        Nothing <- clause fc n
          | Just lam => pure (embedClosed lam)
        pure (Ref fc Func n)
    -- Elaboration writes a type family as `f` in one type and as
    -- `(\x => f x)` in another. They name one data instance.
    walk _ stack tm@(Bind _ _ (Lam {}) (App _ fn (Local _ _ Z _))) =
      case shrink fn (Drop Refl) of
        Just fn' => walk False stack fn'
        Nothing => pure tm
    walk _ stack (App fc f a) = App fc <$> walk True stack f <*> walk False stack a
    walk _ stack (Meta fc n i args) = Meta fc n i <$> traverse (walk False stack) args
    walk _ stack (TDelayed fc r t) = TDelayed fc r <$> walk False stack t
    walk _ stack (TDelay fc r ty a) = TDelay fc r <$> walk False stack ty <*> walk False stack a
    walk _ stack (TForce fc r t) = TForce fc r <$> walk False stack t
    walk _ stack (As fc s p q) = As fc s <$> walk False stack p <*> walk False stack q
    walk _ _ tm = pure tm

||| A runtime variable in a term closed for normalisation: a reference to a
||| definition that does not exist, which no reduction looks into.
runtimeVariable : ClosedTerm
runtimeVariable = Ref EmptyFC Func (MN "idris-mlir-runtime" 0)

isRuntimeVariable : TT vs -> Bool
isRuntimeVariable (Ref _ _ (MN "idris-mlir-runtime" _)) = True
isRuntimeVariable _ = False

||| A type in which no computation is run on a runtime variable: what is
||| known of one is its constructors, as written, so a constructor or a type
||| constructor applied to one stays, and any other call to one, a
||| computation of a value, is unknown (`Erased`), as a runtime argument's
||| shape is read (`skeleton`). A computation on a value nothing is known of
||| can only be stuck, or never end: a parser's, built of closures that call
||| one another, unfolds without end once normalised under them. A function
||| that does not match on its arguments runs nothing on the value
||| (`(PiInfo . Term) vars`): it is unfolded, as far as a depth, and what it
||| calls is cut in turn. A function
||| whose result is a type (`IsNothing m = m = Nothing`) is no such
||| computation: the type it gives is needed whatever the value, and is cut
||| inside instead. Nor is a lambda applied to one, a type family at a
||| value (`(\m => Vect m Int) n`), which is substituted. A value whose
||| constructors are known (`Shaped`) is no runtime variable, and a type
||| still reduces on it.
cutRuntime : {auto c : Ref Ctxt Defs} -> {vars : Scope} -> TT vars -> Core (TT vars)
cutRuntime = cut 64
  where
    typeFunction : Name -> Core Bool

    -- The definition of a function that does not match on its arguments,
    -- as lambdas over them, and how many it takes.
    plain : Name -> Core (Maybe (ClosedTerm, Nat))

    binder : {vs : Scope} -> Nat -> TTBinder (TT vs) -> Core (TTBinder (TT vs))

    cut : {vs : Scope} -> Nat -> TT vs -> Core (TT vs)
    cut fuel tm =
      if not (mentions isRuntimeVariable tm) then pure tm else case getFnArgs tm of
        (Bind fc _ (Lam {}) sc, a :: as) => cut fuel (foldl (App fc) (subst a sc) as)
        (Bind fc x b sc, []) => Bind fc x <$> binder fuel b <*> cut fuel sc
        (TDelayed fc r t, []) => TDelayed fc r <$> cut fuel t
        (h@(Ref fc (DataCon _ _) _), args) => foldl (App fc) h <$> traverse (cut fuel) args
        (h@(Ref fc (TyCon _) _), args) => foldl (App fc) h <$> traverse (cut fuel) args
        (h@(Ref fc Func n), args) =>
          if !(typeFunction n)
             then foldl (App fc) h <$> traverse (cut fuel) args
             -- A function that does not match on its arguments runs
             -- nothing on the value (`(.)` in `(PiInfo . Term) vars`): it
             -- is unfolded, and what it calls is cut in turn.
             else case (fuel, !(plain n)) of
               (S fuel', Just (body, arity)) =>
                 if length args < arity then pure (Erased fc Placeholder)
                 else cut fuel' (foldl (App fc) (embedClosed body)
                                       (reverse (take arity args) ++ drop arity args))
               _ => pure (Erased fc Placeholder)
        _ => pure (Erased EmptyFC Placeholder)

    typeFunction n = do
      defs <- get Ctxt
      Just def <- lookupCtxtExact n (gamma defs)
        | Nothing => pure False
      computesType def

    plain n = do
      defs <- get Ctxt
      Just def <- lookupCtxtExact n (gamma defs)
        | Nothing => pure Nothing
      case definition def of
        PMDef _ pargs (STerm _ body) _ _ => pure (Just (wrapLams EmptyFC body, length pargs))
        _ => pure Nothing

    binder fuel (Lam bfc r p ty) = Lam bfc r p <$> cut fuel ty
    binder fuel (Let bfc r val ty) = Let bfc r <$> cut fuel val <*> cut fuel ty
    binder fuel (Pi bfc r p ty) = Pi bfc r p <$> cut fuel ty
    binder fuel (PVar bfc r p ty) = PVar bfc r p <$> cut fuel ty
    binder fuel (PLet bfc r val ty) = PLet bfc r <$> cut fuel val <*> cut fuel ty
    binder fuel (PVTy bfc r ty) = PVTy bfc r <$> cut fuel ty

||| The closed normal form of a term in scope, with type variables replaced by
||| their known values and every runtime variable by `Erased`, once every
||| computation on one is cut (`cutRuntime`). A solved metavariable is
||| filled in first: it stands applied to every variable in scope where it
||| was made, runtime ones too, which its solution need not use. A
||| definition that computes a type unfolds whatever its visibility
||| (`normaliseTypes`): Idris's plain `normalise` keeps a `private` function
||| of another module as it is (a type-level function such as
||| Data.SortedMap's `delType`), which is a module boundary, not a value.
||| Any other unfolds as Idris's own normalisation unfolds it: a value whose
||| definition its module keeps to itself stays as it is (a parser's, whose
||| closures, normalised, would unfold without end).
export
closeNormalise : {auto c : Ref Ctxt Defs} -> {vars : Scope} ->
                 FC -> List (VarInfo a) -> TT vars -> Core ClosedTerm
closeNormalise fc env tm = do
  closed <- solved (betaAll (wrapLams fc tm) (reverse (map value env)))
  defs <- get Ctxt
  normaliseTypes defs [] !(cutRuntime closed)
  where
    value : VarInfo a -> ClosedTerm
    value (TypeValue t) = t
    value (Static t _) = t
    value (Shaped _ _ _ s) = s
    value (Runtime {}) = runtimeVariable
