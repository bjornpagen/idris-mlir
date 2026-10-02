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

mutual
  export
  tree : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> Ord a =>
         Ctx -> List (VarInfo a) -> CaseTree vars -> Core (Term a)
  tree ctx env (STerm _ tm) = term ctx env tm
  -- Idris proved it cannot be reached. An `Unmatched` leaf of a covering
  -- definition is one too: a definition whose clauses are all impossible
  -- has only that leaf. In a definition with missing cases it is one of
  -- them, and crashes.
  tree ctx env (Unmatched msg) = missingCase ctx <$> toLoc ctx.fc
  tree ctx env Impossible = Unreachable <$> toLoc ctx.fc
  tree ctx env (Case idx _ scTy alts) = do
    loc <- toLoc ctx.fc
    -- What is known of the value's shape rules alternatives out.
    let shape = case getAt idx env of
                  Just (Shaped _ _ s) => Just s
                  _ => Nothing
    case map plain (getAt idx env) of
      Just (Runtime i (Just WorldT)) => case alts of
        [ConstCase WorldVal rhs] => tree ctx env rhs
        _ => internal ctx.fc "an unexpected match on the world"
      -- A match on a quantity-0 value (a proof, an index) is in the
      -- compile-time tree only when its type forces the alternative, as
      -- Idris's erasure check guarantees; its fields are erased too.
      Just (Runtime i (Just ErasedT)) => forced alts
      Just (TypeValue (Erased _ _)) => forced alts
      Just (Runtime i (Just (DataT inst))) => do
        (conAlts, def) <- conAlternatives ctx env shape inst alts
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
        if any isConCase alts then natCase ctx env shape loc i alts else literals loc i
      Just (Runtime i (Just _)) => literals loc i
      -- A match on an implementation selects its alternative now.
      Just (Static t) => staticCase ctx env t alts
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
        (litAlts, def) <- litAlternatives ctx env alts
        let Just def = def <|> (if ctx.complete then Nothing else Just (missingCase ctx loc))
          | Nothing => reject ctx.fc ctx.owner Match "a literal match without a default"
        pure (CaseLit loc i litAlts def)

      forced : List (CaseAlt vars) -> Core (Term a)
      forced [ConCase _ _ args rhs] =
        tree ctx (map (const (TypeValue (Erased ctx.fc Placeholder))) args ++ env) rhs
      forced [DefaultCase rhs] = tree ctx env rhs
      forced _ = reject ctx.fc ctx.owner Match "a match on an erased value with more than one alternative"

  ||| A match on a `Nat`-like value: zero, or a successor binding the
  ||| predecessor. The default stands for whichever the tree leaves out.
  ||| Each alternative is translated once, so every label stays unique.
  natCase : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> Ord a =>
            Ctx -> List (VarInfo a) -> Maybe ClosedTerm -> Loc -> a -> List (CaseAlt vars) -> Core (Term a)
  natCase ctx env shape loc x alts = do
    (zero, succ, def) <- natAlternatives ctx env shape loc x alts
    case (zero, succ, def) of
      (Nothing, Nothing, d) => pure (fromMaybe (missingCase ctx loc) d)
      (z, s, d) => pure (CaseNat loc x (fromMaybe (fromMaybe (missingCase ctx loc) d) z)
                                       (fromMaybe (maybe (missingCase ctx loc) (map Free) d) s))

  ||| The alternatives of a match on a `Nat`-like value: zero's, the
  ||| successor's (over the predecessor, its erased arguments compile-time
  ||| values), and the default. The value's shape, if known, rules one of
  ||| the two out, and gives the predecessor its own.
  natAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> Ord a =>
                    Ctx -> List (VarInfo a) -> Maybe ClosedTerm -> Loc -> a -> List (CaseAlt vars) ->
                    Core (Maybe (Term a), Maybe (Term (Under 1 a)), Maybe (Term a))
  natAlternatives ctx env shape loc x [] = pure (Nothing, Nothing, Nothing)
  natAlternatives ctx env shape loc x (ConCase cn _ args rhs :: rest) = do
    def <- lookupDef ctx.fc ctx.owner cn
    isErased <- erasedArgs cn
    dead <- excludedBy shape (fullname def)
    case natRole def of
      Just Zero => do
        z <- if dead then pure (Unreachable loc)
             else tree ctx (map (const (TypeValue (Erased ctx.fc Placeholder))) args ++ env) rhs
        (_, s, d) <- natAlternatives ctx env shape loc x rest
        pure (Just z, s, d)
      Just Succ => do
        let erased = isErased ++ replicate (length args) False
        let predInfo : VarInfo (Under 1 a)
            predInfo = case predecessor (shapeArgs shape) erased of
                         Just p => shaped (Bound FZ) NatT p
                         Nothing => Runtime (Bound FZ) (Just NatT)
        let infos = zipWith (\_, e => if e then TypeValue (Erased ctx.fc Placeholder) else predInfo)
                            args erased
        body <- if dead then pure (Unreachable loc) else tree ctx (under infos env) rhs
        (z, _, d) <- natAlternatives ctx env shape loc x rest
        pure (z, Just body, d)
      Nothing => internal ctx.fc ("a constructor of another type in a match on a Nat-like value")
    where
      -- The successor's one runtime argument, among the shape's.
      predecessor : List ClosedTerm -> List Bool -> Maybe ClosedTerm
      predecessor (a :: as) (True :: es) = predecessor as es
      predecessor (a :: as) _ = Just a
      predecessor [] _ = Nothing
  natAlternatives ctx env shape loc x (DefaultCase rhs :: _) = pure (Nothing, Nothing, Just !(tree ctx env rhs))
  natAlternatives ctx env shape loc x (_ :: _) = internal ctx.fc "an unexpected alternative"

  ||| A match on a compile-time value: the implementation is reduced to its
  ||| constructor, and the alternative's variables stand for its arguments.
  staticCase : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> Ord a =>
               Ctx -> List (VarInfo a) -> ClosedTerm -> List (CaseAlt vars) -> Core (Term a)
  staticCase ctx env t alts = do
    Just (cn, cargs) <- whnf 64 t
      | Nothing => reject ctx.fc ctx.owner RuntimeClosure
                     ("an implementation that does not reduce to its constructor: " ++ showTT t)
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
          tree ctx (infos ++ env) rhs
      pick cn infos (DefaultCase rhs :: _) = tree ctx env rhs
      pick cn infos (_ :: rest) = pick cn infos rest
      pick cn infos [] = internal ctx.fc ("no alternative for " ++ show cn)

  ||| The constructor alternatives of a match, each over its fields, and
  ||| the default. The value's shape, if known, rules out every other
  ||| constructor and gives the fields their shapes.
  conAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> Ord a =>
                    Ctx -> List (VarInfo a) -> Maybe ClosedTerm -> DataId -> List (CaseAlt vars) ->
                    Core (List (Alt a), Maybe (Term a))
  conAlternatives ctx env shape inst [] = pure ([], Nothing)
  conAlternatives ctx env shape inst (ConCase cn _ args rhs :: rest) = do
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
        tree ctx (under (arrange info.layout info.params fields) env) rhs
      Nothing => Unreachable <$> toLoc ctx.fc
    (alts, def') <- conAlternatives ctx env shape inst rest
    pure (MkAlt cid bs body :: alts, def')
  conAlternatives ctx env shape inst (DefaultCase rhs :: _) = pure ([], Just !(tree ctx env rhs))
  conAlternatives ctx env shape inst (DelayCase {} :: _) =
    reject ctx.fc ctx.owner Laziness "a match on a lazy value"
  conAlternatives ctx env shape inst (ConstCase {} :: _) =
    internal ctx.fc "a constant alternative in a constructor match"

  litAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> Ord a =>
                    Ctx -> List (VarInfo a) -> List (CaseAlt vars) ->
                    Core (List (Lit, Term a), Maybe (Term a))
  litAlternatives ctx env [] = pure ([], Nothing)
  litAlternatives ctx env (ConstCase c rhs :: rest) = do
    Just lit <- pure (constantLit c)
      | Nothing => reject ctx.fc ctx.owner StringPrimitive ("a match on " ++ show c)
    case lit of
      LDouble _ => reject ctx.fc ctx.owner Primitive "a match on a Double literal"
      _ => pure ()
    body <- tree ctx env rhs
    (alts, def) <- litAlternatives ctx env rest
    pure ((lit, body) :: alts, def)
  litAlternatives ctx env (DefaultCase rhs :: _) = pure ([], Just !(tree ctx env rhs))
  litAlternatives ctx env _ = internal ctx.fc "an unexpected alternative"
