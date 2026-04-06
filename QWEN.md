## Qwen Added Memories
- Project: axiomatic-engineering — OCaml CLI tool "axioms-sync" that reads axiom specs (markdown), diffs against frozen state, and uses AI agents to implement/validate changes in code.

Key workflow: user edits axioms/ → runs `axioms-sync [--axiom ID]` → AI agents update code/

Architecture:
- lib/types/types.ml — core types: axiom, axiom_system, label_def (with phases: @implementation, @validation, @satisfaction), task, config, axiom_change
- lib/loader/loader.ml — parses axiom markdown files with label cascade, glossary, refs
- lib/changes.ml — computes changes: Full (all axioms), Diff (snapshot vs freeze), Specific (--axiom flag → returns matched axioms as Modified)
- lib/planner/planner.ml — generates implementation/validation/satisfaction tasks; filter_content strips content with forbidden labels from context
- lib/consistency/consistency.ml — checks ref links, semantic consistency
- lib/markers/markers.ml — validates @axiom markers in code against axiom files
- lib/snapshot.ml — creates/restores freeze files for diff mode
- lib/config/config.ml — merges global (~/.config/axioms-sync.toml), project (.axioms/axioms-sync.toml), CLI args, env vars
- lib/axioms_sync.ml — orchestrator: load → consistency → changes → markers → planner
- bin/main.ml — CLI entry point (mostly commented out during development)

Label scoping rules (filter_content in planner.ml):
1. Label in ## heading → applies to whole section
2. Label on own line → context switch until blank line
3. Label inline with text → applies to that line only
4. Blank line resets context to section-level labels

Build: dune build && make install → ~/.local/bin/axioms-sync
Tests: in test/axioms_sync_test.ml
