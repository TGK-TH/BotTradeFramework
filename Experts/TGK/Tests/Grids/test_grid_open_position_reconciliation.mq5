#property strict
#property version "1.00"
#property description "Grid Open Position Reconciliation tests; no trading."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridOpenPositionSnapshot.mqh>
#include <BotTrade/Grid/GridEntryMappingReducer.mqh>
#include <BotTrade/Grid/GridLevelRuntimeCoordinator.mqh>
#include <BotTrade/Grid/GridOpenPositionReconciliation.mqh>

CTGKTestRunner Tests;

#define G_SYMBOL "XAUUSD"
#define G_MAGIC 710502
#define G_MAGIC_LITERAL "710502"
#define G_INSTANCE "UT-INSTANCE"
#define G_EPOCH 1
#define G_EPOCH_LITERAL "1"
#define G_NORMAL_LEVEL_COUNT 8

// ---------------------------------------------------------------------------
// Fake ports
// ---------------------------------------------------------------------------

// Scripted two-scan Account port. It never touches the MT5 Position API.
class CFakeOpenPositionSource : public CTGKGridOpenPositionSource
{
public:
  STGKGridOpenPositionRecord first_scan[];
  STGKGridOpenPositionRecord second_scan[];
  bool fail_total;
  int total_call_count;
  int current_scan;
  int selected_index;

  CFakeOpenPositionSource()
  {
    Reset();
  }

  void Reset()
  {
    ArrayResize(first_scan, 0);
    ArrayResize(second_scan, 0);
    fail_total = false;
    total_call_count = 0;
    current_scan = 0;
    selected_index = -1;
  }

  void CopyScan(int scan, STGKGridOpenPositionRecord &records[])
  {
    int total = scan == 0 ? ArraySize(first_scan) : ArraySize(second_scan);
    ArrayResize(records, total);
    for(int index = 0; index < total; index++)
      records[index] = scan == 0 ? first_scan[index] : second_scan[index];
  }

  virtual bool TotalPositions(int &total)
  {
    total = -1;
    if(fail_total)
      return false;

    STGKGridOpenPositionRecord records[];
    CopyScan(current_scan, records);
    total = ArraySize(records);

    total_call_count++;
    current_scan = (total_call_count / 2) % 2;
    return true;
  }

  virtual bool TicketAt(int index, ulong &ticket)
  {
    ticket = 0;

    STGKGridOpenPositionRecord records[];
    CopyScan(current_scan, records);
    if(index < 0 || index >= ArraySize(records))
      return false;

    ticket = records[index].ticket;
    return true;
  }

  virtual bool SelectTicket(ulong ticket)
  {
    STGKGridOpenPositionRecord records[];
    CopyScan(current_scan, records);

    selected_index = -1;
    for(int index = 0; index < ArraySize(records); index++)
    {
      if(records[index].ticket == ticket)
      {
        selected_index = index;
        break;
      }
    }

    return selected_index >= 0;
  }

  virtual bool ReadSelectedPosition(STGKGridOpenPositionRecord &record)
  {
    record.position_identifier = "";
    record.ticket = 0;
    record.symbol = "";
    record.magic_number = 0;
    record.volume = 0.0;

    if(selected_index < 0)
      return false;

    STGKGridOpenPositionRecord records[];
    CopyScan(current_scan, records);
    record = records[selected_index];
    return true;
  }
};

// In-memory Mapping Journal. It can inject an append failure and keeps the
// sequence continuity the production adapter guarantees.
class CFakeJournalPort : public CTGKGridMappingJournalPort
{
public:
  STGKGridMappingJournalRecord records[];
  long next_sequence;
  bool fail_append;

  CFakeJournalPort()
  {
    Reset();
  }

  void Reset()
  {
    ArrayResize(records, 0);
    next_sequence = 1;
    fail_append = false;
  }

  virtual bool ReadNextSequence(long &value)
  {
    value = next_sequence;
    return true;
  }

  virtual bool AppendOne(
    ENUM_TGK_GRID_MAPPING_RECORD_TYPE record_type,
    string payload)
  {
    if(fail_append)
      return false;

    int index = ArraySize(records);
    if(ArrayResize(records, index + 1) != index + 1)
      return false;

    records[index].sequence = next_sequence;
    records[index].record_type = record_type;
    records[index].payload = payload;
    next_sequence++;
    return true;
  }
};

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

class CFixture
{
public:
  CTGKGridEntryMappingReducer reducer;
  CTGKGridLevelRuntimeCoordinator coordinator;
  CFakeJournalPort journal;
  CFakeOpenPositionSource source;
  CTGKGridOpenPositionAcquirer acquirer;
  CTGKGridOpenPositionReconciliation reconciliation;
  string mode;
  bool built;

  CFixture()
  {
    mode = "BUY";
    built = false;
  }
};

void PushRecord(
  STGKGridOpenPositionRecord &records[],
  string position_identifier,
  ulong ticket,
  string symbol,
  long magic_number,
  double volume)
{
  int index = ArraySize(records);
  ArrayResize(records, index + 1);
  records[index].position_identifier = position_identifier;
  records[index].ticket = ticket;
  records[index].symbol = symbol;
  records[index].magic_number = magic_number;
  records[index].volume = volume;
}

void CopyRecords(
  STGKGridOpenPositionRecord &source[],
  STGKGridOpenPositionRecord &destination[])
{
  int total = ArraySize(source);
  ArrayResize(destination, total);
  for(int index = 0; index < total; index++)
    destination[index] = source[index];
}

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

void AddMappedPosition(
  STGKGridMappingJournalRecord &records[],
  int &sequence,
  string request_id,
  string mode,
  int level_index,
  string position_identifier,
  string position_ticket,
  string deal_ticket,
  double volume)
{
  string volume_literal = DoubleToString(volume, 2);

  AddRecord(
    records,
    sequence++,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    StringFormat(
      "v1|%s|%s|%s|%s|LEVEL|%d|%s|%s|%s",
      request_id,
      G_SYMBOL,
      G_MAGIC_LITERAL,
      mode,
      level_index,
      volume_literal,
      G_EPOCH_LITERAL,
      G_INSTANCE));
  AddRecord(
    records,
    sequence++,
    TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
    StringFormat(
      "v1|%s|DONE|%s|%s",
      request_id,
      position_ticket,
      deal_ticket));
  AddRecord(
    records,
    sequence++,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    StringFormat(
      "v1|%s|%s|%s|%s",
      request_id,
      deal_ticket,
      position_identifier,
      volume_literal));
  AddRecord(
    records,
    sequence++,
    TGK_GRID_MAPPING_RECORD_POSITION_MAPPING,
    StringFormat(
      "v1|%s|%s|%s|LEVEL|%d|%s|%s|%s|%s|%s",
      request_id,
      G_SYMBOL,
      G_MAGIC_LITERAL,
      level_index,
      position_identifier,
      position_ticket,
      volume_literal,
      G_EPOCH_LITERAL,
      G_INSTANCE));
}

ulong ParseTicket(string value)
{
  int length = StringLen(value);
  if(length <= 0 || length > 10)
    return 0;

  ulong parsed = 0;
  for(int index = 0; index < length; index++)
  {
    ushort character = StringGetCharacter(value, index);
    if(character < '0' || character > '9')
      return 0;
    parsed = parsed * 10 + (ulong)(character - '0');
  }

  return parsed;
}

bool ProjectReducer(
  CTGKGridEntryMappingReducer &reducer,
  ENUM_TGK_GRID_LEVEL_STATE &anchor_state,
  STGKGridLevelStateHydration &level_states[],
  STGKGridLevelPositionRecord &positions[],
  STGKGridEntryRequestHydration &entry_request)
{
  ArrayResize(level_states, 0);
  ArrayResize(positions, 0);
  entry_request.present = false;
  entry_request.request_id = "";
  entry_request.is_anchor = false;
  entry_request.level_index = -1;
  entry_request.requested_volume = 0.0;

  if(!reducer.TryGetAnchorState(anchor_state))
    return false;

  for(int level_index = 0; level_index < G_NORMAL_LEVEL_COUNT; level_index++)
  {
    int state_value = reducer.LevelStateAt(level_index);
    if(state_value < 0)
      return false;

    int level_position = ArraySize(level_states);
    if(ArrayResize(level_states, level_position + 1) != level_position + 1)
      return false;

    level_states[level_position].level_index = level_index;
    level_states[level_position].state = (ENUM_TGK_GRID_LEVEL_STATE)state_value;
  }

  for(int index = 0; index < reducer.PositionCount(); index++)
  {
    STGKGridPositionMappingProjection projection;
    if(!reducer.TryGetPositionMappingAt(index, projection))
      return false;

    ulong ticket = ParseTicket(projection.position_ticket);
    if(ticket == 0)
      return false;

    int position_index = ArraySize(positions);
    if(ArrayResize(positions, position_index + 1) != position_index + 1)
      return false;

    positions[position_index].ticket = ticket;
    positions[position_index].symbol = projection.symbol;
    positions[position_index].magic_number = projection.magic_number;
    positions[position_index].is_anchor = projection.target_kind == "ANCHOR";
    positions[position_index].level_index = projection.level_index;
    positions[position_index].volume = projection.remaining_volume;
    positions[position_index].position_identifier = projection.position_identifier;
  }

  bool has_unresolved_request = false;
  STGKGridMappingRequestState request_state;
  if(!reducer.TryGetUnresolvedRequest(has_unresolved_request, request_state))
    return false;

  if(has_unresolved_request)
  {
    entry_request.present = true;
    entry_request.request_id = request_state.request_id;
    entry_request.is_anchor = request_state.target_kind == "ANCHOR";
    entry_request.level_index = request_state.level_index;
    entry_request.requested_volume = request_state.requested_volume;
  }

  return true;
}

bool HydrateCoordinator(
  CTGKGridLevelRuntimeCoordinator &coordinator,
  CTGKGridEntryMappingReducer &reducer,
  double current_bid,
  double current_ask)
{
  STGKGridPersistedConfigProjection config;
  if(!reducer.TryGetPersistedConfig(config))
    return false;

  ENUM_TGK_GRID_LEVEL_STATE anchor_state;
  STGKGridLevelStateHydration level_states[];
  STGKGridLevelPositionRecord positions[];
  STGKGridEntryRequestHydration entry_request;
  if(!ProjectReducer(
    reducer,
    anchor_state,
    level_states,
    positions,
    entry_request))
    return false;

  return coordinator.HydrateRuntimeState(
    config.mode,
    config.anchor_price,
    config.grid_step,
    config.lower_bound,
    config.upper_bound,
    config.persisted_level_count - 1,
    config.symbol,
    config.magic_number,
    config.config_epoch,
    config,
    current_bid,
    current_ask,
    anchor_state,
    level_states,
    positions,
    entry_request);
}

// Committed configuration with zero, one or two Position Mappings.
bool BuildCommittedRecords(
  STGKGridMappingJournalRecord &records[],
  string mode,
  int mapped_level_count)
{
  ArrayResize(records, 0);
  AddRecord(
    records,
    1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    StringFormat(
      "v1|RESET_COMMITTED|%s|%s|5.0|3980.0|4020.0|4000.0|9",
      G_EPOCH_LITERAL,
      mode));

  int sequence = 2;
  if(mapped_level_count >= 1)
    AddMappedPosition(
      records,
      sequence,
      "REQ-L0",
      mode,
      0,
      "3100001",
      "4100001",
      "2100001",
      0.10);
  if(mapped_level_count >= 2)
    AddMappedPosition(
      records,
      sequence,
      "REQ-L5",
      mode,
      5,
      "3100002",
      "4100002",
      "2100002",
      0.20);

  return true;
}

bool BuildFixture(
  CFixture &fixture,
  string mode,
  int mapped_level_count)
{
  fixture.built = false;
  fixture.mode = mode;

  STGKGridMappingJournalRecord records[];
  BuildCommittedRecords(records, mode, mapped_level_count);

  if(!fixture.reducer.Initialize(G_SYMBOL, G_MAGIC, G_INSTANCE))
    return false;
  if(!fixture.reducer.Replay(records, ArraySize(records)))
    return false;

  if(!HydrateCoordinator(
    fixture.coordinator,
    fixture.reducer,
    3999.0,
    4000.0))
    return false;

  fixture.journal.Reset();
  fixture.journal.next_sequence = fixture.reducer.LastSequence() + 1;
  fixture.source.Reset();

  ENUM_TGK_GRID_MODE grid_mode = mode == "BUY"
                                 ? TGK_GRID_MODE_BUY
                                 : TGK_GRID_MODE_SELL;

  if(!fixture.acquirer.Initialize(fixture.source, G_SYMBOL, G_MAGIC))
    return false;
  if(!fixture.reconciliation.Initialize(
    fixture.acquirer,
    fixture.journal,
    G_SYMBOL,
    G_MAGIC,
    G_INSTANCE,
    grid_mode,
    G_EPOCH))
    return false;

  fixture.built = true;
  return true;
}

// Unresolved Entry Request with durable Deal evidence and no Mapping.
bool BuildUnresolvedFixture(CFixture &fixture, string mode)
{
  fixture.built = false;
  fixture.mode = mode;

  STGKGridMappingJournalRecord records[];
  ArrayResize(records, 0);
  AddRecord(
    records,
    1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    StringFormat(
      "v1|RESET_COMMITTED|%s|%s|5.0|3980.0|4020.0|4000.0|9",
      G_EPOCH_LITERAL,
      mode));
  AddRecord(
    records,
    2,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    StringFormat(
      "v1|REQ-U1|%s|%s|BUY|LEVEL|2|0.10|%s|%s",
      G_SYMBOL,
      G_MAGIC_LITERAL,
      G_EPOCH_LITERAL,
      G_INSTANCE));
  AddRecord(
    records,
    3,
    TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
    "v1|REQ-U1|DONE|9000001|2100003");
  AddRecord(
    records,
    4,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    "v1|REQ-U1|2100003|3100003|0.10");

  if(!fixture.reducer.Initialize(G_SYMBOL, G_MAGIC, G_INSTANCE))
    return false;
  if(!fixture.reducer.Replay(records, ArraySize(records)))
    return false;

  if(!HydrateCoordinator(
    fixture.coordinator,
    fixture.reducer,
    3999.0,
    4000.0))
    return false;

  fixture.journal.Reset();
  fixture.journal.next_sequence = fixture.reducer.LastSequence() + 1;
  fixture.source.Reset();

  ENUM_TGK_GRID_MODE grid_mode = mode == "BUY"
                                 ? TGK_GRID_MODE_BUY
                                 : TGK_GRID_MODE_SELL;

  if(!fixture.acquirer.Initialize(fixture.source, G_SYMBOL, G_MAGIC))
    return false;
  if(!fixture.reconciliation.Initialize(
    fixture.acquirer,
    fixture.journal,
    G_SYMBOL,
    G_MAGIC,
    G_INSTANCE,
    grid_mode,
    G_EPOCH))
    return false;

  fixture.built = true;
  return true;
}

void SetLivePositions(
  CFixture &fixture,
  STGKGridOpenPositionRecord &records[])
{
  CopyRecords(records, fixture.source.first_scan);
  CopyRecords(records, fixture.source.second_scan);
}

void BuildBothMappings(STGKGridOpenPositionRecord &records[])
{
  ArrayResize(records, 0);
  PushRecord(records, "3100001", 4100001, G_SYMBOL, G_MAGIC, 0.10);
  PushRecord(records, "3100002", 4100002, G_SYMBOL, G_MAGIC, 0.20);
}

// A Ticket refresh on Level 5: the smallest Durable change that still drives
// the whole Append -> Apply -> Hydrate -> Release path.
bool BuildTicketRefreshFixture(CFixture &fixture)
{
  if(!BuildFixture(fixture, "BUY", 2))
    return false;

  STGKGridOpenPositionRecord live[];
  ArrayResize(live, 0);
  PushRecord(live, "3100001", 4100001, G_SYMBOL, G_MAGIC, 0.10);
  PushRecord(live, "3100002", 4100012, G_SYMBOL, G_MAGIC, 0.20);
  SetLivePositions(fixture, live);
  return true;
}

// Rebuilds the Reducer from the fixture's committed records plus every record
// its Journal accepted. Recovery must derive from the Journal only.
bool ReplayFixtureJournal(
  CFixture &fixture,
  CTGKGridEntryMappingReducer &recovered)
{
  STGKGridMappingJournalRecord recovery[];
  BuildCommittedRecords(recovery, fixture.mode, 2);

  for(int index = 0; index < ArraySize(fixture.journal.records); index++)
    AddRecord(
      recovery,
      fixture.journal.records[index].sequence,
      fixture.journal.records[index].record_type,
      fixture.journal.records[index].payload);

  if(!recovered.Initialize(G_SYMBOL, G_MAGIC, G_INSTANCE))
    return false;

  return recovered.Replay(recovery, ArraySize(recovery));
}

int RuntimeLevelState(
  CTGKGridLevelRuntimeCoordinator &coordinator,
  int level_index)
{
  ENUM_TGK_GRID_LEVEL_STATE state;
  if(!coordinator.GetLevelState(level_index, state))
    return -1;

  return (int)state;
}

int CountCloseEvents(string payload)
{
  int count = 0;
  int position = 0;
  while(true)
  {
    int found = StringFind(payload, "POSITION_CLOSED", position);
    if(found < 0)
      break;
    count++;
    position = found + 1;
  }
  return count;
}

int CountMetadataEvents(string payload)
{
  int count = 0;
  int position = 0;
  while(true)
  {
    int found = StringFind(payload, "POSITION_METADATA", position);
    if(found < 0)
      break;
    count++;
    position = found + 1;
  }
  return count;
}

int OnInit()
{
  Tests.BeginSuite("TGK Grid Open Position Reconciliation");

  // -------------------------------------------------------------------------
  Tests.BeginTest("C-05 matching Identifier confirms the Mapping without writes");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));
    Tests.AssertTrue("Runtime waits for Reconciliation", valid.coordinator.IsReconciliationPending());

    STGKGridOpenPositionRecord live[];
    BuildBothMappings(live);
    SetLivePositions(valid, live);

    long sequence_before = valid.reducer.LastSequence();
    Tests.AssertEqualInt(
      "unchanged Live set is a no-op",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_NO_CHANGE);
    Tests.AssertEqualInt("no Journal record written", ArraySize(valid.journal.records), 0);
    Tests.AssertEqualLong("Reducer Sequence unchanged", valid.reducer.LastSequence(), sequence_before);
    Tests.AssertFalse(
      "the validated no-op releases the Gate",
      valid.coordinator.IsReconciliationPending());
    Tests.AssertFalse(
      "the release offers no Anchor activation",
      valid.coordinator.HasPendingAnchorActivation());
    Tests.AssertEqualInt(
      "Runtime hydrated both Mappings",
      valid.coordinator.PositionCount(),
      2);

    STGKGridLevelPositionRecord hydrated;
    Tests.AssertTrue(
      "read the hydrated Anchor-side Mapping",
      valid.coordinator.TryGetPositionAt(0, hydrated));
    Tests.AssertEqualString(
      "hydrated Identifier",
      hydrated.position_identifier,
      "3100001");
    Tests.AssertEqualLong("hydrated Ticket", (long)hydrated.ticket, 4100001);
    Tests.AssertEqualDouble("hydrated Volume", hydrated.volume, 0.10);
    Tests.AssertEqualString("mapping Identifier kept", valid.reducer.PositionIdentifierAt(0), "3100001");
    Tests.AssertEqualString("mapping Ticket kept", valid.reducer.PositionTicketAt(1), "4100002");
    Tests.AssertEqualDouble("mapping Volume kept", valid.reducer.PositionVolumeAt(1), 0.20);
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("C-06 same Identifier with a new Ticket refreshes metadata only");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    STGKGridOpenPositionRecord live[];
    ArrayResize(live, 0);
    PushRecord(live, "3100001", 4100001, G_SYMBOL, G_MAGIC, 0.10);
    PushRecord(live, "3100002", 4100012, G_SYMBOL, G_MAGIC, 0.20);
    SetLivePositions(valid, live);

    Tests.AssertEqualInt(
      "Ticket refresh is applied",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_APPLIED);
    Tests.AssertEqualInt("one Journal record", ArraySize(valid.journal.records), 1);
    Tests.AssertEqualInt(
      "one metadata event",
      CountMetadataEvents(valid.journal.records[0].payload),
      1);
    Tests.AssertEqualInt("no close event", CountCloseEvents(valid.journal.records[0].payload), 0);
    Tests.AssertEqualInt("Mapping count unchanged", valid.reducer.PositionCount(), 2);
    Tests.AssertEqualString(
      "Identifier stays canonical",
      valid.reducer.PositionIdentifierAt(1),
      "3100002");
    Tests.AssertEqualString(
      "Ticket refreshed",
      valid.reducer.PositionTicketAt(1),
      "4100012");
    Tests.AssertFalse("Gate released after durable Apply", valid.coordinator.IsReconciliationPending());
    Tests.AssertEqualInt(
      "Level remains ACTIVE",
      valid.reducer.LevelStateAt(5),
      (int)TGK_GRID_LEVEL_ACTIVE);
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("C-07 lower Volume keeps the Mapping and ACTIVE state");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    STGKGridOpenPositionRecord live[];
    ArrayResize(live, 0);
    PushRecord(live, "3100001", 4100001, G_SYMBOL, G_MAGIC, 0.10);
    PushRecord(live, "3100002", 4100002, G_SYMBOL, G_MAGIC, 0.05);
    SetLivePositions(valid, live);

    Tests.AssertEqualInt(
      "partial close is applied",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_APPLIED);
    Tests.AssertEqualInt("one Journal record", ArraySize(valid.journal.records), 1);
    Tests.AssertEqualInt(
      "one metadata event",
      CountMetadataEvents(valid.journal.records[0].payload),
      1);
    Tests.AssertEqualInt("no close event", CountCloseEvents(valid.journal.records[0].payload), 0);
    Tests.AssertEqualInt("Mapping count unchanged", valid.reducer.PositionCount(), 2);
    Tests.AssertEqualDouble(
      "remaining Volume applied",
      valid.reducer.PositionVolumeAt(1),
      0.05);
    Tests.AssertEqualInt(
      "Level still ACTIVE",
      valid.reducer.LevelStateAt(5),
      (int)TGK_GRID_LEVEL_ACTIVE);
    Tests.AssertEqualInt(
      "Runtime Level still ACTIVE",
      RuntimeLevelState(valid.coordinator, 5),
      (int)TGK_GRID_LEVEL_ACTIVE);
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("C-08 identical Volume and Ticket is a no-op");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    STGKGridOpenPositionRecord live[];
    BuildBothMappings(live);
    SetLivePositions(valid, live);

    Tests.AssertEqualInt(
      "identical observation is a no-op",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_NO_CHANGE);
    Tests.AssertEqualInt("no Journal record", ArraySize(valid.journal.records), 0);
    Tests.AssertEqualLong("Sequence unchanged", valid.reducer.LastSequence(), 9);
    Tests.AssertFalse(
      "the validated no-op releases the Gate",
      valid.coordinator.IsReconciliationPending());
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("C-09 increased Volume fails closed without a write");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    STGKGridOpenPositionRecord live[];
    ArrayResize(live, 0);
    PushRecord(live, "3100001", 4100001, G_SYMBOL, G_MAGIC, 0.10);
    PushRecord(live, "3100002", 4100002, G_SYMBOL, G_MAGIC, 0.25);
    SetLivePositions(valid, live);

    Tests.AssertEqualInt(
      "Conflicting Evidence is rejected",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_CONFLICT);
    Tests.AssertEqualInt("no Journal record", ArraySize(valid.journal.records), 0);
    Tests.AssertEqualLong("Sequence unchanged", valid.reducer.LastSequence(), 9);
    Tests.AssertEqualDouble(
      "Volume unchanged",
      valid.reducer.PositionVolumeAt(1),
      0.20);
    Tests.AssertTrue("Gate stays closed", valid.coordinator.IsReconciliationPending());
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("C-10 missing Mapping is a reason-free Full Close using Ask");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    STGKGridOpenPositionRecord live[];
    ArrayResize(live, 0);
    PushRecord(live, "3100002", 4100002, G_SYMBOL, G_MAGIC, 0.20);
    SetLivePositions(valid, live);

    Tests.AssertEqualInt(
      "missing Mapping closes the position",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3997.0, 3998.0),
      (int)TGK_GRID_RECONCILIATION_APPLIED);
    Tests.AssertEqualInt("one Journal record", ArraySize(valid.journal.records), 1);
    Tests.AssertEqualInt(
      "one close event",
      CountCloseEvents(valid.journal.records[0].payload),
      1);
    Tests.AssertEqualInt("Mapping removed", valid.reducer.PositionCount(), 1);
    Tests.AssertEqualString(
      "surviving Mapping Identifier",
      valid.reducer.PositionIdentifierAt(0),
      "3100002");
    Tests.AssertEqualInt(
      "closed Level returns READY above the Level price",
      valid.reducer.LevelStateAt(0),
      (int)TGK_GRID_LEVEL_READY);
    Tests.AssertEqualInt(
      "Runtime Level matches the Reducer",
      RuntimeLevelState(valid.coordinator, 0),
      (int)TGK_GRID_LEVEL_READY);
    Tests.AssertFalse("Gate released", valid.coordinator.IsReconciliationPending());
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("C-10 post-close state uses the current executable-side quote");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    STGKGridOpenPositionRecord live[];
    ArrayResize(live, 0);
    PushRecord(live, "3100002", 4100002, G_SYMBOL, G_MAGIC, 0.20);
    SetLivePositions(valid, live);

    Tests.AssertEqualInt(
      "close below the Level price is applied",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3974.0, 3975.0),
      (int)TGK_GRID_RECONCILIATION_APPLIED);
    Tests.AssertEqualInt(
      "closed Level waits for activation",
      valid.reducer.LevelStateAt(0),
      (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
    Tests.AssertEqualInt(
      "Runtime Level waits for activation",
      RuntimeLevelState(valid.coordinator, 0),
      (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("C-10 multiple missing Mappings share one atomic Journal record");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    STGKGridOpenPositionRecord live[];
    ArrayResize(live, 0);
    SetLivePositions(valid, live);

    Tests.AssertEqualInt(
      "both missing Mappings close",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_APPLIED);
    Tests.AssertEqualInt("exactly one Journal record", ArraySize(valid.journal.records), 1);
    Tests.AssertEqualInt(
      "two close events in one record",
      CountCloseEvents(valid.journal.records[0].payload),
      2);
    Tests.AssertEqualInt("no Mapping left", valid.reducer.PositionCount(), 0);
    Tests.AssertEqualLong(
      "one Sequence step for the whole batch",
      valid.reducer.LastSequence(),
      10);
    Tests.AssertEqualInt("first Level READY", valid.reducer.LevelStateAt(0), (int)TGK_GRID_LEVEL_READY);
    // Level 5 sits at 4010, above the BUY-side Ask of 4000, so the WP-05A.2
    // post-close rule keeps it on the wrong side and waits for activation.
    Tests.AssertEqualInt(
      "second Level waits for activation",
      valid.reducer.LevelStateAt(5),
      (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("C-10 SELL direction uses Bid for the post-close state");
  {
    CFixture sell_ready;
    Tests.AssertTrue("build SELL fixture", BuildFixture(sell_ready, "SELL", 2));

    STGKGridOpenPositionRecord live[];
    ArrayResize(live, 0);
    PushRecord(live, "3100002", 4100002, G_SYMBOL, G_MAGIC, 0.20);
    SetLivePositions(sell_ready, live);

    Tests.AssertEqualInt(
      "SELL close below the Level price is applied",
      (int)sell_ready.reconciliation.Run(sell_ready.reducer, sell_ready.coordinator, 3975.0, 3976.0),
      (int)TGK_GRID_RECONCILIATION_APPLIED);
    Tests.AssertEqualInt(
      "SELL Level stays READY",
      sell_ready.reducer.LevelStateAt(0),
      (int)TGK_GRID_LEVEL_READY);

    CFixture sell_wait;
    Tests.AssertTrue("build SELL fixture", BuildFixture(sell_wait, "SELL", 2));
    ArrayResize(live, 0);
    PushRecord(live, "3100002", 4100002, G_SYMBOL, G_MAGIC, 0.20);
    SetLivePositions(sell_wait, live);

    Tests.AssertEqualInt(
      "SELL close above the Level price is applied",
      (int)sell_wait.reconciliation.Run(sell_wait.reducer, sell_wait.coordinator, 3985.0, 3986.0),
      (int)TGK_GRID_RECONCILIATION_APPLIED);
    Tests.AssertEqualInt(
      "SELL Level waits for activation",
      sell_wait.reducer.LevelStateAt(0),
      (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("C-11 a repeated Snapshot produces no duplicate close record");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    STGKGridOpenPositionRecord live[];
    ArrayResize(live, 0);
    PushRecord(live, "3100002", 4100002, G_SYMBOL, G_MAGIC, 0.20);
    SetLivePositions(valid, live);

    Tests.AssertEqualInt(
      "first observation closes",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_APPLIED);

    // A fresh acquisition over the same account state against the updated
    // Reducer is a no-op: the closed Mapping is gone and nothing replaces it.
    STGKGridOpenPositionSnapshot repeated;
    Tests.AssertTrue(
      "acquire a fresh token",
      valid.acquirer.Acquire(valid.reducer.LastSequence(), repeated));
    Tests.AssertTrue(
      "consume the fresh token",
      valid.acquirer.Consume(repeated, valid.reducer.LastSequence()));

    CTGKGridOpenPositionReconciler policy;
    Tests.AssertTrue(
      "initialize policy",
      policy.Initialize(G_SYMBOL, G_MAGIC, G_INSTANCE, TGK_GRID_MODE_BUY, G_EPOCH));

    string payload = "";
    int event_count = 0;
    Tests.AssertEqualInt(
      "repeated observation is a no-op",
      (int)policy.TryBuildBatch(
        GetPointer(valid.acquirer),
        valid.reducer,
        valid.coordinator,
        repeated,
        3999.0,
        4000.0,
        payload,
        event_count),
      (int)TGK_GRID_RECONCILIATION_NO_CHANGE);
    Tests.AssertEqualInt("no additional Journal record", ArraySize(valid.journal.records), 1);
    Tests.AssertEqualInt("Mapping count stable", valid.reducer.PositionCount(), 1);
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("C-12 unmapped Owned Position without evidence is an Orphan");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    STGKGridOpenPositionRecord live[];
    ArrayResize(live, 0);
    PushRecord(live, "3100001", 4100001, G_SYMBOL, G_MAGIC, 0.10);
    PushRecord(live, "3100002", 4100002, G_SYMBOL, G_MAGIC, 0.20);
    PushRecord(live, "3100009", 4100009, G_SYMBOL, G_MAGIC, 0.10);
    SetLivePositions(valid, live);

    Tests.AssertEqualInt(
      "Orphan fails closed",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_ORPHAN);
    Tests.AssertEqualInt("no Journal record", ArraySize(valid.journal.records), 0);
    Tests.AssertEqualInt("no Mapping adopted", valid.reducer.PositionCount(), 2);
    Tests.AssertEqualInt("no Level activated", valid.reducer.LevelStateAt(2), (int)TGK_GRID_LEVEL_READY);
    Tests.AssertTrue("Gate stays closed", valid.coordinator.IsReconciliationPending());
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("C-16 unresolved Request with Deal evidence stays unresolved");
  {
    CFixture unresolved;
    Tests.AssertTrue("build unresolved fixture", BuildUnresolvedFixture(unresolved, "BUY"));
    Tests.AssertTrue(
      "Runtime restored the unresolved Request",
      unresolved.coordinator.IsRequestUnresolved());
    Tests.AssertEqualString(
      "restored Request Identifier",
      unresolved.coordinator.PendingRequestId(),
      "REQ-U1");

    STGKGridOpenPositionRecord live[];
    ArrayResize(live, 0);
    PushRecord(live, "3100003", 4100003, G_SYMBOL, G_MAGIC, 0.10);
    SetLivePositions(unresolved, live);

    Tests.AssertEqualInt(
      "matching Deal evidence is not adopted",
      (int)unresolved.reconciliation.Run(
        unresolved.reducer,
        unresolved.coordinator,
        3999.0,
        4000.0),
      (int)TGK_GRID_RECONCILIATION_NO_CHANGE);
    Tests.AssertEqualInt("no Journal record", ArraySize(unresolved.journal.records), 0);
    Tests.AssertTrue(
      "Request stays unresolved",
      unresolved.reducer.HasUnresolvedRequest());
    Tests.AssertEqualString(
      "Request Identifier unchanged",
      unresolved.reducer.UnresolvedRequestId(),
      "REQ-U1");
    Tests.AssertEqualInt("no Mapping created", unresolved.reducer.PositionCount(), 0);
    Tests.AssertEqualInt(
      "Target Level not ACTIVE",
      unresolved.reducer.LevelStateAt(2),
      (int)TGK_GRID_LEVEL_READY);
    Tests.AssertFalse(
      "the validated no-op releases the Gate",
      unresolved.coordinator.IsReconciliationPending());
    Tests.AssertTrue(
      "the unresolved Request survives the release",
      unresolved.coordinator.IsRequestUnresolved());
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("C-12 Owned Position without a matching Deal Association is an Orphan");
  {
    CFixture unresolved;
    Tests.AssertTrue("build unresolved fixture", BuildUnresolvedFixture(unresolved, "BUY"));

    STGKGridOpenPositionRecord live[];
    ArrayResize(live, 0);
    PushRecord(live, "3100009", 4100009, G_SYMBOL, G_MAGIC, 0.10);
    SetLivePositions(unresolved, live);

    Tests.AssertEqualInt(
      "unproven Owned Position fails closed",
      (int)unresolved.reconciliation.Run(
        unresolved.reducer,
        unresolved.coordinator,
        3999.0,
        4000.0),
      (int)TGK_GRID_RECONCILIATION_ORPHAN);
    Tests.AssertEqualInt("no Journal record", ArraySize(unresolved.journal.records), 0);
    Tests.AssertEqualInt("no Mapping created", unresolved.reducer.PositionCount(), 0);
    Tests.AssertTrue(
      "Request stays unresolved",
      unresolved.reducer.HasUnresolvedRequest());
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("C-13 an unstable Snapshot cannot produce a Full Close");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    // The mapped Identifier is absent from a partial scan, but the second scan
    // disagrees, so neither observation is authoritative.
    STGKGridOpenPositionRecord live[];
    ArrayResize(live, 0);
    PushRecord(live, "3100002", 4100002, G_SYMBOL, G_MAGIC, 0.20);
    CopyRecords(live, valid.source.first_scan);

    STGKGridOpenPositionRecord second[];
    ArrayResize(second, 0);
    PushRecord(second, "3100002", 4100002, G_SYMBOL, G_MAGIC, 0.20);
    PushRecord(second, "3100001", 4100001, G_SYMBOL, G_MAGIC, 0.10);
    CopyRecords(second, valid.source.second_scan);

    Tests.AssertEqualInt(
      "unstable Snapshot is rejected",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_INVALID);
    Tests.AssertEqualInt("no Journal record", ArraySize(valid.journal.records), 0);
    Tests.AssertEqualInt("no Mapping removed", valid.reducer.PositionCount(), 2);
    Tests.AssertEqualInt("Level unchanged", valid.reducer.LevelStateAt(0), (int)TGK_GRID_LEVEL_ACTIVE);
    Tests.AssertTrue("Gate stays closed", valid.coordinator.IsReconciliationPending());
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("C-14 Journal append failure leaves Reducer and Gate untouched");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    STGKGridOpenPositionRecord live[];
    ArrayResize(live, 0);
    PushRecord(live, "3100002", 4100012, G_SYMBOL, G_MAGIC, 0.20);
    SetLivePositions(valid, live);

    valid.journal.fail_append = true;
    long sequence_before = valid.reducer.LastSequence();

    Tests.AssertEqualInt(
      "append failure is reported",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_STORAGE_FAILED);
    Tests.AssertEqualInt("no Journal record", ArraySize(valid.journal.records), 0);
    Tests.AssertEqualLong("Reducer Sequence unchanged", valid.reducer.LastSequence(), sequence_before);
    Tests.AssertEqualInt("metadata not applied", valid.reducer.PositionCount(), 2);
    Tests.AssertEqualString(
      "Ticket unchanged",
      valid.reducer.PositionTicketAt(1),
      "4100002");
    Tests.AssertEqualInt("close not applied", valid.reducer.LevelStateAt(0), (int)TGK_GRID_LEVEL_ACTIVE);
    Tests.AssertTrue("Gate stays closed", valid.coordinator.IsReconciliationPending());
    Tests.AssertFalse("no Recovery Required", valid.reconciliation.IsRecoveryRequired());
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("C-15 an older Snapshot cannot affect a newer Mapping");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    STGKGridOpenPositionRecord live[];
    ArrayResize(live, 0);
    PushRecord(live, "3100002", 4100002, G_SYMBOL, G_MAGIC, 0.20);
    SetLivePositions(valid, live);

    STGKGridOpenPositionSnapshot older;
    Tests.AssertTrue(
      "acquire the older token",
      valid.acquirer.Acquire(valid.reducer.LastSequence(), older));

    STGKGridOpenPositionSnapshot newer;
    Tests.AssertTrue(
      "acquire the newer token",
      valid.acquirer.Acquire(valid.reducer.LastSequence(), newer));
    Tests.AssertFalse(
      "the older generation is rejected",
      valid.acquirer.Consume(older, valid.reducer.LastSequence()));
    Tests.AssertTrue(
      "the newer generation is accepted",
      valid.acquirer.Consume(newer, valid.reducer.LastSequence()));

    Tests.AssertEqualInt(
      "newer observation closes the old Mapping",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_APPLIED);
    Tests.AssertEqualInt("one Mapping left", valid.reducer.PositionCount(), 1);

    // The stale envelope can never drive a second batch: its Base Sequence no
    // longer matches the advanced Reducer.
    STGKGridOpenPositionSnapshot stale;
    stale = older;
    stale.consumed = false;
    CTGKGridOpenPositionReconciler policy;
    Tests.AssertTrue(
      "initialize policy",
      policy.Initialize(G_SYMBOL, G_MAGIC, G_INSTANCE, TGK_GRID_MODE_BUY, G_EPOCH));

    string payload = "";
    int event_count = 0;
    Tests.AssertEqualInt(
      "stale Base Sequence is rejected",
      (int)policy.TryBuildBatch(
        GetPointer(valid.acquirer),
        valid.reducer,
        valid.coordinator,
        stale,
        3999.0,
        4000.0,
        payload,
        event_count),
      (int)TGK_GRID_RECONCILIATION_INVALID);
    Tests.AssertEqualInt("no extra Journal record", ArraySize(valid.journal.records), 1);
    Tests.AssertEqualInt("Mapping count stable", valid.reducer.PositionCount(), 1);
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("C-17 a Reducer advance after acquisition rejects the Snapshot");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    STGKGridOpenPositionRecord live[];
    BuildBothMappings(live);
    SetLivePositions(valid, live);

    STGKGridOpenPositionSnapshot pending;
    long base_sequence = valid.reducer.LastSequence();
    Tests.AssertTrue("acquire against the current Sequence", valid.acquirer.Acquire(base_sequence, pending));

    // A new Mapping transition commits before the Snapshot is consumed.
    Tests.AssertTrue(
      "advance the Reducer Sequence",
      valid.reducer.ApplyCommittedRecord(
        TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
        "v1|POSITION_METADATA|3100002|0.20|4100022"));
    Tests.AssertEqualLong(
      "Sequence advanced",
      valid.reducer.LastSequence(),
      base_sequence + 1);
    Tests.AssertFalse(
      "the stale Snapshot cannot be consumed",
      valid.acquirer.Consume(pending, valid.reducer.LastSequence()));

    Tests.AssertEqualInt(
      "no Durable write from the stale observation",
      ArraySize(valid.journal.records),
      0);
    Tests.AssertEqualInt("Mapping count unchanged", valid.reducer.PositionCount(), 2);
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("Foreign Symbol and Magic are never reconciled");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    STGKGridOpenPositionRecord live[];
    BuildBothMappings(live);
    PushRecord(live, "3200001", 4200001, "EURUSD", G_MAGIC, 0.10);
    PushRecord(live, "3200002", 4200002, G_SYMBOL, 710999, 0.10);
    PushRecord(live, "3200003", 4200003, G_SYMBOL, 0, 0.10);
    SetLivePositions(valid, live);

    Tests.AssertEqualInt(
      "foreign positions are ignored",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_NO_CHANGE);
    Tests.AssertEqualInt("no Journal record", ArraySize(valid.journal.records), 0);
    Tests.AssertEqualInt("mapping count unchanged", valid.reducer.PositionCount(), 2);
    Tests.AssertFalse(
      "the validated no-op releases the Gate",
      valid.coordinator.IsReconciliationPending());
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("Reconciliation is refused once the Gate was released");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    STGKGridOpenPositionRecord live[];
    ArrayResize(live, 0);
    PushRecord(live, "3100001", 4100001, G_SYMBOL, G_MAGIC, 0.10);
    PushRecord(live, "3100002", 4100012, G_SYMBOL, G_MAGIC, 0.20);
    SetLivePositions(valid, live);

    Tests.AssertEqualInt(
      "first observation releases the Gate",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_APPLIED);
    Tests.AssertFalse(
      "Gate is released",
      valid.coordinator.IsReconciliationPending());

    long sequence_after_release = valid.reducer.LastSequence();
    Tests.AssertEqualInt(
      "a released Runtime refuses a second Reconciliation",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_INVALID);
    Tests.AssertEqualInt("no extra Journal record", ArraySize(valid.journal.records), 1);
    Tests.AssertEqualLong(
      "Reducer Sequence stable",
      valid.reducer.LastSequence(),
      sequence_after_release);
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("CR-02 an empty Snapshot and empty Mapping release the Gate");
  {
    CFixture empty;
    Tests.AssertTrue("build fixture", BuildFixture(empty, "BUY", 0));

    STGKGridOpenPositionRecord no_live[];
    ArrayResize(no_live, 0);
    SetLivePositions(empty, no_live);

    long sequence_before = empty.reducer.LastSequence();
    Tests.AssertEqualInt(
      "an empty account against an empty Mapping is a no-op",
      (int)empty.reconciliation.Run(empty.reducer, empty.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_NO_CHANGE);
    Tests.AssertEqualInt("no Journal record", ArraySize(empty.journal.records), 0);
    Tests.AssertEqualLong(
      "Reducer Sequence unchanged",
      empty.reducer.LastSequence(),
      sequence_before);
    Tests.AssertFalse(
      "the validated empty no-op releases the Gate",
      empty.coordinator.IsReconciliationPending());
    Tests.AssertEqualInt("no hydrated Mapping", empty.coordinator.PositionCount(), 0);
    Tests.AssertFalse(
      "Recovery is not required",
      empty.reconciliation.IsRecoveryRequired());
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("CR-05 a forged Snapshot never reaches the Diff");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    STGKGridOpenPositionRecord live[];
    BuildBothMappings(live);
    SetLivePositions(valid, live);

    STGKGridOpenPositionSnapshot forged;
    forged.status = TGK_GRID_OPEN_POSITION_COMPLETE;
    forged.symbol = G_SYMBOL;
    forged.magic_number = G_MAGIC;
    forged.first_scan_total = 2;
    forged.second_scan_total = 2;
    forged.generation = 1;
    forged.base_sequence = valid.reducer.LastSequence();
    // The caller-writable flag claims a consumed token. It must not be trusted.
    forged.consumed = true;

    CTGKGridOpenPositionReconciler policy;
    Tests.AssertTrue(
      "initialize policy",
      policy.Initialize(G_SYMBOL, G_MAGIC, G_INSTANCE, TGK_GRID_MODE_BUY, G_EPOCH));

    string payload = "";
    int event_count = 0;
    Tests.AssertEqualInt(
      "a forged Snapshot is refused",
      (int)policy.TryBuildBatch(
        GetPointer(valid.acquirer),
        valid.reducer,
        valid.coordinator,
        forged,
        3999.0,
        4000.0,
        payload,
        event_count),
      (int)TGK_GRID_RECONCILIATION_INVALID);
    Tests.AssertEqualInt("no Journal record", ArraySize(valid.journal.records), 0);
    Tests.AssertEqualLong("Reducer Sequence unchanged", valid.reducer.LastSequence(), 9);
    Tests.AssertEqualInt("no Mapping changed", valid.reducer.PositionCount(), 2);
    Tests.AssertTrue("Gate stays closed", valid.coordinator.IsReconciliationPending());
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("CR-05 an unconsumed Snapshot is refused");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    STGKGridOpenPositionRecord live[];
    BuildBothMappings(live);
    SetLivePositions(valid, live);

    STGKGridOpenPositionSnapshot pending;
    Tests.AssertTrue(
      "acquire without consuming",
      valid.acquirer.Acquire(valid.reducer.LastSequence(), pending));

    CTGKGridOpenPositionReconciler policy;
    Tests.AssertTrue(
      "initialize policy",
      policy.Initialize(G_SYMBOL, G_MAGIC, G_INSTANCE, TGK_GRID_MODE_BUY, G_EPOCH));

    string payload = "";
    int event_count = 0;
    Tests.AssertEqualInt(
      "an unconsumed Snapshot is refused",
      (int)policy.TryBuildBatch(
        GetPointer(valid.acquirer),
        valid.reducer,
        valid.coordinator,
        pending,
        3999.0,
        4000.0,
        payload,
        event_count),
      (int)TGK_GRID_RECONCILIATION_INVALID);
    Tests.AssertEqualInt("no Journal record", ArraySize(valid.journal.records), 0);
    Tests.AssertEqualLong("Reducer Sequence unchanged", valid.reducer.LastSequence(), 9);
    Tests.AssertTrue("Gate stays closed", valid.coordinator.IsReconciliationPending());
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("CR-05 a consumed Snapshot cannot be replayed");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    STGKGridOpenPositionRecord live[];
    BuildBothMappings(live);
    SetLivePositions(valid, live);

    STGKGridOpenPositionSnapshot token;
    Tests.AssertTrue(
      "acquire the token",
      valid.acquirer.Acquire(valid.reducer.LastSequence(), token));

    Tests.AssertTrue(
      "consume the token",
      valid.acquirer.Consume(token, valid.reducer.LastSequence()));

    CTGKGridOpenPositionReconciler policy;
    Tests.AssertTrue(
      "initialize policy",
      policy.Initialize(G_SYMBOL, G_MAGIC, G_INSTANCE, TGK_GRID_MODE_BUY, G_EPOCH));

    string payload = "";
    int event_count = 0;
    Tests.AssertEqualInt(
      "the first Diff attempt is allowed",
      (int)policy.TryBuildBatch(
        GetPointer(valid.acquirer),
        valid.reducer,
        valid.coordinator,
        token,
        3999.0,
        4000.0,
        payload,
        event_count),
      (int)TGK_GRID_RECONCILIATION_NO_CHANGE);
    Tests.AssertEqualInt(
      "a replayed Snapshot is refused",
      (int)policy.TryBuildBatch(
        GetPointer(valid.acquirer),
        valid.reducer,
        valid.coordinator,
        token,
        3999.0,
        4000.0,
        payload,
        event_count),
      (int)TGK_GRID_RECONCILIATION_INVALID);
    Tests.AssertEqualInt("no Journal record", ArraySize(valid.journal.records), 0);
    Tests.AssertEqualLong("Reducer Sequence unchanged", valid.reducer.LastSequence(), 9);
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("CR-05 a superseded generation is refused");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    STGKGridOpenPositionRecord live[];
    BuildBothMappings(live);
    SetLivePositions(valid, live);

    STGKGridOpenPositionSnapshot older;
    Tests.AssertTrue(
      "acquire the older token",
      valid.acquirer.Acquire(valid.reducer.LastSequence(), older));

    STGKGridOpenPositionSnapshot newer;
    Tests.AssertTrue(
      "acquire the newer token",
      valid.acquirer.Acquire(valid.reducer.LastSequence(), newer));
    Tests.AssertTrue(
      "consume the newer token",
      valid.acquirer.Consume(newer, valid.reducer.LastSequence()));

    CTGKGridOpenPositionReconciler policy;
    Tests.AssertTrue(
      "initialize policy",
      policy.Initialize(G_SYMBOL, G_MAGIC, G_INSTANCE, TGK_GRID_MODE_BUY, G_EPOCH));

    string payload = "";
    int event_count = 0;
    Tests.AssertEqualInt(
      "a superseded generation is refused",
      (int)policy.TryBuildBatch(
        GetPointer(valid.acquirer),
        valid.reducer,
        valid.coordinator,
        older,
        3999.0,
        4000.0,
        payload,
        event_count),
      (int)TGK_GRID_RECONCILIATION_INVALID);
    Tests.AssertEqualInt("no Journal record", ArraySize(valid.journal.records), 0);
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("CR-05 a Base Sequence mismatch is refused");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildFixture(valid, "BUY", 2));

    STGKGridOpenPositionRecord live[];
    BuildBothMappings(live);
    SetLivePositions(valid, live);

    STGKGridOpenPositionSnapshot token;
    Tests.AssertTrue(
      "acquire the token",
      valid.acquirer.Acquire(valid.reducer.LastSequence(), token));

    Tests.AssertTrue(
      "consume the token",
      valid.acquirer.Consume(token, valid.reducer.LastSequence()));

    Tests.AssertTrue(
      "advance the Reducer after the Consume",
      valid.reducer.ApplyCommittedRecord(
        TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
        "v1|POSITION_METADATA|3100002|0.20|4100022"));
    Tests.AssertEqualLong("Sequence advanced", valid.reducer.LastSequence(), 10);

    CTGKGridOpenPositionReconciler policy;
    Tests.AssertTrue(
      "initialize policy",
      policy.Initialize(G_SYMBOL, G_MAGIC, G_INSTANCE, TGK_GRID_MODE_BUY, G_EPOCH));

    string payload = "";
    int event_count = 0;
    Tests.AssertEqualInt(
      "the stale Base Sequence is refused",
      (int)policy.TryBuildBatch(
        GetPointer(valid.acquirer),
        valid.reducer,
        valid.coordinator,
        token,
        3999.0,
        4000.0,
        payload,
        event_count),
      (int)TGK_GRID_RECONCILIATION_INVALID);
    Tests.AssertEqualInt("no Journal record", ArraySize(valid.journal.records), 0);
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("CR-08 Diff cannot receive a caller-supplied Position Set");
  {
    CFixture first_snapshot_fixture;
    Tests.AssertTrue("build fixture", BuildFixture(first_snapshot_fixture, "BUY", 2));

    STGKGridOpenPositionRecord actual_positions[];
    BuildBothMappings(actual_positions);
    SetLivePositions(first_snapshot_fixture, actual_positions);

    STGKGridOpenPositionSnapshot empty_token;
    Tests.AssertTrue(
      "acquire trusted Positions",
      first_snapshot_fixture.acquirer.Acquire(first_snapshot_fixture.reducer.LastSequence(), empty_token));
    Tests.AssertTrue(
      "consume trusted Snapshot",
      first_snapshot_fixture.acquirer.Consume(empty_token, first_snapshot_fixture.reducer.LastSequence()));

    CTGKGridOpenPositionReconciler empty_policy;
    Tests.AssertTrue(
      "initialize policy",
      empty_policy.Initialize(G_SYMBOL, G_MAGIC, G_INSTANCE, TGK_GRID_MODE_BUY, G_EPOCH));

    string empty_payload = "";
    int empty_event_count = 0;
    Tests.AssertEqualInt(
      "the Acquirer-owned two-Position Set yields NO_CHANGE",
      (int)empty_policy.TryBuildBatch(
        GetPointer(first_snapshot_fixture.acquirer),
        first_snapshot_fixture.reducer,
        first_snapshot_fixture.coordinator,
        empty_token,
        3999.0,
        4000.0,
        empty_payload,
        empty_event_count),
      (int)TGK_GRID_RECONCILIATION_NO_CHANGE);
    Tests.AssertEqualInt("no false Full Close Journal record", ArraySize(first_snapshot_fixture.journal.records), 0);
    Tests.AssertEqualLong("Reducer Sequence unchanged", first_snapshot_fixture.reducer.LastSequence(), 9);
    Tests.AssertEqualInt("both Mappings remain", first_snapshot_fixture.reducer.PositionCount(), 2);
    Tests.AssertEqualInt("no Diff events", empty_event_count, 0);
    Tests.AssertEqualString("no Diff payload", empty_payload, "");

  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("CR-06 a Projection failure after the durable commit requires recovery");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildTicketRefreshFixture(valid));
    Tests.AssertTrue(
      "inject the Projection failure",
      valid.reconciliation.SetProjectionFailureInjectionForTest(true));

    Tests.AssertEqualInt(
      "the Projection failure is reported",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_HYDRATION_FAILED);
    Tests.AssertTrue(
      "Recovery is required",
      valid.reconciliation.IsRecoveryRequired());
    Tests.AssertEqualInt(
      "the batch was durably appended",
      ArraySize(valid.journal.records),
      1);
    Tests.AssertEqualLong(
      "the Durable commit advanced the Sequence",
      valid.reducer.LastSequence(),
      10);
    Tests.AssertEqualString(
      "the Durable commit is applied",
      valid.reducer.PositionTicketAt(1),
      "4100012");
    Tests.AssertTrue("Gate stays closed", valid.coordinator.IsReconciliationPending());
    Tests.AssertEqualInt(
      "a later Run is refused",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_RECOVERY_REQUIRED);
    Tests.AssertEqualInt(
      "no second Journal record",
      ArraySize(valid.journal.records),
      1);
    Tests.AssertEqualLong(
      "no Sequence corruption",
      valid.reducer.LastSequence(),
      10);

    CTGKGridEntryMappingReducer recovered;
    Tests.AssertTrue("replay the Journal", ReplayFixtureJournal(valid, recovered));
    Tests.AssertEqualString(
      "recovery restores the committed Ticket",
      recovered.PositionTicketAt(1),
      "4100012");
    Tests.AssertEqualLong(
      "recovery restores the committed Sequence",
      recovered.LastSequence(),
      10);
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("CR-06 a Hydration failure after the durable commit requires recovery");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildTicketRefreshFixture(valid));
    Tests.AssertTrue(
      "inject the Hydration failure",
      valid.reconciliation.SetHydrationFailureInjectionForTest(true));

    Tests.AssertEqualInt(
      "the Hydration failure is reported",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_HYDRATION_FAILED);
    Tests.AssertTrue(
      "Recovery is required",
      valid.reconciliation.IsRecoveryRequired());
    Tests.AssertEqualInt(
      "the batch was durably appended",
      ArraySize(valid.journal.records),
      1);
    Tests.AssertEqualLong(
      "the Durable commit advanced the Sequence",
      valid.reducer.LastSequence(),
      10);
    Tests.AssertTrue("Gate stays closed", valid.coordinator.IsReconciliationPending());
    Tests.AssertEqualInt(
      "a later Run is refused",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_RECOVERY_REQUIRED);
    Tests.AssertEqualInt(
      "no second Journal record",
      ArraySize(valid.journal.records),
      1);

    CTGKGridEntryMappingReducer recovered;
    Tests.AssertTrue("replay the Journal", ReplayFixtureJournal(valid, recovered));
    Tests.AssertEqualLong(
      "recovery restores the committed Sequence",
      recovered.LastSequence(),
      10);
  }
  Tests.EndTest();

  // -------------------------------------------------------------------------
  Tests.BeginTest("CR-06 a Gate release failure after the durable commit requires recovery");
  {
    CFixture valid;
    Tests.AssertTrue("build fixture", BuildTicketRefreshFixture(valid));
    Tests.AssertTrue(
      "inject the Gate release failure",
      valid.reconciliation.SetGateFailureInjectionForTest(true));

    Tests.AssertEqualInt(
      "the Gate failure is reported",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_GATE_FAILED);
    Tests.AssertTrue(
      "Recovery is required",
      valid.reconciliation.IsRecoveryRequired());
    Tests.AssertEqualInt(
      "the batch was durably appended",
      ArraySize(valid.journal.records),
      1);
    Tests.AssertEqualLong(
      "the Durable commit advanced the Sequence",
      valid.reducer.LastSequence(),
      10);
    Tests.AssertTrue("Gate stays closed", valid.coordinator.IsReconciliationPending());
    Tests.AssertEqualInt(
      "a later Run is refused",
      (int)valid.reconciliation.Run(valid.reducer, valid.coordinator, 3999.0, 4000.0),
      (int)TGK_GRID_RECONCILIATION_RECOVERY_REQUIRED);
    Tests.AssertEqualInt(
      "no second Journal record",
      ArraySize(valid.journal.records),
      1);

    CTGKGridEntryMappingReducer recovered;
    Tests.AssertTrue("replay the Journal", ReplayFixtureJournal(valid, recovered));
    Tests.AssertEqualString(
      "recovery restores the committed Ticket",
      recovered.PositionTicketAt(1),
      "4100012");
  }
  Tests.EndTest();

  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick()
{
}
