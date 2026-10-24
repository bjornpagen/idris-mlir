-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Idris.Syntax.Traversals

import Idris.Syntax

import TTImp.TTImp

import Data.SnocList

%default total

-- Every list, option and wrapper the syntax holds terms in is walked by a
-- function of its own rather than by `map` or `traverse`, so that each
-- recursive call is on a part of the term it was given and each traversal
-- is total by its structure. The walkers of `mapPTermM` combine their parts
-- with `<*>`, so every part is walked and the first failure is the result.

export
mapPTermM : (PTerm' nm -> Core (PTerm' nm)) -> PTerm' nm -> Core (PTerm' nm)
mapPTermM f = goPTerm where

  mutual

    goPTerm : PTerm' nm -> Core (PTerm' nm)
    goPTerm t@(PRef {}) = f t
    goPTerm (NewPi (MkFCVal fc x)) =
      NewPi . MkFCVal fc <$> goPBinderScope x
    goPTerm (Forall (MkFCVal fc (ns, x))) =
      Forall . MkFCVal fc . MkPair ns <$> goPTerm x
    goPTerm (PPi fc x info z argTy retTy) =
      PPi fc x <$> goPiInfo info
               <*> pure z
               <*> goPTerm argTy
               <*> goPTerm retTy
      >>= f
    goPTerm (PLam fc x info pat argTy scope) =
      PLam fc x <$> goPiInfo info
                <*> goPTerm pat
                <*> goPTerm argTy
                <*> goPTerm scope
      >>= f
    goPTerm (PLet fc x pat nTy nVal scope alts) =
      PLet fc x <$> goPTerm pat
                <*> goPTerm nTy
                <*> goPTerm nVal
                <*> goPTerm scope
                <*> goPClauses alts
      >>= f
    goPTerm (PCase fc opts x xs) =
      PCase fc <$> goPFnOpts opts
               <*> goPTerm x
               <*> goPClauses xs
      >>= f
    goPTerm (PLocal fc xs scope) =
      PLocal fc <$> goPDecls xs
                <*> goPTerm scope
      >>= f
    goPTerm (PUpdate fc xs) =
      PUpdate fc <$> goPFieldUpdates xs
      >>= f
    goPTerm (PApp fc x y) =
      PApp fc <$> goPTerm x
              <*> goPTerm y
      >>= f
    goPTerm (PWithApp fc x y) =
      PWithApp fc <$> goPTerm x
                  <*> goPTerm y
      >>= f
    goPTerm (PAutoApp fc x y) =
      PAutoApp fc <$> goPTerm x
                         <*> goPTerm y
      >>= f
    goPTerm (PNamedApp fc x n y) =
      PNamedApp fc <$> goPTerm x
                   <*> pure n
                   <*> goPTerm y
      >>= f
    goPTerm (PDelayed fc x y) =
      PDelayed fc x <$> goPTerm y
      >>= f
    goPTerm (PDelay fc x) =
      PDelay fc <$> goPTerm x
      >>= f
    goPTerm (PForce fc x) =
      PForce fc <$> goPTerm x
      >>= f
    goPTerm t@(PSearch {}) = f t
    goPTerm t@(PPrimVal {}) = f t
    goPTerm (PQuote fc x) =
      PQuote fc <$> goPTerm x
      >>= f
    goPTerm t@(PQuoteName {}) = f t
    goPTerm (PQuoteDecl fc x) =
      PQuoteDecl fc <$> goPDecls x
      >>= f
    goPTerm (PUnquote fc x) =
      PUnquote fc <$> goPTerm x
      >>= f
      >>= f
    goPTerm t@(PHole {}) = f t
    goPTerm t@(PType {}) = f t
    goPTerm (PAs fc nameFC x pat) =
      PAs fc nameFC x <$> goPTerm pat
      >>= f
    goPTerm (PDotted fc x) =
      PDotted fc <$> goPTerm x
      >>= f
    goPTerm t@(PImplicit {}) = f t
    goPTerm t@(PInfer {}) = f t
    goPTerm (POp fc (MkFCVal lhsFC lhs) op right) =
      POp fc
          <$> (MkFCVal lhsFC <$> goOpBinder lhs)
          <*> pure op
          <*> goPTerm right
      >>= f
    goPTerm (PPrefixOp fc x y) =
      PPrefixOp fc x <$> goPTerm y
      >>= f
    goPTerm (PSectionL fc x y) =
      PSectionL fc x <$> goPTerm y
      >>= f
    goPTerm (PSectionR fc x y) =
      PSectionR fc <$> goPTerm x
                   <*> pure y
      >>= f
    goPTerm (PEq fc x y) =
      PEq fc <$> goPTerm x
             <*> goPTerm y
      >>= f
    goPTerm (PBracketed fc x) =
      PBracketed fc <$> goPTerm x
      >>= f
    goPTerm (PString fc x ys) =
      PString fc x <$> goPStrings ys
      >>= f
    goPTerm (PMultiline fc x y zs) =
      PMultiline fc x y <$> goPStringLines zs
      >>= f
    goPTerm (PDoBlock fc ns xs) =
      PDoBlock fc ns <$> goPDos xs
      >>= f
    goPTerm (PBang fc x) =
      PBang fc <$> goPTerm x
      >>= f
    goPTerm (PIdiom fc ns x) =
      PIdiom fc ns <$> goPTerm x
      >>= f
    goPTerm (PList fc nilFC xs) =
      PList fc nilFC <$> goTagged xs
      >>= f
    goPTerm (PSnocList fc nilFC xs) =
      PSnocList fc nilFC <$> goTaggedSnoc xs
      >>= f
    goPTerm (PPair fc x y) =
      PPair fc <$> goPTerm x
               <*> goPTerm y
      >>= f
    goPTerm (PDPair fc opFC x y z) =
      PDPair fc opFC
                <$> goPTerm x
                <*> goPTerm y
                <*> goPTerm z
      >>= f
    goPTerm t@(PUnit {}) = f t
    goPTerm (PIfThenElse fc x y z) =
      PIfThenElse fc <$> goPTerm x
                     <*> goPTerm y
                     <*> goPTerm z
      >>= f
    goPTerm (PComprehension fc x xs) =
      PComprehension fc <$> goPTerm x
                        <*> goPDos xs
      >>= f
    goPTerm (PRewrite fc x y) =
      PRewrite fc <$> goPTerm x
                  <*> goPTerm y
      >>= f
    goPTerm (PRange fc x y z) =
      PRange fc <$> goPTerm x
                <*> goMPTerm y
                <*> goPTerm z
      >>= f
    goPTerm (PRangeStream fc x y) =
      PRangeStream fc <$> goPTerm x
                      <*> goMPTerm y
      >>= f
    goPTerm (PUnifyLog fc k x) =
      PUnifyLog fc k <$> goPTerm x
      >>= f
    goPTerm (PPostfixApp fc rec fields) =
      PPostfixApp fc <$> goPTerm rec <*> pure fields
      >>= f
    goPTerm (PPostfixAppPartial fc fields) =
      f (PPostfixAppPartial fc fields)
    goPTerm (PWithUnambigNames fc ns rhs) =
      PWithUnambigNames fc ns <$> goPTerm rhs
      >>= f

    goOpBinder : OperatorLHSInfo (PTerm' nm) -> Core (OperatorLHSInfo (PTerm' nm))
    goOpBinder (NoBinder lhs) = NoBinder <$> goPTerm lhs
    goOpBinder (BindType name ty) = BindType <$> goPTerm name <*> goPTerm ty
    goOpBinder (BindExpr name expr) = BindExpr <$> goPTerm name <*> goPTerm expr
    goOpBinder (BindExplicitType name type expr)
      = BindExplicitType <$> goPTerm name <*> goPTerm type <*> goPTerm expr

    goPFieldUpdate : PFieldUpdate' nm -> Core (PFieldUpdate' nm)
    goPFieldUpdate (PSetField p t)    = PSetField p <$> goPTerm t
    goPFieldUpdate (PSetFieldApp p t) = PSetFieldApp p <$> goPTerm t

    goPStr : PStr' nm -> Core (PStr' nm)
    goPStr (StrInterp fc t) = StrInterp fc <$> goPTerm t
    goPStr x                = pure x

    goPDo : PDo' nm -> Core (PDo' nm)
    goPDo (DoExp fc t) = DoExp fc <$> goPTerm t
    goPDo (DoBind fc nameFC n c ty t) = DoBind fc nameFC n c <$> goMPTerm ty <*> goPTerm t
    goPDo (DoBindPat fc t ty u cls) =
      DoBindPat fc <$> goPTerm t
                   <*> goMPTerm ty
                   <*> goPTerm u
                   <*> goPClauses cls
    goPDo (DoLet fc lhsFC n c t scope) =
       DoLet fc lhsFC n c <$> goPTerm t
                          <*> goPTerm scope
    goPDo (DoLetPat fc pat t scope cls) =
       DoLetPat fc <$> goPTerm pat
                   <*> goPTerm t
                   <*> goPTerm scope
                   <*> goPClauses cls
    goPDo (DoLetLocal fc decls) = DoLetLocal fc <$> goPDecls decls
    goPDo (DoRewrite fc t) = DoRewrite fc <$> goPTerm t

    goPClause : PClause' nm -> Core (PClause' nm)
    goPClause (MkPatClause fc lhs rhs wh) =
      MkPatClause fc <$> goPTerm lhs
                     <*> goPTerm rhs
                     <*> goPDecls wh
    goPClause (MkWithClause fc lhs wps flags cls) =
      MkWithClause fc <$> goPTerm lhs
                      <*> goPWithProblems1 wps
                      <*> pure flags
                      <*> goPClauses cls
    goPClause (MkImpossible fc lhs) = MkImpossible fc <$> goPTerm lhs

    goPWithProblem : PWithProblem' nm -> Core (PWithProblem' nm)
    goPWithProblem (MkPWithProblem rig wval mnm)
      = MkPWithProblem rig <$> goPTerm wval <*> pure mnm

    goPClaim : PClaimData' nm -> Core (PClaimData' nm)
    goPClaim (MkPClaim c v opts (MkFCVal fc tdecl)) =
      MkPClaim c v <$> goPFnOpts opts
                   <*> (MkFCVal fc <$> goPTypeDecl tdecl)

    goBasicMultiBinder : BasicMultiBinder' nm -> Core (BasicMultiBinder' nm)
    goBasicMultiBinder (MkBasicMultiBinder rig names type)
      = MkBasicMultiBinder rig names <$> goPTerm type

    goPBinder : PBinder' nm -> Core (PBinder' nm)
    goPBinder (MkPBinder info bind)
      = MkPBinder <$> goPiInfo info <*> goBasicMultiBinder bind

    goPlainBinder : PlainBinder' nm -> Core (PlainBinder' nm)
    goPlainBinder (MkWithName n t) = MkWithName n <$> goPTerm t

    goPBinderScope : PBinderScope' nm -> Core (PBinderScope' nm)
    goPBinderScope (MkPBinderScope binder scope)
      = MkPBinderScope <$> goPBinder binder <*> goPTerm scope

    goPDecl : PDeclNoFC' nm -> Core (PDeclNoFC' nm)
    goPDecl (PClaim claim) =
      PClaim <$> goPClaim claim
    goPDecl (PDef cls) = PDef <$> goPClauses cls
    goPDecl (PData doc v mbt d) = PData doc v mbt <$> goPDataDecl d
    goPDecl (PParameters (Left nts) ps) =
      PParameters . Left <$> goPlainBinders1 nts
                         <*> goPDecls ps
    goPDecl (PParameters (Right nts) ps) =
      PParameters . Right <$> goPBinders1 nts
                          <*> goPDecls ps
    goPDecl (PUsing mnts ps) =
      PUsing <$> goTagged mnts
             <*> goPDecls ps
    goPDecl (PInterface v mnts n doc nrts ns mn ps) =
      PInterface v <$> goTagged mnts
                   <*> pure n
                   <*> pure doc
                   <*> goBasicMultiBinders nrts
                   <*> pure ns
                   <*> pure mn
                   <*> goPDecls ps
    goPDecl (PImplementation v opts p is cs n ts mn ns mps) =
      PImplementation v opts p <$> goImplicits is
                               <*> goTagged cs
                               <*> pure n
                               <*> goPTerms ts
                               <*> pure mn
                               <*> pure ns
                               <*> goMPDecls mps
    goPDecl (PRecord doc v tot (MkPRecord n nts opts mn fs)) =
      pure $ PRecord doc v tot !(MkPRecord n <$> goPBinders nts
                                             <*> pure opts
                                             <*> pure mn
                                             <*> goPFields fs)
    goPDecl (PRecord doc v tot (MkPRecordLater n nts)) =
      pure $ PRecord doc v tot (MkPRecordLater n !(goPBinders nts))
    goPDecl (PFail msg ps) = PFail msg <$> goPDecls ps
    goPDecl (PMutual ps) = PMutual <$> goPDecls ps
    goPDecl (PFixity p) = pure (PFixity p)
    goPDecl (PNamespace strs ps) = PNamespace strs <$> goPDecls ps
    goPDecl (PTransform n a b) = PTransform n <$> goPTerm a <*> goPTerm b
    goPDecl (PDirective d) = pure (PDirective d)
    goPDecl p@(PBuiltin {}) = pure p

    goPTypeDecl : PTypeDeclData' nm -> Core (PTypeDeclData' nm)
    goPTypeDecl (MkPTy n d t) = MkPTy n d <$> goPTerm t

    goPDataDecl : PDataDecl' nm -> Core (PDataDecl' nm)
    goPDataDecl (MkPData fc n t opts tdecls) =
      MkPData fc n <$> goMPTerm t
                   <*> pure opts
                   <*> goPTypeDecls tdecls
    goPDataDecl (MkPLater fc n t) = MkPLater fc n <$> goPTerm t

    goPiInfo : PiInfo (PTerm' nm) -> Core (PiInfo (PTerm' nm))
    goPiInfo (DefImplicit t) = DefImplicit <$> goPTerm t
    goPiInfo t = pure t

    goPiBindData : PiBindData (PTerm' nm) -> Core (PiBindData (PTerm' nm))
    goPiBindData (MkPiBindData info ty)
      = MkPiBindData <$> goPiInfo info <*> goPTerm ty

    goPFnOpt : PFnOpt' nm -> Core (PFnOpt' nm)
    goPFnOpt o@(IFnOpt {}) = pure o
    goPFnOpt (PForeign ts) = PForeign <$> goPTerms ts

    goMPTerm : Maybe (PTerm' nm) -> Core (Maybe $ PTerm' nm)
    goMPTerm Nothing  = pure Nothing
    goMPTerm (Just t) = Just <$> goPTerm t

    goPTerms : List (PTerm' nm) -> Core (List $ PTerm' nm)
    goPTerms []        = pure []
    goPTerms (t :: ts) = (::) <$> goPTerm t <*> goPTerms ts

    goTagged : List (a, PTerm' nm) -> Core (List (a, PTerm' nm))
    goTagged [] = pure []
    goTagged ((l, t) :: ts) = (::) . MkPair l <$> goPTerm t <*> goTagged ts

    goTaggedSnoc : SnocList (a, PTerm' nm) -> Core (SnocList (a, PTerm' nm))
    goTaggedSnoc [<] = pure [<]
    goTaggedSnoc (ts :< (l, t)) = (:<) <$> goTaggedSnoc ts <*> (MkPair l <$> goPTerm t)

    goPStringLines : List (List (PStr' nm)) -> Core (List (List (PStr' nm)))
    goPStringLines []        = pure []
    goPStringLines (line :: lines) = (::) <$> goPStrings line <*> goPStringLines lines

    goPStrings : List (PStr' nm) -> Core (List (PStr' nm))
    goPStrings []        = pure []
    goPStrings (str :: strs) = (::) <$> goPStr str <*> goPStrings strs

    goPDos : List (PDo' nm) -> Core (List (PDo' nm))
    goPDos []        = pure []
    goPDos (d :: ds) = (::) <$> goPDo d <*> goPDos ds

    goPClauses : List (PClause' nm) -> Core (List (PClause' nm))
    goPClauses []          = pure []
    goPClauses (cl :: cls) = (::) <$> goPClause cl <*> goPClauses cls

    goPWithProblems1 : List1 (PWithProblem' nm) -> Core (List1 (PWithProblem' nm))
    goPWithProblems1 (w ::: ws) = (:::) <$> goPWithProblem w <*> goPWithProblems ws

    goPWithProblems : List (PWithProblem' nm) -> Core (List (PWithProblem' nm))
    goPWithProblems []        = pure []
    goPWithProblems (w :: ws) = (::) <$> goPWithProblem w <*> goPWithProblems ws

    goMPDecls : Maybe (List (PDecl' nm)) -> Core (Maybe (List (PDecl' nm)))
    goMPDecls Nothing   = pure Nothing
    goMPDecls (Just ps) = Just <$> goPDecls ps

    goPDecls : List (PDecl' nm) -> Core (List (PDecl' nm))
    goPDecls []          = pure []
    goPDecls (MkFCVal fc d :: ds) = (::) . MkFCVal fc <$> goPDecl d <*> goPDecls ds

    goPFieldUpdates : List (PFieldUpdate' nm) -> Core (List (PFieldUpdate' nm))
    goPFieldUpdates []          = pure []
    goPFieldUpdates (fu :: fus) = (::) <$> goPFieldUpdate fu <*> goPFieldUpdates fus

    goPFields : List (PField' nm) -> Core (List (PField' nm))
    goPFields [] = pure []
    goPFields (MkWithFCDocRigNames fc d r ns b :: fs)
      = (::) . MkWithFCDocRigNames fc d r ns <$> goPiBindData b <*> goPFields fs

    goImplicits : List (WithFCRigName (PiBindData (PTerm' nm))) ->
                  Core (List (WithFCRigName (PiBindData (PTerm' nm))))
    goImplicits [] = pure []
    goImplicits (MkWithFCRigName fc r n b :: is)
      = (::) . MkWithFCRigName fc r n <$> goPiBindData b <*> goImplicits is

    goPFnOpts : List (PFnOpt' nm) -> Core (List (PFnOpt' nm))
    goPFnOpts []        = pure []
    goPFnOpts (o :: os) = (::) <$> goPFnOpt o <*> goPFnOpts os

    goPTypeDecls : List (PTypeDecl' nm) -> Core (List (PTypeDecl' nm))
    goPTypeDecls []        = pure []
    goPTypeDecls (MkFCVal fc t :: ts) = (::) . MkFCVal fc <$> goPTypeDecl t <*> goPTypeDecls ts

    goBasicMultiBinders : List (BasicMultiBinder' nm) -> Core (List (BasicMultiBinder' nm))
    goBasicMultiBinders []        = pure []
    goBasicMultiBinders (b :: bs) = (::) <$> goBasicMultiBinder b <*> goBasicMultiBinders bs

    goPBinders1 : List1 (PBinder' nm) -> Core (List1 (PBinder' nm))
    goPBinders1 (b ::: bs) = (:::) <$> goPBinder b <*> goPBinders bs

    goPBinders : List (PBinder' nm) -> Core (List (PBinder' nm))
    goPBinders []        = pure []
    goPBinders (b :: bs) = (::) <$> goPBinder b <*> goPBinders bs

    goPlainBinders1 : List1 (PlainBinder' nm) -> Core (List1 (PlainBinder' nm))
    goPlainBinders1 (b ::: bs) = (:::) <$> goPlainBinder b <*> goPlainBinders bs

    goPlainBinders : List (PlainBinder' nm) -> Core (List (PlainBinder' nm))
    goPlainBinders []        = pure []
    goPlainBinders (b :: bs) = (::) <$> goPlainBinder b <*> goPlainBinders bs

export
mapPTerm : (PTerm' nm -> PTerm' nm) -> PTerm' nm -> PTerm' nm
mapPTerm f = goPTerm where

  mutual

    goPTerm : PTerm' nm -> PTerm' nm
    goPTerm t@(PRef {}) = f t
    goPTerm (Forall binderScope)
      = Forall (map (mapSnd f) binderScope)
    goPTerm (NewPi (MkFCVal fc binderScope))
      = NewPi (MkFCVal fc (goPBinderScope binderScope))
    goPTerm (PPi fc x info z argTy retTy)
      = f $ PPi fc x (goPiInfo info) z (goPTerm argTy) (goPTerm retTy)
    goPTerm (PLam fc x info z argTy scope)
      = f $ PLam fc x (goPiInfo info) z (goPTerm argTy) (goPTerm scope)
    goPTerm (PLet fc x pat nTy nVal scope alts)
      = f $ PLet fc x (goPTerm pat) (goPTerm nTy) (goPTerm nVal) (goPTerm scope) (goPClauses alts)
    goPTerm (PCase fc opts x xs)
      = f $ PCase fc (goPFnOpts opts) (goPTerm x) (goPClauses xs)
    goPTerm (PLocal fc xs scope)
      = f $ PLocal fc (goPDecls xs) (goPTerm scope)
    goPTerm (PUpdate fc xs)
      = f $ PUpdate fc (goPFieldUpdates xs)
    goPTerm (PApp fc x y)
      = f $ PApp fc (goPTerm x) (goPTerm y)
    goPTerm (PWithApp fc x y)
      = f $ PWithApp fc (goPTerm x) (goPTerm y)
    goPTerm (PAutoApp fc x y)
      = f $ PAutoApp fc (goPTerm x) (goPTerm y)
    goPTerm (PNamedApp fc x n y)
      = f $ PNamedApp fc (goPTerm x) n (goPTerm y)
    goPTerm (PDelayed fc x y)
      = f $ PDelayed fc x (goPTerm y)
    goPTerm (PDelay fc x)
      = f $ PDelay fc $ goPTerm x
    goPTerm (PForce fc x)
      = f $ PForce fc $ goPTerm x
    goPTerm t@(PSearch {}) = f t
    goPTerm t@(PPrimVal {}) = f t
    goPTerm (PQuote fc x)
      = f $ PQuote fc $ goPTerm x
    goPTerm t@(PQuoteName {}) = f t
    goPTerm (PQuoteDecl fc x)
      = f $ PQuoteDecl fc (goPDecls x)
    goPTerm (PUnquote fc x)
      = f $ PUnquote fc $ goPTerm x
    goPTerm t@(PHole {}) = f t
    goPTerm t@(PType {}) = f t
    goPTerm (PAs fc nameFC x pat)
      = f $ PAs fc nameFC x $ goPTerm pat
    goPTerm (PDotted fc x)
      = f $ PDotted fc $ goPTerm x
    goPTerm t@(PImplicit {}) = f t
    goPTerm t@(PInfer {}) = f t
    goPTerm (POp fc autoBindInfo opName z)
      = f $ POp fc (map (map f) autoBindInfo) opName (goPTerm z)
    goPTerm (PPrefixOp fc x y)
      = f $ PPrefixOp fc x $ goPTerm y
    goPTerm (PSectionL fc x y)
      = f $ PSectionL fc x $ goPTerm y
    goPTerm (PSectionR fc x y)
      = f $ PSectionR fc (goPTerm x) y
    goPTerm (PEq fc x y)
      = f $ PEq fc (goPTerm x) (goPTerm y)
    goPTerm (PBracketed fc x)
      = f $ PBracketed fc $ goPTerm x
    goPTerm (PString fc x ys)
      = f $ PString fc x $ goPStrings ys
    goPTerm (PMultiline fc x y zs)
      = f $  PMultiline fc x y $ goPStringLines zs
    goPTerm (PDoBlock fc ns xs)
      = f $ PDoBlock fc ns $ goPDos xs
    goPTerm (PBang fc x)
      = f $ PBang fc $ goPTerm x
    goPTerm (PIdiom fc ns x)
      = f $ PIdiom fc ns $ goPTerm x
    goPTerm (PList fc nilFC xs)
      = f $ PList fc nilFC $ goTagged xs
    goPTerm (PSnocList fc nilFC xs)
      = f $ PSnocList fc nilFC $ goTaggedSnoc xs
    goPTerm (PPair fc x y)
      = f $ PPair fc (goPTerm x) (goPTerm y)
    goPTerm (PDPair fc opFC x y z)
      = f $ PDPair fc opFC (goPTerm x) (goPTerm y) (goPTerm z)
    goPTerm t@(PUnit {}) = f t
    goPTerm (PIfThenElse fc x y z)
      = f $ PIfThenElse fc (goPTerm x) (goPTerm y) (goPTerm z)
    goPTerm (PComprehension fc x xs)
      = f $ PComprehension fc (goPTerm x) (goPDos xs)
    goPTerm (PRewrite fc x y)
      = f $ PRewrite fc (goPTerm x) (goPTerm y)
    goPTerm (PRange fc x y z)
      = f $ PRange fc (goPTerm x) (goMPTerm y) (goPTerm z)
    goPTerm (PRangeStream fc x y)
      = f $ PRangeStream fc (goPTerm x) (goMPTerm y)
    goPTerm (PUnifyLog fc k x)
      = f $ PUnifyLog fc k (goPTerm x)
    goPTerm (PPostfixApp fc rec fields)
      = f $ PPostfixApp fc (goPTerm rec) fields
    goPTerm t@(PPostfixAppPartial fc fields) = f t
    goPTerm (PWithUnambigNames fc ns rhs)
      = f $ PWithUnambigNames fc ns (goPTerm rhs)

    goPFieldUpdate : PFieldUpdate' nm -> PFieldUpdate' nm
    goPFieldUpdate (PSetField p t)    = PSetField p $ goPTerm t
    goPFieldUpdate (PSetFieldApp p t) = PSetFieldApp p $ goPTerm t

    goPStr : PStr' nm -> PStr' nm
    goPStr (StrInterp fc t) = StrInterp fc $ goPTerm t
    goPStr x                = x

    goPDo : PDo' nm -> PDo' nm
    goPDo (DoExp fc t) = DoExp fc $ goPTerm t
    goPDo (DoBind fc nameFC n c ty t) = DoBind fc nameFC n c (goMPTerm ty) (goPTerm t)
    goPDo (DoBindPat fc t ty u cls)
      = DoBindPat fc (goPTerm t) (goMPTerm ty) (goPTerm u) (goPClauses cls)
    goPDo (DoLet fc lhsFC n c t scope)
      = DoLet fc lhsFC n c (goPTerm t) (goPTerm scope)
    goPDo (DoLetPat fc pat t scope cls)
      = DoLetPat fc (goPTerm pat) (goPTerm t) (goPTerm scope) (goPClauses cls)
    goPDo (DoLetLocal fc decls) = DoLetLocal fc $ goPDecls decls
    goPDo (DoRewrite fc t) = DoRewrite fc $ goPTerm t

    goPWithProblem : PWithProblem' nm -> PWithProblem' nm
    goPWithProblem (MkPWithProblem rig wval mnm)= MkPWithProblem rig (goPTerm wval) mnm

    goPClause : PClause' nm -> PClause' nm
    goPClause (MkPatClause fc lhs rhs wh)
      = MkPatClause fc (goPTerm lhs) (goPTerm rhs) (goPDecls wh)
    goPClause (MkWithClause fc lhs wps flags cls)
      = MkWithClause fc (goPTerm lhs) (goPWithProblems1 wps) flags (goPClauses cls)
    goPClause (MkImpossible fc lhs) = MkImpossible fc $ goPTerm lhs

    goPClaim : PClaimData' nm -> PClaimData' nm
    goPClaim (MkPClaim c v opts (MkFCVal fc tdecl))
      = MkPClaim c v (goPFnOpts opts) (MkFCVal fc (goPTypeDecl tdecl))

    goPBinderScope : PBinderScope' nm -> PBinderScope' nm
    goPBinderScope (MkPBinderScope binder scope)
      = MkPBinderScope (goPBinder binder) (goPTerm scope)

    goPDecl : PDeclNoFC' nm -> PDeclNoFC' nm
    goPDecl (PClaim claim)
      = PClaim $ goPClaim claim
    goPDecl (PDef cls) = PDef $ goPClauses cls
    goPDecl (PData doc v mbt d) = PData doc v mbt $ goPDataDecl d
    goPDecl (PParameters (Left nts) ps)
      = PParameters (Left (goPlainBinders1 nts)) (goPDecls ps)
    goPDecl (PParameters (Right nts) ps)
      = PParameters (Right (goPBinders1 nts)) (goPDecls ps)
    goPDecl (PUsing mnts ps)
      = PUsing (goTagged mnts) (goPDecls ps)
    goPDecl (PInterface v mnts n doc nrts ns mn ps)
      = PInterface v (goTagged mnts) n doc (goBasicMultiBinders nrts) ns mn (goPDecls ps)
    goPDecl (PImplementation v opts p is cs n ts mn ns mps)
      = PImplementation v opts p (goImplicits is) (goTagged cs)
           n (goPTerms ts) mn ns (goMPDecls mps)
    goPDecl (PRecord doc v tot (MkPRecord n nts opts mn fs))
      = PRecord doc v tot
          (MkPRecord n (goPBinders nts) opts mn (goPFields fs))
    goPDecl (PRecord doc v tot (MkPRecordLater n nts))
      = PRecord doc v tot (MkPRecordLater n (goPBinders nts))
    goPDecl (PFail msg ps) = PFail msg $ goPDecls ps
    goPDecl (PMutual ps) = PMutual $ goPDecls ps
    goPDecl (PFixity p) = PFixity p
    goPDecl (PNamespace strs ps) = PNamespace strs $ goPDecls ps
    goPDecl (PTransform n a b) = PTransform n (goPTerm a) (goPTerm b)
    goPDecl (PDirective d) = PDirective d
    goPDecl p@(PBuiltin {}) = p

    goPBinder : PBinder' nm -> PBinder' nm
    goPBinder (MkPBinder info bind) = MkPBinder (goPiInfo info) (goBasicMultiBinder bind)

    goPlainBinder : PlainBinder' nm -> PlainBinder' nm
    goPlainBinder (MkWithName n t) = MkWithName n (goPTerm t)

    goBasicMultiBinder : BasicMultiBinder' nm -> BasicMultiBinder' nm
    goBasicMultiBinder (MkBasicMultiBinder rig names type)
      = MkBasicMultiBinder rig names (goPTerm type)

    goPTypeDecl : PTypeDeclData' nm -> PTypeDeclData' nm
    goPTypeDecl (MkPTy n d t) = MkPTy n d $ goPTerm t

    goPDataDecl : PDataDecl' nm -> PDataDecl' nm
    goPDataDecl (MkPData fc n t opts tdecls)
      = MkPData fc n (goMPTerm t) opts (goPTypeDecls tdecls)
    goPDataDecl (MkPLater fc n t) = MkPLater fc n $ goPTerm t

    goPiInfo : PiInfo (PTerm' nm) -> PiInfo (PTerm' nm)
    goPiInfo (DefImplicit t) = DefImplicit $ goPTerm t
    goPiInfo t = t

    goPiBindData : PiBindData (PTerm' nm) -> PiBindData (PTerm' nm)
    goPiBindData (MkPiBindData info ty) = MkPiBindData (goPiInfo info) (goPTerm ty)

    goPFnOpt : PFnOpt' nm -> PFnOpt' nm
    goPFnOpt o@(IFnOpt {}) = o
    goPFnOpt (PForeign ts) = PForeign $ goPTerms ts

    goMPTerm : Maybe (PTerm' nm) -> Maybe (PTerm' nm)
    goMPTerm Nothing  = Nothing
    goMPTerm (Just t) = Just (goPTerm t)

    goPTerms : List (PTerm' nm) -> List (PTerm' nm)
    goPTerms []        = []
    goPTerms (t :: ts) = goPTerm t :: goPTerms ts

    goTagged : List (a, PTerm' nm) -> List (a, PTerm' nm)
    goTagged [] = []
    goTagged ((l, t) :: ts) = (l, goPTerm t) :: goTagged ts

    goTaggedSnoc : SnocList (a, PTerm' nm) -> SnocList (a, PTerm' nm)
    goTaggedSnoc [<] = [<]
    goTaggedSnoc (ts :< (l, t)) = goTaggedSnoc ts :< (l, goPTerm t)

    goPStringLines : List (List (PStr' nm)) -> List (List (PStr' nm))
    goPStringLines []              = []
    goPStringLines (line :: lines) = goPStrings line :: goPStringLines lines

    goPStrings : List (PStr' nm) -> List (PStr' nm)
    goPStrings []            = []
    goPStrings (str :: strs) = goPStr str :: goPStrings strs

    goPDos : List (PDo' nm) -> List (PDo' nm)
    goPDos []        = []
    goPDos (d :: ds) = goPDo d :: goPDos ds

    goPClauses : List (PClause' nm) -> List (PClause' nm)
    goPClauses []          = []
    goPClauses (cl :: cls) = goPClause cl :: goPClauses cls

    goPWithProblems1 : List1 (PWithProblem' nm) -> List1 (PWithProblem' nm)
    goPWithProblems1 (w ::: ws) = goPWithProblem w ::: goPWithProblems ws

    goPWithProblems : List (PWithProblem' nm) -> List (PWithProblem' nm)
    goPWithProblems []        = []
    goPWithProblems (w :: ws) = goPWithProblem w :: goPWithProblems ws

    goMPDecls : Maybe (List (PDecl' nm)) -> Maybe (List (PDecl' nm))
    goMPDecls Nothing   = Nothing
    goMPDecls (Just ps) = Just (goPDecls ps)

    goPDecls : List (PDecl' nm) -> List (PDecl' nm)
    goPDecls []                   = []
    goPDecls (MkFCVal fc d :: ds) = MkFCVal fc (goPDecl d) :: goPDecls ds

    goPFieldUpdates : List (PFieldUpdate' nm) -> List (PFieldUpdate' nm)
    goPFieldUpdates []          = []
    goPFieldUpdates (fu :: fus) = goPFieldUpdate fu :: goPFieldUpdates fus

    goPFields : List (PField' nm) -> List (PField' nm)
    goPFields [] = []
    goPFields (MkWithFCDocRigNames fc d r ns b :: fs)
      = MkWithFCDocRigNames fc d r ns (goPiBindData b) :: goPFields fs

    goImplicits : List (WithFCRigName (PiBindData (PTerm' nm))) ->
                  List (WithFCRigName (PiBindData (PTerm' nm)))
    goImplicits [] = []
    goImplicits (MkWithFCRigName fc r n b :: is)
      = MkWithFCRigName fc r n (goPiBindData b) :: goImplicits is

    goPFnOpts : List (PFnOpt' nm) -> List (PFnOpt' nm)
    goPFnOpts []        = []
    goPFnOpts (o :: os) = goPFnOpt o :: goPFnOpts os

    goPTypeDecls : List (PTypeDecl' nm) -> List (PTypeDecl' nm)
    goPTypeDecls []                   = []
    goPTypeDecls (MkFCVal fc t :: ts) = MkFCVal fc (goPTypeDecl t) :: goPTypeDecls ts

    goBasicMultiBinders : List (BasicMultiBinder' nm) -> List (BasicMultiBinder' nm)
    goBasicMultiBinders []        = []
    goBasicMultiBinders (b :: bs) = goBasicMultiBinder b :: goBasicMultiBinders bs

    goPBinders1 : List1 (PBinder' nm) -> List1 (PBinder' nm)
    goPBinders1 (b ::: bs) = goPBinder b ::: goPBinders bs

    goPBinders : List (PBinder' nm) -> List (PBinder' nm)
    goPBinders []        = []
    goPBinders (b :: bs) = goPBinder b :: goPBinders bs

    goPlainBinders1 : List1 (PlainBinder' nm) -> List1 (PlainBinder' nm)
    goPlainBinders1 (b ::: bs) = goPlainBinder b ::: goPlainBinders bs

    goPlainBinders : List (PlainBinder' nm) -> List (PlainBinder' nm)
    goPlainBinders []        = []
    goPlainBinders (b :: bs) = goPlainBinder b :: goPlainBinders bs

||| Replace the FCs in a term with the one provided.
||| The current implementation is not correct: we're only substituting
||| in PTerm but it should be enough for our purposes (making sure the
||| ellipsis used in a with clause's LHS refers to the correct line).
export
substFC : FC -> PTerm' nm -> PTerm' nm
substFC fc = mapPTerm $ \case
  PRef _ x => PRef fc x
  NewPi x => NewPi (setFC fc x)
  Forall x => Forall (setFC fc x)
  PPi _ x y z argTy retTy => PPi fc x y z argTy retTy
  PLam _ x y pat argTy scope => PLam fc x y pat argTy scope
  PLet _ x pat nTy nVal scope alts => PLet fc x pat nTy nVal scope alts
  PCase _ opts x xs => PCase fc opts x xs
  PLocal _ xs scope => PLocal fc xs scope
  PUpdate _ xs => PUpdate fc xs
  PApp _ x y => PApp fc x y
  PWithApp _ x y => PWithApp fc x y
  PNamedApp _ x n y => PNamedApp fc x n y
  PAutoApp _ x y => PAutoApp fc x y
  PDelayed _ x y => PDelayed fc x y
  PDelay _ x => PDelay fc x
  PForce _ x => PForce fc x
  PSearch _ => PSearch fc
  PPrimVal _ x => PPrimVal fc x
  PQuote _ x => PQuote fc x
  PQuoteName _ n => PQuoteName fc n
  PQuoteDecl _ xs => PQuoteDecl fc xs
  PUnquote _ x => PUnquote fc x
  PHole _ holename => PHole fc holename
  PType _ => PType fc
  PAs _ _ n pattern => PAs fc fc n pattern
  PDotted _ x => PDotted fc x
  PImplicit _ => PImplicit fc
  PInfer _ => PInfer fc
  POp _ ab nm r => POp fc (setFC fc ab) nm r
  PPrefixOp _ x y => PPrefixOp fc (setFC fc x) y
  PSectionL _ x y => PSectionL fc (setFC fc x) y
  PSectionR _ x y => PSectionR fc x (setFC fc y)
  PEq _ x y => PEq fc x y
  PBracketed _ x => PBracketed fc x
  PString _ x ys => PString fc x ys
  PMultiline _ x y zs => PMultiline fc x y zs
  PDoBlock _ x xs => PDoBlock fc x xs
  PBang _ x => PBang fc x
  PIdiom _ x y => PIdiom fc x y
  PList _ _ xs => PList fc fc xs
  PSnocList _ _ sx => PSnocList fc fc sx
  PPair _ x y => PPair fc x y
  PDPair _ _ x y z => PDPair fc fc x y z
  PUnit _ => PUnit fc
  PIfThenElse _ x y z => PIfThenElse fc x y z
  PComprehension _ x xs => PComprehension fc x xs
  PRewrite _ x y => PRewrite fc x y
  PRange _ x y z => PRange fc x y z
  PRangeStream _ x y => PRangeStream fc x y
  PPostfixApp _ x xs => PPostfixApp fc x xs
  PPostfixAppPartial _ xs => PPostfixAppPartial fc xs
  PUnifyLog _ x y => PUnifyLog fc x y
  PWithUnambigNames _ xs x => PWithUnambigNames fc xs x
