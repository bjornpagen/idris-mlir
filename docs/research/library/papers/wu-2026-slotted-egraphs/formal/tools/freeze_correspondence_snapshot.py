#!/usr/bin/env python3
"""Freeze the single permitted current correspondence-review snapshot."""

from __future__ import annotations

import hashlib
import json
import pathlib

import yaml


ROOT = pathlib.Path(__file__).resolve().parents[2]
FORMAL = ROOT / "formal"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def digest(value: object) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def main() -> None:
    registry = yaml.safe_load((FORMAL / "formal-units.yaml").read_text(encoding="utf-8"))
    compiler = json.loads(
        (FORMAL / "compiler-correspondence-metadata.json").read_text(encoding="utf-8")
    )
    compiler_by_id = {entry["formal_id"]: entry for entry in compiler["entries"]}
    active = sorted(
        (
            unit
            for unit in registry["formal_units"]
            if unit.get("active_status") == "ACTIVE"
        ),
        key=lambda unit: unit["formal_id"],
    )
    if len(active) != 146:
        raise RuntimeError("expected 146 ACTIVE units")
    mapping_set = []
    for unit in active:
        metadata = compiler_by_id[unit["formal_id"]]
        mapping_set.append(
            {
                "formal_id": unit["formal_id"],
                "paper_kind": unit["paper_kind"],
                "paper_title": unit["paper_title"],
                "source_file": unit["source_file"],
                "source_line_start": unit["source_line_start"],
                "source_line_end": unit["source_line_end"],
                "source_excerpt_sha256": unit["source_excerpt_sha256"],
                "paper_source_normal_sha256": metadata["paper_source_normal_sha256"],
                "normative_statement": unit["normative_statement"],
                "paper_statement_hash": unit["paper_statement_hash"],
                "lean_declaration": unit["lean_declaration"],
                "lean_file": unit["lean_file"],
                "lean_file_sha256": unit["lean_file_sha256"],
                "lean_pretty_printed_type": unit["lean_pretty_printed_type"],
                "statement_hash": unit["statement_hash"],
                "lean_type_normal_sha256": metadata["lean_type_normal_sha256"],
                "all_explicit_hypotheses": unit["all_explicit_hypotheses"],
                "all_implicit_typeclass_or_decidability_hypotheses": unit[
                    "all_implicit_typeclass_or_decidability_hypotheses"
                ],
                "compiler_telescope": metadata["telescope"],
                "direct_dependencies": unit["direct_dependencies"],
                "transitive_dependencies": unit["transitive_dependencies"],
                "lean_direct_dependencies": unit["lean_direct_dependencies"],
                "lean_transitive_dependencies": unit["lean_transitive_dependencies"],
                "compiler_used_active_mappings": metadata[
                    "compiler_used_active_mappings"
                ],
                "foundation_axioms": unit["foundation_axioms"],
                "proof_status": unit["proof_status"],
                "mapping_status": unit["mapping_status"],
                "correspondence_status": unit["correspondence_status"],
            }
        )

    files = {
        "formal_registry_sha256": sha(FORMAL / "formal-units.yaml"),
        "paper_lean_map_sha256": sha(FORMAL / "paper-lean-map.json"),
        "compiler_metadata_sha256": sha(
            FORMAL / "compiler-correspondence-metadata.json"
        ),
        "paper_dependency_graph_sha256": sha(FORMAL / "dependency-graph.json"),
        "compiler_dependency_graph_sha256": sha(
            FORMAL / "compiler-dependency-graph.json"
        ),
        "proof_sketch_audit_sha256": sha(FORMAL / "proof-sketch-audit.json"),
        "axiom_report_sha256": sha(FORMAL / "axiom-report.json"),
        "normalization_contract_sha256": sha(FORMAL / "normalization-contract.json"),
        "formal_statement_index_sha256": sha(
            FORMAL / "formal-statement-index.tex"
        ),
        "artifact_refinement_map_sha256": sha(
            FORMAL / "artifact-refinement-map.json"
        ),
        "edge_case_closure_sha256": sha(FORMAL / "edge-case-closure.json"),
        "trace_witness_binding_report_sha256": sha(
            FORMAL / "trace-envelope-witness-binding-report.json"
        ),
        "metadata_generator_sha256": sha(
            FORMAL / "tools/regenerate_current_metadata.py"
        ),
        "snapshot_generator_sha256": sha(pathlib.Path(__file__)),
    }
    material = {
        "repair_scope": "LISTED_LITERAL_DEFECTS_AND_EXACT_TRACE_WITNESS_BINDING_ONLY",
        "input_zip_sha256": "736ab5787c2c1f32c9904df432a256fea8e453d7fbd71e687c2e475b21305a61",
        "active_manuscript_graph_sha256": registry["source_snapshot"][
            "active_source_graph_sha256"
        ],
        "formal_source_config_sha256": registry["formal_source_sha256"],
        "mapping_set_sha256": digest(mapping_set),
        "trace_envelope_witness_sha256": "d4571f177607c4073f35466ab7d8bd2bf642bd1190a4ba38508c5a5ddfa93b7f",
        **files,
        "counts": {
            "audit_rows": 158,
            "active_formal_units": 146,
            "proofs": 83,
            "definitions": 44,
            "constructors": 19,
            "named_environments": 27,
            "inline_leanref_tags": 146,
            "supplemental_witness_active_claim_delta": 0,
        },
    }
    manifest = {
        "schema_version": "4.0",
        "status": "FROZEN_CURRENT_SINGLE_ROUND_CORRESPONDENCE_REVIEW_INPUT",
        "snapshot_id": digest(material),
        "snapshot_id_algorithm": "SHA-256 of canonical compact JSON with sorted keys of snapshot_material",
        "snapshot_material": material,
        "mapping_set_algorithm": (
            "Select ACTIVE rows, sort by formal_id, retain exact paper span, normalized "
            "paper hash, controlled statement, Lean type/hash, paper and compiler "
            "hypotheses, curated and compiler dependencies, axioms, and status fields; "
            "then SHA-256 canonical compact JSON with sorted keys."
        ),
        "review_requirements": {
            "process_id": "bounded-arxiv-correspondence-2026-09-02",
            "fresh_independent_reviewer_count": 2,
            "required_roles": [
                "PAPER_LEAN_SEMANTIC_CORRESPONDENCE_AND_IDENTIFIER_LEAK_SCAN",
                "LEAN_METADATA_COHERENCE_AND_IDENTIFIER_LEAK_SCAN",
            ],
            "maximum_review_rounds": 1,
            "completed_review_rounds": 0,
            "this_is_only_permitted_round": True,
            "coverage": "All 146 ACTIVE mappings, all 27 named environments, and the supplemental witness binding.",
            "source_mutation_during_review": "PROHIBITED",
            "latex_build": "PROHIBITED_THIS_GATE",
            "pdf_qa": "PROHIBITED_THIS_GATE",
        },
    }
    (FORMAL / "review-snapshot-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps({"snapshot_id": manifest["snapshot_id"], **files}, sort_keys=True))


if __name__ == "__main__":
    main()
