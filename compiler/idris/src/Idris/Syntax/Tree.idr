-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2026 Bjorn Pagen
||| The parse tree: what the parser makes of a source, as columns, and the
||| syntax it decodes to.
|||
||| The parser makes a node for each form it parses, its children made
||| before it, each node holding its location, its children's ids and how
||| many nodes its unfolding has. A subtree the grammar uses twice (a data
||| type's return type in each of its constructors, a tuple section's
||| variable in its lambda and in its pair) is one node with two parents, so
||| the tree is a graph without cycles, and every child unfolds to fewer
||| nodes than its parent. The nodes are made in the parse's state, so a
||| branch that fails drops the nodes it made with the rest of what it made.
||| Once the parse is done the nodes are frozen into columns read by
||| position, and decoding them gives the terms, clauses and declarations
||| the rest of the compiler reads.
module Idris.Syntax.Tree

import Idris.Syntax
import Idris.Syntax.Traversals
import TTImp.TTImp

import Array

import Control.WellFounded
import Data.DPair
import Data.List
import Data.List1
import Data.Maybe
import Data.Nat
import Data.So

import Libraries.Data.WithDefault

%default total

-- Core's own monad functions are hidden: every applicative and monadic step
-- here is an interface's, at the type the step is taken in.
%hide Core.Core.(>>=)
%hide Core.Core.(>>)
%hide Core.Core.pure
%hide Core.Core.(<*>)
%hide Core.Core.traverse
%hide Core.Core.map

------------------------------------------------------------------------------
-- Forms
------------------------------------------------------------------------------

||| The syntax a node of the parse tree stands for.
public export
data Form
  = FTerm | FClause | FDecl | FDo | FStr | FUpdate | FOpt | FData | FRecord
  | FTyDecl | FField | FWith | FNames | FBinder | FPlain | FImplicit

||| What a node of each form decodes to.
public export
Decoded : Form -> Type
Decoded FTerm = PTerm
Decoded FClause = PClause
Decoded FDecl = PDecl
Decoded FDo = PDo
Decoded FStr = PStr
Decoded FUpdate = PFieldUpdate
Decoded FOpt = PFnOpt
Decoded FData = PDataDecl
Decoded FRecord = PRecordDecl' Name
Decoded FTyDecl = PTypeDecl
Decoded FField = PField
Decoded FWith = PWithProblem
Decoded FNames = BasicMultiBinder
Decoded FBinder = PBinder
Decoded FPlain = PlainBinder
Decoded FImplicit = WithFCRigName (PiBindData PTerm)

||| A node a parse has made, of the form its rule gives: its place among
||| the nodes made, and how many nodes it unfolds to, which is what its
||| parent's count adds up.
export
record Id (x : Form) where
  constructor MkId
  place : Nat
  size : Nat

||| A node of a frozen tree of `n` nodes, of the form it stands for.
export
record Within (n : Nat) (x : Form) where
  constructor At
  pos : Fin n

------------------------------------------------------------------------------
-- Nodes
------------------------------------------------------------------------------

||| A declaration without its location, each child the node of its form.
public export
data DeclOf : (Form -> Type) -> Type where
  DcClaim : RigCount -> Visibility -> List (c FOpt) -> c FTyDecl -> DeclOf c
  DcDef : List (c FClause) -> DeclOf c
  DcData : (doc : String) -> WithDefault Visibility Private -> Maybe TotalReq ->
           c FData -> DeclOf c
  DcParameters : Either (List1 (c FPlain)) (List1 (c FBinder)) -> List (c FDecl) ->
                 DeclOf c
  DcUsing : List (Maybe Name, c FTerm) -> List (c FDecl) -> DeclOf c
  DcInterface : WithDefault Visibility Private ->
                (constraints : List (Maybe Name, c FTerm)) -> Name -> (doc : String) ->
                (params : List (c FNames)) -> (det : Maybe (List1 Name)) ->
                (conName : Maybe (WithDocFC Name)) -> List (c FDecl) -> DeclOf c
  DcImplementation : Visibility -> List (c FOpt) -> Pass ->
                     (implicits : List (c FImplicit)) ->
                     (constraints : List (Maybe Name, c FTerm)) -> Name ->
                     (params : List (c FTerm)) -> (implName : Maybe Name) ->
                     (nusing : List Name) -> Maybe (List (c FDecl)) -> DeclOf c
  DcRecord : (doc : String) -> WithDefault Visibility Private -> Maybe TotalReq ->
             c FRecord -> DeclOf c
  DcFail : Maybe String -> List (c FDecl) -> DeclOf c
  DcMutual : List (c FDecl) -> DeclOf c
  DcFixity : PFixityData -> DeclOf c
  DcNamespace : Namespace -> List (c FDecl) -> DeclOf c
  DcTransform : String -> c FTerm -> c FTerm -> DeclOf c
  DcRunElab : c FTerm -> DeclOf c
  DcDirective : Directive' (c FTerm) -> DeclOf c
  DcBuiltin : BuiltinType -> Name -> DeclOf c

||| A node of the parse tree, each child the node of its form: an id while
||| the tree is made, a position once it is frozen. Each form of the syntax
||| the parser writes is a node, which decodes to its constructor; a
||| declaration's lists of declarations decode to the definitions their
||| neighbouring clauses make.
public export
data NodeOf : (Form -> Type) -> Type where
  -- Terms
  TmRef : FC -> Name -> NodeOf c
  TmNewPi : FC -> c FBinder -> (scope : c FTerm) -> NodeOf c
  TmForall : FC -> List1 (WithFC Name) -> (scope : c FTerm) -> NodeOf c
  TmPi : FC -> RigCount -> PiInfo (c FTerm) -> Maybe Name ->
         (argTy : c FTerm) -> (retTy : c FTerm) -> NodeOf c
  TmLam : FC -> RigCount -> PiInfo (c FTerm) -> (pat : c FTerm) ->
          (argTy : c FTerm) -> (scope : c FTerm) -> NodeOf c
  TmLet : FC -> RigCount -> (pat : c FTerm) -> (nTy : c FTerm) -> (nVal : c FTerm) ->
          (scope : c FTerm) -> (alts : List (c FClause)) -> NodeOf c
  TmCase : FC -> List (c FOpt) -> c FTerm -> List (c FClause) -> NodeOf c
  ||| A `let`'s local declarations, a block of them for each run its
  ||| bindings do not break.
  TmLocal : FC -> List (List (c FDecl)) -> (scope : c FTerm) -> NodeOf c
  TmUpdate : FC -> List (c FUpdate) -> NodeOf c
  TmApp : FC -> c FTerm -> c FTerm -> NodeOf c
  TmWithApp : FC -> c FTerm -> c FTerm -> NodeOf c
  TmNamedApp : FC -> c FTerm -> Name -> c FTerm -> NodeOf c
  TmAutoApp : FC -> c FTerm -> c FTerm -> NodeOf c
  TmDelayed : FC -> LazyReason -> c FTerm -> NodeOf c
  TmDelay : FC -> c FTerm -> NodeOf c
  TmForce : FC -> c FTerm -> NodeOf c
  TmSearch : FC -> NodeOf c
  TmPrimVal : FC -> Constant -> NodeOf c
  TmQuote : FC -> c FTerm -> NodeOf c
  TmQuoteName : FC -> Name -> NodeOf c
  TmQuoteDecl : FC -> List (c FDecl) -> NodeOf c
  TmUnquote : FC -> c FTerm -> NodeOf c
  TmRunElab : FC -> c FTerm -> NodeOf c
  TmHole : FC -> (bracket : Bool) -> (holename : Ident) -> NodeOf c
  TmType : FC -> NodeOf c
  TmAs : FC -> (nameFC : FC) -> Name -> (pattern : c FTerm) -> NodeOf c
  TmDotted : FC -> c FTerm -> NodeOf c
  TmImplicit : FC -> NodeOf c
  TmInfer : FC -> NodeOf c
  TmOp : (full : FC) -> WithFC (OperatorLHSInfo (c FTerm)) -> WithFC OpStr ->
         (rhs : c FTerm) -> NodeOf c
  TmPrefixOp : (full : FC) -> WithFC OpStr -> c FTerm -> NodeOf c
  TmSectionL : (full : FC) -> WithFC OpStr -> c FTerm -> NodeOf c
  TmSectionR : (full : FC) -> c FTerm -> WithFC OpStr -> NodeOf c
  TmBracketed : FC -> c FTerm -> NodeOf c
  TmString : FC -> (hashtag : Nat) -> List (c FStr) -> NodeOf c
  TmMultiline : FC -> (hashtag : Nat) -> (indent : Nat) -> List (List (c FStr)) -> NodeOf c
  TmDoBlock : FC -> Maybe Namespace -> List (c FDo) -> NodeOf c
  TmBang : FC -> c FTerm -> NodeOf c
  TmIdiom : FC -> Maybe Namespace -> c FTerm -> NodeOf c
  TmList : (full, nilFC : FC) -> List (FC, c FTerm) -> NodeOf c
  TmSnocList : (full, nilFC : FC) -> SnocList (FC, c FTerm) -> NodeOf c
  TmPair : FC -> c FTerm -> c FTerm -> NodeOf c
  TmDPair : (full, opFC : FC) -> c FTerm -> c FTerm -> c FTerm -> NodeOf c
  TmUnit : FC -> NodeOf c
  TmIfThenElse : FC -> c FTerm -> c FTerm -> c FTerm -> NodeOf c
  TmComprehension : FC -> c FTerm -> List (c FDo) -> NodeOf c
  TmRewrite : FC -> c FTerm -> c FTerm -> NodeOf c
  TmRange : FC -> c FTerm -> Maybe (c FTerm) -> c FTerm -> NodeOf c
  TmRangeStream : FC -> c FTerm -> Maybe (c FTerm) -> NodeOf c
  TmPostfixApp : FC -> c FTerm -> List (FC, Name) -> NodeOf c
  TmPostfixAppPartial : FC -> List (FC, Name) -> NodeOf c
  TmUnifyLog : FC -> LogLevel -> c FTerm -> NodeOf c
  TmWithNames : FC -> List (FC, Name) -> c FTerm -> NodeOf c
  ||| A term with every location in it the one given: the left side of a
  ||| `with` clause written `_`, which is its parent's, where the `_` is.
  TmRelocated : FC -> c FTerm -> NodeOf c
  -- Clauses
  ClPattern : FC -> (lhs : c FTerm) -> (rhs : c FTerm) -> (whereblock : List (c FDecl)) ->
              NodeOf c
  ClWith : FC -> (lhs : c FTerm) -> List1 (c FWith) -> List WithFlag -> List (c FClause) ->
           NodeOf c
  ClImpossible : FC -> (lhs : c FTerm) -> NodeOf c
  -- Declarations
  Declared : FC -> DeclOf c -> NodeOf c
  -- Statements of a `do` block
  StExp : FC -> c FTerm -> NodeOf c
  StBind : FC -> (nameFC : FC) -> Name -> RigCount -> Maybe (c FTerm) -> c FTerm -> NodeOf c
  StBindPat : FC -> c FTerm -> Maybe (c FTerm) -> c FTerm -> List (c FClause) -> NodeOf c
  ||| A `let` binding: of a variable or a pattern, as its pattern decodes.
  StLet : FC -> RigCount -> (pat : c FTerm) -> (ty : c FTerm) -> (val : c FTerm) ->
          (alts : List (c FClause)) -> NodeOf c
  StLetLocal : FC -> List (List (c FDecl)) -> NodeOf c
  StRewrite : FC -> c FTerm -> NodeOf c
  -- Pieces of a string
  PcLiteral : FC -> String -> NodeOf c
  PcInterp : FC -> c FTerm -> NodeOf c
  -- Updates of a record's fields
  UpSet : (path : List Ident) -> c FTerm -> NodeOf c
  UpApply : (path : List Ident) -> c FTerm -> NodeOf c
  -- A function's options
  OpFn : FnOpt' Name -> NodeOf c
  OpForeign : List (c FTerm) -> NodeOf c
  OpForeignExport : List (c FTerm) -> NodeOf c
  -- The bodies of data and record declarations
  DtBody : FC -> (tyname : Name) -> (tycon : Maybe (c FTerm)) -> (opts : List DataOpt) ->
           (datacons : List (c FTyDecl)) -> NodeOf c
  DtLater : FC -> (tyname : Name) -> (tycon : c FTerm) -> NodeOf c
  RcBody : (tyname : Name) -> (params : List (c FBinder)) -> (opts : List DataOpt) ->
           (conName : Maybe (WithDocFC Name)) -> (decls : List (c FField)) -> NodeOf c
  RcLater : (tyname : Name) -> (params : List (c FBinder)) -> NodeOf c
  -- Type declarations, a record's fields and a `with` clause's problems
  TyClaim : FC -> List1 (String, WithFC Name) -> (doc : String) -> (type : c FTerm) ->
            NodeOf c
  FdField : FC -> (doc : String) -> RigCount -> List (WithFC Name) -> PiInfo (c FTerm) ->
            (type : c FTerm) -> NodeOf c
  WpValue : RigCount -> (value : c FTerm) -> (proof : Maybe (RigCount, Name)) -> NodeOf c
  -- Binders
  BnNames : RigCount -> List1 (WithFC Name) -> (type : c FTerm) -> NodeOf c
  BnPi : PiInfo (c FTerm) -> c FNames -> NodeOf c
  BnPlain : WithFC Name -> (type : c FTerm) -> NodeOf c
  BnImplicit : FC -> RigCount -> WithFC Name -> PiInfo (c FTerm) -> (type : c FTerm) ->
               NodeOf c

||| A node of a frozen tree of `n` nodes.
public export
Node : Nat -> Type
Node n = NodeOf (Within n)

------------------------------------------------------------------------------
-- Children
------------------------------------------------------------------------------

traverseLHS : Applicative f => (a -> f b) -> OperatorLHSInfo a -> f (OperatorLHSInfo b)
traverseLHS g (NoBinder l) = NoBinder <$> g l
traverseLHS g (BindType n ty) = BindType <$> g n <*> g ty
traverseLHS g (BindExpr n e) = BindExpr <$> g n <*> g e
traverseLHS g (BindExplicitType n ty e) = BindExplicitType <$> g n <*> g ty <*> g e

traverseLocated : Applicative f => (a -> f b) -> List (FC, a) -> f (List (FC, b))
traverseLocated g = traverse (\(fc, x) => MkPair fc <$> g x)

traverseSnocLocated : Applicative f => (a -> f b) -> SnocList (FC, a) -> f (SnocList (FC, b))
traverseSnocLocated g [<] = pure [<]
traverseSnocLocated g (xs :< (fc, x)) = (\ys, y => ys :< (fc, y)) <$> traverseSnocLocated g xs <*> g x

traverseNamed : Applicative f => (a -> f b) -> List (Maybe Name, a) -> f (List (Maybe Name, b))
traverseNamed g = traverse (\(n, x) => MkPair n <$> g x)

-- Every child of a declaration, each changed by `g` at its form.
traverseDecl : Applicative m => ({0 x : Form} -> src x -> m (dst x)) -> DeclOf src -> m (DeclOf dst)
traverseDecl g (DcClaim rig vis opts ty) = DcClaim rig vis <$> traverse g opts <*> g ty
traverseDecl g (DcDef cs) = DcDef <$> traverse g cs
traverseDecl g (DcData doc vis tot d) = DcData doc vis tot <$> g d
traverseDecl g (DcParameters (Left ps) ds)
    = (\ps', ds' => DcParameters (Left ps') ds') <$> traverse g ps <*> traverse g ds
traverseDecl g (DcParameters (Right ps) ds)
    = (\ps', ds' => DcParameters (Right ps') ds') <$> traverse g ps <*> traverse g ds
traverseDecl g (DcUsing us ds) = DcUsing <$> traverseNamed g us <*> traverse g ds
traverseDecl g (DcInterface vis cons n doc ps det con ds)
    = (\cons', ps', ds' => DcInterface vis cons' n doc ps' det con ds')
        <$> traverseNamed g cons <*> traverse g ps <*> traverse g ds
traverseDecl g (DcImplementation vis opts pass imps cons n ps iname nusing body)
    = (\opts', imps', cons', ps', body' =>
          DcImplementation vis opts' pass imps' cons' n ps' iname nusing body')
        <$> traverse g opts <*> traverse g imps <*> traverseNamed g cons
        <*> traverse g ps <*> traverse (traverse g) body
traverseDecl g (DcRecord doc vis tot r) = DcRecord doc vis tot <$> g r
traverseDecl g (DcFail msg ds) = DcFail msg <$> traverse g ds
traverseDecl g (DcMutual ds) = DcMutual <$> traverse g ds
traverseDecl g (DcFixity fx) = pure (DcFixity fx)
traverseDecl g (DcNamespace ns ds) = DcNamespace ns <$> traverse g ds
traverseDecl g (DcTransform n l r) = DcTransform n <$> g l <*> g r
traverseDecl g (DcRunElab e) = DcRunElab <$> g e
traverseDecl g (DcDirective d) = DcDirective <$> traverseDirective g d
traverseDecl g (DcBuiltin ty n) = pure (DcBuiltin ty n)

-- Every child of a node, each changed by `g` at its form.
traverseNode : Applicative m => ({0 x : Form} -> src x -> m (dst x)) -> NodeOf src -> m (NodeOf dst)
traverseNode g (TmRef fc n) = pure (TmRef fc n)
traverseNode g (TmNewPi fc b sc) = TmNewPi fc <$> g b <*> g sc
traverseNode g (TmForall fc ns sc) = TmForall fc ns <$> g sc
traverseNode g (TmPi fc rig p n a r) = TmPi fc rig <$> traverse g p <*> pure n <*> g a <*> g r
traverseNode g (TmLam fc rig p pat a sc)
    = TmLam fc rig <$> traverse g p <*> g pat <*> g a <*> g sc
traverseNode g (TmLet fc rig pat ty val sc alts)
    = TmLet fc rig <$> g pat <*> g ty <*> g val <*> g sc <*> traverse g alts
traverseNode g (TmCase fc opts scr alts)
    = TmCase fc <$> traverse g opts <*> g scr <*> traverse g alts
traverseNode g (TmLocal fc dss sc) = TmLocal fc <$> traverse (traverse g) dss <*> g sc
traverseNode g (TmUpdate fc us) = TmUpdate fc <$> traverse g us
traverseNode g (TmApp fc f a) = TmApp fc <$> g f <*> g a
traverseNode g (TmWithApp fc f a) = TmWithApp fc <$> g f <*> g a
traverseNode g (TmNamedApp fc f n a) = (\f', a' => TmNamedApp fc f' n a') <$> g f <*> g a
traverseNode g (TmAutoApp fc f a) = TmAutoApp fc <$> g f <*> g a
traverseNode g (TmDelayed fc r e) = TmDelayed fc r <$> g e
traverseNode g (TmDelay fc e) = TmDelay fc <$> g e
traverseNode g (TmForce fc e) = TmForce fc <$> g e
traverseNode g (TmSearch fc) = pure (TmSearch fc)
traverseNode g (TmPrimVal fc k) = pure (TmPrimVal fc k)
traverseNode g (TmQuote fc e) = TmQuote fc <$> g e
traverseNode g (TmQuoteName fc n) = pure (TmQuoteName fc n)
traverseNode g (TmQuoteDecl fc ds) = TmQuoteDecl fc <$> traverse g ds
traverseNode g (TmUnquote fc e) = TmUnquote fc <$> g e
traverseNode g (TmRunElab fc e) = TmRunElab fc <$> g e
traverseNode g (TmHole fc b n) = pure (TmHole fc b n)
traverseNode g (TmType fc) = pure (TmType fc)
traverseNode g (TmAs fc nfc n e) = TmAs fc nfc n <$> g e
traverseNode g (TmDotted fc e) = TmDotted fc <$> g e
traverseNode g (TmImplicit fc) = pure (TmImplicit fc)
traverseNode g (TmInfer fc) = pure (TmInfer fc)
traverseNode g (TmOp fc (MkWithData lfc l) op r)
    = (\l', r' => TmOp fc (MkWithData lfc l') op r') <$> traverseLHS g l <*> g r
traverseNode g (TmPrefixOp fc op e) = TmPrefixOp fc op <$> g e
traverseNode g (TmSectionL fc op e) = TmSectionL fc op <$> g e
traverseNode g (TmSectionR fc e op) = (\e' => TmSectionR fc e' op) <$> g e
traverseNode g (TmBracketed fc e) = TmBracketed fc <$> g e
traverseNode g (TmString fc h ps) = TmString fc h <$> traverse g ps
traverseNode g (TmMultiline fc h i ls) = TmMultiline fc h i <$> traverse (traverse g) ls
traverseNode g (TmDoBlock fc ns ss) = TmDoBlock fc ns <$> traverse g ss
traverseNode g (TmBang fc e) = TmBang fc <$> g e
traverseNode g (TmIdiom fc ns e) = TmIdiom fc ns <$> g e
traverseNode g (TmList fc nfc xs) = TmList fc nfc <$> traverseLocated g xs
traverseNode g (TmSnocList fc nfc xs) = TmSnocList fc nfc <$> traverseSnocLocated g xs
traverseNode g (TmPair fc l r) = TmPair fc <$> g l <*> g r
traverseNode g (TmDPair fc opfc l ty r) = TmDPair fc opfc <$> g l <*> g ty <*> g r
traverseNode g (TmUnit fc) = pure (TmUnit fc)
traverseNode g (TmIfThenElse fc c t e) = TmIfThenElse fc <$> g c <*> g t <*> g e
traverseNode g (TmComprehension fc e ss) = TmComprehension fc <$> g e <*> traverse g ss
traverseNode g (TmRewrite fc r e) = TmRewrite fc <$> g r <*> g e
traverseNode g (TmRange fc x y z) = TmRange fc <$> g x <*> traverse g y <*> g z
traverseNode g (TmRangeStream fc x y) = TmRangeStream fc <$> g x <*> traverse g y
traverseNode g (TmPostfixApp fc e ps) = (\e' => TmPostfixApp fc e' ps) <$> g e
traverseNode g (TmPostfixAppPartial fc ps) = pure (TmPostfixAppPartial fc ps)
traverseNode g (TmUnifyLog fc lvl e) = TmUnifyLog fc lvl <$> g e
traverseNode g (TmWithNames fc ns e) = TmWithNames fc ns <$> g e
traverseNode g (TmRelocated fc e) = TmRelocated fc <$> g e
traverseNode g (ClPattern fc l r ws) = ClPattern fc <$> g l <*> g r <*> traverse g ws
traverseNode g (ClWith fc l wps flags cs)
    = (\l', wps', cs' => ClWith fc l' wps' flags cs')
        <$> g l <*> traverse g wps <*> traverse g cs
traverseNode g (ClImpossible fc l) = ClImpossible fc <$> g l
traverseNode g (Declared fc d) = Declared fc <$> traverseDecl g d
traverseNode g (StExp fc e) = StExp fc <$> g e
traverseNode g (StBind fc nfc n rig ty v) = StBind fc nfc n rig <$> traverse g ty <*> g v
traverseNode g (StBindPat fc p ty v alts)
    = StBindPat fc <$> g p <*> traverse g ty <*> g v <*> traverse g alts
traverseNode g (StLet fc rig p ty v alts)
    = StLet fc rig <$> g p <*> g ty <*> g v <*> traverse g alts
traverseNode g (StLetLocal fc dss) = StLetLocal fc <$> traverse (traverse g) dss
traverseNode g (StRewrite fc e) = StRewrite fc <$> g e
traverseNode g (PcLiteral fc s) = pure (PcLiteral fc s)
traverseNode g (PcInterp fc e) = PcInterp fc <$> g e
traverseNode g (UpSet path e) = UpSet path <$> g e
traverseNode g (UpApply path e) = UpApply path <$> g e
traverseNode g (OpFn o) = pure (OpFn o)
traverseNode g (OpForeign es) = OpForeign <$> traverse g es
traverseNode g (OpForeignExport es) = OpForeignExport <$> traverse g es
traverseNode g (DtBody fc n ty opts cons)
    = (\ty', cons' => DtBody fc n ty' opts cons') <$> traverse g ty <*> traverse g cons
traverseNode g (DtLater fc n ty) = DtLater fc n <$> g ty
traverseNode g (RcBody n ps opts con fs)
    = (\ps', fs' => RcBody n ps' opts con fs') <$> traverse g ps <*> traverse g fs
traverseNode g (RcLater n ps) = RcLater n <$> traverse g ps
traverseNode g (TyClaim fc ns doc ty) = TyClaim fc ns doc <$> g ty
traverseNode g (FdField fc doc rig ns p ty) = FdField fc doc rig ns <$> traverse g p <*> g ty
traverseNode g (WpValue rig v prf) = (\v' => WpValue rig v' prf) <$> g v
traverseNode g (BnNames rig ns ty) = BnNames rig ns <$> g ty
traverseNode g (BnPi p b) = BnPi <$> traverse g p <*> g b
traverseNode g (BnPlain n ty) = BnPlain n <$> g ty
traverseNode g (BnImplicit fc rig n p ty) = BnImplicit fc rig n <$> traverse g p <*> g ty

-- A count of nodes: the applicative that adds the counts of the parts and
-- builds nothing of them.
data Count : Type -> Type where
  Counting : Nat -> Count a

counted : Count a -> Nat
counted (Counting n) = n

Functor Count where
  map _ (Counting n) = Counting n

Applicative Count where
  pure _ = Counting Z
  Counting m <*> Counting n = Counting (m + n)

-- How many nodes a node unfolds to: itself, and what each child unfolds to.
unfolding : NodeOf Id -> Nat
unfolding nd = S (counted (traverseNode {src = Id} {dst = Id} (\i => Counting i.size) nd))

------------------------------------------------------------------------------
-- Columns
------------------------------------------------------------------------------

-- A column being built: its cells in the order they were added, its length
-- in its type.
data Growing : Nat -> Type -> Type where
  NoCells : Growing Z a
  AddCell : Growing n a -> a -> Growing (S n) a

-- A column's cells in the order they were added, and that there are `k` of
-- them, which only the type says.
cells : Growing k a -> Subset (List a) (\xs => length xs = k)
cells col = let Element xs same = after col [] in
                Element xs (trans same (plusZeroRightNeutral k))
  where
    after : Growing j a -> (acc : List a) -> Subset (List a) (\xs => length xs = j + length acc)
    after NoCells acc = Element acc Refl
    after {j = S i} (AddCell col x) acc
        = let Element xs same = after col (x :: acc) in
              Element xs (trans same (sym (plusSuccRightSucc i (length acc))))

-- A column frozen, its cells in the order they were added.
column : Growing k a -> Vector k a
column col = let Element xs same = cells col in
                 replace {p = \m => Vector m a} same (Array.fromList xs)

-- Every node's children as positions among `n` nodes, when each is one.
bounded : (n : Nat) -> Growing k (NodeOf Id) -> Maybe (Growing k (Node n))
bounded n NoCells = Just NoCells
bounded n (AddCell col nd)
    = AddCell <$> bounded n col
           <*> traverseNode {src = Id} {dst = Within n} (\i => At <$> checkIndex n i.place) nd

------------------------------------------------------------------------------
-- Making the tree
------------------------------------------------------------------------------

||| The nodes a parse has made so far, in the order it made them, and how
||| many nodes each unfolds to.
export
record Builder where
  constructor MkBuilder
  made : Nat
  built : Growing made (NodeOf Id)
  sizes : Growing made Nat

||| No nodes made.
export
noNodes : Builder
noNodes = MkBuilder Z NoCells NoCells

||| A step of making the parse tree.
export
record Build (a : Type) where
  constructor MkBuild
  step : Builder -> (Builder, a)

||| A step of making the parse tree taken on the nodes made so far.
export
runBuild : Build a -> Builder -> (Builder, a)
runBuild b = step b

export
Functor Build where
  map f (MkBuild g) = MkBuild (\b => let (b', x) = g b in (b', f x))

export
Applicative Build where
  pure x = MkBuild (\b => (b, x))
  MkBuild f <*> MkBuild g
      = MkBuild (\b => let (b1, h) = f b
                           (b2, x) = g b1 in
                           (b2, h x))

export
Monad Build where
  MkBuild g >>= k = MkBuild (\b => let (b1, x) = g b in step (k x) b1)

||| A node made of what its rule parsed, each child made before it: its id,
||| at the form its rule gives.
export
make : NodeOf Id -> Build (Id x)
make nd
    = MkBuild $ \(MkBuilder made built sizes) =>
        let size = unfolding nd in
        (MkBuilder (S made) (AddCell built nd) (AddCell sizes size), MkId made size)

||| A hole written as an argument is bracketed. The argument is the node made
||| last, so the hole's node is replaced where it is.
export
bracketHole : Id FTerm -> Build ()
bracketHole i = MkBuild (\b => (bracketLast b, ()))
  where
    bracketLast : Builder -> Builder
    bracketLast b@(MkBuilder made (AddCell col (TmHole fc _ n)) sizes)
        = if S i.place == made then MkBuilder made (AddCell col (TmHole fc True n)) sizes else b
    bracketLast b = b

||| Where `_` is written, if the node made last is the given one and is `_`.
export
implicitAt : Id FTerm -> Build (Maybe FC)
implicitAt i = MkBuild (\b => (b, lastImplicit b))
  where
    lastImplicit : Builder -> Maybe FC
    lastImplicit (MkBuilder made (AddCell _ (TmImplicit fc)) _)
        = if S i.place == made then Just fc else Nothing
    lastImplicit _ = Nothing

||| The names of the holes a parse wrote, in the order it wrote them, read
||| from its hole nodes.
export
holesWritten : Builder -> List Ident
holesWritten (MkBuilder _ built _)
    = let Element nds _ = cells built in mapMaybe holeName nds
  where
    holeName : NodeOf Id -> Maybe Ident
    holeName (TmHole _ _ n) = Just n
    holeName _ = Nothing

------------------------------------------------------------------------------
-- The frozen tree
------------------------------------------------------------------------------

||| A parse's nodes frozen into columns: each node, its children positions
||| among them; and how many nodes each unfolds to.
export
record ParseTree where
  constructor MkParseTree
  nodeCount : Nat
  nodes : Vector nodeCount (Node nodeCount)
  sizes : Vector nodeCount Nat

||| The tree a parse made, frozen. Nothing when a node's child is not among
||| the nodes made, which making a child before its parent makes impossible.
export
frozenTree : Builder -> Maybe ParseTree
frozenTree (MkBuilder made built sizes)
    = (\nds => MkParseTree made (column nds) (column sizes)) <$> bounded made built

||| What a grammar gives: the syntax it parsed, read off the frozen tree.
public export
Read : Type -> Type
Read a = ParseTree -> Maybe a

nodeAt : (t : ParseTree) -> Fin (nodeCount t) -> Node (nodeCount t)
nodeAt t i = t.nodes !! [<i]

sizeAt : (t : ParseTree) -> Fin (nodeCount t) -> Nat
sizeAt t i = t.sizes !! [<i]

------------------------------------------------------------------------------
-- Decoding
------------------------------------------------------------------------------

-- All the clauses get parsed as one-clause definitions. Collect any
-- neighbouring clauses into one definition. This might mean merging two
-- functions which are different, if there are forward declarations,
-- but we'll split them in Desugar.idr. We can't do this when parsing,
-- because we haven't resolved operator precedences yet.
collectDefs : List PDecl -> List PDecl
collectDefs [] = []
collectDefs (def@(MkWithData _ (PDef cs)) :: ds)
    = let (csWithFC, rest) = spanBy isPDef ds
          cs' = cs ++ concat (map (.val) csWithFC)
          annot' = foldr {t=List}
                   (\fc1, fc2 => fromMaybe EmptyFC (mergeFC fc1 fc2))
                   def.fc
                   (map (.fc) csWithFC)
      in
          MkFCVal annot' (PDef cs') :: assert_total (collectDefs rest)
collectDefs (MkWithData annot (PNamespace ns nds) :: ds)
    = MkWithData annot (PNamespace ns (collectDefs nds)) :: collectDefs ds
collectDefs (MkWithData fc (PMutual nds) :: ds)
    = MkWithData fc (PMutual (collectDefs nds)) :: collectDefs ds
collectDefs (d :: ds)
    = d :: collectDefs ds

-- A `let` in a `do` block binds a variable where its pattern is one, and
-- matches its pattern otherwise.
letBound : FC -> RigCount -> PTerm -> PTerm -> PTerm -> List PClause -> PDo
letBound fc rig (PRef fc' (UN un)) ty val []
    = if isPatternVariable un
         then DoLet fc fc' (UN un) rig ty val
         else DoLetPat fc (PRef fc' (UN un)) ty val []
letBound fc rig (PImplicit fc') ty val [] = DoLet fc fc' (UN Underscore) rig ty val
letBound fc rig pat ty val alts = DoLetPat fc pat ty val alts

-- Decoding is a recursion over how many nodes the node being decoded
-- unfolds to. Each child unfolds to fewer than its parent, which is decided
-- as the child is reached (`child`), so the recursion descends a measure. A
-- tree the parser made breaks neither that nor the forms of its children; a
-- tree that does is no syntax, and decodes to nothing.
mutual
  child : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) -> (x : Form) ->
        Within (nodeCount t) x -> Maybe (Decoded x)
  child t m (Access rec) x (At c)
      = let mc = sizeAt t c in
        case choose (mc < m) of
             Left lt => decodeAs t mc (rec mc (ltOpReflectsLT mc m lt)) x (nodeAt t c)
             Right _ => Nothing

  decodeAs : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) -> (x : Form) ->
             Node (nodeCount t) -> Maybe (Decoded x)
  decodeAs t m acc FTerm nd = decodeTerm t m acc nd
  decodeAs t m acc FClause nd = decodeClause t m acc nd
  decodeAs t m acc FDecl nd = decodeDecl t m acc nd
  decodeAs t m acc FDo nd = decodeStatement t m acc nd
  decodeAs t m acc FStr nd = decodePiece t m acc nd
  decodeAs t m acc FUpdate nd = decodeUpdate t m acc nd
  decodeAs t m acc FOpt nd = decodeOpt t m acc nd
  decodeAs t m acc FData nd = decodeData t m acc nd
  decodeAs t m acc FRecord nd = decodeRecord t m acc nd
  decodeAs t m acc FTyDecl nd = decodeTyClaim t m acc nd
  decodeAs t m acc FField nd = decodeField t m acc nd
  decodeAs t m acc FWith nd = decodeWith t m acc nd
  decodeAs t m acc FNames nd = decodeNames t m acc nd
  decodeAs t m acc FBinder nd = decodeBinder t m acc nd
  decodeAs t m acc FPlain nd = decodePlain t m acc nd
  decodeAs t m acc FImplicit nd = decodeImplicit t m acc nd

  children : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) -> (x : Form) ->
         List (Within (nodeCount t) x) -> Maybe (List (Decoded x))
  children t m acc x [] = Just []
  children t m acc x (c :: cs) = (::) <$> child t m acc x c <*> children t m acc x cs

  children1 : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) -> (x : Form) ->
          List1 (Within (nodeCount t) x) -> Maybe (List1 (Decoded x))
  children1 t m acc x (c ::: cs) = (:::) <$> child t m acc x c <*> children t m acc x cs

  optChild : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) -> (x : Form) ->
           Maybe (Within (nodeCount t) x) -> Maybe (Maybe (Decoded x))
  optChild t m acc x Nothing = Just Nothing
  optChild t m acc x (Just c) = Just <$> child t m acc x c

  locatedChildren : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
            List (FC, Within (nodeCount t) FTerm) -> Maybe (List (FC, PTerm))
  locatedChildren t m acc [] = Just []
  locatedChildren t m acc ((fc, c) :: cs)
      = (\e, es => (fc, e) :: es) <$> child t m acc FTerm c <*> locatedChildren t m acc cs

  snocChildren : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
                SnocList (FC, Within (nodeCount t) FTerm) -> Maybe (SnocList (FC, PTerm))
  snocChildren t m acc [<] = Just [<]
  snocChildren t m acc (cs :< (fc, c))
      = (\es, e => es :< (fc, e)) <$> snocChildren t m acc cs <*> child t m acc FTerm c

  namedChildren : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
          List (Maybe Name, Within (nodeCount t) FTerm) -> Maybe (List (Maybe Name, PTerm))
  namedChildren t m acc [] = Just []
  namedChildren t m acc ((n, c) :: cs)
      = (\e, es => (n, e) :: es) <$> child t m acc FTerm c <*> namedChildren t m acc cs

  piChild : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
           PiInfo (Within (nodeCount t) FTerm) -> Maybe (PiInfo PTerm)
  piChild t m acc Implicit = Just Implicit
  piChild t m acc Explicit = Just Explicit
  piChild t m acc AutoImplicit = Just AutoImplicit
  piChild t m acc (DefImplicit c) = DefImplicit <$> child t m acc FTerm c

  lhsChild : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
            OperatorLHSInfo (Within (nodeCount t) FTerm) -> Maybe (OperatorLHSInfo PTerm)
  lhsChild t m acc (NoBinder l) = NoBinder <$> child t m acc FTerm l
  lhsChild t m acc (BindType n ty)
      = BindType <$> child t m acc FTerm n <*> child t m acc FTerm ty
  lhsChild t m acc (BindExpr n e)
      = BindExpr <$> child t m acc FTerm n <*> child t m acc FTerm e
  lhsChild t m acc (BindExplicitType n ty e)
      = BindExplicitType <$> child t m acc FTerm n <*> child t m acc FTerm ty
                         <*> child t m acc FTerm e

  -- A block of declarations, each run of neighbouring clauses one
  -- definition.
  declBlock : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
              List (Within (nodeCount t) FDecl) -> Maybe (List PDecl)
  declBlock t m acc ds = collectDefs <$> children t m acc FDecl ds

  -- A `let`'s local declarations: its blocks in turn, each collected on its
  -- own.
  declBlocks : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
               List (List (Within (nodeCount t) FDecl)) -> Maybe (List PDecl)
  declBlocks t m acc [] = Just []
  declBlocks t m acc (ds :: dss) = (++) <$> declBlock t m acc ds <*> declBlocks t m acc dss

  stringLines : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
             List (List (Within (nodeCount t) FStr)) -> Maybe (List (List PStr))
  stringLines t m acc [] = Just []
  stringLines t m acc (l :: ls) = (::) <$> children t m acc FStr l <*> stringLines t m acc ls

  directiveOf : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
              Directive' (Within (nodeCount t) FTerm) -> Maybe Directive
  directiveOf t m acc (StartExpr e) = StartExpr <$> child t m acc FTerm e
  -- Every other directive holds no term, so traversing it decodes nothing.
  directiveOf t m acc d = traverseDirective (const Nothing) d

  decodeTerm : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
         Node (nodeCount t) -> Maybe PTerm
  decodeTerm t m acc (TmRef fc n) = Just (PRef fc n)
  decodeTerm t m acc (TmNewPi fc b sc)
      = (\b', sc' => NewPi (MkFCVal fc (MkPBinderScope b' sc')))
          <$> child t m acc FBinder b <*> child t m acc FTerm sc
  decodeTerm t m acc (TmForall fc ns sc)
      = (\sc' => Forall (MkFCVal fc (ns, sc'))) <$> child t m acc FTerm sc
  decodeTerm t m acc (TmPi fc rig p n a r)
      = (\p', a', r' => PPi fc rig p' n a' r')
          <$> piChild t m acc p <*> child t m acc FTerm a <*> child t m acc FTerm r
  decodeTerm t m acc (TmLam fc rig p pat a sc)
      = PLam fc rig <$> piChild t m acc p <*> child t m acc FTerm pat
                    <*> child t m acc FTerm a <*> child t m acc FTerm sc
  decodeTerm t m acc (TmLet fc rig pat ty val sc alts)
      = PLet fc rig <$> child t m acc FTerm pat <*> child t m acc FTerm ty
                    <*> child t m acc FTerm val <*> child t m acc FTerm sc
                    <*> children t m acc FClause alts
  decodeTerm t m acc (TmCase fc opts scr alts)
      = PCase fc <$> children t m acc FOpt opts <*> child t m acc FTerm scr
                 <*> children t m acc FClause alts
  decodeTerm t m acc (TmLocal fc dss sc)
      = PLocal fc <$> declBlocks t m acc dss <*> child t m acc FTerm sc
  decodeTerm t m acc (TmUpdate fc us) = PUpdate fc <$> children t m acc FUpdate us
  decodeTerm t m acc (TmApp fc f a) = PApp fc <$> child t m acc FTerm f <*> child t m acc FTerm a
  decodeTerm t m acc (TmWithApp fc f a)
      = PWithApp fc <$> child t m acc FTerm f <*> child t m acc FTerm a
  decodeTerm t m acc (TmNamedApp fc f n a)
      = (\f', a' => PNamedApp fc f' n a') <$> child t m acc FTerm f <*> child t m acc FTerm a
  decodeTerm t m acc (TmAutoApp fc f a)
      = PAutoApp fc <$> child t m acc FTerm f <*> child t m acc FTerm a
  decodeTerm t m acc (TmDelayed fc r e) = PDelayed fc r <$> child t m acc FTerm e
  decodeTerm t m acc (TmDelay fc e) = PDelay fc <$> child t m acc FTerm e
  decodeTerm t m acc (TmForce fc e) = PForce fc <$> child t m acc FTerm e
  decodeTerm t m acc (TmSearch fc) = Just (PSearch fc)
  decodeTerm t m acc (TmPrimVal fc k) = Just (PPrimVal fc k)
  decodeTerm t m acc (TmQuote fc e) = PQuote fc <$> child t m acc FTerm e
  decodeTerm t m acc (TmQuoteName fc n) = Just (PQuoteName fc n)
  decodeTerm t m acc (TmQuoteDecl fc ds) = PQuoteDecl fc <$> declBlock t m acc ds
  decodeTerm t m acc (TmUnquote fc e) = PUnquote fc <$> child t m acc FTerm e
  decodeTerm t m acc (TmRunElab fc e) = PRunElab fc <$> child t m acc FTerm e
  decodeTerm t m acc (TmHole fc b n) = Just (PHole fc b n)
  decodeTerm t m acc (TmType fc) = Just (PType fc)
  decodeTerm t m acc (TmAs fc nfc n e) = PAs fc nfc n <$> child t m acc FTerm e
  decodeTerm t m acc (TmDotted fc e) = PDotted fc <$> child t m acc FTerm e
  decodeTerm t m acc (TmImplicit fc) = Just (PImplicit fc)
  decodeTerm t m acc (TmInfer fc) = Just (PInfer fc)
  decodeTerm t m acc (TmOp fc (MkWithData lfc l) op r)
      = (\l', r' => POp fc (MkWithData lfc l') op r')
          <$> lhsChild t m acc l <*> child t m acc FTerm r
  decodeTerm t m acc (TmPrefixOp fc op e) = PPrefixOp fc op <$> child t m acc FTerm e
  decodeTerm t m acc (TmSectionL fc op e) = PSectionL fc op <$> child t m acc FTerm e
  decodeTerm t m acc (TmSectionR fc e op) = (\e' => PSectionR fc e' op) <$> child t m acc FTerm e
  decodeTerm t m acc (TmBracketed fc e) = PBracketed fc <$> child t m acc FTerm e
  decodeTerm t m acc (TmString fc h ps) = PString fc h <$> children t m acc FStr ps
  decodeTerm t m acc (TmMultiline fc h i ls) = PMultiline fc h i <$> stringLines t m acc ls
  decodeTerm t m acc (TmDoBlock fc ns ss) = PDoBlock fc ns <$> children t m acc FDo ss
  decodeTerm t m acc (TmBang fc e) = PBang fc <$> child t m acc FTerm e
  decodeTerm t m acc (TmIdiom fc ns e) = PIdiom fc ns <$> child t m acc FTerm e
  decodeTerm t m acc (TmList fc nfc xs) = PList fc nfc <$> locatedChildren t m acc xs
  decodeTerm t m acc (TmSnocList fc nfc xs) = PSnocList fc nfc <$> snocChildren t m acc xs
  decodeTerm t m acc (TmPair fc l r) = PPair fc <$> child t m acc FTerm l <*> child t m acc FTerm r
  decodeTerm t m acc (TmDPair fc opfc l ty r)
      = PDPair fc opfc <$> child t m acc FTerm l <*> child t m acc FTerm ty
                       <*> child t m acc FTerm r
  decodeTerm t m acc (TmUnit fc) = Just (PUnit fc)
  decodeTerm t m acc (TmIfThenElse fc c th el)
      = PIfThenElse fc <$> child t m acc FTerm c <*> child t m acc FTerm th
                       <*> child t m acc FTerm el
  decodeTerm t m acc (TmComprehension fc e ss)
      = PComprehension fc <$> child t m acc FTerm e <*> children t m acc FDo ss
  decodeTerm t m acc (TmRewrite fc r e)
      = PRewrite fc <$> child t m acc FTerm r <*> child t m acc FTerm e
  decodeTerm t m acc (TmRange fc x y z)
      = PRange fc <$> child t m acc FTerm x <*> optChild t m acc FTerm y <*> child t m acc FTerm z
  decodeTerm t m acc (TmRangeStream fc x y)
      = PRangeStream fc <$> child t m acc FTerm x <*> optChild t m acc FTerm y
  decodeTerm t m acc (TmPostfixApp fc e ps) = (\e' => PPostfixApp fc e' ps) <$> child t m acc FTerm e
  decodeTerm t m acc (TmPostfixAppPartial fc ps) = Just (PPostfixAppPartial fc ps)
  decodeTerm t m acc (TmUnifyLog fc lvl e) = PUnifyLog fc lvl <$> child t m acc FTerm e
  decodeTerm t m acc (TmWithNames fc ns e) = PWithUnambigNames fc ns <$> child t m acc FTerm e
  decodeTerm t m acc (TmRelocated fc e) = substFC fc <$> child t m acc FTerm e
  decodeTerm t m acc _ = Nothing

  decodeClause : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
           Node (nodeCount t) -> Maybe PClause
  decodeClause t m acc (ClPattern fc l r ws)
      = MkPatClause fc <$> child t m acc FTerm l <*> child t m acc FTerm r
                       <*> declBlock t m acc ws
  decodeClause t m acc (ClWith fc l wps flags cs)
      = (\l', wps', cs' => MkWithClause fc l' wps' flags cs')
          <$> child t m acc FTerm l <*> children1 t m acc FWith wps <*> children t m acc FClause cs
  decodeClause t m acc (ClImpossible fc l) = MkImpossible fc <$> child t m acc FTerm l
  decodeClause t m acc _ = Nothing

  decodeDecl : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
         Node (nodeCount t) -> Maybe PDecl
  decodeDecl t m acc (Declared fc d) = MkFCVal fc <$> decodeDeclOf t m acc d
  decodeDecl t m acc _ = Nothing

  decodeDeclOf : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
           DeclOf (Within (nodeCount t)) -> Maybe PDeclNoFC
  decodeDeclOf t m acc (DcClaim rig vis opts ty)
      = (\opts', ty' => PClaim (MkPClaim rig vis opts' ty'))
          <$> children t m acc FOpt opts <*> child t m acc FTyDecl ty
  decodeDeclOf t m acc (DcDef cs) = PDef <$> children t m acc FClause cs
  decodeDeclOf t m acc (DcData doc vis tot d) = PData doc vis tot <$> child t m acc FData d
  decodeDeclOf t m acc (DcParameters (Left ps) ds)
      = (\ps', ds' => PParameters (Left ps') ds')
          <$> children1 t m acc FPlain ps <*> declBlock t m acc ds
  decodeDeclOf t m acc (DcParameters (Right ps) ds)
      = (\ps', ds' => PParameters (Right ps') ds')
          <$> children1 t m acc FBinder ps <*> declBlock t m acc ds
  decodeDeclOf t m acc (DcUsing us ds) = PUsing <$> namedChildren t m acc us <*> declBlock t m acc ds
  decodeDeclOf t m acc (DcInterface vis cons n doc ps det con ds)
      = (\cons', ps', ds' => PInterface vis cons' n doc ps' det con ds')
          <$> namedChildren t m acc cons <*> children t m acc FNames ps <*> declBlock t m acc ds
  decodeDeclOf t m acc (DcImplementation vis opts pass imps cons n ps iname nusing Nothing)
      = (\opts', imps', cons', ps' =>
            PImplementation vis opts' pass imps' cons' n ps' iname nusing Nothing)
          <$> children t m acc FOpt opts <*> children t m acc FImplicit imps
          <*> namedChildren t m acc cons <*> children t m acc FTerm ps
  decodeDeclOf t m acc (DcImplementation vis opts pass imps cons n ps iname nusing (Just ds))
      = (\opts', imps', cons', ps', ds' =>
            PImplementation vis opts' pass imps' cons' n ps' iname nusing (Just ds'))
          <$> children t m acc FOpt opts <*> children t m acc FImplicit imps
          <*> namedChildren t m acc cons <*> children t m acc FTerm ps <*> declBlock t m acc ds
  decodeDeclOf t m acc (DcRecord doc vis tot r) = PRecord doc vis tot <$> child t m acc FRecord r
  decodeDeclOf t m acc (DcFail msg ds) = PFail msg <$> declBlock t m acc ds
  decodeDeclOf t m acc (DcMutual ds) = PMutual <$> declBlock t m acc ds
  decodeDeclOf t m acc (DcFixity fx) = Just (PFixity fx)
  decodeDeclOf t m acc (DcNamespace ns ds) = PNamespace ns <$> declBlock t m acc ds
  decodeDeclOf t m acc (DcTransform n l r)
      = PTransform n <$> child t m acc FTerm l <*> child t m acc FTerm r
  decodeDeclOf t m acc (DcRunElab e) = PRunElabDecl <$> child t m acc FTerm e
  decodeDeclOf t m acc (DcDirective d) = PDirective <$> directiveOf t m acc d
  decodeDeclOf t m acc (DcBuiltin ty n) = Just (PBuiltin ty n)

  decodeStatement : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
              Node (nodeCount t) -> Maybe PDo
  decodeStatement t m acc (StExp fc e) = DoExp fc <$> child t m acc FTerm e
  decodeStatement t m acc (StBind fc nfc n rig ty v)
      = DoBind fc nfc n rig <$> optChild t m acc FTerm ty <*> child t m acc FTerm v
  decodeStatement t m acc (StBindPat fc p ty v alts)
      = DoBindPat fc <$> child t m acc FTerm p <*> optChild t m acc FTerm ty
                     <*> child t m acc FTerm v <*> children t m acc FClause alts
  decodeStatement t m acc (StLet fc rig p ty v alts)
      = letBound fc rig <$> child t m acc FTerm p <*> child t m acc FTerm ty
                        <*> child t m acc FTerm v <*> children t m acc FClause alts
  decodeStatement t m acc (StLetLocal fc dss) = DoLetLocal fc <$> declBlocks t m acc dss
  decodeStatement t m acc (StRewrite fc e) = DoRewrite fc <$> child t m acc FTerm e
  decodeStatement t m acc _ = Nothing

  decodePiece : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
          Node (nodeCount t) -> Maybe PStr
  decodePiece t m acc (PcLiteral fc s) = Just (StrLiteral fc s)
  decodePiece t m acc (PcInterp fc e) = StrInterp fc <$> child t m acc FTerm e
  decodePiece t m acc _ = Nothing

  decodeUpdate : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
                Node (nodeCount t) -> Maybe PFieldUpdate
  decodeUpdate t m acc (UpSet path e) = PSetField path <$> child t m acc FTerm e
  decodeUpdate t m acc (UpApply path e) = PSetFieldApp path <$> child t m acc FTerm e
  decodeUpdate t m acc _ = Nothing

  decodeOpt : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
          Node (nodeCount t) -> Maybe PFnOpt
  decodeOpt t m acc (OpFn o) = Just (IFnOpt o)
  decodeOpt t m acc (OpForeign es) = PForeign <$> children t m acc FTerm es
  decodeOpt t m acc (OpForeignExport es) = PForeignExport <$> children t m acc FTerm es
  decodeOpt t m acc _ = Nothing

  decodeData : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
             Node (nodeCount t) -> Maybe PDataDecl
  decodeData t m acc (DtBody fc n ty opts cons)
      = (\ty', cons' => MkPData fc n ty' opts cons')
          <$> optChild t m acc FTerm ty <*> children t m acc FTyDecl cons
  decodeData t m acc (DtLater fc n ty) = MkPLater fc n <$> child t m acc FTerm ty
  decodeData t m acc _ = Nothing

  decodeRecord : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
               Node (nodeCount t) -> Maybe (PRecordDecl' Name)
  decodeRecord t m acc (RcBody n ps opts con fs)
      = (\ps', fs' => MkPRecord n ps' opts con fs')
          <$> children t m acc FBinder ps <*> children t m acc FField fs
  decodeRecord t m acc (RcLater n ps) = MkPRecordLater n <$> children t m acc FBinder ps
  decodeRecord t m acc _ = Nothing

  decodeTyClaim : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
            Node (nodeCount t) -> Maybe PTypeDecl
  decodeTyClaim t m acc (TyClaim fc ns doc ty)
      = (\ty' => MkFCVal fc (MkPTy ns doc ty')) <$> child t m acc FTerm ty
  decodeTyClaim t m acc _ = Nothing

  decodeField : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
          Node (nodeCount t) -> Maybe PField
  decodeField t m acc (FdField fc doc rig ns p ty)
      = (\p', ty' => MkWithFCDocRigNames fc doc rig ns (MkPiBindData p' ty'))
          <$> piChild t m acc p <*> child t m acc FTerm ty
  decodeField t m acc _ = Nothing

  decodeWith : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
                Node (nodeCount t) -> Maybe PWithProblem
  decodeWith t m acc (WpValue rig v prf)
      = (\v' => MkPWithProblem rig v' prf) <$> child t m acc FTerm v
  decodeWith t m acc _ = Nothing

  decodeNames : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
          Node (nodeCount t) -> Maybe BasicMultiBinder
  decodeNames t m acc (BnNames rig ns ty) = MkBasicMultiBinder rig ns <$> child t m acc FTerm ty
  decodeNames t m acc _ = Nothing

  decodeBinder : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
           Node (nodeCount t) -> Maybe PBinder
  decodeBinder t m acc (BnPi p b) = MkPBinder <$> piChild t m acc p <*> child t m acc FNames b
  decodeBinder t m acc _ = Nothing

  decodePlain : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
          Node (nodeCount t) -> Maybe PlainBinder
  decodePlain t m acc (BnPlain n ty) = MkWithName n <$> child t m acc FTerm ty
  decodePlain t m acc _ = Nothing

  decodeImplicit : (t : ParseTree) -> (m : Nat) -> (0 _ : Accessible LT m) ->
                   Node (nodeCount t) -> Maybe (WithFCRigName (PiBindData PTerm))
  decodeImplicit t m acc (BnImplicit fc rig n p ty)
      = (\p', ty' => MkWithFCRigName fc rig n (MkPiBindData p' ty'))
          <$> piChild t m acc p <*> child t m acc FTerm ty
  decodeImplicit t m acc _ = Nothing

||| The declarations a parse gave, read off its tree, each run of
||| neighbouring clauses one definition. Nothing for a node outside the
||| tree, which only another parse gives.
export
declsIn : List (Id FDecl) -> Read (List PDecl)
declsIn ds t = collectDefs <$> traverse root ds
  where
    root : Id FDecl -> Maybe PDecl
    root i = do c <- checkIndex (nodeCount t) i.place
                let m = sizeAt t c
                decodeDecl t m (wellFounded m) (nodeAt t c)
