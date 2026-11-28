#property strict
#property version "1.00"
#property description "Grid Runtime State Restoration tests; no trading."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridEntryMappingSnapshotStorage.mqh>
#include <BotTrade/Grid/GridLevelRuntimeCoordinator.mqh>

CTGKTestRunner Tests;

// Fixture configuration: a BUY Grid with 4 lower Levels (3980, 3985, 3990,
// 3995), 4 upper Levels (4005, 4010, 4015, 4020) and the Anchor at 4000.
// The persisted Level count includes the Anchor, while the Engine Level count
// excludes it.
string g_symbol;
string g_instance_id;
long g_magic_number = 710001;
long g_config_epoch = 1;
double g_anchor_price = 4000.0;
double g_grid_step = 5.0;
double g_lower_bound = 3980.0;
double g_upper_bound = 4020.0;
int g_normal_level_count = 8;
// Canonical committed configuration of the fixture dataset, captured once from
// a valid Replay and passed to every Hydration as the persisted authority.
STGKGridPersistedConfigProjection g_persisted_config;

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

// Committed configuration plus the mandatory Level State record. Every normal
// Level starts READY and the Anchor starts READY.
void AddBaseConfiguration(STGKGridMappingJournalRecord &records[])
{
  AddRecord(
    records,
    1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|RESET_COMMITTED|1|BUY|5.0|3980.0|4020.0|4000.0|9");
  AddRecord(
    records,
    2,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|LEVEL_STATE|1|1|READY");
}

void AddMappedPosition(
  STGKGridMappingJournalRecord &records[],
  int &sequence,
  string instance_id,
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
      "v1|%s|%s|%I64d|BUY|%s|%d|0.01|1|%s",
      request_id,
      g_symbol,
      g_magic_number,
      target_kind,
      level_index,
      instance_id));
  AddRecord(
    records,
    sequence++,
    TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
    StringFormat("v1|%s|DONE|%s|0", request_id, order_ticket));
  AddRecord(
    records,
    sequence++,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    StringFormat("v1|%s|%s|%s|0.01", request_id, deal_ticket, position_identifier));
  AddRecord(
    records,
    sequence++,
    TGK_GRID_MAPPING_RECORD_POSITION_MAPPING,
    StringFormat(
      "v1|%s|%s|%I64d|%s|%d|%s|%s|0.01|1|%s",
      request_id,
      g_symbol,
      g_magic_number,
      target_kind,
      level_index,
      position_identifier,
      position_ticket,
      instance_id));
}

// An accepted Entry Request that has not produced a Mapping yet.
void AddUnresolvedRequest(
  STGKGridMappingJournalRecord &records[],
  int &sequence,
  string instance_id,
  string request_id,
  string target_kind,
  int level_index,
  double volume)
{
  AddRecord(
    records,
    sequence++,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    StringFormat(
      "v1|%s|%s|%I64d|BUY|%s|%d|%s|1|%s",
      request_id,
      g_symbol,
      g_magic_number,
      target_kind,
      level_index,
      DoubleToString(volume, 2),
      instance_id));
}

bool ReplayFixture(
  STGKGridMappingJournalRecord &records[],
  string instance_id,
  CTGKGridEntryMappingReducer &reducer)
{
  if(!reducer.Initialize(g_symbol, g_magic_number, instance_id))
    return false;

  return reducer.Replay(records, ArraySize(records));
}

void ClearEntryRequest(STGKGridEntryRequestHydration &entry_request)
{
  entry_request.present = false;
  entry_request.request_id = "";
  entry_request.is_anchor = false;
  entry_request.level_index = -1;
  entry_request.requested_volume = 0.0;
}

ulong ParseTicket(string value)
{
  int length = StringLen(value);
  if(length <= 0 || length > 20)
    return 0;

  ulong parsed = 0;
  for(int index = 0; index < length; index++)
  {
    ushort character = StringGetCharacter(value, index);
    if(character < '0' || character > '9')
      return 0;

    ulong digit = (ulong)(character - '0');
    if(parsed > 1844674407370955161)
      return 0;
    if(parsed == 1844674407370955161 && digit > 5)
      return 0;

    parsed = parsed * 10 + digit;
  }

  return parsed;
}

// Read-only projection of the canonical Reducer into the Runtime Hydration
// inputs. This is the Startup Restore sequence up to the Hydration call.
bool ProjectRestoreState(
  CTGKGridEntryMappingReducer &reducer,
  STGKGridLevelStateHydration &level_states[],
  STGKGridLevelPositionRecord &positions[],
  STGKGridEntryRequestHydration &entry_request)
{
  ArrayResize(level_states, 0);
  ArrayResize(positions, 0);
  ClearEntryRequest(entry_request);

  if(reducer.LevelCount() != g_normal_level_count)
    return false;

  for(int level_index = 0; level_index < g_normal_level_count; level_index++)
  {
    int state_value = reducer.LevelStateAt(level_index);
    if(state_value < (int)TGK_GRID_LEVEL_READY ||
       state_value > (int)TGK_GRID_LEVEL_WAIT_ACTIVATION)
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

// One explicit Hydration request. A mismatch case varies exactly one field while
// every other input stays canonical.
bool HydrateRequest(
  CTGKGridLevelRuntimeCoordinator &coordinator,
  STGKGridPersistedConfigProjection &persisted_config,
  ENUM_TGK_GRID_MODE mode,
  double anchor_price,
  double grid_step,
  double lower_bound,
  double upper_bound,
  int normal_level_count,
  string symbol,
  long magic_number,
  long config_epoch,
  ENUM_TGK_GRID_LEVEL_STATE anchor_state,
  STGKGridLevelStateHydration &level_states[],
  STGKGridLevelPositionRecord &positions[],
  STGKGridEntryRequestHydration &entry_request)
{
  return coordinator.HydrateRuntimeState(
    mode,
    anchor_price,
    grid_step,
    lower_bound,
    upper_bound,
    normal_level_count,
    symbol,
    magic_number,
    config_epoch,
    persisted_config,
    3999.0,
    4000.0,
    anchor_state,
    level_states,
    positions,
    entry_request);
}

// Hydration request that matches the committed fixture configuration.
bool HydrateFixture(
  CTGKGridLevelRuntimeCoordinator &coordinator,
  ENUM_TGK_GRID_LEVEL_STATE anchor_state,
  STGKGridLevelStateHydration &level_states[],
  STGKGridLevelPositionRecord &positions[],
  STGKGridEntryRequestHydration &entry_request)
{
  return HydrateRequest(
    coordinator,
    g_persisted_config,
    TGK_GRID_MODE_BUY,
    g_anchor_price,
    g_grid_step,
    g_lower_bound,
    g_upper_bound,
    g_normal_level_count,
    g_symbol,
    g_magic_number,
    g_config_epoch,
    anchor_state,
    level_states,
    positions,
    entry_request);
}

// A rejected Hydration must leave no usable Runtime state and no released Gate.
void AssertRejectedHydration(
  string label,
  bool hydrated,
  CTGKGridLevelRuntimeCoordinator &coordinator)
{
  ENUM_TGK_GRID_LEVEL_STATE level_state;

  Tests.AssertFalse(
    label + " rejects Hydration",
    hydrated);
  Tests.AssertEqualInt(
    label + " reports RESTORE_ERROR",
    (int)coordinator.RestoreStatus(),
    (int)TGK_GRID_RUNTIME_RESTORE_ERROR);
  Tests.AssertEqualInt(
    label + " releases no Position state",
    coordinator.PositionCount(),
    0);
  Tests.AssertFalse(
    label + " exposes no Level state",
    coordinator.GetLevelState(0, level_state));
  Tests.AssertFalse(
    label + " leaves the Reconciliation Gate closed",
    coordinator.IsReconciliationPending());
  Tests.AssertEqualString(
    label + " exposes no Instance identity",
    coordinator.PersistedInstanceId(),
    "");
}

// Full Storage/Reducer/Runtime Restore path for one already-replayed Reducer.
bool RestoreIntoRuntime(
  CTGKGridEntryMappingReducer &reducer,
  CTGKGridLevelRuntimeCoordinator &coordinator)
{
  ENUM_TGK_GRID_LEVEL_STATE anchor_state;
  if(!reducer.TryGetAnchorState(anchor_state))
    return false;

  STGKGridLevelStateHydration level_states[];
  STGKGridLevelPositionRecord positions[];
  STGKGridEntryRequestHydration entry_request;
  if(!ProjectRestoreState(reducer, level_states, positions, entry_request))
    return false;

  return HydrateFixture(
    coordinator,
    anchor_state,
    level_states,
    positions,
    entry_request);
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

int CountRuntimeLevelState(
  CTGKGridLevelRuntimeCoordinator &coordinator,
  ENUM_TGK_GRID_LEVEL_STATE expected_state)
{
  int count = 0;
  for(int level_index = 0; level_index < g_normal_level_count; level_index++)
  {
    if(RuntimeLevelState(coordinator, level_index) == (int)expected_state)
      count++;
  }
  return count;
}

bool SameRuntimeProjection(
  CTGKGridLevelRuntimeCoordinator &left,
  CTGKGridLevelRuntimeCoordinator &right)
{
  if(left.PositionCount() != right.PositionCount() ||
     left.RestoreStatus() != right.RestoreStatus() ||
     left.IsReconciliationPending() != right.IsReconciliationPending() ||
     (int)left.GetAnchorState() != (int)right.GetAnchorState())
    return false;

  for(int level_index = 0; level_index < g_normal_level_count; level_index++)
  {
    if(RuntimeLevelState(left, level_index) != RuntimeLevelState(right, level_index))
      return false;
  }

  for(int index = 0; index < left.PositionCount(); index++)
  {
    STGKGridLevelPositionRecord left_position;
    STGKGridLevelPositionRecord right_position;
    if(!left.TryGetPositionAt(index, left_position) ||
       !right.TryGetPositionAt(index, right_position))
      return false;

    if(left_position.position_identifier != right_position.position_identifier ||
       left_position.ticket != right_position.ticket ||
       left_position.symbol != right_position.symbol ||
       left_position.magic_number != right_position.magic_number ||
       left_position.is_anchor != right_position.is_anchor ||
       left_position.level_index != right_position.level_index ||
       MathAbs(left_position.volume - right_position.volume) > 0.00000001)
      return false;
  }

  return true;
}

int OnInit()
{
  g_symbol = _Symbol;
  g_instance_id = StringFormat(
    "UT%d_%I64d",
    (int)ChartID(),
    (long)TimeLocal());

  Tests.BeginSuite("TGK Grid Runtime State Restoration");

  Tests.BeginTest("B-01 valid Snapshot with READY Anchor hydrates into PENDING_RECONCILIATION");
  STGKGridMappingJournalRecord b01_records[];
  AddBaseConfiguration(b01_records);
  CTGKGridEntryMappingReducer b01_reducer;
  Tests.AssertTrue(
    "B-01 replay committed configuration",
    ReplayFixture(b01_records, g_instance_id, b01_reducer));
  Tests.AssertTrue(
    "B-01 the committed Grid configuration is projected",
    b01_reducer.TryGetPersistedConfig(g_persisted_config));
  Tests.AssertEqualString(
    "B-01 the projection carries the Instance identity",
    g_persisted_config.instance_id,
    g_instance_id);
  Tests.AssertEqualInt(
    "B-01 the persisted Level count includes the Anchor",
    g_persisted_config.persisted_level_count,
    g_normal_level_count + 1);
  Tests.AssertEqualInt(
    "B-01 the Engine Level count excludes the Anchor",
    g_persisted_config.persisted_level_count - 1,
    g_normal_level_count);

  CTGKGridLevelRuntimeCoordinator b01_runtime;
  Tests.AssertTrue(
    "B-01 Runtime Hydration succeeds",
    RestoreIntoRuntime(b01_reducer, b01_runtime));
  Tests.AssertEqualInt(
    "B-01 Restore finishes in RESTORED_PENDING_RECONCILIATION",
    (int)b01_runtime.RestoreStatus(),
    (int)TGK_GRID_RUNTIME_RESTORE_PENDING_RECONCILIATION);
  Tests.AssertTrue(
    "B-01 Reconciliation Gate is closed",
    b01_runtime.IsReconciliationPending());
  Tests.AssertEqualInt(
    "B-01 Anchor State is READY",
    (int)b01_runtime.GetAnchorState(),
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertEqualInt(
    "B-01 all normal Levels are READY",
    CountRuntimeLevelState(b01_runtime, TGK_GRID_LEVEL_READY),
    g_normal_level_count);
  Tests.AssertEqualInt(
    "B-01 Hydration invents no Position Mapping",
    b01_runtime.PositionCount(),
    0);
  Tests.AssertFalse(
    "B-01 restored Runtime has no unresolved Request",
    b01_runtime.IsRequestUnresolved());
  Tests.AssertTrue(
    "B-01 Grid context matches the restored configuration",
    b01_runtime.MatchesGridContext(
      g_symbol,
      g_magic_number,
      TGK_GRID_MODE_BUY,
      g_config_epoch));

  STGKGridLevelPositionRecord b01_anchor;
  b01_anchor.ticket = 4000001;
  b01_anchor.symbol = g_symbol;
  b01_anchor.magic_number = g_magic_number;
  b01_anchor.is_anchor = true;
  b01_anchor.level_index = -1;
  b01_anchor.volume = 0.01;
  Tests.AssertFalse(
    "B-01 initial Anchor registration is refused while the Gate is closed",
    b01_runtime.RegisterInitialAnchorPosition(b01_anchor));

  ENUM_TGK_GRID_COORDINATOR_RESULT b01_result;
  STGKGridLevelCandidate b01_candidate;
  Tests.AssertEqualInt(
    "B-01 a crossed Level offers no Candidate",
    (int)b01_runtime.UpdatePrice(3989.0, 3990.0, b01_result, b01_candidate),
    (int)TGK_GRID_COORDINATOR_NO_CANDIDATE);
  Tests.AssertEqualInt(
    "B-01 no Candidate target is reported",
    b01_candidate.level_index,
    -1);
  Tests.AssertTrue(
    "B-01 Gate stays closed after a price update",
    b01_runtime.IsReconciliationPending());
  Tests.EndTest();

  Tests.BeginTest("B-02 ACTIVE Anchor and its Mapping are restored onto the Anchor target");
  STGKGridMappingJournalRecord b02_records[];
  AddBaseConfiguration(b02_records);
  int b02_sequence = ArraySize(b02_records) + 1;
  AddMappedPosition(
    b02_records,
    b02_sequence,
    g_instance_id,
    "REQ-B02-ANCHOR",
    "ANCHOR",
    -1,
    2101);
  CTGKGridEntryMappingReducer b02_reducer;
  Tests.AssertTrue(
    "B-02 replay ACTIVE Anchor fixture",
    ReplayFixture(b02_records, g_instance_id, b02_reducer));

  CTGKGridLevelRuntimeCoordinator b02_runtime;
  Tests.AssertTrue(
    "B-02 Runtime Hydration succeeds",
    RestoreIntoRuntime(b02_reducer, b02_runtime));
  Tests.AssertEqualInt(
    "B-02 Anchor State is ACTIVE",
    (int)b02_runtime.GetAnchorState(),
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.AssertEqualInt(
    "B-02 one Position Mapping is restored",
    b02_runtime.PositionCount(),
    1);

  STGKGridLevelPositionRecord b02_position;
  Tests.AssertTrue(
    "B-02 restored Mapping is readable",
    b02_runtime.TryGetPositionAt(0, b02_position));
  Tests.AssertTrue(
    "B-02 Mapping is bound to the Anchor target",
    b02_position.is_anchor && b02_position.level_index == -1);
  Tests.AssertEqualString(
    "B-02 Position Identifier is restored",
    b02_position.position_identifier,
    "3002101");
  Tests.AssertEqualLong(
    "B-02 Position Ticket is restored",
    (long)b02_position.ticket,
    4002101);
  Tests.AssertEqualDouble(
    "B-02 Remaining Volume is restored",
    b02_position.volume,
    0.01,
    0.000001);
  Tests.AssertTrue(
    "B-02 restored Mapping keeps the exact identity",
    b02_position.symbol == g_symbol &&
    b02_position.magic_number == g_magic_number);
  Tests.AssertEqualInt(
    "B-02 normal Levels stay READY",
    CountRuntimeLevelState(b02_runtime, TGK_GRID_LEVEL_READY),
    g_normal_level_count);
  Tests.EndTest();

  Tests.BeginTest("B-03 WAIT_ACTIVATION Anchor is restored without an Activation Pending state");
  STGKGridMappingJournalRecord b03_records[];
  AddBaseConfiguration(b03_records);
  int b03_sequence = ArraySize(b03_records) + 1;
  AddMappedPosition(
    b03_records,
    b03_sequence,
    g_instance_id,
    "REQ-B03-ANCHOR",
    "ANCHOR",
    -1,
    2201);
  AddRecord(
    b03_records,
    b03_sequence++,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|POSITION_CLOSED|3002201|WAIT_ACTIVATION");
  CTGKGridEntryMappingReducer b03_reducer;
  Tests.AssertTrue(
    "B-03 replay closed Anchor fixture",
    ReplayFixture(b03_records, g_instance_id, b03_reducer));

  CTGKGridLevelRuntimeCoordinator b03_runtime;
  Tests.AssertTrue(
    "B-03 Runtime Hydration succeeds",
    RestoreIntoRuntime(b03_reducer, b03_runtime));
  Tests.AssertEqualInt(
    "B-03 Anchor State is WAIT_ACTIVATION",
    (int)b03_runtime.GetAnchorState(),
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.AssertEqualInt(
    "B-03 closed Anchor keeps no Mapping",
    b03_runtime.PositionCount(),
    0);
  Tests.AssertFalse(
    "B-03 Hydration creates no pending Anchor activation",
    b03_runtime.HasPendingAnchorActivation());

  ENUM_TGK_GRID_COORDINATOR_RESULT b03_result;
  STGKGridLevelCandidate b03_candidate;
  Tests.AssertEqualInt(
    "B-03 a crossed Anchor emits no Candidate",
    (int)b03_runtime.UpdatePrice(4000.5, 4001.0, b03_result, b03_candidate),
    (int)TGK_GRID_COORDINATOR_NO_CANDIDATE);
  Tests.AssertFalse(
    "B-03 a crossed Anchor stays without a pending activation",
    b03_runtime.HasPendingAnchorActivation());
  Tests.AssertEqualInt(
    "B-03 Anchor State is unchanged by the price update",
    (int)b03_runtime.GetAnchorState(),
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.EndTest();

  Tests.BeginTest("B-04 every normal Level State is restored instead of the current Quote default");
  STGKGridMappingJournalRecord b04_records[];
  AddBaseConfiguration(b04_records);
  int b04_sequence = ArraySize(b04_records) + 1;
  AddRecord(
    b04_records,
    b04_sequence++,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|LEVEL_STATE|1|3|WAIT_ACTIVATION");
  AddRecord(
    b04_records,
    b04_sequence++,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|LEVEL_STATE|1|5|WAIT_ACTIVATION");
  AddMappedPosition(
    b04_records,
    b04_sequence,
    g_instance_id,
    "REQ-B04-LEVEL",
    "LEVEL",
    1,
    2301);
  CTGKGridEntryMappingReducer b04_reducer;
  Tests.AssertTrue(
    "B-04 replay mixed Level State fixture",
    ReplayFixture(b04_records, g_instance_id, b04_reducer));

  CTGKGridLevelRuntimeCoordinator b04_runtime;
  Tests.AssertTrue(
    "B-04 Runtime Hydration succeeds",
    RestoreIntoRuntime(b04_reducer, b04_runtime));
  Tests.AssertEqualInt(
    "B-04 Level 0 is READY",
    RuntimeLevelState(b04_runtime, 0),
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertEqualInt(
    "B-04 Level 1 is ACTIVE",
    RuntimeLevelState(b04_runtime, 1),
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.AssertEqualInt(
    "B-04 Level 2 is READY",
    RuntimeLevelState(b04_runtime, 2),
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertEqualInt(
    "B-04 Level 3 is WAIT_ACTIVATION",
    RuntimeLevelState(b04_runtime, 3),
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.AssertEqualInt(
    "B-04 Level 4 stays READY instead of the Quote-derived WAIT_ACTIVATION",
    RuntimeLevelState(b04_runtime, 4),
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertEqualInt(
    "B-04 Level 5 is WAIT_ACTIVATION",
    RuntimeLevelState(b04_runtime, 5),
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.AssertEqualInt(
    "B-04 Level 6 is READY",
    RuntimeLevelState(b04_runtime, 6),
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertEqualInt(
    "B-04 Level 7 is READY",
    RuntimeLevelState(b04_runtime, 7),
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertEqualInt(
    "B-04 Anchor stays READY",
    (int)b04_runtime.GetAnchorState(),
    (int)TGK_GRID_LEVEL_READY);
  Tests.EndTest();

  Tests.BeginTest("B-05 multiple Position Mappings restore Identifier, Target, Ticket and Volume");
  STGKGridMappingJournalRecord b05_records[];
  AddBaseConfiguration(b05_records);
  int b05_sequence = ArraySize(b05_records) + 1;
  AddMappedPosition(
    b05_records,
    b05_sequence,
    g_instance_id,
    "REQ-B05-ANCHOR",
    "ANCHOR",
    -1,
    2401);
  AddMappedPosition(
    b05_records,
    b05_sequence,
    g_instance_id,
    "REQ-B05-LEVEL-1",
    "LEVEL",
    1,
    2402);
  AddMappedPosition(
    b05_records,
    b05_sequence,
    g_instance_id,
    "REQ-B05-LEVEL-6",
    "LEVEL",
    6,
    2403);
  CTGKGridEntryMappingReducer b05_reducer;
  Tests.AssertTrue(
    "B-05 replay three Mapping fixture",
    ReplayFixture(b05_records, g_instance_id, b05_reducer));

  CTGKGridLevelRuntimeCoordinator b05_runtime;
  Tests.AssertTrue(
    "B-05 Runtime Hydration succeeds",
    RestoreIntoRuntime(b05_reducer, b05_runtime));
  Tests.AssertEqualInt(
    "B-05 three Position Mappings are restored",
    b05_runtime.PositionCount(),
    3);

  STGKGridLevelPositionRecord b05_anchor;
  STGKGridLevelPositionRecord b05_level_one;
  STGKGridLevelPositionRecord b05_level_six;
  Tests.AssertTrue(
    "B-05 Anchor Mapping is readable",
    b05_runtime.TryGetPositionAt(0, b05_anchor));
  Tests.AssertTrue(
    "B-05 first Level Mapping is readable",
    b05_runtime.TryGetPositionAt(1, b05_level_one));
  Tests.AssertTrue(
    "B-05 second Level Mapping is readable",
    b05_runtime.TryGetPositionAt(2, b05_level_six));
  Tests.AssertTrue(
    "B-05 Anchor target is restored",
    b05_anchor.is_anchor && b05_anchor.level_index == -1);
  Tests.AssertEqualString(
    "B-05 Anchor Identifier",
    b05_anchor.position_identifier,
    "3002401");
  Tests.AssertEqualLong(
    "B-05 Anchor Ticket",
    (long)b05_anchor.ticket,
    4002401);
  Tests.AssertEqualDouble(
    "B-05 Anchor Volume",
    b05_anchor.volume,
    0.01,
    0.000001);
  Tests.AssertTrue(
    "B-05 Level 1 target is restored",
    !b05_level_one.is_anchor && b05_level_one.level_index == 1);
  Tests.AssertEqualString(
    "B-05 Level 1 Identifier",
    b05_level_one.position_identifier,
    "3002402");
  Tests.AssertEqualLong(
    "B-05 Level 1 Ticket",
    (long)b05_level_one.ticket,
    4002402);
  Tests.AssertTrue(
    "B-05 Level 6 target is restored",
    !b05_level_six.is_anchor && b05_level_six.level_index == 6);
  Tests.AssertEqualString(
    "B-05 Level 6 Identifier",
    b05_level_six.position_identifier,
    "3002403");
  Tests.AssertEqualLong(
    "B-05 Level 6 Ticket",
    (long)b05_level_six.ticket,
    4002403);
  Tests.AssertEqualInt(
    "B-05 Level 1 is ACTIVE",
    RuntimeLevelState(b05_runtime, 1),
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.AssertEqualInt(
    "B-05 Level 6 is ACTIVE",
    RuntimeLevelState(b05_runtime, 6),
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.AssertFalse(
    "B-05 no Mapping is reported out of range",
    b05_runtime.TryGetPositionAt(3, b05_anchor));
  Tests.EndTest();

  Tests.BeginTest("B-06 an unresolved Entry Request stays unresolved and never becomes ACTIVE");
  STGKGridMappingJournalRecord b06_records[];
  AddBaseConfiguration(b06_records);
  int b06_sequence = ArraySize(b06_records) + 1;
  AddUnresolvedRequest(
    b06_records,
    b06_sequence,
    g_instance_id,
    "REQ-B06-PENDING",
    "LEVEL",
    2,
    0.10);
  CTGKGridEntryMappingReducer b06_reducer;
  Tests.AssertTrue(
    "B-06 replay pending Request fixture",
    ReplayFixture(b06_records, g_instance_id, b06_reducer));
  Tests.AssertTrue(
    "B-06 Reducer keeps the Request unresolved",
    b06_reducer.HasUnresolvedRequest());
  Tests.AssertEqualString(
    "B-06 Reducer reports the Request Identifier",
    b06_reducer.UnresolvedRequestId(),
    "REQ-B06-PENDING");
  Tests.AssertEqualInt(
    "B-06 Reducer creates no Mapping",
    b06_reducer.PositionCount(),
    0);

  CTGKGridLevelRuntimeCoordinator b06_runtime;
  Tests.AssertTrue(
    "B-06 Runtime Hydration succeeds",
    RestoreIntoRuntime(b06_reducer, b06_runtime));
  Tests.AssertTrue(
    "B-06 Runtime keeps the Request unresolved",
    b06_runtime.IsRequestUnresolved());
  Tests.AssertEqualString(
    "B-06 Runtime keeps the Request Identifier",
    b06_runtime.PendingRequestId(),
    "REQ-B06-PENDING");
  Tests.AssertEqualInt(
    "B-06 Hydration invents no Mapping",
    b06_runtime.PositionCount(),
    0);
  Tests.AssertEqualInt(
    "B-06 the Request Target stays READY",
    RuntimeLevelState(b06_runtime, 2),
    (int)TGK_GRID_LEVEL_READY);

  ENUM_TGK_GRID_COORDINATOR_RESULT b06_result;
  STGKGridLevelCandidate b06_candidate;
  Tests.AssertEqualInt(
    "B-06 the Gate keeps a crossed Target without a Candidate",
    (int)b06_runtime.UpdatePrice(3989.0, 3990.0, b06_result, b06_candidate),
    (int)TGK_GRID_COORDINATOR_NO_CANDIDATE);
  Tests.AssertTrue(
    "B-06 the Request is still unresolved after a price update",
    b06_runtime.IsRequestUnresolved());

  STGKGridMappingRequestState b06_request_state;
  bool b06_has_request = false;
  Tests.AssertTrue(
    "B-06 the Reducer projects the unresolved Request",
    b06_reducer.TryGetUnresolvedRequest(b06_has_request, b06_request_state));
  Tests.AssertTrue(
    "B-06 the Reducer reports the unresolved Request",
    b06_has_request);
  Tests.AssertEqualDouble(
    "B-06 the Hydrated Volume equals the projected Request Volume",
    b06_runtime.PendingRequestVolume(),
    b06_request_state.requested_volume,
    0.000000001);

  // Reconcile is never an implicit Gate release: WP-05C owns that step.
  ENUM_TGK_GRID_COORDINATOR_RESULT b06_reconcile_result;
  STGKGridLevelCandidate b06_reconcile_candidate;
  STGKGridLevelPositionRecord b06_reconcile_positions[];
  STGKGridLevelCloseEvent b06_close_events[];
  Tests.AssertEqualInt(
    "B-06 Reconcile is rejected while the Gate is pending",
    (int)b06_runtime.Reconcile(
      b06_reconcile_positions,
      b06_close_events,
      TGK_GRID_ENTRY_RESOLUTION_TERMINAL_NO_POSITION_NO_ORDER,
      3989.0,
      3990.0,
      b06_reconcile_result,
      b06_reconcile_candidate),
    (int)TGK_GRID_COORDINATOR_ERROR);
  Tests.AssertTrue(
    "B-06 the Request stays unresolved after Reconcile",
    b06_runtime.IsRequestUnresolved());
  Tests.AssertEqualString(
    "B-06 the Request Identifier survives Reconcile",
    b06_runtime.PendingRequestId(),
    "REQ-B06-PENDING");
  Tests.AssertEqualDouble(
    "B-06 the Requested Volume survives Reconcile",
    b06_runtime.PendingRequestVolume(),
    0.10,
    0.000001);
  Tests.AssertEqualInt(
    "B-06 the Request Target stays READY after Reconcile",
    RuntimeLevelState(b06_runtime, 2),
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertTrue(
    "B-06 the Gate is still pending after Reconcile",
    b06_runtime.IsReconciliationPending());

  ENUM_TGK_GRID_LEVEL_STATE b06_anchor_state;
  Tests.AssertTrue(
    "B-06 Anchor State is readable",
    b06_reducer.TryGetAnchorState(b06_anchor_state));

  STGKGridLevelStateHydration b06_level_states[];
  STGKGridLevelPositionRecord b06_positions[];
  STGKGridEntryRequestHydration b06_invalid_request;
  Tests.AssertTrue(
    "B-06 the Request projection is rebuilt",
    ProjectRestoreState(
      b06_reducer,
      b06_level_states,
      b06_positions,
      b06_invalid_request));
  Tests.AssertEqualDouble(
    "B-06 the projected Requested Volume is canonical",
    b06_invalid_request.requested_volume,
    0.10,
    0.000001);

  b06_invalid_request.requested_volume = 0.0;
  CTGKGridLevelRuntimeCoordinator b06_zero_volume;
  AssertRejectedHydration(
    "B-06 zero Requested Volume",
    HydrateFixture(
      b06_zero_volume,
      b06_anchor_state,
      b06_level_states,
      b06_positions,
      b06_invalid_request),
    b06_zero_volume);

  b06_invalid_request.requested_volume = -0.10;
  CTGKGridLevelRuntimeCoordinator b06_negative_volume;
  AssertRejectedHydration(
    "B-06 negative Requested Volume",
    HydrateFixture(
      b06_negative_volume,
      b06_anchor_state,
      b06_level_states,
      b06_positions,
      b06_invalid_request),
    b06_negative_volume);

  b06_invalid_request.requested_volume = MathArcsin(2.0);
  CTGKGridLevelRuntimeCoordinator b06_non_finite_volume;
  AssertRejectedHydration(
    "B-06 non-finite Requested Volume",
    HydrateFixture(
      b06_non_finite_volume,
      b06_anchor_state,
      b06_level_states,
      b06_positions,
      b06_invalid_request),
    b06_non_finite_volume);

  Tests.AssertTrue(
    "B-06 the source Request is unchanged by the rejected Hydrations",
    ProjectRestoreState(
      b06_reducer,
      b06_level_states,
      b06_positions,
      b06_invalid_request) &&
    MathAbs(b06_invalid_request.requested_volume - 0.10) <= 0.000001);
  Tests.EndTest();

  Tests.BeginTest("B-07 invalid committed state fails closed without partial Runtime activation");
  STGKGridMappingJournalRecord b07_records[];
  AddBaseConfiguration(b07_records);
  AddRecord(
    b07_records,
    3,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|LEVEL_STATE|1|1|ACTIVE");
  CTGKGridEntryMappingReducer b07_reducer;
  Tests.AssertFalse(
    "B-07 conflicting committed state rejects Replay",
    ReplayFixture(b07_records, g_instance_id, b07_reducer));
  Tests.AssertEqualInt(
    "B-07 Reducer enters RECOVERY_ERROR",
    (int)b07_reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);

  ENUM_TGK_GRID_LEVEL_STATE b07_anchor_state;
  Tests.AssertFalse(
    "B-07 an unhealthy Reducer exposes no Anchor State",
    b07_reducer.TryGetAnchorState(b07_anchor_state));

  CTGKGridLevelRuntimeCoordinator b07_replay_runtime;
  Tests.AssertFalse(
    "B-07 no Runtime is activated from an unhealthy Reducer",
    RestoreIntoRuntime(b07_reducer, b07_replay_runtime));
  Tests.AssertFalse(
    "B-07 the unhealthy Runtime is not reconcilable",
    b07_replay_runtime.IsReconciliationPending());

  CTGKGridLevelRuntimeCoordinator b07_empty_runtime;
  STGKGridLevelStateHydration b07_level_states[];
  STGKGridLevelPositionRecord b07_positions[];
  STGKGridEntryRequestHydration b07_request;
  ClearEntryRequest(b07_request);
  Tests.AssertFalse(
    "B-07 an incomplete projection rejects Hydration",
    HydrateFixture(
      b07_empty_runtime,
      TGK_GRID_LEVEL_READY,
      b07_level_states,
      b07_positions,
      b07_request));
  Tests.AssertEqualInt(
    "B-07 rejected Hydration reports RESTORE_ERROR",
    (int)b07_empty_runtime.RestoreStatus(),
    (int)TGK_GRID_RUNTIME_RESTORE_ERROR);

  ENUM_TGK_GRID_COORDINATOR_RESULT b07_result;
  STGKGridLevelCandidate b07_candidate;
  Tests.AssertEqualInt(
    "B-07 the rejected Runtime cannot process a Quote",
    (int)b07_empty_runtime.UpdatePrice(3989.0, 3990.0, b07_result, b07_candidate),
    (int)TGK_GRID_COORDINATOR_ERROR);
  Tests.AssertEqualInt(
    "B-07 the rejected Runtime has no Position state",
    b07_empty_runtime.PositionCount(),
    0);
  Tests.EndTest();

  Tests.BeginTest("B-08 Identity, Symbol, Magic, Mode or Epoch mismatch rejects the whole Hydration");
  STGKGridMappingJournalRecord b08_records[];
  AddBaseConfiguration(b08_records);
  int b08_sequence = ArraySize(b08_records) + 1;
  AddMappedPosition(
    b08_records,
    b08_sequence,
    g_instance_id,
    "REQ-B08-LEVEL",
    "LEVEL",
    1,
    2501);
  CTGKGridEntryMappingReducer b08_reducer;
  Tests.AssertTrue(
    "B-08 replay identity fixture",
    ReplayFixture(b08_records, g_instance_id, b08_reducer));
  Tests.AssertTrue(
    "B-08 matching context is accepted",
    b08_reducer.MatchesContext(
      g_instance_id,
      g_symbol,
      g_magic_number,
      TGK_GRID_MODE_BUY,
      g_config_epoch));
  Tests.AssertFalse(
    "B-08 different Instance ID is rejected",
    b08_reducer.MatchesContext(
      g_instance_id + "_OTHER",
      g_symbol,
      g_magic_number,
      TGK_GRID_MODE_BUY,
      g_config_epoch));
  Tests.AssertFalse(
    "B-08 different Symbol is rejected",
    b08_reducer.MatchesContext(
      g_instance_id,
      g_symbol + "X",
      g_magic_number,
      TGK_GRID_MODE_BUY,
      g_config_epoch));
  Tests.AssertFalse(
    "B-08 different Magic Number is rejected",
    b08_reducer.MatchesContext(
      g_instance_id,
      g_symbol,
      g_magic_number + 1,
      TGK_GRID_MODE_BUY,
      g_config_epoch));
  Tests.AssertFalse(
    "B-08 different Mode is rejected",
    b08_reducer.MatchesContext(
      g_instance_id,
      g_symbol,
      g_magic_number,
      TGK_GRID_MODE_SELL,
      g_config_epoch));
  Tests.AssertFalse(
    "B-08 different Config Epoch is rejected",
    b08_reducer.MatchesContext(
      g_instance_id,
      g_symbol,
      g_magic_number,
      TGK_GRID_MODE_BUY,
      g_config_epoch + 1));

  ENUM_TGK_GRID_LEVEL_STATE b08_anchor_state;
  Tests.AssertTrue(
    "B-08 Anchor State is readable",
    b08_reducer.TryGetAnchorState(b08_anchor_state));
  STGKGridLevelStateHydration b08_level_states[];
  STGKGridLevelPositionRecord b08_positions[];
  STGKGridEntryRequestHydration b08_request;
  Tests.AssertTrue(
    "B-08 valid projection is available",
    ProjectRestoreState(
      b08_reducer,
      b08_level_states,
      b08_positions,
      b08_request));
  Tests.AssertEqualInt(
    "B-08 one Mapping is projected",
    ArraySize(b08_positions),
    1);

  STGKGridPositionMappingProjection b08_projection;
  Tests.AssertTrue(
    "B-08 Mapping projection is readable",
    b08_reducer.TryGetPositionMappingAt(0, b08_projection));
  Tests.AssertEqualString(
    "B-08 projection carries the Instance identity",
    b08_projection.instance_id,
    g_instance_id);
  Tests.AssertEqualString(
    "B-08 projection carries the Position Identifier",
    b08_projection.position_identifier,
    "3002501");
  Tests.AssertEqualInt(
    "B-08 projection carries the Target",
    b08_projection.level_index,
    1);

  STGKGridPersistedConfigProjection b08_config;
  Tests.AssertTrue(
    "B-08 the committed Grid configuration is projected",
    b08_reducer.TryGetPersistedConfig(b08_config));
  Tests.AssertEqualString(
    "B-08 the configuration projection carries the Instance identity",
    b08_config.instance_id,
    g_instance_id);
  Tests.AssertEqualString(
    "B-08 the configuration projection carries the Symbol",
    b08_config.symbol,
    g_symbol);
  Tests.AssertEqualLong(
    "B-08 the configuration projection carries the Magic Number",
    b08_config.magic_number,
    g_magic_number);
  Tests.AssertEqualInt(
    "B-08 the configuration projection carries the Grid Mode",
    (int)b08_config.mode,
    (int)TGK_GRID_MODE_BUY);
  Tests.AssertEqualDouble(
    "B-08 the configuration projection carries the Anchor Price",
    b08_config.anchor_price,
    g_anchor_price,
    0.000000001);
  Tests.AssertEqualDouble(
    "B-08 the configuration projection carries the Grid Step",
    b08_config.grid_step,
    g_grid_step,
    0.000000001);
  Tests.AssertEqualDouble(
    "B-08 the configuration projection carries the Lower Bound",
    b08_config.lower_bound,
    g_lower_bound,
    0.000000001);
  Tests.AssertEqualDouble(
    "B-08 the configuration projection carries the Upper Bound",
    b08_config.upper_bound,
    g_upper_bound,
    0.000000001);
  Tests.AssertEqualInt(
    "B-08 the projected persisted Level count includes the Anchor",
    b08_config.persisted_level_count,
    g_normal_level_count + 1);
  Tests.AssertEqualLong(
    "B-08 the configuration projection carries the Config Epoch",
    b08_config.config_epoch,
    g_config_epoch);

  b08_positions[0].symbol = g_symbol + "X";
  CTGKGridLevelRuntimeCoordinator b08_rejected_runtime;
  Tests.AssertFalse(
    "B-08 foreign Symbol Mapping rejects Hydration",
    HydrateFixture(
      b08_rejected_runtime,
      b08_anchor_state,
      b08_level_states,
      b08_positions,
      b08_request));
  Tests.AssertEqualInt(
    "B-08 rejected Hydration reports RESTORE_ERROR",
    (int)b08_rejected_runtime.RestoreStatus(),
    (int)TGK_GRID_RUNTIME_RESTORE_ERROR);
  Tests.AssertEqualInt(
    "B-08 rejected Hydration releases no partial Position state",
    b08_rejected_runtime.PositionCount(),
    0);
  Tests.AssertFalse(
    "B-08 rejected Hydration leaves no usable Level state",
    b08_rejected_runtime.GetLevelState(1, b07_anchor_state));

  STGKGridLevelStateHydration b08_clean_level_states[];
  STGKGridLevelPositionRecord b08_clean_positions[];
  STGKGridEntryRequestHydration b08_clean_request;
  Tests.AssertTrue(
    "B-08 a clean projection is still available",
    ProjectRestoreState(
      b08_reducer,
      b08_clean_level_states,
      b08_clean_positions,
      b08_clean_request));
  CTGKGridLevelRuntimeCoordinator b08_accepted_runtime;
  Tests.AssertTrue(
    "B-08 matching identity hydrates",
    HydrateFixture(
      b08_accepted_runtime,
      b08_anchor_state,
      b08_clean_level_states,
      b08_clean_positions,
      b08_clean_request));
  Tests.AssertEqualInt(
    "B-08 accepted Hydration restores the Mapping",
    b08_accepted_runtime.PositionCount(),
    1);
  Tests.AssertEqualString(
    "B-08 accepted Hydration keeps the Instance identity",
    b08_accepted_runtime.PersistedInstanceId(),
    g_instance_id);

  long b08_sequence_before = b08_reducer.LastSequence();
  int b08_position_count_before = b08_reducer.PositionCount();

  // Same Level count but every Level price shifted: the Engine can still build
  // 8 Levels, so only the geometry comparison can reject this Restore.
  CTGKGridLevelRuntimeCoordinator b08_shifted_anchor;
  AssertRejectedHydration(
    "B-08 shifted Anchor with the same Level count",
    HydrateRequest(
      b08_shifted_anchor,
      b08_config,
      TGK_GRID_MODE_BUY,
      g_anchor_price + g_grid_step * 0.4,
      g_grid_step,
      g_lower_bound + g_grid_step * 0.4,
      g_upper_bound + g_grid_step * 0.4,
      g_normal_level_count,
      g_symbol,
      g_magic_number,
      g_config_epoch,
      b08_anchor_state,
      b08_clean_level_states,
      b08_clean_positions,
      b08_clean_request),
    b08_shifted_anchor);

  CTGKGridLevelRuntimeCoordinator b08_different_anchor;
  AssertRejectedHydration(
    "B-08 different Anchor Price",
    HydrateRequest(
      b08_different_anchor,
      b08_config,
      TGK_GRID_MODE_BUY,
      g_anchor_price + g_grid_step,
      g_grid_step,
      g_lower_bound,
      g_upper_bound,
      g_normal_level_count,
      g_symbol,
      g_magic_number,
      g_config_epoch,
      b08_anchor_state,
      b08_clean_level_states,
      b08_clean_positions,
      b08_clean_request),
    b08_different_anchor);

  CTGKGridLevelRuntimeCoordinator b08_different_step;
  AssertRejectedHydration(
    "B-08 different Grid Step",
    HydrateRequest(
      b08_different_step,
      b08_config,
      TGK_GRID_MODE_BUY,
      g_anchor_price,
      g_grid_step + 0.001,
      g_lower_bound,
      g_upper_bound,
      g_normal_level_count,
      g_symbol,
      g_magic_number,
      g_config_epoch,
      b08_anchor_state,
      b08_clean_level_states,
      b08_clean_positions,
      b08_clean_request),
    b08_different_step);

  CTGKGridLevelRuntimeCoordinator b08_different_lower;
  AssertRejectedHydration(
    "B-08 different Lower Bound",
    HydrateRequest(
      b08_different_lower,
      b08_config,
      TGK_GRID_MODE_BUY,
      g_anchor_price,
      g_grid_step,
      g_lower_bound - 1.0,
      g_upper_bound,
      g_normal_level_count,
      g_symbol,
      g_magic_number,
      g_config_epoch,
      b08_anchor_state,
      b08_clean_level_states,
      b08_clean_positions,
      b08_clean_request),
    b08_different_lower);

  CTGKGridLevelRuntimeCoordinator b08_different_upper;
  AssertRejectedHydration(
    "B-08 different Upper Bound",
    HydrateRequest(
      b08_different_upper,
      b08_config,
      TGK_GRID_MODE_BUY,
      g_anchor_price,
      g_grid_step,
      g_lower_bound,
      g_upper_bound + 1.0,
      g_normal_level_count,
      g_symbol,
      g_magic_number,
      g_config_epoch,
      b08_anchor_state,
      b08_clean_level_states,
      b08_clean_positions,
      b08_clean_request),
    b08_different_upper);

  CTGKGridLevelRuntimeCoordinator b08_different_level_count;
  AssertRejectedHydration(
    "B-08 different persisted Level count",
    HydrateRequest(
      b08_different_level_count,
      b08_config,
      TGK_GRID_MODE_BUY,
      g_anchor_price,
      g_grid_step,
      g_lower_bound,
      g_upper_bound,
      g_normal_level_count - 1,
      g_symbol,
      g_magic_number,
      g_config_epoch,
      b08_anchor_state,
      b08_clean_level_states,
      b08_clean_positions,
      b08_clean_request),
    b08_different_level_count);

  CTGKGridLevelRuntimeCoordinator b08_different_mode;
  AssertRejectedHydration(
    "B-08 different Grid Mode",
    HydrateRequest(
      b08_different_mode,
      b08_config,
      TGK_GRID_MODE_SELL,
      g_anchor_price,
      g_grid_step,
      g_lower_bound,
      g_upper_bound,
      g_normal_level_count,
      g_symbol,
      g_magic_number,
      g_config_epoch,
      b08_anchor_state,
      b08_clean_level_states,
      b08_clean_positions,
      b08_clean_request),
    b08_different_mode);

  // A difference inside the Engine epsilon is the same geometry.
  CTGKGridLevelRuntimeCoordinator b08_epsilon_anchor;
  Tests.AssertTrue(
    "B-08 an Anchor within the Engine epsilon is accepted",
    HydrateRequest(
      b08_epsilon_anchor,
      b08_config,
      TGK_GRID_MODE_BUY,
      g_anchor_price + g_grid_step * 0.0000000005,
      g_grid_step,
      g_lower_bound,
      g_upper_bound,
      g_normal_level_count,
      g_symbol,
      g_magic_number,
      g_config_epoch,
      b08_anchor_state,
      b08_clean_level_states,
      b08_clean_positions,
      b08_clean_request));
  Tests.AssertEqualInt(
    "B-08 epsilon Anchor Hydration restores the Mapping",
    b08_epsilon_anchor.PositionCount(),
    1);

  // F-11: the request is a validation input only. The Engine must be built from
  // the persisted projection, so the Runtime Geometry is the committed Geometry
  // even though the requested Anchor differed inside the Engine epsilon.
  Tests.AssertEqualDouble(
    "B-08 epsilon Anchor Hydration keeps the persisted Anchor Price",
    b08_epsilon_anchor.AnchorPrice(),
    g_anchor_price,
    0.0000000001);
  Tests.AssertEqualString(
    "B-08 epsilon Anchor Hydration keeps the persisted Instance identity",
    b08_epsilon_anchor.PersistedInstanceId(),
    b08_config.instance_id);

  double b08_level_price = 0.0;
  Tests.AssertTrue(
    "B-08 the lowest Level Price is readable",
    b08_epsilon_anchor.GetLevelPrice(0, b08_level_price));
  Tests.AssertEqualDouble(
    "B-08 the lowest Level uses the persisted Lower geometry",
    b08_level_price,
    g_lower_bound,
    0.0000000001);

  double b08_first_upper_price = 0.0;
  Tests.AssertTrue(
    "B-08 the first upper Level Price is readable",
    b08_epsilon_anchor.GetLevelPrice(
      g_normal_level_count / 2,
      b08_first_upper_price));
  Tests.AssertEqualDouble(
    "B-08 the first upper Level uses the persisted Anchor and Step",
    b08_first_upper_price,
    g_anchor_price + g_grid_step,
    0.0000000001);

  double b08_highest_level_price = 0.0;
  Tests.AssertTrue(
    "B-08 the highest Level Price is readable",
    b08_epsilon_anchor.GetLevelPrice(
      g_normal_level_count - 1,
      b08_highest_level_price));
  Tests.AssertEqualDouble(
    "B-08 the highest Level uses the persisted Upper geometry",
    b08_highest_level_price,
    g_upper_bound,
    0.0000000001);

  double b08_unused_level_price = 0.0;
  Tests.AssertFalse(
    "B-08 the restored Grid has exactly the persisted Level count",
    b08_epsilon_anchor.GetLevelPrice(
      g_normal_level_count,
      b08_unused_level_price));
  Tests.AssertEqualInt(
    "B-08 the shifted-Anchor rejection still holds",
    (int)b08_shifted_anchor.RestoreStatus(),
    (int)TGK_GRID_RUNTIME_RESTORE_ERROR);
  Tests.AssertEqualDouble(
    "B-08 a rejected Hydration exposes no Anchor Price",
    b08_shifted_anchor.AnchorPrice(),
    0.0,
    0.0000000001);

  Tests.AssertEqualLong(
    "B-08 rejected Hydrations leave the Reducer sequence unchanged",
    b08_reducer.LastSequence(),
    b08_sequence_before);
  Tests.AssertEqualInt(
    "B-08 rejected Hydrations leave the Reducer Mapping state unchanged",
    b08_reducer.PositionCount(),
    b08_position_count_before);
  STGKGridPersistedConfigProjection b08_config_after;
  Tests.AssertTrue(
    "B-08 the committed configuration is still projected",
    b08_reducer.TryGetPersistedConfig(b08_config_after));
  Tests.AssertEqualDouble(
    "B-08 the committed Anchor Price is unchanged",
    b08_config_after.anchor_price,
    g_anchor_price,
    0.000000001);
  Tests.EndTest();

  Tests.BeginTest("B-09 duplicated or invalid Mapping targets reject the Restore");
  STGKGridMappingJournalRecord b09_records[];
  AddBaseConfiguration(b09_records);
  int b09_sequence = ArraySize(b09_records) + 1;
  AddMappedPosition(
    b09_records,
    b09_sequence,
    g_instance_id,
    "REQ-B09-LEVEL-1",
    "LEVEL",
    1,
    2601);
  AddMappedPosition(
    b09_records,
    b09_sequence,
    g_instance_id,
    "REQ-B09-LEVEL-6",
    "LEVEL",
    6,
    2602);
  CTGKGridEntryMappingReducer b09_reducer;
  Tests.AssertTrue(
    "B-09 replay two Mapping fixture",
    ReplayFixture(b09_records, g_instance_id, b09_reducer));

  ENUM_TGK_GRID_LEVEL_STATE b09_anchor_state;
  Tests.AssertTrue(
    "B-09 Anchor State is readable",
    b09_reducer.TryGetAnchorState(b09_anchor_state));

  STGKGridLevelStateHydration b09_level_states[];
  STGKGridLevelPositionRecord b09_positions[];
  STGKGridEntryRequestHydration b09_request;
  Tests.AssertTrue(
    "B-09 two Mappings are projected",
    ProjectRestoreState(
      b09_reducer,
      b09_level_states,
      b09_positions,
      b09_request) &&
    ArraySize(b09_positions) == 2);

  b09_positions[1].position_identifier = b09_positions[0].position_identifier;
  CTGKGridLevelRuntimeCoordinator b09_duplicate_identifier;
  Tests.AssertFalse(
    "B-09 duplicated Position Identifier rejects Hydration",
    HydrateFixture(
      b09_duplicate_identifier,
      b09_anchor_state,
      b09_level_states,
      b09_positions,
      b09_request));
  Tests.AssertEqualInt(
    "B-09 duplicated Identifier releases no Position state",
    b09_duplicate_identifier.PositionCount(),
    0);

  STGKGridLevelPositionRecord b09_single_positions[];
  STGKGridLevelStateHydration b09_single_level_states[];
  STGKGridEntryRequestHydration b09_single_request;
  Tests.AssertTrue(
    "B-09 second projection is rebuilt",
    ProjectRestoreState(
      b09_reducer,
      b09_single_level_states,
      b09_single_positions,
      b09_single_request));
  int b09_duplicate_target_index = ArraySize(b09_single_positions);
  ArrayResize(b09_single_positions, b09_duplicate_target_index + 1);
  b09_single_positions[b09_duplicate_target_index] = b09_positions[0];
  b09_single_positions[b09_duplicate_target_index].ticket = 4009999;
  b09_single_positions[b09_duplicate_target_index].position_identifier = "3099999";
  CTGKGridLevelRuntimeCoordinator b09_duplicate_target;
  Tests.AssertFalse(
    "B-09 duplicated Mapping Target rejects Hydration",
    HydrateFixture(
      b09_duplicate_target,
      b09_anchor_state,
      b09_single_level_states,
      b09_single_positions,
      b09_single_request));

  STGKGridLevelPositionRecord b09_invalid_positions[];
  STGKGridLevelStateHydration b09_invalid_level_states[];
  STGKGridEntryRequestHydration b09_invalid_request;
  Tests.AssertTrue(
    "B-09 third projection is rebuilt",
    ProjectRestoreState(
      b09_reducer,
      b09_invalid_level_states,
      b09_invalid_positions,
      b09_invalid_request));
  b09_invalid_positions[0].level_index = g_normal_level_count;
  CTGKGridLevelRuntimeCoordinator b09_invalid_target;
  Tests.AssertFalse(
    "B-09 out-of-range Level index rejects Hydration",
    HydrateFixture(
      b09_invalid_target,
      b09_anchor_state,
      b09_invalid_level_states,
      b09_invalid_positions,
      b09_invalid_request));

  STGKGridLevelPositionRecord b09_anchor_positions[];
  STGKGridLevelStateHydration b09_anchor_level_states[];
  STGKGridEntryRequestHydration b09_anchor_request;
  Tests.AssertTrue(
    "B-09 fourth projection is rebuilt",
    ProjectRestoreState(
      b09_reducer,
      b09_anchor_level_states,
      b09_anchor_positions,
      b09_anchor_request));
  b09_anchor_positions[0].is_anchor = true;
  CTGKGridLevelRuntimeCoordinator b09_invalid_anchor;
  Tests.AssertFalse(
    "B-09 Anchor Mapping with a Level index rejects Hydration",
    HydrateFixture(
      b09_invalid_anchor,
      b09_anchor_state,
      b09_anchor_level_states,
      b09_anchor_positions,
      b09_anchor_request));

  STGKGridLevelPositionRecord b09_ready_positions[];
  STGKGridLevelStateHydration b09_ready_level_states[];
  STGKGridEntryRequestHydration b09_ready_request;
  Tests.AssertTrue(
    "B-09 fifth projection is rebuilt",
    ProjectRestoreState(
      b09_reducer,
      b09_ready_level_states,
      b09_ready_positions,
      b09_ready_request));
  b09_ready_positions[0].level_index = 2;
  CTGKGridLevelRuntimeCoordinator b09_ready_target;
  Tests.AssertFalse(
    "B-09 a Mapping to a READY Level rejects Hydration",
    HydrateFixture(
      b09_ready_target,
      b09_anchor_state,
      b09_ready_level_states,
      b09_ready_positions,
      b09_ready_request));
  Tests.AssertEqualInt(
    "B-09 rejected Mapping Target releases no Position state",
    b09_ready_target.PositionCount(),
    0);
  Tests.AssertEqualInt(
    "B-09 rejected Mapping Target reports RESTORE_ERROR",
    (int)b09_ready_target.RestoreStatus(),
    (int)TGK_GRID_RUNTIME_RESTORE_ERROR);
  Tests.EndTest();

  Tests.BeginTest("B-10 a failure in the middle of a Mapping list releases no partial Runtime state");
  STGKGridMappingJournalRecord b10_records[];
  AddBaseConfiguration(b10_records);
  int b10_sequence = ArraySize(b10_records) + 1;
  AddMappedPosition(
    b10_records,
    b10_sequence,
    g_instance_id,
    "REQ-B10-ANCHOR",
    "ANCHOR",
    -1,
    2701);
  AddMappedPosition(
    b10_records,
    b10_sequence,
    g_instance_id,
    "REQ-B10-LEVEL-1",
    "LEVEL",
    1,
    2702);
  AddMappedPosition(
    b10_records,
    b10_sequence,
    g_instance_id,
    "REQ-B10-LEVEL-6",
    "LEVEL",
    6,
    2703);
  CTGKGridEntryMappingReducer b10_reducer;
  Tests.AssertTrue(
    "B-10 replay three Mapping fixture",
    ReplayFixture(b10_records, g_instance_id, b10_reducer));

  ENUM_TGK_GRID_LEVEL_STATE b10_anchor_state;
  Tests.AssertTrue(
    "B-10 Anchor State is readable",
    b10_reducer.TryGetAnchorState(b10_anchor_state));

  STGKGridLevelStateHydration b10_level_states[];
  STGKGridLevelPositionRecord b10_positions[];
  STGKGridEntryRequestHydration b10_request;
  Tests.AssertTrue(
    "B-10 three Mappings are projected",
    ProjectRestoreState(
      b10_reducer,
      b10_level_states,
      b10_positions,
      b10_request) &&
    ArraySize(b10_positions) == 3);

  b10_positions[2].ticket = 0;
  CTGKGridLevelRuntimeCoordinator b10_rejected_runtime;
  Tests.AssertFalse(
    "B-10 an invalid last Mapping rejects the whole Hydration",
    HydrateFixture(
      b10_rejected_runtime,
      b10_anchor_state,
      b10_level_states,
      b10_positions,
      b10_request));
  Tests.AssertEqualInt(
    "B-10 the rejected Runtime holds no Position",
    b10_rejected_runtime.PositionCount(),
    0);
  Tests.AssertEqualInt(
    "B-10 the rejected Runtime reports RESTORE_ERROR",
    (int)b10_rejected_runtime.RestoreStatus(),
    (int)TGK_GRID_RUNTIME_RESTORE_ERROR);

  ENUM_TGK_GRID_LEVEL_STATE b10_level_state;
  Tests.AssertFalse(
    "B-10 the rejected Runtime exposes no Level state",
    b10_rejected_runtime.GetLevelState(1, b10_level_state));

  ENUM_TGK_GRID_COORDINATOR_RESULT b10_result;
  STGKGridLevelCandidate b10_candidate;
  Tests.AssertEqualInt(
    "B-10 the rejected Runtime cannot process a Quote",
    (int)b10_rejected_runtime.UpdatePrice(3989.0, 3990.0, b10_result, b10_candidate),
    (int)TGK_GRID_COORDINATOR_ERROR);

  Tests.AssertTrue(
    "B-10 the source projection is unchanged",
    ProjectRestoreState(
      b10_reducer,
      b10_level_states,
      b10_positions,
      b10_request) &&
    ArraySize(b10_positions) == 3);
  CTGKGridLevelRuntimeCoordinator b10_accepted_runtime;
  Tests.AssertTrue(
    "B-10 the clean projection hydrates",
    HydrateFixture(
      b10_accepted_runtime,
      b10_anchor_state,
      b10_level_states,
      b10_positions,
      b10_request));
  Tests.AssertEqualInt(
    "B-10 the clean projection restores every Mapping",
    b10_accepted_runtime.PositionCount(),
    3);

  // F-12: a Hydration that fails after a successful Restore must leave the
  // Coordinator fail-closed. Every public accessor that could expose the old
  // Runtime must refuse to answer.
  STGKGridPersistedConfigProjection b10_config;
  Tests.AssertTrue(
    "B-10 the committed configuration is projected",
    b10_reducer.TryGetPersistedConfig(b10_config));
  Tests.AssertEqualInt(
    "B-10 the first Hydration restores an ACTIVE Anchor",
    (int)b10_accepted_runtime.GetAnchorState(),
    (int)TGK_GRID_LEVEL_ACTIVE);
  double b10_previous_level_price = 0.0;
  Tests.AssertTrue(
    "B-10 the first Hydration restores Level geometry",
    b10_accepted_runtime.GetLevelPrice(0, b10_previous_level_price));
  Tests.AssertEqualDouble(
    "B-10 the first Hydration restores the Anchor Price",
    b10_accepted_runtime.AnchorPrice(),
    g_anchor_price,
    0.0000000001);
  Tests.AssertEqualString(
    "B-10 the first Hydration restores the Instance identity",
    b10_accepted_runtime.PersistedInstanceId(),
    g_instance_id);

  long b10_sequence_before_failure = b10_reducer.LastSequence();
  int b10_positions_before_failure = b10_reducer.PositionCount();

  // A foreign Config Epoch is rejected by ValidatePersistedConfig(), before the
  // Engine is initialized, so the previous Engine build is never replaced.
  b10_config.config_epoch = g_config_epoch + 1;
  Tests.AssertFalse(
    "B-10 a second Hydration with a foreign Config Epoch fails",
    HydrateRequest(
      b10_accepted_runtime,
      b10_config,
      TGK_GRID_MODE_BUY,
      g_anchor_price,
      g_grid_step,
      g_lower_bound,
      g_upper_bound,
      g_normal_level_count,
      g_symbol,
      g_magic_number,
      g_config_epoch,
      b10_anchor_state,
      b10_level_states,
      b10_positions,
      b10_request));
  Tests.AssertEqualInt(
    "B-10 the failed second Hydration reports RESTORE_ERROR",
    (int)b10_accepted_runtime.RestoreStatus(),
    (int)TGK_GRID_RUNTIME_RESTORE_ERROR);
  Tests.AssertEqualInt(
    "B-10 the failed second Hydration exposes no stale Anchor state",
    (int)b10_accepted_runtime.GetAnchorState(),
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  ENUM_TGK_GRID_LEVEL_STATE b10_stale_level_state;
  Tests.AssertFalse(
    "B-10 the failed second Hydration exposes no stale Level state",
    b10_accepted_runtime.GetLevelState(0, b10_stale_level_state));
  Tests.AssertEqualDouble(
    "B-10 the failed second Hydration exposes no stale Anchor Price",
    b10_accepted_runtime.AnchorPrice(),
    0.0,
    0.0000000001);
  double b10_stale_level_price = 0.0;
  Tests.AssertFalse(
    "B-10 the failed second Hydration exposes no stale Level Price",
    b10_accepted_runtime.GetLevelPrice(0, b10_stale_level_price));
  Tests.AssertEqualInt(
    "B-10 the failed second Hydration exposes no stale Position count",
    b10_accepted_runtime.PositionCount(),
    0);
  STGKGridLevelPositionRecord b10_stale_position;
  Tests.AssertFalse(
    "B-10 the failed second Hydration exposes no stale Position record",
    b10_accepted_runtime.TryGetPositionAt(0, b10_stale_position));
  Tests.AssertFalse(
    "B-10 the failed second Hydration exposes no unresolved Request",
    b10_accepted_runtime.IsRequestUnresolved());
  Tests.AssertEqualString(
    "B-10 the failed second Hydration exposes no Pending Request ID",
    b10_accepted_runtime.PendingRequestId(),
    "");
  Tests.AssertEqualDouble(
    "B-10 the failed second Hydration exposes no Pending Request Volume",
    b10_accepted_runtime.PendingRequestVolume(),
    0.0,
    0.00000001);
  Tests.AssertFalse(
    "B-10 the failed second Hydration leaves the Gate closed",
    b10_accepted_runtime.IsReconciliationPending());
  Tests.AssertEqualString(
    "B-10 the failed second Hydration exposes no Instance identity",
    b10_accepted_runtime.PersistedInstanceId(),
    "");
  Tests.AssertFalse(
    "B-10 the failed second Hydration matches no Grid context",
    b10_accepted_runtime.MatchesGridContext(
      g_symbol,
      g_magic_number,
      TGK_GRID_MODE_BUY,
      g_config_epoch));
  Tests.AssertFalse(
    "B-10 the failed second Hydration matches no identity",
    b10_accepted_runtime.MatchesIdentity(g_symbol, g_magic_number));
  Tests.AssertFalse(
    "B-10 the failed second Hydration keeps no pending Anchor activation",
    b10_accepted_runtime.HasPendingAnchorActivation());

  STGKGridLevelPositionRecord b10_registration;
  b10_registration.ticket = 4002799;
  b10_registration.symbol = g_symbol;
  b10_registration.magic_number = g_magic_number;
  b10_registration.is_anchor = true;
  b10_registration.level_index = -1;
  b10_registration.volume = 0.01;
  Tests.AssertFalse(
    "B-10 the failed second Hydration cannot register an initial Anchor",
    b10_accepted_runtime.RegisterInitialAnchorPosition(b10_registration));
  Tests.AssertEqualInt(
    "B-10 the failed second Hydration offers no Candidate",
    (int)b10_accepted_runtime.UpdatePrice(
      3989.0,
      3990.0,
      b10_result,
      b10_candidate),
    (int)TGK_GRID_COORDINATOR_ERROR);
  Tests.AssertEqualInt(
    "B-10 the failed second Hydration reports no Candidate target",
    b10_candidate.level_index,
    -1);
  Tests.AssertEqualLong(
    "B-10 the failed second Hydration leaves the Reducer sequence unchanged",
    b10_reducer.LastSequence(),
    b10_sequence_before_failure);
  Tests.AssertEqualInt(
    "B-10 the failed second Hydration leaves the Reducer state unchanged",
    b10_reducer.PositionCount(),
    b10_positions_before_failure);
  Tests.EndTest();

  Tests.BeginTest("B-11 repeated Restore of the same dataset yields the same Runtime projection");
  string b11_instance = g_instance_id + "_B11";
  STGKGridMappingJournalRecord b11_records[];
  AddBaseConfiguration(b11_records);
  int b11_sequence = ArraySize(b11_records) + 1;
  AddMappedPosition(
    b11_records,
    b11_sequence,
    b11_instance,
    "REQ-B11-ANCHOR",
    "ANCHOR",
    -1,
    2801);
  AddMappedPosition(
    b11_records,
    b11_sequence,
    b11_instance,
    "REQ-B11-LEVEL",
    "LEVEL",
    1,
    2802);
  CTGKGridEntryMappingReducer b11_source;
  Tests.AssertTrue(
    "B-11 replay committed fixture",
    ReplayFixture(b11_records, b11_instance, b11_source));
  string b11_payload;
  Tests.AssertTrue(
    "B-11 export committed Snapshot",
    b11_source.ExportSnapshot(b11_payload));

  CTGKGridEntryMappingSnapshotStorage b11_storage;
  Tests.AssertTrue(
    "B-11 initialize storage",
    b11_storage.Initialize(g_symbol, b11_instance));
  Tests.AssertTrue(
    "B-11 bootstrap committed Snapshot",
    b11_storage.Bootstrap(b11_payload, b11_source.LastSequence()));

  CTGKGridEntryMappingSnapshotStorage b11_restarted;
  Tests.AssertTrue(
    "B-11 restart storage",
    b11_restarted.Initialize(g_symbol, b11_instance));
  string b11_recovered_payload;
  long b11_checkpoint = -1;
  STGKGridMappingJournalRecord b11_journal[];
  int b11_journal_count = 0;
  long b11_next_sequence = 0;
  Tests.AssertTrue(
    "B-11 recover Snapshot and Journal",
    b11_restarted.Replay(
      b11_recovered_payload,
      b11_checkpoint,
      b11_journal,
      b11_journal_count,
      b11_next_sequence));

  CTGKGridEntryMappingReducer b11_first_reducer;
  bool b11_first_restore =
    b11_first_reducer.Initialize(g_symbol, g_magic_number, b11_instance) &&
    b11_first_reducer.RestoreSnapshot(b11_recovered_payload, b11_checkpoint) &&
    b11_first_reducer.Replay(b11_journal, b11_journal_count);
  CTGKGridLevelRuntimeCoordinator b11_first_runtime;
  Tests.AssertTrue(
    "B-11 first Restore hydrates",
    b11_first_restore &&
    RestoreIntoRuntime(b11_first_reducer, b11_first_runtime));
  long b11_sequence_after_first = b11_restarted.LastSequence();

  CTGKGridEntryMappingReducer b11_second_reducer;
  bool b11_second_restore =
    b11_second_reducer.Initialize(g_symbol, g_magic_number, b11_instance) &&
    b11_second_reducer.RestoreSnapshot(b11_recovered_payload, b11_checkpoint) &&
    b11_second_reducer.Replay(b11_journal, b11_journal_count);
  CTGKGridLevelRuntimeCoordinator b11_second_runtime;
  Tests.AssertTrue(
    "B-11 second Restore hydrates",
    b11_second_restore &&
    RestoreIntoRuntime(b11_second_reducer, b11_second_runtime));
  long b11_sequence_after_second = b11_restarted.LastSequence();

  Tests.AssertEqualInt(
    "B-11 both Runtimes hold the same Position count",
    b11_first_runtime.PositionCount(),
    2);
  Tests.AssertTrue(
    "B-11 both Runtimes are identical projections",
    SameRuntimeProjection(b11_first_runtime, b11_second_runtime));
  Tests.AssertEqualLong(
    "B-11 Hydration appends no Journal record",
    b11_sequence_after_second,
    b11_sequence_after_first);
  Tests.AssertEqualLong(
    "B-11 Journal sequence follows the committed checkpoint",
    b11_sequence_after_first,
    b11_source.LastSequence());
  Tests.AssertEqualLong(
    "B-11 Reducer sequence is unchanged by Hydration",
    b11_first_reducer.LastSequence(),
    b11_source.LastSequence());
  Tests.AssertTrue(
    "B-11 clean storage",
    b11_restarted.DeleteAllFilesForTest());
  Tests.EndTest();

  Tests.BeginTest("B-12 Restore after a Snapshot checkpoint reflects the replayed Journal tail");
  string b12_instance = g_instance_id + "_B12";
  STGKGridMappingJournalRecord b12_base_records[];
  AddBaseConfiguration(b12_base_records);
  CTGKGridEntryMappingReducer b12_source;
  Tests.AssertTrue(
    "B-12 replay checkpoint fixture",
    ReplayFixture(b12_base_records, b12_instance, b12_source));
  string b12_payload;
  Tests.AssertTrue(
    "B-12 export checkpoint Snapshot",
    b12_source.ExportSnapshot(b12_payload));

  CTGKGridEntryMappingSnapshotStorage b12_storage;
  Tests.AssertTrue(
    "B-12 initialize storage",
    b12_storage.Initialize(g_symbol, b12_instance));
  Tests.AssertTrue(
    "B-12 bootstrap checkpoint Snapshot",
    b12_storage.Bootstrap(b12_payload, b12_source.LastSequence()));
  Tests.AssertTrue(
    "B-12 append post-checkpoint Entry Intent",
    b12_storage.Append(
      TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
      StringFormat(
        "v1|REQ-B12-LEVEL|%s|%I64d|BUY|LEVEL|1|0.01|1|%s",
        g_symbol,
        g_magic_number,
        b12_instance)));
  Tests.AssertTrue(
    "B-12 append post-checkpoint Execution Result",
    b12_storage.Append(
      TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
      "v1|REQ-B12-LEVEL|DONE|1000201|2000201"));
  Tests.AssertTrue(
    "B-12 append post-checkpoint Deal Association",
    b12_storage.Append(
      TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
      "v1|REQ-B12-LEVEL|2000201|3000201|0.01"));
  Tests.AssertTrue(
    "B-12 append post-checkpoint Position Mapping",
    b12_storage.Append(
      TGK_GRID_MAPPING_RECORD_POSITION_MAPPING,
      StringFormat(
        "v1|REQ-B12-LEVEL|%s|%I64d|LEVEL|1|3000201|4000201|0.01|1|%s",
        g_symbol,
        g_magic_number,
        b12_instance)));

  CTGKGridEntryMappingSnapshotStorage b12_restarted;
  Tests.AssertTrue(
    "B-12 restart storage",
    b12_restarted.Initialize(g_symbol, b12_instance));
  string b12_recovered_payload;
  long b12_checkpoint = -1;
  STGKGridMappingJournalRecord b12_journal[];
  int b12_journal_count = 0;
  long b12_next_sequence = 0;
  Tests.AssertTrue(
    "B-12 recover Snapshot and Journal",
    b12_restarted.Replay(
      b12_recovered_payload,
      b12_checkpoint,
      b12_journal,
      b12_journal_count,
      b12_next_sequence));
  Tests.AssertEqualLong(
    "B-12 checkpoint is the committed Snapshot sequence",
    b12_checkpoint,
    b12_source.LastSequence());
  Tests.AssertEqualInt(
    "B-12 four Journal records were replayed",
    b12_journal_count,
    4);
  Tests.AssertEqualLong(
    "B-12 next sequence follows the Journal tail",
    b12_next_sequence,
    7);

  CTGKGridEntryMappingReducer b12_reducer;
  bool b12_restore =
    b12_reducer.Initialize(g_symbol, g_magic_number, b12_instance) &&
    b12_reducer.RestoreSnapshot(b12_recovered_payload, b12_checkpoint) &&
    b12_reducer.Replay(b12_journal, b12_journal_count);
  Tests.AssertTrue(
    "B-12 Restore and Replay succeed",
    b12_restore);
  Tests.AssertEqualLong(
    "B-12 Reducer sequence includes the Journal tail",
    b12_reducer.LastSequence(),
    6);
  Tests.AssertEqualInt(
    "B-12 replayed Mapping is ACTIVE",
    b12_reducer.LevelStateAt(1),
    (int)TGK_GRID_LEVEL_ACTIVE);

  CTGKGridLevelRuntimeCoordinator b12_runtime;
  Tests.AssertTrue(
    "B-12 Runtime Hydration succeeds",
    RestoreIntoRuntime(b12_reducer, b12_runtime));
  Tests.AssertEqualInt(
    "B-12 Runtime reflects the replayed Level State",
    RuntimeLevelState(b12_runtime, 1),
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.AssertEqualInt(
    "B-12 Runtime reflects the replayed Mapping",
    b12_runtime.PositionCount(),
    1);

  STGKGridLevelPositionRecord b12_position;
  Tests.AssertTrue(
    "B-12 replayed Mapping is readable",
    b12_runtime.TryGetPositionAt(0, b12_position));
  Tests.AssertEqualString(
    "B-12 replayed Position Identifier",
    b12_position.position_identifier,
    "3000201");
  Tests.AssertEqualLong(
    "B-12 replayed Position Ticket",
    (long)b12_position.ticket,
    4000201);
  Tests.AssertFalse(
    "B-12 the replayed Request is resolved by its Mapping",
    b12_runtime.IsRequestUnresolved());
  Tests.AssertEqualLong(
    "B-12 Hydration appends no Journal record after the replayed tail",
    b12_restarted.LastSequence(),
    6);
  Tests.AssertTrue(
    "B-12 clean storage",
    b12_restarted.DeleteAllFilesForTest());
  Tests.EndTest();

  Tests.BeginTest("B-13 a restored Mapping stays dormant until Live Positions are reconciled");
  STGKGridMappingJournalRecord b13_records[];
  AddBaseConfiguration(b13_records);
  int b13_sequence = ArraySize(b13_records) + 1;
  AddMappedPosition(
    b13_records,
    b13_sequence,
    g_instance_id,
    "REQ-B13-LEVEL",
    "LEVEL",
    1,
    2901);
  CTGKGridEntryMappingReducer b13_reducer;
  Tests.AssertTrue(
    "B-13 replay restored Mapping fixture",
    ReplayFixture(b13_records, g_instance_id, b13_reducer));

  CTGKGridLevelRuntimeCoordinator b13_runtime;
  Tests.AssertTrue(
    "B-13 Runtime Hydration succeeds",
    RestoreIntoRuntime(b13_reducer, b13_runtime));
  Tests.AssertEqualInt(
    "B-13 Level 1 is restored ACTIVE",
    RuntimeLevelState(b13_runtime, 1),
    (int)TGK_GRID_LEVEL_ACTIVE);

  ENUM_TGK_GRID_COORDINATOR_RESULT b13_result;
  STGKGridLevelCandidate b13_candidate;
  Tests.AssertEqualInt(
    "B-13 first crossed Level offers no Candidate",
    (int)b13_runtime.UpdatePrice(3989.0, 3990.0, b13_result, b13_candidate),
    (int)TGK_GRID_COORDINATOR_NO_CANDIDATE);
  Tests.AssertEqualInt(
    "B-13 second crossed Level offers no Candidate",
    (int)b13_runtime.UpdatePrice(3984.0, 3985.0, b13_result, b13_candidate),
    (int)TGK_GRID_COORDINATOR_NO_CANDIDATE);
  Tests.AssertEqualInt(
    "B-13 an Entry Request cannot be recorded",
    (int)(b13_runtime.RecordEntryRequest(
      b13_candidate,
      TGK_GRID_ENTRY_REQUEST_ACCEPTED) ? 1 : 0),
    0);
  Tests.AssertTrue(
    "B-13 the Reconciliation Gate stays closed",
    b13_runtime.IsReconciliationPending());
  Tests.AssertEqualInt(
    "B-13 the Runtime stays in RESTORED_PENDING_RECONCILIATION",
    (int)b13_runtime.RestoreStatus(),
    (int)TGK_GRID_RUNTIME_RESTORE_PENDING_RECONCILIATION);
  Tests.AssertEqualInt(
    "B-13 the restored Level stays ACTIVE",
    RuntimeLevelState(b13_runtime, 1),
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.AssertEqualInt(
    "B-13 the restored Mapping is untouched",
    b13_runtime.PositionCount(),
    1);

  STGKGridLevelPositionRecord b13_reconcile_positions[];
  ArrayResize(b13_reconcile_positions, 1);
  Tests.AssertTrue(
    "B-13 the restored Mapping is copied into the Reconcile snapshot",
    b13_runtime.TryGetPositionAt(0, b13_reconcile_positions[0]));
  STGKGridLevelCloseEvent b13_close_events[];
  Tests.AssertEqualInt(
    "B-13 Reconcile is rejected while the Gate is pending",
    (int)b13_runtime.Reconcile(
      b13_reconcile_positions,
      b13_close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      3999.0,
      4000.0,
      b13_result,
      b13_candidate),
    (int)TGK_GRID_COORDINATOR_ERROR);
  Tests.AssertEqualInt(
    "B-13 rejected Reconcile offers no Candidate",
    b13_candidate.level_index,
    -1);
  Tests.AssertTrue(
    "B-13 rejected Reconcile keeps the Gate pending",
    b13_runtime.IsReconciliationPending());
  Tests.AssertEqualInt(
    "B-13 rejected Reconcile keeps the Level ACTIVE",
    RuntimeLevelState(b13_runtime, 1),
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.AssertEqualInt(
    "B-13 rejected Reconcile keeps the Mapping",
    b13_runtime.PositionCount(),
    1);
  Tests.AssertEqualInt(
    "B-13 rejected Reconcile stays in RESTORED_PENDING_RECONCILIATION",
    (int)b13_runtime.RestoreStatus(),
    (int)TGK_GRID_RUNTIME_RESTORE_PENDING_RECONCILIATION);
  Tests.EndTest();

  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick()
{
}
