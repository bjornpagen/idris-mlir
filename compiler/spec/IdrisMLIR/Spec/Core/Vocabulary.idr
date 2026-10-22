-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The whole vocabulary an area of the dialect is written in, in one
||| import: what an area's declarations module needs to state its ops,
||| types, attributes, sets, interfaces, rules and headers.
module IdrisMLIR.Spec.Core.Vocabulary

import public IdrisMLIR.Spec.Core.Text
import public IdrisMLIR.Spec.Core.Dialect
import public IdrisMLIR.Spec.Core.Hooks
import public IdrisMLIR.Spec.Core.Enums
import public IdrisMLIR.Spec.Core.Cpp
import public IdrisMLIR.Spec.Core.Upstream
import public IdrisMLIR.Spec.Core.Interfaces
import public IdrisMLIR.Spec.Core.Types
import public IdrisMLIR.Spec.Core.Constraints
import public IdrisMLIR.Spec.Core.Format
import public IdrisMLIR.Spec.Core.Ods
import public IdrisMLIR.Spec.Core.Admitted
import public IdrisMLIR.Spec.Core.Op
import public IdrisMLIR.Spec.Core.Rewrite
import public IdrisMLIR.Spec.Core.Rules
import public IdrisMLIR.Spec.Core.Declarations
import public IdrisMLIR.Spec.Pipeline.Stage

%default total
