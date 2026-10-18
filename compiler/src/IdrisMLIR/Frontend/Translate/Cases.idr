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

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Dictionaries
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Forced
import IdrisMLIR.Frontend.Translate.Shapes
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Terms
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Syntax.Idr
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.WellFounded
import Data.Fin
import Data.List
import Data.List1
import Data.String
import Decidable.Equality
import Data.SortedMap
import Data.SortedSet
import Data.Vect

%default total

||| What each argument of a constructor alternative binds, in argument
||| order, read with the shape of the matched value's argument there when
||| its shape is known: a parameter is the instance's value, an argument of
||| quantity 0 a compile-time one, a dictionary field the implementation
||| the program builds it with, and a runtime field what `field` makes of
||| it and its shape. Nothing when a dictionary field has no construction
||| site yet, so that the constructor has no value (`Dictionaries`); every
||| dictionary field is asked, each in turn.
argsBound : {auto s : Ref TState TS} ->
            (field : Nat -> Binder -> ClosedTerm -> Maybe ClosedTerm -> VarInfo a) ->
            List ArgKind -> List ClosedTerm -> Core (Maybe (List (VarInfo a)))
argsBound field args shapes = sequence <$> go args shapes
  where
    -- The shape of an argument and those of the arguments after it; none
    -- once the shape gives no more.
    next : List ClosedTerm -> (Maybe ClosedTerm, List ClosedTerm)
    next [] = (Nothing, [])
    next (s :: ss) = (Just s, ss)

    go : List ArgKind -> List ClosedTerm -> Core (List (Maybe (VarInfo a)))
    go [] _ = pure []
    go (a :: as) ss = do
      let (s, ss') = next ss
      v <- case a of
             Param v => pure (Just (TypeValue v))
             ErasedArg => pure (Just (TypeValue (Erased EmptyFC Placeholder)))
             DictArg key _ => map (\impl => Static impl Nothing) <$> dictionaryOf key
             Field i b ity => pure (Just (field i b ity s))
      (v ::) <$> go as ss'

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

||| An arm of a match as its tree gives it: none, one no value takes (Idris
||| proved it impossible, or the value's shape rules it out), or one that
||| runs. An arm no value takes is left out of the match.
data Arm t = Absent | Dead | Present t

Functor Arm where
  map f Absent = Absent
  map f Dead = Dead
  map f (Present t) = Present (f t)

||| An arm, or, where the tree gives none, another.
orElse : Arm t -> Arm t -> Arm t
orElse Absent other = other
orElse arm _ = arm

||| What runs where the tree has no arm: nothing in a covering definition,
||| a crash otherwise.
missingArm : {0 nv : Nat} -> Ctx -> Loc -> Arm (IdrisMLIR.Term.Term nv)
missingArm ctx loc = if ctx.complete then Dead else Present (Crash loc ("unhandled input for " ++ ctx.owner))

||| A match's possible arms: its alternatives and its default when one runs,
||| its alternatives when none does; with no possible arm, the match is
||| unreachable.
armsOf : Loc -> Fin n -> List (Alt n) -> Arm (IdrisMLIR.Term.Term n) -> IdrisMLIR.Term.Term n
armsOf loc i alts (Present d) = Case loc i (Defaulted alts d)
armsOf loc i (a :: as) _ = Case loc i (Exhaustive (a ::: as))
armsOf loc i [] _ = Unreachable loc

||| A match on a natural's possible arms; with no possible arm, the match is
||| unreachable.
natArms : Loc -> Fin n -> Arm (IdrisMLIR.Term.Term n) -> Arm (Shown, IdrisMLIR.Term.Term (Under 1 n)) ->
          IdrisMLIR.Term.Term n
natArms loc x (Present z) (Present (p, s)) = CaseNat loc x (Both z p s)
natArms loc x (Present z) _ = CaseNat loc x (OnlyZero z)
natArms loc x _ (Present (p, s)) = CaseNat loc x (OnlySucc p s)
natArms loc x _ _ = Unreachable loc

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
export
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
export
coversAll : {auto c : Ref Ctxt Defs} -> List (CaseAlt vars) -> Core Bool
coversAll alts = do
  named <- SortedSet.fromList <$> traverse toFullNames (mapMaybe conName alts)
  every <- traverse toFullNames !(siblings alts)
  pure (not (null every) && all (\c => contains c named) every)

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

mutual
  ||| A case tree over its scope's variables, and the clauses that reach
  ||| it (`Forced`). Each leaf's term starts a path of its own
  ||| (`Terms.term`), and reads each variable where its clauses hold it.
  export
  tree : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
         Ctx -> List (VarInfo (Fin nv)) -> Clauses vars -> CaseTree vars -> Core (Term nv)
  tree ctx env cls (STerm _ tm) = term asWritten start (sizeAccessible start) ctx (heldAt cls env) tm
  -- Idris proved it cannot be reached. An `Unmatched` leaf of a covering
  -- definition is one too: a definition whose clauses are all impossible
  -- has only that leaf. In a definition with missing cases it is one of
  -- them, and crashes.
  tree ctx env cls (Unmatched msg) = missingCase ctx <$> toLoc ctx.fc
  tree ctx env cls Impossible = Unreachable <$> toLoc ctx.fc
  tree ctx env cls (Case {name} idx p _ alts) = do
    loc <- toLoc ctx.fc
    case getAt idx env of
      Just (Runtime i (Just WorldT) _) => case alts of
        [ConstCase WorldVal rhs] => tree ctx env (afterLit WorldVal scrutinee cls) rhs
        _ => internal ctx.fc "an unexpected match on the world"
      -- A match on a quantity-0 value (a proof, an index) is in the
      -- compile-time tree only when its type forces the alternative, as
      -- Idris's erasure check guarantees; its fields are erased too.
      Just (TypeValue (Erased _ _)) => forced alts
      -- A match on an implementation selects its alternative now.
      Just (Static t hole) => staticCase ctx env cls scrutinee t hole alts
      Just v@(Runtime i _ _) => runtime loc v i
      Just v@(Shaped i _ _ _) => runtime loc v i
      _ => internal ctx.fc "a match on a compile-time value"
    where
      scrutinee : Var vars
      scrutinee = MkVar p

      literals : Loc -> Fin nv -> Core (Term nv)
      literals loc i = do
        (litAlts, def) <- litAlternatives ctx env cls scrutinee alts
        let Just def = def <|> (if ctx.complete then Nothing else Just (missingCase ctx loc))
          | Nothing => reject ctx.fc ctx.owner Match "a literal match without a default"
        pure (CaseLit loc i (LitDefault litAlts def))

      -- The data instance a match's constructors are of, at the value's
      -- type. The Core type names it when it is a declaration the
      -- constructor belongs to; a value of a type with one runtime field
      -- has its field's type, so the Idris type names it then.
      instanceOf : VarInfo (Fin nv) -> GlobalDef -> Core DataId
      instanceOf v def = do
        st <- get TState
        let cn = fullname def
        fromCore <- case coreTyOf v of
                      Just (DataT d) => do
                        Just cid <- conIdOf d def
                          | Nothing => pure Nothing
                        pure (case lookup cid st.cons of
                                Just layout => if layout.name == cn then Just d else Nothing
                                Nothing => Nothing)
                      _ => pure Nothing
        case (fromCore, idrisTypeOf v) of
          (Just d, _) => pure d
          (Nothing, Just ity) => do
            ity' <- normaliseClosed ity
            Just (inst, _) <- dataOf ctx.fc ctx.owner ity'
              | Nothing => do
                  -- A value array is abstract: only the functions the
                  -- registry knows open it, and their bodies are not
                  -- translated.
                  Just _ <- arrayView ity'
                    | Nothing => internal ctx.fc ("a match on " ++ show cn ++ " at a type that is not data")
                  reject ctx.fc ctx.owner HookShape
                         ("the array type of " ++ show cn ++ " is opaque: its constructor is matched")
            pure inst
          (Nothing, Nothing) =>
            internal ctx.fc ("a match on " ++ show cn ++ " of a value whose type is not known")

      -- A match on a runtime value's constructors or literals.
      matched : Loc -> VarInfo (Fin nv) -> Fin nv -> Core (Term nv)
      matched loc v i =
        case mapMaybe conName alts of
          [] => literals loc i
          (cn :: _) => do
            def <- lookupDef ctx.fc ctx.owner cn
            let shape = shapeOf v
            case natRole def of
              -- A `Nat`-like value is a natural: a match on its
              -- constructors is a match on zero.
              Just _ => natCase ctx env cls scrutinee shape loc i (idrisTypeOf v) alts
              Nothing => do
                inst <- instanceOf v def
                st <- get TState
                if isJust (newtypeOf inst st)
                   then newtypeCase ctx env cls scrutinee v inst alts
                   else do
                     every <- coversAll alts
                     built <- builtNamed shape alts
                     (named, conAlts, fallback) <- conAlternatives ctx env cls scrutinee shape every built inst alts
                     st' <- get TState
                     -- Constructors a tree with no default leaves out are
                     -- impossible when the definition is covering, and
                     -- crash otherwise.
                     let crashing = case (fallback, ctx.complete, declared inst st') of
                                      (Absent, False, Just dt) =>
                                        map (\(k ** c) => MkAlt c (replicate k (shown "_")) (missingCase ctx loc))
                                            (filter (\(_ ** c) => not (contains c.id named)) (consOf dt))
                                      _ => []
                     pure (armsOf loc i (conAlts ++ crashing) fallback)

      -- A match on a runtime value, by what its alternatives match: a
      -- suspension's form, a natural's constructors, one runtime field's
      -- constructor, a declaration's constructors, or literals. A
      -- suspension has one form, `Delay x`, so its match chooses nothing:
      -- it is the force, whose value `x` binds, then the alternative's
      -- tree, whose first variable is the value's type, erased.
      runtime : Loc -> VarInfo (Fin nv) -> Fin nv -> Core (Term nv)
      runtime loc v i = delayed alts
        where
          -- The first alternative that matches a suspension, or a match on
          -- the value's constructors or literals.
          delayed : List (CaseAlt vars) -> Core (Term nv)
          delayed (DelayCase _ arg rhs :: _) = do
            let value = case (coreTyOf v, idrisTypeOf v) of
                          (Just (LazyT t), Just (TDelayed _ _ ity)) => Runtime FZ (Just t) (Just ity)
                          (Just (LazyT t), _) => Runtime FZ (Just t) Nothing
                          _ => Runtime FZ Nothing Nothing
            body <- tree ctx (under {k = 1} [TypeValue (Erased ctx.fc Placeholder), value] env)
                         (afterDelay scrutinee cls) rhs
            pure (Let loc (binderName arg) Many (Resume loc (Var loc i)) body)
          delayed (_ :: rest) = delayed rest
          delayed [] = matched loc v i

      forced : List (CaseAlt vars) -> Core (Term nv)
      forced [ConCase cn _ args rhs] = do
        def <- lookupDef ctx.fc ctx.owner cn
        tree ctx (map (const (TypeValue (Erased ctx.fc Placeholder))) args ++ env)
             !(afterCon cn (type def) scrutinee args cls) rhs
      forced [DefaultCase rhs] = tree ctx env cls rhs
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
            Ctx -> List (VarInfo (Fin nv)) -> Clauses vars -> Var vars ->
            Maybe ClosedTerm -> Loc -> Fin nv -> Maybe ClosedTerm ->
            List (CaseAlt vars) -> Core (Term nv)
  natCase ctx env cls scrutinee shape loc x ity alts = do
    every <- coversAll alts
    built <- builtNamed shape alts
    (z, s, d) <- natAlternatives ctx env cls scrutinee shape ity (every || built) loc x alts
    -- Where the tree has no arm for zero or a successor, the default runs,
    -- or, with none, what runs where the tree has no arm.
    let otherwise = orElse d (missingArm ctx loc)
    pure $ case (z, s) of
      (Absent, Absent) => case otherwise of
        Present t => t
        _ => Unreachable loc
      _ => natArms loc x (orElse z otherwise) (orElse s (map (\t => (shown "_", weakenUnder 1 t)) otherwise))

  ||| The alternatives of a match on a `Nat`-like value: zero's, the
  ||| successor's (over the predecessor, named, its erased arguments
  ||| compile-time values), and the default, unless no value takes it
  ||| (`deadDefault`). The value's shape, if known, rules one of the two out,
  ||| and gives the predecessor its own; the predecessor is of the value's
  ||| type (`ity`).
  natAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                    Ctx -> List (VarInfo (Fin nv)) -> Clauses vars -> Var vars ->
                    Maybe ClosedTerm -> Maybe ClosedTerm -> Bool -> Loc -> Fin nv ->
                    List (CaseAlt vars) ->
                    Core (Arm (Term nv), Arm (Shown, Term (Under 1 nv)), Arm (Term nv))
  natAlternatives ctx env cls scrutinee shape ity deadDefault loc x [] = pure (Absent, Absent, Absent)
  natAlternatives ctx env cls scrutinee shape ity deadDefault loc x (ConCase cn _ args rhs :: rest) = do
    def <- lookupDef ctx.fc ctx.owner cn
    erasedAt <- erasedArgs cn
    dead <- excludedBy shape (fullname def)
    cls' <- afterCon cn (type def) scrutinee args cls
    case natRole def of
      Just Zero => do
        z <- if dead then pure Dead
             else Present <$> tree ctx (map (const (TypeValue (Erased ctx.fc Placeholder))) args ++ env) cls' rhs
        (_, s, d) <- natAlternatives ctx env cls scrutinee shape ity deadDefault loc x rest
        pure (z, s, d)
      Just Succ => do
        let erased = erasedAt ++ replicate (length args) False
        let predInfo : VarInfo (Fin (Under 1 nv))
            predInfo = case (predecessor (shapeArgs shape) erased, ity) of
                         (Just p, Just t) => shaped FZ NatT t p
                         _ => Runtime FZ (Just NatT) ity
        let infos = zipWith (\_, e => if e then TypeValue (Erased ctx.fc Placeholder) else predInfo)
                            args erased
        let pred = maybe (shown "_") (binderName . fst) (find (not . snd) (zip args erased))
        body <- if dead then pure Dead
                else (\b => Present (pred, b)) <$> tree ctx (under {k = 1} infos env) cls' rhs
        (z, _, d) <- natAlternatives ctx env cls scrutinee shape ity deadDefault loc x rest
        pure (z, body, d)
      Nothing => internal ctx.fc ("a constructor of another type in a match on a Nat-like value")
    where
      -- The successor's one runtime argument, among the shape's.
      predecessor : List ClosedTerm -> List Bool -> Maybe ClosedTerm
      predecessor (a :: as) (True :: es) = predecessor as es
      predecessor (a :: as) _ = Just a
      predecessor [] _ = Nothing
  natAlternatives ctx env cls scrutinee shape ity deadDefault loc x (DefaultCase rhs :: _) =
    pure (Absent, Absent, !(if deadDefault then pure Dead else Present <$> tree ctx env cls rhs))
  natAlternatives ctx env cls scrutinee shape ity deadDefault loc x (_ :: _) =
    internal ctx.fc "an unexpected alternative"

  ||| A match on a compile-time value: the implementation is reduced to its
  ||| constructor, and the alternative's variables stand for its arguments.
  ||| An argument that mentions the runtime value the implementation closes
  ||| over closes over it too.
  staticCase : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
               Ctx -> List (VarInfo (Fin nv)) -> Clauses vars -> Var vars ->
               ClosedTerm -> Maybe (Fin nv, Holes) ->
               List (CaseAlt vars) -> Core (Term nv)
  staticCase ctx env cls scrutinee t hole alts = do
    Built cn cargs <- whnf t
      | Stuck on => do
          -- An implementation chosen by a runtime value, or computed by a
          -- definition no compile-time reduction may run, is one whose set
          -- of choices nothing bounds.
          let rule = case on of
                       OnRuntime _ => RuntimeClosure
                       _ => StaticArgument
          reject ctx.fc ctx.owner rule
                 ("an implementation that does not reduce to its constructor: " ++ !(showTT t) ++
                  ", stuck on " ++ !(stuckText on))
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
          def <- lookupDef ctx.fc ctx.owner con
          tree ctx (infos ++ env) !(afterCon con (type def) scrutinee args cls) rhs
      pick cn infos (DefaultCase rhs :: _) = tree ctx env cls rhs
      pick cn infos (_ :: rest) = pick cn infos rest
      pick cn infos [] = internal ctx.fc ("no alternative for " ++ show cn)

  ||| A match on a value of a type with one runtime field, which is the
  ||| field's value: nothing is matched at runtime, the alternative's
  ||| arguments stand for what the constructor holds, and its field for the
  ||| matched value itself, at the field's type.
  newtypeCase : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                Ctx -> List (VarInfo (Fin nv)) -> Clauses vars -> Var vars ->
                VarInfo (Fin nv) -> DataId -> List (CaseAlt vars) -> Core (Term nv)
  newtypeCase ctx env cls here scrutinee inst alts = firstNamed alts
    where
      -- The field is the matched value itself, with what its shape says
      -- of it.
      field : Nat -> Binder -> ClosedTerm -> Maybe ClosedTerm -> VarInfo (Fin nv)
      field _ b ity s = case (variableOf scrutinee, s) of
        (Just x, Just s') => shaped x (typeOf b) ity s'
        (Just x, Nothing) => Runtime x (Just (typeOf b)) (Just ity)
        (Nothing, _) => TypeValue (Erased EmptyFC Placeholder)

      -- The default, when no alternative names the constructor.
      fallback : List (CaseAlt vars) -> Core (Term nv)
      fallback (DefaultCase rhs :: _) = tree ctx env cls rhs
      fallback (_ :: rest) = fallback rest
      fallback [] = internal ctx.fc "a match on a value of one field without an alternative"

      -- The first alternative that names the constructor, or the default.
      firstNamed : List (CaseAlt vars) -> Core (Term nv)
      firstNamed (ConCase cn _ args rhs :: _) = do
        def <- lookupDef ctx.fc ctx.owner cn
        Just cid <- conIdOf inst def
          | Nothing => internal ctx.fc ("the constructor " ++ show (fullname def) ++ " is not registered")
        st <- get TState
        let Just info = lookup cid st.cons
          | Nothing => internal ctx.fc ("the constructor " ++ show (fullname def) ++ " is not registered")
        when (length info.args /= length args) $
          reject ctx.fc ctx.owner CompiledModule
                 ("constructor " ++ show (fullname def) ++ " binds an unexpected number of arguments")
        -- A dictionary field no construction site has given is one of no
        -- value: the alternative is unreachable (`Dictionaries`).
        Just infos <- argsBound field info.args (shapeArgs (shapeOf scrutinee))
          | Nothing => Unreachable <$> toLoc ctx.fc
        tree ctx (infos ++ env) !(afterCon cn (type def) here args cls) rhs
      firstNamed (_ :: rest) = firstNamed rest
      firstNamed [] = fallback alts

  ||| The constructors a match's alternatives name, its possible
  ||| alternatives, each over its fields, named as the alternative names
  ||| them, and the default: none when the alternatives name every
  ||| constructor (`every`), one no value takes when they name the one the
  ||| value's shape says it was built with (`built`). The shape, if known,
  ||| rules out every other constructor and gives the fields their shapes;
  ||| an alternative it rules out, or of a constructor with no value yet,
  ||| is no possible one.
  conAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                    Ctx -> List (VarInfo (Fin nv)) -> Clauses vars -> Var vars ->
                    Maybe ClosedTerm -> Bool -> Bool -> DataId ->
                    List (CaseAlt vars) -> Core (SortedSet ConId, List (Alt nv), Arm (Term nv))
  conAlternatives ctx env cls scrutinee shape every built inst [] = pure (empty, [], Absent)
  conAlternatives ctx env cls scrutinee shape every built inst (ConCase cn _ args rhs :: rest) = do
    def <- lookupDef ctx.fc ctx.owner cn
    Just cid <- conIdOf inst def
      | Nothing => internal ctx.fc ("the constructor " ++ show (fullname def) ++ " is not registered")
    st <- get TState
    let Just info = lookup cid st.cons
      | Nothing => internal ctx.fc ("the constructor " ++ show (fullname def) ++ " is not registered")
    when (length info.args /= length args) $
      reject ctx.fc ctx.owner CompiledModule
             ("constructor " ++ show (fullname def) ++ " binds an unexpected number of arguments")
    let named = mapMaybe fieldNamed (zip args info.args)
    -- The alternative binds the constructor's fields, as many as its tree
    -- names.
    let (k ** con) = info.con
    let Yes counted = decEq (length named) k
      | No _ => internal ctx.fc ("the constructor " ++ show (fullname def) ++ " of " ++ show k ++
                                 " fields, which its alternative binds " ++ show (length named) ++ " of")
    dead <- excludedBy shape (fullname def)
    -- A dictionary field stands for the one implementation the program
    -- builds it with; before any construction site is known, no value of
    -- the constructor exists and the alternative is impossible
    -- (`Dictionaries`).
    found <- argsBound (fieldAt k) info.args (shapeArgs shape)
    alt <- case found of
      Just infos => if dead then pure Nothing else do
        body <- tree ctx (under {k} infos env) !(afterCon cn (type def) scrutinee args cls) rhs
        pure (Just (MkAlt con (replace {p = \c => Vect c Shown} counted (fromList named)) body))
      Nothing => pure Nothing
    (others, alts, fallback) <- conAlternatives ctx env cls scrutinee shape every built inst rest
    pure (insert cid others, maybe alts (:: alts) alt, fallback)
    where
      fieldNamed : (Name, ArgKind) -> Maybe Shown
      fieldNamed (n, Field _ _ _) = Just (binderName n)
      fieldNamed _ = Nothing

      -- Runtime field `i` is the alternative's `Bound i`, with what the
      -- value's shape says of it.
      fieldAt : (k : Nat) -> Nat -> Binder -> ClosedTerm -> Maybe ClosedTerm -> VarInfo (Fin (Under k nv))
      fieldAt k i b ity s = case natToFin i k of
        Just f => case s of
          Just s' => shaped (Bound {n = nv} f) (typeOf b) ity s'
          Nothing => Runtime (Bound {n = nv} f) (Just (typeOf b)) (Just ity)
        Nothing => TypeValue (Erased EmptyFC Placeholder)
  conAlternatives ctx env cls scrutinee shape every built inst (DefaultCase rhs :: _) =
    if every then pure (empty, [], Absent)
      else if built then pure (empty, [], Dead)
      else (\d => (empty, [], Present d)) <$> tree ctx env cls rhs
  conAlternatives ctx env cls scrutinee shape every built inst (DelayCase {} :: _) =
    internal ctx.fc "a suspension's alternative in a constructor match"
  conAlternatives ctx env cls scrutinee shape every built inst (ConstCase {} :: _) =
    internal ctx.fc "a constant alternative in a constructor match"

  litAlternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                    Ctx -> List (VarInfo (Fin nv)) -> Clauses vars -> Var vars ->
                    List (CaseAlt vars) ->
                    Core (List (Lit, Term nv), Maybe (Term nv))
  litAlternatives ctx env cls scrutinee [] = pure ([], Nothing)
  litAlternatives ctx env cls scrutinee (ConstCase c rhs :: rest) = do
    Just lit <- pure (constantLit c)
      | Nothing => reject ctx.fc ctx.owner StringPrimitive ("a match on " ++ show c)
    case lit of
      LDouble _ => reject ctx.fc ctx.owner Primitive "a match on a Double literal"
      _ => pure ()
    body <- tree ctx env (afterLit c scrutinee cls) rhs
    (alts, def) <- litAlternatives ctx env cls scrutinee rest
    pure ((lit, body) :: alts, def)
  litAlternatives ctx env cls scrutinee (DefaultCase rhs :: _) =
    pure ([], Just !(tree ctx env cls rhs))
  litAlternatives ctx env cls scrutinee _ = internal ctx.fc "an unexpected alternative"
