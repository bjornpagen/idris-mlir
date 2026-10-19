#!/bin/sh
# SPDX-License-Identifier: 0BSD
# Copyright (c) 2026 Bjorn Pagen
idris-mlir-opt --mlir-very-unsafe-disable-verifier-on-parsing "$1"
