-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Libraries.Text.PrettyPrint.Prettyprinter.SimpleDocTree

import Libraries.Text.PrettyPrint.Prettyprinter.Doc

%default total

||| Tree-like structure more suitable for rendering to a structured
||| format such as HTML.
public export
data SimpleDocTree : Type -> Type where
  STEmpty : SimpleDocTree ann
  STChar : (c : Char) -> SimpleDocTree ann
  STText : (len : Int) -> (text : String) -> SimpleDocTree ann
  STLine : (i : Int) -> SimpleDocTree ann
  STAnn : ann -> (rest : SimpleDocTree ann) -> SimpleDocTree ann
  STConcat : List (SimpleDocTree ann) -> SimpleDocTree ann

-- Each walk over a tree walks a concatenation's list in a function of its
-- own, so every call is on a part of the tree or of the list it was given.
mutual
  ||| Changes the annotation of a document, or none at all.
  export
  alterAnnotationsST : (ann -> List ann') -> SimpleDocTree ann -> SimpleDocTree ann'
  alterAnnotationsST re STEmpty = STEmpty
  alterAnnotationsST re (STChar c) = STChar c
  alterAnnotationsST re (STText len text) = STText len text
  alterAnnotationsST re (STLine i) = STLine i
  alterAnnotationsST re (STAnn ann rest) = foldr STAnn (alterAnnotationsST re rest) (re ann)
  alterAnnotationsST re (STConcat xs) = STConcat (alterEach re xs)

  alterEach : (ann -> List ann') -> List (SimpleDocTree ann) -> List (SimpleDocTree ann')
  alterEach re [] = []
  alterEach re (x :: xs) = alterAnnotationsST re x :: alterEach re xs

||| Changes the annotation of a document.
export
reAnnotateST : (ann -> ann') -> SimpleDocTree ann -> SimpleDocTree ann'
reAnnotateST f = alterAnnotationsST (pure . f)

||| Removes all annotations.
export
unAnnotateST : SimpleDocTree ann -> SimpleDocTree xxx
unAnnotateST = alterAnnotationsST (const [])

mutual
  ||| Collects all annotations from a document.
  export
  collectAnnotations : Monoid m => (ann -> m) -> SimpleDocTree ann -> m
  collectAnnotations f STEmpty = neutral
  collectAnnotations f (STChar c) = neutral
  collectAnnotations f (STText len text) = neutral
  collectAnnotations f (STLine i) = neutral
  collectAnnotations f (STAnn ann rest) = f ann <+> collectAnnotations f rest
  collectAnnotations f (STConcat xs) = collectEach f xs

  collectEach : Monoid m => (ann -> m) -> List (SimpleDocTree ann) -> m
  collectEach f [] = neutral
  collectEach f (x :: xs) = collectAnnotations f x <+> collectEach f xs

mutual
  ||| Transform a document based on its annotations.
  export
  traverse : Applicative f => (ann -> f ann') -> SimpleDocTree ann -> f (SimpleDocTree ann')
  traverse f STEmpty = pure STEmpty
  traverse f (STChar c) = pure $ STChar c
  traverse f (STText len text) = pure $ STText len text
  traverse f (STLine i) = pure $ STLine i
  traverse f (STAnn ann rest) = STAnn <$> f ann <*> traverse f rest
  traverse f (STConcat xs) = STConcat <$> traverseEach f xs

  traverseEach : Applicative f => (ann -> f ann') -> List (SimpleDocTree ann) -> f (List (SimpleDocTree ann'))
  traverseEach f [] = pure []
  traverseEach f (x :: xs) = (::) <$> traverse f x <*> traverseEach f xs

-- An annotation pushed and not yet popped, with the trees read before it
-- in the part of the stream that holds it.
record Pushed ann where
  constructor MkPushed
  annotation : ann
  preceding : SnocList (SimpleDocTree ann)

-- Trees in order, each but the last before the trees after it.
spine : SnocList (SimpleDocTree ann) -> SimpleDocTree ann -> SimpleDocTree ann
spine [<] tip = tip
spine (sx :< x) tip = spine sx (STConcat [x, tip])

-- The trees read before a pop: the last stands alone, and where there
-- are none, an annotation around them is dropped.
popped : SnocList (SimpleDocTree ann) -> Maybe (SimpleDocTree ann)
popped [<] = Nothing
popped (sx :< x) = Just (spine sx x)

-- Where the stream ends inside annotations, what was read before the
-- outermost of them, as if it had been popped there.
unclosed : Pushed ann -> List (Pushed ann) -> Maybe (SimpleDocTree ann)
unclosed p [] = popped p.preceding
unclosed _ (p :: ps) = unclosed p ps

-- The trees of a stream, read left to right in one pass: `here` holds the
-- trees read since the innermost annotation still open was pushed (or
-- since the start, where none is open), and `around` the annotations
-- still open, innermost first. A pop with none open is a stream no tree
-- stands for.
build : (here : SnocList (SimpleDocTree ann)) -> (around : List (Pushed ann)) ->
        SimpleDocStream ann -> Maybe (SimpleDocTree ann)
build here [] SEmpty = Just (spine here STEmpty)
build here (p :: ps) SEmpty = unclosed p ps
build here around (SChar c rest) = build (here :< STChar c) around rest
build here around (SText len text rest) = build (here :< STText len text) around rest
build here around (SLine i rest) = build (here :< STLine i) around rest
build here around (SAnnPush ann rest) = build [<] (MkPushed ann here :: around) rest
build here [] (SAnnPop rest) = Nothing
build here (MkPushed ann prior :: around) (SAnnPop rest)
    = build (maybe prior (\tree => prior :< STAnn ann tree) (popped here)) around rest

export
fromStream : SimpleDocStream ann -> SimpleDocTree ann
fromStream sdoc = case build [<] [] sdoc of
    Just tree => flatten tree
    Nothing => internalError
  where
    flatten : SimpleDocTree ann -> SimpleDocTree ann
    flatten (STConcat [x, STEmpty]) = flatten x
    flatten (STConcat [x, STConcat xs]) = case flatten (STConcat xs) of
      (STConcat xs') => STConcat (x :: xs')
      y => STConcat [x, y]
    flatten x = x

    internalError : SimpleDocTree ann
    internalError = let msg = "<internal pretty printing error>" in
                        STText (cast $ length msg) msg
