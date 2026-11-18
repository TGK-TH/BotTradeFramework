#property strict
#property version "1.00"
#property description "Grid Entry Execution Resolver integration tests; no trading."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridEntryExecutionResolver.mqh>

CTGKTestRunner Tests;
CTGKGridEntryExecutionCaller Caller;

void AddRecord(
  STGKGridMappingJournalRecord &records[],
  long sequence,
  ENUM_TGK_GRID_MAPPING_RECORD_TYPE record_type,
  string payload
)
{
  int index = ArraySize(records);
  ArrayResize(records, index + 1);
  records[index].sequence = sequence;
  records[index].record_type = record_type;
  records[index].payload = payload;
}

void AddBaseConfiguration(STGKGridMappingJournalRecord &records[])
{
  AddRecord(
    records,
    1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|RESET_COMMITTED|1|BUY|5.0|3960.0|4040.0|4000.0|17");
}

void AddMappedLevelSeven(STGKGridMappingJournalRecord &records[])
{
  AddRecord(
    records,
    2,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-007|XAUUSD|710001|BUY|LEVEL|7|0.01|1|UT-INSTANCE");
  AddRecord(
    records,
    3,
    TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
    "v1|REQ-007|DONE|1000007|0");
  AddRecord(
    records,
    4,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    "v1|REQ-007|2000007|3000007|0.01");
  AddRecord(
    records,
    5,
    TGK_GRID_MAPPING_RECORD_POSITION_MAPPING,
    "v1|REQ-007|XAUUSD|710001|LEVEL|7|3000007|4000007|0.01|1|UT-INSTANCE");
}

void AddMappedAnchor(STGKGridMappingJournalRecord &records[])
{
  AddRecord(
    records,
    2,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-ANCHOR|XAUUSD|710001|BUY|ANCHOR|-1|0.01|1|UT-INSTANCE");
  AddRecord(
    records,
    3,
    TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
    "v1|REQ-ANCHOR|DONE|1000008|0");
  AddRecord(
    records,
    4,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    "v1|REQ-ANCHOR|2000008|3000008|0.01");
  AddRecord(
    records,
    5,
    TGK_GRID_MAPPING_RECORD_POSITION_MAPPING,
    "v1|REQ-ANCHOR|XAUUSD|710001|ANCHOR|-1|3000008|4000008|0.01|1|UT-INSTANCE");
}

bool InitializeCoordinator(CTGKGridLevelRuntimeCoordinator &coordinator)
{
  bool initialized = coordinator.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3960.0,
    4040.0,
    16,
    "XAUUSD",
    710001,
    3995.0,
    3996.0);
  bool epoch_bound = initialized && coordinator.BindConfigEpoch(1);
  Tests.AssertTrue(
    "fixture Coordinator initialized and bound to Config Epoch 1",
    epoch_bound);
  return epoch_bound;
}

bool InitializeCoordinatorForEpoch(
  CTGKGridLevelRuntimeCoordinator &coordinator,
  long config_epoch
)
{
  bool initialized = coordinator.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3960.0,
    4040.0,
    16,
    "XAUUSD",
    710001,
    3995.0,
    3996.0);
  return initialized && coordinator.BindConfigEpoch(config_epoch);
}

bool InitializeReducer(
  CTGKGridEntryMappingReducer &reducer,
  STGKGridMappingJournalRecord &records[]
)
{
  bool initialized = reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE");
  bool replayed = initialized &&
                  reducer.Replay(records, ArraySize(records));
  Tests.AssertTrue("fixture Reducer initialized and replayed", replayed);
  return replayed;
}

bool InitializeMappedLevelSeven(
  CTGKGridLevelRuntimeCoordinator &coordinator,
  CTGKGridEntryMappingReducer &reducer
)
{
  if(!InitializeCoordinator(coordinator))
    return false;

  STGKGridLevelCandidate offered_candidate;
  ENUM_TGK_GRID_COORDINATOR_RESULT result;
  if(coordinator.UpdatePrice(
    3994.0,
    3995.0,
    result,
    offered_candidate) != TGK_GRID_COORDINATOR_CANDIDATE_READY ||
     offered_candidate.is_anchor ||
     offered_candidate.level_index != 7 ||
     !coordinator.RecordEntryRequest(
       offered_candidate,
       TGK_GRID_ENTRY_REQUEST_ACCEPTED))
    return false;

  STGKGridLevelPositionRecord position;
  position.ticket = 4000007;
  position.symbol = "XAUUSD";
  position.magic_number = 710001;
  position.is_anchor = false;
  position.level_index = 7;
  position.volume = 0.01;

  STGKGridLevelPositionRecord positions[];
  ArrayResize(positions, 1);
  positions[0] = position;
  STGKGridLevelCloseEvent close_events[];
  STGKGridLevelCandidate next_candidate;
  if(coordinator.Reconcile(
    positions,
    close_events,
    TGK_GRID_ENTRY_RESOLUTION_PENDING,
    3994.0,
    3995.0,
    result,
    next_candidate) == TGK_GRID_COORDINATOR_ERROR)
    return false;

  STGKGridMappingJournalRecord records[];
  AddBaseConfiguration(records);
  AddMappedLevelSeven(records);
  return InitializeReducer(reducer, records);
}

void SetCandidate(
  STGKGridEntryExecutionCandidate &candidate,
  int level_index
)
{
  candidate.instance_id = "UT-INSTANCE";
  candidate.symbol = "XAUUSD";
  candidate.magic_number = 710001;
  candidate.mode = TGK_GRID_MODE_BUY;
  candidate.config_epoch = 1;
  candidate.target_level.is_anchor = false;
  candidate.target_level.level_index = level_index;
  candidate.entry_price = (level_index == 7) ? 3995.0 : 3960.0;
}

void SetResultSentinel(STGKGridEntryExecutionResult &result)
{
  result.decision = (ENUM_TGK_GRID_ENTRY_DECISION)99;
  result.reason_code = (ENUM_TGK_GRID_ENTRY_REASON)99;
  result.target_level.is_anchor = true;
  result.target_level.level_index = 4321;
}

void AssertResult(
  string prefix,
  STGKGridEntryExecutionResult &result,
  STGKGridEntryExecutionCandidate &candidate,
  ENUM_TGK_GRID_ENTRY_DECISION decision,
  ENUM_TGK_GRID_ENTRY_REASON reason
)
{
  Tests.AssertEqualInt(
    prefix + " decision",
    (int)result.decision,
    (int)decision);
  Tests.AssertEqualInt(
    prefix + " reason",
    (int)result.reason_code,
    (int)reason);
  Tests.AssertEqualInt(
    prefix + " copied target",
    result.target_level.is_anchor == candidate.target_level.is_anchor &&
    result.target_level.level_index == candidate.target_level.level_index
      ? 1
      : 0,
    1);
}

void AssertResolverFailurePreservesResult(
  string prefix,
  STGKGridEntryExecutionResult &result
)
{
  Tests.AssertEqualInt(
    prefix + " does not call Policy decision",
    (int)result.decision,
    99);
  Tests.AssertEqualInt(
    prefix + " does not call Policy reason",
    (int)result.reason_code,
    99);
  Tests.AssertEqualInt(
    prefix + " preserves target output",
    result.target_level.is_anchor &&
    result.target_level.level_index == 4321
      ? 1
      : 0,
    1);
}

int OnInit()
{
  Tests.BeginSuite("TGK Grid Entry Execution Resolver");

  Tests.BeginTest("A01 Current Level 0 resolves to READY and unmapped");
  CTGKGridLevelRuntimeCoordinator coordinator_a01;
  CTGKGridEntryMappingReducer reducer_a01;
  InitializeCoordinator(coordinator_a01);
  STGKGridMappingJournalRecord records_a01[];
  AddBaseConfiguration(records_a01);
  InitializeReducer(reducer_a01, records_a01);
  STGKGridEntryExecutionCandidate candidate_a01;
  SetCandidate(candidate_a01, 0);
  STGKGridEntryExecutionResult result_a01;
  Tests.AssertTrue(
    "Caller evaluates resolved context",
    Caller.Evaluate(
      candidate_a01,
      coordinator_a01,
      reducer_a01,
      TGK_GRID_ENTRY_EXECUTION_NORMAL,
      result_a01));
  AssertResult(
    "Level 0",
    result_a01,
    candidate_a01,
    TGK_GRID_ENTRY_DECISION_ALLOW,
    TGK_GRID_ENTRY_REASON_ELIGIBLE);
  Tests.EndTest();

  Tests.BeginTest("A02 Anchor context is resolved from the current Instance");
  CTGKGridLevelRuntimeCoordinator coordinator_a02;
  CTGKGridEntryMappingReducer reducer_a02;
  InitializeCoordinator(coordinator_a02);
  STGKGridLevelPositionRecord anchor_position;
  anchor_position.ticket = 4000008;
  anchor_position.symbol = "XAUUSD";
  anchor_position.magic_number = 710001;
  anchor_position.is_anchor = true;
  anchor_position.level_index = -1;
  anchor_position.volume = 0.01;
  Tests.AssertTrue(
    "register initial Anchor in runtime",
    coordinator_a02.RegisterInitialAnchorPosition(anchor_position));
  STGKGridMappingJournalRecord records_a02[];
  AddBaseConfiguration(records_a02);
  AddMappedAnchor(records_a02);
  InitializeReducer(reducer_a02, records_a02);
  STGKGridEntryExecutionCandidate candidate_a02;
  SetCandidate(candidate_a02, -1);
  candidate_a02.target_level.is_anchor = true;
  candidate_a02.entry_price = 4000.0;
  STGKGridEntryExecutionResult result_a02;
  Tests.AssertTrue(
    "Anchor target resolves",
    Caller.Evaluate(
      candidate_a02,
      coordinator_a02,
      reducer_a02,
      TGK_GRID_ENTRY_EXECUTION_NORMAL,
      result_a02));
  AssertResult(
    "Mapped Anchor",
    result_a02,
    candidate_a02,
    TGK_GRID_ENTRY_DECISION_REJECT,
    TGK_GRID_ENTRY_REASON_LEVEL_NOT_ELIGIBLE);
  Tests.EndTest();

  Tests.BeginTest("B01 Different Instance ID fails closed without Policy call");
  CTGKGridLevelRuntimeCoordinator coordinator_b01;
  CTGKGridEntryMappingReducer reducer_b01;
  InitializeCoordinator(coordinator_b01);
  STGKGridMappingJournalRecord records_b01[];
  AddBaseConfiguration(records_b01);
  InitializeReducer(reducer_b01, records_b01);
  STGKGridEntryExecutionCandidate candidate_b01;
  SetCandidate(candidate_b01, 0);
  candidate_b01.instance_id = "OTHER-INSTANCE";
  STGKGridEntryExecutionResult result_b01;
  SetResultSentinel(result_b01);
  Tests.AssertFalse(
    "mismatched Instance ID rejected by Resolver",
    Caller.Evaluate(
      candidate_b01,
      coordinator_b01,
      reducer_b01,
      TGK_GRID_ENTRY_EXECUTION_NORMAL,
      result_b01));
  AssertResolverFailurePreservesResult("Instance mismatch", result_b01);
  Tests.EndTest();

  Tests.BeginTest("B02 Different Symbol fails closed without Policy call");
  CTGKGridLevelRuntimeCoordinator coordinator_b02;
  CTGKGridEntryMappingReducer reducer_b02;
  InitializeCoordinator(coordinator_b02);
  STGKGridMappingJournalRecord records_b02[];
  AddBaseConfiguration(records_b02);
  InitializeReducer(reducer_b02, records_b02);
  STGKGridEntryExecutionCandidate candidate_b02;
  SetCandidate(candidate_b02, 0);
  candidate_b02.symbol = "EURUSD";
  STGKGridEntryExecutionResult result_b02;
  SetResultSentinel(result_b02);
  Tests.AssertFalse(
    "mismatched Symbol rejected by Resolver",
    Caller.Evaluate(
      candidate_b02,
      coordinator_b02,
      reducer_b02,
      TGK_GRID_ENTRY_EXECUTION_NORMAL,
      result_b02));
  AssertResolverFailurePreservesResult("Symbol mismatch", result_b02);
  Tests.EndTest();

  Tests.BeginTest("B03 Different Magic Number fails closed without Policy call");
  CTGKGridLevelRuntimeCoordinator coordinator_b03;
  CTGKGridEntryMappingReducer reducer_b03;
  InitializeCoordinator(coordinator_b03);
  STGKGridMappingJournalRecord records_b03[];
  AddBaseConfiguration(records_b03);
  InitializeReducer(reducer_b03, records_b03);
  STGKGridEntryExecutionCandidate candidate_b03;
  SetCandidate(candidate_b03, 0);
  candidate_b03.magic_number = 710002;
  STGKGridEntryExecutionResult result_b03;
  SetResultSentinel(result_b03);
  Tests.AssertFalse(
    "mismatched Magic rejected by Resolver",
    Caller.Evaluate(
      candidate_b03,
      coordinator_b03,
      reducer_b03,
      TGK_GRID_ENTRY_EXECUTION_NORMAL,
      result_b03));
  AssertResolverFailurePreservesResult("Magic mismatch", result_b03);
  Tests.EndTest();

  Tests.BeginTest("B04 Different Mode fails closed without Policy call");
  CTGKGridLevelRuntimeCoordinator coordinator_b04;
  CTGKGridEntryMappingReducer reducer_b04;
  InitializeCoordinator(coordinator_b04);
  STGKGridMappingJournalRecord records_b04[];
  AddBaseConfiguration(records_b04);
  InitializeReducer(reducer_b04, records_b04);
  STGKGridEntryExecutionCandidate candidate_b04;
  SetCandidate(candidate_b04, 0);
  candidate_b04.mode = TGK_GRID_MODE_SELL;
  STGKGridEntryExecutionResult result_b04;
  SetResultSentinel(result_b04);
  Tests.AssertFalse(
    "mismatched Mode rejected by Resolver",
    Caller.Evaluate(
      candidate_b04,
      coordinator_b04,
      reducer_b04,
      TGK_GRID_ENTRY_EXECUTION_NORMAL,
      result_b04));
  AssertResolverFailurePreservesResult("Mode mismatch", result_b04);
  Tests.EndTest();

  Tests.BeginTest("B05 Different Config Epoch fails closed without Policy call");
  CTGKGridLevelRuntimeCoordinator coordinator_b05;
  CTGKGridEntryMappingReducer reducer_b05;
  InitializeCoordinator(coordinator_b05);
  STGKGridMappingJournalRecord records_b05[];
  AddBaseConfiguration(records_b05);
  InitializeReducer(reducer_b05, records_b05);
  STGKGridEntryExecutionCandidate candidate_b05;
  SetCandidate(candidate_b05, 0);
  candidate_b05.config_epoch = 2;
  STGKGridEntryExecutionResult result_b05;
  SetResultSentinel(result_b05);
  Tests.AssertFalse(
    "mismatched Config Epoch rejected by Resolver",
    Caller.Evaluate(
      candidate_b05,
      coordinator_b05,
      reducer_b05,
      TGK_GRID_ENTRY_EXECUTION_NORMAL,
      result_b05));
  AssertResolverFailurePreservesResult("Config Epoch mismatch", result_b05);
  Tests.EndTest();

  Tests.BeginTest("B06 Malformed Anchor key fails closed without Policy call");
  CTGKGridLevelRuntimeCoordinator coordinator_b06;
  CTGKGridEntryMappingReducer reducer_b06;
  InitializeCoordinator(coordinator_b06);
  STGKGridMappingJournalRecord records_b06[];
  AddBaseConfiguration(records_b06);
  InitializeReducer(reducer_b06, records_b06);
  STGKGridEntryExecutionCandidate candidate_b06;
  SetCandidate(candidate_b06, 0);
  candidate_b06.target_level.is_anchor = true;
  candidate_b06.target_level.level_index = 0;
  STGKGridEntryExecutionResult result_b06;
  SetResultSentinel(result_b06);
  Tests.AssertFalse(
    "malformed Anchor key rejected",
    Caller.Evaluate(
      candidate_b06,
      coordinator_b06,
      reducer_b06,
      TGK_GRID_ENTRY_EXECUTION_NORMAL,
      result_b06));
  AssertResolverFailurePreservesResult("Malformed Anchor", result_b06);
  Tests.EndTest();

  Tests.BeginTest("B07 Negative normal Level index fails closed");
  CTGKGridLevelRuntimeCoordinator coordinator_b07;
  CTGKGridEntryMappingReducer reducer_b07;
  InitializeCoordinator(coordinator_b07);
  STGKGridMappingJournalRecord records_b07[];
  AddBaseConfiguration(records_b07);
  InitializeReducer(reducer_b07, records_b07);
  STGKGridEntryExecutionCandidate candidate_b07;
  SetCandidate(candidate_b07, -1);
  STGKGridEntryExecutionResult result_b07;
  SetResultSentinel(result_b07);
  Tests.AssertFalse(
    "negative normal index rejected",
    Caller.Evaluate(
      candidate_b07,
      coordinator_b07,
      reducer_b07,
      TGK_GRID_ENTRY_EXECUTION_NORMAL,
      result_b07));
  AssertResolverFailurePreservesResult("Negative normal index", result_b07);
  Tests.EndTest();

  Tests.BeginTest("B08 Out-of-range target fails closed without Policy call");
  CTGKGridLevelRuntimeCoordinator coordinator_b08;
  CTGKGridEntryMappingReducer reducer_b08;
  InitializeCoordinator(coordinator_b08);
  STGKGridMappingJournalRecord records_b08[];
  AddBaseConfiguration(records_b08);
  InitializeReducer(reducer_b08, records_b08);
  STGKGridEntryExecutionCandidate candidate_b08;
  SetCandidate(candidate_b08, 16);
  STGKGridEntryExecutionResult result_b08;
  SetResultSentinel(result_b08);
  Tests.AssertFalse(
    "out-of-range target rejected",
    Caller.Evaluate(
      candidate_b08,
      coordinator_b08,
      reducer_b08,
      TGK_GRID_ENTRY_EXECUTION_NORMAL,
      result_b08));
  AssertResolverFailurePreservesResult("Out-of-range target", result_b08);
  Tests.EndTest();

  Tests.BeginTest("B09 Unconfigured Reducer fails closed without Policy call");
  CTGKGridLevelRuntimeCoordinator coordinator_b09;
  CTGKGridEntryMappingReducer reducer_b09;
  InitializeCoordinator(coordinator_b09);
  Tests.AssertTrue(
    "initialize empty Reducer",
    reducer_b09.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  STGKGridEntryExecutionCandidate candidate_b09;
  SetCandidate(candidate_b09, 0);
  STGKGridEntryExecutionResult result_b09;
  SetResultSentinel(result_b09);
  Tests.AssertFalse(
    "no committed Reducer configuration rejected",
    Caller.Evaluate(
      candidate_b09,
      coordinator_b09,
      reducer_b09,
      TGK_GRID_ENTRY_EXECUTION_NORMAL,
      result_b09));
  AssertResolverFailurePreservesResult("Unconfigured Reducer", result_b09);
  Tests.EndTest();

  Tests.BeginTest("B10 Reducer Recovery Error fails closed without Policy call");
  CTGKGridLevelRuntimeCoordinator coordinator_b10;
  CTGKGridEntryMappingReducer reducer_b10;
  InitializeCoordinator(coordinator_b10);
  Tests.AssertTrue(
    "initialize Reducer before invalid replay",
    reducer_b10.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  STGKGridMappingJournalRecord invalid_records[];
  AddRecord(
    invalid_records,
    1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "invalid-payload");
  Tests.AssertFalse(
    "invalid replay enters Recovery Error",
    reducer_b10.Replay(invalid_records, ArraySize(invalid_records)));
  Tests.AssertEqualInt(
    "Reducer reports Recovery Error",
    (int)reducer_b10.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);
  STGKGridEntryExecutionCandidate candidate_b10;
  SetCandidate(candidate_b10, 0);
  STGKGridEntryExecutionResult result_b10;
  SetResultSentinel(result_b10);
  Tests.AssertFalse(
    "Reducer Recovery Error rejected",
    Caller.Evaluate(
      candidate_b10,
      coordinator_b10,
      reducer_b10,
      TGK_GRID_ENTRY_EXECUTION_NORMAL,
      result_b10));
  AssertResolverFailurePreservesResult("Reducer Recovery Error", result_b10);
  Tests.EndTest();

  Tests.BeginTest("B11 Runtime and persistent Level State disagreement fails closed");
  CTGKGridLevelRuntimeCoordinator coordinator_b11;
  CTGKGridEntryMappingReducer reducer_b11;
  InitializeCoordinator(coordinator_b11);
  STGKGridMappingJournalRecord records_b11[];
  AddBaseConfiguration(records_b11);
  AddRecord(
    records_b11,
    2,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|LEVEL_STATE|1|0|WAIT_ACTIVATION");
  InitializeReducer(reducer_b11, records_b11);
  STGKGridEntryExecutionCandidate candidate_b11;
  SetCandidate(candidate_b11, 0);
  STGKGridEntryExecutionResult result_b11;
  SetResultSentinel(result_b11);
  Tests.AssertFalse(
    "different current/persisted state rejected",
    Caller.Evaluate(
      candidate_b11,
      coordinator_b11,
      reducer_b11,
      TGK_GRID_ENTRY_EXECUTION_NORMAL,
      result_b11));
  AssertResolverFailurePreservesResult("State disagreement", result_b11);
  Tests.EndTest();

  Tests.BeginTest("C01 Unresolved state disagreement fails closed");
  CTGKGridLevelRuntimeCoordinator coordinator_c01;
  CTGKGridEntryMappingReducer reducer_c01;
  InitializeCoordinator(coordinator_c01);
  STGKGridMappingJournalRecord records_c01[];
  AddBaseConfiguration(records_c01);
  AddRecord(
    records_c01,
    2,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-PENDING|XAUUSD|710001|BUY|LEVEL|7|0.01|1|UT-INSTANCE");
  InitializeReducer(reducer_c01, records_c01);
  STGKGridEntryExecutionCandidate candidate_c01;
  SetCandidate(candidate_c01, 7);
  STGKGridEntryExecutionResult result_c01;
  SetResultSentinel(result_c01);
  Tests.AssertFalse(
    "persistent/runtime unresolved disagreement rejected",
    Caller.Evaluate(
      candidate_c01,
      coordinator_c01,
      reducer_c01,
      TGK_GRID_ENTRY_EXECUTION_NORMAL,
      result_c01));
  AssertResolverFailurePreservesResult("Unresolved disagreement", result_c01);
  Tests.EndTest();

  Tests.BeginTest("C02 Matching unresolved state reaches Policy and blocks entry");
  CTGKGridLevelRuntimeCoordinator coordinator_c02;
  CTGKGridEntryMappingReducer reducer_c02;
  InitializeCoordinator(coordinator_c02);
  STGKGridLevelCandidate offered_c02;
  ENUM_TGK_GRID_COORDINATOR_RESULT coordinator_result_c02;
  Tests.AssertEqualInt(
    "offer pending target",
    (int)coordinator_c02.UpdatePrice(
      3994.0,
      3995.0,
      coordinator_result_c02,
      offered_c02),
    (int)TGK_GRID_COORDINATOR_CANDIDATE_READY);
  Tests.AssertEqualInt("pending target is Level 7", offered_c02.level_index, 7);
  Tests.AssertTrue(
    "Coordinator records unresolved request",
    coordinator_c02.RecordEntryRequest(
      offered_c02,
      TGK_GRID_ENTRY_REQUEST_ACCEPTED));
  STGKGridMappingJournalRecord records_c02[];
  AddBaseConfiguration(records_c02);
  AddRecord(
    records_c02,
    2,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-PENDING|XAUUSD|710001|BUY|LEVEL|7|0.01|1|UT-INSTANCE");
  InitializeReducer(reducer_c02, records_c02);
  STGKGridEntryExecutionCandidate candidate_c02;
  SetCandidate(candidate_c02, 7);
  STGKGridEntryExecutionResult result_c02;
  Tests.AssertTrue(
    "coherent unresolved context evaluated",
    Caller.Evaluate(
      candidate_c02,
      coordinator_c02,
      reducer_c02,
      TGK_GRID_ENTRY_EXECUTION_NORMAL,
      result_c02));
  AssertResult(
    "Unresolved request",
    result_c02,
    candidate_c02,
    TGK_GRID_ENTRY_DECISION_REJECT,
    TGK_GRID_ENTRY_REASON_UNRESOLVED_REQUEST);
  Tests.EndTest();

  Tests.BeginTest("C03 Stale Runtime Config Epoch fails closed without Policy call");
  CTGKGridLevelRuntimeCoordinator coordinator_b12;
  CTGKGridEntryMappingReducer reducer_b12;
  Tests.AssertTrue(
    "initialize runtime with stale Config Epoch",
    InitializeCoordinatorForEpoch(coordinator_b12, 2));
  STGKGridMappingJournalRecord records_b12[];
  AddBaseConfiguration(records_b12);
  InitializeReducer(reducer_b12, records_b12);
  STGKGridEntryExecutionCandidate candidate_b12;
  SetCandidate(candidate_b12, 0);
  STGKGridEntryExecutionResult result_b12;
  SetResultSentinel(result_b12);
  Tests.AssertFalse(
    "stale runtime configuration rejected",
    Caller.Evaluate(
      candidate_b12,
      coordinator_b12,
      reducer_b12,
      TGK_GRID_ENTRY_EXECUTION_NORMAL,
      result_b12));
  AssertResolverFailurePreservesResult("Runtime Config Epoch mismatch", result_b12);
  Tests.EndTest();

  Tests.BeginTest("F01 Level 0 unmapped, Level 7 mapped, then Level 0 again");
  CTGKGridLevelRuntimeCoordinator coordinator_f01;
  CTGKGridEntryMappingReducer reducer_f01;
  Tests.AssertTrue(
    "initialize mapped Level 7 fixture",
    InitializeMappedLevelSeven(coordinator_f01, reducer_f01));
  STGKGridEntryExecutionCandidate candidate_level_0;
  SetCandidate(candidate_level_0, 0);
  STGKGridEntryExecutionCandidate candidate_level_7;
  SetCandidate(candidate_level_7, 7);
  STGKGridEntryExecutionResult result_f01;
  Tests.AssertTrue(
    "Level 0 is resolved and evaluated first",
    Caller.Evaluate(
      candidate_level_0,
      coordinator_f01,
      reducer_f01,
      TGK_GRID_ENTRY_EXECUTION_NORMAL,
      result_f01));
  AssertResult(
    "Level 0 first",
    result_f01,
    candidate_level_0,
    TGK_GRID_ENTRY_DECISION_ALLOW,
    TGK_GRID_ENTRY_REASON_ELIGIBLE);
  Tests.AssertTrue(
    "Level 7 is resolved with its own mapped context",
    Caller.Evaluate(
      candidate_level_7,
      coordinator_f01,
      reducer_f01,
      TGK_GRID_ENTRY_EXECUTION_NORMAL,
      result_f01));
  AssertResult(
    "Level 7 mapped",
    result_f01,
    candidate_level_7,
    TGK_GRID_ENTRY_DECISION_REJECT,
    TGK_GRID_ENTRY_REASON_LEVEL_NOT_ELIGIBLE);
  Tests.AssertTrue(
    "Level 0 is freshly resolved again",
    Caller.Evaluate(
      candidate_level_0,
      coordinator_f01,
      reducer_f01,
      TGK_GRID_ENTRY_EXECUTION_NORMAL,
      result_f01));
  AssertResult(
    "Level 0 again",
    result_f01,
    candidate_level_0,
    TGK_GRID_ENTRY_DECISION_ALLOW,
    TGK_GRID_ENTRY_REASON_ELIGIBLE);
  Tests.EndTest();

  Tests.EndSuite();
  return INIT_SUCCEEDED;
}
