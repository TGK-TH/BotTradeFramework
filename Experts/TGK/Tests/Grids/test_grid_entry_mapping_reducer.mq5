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

  Tests.BeginTest("Partial close retains Mapping; confirmed full close prunes Mapping but retains Level State");
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
    "Level State retained as WAIT_RETURN",
    closed_reducer.LevelStateAt(1),
    (int)TGK_GRID_LEVEL_WAIT_RETURN);

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

  Tests.BeginTest("Committed Reset exposes a READY Anchor State without changing Normal Level States");
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
    "Anchor State is READY after RESET_COMMITTED",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_READY);
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
      "repeated Anchor query returns READY",
      (int)anchor_state,
      (int)TGK_GRID_LEVEL_READY);
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

  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick()
{
}
