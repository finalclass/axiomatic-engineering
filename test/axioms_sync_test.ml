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
    {|{"score": 1.4, "reason": "Score out of range should be rejected."}|}
