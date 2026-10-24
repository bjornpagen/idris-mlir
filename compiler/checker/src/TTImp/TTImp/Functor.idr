-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module TTImp.TTImp.Functor

import Core.TT
import Core.WithData
import TTImp.TTImp

%default total

-- Every list, option and wrapper the syntax holds terms in is renamed by a
-- function of its own rather than by `map`, so that each recursive call is
-- on a part of the term it was given and renaming is total by its
-- structure. The `Functor` implementations are these functions.
parameters {0 a : Type} {0 b : Type} (f : a -> b)

  renameRawImp : RawImp' a -> RawImp' b

  renameRawImps : List (RawImp' a) -> List (RawImp' b)
  renameRawImps [] = []
  renameRawImps (t :: ts) = renameRawImp t :: renameRawImps ts

  renameMaybeRawImp : Maybe (RawImp' a) -> Maybe (RawImp' b)
  renameMaybeRawImp Nothing = Nothing
  renameMaybeRawImp (Just t) = Just (renameRawImp t)

  renamePiInfo : PiInfo (RawImp' a) -> PiInfo (RawImp' b)
  renamePiInfo Implicit = Implicit
  renamePiInfo Explicit = Explicit
  renamePiInfo AutoImplicit = AutoImplicit
  renamePiInfo (DefImplicit t) = DefImplicit (renameRawImp t)

  renamePiBindData : PiBindData (RawImp' a) -> PiBindData (RawImp' b)
  renamePiBindData (MkPiBindData info ty) = MkPiBindData (renamePiInfo info) (renameRawImp ty)

  renameImpClause : ImpClause' a -> ImpClause' b

  renameImpClauses : List (ImpClause' a) -> List (ImpClause' b)
  renameImpClauses [] = []
  renameImpClauses (cl :: cls) = renameImpClause cl :: renameImpClauses cls

  renameImpClause (PatClause fc lhs rhs)
    = PatClause fc (renameRawImp lhs) (renameRawImp rhs)
  renameImpClause (WithClause fc lhs rig wval prf flags xs)
    = WithClause fc (renameRawImp lhs) rig (renameRawImp wval) prf flags (renameImpClauses xs)
  renameImpClause (ImpossibleClause fc lhs)
    = ImpossibleClause fc (renameRawImp lhs)

  renameFnOpt : FnOpt' a -> FnOpt' b
  renameFnOpt Unsafe = Unsafe
  renameFnOpt Inline = Inline
  renameFnOpt NoInline = NoInline
  renameFnOpt Deprecate = Deprecate
  renameFnOpt TCInline = TCInline
  renameFnOpt (Hint direct) = Hint direct
  renameFnOpt (GlobalHint fallback) = GlobalHint fallback
  renameFnOpt ExternFn = ExternFn
  renameFnOpt (ForeignFn ts) = ForeignFn (renameRawImps ts)
  renameFnOpt Invertible = Invertible
  renameFnOpt (Totality tot) = Totality tot
  renameFnOpt (SpecArgs ns) = SpecArgs ns

  renameFnOpts : List (FnOpt' a) -> List (FnOpt' b)
  renameFnOpts [] = []
  renameFnOpts (opt :: opts) = renameFnOpt opt :: renameFnOpts opts

  renameImpTy : ImpTy' a -> ImpTy' b
  renameImpTy (MkWithFCTyName fc n ty) = MkWithFCTyName fc n (renameRawImp ty)

  renameImpTys : List (ImpTy' a) -> List (ImpTy' b)
  renameImpTys [] = []
  renameImpTys (ty :: tys) = renameImpTy ty :: renameImpTys tys

  renameClaim : IClaimData a -> IClaimData b
  renameClaim (MkIClaimData rig vis opts ty)
    = MkIClaimData rig vis (renameFnOpts opts) (renameImpTy ty)

  renameImpData : ImpData' a -> ImpData' b
  renameImpData (MkImpData fc n tycon opts datacons)
    = MkImpData fc n (renameMaybeRawImp tycon) opts (renameImpTys datacons)
  renameImpData (MkImpLater fc n tycon) = MkImpLater fc n (renameRawImp tycon)

  renameParameter : ImpParameter' (RawImp' a) -> ImpParameter' (RawImp' b)
  renameParameter (MkWithRigName rig n bind) = MkWithRigName rig n (renamePiBindData bind)

  renameParameters : List (ImpParameter' (RawImp' a)) -> List (ImpParameter' (RawImp' b))
  renameParameters [] = []
  renameParameters (p :: ps) = renameParameter p :: renameParameters ps

  renameParameters1 : List1 (ImpParameter' (RawImp' a)) -> List1 (ImpParameter' (RawImp' b))
  renameParameters1 (p ::: ps) = renameParameter p ::: renameParameters ps

  renameFields : List (IField' a) -> List (IField' b)
  renameFields [] = []
  renameFields (MkWithFCRigName fc rig n bind :: fields)
    = MkWithFCRigName fc rig n (renamePiBindData bind) :: renameFields fields

  renameImpRecord : ImpRecordData a -> ImpRecordData b
  renameImpRecord (MkImpRecord (MkWithName tyn params) (MkWithNameOpts con opts fields))
    = MkImpRecord (MkWithName tyn (renameParameters params))
                  (MkWithNameOpts con opts (renameFields fields))

  renameImpDecl : ImpDecl' a -> ImpDecl' b

  renameImpDecls : List (ImpDecl' a) -> List (ImpDecl' b)
  renameImpDecls [] = []
  renameImpDecls (d :: ds) = renameImpDecl d :: renameImpDecls ds

  renameImpDecl (IClaim (MkFCVal fc c)) = IClaim (MkFCVal fc (renameClaim c))
  renameImpDecl (IData fc vis mbtot dt) = IData fc vis mbtot (renameImpData dt)
  renameImpDecl (IDef fc nm cls) = IDef fc nm (renameImpClauses cls)
  renameImpDecl (IParameters fc ps ds)
    = IParameters fc (renameParameters1 ps) (renameImpDecls ds)
  renameImpDecl (IRecord fc cs vis mbtot (MkFCVal rfc rec))
    = IRecord fc cs vis mbtot (MkFCVal rfc (renameImpRecord rec))
  renameImpDecl (IFail fc msg ds) = IFail fc msg (renameImpDecls ds)
  renameImpDecl (INamespace fc ns ds) = INamespace fc ns (renameImpDecls ds)
  renameImpDecl (ITransform fc n lhs rhs)
    = ITransform fc n (renameRawImp lhs) (renameRawImp rhs)
  renameImpDecl (IPragma fc xs k) = IPragma fc xs k
  renameImpDecl (ILog x) = ILog x
  renameImpDecl (IBuiltin fc ty n) = IBuiltin fc ty n

  renameIFieldUpdate : IFieldUpdate' a -> IFieldUpdate' b
  renameIFieldUpdate (ISetField path t) = ISetField path (renameRawImp t)
  renameIFieldUpdate (ISetFieldApp path t) = ISetFieldApp path (renameRawImp t)

  renameIFieldUpdates : List (IFieldUpdate' a) -> List (IFieldUpdate' b)
  renameIFieldUpdates [] = []
  renameIFieldUpdates (upd :: upds) = renameIFieldUpdate upd :: renameIFieldUpdates upds

  renameAltType : AltType' a -> AltType' b
  renameAltType FirstSuccess = FirstSuccess
  renameAltType Unique = Unique
  renameAltType (UniqueDefault t) = UniqueDefault (renameRawImp t)

  renameOverlaid : Overlaid' a -> Overlaid' b
  renameOverlaid (PairOf l r) = PairOf (renameRawImp l) (renameRawImp r)
  renameOverlaid UnitOf = UnitOf
  renameOverlaid (DPairOf opFC nameFC n r) = DPairOf opFC nameFC n (renameRawImp r)

  renameRawImp (IVar fc nm) = IVar fc (f nm)
  renameRawImp (IPi fc rig info nm x sc)
    = IPi fc rig (renamePiInfo info) nm (renameRawImp x) (renameRawImp sc)
  renameRawImp (ILam fc rig info nm x sc)
    = ILam fc rig (renamePiInfo info) nm (renameRawImp x) (renameRawImp sc)
  renameRawImp (ILet fc lhsFC rig nm ty val sc)
    = ILet fc lhsFC rig nm (renameRawImp ty) (renameRawImp val) (renameRawImp sc)
  renameRawImp (ICase fc opts sc ty cls)
    = ICase fc (renameFnOpts opts) (renameRawImp sc) (renameRawImp ty) (renameImpClauses cls)
  renameRawImp (ILocal fc ds sc)
    = ILocal fc (renameImpDecls ds) (renameRawImp sc)
  renameRawImp (ICaseLocal fc userN intN args sc)
    = ICaseLocal fc userN intN args (renameRawImp sc)
  renameRawImp (IUpdate fc upds rec)
    = IUpdate fc (renameIFieldUpdates upds) (renameRawImp rec)
  renameRawImp (IApp fc fn t)
    = IApp fc (renameRawImp fn) (renameRawImp t)
  renameRawImp (IAutoApp fc fn t)
    = IAutoApp fc (renameRawImp fn) (renameRawImp t)
  renameRawImp (INamedApp fc fn nm t)
    = INamedApp fc (renameRawImp fn) nm (renameRawImp t)
  renameRawImp (IWithApp fc fn t)
    = IWithApp fc (renameRawImp fn) (renameRawImp t)
  renameRawImp (ISearch fc)
    = ISearch fc
  renameRawImp (IAlternative fc alt ts)
    = IAlternative fc (renameAltType alt) (renameRawImps ts)
  renameRawImp (ITypeOrValue fc ovl)
    = ITypeOrValue fc (renameOverlaid ovl)
  renameRawImp (IRewrite fc e t)
    = IRewrite fc (renameRawImp e) (renameRawImp t)
  renameRawImp (ICoerced fc e)
    = ICoerced fc (renameRawImp e)
  renameRawImp (IBindHere fc bd t)
    = IBindHere fc bd (renameRawImp t)
  renameRawImp (IBindVar fc str)
    = IBindVar fc str
  renameRawImp (IAs fc nmFC side nm t)
    = IAs fc nmFC side nm (renameRawImp t)
  renameRawImp (IMustUnify fc reason t)
    = IMustUnify fc reason (renameRawImp t)
  renameRawImp (IDelayed fc reason t)
    = IDelayed fc reason (renameRawImp t)
  renameRawImp (IDelay fc t)
    = IDelay fc (renameRawImp t)
  renameRawImp (IForce fc t)
    = IForce fc (renameRawImp t)
  renameRawImp (IQuote fc t)
    = IQuote fc (renameRawImp t)
  renameRawImp (IQuoteName fc nm)
    = IQuoteName fc nm
  renameRawImp (IQuoteDecl fc ds)
    = IQuoteDecl fc (renameImpDecls ds)
  renameRawImp (IUnquote fc t)
    = IUnquote fc (renameRawImp t)
  renameRawImp (IPrimVal fc c)
    = IPrimVal fc c
  renameRawImp (IType fc)
    = IType fc
  renameRawImp (IHole fc str)
    = IHole fc str
  renameRawImp (IUnifyLog fc lvl t)
    = IUnifyLog fc lvl (renameRawImp t)
  renameRawImp (Implicit fc bindIfUnsolved)
    = Implicit fc bindIfUnsolved
  renameRawImp (IWithUnambigNames fc ns t)
    = IWithUnambigNames fc ns (renameRawImp t)

export
Functor RawImp' where
  map = renameRawImp

export
Functor ImpClause' where
  map = renameImpClause

export
Functor IClaimData where
  map = renameClaim

export
Functor ImpDecl' where
  map = renameImpDecl

export
Functor FnOpt' where
  map = renameFnOpt

export
Functor ImpData' where
  map = renameImpData

export
Functor ImpRecordData where
  map = renameImpRecord

export
Functor IFieldUpdate' where
  map = renameIFieldUpdate

export
Functor AltType' where
  map = renameAltType

export
Functor Overlaid' where
  map = renameOverlaid
