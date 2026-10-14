-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Libraries.Data.Ordering.Extra

%default total

export infixl 5 `thenCmp`

export
thenCmp : Ordering -> Lazy Ordering -> Ordering
thenCmp LT _ = LT
thenCmp EQ o = o
thenCmp GT _ = GT
