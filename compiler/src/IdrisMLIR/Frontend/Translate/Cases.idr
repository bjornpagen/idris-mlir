||| Case trees: Idris's compile-time case trees (`treeCT`) as Core matches.
||| A match on a compile-time value selects its alternative now.
module IdrisMLIR.Frontend.Translate.Cases

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Dictionaries
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Terms
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Rule
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.Fin
import Data.List
import Data.SortedMap
import Data.Vect

%default covering

||| The variables a constructor alternative binds for its fields, in field
||| order: field `i` is `Bound i`.
fieldInfos : {k : Nat} -> (bs : Vect k Binder) -> List (VarInfo (Under k a))
fieldInfos bs = toList (zipWith (\i, b => Runtime (Bound i) (Just (typeOf b))) range bs)

||| A leaf no input reaches: `Unreachable` in a covering definition
||| (Idris proved no input reaches it), a crash otherwise.
missingCase : {0 a : Type} -> Ctx -> Loc -> IdrisMLIR.Term.Term a
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
    built tm = case spine tm [] of
      (Ref _ (TyCon _) tn, _) => Just tn
      _ => Nothing

||| Can the default alternative of a match be taken? Not when the match
||| names every constructor of the type, nor when it names the one the
||| value's shape, if known, says it was built with: the default then
||| stands for no value the match sees. Its code, which may call for
||| instances no value needs (one a constructor deeper, where a shape keys
||| the instance), is not translated.
defaultDead : {auto c : Ref Ctxt Defs} -> Maybe ClosedTerm -> List (CaseAlt vars) -> Core Bool
defaultDead shape alts = do
  named <- traverse toFullNames (mapMaybe conName alts)
  every <- traverse toFullNames !(siblings alts)
  built <- case the (Maybe (Name, List ClosedTerm)) (shape >>= shapeHead) of
    Just (cn, _) => pure (elem !(toFullNames cn) named)
    Nothing => pure False
  pure (built || (not (null every) && all (\c => elem c named) every))

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

||| The types of an alternative's scope: the `k` arguments of the
||| constructor it matches, in front of the scope of the match.
alternativeTypes : {auto c : Ref Ctxt Defs} -> Name -> Nat -> List (Maybe Typed) -> Core (List (Maybe Typed))
alternativeTypes cn k tys = do
  defs <- get Ctxt
  args <- maybe (replicate k Nothing) (telescope k . type) <$> lookupCtxtExact cn (gamma defs)
  pure (args ++ map (map shift) tys)
  where
    shift : Typed -> Typed
    shift (MkTyped t at) = MkTyped t (map (+ k) . at)

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
    pairs con sc = case (spine con [], spine sc []) of
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
bindEquated : Nat -> List (Nat, Nat) -> List (VarInfo b) -> List (VarInfo b)
bindEquated k eqs env = foldl one env eqs
  where
    runtime : VarInfo b -> Bool
    runtime (Runtime _ (Just ErasedT)) = False
    runtime (Runtime _ (Just _)) = True
    runtime (Shaped {}) = True
    runtime _ = False

    erased : VarInfo b -> Bool
    erased (Runtime _ (Just ErasedT)) = True
    erased _ = False

    setAt : Nat -> VarInfo b -> List (VarInfo b) -> List (VarInfo b)
    setAt Z v (_ :: xs) = v :: xs
    setAt (S i) v (x :: xs) = x :: setAt i v xs
    setAt _ _ [] = []

    one : List (VarInfo b) -> (Nat, Nat) -> List (VarInfo b)
    one e (j, p) = case (getAt (k + j) e, getAt p e) of
      (Just v, Just f) => if erased v && runtime f then setAt (k + j) f e else e
      _ => e

mutual
  ||| A case tree over its scope's variables, and their types as their
  ||| binders give them (`Typed`).
  export
  tree : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
         Ctx -> List (VarInfo a) -> List (Maybe Typed) -> CaseTree vars -> Core (Term a)
  tree ctx env tys (STerm _ tm) = term ctx env tm
  -- Idris proved it cannot be reached. An `Unmatched` leaf of a covering
  -- definition is one too: a definition whose clauses are all impossible
  -- has only that leaf. In a definition with missing cases it is one of
  -- them, and crashes.
  tree ctx env tys (Unmatched msg) = missingCase ctx <$> toLoc ctx.fc
  tree ctx env tys Impossible = Unreachable <$> toLoc ctx.fc
  tree ctx env tys (Case idx _ _ alts) = do
    loc <- toLoc ctx.fc
    -- What is known of the value's shape rules alternatives out.
    let shape = case getAt idx env of
                  Just (Shaped _ _ s) => Just s
                  _ => Nothing
    case map plain (getAt idx env) of
      Just (Runtime i (Just WorldT)) => case alts of
        [ConstCase WorldVal rhs] => tree ctx env tys rhs
        _ => internal ctx.fc "an unexpected match on the world"
      -- A match on a quantity-0 value (a proof, an index) is in the
      -- compile-time tree only when its type forces the alternative, as
      -- Idris's erasure check guarantees; its fields are erased too.
      Just (Runtime i (Just ErasedT)) => forced alts
      Just (TypeValue (Erased _ _)) => forced alts
      Just (Runtime i (Just (DataT inst))) => do
        (conAlts, def) <- conAlternatives ctx env tys shape !(defaultDead shape alts) inst
                                          (join (getAt idx tys)) alts
        st <- get TState
        -- Constructors the tree leaves out are impossible when the
        -- definition is covering, and crash otherwise.
        let missing = case (def, lookup inst st.datas) of
                        (Nothing, Just dt) => filter (\c => not (any (\(MkAlt k _ _) => k == c.id) conAlts)) dt.cons
                        _ => []
        let absurd = map (\c => MkAlt c.id (fromList c.fields) (missingCase ctx loc)) missing
        pure (Case loc i (conAlts ++ absurd) def)
      -- A `Nat`-like value is a natural: a match on its constructors is a
      -- match on zero.
      Just (Runtime i (Just NatT)) =>
        if any isConCase alts then natCase ctx env tys shape loc i alts else literals loc i
      Just (Runtime i (Just _)) => literals loc i
      -- A match on an implementation selects its alternative now.
      Just (Static t) => staticCase ctx env tys t alts
      _ => internal ctx.fc "a match on a compile-time value"
    where
      -- A shaped value is matched as a runtime value of its type.
      plain : VarInfo a -> VarInfo a
      plain (Shaped x t _) = Runtime x (Just t)
      plain v = v

      isConCase : CaseAlt vars -> Bool
      isConCase (ConCase {}) = True
      isConCase _ = False

      literals : Loc -> a -> Core (Term a)
      literals loc i = do
        (litAlts, def) <- litAlternatives ctx env tys alts
        let Just def = def <|> (if ctx.complete then Nothing else Just (missingCase ctx loc))
          | Nothing => reject ctx.fc ctx.owner Match "a literal match without a default"
        pure (CaseLit loc i litAlts def)

      forced : List (CaseAlt vars) -> Core (Term a)
      forced [ConCase cn _ args rhs] =
        tree ctx (map (const (TypeValue (Erased ctx.fc Placeholder))) args ++ env)
             !(alternativeTypes cn (length args) tys) rhs
      forced [DefaultCase rhs] = tree ctx env tys rhs
      forced _ = reject ctx.fc ctx.owner Match "a match on an erased value with more than one alternative"

  ||| A match on a `Nat`-like value: zero, or a successor binding the
  ||| predecessor. The default stands for whichever the tree leaves out.
  natCase : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
            Ctx -> List (VarInfo a) -> List (Maybe Typed) -> Maybe ClosedTerm -> Loc -> a ->
            List (CaseAlt vars) -> Core (Term a)
  natCase ctx env tys shape loc x alts = do
    (zero, succ, def) <- natAlternatives ctx env tys shape !(defaultDead shape alts) loc x alts
    case (zero, succ, def) of
      (Nothing, Nothing, d) => pure (fromMaybe (missingCase ctx loc) d)
      (z, s, d) => pure (CaseNat loc x (fromMaybe (fromMaybe (missingCase ctx loc) d) z)
                                       (fromMaybe (maybe (missingCase ctx loc) (map Free) d) s))

  ||| The alternatives of a match on a `Nat`-like value: zero's, the
  ||| successor's (over the predecessor, its erased arguments compile-time
  ||| values), and the default, unless no value takes it (`defaultDead`,
  ||| given as `deadDefault`). The value's shape, if known, rules one of
  ||| the two out, and gives the predecessor its own.
  natAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                    Ctx -> List (VarInfo a) -> List (Maybe Typed) -> Maybe ClosedTerm -> Bool -> Loc -> a ->
                    List (CaseAlt vars) -> Core (Maybe (Term a), Maybe (Term (Under 1 a)), Maybe (Term a))
  natAlternatives ctx env tys shape deadDefault loc x [] = pure (Nothing, Nothing, Nothing)
  natAlternatives ctx env tys shape deadDefault loc x (ConCase cn _ args rhs :: rest) = do
    def <- lookupDef ctx.fc ctx.owner cn
    isErased <- erasedArgs cn
    dead <- excludedBy shape (fullname def)
    tys' <- alternativeTypes cn (length args) tys
    case natRole def of
      Just Zero => do
        z <- if dead then pure (Unreachable loc)
             else tree ctx (map (const (TypeValue (Erased ctx.fc Placeholder))) args ++ env) tys' rhs
        (_, s, d) <- natAlternatives ctx env tys shape deadDefault loc x rest
        pure (Just z, s, d)
      Just Succ => do
        let erased = isErased ++ replicate (length args) False
        let predInfo : VarInfo (Under 1 a)
            predInfo = case predecessor (shapeArgs shape) erased of
                         Just p => shaped (Bound FZ) NatT p
                         Nothing => Runtime (Bound FZ) (Just NatT)
        let infos = zipWith (\_, e => if e then TypeValue (Erased ctx.fc Placeholder) else predInfo)
                            args erased
        body <- if dead then pure (Unreachable loc) else tree ctx (under infos env) tys' rhs
        (z, _, d) <- natAlternatives ctx env tys shape deadDefault loc x rest
        pure (z, Just body, d)
      Nothing => internal ctx.fc ("a constructor of another type in a match on a Nat-like value")
    where
      -- The successor's one runtime argument, among the shape's.
      predecessor : List ClosedTerm -> List Bool -> Maybe ClosedTerm
      predecessor (a :: as) (True :: es) = predecessor as es
      predecessor (a :: as) _ = Just a
      predecessor [] _ = Nothing
  natAlternatives ctx env tys shape deadDefault loc x (DefaultCase rhs :: _) =
    pure (Nothing, Nothing, Just !(if deadDefault then pure (Unreachable loc) else tree ctx env tys rhs))
  natAlternatives ctx env tys shape deadDefault loc x (_ :: _) = internal ctx.fc "an unexpected alternative"

  ||| A match on a compile-time value: the implementation is reduced to its
  ||| constructor, and the alternative's variables stand for its arguments.
  staticCase : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
               Ctx -> List (VarInfo a) -> List (Maybe Typed) -> ClosedTerm -> List (CaseAlt vars) -> Core (Term a)
  staticCase ctx env tys t alts = do
    Just (cn, cargs) <- whnf 64 t
      | Nothing => reject ctx.fc ctx.owner RuntimeClosure
                     ("an implementation that does not reduce to its constructor: " ++ !(showTT t))
    cn <- toFullNames cn
    erased <- erasedArgs cn
    pick cn (zipWith info (erased ++ replicate (length cargs) False) cargs) alts
    where
      info : Bool -> ClosedTerm -> VarInfo a
      info True v = TypeValue v
      info False v = Static v
      pick : Name -> List (VarInfo a) -> List (CaseAlt vars) -> Core (Term a)
      pick cn infos (ConCase k _ args rhs :: rest) = do
        k <- toFullNames k
        if k /= cn then pick cn infos rest else do
          when (length args /= length infos) $
            internal ctx.fc ("constructor " ++ show cn ++ " binds an unexpected number of arguments")
          tree ctx (infos ++ env) !(alternativeTypes cn (length args) tys) rhs
      pick cn infos (DefaultCase rhs :: _) = tree ctx env tys rhs
      pick cn infos (_ :: rest) = pick cn infos rest
      pick cn infos [] = internal ctx.fc ("no alternative for " ++ show cn)

  ||| The constructor alternatives of a match, each over its fields, and
  ||| the default, unless no value takes it (`defaultDead`, given as
  ||| `deadDefault`). The value's shape, if known, rules out every other
  ||| constructor and gives the fields their shapes.
  conAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                    Ctx -> List (VarInfo a) -> List (Maybe Typed) -> Maybe ClosedTerm -> Bool -> DataId ->
                    Maybe Typed -> List (CaseAlt vars) -> Core (List (Alt a), Maybe (Term a))
  conAlternatives ctx env tys shape deadDefault inst scTy [] = pure ([], Nothing)
  conAlternatives ctx env tys shape deadDefault inst scTy (ConCase cn _ args rhs :: rest) = do
    def <- lookupDef ctx.fc ctx.owner cn
    let cid = MkConId inst (shortName (fullname def))
    st <- get TState
    let Just info = lookup cid st.cons
      | Nothing => internal ctx.fc ("unknown constructor " ++ cid.name ++ " of " ++ inst.name)
    let bs = fromList info.con.fields
    when (length info.layout /= length args) $
      reject ctx.fc ctx.owner CompiledModule ("constructor " ++ cid.name ++ " binds an unexpected number of arguments")
    dead <- excludedBy shape (fullname def)
    -- A dictionary field stands for the one implementation the program
    -- builds it with; before any construction site is known, no value of
    -- the constructor exists and the alternative is unreachable
    -- (`Dictionaries`).
    dicts <- traverse (\(i, _) => map (i,) <$> dictionaryOf cid i) info.dicts
    body <- case the (Maybe (List (Nat, ClosedTerm))) (sequence dicts) of
      Just impls => if dead then Unreachable <$> toLoc ctx.fc else do
        let shapes = fieldsOnly info.layout (shapeArgs shape)
        let fields = zipWith (\i, f => case (Data.List.lookup i impls, f, getAt i shapes) of
                                         (Just impl, _, _) => Static impl
                                         (Nothing, Runtime x (Just t), Just s) => shaped x t s
                                         _ => f)
                             [0 .. length bs] (fieldInfos bs)
        eqs <- equated (length args) (type def) scTy
        tree ctx (bindEquated (length args) eqs (under (arrange info.layout info.params fields) env))
             !(alternativeTypes cn (length args) tys) rhs
      Nothing => Unreachable <$> toLoc ctx.fc
    (alts, def') <- conAlternatives ctx env tys shape deadDefault inst scTy rest
    pure (MkAlt cid bs body :: alts, def')
  conAlternatives ctx env tys shape deadDefault inst scTy (DefaultCase rhs :: _) =
    pure ([], Just !(if deadDefault then Unreachable <$> toLoc ctx.fc else tree ctx env tys rhs))
  conAlternatives ctx env tys shape deadDefault inst scTy (DelayCase {} :: _) =
    reject ctx.fc ctx.owner Laziness "a match on a lazy value"
  conAlternatives ctx env tys shape deadDefault inst scTy (ConstCase {} :: _) =
    internal ctx.fc "a constant alternative in a constructor match"

  litAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                    Ctx -> List (VarInfo a) -> List (Maybe Typed) -> List (CaseAlt vars) ->
                    Core (List (Lit, Term a), Maybe (Term a))
  litAlternatives ctx env tys [] = pure ([], Nothing)
  litAlternatives ctx env tys (ConstCase c rhs :: rest) = do
    Just lit <- pure (constantLit c)
      | Nothing => reject ctx.fc ctx.owner StringPrimitive ("a match on " ++ show c)
    case lit of
      LDouble _ => reject ctx.fc ctx.owner Primitive "a match on a Double literal"
      _ => pure ()
    body <- tree ctx env tys rhs
    (alts, def) <- litAlternatives ctx env tys rest
    pure ((lit, body) :: alts, def)
  litAlternatives ctx env tys (DefaultCase rhs :: _) = pure ([], Just !(tree ctx env tys rhs))
  litAlternatives ctx env tys _ = internal ctx.fc "an unexpected alternative"
