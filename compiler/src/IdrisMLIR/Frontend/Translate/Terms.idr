||| Terms: a TT term in scope, with an environment saying what each of its
||| variables stands for, as a Core term. A call requests the instance it
||| calls.
module IdrisMLIR.Frontend.Translate.Terms

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Dialect.Idr
import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Dictionaries
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Hooks
import IdrisMLIR.Frontend.Translate.Instances
import IdrisMLIR.Frontend.Translate.Primitives
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Registry
import IdrisMLIR.Registry.Libraries
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

||| The number of arguments a type takes, as its binders say.
binders : TT vars -> Nat
binders (Bind _ _ (Pi {}) sc) = S (binders sc)
binders _ = Z

||| Eta-expands a known head applied to too few arguments:
||| `\x.. => head(args ++ xs)`.
etaExpand : {0 a : Type} -> Loc -> List Binder -> ({0 b : Type} -> List (Term b) -> Term b) -> List (Term a) -> Term a
etaExpand loc [] mk given = mk given
etaExpand loc (b :: rest) mk given =
  Lam loc b (etaExpand loc rest mk (map (map Free) given ++ [argument b]))
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
    runtime (i, ValueParam (Held _ _) _) = Just i
    runtime _ = Nothing

||| The term of an array loop's op over its runtime operands (`Hook.ArrayLoop`),
||| at the types its call fixes: a generated array of `n` elements, the
||| function at the index (`Bound 0`), and at 0 as the fill base's
||| primitive needs, which the library's definition applies first too; a
||| fold of `arr` from `z`, the function at the accumulator, the index and
||| the element (`Bound 0`, `Bound 2`, `Bound 1`). The operands are as
||| `finish` gives them, one per runtime parameter, the world last.
loopTerm : Loc -> IdrRegionPrim -> List Ty -> DataId -> {0 b : Type} -> List (Term b) -> Term b
loopTerm loc ArrayGenerate tys res [n, f, w] =
  Region {k = regionArity ArrayGenerate} loc ArrayGenerate tys
         [n, App loc f (Literal loc (LInt IdrisInt 0)), w]
         (App loc (map Free f) (Var loc (Bound FZ))) res
loopTerm loc ArrayFold tys res [arr, z, f, w] =
  Region {k = regionArity ArrayFold} loc ArrayFold tys [arr, z, w]
         (App loc (App loc (App loc (map Free f) (Var loc (Bound FZ))) (Var loc (Bound (FS (FS FZ)))))
              (Var loc (Bound (FS FZ)))) res
loopTerm loc _ _ _ _ = Unreachable loc

mutual
  export
  term : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
         Ctx -> List (VarInfo a) -> TT vars -> Core (Term a)
  term ctx env (Local fc _ idx _) = do
    loc <- toLoc (bestFC ctx fc)
    case getAt idx env of
      Just (Runtime x _) => pure (Var loc x)
      Just (Shaped x _ _) => pure (Var loc x)
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
    pure (Lam loc b body)
  term ctx env (TDelay fc _ _ arg) = suspend ctx env fc arg
  term ctx env (TForce fc _ arg) = Resume <$> toLoc (bestFC ctx fc) <*> term ctx env arg
  term ctx env (TDelayed fc _ _) = Erased <$> toLoc (bestFC ctx fc)
  term ctx env (Meta fc n _ args) = do
    Just tm <- solution (bestFC ctx fc) n args
      | Nothing => reject (bestFC ctx fc) ctx.owner EscapeHatch ("the hole " ++ show n)
    term ctx env tm
  term ctx env (As fc _ _ pat) = term ctx env pat
  term ctx env tm@(App fc _ _) = let (fn, args) = spine tm [] in application ctx env fc fn args
  term ctx env tm@(Ref fc _ _) = application ctx env fc tm []
  term ctx env (Bind fc _ _ _) = internal (bestFC ctx fc) "a binder in a runtime position"

  suspend : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
            Ctx -> List (VarInfo a) -> FC -> TT vars -> Core (Term a)
  suspend ctx env fc arg = do
    loc <- toLoc (bestFC ctx fc)
    body <- term ctx env arg
    pure (Suspend loc body)

  application : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
                Ctx -> List (VarInfo a) -> FC -> TT vars -> List (TT vars) -> Core (Term a)
  application ctx env afc (Ref rfc nt name) args = do
    let fc = bestFC ctx rfc
    loc <- toLoc fc
    def <- lookupDef fc ctx.owner name
    let full = fullname def
    -- What a hook lowers a call of this definition to stands for it, the
    -- registry's entry it applied.
    let lowered = Just (shown (show full))
    case definition def of
      -- A hook for the identity on the one runtime argument, the last its
      -- type takes (`replace`, `rewrite__impl`, which `rewrite` elaborates
      -- to, and the pointer casts); the rest are proofs and types. By the
      -- type, not the clause: `prim__castPtr = believe_me` binds only its
      -- erased type.
      PMDef _ params _ _ _ => case deprecatedOf (hooksOf full) of
        Just msg => reject fc ctx.owner Deprecated msg
        Nothing => case (natOperationOf (hooksOf full), builderOf (hooksOf full),
                         arrayLoopOf (hooksOf full)) of
          (Just m, _, _) => natOperation fc loc lowered m (length params) (type def) args
          (_, Just p, _) => builderCall fc loc lowered (length params) p (type def) args
          (_, _, Just loop) => arrayLoop fc loc loop full (length params) (type def) args
          _ =>
            if identityOnLast (hooksOf full) && length args >= binders (type def)
               then do
                 let (now, rest) = splitAt (binders (type def)) args
                 v <- maybe (pure (Erased loc)) (term ctx env) (last' now)
                 applyAll loc v rest
               else do
                 exiting <- exitCast def
                 if exiting
                    then exitAction fc loc (length params) (type def) args
                    else call fc loc full Nothing (length params) (type def) args
      DCon tag arity _ => constructor fc loc def arity args
      TCon {} => pure (Erased loc)
      Builtin {arity} op => primitive fc loc full arity op (type def) args
      -- An IO primitive the registry lists, a `%foreign` one by
      -- its spec and an `%extern` one by its name.
      ForeignDef arity specs => case foreignHookOf full specs of
        Just (Right (IOCall p lits)) => ioCall fc loc lowered arity p lits (type def) args
        Just (Right ArraySize) => arraySize fc loc lowered arity (type def) args
        Just (Right (PrimCall p)) => primCall fc loc lowered arity p (type def) args
        Just (Right (Handle h)) => applyAll loc (Literal loc h) args
        Just (Right (Builds p)) => builderCall fc loc lowered arity p (type def) args
        Just (Right (Alias q)) => aliasCall fc loc lowered q args
        Just (Right (Deprecated msg)) => reject fc ctx.owner Deprecated msg
        Just (Left wrong) => reject fc (show full) HookShape wrong
        _ => reject fc ctx.owner EscapeHatch ("foreign function " ++ show full)
      ExternDef arity => case (ioCallOf (hooksOf full), arrayCallOf (hooksOf full),
                              systemFactOf (hooksOf full)) of
        (Just (p, lits), _, _) => ioCall fc loc lowered arity p lits (type def) args
        (_, Just op, _) => arrayCall fc loc arity op (type def) args
        (_, _, Just TargetOs) => applyAll loc (SystemOs loc) args
        (_, _, Just BackendName) => applyAll loc (Literal loc (LStr codegenName)) args
        _ => reject fc ctx.owner EscapeHatch ("extern function " ++ show full)
      Hole {} => reject fc ctx.owner EscapeHatch ("the hole " ++ show full)
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
          arg (ValueParam (Held _ _) _, x) = term ctx env x
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
             pure (etaExpand loc (map runtimeBinder missing) mk given)
        where
          isStatic : PKind -> Bool
          isStatic (ValueParam _ _) = False
          isStatic _ = True

      call : FC -> Loc -> Name -> Maybe Shown -> Nat -> ClosedTerm -> List (TT vars) -> Core (Term a)
      call fc loc name lowered arity ty xs = do
        (kinds, _) <- classify fc ctx.owner arity ty (argValues (take arity xs))
        inst <- request fc ctx.owner name kinds
        given <- arguments loc kinds (take arity xs)
        finish loc kinds given (Call loc inst lowered) (drop arity xs)

      -- Is the definition being translated one whose calls end the program
      -- (`Hook.Exits`, `System.exitWith`)? Its `believe_me` gives the
      -- exit's `PrimIO ()` any result, which is sound only because that
      -- action does not return; anywhere else `believe_me` stays an escape
      -- hatch.
      exiting : Core Bool
      exiting = do
        st <- get TState
        let Just r = st.current >>= \i => lookup i st.requesters
          | Nothing => pure False
        owner <- lookupDef afc ctx.owner r.name
        pure (isJust (exitOf (hooksOf (fullname owner))))

      -- Is a definition `believe_me`, whose body is the `BelieveMe`
      -- primitive?
      believeMe : GlobalDef -> Core Bool
      believeMe def = do
        let PMDef _ _ (STerm _ tm) _ _ = definition def
          | _ => pure False
        let (Ref _ _ n, _) = spine tm []
          | _ => pure False
        defs <- get Ctxt
        Just prim <- lookupCtxtExact n (gamma defs)
          | Nothing => pure False
        let Builtin BelieveMe = definition prim
          | _ => pure False
        pure True

      exitCast : GlobalDef -> Core Bool
      exitCast def = do
        wrapper <- believeMe def
        if wrapper then exiting else pure False

      -- The exit's `believe_me`, on the action: the action applied to the
      -- world, after which nothing runs.
      exitAction : FC -> Loc -> Nat -> ClosedTerm -> List (TT vars) -> Core (Term a)
      exitAction fc loc arity ty xs = do
        (kinds, _) <- classify fc ctx.owner arity ty (argValues (take arity xs))
        given <- arguments loc kinds (take arity xs)
        finish loc kinds given exits (drop arity xs)
        where
          exits : {0 b : Type} -> List (Term b) -> Term b
          exits ns = case last' ns of
            Just act => Lam loc (Held Once WorldT)
                          (Let loc Many (App loc (map Free act) (Var loc (Bound FZ))) (Unreachable loc))
            Nothing => Unreachable loc

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
        inst <- request fc ctx.owner (fullname def) kinds
        pure (\ns => let (now, rest) = splitAt arity ns in
                     foldl (App loc) (Call loc inst Nothing now) rest)
        where
          isRuntime : PKind -> Bool
          isRuntime (ValueParam _ _) = True
          isRuntime _ = False

      -- A function on naturals, as the primitives it means (the registry's
      -- `NatOperation`); partially applied, it is eta-expanded like a call.
      natOperation : FC -> Loc -> Maybe Shown -> NatMeaning -> Nat -> ClosedTerm -> List (TT vars) -> Core (Term a)
      natOperation fc loc lowered m arity ty xs = do
        (kinds, _) <- classify fc ctx.owner arity ty (argValues (take arity xs))
        given <- arguments loc kinds (take arity xs)
        case m of
          Primitive p => finish loc kinds given (PrimApp loc p lowered) (drop arity xs)
          Clamped p =>
            finish loc kinds given
                   (\ns => PrimApp loc (Op NatFromBig) lowered
                             [PrimApp loc p lowered (map (\n => PrimApp loc (Op NatToBig) lowered [n]) ns)])
                   (drop arity xs)
          Tested c q => do
            toBool <- libraryCall fc loc q
            finish loc kinds given (\ns => toBool [PrimApp loc (NatCompare c) lowered ns]) (drop arity xs)
          OnIntegers q => do
            f <- libraryCall fc loc q
            finish loc kinds given (\ns => f (map (\n => PrimApp loc (Op NatToBig) lowered [n]) ns)) (drop arity xs)

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
               (\xs => PrimApp loc (Op BigAdd) Nothing (Data.List.take 1 (drop i xs) ++ [Literal loc (LNat 1)])) extra

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
            let Just info = lookup cid st.cons
              | Nothing => internal fc ("the constructor " ++ cid.name ++ " of " ++ inst.name ++ " is not registered")
            let fieldKinds = fieldsOnly info.layout kinds
            -- An implementation given to a dictionary field is the one the
            -- field holds, for the whole program.
            for_ (zip [0 .. length fieldKinds] fieldKinds) $ \(i, kind) =>
              case (Data.List.lookup i info.dicts, kind) of
                (Just ty, DictParam t) => recordDictionary fc ctx.owner cid ty i t
                (Just _, _) => internal fc ("a runtime value for a dictionary field of " ++ cid.name)
                (Nothing, DictParam _) => internal fc ("an implementation for a runtime field of " ++ cid.name)
                _ => pure ()
            finish loc fieldKinds (fieldsOnly info.layout given) (ConApp loc cid) (drop arity xs)

      primitive : FC -> Loc -> Name -> Nat -> PrimFn ar -> ClosedTerm -> List (TT vars) -> Core (Term a)
      primitive fc loc name arity op ty xs = case op of
        BelieveMe => do
          exit <- exiting
          if exit then exitAction fc loc arity ty xs
                  else reject fc ctx.owner EscapeHatch "believe_me"
        -- A user's crash is rejected. A trusted library's is the string it
        -- is given: the program ends with that string and does not return.
        Crash => do
          here <- toLoc ctx.fc
          if covers Trusted here.origin
            then case last' (take arity xs) of
              Just m => do
                s <- term ctx env m
                pure (PrimApp loc (Op CrashStr) Nothing [s])
              Nothing => reject fc ctx.owner EscapeHatch "idris_crash"
            else reject fc ctx.owner EscapeHatch "idris_crash"
        Neg DoubleType => supported
        Neg IntegerType => supported
        Neg _ => reject fc ctx.owner Primitive "negate"
        _ => supported
        where
          -- The primitive on the arguments its type takes, in the order its
          -- op takes them.
          supported : Core (Term a)
          supported = case primOp op of
            Nothing => reject fc ctx.owner Primitive ("primitive " ++ show name)
            Just p => do
              (kinds, _) <- classify fc ctx.owner arity ty []
              given <- arguments loc kinds (take arity xs)
              finish loc kinds given (PrimApp loc p Nothing . opOrder op) (drop arity xs)

      -- A string built once from a list: the primitive of the one
      -- parameter, a list, which it takes at the list's own instance.
      builderCall : FC -> Loc -> Maybe Shown -> Nat -> IdrPrim -> ClosedTerm -> List (TT vars) -> Core (Term a)
      builderCall fc loc lowered arity p ty xs = do
        (kinds, _) <- classify fc ctx.owner arity ty []
        let [ValueParam (Held _ (DataT _)) _] = kinds
          | _ => internal fc "a string built from something other than a list"
        given <- arguments loc kinds (take arity xs)
        finish loc kinds given (PrimApp loc (Op p) lowered) (drop arity xs)

      -- A call of the library function a foreign definition stands for.
      aliasCall : FC -> Loc -> Maybe Shown -> QName -> List (TT vars) -> Core (Term a)
      aliasCall fc loc lowered q xs = do
        target <- lookupDef fc ctx.owner (toName q)
        let PMDef _ params _ _ _ = definition target
          | _ => internal fc (show q ++ " is not a function to stand for")
        call fc loc (fullname target) lowered (length params) (type target) xs

      -- A primitive the registry lists, on the call's arguments and then
      -- the literals the call does not supply (a new buffer's zero byte,
      -- `array.new`'s fill). One that performs IO is an effect, whose
      -- world stays its last operand, at the type its call fixes: a buffer
      -- word's, the word a load gives (its result's) or a store takes (its
      -- argument before the world), or an array's element, of the array
      -- among its operands or in its result. One that does not has no
      -- world and no `IORes` in its type, and is pure.
      ioCall : FC -> Loc -> Maybe Shown -> Nat -> IdrPrim -> List Lit -> ClosedTerm -> List (TT vars) ->
               Core (Term a)
      ioCall fc loc lowered arity p lits ty xs = do
        (kinds, resTy) <- classify fc ctx.owner arity ty []
        if primPerformsIO p
           then do
             result <- normaliseClosed resTy
             DataT res <- coreType fc ctx.owner ValueType result
               | _ => internal fc "an IO primitive with an unexpected type"
             tys <- wordOf p kinds result
             given <- arguments loc kinds (take arity xs)
             finish loc kinds given (\ys => Effect loc p tys (beforeWorld ys) res) (drop arity xs)
           else do
             given <- arguments loc kinds (take arity xs)
             finish loc kinds given (\ys => PrimApp loc (Op p) lowered (ys ++ map (Literal loc) lits))
                    (drop arity xs)
        where
          beforeWorld : {0 b : Type} -> List (Term b) -> List (Term b)
          beforeWorld ys = case reverse ys of
            w :: own => reverse own ++ map (Literal loc) lits ++ [w]
            [] => map (Literal loc) lits

          -- What an IO primitive's result holds besides the world.
          held : ClosedTerm -> Core (List Ty)
          held result = case spine result [] of
            (_, [t]) => (\w => [w]) <$> coreType fc ctx.owner ValueType t
            _ => pure []

          operandType : PKind -> Maybe Ty
          operandType (ValueParam (Held _ t) _) = Just t
          operandType _ = Nothing

          arrayElement : Ty -> Maybe Ty
          arrayElement (ArrayT _ e) = Just e
          arrayElement _ = Nothing

          element : List PKind -> ClosedTerm -> Core (List Ty)
          element kinds result = do
            outs <- held result
            case mapMaybe arrayElement (mapMaybe operandType kinds ++ outs) of
              e :: _ => pure [e]
              [] => internal fc "an array primitive without an array"

          wordOf : IdrPrim -> List PKind -> ClosedTerm -> Core (List Ty)
          wordOf BufferLoad _ result = do
            [t] <- held result
              | _ => internal fc "a buffer load whose result holds no one word"
            pure [t]
          wordOf BufferStore kinds _ = case reverse kinds of
            (_ :: ValueParam (Held _ t) _ :: _) => pure [t]
            _ => internal fc "a buffer store without the word it stores"
          wordOf ArrayNew kinds result = element kinds result
          wordOf ArrayGet kinds result = element kinds result
          wordOf ArraySet kinds result = element kinds result
          wordOf _ _ _ = pure []

      isRuntime : PKind -> Bool
      isRuntime (ValueParam (Held _ _) _) = True
      isRuntime _ = False

      runtimeOnly : List PKind -> List (Term a) -> List (Term a)
      runtimeOnly (k :: ks) (g :: gs) = if isRuntime k then g :: runtimeOnly ks gs else runtimeOnly ks gs
      runtimeOnly _ _ = []

      -- A function over arrays is polymorphic in its element (and a fold
      -- in its accumulator), so its type arguments fix the operation's
      -- types, and only its runtime arguments are the operation's
      -- operands: those parameters, the instances of the type parameters
      -- in order, the arguments given for them, and the result type.
      arrayOperands : FC -> Loc -> Nat -> ClosedTerm -> List (TT vars) ->
                      Core (List PKind, List Ty, List (Term a), ClosedTerm)
      arrayOperands fc loc arity ty xs = do
        (kinds, resTy) <- classify fc ctx.owner arity ty (argValues (take arity xs))
        tys <- traverse (coreType fc ctx.owner ValueType) (typeParams kinds)
        given <- arguments loc kinds (take arity xs)
        pure (filter isRuntime kinds, tys, runtimeOnly kinds given, resTy)
        where
          typeParams : List PKind -> List ClosedTerm
          typeParams (TypeParam t :: ks) = t :: typeParams ks
          typeParams (_ :: ks) = typeParams ks
          typeParams [] = []

      -- An array operation: IO, in the world's order.
      arrayCall : FC -> Loc -> Nat -> IdrPrim -> ClosedTerm -> List (TT vars) -> Core (Term a)
      arrayCall fc loc arity p ty xs = do
        (kinds, [el], given, resTy) <- arrayOperands fc loc arity ty xs
          | _ => internal fc "an array primitive without its one element type"
        DataT res <- coreType fc ctx.owner ValueType !(normaliseClosed resTy)
          | _ => internal fc "an array primitive with an unexpected type"
        finish loc kinds given (\ys => Effect loc p [el] ys res) (drop arity xs)

      -- A library loop over an array's index space (the registry's
      -- `ArrayLoop`): the op of that loop, its body applying the function,
      -- when the element and a fold's accumulator are machine words, which
      -- a memref holds and a vector lane computes; at any other instance a
      -- call of the library's definition, the same loop in Idris. IO, in
      -- the world's order, like the array primitives.
      arrayLoop : FC -> Loc -> IdrRegionPrim -> Name -> Nat -> ClosedTerm -> List (TT vars) -> Core (Term a)
      arrayLoop fc loc loop name arity ty xs = do
        (kinds, tys, given, resTy) <- arrayOperands fc loc arity ty xs
        DataT res <- coreType fc ctx.owner ValueType !(normaliseClosed resTy)
          | _ => internal fc "an array loop with an unexpected type"
        if all word tys
           then finish loc kinds given (loopTerm loc loop tys res) (drop arity xs)
           else call fc loc name Nothing arity ty xs
        where
          word : Ty -> Bool
          word (IntT _) = True
          word CharT = True
          word DoubleT = True
          word _ = False

      -- The length of an array, at the element its type argument fixes.
      arraySize : FC -> Loc -> Maybe Shown -> Nat -> ClosedTerm -> List (TT vars) -> Core (Term a)
      arraySize fc loc lowered arity ty xs = do
        (kinds, [el], given, _) <- arrayOperands fc loc arity ty xs
          | _ => internal fc "an array's length without its one element type"
        finish loc kinds given (PrimApp loc (ArrayLength el) lowered) (drop arity xs)

      -- A pure primitive on the call's runtime arguments, which its type
      -- fixes: a buffer's length, an index checked against a bound.
      primCall : FC -> Loc -> Maybe Shown -> Nat -> Prim -> ClosedTerm -> List (TT vars) -> Core (Term a)
      primCall fc loc lowered arity p ty xs = do
        (kinds, _) <- classify fc ctx.owner arity ty []
        given <- arguments loc kinds (take arity xs)
        finish loc kinds given (PrimApp loc p lowered) (drop arity xs)
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
