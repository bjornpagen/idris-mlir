-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A check of the harness's that asks idr-expect itself, which states
||| harnessed of every module it is given.
module Asks

export
asks : List String
asks = ["--idr-expect=holds=harnessed", "-o", "/dev/null"]
