-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module TTImp.Reflect

import Core.Context
import Core.Env
import Core.Normalise
import Core.Reflect
import Core.Value

import TTImp.TTImp
import Libraries.Data.WithDefault

%default covering

||| The depth base's reflected syntax holds for a search written `%search`,
||| as the language's parser writes that syntax.
writtenSearchDepth : Nat
writtenSearchDepth = 50

export
Reify BindMode where
  reify defs val@(NDCon _ n _ _ args)
      = case (!(knownCon defs n), args) of
             (Just KPI, [(_, c)])
                 => do c' <- reify defs !(evalClosure defs c)
                       pure (PI c')
             (Just KPATTERN, _) => pure PATTERN
             (Just KCOVERAGE, _) => pure COVERAGE
             (Just KNONE, _) => pure NONE
             _ => cantReify val "BindMode"
  reify deva val = cantReify val "BindMode"

export
Reflect BindMode where
  reflect fc defs lhs env (PI c)
      = do c' <- reflect fc defs lhs env c
           appCon fc defs (reflectionttimp KPI) [c']
  reflect fc defs lhs env PATTERN
      = getCon fc defs (reflectionttimp KPATTERN)
  reflect fc defs lhs env COVERAGE
      = getCon fc defs (reflectionttimp KCOVERAGE)
  reflect fc defs lhs env NONE
      = getCon fc defs (reflectionttimp KNONE)

export
Reify UseSide where
  reify defs val@(NDCon _ n _ _ args)
      = case (!(knownCon defs n), args) of
             (Just KUseLeft, _) => pure UseLeft
             (Just KUseRight, _) => pure UseRight
             _ => cantReify val "UseSide"
  reify defs val = cantReify val "UseSide"

export
Reflect UseSide where
  reflect fc defs lhs env UseLeft
      = getCon fc defs (reflectionttimp KUseLeft)
  reflect fc defs lhs env UseRight
      = getCon fc defs (reflectionttimp KUseRight)

export
Reify DotReason where
  reify defs val@(NDCon _ n _ _ args)
      = case (!(knownCon defs n), args) of
             (Just KNonLinearVar, _) => pure NonLinearVar
             (Just KVarApplied, _) => pure VarApplied
             (Just KNotConstructor, _) => pure NotConstructor
             (Just KErasedArg, _) => pure ErasedArg
             (Just KUserDotted, _) => pure UserDotted
             (Just KUnknownDot, _) => pure UnknownDot
             (Just KUnderAppliedCon, _) => pure UnderAppliedCon
             _ => cantReify val "DotReason"
  reify defs val = cantReify val "DotReason"

export
Reflect DotReason where
  reflect fc defs lhs env NonLinearVar
      = getCon fc defs (reflectionttimp KNonLinearVar)
  reflect fc defs lhs env VarApplied
      = getCon fc defs (reflectionttimp KVarApplied)
  reflect fc defs lhs env NotConstructor
      = getCon fc defs (reflectionttimp KNotConstructor)
  reflect fc defs lhs env ErasedArg
      = getCon fc defs (reflectionttimp KErasedArg)
  reflect fc defs lhs env UserDotted
      = getCon fc defs (reflectionttimp KUserDotted)
  reflect fc defs lhs env UnknownDot
      = getCon fc defs (reflectionttimp KUnknownDot)
  reflect fc defs lhs env UnderAppliedCon
      = getCon fc defs (reflectionttimp KUnderAppliedCon)


mutual
  export
  Reify RawImp where
    reify defs val@(NDCon _ n _ _ args)
        = case (!(knownCon defs n), map snd args) of
               (Just KIVar, [fc, n])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          n' <- reify defs !(evalClosure defs n)
                          pure (IVar fc' n')
               (Just KIPi, [fc, c, p, mn, aty, rty])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          c' <- reify defs !(evalClosure defs c)
                          p' <- reify defs !(evalClosure defs p)
                          mn' <- reify defs !(evalClosure defs mn)
                          aty' <- reify defs !(evalClosure defs aty)
                          rty' <- reify defs !(evalClosure defs rty)
                          pure (IPi fc' c' p' mn' aty' rty')
               (Just KILam, [fc, c, p, mn, aty, lty])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          c' <- reify defs !(evalClosure defs c)
                          p' <- reify defs !(evalClosure defs p)
                          mn' <- reify defs !(evalClosure defs mn)
                          aty' <- reify defs !(evalClosure defs aty)
                          lty' <- reify defs !(evalClosure defs lty)
                          pure (ILam fc' c' p' mn' aty' lty')
               (Just KILet, [fc, lhsFC, c, n, ty, val, sc])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          lhsFC' <- reify defs !(evalClosure defs lhsFC)
                          c' <- reify defs !(evalClosure defs c)
                          n' <- reify defs !(evalClosure defs n)
                          ty' <- reify defs !(evalClosure defs ty)
                          val' <- reify defs !(evalClosure defs val)
                          sc' <- reify defs !(evalClosure defs sc)
                          pure (ILet fc' lhsFC' c' n' ty' val' sc')
               (Just KICase, [fc, opts, sc, ty, cs])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          opts' <- reify defs !(evalClosure defs opts)
                          sc' <- reify defs !(evalClosure defs sc)
                          ty' <- reify defs !(evalClosure defs ty)
                          cs' <- reify defs !(evalClosure defs cs)
                          pure (ICase fc' opts' sc' ty' cs')
               (Just KILocal, [fc, ds, sc])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          ds' <- reify defs !(evalClosure defs ds)
                          sc' <- reify defs !(evalClosure defs sc)
                          pure (ILocal fc' ds' sc')
               (Just KIUpdate, [fc, ds, sc])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          ds' <- reify defs !(evalClosure defs ds)
                          sc' <- reify defs !(evalClosure defs sc)
                          pure (IUpdate fc' ds' sc')
               (Just KIApp, [fc, f, a])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          f' <- reify defs !(evalClosure defs f)
                          a' <- reify defs !(evalClosure defs a)
                          pure (IApp fc' f' a')
               (Just KINamedApp, [fc, f, m, a])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          f' <- reify defs !(evalClosure defs f)
                          m' <- reify defs !(evalClosure defs m)
                          a' <- reify defs !(evalClosure defs a)
                          pure (INamedApp fc' f' m' a')
               (Just KIAutoApp, [fc, f, a])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          f' <- reify defs !(evalClosure defs f)
                          a' <- reify defs !(evalClosure defs a)
                          pure (IAutoApp fc' f' a')
               (Just KIWithApp, [fc, f, a])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          f' <- reify defs !(evalClosure defs f)
                          a' <- reify defs !(evalClosure defs a)
                          pure (IWithApp fc' f' a')
               -- A search here has no depth: a script's is dropped.
               (Just KISearch, [fc, d])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          pure (ISearch fc')
               (Just KIAlternative, [fc, t, as])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          t' <- reify defs !(evalClosure defs t)
                          as' <- reify defs !(evalClosure defs as)
                          pure (IAlternative fc' t' as')
               (Just KIRewrite, [fc, t, sc])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          t' <- reify defs !(evalClosure defs t)
                          sc' <- reify defs !(evalClosure defs sc)
                          pure (IRewrite fc' t' sc')
               (Just KIBindHere, [fc, t, sc])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          t' <- reify defs !(evalClosure defs t)
                          sc' <- reify defs !(evalClosure defs sc)
                          pure (IBindHere fc' t' sc')
               (Just KIBindVar, [fc, n])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          n' <- reify defs !(evalClosure defs n)
                          pure (IBindVar fc' n')
               (Just KIAs, [fc, nameFC, s, n, t])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          nameFC' <- reify defs !(evalClosure defs nameFC)
                          s' <- reify defs !(evalClosure defs s)
                          n' <- reify defs !(evalClosure defs n)
                          t' <- reify defs !(evalClosure defs t)
                          pure (IAs fc' nameFC' s' n' t')
               (Just KIMustUnify, [fc, r, t])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          r' <- reify defs !(evalClosure defs r)
                          t' <- reify defs !(evalClosure defs t)
                          pure (IMustUnify fc' r' t')
               (Just KIDelayed, [fc, r, t])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          r' <- reify defs !(evalClosure defs r)
                          t' <- reify defs !(evalClosure defs t)
                          pure (IDelayed fc' r' t')
               (Just KIDelay, [fc, t])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          t' <- reify defs !(evalClosure defs t)
                          pure (IDelay fc' t')
               (Just KIForce, [fc, t])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          t' <- reify defs !(evalClosure defs t)
                          pure (IForce fc' t')
               (Just KIQuote, [fc, t])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          t' <- reify defs !(evalClosure defs t)
                          pure (IQuote fc' t')
               (Just KIQuoteName, [fc, t])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          t' <- reify defs !(evalClosure defs t)
                          pure (IQuoteName fc' t')
               (Just KIQuoteDecl, [fc, t])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          t' <- reify defs !(evalClosure defs t)
                          pure (IQuoteDecl fc' t')
               (Just KIUnquote, [fc, t])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          t' <- reify defs !(evalClosure defs t)
                          pure (IUnquote fc' t')
               (Just KIPrimVal, [fc, t])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          t' <- reify defs !(evalClosure defs t)
                          pure (IPrimVal fc' t')
               (Just KIType, [fc])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          pure (IType fc')
               (Just KIHole, [fc, n])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          n' <- reify defs !(evalClosure defs n)
                          pure (IHole fc' n')
               (Just KImplicit, [fc, n])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          n' <- reify defs !(evalClosure defs n)
                          pure (Implicit fc' n')
               (Just KIWithUnambigNames, [fc, ns, t])
                    => do fc' <- reify defs !(evalClosure defs fc)
                          ns' <- reify defs !(evalClosure defs ns)
                          t' <- reify defs !(evalClosure defs t)
                          pure (IWithUnambigNames fc' ns' t')
               _ => cantReify val "TTImp"
    reify defs val = cantReify val "TTImp"

  export
  Reify IFieldUpdate where
    reify defs val@(NDCon _ n _ _ args)
        = case (!(knownCon defs n), args) of
               (Just KISetField, [(_, x), (_, y)])
                    => do x' <- reify defs !(evalClosure defs x)
                          y' <- reify defs !(evalClosure defs y)
                          pure (ISetField x' y')
               (Just KISetFieldApp, [(_, x), (_, y)])
                    => do x' <- reify defs !(evalClosure defs x)
                          y' <- reify defs !(evalClosure defs y)
                          pure (ISetFieldApp x' y')
               _ => cantReify val "IFieldUpdate"
    reify defs val = cantReify val "IFieldUpdate"

  export
  Reify AltType where
    reify defs val@(NDCon _ n _ _ args)
        = case (!(knownCon defs n), args) of
               (Just KFirstSuccess, _)
                    => pure FirstSuccess
               (Just KUnique, _)
                    => pure Unique
               (Just KUniqueDefault, [(_, x)])
                    => do x' <- reify defs !(evalClosure defs x)
                          pure (UniqueDefault x')
               _ => cantReify val "AltType"
    reify defs val = cantReify val "AltType"

  export
  Reify FnOpt where
    reify defs val@(NDCon _ n _ _ args)
        = case (!(knownCon defs n), args) of
               (Just KInline, _) => pure Inline
               (Just KUnsafe, _) => pure Unsafe
               (Just KNoInline, _) => pure NoInline
               (Just KDeprecate, _) => pure Deprecate
               (Just KTCInline, _) => pure TCInline
               (Just KHint, [(_, x)])
                    => do x' <- reify defs !(evalClosure defs x)
                          pure (Hint x')
               (Just KGlobalHint, [(_, x)])
                    => do x' <- reify defs !(evalClosure defs x)
                          pure (GlobalHint x')
               (Just KExternFn, _) => pure ExternFn
               (Just KForeignFn, [(_, x)])
                    => do x' <- reify defs !(evalClosure defs x)
                          pure (ForeignFn x')
               (Just KForeignExport, [(_, x)])
                    => do x' <- reify defs !(evalClosure defs x)
                          pure (ForeignExport x')
               (Just KInvertible, _) => pure Invertible
               (Just KTotality, [(_, x)])
                    => do x' <- reify defs !(evalClosure defs x)
                          pure (Totality x')
               (Just KMacro, _) => pure Macro
               (Just KSpecArgs, [(_, x)])
                    => do x' <- reify defs !(evalClosure defs x)
                          pure (SpecArgs x')
               _ => cantReify val "FnOpt"
    reify defs val = cantReify val "FnOpt"

  export
  Reify ImpTy where
    reify defs val@(NDCon _ n _ _ args)
        = case (!(knownCon defs n), map snd args) of
               (Just KMkTy, [w, y, z])
                    => do fc' <- reify defs !(evalClosure defs w)
                          name' <- the (Core (WithFC Name)) (reify defs !(evalClosure defs y))
                          term' <- reify defs !(evalClosure defs z)
                          pure (MkWithFCTyName fc' name' term')
               _ => cantReify val "ITy"
    reify defs val = cantReify val "ITy"

  export
  Reify DataOpt where
    reify defs val@(NDCon _ n _ _ args)
        = case (!(knownCon defs n), args) of
               (Just KSearchBy, [(_, x)])
                    => do x' <- reify defs !(evalClosure defs x)
                          pure (SearchBy x')
               (Just KNoHints, _) => pure NoHints
               (Just KUniqueSearch, _) => pure UniqueSearch
               (Just KExternal, _) => pure External
               (Just KNoNewtype, _) => pure NoNewtype
               _ => cantReify val "DataOpt"
    reify defs val = cantReify val "DataOpt"

  export
  Reify ImpData where
    reify defs val@(NDCon _ n _ _ args)
        = case (!(knownCon defs n), map snd args) of
               (Just KMkData, [v,w,x,y,z])
                    => do v' <- reify defs !(evalClosure defs v)
                          w' <- reify defs !(evalClosure defs w)
                          x' <- reify defs !(evalClosure defs x)
                          y' <- reify defs !(evalClosure defs y)
                          z' <- reify defs !(evalClosure defs z)
                          pure (MkImpData v' w' x' y' z')
               (Just KMkLater, [x,y,z])
                    => do x' <- reify defs !(evalClosure defs x)
                          y' <- reify defs !(evalClosure defs y)
                          z' <- reify defs !(evalClosure defs z)
                          pure (MkImpLater x' y' z')
               _ => cantReify val "Data"
    reify defs val = cantReify val "Data"

  export
  Reify IField where
    reify defs val@(NDCon _ n _ _ args)
        = case (!(knownCon defs n), map snd args) of
               (Just KMkIField, [v,w,x,y,z])
                    => do fc <- reify defs !(evalClosure defs v)
                          rig <- reify defs !(evalClosure defs w)
                          info <- reify defs !(evalClosure defs x)
                          name <- reify defs !(evalClosure defs y)
                          type <- reify defs !(evalClosure defs z)
                          pure (MkWithFCRigName fc rig (NoFC name) (MkPiBindData info type))
               _ => cantReify val "IField"
    reify defs val = cantReify val "IField"

  export
  Reify ImpRecord where
    reify defs val@(NDCon _ n _ _ args)
        = case (!(knownCon defs n), map snd args) of
               (Just KMkRecord, [v,w,x,y,z,a])
                    => do fc <- reify defs !(evalClosure defs v)
                          tyName <- reify defs !(evalClosure defs w)
                          params <- reify defs !(evalClosure defs x)
                          opts <- reify defs !(evalClosure defs y)
                          conName <- reify defs !(evalClosure defs z)
                          fields <- reify defs !(evalClosure defs a)
                          pure (MkFCVal fc $ MkImpRecord (MkWithName (NoFC tyName) (map fromOldParams params))
                                                      (MkWithNameOpts (NoFC conName) opts fields))
               _ => cantReify val "Record"
    reify defs val = cantReify val "Record"

  export
  Reify WithFlag where
    reify defs val@(NDCon _ n _ _ args)
        = case (!(knownCon defs n), map snd args) of
               (Just KSyntactic, [])
                    => pure Syntactic
               _ => cantReify val "WithFlag"
    reify defs val = cantReify val "WithFlag"

  export
  Reify ImpClause where
    reify defs val@(NDCon _ n _ _ args)
        = case (!(knownCon defs n), map snd args) of
               (Just KPatClause, [x,y,z])
                    => do x' <- reify defs !(evalClosure defs x)
                          y' <- reify defs !(evalClosure defs y)
                          z' <- reify defs !(evalClosure defs z)
                          pure (PatClause x' y' z')
               (Just KWithClause, [u,v,w,x,y,z,a])
                    => do u' <- reify defs !(evalClosure defs u)
                          v' <- reify defs !(evalClosure defs v)
                          w' <- reify defs !(evalClosure defs w)
                          x' <- reify defs !(evalClosure defs x)
                          y' <- reify defs !(evalClosure defs y)
                          z' <- reify defs !(evalClosure defs z)
                          a' <- reify defs !(evalClosure defs a)
                          pure (WithClause u' v' w' x' y' z' a')
               (Just KImpossibleClause, [x,y])
                    => do x' <- reify defs !(evalClosure defs x)
                          y' <- reify defs !(evalClosure defs y)
                          pure (ImpossibleClause x' y')
               _ => cantReify val "Clause"
    reify defs val = cantReify val "Clause"

  export
  Reify (IClaimData Name) where
    reify defs val@(NDCon _ n _ _ args)
        = case (!(knownCon defs n), map snd args) of
               (Just KMkIClaimData, [w, x, y, z])
                    => do w' <- reify defs !(evalClosure defs w)
                          x' <- reify defs !(evalClosure defs x)
                          y' <- reify defs !(evalClosure defs y)
                          z' <- reify defs !(evalClosure defs z)
                          pure (MkIClaimData w' x' y' z')
               _ => cantReify val "IClaimData"
    reify defs val = cantReify val "IClaimData"

  export
  Reify ImpDecl where
    reify defs val@(NDCon _ n _ _ args)
        = case (!(knownCon defs n), map snd args) of
               (Just KIClaim, [v])
                    => do v' <- reify defs !(evalClosure defs v)
                          pure (IClaim v')
               (Just KIData, [x,y,z,w])
                    => do x' <- reify defs !(evalClosure defs x)
                          y' <- reify defs !(evalClosure defs y)
                          z' <- reify defs !(evalClosure defs z)
                          w' <- reify defs !(evalClosure defs w)
                          pure (IData x' y' z' w')
               (Just KIDef, [x,y,z])
                    => do x' <- reify defs !(evalClosure defs x)
                          y' <- reify defs !(evalClosure defs y)
                          z' <- reify defs !(evalClosure defs z)
                          pure (IDef x' y' z')
               (Just KIParameters, [x,y,z])
                    => do x' <- reify defs !(evalClosure defs x)
                          y' <- reify defs !(evalClosure defs y)
                          z' <- reify defs !(evalClosure defs z)
                          pure (IParameters x' (map fromOldParams y') z')
               (Just KIRecord, [w,x,y,z,u])
                    => do w' <- reify defs !(evalClosure defs w)
                          -- Base holds the nested namespace as its text.
                          nested <- the (Core (Maybe String)) (reify defs !(evalClosure defs x))
                          x' <- traverseOpt internNamespace nested
                          y' <- reify defs !(evalClosure defs y)
                          z' <- reify defs !(evalClosure defs z)
                          u' <- reify defs !(evalClosure defs u)
                          pure (IRecord w' x' y' z' u')
               (Just KIFail, [w,x,y])
                    => do w' <- reify defs !(evalClosure defs w)
                          x' <- reify defs !(evalClosure defs x)
                          y' <- reify defs !(evalClosure defs y)
                          pure (IFail w' x' y')
               (Just KINamespace, [w,x,y])
                    => do w' <- reify defs !(evalClosure defs w)
                          x' <- reify defs !(evalClosure defs x)
                          y' <- reify defs !(evalClosure defs y)
                          pure (INamespace w' x' y')
               (Just KITransform, [w,x,y,z])
                    => do w' <- reify defs !(evalClosure defs w)
                          x' <- reify defs !(evalClosure defs x)
                          y' <- reify defs !(evalClosure defs y)
                          z' <- reify defs !(evalClosure defs z)
                          pure (ITransform w' x' y' z')
               (Just KILog, [x])
                    => do x' <- reify defs !(evalClosure defs x)
                          pure (ILog x')
               _ => cantReify val "Decl"
    reify defs val = cantReify val "Decl"

mutual
  export
  Reflect RawImp where
    reflect fc defs lhs env (IVar tfc n)
        = do fc' <- reflect fc defs lhs env tfc
             n' <- reflect fc defs lhs env n
             appCon fc defs (reflectionttimp KIVar) [fc', n']
    reflect fc defs lhs env (IPi tfc c p mn aty rty)
        = do fc' <- reflect fc defs lhs env tfc
             c' <- reflect fc defs lhs env c
             p' <- reflect fc defs lhs env p
             mn' <- reflect fc defs lhs env mn
             aty' <- reflect fc defs lhs env aty
             rty' <- reflect fc defs lhs env rty
             appCon fc defs (reflectionttimp KIPi) [fc', c', p', mn', aty', rty']
    reflect fc defs lhs env (ILam tfc c p mn aty rty)
        = do fc' <- reflect fc defs lhs env tfc
             c' <- reflect fc defs lhs env c
             p' <- reflect fc defs lhs env p
             mn' <- reflect fc defs lhs env mn
             aty' <- reflect fc defs lhs env aty
             rty' <- reflect fc defs lhs env rty
             appCon fc defs (reflectionttimp KILam) [fc', c', p', mn', aty', rty']
    reflect fc defs lhs env (ILet tfc lhsFC c n aty aval sc)
        = do fc' <- reflect fc defs lhs env tfc
             lhsFC' <- reflect fc defs lhs env lhsFC
             c' <- reflect fc defs lhs env c
             n' <- reflect fc defs lhs env n
             aty' <- reflect fc defs lhs env aty
             aval' <- reflect fc defs lhs env aval
             sc' <- reflect fc defs lhs env sc
             appCon fc defs (reflectionttimp KILet) [fc', lhsFC', c', n', aty', aval', sc']
    reflect fc defs lhs env (ICase tfc opts sc ty cs)
        = do fc' <- reflect fc defs lhs env tfc
             opts' <- reflect fc defs lhs env opts
             sc' <- reflect fc defs lhs env sc
             ty' <- reflect fc defs lhs env ty
             cs' <- reflect fc defs lhs env cs
             appCon fc defs (reflectionttimp KICase) [fc', opts', sc', ty', cs']
    reflect fc defs lhs env (ILocal tfc ds sc)
        = do fc' <- reflect fc defs lhs env tfc
             ds' <- reflect fc defs lhs env ds
             sc' <- reflect fc defs lhs env sc
             appCon fc defs (reflectionttimp KILocal) [fc', ds', sc']
    reflect fc defs lhs env (ICaseLocal tfc u i args t)
        = reflect fc defs lhs env t -- shouldn't see this anyway...
    reflect fc defs lhs env (IUpdate tfc ds sc)
        = do fc' <- reflect fc defs lhs env tfc
             ds' <- reflect fc defs lhs env ds
             sc' <- reflect fc defs lhs env sc
             appCon fc defs (reflectionttimp KIUpdate) [fc', ds', sc']
    reflect fc defs lhs env (IApp tfc f a)
        = do fc' <- reflect fc defs lhs env tfc
             f' <- reflect fc defs lhs env f
             a' <- reflect fc defs lhs env a
             appCon fc defs (reflectionttimp KIApp) [fc', f', a']
    reflect fc defs lhs env (IAutoApp tfc f a)
        = do fc' <- reflect fc defs lhs env tfc
             f' <- reflect fc defs lhs env f
             a' <- reflect fc defs lhs env a
             appCon fc defs (reflectionttimp KIAutoApp) [fc', f', a']
    reflect fc defs lhs env (INamedApp tfc f m a)
        = do fc' <- reflect fc defs lhs env tfc
             f' <- reflect fc defs lhs env f
             m' <- reflect fc defs lhs env m
             a' <- reflect fc defs lhs env a
             appCon fc defs (reflectionttimp KINamedApp) [fc', f', m', a']
    reflect fc defs lhs env (IWithApp tfc f a)
        = do fc' <- reflect fc defs lhs env tfc
             f' <- reflect fc defs lhs env f
             a' <- reflect fc defs lhs env a
             appCon fc defs (reflectionttimp KIWithApp) [fc', f', a']
    -- A quoted search is the term its syntax writes in the language, with
    -- the depth the language gives `%search`. This checker's search has no
    -- depth, and reading a script's search drops the one it holds, so the
    -- depth is only what a script sees of the term it quoted.
    reflect fc defs lhs env (ISearch tfc)
        = do fc' <- reflect fc defs lhs env tfc
             d' <- reflect fc defs lhs env writtenSearchDepth
             appCon fc defs (reflectionttimp KISearch) [fc', d']
    reflect fc defs lhs env (IAlternative tfc t as)
        = do fc' <- reflect fc defs lhs env tfc
             t' <- reflect fc defs lhs env t
             as' <- reflect fc defs lhs env as
             appCon fc defs (reflectionttimp KIAlternative) [fc', t', as']
    -- Base's reflected syntax has no such node, so a script sees the
    -- alternative upstream builds for the same syntax: its two readings,
    -- the value the default.
    reflect fc defs lhs env (ITypeOrValue tfc ovl)
        = reflect fc defs lhs env
            (IAlternative tfc (UniqueDefault (valueReading tfc ovl))
                          [typeReading tfc ovl, valueReading tfc ovl])
    reflect fc defs lhs env (IRewrite tfc t sc)
        = do fc' <- reflect fc defs lhs env tfc
             t' <- reflect fc defs lhs env t
             sc' <- reflect fc defs lhs env sc
             appCon fc defs (reflectionttimp KIRewrite) [fc', t', sc']
    reflect fc defs lhs env (ICoerced tfc d) = reflect fc defs lhs env d
    reflect fc defs lhs env (IBindHere tfc n sc)
        = do fc' <- reflect fc defs lhs env tfc
             n' <- reflect fc defs lhs env n
             sc' <- reflect fc defs lhs env sc
             appCon fc defs (reflectionttimp KIBindHere) [fc', n', sc']
    reflect fc defs lhs env (IBindVar tfc n)
        = do fc' <- reflect fc defs lhs env tfc
             n' <- reflect fc defs lhs env n
             appCon fc defs (reflectionttimp KIBindVar) [fc', n']
    reflect fc defs lhs env (IAs tfc nameFC s n t)
        = do fc' <- reflect fc defs lhs env tfc
             nameFC' <- reflect fc defs lhs env nameFC
             s' <- reflect fc defs lhs env s
             n' <- reflect fc defs lhs env n
             t' <- reflect fc defs lhs env t
             appCon fc defs (reflectionttimp KIAs) [fc', nameFC', s', n', t']
    reflect fc defs lhs env (IMustUnify tfc r t)
        = do fc' <- reflect fc defs lhs env tfc
             r' <- reflect fc defs lhs env r
             t' <- reflect fc defs lhs env t
             appCon fc defs (reflectionttimp KIMustUnify) [fc', r', t']
    reflect fc defs lhs env (IDelayed tfc r t)
        = do fc' <- reflect fc defs lhs env tfc
             r' <- reflect fc defs lhs env r
             t' <- reflect fc defs lhs env t
             appCon fc defs (reflectionttimp KIDelayed) [fc', r', t']
    reflect fc defs lhs env (IDelay tfc t)
        = do fc' <- reflect fc defs lhs env tfc
             t' <- reflect fc defs lhs env t
             appCon fc defs (reflectionttimp KIDelay) [fc', t']
    reflect fc defs lhs env (IForce tfc t)
        = do fc' <- reflect fc defs lhs env tfc
             t' <- reflect fc defs lhs env t
             appCon fc defs (reflectionttimp KIForce) [fc', t']
    reflect fc defs lhs env (IQuote tfc t)
        = do fc' <- reflect fc defs lhs env tfc
             t' <- reflect fc defs lhs env t
             appCon fc defs (reflectionttimp KIQuote) [fc', t']
    reflect fc defs lhs env (IQuoteName tfc t)
        = do fc' <- reflect fc defs lhs env tfc
             t' <- reflect fc defs lhs env t
             appCon fc defs (reflectionttimp KIQuoteName) [fc', t']
    reflect fc defs lhs env (IQuoteDecl tfc t)
        = do fc' <- reflect fc defs lhs env tfc
             t' <- reflect fc defs lhs env t
             appCon fc defs (reflectionttimp KIQuoteDecl) [fc', t']
    reflect fc defs lhs env (IUnquote tfc (IVar _ t))
        = pure (Ref tfc Bound t)
    reflect fc defs lhs env (IUnquote tfc t)
        = throw (InternalError "Can't reflect an unquote: escapes should be lifted out")
    reflect fc defs lhs env (IRunElab tfc _ t)
        = throw (InternalError "Can't reflect a %runElab")
    reflect fc defs lhs env (IPrimVal tfc t)
        = do fc' <- reflect fc defs lhs env tfc
             t' <- reflect fc defs lhs env t
             appCon fc defs (reflectionttimp KIPrimVal) [fc', t']
    reflect fc defs lhs env (IType tfc)
        = do fc' <- reflect fc defs lhs env tfc
             appCon fc defs (reflectionttimp KIType) [fc']
    reflect fc defs lhs env (IHole tfc t)
        = do fc' <- reflect fc defs lhs env tfc
             t' <- reflect fc defs lhs env t
             appCon fc defs (reflectionttimp KIHole) [fc', t']
    reflect fc defs lhs env (IUnifyLog tfc _ t)
        = reflect fc defs lhs env t
    reflect fc defs True env (Implicit tfc t)
        = pure (Erased fc Placeholder)
    reflect fc defs lhs env (Implicit tfc t)
        = do fc' <- reflect fc defs lhs env tfc
             t' <- reflect fc defs lhs env t
             appCon fc defs (reflectionttimp KImplicit) [fc', t']
    reflect fc defs lhs env (IWithUnambigNames tfc ns t)
        = do fc' <- reflect fc defs lhs env tfc
             ns' <- reflect fc defs lhs env ns
             t' <- reflect fc defs lhs env t
             appCon fc defs (reflectionttimp KIWithUnambigNames) [fc', ns', t']

  export
  Reflect IFieldUpdate where
    reflect fc defs lhs env (ISetField p t)
        = do p' <- reflect fc defs lhs env p
             t' <- reflect fc defs lhs env t
             appCon fc defs (reflectionttimp KISetField) [p', t']
    reflect fc defs lhs env (ISetFieldApp p t)
        = do p' <- reflect fc defs lhs env p
             t' <- reflect fc defs lhs env t
             appCon fc defs (reflectionttimp KISetFieldApp) [p', t']

  export
  Reflect AltType where
    reflect fc defs lhs env FirstSuccess = getCon fc defs (reflectionttimp KFirstSuccess)
    reflect fc defs lhs env Unique = getCon fc defs (reflectionttimp KUnique)
    reflect fc defs lhs env (UniqueDefault x)
        = do x' <- reflect fc defs lhs env x
             appCon fc defs (reflectionttimp KUniqueDefault) [x']

  export
  Reflect FnOpt where
    reflect fc defs lhs env Unsafe = getCon fc defs (reflectionttimp KUnsafe)
    reflect fc defs lhs env Inline = getCon fc defs (reflectionttimp KInline)
    reflect fc defs lhs env NoInline = getCon fc defs (reflectionttimp KNoInline)
    reflect fc defs lhs env Deprecate = getCon fc defs (reflectionttimp KDeprecate)
    reflect fc defs lhs env TCInline = getCon fc defs (reflectionttimp KTCInline)
    reflect fc defs lhs env (Hint x)
        = do x' <- reflect fc defs lhs env x
             appCon fc defs (reflectionttimp KHint) [x']
    reflect fc defs lhs env (GlobalHint x)
        = do x' <- reflect fc defs lhs env x
             appCon fc defs (reflectionttimp KGlobalHint) [x']
    reflect fc defs lhs env ExternFn = getCon fc defs (reflectionttimp KExternFn)
    reflect fc defs lhs env (ForeignFn x)
        = do x' <- reflect fc defs lhs env x
             appCon fc defs (reflectionttimp KForeignFn) [x']
    reflect fc defs lhs env (ForeignExport x)
        = do x' <- reflect fc defs lhs env x
             appCon fc defs (reflectionttimp KForeignExport) [x']
    reflect fc defs lhs env Invertible = getCon fc defs (reflectionttimp KInvertible)
    reflect fc defs lhs env (Totality r)
        = do r' <- reflect fc defs lhs env r
             appCon fc defs (reflectionttimp KTotality) [r']
    reflect fc defs lhs env Macro = getCon fc defs (reflectionttimp KMacro)
    reflect fc defs lhs env (SpecArgs r)
        = do r' <- reflect fc defs lhs env r
             appCon fc defs (reflectionttimp KSpecArgs) [r']

  export
  Reflect ImpTy where
    reflect fc defs lhs env ty
        = do w' <- reflect fc defs lhs env ty.fc
             x' <- reflect fc defs lhs env ty.tyName
             z' <- reflect fc defs lhs env ty.val
             appCon fc defs (reflectionttimp KMkTy) [w', x', z']

  export
  Reflect DataOpt where
    reflect fc defs lhs env (SearchBy x)
        = do x' <- reflect fc defs lhs env x
             appCon fc defs (reflectionttimp KSearchBy) [x']
    reflect fc defs lhs env NoHints = getCon fc defs (reflectionttimp KNoHints)
    reflect fc defs lhs env UniqueSearch = getCon fc defs (reflectionttimp KUniqueSearch)
    reflect fc defs lhs env External = getCon fc defs (reflectionttimp KExternal)
    reflect fc defs lhs env NoNewtype = getCon fc defs (reflectionttimp KNoNewtype)

  export
  Reflect ImpData where
    reflect fc defs lhs env (MkImpData v w x y z)
        = do v' <- reflect fc defs lhs env v
             w' <- reflect fc defs lhs env w
             x' <- reflect fc defs lhs env x
             y' <- reflect fc defs lhs env y
             z' <- reflect fc defs lhs env z
             appCon fc defs (reflectionttimp KMkData) [v', w', x', y', z']
    reflect fc defs lhs env (MkImpLater x y z)
        = do x' <- reflect fc defs lhs env x
             y' <- reflect fc defs lhs env y
             z' <- reflect fc defs lhs env z
             appCon fc defs (reflectionttimp KMkLater) [x', y', z']

  export
  Reflect IField where
    reflect fc defs lhs env field -- Order matters to maintain compatibility with elab reflection
        = do v' <- reflect fc defs lhs env field.fc
             w' <- reflect fc defs lhs env field.rig
             x' <- reflect fc defs lhs env field.val.info
             y' <- reflect fc defs lhs env field.name.val
             z' <- reflect fc defs lhs env field.val.boundType
             appCon fc defs (reflectionttimp KMkIField) [v', w', x', y', z']
  export
  Reflect ImpRecord where
    reflect fc defs lhs env r@(MkFCVal _ $ MkImpRecord header body)
        = do v' <- reflect fc defs lhs env r.fc
             w' <- reflect fc defs lhs env header.name.val
             x' <- reflect fc defs lhs env (map toOldParams header.val)
             y' <- reflect fc defs lhs env body.opts
             z' <- reflect fc defs lhs env body.name.val
             a' <- reflect fc defs lhs env body.val
             appCon fc defs (reflectionttimp KMkRecord) [v', w', x', y', z', a']

  export
  Reflect WithFlag where
    reflect fc defs lhs env Syntactic
        = getCon fc defs (reflectionttimp KSyntactic)

  export
  Reflect ImpClause where
    reflect fc defs lhs env (PatClause x y z)
        = do x' <- reflect fc defs lhs env x
             y' <- reflect fc defs lhs env y
             z' <- reflect fc defs lhs env z
             appCon fc defs (reflectionttimp KPatClause) [x', y', z']
    reflect fc defs lhs env (WithClause u v w x y z a)
        = do u' <- reflect fc defs lhs env u
             v' <- reflect fc defs lhs env v
             w' <- reflect fc defs lhs env w
             x' <- reflect fc defs lhs env x
             y' <- reflect fc defs lhs env y
             z' <- reflect fc defs lhs env z
             a' <- reflect fc defs lhs env a
             appCon fc defs (reflectionttimp KWithClause) [u', v', w', x', y', z', a']
    reflect fc defs lhs env (ImpossibleClause x y)
        = do x' <- reflect fc defs lhs env x
             y' <- reflect fc defs lhs env y
             appCon fc defs (reflectionttimp KImpossibleClause) [x', y']

  export
  Reflect (IClaimData Name) where
    reflect fc defs lhs env (MkIClaimData w x y z)
        = do w' <- reflect fc defs lhs env w
             x' <- reflect fc defs lhs env x
             y' <- reflect fc defs lhs env y
             z' <- reflect fc defs lhs env z
             appCon fc defs (reflectionttimp KMkIClaimData) [w', x', y', z']

  export
  Reflect ImpDecl where
    reflect fc defs lhs env (IClaim v)
        = do v' <- reflect fc defs lhs env v
             appCon fc defs (reflectionttimp KIClaim) [v']
    reflect fc defs lhs env (IData x y z w)
        = do x' <- reflect fc defs lhs env x
             y' <- reflect fc defs lhs env y
             z' <- reflect fc defs lhs env z
             w' <- reflect fc defs lhs env w
             appCon fc defs (reflectionttimp KIData) [x', y', z', w']
    reflect fc defs lhs env (IDef x y z)
        = do x' <- reflect fc defs lhs env x
             y' <- reflect fc defs lhs env y
             z' <- reflect fc defs lhs env z
             appCon fc defs (reflectionttimp KIDef) [x', y', z']
    reflect fc defs lhs env (IParameters x y z)
        = do x' <- reflect fc defs lhs env x
             y' <- reflect fc defs lhs env (map toOldParams y)
             z' <- reflect fc defs lhs env z
             appCon fc defs (reflectionttimp KIParameters) [x', y', z']
    reflect fc defs lhs env (IRecord w x y z u)
        = do w' <- reflect fc defs lhs env w
             -- Base holds the nested namespace as its text.
             x' <- reflect fc defs lhs env (map show x)
             y' <- reflect fc defs lhs env y
             z' <- reflect fc defs lhs env z
             u' <- reflect fc defs lhs env u
             appCon fc defs (reflectionttimp KIRecord) [w', x', y', z', u']
    reflect fc defs lhs env (IFail x y z)
        = do x' <- reflect fc defs lhs env x
             y' <- reflect fc defs lhs env y
             z' <- reflect fc defs lhs env z
             appCon fc defs (reflectionttimp KIFail) [x', y', z']
    reflect fc defs lhs env (INamespace x y z)
        = do x' <- reflect fc defs lhs env x
             y' <- reflect fc defs lhs env y
             z' <- reflect fc defs lhs env z
             appCon fc defs (reflectionttimp KINamespace) [x', y', z']
    reflect fc defs lhs env (ITransform w x y z)
        = do w' <- reflect fc defs lhs env w
             x' <- reflect fc defs lhs env x
             y' <- reflect fc defs lhs env y
             z' <- reflect fc defs lhs env z
             appCon fc defs (reflectionttimp KITransform) [w', x', y', z']
    reflect fc defs lhs env (IRunElabDecl w x)
        = throw (GenericMsg fc "Can't reflect a %runElab")
    reflect fc defs lhs env (IPragma _ _ x)
        = throw (GenericMsg fc "Can't reflect a pragma")
    reflect fc defs lhs env (ILog x)
        = do x' <- reflect fc defs lhs env x
             appCon fc defs (reflectionttimp KILog) [x']
    reflect fc defs lhs env (IBuiltin {})
        = throw (GenericMsg fc "Can't reflect a %builtin")
