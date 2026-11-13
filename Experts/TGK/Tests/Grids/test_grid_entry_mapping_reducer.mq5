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
    "v1|RESET_COMMITTED|1|BUY|1.0|3900.0|4100.0|4000.0|10");
  AddRecord(
    records,
    2,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|LEVEL_STATE|1|1|READY");
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
  Tests.AssertEqualInt("two Deals associated", reducer.DealCount(), 2);
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
    "v1|RESET_COMMITTED|2|SELL|2.0|3800.0|4200.0|4000.0|10");
  CTGKGridEntryMappingReducer reset_after_close_reducer;
  Tests.AssertTrue(
    "initialize completed-reset reducer",
    reset_after_close_reducer.Initialize("XAUUSD", 710001, "UT-INSTANCE"));
  Tests.AssertTrue(
    "completed Reset prunes old Level State",
    reset_after_close_reducer.Replay(records, ArraySize(records)));
  Tests.AssertEqualInt(
    "old Level State removed after confirmed Reset",
    reset_after_close_reducer.LevelStateAt(1),
    -1);
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
    "v1|RESET_COMMITTED|2|SELL|2.0|3800.0|4200.0|4000.0|10");

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

  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick()
{
}
