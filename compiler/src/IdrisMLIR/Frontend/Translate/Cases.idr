-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Case trees: Idris's compile-time case trees (`treeCT`) as Core matches.
||| A match on a compile-time value selects its alternative now, and so does
||| a match on a value of a type with one runtime field, which is its
||| field's value.
module IdrisMLIR.Frontend.Translate.Cases

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Dictionaries
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Forced
import IdrisMLIR.Frontend.Translate.Shapes
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Terms
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Syntax.Idr
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.Fin
import Data.List
import Data.String
import Data.SortedMap
import Data.Vect

%default covering

||| The variables a constructor alternative binds, in argument order: a
||| parameter is the instance's value, an argument of quantity 0 a
||| compile-time one, a dictionary field the implementation the program
||| builds it with (`impls`, by position), and runtime field `i` the
||| alternative's `Bound i`, with what the value's shape says of it
||| (`shapes`, by position).
argInfos : {k : Nat} -> {0 nv : Nat} -> List ArgKind -> List (Nat, ClosedTerm) -> List ClosedTerm ->
           List (VarInfo (Fin (Under k nv)))
argInfos kinds impls shapes = zipWith info [0 .. length kinds] kinds
  where
    info : Nat -> ArgKind -> VarInfo (Fin (Under k nv))
    info p (Param v) = TypeValue v
    info p ErasedArg = TypeValue (Erased EmptyFC Placeholder)
    info p (DictArg _) = Static (fromMaybe (Erased EmptyFC Placeholder) (lookup p impls)) Nothing
    info p (Field i b ity) = case natToFin i k of
      Just f => case getAt p shapes of
        Just s => shaped (Bound {n = nv} f) (typeOf b) ity s
        Nothing => Runtime (Bound {n = nv} f) (Just (typeOf b)) (Just ity)
      Nothing => TypeValue (Erased EmptyFC Placeholder)

||| The positions of a constructor's dictionary fields, among its arguments.
dictPositions : List ArgKind -> List Nat
dictPositions kinds = mapMaybe dict (zip [0 .. length kinds] kinds)
  where
    dict : (Nat, ArgKind) -> Maybe Nat
    dict (i, DictArg _) = Just i
    dict _ = Nothing

||| The implementations a constructor's dictionary fields hold, by
||| position; `Nothing` when no construction site has given one yet, and
||| the constructor has no value (`Dictionaries`).
dictionariesOf : {auto s : Ref TState TS} -> ConId -> List ArgKind -> Core (Maybe (List (Nat, ClosedTerm)))
dictionariesOf cid kinds = do
  found <- traverse (\i => map (i,) <$> dictionaryOf cid i) (dictPositions kinds)
  pure (sequence found)

||| What a runtime variable's binder says of it: its Core type, its Idris
||| type, the shape of its value, and the variable.
coreTyOf : VarInfo a -> Maybe Ty
coreTyOf (Runtime _ t _) = t
coreTyOf (Shaped _ t _ _) = Just t
coreTyOf _ = Nothing

idrisTypeOf : VarInfo a -> Maybe ClosedTerm
idrisTypeOf (Runtime _ _ t) = t
idrisTypeOf (Shaped _ _ t _) = Just t
idrisTypeOf _ = Nothing

shapeOf : VarInfo a -> Maybe ClosedTerm
shapeOf (Shaped _ _ _ s) = Just s
shapeOf _ = Nothing

variableOf : VarInfo a -> Maybe a
variableOf (Runtime x _ _) = Just x
variableOf (Shaped x _ _ _) = Just x
variableOf _ = Nothing

||| A leaf no input reaches: `Unreachable` in a covering definition
||| (Idris proved no input reaches it), a crash otherwise.
missingCase : {0 nv : Nat} -> Ctx -> Loc -> IdrisMLIR.Term.Term nv
missingCase ctx loc =
  if ctx.complete then Unreachable loc else Crash loc ("unhandled input for " ++ ctx.owner)

||| Does the shape of the matched value, if known, rule out the alternative
||| for this constructor? A value built with another constructor never
||| takes it, and the alternative's code, typed at the other constructor,
||| need not fit the instance.
excludedBy : {auto c : Ref Ctxt Defs} -> Maybe ClosedTerm -> Name -> Core Bool
excludedBy shape cn = case maybe Nothing shapeHead shape of
  Just (built, _) => (/=) <$> toFullNames built <*> toFullNames cn
  Nothing => pure False

||| The shapes of a constructor's arguments, from the shape of the value.
shapeArgs : Maybe ClosedTerm -> List ClosedTerm
shapeArgs shape = maybe [] snd (maybe Nothing shapeHead shape)

conName : CaseAlt vars -> Maybe Name
conName (ConCase cn _ _ _) = Just cn
conName _ = Nothing

||| Every constructor of the type a match's constructors build.
siblings : {auto c : Ref Ctxt Defs} -> List (CaseAlt vars) -> Core (List Name)
siblings alts = case mapMaybe conName alts of
  [] => pure []
  (cn :: _) => do
    defs <- get Ctxt
    Just def <- lookupCtxtExact cn (gamma defs)
      | Nothing => pure []
    let Just tn = built (type def)
      | Nothing => pure []
    Just tdef <- lookupCtxtExact tn (gamma defs)
      | Nothing => pure []
    case definition tdef of
      TCon _ _ _ _ _ (Just cons) _ => pure cons
      _ => pure []
  where
    built : TT vs -> Maybe Name
    built (Bind _ _ (Pi {}) sc) = built sc
    built tm = case getFnArgs tm of
      (Ref _ (TyCon _) tn, _) => Just tn
      _ => Nothing

||| Does a match name every constructor of the type? Then its default, which
||| Idris's tree keeps for the clauses after a complete split, stands for
||| no value: it is not translated, and the match has none.
coversAll : {auto c : Ref Ctxt Defs} -> List (CaseAlt vars) -> Core Bool
coversAll alts = do
  named <- traverse toFullNames (mapMaybe conName alts)
  every <- traverse toFullNames !(siblings alts)
  pure (not (null every) && all (\c => elem c named) every)

||| Does a match name the constructor the value's shape, if known, says it
||| was built with? Then its default stands for no value the match sees, and
||| its code, which may call for instances no value needs (one a constructor
||| deeper, where a shape keys the instance), is not translated.
builtNamed : {auto c : Ref Ctxt Defs} -> Maybe ClosedTerm -> List (CaseAlt vars) -> Core Bool
builtNamed shape alts = case the (Maybe (Name, List ClosedTerm)) (shape >>= shapeHead) of
  Just (cn, _) => do
    named <- traverse toFullNames (mapMaybe conName alts)
    pure (elem !(toFullNames cn) named)
  Nothing => pure False

||| The type of a variable of a case tree's scope, as its binder gives it:
||| a parameter of the definition, or an argument of the constructor an
||| alternative matched. Its variable `i` is the variable at position
||| `at i` of the scope, if the binder's telescope binds it. Idris's
||| compile-time tree does not keep the type of the value it matches.
export
data Typed : Type where
  MkTyped : {0 sc : Scope} -> TT sc -> (Nat -> Maybe Nat) -> Typed

||| The types of the first `k` binders of a telescope, in order, as the
||| first `k` positions of a scope: binder `p`'s variable `i` is binder
||| `p - 1 - i`.
export
telescope : Nat -> ClosedTerm -> List (Maybe Typed)
telescope k = go 0
  where
    go : Nat -> TT vs -> List (Maybe Typed)
    go p tm = if p >= k then [] else case tm of
      Bind _ _ (Pi _ _ _ a) sc =>
        Just (MkTyped a (\i => if i < p then Just (minus p (S i)) else Nothing)) :: go (S p) sc
      _ => replicate (minus k p) Nothing

||| A variable's type once matches have shown the locals it mentions. A
||| known constructor becomes that view; its arguments stay env positions,
||| which is what lining the constructor's result up against the view needs.
viewOf : Typed -> List (Maybe Known) -> View
viewOf (MkTyped tm at) known = case getFnArgs tm of
  -- An index the type does not place in the environment decides nothing.
  -- One still a variable is `VLocal`: a concrete constructor on the other
  -- side then does not fit. A match records `VRef` through `KnownCon`.
  (Local _ _ i _, []) => case at i of
    Just p => case getAt p known of
      Just (Just (KnownCon n ps)) => VRef n (map VLocal ps)
      _ => VLocal p
    Nothing => VSkip
  (Ref _ _ n, args) => VRef n (map (\a => viewOf (MkTyped a at) known) args)
  (PrimVal _ c, []) => VLit c
  _ => VSkip

replaceAt : Nat -> a -> List a -> List a
replaceAt Z v (_ :: xs) = v :: xs
replaceAt (S i) v (x :: xs) = x :: replaceAt i v xs
replaceAt _ _ xs = xs

||| Substitute pattern-argument locals with terms learned from the
||| scrutinee. `Nothing` when a local has no learned term, or the domain
||| binds its own variable: the generic telescope entry then stays, and
||| its `at` already names pattern-argument positions.
substDomain : {0 sc : _} -> {0 vs : _} -> Nat -> List (Maybe (TT sc)) -> TT vs -> Maybe (TT sc)
substDomain p learned t = go t
  where
    go : {0 vs' : _} -> TT vs' -> Maybe (TT sc)
    go (Local _ _ i _) =
      if i >= p then Nothing
      else case getAt (minus p (S i)) learned of
        Just (Just tm) => Just tm
        _ => Nothing
    go (Ref fc nt n) = Just (Ref fc nt n)
    go (App fc f a) = App fc <$> go f <*> go a
    go (PrimVal fc c) = Just (PrimVal fc c)
    go (TType fc u) = Just (TType fc u)
    go (Erased fc Placeholder) = Just (Erased fc Placeholder)
    go (Erased fc Impossible) = Just (Erased fc Impossible)
    go (Erased fc (Dotted d)) = (\d' => Erased fc (Dotted d')) <$> go d
    go (TDelayed fc r d) = TDelayed fc r <$> go d
    go (TDelay fc r ty a) = TDelay fc r <$> go ty <*> go a
    go (TForce fc r d) = TForce fc r <$> go d
    go _ = Nothing

bindPat : {0 sc : _} -> Nat -> List (Maybe (TT sc)) -> TT sc -> Maybe (List (Maybe (TT sc)))
bindPat pat learned rhs = case getAt pat learned of
  Just Nothing => Just (replaceAt pat (Just rhs) learned)
  Just (Just old) => if eqTerm old rhs then Just learned else Nothing
  Nothing => Nothing

unifyLearned : {auto c : Ref Ctxt Defs} -> {0 sc : _} -> {0 vs : _} ->
               Nat -> List (Maybe (TT sc)) -> TT vs -> TT sc ->
               Core (Maybe (List (Maybe (TT sc))))
unifyLearned k learned (Local _ _ i _) rhs =
  if i < k then pure (bindPat (minus k (S i)) learned rhs) else pure Nothing
unifyLearned k learned lhs rhs = case (getFnArgs lhs, getFnArgs rhs) of
  ((Ref _ _ n, as), (Ref _ _ m, bs)) => do
    same <- (==) <$> toFullNames n <*> toFullNames m
    if same && length as == length bs then unifyArgs learned (zip as bs) else pure Nothing
  ((PrimVal _ c, []), (PrimVal _ d, [])) =>
    pure (if c == d then Just learned else Nothing)
  ((TType {}, []), (TType {}, [])) => pure (Just learned)
  ((Erased _ Placeholder, []), (Erased _ Placeholder, [])) => pure (Just learned)
  ((Erased _ Impossible, []), (Erased _ Impossible, [])) => pure (Just learned)
  _ => pure Nothing
  where
    unifyArgs : List (Maybe (TT sc)) -> List (TT vs, TT sc) -> Core (Maybe (List (Maybe (TT sc))))
    unifyArgs acc [] = pure (Just acc)
    unifyArgs acc ((a, b) :: rest) = do
      Just acc' <- unifyLearned k acc a b
        | Nothing => pure Nothing
      unifyArgs acc' rest

||| Binders of the constructor's result, learned by unifying that result
||| with the scrutinee. The terms are in the scrutinee's scope.
learnBinders : {auto c : Ref Ctxt Defs} -> {0 sc : _} -> {0 vs : _} ->
               Nat -> TT vs -> TT sc -> Core (Maybe (List (Maybe (TT sc))))
learnBinders k ty rhs = walk k (replicate k Nothing) ty
  where
    walk : {0 vs' : _} -> Nat -> List (Maybe (TT sc)) -> TT vs' ->
           Core (Maybe (List (Maybe (TT sc))))
    walk Z learned ret = unifyLearned k learned ret rhs
    walk (S n) learned (Bind _ _ (Pi {}) sc) = walk n learned sc
    walk _ _ _ = pure Nothing

||| Domains whose binders all substitute, written at the scrutinee's
||| `at` shifted by `k`: this `Typed` sits in the new arguments, which
||| are not shifted again. A domain that does not substitute keeps its
||| generic telescope entry.
fillDomains : {0 sc : _} -> {0 vs : _} -> Nat -> (Nat -> Maybe Nat) ->
              List (Maybe (TT sc)) -> List (Maybe Typed) -> TT vs -> List (Maybe Typed)
fillDomains k scAt learned generic ty = go 0 generic ty
  where
    shifted : Nat -> Maybe Nat
    shifted i = map (+ k) (scAt i)
    go : {0 vs' : _} -> Nat -> List (Maybe Typed) -> TT vs' -> List (Maybe Typed)
    go p (g :: gs) (Bind _ _ (Pi _ _ _ a) sc) =
      let here = case substDomain p learned a of
                   Just tm => Just (MkTyped tm shifted)
                   Nothing => g
      in here :: go (S p) gs sc
    go _ gs _ = gs

||| The types of an alternative's scope: the `k` arguments of the
||| constructor it matches, in front of the scope of the match. Where the
||| scrutinee's type is known, an argument domain is that type's instance
||| of the domain, so a nested match sees the field's specialised type
||| and an erased outer variable can be bound to the runtime field.
alternativeTypes : {auto c : Ref Ctxt Defs} ->
                   Name -> Nat -> Maybe Typed -> List (Maybe Typed) -> Core (List (Maybe Typed))
alternativeTypes cn k scTy tys = do
  defs <- get Ctxt
  found <- lookupCtxtExact cn (gamma defs)
  let generic = maybe (replicate k Nothing) (telescope k . type) found
  args <- case (scTy, found) of
    (Just (MkTyped sc scAt), Just def) => do
      learned <- learnBinders k (type def) sc
      pure (case learned of
              Just bs => fillDomains k scAt bs generic (type def)
              Nothing => generic)
    _ => pure generic
  pure (args ++ map (map (shift k)) tys)
  where
    shift : Nat -> Typed -> Typed
    shift n (MkTyped t at) = MkTyped t (map (+ n) . at)

||| The variables of the matched value's type that a constructor's type
||| equates with its arguments, as pairs of the variable's position and the
||| argument's: where the value's type has a variable (`Tag n`), the
||| constructor's result has one of its own arguments (`MkTag : (n : Nat)
||| -> Tag n`), and the two are one value in the alternative. Idris's
||| compile-time tree names whichever of the two unification kept, which
||| can be the index where the program wrote the field: `f (MkTag k) = k`
||| returns `n`.
equated : {auto c : Ref Ctxt Defs} -> Nat -> ClosedTerm -> Maybe Typed -> Core (List (Nat, Nat))
equated k conTy Nothing = pure []
equated k conTy (Just (MkTyped scTy at)) = go k conTy
  where
    pairs : TT cs -> TT vs -> Core (List (Nat, Nat))
    pairs (Local _ _ i _) (Local _ _ j _) =
      pure (case at j of
              Just v => if i < k then [(v, minus k (S i))] else []
              Nothing => [])
    pairs con sc = case (getFnArgs con, getFnArgs sc) of
      ((Ref _ _ n, as), (Ref _ _ m, bs)) => do
        same <- (==) <$> toFullNames n <*> toFullNames m
        if same && length as == length bs
           then concat <$> traverse (\(a, b) => pairs a b) (zip as bs)
           else pure []
      _ => pure []

    go : Nat -> TT cs -> Core (List (Nat, Nat))
    go Z ret = pairs ret scTy
    go (S r) (Bind _ _ (Pi {}) sc) = go r sc
    go _ _ = pure []

||| An alternative's variables, with each erased variable that its
||| constructor equates with a runtime argument (`equated`) bound to that
||| argument: the two are one value, which the argument holds at runtime.
||| Several outer variables can be that same argument (`Refl` makes the
||| two indices of a `Thin` one list). The case tree names the erased
||| one, and a runtime parameter is passed the list.
bindEquated : Nat -> List (Nat, Nat) -> List (VarInfo b) -> List (VarInfo b)
bindEquated k eqs env = foldl one (share eqs env) eqs
  where
    runtime : VarInfo b -> Bool
    runtime (Runtime _ (Just _) _) = True
    runtime (Shaped {}) = True
    runtime _ = False

    erased : VarInfo b -> Bool
    erased (TypeValue (Erased _ _)) = True
    erased _ = False

    setAt : Nat -> VarInfo b -> List (VarInfo b) -> List (VarInfo b)
    setAt Z v (_ :: xs) = v :: xs
    setAt (S i) v (x :: xs) = x :: setAt i v xs
    setAt _ _ [] = []

    atOuter : Nat -> List (VarInfo b) -> Maybe (VarInfo b)
    atOuter j e = getAt (k + j) e

    -- A runtime outer variable equated with this pattern argument.
    runtimeOuter : Nat -> List (Nat, Nat) -> List (VarInfo b) -> Maybe (VarInfo b)
    runtimeOuter _ [] _ = Nothing
    runtimeOuter p ((j, q) :: rest) e =
      if p /= q then runtimeOuter p rest e else case atOuter j e of
        Just v => if runtime v then Just v else runtimeOuter p rest e
        Nothing => runtimeOuter p rest e

    -- Outer variables that are one pattern argument are one value. An
    -- erased one is bound to the runtime one.
    share : List (Nat, Nat) -> List (VarInfo b) -> List (VarInfo b)
    share [] e = e
    share ((j, p) :: rest) e =
      let e' = case (atOuter j e, runtimeOuter p ((j, p) :: rest) e) of
                 (Just v, Just r) => if erased v then setAt (k + j) r e else e
                 _ => e
      in share rest e'

    one : List (VarInfo b) -> (Nat, Nat) -> List (VarInfo b)
    one e (j, p) = case (atOuter j e, getAt p e) of
      (Just v, Just f) => if erased v && runtime f then setAt (k + j) f e else e
      _ => e

||| At a leaf, an erased variable may be the same value as a runtime
||| argument. The case tree did not match it: earlier matches left one
||| constructor of its type, and the tree names the erased variable.
||| Doing this before a match would change which value that match
||| compiles, so it runs only once the alternatives are done. A family
||| with one constructor is left alone: its result equates indices the
||| branch never proved equal.
forcedEnv : {auto c : Ref Ctxt Defs} -> {0 nv : Nat} ->
            List (VarInfo (Fin nv)) -> List (Maybe Typed) -> List (Maybe Known) ->
            Core (List (VarInfo (Fin nv)))
forcedEnv env tys known =
  if any isJust known then scan 0 env tys else pure env
  where
    isErasedVar : VarInfo a -> Bool
    isErasedVar (TypeValue (Erased _ _)) = True
    isErasedVar _ = False

    retarget : List (VarInfo (Fin nv)) -> Typed -> Core (List (VarInfo (Fin nv)))
    retarget e ty = case viewOf ty known of
      VRef tn _ => do
        cons <- dataConstructors tn
        let view = viewOf ty known
        fits <- mapMaybe id <$> traverse (\cn => matchConstructor cn view) cons
        case fits of
          [(k, eqs)] => if length cons > 1
                          then pure (drop k (bindEquated k eqs
                                       (replicate k (TypeValue (Erased EmptyFC Placeholder)) ++ e)))
                          else pure e
          _ => pure e
      _ => pure e

    scan : Nat -> List (VarInfo (Fin nv)) -> List (Maybe Typed) ->
           Core (List (VarInfo (Fin nv)))
    scan _ e [] = pure e
    scan i e (Nothing :: rest) = scan (S i) e rest
    scan i e (Just ty :: rest) = do
      e' <- case getAt i e of
        Just v => if isErasedVar v then retarget e ty else pure e
        Nothing => pure e
      scan (S i) e' rest


mutual
  ||| A case tree over its scope's variables, and their types as their
  ||| binders give them (`Typed`).
  export
  tree : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
         Ctx -> List (VarInfo (Fin nv)) -> List (Maybe Typed) -> List (Maybe Known) ->
         CaseTree vars -> Core (Term nv)
  tree ctx env tys known (STerm _ tm) = do
    env' <- forcedEnv env tys known
    term ctx env' tm
  -- Idris proved it cannot be reached. An `Unmatched` leaf of a covering
  -- definition is one too: a definition whose clauses are all impossible
  -- has only that leaf. In a definition with missing cases it is one of
  -- them, and crashes.
  tree ctx env tys known (Unmatched msg) = missingCase ctx <$> toLoc ctx.fc
  tree ctx env tys known Impossible = Unreachable <$> toLoc ctx.fc
  tree ctx env tys known (Case {name} idx _ _ alts) = do
    loc <- toLoc ctx.fc
    case getAt idx env of
      Just (Runtime i (Just WorldT) _) => case alts of
        [ConstCase WorldVal rhs] => tree ctx env tys known rhs
        _ => internal ctx.fc "an unexpected match on the world"
      -- A match on a quantity-0 value (a proof, an index) is in the
      -- compile-time tree only when its type forces the alternative, as
      -- Idris's erasure check guarantees; its fields are erased too.
      Just (TypeValue (Erased _ _)) => forced alts
      -- A match on an implementation selects its alternative now.
      Just (Static t hole) => staticCase ctx env tys known idx t hole alts
      Just v@(Runtime i _ _) => runtime loc v i
      Just v@(Shaped i _ _ _) => runtime loc v i
      _ => internal ctx.fc "a match on a compile-time value"
    where
      isDelayCase : CaseAlt vars -> Bool
      isDelayCase (DelayCase {}) = True
      isDelayCase _ = False

      literals : Loc -> Fin nv -> Core (Term nv)
      literals loc i = do
        (litAlts, def) <- litAlternatives ctx env tys known alts
        let Just def = def <|> (if ctx.complete then Nothing else Just (missingCase ctx loc))
          | Nothing => reject ctx.fc ctx.owner Match "a literal match without a default"
        pure (CaseLit loc i litAlts def)

      -- The data instance a match's constructors are of, at the value's
      -- type. The Core type names it when it is a declaration the
      -- constructor belongs to; a value of a type with one runtime field
      -- has its field's type, so the Idris type names it then.
      instanceOf : VarInfo (Fin nv) -> Name -> Core DataId
      instanceOf v cn = do
        st <- get TState
        let fromCore = case coreTyOf v of
                         Just (DataT d) => case lookup (MkConId d (shortName cn)) st.cons of
                           Just layout => if layout.name == cn then Just d else Nothing
                           Nothing => Nothing
                         _ => Nothing
        case (fromCore, idrisTypeOf v) of
          (Just d, _) => pure d
          (Nothing, Just ity) => do
            ity' <- normaliseClosed ity
            Just (inst, _) <- dataOf ctx.fc ctx.owner ity'
              | Nothing => do
                  -- A value array is abstract: only the functions the
                  -- registry knows open it, and their bodies are not
                  -- translated.
                  Just _ <- arrayShape ity'
                    | Nothing => internal ctx.fc ("a match on " ++ show cn ++ " at a type that is not data")
                  reject ctx.fc ctx.owner HookShape
                         ("the array type of " ++ show cn ++ " is opaque: its constructor is matched")
            pure inst
          (Nothing, Nothing) =>
            internal ctx.fc ("a match on " ++ show cn ++ " of a value whose type is not known")

      -- A match on a runtime value, by what its alternatives match: a
      -- natural's constructors, one runtime field's constructor, a
      -- declaration's constructors, or literals.
      runtime : Loc -> VarInfo (Fin nv) -> Fin nv -> Core (Term nv)
      runtime loc v i =
        if any isDelayCase alts then reject ctx.fc ctx.owner Laziness "a match on a lazy value" else
        case mapMaybe conName alts of
          [] => literals loc i
          (cn :: _) => do
            def <- lookupDef ctx.fc ctx.owner cn
            let shape = shapeOf v
            case natRole def of
              -- A `Nat`-like value is a natural: a match on its
              -- constructors is a match on zero.
              Just _ => natCase ctx env tys known idx shape loc i (idrisTypeOf v) alts
              Nothing => do
                inst <- instanceOf v (fullname def)
                st <- get TState
                if isJust (lookup inst st.newtypes)
                   then newtypeCase ctx env tys known idx v inst alts
                   else do
                     every <- coversAll alts
                     built <- builtNamed shape alts
                     (conAlts, dflt) <- conAlternatives ctx env tys known shape every built inst
                                                        (join (getAt idx tys)) idx alts
                     st' <- get TState
                     -- Constructors the tree leaves out are impossible when
                     -- the definition is covering, and crash otherwise.
                     let missing = case (dflt, lookup inst st'.datas) of
                                     (Nothing, Just dt) => filter (\c => not (any (\(MkAlt k _ _) => k == c.id) conAlts)) dt.cons
                                     _ => []
                     let absurd = map (\c => MkAlt c.id (fromList (map (\b => (shown "_", b)) c.fields)) (missingCase ctx loc)) missing
                     pure (Case loc i (conAlts ++ absurd) dflt)

      forced : List (CaseAlt vars) -> Core (Term nv)
      forced [ConCase cn _ args rhs] =
        let k = length args in
        tree ctx (map (const (TypeValue (Erased ctx.fc Placeholder))) args ++ env)
             !(alternativeTypes cn k (join (getAt idx tys)) tys)
             (underKnown k idx cn known) rhs
      forced [DefaultCase rhs] = tree ctx env tys known rhs
      forced _ = do
        cons <- traverse altName alts
        reject ctx.fc ctx.owner Match
               ("a match on `" ++ show name ++ "`, which is erased (quantity 0, or an index or proof " ++
                "with no runtime value), between " ++ joinBy ", " cons ++ ": only a runtime value can " ++
                "choose an alternative; match on the runtime value that determines it instead")
        where
          altName : CaseAlt vars -> Core String
          altName (ConCase cn _ _ _) = show <$> toFullNames cn
          altName (ConstCase c _) = pure (show c)
          altName (DelayCase {}) = pure "Delay"
          altName (DefaultCase _) = pure "the default"

  ||| A match on a `Nat`-like value: zero, or a successor binding the
  ||| predecessor. The default stands for whichever the tree leaves out.
  natCase : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
            Ctx -> List (VarInfo (Fin nv)) -> List (Maybe Typed) -> List (Maybe Known) -> Nat ->
            Maybe ClosedTerm -> Loc -> Fin nv -> Maybe ClosedTerm ->
            List (CaseAlt vars) -> Core (Term nv)
  natCase ctx env tys known idx shape loc x ity alts = do
    every <- coversAll alts
    built <- builtNamed shape alts
    (zero, succ, def) <- natAlternatives ctx env tys known idx shape ity (every || built) loc x alts
    case (zero, succ, def) of
      (Nothing, Nothing, d) => pure (fromMaybe (missingCase ctx loc) d)
      (z, s, d) => do
        let (pred, body) = fromMaybe (shown "_", maybe (missingCase ctx loc) (weakenUnder 1) d) s
        pure (CaseNat loc x (fromMaybe (fromMaybe (missingCase ctx loc) d) z) pred body)

  ||| The alternatives of a match on a `Nat`-like value: zero's, the
  ||| successor's (over the predecessor, named, its erased arguments
  ||| compile-time values), and the default, unless no value takes it
  ||| (`deadDefault`). The value's shape, if known, rules one of the two out,
  ||| and gives the predecessor its own; the predecessor is of the value's
  ||| type (`ity`).
  natAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                    Ctx -> List (VarInfo (Fin nv)) -> List (Maybe Typed) -> List (Maybe Known) -> Nat ->
                    Maybe ClosedTerm -> Maybe ClosedTerm -> Bool -> Loc -> Fin nv ->
                    List (CaseAlt vars) ->
                    Core (Maybe (Term nv), Maybe (Shown, Term (Under 1 nv)), Maybe (Term nv))
  natAlternatives ctx env tys known idx shape ity deadDefault loc x [] = pure (Nothing, Nothing, Nothing)
  natAlternatives ctx env tys known idx shape ity deadDefault loc x (ConCase cn _ args rhs :: rest) = do
    def <- lookupDef ctx.fc ctx.owner cn
    isErased <- erasedArgs cn
    dead <- excludedBy shape (fullname def)
    let k = length args
    tys' <- alternativeTypes cn k (join (getAt idx tys)) tys
    case natRole def of
      Just Zero => do
        z <- if dead then pure (Unreachable loc)
             else tree ctx (map (const (TypeValue (Erased ctx.fc Placeholder))) args ++ env) tys'
                       (underKnown k idx cn known) rhs
        (_, s, d) <- natAlternatives ctx env tys known idx shape ity deadDefault loc x rest
        pure (Just z, s, d)
      Just Succ => do
        let erased = isErased ++ replicate (length args) False
        let predInfo : VarInfo (Fin (Under 1 nv))
            predInfo = case (predecessor (shapeArgs shape) erased, ity) of
                         (Just p, Just t) => shaped FZ NatT t p
                         _ => Runtime FZ (Just NatT) ity
        let infos = zipWith (\_, e => if e then TypeValue (Erased ctx.fc Placeholder) else predInfo)
                            args erased
        let pred = maybe (shown "_") (binderName . fst) (find (not . snd) (zip args erased))
        body <- if dead then pure (Unreachable loc)
                else tree ctx (under {k = 1} infos env) tys' (underKnown (length infos) idx cn known) rhs
        (z, _, d) <- natAlternatives ctx env tys known idx shape ity deadDefault loc x rest
        pure (z, Just (pred, body), d)
      Nothing => internal ctx.fc ("a constructor of another type in a match on a Nat-like value")
    where
      -- The successor's one runtime argument, among the shape's.
      predecessor : List ClosedTerm -> List Bool -> Maybe ClosedTerm
      predecessor (a :: as) (True :: es) = predecessor as es
      predecessor (a :: as) _ = Just a
      predecessor [] _ = Nothing
  natAlternatives ctx env tys known idx shape ity deadDefault loc x (DefaultCase rhs :: _) =
    pure (Nothing, Nothing, Just !(if deadDefault then pure (Unreachable loc) else tree ctx env tys known rhs))
  natAlternatives ctx env tys known idx shape ity deadDefault loc x (_ :: _) =
    internal ctx.fc "an unexpected alternative"

  ||| A match on a compile-time value: the implementation is reduced to its
  ||| constructor, and the alternative's variables stand for its arguments.
  ||| An argument that mentions the runtime value the implementation closes
  ||| over closes over it too.
  staticCase : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
               Ctx -> List (VarInfo (Fin nv)) -> List (Maybe Typed) -> List (Maybe Known) -> Nat ->
               ClosedTerm -> Maybe (Fin nv, Holes) ->
               List (CaseAlt vars) -> Core (Term nv)
  staticCase ctx env tys known idx t hole alts = do
    Just (cn, cargs) <- whnf 64 t
      | Nothing => do reject ctx.fc ctx.owner RuntimeClosure
                        ("an implementation that does not reduce to its constructor: " ++ !(showTT t))
    cn <- toFullNames cn
    erased <- erasedArgs cn
    pick cn (zipWith info (erased ++ replicate (length cargs) False) cargs) alts
    where
      info : Bool -> ClosedTerm -> VarInfo (Fin nv)
      info True v = TypeValue v
      info False v = Static v (if mentionsHole v then hole else Nothing)
      pick : Name -> List (VarInfo (Fin nv)) -> List (CaseAlt vars) -> Core (Term nv)
      pick cn infos (ConCase con _ args rhs :: rest) = do
        full <- toFullNames con
        if full /= cn then pick cn infos rest else do
          when (length args /= length infos) $
            internal ctx.fc ("constructor " ++ show cn ++ " binds an unexpected number of arguments")
          let k = length infos
          tree ctx (infos ++ env) !(alternativeTypes cn k (join (getAt idx tys)) tys)
               (underKnown k idx con known) rhs
      pick cn infos (DefaultCase rhs :: _) = tree ctx env tys known rhs
      pick cn infos (_ :: rest) = pick cn infos rest
      pick cn infos [] = internal ctx.fc ("no alternative for " ++ show cn)

  ||| A match on a value of a type with one runtime field, which is the
  ||| field's value: nothing is matched at runtime, the alternative's
  ||| arguments stand for what the constructor holds, and its field for the
  ||| matched value itself, at the field's type.
  newtypeCase : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                Ctx -> List (VarInfo (Fin nv)) -> List (Maybe Typed) -> List (Maybe Known) -> Nat ->
                VarInfo (Fin nv) -> DataId -> List (CaseAlt vars) -> Core (Term nv)
  newtypeCase ctx env tys known idx scrutinee inst alts = case find isConCase alts of
    Just (ConCase cn _ args rhs) => do
      def <- lookupDef ctx.fc ctx.owner cn
      let cid = MkConId inst (shortName (fullname def))
      st <- get TState
      let Just info = lookup cid st.cons
        | Nothing => internal ctx.fc ("the constructor " ++ show (fullname def) ++ " is not registered")
      when (length info.args /= length args) $
        reject ctx.fc ctx.owner CompiledModule
               ("constructor " ++ show (fullname def) ++ " binds an unexpected number of arguments")
      -- A dictionary field no construction site has given is one of no
      -- value: the alternative is unreachable (`Dictionaries`).
      Just impls <- dictionariesOf cid info.args
        | Nothing => Unreachable <$> toLoc ctx.fc
      let shapes = shapeArgs (shapeOf scrutinee)
      let infos = zipWith (argInfo impls shapes) [0 .. length info.args] info.args
      let k = length args
      let scTy = join (getAt idx tys)
      eqs <- equated k (type def) scTy
      tree ctx (bindEquated k eqs (infos ++ env)) !(alternativeTypes cn k scTy tys)
           (underKnown k idx cn known) rhs
    _ => case find isDefault alts of
      Just (DefaultCase rhs) => tree ctx env tys known rhs
      _ => internal ctx.fc "a match on a value of one field without an alternative"
    where
      isConCase : CaseAlt vars -> Bool
      isConCase (ConCase {}) = True
      isConCase _ = False

      argInfo : List (Nat, ClosedTerm) -> List ClosedTerm -> Nat -> ArgKind -> VarInfo (Fin nv)
      argInfo impls shapes p (Param v) = TypeValue v
      argInfo impls shapes p ErasedArg = TypeValue (Erased EmptyFC Placeholder)
      argInfo impls shapes p (DictArg _) = Static (fromMaybe (Erased EmptyFC Placeholder) (lookup p impls)) Nothing
      argInfo impls shapes p (Field _ b ity) = case (variableOf scrutinee, getAt p shapes) of
        (Just x, Just s) => shaped x (typeOf b) ity s
        (Just x, Nothing) => Runtime x (Just (typeOf b)) (Just ity)
        (Nothing, _) => TypeValue (Erased EmptyFC Placeholder)

  ||| The constructor alternatives of a match, each over its fields, named
  ||| as the alternative names them, and the default: none when the
  ||| alternatives name every constructor (`every`), unreachable when they
  ||| name the one the value's shape says it was built with (`built`). The
  ||| shape, if known, rules out every other constructor and gives the
  ||| fields their shapes.
  conAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                    Ctx -> List (VarInfo (Fin nv)) -> List (Maybe Typed) -> List (Maybe Known) ->
                    Maybe ClosedTerm -> Bool -> Bool -> DataId ->
                    Maybe Typed -> Nat -> List (CaseAlt vars) -> Core (List (Alt nv), Maybe (Term nv))
  conAlternatives ctx env tys known shape every built inst scTy idx [] = pure ([], Nothing)
  conAlternatives ctx env tys known shape every built inst scTy idx (ConCase cn _ args rhs :: rest) = do
    def <- lookupDef ctx.fc ctx.owner cn
    let cid = MkConId inst (shortName (fullname def))
    st <- get TState
    let Just info = lookup cid st.cons
      | Nothing => internal ctx.fc ("the constructor " ++ show (fullname def) ++ " is not registered")
    when (length info.args /= length args) $
      reject ctx.fc ctx.owner CompiledModule
             ("constructor " ++ show (fullname def) ++ " binds an unexpected number of arguments")
    let named = mapMaybe fieldNamed (zip args info.args)
    dead <- excludedBy shape (fullname def)
    -- A dictionary field stands for the one implementation the program
    -- builds it with; before any construction site is known, no value of
    -- the constructor exists and the alternative is unreachable
    -- (`Dictionaries`).
    found <- dictionariesOf cid info.args
    body <- case found of
      Just impls => if dead then Unreachable <$> toLoc ctx.fc else do
        let k = length args
        eqs <- equated k (type def) scTy
        let env' = bindEquated k eqs (under {k = length named}
                         (argInfos {k = length named} {nv} info.args impls (shapeArgs shape)) env)
        tree ctx env' !(alternativeTypes cn k scTy tys) (underKnown k idx cn known) rhs
      Nothing => Unreachable <$> toLoc ctx.fc
    (alts, def') <- conAlternatives ctx env tys known shape every built inst scTy idx rest
    pure (MkAlt cid (fromList named) body :: alts, def')
    where
      fieldNamed : (Name, ArgKind) -> Maybe (Shown, Binder)
      fieldNamed (n, Field _ b _) = Just (binderName n, b)
      fieldNamed _ = Nothing
  conAlternatives ctx env tys known shape every built inst scTy idx (DefaultCase rhs :: _) =
    if every then pure ([], Nothing) else do
      d <- if built then Unreachable <$> toLoc ctx.fc else tree ctx env tys known rhs
      pure ([], Just d)
  conAlternatives ctx env tys known shape every built inst scTy idx (DelayCase {} :: _) =
    reject ctx.fc ctx.owner Laziness "a match on a lazy value"
  conAlternatives ctx env tys known shape every built inst scTy idx (ConstCase {} :: _) =
    internal ctx.fc "a constant alternative in a constructor match"

  litAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                    Ctx -> List (VarInfo (Fin nv)) -> List (Maybe Typed) -> List (Maybe Known) ->
                    List (CaseAlt vars) ->
                    Core (List (Lit, Term nv), Maybe (Term nv))
  litAlternatives ctx env tys known [] = pure ([], Nothing)
  litAlternatives ctx env tys known (ConstCase c rhs :: rest) = do
    Just lit <- pure (constantLit c)
      | Nothing => reject ctx.fc ctx.owner StringPrimitive ("a match on " ++ show c)
    case lit of
      LDouble _ => reject ctx.fc ctx.owner Primitive "a match on a Double literal"
      _ => pure ()
    body <- tree ctx env tys known rhs
    (alts, def) <- litAlternatives ctx env tys known rest
    pure ((lit, body) :: alts, def)
  litAlternatives ctx env tys known (DefaultCase rhs :: _) =
    pure ([], Just !(tree ctx env tys known rhs))
  litAlternatives ctx env tys known _ = internal ctx.fc "an unexpected alternative"
