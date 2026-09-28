#!/usr/bin/env python3
"""Regenerate the current paper--Lean correspondence metadata.

This tool intentionally does not invoke Lean or LaTeX.  It rebinds the current
paper spans to the existing compiler projection only after every mapped Lean
file passes its recorded SHA-256 check, then recomputes statement, hypothesis,
and dependency carriers under the frozen normalization contract.
"""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import unicodedata

import yaml


ROOT = pathlib.Path(__file__).resolve().parents[2]
FORMAL = ROOT / "formal"
INPUT_ZIP_SHA256 = "736ab5787c2c1f32c9904df432a256fea8e453d7fbd71e687c2e475b21305a61"
NORMALIZATION_SHA256 = "9b4a84e6b492a65bed6c9446b1c3c9e255e21277caba9cc9d8c31d713c873bc6"
WITNESS_SHA256 = "d4571f177607c4073f35466ab7d8bd2bf642bd1190a4ba38508c5a5ddfa93b7f"
WITNESS_COMMIT = "f5dbc1a04e10b61e39e6fe1b0fe8d5b236728625"
WITNESS_BLOB_SHA1 = "48528272445b6fa81ebd6c1f30680cd285751b5f"
WITNESS_REPOSITORY_PATH = (
    "paper-claims/formal/TypedSlottedEGraphsPaper/TraceEnvelopeWitness.lean"
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: pathlib.Path) -> str:
    return sha256_bytes(path.read_bytes())


def canonical_json_bytes(value: object) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def canonical_hash(value: object) -> str:
    return sha256_bytes(canonical_json_bytes(value))


def load_json(path: pathlib.Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def dump_json(path: pathlib.Path, value: object) -> None:
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def dump_yaml(path: pathlib.Path, value: object) -> None:
    path.write_text(
        yaml.safe_dump(
            value,
            allow_unicode=True,
            sort_keys=False,
            width=100000,
            default_flow_style=False,
        ),
        encoding="utf-8",
    )


def strip_tex_comment(line: str) -> str:
    for index, char in enumerate(line):
        if char != "%":
            continue
        backslashes = 0
        cursor = index - 1
        while cursor >= 0 and line[cursor] == "\\":
            backslashes += 1
            cursor -= 1
        if backslashes % 2 == 0:
            return line[:index]
    return line


def paper_normal_form(excerpt: str, formal_id: str, declaration: str) -> str:
    value = excerpt.replace("\r\n", "\n").replace("\r", "\n")
    value = unicodedata.normalize("NFC", value)
    value = "\n".join(strip_tex_comment(line) for line in value.split("\n"))
    identifying_tag = f"\\leanref{{{formal_id}}}{{{declaration}}}"
    if value.count(identifying_tag) != 1:
        raise RuntimeError(
            f"expected exactly one identifying tag for {formal_id}, "
            f"found {value.count(identifying_tag)}"
        )
    value = value.replace(identifying_tag, "", 1)
    return re.sub(r"\s+", " ", value).strip()


def source_excerpt(unit: dict) -> str:
    path = ROOT / unit["source_file"]
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    start = int(unit["source_line_start"])
    end = int(unit["source_line_end"])
    if start < 1 or end < start or end > len(lines):
        raise RuntimeError(f"invalid source span for {unit['formal_id']}")
    excerpt = "".join(lines[start - 1 : end])
    identifying_tag = (
        f"\\leanref{{{unit['formal_id']}}}{{{unit['lean_declaration']}}}"
    )
    if identifying_tag not in excerpt:
        raise RuntimeError(
            f"recorded span for {unit['formal_id']} does not contain its tag"
        )
    return excerpt


def closure(nodes: list[str], direct: dict[str, list[str]]) -> dict[str, list[str]]:
    order = {node: index for index, node in enumerate(nodes)}
    result: dict[str, list[str]] = {}
    for node in nodes:
        seen: set[str] = set()
        stack = list(reversed(direct.get(node, [])))
        while stack:
            target = stack.pop()
            if target == node or target in seen:
                continue
            seen.add(target)
            stack.extend(reversed(direct.get(target, [])))
        result[node] = sorted(seen, key=order.__getitem__)
    return result


def assert_acyclic(nodes: list[str], direct: dict[str, list[str]]) -> None:
    state = {node: 0 for node in nodes}

    def visit(node: str) -> None:
        if state[node] == 1:
            raise RuntimeError(f"dependency cycle through {node}")
        if state[node] == 2:
            return
        state[node] = 1
        for target in direct.get(node, []):
            visit(target)
        state[node] = 2

    for node in nodes:
        visit(node)


def source_graph(files: list[dict]) -> str:
    return canonical_hash([{"path": item["path"], "sha256": item["sha256"]} for item in files])


def formal_source_config() -> tuple[list[dict], list[dict], str]:
    paper_index = FORMAL / "PaperIndex.lean"
    lean_sources = sorted((FORMAL / "TypedSlottedEGraphsPaper").glob("*.lean"))
    source_files = [
        {"path": "PaperIndex.lean", "sha256": sha256_file(paper_index)},
        *[
            {
                "path": str(path.relative_to(FORMAL)),
                "sha256": sha256_file(path),
            }
            for path in lean_sources
        ],
    ]
    entries = [
        {"path": f"formal/{item['path']}", "sha256": item["sha256"]}
        for item in source_files
    ]
    for relative in ["lake-manifest.json", "lakefile.toml", "lean-toolchain"]:
        entries.append(
            {
                "path": f"formal/{relative}",
                "sha256": sha256_file(FORMAL / relative),
            }
        )
    return source_files, entries, canonical_hash(entries)


def validate_and_collect_tags(active_units: list[dict]) -> dict:
    pattern = re.compile(r"\\leanref\{([^{}]+)\}\{([^{}]+)\}")
    found: list[tuple[str, str]] = []
    for relative in ["foundations_compressed.tex", "appendixC_vmcai_stage1.tex"]:
        found.extend(pattern.findall((ROOT / relative).read_text(encoding="utf-8")))
    ids = [item[0] for item in found]
    declarations = [item[1] for item in found]
    expected = {(unit["formal_id"], unit["lean_declaration"]) for unit in active_units}
    if len(found) != 146 or len(set(ids)) != 146 or len(set(declarations)) != 146:
        raise RuntimeError("source tag bijection is not 146/146/146")
    if set(found) != expected:
        raise RuntimeError("source tags do not exactly equal ACTIVE registry mappings")
    return {
        "status": "PASS_EXACT_BIJECTION_CURRENT_SNAPSHOT",
        "tag_count": 146,
        "unique_active_id_count": 146,
        "unique_exact_declaration_count": 146,
        "files": ["foundations_compressed.tex", "appendixC_vmcai_stage1.tex"],
    }


def regenerate() -> None:
    if sha256_file(FORMAL / "normalization-contract.json") != NORMALIZATION_SHA256:
        raise RuntimeError("normalization contract changed")
    witness = FORMAL / "TypedSlottedEGraphsPaper" / "TraceEnvelopeWitness.lean"
    if sha256_file(witness) != WITNESS_SHA256:
        raise RuntimeError("packaged TraceEnvelopeWitness.lean is not the pinned file")
    lake_text = (FORMAL / "lakefile.toml").read_text(encoding="utf-8")
    witness_root = '"TypedSlottedEGraphsPaper.TraceEnvelopeWitness"'
    if lake_text.count(witness_root) != 1:
        raise RuntimeError("witness must occur exactly once in Lake roots")

    registry_path = FORMAL / "formal-units.yaml"
    registry = yaml.safe_load(registry_path.read_text(encoding="utf-8"))
    compiler_path = FORMAL / "compiler-correspondence-metadata.json"
    compiler = load_json(compiler_path)
    old_compiler_sha = compiler.get("regeneration_provenance", {}).get(
        "previous_metadata_sha256", sha256_file(compiler_path)
    )
    compiler_by_id = {entry["formal_id"]: entry for entry in compiler["entries"]}

    normative_overrides = {
        "TSG-DEF-007": (
            "A flexible-arity typed slotted e-graph environment has finite class and "
            "stored-shape encodings, a depth-decreasing typed parent forest with total "
            "find, a collision-owner relation, and symmetry predicates closed under "
            "identity, inverse, and composition; its quiescent collision index is exact "
            "only as stated."
        ),
        "TSG-ACC-001": (
            "The executable ceiling-log function is zero at inputs 0 and 1, and for "
            "every natural k its value at k+2 is floor(log2(k+1))+1."
        ),
    }
    for unit in registry["formal_units"]:
        if unit["formal_id"] in normative_overrides:
            unit["normative_statement"] = normative_overrides[unit["formal_id"]]
        unit["paper_statement_hash"] = sha256_bytes(
            unit["normative_statement"].encode("utf-8")
        )
        if unit.get("active_status") != "ACTIVE":
            continue
        excerpt = source_excerpt(unit)
        unit["source_excerpt_sha256"] = sha256_bytes(excerpt.encode("utf-8"))
        lean_file = ROOT / unit["lean_file"]
        current_lean_sha = sha256_file(lean_file)
        if current_lean_sha != unit["lean_file_sha256"]:
            raise RuntimeError(f"mapped Lean file changed for {unit['formal_id']}")
        if unit["formal_id"] not in compiler_by_id:
            raise RuntimeError(f"missing compiler metadata for {unit['formal_id']}")

    active_units = [
        unit for unit in registry["formal_units"] if unit.get("active_status") == "ACTIVE"
    ]
    if len(active_units) != 146:
        raise RuntimeError("active formal-unit count changed")
    tag_gate = validate_and_collect_tags(active_units)
    author_files = registry["source_snapshot"]["files"]
    for item in author_files:
        item["sha256"] = sha256_file(ROOT / item["path"])
    registry["source_snapshot"]["entrypoint_sha256"] = sha256_file(
        ROOT / registry["source_snapshot"]["entrypoint"]
    )
    registry["source_snapshot"]["active_source_graph_sha256"] = source_graph(
        author_files
    )
    registry["source_snapshot"]["uploaded_zip_sha256"] = INPUT_ZIP_SHA256
    registry["source_snapshot"]["aggregate_algorithm"] = (
        "SHA-256 of canonical compact JSON with sorted object keys and recorded "
        "source-list order preserved for the current path/SHA-256 entries."
    )
    source_files, source_config_entries, formal_source_hash = formal_source_config()
    registry["registry_status"] = "CURRENT_METADATA_REGENERATED_PENDING_FRESH_CORRESPONDENCE_REVIEW"
    registry["source_tag_gate"] = tag_gate
    registry["formal_source_sha256"] = formal_source_hash
    registry["normalization_contract_sha256"] = NORMALIZATION_SHA256
    registry["current_regeneration"] = {
        "generator": "formal/tools/regenerate_current_metadata.py",
        "generator_sha256": sha256_file(pathlib.Path(__file__)),
        "method": "CURRENT_PAPER_SPANS_RECOMPUTED_AND_LEAN_PROJECTION_CARRIED_FORWARD_BY_EXACT_FILE_HASH",
        "previous_compiler_metadata_sha256": old_compiler_sha,
        "mapped_lean_file_hashes_verified": 146,
        "fresh_lean_dump_executed": False,
        "trace_witness_sha256": WITNESS_SHA256,
        "trace_witness_active_claim_count_delta": 0,
    }
    dump_yaml(registry_path, registry)
    registry_sha = sha256_file(registry_path)

    registry_by_id = {unit["formal_id"]: unit for unit in active_units}
    for entry in compiler["entries"]:
        unit = registry_by_id[entry["formal_id"]]
        if entry["declaration"] != unit["lean_declaration"]:
            raise RuntimeError(f"declaration mismatch for {unit['formal_id']}")
        current_lean_sha = sha256_file(ROOT / entry["lean_file"])
        if current_lean_sha != entry["lean_file_sha256"]:
            raise RuntimeError(f"compiler projection file changed for {unit['formal_id']}")
        excerpt = source_excerpt(unit)
        normal = paper_normal_form(
            excerpt, unit["formal_id"], unit["lean_declaration"]
        )
        entry["paper_source"] = {
            "file": unit["source_file"],
            "line_start": unit["source_line_start"],
            "line_end": unit["source_line_end"],
            "excerpt_sha256": unit["source_excerpt_sha256"],
        }
        entry["paper_source_normal"] = normal
        entry["paper_source_normal_sha256"] = sha256_bytes(normal.encode("utf-8"))
    compiler["status"] = "CURRENT_PAPER_REBOUND_TO_HASH_VERIFIED_LEAN_4_33_PROJECTION"
    compiler["normalization_contract_sha256"] = NORMALIZATION_SHA256
    compiler["active_mapping_count"] = 146
    compiler["regeneration_provenance"] = {
        "previous_metadata_sha256": old_compiler_sha,
        "paper_fields_regenerated_from_current_source": True,
        "hypothesis_and_Lean_type_fields_carried_forward_by_exact_lean_file_sha256": True,
        "mapped_lean_file_hashes_verified": 146,
        "fresh_Lean_environment_dump_executed": False,
        "reason": "The historical dump tool was not packaged; the mapped Lean files are byte-identical.",
    }
    dump_json(compiler_path, compiler)
    compiler_sha = sha256_file(compiler_path)

    paper_map_path = FORMAL / "paper-lean-map.json"
    paper_map = load_json(paper_map_path)
    for entry in paper_map["entries"]:
        unit = next(
            unit
            for unit in registry["formal_units"]
            if unit["formal_id"] == entry["formal_id"]
        )
        entry["active_status"] = unit["active_status"]
        entry["paper_kind"] = unit["paper_kind"]
        entry["paper_title"] = unit["paper_title"]
        entry["normalized_statement"] = unit["normative_statement"]
        entry["paper_statement_hash"] = unit["paper_statement_hash"]
        entry["source"] = {
            "file": unit["source_file"],
            "line_start": unit["source_line_start"],
            "line_end": unit["source_line_end"],
            "source_excerpt_sha256": unit.get("source_excerpt_sha256"),
        }
        entry["lean_declaration"] = unit["lean_declaration"]
        entry["lean_file"] = unit["lean_file"]
        entry["lean_file_sha256"] = unit["lean_file_sha256"]
        entry["lean_pretty_printed_type"] = unit["lean_pretty_printed_type"]
        entry["statement_hash"] = unit["statement_hash"]
        entry["foundation_axioms"] = unit["foundation_axioms"]
        entry["mapping_status"] = unit["mapping_status"]
        entry["proof_status"] = unit["proof_status"]
        entry["correspondence_status"] = unit["correspondence_status"]
    paper_map["map_status"] = "CURRENT_STATEMENT_METADATA_REGENERATED_PENDING_FRESH_REVIEW"
    paper_map["formal_registry_sha256"] = registry_sha
    paper_map["source_tag_gate"] = tag_gate
    paper_map["normalization_contract_sha256"] = NORMALIZATION_SHA256
    paper_map["regeneration_provenance"] = {
        "generator": "formal/tools/regenerate_current_metadata.py",
        "compiler_metadata_sha256": compiler_sha,
        "active_mapping_count": 146,
    }
    dump_json(paper_map_path, paper_map)

    compiler_graph_path = FORMAL / "compiler-dependency-graph.json"
    compiler_graph = load_json(compiler_graph_path)
    sorted_ids = sorted(registry_by_id)
    compiler_direct = {}
    for entry in compiler["entries"]:
        mapped_ids = [
            item["formal_id"] if isinstance(item, dict) else item
            for item in entry["compiler_used_active_mappings"]
        ]
        compiler_direct[entry["formal_id"]] = sorted(
            set(mapped_ids), key=sorted_ids.index
        )
    assert_acyclic(sorted_ids, compiler_direct)
    compiler_transitive = closure(sorted_ids, compiler_direct)
    compiler_nodes = [
        {"formal_id": formal_id, "lean_declaration": registry_by_id[formal_id]["lean_declaration"]}
        for formal_id in sorted_ids
    ]
    compiler_edges = []
    for source in sorted_ids:
        for target in compiler_direct[source]:
            compiler_edges.append(
                {
                    "from": source,
                    "to": target,
                    "kind": "COMPILER_USED_ACTIVE_DECLARATION",
                    "lean_from": registry_by_id[source]["lean_declaration"],
                    "lean_to": registry_by_id[target]["lean_declaration"],
                }
            )
    compiler_graph.update(
        {
            "graph_status": "RECOMPUTED_FROM_HASH_VERIFIED_COMPILER_PROJECTION",
            "formal_registry_sha256": registry_sha,
            "normalization_contract_sha256": NORMALIZATION_SHA256,
            "compiler_correspondence_metadata_sha256": compiler_sha,
            "active_node_count": 146,
            "direct_edge_count": len(compiler_edges),
            "transitive_pair_count": sum(map(len, compiler_transitive.values())),
            "nodes": compiler_nodes,
            "direct_dependencies": compiler_direct,
            "edges": compiler_edges,
            "transitive_dependencies": compiler_transitive,
            "strongly_connected_components": [[formal_id] for formal_id in sorted_ids],
            "strongly_connected_component_count": 146,
            "cyclic_strongly_connected_components": [],
            "cyclic_scc_count": 0,
            "cyclic_node_count": 0,
            "self_loop_count": 0,
            "is_acyclic": True,
            "regeneration_provenance": {
                "direct_edges_recomputed_from": "compiler-correspondence-metadata.json:compiler_used_active_mappings",
                "transitive_closure_recomputed": True,
            },
        }
    )
    dump_json(compiler_graph_path, compiler_graph)
    compiler_graph_sha = sha256_file(compiler_graph_path)

    dependency_path = FORMAL / "dependency-graph.json"
    dependency = load_json(dependency_path)
    all_units = registry["formal_units"]
    all_ids = [unit["formal_id"] for unit in all_units]
    all_by_id = {unit["formal_id"]: unit for unit in all_units}
    paper_direct = {
        unit["formal_id"]: list(unit["direct_dependencies"]) for unit in all_units
    }
    for source, targets in paper_direct.items():
        for target in targets:
            if target not in all_by_id:
                raise RuntimeError(f"unknown paper dependency {source} -> {target}")
    assert_acyclic(all_ids, paper_direct)
    paper_transitive = closure(all_ids, paper_direct)
    paper_nodes = [
        {
            "formal_id": unit["formal_id"],
            "active_status": unit["active_status"],
            "paper_title": unit["paper_title"],
            "lean_declaration": unit["lean_declaration"],
            "mapping_status": unit["mapping_status"],
            "foundation_axioms": unit["foundation_axioms"],
        }
        for unit in all_units
    ]
    paper_edges = []
    for source in all_ids:
        for target in paper_direct[source]:
            paper_edges.append(
                {
                    "from": source,
                    "to": target,
                    "kind": "PAPER_DIRECT_DEPENDENCY",
                    "lean_from": all_by_id[source].get("lean_declaration"),
                    "lean_to": all_by_id[target].get("lean_declaration"),
                }
            )
    dependency.update(
        {
            "graph_status": "CURRENT_CURATED_EDGES_AND_TRANSITIVE_CLOSURE_RECOMPUTED",
            "formal_registry_sha256": registry_sha,
            "source_tag_gate": tag_gate,
            "nodes": paper_nodes,
            "edges": paper_edges,
            "transitive_dependencies": paper_transitive,
            "cycle_count": 0,
            "active_node_count": 146,
            "normalization_contract_sha256": NORMALIZATION_SHA256,
            "compiler_dependency_graph_sha256": compiler_graph_sha,
            "edge_count": len(paper_edges),
            "regeneration_provenance": {
                "direct_edges_recomputed_from": "formal-units.yaml:direct_dependencies",
                "transitive_closure_recomputed": True,
            },
        }
    )
    dump_json(dependency_path, dependency)

    proof_path = FORMAL / "proof-sketch-audit.json"
    proof = load_json(proof_path)
    for entry in proof["entries"]:
        unit = registry_by_id[entry["formal_id"]]
        entry["paper_title"] = unit["paper_title"]
        entry["central_lean_declaration"] = unit["lean_declaration"]
        entry["central_type_hash"] = unit["statement_hash"]
        entry["foundation_axioms"] = unit["foundation_axioms"]
        entry["registry_paper_direct_dependencies"] = unit["direct_dependencies"]
    proof["audit_status"] = "CURRENT_PROOF_AND_HYPOTHESIS_METADATA_REBOUND_PENDING_FRESH_REVIEW"
    proof["formal_registry_sha256"] = registry_sha
    proof["normalization_contract_sha256"] = NORMALIZATION_SHA256
    proof["regeneration_provenance"] = {
        "paper_fields_regenerated": True,
        "Lean_proof_fields_carried_forward_by_exact_file_hash": True,
    }
    dump_json(proof_path, proof)

    axiom_path = FORMAL / "axiom-report.json"
    axiom = load_json(axiom_path)
    if len(axiom["entries"]) != 83:
        raise RuntimeError("axiom entry count changed")
    for entry in axiom["entries"]:
        unit = registry_by_id[entry["formal_id"]]
        if entry["lean_declaration"] != unit["lean_declaration"]:
            raise RuntimeError(f"axiom declaration mismatch for {unit['formal_id']}")
        entry["statement_hash"] = unit["statement_hash"]
    axiom["status"] = "CURRENT_REGISTRY_BOUND_TO_PRIOR_AXIOM_OUTPUT_BY_EXACT_LEAN_FILE_HASH"
    axiom["formal_units_sha256"] = registry_sha
    axiom["normalization_contract_sha256"] = NORMALIZATION_SHA256
    axiom["regeneration_provenance"] = {
        "fresh_axiom_commands_executed": False,
        "mapped_lean_file_hashes_verified": 146,
        "next_clean_build_gate_pending": True,
    }
    dump_json(axiom_path, axiom)

    artifact_path = FORMAL / "artifact-refinement-map.json"
    artifact = load_json(artifact_path)
    artifact["repository_snapshot"]["formal_registry_sha256"] = registry_sha
    artifact["metadata_rebinding"] = {
        "formal_registry_sha256": registry_sha,
        "java_changes": 0,
        "experimental_result_changes": 0,
        "closure_status_preserved": "PARTIAL",
    }
    dump_json(artifact_path, artifact)

    edge_path = FORMAL / "edge-case-closure.json"
    edge = load_json(edge_path)
    edge["formal_registry_sha256"] = registry_sha
    edge["metadata_rebinding"] = {
        "formal_registry_sha256": registry_sha,
        "claim_changes": 0,
        "status_changes": 0,
    }
    dump_json(edge_path, edge)

    index_path = FORMAL / "formal-statement-index.tex"
    index = index_path.read_text(encoding="utf-8")
    marker = "\\begingroup\\tiny\n"
    if marker not in index:
        raise RuntimeError("formal statement index marker missing")
    table = marker + index.split(marker, 1)[1]
    for unit in active_units:
        escaped_id = unit["formal_id"].replace("-", "-\\allowbreak{}")
        if f"\\texttt{{{escaped_id}}}" not in table:
            raise RuntimeError(f"formal statement index missing {unit['formal_id']}")
    index_header = (
        "% Generated and verified from formal/formal-units.yaml; do not edit by hand.\n"
        "\\subsection{Complete formal statement index}\n"
        "\\label{app:formal-statement-index}\n"
        "The current census contains 146 active formal units with an exact "
        "146-ID/146-declaration source-tag bijection.  Each row names one distinct "
        "Lean declaration; the suffix is the first twelve hexadecimal digits of "
        "its exact pretty-type SHA-256.\n"
    )
    index_path.write_text(index_header + table, encoding="utf-8")

    witness_report = {
        "schema_version": "1.0",
        "status": "EXACT_WITNESS_BYTES_BOUND_SUPPLEMENTAL_TO_146_UNIT_REGISTRY",
        "scope": "CURRENT_CORRESPONDENCE_ONLY_NO_LEAN_BUILD_NO_LATEX_BUILD_NO_PDF_QA",
        "repository": "AlexandervonWu/ACGN",
        "repository_commit": WITNESS_COMMIT,
        "repository_path": WITNESS_REPOSITORY_PATH,
        "repository_git_blob_sha1": WITNESS_BLOB_SHA1,
        "repository_sha256": WITNESS_SHA256,
        "packaged_path": "formal/TypedSlottedEGraphsPaper/TraceEnvelopeWitness.lean",
        "packaged_sha256": sha256_file(witness),
        "byte_identity": True,
        "lake_root": "TypedSlottedEGraphsPaper.TraceEnvelopeWitness",
        "lakefile_sha256": sha256_file(FORMAL / "lakefile.toml"),
        "paper_index_changed": False,
        "active_formal_unit_count_before": 146,
        "active_formal_unit_count_after": 146,
        "active_claim_count_delta": 0,
        "declaration_inventory": {
            "total": 30,
            "structures": 1,
            "inductives": 2,
            "definitions": 19,
            "theorems": 8,
        },
        "historical_focused_build_evidence": {
            "report": "formal/trace-envelope-witness-sync-report.json",
            "witness_sha256_match": True,
            "reported_axiom_union": ["propext", "Quot.sound"],
            "current_round_fresh_build_executed": False,
        },
        "supported_statement": (
            "One fixed nontrivial abstract trace has exact indexed adjacency and "
            "replays under the module's finite-set interpreter to equal endpoint denotations."
        ),
        "explicit_nonclaims": [
            "Java producer-verifier correspondence",
            "parser refinement",
            "whole-artifact correctness",
            "coverage of all trace shapes",
            "experimental trace replay",
        ],
    }
    dump_json(FORMAL / "trace-envelope-witness-binding-report.json", witness_report)

    print(
        json.dumps(
            {
                "formal_registry_sha256": registry_sha,
                "author_source_graph_sha256": registry["source_snapshot"]["active_source_graph_sha256"],
                "formal_source_config_sha256": formal_source_hash,
                "compiler_metadata_sha256": compiler_sha,
                "active_mapping_count": 146,
                "witness_sha256": WITNESS_SHA256,
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    regenerate()
