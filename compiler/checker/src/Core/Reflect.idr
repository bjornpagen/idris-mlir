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
reflectiontt : Known -> Name
reflectiontt k = NS reflectionTTNS (knownUN k)

export
reflectionttimp : Known -> Name
reflectionttimp k = NS reflectionTTImpNS (knownUN k)

export
cantReflect : FC -> String -> Core a
cantReflect fc ty
    = throw (GenericMsg fc ("Can't reflect as " ++ ty))

export
Reflect () where
  reflect fc defs lhs env _ = getCon fc defs (builtin KMkUnit)

export
Reflect String where
  reflect fc defs lhs env x = pure (PrimVal fc (Str x))

||| Base spells every identifier of a reflected name as a `String`: the text
||| enters the session's table of identifiers where a script hands it to the
||| compiler, and an identifier goes back to a script as its text.
export
Reflect Ident where
  reflect fc defs lhs env i = reflect fc defs lhs env i.text

export
Reflect Int where
  reflect fc defs lhs env x = pure (PrimVal fc (I x))

export
Reflect Int8 where
  reflect fc defs lhs env x = pure (PrimVal fc (I8 x))

export
Reflect Int16 where
  reflect fc defs lhs env x = pure (PrimVal fc (I16 x))

export
Reflect Int32 where
  reflect fc defs lhs env x = pure (PrimVal fc (I32 x))

export
Reflect Int64 where
  reflect fc defs lhs env x = pure (PrimVal fc (I64 x))

export
Reflect Bits8 where
  reflect fc defs lhs env x = pure (PrimVal fc (B8 x))

export
Reflect Bits16 where
  reflect fc defs lhs env x = pure (PrimVal fc (B16 x))

export
Reflect Bits32 where
  reflect fc defs lhs env x = pure (PrimVal fc (B32 x))

export
Reflect Bits64 where
  reflect fc defs lhs env x = pure (PrimVal fc (B64 x))

export
Reflect Integer where
  reflect fc defs lhs env x = pure (PrimVal fc (BI x))

export
Reflect Char where
  reflect fc defs lhs env x = pure (PrimVal fc (Ch x))

export
Reflect Double where
  reflect fc defs lhs env x = pure (PrimVal fc (Db x))

export
Reflect Bool where
  reflect fc defs lhs env True = getCon fc defs (basics KTrue)
  reflect fc defs lhs env False = getCon fc defs (basics KFalse)

export
Reflect Nat where
  reflect fc defs lhs env Z = getCon fc defs (preludetypes KZ)
  reflect fc defs lhs env (S k)
      = do k' <- reflect fc defs lhs env k
           appCon fc defs (preludetypes KS) [k']

export
Reflect a => Reflect (List a) where
  reflect fc defs lhs env [] = appCon fc defs (basics KNil) [Erased fc Placeholder]
  reflect fc defs lhs env (x :: xs)
      = do x' <- reflect fc defs lhs env x
           xs' <- reflect fc defs lhs env xs
           appCon fc defs (basics KCons) [Erased fc Placeholder, x', xs']

export
Reflect a => Reflect (List1 a) where
  reflect fc defs lhs env xxs
      = do x' <- reflect fc defs lhs env (head xxs)
           xs' <- reflect fc defs lhs env (tail xxs)
           appCon fc defs (NS list1NS (knownUN KCons1)) [Erased fc Placeholder, x', xs']

export
Reflect a => Reflect (SnocList a) where
  reflect fc defs lhs env [<] = appCon fc defs (basics KLin) [Erased fc Placeholder]
  reflect fc defs lhs env (sx :< x)
      = do sx' <- reflect fc defs lhs env sx
           x' <- reflect fc defs lhs env x
           appCon fc defs (basics KSnoc) [Erased fc Placeholder, sx', x']

export
Reflect a => Reflect (Maybe a) where
  reflect fc defs lhs env Nothing = appCon fc defs (preludetypes KNothing) [Erased fc Placeholder]
  reflect fc defs lhs env (Just x)
      = do x' <- reflect fc defs lhs env x
           appCon fc defs (preludetypes KJust) [Erased fc Placeholder, x']


export
Reflect a => Reflect (WithDefault a def) where
  reflect fc defs lhs env def
    = onWithDefault
        (appCon fc defs (reflectionttimp KDefaultedValue) [Erased fc Placeholder, Erased fc Placeholder])
        (\x => do x' <- reflect fc defs lhs env x
                  appCon fc defs (reflectionttimp KSpecifiedValue) [Erased fc Placeholder, Erased fc Placeholder, x'])
        def

export
(Reflect a, Reflect b) => Reflect (a, b) where
  reflect fc defs lhs env (x, y)
      = do x' <- reflect fc defs lhs env x
           y' <- reflect fc defs lhs env y
           appCon fc defs (builtin KMkPair) [Erased fc Placeholder, Erased fc Placeholder, x', y']

export
Reflect Namespace where
  reflect fc defs lhs env ns
    = do ns' <- reflect fc defs lhs env (unsafeUnfoldNamespace ns)
         appCon fc defs (reflectiontt KMkNS) [ns']

export
Reflect ModuleIdent where
  reflect fc defs lhs env ns
    = do ns' <- reflect fc defs lhs env (unsafeUnfoldModuleIdent ns)
         appCon fc defs (reflectiontt KMkMI) [ns']

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
Reflect Visibility where
  reflect fc defs lhs env Private = getCon fc defs (reflectiontt KPrivate)
  reflect fc defs lhs env Export = getCon fc defs (reflectiontt KExport)
  reflect fc defs lhs env Public = getCon fc defs (reflectiontt KPublic)

export
Reflect TotalReq where
  reflect fc defs lhs env Total = getCon fc defs (reflectiontt KTotal)
  reflect fc defs lhs env CoveringOnly = getCon fc defs (reflectiontt KCoveringOnly)
  reflect fc defs lhs env PartialOK = getCon fc defs (reflectiontt KPartialOK)

export
Reflect RigCount where
  reflect fc defs lhs env r
      = elimSemi (getCon fc defs (reflectiontt KM0))
                 (getCon fc defs (reflectiontt KM1))
                 (const (getCon fc defs (reflectiontt KMW)))
                 r

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
Reflect LazyReason where
  reflect fc defs lhs env LInf = getCon fc defs (reflectiontt KLInf)
  reflect fc defs lhs env LLazy = getCon fc defs (reflectiontt KLLazy)
  reflect fc defs lhs env LUnknown = getCon fc defs (reflectiontt KLUnknown)

export
Reflect BuiltinType where
  reflect fc defs lhs env BuiltinNatural
      = getCon fc defs (reflectiontt KBuiltinNatural)
  reflect fc defs lhs env NaturalToInteger
      = getCon fc defs (reflectiontt KNaturalToInteger)
  reflect fc defs lhs env IntegerToNatural
      = getCon fc defs (reflectiontt KIntegerToNatural)

export
Reflect VirtualIdent where
  reflect fc defs lhs env Interactive
      = getCon fc defs (reflectiontt KInteractive)

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
Reflect a => Reflect (WithFC a) where
  reflect fc defs lhs env value
      = do loc' <- reflect fc defs lhs env value.fc
           val' <- reflect fc defs lhs env value.val
           appCon fc defs (reflectiontt KMkFCVal) [Erased fc Placeholder, loc', val']
