-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The relational core: relations over a finite universe, joined by
||| generic join, filtered by conditions and Allen's interval relations,
||| aggregated by exact merges, and saturated by semi-naive fixpoints whose
||| end the universe's size proves.
module Relational

import public Relational.Order
import public Relational.Map
import public Relational.Join
import public Relational.Interval
import public Relational.Fixpoint

%default total
