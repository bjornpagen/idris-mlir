-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
-- The shape of the data type a constructor belongs to (a list's nil or
-- cons, an enumeration, a record): one of the constructor's flags, which
-- elaboration decides and a TTC keeps. The module holds no expression to
-- compile, since the frontend reads checked TT.
module Core.CompileExpr

%default total

-- Backends might be able to treat some 'shapes' of data type specially,
-- e.g. enumerations or lists.
-- They can use or ignore this information as they see fit.
public export
data ConInfo = DATACON -- normal data constructor
             | TYCON -- normal type constructor
             | NIL -- nil of a list or option shaped thing
             | CONS -- cons of a list shaped thing
             | ENUM Nat -- part of an enumeration with the given number of constructors
             | NOTHING -- nothing of an option shaped thing
             | JUST -- just of an option shaped thing
             | RECORD -- record constructor (no tag)
             | ZERO -- zero of a nat-like type
             | SUCC -- successor of a nat-like type
             | UNIT -- unit

export
Show ConInfo where
  show DATACON = "[datacon]"
  show TYCON   = "[tycon]"
  show NIL     = "[nil]"
  show CONS    = "[cons]"
  show (ENUM n) = "[enum " ++ show n ++ "]"
  show NOTHING = "[nothing]"
  show JUST    = "[just]"
  show RECORD  = "[record]"
  show ZERO    = "[zero]"
  show SUCC    = "[succ]"
  show UNIT    = "[unit]"

export
Eq ConInfo where
  DATACON == DATACON = True
  TYCON == TYCON = True
  NIL == NIL = True
  CONS == CONS = True
  ENUM x == ENUM y = x == y
  NOTHING == NOTHING = True
  JUST == JUST = True
  RECORD == RECORD = True
  ZERO == ZERO = True
  SUCC == SUCC = True
  UNIT == UNIT = True
  _ == _ = False
