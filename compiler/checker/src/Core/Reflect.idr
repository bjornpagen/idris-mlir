-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.Reflect

import Data.List1

import Core.Context
import Core.Env
import Core.Normalise
import Core.Value

import Libraries.Data.WithDefault

%default covering


public export
interface Reify a where
  reify : {auto c : Ref Ctxt Defs} ->
          {vars : _} ->
          Defs -> NF vars -> Core a

public export
interface Reflect a where
  reflect : {vars : _} ->
            FC -> Defs -> (onLHS : Bool) ->
            Env Term vars -> a -> Core (Term vars)

export
getCon : {vars : _} ->
         FC -> Defs -> Name -> Core (Term vars)
getCon fc defs n
    = case !(lookupDefExact n (gamma defs)) of
           Just (DCon t a _) => resolved (gamma defs) (Ref fc (DataCon t a) n)
           Just (TCon a _ _ _ _ _ _) => resolved (gamma defs) (Ref fc (TyCon a) n)
           Just _ => resolved (gamma defs) (Ref fc Func n)
           _ => throw (UndefinedName fc n)

export
appCon : {vars : _} ->
         FC -> Defs -> Name -> List (Term vars) -> Core (Term vars)
appCon fc defs n args
    = do fn <- getCon fc defs n
         resolved (gamma defs) (apply fc fn args)

||| Which known identifier names a value's constructor, its namespace
||| dropped: base's reflected types are told apart by their constructors'
||| names, and each name a reifier expects is one the compiler spells.
export
knownCon : Defs -> Name -> Core (Maybe Known)
knownCon defs n = pure (knownRoot (dropAllNS !(full (gamma defs) n)))

export
preludetypes : Known -> Name
preludetypes k = NS typesNS (knownUN k)

export
basics : Known -> Name
basics k = NS basicsNS (knownUN k)

export
builtin : Known -> Name
builtin k = NS builtinNS (knownUN k)

export
primio : Known -> Name
primio k = NS primIONS (knownUN k)

export
reflection : Known -> Name
reflection k = NS reflectionNS (knownUN k)

export
reflectiontt : Known -> Name
reflectiontt k = NS reflectionTTNS (knownUN k)

export
reflectionttimp : Known -> Name
reflectionttimp k = NS reflectionTTImpNS (knownUN k)

export
cantReify : Ref Ctxt Defs => {vars : _} -> NF vars -> String -> Core a
cantReify val ty = do
  logNF "reflection.reify" 10 "Can't reify as \{ty}" (mkEnv emptyFC vars) val
  throw (GenericMsg (getLoc val) ("Can't reify as " ++ ty))

export
cantReflect : FC -> String -> Core a
cantReflect fc ty
    = throw (GenericMsg fc ("Can't reflect as " ++ ty))

export
Reify () where
  reify defs _ = pure ()

export
Reflect () where
  reflect fc defs lhs env _ = getCon fc defs (builtin KMkUnit)

export
Reify String where
  reify defs (NPrimVal _ (Str str)) = pure str
  reify defs val = cantReify val "String"

export
Reflect String where
  reflect fc defs lhs env x = pure (PrimVal fc (Str x))

||| Base spells every identifier of a reflected name as a `String`: the text
||| enters the session's table of identifiers where a script hands it to the
||| compiler, and an identifier goes back to a script as its text.
export
Reify Ident where
  reify defs val = intern !(the (Core String) (reify defs val))

export
Reflect Ident where
  reflect fc defs lhs env i = reflect fc defs lhs env i.text

export
Reify Int where
  reify defs (NPrimVal _ (I v)) = pure v
  reify defs val = cantReify val "Int"

export
Reflect Int where
  reflect fc defs lhs env x = pure (PrimVal fc (I x))

export
Reify Int8 where
  reify defs (NPrimVal _ (I8 v)) = pure v
  reify defs val = cantReify val "Int8"

export
Reflect Int8 where
  reflect fc defs lhs env x = pure (PrimVal fc (I8 x))

export
Reify Int16 where
  reify defs (NPrimVal _ (I16 v)) = pure v
  reify defs val = cantReify val "Int16"

export
Reflect Int16 where
  reflect fc defs lhs env x = pure (PrimVal fc (I16 x))

export
Reify Int32 where
  reify defs (NPrimVal _ (I32 v)) = pure v
  reify defs val = cantReify val "Int32"

export
Reflect Int32 where
  reflect fc defs lhs env x = pure (PrimVal fc (I32 x))

export
Reify Int64 where
  reify defs (NPrimVal _ (I64 v)) = pure v
  reify defs val = cantReify val "Int64"

export
Reflect Int64 where
  reflect fc defs lhs env x = pure (PrimVal fc (I64 x))

export
Reify Bits8 where
  reify defs (NPrimVal _ (B8 v)) = pure v
  reify defs val = cantReify val "Bits8"

export
Reflect Bits8 where
  reflect fc defs lhs env x = pure (PrimVal fc (B8 x))

export
Reify Bits16 where
  reify defs (NPrimVal _ (B16 v)) = pure v
  reify defs val = cantReify val "Bits16"

export
Reflect Bits16 where
  reflect fc defs lhs env x = pure (PrimVal fc (B16 x))

export
Reify Bits32 where
  reify defs (NPrimVal _ (B32 v)) = pure v
  reify defs val = cantReify val "Bits32"

export
Reflect Bits32 where
  reflect fc defs lhs env x = pure (PrimVal fc (B32 x))

export
Reify Bits64 where
  reify defs (NPrimVal _ (B64 v)) = pure v
  reify defs val = cantReify val "Bits64"

export
Reflect Bits64 where
  reflect fc defs lhs env x = pure (PrimVal fc (B64 x))

export
Reify Integer where
  reify defs (NPrimVal _ (BI v)) = pure v
  reify defs val = cantReify val "Integer"

export
Reflect Integer where
  reflect fc defs lhs env x = pure (PrimVal fc (BI x))

export
Reify Char where
  reify defs (NPrimVal _ (Ch v)) = pure v
  reify defs val = cantReify val "Char"

export
Reflect Char where
  reflect fc defs lhs env x = pure (PrimVal fc (Ch x))

export
Reify Double where
  reify defs (NPrimVal _ (Db v)) = pure v
  reify defs val = cantReify val "Double"

export
Reflect Double where
  reflect fc defs lhs env x = pure (PrimVal fc (Db x))

export
Reify Bool where
  reify defs val@(NDCon _ n _ _ _)
      = case !(knownCon defs n) of
            Just KTrue => pure True
            Just KFalse => pure False
            _ => cantReify val "Bool"
  reify defs val = cantReify val "Bool"

export
Reflect Bool where
  reflect fc defs lhs env True = getCon fc defs (basics KTrue)
  reflect fc defs lhs env False = getCon fc defs (basics KFalse)

export
Reify Nat where
  reify defs val@(NDCon _ n _ _ args)
      = case (!(knownCon defs n), args) of
             (Just KZ, _) => pure Z
             (Just KS, [(_, k)])
                 => do k' <- reify defs !(evalClosure defs k)
                       pure (S k')
             _ => cantReify val "Nat"
  reify defs val = cantReify val "Nat"

export
Reflect Nat where
  reflect fc defs lhs env Z = getCon fc defs (preludetypes KZ)
  reflect fc defs lhs env (S k)
      = do k' <- reflect fc defs lhs env k
           appCon fc defs (preludetypes KS) [k']

export
Reify a => Reify (List a) where
  reify defs val@(NDCon _ n _ _ args)
      = case (!(knownCon defs n), args) of
             (Just KNil, _) => pure []
             (Just KCons, [_, (_, x), (_, xs)])
                  => do x' <- reify defs !(evalClosure defs x)
                        xs' <- reify defs !(evalClosure defs xs)
                        pure (x' :: xs')
             _ => cantReify val "List"
  reify defs val = cantReify val "List"

export
Reflect a => Reflect (List a) where
  reflect fc defs lhs env [] = appCon fc defs (basics KNil) [Erased fc Placeholder]
  reflect fc defs lhs env (x :: xs)
      = do x' <- reflect fc defs lhs env x
           xs' <- reflect fc defs lhs env xs
           appCon fc defs (basics KCons) [Erased fc Placeholder, x', xs']

export
Reify a => Reify (List1 a) where
  reify defs val@(NDCon _ n _ _ [_, (_, x), (_, xs)])
      = case !(knownCon defs n) of
             Just KCons1
                  => do x' <- reify defs !(evalClosure defs x)
                        xs' <- reify defs !(evalClosure defs xs)
                        pure (x' ::: xs')
             _ => cantReify val "List1"
  reify defs val = cantReify val "List1"

export
Reflect a => Reflect (List1 a) where
  reflect fc defs lhs env xxs
      = do x' <- reflect fc defs lhs env (head xxs)
           xs' <- reflect fc defs lhs env (tail xxs)
           appCon fc defs (NS list1NS (knownUN KCons1)) [Erased fc Placeholder, x', xs']

export
Reify a => Reify (SnocList a) where
  reify defs val@(NDCon _ n _ _ args)
      = case (!(knownCon defs n), args) of
             (Just KLin, _) => pure [<]
             (Just KSnoc, [_, (_, sx), (_, x)])
                  => do sx' <- reify defs !(evalClosure defs sx)
                        x' <- reify defs !(evalClosure defs x)
                        pure (sx' :< x')
             _ => cantReify val "SnocList"
  reify defs val = cantReify val "SnocList"

export
Reflect a => Reflect (SnocList a) where
  reflect fc defs lhs env [<] = appCon fc defs (basics KLin) [Erased fc Placeholder]
  reflect fc defs lhs env (sx :< x)
      = do sx' <- reflect fc defs lhs env sx
           x' <- reflect fc defs lhs env x
           appCon fc defs (basics KSnoc) [Erased fc Placeholder, sx', x']

export
Reify a => Reify (Maybe a) where
  reify defs val@(NDCon _ n _ _ args)
      = case (!(knownCon defs n), args) of
             (Just KNothing, _) => pure Nothing
             (Just KJust, [_, (_, x)])
                  => do x' <- reify defs !(evalClosure defs x)
                        pure (Just x')
             _ => cantReify val "Maybe"
  reify defs val = cantReify val "Maybe"

export
Reflect a => Reflect (Maybe a) where
  reflect fc defs lhs env Nothing = appCon fc defs (preludetypes KNothing) [Erased fc Placeholder]
  reflect fc defs lhs env (Just x)
      = do x' <- reflect fc defs lhs env x
           appCon fc defs (preludetypes KJust) [Erased fc Placeholder, x']


export
Reify a => Reify (WithDefault a def) where
  reify defs val@(NDCon _ n _ _ args)
      = case (!(knownCon defs n), args) of
             (Just KDefaultedValue, _) => pure defaulted
             (Just KSpecifiedValue, [_, _, (_, x)])
                  => do x' <- reify defs !(evalClosure defs x)
                        pure (specified x')
             _ => cantReify val "WithDefault"
  reify defs val = cantReify val "WithDefault"

export
Reflect a => Reflect (WithDefault a def) where
  reflect fc defs lhs env def
    = onWithDefault
        (appCon fc defs (reflectionttimp KDefaultedValue) [Erased fc Placeholder, Erased fc Placeholder])
        (\x => do x' <- reflect fc defs lhs env x
                  appCon fc defs (reflectionttimp KSpecifiedValue) [Erased fc Placeholder, Erased fc Placeholder, x'])
        def

export
(Reify a, Reify b) => Reify (a, b) where
  reify defs val@(NDCon _ n _ _ [_, _, (_, x), (_, y)])
      = case !(knownCon defs n) of
             Just KMkPair
                 => do x' <- reify defs !(evalClosure defs x)
                       y' <- reify defs !(evalClosure defs y)
                       pure (x', y')
             _ => cantReify val "Pair"
  reify defs val = cantReify val "Pair"

export
(Reflect a, Reflect b) => Reflect (a, b) where
  reflect fc defs lhs env (x, y)
      = do x' <- reflect fc defs lhs env x
           y' <- reflect fc defs lhs env y
           appCon fc defs (builtin KMkPair) [Erased fc Placeholder, Erased fc Placeholder, x', y']

export
Reify Namespace where
  reify defs val@(NDCon _ n _ _ [(_, ns)])
    = case !(knownCon defs n) of
        Just KMkNS
          => do ns' <- reify defs !(evalClosure defs ns)
                pure (unsafeFoldNamespace ns')
        _ => cantReify val "Namespace"
  reify defs val = cantReify val "Namespace"

export
Reflect Namespace where
  reflect fc defs lhs env ns
    = do ns' <- reflect fc defs lhs env (unsafeUnfoldNamespace ns)
         appCon fc defs (reflectiontt KMkNS) [ns']

export
Reify ModuleIdent where
  reify defs val@(NDCon _ n _ _ [(_, ns)])
    = case !(knownCon defs n) of
        Just KMkMI
          => do ns' <- reify defs !(evalClosure defs ns)
                pure (unsafeFoldModuleIdent ns')
        _ => cantReify val "ModuleIdent"
  reify defs val = cantReify val "ModuleIdent"

export
Reflect ModuleIdent where
  reflect fc defs lhs env ns
    = do ns' <- reflect fc defs lhs env (unsafeUnfoldModuleIdent ns)
         appCon fc defs (reflectiontt KMkMI) [ns']

export
Reify UserName where
  reify defs val@(NDCon _ n _ _ args)
      = case (!(knownCon defs n), args) of
             (Just KBasic, [(_, str)])
                 => do str' <- reify defs !(evalClosure defs str)
                       pure (Basic str')
             (Just KField, [(_, str)])
                 => do str' <- reify defs !(evalClosure defs str)
                       pure (Field str')
             (Just KUnderscore, [])
                 => pure Underscore
             _ => cantReify val "Name, the name was not found in context"
  reify defs val = cantReify val "Name, value is not an NDCon interally"

export
Reflect UserName where
  reflect fc defs lhs env (Basic x)
      = do x' <- reflect fc defs lhs env x
           appCon fc defs (reflectiontt KBasic) [x']
  reflect fc defs lhs env (Field x)
      = do x' <- reflect fc defs lhs env x
           appCon fc defs (reflectiontt KField) [x']
  reflect fc defs lhs env Underscore
      = do appCon fc defs (reflectiontt KUnderscore) []

export
Reify Name where
  reify defs val@(NDCon _ n _ _ args)
      = case (!(knownCon defs n), args) of
             (Just KUN, [(_, str)])
                 => do str' <- reify defs !(evalClosure defs str)
                       pure (UN str')
             (Just KMN, [(_, str), (_, i)])
                 => do str' <- reify defs !(evalClosure defs str)
                       i' <- reify defs !(evalClosure defs i)
                       pure (MN str' i')
             (Just KNS, [(_, ns), (_, n)])
                 => do ns' <- reify defs !(evalClosure defs ns)
                       n' <- reify defs !(evalClosure defs n)
                       pure (NS ns' n')
             (Just KDN, [(_, str), (_, n)])
                 => do str' <- reify defs !(evalClosure defs str)
                       n' <- reify defs !(evalClosure defs n)
                       pure (DN str' n')
             (Just KNested, [(_, ix), (_, n)])
                 => do ix' <- reify defs !(evalClosure defs ix)
                       n' <- reify defs !(evalClosure defs n)
                       pure (Nested ix' n')
             -- A block is named by its definition and its ordinal, which
             -- the reflected form, a printed parent, does not hold; and a
             -- script cannot name a block before the block exists.
             (Just KCaseBlock, _)
                 => cantReify val "Name, a case block is not named by a script"
             (Just KWithBlock, _)
                 => cantReify val "Name, a with block is not named by a script"
             _ => cantReify val "Name, the name was not found in context"
  reify defs val = cantReify val "Name, value is not an NDCon interally"

export
Reflect Name where
  reflect fc defs lhs env (UN x)
      = do x' <- reflect fc defs lhs env x
           appCon fc defs (reflectiontt KUN) [x']
  reflect fc defs lhs env (MN x i)
      = do x' <- reflect fc defs lhs env x
           i' <- reflect fc defs lhs env i
           appCon fc defs (reflectiontt KMN) [x', i']
  reflect fc defs lhs env (NS ns n)
      = do ns' <- reflect fc defs lhs env ns
           n' <- reflect fc defs lhs env n
           appCon fc defs (reflectiontt KNS) [ns', n']
  reflect fc defs lhs env (DN str n)
      = do str' <- reflect fc defs lhs env str
           n' <- reflect fc defs lhs env n
           appCon fc defs (reflectiontt KDN) [str', n']
  reflect fc defs lhs env (Nested ix n)
      = do ix' <- reflect fc defs lhs env ix
           n'  <- reflect fc defs lhs env n
           appCon fc defs (reflectiontt KNested) [ix',n']
  -- Reflected as base's form: the parent printed (without its namespace,
  -- as a block's message prints it), the ordinal an `Int`.
  reflect fc defs lhs env (CaseBlock outer i)
      = do outer' <- reflect fc defs lhs env (show (snd (splitNS outer)))
           i' <- reflect fc defs lhs env (the Int (cast i))
           appCon fc defs (reflectiontt KCaseBlock) [outer',i']
  reflect fc defs lhs env (WithBlock outer i)
      = do outer' <- reflect fc defs lhs env (show (snd (splitNS outer)))
           i' <- reflect fc defs lhs env (the Int (cast i))
           appCon fc defs (reflectiontt KWithBlock) [outer',i']
  reflect fc defs lhs env (Resolved i)
      = case !(full (gamma defs) (Resolved i)) of
             Resolved _ => cantReflect fc
                      "Name directly, Resolved is intentionally internal"
             n => reflect fc defs lhs env n
  reflect fc defs lhs env n = cantReflect fc
    "Name, reflecting it is unimplemented or intentionally internal"

export
Reify NameType where
  reify defs val@(NDCon _ n _ _ args)
      = case (!(knownCon defs n), args) of
             (Just KBound, _) => pure Bound
             (Just KFunc, _) => pure Func
             (Just KDataCon, [(_, t), (_, i)])
                  => do t' <- reify defs !(evalClosure defs t)
                        i' <- reify defs !(evalClosure defs i)
                        pure (DataCon t' i')
             (Just KTyCon, [(_, i)])
                  => do i' <- reify defs !(evalClosure defs i)
                        pure (TyCon i')
             _ => cantReify val "NameType"
  reify defs val = cantReify val "NameType"

export
Reflect NameType where
  reflect fc defs lhs env Bound = getCon fc defs (reflectiontt KBound)
  reflect fc defs lhs env Func = getCon fc defs (reflectiontt KFunc)
  reflect fc defs lhs env (DataCon t i)
      = do t' <- reflect fc defs lhs env t
           i' <- reflect fc defs lhs env i
           appCon fc defs (reflectiontt KDataCon) [t', i']
  reflect fc defs lhs env (TyCon i)
      = do i' <- reflect fc defs lhs env i
           appCon fc defs (reflectiontt KTyCon) [PrimVal fc (I 0), i']

export
Reify PrimType where
  reify defs val@(NDCon _ n _ _ args)
      = case (!(knownCon defs n), args) of
             (Just KIntType, [])
                  => pure IntType
             (Just KInt8Type, [])
                  => pure Int8Type
             (Just KInt16Type, [])
                  => pure Int16Type
             (Just KInt32Type, [])
                  => pure Int32Type
             (Just KInt64Type, [])
                  => pure Int64Type
             (Just KIntegerType, [])
                  => pure IntegerType
             (Just KBits8Type, [])
                  => pure Bits8Type
             (Just KBits16Type, [])
                  => pure Bits16Type
             (Just KBits32Type, [])
                  => pure Bits32Type
             (Just KBits64Type, [])
                  => pure Bits64Type
             (Just KStringType, [])
                  => pure StringType
             (Just KCharType, [])
                  => pure CharType
             (Just KDoubleType, [])
                  => pure DoubleType
             (Just KWorldType, [])
                  => pure WorldType
             _ => cantReify val "PrimType"
  reify defs val = cantReify val "PrimType"

export
Reify Constant where
  reify defs val@(NDCon _ n _ _ args)
      = case (!(knownCon defs n), args) of
             (Just KI, [(_, x)])
                  => do x' <- reify defs !(evalClosure defs x)
                        pure (I x')
             (Just KI8, [(_, x)])
                  => do x' <- reify defs !(evalClosure defs x)
                        pure (I8 x')
             (Just KI16, [(_, x)])
                  => do x' <- reify defs !(evalClosure defs x)
                        pure (I16 x')
             (Just KI32, [(_, x)])
                  => do x' <- reify defs !(evalClosure defs x)
                        pure (I32 x')
             (Just KI64, [(_, x)])
                  => do x' <- reify defs !(evalClosure defs x)
                        pure (I64 x')
             (Just KBI, [(_, x)])
                  => do x' <- reify defs !(evalClosure defs x)
                        pure (BI x')
             (Just KB8, [(_, x)])
                  => do x' <- reify defs !(evalClosure defs x)
                        pure (B8 x')
             (Just KB16, [(_, x)])
                  => do x' <- reify defs !(evalClosure defs x)
                        pure (B16 x')
             (Just KB32, [(_, x)])
                  => do x' <- reify defs !(evalClosure defs x)
                        pure (B32 x')
             (Just KB64, [(_, x)])
                  => do x' <- reify defs !(evalClosure defs x)
                        pure (B64 x')
             (Just KStr, [(_, x)])
                  => do x' <- reify defs !(evalClosure defs x)
                        pure (Str x')
             (Just KCh, [(_, x)])
                  => do x' <- reify defs !(evalClosure defs x)
                        pure (Ch x')
             (Just KDb, [(_, x)])
                  => do x' <- reify defs !(evalClosure defs x)
                        pure (Db x')
             (Just KPrT, [(_, x)])
                  => do x' <- reify defs !(evalClosure defs x)
                        pure (PrT x')
             (Just KWorldVal, [])
                  => pure WorldVal
             _ => cantReify val "Constant"
  reify defs val = cantReify val "Constant"

export
Reflect PrimType where
  reflect fc defs lhs env IntType
      = getCon fc defs (reflectiontt KIntType)
  reflect fc defs lhs env Int8Type
      = getCon fc defs (reflectiontt KInt8Type)
  reflect fc defs lhs env Int16Type
      = getCon fc defs (reflectiontt KInt16Type)
  reflect fc defs lhs env Int32Type
      = getCon fc defs (reflectiontt KInt32Type)
  reflect fc defs lhs env Int64Type
      = getCon fc defs (reflectiontt KInt64Type)
  reflect fc defs lhs env IntegerType
      = getCon fc defs (reflectiontt KIntegerType)
  reflect fc defs lhs env Bits8Type
      = getCon fc defs (reflectiontt KBits8Type)
  reflect fc defs lhs env Bits16Type
      = getCon fc defs (reflectiontt KBits16Type)
  reflect fc defs lhs env Bits32Type
      = getCon fc defs (reflectiontt KBits32Type)
  reflect fc defs lhs env Bits64Type
      = getCon fc defs (reflectiontt KBits64Type)
  reflect fc defs lhs env StringType
      = getCon fc defs (reflectiontt KStringType)
  reflect fc defs lhs env CharType
      = getCon fc defs (reflectiontt KCharType)
  reflect fc defs lhs env DoubleType
      = getCon fc defs (reflectiontt KDoubleType)
  reflect fc defs lhs env WorldType
      = getCon fc defs (reflectiontt KWorldType)

export
Reflect Constant where
  reflect fc defs lhs env (I x)
      = do x' <- reflect fc defs lhs env x
           appCon fc defs (reflectiontt KI) [x']
  reflect fc defs lhs env (I8 x)
      = do x' <- reflect fc defs lhs env x
           appCon fc defs (reflectiontt KI8) [x']
  reflect fc defs lhs env (I16 x)
      = do x' <- reflect fc defs lhs env x
           appCon fc defs (reflectiontt KI16) [x']
  reflect fc defs lhs env (I32 x)
      = do x' <- reflect fc defs lhs env x
           appCon fc defs (reflectiontt KI32) [x']
  reflect fc defs lhs env (I64 x)
      = do x' <- reflect fc defs lhs env x
           appCon fc defs (reflectiontt KI64) [x']
  reflect fc defs lhs env (BI x)
      = do x' <- reflect fc defs lhs env x
           appCon fc defs (reflectiontt KBI) [x']
  reflect fc defs lhs env (B8 x)
      = do x' <- reflect fc defs lhs env x
           appCon fc defs (reflectiontt KB8) [x']
  reflect fc defs lhs env (B16 x)
      = do x' <- reflect fc defs lhs env x
           appCon fc defs (reflectiontt KB16) [x']
  reflect fc defs lhs env (B32 x)
      = do x' <- reflect fc defs lhs env x
           appCon fc defs (reflectiontt KB32) [x']
  reflect fc defs lhs env (B64 x)
      = do x' <- reflect fc defs lhs env x
           appCon fc defs (reflectiontt KB64) [x']
  reflect fc defs lhs env (Str x)
      = do x' <- reflect fc defs lhs env x
           appCon fc defs (reflectiontt KStr) [x']
  reflect fc defs lhs env (Ch x)
      = do x' <- reflect fc defs lhs env x
           appCon fc defs (reflectiontt KCh) [x']
  reflect fc defs lhs env (Db x)
      = do x' <- reflect fc defs lhs env x
           appCon fc defs (reflectiontt KDb) [x']
  reflect fc defs lhs env (PrT x)
      = do x' <- reflect fc defs lhs env x
           appCon fc defs (reflectiontt KPrT) [x']
  reflect fc defs lhs env WorldVal
      = getCon fc defs (reflectiontt KWorldVal)

export
Reify Visibility where
  reify defs val@(NDCon _ n _ _ _)
      = case !(knownCon defs n) of
             Just KPrivate => pure Private
             Just KExport => pure Export
             Just KPublic => pure Public
             _ => cantReify val "Visibility"
  reify defs val = cantReify val "Visibility"

export
Reflect Visibility where
  reflect fc defs lhs env Private = getCon fc defs (reflectiontt KPrivate)
  reflect fc defs lhs env Export = getCon fc defs (reflectiontt KExport)
  reflect fc defs lhs env Public = getCon fc defs (reflectiontt KPublic)

export
Reify TotalReq where
  reify defs val@(NDCon _ n _ _ _)
      = case !(knownCon defs n) of
             Just KTotal => pure Total
             Just KCoveringOnly => pure CoveringOnly
             Just KPartialOK => pure PartialOK
             _ => cantReify val "TotalReq"
  reify defs val = cantReify val "TotalReq"

export
Reflect TotalReq where
  reflect fc defs lhs env Total = getCon fc defs (reflectiontt KTotal)
  reflect fc defs lhs env CoveringOnly = getCon fc defs (reflectiontt KCoveringOnly)
  reflect fc defs lhs env PartialOK = getCon fc defs (reflectiontt KPartialOK)

export
Reify RigCount where
  reify defs val@(NDCon _ n _ _ _)
      = case !(knownCon defs n) of
             Just KM0 => pure erased
             Just KM1 => pure linear
             Just KMW => pure top
             _ => cantReify val "Count"
  reify defs val = cantReify val "Count"

export
Reflect RigCount where
  reflect fc defs lhs env r
      = elimSemi (getCon fc defs (reflectiontt KM0))
                 (getCon fc defs (reflectiontt KM1))
                 (const (getCon fc defs (reflectiontt KMW)))
                 r

export
Reify t => Reify (PiInfo t) where
  reify defs val@(NDCon _ n _ _ args)
      = case (!(knownCon defs n), args) of
             (Just KImplicitArg, _) => pure Implicit
             (Just KExplicitArg, _) => pure Explicit
             (Just KAutoImplicit, _) => pure AutoImplicit
             (Just KDefImplicit, [_, (_, t)])
                 => do t' <- reify defs !(evalClosure defs t)
                       pure (DefImplicit t')
             _ => cantReify val "PiInfo"
  reify defs val = cantReify val "PiInfo"

export
Reflect t => Reflect (PiInfo t) where
  reflect fc defs lhs env Implicit
      = appCon fc defs (reflectiontt KImplicitArg) [Erased fc Placeholder]
  reflect fc defs lhs env Explicit
      = appCon fc defs (reflectiontt KExplicitArg) [Erased fc Placeholder]
  reflect fc defs lhs env AutoImplicit
      = appCon fc defs (reflectiontt KAutoImplicit) [Erased fc Placeholder]
  reflect fc defs lhs env (DefImplicit t)
      = do t' <- reflect fc defs lhs env t
           appCon fc defs (reflectiontt KDefImplicit) [Erased fc Placeholder, t']

export
Reify LazyReason where
  reify defs val@(NDCon _ n _ _ _)
      = case !(knownCon defs n) of
             Just KLInf => pure LInf
             Just KLLazy => pure LLazy
             Just KLUnknown => pure LUnknown
             _ => cantReify val "LazyReason"
  reify defs val = cantReify val "LazyReason"

export
Reflect LazyReason where
  reflect fc defs lhs env LInf = getCon fc defs (reflectiontt KLInf)
  reflect fc defs lhs env LLazy = getCon fc defs (reflectiontt KLLazy)
  reflect fc defs lhs env LUnknown = getCon fc defs (reflectiontt KLUnknown)

export
Reify VirtualIdent where
  reify defs val@(NDCon _ n _ _ args)
      = case (!(knownCon defs n), args) of
             (Just KInteractive, [])
                   => pure Interactive
             _ => cantReify val "VirtualIdent"
  reify defs val = cantReify val "VirtualIdent"

export
Reflect BuiltinType where
  reflect fc defs lhs env BuiltinNatural
      = getCon fc defs (reflectiontt KBuiltinNatural)
  reflect fc defs lhs env NaturalToInteger
      = getCon fc defs (reflectiontt KNaturalToInteger)
  reflect fc defs lhs env IntegerToNatural
      = getCon fc defs (reflectiontt KIntegerToNatural)

export
Reify BuiltinType where
  reify defs val@(NDCon _ n _ _ args)
      = case (!(knownCon defs n), args) of
             (Just KBuiltinNatural, [])
                   => pure BuiltinNatural
             (Just KNaturalToInteger, [])
                   => pure NaturalToInteger
             (Just KIntegerToNatural, [])
                   => pure IntegerToNatural
             _ => cantReify val "BuiltinType"
  reify defs val = cantReify val "BuiltinType"

export
Reflect VirtualIdent where
  reflect fc defs lhs env Interactive
      = getCon fc defs (reflectiontt KInteractive)

export
Reify OriginDesc where
  reify defs val@(NDCon _ n _ _ args)
      = case (!(knownCon defs n), args) of
             (Just KPhysicalIdrSrc, [(_, ident)])
                   => do ident' <- reify defs !(evalClosure defs ident)
                         pure (PhysicalIdrSrc ident')
             (Just KPhysicalPkgSrc, [(_, fname)])
                   => do fname' <- reify defs !(evalClosure defs fname)
                         pure (PhysicalPkgSrc fname')
             (Just KVirtual, [(_, ident)])
                   => do ident' <- reify defs !(evalClosure defs ident)
                         pure (Virtual ident')
             _ => cantReify val "OriginDesc"
  reify defs val = cantReify val "OriginDesc"

export
Reflect OriginDesc where
  reflect fc defs lhs env (PhysicalIdrSrc ident)
      = do ident' <- reflect fc defs lhs env ident
           appCon fc defs (reflectiontt KPhysicalIdrSrc) [ident']
  reflect fc defs lhs env (PhysicalPkgSrc fname)
      = do fname' <- reflect fc defs lhs env fname
           appCon fc defs (reflectiontt KPhysicalPkgSrc) [fname']
  reflect fc defs lhs env (Virtual ident)
      = do ident' <- reflect fc defs lhs env ident
           appCon fc defs (reflectiontt KVirtual) [ident']

export
Reify FC where
  reify defs val@(NDCon _ n _ _ args)
      = case (!(knownCon defs n), args) of
             (Just KMkFC, [(_, fn), (_, start), (_, end)])
                   => do fn' <- reify defs !(evalClosure defs fn)
                         start' <- reify defs !(evalClosure defs start)
                         end' <- reify defs !(evalClosure defs end)
                         pure (MkFC fn' start' end')
             (Just KEmptyFC, _) => pure EmptyFC
             _ => cantReify val "FC"
  reify defs val = cantReify val "FC"

export
Reflect FC where
  reflect fc defs True env _ = pure $ Erased fc Placeholder
  reflect fc defs lhs env (MkFC fn start end)
      = do fn' <- reflect fc defs lhs env fn
           start' <- reflect fc defs lhs env start
           end' <- reflect fc defs lhs env end
           appCon fc defs (reflectiontt KMkFC) [fn', start', end']
  reflect fc defs lhs env (MkVirtualFC fn start end)
      = do fn' <- reflect fc defs lhs env fn
           start' <- reflect fc defs lhs env start
           end' <- reflect fc defs lhs env end
           appCon fc defs (reflectiontt KMkFC) [fn', start', end']
  reflect fc defs lhs env EmptyFC = getCon fc defs (reflectiontt KEmptyFC)

export
Reify a => Reify (WithFC a) where
  reify defs val@(NDCon _ n _ _ args)
      = do t <- dropAllNS <$> full (gamma defs) n
           case (knownRoot t, map snd args) of
             (Just KMkFCVal, [fcterm, nestedVal]) => do
                 fc <- reify defs !(evalClosure defs fcterm)
                 val <- reify defs !(evalClosure defs nestedVal)
                 pure $ MkFCVal fc val
             (Just KMkFCVal, [_, fc, l2]) => do
                 fc' <- reify defs !(evalClosure defs fc)
                 val' <- reify defs !(evalClosure defs l2)
                 pure $ MkFCVal fc' val'
             (_, l) => cantReify val "WithFC constructor: \{show t}, args: \{show (length l)}"
  reify defs val = cantReify val "Expected WithFC, found something else"

export
Reflect a => Reflect (WithFC a) where
  reflect fc defs lhs env value
      = do loc' <- reflect fc defs lhs env value.fc
           val' <- reflect fc defs lhs env value.val
           appCon fc defs (reflectiontt KMkFCVal) [Erased fc Placeholder, loc', val']

{-
-- Reflection of well typed terms: We don't reify terms because that involves
-- type checking, but we can reflect them

-- TODO: Do we need this? Fix reify if we do.

export
Reflect (IsVar name idx vs) where
  reflect fc defs lhs env First
      = appCon fc defs (reflectiontt KFirst) [Erased fc Placeholder, Erased fc Placeholder]
  reflect fc defs lhs env (Later p)
      = do p' <- reflect fc defs lhs env p
           appCon fc defs (reflectiontt KLater)
                  [Erased fc Placeholder, Erased fc Placeholder,
                   Erased fc Placeholder, Erased fc Placeholder, p']

-- Assume terms are normalised so there's not Let bindings in particular
export
Reflect (Term vs) where
  reflect fc defs lhs env (Local {name} lfc _ idx prf)
      = do lfc' <- reflect fc defs lhs env lfc
           idx' <- reflect fc defs lhs env idx
           appCon fc defs (reflectiontt KLocal)
                  [Erased fc Placeholder, Erased fc Placeholder, lfc', idx', Erased fc Placeholder]
  reflect fc defs lhs env (Ref rfc nt n)
      = do rfc' <- reflect fc defs lhs env rfc
           nt' <- reflect fc defs lhs env nt
           n' <- reflect fc defs lhs env n
           appCon fc defs (reflectiontt KRef)
                  [Erased fc Placeholder, rfc', nt', n']
  reflect fc defs lhs env (Bind bfc x (Pi c p ty) sc)
      = do bfc' <- reflect fc defs lhs env bfc
           x' <- reflect fc defs lhs env x
           c' <- reflect fc defs lhs env c
           p' <- reflect fc defs lhs env p
           ty' <- reflect fc defs lhs env ty
           sc' <- reflect fc defs lhs env sc
           appCon fc defs (reflectiontt KPi)
                  [Erased fc Placeholder, bfc', c', p', x', ty', sc']
  reflect fc defs lhs env (Bind bfc x (Lam c p ty) sc)
      = do bfc' <- reflect fc defs lhs env bfc
           x' <- reflect fc defs lhs env x
           c' <- reflect fc defs lhs env c
           p' <- reflect fc defs lhs env p
           ty' <- reflect fc defs lhs env ty
           sc' <- reflect fc defs lhs env sc
           appCon fc defs (reflectiontt KLam)
                  [Erased fc Placeholder, bfc', c', p', x', ty', sc']
  reflect fc defs lhs env (App afc fn arg)
      = do afc' <- reflect fc defs lhs env afc
           fn' <- reflect fc defs lhs env fn
           arg' <- reflect fc defs lhs env arg
           appCon fc defs (reflectiontt KApp)
                  [Erased fc Placeholder, afc', fn', arg']
  reflect fc defs lhs env (TDelayed dfc r tm)
      = do dfc' <- reflect fc defs lhs env dfc
           r' <- reflect fc defs lhs env r
           tm' <- reflect fc defs lhs env tm
           appCon fc defs (reflectiontt KTDelayed)
                  [Erased fc Placeholder, dfc', r', tm']
  -- Base's reflected term is upstream's, with a reason and no origin.
  reflect fc defs lhs env (TDelay dfc d ty tm)
      = do dfc' <- reflect fc defs lhs env dfc
           r' <- reflect fc defs lhs env d.reason
           ty' <- reflect fc defs lhs env ty
           tm' <- reflect fc defs lhs env tm
           appCon fc defs (reflectiontt KTDelay)
                  [Erased fc Placeholder, dfc', r', ty', tm']
  reflect fc defs lhs env (TForce dfc r tm)
      = do dfc' <- reflect fc defs lhs env dfc
           r' <- reflect fc defs lhs env r
           tm' <- reflect fc defs lhs env tm
           appCon fc defs (reflectiontt KTForce)
                  [Erased fc Placeholder, r', dfc', tm']
  reflect fc defs lhs env (PrimVal pfc c)
      = do pfc' <- reflect fc defs lhs env pfc
           c' <- reflect fc defs lhs env c
           appCon fc defs (reflectiontt KPrimVal)
                  [Erased fc Placeholder, pfc', c']
  reflect fc defs lhs env (Erased efc _)
      = do efc' <- reflect fc defs lhs env efc
           appCon fc defs (reflectiontt KErased)
                  [Erased fc Placeholder, efc']
  reflect fc defs lhs env (TType tfc)
      = do tfc' <- reflect fc defs lhs env tfc
           appCon fc defs (reflectiontt KTType)
                  [Erased fc Placeholder, tfc']
  reflect fc defs lhs env val = cantReflect fc "Term"
  -}
