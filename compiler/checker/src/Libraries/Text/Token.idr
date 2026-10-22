-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Libraries.Text.Token

%default total

||| A token of a kind and the text that was recognised. What the text means
||| is the reader's: a grammar that wants a number reads one from the text,
||| at the type it wants, so no type is computed from a kind.
public export
record Token k where
  constructor Tok
  kind : k
  text : String
