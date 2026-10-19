// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
static const char *text = R"(
module attributes {idr.stage = "higher"} {
)";
void run(Importer &importer) { importer.run(); }
