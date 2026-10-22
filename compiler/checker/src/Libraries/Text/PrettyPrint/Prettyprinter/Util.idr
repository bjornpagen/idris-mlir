-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Libraries.Text.PrettyPrint.Prettyprinter.Util

import Libraries.Text.PrettyPrint.Prettyprinter.Doc
import Libraries.Text.PrettyPrint.Prettyprinter.Render.String

%default total

||| Split an input into word-sized `Doc`.
export
words : String -> List (Doc ann)
words s = map pretty0 $ map pack (go [<] (unpack s))
  where
    -- A word read so far, before the words after it; none if it is empty.
    flush : SnocList Char -> List (List Char) -> List (List Char)
    flush [<] ws = ws
    flush word ws = (word <>> []) :: ws

    -- The runs of characters between whitespace, read one character at a
    -- time, `word` the run read so far.
    go : SnocList Char -> List Char -> List (List Char)
    go word [] = flush word []
    go word (c :: cs) = if isSpace c then flush word (go [<] cs) else go (word :< c) cs

||| Optionally annotate a document
export
annotateM : Maybe ann -> Doc ann -> Doc ann
annotateM = maybe id annotate

||| Insert soft linebreaks between words, so that text is broken into multiple
||| lines when it exceeds the available width.
export
reflow : String -> Doc ann
reflow = fillSep . words

||| Renders a document with a certain width.
export
putDocW : Nat -> Doc ann -> IO ()
putDocW w = renderIO . layoutPretty ({ layoutPageWidth := AvailablePerLine (cast w) 1 } defaultLayoutOptions)
