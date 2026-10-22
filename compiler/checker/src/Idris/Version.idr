-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
||| Sets and display version of Idris.
module Idris.Version

import IdrisPaths
import public Libraries.Data.Version

%default total

export
version : Version
version with (idrisVersion)
 version | (s,"") = MkVersion s Nothing
 version | (s,t) = MkVersion s (Just t)
