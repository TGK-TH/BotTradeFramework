#property strict
#property version "1.00"
#property description "Grid Entry Execution Policy unit tests; pure decision only, no trading."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridEntryExecutionPolicy.mqh>

CTGKTestRunner Tests;
CTGKGridEntryExecutionPolicy Policy;

void SetValidCandidate(STGKGridEntryExecutionCandidate &candidate)
{
  candidate.instance_id = "UT_INSTANCE";
  candidate.symbol = "XAUUSD";
  candidate.magic_number = 710001;
  candidate.mode = TGK_GRID_MODE_BUY;
  candidate.config_epoch = 1;
  candidate.target_level.is_anchor = false;
  candidate.target_level.level_index = 0;
  candidate.entry_price = 3995.0;
}

void SetValidLevelContext(STGKGridEntryExecutionLevelContext &context)
{
  context.level_exists = true;
  context.level_state = TGK_GRID_LEVEL_READY;
  context.has_position_mapping = false;
}

void SetValidExecutionContext(STGKGridEntryExecutionContext &context)
{
  context.has_unresolved_request = false;
  context.identity_valid = true;
  context.execution_state = TGK_GRID_ENTRY_EXECUTION_NORMAL;
}

void AssertEvaluation(
  string assertion_prefix,
  STGKGridEntryExecutionCandidate &candidate,
  STGKGridEntryExecutionLevelContext &level_context,
  STGKGridEntryExecutionContext &execution_context,
  ENUM_TGK_GRID_ENTRY_DECISION expected_decision,
  ENUM_TGK_GRID_ENTRY_REASON expected_reason
)
{
  STGKGridEntryExecutionResult result;
  Policy.Evaluate(
    candidate,
    level_context,
    execution_context,
    result);

  Tests.AssertEqualInt(
    assertion_prefix + " decision",
    (int)result.decision,
    (int)expected_decision);
  Tests.AssertEqualInt(
    assertion_prefix + " reason",
    (int)result.reason_code,
    (int)expected_reason);
  Tests.AssertEqualInt(
    assertion_prefix + " target is copied",
    result.target_level.is_anchor == candidate.target_level.is_anchor &&
    result.target_level.level_index == candidate.target_level.level_index
      ? 1
      : 0,
    1);
}

void AssertAllow(
  string assertion_prefix,
  STGKGridEntryExecutionCandidate &candidate,
  STGKGridEntryExecutionLevelContext &level_context,
  STGKGridEntryExecutionContext &execution_context
)
{
  AssertEvaluation(
    assertion_prefix,
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_DECISION_ALLOW,
    TGK_GRID_ENTRY_REASON_ELIGIBLE);
}

void AssertReject(
  string assertion_prefix,
  STGKGridEntryExecutionCandidate &candidate,
  STGKGridEntryExecutionLevelContext &level_context,
  STGKGridEntryExecutionContext &execution_context,
  ENUM_TGK_GRID_ENTRY_REASON expected_reason
)
{
  AssertEvaluation(
    assertion_prefix,
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_DECISION_REJECT,
    expected_reason);
}

int OnInit()
{
  Tests.BeginSuite("TGK Grid Entry Execution Policy");

  STGKGridEntryExecutionCandidate candidate;
  STGKGridEntryExecutionLevelContext level_context;
  STGKGridEntryExecutionContext execution_context;

  // Group A — Valid Candidate (4)

  Tests.BeginTest("A01 READY Anchor permits a valid Candidate");
  SetValidCandidate(candidate);
  candidate.target_level.is_anchor = true;
  candidate.target_level.level_index = -1;
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  AssertAllow(
    "READY Anchor",
    candidate,
    level_context,
    execution_context);
  Tests.EndTest();

  Tests.BeginTest("A02 WAIT_RETURN Level permits a valid Candidate");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  level_context.level_state = TGK_GRID_LEVEL_WAIT_RETURN;
  SetValidExecutionContext(execution_context);
  AssertAllow(
    "WAIT_RETURN",
    candidate,
    level_context,
    execution_context);
  Tests.EndTest();

  Tests.BeginTest("A03 BUY Grid Mode is accepted");
  SetValidCandidate(candidate);
  candidate.mode = TGK_GRID_MODE_BUY;
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  AssertAllow(
    "BUY mode",
    candidate,
    level_context,
    execution_context);
  Tests.EndTest();

  Tests.BeginTest("A04 SELL Grid Mode is accepted");
  SetValidCandidate(candidate);
  candidate.mode = TGK_GRID_MODE_SELL;
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  AssertAllow(
    "SELL mode",
    candidate,
    level_context,
    execution_context);
  Tests.EndTest();

  // Group B — Candidate Validation (9)

  Tests.BeginTest("B01 Empty Instance ID is invalid");
  SetValidCandidate(candidate);
  candidate.instance_id = "";
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  AssertReject(
    "empty Instance ID",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_INVALID_CANDIDATE);
  Tests.EndTest();

  Tests.BeginTest("B02 Empty Symbol is invalid");
  SetValidCandidate(candidate);
  candidate.symbol = "";
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  AssertReject(
    "empty Symbol",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_INVALID_CANDIDATE);
  Tests.EndTest();

  Tests.BeginTest("B03 Non-positive Magic Number is invalid");
  SetValidCandidate(candidate);
  candidate.magic_number = 0;
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  AssertReject(
    "invalid Magic",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_INVALID_CANDIDATE);
  Tests.EndTest();

  Tests.BeginTest("B04 Unknown Grid Mode is invalid");
  SetValidCandidate(candidate);
  candidate.mode = (ENUM_TGK_GRID_MODE)99;
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  AssertReject(
    "unknown Grid Mode",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_INVALID_CANDIDATE);
  Tests.EndTest();

  Tests.BeginTest("B05 Non-positive Config Epoch is invalid");
  SetValidCandidate(candidate);
  candidate.config_epoch = 0;
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  AssertReject(
    "invalid Config Epoch",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_INVALID_CANDIDATE);
  Tests.EndTest();

  Tests.BeginTest("B06 Invalid Anchor and Level index representation is rejected");
  SetValidCandidate(candidate);
  candidate.target_level.is_anchor = true;
  candidate.target_level.level_index = 0;
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  AssertReject(
    "invalid Target Level",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_INVALID_CANDIDATE);
  Tests.EndTest();

  Tests.BeginTest("B07 Zero Entry Price is invalid");
  SetValidCandidate(candidate);
  candidate.entry_price = 0.0;
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  AssertReject(
    "zero Entry Price",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_INVALID_CANDIDATE);
  Tests.EndTest();

  Tests.BeginTest("B08 Negative Entry Price is invalid");
  SetValidCandidate(candidate);
  candidate.entry_price = -1.0;
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  AssertReject(
    "negative Entry Price",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_INVALID_CANDIDATE);
  Tests.EndTest();

  Tests.BeginTest("B09 NaN and Infinity Entry Prices are invalid");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  candidate.entry_price = MathArcsin(2.0);
  AssertReject(
    "NaN Entry Price",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_INVALID_CANDIDATE);
  candidate.entry_price = MathExp(1000.0);
  AssertReject(
    "Infinity Entry Price",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_INVALID_CANDIDATE);
  Tests.EndTest();

  // Group C — Identity & Execution State (6)

  Tests.BeginTest("C01 Identity mismatch is rejected");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  execution_context.identity_valid = false;
  AssertReject(
    "Identity mismatch",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_IDENTITY_MISMATCH);
  Tests.EndTest();

  Tests.BeginTest("C02 NORMAL Execution State allows an otherwise valid Candidate");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  AssertAllow(
    "NORMAL execution",
    candidate,
    level_context,
    execution_context);
  Tests.EndTest();

  Tests.BeginTest("C03 MAINTENANCE_ERROR blocks entry");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  execution_context.execution_state = TGK_GRID_ENTRY_EXECUTION_MAINTENANCE_ERROR;
  AssertReject(
    "Maintenance Error",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_EXECUTION_BLOCKED);
  Tests.EndTest();

  Tests.BeginTest("C04 RECOVERY_ERROR blocks entry");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  execution_context.execution_state = TGK_GRID_ENTRY_EXECUTION_RECOVERY_ERROR;
  AssertReject(
    "Recovery Error",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_EXECUTION_BLOCKED);
  Tests.EndTest();

  Tests.BeginTest("C05 Unknown Execution State fails closed");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  execution_context.execution_state = (ENUM_TGK_GRID_ENTRY_EXECUTION_STATE)99;
  AssertReject(
    "Unknown execution state",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_EXECUTION_BLOCKED);
  Tests.EndTest();

  Tests.BeginTest("C06 Identity mismatch precedes Execution Blocked");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  execution_context.identity_valid = false;
  execution_context.execution_state = TGK_GRID_ENTRY_EXECUTION_RECOVERY_ERROR;
  AssertReject(
    "Identity before blocked",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_IDENTITY_MISMATCH);
  Tests.EndTest();

  // Group D — Request & Level Eligibility (9)

  Tests.BeginTest("D01 Unresolved Request blocks a new Entry");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  execution_context.has_unresolved_request = true;
  AssertReject(
    "Unresolved Request",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_UNRESOLVED_REQUEST);
  Tests.EndTest();

  Tests.BeginTest("D02 Missing Target Level is rejected");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  level_context.level_exists = false;
  AssertReject(
    "Level missing",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_LEVEL_NOT_FOUND);
  Tests.EndTest();

  Tests.BeginTest("D03 ACTIVE Level is not eligible");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  level_context.level_state = TGK_GRID_LEVEL_ACTIVE;
  AssertReject(
    "ACTIVE Level",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_LEVEL_NOT_ELIGIBLE);
  Tests.EndTest();

  Tests.BeginTest("D04 WAIT_ACTIVATION Level is not eligible");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  level_context.level_state = TGK_GRID_LEVEL_WAIT_ACTIVATION;
  AssertReject(
    "WAIT_ACTIVATION Level",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_LEVEL_NOT_ELIGIBLE);
  Tests.EndTest();

  Tests.BeginTest("D05 Unknown Level State fails closed");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  level_context.level_state = (ENUM_TGK_GRID_LEVEL_STATE)99;
  AssertReject(
    "Unknown Level State",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_LEVEL_NOT_ELIGIBLE);
  Tests.EndTest();

  Tests.BeginTest("D06 READY Level without Position Mapping is eligible");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  AssertAllow(
    "READY unmapped",
    candidate,
    level_context,
    execution_context);
  Tests.EndTest();

  Tests.BeginTest("D07 WAIT_RETURN Level without Position Mapping is eligible");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  level_context.level_state = TGK_GRID_LEVEL_WAIT_RETURN;
  SetValidExecutionContext(execution_context);
  AssertAllow(
    "WAIT_RETURN unmapped",
    candidate,
    level_context,
    execution_context);
  Tests.EndTest();

  Tests.BeginTest("D08 Already mapped Target Level is rejected");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  level_context.has_position_mapping = true;
  AssertReject(
    "Already mapped",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_ALREADY_MAPPED);
  Tests.EndTest();

  Tests.BeginTest("D09 Missing Level takes precedence over Mapping flag");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  level_context.level_exists = false;
  level_context.has_position_mapping = true;
  AssertReject(
    "Missing before mapped",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_LEVEL_NOT_FOUND);
  Tests.EndTest();

  // Group E — Decision Precedence (6)

  Tests.BeginTest("E01 INVALID_CANDIDATE precedes IDENTITY_MISMATCH");
  SetValidCandidate(candidate);
  candidate.symbol = "";
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  execution_context.identity_valid = false;
  AssertReject(
    "Invalid Candidate precedence",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_INVALID_CANDIDATE);
  Tests.EndTest();

  Tests.BeginTest("E02 IDENTITY_MISMATCH precedes EXECUTION_BLOCKED");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  execution_context.identity_valid = false;
  execution_context.execution_state = TGK_GRID_ENTRY_EXECUTION_MAINTENANCE_ERROR;
  AssertReject(
    "Identity precedence",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_IDENTITY_MISMATCH);
  Tests.EndTest();

  Tests.BeginTest("E03 EXECUTION_BLOCKED precedes UNRESOLVED_REQUEST");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  execution_context.execution_state = TGK_GRID_ENTRY_EXECUTION_RECOVERY_ERROR;
  execution_context.has_unresolved_request = true;
  AssertReject(
    "Execution precedence",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_EXECUTION_BLOCKED);
  Tests.EndTest();

  Tests.BeginTest("E04 UNRESOLVED_REQUEST precedes LEVEL_NOT_FOUND");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  execution_context.has_unresolved_request = true;
  level_context.level_exists = false;
  AssertReject(
    "Request precedence",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_UNRESOLVED_REQUEST);
  Tests.EndTest();

  Tests.BeginTest("E05 LEVEL_NOT_FOUND precedes LEVEL_NOT_ELIGIBLE");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  level_context.level_exists = false;
  level_context.level_state = TGK_GRID_LEVEL_ACTIVE;
  AssertReject(
    "Level missing precedence",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_LEVEL_NOT_FOUND);
  Tests.EndTest();

  Tests.BeginTest("E06 LEVEL_NOT_ELIGIBLE precedes ALREADY_MAPPED");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  level_context.level_state = TGK_GRID_LEVEL_ACTIVE;
  level_context.has_position_mapping = true;
  AssertReject(
    "Eligibility precedence",
    candidate,
    level_context,
    execution_context,
    TGK_GRID_ENTRY_REASON_LEVEL_NOT_ELIGIBLE);
  Tests.EndTest();

  // Group F — Stateless & Deterministic (6)

  Tests.BeginTest("F01 Repeated evaluation is deterministic");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  STGKGridEntryExecutionResult first_result;
  STGKGridEntryExecutionResult second_result;
  Policy.Evaluate(
    candidate,
    level_context,
    execution_context,
    first_result);
  Policy.Evaluate(
    candidate,
    level_context,
    execution_context,
    second_result);
  Tests.AssertEqualInt("same Decision",
    (int)second_result.decision, (int)first_result.decision);
  Tests.AssertEqualInt("same Reason",
    (int)second_result.reason_code, (int)first_result.reason_code);
  Tests.AssertEqualInt("same Target Level",
    second_result.target_level.level_index, first_result.target_level.level_index);
  Tests.EndTest();

  Tests.BeginTest("F02 Evaluating one Candidate does not affect another Candidate");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  STGKGridEntryExecutionResult first_candidate_result;
  Policy.Evaluate(
    candidate,
    level_context,
    execution_context,
    first_candidate_result);
  STGKGridEntryExecutionCandidate second_candidate;
  SetValidCandidate(second_candidate);
  second_candidate.target_level.level_index = 7;
  second_candidate.entry_price = 4030.0;
  STGKGridEntryExecutionResult second_candidate_result;
  Policy.Evaluate(
    second_candidate,
    level_context,
    execution_context,
    second_candidate_result);
  STGKGridEntryExecutionResult first_candidate_recheck;
  Policy.Evaluate(
    candidate,
    level_context,
    execution_context,
    first_candidate_recheck);
  Tests.AssertEqualInt("first Candidate remains eligible",
    (int)first_candidate_result.reason_code, (int)TGK_GRID_ENTRY_REASON_ELIGIBLE);
  Tests.AssertEqualInt("first Candidate remains deterministic after second evaluation",
    (int)first_candidate_recheck.reason_code, (int)first_candidate_result.reason_code);
  Tests.AssertEqualInt("second Candidate independently eligible",
    (int)second_candidate_result.reason_code, (int)TGK_GRID_ENTRY_REASON_ELIGIBLE);
  Tests.AssertEqualInt("second Target Level is preserved",
    second_candidate_result.target_level.level_index, 7);
  Tests.EndTest();

  Tests.BeginTest("F03 Repeated rejection does not mutate Policy or input contexts");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  execution_context.has_unresolved_request = true;
  STGKGridEntryExecutionResult rejected_once;
  STGKGridEntryExecutionResult rejected_twice;
  Policy.Evaluate(
    candidate,
    level_context,
    execution_context,
    rejected_once);
  Policy.Evaluate(
    candidate,
    level_context,
    execution_context,
    rejected_twice);
  Tests.AssertEqualInt("first rejection reason",
    (int)rejected_once.reason_code, (int)TGK_GRID_ENTRY_REASON_UNRESOLVED_REQUEST);
  Tests.AssertEqualInt("second rejection reason",
    (int)rejected_twice.reason_code, (int)TGK_GRID_ENTRY_REASON_UNRESOLVED_REQUEST);
  Tests.AssertTrue("unresolved flag remains set", execution_context.has_unresolved_request);
  Tests.AssertTrue("identity remains valid", execution_context.identity_valid);
  Tests.EndTest();

  Tests.BeginTest("F04 Evaluate does not mutate Candidate or Context inputs");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  string original_instance_id = candidate.instance_id;
  string original_symbol = candidate.symbol;
  long original_magic = candidate.magic_number;
  int original_mode = (int)candidate.mode;
  long original_epoch = candidate.config_epoch;
  bool original_target_is_anchor = candidate.target_level.is_anchor;
  int original_target_level_index = candidate.target_level.level_index;
  double original_entry_price = candidate.entry_price;
  int original_level_state = (int)level_context.level_state;
  bool original_level_exists = level_context.level_exists;
  bool original_mapping = level_context.has_position_mapping;
  bool original_identity = execution_context.identity_valid;
  bool original_unresolved = execution_context.has_unresolved_request;
  int original_execution_state = (int)execution_context.execution_state;
  STGKGridEntryExecutionResult result;
  Policy.Evaluate(
    candidate,
    level_context,
    execution_context,
    result);
  Tests.AssertEqualString(
    "Instance ID unchanged",
    candidate.instance_id,
    original_instance_id);
  Tests.AssertEqualString(
    "Symbol unchanged",
    candidate.symbol,
    original_symbol);
  Tests.AssertEqualLong(
    "Magic unchanged",
    candidate.magic_number,
    original_magic);
  Tests.AssertEqualInt("Mode unchanged", (int)candidate.mode, original_mode);
  Tests.AssertEqualLong(
    "Epoch unchanged",
    candidate.config_epoch,
    original_epoch);
  Tests.AssertEqualInt("Target Anchor flag unchanged",
    candidate.target_level.is_anchor ? 1 : 0, original_target_is_anchor ? 1 : 0);
  Tests.AssertEqualInt("Target Level index unchanged",
    candidate.target_level.level_index, original_target_level_index);
  Tests.AssertEqualDouble(
    "Entry Price unchanged",
    candidate.entry_price,
    original_entry_price);
  Tests.AssertEqualInt("Level State unchanged",
    (int)level_context.level_state, original_level_state);
  Tests.AssertEqualInt("Level Exists unchanged",
    level_context.level_exists ? 1 : 0, original_level_exists ? 1 : 0);
  Tests.AssertEqualInt("Mapping unchanged",
    level_context.has_position_mapping ? 1 : 0, original_mapping ? 1 : 0);
  Tests.AssertEqualInt("Identity unchanged",
    execution_context.identity_valid ? 1 : 0, original_identity ? 1 : 0);
  Tests.AssertEqualInt("Unresolved unchanged",
    execution_context.has_unresolved_request ? 1 : 0, original_unresolved ? 1 : 0);
  Tests.AssertEqualInt("Execution State unchanged",
    (int)execution_context.execution_state, original_execution_state);
  Tests.EndTest();

  Tests.BeginTest("F05 Fresh blocked Context changes an eligible Candidate to REJECT");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  STGKGridEntryExecutionResult normal_result;
  Policy.Evaluate(
    candidate,
    level_context,
    execution_context,
    normal_result);
  execution_context.execution_state = TGK_GRID_ENTRY_EXECUTION_MAINTENANCE_ERROR;
  STGKGridEntryExecutionResult blocked_result;
  Policy.Evaluate(
    candidate,
    level_context,
    execution_context,
    blocked_result);
  Tests.AssertEqualInt("NORMAL context allows",
    (int)normal_result.decision, (int)TGK_GRID_ENTRY_DECISION_ALLOW);
  Tests.AssertEqualInt("Blocked fresh context rejects",
    (int)blocked_result.decision, (int)TGK_GRID_ENTRY_DECISION_REJECT);
  Tests.AssertEqualInt("Blocked reason is explicit",
    (int)blocked_result.reason_code, (int)TGK_GRID_ENTRY_REASON_EXECUTION_BLOCKED);
  Tests.EndTest();

  Tests.BeginTest("F06 Fresh NORMAL Context reevaluates after a prior Blocked result");
  SetValidCandidate(candidate);
  SetValidLevelContext(level_context);
  SetValidExecutionContext(execution_context);
  execution_context.execution_state = TGK_GRID_ENTRY_EXECUTION_RECOVERY_ERROR;
  STGKGridEntryExecutionResult prior_blocked_result;
  Policy.Evaluate(
    candidate,
    level_context,
    execution_context,
    prior_blocked_result);
  execution_context.execution_state = TGK_GRID_ENTRY_EXECUTION_NORMAL;
  STGKGridEntryExecutionResult fresh_normal_result;
  Policy.Evaluate(
    candidate,
    level_context,
    execution_context,
    fresh_normal_result);
  Tests.AssertEqualInt("prior Blocked context rejected",
    (int)prior_blocked_result.reason_code, (int)TGK_GRID_ENTRY_REASON_EXECUTION_BLOCKED);
  Tests.AssertEqualInt("fresh NORMAL context allows",
    (int)fresh_normal_result.decision, (int)TGK_GRID_ENTRY_DECISION_ALLOW);
  Tests.AssertEqualInt("fresh NORMAL reason is ELIGIBLE",
    (int)fresh_normal_result.reason_code, (int)TGK_GRID_ENTRY_REASON_ELIGIBLE);
  Tests.EndTest();

  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick()
{
}
