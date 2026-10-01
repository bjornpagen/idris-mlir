||| Terms: a TT term in scope, with an environment saying what each of its
||| variables stands for, as a Core term. A call requests the instance it
||| calls.
module IdrisMLIR.Frontend.Translate.Terms

import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Hooks
import IdrisMLIR.Frontend.Translate.Instances
import IdrisMLIR.Frontend.Translate.Primitives
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Registry
import IdrisMLIR.Rule
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.Fin
import Data.List
import Data.SortedMap
import Data.Vect

%default covering

public export
record Ctx where
  constructor MkCtx
  owner : String
  fc : FC
  complete : Bool     -- Idris found no missing case

export
constantLit : Constant -> Maybe Lit
constantLit (I x) = Just (LInt IdrisInt (cast x))
constantLit (I8 x) = Just (LInt SInt8 (cast x))
constantLit (I16 x) = Just (LInt SInt16 (cast x))
constantLit (I32 x) = Just (LInt SInt32 (cast x))
constantLit (I64 x) = Just (LInt SInt64 (cast x))
constantLit (B8 x) = Just (LInt UInt8 (cast x))
constantLit (B16 x) = Just (LInt UInt16 (cast x))
constantLit (B32 x) = Just (LInt UInt32 (cast x))
constantLit (B64 x) = Just (LInt UInt64 (cast x))
constantLit (Ch x) = Just (LChar (cast (ord x)))
constantLit (Str x) = Just (LStr x)
constantLit (Db x) = Just (LDouble x)
constantLit (BI x) = Just (LBig x)
constantLit _ = Nothing

bestFC : Ctx -> FC -> FC
bestFC ctx fc = if isEmptyFC fc then ctx.fc else fc

||| A closure-converted lambda (`Term.lam`).
closure : {auto s : Ref TState TS} -> Ord a => FC -> Loc -> Binder -> Term (Under 1 a) -> Core (Term a)
closure fc loc b body = do
  lbl <- label
  maybe (internal fc "a lambda body that is not well scoped") pure (lam loc lbl b body)

||| Eta-expands a known head applied to too few arguments:
||| `\x.. => head(args ++ xs)`.
etaExpand : {auto s : Ref TState TS} -> Ord a => FC -> Loc -> List Binder ->
            ({0 b : Type} -> List (Term b) -> Term b) -> List (Term a) -> Core (Term a)
etaExpand fc loc [] mk given = pure (mk given)
etaExpand fc loc (b :: rest) mk given = do
  body <- etaExpand fc loc rest mk (map (map Free) given ++ [argument b])
  closure fc loc b body
  where
    argument : Binder -> Term (Under 1 a)
    argument Gone = Erased loc
    argument (Held _ _) = Var loc (Bound FZ)

||| The position of a `Nat`-like successor's argument: its one argument of
||| runtime quantity (the others are erased indices, as `FS`'s).
succArg : List PKind -> Maybe Nat
succArg kinds = case mapMaybe runtime (zip [0 .. length kinds] kinds) of
  [i] => Just i
  _ => Nothing
  where
    runtime : (Nat, PKind) -> Maybe Nat
    runtime (i, ValueParam (Held _ _)) = Just i
    runtime _ = Nothing

mutual
  export
  term : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> Ord a =>
         Ctx -> List (VarInfo a) -> TT vars -> Core (Term a)
  term ctx env (Local fc _ idx _) = do
    loc <- toLoc (bestFC ctx fc)
    case getAt idx env of
      Just (Runtime x _) => pure (Var loc x)
      Just (TypeValue _) => pure (Erased loc)
      Just (Static t) => term {vars} ctx env (embedClosed {vars} t)
      Nothing => internal (bestFC ctx fc) "a variable out of scope"
  term ctx env (PrimVal fc c) = do
    loc <- toLoc (bestFC ctx fc)
    case constantLit c of
      Just l => pure (Literal loc l)
      Nothing => case c of
        -- A trusted library forges a world (`unsafePerformIO`); the
        -- profile has rejected the user's (Profile.checkReachable).
        WorldVal => pure (NewWorld loc)
        PrT _ => pure (Erased loc)
        _ => reject (bestFC ctx fc) ctx.owner ValueType ("constant " ++ show c)
  term ctx env (TType fc _) = Erased <$> toLoc (bestFC ctx fc)
  term ctx env (Erased fc _) = Erased <$> toLoc (bestFC ctx fc)
  term ctx env (Bind fc _ (Pi {}) _) = Erased <$> toLoc (bestFC ctx fc)
  term ctx env tm@(Bind fc x (Let lfc rig val ty) sc) = do
    let Nothing = delayedLets tm
      | Just (dfc, arg) => suspend ctx env dfc arg
    -- TTC does not keep the types of lets (Core.TTC, `Let` binders): `Emit`
    -- synthesizes them.
    loc <- toLoc (bestFC ctx fc)
    let env' = under [Runtime (Bound FZ) Nothing] env
    if isErased rig
       then Let loc Many (Erased loc) <$> term ctx env' sc
       else Let loc (useOf rig) <$> term ctx env val <*> term ctx env' sc
  term ctx env (Bind fc x (Lam lfc rig _ ty) sc) = do
    loc <- toLoc (bestFC ctx fc)
    b <- binderOf rig (coreType (bestFC ctx fc) ctx.owner ValueType !(closeNormalise fc env ty))
    body <- term ctx (under [Runtime (Bound FZ) (Just (typeOf b))] env) sc
    closure fc loc b body
  term ctx env (TDelay fc _ _ arg) = suspend ctx env fc arg
  term ctx env (TForce fc _ arg) = Resume <$> toLoc (bestFC ctx fc) <*> term ctx env arg
  term ctx env (TDelayed fc _ _) = Erased <$> toLoc (bestFC ctx fc)
  term ctx env (Meta fc n _ _) = reject (bestFC ctx fc) ctx.owner Laziness ("hole or metavariable " ++ show n)
  term ctx env (As fc _ _ pat) = term ctx env pat
  term ctx env tm@(App fc _ _) = let (fn, args) = spine tm [] in application ctx env fc fn args
  term ctx env tm@(Ref fc _ _) = application ctx env fc tm []
  term ctx env (Bind fc _ _ _) = internal (bestFC ctx fc) "a binder in a runtime position"

  suspend : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> Ord a =>
            Ctx -> List (VarInfo a) -> FC -> TT vars -> Core (Term a)
  suspend ctx env fc arg = do
    loc <- toLoc (bestFC ctx fc)
    body <- term ctx env arg
    lbl <- label
    maybe (internal fc "a delayed term that is not well scoped") pure (delay loc lbl body)

  application : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} -> Ord a =>
                Ctx -> List (VarInfo a) -> FC -> TT vars -> List (TT vars) -> Core (Term a)
  application ctx env afc (Ref rfc nt name) args = do
    let fc = bestFC ctx rfc
    loc <- toLoc fc
    def <- lookupDef fc ctx.owner name
    let full = fullname def
    case definition def of
      -- A hook for the identity on the one runtime argument, the
      -- last (`replace`, and `rewrite__impl`, which `rewrite` elaborates
      -- to); the rest are proofs and types.
      PMDef _ params _ _ _ => case natOperationOf (hooksOf full) of
        Just m => natOperation fc loc m (length params) (type def) args
        Nothing =>
          if identityOnLast (hooksOf full) && length args >= length params
             then do
               let (now, rest) = splitAt (length params) args
               v <- maybe (pure (Erased loc)) (term ctx env) (last' now)
               applyAll loc v rest
             else call fc loc full (length params) (type def) args
      DCon tag arity _ => constructor fc loc def arity args
      TCon {} => pure (Erased loc)
      Builtin {arity} op => primitive fc loc full arity op args
      -- An IO primitive the registry lists, a `%foreign` one by
      -- its spec and an `%extern` one by its name.
      ForeignDef arity specs => case foreignHookOf full specs of
        Just (Right (IOCall op)) => ioCall fc loc arity op (type def) args
        Just (Right ArraySize) => arraySize fc loc arity (type def) args
        Just (Left wrong) => reject fc (show full) HookShape wrong
        _ => reject fc ctx.owner EscapeHatch ("foreign function " ++ show full)
      ExternDef arity => case (ioCallOf (hooksOf full), arrayCallOf (hooksOf full)) of
        (Just op, _) => ioCall fc loc arity op (type def) args
        (_, Just op) => arrayCall fc loc arity op (type def) args
        _ => reject fc ctx.owner EscapeHatch ("extern function " ++ show full)
      Hole {} => reject fc ctx.owner Laziness ("hole " ++ show full)
      _ => internal fc ("a reference to " ++ show full)
    where
      applyAll : Loc -> Term a -> List (TT vars) -> Core (Term a)
      applyAll loc f [] = pure f
      applyAll loc f (x :: xs) = applyAll loc (App loc f !(term ctx env x)) xs

      -- Arguments: values of type parameters, erased ones, runtime ones.
      arguments : Loc -> List PKind -> List (TT vars) -> Core (List (Term a))
      arguments loc kinds xs = traverse arg (zip kinds xs)
        where
          arg : (PKind, TT vars) -> Core (Term a)
          arg (ValueParam (Held _ _), x) = term ctx env x
          arg _ = pure (Erased loc)

      isImplementation : TT vars -> Bool
      isImplementation (Local _ _ idx _) = case getAt idx env of
        Just (Static _) => True
        _ => False
      isImplementation _ = False

      argValue : TT vars -> Maybe ArgValue
      argValue x = Just (MkArgValue (closeNormalise afc env x) (solved (closeWritten afc env x)) (isImplementation x))

      argValues : List (TT vars) -> ArgValues
      argValues = map argValue

      finish : Loc -> List PKind -> List (Term a) ->
               ({0 b : Type} -> List (Term b) -> Term b) -> List (TT vars) -> Core (Term a)
      finish loc kinds given mk extra = do
        let missing = drop (length given) kinds
        if null missing
           then applyAll loc (mk given) extra
           else do
             when (any isStatic missing) $
               reject afc ctx.owner StaticArgument "a partially applied type parameter or implementation"
             etaExpand afc loc (map runtimeBinder missing) mk given
        where
          isStatic : PKind -> Bool
          isStatic (ValueParam _) = False
          isStatic _ = True

      call : FC -> Loc -> Name -> Nat -> ClosedTerm -> List (TT vars) -> Core (Term a)
      call fc loc name arity ty xs = do
        (kinds, _) <- classify fc ctx.owner arity ty (argValues (take arity xs))
        let statics = map (\k => case k of
                                    TypeParam t => Just t
                                    DictParam t => Just t
                                    _ => Nothing) kinds
        inst <- request fc ctx.owner name statics
        given <- arguments loc kinds (take arity xs)
        finish loc kinds given (Call loc inst) (drop arity xs)

      -- A call of a monomorphic library function the registry names, on
      -- runtime arguments: saturated, and the ones past its arity applied.
      libraryCall : FC -> Loc -> QName -> Core ({0 b : Type} -> List (Term b) -> Term b)
      libraryCall fc loc q = do
        def <- lookupDef fc ctx.owner (toName q)
        let PMDef _ params _ _ _ = definition def
          | _ => reject fc (show q) HookShape "the registry names a library function that is not a definition"
        let arity = length params
        (kinds, _) <- classify fc ctx.owner arity (type def) (replicate arity Nothing)
        let True = all isRuntime kinds
          | False => reject fc (show q) HookShape "the registry names a library function with compile-time arguments"
        inst <- request fc ctx.owner (fullname def) (replicate arity Nothing)
        pure (\ns => let (now, rest) = splitAt arity ns in
                     foldl (App loc) (Call loc inst now) rest)
        where
          isRuntime : PKind -> Bool
          isRuntime (ValueParam _) = True
          isRuntime _ = False

      -- A function on naturals, as the primitives it means (the registry's
      -- `NatOperation`); partially applied, it is eta-expanded like a call.
      natOperation : FC -> Loc -> NatMeaning -> Nat -> ClosedTerm -> List (TT vars) -> Core (Term a)
      natOperation fc loc m arity ty xs = do
        (kinds, _) <- classify fc ctx.owner arity ty (argValues (take arity xs))
        given <- arguments loc kinds (take arity xs)
        case m of
          Primitive p => finish loc kinds given (PrimApp loc p) (drop arity xs)
          Clamped p =>
            finish loc kinds given
                   (\ns => PrimApp loc NatFromBig [PrimApp loc p (map (\n => PrimApp loc NatToBig [n]) ns)])
                   (drop arity xs)
          Tested c q => do
            toBool <- libraryCall fc loc q
            finish loc kinds given (\ns => toBool [PrimApp loc (NatCompare c) ns]) (drop arity xs)
          OnIntegers q => do
            f <- libraryCall fc loc q
            finish loc kinds given (\ns => f (map (\n => PrimApp loc NatToBig [n]) ns)) (drop arity xs)

      -- A constructor of a `Nat`-like type is a natural: zero is 0, a
      -- successor adds 1.
      natConstructor : FC -> Loc -> NatRole -> List PKind -> List (Term a) ->
                       List (TT vars) -> Core (Term a)
      natConstructor fc loc Zero kinds given extra =
        finish loc kinds given (\_ => Literal loc (LNat 0)) extra
      natConstructor fc loc Succ kinds given extra = do
        let Just i = succArg kinds
          | Nothing => internal fc "a successor without one runtime argument"
        finish loc kinds given
               (\xs => PrimApp loc NatAdd (Data.List.take 1 (drop i xs) ++ [Literal loc (LNat 1)])) extra

      constructor : FC -> Loc -> GlobalDef -> Nat -> List (TT vars) -> Core (Term a)
      constructor fc loc def arity xs = do
        (kinds, resTy) <- classify fc ctx.owner arity (type def) (argValues (take arity xs))
        given <- arguments loc kinds (take arity xs)
        case natRole def of
          Just role => natConstructor fc loc role kinds given (drop arity xs)
          Nothing => do
            DataT inst <- coreType fc ctx.owner ValueType !(normaliseClosed resTy)
              | _ => internal fc "a constructor of a type that is not data"
            -- The data type's parameters are not fields, wherever they are
            -- among the constructor's arguments; a type argument that is
            -- not one is an erased field.
            st <- get TState
            let cid = MkConId inst (shortName (fullname def))
            let layout = maybe [] (.layout) (lookup cid st.cons)
            finish loc (fieldsOnly layout kinds) (fieldsOnly layout given) (ConApp loc cid) (drop arity xs)

      primitive : FC -> Loc -> Name -> Nat -> PrimFn ar -> List (TT vars) -> Core (Term a)
      primitive fc loc name arity op xs = case op of
        BelieveMe => reject fc ctx.owner EscapeHatch "believe_me"
        Crash => reject fc ctx.owner EscapeHatch "idris_crash"
        Neg DoubleType => supported
        Neg IntegerType => supported
        Neg _ => reject fc ctx.owner Primitive "negate"
        ShiftL _ => reject fc ctx.owner Primitive "shift left"
        ShiftR _ => reject fc ctx.owner Primitive "shift right"
        _ => supported
        where
          supported : Core (Term a)
          supported = case primOp op of
            Nothing => reject fc ctx.owner Primitive ("primitive " ++ show name)
            Just p => do
              args' <- traverse (term ctx env) (take arity xs)
              let kinds = map (ValueParam . Held Many) (primArgs p)
              finish loc kinds args' (PrimApp loc p) (drop arity xs)

      ioCall : FC -> Loc -> Nat -> IOOp -> ClosedTerm -> List (TT vars) -> Core (Term a)
      ioCall fc loc arity op ty xs = do
        (kinds, resTy) <- classify fc ctx.owner arity ty []
        DataT res <- coreType fc ctx.owner ValueType !(normaliseClosed resTy)
          | _ => internal fc "an IO primitive with an unexpected type"
        given <- arguments loc kinds (take arity xs)
        finish loc kinds given (\ys => Effect loc op ys res) (drop arity xs)

      -- An array primitive is polymorphic in its element, so its one type
      -- argument fixes the operation's element type, and only its runtime
      -- arguments are the operation's operands: those parameters, the
      -- element type, the arguments given for them, and the result type.
      arrayOperands : FC -> Loc -> Nat -> ClosedTerm -> List (TT vars) ->
                      Core (List PKind, Ty, List (Term a), ClosedTerm)
      arrayOperands fc loc arity ty xs = do
        (kinds, resTy) <- classify fc ctx.owner arity ty (argValues (take arity xs))
        Just element <- pure (elementOf kinds)
          | Nothing => internal fc "an array primitive without its element type"
        el <- coreType fc ctx.owner ValueType element
        given <- arguments loc kinds (take arity xs)
        pure (filter isRuntime kinds, el, runtimeOnly kinds given, resTy)
        where
          elementOf : List PKind -> Maybe ClosedTerm
          elementOf (TypeParam t :: _) = Just t
          elementOf (_ :: ks) = elementOf ks
          elementOf [] = Nothing

          isRuntime : PKind -> Bool
          isRuntime (ValueParam (Held _ _)) = True
          isRuntime _ = False

          runtimeOnly : List PKind -> List (Term a) -> List (Term a)
          runtimeOnly (k :: ks) (g :: gs) = if isRuntime k then g :: runtimeOnly ks gs else runtimeOnly ks gs
          runtimeOnly _ _ = []

      -- An array operation: IO, in the world's order.
      arrayCall : FC -> Loc -> Nat -> ArrayOp -> ClosedTerm -> List (TT vars) -> Core (Term a)
      arrayCall fc loc arity op ty xs = do
        (kinds, el, given, resTy) <- arrayOperands fc loc arity ty xs
        DataT res <- coreType fc ctx.owner ValueType !(normaliseClosed resTy)
          | _ => internal fc "an array primitive with an unexpected type"
        finish loc kinds given (\ys => Effect loc (Array op el) ys res) (drop arity xs)

      -- The length of an array: a primitive of the array alone.
      arraySize : FC -> Loc -> Nat -> ClosedTerm -> List (TT vars) -> Core (Term a)
      arraySize fc loc arity ty xs = do
        (kinds, el, given, _) <- arrayOperands fc loc arity ty xs
        finish loc kinds given (PrimApp loc (ArrayLength el)) (drop arity xs)
  application ctx env afc fn args = case headStep fn args of
    Just (h, as) => let (h', as') = spine h [] in application ctx env afc h' (as' ++ as)
    Nothing => do
      loc <- toLoc (bestFC ctx afc)
      f <- term ctx env fn
      applyAll loc f args
    where
      ||| An implementation applied to arguments is used as written; its type
      ||| arguments are substituted, so its body is translated at the types of
      ||| this use.
      staticArg : TT vars -> Bool
      staticArg (Local _ _ idx _) = case getAt idx env of
        Just (Static _) => True
        _ => False
      staticArg _ = False

      headStep : TT vars -> List (TT vars) -> Maybe (TT vars, List (TT vars))
      headStep (Local _ _ idx _) as = case getAt idx env of
        Just (Static t) => Just (embedClosed t, as)
        _ => Nothing
      -- A lambda over an implementation (`\@{m} => ...`, as a dictionary's
      -- polymorphic method field is written) takes it as written, like a
      -- type: it is a compile-time value.
      headStep (Bind _ _ (Lam _ rig pinfo _) sc) (a :: as) =
        if isErased rig || isAuto pinfo || staticArg a then Just (subst a sc, as) else Nothing
      headStep _ _ = Nothing

      applyAll : Loc -> Term a -> List (TT vars) -> Core (Term a)
      applyAll loc f [] = pure f
      applyAll loc f (x :: xs) = applyAll loc (App loc f !(term ctx env x)) xs
