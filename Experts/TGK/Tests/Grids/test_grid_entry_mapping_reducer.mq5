#property strict
#property version "1.00"
#property description "Grid Entry Mapping Reducer tests; no trading."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridEntryMappingStorage.mqh>
#include <BotTrade/Grid/GridEntryMappingReducer.mqh>

CTGKTestRunner Tests;

void AddRecord(
  STGKGridMappingJournalRecord &records[],
  long sequence,
  ENUM_TGK_GRID_MAPPING_RECORD_TYPE record_type,
  string payload)
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
    "v1|RESET_COMMITTED|1|BUY|1.0|3900.0|4100.0|4000.0|201");
  AddRecord(
    records,
    2,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|LEVEL_STATE|1|1|READY");
}

void AddMappedPosition(
  STGKGridMappingJournalRecord &records[],
  int &sequence,
  string request_id,
  string target_kind,
  int level_index,
  int identifier_seed)
{
  string deal_ticket = StringFormat("%I64d", 2000000 + identifier_seed);
  string position_identifier = StringFormat("%I64d", 3000000 + identifier_seed);
  string position_ticket = StringFormat("%I64d", 4000000 + identifier_seed);
  string order_ticket = StringFormat("%I64d", 1000000 + identifier_seed);

  AddRecord(
    records,
    sequence++,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    StringFormat(
      "v1|%s|XAUUSD|710001|BUY|%s|%d|0.01|1|UT-INSTANCE",
      request_id,
      target_kind,
      level_index));
  AddRecord(
    records,
    sequence++,
    TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
    StringFormat(
      "v1|%s|DONE|%s|0",
      request_id,
      order_ticket));
  AddRecord(
    records,
    sequence++,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    StringFormat(
      "v1|%s|%s|%s|0.01",
      request_id,
      deal_ticket,
      position_identifier));
  AddRecord(
    records,
    sequence++,
    TGK_GRID_MAPPING_RECORD_POSITION_MAPPING,
    StringFormat(
      "v1|%s|XAUUSD|710001|%s|%d|%s|%s|0.01|1|UT-INSTANCE",
      request_id,
      target_kind,
      level_index,
      position_identifier,
      position_ticket));
}

void AddFilledLevelRequest(STGKGridMappingJournalRecord &records[])
{
  int sequence = ArraySize(records) + 1;
  AddRecord(
    records,
    sequence++,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-001|XAUUSD|710001|BUY|LEVEL|1|0.10|1|UT-INSTANCE");
  AddRecord(
    records,
    sequence++,
    TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
    "v1|REQ-001|DONE_PARTIAL|9007199254740995|9007199254740997");
  AddRecord(
    records,
    sequence++,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    "v1|REQ-001|9007199254740997|18446744073709551613|0.04");
  AddRecord(
    records,
    sequence++,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    "v1|REQ-001|9007199254740998|18446744073709551613|0.06");
  AddRecord(
    records,
    sequence++,
    TGK_GRID_MAPPING_RECORD_POSITION_MAPPING,
    "v1|REQ-001|XAUUSD|710001|LEVEL|1|18446744073709551613|18446744073709551614|0.10|1|UT-INSTANCE");
}

// Fixture kinds: 0 = mapped Anchor ACTIVE, 1 = closed Anchor WAIT_ACTIVATION,
// 2 = committed configuration with a READY Anchor and no mapping.
int BuildAnchorStateFixture(
  STGKGridMappingJournalRecord &records[],
  int fixture_kind)
{
  AddBaseConfiguration(records);
  if(fixture_kind == 2)
    return ArraySize(records);

  int sequence = ArraySize(records) + 1;
  AddMappedPosition(
    records,
    sequence,
    "REQ-CR01-GUARD",
    "ANCHOR",
    -1,
    9981);
  if(fixture_kind == 1)
    AddRecord(
      records,
      sequence,
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      "v1|POSITION_CLOSED|3009981|WAIT_ACTIVATION");
  return ArraySize(records);
}

bool ReplayAnchorStateAttempt(string payload, int fixture_kind)
{
  STGKGridMappingJournalRecord records[];
  int count = BuildAnchorStateFixture(records, fixture_kind);
  AddRecord(
    records,
    count + 1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    payload);

  CTGKGridEntryMappingReducer reducer;
  if(!reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"))
    return false;
  return reducer.Replay(records, ArraySize(records));
}

// Committed configuration with two mapped Levels, ready for one Reconciliation
// Batch record.
int BuildBatchFixture(STGKGridMappingJournalRecord &records[])
{
  AddBaseConfiguration(records);
  int sequence = ArraySize(records) + 1;
  AddMappedPosition(records, sequence, "REQ-RB-1", "LEVEL", 1, 8101);
  AddMappedPosition(records, sequence, "REQ-RB-2", "LEVEL", 2, 8102);
  return ArraySize(records);
}

// Replays the fixture plus one Reconciliation Batch record and reports the
// resulting committed state.
void ReplayBatchOutcome(
  string batch_payload,
  bool &replayed,
  double &volume_after,
  int &position_count_after,
  int &level_one_state_after,
  int &level_two_state_after)
{
  STGKGridMappingJournalRecord records[];
  BuildBatchFixture(records);
  AddRecord(
    records,
    ArraySize(records) + 1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    batch_payload);

  CTGKGridEntryMappingReducer reducer;
  replayed = false;
  volume_after = 0.0;
  position_count_after = 0;
  level_one_state_after = -1;
  level_two_state_after = -1;

  if(!reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"))
    return;

  replayed = reducer.Replay(records, ArraySize(records));
  volume_after = reducer.PositionVolumeAt(0);
  position_count_after = reducer.PositionCount();
  level_one_state_after = reducer.LevelStateAt(1);
  level_two_state_after = reducer.LevelStateAt(2);
}

int OnInit()
{
  Tests.BeginSuite("TGK Grid Entry Mapping Reducer");

  Tests.BeginTest("Replay builds a confirmed Position Mapping from partial-fill Deals");
  STGKGridMappingJournalRecord records[];
  AddBaseConfiguration(records);
  AddFilledLevelRequest(records);

  CTGKGridEntryMappingReducer reducer;
  Tests.AssertTrue(
    "initialize reducer identity",
    reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay valid event stream",
    reducer.Replay(records, ArraySize(records)));

  Tests.AssertEqualLong("last sequence", reducer.LastSequence(), 7);
  Tests.AssertEqualInt("one active Position", reducer.PositionCount(), 1);
  Tests.AssertEqualInt(
    "Deal Associations pruned after confirmed Position Mapping",
    reducer.DealCount(),
    0);
  Tests.AssertFalse("confirmed mapping resolves Entry Request", reducer.HasUnresolvedRequest());
  Tests.AssertEqualString(
    "large Position Identifier preserved",
    reducer.PositionIdentifierAt(0),
    "18446744073709551613");
  Tests.AssertEqualString(
    "large Position Ticket preserved",
    reducer.PositionTicketAt(0),
    "18446744073709551614");
  Tests.AssertEqualDouble("reconciled Position volume", reducer.PositionVolumeAt(0), 0.10);
  Tests.AssertEqualInt(
    "mapped Level becomes ACTIVE",
    reducer.LevelStateAt(1),
    (int)TGK_GRID_LEVEL_ACTIVE);

  AddRecord(
    records,
    8,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_TICKET|18446744073709551613|18446744073709551610");
  STGKGridMappingJournalRecord ticket_records[];
  ArrayResize(ticket_records, 8);
  for(int i = 0; i < 8; i++)
    ticket_records[i] = records[i];

  CTGKGridEntryMappingReducer ticket_reducer;
  Tests.AssertTrue(
    "initialize ticket-refresh reducer",
    ticket_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay Position Ticket refresh",
    ticket_reducer.Replay(ticket_records, ArraySize(ticket_records)));
  Tests.AssertEqualString(
    "Position Identifier remains stable",
    ticket_reducer.PositionIdentifierAt(0),
    "18446744073709551613");
  Tests.AssertEqualString(
    "Position Ticket updates as execution handle",
    ticket_reducer.PositionTicketAt(0),
    "18446744073709551610");
  Tests.EndTest();

  Tests.BeginTest("Partial close retains Mapping; legacy full close prunes Mapping and normalizes state");
  AddRecord(
    records,
    9,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_VOLUME|18446744073709551613|0.04");

  STGKGridMappingJournalRecord partial_records[];
  ArrayResize(partial_records, 9);
  for(int i = 0; i < 9; i++)
    partial_records[i] = records[i];

  CTGKGridEntryMappingReducer partial_reducer;
  Tests.AssertTrue(
    "initialize partial-close reducer",
    partial_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay partial-close event",
    partial_reducer.Replay(partial_records, ArraySize(partial_records)));
  Tests.AssertEqualInt("partial close retains Position", partial_reducer.PositionCount(), 1);
  Tests.AssertEqualDouble("partial close updates remaining volume", partial_reducer.PositionVolumeAt(0), 0.04);
  Tests.AssertEqualInt(
    "partial close keeps Level ACTIVE",
    partial_reducer.LevelStateAt(1),
    (int)TGK_GRID_LEVEL_ACTIVE);

  AddRecord(
    records,
    10,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_CLOSED|18446744073709551613|TP|WAIT_RETURN");

  CTGKGridEntryMappingReducer closed_reducer;
  Tests.AssertTrue(
    "initialize close reducer",
    closed_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay partial and full close events",
    closed_reducer.Replay(records, ArraySize(records)));
  Tests.AssertEqualInt("closed Position Mapping removed", closed_reducer.PositionCount(), 0);
  Tests.AssertEqualInt("closed Position Deal history pruned", closed_reducer.DealCount(), 0);
  Tests.AssertEqualInt(
    "legacy WAIT_RETURN normalized to READY on replay",
    closed_reducer.LevelStateAt(1),
    (int)TGK_GRID_LEVEL_READY);

  AddRecord(
    records,
    11,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|RESET_COMMITTED|2|SELL|2.0|3800.0|4200.0|4000.0|201");
  CTGKGridEntryMappingReducer reset_after_close_reducer;
  Tests.AssertTrue(
    "initialize completed-reset reducer",
    reset_after_close_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "completed Reset prunes old Level State",
    reset_after_close_reducer.Replay(records, ArraySize(records)));
  Tests.AssertEqualInt(
    "new Level State initialized READY after confirmed Reset",
    reset_after_close_reducer.LevelStateAt(1),
    (int)TGK_GRID_LEVEL_READY);
  Tests.EndTest();

  Tests.BeginTest("Only one unresolved Entry Request is allowed");
  STGKGridMappingJournalRecord unresolved_records[];
  AddBaseConfiguration(unresolved_records);
  AddRecord(
    unresolved_records,
    3,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-A|XAUUSD|710001|BUY|LEVEL|1|0.10|1|UT-INSTANCE");
  AddRecord(
    unresolved_records,
    4,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-B|XAUUSD|710001|BUY|LEVEL|2|0.10|1|UT-INSTANCE");

  CTGKGridEntryMappingReducer unresolved_reducer;
  Tests.AssertTrue(
    "initialize unresolved reducer",
    unresolved_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "second unresolved Request is rejected",
    unresolved_reducer.Replay(unresolved_records, ArraySize(unresolved_records)));
  Tests.EndTest();

  Tests.BeginTest("Execution Placed is pending reconciliation, not a Position fill");
  STGKGridMappingJournalRecord placed_records[];
  AddBaseConfiguration(placed_records);
  AddRecord(
    placed_records,
    3,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-PLACED|XAUUSD|710001|BUY|LEVEL|1|0.10|1|UT-INSTANCE");
  AddRecord(
    placed_records,
    4,
    TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
    "v1|REQ-PLACED|PLACED|9007199254740995|0");

  CTGKGridEntryMappingReducer placed_reducer;
  Tests.AssertTrue(
    "initialize placed reducer",
    placed_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay placed result",
    placed_reducer.Replay(placed_records, ArraySize(placed_records)));
  Tests.AssertTrue("Request remains unresolved", placed_reducer.HasUnresolvedRequest());
  Tests.AssertEqualInt("Placed does not create Position", placed_reducer.PositionCount(), 0);
  Tests.AssertEqualInt(
    "Level does not become ACTIVE",
    placed_reducer.LevelStateAt(1),
    (int)TGK_GRID_LEVEL_READY);
  Tests.EndTest();

  Tests.BeginTest("Failed execution resolves Request and permits the next Request");
  STGKGridMappingJournalRecord failed_records[];
  AddBaseConfiguration(failed_records);
  AddRecord(
    failed_records,
    3,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-FAIL|XAUUSD|710001|BUY|LEVEL|1|0.10|1|UT-INSTANCE");
  AddRecord(
    failed_records,
    4,
    TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
    "v1|REQ-FAIL|MARKET_CLOSED|0|0");
  AddRecord(
    failed_records,
    5,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-NEXT|XAUUSD|710001|BUY|LEVEL|1|0.10|1|UT-INSTANCE");

  CTGKGridEntryMappingReducer failed_reducer;
  Tests.AssertTrue(
    "initialize failed reducer",
    failed_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "failed result resolves prior Request",
    failed_reducer.Replay(failed_records, ArraySize(failed_records)));
  Tests.AssertTrue("new Request is unresolved", failed_reducer.HasUnresolvedRequest());
  Tests.AssertEqualString(
    "new Request is current",
    failed_reducer.UnresolvedRequestId(),
    "REQ-NEXT");
  Tests.EndTest();

  Tests.BeginTest("Conflicting Position Identifier for one Request is rejected");
  STGKGridMappingJournalRecord conflict_records[];
  AddBaseConfiguration(conflict_records);
  AddRecord(
    conflict_records,
    3,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-CONFLICT|XAUUSD|710001|BUY|LEVEL|1|0.10|1|UT-INSTANCE");
  AddRecord(
    conflict_records,
    4,
    TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
    "v1|REQ-CONFLICT|DONE|9007199254740995|0");
  AddRecord(
    conflict_records,
    5,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    "v1|REQ-CONFLICT|9007199254740997|18446744073709551613|0.04");
  AddRecord(
    conflict_records,
    6,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    "v1|REQ-CONFLICT|9007199254740998|18446744073709551612|0.06");

  CTGKGridEntryMappingReducer conflict_reducer;
  Tests.AssertTrue(
    "initialize conflict reducer",
    conflict_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "conflicting Position Identifier rejected",
    conflict_reducer.Replay(conflict_records, ArraySize(conflict_records)));
  Tests.EndTest();

  Tests.BeginTest("Identity, decimal-string and strict payload validation");
  STGKGridMappingJournalRecord invalid_records[];
  AddBaseConfiguration(invalid_records);
  AddRecord(
    invalid_records,
    3,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-BAD|XAUUSD|710002|BUY|LEVEL|1|0.10|1|UT-INSTANCE");

  CTGKGridEntryMappingReducer identity_reducer;
  Tests.AssertTrue(
    "initialize identity reducer",
    identity_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "Magic mismatch rejected",
    identity_reducer.Replay(invalid_records, ArraySize(invalid_records)));

  ArrayFree(invalid_records);
  AddBaseConfiguration(invalid_records);
  AddRecord(
    invalid_records,
    3,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-OTHER-INSTANCE|XAUUSD|710001|BUY|LEVEL|1|0.10|1|UT-OTHER");
  CTGKGridEntryMappingReducer instance_reducer;
  Tests.AssertTrue(
    "initialize Instance validation reducer",
    instance_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "Instance mismatch rejected",
    instance_reducer.Replay(invalid_records, ArraySize(invalid_records)));

  ArrayFree(invalid_records);
  AddBaseConfiguration(invalid_records);
  AddRecord(
    invalid_records,
    3,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-BAD-ID|XAUUSD|710001|BUY|LEVEL|1|0.10|1|UT-INSTANCE");
  AddRecord(
    invalid_records,
    4,
    TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
    "v1|REQ-BAD-ID|DONE|9007199254740995|0");
  AddRecord(
    invalid_records,
    5,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    "v1|REQ-BAD-ID|90A7199254740997|18446744073709551613|0.10");

  CTGKGridEntryMappingReducer decimal_reducer;
  Tests.AssertTrue(
    "initialize decimal reducer",
    decimal_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "non-decimal Deal Ticket rejected",
    decimal_reducer.Replay(invalid_records, ArraySize(invalid_records)));

  ArrayFree(invalid_records);
  AddBaseConfiguration(invalid_records);
  AddRecord(
    invalid_records,
    3,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-UNKNOWN|XAUUSD|710001|BUY|LEVEL|1|0.10|1|UT-INSTANCE|unexpected");

  CTGKGridEntryMappingReducer schema_reducer;
  Tests.AssertTrue(
    "initialize schema reducer",
    schema_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "unknown payload field rejected",
    schema_reducer.Replay(invalid_records, ArraySize(invalid_records)));
  Tests.EndTest();

  Tests.BeginTest("Reset cannot prune Levels while Position or Request remains");
  STGKGridMappingJournalRecord reset_records[];
  AddBaseConfiguration(reset_records);
  AddFilledLevelRequest(reset_records);
  AddRecord(
    reset_records,
    8,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|RESET_COMMITTED|2|SELL|2.0|3800.0|4200.0|4000.0|201");

  CTGKGridEntryMappingReducer reset_reducer;
  Tests.AssertTrue(
    "initialize reset reducer",
    reset_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "Reset with active Position is rejected",
    reset_reducer.Replay(reset_records, ArraySize(reset_records)));
  Tests.EndTest();

  Tests.BeginTest("Journal Sequence must be continuous");
  STGKGridMappingJournalRecord sequence_records[];
  AddBaseConfiguration(sequence_records);
  sequence_records[1].sequence = 3;

  CTGKGridEntryMappingReducer sequence_reducer;
  Tests.AssertTrue(
    "initialize sequence reducer",
    sequence_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "sequence gap rejected",
    sequence_reducer.Replay(sequence_records, ArraySize(sequence_records)));
  Tests.EndTest();

  Tests.BeginTest("Deal Association capacity accepts 100 and rejects 101 without truncation");
  STGKGridMappingJournalRecord deal_capacity_records[];
  AddBaseConfiguration(deal_capacity_records);
  AddRecord(
    deal_capacity_records,
    3,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-DEAL-CAP|XAUUSD|710001|BUY|LEVEL|1|2.0|1|UT-INSTANCE");
  AddRecord(
    deal_capacity_records,
    4,
    TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
    "v1|REQ-DEAL-CAP|DONE|9007199254740995|0");
  for(int i = 0; i < TGK_GRID_MAPPING_MAX_DEALS_PER_REQUEST; i++)
  {
    AddRecord(
      deal_capacity_records,
      ArraySize(deal_capacity_records) + 1,
      TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
      StringFormat(
        "v1|REQ-DEAL-CAP|%d|123456789|0.01",
        10000 + i));
  }

  CTGKGridEntryMappingReducer deal_capacity_reducer;
  Tests.AssertTrue(
    "initialize Deal capacity reducer",
    deal_capacity_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "exactly 100 Deal Associations are accepted",
    deal_capacity_reducer.Replay(
      deal_capacity_records,
      ArraySize(deal_capacity_records)));
  Tests.AssertEqualInt(
    "all 100 Deal Associations are retained",
    deal_capacity_reducer.DealCount(),
    100);

  AddRecord(
    deal_capacity_records,
    ArraySize(deal_capacity_records) + 1,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    "v1|REQ-DEAL-CAP|999999|123456789|0.01");
  CTGKGridEntryMappingReducer deal_overflow_reducer;
  Tests.AssertTrue(
    "initialize Deal overflow reducer",
    deal_overflow_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "101st Deal Association is rejected",
    deal_overflow_reducer.Replay(
      deal_capacity_records,
      ArraySize(deal_capacity_records)));
  Tests.AssertEqualInt(
    "overflow enters RECOVERY_ERROR",
    (int)deal_overflow_reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);
  Tests.AssertEqualInt(
    "prior 100 Deal Associations remain intact",
    deal_overflow_reducer.DealCount(),
    100);
  Tests.EndTest();

  Tests.BeginTest("Grid configuration rejects more than 1,000 Levels");
  STGKGridMappingJournalRecord level_capacity_records[];
  AddRecord(
    level_capacity_records,
    1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|RESET_COMMITTED|1|BUY|1.0|3500.0|4500.0|4000.0|1001");
  CTGKGridEntryMappingReducer level_capacity_reducer;
  Tests.AssertTrue(
    "initialize Level capacity reducer",
    level_capacity_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "1,001 Levels are rejected",
    level_capacity_reducer.Replay(
      level_capacity_records,
      ArraySize(level_capacity_records)));
  Tests.EndTest();

  Tests.BeginTest("Grid Level count must match Bounds, Grid Step and Anchor formula");
  STGKGridMappingJournalRecord level_formula_records[];
  AddRecord(
    level_formula_records,
    1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|RESET_COMMITTED|1|BUY|1.0|3900.0|4100.0|4000.0|200");
  CTGKGridEntryMappingReducer level_formula_reducer;
  Tests.AssertTrue(
    "initialize Level formula reducer",
    level_formula_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "incorrect Level count is rejected",
    level_formula_reducer.Replay(
      level_formula_records,
      ArraySize(level_formula_records)));
  Tests.AssertEqualInt(
    "incorrect persisted Level count enters RECOVERY_ERROR",
    (int)level_formula_reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);
  Tests.EndTest();

  Tests.BeginTest("Position Mapping capacity accepts 1,000 and Snapshot rejects 1,001");
  STGKGridMappingJournalRecord position_capacity_records[];
  int position_sequence = 1;
  AddRecord(
    position_capacity_records,
    position_sequence++,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|RESET_COMMITTED|1|BUY|1.0|3500.0|4499.0|4000.0|1000");
  for(int level = 0; level < 999; level++)
  {
    AddRecord(
      position_capacity_records,
      position_sequence++,
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      StringFormat("v1|LEVEL_STATE|1|%d|READY", level));
  }

  AddMappedPosition(
    position_capacity_records,
    position_sequence,
    "REQ-ANCHOR",
    "ANCHOR",
    -1,
    0);
  for(int level = 0; level < 999; level++)
  {
    AddMappedPosition(
      position_capacity_records,
      position_sequence,
      StringFormat("REQ-%d", level),
      "LEVEL",
      level,
      level + 1);
  }

  CTGKGridEntryMappingReducer position_capacity_reducer;
  Tests.AssertTrue(
    "initialize Position capacity reducer",
    position_capacity_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "exactly 1,000 Position Mappings are accepted",
    position_capacity_reducer.Replay(
      position_capacity_records,
      ArraySize(position_capacity_records)));
  Tests.AssertEqualInt(
    "all 1,000 Position Mappings remain present",
    position_capacity_reducer.PositionCount(),
    1000);

  string position_snapshot_payload;
  Tests.AssertTrue(
    "serialize all 1,000 active Position Mappings",
    position_capacity_reducer.ExportSnapshot(position_snapshot_payload));
  string position_overflow_payload = position_snapshot_payload;
  int position_count_replacements = StringReplace(
    position_overflow_payload,
    "|1000|1000|0|1000|999",
    "|1000|1000|0|1001|999");
  Tests.AssertEqualInt(
    "change Snapshot Position count to the rejected 1,001 boundary",
    position_count_replacements,
    1);

  CTGKGridEntryMappingReducer position_overflow_reducer;
  Tests.AssertTrue(
    "initialize Position overflow Reducer",
    position_overflow_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "Snapshot with 1,001 Position Mappings is rejected",
    position_overflow_reducer.RestoreSnapshot(
      position_overflow_payload,
      position_capacity_reducer.LastSequence()));
  Tests.AssertEqualInt(
    "Position Snapshot overflow enters RECOVERY_ERROR",
    (int)position_overflow_reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);
  Tests.AssertEqualInt(
    "source still preserves all 1,000 Position Mappings",
    position_capacity_reducer.PositionCount(),
    1000);
  Tests.EndTest();

  Tests.BeginTest("Snapshot String Field accepts 4 KiB and rejects 4 KiB plus one byte");
  string request_id_4k;
  Tests.AssertTrue(
    "create exactly 4 KiB Request ID",
    StringInit(request_id_4k, 4096, 'R'));
  STGKGridMappingJournalRecord snapshot_field_records[];
  AddRecord(
    snapshot_field_records,
    1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|RESET_COMMITTED|1|BUY|1.0|3900.0|4100.0|4000.0|201");
  AddRecord(
    snapshot_field_records,
    2,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    StringFormat(
      "v1|%s|XAUUSD|710001|BUY|LEVEL|0|0.10|1|UT-INSTANCE",
      request_id_4k));

  CTGKGridEntryMappingReducer exact_snapshot_field_reducer;
  Tests.AssertTrue(
    "initialize exact Snapshot field Reducer",
    exact_snapshot_field_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay exact 4 KiB Request ID",
    exact_snapshot_field_reducer.Replay(
      snapshot_field_records,
      ArraySize(snapshot_field_records)));
  string exact_snapshot_field_payload;
  Tests.AssertTrue(
    "Snapshot accepts a 4 KiB String Field",
    exact_snapshot_field_reducer.ExportSnapshot(exact_snapshot_field_payload));

  CTGKGridEntryMappingReducer exact_snapshot_field_restored;
  Tests.AssertTrue(
    "initialize exact Snapshot field restore target",
    exact_snapshot_field_restored.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "restore Snapshot with 4 KiB String Field",
    exact_snapshot_field_restored.RestoreSnapshot(
      exact_snapshot_field_payload,
      exact_snapshot_field_reducer.LastSequence()));

  string request_id_over_4k;
  Tests.AssertTrue(
    "create 4 KiB plus one Request ID",
    StringInit(request_id_over_4k, 4097, 'R'));
  STGKGridMappingJournalRecord oversized_snapshot_field_records[];
  AddRecord(
    oversized_snapshot_field_records,
    1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|RESET_COMMITTED|1|BUY|1.0|3900.0|4100.0|4000.0|201");
  AddRecord(
    oversized_snapshot_field_records,
    2,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    StringFormat(
      "v1|%s|XAUUSD|710001|BUY|LEVEL|0|0.10|1|UT-INSTANCE",
      request_id_over_4k));
  CTGKGridEntryMappingReducer oversized_snapshot_field_reducer;
  Tests.AssertTrue(
    "initialize oversized Snapshot field Reducer",
    oversized_snapshot_field_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay oversized Request ID fixture before serialization",
    oversized_snapshot_field_reducer.Replay(
      oversized_snapshot_field_records,
      ArraySize(oversized_snapshot_field_records)));
  string rejected_snapshot_field_payload;
  Tests.AssertFalse(
    "Snapshot rejects a String Field above 4 KiB without truncation",
    oversized_snapshot_field_reducer.ExportSnapshot(rejected_snapshot_field_payload));
  Tests.EndTest();

  Tests.BeginTest("Read-only context queries require the exact healthy committed configuration");
  STGKGridMappingJournalRecord context_records[];
  AddBaseConfiguration(context_records);
  CTGKGridEntryMappingReducer context_reducer;
  Tests.AssertTrue(
    "initialize context reducer",
    context_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay committed BUY configuration",
    context_reducer.Replay(context_records, ArraySize(context_records)));
  Tests.AssertTrue(
    "exact Instance/Symbol/Magic/Mode/Epoch matches",
    context_reducer.MatchesContext(
      "UT-INSTANCE",
      "XAUUSD",
      710001,
      TGK_GRID_MODE_BUY,
      1));
  Tests.AssertFalse(
    "different Instance does not match",
    context_reducer.MatchesContext(
      "UT-OTHER",
      "XAUUSD",
      710001,
      TGK_GRID_MODE_BUY,
      1));
  Tests.AssertFalse(
    "different Symbol does not match",
    context_reducer.MatchesContext(
      "UT-INSTANCE",
      "EURUSD",
      710001,
      TGK_GRID_MODE_BUY,
      1));
  Tests.AssertFalse(
    "different Magic does not match",
    context_reducer.MatchesContext(
      "UT-INSTANCE",
      "XAUUSD",
      710002,
      TGK_GRID_MODE_BUY,
      1));
  Tests.AssertFalse(
    "different Mode does not match",
    context_reducer.MatchesContext(
      "UT-INSTANCE",
      "XAUUSD",
      710001,
      TGK_GRID_MODE_SELL,
      1));
  Tests.AssertFalse(
    "different Config Epoch does not match",
    context_reducer.MatchesContext(
      "UT-INSTANCE",
      "XAUUSD",
      710001,
      TGK_GRID_MODE_BUY,
      2));
  Tests.AssertFalse(
    "non-positive Config Epoch does not match",
    context_reducer.MatchesContext(
      "UT-INSTANCE",
      "XAUUSD",
      710001,
      TGK_GRID_MODE_BUY,
      0));

  CTGKGridEntryMappingReducer uninitialized_context;
  Tests.AssertFalse(
    "uninitialized Reducer does not match",
    uninitialized_context.MatchesContext(
      "UT-INSTANCE",
      "XAUUSD",
      710001,
      TGK_GRID_MODE_BUY,
      1));

  STGKGridMappingJournalRecord failed_context_records[];
  AddBaseConfiguration(failed_context_records);
  failed_context_records[1].sequence = 3;
  CTGKGridEntryMappingReducer failed_context;
  Tests.AssertTrue(
    "initialize failed-context Reducer",
    failed_context.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "malformed replay is rejected",
    failed_context.Replay(
      failed_context_records,
      ArraySize(failed_context_records)));
  Tests.AssertFalse(
    "Reducer in Recovery Error does not match",
    failed_context.MatchesContext(
      "UT-INSTANCE",
      "XAUUSD",
      710001,
      TGK_GRID_MODE_BUY,
      1));
  Tests.EndTest();

  Tests.BeginTest("Target mapping query distinguishes unmapped, mapped and invalid targets");
  STGKGridMappingJournalRecord mapping_query_records[];
  AddBaseConfiguration(mapping_query_records);
  CTGKGridEntryMappingReducer unmapped_query;
  Tests.AssertTrue(
    "initialize unmapped-query Reducer",
    unmapped_query.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay committed configuration for unmapped query",
    unmapped_query.Replay(
      mapping_query_records,
      ArraySize(mapping_query_records)));
  bool has_mapping = true;
  Tests.AssertTrue(
    "valid unmapped Level query succeeds",
    unmapped_query.TryGetPositionMapping(false, 1, has_mapping));
  Tests.AssertFalse("valid Level has no Position Mapping", has_mapping);
  Tests.AssertFalse(
    "negative normal Level query fails",
    unmapped_query.TryGetPositionMapping(false, -1, has_mapping));
  Tests.AssertFalse("failed query clears mapping output", has_mapping);
  Tests.AssertFalse(
    "Anchor query with non-anchor index fails",
    unmapped_query.TryGetPositionMapping(true, 0, has_mapping));
  Tests.AssertFalse("invalid Anchor query clears output", has_mapping);
  Tests.AssertFalse(
    "out-of-range Level query fails",
    unmapped_query.TryGetPositionMapping(false, 200, has_mapping));
  Tests.AssertFalse("out-of-range query clears output", has_mapping);

  STGKGridMappingJournalRecord mapped_level_records[];
  AddBaseConfiguration(mapped_level_records);
  int mapping_sequence = 3;
  AddMappedPosition(
    mapped_level_records,
    mapping_sequence,
    "REQ-MAPPED-LEVEL",
    "LEVEL",
    1,
    8101);
  CTGKGridEntryMappingReducer mapped_level_query;
  Tests.AssertTrue(
    "initialize mapped-Level Reducer",
    mapped_level_query.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay mapped-Level events",
    mapped_level_query.Replay(
      mapped_level_records,
      ArraySize(mapped_level_records)));
  Tests.AssertTrue(
    "mapped Level query succeeds",
    mapped_level_query.TryGetPositionMapping(false, 1, has_mapping));
  Tests.AssertTrue("target Level has Position Mapping", has_mapping);
  Tests.AssertTrue(
    "different Level query succeeds",
    mapped_level_query.TryGetPositionMapping(false, 0, has_mapping));
  Tests.AssertFalse("mapping is scoped to target Level", has_mapping);

  STGKGridMappingJournalRecord mapped_anchor_records[];
  AddBaseConfiguration(mapped_anchor_records);
  int anchor_sequence = 3;
  AddMappedPosition(
    mapped_anchor_records,
    anchor_sequence,
    "REQ-MAPPED-ANCHOR",
    "ANCHOR",
    -1,
    8102);
  CTGKGridEntryMappingReducer mapped_anchor_query;
  Tests.AssertTrue(
    "initialize mapped-Anchor Reducer",
    mapped_anchor_query.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay mapped-Anchor events",
    mapped_anchor_query.Replay(
      mapped_anchor_records,
      ArraySize(mapped_anchor_records)));
  Tests.AssertTrue(
    "mapped Anchor query succeeds",
    mapped_anchor_query.TryGetPositionMapping(true, -1, has_mapping));
  Tests.AssertTrue("Anchor has Position Mapping", has_mapping);

  CTGKGridEntryMappingReducer uninitialized_mapping_query;
  has_mapping = true;
  Tests.AssertFalse(
    "uninitialized Reducer mapping query fails",
    uninitialized_mapping_query.TryGetPositionMapping(false, 1, has_mapping));
  Tests.AssertFalse("failed uninitialized query clears output", has_mapping);

  CTGKGridEntryMappingReducer failed_mapping_query;
  STGKGridMappingJournalRecord failed_mapping_records[];
  AddBaseConfiguration(failed_mapping_records);
  failed_mapping_records[1].sequence = 3;
  Tests.AssertTrue(
    "initialize failed mapping-query Reducer",
    failed_mapping_query.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "malformed mapping-query replay is rejected",
    failed_mapping_query.Replay(
      failed_mapping_records,
      ArraySize(failed_mapping_records)));
  has_mapping = true;
  Tests.AssertFalse(
    "Recovery Error mapping query fails",
    failed_mapping_query.TryGetPositionMapping(false, 1, has_mapping));
  Tests.AssertFalse("failed Recovery Error query clears output", has_mapping);
  Tests.EndTest();

  Tests.BeginTest("Anchor State is not exposed before a committed configuration");
  ENUM_TGK_GRID_LEVEL_STATE anchor_state = TGK_GRID_LEVEL_WAIT_ACTIVATION;
  CTGKGridEntryMappingReducer uninitialized_anchor_reducer;
  Tests.AssertFalse(
    "uninitialized Reducer exposes no Anchor State",
    uninitialized_anchor_reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "failed Anchor query returns the deterministic default",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_READY);

  CTGKGridEntryMappingReducer initialized_anchor_reducer;
  Tests.AssertTrue(
    "initialize unconfigured Anchor Reducer",
    initialized_anchor_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  anchor_state = TGK_GRID_LEVEL_WAIT_RETURN;
  Tests.AssertFalse(
    "initialized Reducer without RESET_COMMITTED exposes no Anchor State",
    initialized_anchor_reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "unconfigured Anchor query returns the deterministic default",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_READY);
  Tests.EndTest();

  Tests.BeginTest("Anchor mapping confirmation activates Anchor State without changing Normal Level States");
  STGKGridMappingJournalRecord anchor_records[];
  AddBaseConfiguration(anchor_records);
  int anchor_mapping_sequence = 3;
  AddMappedPosition(
    anchor_records,
    anchor_mapping_sequence,
    "REQ-ANCHOR-LEVEL",
    "LEVEL",
    1,
    9101);
  AddMappedPosition(
    anchor_records,
    anchor_mapping_sequence,
    "REQ-ANCHOR-POSITION",
    "ANCHOR",
    -1,
    9102);

  CTGKGridEntryMappingReducer anchor_reducer;
  Tests.AssertTrue(
    "initialize committed Anchor Reducer",
    anchor_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay committed Anchor configuration",
    anchor_reducer.Replay(anchor_records, ArraySize(anchor_records)));
  Tests.AssertTrue(
    "committed Reducer exposes Anchor State",
    anchor_reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "Anchor State becomes ACTIVE when its Position Mapping is confirmed",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.AssertEqualInt(
    "mapped Level remains ACTIVE",
    anchor_reducer.LevelStateAt(1),
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.AssertEqualInt(
    "unmapped Level remains READY",
    anchor_reducer.LevelStateAt(0),
    (int)TGK_GRID_LEVEL_READY);

  long anchor_last_sequence = anchor_reducer.LastSequence();
  int anchor_level_count = anchor_reducer.LevelCount();
  int anchor_position_count = anchor_reducer.PositionCount();
  int anchor_level_state = anchor_reducer.LevelStateAt(1);
  for(int i = 0; i < 3; i++)
  {
    Tests.AssertTrue(
      "repeated Anchor query succeeds",
      anchor_reducer.TryGetAnchorState(anchor_state));
    Tests.AssertEqualInt(
      "repeated Anchor query returns ACTIVE",
      (int)anchor_state,
      (int)TGK_GRID_LEVEL_ACTIVE);
  }
  Tests.AssertEqualLong(
    "Anchor query preserves Sequence",
    anchor_reducer.LastSequence(),
    anchor_last_sequence);
  Tests.AssertEqualInt(
    "Anchor query preserves Level count",
    anchor_reducer.LevelCount(),
    anchor_level_count);
  Tests.AssertEqualInt(
    "Anchor query preserves Position count",
    anchor_reducer.PositionCount(),
    anchor_position_count);
  Tests.AssertEqualInt(
    "Anchor query preserves Level State",
    anchor_reducer.LevelStateAt(1),
    anchor_level_state);
  Tests.EndTest();

  Tests.BeginTest("Anchor State fails closed when the Reducer is invalid or unhealthy");
  STGKGridMappingJournalRecord invalid_anchor_reset_records[];
  AddRecord(
    invalid_anchor_reset_records,
    1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|RESET_COMMITTED|1|BUY|1.0|3900.0|4100.0|4000.0|200");
  CTGKGridEntryMappingReducer invalid_anchor_reset_reducer;
  Tests.AssertTrue(
    "initialize invalid Reset Anchor Reducer",
    invalid_anchor_reset_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "invalid RESET_COMMITTED is rejected",
    invalid_anchor_reset_reducer.Replay(
      invalid_anchor_reset_records,
      ArraySize(invalid_anchor_reset_records)));
  Tests.AssertEqualInt(
    "invalid Reset enters RECOVERY_ERROR",
    (int)invalid_anchor_reset_reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);
  anchor_state = TGK_GRID_LEVEL_ACTIVE;
  Tests.AssertFalse(
    "invalid Reset exposes no Anchor State",
    invalid_anchor_reset_reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "invalid Reset returns the deterministic default",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_READY);

  STGKGridMappingJournalRecord failed_anchor_records[];
  AddBaseConfiguration(failed_anchor_records);
  AddRecord(
    failed_anchor_records,
    4,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|LEVEL_STATE|1|1|ACTIVE");
  CTGKGridEntryMappingReducer failed_anchor_reducer;
  Tests.AssertTrue(
    "initialize failing Anchor Reducer",
    failed_anchor_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "Sequence gap after committed Reset is rejected",
    failed_anchor_reducer.Replay(
      failed_anchor_records,
      ArraySize(failed_anchor_records)));
  Tests.AssertEqualInt(
    "post-Reset failure enters RECOVERY_ERROR",
    (int)failed_anchor_reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);
  anchor_state = TGK_GRID_LEVEL_WAIT_RETURN;
  Tests.AssertFalse(
    "unhealthy Reducer exposes no Anchor State",
    failed_anchor_reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "unhealthy Reducer returns the deterministic default",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_READY);

  STGKGridMappingJournalRecord committed_anchor_records[];
  AddBaseConfiguration(committed_anchor_records);
  CTGKGridEntryMappingReducer failed_snapshot_anchor_reducer;
  Tests.AssertTrue(
    "initialize failed Snapshot Anchor Reducer",
    failed_snapshot_anchor_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay committed configuration before failed Snapshot",
    failed_snapshot_anchor_reducer.Replay(
      committed_anchor_records,
      ArraySize(committed_anchor_records)));
  Tests.AssertFalse(
    "malformed Snapshot is rejected",
    failed_snapshot_anchor_reducer.RestoreSnapshot("v1|STATE", 2));
  anchor_state = TGK_GRID_LEVEL_ACTIVE;
  Tests.AssertFalse(
    "failed Snapshot restore exposes no Anchor State",
    failed_snapshot_anchor_reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "failed Snapshot restore returns the deterministic default",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_READY);
  Tests.EndTest();

  Tests.BeginTest("Second committed Reset re-establishes a READY Anchor State");
  STGKGridMappingJournalRecord second_anchor_reset_records[];
  AddBaseConfiguration(second_anchor_reset_records);
  AddRecord(
    second_anchor_reset_records,
    3,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|RESET_COMMITTED|2|SELL|2.0|3800.0|4200.0|4000.0|201");
  CTGKGridEntryMappingReducer second_anchor_reset_reducer;
  Tests.AssertTrue(
    "initialize second Reset Anchor Reducer",
    second_anchor_reset_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "second committed Reset is accepted",
    second_anchor_reset_reducer.Replay(
      second_anchor_reset_records,
      ArraySize(second_anchor_reset_records)));
  Tests.AssertTrue(
    "second committed Reset exposes Anchor State",
    second_anchor_reset_reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "Anchor State is READY for the new Configuration Epoch",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertEqualInt(
    "Normal Level States are rebuilt READY",
    second_anchor_reset_reducer.LevelStateAt(1),
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertEqualInt(
    "new Configuration Epoch rebuilds 200 Level States",
    second_anchor_reset_reducer.LevelCount(),
    200);
  Tests.EndTest();

  Tests.BeginTest("Anchor becomes ACTIVE only when a confirmed Position Mapping exists");
  STGKGridMappingJournalRecord anchor_activation_records[];
  AddBaseConfiguration(anchor_activation_records);
  AddRecord(
    anchor_activation_records,
    3,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-A-ANCHOR|XAUUSD|710001|BUY|ANCHOR|-1|0.01|1|UT-INSTANCE");

  CTGKGridEntryMappingReducer anchor_intent_reducer;
  Tests.AssertTrue(
    "initialize Anchor intent Reducer",
    anchor_intent_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay Anchor Entry Intent",
    anchor_intent_reducer.Replay(
      anchor_activation_records,
      ArraySize(anchor_activation_records)));
  Tests.AssertTrue(
    "A01 Anchor intent alone exposes Anchor State",
    anchor_intent_reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "A01 Anchor intent alone does not activate Anchor",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_READY);

  AddRecord(
    anchor_activation_records,
    4,
    TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
    "v1|REQ-A-ANCHOR|DONE|7000001|7000002");
  AddRecord(
    anchor_activation_records,
    5,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    "v1|REQ-A-ANCHOR|7000002|7000003|0.01");

  CTGKGridEntryMappingReducer anchor_deal_reducer;
  Tests.AssertTrue(
    "initialize Anchor Deal Reducer",
    anchor_deal_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay Anchor Execution Result and Deal Association",
    anchor_deal_reducer.Replay(
      anchor_activation_records,
      ArraySize(anchor_activation_records)));
  Tests.AssertTrue(
    "A02/A03 Anchor stays mapped-free without a Position Mapping",
    anchor_deal_reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "A02/A03 Accepted result and Deal Association do not activate Anchor",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertEqualInt(
    "A02/A03 no Position Mapping is created",
    anchor_deal_reducer.PositionCount(),
    0);

  AddRecord(
    anchor_activation_records,
    6,
    TGK_GRID_MAPPING_RECORD_POSITION_MAPPING,
    "v1|REQ-A-ANCHOR|XAUUSD|710001|ANCHOR|-1|7000003|7000004|0.01|1|UT-INSTANCE");

  CTGKGridEntryMappingReducer anchor_mapped_reducer;
  Tests.AssertTrue(
    "initialize confirmed Anchor Reducer",
    anchor_mapped_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay confirmed Anchor Position Mapping",
    anchor_mapped_reducer.Replay(
      anchor_activation_records,
      ArraySize(anchor_activation_records)));
  Tests.AssertTrue(
    "A04 confirmed Anchor mapping exposes Anchor State",
    anchor_mapped_reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "A04 confirmed Anchor mapping activates Anchor State",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.EndTest();

  Tests.BeginTest("Invalid or duplicate Anchor mapping is rejected before mutation");
  STGKGridMappingJournalRecord duplicate_anchor_records[];
  AddBaseConfiguration(duplicate_anchor_records);
  int duplicate_sequence = 3;
  AddMappedPosition(
    duplicate_anchor_records,
    duplicate_sequence,
    "REQ-ANCHOR-FIRST",
    "ANCHOR",
    -1,
    9201);
  AddRecord(
    duplicate_anchor_records,
    duplicate_sequence,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-ANCHOR-SECOND|XAUUSD|710001|BUY|ANCHOR|-1|0.01|1|UT-INSTANCE");

  CTGKGridEntryMappingReducer duplicate_anchor_reducer;
  Tests.AssertTrue(
    "initialize duplicate Anchor Reducer",
    duplicate_anchor_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "A05 second Anchor mapping is rejected",
    duplicate_anchor_reducer.Replay(
      duplicate_anchor_records,
      ArraySize(duplicate_anchor_records)));
  Tests.AssertEqualInt(
    "A05 duplicate Anchor mapping enters RECOVERY_ERROR",
    (int)duplicate_anchor_reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);
  Tests.AssertEqualInt(
    "A05 only the first Anchor mapping remains",
    duplicate_anchor_reducer.PositionCount(),
    1);

  STGKGridMappingJournalRecord invalid_anchor_records[];
  AddBaseConfiguration(invalid_anchor_records);
  AddRecord(
    invalid_anchor_records,
    3,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-A-BAD|XAUUSD|710001|BUY|ANCHOR|-1|0.01|1|UT-INSTANCE");
  AddRecord(
    invalid_anchor_records,
    4,
    TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
    "v1|REQ-A-BAD|DONE|7000101|7000102");
  AddRecord(
    invalid_anchor_records,
    5,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    "v1|REQ-A-BAD|7000102|7000103|0.01");
  AddRecord(
    invalid_anchor_records,
    6,
    TGK_GRID_MAPPING_RECORD_POSITION_MAPPING,
    "v1|REQ-A-BAD|XAUUSD|710002|ANCHOR|-1|7000103|7000104|0.01|1|UT-INSTANCE");

  CTGKGridEntryMappingReducer invalid_anchor_reducer;
  Tests.AssertTrue(
    "initialize invalid Anchor Reducer",
    invalid_anchor_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "A06 Anchor mapping with invalid identity is rejected",
    invalid_anchor_reducer.Replay(
      invalid_anchor_records,
      ArraySize(invalid_anchor_records)));
  Tests.AssertEqualInt(
    "A06 invalid Anchor identity enters RECOVERY_ERROR",
    (int)invalid_anchor_reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);
  Tests.AssertEqualInt(
    "A06 no Position Mapping is stored",
    invalid_anchor_reducer.PositionCount(),
    0);
  Tests.EndTest();

  Tests.BeginTest("Anchor and Level Partial Close update Volume and Ticket while staying ACTIVE");
  STGKGridMappingJournalRecord metadata_records[];
  AddBaseConfiguration(metadata_records);
  int metadata_sequence = 3;
  AddMappedPosition(
    metadata_records,
    metadata_sequence,
    "REQ-META-ANCHOR",
    "ANCHOR",
    -1,
    9301);
  AddRecord(
    metadata_records,
    metadata_sequence++,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_METADATA|3009301|0.006|4009301");
  AddRecord(
    metadata_records,
    metadata_sequence++,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_METADATA|3009301|0.006|4009401");

  CTGKGridEntryMappingReducer metadata_reducer;
  Tests.AssertTrue(
    "initialize metadata Reducer",
    metadata_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay Partial Close metadata",
    metadata_reducer.Replay(
      metadata_records,
      ArraySize(metadata_records)));
  Tests.AssertEqualInt("P01 Anchor mapping remains", metadata_reducer.PositionCount(), 1);
  Tests.AssertEqualDouble("P01 Anchor Volume updated", metadata_reducer.PositionVolumeAt(0), 0.006);
  Tests.AssertEqualString("P04 refreshed Position Ticket", metadata_reducer.PositionTicketAt(0), "4009401");
  Tests.AssertEqualString("P04 Position Identifier unchanged", metadata_reducer.PositionIdentifierAt(0), "3009301");
  Tests.AssertTrue(
    "P04/P05 Anchor State remains queryable",
    metadata_reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "P04/P05 Anchor remains ACTIVE after Partial Close",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_ACTIVE);

  AddRecord(
    metadata_records,
    ArraySize(metadata_records) + 1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_METADATA|3009301|0.006|4009401");
  CTGKGridEntryMappingReducer duplicate_metadata_reducer;
  Tests.AssertTrue(
    "initialize duplicate metadata Reducer",
    duplicate_metadata_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "I09 unchanged metadata observation is rejected",
    duplicate_metadata_reducer.Replay(
      metadata_records,
      ArraySize(metadata_records)));
  Tests.EndTest();

  Tests.BeginTest("Conflicting Partial Close metadata fails closed");
  STGKGridMappingJournalRecord metadata_anchor_fixture[];
  AddBaseConfiguration(metadata_anchor_fixture);
  int metadata_anchor_sequence = 3;
  AddMappedPosition(
    metadata_anchor_fixture,
    metadata_anchor_sequence,
    "REQ-META-CONFLICT",
    "ANCHOR",
    -1,
    9401);

  STGKGridMappingJournalRecord grown_volume_records[];
  ArrayResize(grown_volume_records, ArraySize(metadata_anchor_fixture));
  for(int i = 0; i < ArraySize(metadata_anchor_fixture); i++)
    grown_volume_records[i] = metadata_anchor_fixture[i];
  AddRecord(
    grown_volume_records,
    ArraySize(grown_volume_records) + 1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_METADATA|3009401|0.02|4009401");
  CTGKGridEntryMappingReducer grown_volume_reducer;
  Tests.AssertTrue(
    "initialize grown-Volume Reducer",
    grown_volume_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "P07 increased Volume for the same Position is rejected",
    grown_volume_reducer.Replay(
      grown_volume_records,
      ArraySize(grown_volume_records)));
  Tests.AssertEqualInt(
    "P07 conflicting Volume enters RECOVERY_ERROR",
    (int)grown_volume_reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);

  STGKGridMappingJournalRecord zero_volume_records[];
  ArrayResize(zero_volume_records, ArraySize(metadata_anchor_fixture));
  for(int i = 0; i < ArraySize(metadata_anchor_fixture); i++)
    zero_volume_records[i] = metadata_anchor_fixture[i];
  AddRecord(
    zero_volume_records,
    ArraySize(zero_volume_records) + 1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_METADATA|3009401|0|4009401");
  CTGKGridEntryMappingReducer zero_volume_reducer;
  Tests.AssertTrue(
    "initialize zero-Volume Reducer",
    zero_volume_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "P06 zero Volume must use the Full Close transition",
    zero_volume_reducer.Replay(
      zero_volume_records,
      ArraySize(zero_volume_records)));

  STGKGridMappingJournalRecord unknown_metadata_records[];
  ArrayResize(unknown_metadata_records, ArraySize(metadata_anchor_fixture));
  for(int i = 0; i < ArraySize(metadata_anchor_fixture); i++)
    unknown_metadata_records[i] = metadata_anchor_fixture[i];
  AddRecord(
    unknown_metadata_records,
    ArraySize(unknown_metadata_records) + 1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_METADATA|3009999|0.005|4009999");
  CTGKGridEntryMappingReducer unknown_metadata_reducer;
  Tests.AssertTrue(
    "initialize unknown-Identifier Reducer",
    unknown_metadata_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "P08 unknown Position Identifier is rejected",
    unknown_metadata_reducer.Replay(
      unknown_metadata_records,
      ArraySize(unknown_metadata_records)));
  Tests.EndTest();

  Tests.BeginTest("Reason-free Full Close updates Anchor and Level state atomically");
  STGKGridMappingJournalRecord anchor_close_records[];
  AddBaseConfiguration(anchor_close_records);
  int anchor_close_sequence = 3;
  AddMappedPosition(
    anchor_close_records,
    anchor_close_sequence,
    "REQ-CLOSE-ANCHOR",
    "ANCHOR",
    -1,
    9501);
  AddRecord(
    anchor_close_records,
    anchor_close_sequence,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_CLOSED|3009501|WAIT_ACTIVATION");

  CTGKGridEntryMappingReducer anchor_close_reducer;
  Tests.AssertTrue(
    "initialize Anchor close Reducer",
    anchor_close_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay reason-free Anchor close",
    anchor_close_reducer.Replay(
      anchor_close_records,
      ArraySize(anchor_close_records)));
  Tests.AssertEqualInt("C11 Anchor mapping removed", anchor_close_reducer.PositionCount(), 0);
  Tests.AssertTrue(
    "C11 Anchor State remains queryable",
    anchor_close_reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "C11 Anchor State updated to WAIT_ACTIVATION",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);

  STGKGridMappingJournalRecord level_close_records[];
  AddBaseConfiguration(level_close_records);
  AddFilledLevelRequest(level_close_records);
  AddRecord(
    level_close_records,
    ArraySize(level_close_records) + 1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_CLOSED|18446744073709551613|WAIT_ACTIVATION");
  CTGKGridEntryMappingReducer level_close_reducer;
  Tests.AssertTrue(
    "initialize Level close Reducer",
    level_close_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay reason-free Level close",
    level_close_reducer.Replay(
      level_close_records,
      ArraySize(level_close_records)));
  Tests.AssertEqualInt("C12 Level mapping removed", level_close_reducer.PositionCount(), 0);
  Tests.AssertEqualInt(
    "C12 Level State updated to WAIT_ACTIVATION",
    level_close_reducer.LevelStateAt(1),
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);

  STGKGridMappingJournalRecord two_close_records[];
  AddBaseConfiguration(two_close_records);
  int two_close_sequence = 3;
  AddMappedPosition(
    two_close_records,
    two_close_sequence,
    "REQ-TWO-CLOSE-1",
    "LEVEL",
    1,
    9551);
  AddMappedPosition(
    two_close_records,
    two_close_sequence,
    "REQ-TWO-CLOSE-2",
    "LEVEL",
    2,
    9552);
  int first_close_count = ArraySize(two_close_records);
  AddRecord(
    two_close_records,
    two_close_sequence++,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_CLOSED|3009551|READY");
  AddRecord(
    two_close_records,
    two_close_sequence,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_CLOSED|3009552|WAIT_ACTIVATION");

  STGKGridMappingJournalRecord interrupted_close_records[];
  ArrayResize(interrupted_close_records, first_close_count + 1);
  for(int i = 0; i <= first_close_count; i++)
    interrupted_close_records[i] = two_close_records[i];

  CTGKGridEntryMappingReducer interrupted_close_reducer;
  Tests.AssertTrue(
    "initialize interrupted close Reducer",
    interrupted_close_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay only the first committed close record",
    interrupted_close_reducer.Replay(
      interrupted_close_records,
      ArraySize(interrupted_close_records)));
  Tests.AssertEqualInt(
    "C16 first close removes one mapping",
    interrupted_close_reducer.PositionCount(),
    1);
  Tests.AssertEqualInt(
    "C16 second Level remains ACTIVE until its record",
    interrupted_close_reducer.LevelStateAt(2),
    (int)TGK_GRID_LEVEL_ACTIVE);

  CTGKGridEntryMappingReducer two_close_reducer;
  Tests.AssertTrue(
    "initialize two-close Reducer",
    two_close_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay both ordered close records",
    two_close_reducer.Replay(
      two_close_records,
      ArraySize(two_close_records)));
  Tests.AssertEqualInt("C16 both mappings removed", two_close_reducer.PositionCount(), 0);
  Tests.AssertEqualInt(
    "C16 first Level closed",
    two_close_reducer.LevelStateAt(1),
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertEqualInt(
    "C16 second Level closed",
    two_close_reducer.LevelStateAt(2),
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.EndTest();

  Tests.BeginTest("Invalid Full Close evidence is rejected without mutation");
  STGKGridMappingJournalRecord close_fixture[];
  AddBaseConfiguration(close_fixture);
  int close_fixture_sequence = 3;
  AddMappedPosition(
    close_fixture,
    close_fixture_sequence,
    "REQ-CLOSE-ERROR",
    "ANCHOR",
    -1,
    9601);

  STGKGridMappingJournalRecord close_active_records[];
  ArrayResize(close_active_records, ArraySize(close_fixture));
  for(int i = 0; i < ArraySize(close_fixture); i++)
    close_active_records[i] = close_fixture[i];
  AddRecord(
    close_active_records,
    ArraySize(close_active_records) + 1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_CLOSED|3009601|ACTIVE");
  CTGKGridEntryMappingReducer close_active_reducer;
  Tests.AssertTrue(
    "initialize ACTIVE close Reducer",
    close_active_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "C15 Full Close cannot set ACTIVE",
    close_active_reducer.Replay(
      close_active_records,
      ArraySize(close_active_records)));
  Tests.AssertEqualInt(
    "C15 rejected close leaves the mapping intact",
    close_active_reducer.PositionCount(),
    1);

  CTGKGridEntryMappingReducer close_prefix_reducer;
  Tests.AssertTrue(
    "initialize valid close-prefix Reducer",
    close_prefix_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay valid close-prefix fixture",
    close_prefix_reducer.Replay(
      close_fixture,
      ArraySize(close_fixture)));
  Tests.AssertTrue(
    "C15 pre-close Anchor State is queryable",
    close_prefix_reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "C15 pre-close Anchor State is ACTIVE",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_ACTIVE);

  STGKGridMappingJournalRecord unknown_close_records[];
  ArrayResize(unknown_close_records, ArraySize(close_fixture));
  for(int i = 0; i < ArraySize(close_fixture); i++)
    unknown_close_records[i] = close_fixture[i];
  AddRecord(
    unknown_close_records,
    ArraySize(unknown_close_records) + 1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_CLOSED|3009999|READY");
  CTGKGridEntryMappingReducer unknown_close_reducer;
  Tests.AssertTrue(
    "initialize unknown close Reducer",
    unknown_close_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "C13 Full Close with unknown Identifier is rejected",
    unknown_close_reducer.Replay(
      unknown_close_records,
      ArraySize(unknown_close_records)));
  Tests.AssertEqualInt(
    "C13 unknown close enters RECOVERY_ERROR",
    (int)unknown_close_reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);
  Tests.EndTest();

  Tests.BeginTest("Legacy close payloads replay and normalize without a reason branch");
  STGKGridMappingJournalRecord legacy_tp_records[];
  AddBaseConfiguration(legacy_tp_records);
  AddFilledLevelRequest(legacy_tp_records);
  AddRecord(
    legacy_tp_records,
    ArraySize(legacy_tp_records) + 1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_CLOSED|18446744073709551613|TP|WAIT_RETURN");
  CTGKGridEntryMappingReducer legacy_tp_reducer;
  Tests.AssertTrue(
    "initialize legacy TP Reducer",
    legacy_tp_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "L01 replay legacy TP close",
    legacy_tp_reducer.Replay(
      legacy_tp_records,
      ArraySize(legacy_tp_records)));
  Tests.AssertEqualInt("L01 legacy mapping removed", legacy_tp_reducer.PositionCount(), 0);
  Tests.AssertEqualInt(
    "L01 legacy WAIT_RETURN normalized to READY",
    legacy_tp_reducer.LevelStateAt(1),
    (int)TGK_GRID_LEVEL_READY);

  string legacy_tp_snapshot_payload;
  Tests.AssertTrue(
    "R07 export Snapshot after legacy normalization",
    legacy_tp_reducer.ExportSnapshot(legacy_tp_snapshot_payload));
  CTGKGridEntryMappingReducer legacy_tp_snapshot_reducer;
  Tests.AssertTrue(
    "initialize legacy-normalized Snapshot Reducer",
    legacy_tp_snapshot_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "R07 restore normalized Snapshot",
    legacy_tp_snapshot_reducer.RestoreSnapshot(
      legacy_tp_snapshot_payload,
      legacy_tp_reducer.LastSequence()));
  Tests.AssertEqualInt(
    "R07 Snapshot writes READY, never WAIT_RETURN",
    legacy_tp_snapshot_reducer.LevelStateAt(1),
    (int)TGK_GRID_LEVEL_READY);

  STGKGridMappingJournalRecord legacy_ready_records[];
  AddBaseConfiguration(legacy_ready_records);
  AddFilledLevelRequest(legacy_ready_records);
  AddRecord(
    legacy_ready_records,
    ArraySize(legacy_ready_records) + 1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_CLOSED|18446744073709551613|NON_TP|READY");
  CTGKGridEntryMappingReducer legacy_ready_reducer;
  Tests.AssertTrue(
    "initialize legacy NON_TP Reducer",
    legacy_ready_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "L02 replay legacy NON_TP close",
    legacy_ready_reducer.Replay(
      legacy_ready_records,
      ArraySize(legacy_ready_records)));
  Tests.AssertEqualInt(
    "L02 legacy close results in READY",
    legacy_ready_reducer.LevelStateAt(1),
    (int)TGK_GRID_LEVEL_READY);

  STGKGridMappingJournalRecord legacy_activation_records[];
  AddBaseConfiguration(legacy_activation_records);
  AddFilledLevelRequest(legacy_activation_records);
  AddRecord(
    legacy_activation_records,
    ArraySize(legacy_activation_records) + 1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_CLOSED|18446744073709551613|NON_TP|WAIT_ACTIVATION");
  CTGKGridEntryMappingReducer legacy_activation_reducer;
  Tests.AssertTrue(
    "initialize legacy WAIT_ACTIVATION Reducer",
    legacy_activation_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "L03 replay legacy WAIT_ACTIVATION close",
    legacy_activation_reducer.Replay(
      legacy_activation_records,
      ArraySize(legacy_activation_records)));
  Tests.AssertEqualInt(
    "L03 WAIT_ACTIVATION is preserved",
    legacy_activation_reducer.LevelStateAt(1),
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);

  STGKGridMappingJournalRecord legacy_anchor_records[];
  AddBaseConfiguration(legacy_anchor_records);
  int legacy_anchor_sequence = 3;
  AddMappedPosition(
    legacy_anchor_records,
    legacy_anchor_sequence,
    "REQ-LEGACY-ANCHOR",
    "ANCHOR",
    -1,
    9701);
  AddRecord(
    legacy_anchor_records,
    legacy_anchor_sequence,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_CLOSED|3009701|TP|NONE");
  CTGKGridEntryMappingReducer legacy_anchor_reducer;
  Tests.AssertTrue(
    "initialize legacy Anchor close Reducer",
    legacy_anchor_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "L04 replay legacy Anchor close",
    legacy_anchor_reducer.Replay(
      legacy_anchor_records,
      ArraySize(legacy_anchor_records)));
  Tests.AssertEqualInt("L04 Anchor mapping removed", legacy_anchor_reducer.PositionCount(), 0);
  Tests.AssertTrue(
    "L04 Anchor State query succeeds",
    legacy_anchor_reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "L04 legacy Anchor NONE normalized to READY",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_READY);
  Tests.EndTest();

  Tests.BeginTest("State-based idempotency rejects duplicate and stale close records");
  STGKGridMappingJournalRecord idempotent_records[];
  AddBaseConfiguration(idempotent_records);
  int idempotent_sequence = 3;
  AddMappedPosition(
    idempotent_records,
    idempotent_sequence,
    "REQ-CLOSE-ONCE",
    "ANCHOR",
    -1,
    9801);
  AddRecord(
    idempotent_records,
    idempotent_sequence,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_CLOSED|3009801|READY");

  CTGKGridEntryMappingReducer idempotent_reducer;
  Tests.AssertTrue(
    "initialize idempotent Reducer",
    idempotent_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "first close is applied exactly once",
    idempotent_reducer.Replay(
      idempotent_records,
      ArraySize(idempotent_records)));
  Tests.AssertEqualInt("I01 mapping is absent after close", idempotent_reducer.PositionCount(), 0);

  AddRecord(
    idempotent_records,
    ArraySize(idempotent_records) + 1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_CLOSED|3009801|READY");
  CTGKGridEntryMappingReducer duplicate_close_reducer;
  Tests.AssertTrue(
    "initialize duplicate close Reducer",
    duplicate_close_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "I06 repeated close record with a new Sequence is rejected",
    duplicate_close_reducer.Replay(
      idempotent_records,
      ArraySize(idempotent_records)));
  Tests.AssertEqualInt(
    "I06 rejected duplicate close enters RECOVERY_ERROR",
    (int)duplicate_close_reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);

  STGKGridMappingJournalRecord remapped_records[];
  AddBaseConfiguration(remapped_records);
  int remapped_sequence = 3;
  AddMappedPosition(
    remapped_records,
    remapped_sequence,
    "REQ-OLD-POSITION",
    "LEVEL",
    1,
    9901);
  AddRecord(
    remapped_records,
    remapped_sequence++,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_CLOSED|3009901|READY");
  AddRecord(
    remapped_records,
    remapped_sequence++,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|LEVEL_STATE|1|1|READY");
  AddMappedPosition(
    remapped_records,
    remapped_sequence,
    "REQ-NEW-POSITION",
    "LEVEL",
    1,
    9902);
  AddRecord(
    remapped_records,
    remapped_sequence,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_CLOSED|3009901|READY");

  CTGKGridEntryMappingReducer remapped_reducer;
  Tests.AssertTrue(
    "initialize remapped Level Reducer",
    remapped_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "I07 stale close for the old Identifier is rejected",
    remapped_reducer.Replay(
      remapped_records,
      ArraySize(remapped_records)));
  Tests.AssertEqualInt(
    "I07 rejected stale close leaves the new mapping intact",
    remapped_reducer.PositionCount(),
    1);
  Tests.AssertEqualString(
    "I07 new Position Identifier is unchanged",
    remapped_reducer.PositionIdentifierAt(0),
    "3009902");
  Tests.AssertEqualInt(
    "I07 new mapping remains ACTIVE",
    remapped_reducer.LevelStateAt(1),
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.EndTest();

  Tests.BeginTest("Snapshot persists Anchor State and rejects a missing Anchor State field");
  STGKGridMappingJournalRecord snapshot_anchor_records[];
  AddBaseConfiguration(snapshot_anchor_records);
  int snapshot_anchor_sequence = 3;
  AddMappedPosition(
    snapshot_anchor_records,
    snapshot_anchor_sequence,
    "REQ-SNAPSHOT-ANCHOR",
    "ANCHOR",
    -1,
    9951);

  CTGKGridEntryMappingReducer snapshot_anchor_source;
  Tests.AssertTrue(
    "initialize Anchor Snapshot source",
    snapshot_anchor_source.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay Anchor Snapshot fixture",
    snapshot_anchor_source.Replay(
      snapshot_anchor_records,
      ArraySize(snapshot_anchor_records)));
  string anchor_snapshot_payload;
  Tests.AssertTrue(
    "export Snapshot with ACTIVE Anchor",
    snapshot_anchor_source.ExportSnapshot(anchor_snapshot_payload));

  CTGKGridEntryMappingReducer snapshot_anchor_restored;
  Tests.AssertTrue(
    "initialize Anchor Snapshot target",
    snapshot_anchor_restored.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "restore Snapshot with ACTIVE Anchor",
    snapshot_anchor_restored.RestoreSnapshot(
      anchor_snapshot_payload,
      snapshot_anchor_source.LastSequence()));
  Tests.AssertEqualInt(
    "F07 Anchor mapping survives Snapshot",
    snapshot_anchor_restored.PositionCount(),
    1);
  Tests.AssertTrue(
    "F07 restored Anchor State is queryable",
    snapshot_anchor_restored.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "F07 restored Anchor State is ACTIVE",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_ACTIVE);

  STGKGridMappingJournalRecord snapshot_base_records[];
  AddBaseConfiguration(snapshot_base_records);
  CTGKGridEntryMappingReducer snapshot_base_reducer;
  Tests.AssertTrue(
    "initialize base Snapshot Reducer",
    snapshot_base_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay base configuration",
    snapshot_base_reducer.Replay(
      snapshot_base_records,
      ArraySize(snapshot_base_records)));
  string base_snapshot_payload;
  Tests.AssertTrue(
    "export base Snapshot",
    snapshot_base_reducer.ExportSnapshot(base_snapshot_payload));

  string missing_anchor_payload = base_snapshot_payload;
  int missing_anchor_replacements = StringReplace(
    missing_anchor_payload,
    "|201|0|0|0|200|0|",
    "|201|0|0|0|200|");
  Tests.AssertEqualInt(
    "remove the required Anchor State field",
    missing_anchor_replacements,
    1);
  CTGKGridEntryMappingReducer missing_anchor_reducer;
  Tests.AssertTrue(
    "initialize missing-Anchor Snapshot Reducer",
    missing_anchor_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "L07 Snapshot without Anchor State fails closed",
    missing_anchor_reducer.RestoreSnapshot(
      missing_anchor_payload,
      snapshot_base_reducer.LastSequence()));
  Tests.AssertEqualInt(
    "L07 missing Anchor State enters RECOVERY_ERROR",
    (int)missing_anchor_reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);

  string legacy_anchor_state_payload = base_snapshot_payload;
  Tests.AssertEqualInt(
    "set legacy numeric WAIT_RETURN Anchor State",
    StringReplace(
      legacy_anchor_state_payload,
      "|201|0|0|0|200|0|",
      "|201|0|0|0|200|2|"),
    1);
  CTGKGridEntryMappingReducer legacy_anchor_state_reducer;
  Tests.AssertTrue(
    "initialize legacy Anchor State Snapshot Reducer",
    legacy_anchor_state_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "L05 load legacy numeric WAIT_RETURN Anchor State",
    legacy_anchor_state_reducer.RestoreSnapshot(
      legacy_anchor_state_payload,
      snapshot_base_reducer.LastSequence()));
  Tests.AssertTrue(
    "L05 normalized Anchor State is queryable",
    legacy_anchor_state_reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "L05 legacy Anchor WAIT_RETURN normalized to READY",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_READY);

  string activation_anchor_state_payload = base_snapshot_payload;
  Tests.AssertEqualInt(
    "set WAIT_ACTIVATION Anchor State",
    StringReplace(
      activation_anchor_state_payload,
      "|201|0|0|0|200|0|",
      "|201|0|0|0|200|3|"),
    1);
  CTGKGridEntryMappingReducer activation_anchor_state_reducer;
  Tests.AssertTrue(
    "initialize WAIT_ACTIVATION Snapshot Reducer",
    activation_anchor_state_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "L06 load WAIT_ACTIVATION Anchor State",
    activation_anchor_state_reducer.RestoreSnapshot(
      activation_anchor_state_payload,
      snapshot_base_reducer.LastSequence()));
  Tests.AssertTrue(
    "L06 Anchor State remains queryable",
    activation_anchor_state_reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "L06 WAIT_ACTIVATION numeric ordinal is preserved",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);

  STGKGridMappingJournalRecord post_snapshot_records[];
  int post_snapshot_sequence = 3;
  AddMappedPosition(
    post_snapshot_records,
    post_snapshot_sequence,
    "REQ-POST-SNAPSHOT",
    "LEVEL",
    1,
    9961);
  CTGKGridEntryMappingReducer post_snapshot_reducer;
  Tests.AssertTrue(
    "initialize post-Snapshot Reducer",
    post_snapshot_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "restore base Snapshot checkpoint",
    post_snapshot_reducer.RestoreSnapshot(
      base_snapshot_payload,
      snapshot_base_reducer.LastSequence()));
  Tests.AssertTrue(
    "F08 replay later Journal records",
    post_snapshot_reducer.Replay(
      post_snapshot_records,
      ArraySize(post_snapshot_records)));
  Tests.AssertEqualInt(
    "F08 later mapping is ACTIVE after replay",
    post_snapshot_reducer.LevelStateAt(1),
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.EndTest();

  Tests.BeginTest("CR-01 Anchor WAIT_ACTIVATION becomes durably READY and is replayable");
  STGKGridMappingJournalRecord activation_records[];
  AddBaseConfiguration(activation_records);
  int activation_sequence = 3;
  AddMappedPosition(
    activation_records,
    activation_sequence,
    "REQ-ACTIVATION",
    "ANCHOR",
    -1,
    9971);
  AddRecord(
    activation_records,
    activation_sequence++,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_CLOSED|3009971|WAIT_ACTIVATION");

  CTGKGridEntryMappingReducer activation_source;
  Tests.AssertTrue(
    "initialize activation source Reducer",
    activation_source.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay Anchor Full Close before activation",
    activation_source.Replay(
      activation_records,
      ArraySize(activation_records)));
  Tests.AssertEqualInt(
    "CR01-01 Anchor mapping is removed",
    activation_source.PositionCount(),
    0);
  Tests.AssertTrue(
    "CR01-01 Anchor State is queryable",
    activation_source.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "CR01-01 Anchor State is WAIT_ACTIVATION",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);

  string waiting_snapshot_payload;
  Tests.AssertTrue(
    "export WAIT_ACTIVATION Snapshot",
    activation_source.ExportSnapshot(waiting_snapshot_payload));

  AddRecord(
    activation_records,
    activation_sequence,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|ANCHOR_STATE|1|READY");

  CTGKGridEntryMappingReducer activation_committed;
  Tests.AssertTrue(
    "initialize activation Reducer",
    activation_committed.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "CR01-06 replay committed activation event",
    activation_committed.Replay(
      activation_records,
      ArraySize(activation_records)));
  Tests.AssertTrue(
    "CR01-06 Anchor State is queryable",
    activation_committed.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "CR01-06 Anchor State restored to READY",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertEqualInt(
    "CR01-06 activation creates no mapping",
    activation_committed.PositionCount(),
    0);

  string ready_snapshot_payload;
  Tests.AssertTrue(
    "export READY Snapshot",
    activation_committed.ExportSnapshot(ready_snapshot_payload));
  CTGKGridEntryMappingReducer activation_restored;
  Tests.AssertTrue(
    "initialize restored Reducer",
    activation_restored.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "CR01-07 restore Snapshot after activation",
    activation_restored.RestoreSnapshot(
      ready_snapshot_payload,
      activation_committed.LastSequence()));
  Tests.AssertTrue(
    "CR01-07 restored Anchor State is queryable",
    activation_restored.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "CR01-07 restored Anchor State is READY",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_READY);
  bool activation_has_mapping = true;
  Tests.AssertTrue(
    "CR01-07 Anchor mapping query succeeds",
    activation_restored.TryGetPositionMapping(
      true,
      -1,
      activation_has_mapping));
  Tests.AssertFalse(
    "CR01-07 no Anchor mapping exists",
    activation_has_mapping);

  CTGKGridEntryMappingReducer activation_restart;
  Tests.AssertTrue(
    "initialize restart Reducer",
    activation_restart.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "restore pre-activation Snapshot checkpoint",
    activation_restart.RestoreSnapshot(
      waiting_snapshot_payload,
      activation_source.LastSequence()));
  STGKGridMappingJournalRecord activation_event[];
  ArrayResize(activation_event, 1);
  activation_event[0] = activation_records[ArraySize(activation_records) - 1];
  Tests.AssertTrue(
    "CR01-13 durable append replays after restart",
    activation_restart.Replay(activation_event, ArraySize(activation_event)));
  Tests.AssertTrue(
    "CR01-13 replayed Anchor State is queryable",
    activation_restart.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "CR01-13 replay converges to READY",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_READY);

  STGKGridMappingJournalRecord duplicate_activation_event[];
  ArrayResize(duplicate_activation_event, 1);
  duplicate_activation_event[0] = activation_event[0];
  duplicate_activation_event[0].sequence = activation_event[0].sequence + 1;
  Tests.AssertFalse(
    "CR01-11 duplicate READY transition is rejected",
    activation_restart.Replay(
      duplicate_activation_event,
      ArraySize(duplicate_activation_event)));
  Tests.EndTest();

  Tests.BeginTest("CR-01 durable Anchor activation permits the next Anchor mapping");
  AddRecord(
    activation_records,
    ArraySize(activation_records) + 1,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-REANCHOR|XAUUSD|710001|BUY|ANCHOR|-1|0.01|1|UT-INSTANCE");
  AddRecord(
    activation_records,
    ArraySize(activation_records) + 1,
    TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
    "v1|REQ-REANCHOR|DONE|1009981|0");
  AddRecord(
    activation_records,
    ArraySize(activation_records) + 1,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    "v1|REQ-REANCHOR|2009981|3009981|0.01");
  AddRecord(
    activation_records,
    ArraySize(activation_records) + 1,
    TGK_GRID_MAPPING_RECORD_POSITION_MAPPING,
    "v1|REQ-REANCHOR|XAUUSD|710001|ANCHOR|-1|3009981|4009981|0.01|1|UT-INSTANCE");

  CTGKGridEntryMappingReducer activation_reentry;
  Tests.AssertTrue(
    "initialize Anchor re-entry Reducer",
    activation_reentry.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "CR01-08/09 Anchor Entry Intent and Mapping are accepted",
    activation_reentry.Replay(
      activation_records,
      ArraySize(activation_records)));
  Tests.AssertEqualInt(
    "CR01-09 Anchor mapping is stored",
    activation_reentry.PositionCount(),
    1);
  Tests.AssertEqualString(
    "CR01-09 stored Anchor Identifier",
    activation_reentry.PositionIdentifierAt(0),
    "3009981");
  Tests.AssertTrue(
    "CR01-09 Anchor State is queryable",
    activation_reentry.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "CR01-09 Anchor State is ACTIVE",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.EndTest();

  Tests.BeginTest("CR-01 invalid Anchor state transitions fail closed");
  STGKGridMappingJournalRecord mapped_guard_records[];
  BuildAnchorStateFixture(mapped_guard_records, 0);
  CTGKGridEntryMappingReducer mapped_guard_prefix;
  Tests.AssertTrue(
    "initialize mapped Anchor guard Reducer",
    mapped_guard_prefix.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay mapped Anchor prefix",
    mapped_guard_prefix.Replay(
      mapped_guard_records,
      ArraySize(mapped_guard_records)));
  Tests.AssertTrue(
    "mapped Anchor prefix is ACTIVE",
    mapped_guard_prefix.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "mapped Anchor prefix state value",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_ACTIVE);

  AddRecord(
    mapped_guard_records,
    ArraySize(mapped_guard_records) + 1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|ANCHOR_STATE|1|READY");
  CTGKGridEntryMappingReducer mapped_guard_reducer;
  Tests.AssertTrue(
    "initialize rejected Anchor transition Reducer",
    mapped_guard_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "CR01-10 transition with an Anchor mapping is rejected",
    mapped_guard_reducer.Replay(
      mapped_guard_records,
      ArraySize(mapped_guard_records)));
  Tests.AssertEqualInt(
    "CR01-10 rejection enters RECOVERY_ERROR",
    (int)mapped_guard_reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);
  Tests.AssertEqualInt(
    "CR01-10 mapping is not removed",
    mapped_guard_reducer.PositionCount(),
    1);

  Tests.AssertFalse(
    "CR01-11 READY origin is rejected",
    ReplayAnchorStateAttempt("v1|ANCHOR_STATE|1|READY", 2));
  Tests.AssertFalse(
    "CR01-11 ACTIVE target is rejected",
    ReplayAnchorStateAttempt("v1|ANCHOR_STATE|1|ACTIVE", 1));
  Tests.AssertFalse(
    "CR01-11 WAIT_ACTIVATION target is rejected",
    ReplayAnchorStateAttempt("v1|ANCHOR_STATE|1|WAIT_ACTIVATION", 1));
  Tests.AssertFalse(
    "CR01-11 unknown state is rejected",
    ReplayAnchorStateAttempt("v1|ANCHOR_STATE|1|BOGUS", 1));
  Tests.AssertFalse(
    "CR01-11 mismatched Config Epoch is rejected",
    ReplayAnchorStateAttempt("v1|ANCHOR_STATE|2|READY", 1));
  Tests.AssertTrue(
    "CR01-11 valid WAIT_ACTIVATION to READY is accepted",
    ReplayAnchorStateAttempt("v1|ANCHOR_STATE|1|READY", 1));
  Tests.EndTest();

  Tests.BeginTest("Reconciliation Batch applies metadata and Full Close atomically");
  bool batch_replayed = false;
  double batch_volume = 0.0;
  int batch_position_count = 0;
  int batch_level_one_state = -1;
  int batch_level_two_state = -1;
  ReplayBatchOutcome(
    "v1|RECONCILIATION_BATCH|2|POSITION_METADATA|3008101|0.005|4008101|POSITION_CLOSED|3008102|READY",
    batch_replayed,
    batch_volume,
    batch_position_count,
    batch_level_one_state,
    batch_level_two_state);
  Tests.AssertTrue("valid batch replays", batch_replayed);
  Tests.AssertEqualInt("one Mapping removed", batch_position_count, 1);
  Tests.AssertEqualDouble("remaining Volume applied", batch_volume, 0.005);
  Tests.AssertEqualInt(
    "metadata target keeps ACTIVE",
    batch_level_one_state,
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.AssertEqualInt(
    "closed target becomes READY",
    batch_level_two_state,
    (int)TGK_GRID_LEVEL_READY);
  Tests.EndTest();

  Tests.BeginTest("Malformed Reconciliation Batch applies no prefix");
  string malformed_batches[];
  ArrayResize(malformed_batches, 0);
  ArrayResize(malformed_batches, ArraySize(malformed_batches) + 1);
  malformed_batches[ArraySize(malformed_batches) - 1] =
    "v1|RECONCILIATION_BATCH|2|POSITION_METADATA|3008101|0.005|4008101";
  ArrayResize(malformed_batches, ArraySize(malformed_batches) + 1);
  malformed_batches[ArraySize(malformed_batches) - 1] =
    "v1|RECONCILIATION_BATCH|1|POSITION_METADATA|3008101|0.005|4008101|POSITION_CLOSED|3008102|READY";
  ArrayResize(malformed_batches, ArraySize(malformed_batches) + 1);
  malformed_batches[ArraySize(malformed_batches) - 1] =
    "v1|RECONCILIATION_BATCH|1|BOGUS_OPERATION|3008101|0.005";
  ArrayResize(malformed_batches, ArraySize(malformed_batches) + 1);
  malformed_batches[ArraySize(malformed_batches) - 1] =
    "v1|RECONCILIATION_BATCH|2|POSITION_METADATA|3008101|0.005|4008101|POSITION_CLOSED|3009999|READY";
  ArrayResize(malformed_batches, ArraySize(malformed_batches) + 1);
  malformed_batches[ArraySize(malformed_batches) - 1] =
    "v1|RECONCILIATION_BATCH|1|POSITION_METADATA|3008101|0.05|4008101";
  ArrayResize(malformed_batches, ArraySize(malformed_batches) + 1);
  malformed_batches[ArraySize(malformed_batches) - 1] =
    "v1|RECONCILIATION_BATCH|0";

  for(int batch_index = 0; batch_index < ArraySize(malformed_batches); batch_index++)
  {
    bool rejected_replay = true;
    double rejected_volume = 0.0;
    int rejected_position_count = 0;
    int rejected_level_one_state = -1;
    int rejected_level_two_state = -1;
    ReplayBatchOutcome(
      malformed_batches[batch_index],
      rejected_replay,
      rejected_volume,
      rejected_position_count,
      rejected_level_one_state,
      rejected_level_two_state);

    Tests.AssertFalse(
      StringFormat("batch %d is rejected", batch_index),
      rejected_replay);
    Tests.AssertEqualInt(
      StringFormat("batch %d removes no Mapping", batch_index),
      rejected_position_count,
      2);
    Tests.AssertEqualDouble(
      StringFormat("batch %d keeps every Volume", batch_index),
      rejected_volume,
      0.01);
    Tests.AssertEqualInt(
      StringFormat("batch %d keeps the metadata target ACTIVE", batch_index),
      rejected_level_one_state,
      (int)TGK_GRID_LEVEL_ACTIVE);
    Tests.AssertEqualInt(
      StringFormat("batch %d keeps the close target ACTIVE", batch_index),
      rejected_level_two_state,
      (int)TGK_GRID_LEVEL_ACTIVE);
  }
  Tests.EndTest();

  Tests.BeginTest("Rejected Reconciliation Batch enters RECOVERY_ERROR");
  STGKGridMappingJournalRecord rejected_records[];
  BuildBatchFixture(rejected_records);
  AddRecord(
    rejected_records,
    ArraySize(rejected_records) + 1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|RECONCILIATION_BATCH|2|POSITION_METADATA|3008101|0.005|4008101|POSITION_CLOSED|3009999|READY");

  CTGKGridEntryMappingReducer rejected_reducer;
  Tests.AssertTrue(
    "initialize rejected batch Reducer",
    rejected_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertFalse(
    "rejected batch fails the record",
    rejected_reducer.Replay(rejected_records, ArraySize(rejected_records)));
  Tests.AssertEqualInt(
    "rejected batch reports RECOVERY_ERROR",
    (int)rejected_reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);
  Tests.EndTest();

  Tests.BeginTest("Deal Association projection is read-only and match scoped");
  STGKGridMappingJournalRecord deal_records[];
  AddBaseConfiguration(deal_records);
  AddRecord(
    deal_records,
    ArraySize(deal_records) + 1,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    "v1|REQ-AD-1|XAUUSD|710001|BUY|LEVEL|1|0.10|1|UT-INSTANCE");
  AddRecord(
    deal_records,
    ArraySize(deal_records) + 1,
    TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
    "v1|REQ-AD-1|DONE_PARTIAL|9101|9201");
  AddRecord(
    deal_records,
    ArraySize(deal_records) + 1,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    "v1|REQ-AD-1|9201|3009201|0.04");
  AddRecord(
    deal_records,
    ArraySize(deal_records) + 1,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    "v1|REQ-AD-1|9202|3009201|0.06");

  CTGKGridEntryMappingReducer deal_reducer;
  Tests.AssertTrue(
    "initialize Deal projection Reducer",
    deal_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay Deal fixture",
    deal_reducer.Replay(deal_records, ArraySize(deal_records)));
  Tests.AssertTrue("Request stays unresolved", deal_reducer.HasUnresolvedRequest());
  Tests.AssertEqualInt("two Deal Associations retained", deal_reducer.DealCount(), 2);

  bool has_association = false;
  string association_request_id = "";
  double association_volume = 0.0;
  Tests.AssertTrue(
    "projection reads a matching Identifier",
    deal_reducer.TryGetDealAssociationProjection(
      "3009201",
      has_association,
      association_request_id,
      association_volume));
  Tests.AssertTrue("matching Identifier has evidence", has_association);
  Tests.AssertEqualString(
    "projected Request Identifier",
    association_request_id,
    "REQ-AD-1");
  Tests.AssertEqualDouble("associated Volume", association_volume, 0.10);

  Tests.AssertTrue(
    "projection reads an unrelated Identifier",
    deal_reducer.TryGetDealAssociationProjection(
      "3009999",
      has_association,
      association_request_id,
      association_volume));
  Tests.AssertFalse("unrelated Identifier has no evidence", has_association);
  Tests.AssertEqualString("no projected Request", association_request_id, "");
  Tests.AssertEqualDouble("no projected Volume", association_volume, 0.0);

  Tests.AssertFalse(
    "a non-canonical Identifier is refused",
    deal_reducer.TryGetDealAssociationProjection(
      "03009201",
      has_association,
      association_request_id,
      association_volume));
  Tests.AssertEqualInt(
    "the projection mutates no Deal state",
    deal_reducer.DealCount(),
    2);
  Tests.AssertTrue(
    "the Request stays unresolved after projection",
    deal_reducer.HasUnresolvedRequest());
  Tests.EndTest();

  Tests.BeginTest("CR-04 a rejected Batch rolls back every sub-event");
  STGKGridMappingJournalRecord rollback_records[];
  BuildBatchFixture(rollback_records);

  CTGKGridEntryMappingReducer rollback_reducer;
  Tests.AssertTrue(
    "initialize rollback Reducer",
    rollback_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay the batch fixture",
    rollback_reducer.Replay(rollback_records, ArraySize(rollback_records)));
  Tests.AssertEqualLong("fixture Sequence", rollback_reducer.LastSequence(), 10);

  // The first sub-event is legal and would change the Volume; the second is
  // rejected, so the whole Batch must be rolled back.
  Tests.AssertFalse(
    "a rejected Batch fails the record",
    rollback_reducer.ApplyCommittedRecord(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      "v1|RECONCILIATION_BATCH|2|POSITION_METADATA|3008101|0.005|4008101|POSITION_CLOSED|3009999|READY"));
  Tests.AssertEqualInt("no Mapping removed", rollback_reducer.PositionCount(), 2);
  Tests.AssertEqualDouble(
    "the legal sub-event is rolled back",
    rollback_reducer.PositionVolumeAt(0),
    0.01);
  Tests.AssertEqualString(
    "the Ticket is unchanged",
    rollback_reducer.PositionTicketAt(0),
    "4008101");
  Tests.AssertEqualInt(
    "the metadata target stays ACTIVE",
    rollback_reducer.LevelStateAt(1),
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.AssertEqualInt(
    "the close target stays ACTIVE",
    rollback_reducer.LevelStateAt(2),
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.AssertEqualLong(
    "the Sequence did not advance",
    rollback_reducer.LastSequence(),
    10);
  Tests.AssertEqualInt(
    "the Reducer stays healthy after a clean rollback",
    (int)rollback_reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_NORMAL);
  Tests.EndTest();

  Tests.BeginTest("CR-04 a failed rollback fails the Reducer closed");
  STGKGridMappingJournalRecord restore_records[];
  BuildBatchFixture(restore_records);

  CTGKGridEntryMappingReducer restore_reducer;
  Tests.AssertTrue(
    "initialize restore Reducer",
    restore_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "replay the batch fixture",
    restore_reducer.Replay(restore_records, ArraySize(restore_records)));
  Tests.AssertTrue(
    "inject the rollback failure",
    restore_reducer.SetRestoreFailureInjectionForTest(true));

  Tests.AssertFalse(
    "a Batch whose rollback fails is rejected",
    restore_reducer.ApplyCommittedRecord(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      "v1|RECONCILIATION_BATCH|2|POSITION_METADATA|3008101|0.005|4008101|POSITION_CLOSED|3009999|READY"));
  Tests.AssertEqualInt(
    "a failed rollback reports RECOVERY_ERROR",
    (int)restore_reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);
  Tests.AssertEqualLong(
    "the Sequence did not advance",
    restore_reducer.LastSequence(),
    10);

  // Every mutation and readiness path must refuse to serve the uncertain state.
  Tests.AssertFalse(
    "a later mutation is refused",
    restore_reducer.ApplyCommittedRecord(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      "v1|POSITION_METADATA|3008101|0.01|4008101"));
  bool restore_has_mapping = true;
  Tests.AssertFalse(
    "mapping readiness fails closed",
    restore_reducer.TryGetPositionMapping(false, 1, restore_has_mapping));
  Tests.AssertFalse("no Mapping is reported", restore_has_mapping);
  Tests.AssertFalse(
    "context validation fails closed",
    restore_reducer.MatchesContext(
      "UT-INSTANCE",
      "XAUUSD",
      710001,
      TGK_GRID_MODE_BUY,
      1));

  // The Journal remains the canonical recovery path.
  CTGKGridEntryMappingReducer restore_recovered;
  Tests.AssertTrue(
    "initialize the recovery Reducer",
    restore_recovered.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "the Journal rebuilds the committed state",
    restore_recovered.Replay(restore_records, ArraySize(restore_records)));
  Tests.AssertEqualInt(
    "recovery restores both Mappings",
    restore_recovered.PositionCount(),
    2);
  Tests.AssertEqualDouble(
    "recovery restores the committed Volume",
    restore_recovered.PositionVolumeAt(0),
    0.01);
  Tests.AssertEqualLong(
    "recovery restores the committed Sequence",
    restore_recovered.LastSequence(),
    10);
  Tests.EndTest();

  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick()
{
}
