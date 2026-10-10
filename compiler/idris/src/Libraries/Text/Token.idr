module Libraries.Text.Token

%default total

||| A token of a particular kind and the text that was recognised.
public export
record Token k where
  constructor Tok
  kind : k
  text : String
