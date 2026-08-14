let expect_no_contradictions text =
  match Axioms_sync.Consistency.classify_semantic_result text with
  | Axioms_sync.Consistency.No_contradictions -> ()
  | _ -> failwith "expected NO_CONTRADICTIONS result"

let expect_contradictions text =
  match Axioms_sync.Consistency.classify_semantic_result text with
  | Axioms_sync.Consistency.Contradictions _ -> ()
  | _ -> failwith "expected CONTRADICTIONS result"

let expect_invalid text =
  match Axioms_sync.Consistency.classify_semantic_result text with
  | Axioms_sync.Consistency.Invalid_response _ -> ()
  | _ -> failwith "expected invalid semantic response"

let expect_no_candidate_contradictions text =
  match Axioms_sync.Consistency.classify_semantic_candidate_result text with
  | Axioms_sync.Consistency.No_contradiction_candidates -> ()
  | _ -> failwith "expected NO_CONTRADICTIONS candidate result"

let expect_candidate_contradictions text =
  match Axioms_sync.Consistency.classify_semantic_candidate_result text with
  | Axioms_sync.Consistency.Contradiction_candidates _ -> ()
  | _ -> failwith "expected contradiction candidate ids"

let expect_invalid_candidate text =
  match Axioms_sync.Consistency.classify_semantic_candidate_result text with
  | Axioms_sync.Consistency.Invalid_candidate_response _ -> ()
  | _ -> failwith "expected invalid candidate response"

let expect_validation_pass text =
  match Axioms_sync.classify_validation_result text with
  | Axioms_sync.Validation_pass -> ()
  | _ -> failwith "expected validation pass"

let expect_validation_issues text =
  match Axioms_sync.classify_validation_result text with
  | Axioms_sync.Validation_issues _ -> ()
  | _ -> failwith "expected validation issues"

let expect_validation_invalid text =
  match Axioms_sync.classify_validation_result text with
  | Axioms_sync.Validation_invalid _ -> ()
  | _ -> failwith "expected invalid validation response"

let expect_satisfaction_ok text =
  match Axioms_sync.classify_satisfaction_result text with
  | Axioms_sync.Satisfaction_ok _ -> ()
  | _ -> failwith "expected valid satisfaction response"

let expect_satisfaction_invalid text =
  match Axioms_sync.classify_satisfaction_result text with
  | Axioms_sync.Satisfaction_invalid _ -> ()
  | _ -> failwith "expected invalid satisfaction response"

let make_label name =
  { Axioms_sync.Types.name
  ; phases= [Axioms_sync.Types.Implementation]
  ; hidden_phases= []
  ; markers= []
  ; model_class= None
  ; description= "" }

let make_task ~axiom_id ~label ~context =
  { Axioms_sync.Types.axiom_id
  ; section_anchor= None
  ; label= make_label label
  ; phase= Axioms_sync.Types.Implementation
  ; context
  ; model_class= Axioms_sync.Types.Smart }

let expect_planning_axiom_dedup () =
  let tasks =
    [ make_task ~axiom_id:"a.md" ~label:"api" ~context:"same context"
    ; make_task ~axiom_id:"a.md" ~label:"ui" ~context:"same context"
    ; make_task ~axiom_id:"b.md" ~label:"worker" ~context:"other context" ]
  in
  let axioms = Axioms_sync.planning_axioms_of_impl_tasks tasks in
  match axioms with
  | [a; b] ->
      if a.axiom_id <> "a.md" then failwith "expected first axiom to be a.md" ;
      if a.labels <> ["api"; "ui"] then failwith "expected merged labels" ;
      if b.axiom_id <> "b.md" then failwith "expected second axiom to be b.md"
  | _ -> failwith "expected tasks to be deduplicated by axiom"

let expect_planning_budget_compacts () =
  let long_text = String.make 4000 'x' in
  let tasks = [make_task ~axiom_id:"a.md" ~label:"api" ~context:long_text] in
  let axiom =
    Axioms_sync.planning_axioms_of_impl_tasks tasks
    |> Axioms_sync.apply_planning_context_budget ~total_budget:1200
    |> List.hd
  in
  if String.length axiom.context > 1200
  then failwith "expected planning context to respect budget" ;
  if not (String.contains axiom.context '.')
  then failwith "expected compacted planning context to contain an ellipsis marker"

let () =
  expect_no_candidate_contradictions "NO_CONTRADICTIONS" ;
  expect_candidate_contradictions
    "CONTRADICTION_IDS: planner/main.md, planner/metadata/add-schema.md" ;
  expect_invalid_candidate "Znaleziono jedną sprzeczność między aksjomatami." ;
  expect_no_contradictions "NO_CONTRADICTIONS" ;
  expect_contradictions
    "CONTRADICTION\n\
     Axiom IDs: planner/main.md, planner/metadata/add-schema.md\n\
     Statements:\n\
     - The user must always be redirected immediately after creation.\n\
     - The user must remain on the form until they click Save.\n\
     Why impossible: The same flow cannot both redirect immediately and keep the \
     user on the form.\n\
     END_CONTRADICTION" ;
  expect_invalid
    "Dokumentacja jest spójna, logiczna i bardzo dobrze skonstruowana pod kątem \
     architektonicznym. Istnieje jednak jedna bezpośrednia i niemożliwa do \
     jednoc" ;
  expect_validation_pass "NO ISSUES" ;
  expect_validation_pass "Final verdict:\nNO ISSUES\nThanks." ;
  expect_validation_issues "ISSUES:\n- Missing handler for metadata schema migration." ;
  expect_validation_issues
    "Analysis complete.\n\nISSUES:\n- Missing handler for metadata schema migration." ;
  expect_validation_invalid
    "W większości wygląda dobrze, ale chcę jeszcze sprawdzić routing zanim \
     wydam werdykt" ;
  expect_satisfaction_ok {|{"score": 0.82, "reason": "Implementation matches the required flow."}|} ;
  expect_satisfaction_ok
    {|Judge notes:
```json
{"score": 0.82, "reason": "Implementation matches the required flow."}
```
|} ;
  expect_satisfaction_invalid "0.82 maybe okay overall" ;
  expect_satisfaction_invalid
    {|{"score": 1.4, "reason": "Score out of range should be rejected."}|} ;
  expect_planning_axiom_dedup () ;
  expect_planning_budget_compacts ()
