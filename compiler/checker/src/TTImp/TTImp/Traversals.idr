-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module TTImp.TTImp.Traversals

import Core.TT
import TTImp.TTImp
import Core.WithData

%default total

-- Every list, option and wrapper the syntax holds terms in is walked by a
-- function of its own rather than by `map`, so that each recursive call is
-- on a part of the term it was given and the traversal is total by its
-- structure.
parameters (f : RawImp' nm -> RawImp' nm)

  export
  mapTTImp : RawImp' nm -> RawImp' nm

  mapTTImps : List (RawImp' nm) -> List (RawImp' nm)
  mapTTImps [] = []
  mapTTImps (t :: ts) = mapTTImp t :: mapTTImps ts

  export
  mapPiInfo : PiInfo (RawImp' nm) -> PiInfo (RawImp' nm)
  mapPiInfo Implicit = Implicit
  mapPiInfo Explicit = Explicit
  mapPiInfo AutoImplicit = AutoImplicit
  mapPiInfo (DefImplicit t) = DefImplicit (mapTTImp t)

  mapPiBindData : PiBindData (RawImp' nm) -> PiBindData (RawImp' nm)
  mapPiBindData (MkPiBindData info ty) = MkPiBindData (mapPiInfo info) (mapTTImp ty)

  export
  mapImpClause : ImpClause' nm -> ImpClause' nm

  mapImpClauses : List (ImpClause' nm) -> List (ImpClause' nm)
  mapImpClauses [] = []
  mapImpClauses (cl :: cls) = mapImpClause cl :: mapImpClauses cls

  mapImpClause (PatClause fc lhs rhs) = PatClause fc (mapTTImp lhs) (mapTTImp rhs)
  mapImpClause (WithClause fc lhs rig wval prf flags cls)
    = WithClause fc (mapTTImp lhs) rig (mapTTImp wval) prf flags (mapImpClauses cls)
  mapImpClause (ImpossibleClause fc lhs) = ImpossibleClause fc (mapTTImp lhs)

  export
  mapFnOpt : FnOpt' nm -> FnOpt' nm
  mapFnOpt Unsafe = Unsafe
  mapFnOpt Inline = Inline
  mapFnOpt NoInline = NoInline
  mapFnOpt Deprecate = Deprecate
  mapFnOpt TCInline = TCInline
  mapFnOpt (Hint b) = Hint b
  mapFnOpt (GlobalHint b) = GlobalHint b
  mapFnOpt ExternFn = ExternFn
  mapFnOpt (ForeignFn ts) = ForeignFn (mapTTImps ts)
  mapFnOpt Invertible = Invertible
  mapFnOpt (Totality treq) = Totality treq
  mapFnOpt (SpecArgs ns) = SpecArgs ns

  mapFnOpts : List (FnOpt' nm) -> List (FnOpt' nm)
  mapFnOpts [] = []
  mapFnOpts (opt :: opts) = mapFnOpt opt :: mapFnOpts opts

  mapImpTy : ImpTy' nm -> ImpTy' nm
  mapImpTy (MkWithFCTyName fc n ty) = MkWithFCTyName fc n (mapTTImp ty)

  mapImpTys : List (ImpTy' nm) -> List (ImpTy' nm)
  mapImpTys [] = []
  mapImpTys (ty :: tys) = mapImpTy ty :: mapImpTys tys

  export
  mapImpData : ImpData' nm -> ImpData' nm
  mapImpData (MkImpData fc n Nothing opts datacons)
    = MkImpData fc n Nothing opts (mapImpTys datacons)
  mapImpData (MkImpData fc n (Just tycon) opts datacons)
    = MkImpData fc n (Just (mapTTImp tycon)) opts (mapImpTys datacons)
  mapImpData (MkImpLater fc n tycon) = MkImpLater fc n (mapTTImp tycon)

  mapParameters : List (ImpParameter' (RawImp' nm)) -> List (ImpParameter' (RawImp' nm))
  mapParameters [] = []
  mapParameters (MkWithRigName rig n bind :: ps)
    = MkWithRigName rig n (mapPiBindData bind) :: mapParameters ps

  mapFields : List (IField' nm) -> List (IField' nm)
  mapFields [] = []
  mapFields (MkWithFCRigName fc rig n bind :: fields)
    = MkWithFCRigName fc rig n (mapPiBindData bind) :: mapFields fields

  export
  mapImpRecord : ImpRecordData nm -> ImpRecordData nm
  mapImpRecord (MkImpRecord (MkWithName tyn params) (MkWithNameOpts con opts fields))
    = MkImpRecord (MkWithName tyn (mapParameters params))
                  (MkWithNameOpts con opts (mapFields fields))

  export
  mapImpDecl : ImpDecl' nm -> ImpDecl' nm

  mapImpDecls : List (ImpDecl' nm) -> List (ImpDecl' nm)
  mapImpDecls [] = []
  mapImpDecls (d :: ds) = mapImpDecl d :: mapImpDecls ds

  mapImpDecl (IClaim (MkFCVal fc (MkIClaimData rig vis opts ty)))
    = IClaim (MkFCVal fc (MkIClaimData rig vis (mapFnOpts opts) (mapImpTy ty)))
  mapImpDecl (IData fc vis mtreq dat) = IData fc vis mtreq (mapImpData dat)
  mapImpDecl (IDef fc n cls) = IDef fc n (mapImpClauses cls)
  mapImpDecl (IParameters fc params xs) = IParameters fc params (mapImpDecls xs)
  mapImpDecl (IRecord fc mstr x y (MkFCVal rfc rec))
    = IRecord fc mstr x y (MkFCVal rfc (mapImpRecord rec))
  mapImpDecl (IFail fc mstr xs) = IFail fc mstr (mapImpDecls xs)
  mapImpDecl (INamespace fc mi xs) = INamespace fc mi (mapImpDecls xs)
  mapImpDecl (ITransform fc n t u) = ITransform fc n (mapTTImp t) (mapTTImp u)
  mapImpDecl (IPragma fc ns g) = IPragma fc ns g
  mapImpDecl (ILog x) = ILog x
  mapImpDecl (IBuiltin fc x n) = IBuiltin fc x n

  export
  mapIFieldUpdate : IFieldUpdate' nm -> IFieldUpdate' nm
  mapIFieldUpdate (ISetField path t) = ISetField path (mapTTImp t)
  mapIFieldUpdate (ISetFieldApp path t) = ISetFieldApp path (mapTTImp t)

  mapIFieldUpdates : List (IFieldUpdate' nm) -> List (IFieldUpdate' nm)
  mapIFieldUpdates [] = []
  mapIFieldUpdates (upd :: upds) = mapIFieldUpdate upd :: mapIFieldUpdates upds

  export
  mapAltType : AltType' nm -> AltType' nm
  mapAltType FirstSuccess = FirstSuccess
  mapAltType Unique = Unique
  mapAltType (UniqueDefault t) = UniqueDefault (mapTTImp t)

  export
  mapOverlaid : Overlaid' nm -> Overlaid' nm
  mapOverlaid (PairOf l r) = PairOf (mapTTImp l) (mapTTImp r)
  mapOverlaid UnitOf = UnitOf
  mapOverlaid (DPairOf opFC nameFC n r) = DPairOf opFC nameFC n (mapTTImp r)

  mapTTImp t@(IVar {}) = f t
  mapTTImp (IPi fc rig pinfo x argTy retTy)
    = f $ IPi fc rig (mapPiInfo pinfo) x (mapTTImp argTy) (mapTTImp retTy)
  mapTTImp (ILam fc rig pinfo x argTy lamTy)
    = f $ ILam fc rig (mapPiInfo pinfo) x (mapTTImp argTy) (mapTTImp lamTy)
  mapTTImp (ILet fc lhsFC rig n nTy nVal scope)
    = f $ ILet fc lhsFC rig n (mapTTImp nTy) (mapTTImp nVal) (mapTTImp scope)
  mapTTImp (ICase fc opts t ty cls)
    = f $ ICase fc opts (mapTTImp t) (mapTTImp ty) (mapImpClauses cls)
  mapTTImp (ILocal fc xs t)
    = f $ ILocal fc (mapImpDecls xs) (mapTTImp t)
  mapTTImp (ICaseLocal fc unm inm args t) = f $ ICaseLocal fc unm inm args (mapTTImp t)
  mapTTImp (IUpdate fc upds t) = f $ IUpdate fc (mapIFieldUpdates upds) (mapTTImp t)
  mapTTImp (IApp fc t u) = f $ IApp fc (mapTTImp t) (mapTTImp u)
  mapTTImp (IAutoApp fc t u) = f $ IAutoApp fc (mapTTImp t) (mapTTImp u)
  mapTTImp (INamedApp fc t n u) = f $ INamedApp fc (mapTTImp t) n (mapTTImp u)
  mapTTImp (IWithApp fc t u) = f $ IWithApp fc (mapTTImp t) (mapTTImp u)
  mapTTImp (ISearch fc) = f $ ISearch fc
  mapTTImp (IAlternative fc alt ts) = f $ IAlternative fc (mapAltType alt) (mapTTImps ts)
  mapTTImp (ITypeOrValue fc ovl) = f $ ITypeOrValue fc (mapOverlaid ovl)
  mapTTImp (IRewrite fc t u) = f $ IRewrite fc (mapTTImp t) (mapTTImp u)
  mapTTImp (ICoerced fc t) = f $ ICoerced fc (mapTTImp t)
  mapTTImp (IBindHere fc bm t) = f $ IBindHere fc bm (mapTTImp t)
  mapTTImp (IBindVar fc str) = f $ IBindVar fc str
  mapTTImp (IAs fc nameFC side n t) = f $ IAs fc nameFC side n (mapTTImp t)
  mapTTImp (IMustUnify fc x t) = f $ IMustUnify fc x (mapTTImp t)
  mapTTImp (IDelayed fc lz t) = f $ IDelayed fc lz (mapTTImp t)
  mapTTImp (IDelay fc t) = f $ IDelay fc (mapTTImp t)
  mapTTImp (IForce fc t) = f $ IForce fc (mapTTImp t)
  mapTTImp (IQuote fc t) = f $ IQuote fc (mapTTImp t)
  mapTTImp (IQuoteName fc n) = f $ IQuoteName fc n
  mapTTImp (IQuoteDecl fc xs) = f $ IQuoteDecl fc (mapImpDecls xs)
  mapTTImp (IUnquote fc t) = f $ IUnquote fc (mapTTImp t)
  mapTTImp (IPrimVal fc c) = f $ IPrimVal fc c
  mapTTImp (IType fc) = f $ IType fc
  mapTTImp (IHole fc str) = f $ IHole fc str
  mapTTImp (IUnifyLog fc x t) = f $ IUnifyLog fc x (mapTTImp t)
  mapTTImp (Implicit fc bindIfUnsolved) = f $ Implicit fc bindIfUnsolved
  mapTTImp (IWithUnambigNames fc xs t) = f $ IWithUnambigNames fc xs (mapTTImp t)
