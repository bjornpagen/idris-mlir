||| The guaranteed eliminations (docs/architecture/06-elimination.md, ELIM-G-*):
||| full Core to first-order Core.
|||
||| A two-level evaluator. `eval` is Futhark's judgment `E ⊢ e ⇝ ⟨e′, sv⟩`
||| (Hovgaard et al. TFP 2018) written in Kovács's `Gen` monad: it returns
||| the static value of a term and emits the residual first-order code of its
||| runtime parts. Values of a type that is not a value type (functions,
||| `Lazy`, static data such as `IO`) exist only here, as `SVal`s.
|||
||| Calls are decided by one driver, positive supercompilation's (Sørensen,
||| Glück and Jones, JFP 1996): a call that carries static information is
||| unfolded; a call is residualized as a call of a specialization keyed by
||| its configuration; and the whistle, homeomorphic embedding of a call's
||| configuration in an ancestor's on the unfolding path, stops unfolding by
||| generalizing the ancestor to their most specific generalization
||| (ELIM-G-19). A match on a runtime value whose alternatives yield static
||| values joins them at their least upper bound, a choice where they differ
||| (ELIM-G-20). `reify` turns a value that must exist at runtime into an
||| atom, or reports why it cannot (PROF-HEAP-*). Residual code keeps the
||| evaluation order of the input (SEM-EVAL-*).
module IdrisMLIR.Simplify

import IdrisMLIR.Code
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Rule
import IdrisMLIR.Simplify.Fold
import IdrisMLIR.Simplify.Gen
import IdrisMLIR.Simplify.Safety
import IdrisMLIR.Simplify.Value
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.List
import Data.Maybe
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.String
import Data.Vect

%default covering

V : Type
V = SVal Atom

------------------------------------------------------------------------------
-- The program
------------------------------------------------------------------------------

fnDef : Loc -> FnId -> M TFn
fnDef l f = do
  st <- get
  maybe (fail CoreCheck1 l ("unknown function " ++ show f)) pure (lookup f st.src.fns)

dataDef : Loc -> DataId -> M Data
dataDef l d = do
  st <- get
  maybe (fail CoreCheck1 l ("unknown data " ++ show d)) pure (lookup d st.src.datas)

conDef : Loc -> ConId -> M Con
conDef l c = do
  st <- get
  maybe (fail CoreCheck1 l ("unknown constructor " ++ show c)) pure (lookup c st.src.cons)

||| Why data is static, as the rule that a runtime choice of its constructor
||| breaks and what the data holds: a function (PROF-HEAP-1), a `Lazy` value
||| (PROF-HEAP-2), itself (SEM-REC-1) or an Integer (SEM-BIG-1), in that
||| order of precedence.
staticReason : SourceIndex -> DataId -> (Rule, String)
staticReason src d =
  case sortBy (\a, b => compare (fst a) (fst b)) (go (length (keys src.datas)) [d] d) of
    ((_, r) :: _) => r
    [] => (ProfHeap1, "a function")
  where
    reasons : Nat -> List DataId -> Ty -> List (Nat, (Rule, String))
    go : Nat -> List DataId -> DataId -> List (Nat, (Rule, String))
    go Z _ _ = []
    go (S k) seen n = case lookup n src.datas of
      Just dt => concatMap (reasons k seen . (.type)) (concatMap (.fields) dt.cons)
      Nothing => []
    reasons k seen (FunT {}) = [(0, (ProfHeap1, "a function"))]
    reasons k seen (LazyT _) = [(1, (ProfHeap2, "a Lazy value"))]
    reasons k seen (StaticT m) =
      if elem m seen then [(2, (ProfData3, "a value of its own type"))] else go k (m :: seen) m
    reasons k seen BigT = [(3, (ProfType4, "an Integer"))]
    reasons k seen (V _) = []

||| The type of a value after eliminations.
elimTy : Loc -> Ty -> List (Elim a) -> M Ty
elimTy l t [] = pure t
elimTy l (FunT _ _ r) (Apply _ :: es) = elimTy l r es
elimTy l (LazyT t) (ForceIt :: es) = elimTy l t es
elimTy l t (Proj c i :: es) = case dataOf t of
  Just _ => do
    con <- conDef l c
    maybe (fail CoreCheck1 l "a projection of a missing field") (\f => elimTy l f.type es) (getAt i con.fields)
  Nothing => fail CoreCheck1 l ("a projection from a value of type " ++ show t)
elimTy l t _ = fail CoreCheck1 l ("cannot eliminate a value of type " ++ show t)

||| The value type of a result that must exist at runtime.
runtimeTy : Loc -> Ty -> M VTy
runtimeTy l BigT = fail ProfType4 l "an Integer would exist at runtime here (SEM-BIG-1)"
runtimeTy l (StaticT d) = do
  st <- get
  dt <- dataDef l d
  let (rule, what) = staticReason st.src d
  fail rule l ("a value of type " ++ dt.idrisName ++ " holds " ++ what ++ ", and it would exist at " ++
               "runtime here, the result of a call that cannot be unfolded further, so it would need the heap")
runtimeTy l t = maybe (fail ProfHeap4 l ("a function or IO action would be the result of a call " ++
                                         "that cannot be unfolded further (" ++ show t ++ ")")) pure (value t)

||| May a call whose result has this static type wait until its result is
||| used (ELIM-G-5)? A function, a `Lazy` value, or an action: data with one
||| constructor that carries no world. Anything else static is computed now.
deferrable : Loc -> Ty -> M Bool
deferrable l (FunT {}) = pure True
deferrable l (LazyT _) = pure True
deferrable l (StaticT d) = do
  dt <- dataDef l d
  pure (case dt.cons of
          [con] => not (any ((== V WorldT) . (.type)) con.fields)
          _ => False)
deferrable l _ = pure False

------------------------------------------------------------------------------
-- What a value is
------------------------------------------------------------------------------

||| The value of a literal: a string and an Integer are static (ELIM-G-6,
||| SEM-BIG-1).
litVal : Lit -> V
litVal (LInt t n) = Dyn (IntT t) (ALit (LInt t n))
litVal (LChar c) = Dyn CharT (ALit (LChar c))
litVal (LStr s) = Text s
litVal (LDouble d) = Dyn DoubleT (ALit (LDouble d))
litVal (LBig n) = Big n

||| A value with static structure: anything but a runtime atom.
structured : V -> Bool
structured (Dyn _ _) = False
structured _ = True

||| A value known entirely at compile time: no runtime variable occurs in it,
||| directly or in what it captures.
constant : V -> Bool
constant v = all known (atoms [v] [])
  where
    known : (VTy, Atom) -> Bool
    known (_, AVar _) = False
    known _ = True

||| A variable or field of a runtime type; an erased one is the value
||| `Erased`, so it only ever reaches quantity-0 positions (CORE-INV-3).
dynVar : VarId -> VTy -> V
dynVar x ErasedT = Dyn ErasedT AErased
dynVar x t = Dyn t (AVar x)

------------------------------------------------------------------------------
-- Strings (ELIM-G-6, ELIM-G-7, ELIM-G-15)
------------------------------------------------------------------------------

||| Is a value a string?
isString : V -> Bool
isString (Text _) = True
isString (Chr _) = True
isString (Shown _ _) = True
isString (Append _ _) = True
isString (Dyn StrT _) = True
isString (Choice _ vs) = all isString vs
isString _ = False

||| A string known entirely.
strLit : V -> Maybe String
strLit (Text s) = Just s
strLit (Dyn StrT (ALit (LStr s))) = Just s
strLit (Append a b) = (++) <$> strLit a <*> strLit b
strLit (Chr (ALit (LChar c))) = Just (singleton (chr (cast c)))
strLit (Shown _ (ALit (LInt _ n))) = Just (show n)
strLit (Shown _ (ALit (LDouble d))) = Just (prim__cast_DoubleString d)
strLit _ = Nothing

||| Joins two strings, keeping literal text together.
append : V -> V -> V
append (Text "") b = b
append a (Text "") = a
append a b = case (strLit a, strLit b) of
  (Just x, Just y) => Text (x ++ y)
  _ => Append a b

||| Is a string known not to be empty (ELIM-G-15)?
nonEmpty : V -> Bool
nonEmpty (Text s) = s /= ""
nonEmpty (Shown _ _) = True
nonEmpty (Chr _) = True
nonEmpty (Append a b) = nonEmpty a || nonEmpty b
nonEmpty (Choice _ vs) = all nonEmpty vs
nonEmpty _ = False

||| The literal a value is known to be.
known : V -> Maybe Lit
known (Big n) = Just (LBig n)
known (Dyn _ (ALit x)) = Just x
known v = LStr <$> strLit v

------------------------------------------------------------------------------
-- Binding
------------------------------------------------------------------------------

||| Extends an environment with the fields of an alternative, the first field
||| innermost.
extend : (fs : List b) -> List V -> Vect n V -> Maybe (Vect (length fs + n) V)
extend [] [] env = Just env
extend (_ :: fs) (v :: vs) env = (v ::) <$> extend fs vs env
extend _ _ _ = Nothing

bindAlt : Loc -> (fs : List b) -> List V -> Vect n V -> M (Vect (length fs + n) V)
bindAlt l fs vs env =
  maybe (fail CoreCheck1 l "an alternative binds the wrong number of fields") pure (extend fs vs env)

||| The literals of a key's atoms, in traversal order.
keyLeaves : Config -> List Leaf
keyLeaves k = map snd (atoms k.args k.elims)


||| The types of the atoms of a shape that a join passes: all but the erased
||| ones, which are `Erased` wherever they are (CORE-INV-3).
passed : SVal a -> List VTy
passed s = filter (/= ErasedT) (map fst (atoms [s] []))

||| The atoms of a shape, from the atoms a join passed.
restore : List VTy -> List Atom -> List Atom
restore [] _ = []
restore (ErasedT :: ts) as = AErased :: restore ts as
restore (_ :: ts) (a :: as) = a :: restore ts as
restore (_ :: ts) [] = AErased :: restore ts []

||| Which atoms of a call's arguments and eliminations may be parameters of
||| a specialization: an erased atom inside a static value is `Erased`
||| wherever it is, while a quantity-0 argument stays a parameter
||| (CORE-ERASE-1).
parameterized : List V -> List (Elim Atom) -> List Bool
parameterized vs es = concatMap arg vs ++ map ((/= ErasedT) . fst) (atoms [] es)
  where
    arg : V -> List Bool
    arg (Dyn _ _) = [True]
    arg v = map ((/= ErasedT) . fst) (atoms [v] [])

||| Each atom of a call: the literal its key fixes, or whether it is a
||| parameter of the specialization.
positions : Config -> List V -> List (Elim Atom) -> List (Either Lit Bool)
positions key vs es = zipWith (\leaf, p => maybe (Right p) Left leaf) (keyLeaves key) (parameterized vs es)

||| The items at the parameters of a specialization.
atParams : List (Either Lit Bool) -> List x -> List x
atParams ps xs = mapMaybe (\(p, x) => if p == Right True then Just x else Nothing) (zip ps xs)

||| Why the driver unfolds a call (ELIM-G-19).
data Reason = Carries   -- static information: structure, a block, a String result, known arguments
            | Matches   -- only a literal in a position the body matches on

------------------------------------------------------------------------------
-- The evaluator
------------------------------------------------------------------------------

mutual
  ||| Evaluates a term and applies eliminations to its value.
  evalK : Vect n V -> Term n -> List (Elim Atom) -> M V
  -- G1: the lambda's body is the action it describes, not prefix code.
  evalK env (Lam _ _ caps _ body) (Apply a :: es) =
    leavePrefix (evalK (a :: map (`index` env) caps) body es)
  evalK env (Lam _ lbl caps b body) [] = pure (Lam lbl (map (`index` env) caps) b body)
  evalK env (Suspend _ _ caps body) (ForceIt :: es) =                              -- G8
    leavePrefix (evalK (map (`index` env) caps) body es)
  evalK env (Suspend _ lbl caps body) [] = pure (Thunk lbl (map (`index` env) caps) body)
  -- Arguments are evaluated left to right, as written, across a curried
  -- application too: `f (g x) (h y)` computes `g x` first (SEM-EVAL-2).
  evalK env t@(App _ _ _) es = do
    let (h, as) = spine t []
    vs <- traverse (\a => evalK env a []) as
    evalK env h (map Apply vs ++ es)
    where
      spine : Term n -> List (Term n) -> (Term n, List (Term n))
      spine (App _ f a) acc = spine f (a :: acc)
      spine f acc = (f, acc)
  evalK env (Resume _ e) es = evalK env e (ForceIt :: es)
  evalK env (Let l q v b) es = do                                                  -- G4
    v' <- if q == Q0 then pure (Dyn ErasedT AErased) else evalK env v []
    evalK (v' :: env) b es
  evalK env (Case l x alts def) es = matchCon env l (index x env) alts def es
  evalK env (CaseLit l x alts def) es = matchLit env l (index x env) alts def es
  evalK env (Unreachable l) es = dead l
  evalK env (Crash l m) es = crash l m
  evalK env e es = do
    v <- eval env e
    consume (locOf e) v es

  ||| Evaluates a term that is not an elimination context.
  eval : Vect n V -> Term n -> M V
  eval env (Var _ i) = pure (index i env)
  eval env (Literal _ lit) = pure (litVal lit)
  eval env (Erased _) = pure (Dyn ErasedT AErased)
  eval env (PrimApp l op args) = traverse (\a => evalK env a []) args >>= prim l op
  eval env (Effect l op args res) = traverse (\a => evalK env a []) args >>= io l op res
  eval env (Call l f args) = do
    vs <- traverse (\a => evalK env a []) args
    fn <- fnDef l f
    callValue l False Nothing fn vs []
  eval env (ConApp l c args) = do
    vs <- traverse (\a => evalK env a []) args
    dt <- dataDef l c.dataId
    -- G2: a constructor of constants stays known until it must exist.
    if dt.static || all constant vs
       then pure (Con c vs)
       else do
         as <- traverse (reify l) vs
         Dyn (DataT c.dataId) <$> bind l (DataT c.dataId) (OCon c (map fst as))
  eval env e = evalK env e []

  ------------------------------------------------------------------------------
  -- Matches
  ------------------------------------------------------------------------------

  ||| A literal match: selected at compile time on a literal, otherwise
  ||| residual, each alternative in its own block.
  matchLit : Vect n V -> Loc -> V -> List (Lit, Term n) -> Term n -> List (Elim Atom) -> M V
  matchLit env l (Choice t vs) alts def es = choose l t vs (\v => matchLit env l v alts def es)
  matchLit env l v alts def es = case known v of
    Just lit => evalK env (maybe def snd (find ((== lit) . fst) alts)) es
    Nothing =>
      if isString v
        -- G15: a string that is known not to be empty is not "".
        then if all ((== LStr "") . fst) alts && nonEmpty v
               then evalK env def es
               else fail ProfPrim4 l "a match on a string built at runtime"
        else do
          (x, _) <- reify l v
          arms <- traverse (\(k, e) => (k,) <$> blockV (locOf e) (evalK env e es)) alts
          d <- blockV (locOf def) (evalK env def es)
          joinLit l x arms d

  ||| A constructor match.
  matchCon : Vect n V -> Loc -> V -> List (Alt n) -> Maybe (Term n) -> List (Elim Atom) -> M V
  -- G2: a known constructor selects its alternative.
  matchCon env l (Con c fs) alts def es = case find (\(MkAlt k _ _) => k == c) alts of
    Just (MkAlt _ bs body) => do
      env' <- bindAlt l bs fs env
      evalK env' body es
    Nothing => maybe (fail CoreCheck1 l "no alternative for a known constructor") (\d => evalK env d es) def
  -- A deferred call of data: an action's fields are projections of it (G5);
  -- anything else is computed now, to its constructor.
  matchCon env l v@(Call f e as ms) alts def es = do
    fn <- fnDef l f
    t <- elimTy l fn.result ms
    Just d <- pure (dataOf t)
      | Nothing => fail ProfHeap1 l "a match on a static value that is not data"
    dt <- dataDef l d
    case (dt.cons, !(deferrable l t)) of
      ([con], True) => do
        fields <- for (zip [0 .. length con.fields] con.fields) $ \(i, fd) =>
          if fd.quantity == Q0 then pure (Dyn ErasedT AErased) else consume l v [Proj con.id i]
        matchCon env l (Con con.id fields) alts def es
      _ => callValue l True (Just e) fn as ms >>= \w => matchCon env l w alts def es
  matchCon env l (Choice t vs) alts def es = choose l t vs (\v => matchCon env l v alts def es)
  -- A runtime match: residual, with fresh binders in each alternative, since
  -- one alternative may be residualized more than once (CORE-INV-1).
  matchCon env l (Dyn (DataT d) x@(AVar _)) alts def es = do
    arms <- for alts $ \(MkAlt c bs body) => do
      con <- conDef l c
      tys <- traverse (\f => runtimeTy l f.type) con.fields
      ys <- traverse (const freshVar) tys
      env' <- bindAlt l bs (zipWith dynVar ys tys) env
      r <- blockV (locOf body) (evalK env' body es)
      pure (MkBranch c ys r)
    d' <- traverse (\e => blockV (locOf e) (evalK env e es)) def
    joinCase l x arms d'
  matchCon env l v alts def es = fail ProfHeap1 l ("a match on " ++ showShape (config v))

  ||| A match on a choice's tag: each alternative is the continuation applied
  ||| to one of its values.
  choose : Loc -> Atom -> List V -> (V -> M V) -> M V
  choose l t vs k = do
    arms <- for (zip [0 .. length vs] vs) $ \(i, v) =>
      (LInt IdrisInt (cast i),) <$> blockV l (k v)
    case reverse arms of
      [] => dead l
      ((_, lst) :: rest) => joinLit l t (reverse rest) lst

  ------------------------------------------------------------------------------
  -- Joins (ELIM-G-20)
  ------------------------------------------------------------------------------

  ||| The atoms a value passes to a join of shape `s`: its own but the
  ||| erased ones, a choice's tag, and undefined atoms for the alternatives
  ||| it is not.
  fit : Loc -> SVal () -> V -> M (List Atom)
  fit l s@(Choice _ alts) (Choice t ws) = do
    let types = passed s
    arms <- for (zip [0 .. length ws] ws) $ \(i, w) =>
      (LInt IdrisInt (cast i),) <$> block l (fit l s w)
    case reverse arms of
      [] => dead l
      ((_, lst) :: rest) => emitCaseLit l types t (reverse rest) lst
  fit l (Choice _ alts) v = do
    let indexed = zip [0 .. length alts] alts
    case find (\(_, a) => isJust (zipMatch (project a) (project v))) indexed of
      Nothing => fail CoreCheck1 l "a value that is none of a join's alternatives"
      Just (k, _) => do
        parts <- for indexed $ \(i, a) =>
          if i == k then fit l a v else pure (map AUndef (passed a))
        pure (ALit (LInt IdrisInt (cast k)) :: concat parts)
  fit l s v = case zipMatch (project s) (project v) of
    Nothing => fail CoreCheck1 l ("a value of shape " ++ showShape (config v) ++ " in a join of another shape")
    Just layer => do
      -- The atoms in traversal order: the layer's own, and each child's.
      parts <- execStateT [<] (traverseF (\(s', w) => do as <- lift (fit l s' w); modify (<>< as))
                                         (\t, (_, a) => when (t /= ErasedT) (modify (:< a))) layer)
      pure (parts <>> [])

  ||| The value of a residual match whose alternatives yield static values:
  ||| their least upper bound, whose atoms the match passes to the rest of
  ||| the block. When no alternative returns, the match ends the block.
  join : Loc -> List (Either (Code Pure) (List Stmt, V)) ->
         (List (Code Pure) -> List VTy -> M (List Atom)) -> (List (Code Pure) -> Code Pure) -> M V
  join l arms emit terminal = do
    let values = mapMaybe returned arms
    case values of
      [] => ends (terminal (mapMaybe stopped arms))
      (v :: vs) => do
        let s = foldl lub (shape v) (map shape vs)
        codes <- for arms $ \arm => case arm of
          Left c => pure c
          Right (p, w) => block l (replay p *> fit l s w)
        as <- emit codes (passed s)
        let every = restore (map fst (atoms [s] [])) as
        pure (fromMaybe (Dyn ErasedT AErased) (head' (fst (refill every AErased [s] []))))
    where
      returned : Either (Code Pure) (List Stmt, V) -> Maybe V
      returned (Right (_, v)) = Just v
      returned (Left _) = Nothing
      stopped : Either (Code Pure) (List Stmt, V) -> Maybe (Code Pure)
      stopped (Left c) = Just c
      stopped (Right _) = Nothing

  joinCase : Loc -> Atom -> List (Branch (Either (Code Pure) (List Stmt, V))) ->
             Maybe (Either (Code Pure) (List Stmt, V)) -> M V
  joinCase l x arms d =
    join l (map (.body) arms ++ toList d)
         (\codes, ts => emitCase l ts x (branches codes) (dflt codes))
         (\codes => Case l x (branches codes) (dflt codes))
    where
      branches : List (Code Pure) -> List (Branch (Code Pure))
      branches codes = zipWith (\b, c => MkBranch b.con b.fields c) arms codes
      dflt : List (Code Pure) -> Maybe (Code Pure)
      dflt codes = case d of
        Nothing => Nothing
        Just _ => head' (drop (length arms) codes)

  joinLit : Loc -> Atom -> List (Lit, Either (Code Pure) (List Stmt, V)) ->
            Either (Code Pure) (List Stmt, V) -> M V
  joinLit l x arms d =
    join l (map snd arms ++ [d])
         (\codes, ts => emitCaseLit l ts x (zip (map fst arms) codes) (lastOr codes))
         (\codes => CaseLit l x (zip (map fst arms) codes) (lastOr codes))
    where
      lastOr : List (Code Pure) -> Code Pure
      lastOr cs = fromMaybe (Absurd l) (last' cs)

  ------------------------------------------------------------------------------
  -- Eliminations and calls
  ------------------------------------------------------------------------------

  ||| Applies eliminations to a value.
  consume : Loc -> V -> List (Elim Atom) -> M V
  consume l v [] = pure v
  consume l (Lam _ caps _ body) (Apply a :: es) = leavePrefix (evalK (a :: caps) body es)
  consume l (Thunk _ caps body) (ForceIt :: es) = leavePrefix (evalK caps body es)
  consume l (Con c fs) (Proj _ i :: es) =
    maybe (fail CoreCheck1 l "a projection of a missing field") (\f => consume l f es) (getAt i fs)
  consume l (Call f e as ms) es = do
    fn <- fnDef l f
    callValue l True (Just e) fn as (ms ++ es)
  consume l (Choice t vs) es = choose l t vs (\v => consume l v es)
  consume l v es = fail ProfHeap1 l ("cannot apply or project " ++ showShape (config v))

  ||| A call of `fn` with argument values and eliminations. `built` is how
  ||| many effects had been emitted when a deferred call was built; a call
  ||| being consumed runs the action it describes, not prefix code.
  callValue : Loc -> Bool -> Maybe Nat -> TFn -> List V -> List (Elim Atom) -> M V
  callValue l consuming built fn vs es = do
    t <- elimTy l fn.result es
    now <- gets effects
    let e = fromMaybe now built
    let run = if consuming then leavePrefix else id
    case value t of
      -- G5: a function or action waits until it is used; anything else
      -- static is computed now.
      Nothing => if !(deferrable l t) then pure (Call fn.id e vs es) else run (drive l built Carries fn vs es)
      -- Moving code across an effect is not unfolding it.
      Just rt => case drives fn vs es rt of
        Just why => if e == now then run (drive l built why fn vs es) else run (residual l built fn vs es)
        Nothing => run (residual l built fn vs es)

  ||| Why a call is unfolded (ELIM-G-19), if it is: for static information it
  ||| carries, or only for a literal in a position the body matches on.
  drives : TFn -> List V -> List (Elim Atom) -> VTy -> Maybe Reason
  drives fn vs es rt =
    let args = vs ++ applied es
        matched = matchedParams fn.arity fn.body
    in if fn.block || fn.inline || rt == StrT || any structured args || all constant args
         then Just Carries
         else if any (\(i, v) => contains i matched && literalAtom v) (zip [0 .. length vs] vs)
           then Just Matches
           else Nothing
    where
      literalAtom : V -> Bool
      literalAtom (Dyn _ (ALit _)) = True
      literalAtom _ = False

  ||| The driver: unfolds a call, unless the whistle blows or the budget of
  ||| this residual body is spent (ELIM-G-19). A call unfolded only for a
  ||| literal its body matches on is unfolded at most `literalDepth` times on
  ||| one path, like call-pattern specialization's bound: a counting loop
  ||| from a literal is not unrolled.
  drive : Loc -> Maybe Nat -> Reason -> TFn -> List V -> List (Elim Atom) -> M V
  drive l built why fn vs es = atSite l $ do
    let c = MkConfig fn.id (map config vs) (configElims es)
    st <- get
    let repeated = unfoldingsOf fn.id st.path
    -- A call that cannot be unfolded further must have a runtime result,
    -- or it cannot be residualized either, here or at a generalized
    -- ancestor: its value would exist at runtime.
    if isJust (whistle c st.path) || spent st
      then do
        ignore (elimTy l fn.result es >>= runtimeTy l)
        blown c st
      else case (why, repeated) of
        (Matches, (i, anc) :: _) =>
          if length repeated >= literalDepth
            then maybe (residual l built fn vs es) (lift . Left . Generalize i) (generalize anc c)
            else unfolding c (unfold l fn vs es) (residualAt l built fn vs es)
        _ => unfolding c (unfold l fn vs es) (residualAt l built fn vs es)
    where
      forget : Config -> Config
      forget k = MkConfig k.fn (map generic k.args) (genericElims k.elims)
      blown : Config -> St -> M V
      blown c st = case whistle c st.path of
        -- Upward: the ancestor is generalized, and what it did is undone.
        Just (Unfolding i anc) => maybe (grows l fn c) (lift . Left . Generalize i) (generalize anc c)
        -- A specialization being made: the call becomes a call of the
        -- specialization for their generalization, often itself.
        Just (Specializing anc) => maybe (grows l fn c) (residualAt l built fn vs es) (generalize anc c)
        -- The budget is spent: the outermost unfolding of the function is
        -- generalized.
        Nothing => case outermost fn.id st.path of
          Just (i, anc) => lift (Left (Generalize i (forget anc)))
          Nothing => residual l built fn vs es

  ||| Evaluates a function's body with the values of its arguments.
  unfold : Loc -> TFn -> List V -> List (Elim Atom) -> M V
  unfold l fn vs es = do
    Just env <- pure (toVect fn.arity vs)
      | Nothing => fail CoreCheck1 l ("a call of " ++ show fn.id ++ " with the wrong arity")
    evalK env fn.body es

  ||| PROF-HEAP-4: the whistle blew on a call whose static arguments grow, so
  ||| no generalization can stand for them at runtime.
  grows : Loc -> TFn -> Config -> M a
  grows l fn c = fail ProfHeap4 l
    (fn.idrisName ++ " passes itself a function, IO action, Lazy value or other static value " ++
     "that grows with each call (" ++ showConfig c ++ "), so it cannot be specialized away")

  ||| A residual call: the specialization for the call's shapes (G3, G5), or
  ||| if that cannot be built, the one for its literals too (G17).
  residual : Loc -> Maybe Nat -> TFn -> List V -> List (Elim Atom) -> M V
  residual l built fn vs es = do
    let key = MkConfig fn.id (map generic vs) (genericElims es)
    let lits = MkConfig fn.id (map config vs) (configElims es)
    if key == lits then residualAt l built fn vs es key else do
      r <- attempt (residualAt l built fn vs es key)
      either (\_ => residualAt l built fn vs es lits) pure r

  ||| A call of the specialization for a key.
  residualAt : Loc -> Maybe Nat -> TFn -> List V -> List (Elim Atom) -> Config -> M V
  residualAt l built fn vs es key = atSite l $ do
    t <- elimTy l fn.result es >>= runtimeTy l
    name <- specialize l fn key vs es t
    now <- gets effects
    when (not (null es)) $
      modify { runs $= (:< (name, l, maybe False (< now) built)) }
    let as = atParams (positions key vs es) (atoms vs es)
    when (any ((== WorldT) . fst) as) effect
    Dyn t <$> bind l t (OCall name (map snd as))

  ||| The specialization of a function for a key, made on first use.
  specialize : Loc -> TFn -> Config -> List V -> List (Elim Atom) -> VTy -> M FnId
  specialize l fn key args es t = do
    st <- get
    case lookup key st.memo of
      Just name => pure name
      Nothing => do
        let n = fromMaybe 0 (lookup fn.id st.made)
        let name = if trivial key then fn.id else MkFnId (fn.id.name ++ "#" ++ show (S n))
        put ({ memo $= insert key name, made $= insert fn.id (S n) } st)
        -- Parameters: the atoms at the key's runtime leaves; a literal the
        -- key fixes is that literal in the body.
        let every = positions key args es
        let free = map fst (atParams every (atoms args es))
        params <- traverse (const freshVar) free
        let (args', es') = refill (supply (zipWith dynAtom params free) every) AErased args es
        Just env <- pure (toVect fn.arity args')
          | Nothing => fail CoreCheck1 l ("a call of " ++ show fn.id ++ " with the wrong arity")
        -- G5: the body before the eliminations apply runs where the action
        -- is used. Effects are counted within one function's code.
        outer <- gets effects
        body <- withPrefix (if null es then Nothing else Just name) $ specializing key $
                  block fn.loc (evalK env fn.body es' >>= \v => (\(a, _) => [a]) <$> reify fn.loc v)
        modify { effects := outer }
        -- CORE-INV-4: a runtime argument keeps the quantity of its
        -- parameter; the atoms of a static value are unrestricted.
        let qs0 = concat (zipWith quantities (toList fn.params) args) ++
                  map (defaultQuantity . fst) (atoms [] es)
        let qs = atParams every qs0
        let spec = if trivial key then Nothing else Just ("specialization of " ++ showConfig key)
        modify { done $= (:< MkCFn name fn.idrisName (zipWith3 MkParam params qs free)
                                   [t] body fn.loc fn.terminating spec) }
        pure name
    where
      dynAtom : VarId -> VTy -> Atom
      dynAtom x ErasedT = AErased
      dynAtom x _ = AVar x
      -- The atoms in order: a fixed literal, the next parameter, or erased.
      supply : List Atom -> List (Either Lit Bool) -> List Atom
      supply ps [] = []
      supply ps (Left lit :: rest) = ALit lit :: supply ps rest
      supply (p :: ps) (Right True :: rest) = p :: supply ps rest
      supply ps (_ :: rest) = AErased :: supply ps rest
      quantities : Binder -> V -> List Quantity
      quantities b (Dyn ErasedT _) = [Q0]
      quantities b (Dyn _ _) = [b.quantity]
      quantities b v = map (defaultQuantity . fst) (atoms [v] [])

  ------------------------------------------------------------------------------
  -- Reification (Futhark's residualization, Kovács's `down`)
  ------------------------------------------------------------------------------

  ||| A value that must exist at runtime, as an atom (PROF-HEAP-1..3).
  reify : Loc -> V -> M (Atom, VTy)
  reify l (Dyn t a) = pure (a, t)
  reify l (Choice t vs) = do
    v <- choose l t vs (\w => (\(a, ty) => Dyn ty a) <$> reify l w)
    reify l v
  reify l (Thunk {}) = fail ProfHeap2 l "a Lazy value would exist at runtime here"
  reify l (Big _) = fail ProfType4 l "an Integer would exist at runtime here (SEM-BIG-1)"
  -- G2: a known constructor of runtime data is built where it must exist.
  reify l v@(Con c fs) = do
    dt <- dataDef l c.dataId
    case (dt.static, dt.cons) of
      (False, _) => do
        as <- traverse (reify l) fs
        x <- bind l (DataT c.dataId) (OCon c (map fst as))
        pure (x, DataT c.dataId)
      (True, [_]) => fail ProfHeap1 l ("a function or IO action would exist at runtime here (" ++
                                       showShape (config v) ++ "); it must be applied, run or passed " ++
                                       "to a known function")
      -- Which constructor a value of static data has is chosen at runtime.
      (True, _) => do
        st <- get
        let (rule, what) = staticReason st.src c.dataId
        fail rule l ("a value of type " ++ dt.idrisName ++ " holds " ++ what ++ ", and it would " ++
                     "exist at runtime here, where which constructor it has is chosen, so it " ++
                     "would need the heap")
  reify l v = if isString v
    then case strLit v of
      Just s => pure (ALit (LStr s), StrT)
      -- Only literals and strings passed around exist at runtime.
      Nothing => fail ProfHeap3 l ("a string is built at runtime here and is not written directly by " ++
                                   "putStr, so it would need the heap")
    else fail ProfHeap1 l ("a function or IO action would exist at runtime here (" ++ showShape (config v) ++
                           "); it must be applied, run or passed to a known function")

  ------------------------------------------------------------------------------
  -- Primitives
  ------------------------------------------------------------------------------

  ||| Primitives: compile-time evaluation (G6) and static strings (G7). A
  ||| primitive of a choice is the primitive of each of its values.
  prim : Loc -> PrimOp -> List V -> M V
  prim l op vs = case (op, findIndex isChoice vs) of
    (Str Append, _) => strings
    (Str Cons, _) => strings
    (Str (ToStr _), _) => strings
    (_, Just i) => case getAt (cast i) vs of
      Just (Choice t ws) => choose l t ws (\w => prim l op (replaceAt (cast i) w vs))
      _ => strings
    _ => strings
    where
      isChoice : V -> Bool
      isChoice (Choice _ _) = True
      isChoice _ = False
      replaceAt : Nat -> V -> List V -> List V
      replaceAt Z w (_ :: xs) = w :: xs
      replaceAt (S k) w (x :: xs) = x :: replaceAt k w xs
      replaceAt _ _ [] = []
      -- SEM-BIG-1: every Integer operation is evaluated here.
      big : BigOp -> M V
      big b = case the (Maybe (List Lit)) (traverse known vs) of
        Just lits => maybe (fail ProfType4 l ("the Integer operation " ++ show b ++ " has no " ++
                                               "value at compile time here (SEM-BIG-1)"))
                           (pure . litVal) (foldBig b lits)
        Nothing => fail ProfType4 l ("an Integer computed from a runtime value (" ++ show b ++
                                     "), which would exist at runtime (SEM-BIG-1)")
      character : V -> M V
      character (Dyn _ (ALit (LChar n))) = pure (Text (singleton (chr (cast n))))
      character c = (\(a, _) => Chr a) <$> reify l c
      scalarOf : VTy -> Scalar
      scalarOf (IntT it) = SInt it
      scalarOf CharT = SChar
      scalarOf _ = SDouble
      shown : VTy -> V -> M V
      shown t n@(Dyn _ (ALit lit)) = case foldStr (ToStr (scalarOf t)) [lit] of
        Just s => pure (litVal s)
        Nothing => (\(a, _) => Shown t a) <$> reify l n
      shown t n = (\(a, _) => Shown t a) <$> reify l n
      strings : M V
      strings = case (op, vs) of
        (Str Append, [a, b]) =>
          if isString a && isString b then pure (append a b) else general l op vs
        (Str Cons, [c, s]) =>
          if isString s then (\h => append h s) <$> character c else general l op vs
        (Str (ToStr SChar), [c]) => character c
        (Str (ToStr (SInt t)), [n]) => shown (IntT t) n
        (Str (ToStr SDouble), [n]) => shown DoubleT n
        -- G15: the first character of a string whose first piece gives it.
        (Str Head, [s]) => case (strLit s, headOf s) of
          (Nothing, Just h) => Dyn CharT <$> h
          _ => general l op vs
        (Big b, _) => big b
        _ => general l op vs

  ||| The first character of a static string, when its first piece gives it
  ||| (ELIM-G-15): a literal or runtime character, or the sign or leading
  ||| digit of an integer shown at runtime.
  headOf : V -> Maybe (M Atom)
  headOf (Text s) = case unpack s of
    (c :: _) => Just (pure (ALit (LChar (cast (ord c)))))
    [] => Nothing
  headOf (Chr c) = Just (pure c)
  headOf (Shown (IntT t) a) = Just (leadingChar t a)
  headOf (Shown DoubleT a) = Just (bind noLoc CharT (OPrim DoubleHead [a]))
  headOf (Append (Text "") b) = headOf b
  headOf (Append a _) = headOf a
  headOf (Choice t vs) =
    if all (isJust . headOf) vs
      then Just (do v <- choose noLoc t vs (\w => maybe (dead noLoc) (map (Dyn CharT)) (headOf w))
                    fst <$> reify noLoc v)
      else Nothing
  headOf _ = Nothing

  ||| `-` for a negative number, else its leading decimal digit, found by
  ||| comparing with the powers of ten that fit the type.
  leadingChar : IntTy -> Atom -> M Atom
  leadingChar t a =
    if signed t
      then do
        neg <- bind noLoc (IntT IdrisInt) (OPrim (Compare CLt (SInt t)) [a, ALit (LInt t 0)])
        minus <- block noLoc (pure [ALit (LChar 45)])
        plus <- block noLoc (pure <$> digitChar (powers t))
        [c] <- emitCaseLit noLoc [CharT] neg [(LInt IdrisInt 1, minus)] plus
          | _ => fail CoreCheck1 noLoc "a leading character"
        pure c
      else digitChar (powers t)
    where
      raise : Integer -> Nat -> Integer
      raise b Z = 1
      raise b (S k) = b * raise b k
      powers : IntTy -> List Integer
      powers t = reverse (takeWhile (<= maxOf) [raise 10 k | k <- [1 .. 19]])
        where
          maxOf : Integer
          maxOf = if signed t then raise 2 (minus (width t) 1) - 1 else raise 2 (width t) - 1
      -- The digit is a divided by the largest power of ten not above it.
      digitChar : List Integer -> M Atom
      digitChar [] = do
        c <- bind noLoc (IntT t) (OPrim (IntOp Add t) [a, ALit (LInt t 48)])
        bind noLoc CharT (OPrim (Cast (SInt t) SChar) [c])
      digitChar (p :: ps) = do
        ge <- bind noLoc (IntT IdrisInt) (OPrim (Compare CGte (SInt t)) [a, ALit (LInt t p)])
        big <- block noLoc $ do
          d <- bind noLoc (IntT t) (OPrim (IntOp Div t) [a, ALit (LInt t p)])
          c <- bind noLoc (IntT t) (OPrim (IntOp Add t) [d, ALit (LInt t 48)])
          pure <$> bind noLoc CharT (OPrim (Cast (SInt t) SChar) [c])
        small <- block noLoc (pure <$> digitChar ps)
        [c] <- emitCaseLit noLoc [CharT] ge [(LInt IdrisInt 1, big)] small
          | _ => fail CoreCheck1 noLoc "a leading digit"
        pure c

  general : Loc -> PrimOp -> List V -> M V
  general l op vs = do
    as <- traverse (reify l) vs
    case (traverse literal (map fst as), op) of
      (Just lits, Run p) => maybe (residualPrim p as) (pure . litVal) (foldPrim p lits)
      (Just lits, Str s) => maybe (runtimeString s) (pure . litVal) (foldStr s lits)
      (Nothing, Run p) => residualPrim p as
      (Nothing, Str s) => runtimeString s
      (_, Big b) => fail CoreCheck1 l ("the Integer operation " ++ show b ++ " reached runtime")
    where
      literal : Atom -> Maybe Lit
      literal (ALit x) = Just x
      literal _ = Nothing
      residualPrim : Prim -> List (Atom, VTy) -> M V
      residualPrim p as = Dyn (primResult p) <$> bind l (primResult p) (OPrim p (map fst as))
      runtimeString : StrOp -> M V
      runtimeString s = fail ProfPrim4 l ("the string operation " ++ show s ++ " is not supported at runtime")

  ------------------------------------------------------------------------------
  -- IO
  ------------------------------------------------------------------------------

  ||| IO primitives, with output fusion for putStr (G7).
  io : Loc -> IOOp -> DataId -> List V -> M V
  io l PutStr res [s, w] =
    if isString s
      then do
        (w', _) <- reify l w
        putStr l res s w'
      else fail CoreCheck1 l "putStr of a value that is not a string"
  io l op res vs = do
    as <- traverse (reify l) vs
    effect
    Dyn (DataT res) <$> bind l (DataT res) (OIO op (map fst as) res)

  ||| Writes a static string: literal and runtime pieces in order, threading
  ||| the world (G7). Returns the last `IORes` value.
  putStr : Loc -> DataId -> V -> Atom -> M V
  putStr l res s w = case (strLit s, s) of
    (Just lit, _) => write PutStr (ALit (LStr lit))
    (_, Dyn StrT a) => write PutStr a
    (_, Chr c) => write PutChar c
    (_, Shown (IntT t) n) => write (PutInt t) n
    (_, Shown _ n) => write PutDouble n
    (_, Append a b) => do
      r <- putStr l res a w
      putStr l res b !(nextWorld r)
    -- G14: a choice, with the rest of the output in each alternative.
    (_, Choice t vs) => choose l t vs (\v => putStr l res v w)
    _ => fail CoreCheck1 l "putStr of a value that is not a string"
    where
      write : IOOp -> Atom -> M V
      write op a = effect *> (Dyn (DataT res) <$> bind l (DataT res) (OIO op [a, w] res))
      ||| The world inside an `IORes` value.
      nextWorld : V -> M Atom
      nextWorld (Dyn _ r) = do
        dt <- dataDef l res
        [mk] <- pure dt.cons
          | _ => fail CoreCheck1 l (show res ++ " is not an IO result")
        bind l WorldT (OField r mk.id 1)
      nextWorld _ = fail CoreCheck1 l "an IO result that is not a runtime value"

------------------------------------------------------------------------------
-- Entry
------------------------------------------------------------------------------

||| A data instance of full Core at runtime.
runtimeData : Data -> Maybe CData
runtimeData d = do
  cons <- traverse (\c => (\fs => MkCCon c.id c.tag fs c.loc) <$>
                            traverse (\f => MkCField f.quantity <$> value f.type) c.fields) d.cons
  pure (MkCData d.id d.idrisName cons d.loc)

||| The data instances a program uses: those its code and signatures
||| mention, and those their fields contain.
usedDatas : SortedMap DataId Data -> List (CFn Pure) -> SortedSet DataId
usedDatas datas fns = close (length (keys datas)) (fromList (concatMap mentioned fns))
  where
    ty : VTy -> List DataId
    ty (DataT d) = [d]
    ty _ = []
    mentioned : CFn Pure -> List DataId
    mentioned f = concatMap ty f.results ++ concatMap (ty . (.type)) f.params ++ datasOf f.body
    fieldsOf : DataId -> List DataId
    fieldsOf d = maybe [] (\dt => mapMaybe (dataOf . (.type)) (concatMap (.fields) dt.cons)) (lookup d datas)
    close : Nat -> SortedSet DataId -> SortedSet DataId
    close Z s = s
    close (S k) s = let s' = union s (fromList (concatMap fieldsOf (Prelude.toList s))) in
                    if length (Prelude.toList s') == length (Prelude.toList s) then s else close k s'

||| Runs the guaranteed eliminations from the root (CORE-PASS-1).
export
simplify : Source -> Either Diag (Target Pure)
simplify src = do
  let ix = MkSourceIndex (fromList [(f.id, f) | f <- src.fns])
                         (fromList [(d.id, d) | d <- src.datas])
                         (fromList [(c.id, c) | d <- src.datas, c <- d.cons])
  let Just root = lookup src.root ix.fns
    | Nothing => Left (MkDiag CoreCheck1 "Simplify" noLoc "the root is missing")
  let run = do
        ps <- for (toList root.params) $ \b => do
          t <- runtimeTy root.loc b.type
          x <- freshVar
          pure (dynVar x t)
        residual root.loc Nothing root ps []
  case runStateT (initial ix) run of
    Left (Fail d) => Left d
    Left (Dead l) => Left (MkDiag CoreCheck1 "Simplify" l "the root cannot return")
    Left (Ends _ _) => Left (MkDiag CoreCheck1 "Simplify" noLoc "a crash outside any function")
    Left (Generalize _ _) => Left (MkDiag CoreCheck1 "Simplify" noLoc "a generalization escaped its unfolding")
    Right (st, _) => do
      let fns = st.done <>> []
      checkMoved fns (st.moved <>> []) (st.runs <>> [])
      let used = usedDatas ix.datas fns
      let Just datas = traverse runtimeData [d | d <- src.datas, contains d.id used]
        | Nothing => Left (MkDiag CoreCheck1 "Simplify" noLoc "static data at runtime")
      pure (MkTarget datas (filter ((== src.root) . (.id)) fns ++ filter ((/= src.root) . (.id)) fns)
                     src.root src.entry)
