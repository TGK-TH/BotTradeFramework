#property strict
#property version "1.00"
#property description "Grid Level Runtime Coordinator tests; no trading."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridLevelRuntimeCoordinator.mqh>

CTGKTestRunner Tests;

void SetPosition(
  STGKGridLevelPositionRecord &position,
  ulong ticket,
  string symbol,
  long magic_number,
  bool is_anchor,
  int level_index,
  double volume
)
{
  position.ticket = ticket;
  position.symbol = symbol;
  position.magic_number = magic_number;
  position.is_anchor = is_anchor;
  position.level_index = level_index;
  position.volume = volume;
}

#define GATE_SYMBOL "XAUUSD"
#define GATE_MAGIC 710601
#define GATE_INSTANCE "UT-GATE"
#define GATE_NORMAL_LEVEL_COUNT 8

void AddCoordinatorRecord(
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

// Complete Canonical Hydration Projection built from a healthy Reducer.
bool BuildGateProjection(
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

  for(int level_index = 0; level_index < GATE_NORMAL_LEVEL_COUNT; level_index++)
  {
    int state_value = reducer.LevelStateAt(level_index);
    if(state_value < 0)
      return false;

    int index = ArraySize(level_states);
    if(ArrayResize(level_states, index + 1) != index + 1)
      return false;

    level_states[index].level_index = level_index;
    level_states[index].state = (ENUM_TGK_GRID_LEVEL_STATE)state_value;
  }

  return true;
}

// Hydrated Runtime waiting on the Reconciliation Gate, with no Position Mapping.
bool BuildGateFixture(
  CTGKGridEntryMappingReducer &reducer,
  CTGKGridLevelRuntimeCoordinator &coordinator)
{
  STGKGridMappingJournalRecord records[];
  AddCoordinatorRecord(
    records,
    1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|RESET_COMMITTED|1|BUY|5.0|3980.0|4020.0|4000.0|9");

  if(!reducer.Initialize(GATE_SYMBOL, GATE_MAGIC, GATE_INSTANCE))
    return false;
  if(!reducer.Replay(records, ArraySize(records)))
    return false;

  STGKGridPersistedConfigProjection config;
  if(!reducer.TryGetPersistedConfig(config))
    return false;

  ENUM_TGK_GRID_LEVEL_STATE anchor_state;
  STGKGridLevelStateHydration level_states[];
  STGKGridLevelPositionRecord positions[];
  STGKGridEntryRequestHydration entry_request;
  if(!BuildGateProjection(
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
    3999.0,
    4000.0,
    anchor_state,
    level_states,
    positions,
    entry_request);
}

void BuildGateProof(
  STGKGridReconciliationGateProof &proof,
  long snapshot_generation,
  long base_sequence)
{
  proof.instance_id = GATE_INSTANCE;
  proof.symbol = GATE_SYMBOL;
  proof.magic_number = GATE_MAGIC;
  proof.mode = TGK_GRID_MODE_BUY;
  proof.config_epoch = 1;
  proof.snapshot_generation = snapshot_generation;
  proof.base_sequence = base_sequence;
}

int OnInit()
{
  Tests.BeginSuite("TGK Grid Level Runtime Coordinator");

  STGKGridLevelCandidate candidate;
  ENUM_TGK_GRID_COORDINATOR_RESULT result;
  STGKGridLevelPositionRecord positions[];
  STGKGridLevelCloseEvent close_events[];

  Tests.BeginTest("Initialization validates identity and Grid configuration");
  CTGKGridLevelRuntimeCoordinator invalid;
  Tests.AssertFalse(
    "empty symbol rejected",
    invalid.Initialize(
      TGK_GRID_MODE_BUY,
      4000.0,
      5.0,
      3992.0,
      4012.0,
      3,
      "",
      710001,
      3999.0,
      4000.0));
  Tests.AssertFalse(
    "non-positive Magic rejected",
    invalid.Initialize(
      TGK_GRID_MODE_BUY,
      4000.0,
      5.0,
      3992.0,
      4012.0,
      3,
      _Symbol,
      0,
      3999.0,
      4000.0));
  Tests.AssertFalse(
    "invalid quote rejected",
    invalid.Initialize(
      TGK_GRID_MODE_BUY,
      4000.0,
      5.0,
      3992.0,
      4012.0,
      3,
      _Symbol,
      710001,
      0.0,
      0.0));
  Tests.EndTest();

  Tests.BeginTest("Runtime context matching binds and enforces Config Epoch");
  CTGKGridLevelRuntimeCoordinator context;
  Tests.AssertFalse(
    "uninitialized Coordinator cannot bind Config Epoch",
    context.BindConfigEpoch(1));
  Tests.AssertTrue(
    "initialize context Coordinator",
    context.Initialize(
      TGK_GRID_MODE_BUY,
      4000.0,
      5.0,
      3992.0,
      4012.0,
      3,
      "XAUUSD",
      710101,
      3999.0,
      4000.0));
  Tests.AssertFalse("zero Config Epoch rejected", context.BindConfigEpoch(0));
  Tests.AssertFalse("negative Config Epoch rejected", context.BindConfigEpoch(-1));
  Tests.AssertFalse(
    "unbound Coordinator does not match Grid context",
    context.MatchesGridContext("XAUUSD", 710101, TGK_GRID_MODE_BUY, 1));
  Tests.AssertTrue("positive Config Epoch binds", context.BindConfigEpoch(1));
  Tests.AssertTrue("same Config Epoch may be rebound", context.BindConfigEpoch(1));
  Tests.AssertTrue(
    "exact Symbol/Magic/Mode/Epoch matches",
    context.MatchesGridContext("XAUUSD", 710101, TGK_GRID_MODE_BUY, 1));
  Tests.AssertFalse(
    "different Symbol does not match",
    context.MatchesGridContext("EURUSD", 710101, TGK_GRID_MODE_BUY, 1));
  Tests.AssertFalse(
    "different Magic does not match",
    context.MatchesGridContext("XAUUSD", 710102, TGK_GRID_MODE_BUY, 1));
  Tests.AssertFalse(
    "different Mode does not match",
    context.MatchesGridContext("XAUUSD", 710101, TGK_GRID_MODE_SELL, 1));
  Tests.AssertFalse(
    "different Config Epoch does not match",
    context.MatchesGridContext("XAUUSD", 710101, TGK_GRID_MODE_BUY, 2));
  Tests.AssertFalse(
    "non-positive matched Config Epoch does not match",
    context.MatchesGridContext("XAUUSD", 710101, TGK_GRID_MODE_BUY, 0));
  Tests.AssertFalse(
    "different Config Epoch cannot replace existing binding",
    context.BindConfigEpoch(2));
  Tests.AssertTrue(
    "original binding remains intact after rejected rebind",
    context.MatchesGridContext("XAUUSD", 710101, TGK_GRID_MODE_BUY, 1));
  Tests.AssertTrue(
    "Mode context matches independently of Epoch",
    context.MatchesModeContext("XAUUSD", 710101, TGK_GRID_MODE_BUY));
  Tests.AssertFalse(
    "Mode context rejects wrong identity",
    context.MatchesModeContext("XAUUSD", 710102, TGK_GRID_MODE_BUY));
  Tests.AssertFalse(
    "Mode context rejects wrong Mode",
    context.MatchesModeContext("XAUUSD", 710101, TGK_GRID_MODE_SELL));
  Tests.EndTest();

  Tests.BeginTest("Invalid quote does not mutate the previous quote");
  CTGKGridLevelRuntimeCoordinator quote_validation;
  quote_validation.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3992.0,
    4012.0,
    3,
    _Symbol,
    710018,
    3999.0,
    4000.0);
  Tests.AssertEqualInt(
    "invalid quote returns ERROR",
    (int)quote_validation.UpdatePrice(
      0.0,
      0.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_ERROR);
  Tests.AssertEqualInt(
    "valid crossing still uses last valid quote",
    (int)quote_validation.UpdatePrice(
      3989.0,
      3990.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_CANDIDATE_READY);
  Tests.AssertEqualDouble(
    "candidate uses expected crossed level",
    candidate.level_price,
    3995.0,
    0.000001);
  Tests.EndTest();

  Tests.BeginTest("BUY candidate is emitted once and carries exact level mapping");
  CTGKGridLevelRuntimeCoordinator buy;
  Tests.AssertTrue(
    "initialize BUY coordinator",
    buy.Initialize(
      TGK_GRID_MODE_BUY,
      4000.0,
      5.0,
      3992.0,
      4012.0,
      3,
      _Symbol,
      710002,
      3999.0,
      4000.0));
  Tests.AssertEqualInt(
    "first downward crossing returns candidate",
    (int)buy.UpdatePrice(
      3989.0,
      3990.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_CANDIDATE_READY);
  Tests.AssertFalse("BUY candidate is not Anchor", candidate.is_anchor);
  Tests.AssertEqualInt("BUY candidate maps to lower level index", candidate.level_index, 0);
  Tests.AssertEqualDouble("BUY candidate price", candidate.level_price, 3995.0, 0.000001);
  Tests.AssertEqualInt(
    "stationary quote does not emit a duplicate",
    (int)buy.UpdatePrice(
      3989.0,
      3990.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_NO_CANDIDATE);
  Tests.AssertEqualInt(
    "same candidate is not emitted again",
    (int)buy.UpdatePrice(
      3988.0,
      3989.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_NO_CANDIDATE);
  Tests.EndTest();

  Tests.BeginTest("Terminal request failure re-arms candidate using latest quote");
  CTGKGridLevelRuntimeCoordinator failed;
  failed.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3992.0,
    4012.0,
    3,
    _Symbol,
    710003,
    3999.0,
    4000.0);
  failed.UpdatePrice(
    3989.0,
    3990.0,
    result,
    candidate
  );
  Tests.AssertTrue(
    "terminal failure acknowledged",
    failed.RecordEntryRequest(
      candidate,
      TGK_GRID_ENTRY_REQUEST_FAILED));
  ENUM_TGK_GRID_LEVEL_STATE state;
  Tests.AssertTrue("failed level state readable", failed.GetLevelState(0, state));
  Tests.AssertEqualInt(
    "failed BUY level above current price waits activation",
    (int)state,
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.EndTest();

  Tests.BeginTest("Accepted request remains unresolved and blocks a second request");
  CTGKGridLevelRuntimeCoordinator pending;
  pending.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3992.0,
    4012.0,
    3,
    _Symbol,
    710004,
    3999.0,
    4000.0);
  pending.UpdatePrice(
    3989.0,
    3990.0,
    result,
    candidate
  );
  Tests.AssertTrue(
    "accepted request recorded",
    pending.RecordEntryRequest(
      candidate,
      TGK_GRID_ENTRY_REQUEST_ACCEPTED));
  Tests.AssertFalse(
    "duplicate acknowledgement cannot create a second request",
    pending.RecordEntryRequest(
      candidate,
      TGK_GRID_ENTRY_REQUEST_ACCEPTED));
  Tests.AssertEqualInt(
    "request unresolved blocks candidate",
    (int)pending.UpdatePrice(
      3994.0,
      3995.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_REQUEST_UNRESOLVED);
  Tests.AssertTrue("pending level state readable", pending.GetLevelState(0, state));
  Tests.AssertEqualInt(
    "accepted request leaves Level non-ACTIVE until Position is confirmed",
    (int)state,
    (int)TGK_GRID_LEVEL_READY);
  Tests.EndTest();

  Tests.BeginTest("BUY retains lowest deferred candidate while request is unresolved");
  CTGKGridLevelRuntimeCoordinator deferred_buy;
  deferred_buy.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3985.0,
    4015.0,
    6,
    _Symbol,
    710005,
    4009.0,
    4010.0);
  deferred_buy.UpdatePrice(
    3999.0,
    4000.0,
    result,
    candidate
  );
  deferred_buy.RecordEntryRequest(
    candidate,
    TGK_GRID_ENTRY_REQUEST_ACCEPTED);
  deferred_buy.UpdatePrice(
    3994.0,
    3995.0,
    result,
    candidate
  );
  deferred_buy.UpdatePrice(
    3989.0,
    3990.0,
    result,
    candidate
  );
  Tests.AssertEqualInt(
    "unresolved state continues price processing",
    (int)result,
    (int)TGK_GRID_COORDINATOR_REQUEST_UNRESOLVED);
  Tests.EndTest();

  Tests.BeginTest("SELL retains the highest deferred candidate while request is unresolved");
  CTGKGridLevelRuntimeCoordinator deferred_sell;
  deferred_sell.Initialize(
    TGK_GRID_MODE_SELL,
    4000.0,
    5.0,
    3985.0,
    4015.0,
    6,
    _Symbol,
    710019,
    3990.0,
    3991.0);
  deferred_sell.UpdatePrice(
    4005.0,
    4006.0,
    result,
    candidate);
  STGKGridLevelCandidate sell_request;
  sell_request.is_anchor = candidate.is_anchor;
  sell_request.level_index = candidate.level_index;
  sell_request.level_price = candidate.level_price;
  deferred_sell.RecordEntryRequest(
    sell_request,
    TGK_GRID_ENTRY_REQUEST_ACCEPTED);
  deferred_sell.UpdatePrice(
    4010.0,
    4011.0,
    result,
    candidate);
  deferred_sell.UpdatePrice(
    4015.0,
    4016.0,
    result,
    candidate);
  ArrayResize(positions, 1);
  SetPosition(
    positions[0],
    6051,
    _Symbol,
    710019,
    false,
    sell_request.level_index,
    0.01);
  ArrayResize(close_events, 0);
  Tests.AssertEqualInt(
    "confirmed SELL request releases best deferred candidate",
    (int)deferred_sell.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      4015.0,
      4016.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_CANDIDATE_READY);
  Tests.AssertEqualInt(
    "highest SELL deferred Level selected",
    candidate.level_index,
    5);
  Tests.AssertEqualDouble(
    "highest SELL deferred price selected",
    candidate.level_price,
    4015.0,
    0.000001);
  Tests.EndTest();

  Tests.BeginTest("Matching Position confirms request and activates mapped Level");
  CTGKGridLevelRuntimeCoordinator confirmed;
  confirmed.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3992.0,
    4012.0,
    3,
    _Symbol,
    710006,
    3999.0,
    4000.0);
  confirmed.UpdatePrice(
    3989.0,
    3990.0,
    result,
    candidate
  );
  confirmed.RecordEntryRequest(
    candidate,
    TGK_GRID_ENTRY_REQUEST_ACCEPTED);
  ArrayResize(positions, 1);
  SetPosition(
    positions[0],
    6001,
    _Symbol,
    710006,
    false,
    0,
    0.01);
  ArrayResize(close_events, 0);
  Tests.AssertEqualInt(
    "matching position resolves request",
    (int)confirmed.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      3988.0,
      3989.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_NO_CANDIDATE);
  Tests.AssertTrue("confirmed level state readable", confirmed.GetLevelState(0, state));
  Tests.AssertEqualInt(
    "confirmed position activates level",
    (int)state,
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.EndTest();

  Tests.BeginTest("Terminal no-position/no-order resolves accepted request as failed");
  CTGKGridLevelRuntimeCoordinator terminal;
  terminal.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3992.0,
    4012.0,
    3,
    _Symbol,
    710007,
    3999.0,
    4000.0);
  terminal.UpdatePrice(
    3989.0,
    3990.0,
    result,
    candidate
  );
  terminal.RecordEntryRequest(
    candidate,
    TGK_GRID_ENTRY_REQUEST_ACCEPTED);
  ArrayResize(positions, 0);
  Tests.AssertEqualInt(
    "pending absence remains unresolved",
    (int)terminal.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      3988.0,
      3989.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_REQUEST_UNRESOLVED);
  Tests.AssertEqualInt(
    "terminal resolution clears request",
    (int)terminal.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_TERMINAL_NO_POSITION_NO_ORDER,
      3988.0,
      3989.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_NO_CANDIDATE);
  Tests.AssertTrue("terminal failed level state readable", terminal.GetLevelState(0, state));
  Tests.AssertEqualInt(
    "terminal failed entry does not become ACTIVE",
    (int)state,
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.EndTest();

  Tests.BeginTest("Position mapped to a different Level cannot confirm the pending Request");
  CTGKGridLevelRuntimeCoordinator wrong_mapping;
  wrong_mapping.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3992.0,
    4012.0,
    3,
    _Symbol,
    710017,
    3999.0,
    4000.0);
  wrong_mapping.UpdatePrice(
    3989.0,
    3990.0,
    result,
    candidate
  );
  wrong_mapping.RecordEntryRequest(
    candidate,
    TGK_GRID_ENTRY_REQUEST_ACCEPTED);
  ArrayResize(positions, 1);
  SetPosition(
    positions[0],
    6451,
    _Symbol,
    710017,
    false,
    1,
    0.01);
  ArrayResize(close_events, 0);
  Tests.AssertEqualInt(
    "different Level mapping is an inconsistency",
    (int)wrong_mapping.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      3989.0,
      3990.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_ERROR);
  Tests.AssertTrue("wrongly mapped Level remains readable", wrong_mapping.GetLevelState(0, state));
  Tests.AssertEqualInt(
    "wrong mapping does not activate requested Level",
    (int)state,
    (int)TGK_GRID_LEVEL_READY);
  Tests.EndTest();

  Tests.BeginTest("Position snapshot rejects invalid and duplicate mappings");
  CTGKGridLevelRuntimeCoordinator validation;
  validation.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3992.0,
    4012.0,
    3,
    _Symbol,
    710008,
    3999.0,
    4000.0);
  ArrayResize(positions, 1);
  SetPosition(positions[0], 0, _Symbol, 710008, false, 0, 0.01);
  Tests.AssertEqualInt(
    "zero ticket rejected",
    (int)validation.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      3999.0,
      4000.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_ERROR);
  ArrayResize(positions, 2);
  SetPosition(positions[0], 6502, _Symbol, 710008, false, 0, 0.01);
  SetPosition(positions[1], 6503, _Symbol, 710008, false, 0, 0.02);
  Tests.AssertEqualInt(
    "duplicate logical Level mapping rejected",
    (int)validation.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      3999.0,
      4000.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_ERROR);
  Tests.EndTest();

  Tests.BeginTest("SELL candidate uses highest crossed eligible level");
  CTGKGridLevelRuntimeCoordinator sell;
  Tests.AssertTrue(
    "initialize SELL coordinator",
    sell.Initialize(
      TGK_GRID_MODE_SELL,
      4000.0,
      5.0,
      3992.0,
      4012.0,
      3,
      _Symbol,
      710009,
      4000.0,
      4001.0));
  Tests.AssertEqualInt(
    "upward crossing returns SELL candidate",
    (int)sell.UpdatePrice(
      4010.0,
      4011.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_CANDIDATE_READY);
  Tests.AssertEqualInt("SELL chooses highest crossed index", candidate.level_index, 2);
  Tests.AssertEqualDouble("SELL chooses highest crossed price", candidate.level_price, 4010.0, 0.000001);
  Tests.EndTest();

  Tests.BeginTest("Position mapping mismatch and duplicate ticket are rejected");
  CTGKGridLevelRuntimeCoordinator mismatch;
  mismatch.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3992.0,
    4012.0,
    3,
    _Symbol,
    710010,
    3999.0,
    4000.0);
  ArrayResize(positions, 2);
  SetPosition(positions[0], 6101, _Symbol, 710010, true, -1, 0.01);
  SetPosition(positions[1], 6101, _Symbol, 710010, false, 0, 0.01);
  Tests.AssertEqualInt(
    "duplicate ticket rejected",
    (int)mismatch.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      3999.0,
      4000.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_ERROR);
  Tests.EndTest();

  Tests.BeginTest("Partial close retains ACTIVE and full close applies TP transition");
  CTGKGridLevelRuntimeCoordinator closing;
  closing.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3992.0,
    4012.0,
    3,
    _Symbol,
    710011,
    3999.0,
    4000.0);
  closing.UpdatePrice(
    3989.0,
    3990.0,
    result,
    candidate
  );
  closing.RecordEntryRequest(candidate, TGK_GRID_ENTRY_REQUEST_ACCEPTED);
  ArrayResize(positions, 1);
  SetPosition(positions[0], 6201, _Symbol, 710011, false, 0, 0.02);
  closing.Reconcile(
    positions,
    close_events,
    TGK_GRID_ENTRY_RESOLUTION_PENDING,
    3988.0,
    3989.0,
    result,
    candidate);
  SetPosition(positions[0], 6201, _Symbol, 710011, false, 0, 0.01);
  Tests.AssertEqualInt(
    "partial close remains valid",
    (int)closing.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      4000.0,
      4001.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_NO_CANDIDATE);
  Tests.AssertTrue("partial level state readable", closing.GetLevelState(0, state));
  Tests.AssertEqualInt("partial volume keeps ACTIVE", (int)state, (int)TGK_GRID_LEVEL_ACTIVE);

  ArrayResize(positions, 0);
  ArrayResize(close_events, 1);
  close_events[0].is_anchor = false;
  close_events[0].level_index = 0;
  Tests.AssertEqualInt(
    "full close applies reason-free event",
    (int)closing.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      4000.0,
      4001.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_NO_CANDIDATE);
  Tests.AssertTrue("closed level state readable", closing.GetLevelState(0, state));
  Tests.AssertEqualInt("full close below current Ask transitions to READY", (int)state, (int)TGK_GRID_LEVEL_READY);
  Tests.AssertTrue("unrelated Level state remains readable", closing.GetLevelState(1, state));
  Tests.AssertEqualInt(
    "closing one Level does not alter another Level",
    (int)state,
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.EndTest();

  Tests.BeginTest("Invalid close event and unexpected unmapped position enter ERROR");
  CTGKGridLevelRuntimeCoordinator unknown_close;
  unknown_close.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3992.0,
    4012.0,
    3,
    _Symbol,
    710012,
    3999.0,
    4000.0);
  unknown_close.UpdatePrice(
    3989.0,
    3990.0,
    result,
    candidate
  );
  unknown_close.RecordEntryRequest(candidate, TGK_GRID_ENTRY_REQUEST_ACCEPTED);
  ArrayResize(close_events, 0);
  ArrayResize(positions, 1);
  SetPosition(positions[0], 6301, _Symbol, 710012, false, 0, 0.01);
  unknown_close.Reconcile(
    positions,
    close_events,
    TGK_GRID_ENTRY_RESOLUTION_PENDING,
    3988.0,
    3989.0,
    result,
    candidate);
  ArrayResize(positions, 0);
  ArrayResize(close_events, 1);
  close_events[0].is_anchor = false;
  close_events[0].level_index = 3;
  Tests.AssertEqualInt(
    "close event with invalid mapping is rejected",
    (int)unknown_close.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      4000.0,
      4001.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_ERROR);
  Tests.AssertTrue("invalid close leaves Level state readable", unknown_close.GetLevelState(0, state));
  Tests.AssertEqualInt(
    "invalid close event does not change ACTIVE state",
    (int)state,
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.EndTest();

  Tests.BeginTest("Deferred BUY candidate keeps the best price and is revalidated");
  CTGKGridLevelRuntimeCoordinator deferred;
  deferred.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3985.0,
    4015.0,
    6,
    _Symbol,
    710013,
    4009.0,
    4010.0);
  deferred.UpdatePrice(
    3999.0,
    4000.0,
    result,
    candidate
  );
  STGKGridLevelCandidate first_request;
  first_request.is_anchor = candidate.is_anchor;
  first_request.level_index = candidate.level_index;
  first_request.level_price = candidate.level_price;
  deferred.RecordEntryRequest(
    first_request,
    TGK_GRID_ENTRY_REQUEST_ACCEPTED);
  deferred.UpdatePrice(
    3994.0,
    3995.0,
    result,
    candidate
  );
  deferred.UpdatePrice(
    3989.0,
    3990.0,
    result,
    candidate
  );
  ArrayResize(positions, 1);
  SetPosition(
    positions[0],
    6401,
    _Symbol,
    710013,
    false,
    first_request.level_index,
    0.01);
  ArrayResize(close_events, 0);
  Tests.AssertEqualInt(
    "confirmed request releases best deferred candidate",
    (int)deferred.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      3989.0,
      3990.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_CANDIDATE_READY);
  Tests.AssertEqualInt(
    "lowest BUY deferred Level selected",
    candidate.level_index,
    1);
  Tests.AssertEqualDouble(
    "lowest BUY deferred price selected",
    candidate.level_price,
    3990.0,
    0.000001);
  Tests.EndTest();

  Tests.BeginTest("Position snapshot rejects wrong identity, invalid index and zero volume");
  CTGKGridLevelRuntimeCoordinator snapshot_validation;
  snapshot_validation.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3992.0,
    4012.0,
    3,
    _Symbol,
    710014,
    3999.0,
    4000.0);
  ArrayResize(positions, 1);
  SetPosition(positions[0], 6501, _Symbol + "_OTHER", 710014, false, 0, 0.01);
  Tests.AssertEqualInt(
    "wrong Symbol rejected",
    (int)snapshot_validation.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      3999.0,
      4000.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_ERROR);
  SetPosition(positions[0], 6501, _Symbol, 710015, false, 0, 0.01);
  Tests.AssertEqualInt(
    "wrong Magic rejected",
    (int)snapshot_validation.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      3999.0,
      4000.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_ERROR);
  SetPosition(positions[0], 6501, _Symbol, 710014, false, 3, 0.01);
  Tests.AssertEqualInt(
    "out-of-range Level Index rejected",
    (int)snapshot_validation.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      3999.0,
      4000.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_ERROR);
  SetPosition(positions[0], 6501, _Symbol, 710014, false, 0, 0.0);
  Tests.AssertEqualInt(
    "zero volume rejected",
    (int)snapshot_validation.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      3999.0,
      4000.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_ERROR);
  Tests.EndTest();

  Tests.BeginTest("Anchor mapping requires index -1 and unexpected positions are rejected");
  CTGKGridLevelRuntimeCoordinator anchor_validation;
  anchor_validation.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3992.0,
    4012.0,
    3,
    _Symbol,
    710015,
    3999.0,
    4000.0);
  ArrayResize(positions, 1);
  SetPosition(positions[0], 6601, _Symbol, 710015, true, 0, 0.01);
  Tests.AssertEqualInt(
    "Anchor with non-negative index rejected",
    (int)anchor_validation.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      3999.0,
      4000.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_ERROR);
  SetPosition(positions[0], 6601, _Symbol, 710015, true, -1, 0.01);
  Tests.AssertTrue(
    "initial Anchor position is explicitly registered",
    anchor_validation.RegisterInitialAnchorPosition(positions[0]));
  Tests.AssertEqualInt(
    "registered Anchor reconciles without an Entry Request",
    (int)anchor_validation.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      3999.0,
      4000.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_NO_CANDIDATE);
  Tests.AssertEqualInt(
    "initial Anchor remains ACTIVE",
    (int)anchor_validation.GetAnchorState(),
    (int)TGK_GRID_LEVEL_ACTIVE);

  ArrayResize(positions, 0);
  ArrayResize(close_events, 1);
  close_events[0].is_anchor = true;
  close_events[0].level_index = -1;
  Tests.AssertEqualInt(
    "Anchor full close applies reason-free event",
    (int)anchor_validation.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      4000.0,
      4001.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_NO_CANDIDATE);
  Tests.AssertEqualInt(
    "Anchor below current Ask becomes READY",
    (int)anchor_validation.GetAnchorState(),
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertEqualInt(
    "Anchor re-entry crossing produces a Candidate",
    (int)anchor_validation.UpdatePrice(
      3998.0,
      3999.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_CANDIDATE_READY);
  Tests.AssertTrue("Anchor Candidate has Anchor flag", candidate.is_anchor);
  Tests.AssertEqualInt("Anchor Candidate uses index -1", candidate.level_index, -1);
  Tests.AssertEqualDouble("Anchor Candidate uses Anchor price", candidate.level_price, 4000.0, 0.000001);
  Tests.EndTest();

  Tests.BeginTest("Full close returns Level to READY when price is above BUY Entry");
  CTGKGridLevelRuntimeCoordinator non_tp;
  non_tp.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3992.0,
    4012.0,
    3,
    _Symbol,
    710016,
    3999.0,
    4000.0);
  non_tp.UpdatePrice(
    3989.0,
    3990.0,
    result,
    candidate
  );
  non_tp.RecordEntryRequest(candidate, TGK_GRID_ENTRY_REQUEST_ACCEPTED);
  ArrayResize(close_events, 0);
  ArrayResize(positions, 1);
  SetPosition(positions[0], 6701, _Symbol, 710016, false, 0, 0.01);
  non_tp.Reconcile(
    positions,
    close_events,
    TGK_GRID_ENTRY_RESOLUTION_PENDING,
    3989.0,
    3990.0,
    result,
    candidate);
  ArrayResize(positions, 0);
  ArrayResize(close_events, 1);
  close_events[0].is_anchor = false;
  close_events[0].level_index = 0;
  Tests.AssertEqualInt(
    "reason-free close reconciles",
    (int)non_tp.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      4000.0,
      4001.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_NO_CANDIDATE);
  Tests.AssertTrue("closed state readable", non_tp.GetLevelState(0, state));
  Tests.AssertEqualInt(
    "close above BUY Entry returns READY",
    (int)state,
    (int)TGK_GRID_LEVEL_READY);
  Tests.EndTest();

  Tests.BeginTest("Anchor activation is withheld until its durable confirmation");
  CTGKGridLevelRuntimeCoordinator anchor_activation;
  Tests.AssertTrue(
    "Anchor activation Coordinator initializes",
    anchor_activation.Initialize(
      TGK_GRID_MODE_BUY,
      4000.0,
      5.0,
      3990.0,
      4010.0,
      4,
      "XAUUSD",
      710017,
      3999.0,
      4000.0));
  Tests.AssertTrue(
    "Anchor activation binds Config Epoch",
    anchor_activation.BindConfigEpoch(1));

  STGKGridLevelPositionRecord anchor_position;
  SetPosition(anchor_position, 6801, "XAUUSD", 710017, true, -1, 0.01);
  Tests.AssertTrue(
    "initial Anchor is registered",
    anchor_activation.RegisterInitialAnchorPosition(anchor_position));

  ArrayResize(positions, 0);
  ArrayResize(close_events, 1);
  close_events[0].is_anchor = true;
  close_events[0].level_index = -1;
  Tests.AssertEqualInt(
    "CR01-01 Anchor close is applied",
    (int)anchor_activation.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      3999.0,
      4000.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_NO_CANDIDATE);
  Tests.AssertEqualInt(
    "CR01-01 Anchor waits activation",
    (int)anchor_activation.GetAnchorState(),
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.AssertFalse(
    "closed Anchor has no pending activation",
    anchor_activation.HasPendingAnchorActivation());

  // Ask moves below the Anchor, then crosses it upward, which is the BUY
  // activation direction.
  anchor_activation.UpdatePrice(
    3998.0,
    3999.0,
    result,
    candidate);
  anchor_activation.UpdatePrice(
    3999.0,
    4000.0,
    result,
    candidate);
  Tests.AssertEqualInt(
    "CR01-02 activation crossing becomes READY",
    (int)anchor_activation.GetAnchorState(),
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertTrue(
    "activation awaits durable confirmation",
    anchor_activation.HasPendingAnchorActivation());

  // After activation the market rises above the Anchor and then crosses it
  // downward, which is the BUY entry direction. That crossed Anchor candidate
  // must still be withheld while the durable record is missing.
  anchor_activation.UpdatePrice(
    4001.0,
    4002.0,
    result,
    candidate);
  Tests.AssertEqualInt(
    "crossed Anchor is not offered before persistence",
    (int)anchor_activation.UpdatePrice(
      3999.0,
      4000.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_NO_CANDIDATE);
  Tests.AssertFalse(
    "withheld candidate is not an Anchor offer",
    candidate.is_anchor);

  Tests.AssertTrue(
    "durable confirmation is accepted",
    anchor_activation.ConfirmAnchorActivation());
  Tests.AssertFalse(
    "confirmed activation is no longer pending",
    anchor_activation.HasPendingAnchorActivation());
  Tests.AssertFalse(
    "activation cannot be confirmed twice",
    anchor_activation.ConfirmAnchorActivation());
  Tests.AssertEqualInt(
    "deferred Anchor candidate is offered after confirmation",
    (int)anchor_activation.UpdatePrice(
      3999.0,
      4000.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_CANDIDATE_READY);
  Tests.AssertTrue("offered candidate is the Anchor", candidate.is_anchor);
  Tests.AssertEqualDouble(
    "offered Anchor price",
    candidate.level_price,
    4000.0,
    0.000001);
  Tests.EndTest();

  Tests.BeginTest("Gate release is refused before a Stable Snapshot");
  CTGKGridLevelRuntimeCoordinator not_pending;
  Tests.AssertTrue(
    "initialize an unprepared Coordinator",
    not_pending.Initialize(
      TGK_GRID_MODE_BUY,
      4000.0,
      5.0,
      3980.0,
      4020.0,
      GATE_NORMAL_LEVEL_COUNT,
      GATE_SYMBOL,
      GATE_MAGIC,
      3999.0,
      4000.0));
  Tests.AssertFalse(
    "the Runtime is not waiting for Reconciliation",
    not_pending.IsReconciliationPending());

  STGKGridReconciliationGateProof unprepared_proof;
  BuildGateProof(unprepared_proof, 1, 0);
  ENUM_TGK_GRID_LEVEL_STATE unprepared_anchor_state = TGK_GRID_LEVEL_READY;
  STGKGridLevelStateHydration unprepared_level_states[];
  STGKGridLevelPositionRecord unprepared_positions[];
  STGKGridEntryRequestHydration unprepared_entry_request;
  unprepared_entry_request.present = false;
  unprepared_entry_request.request_id = "";
  unprepared_entry_request.is_anchor = false;
  unprepared_entry_request.level_index = -1;
  unprepared_entry_request.requested_volume = 0.0;
  ArrayResize(unprepared_level_states, 0);
  ArrayResize(unprepared_positions, 0);
  Tests.AssertFalse(
    "release is refused without Hydration",
    not_pending.ReleaseReconciliationGate(
      unprepared_proof,
      unprepared_anchor_state,
      unprepared_level_states,
      unprepared_positions,
      unprepared_entry_request,
      3999.0,
      4000.0));
  Tests.EndTest();

  Tests.BeginTest("Gate release refuses a mismatched proof or Projection");
  CTGKGridEntryMappingReducer gate_reducer;
  CTGKGridLevelRuntimeCoordinator gate_coordinator;
  Tests.AssertTrue(
    "build hydrated Gate fixture",
    BuildGateFixture(gate_reducer, gate_coordinator));
  Tests.AssertTrue(
    "the hydrated Runtime waits for Reconciliation",
    gate_coordinator.IsReconciliationPending());

  ENUM_TGK_GRID_LEVEL_STATE gate_anchor_state;
  STGKGridLevelStateHydration gate_level_states[];
  STGKGridLevelPositionRecord gate_positions[];
  STGKGridEntryRequestHydration gate_entry_request;
  Tests.AssertTrue(
    "build the Canonical Projection",
    BuildGateProjection(
      gate_reducer,
      gate_anchor_state,
      gate_level_states,
      gate_positions,
      gate_entry_request));
  Tests.AssertEqualInt(
    "Projection covers every Level",
    ArraySize(gate_level_states),
    GATE_NORMAL_LEVEL_COUNT);

  STGKGridReconciliationGateProof gate_proof;
  BuildGateProof(gate_proof, 0, 0);
  Tests.AssertFalse(
    "a zero Snapshot Generation is refused",
    gate_coordinator.ReleaseReconciliationGate(
      gate_proof,
      gate_anchor_state,
      gate_level_states,
      gate_positions,
      gate_entry_request,
      3999.0,
      4000.0));

  BuildGateProof(gate_proof, 1, 0);
  gate_proof.config_epoch = 2;
  Tests.AssertFalse(
    "a different Config Epoch is refused",
    gate_coordinator.ReleaseReconciliationGate(
      gate_proof,
      gate_anchor_state,
      gate_level_states,
      gate_positions,
      gate_entry_request,
      3999.0,
      4000.0));

  BuildGateProof(gate_proof, 1, 0);
  gate_proof.mode = TGK_GRID_MODE_SELL;
  Tests.AssertFalse(
    "a different Mode is refused",
    gate_coordinator.ReleaseReconciliationGate(
      gate_proof,
      gate_anchor_state,
      gate_level_states,
      gate_positions,
      gate_entry_request,
      3999.0,
      4000.0));

  BuildGateProof(gate_proof, 1, 0);
  gate_proof.instance_id = "UT-OTHER";
  Tests.AssertFalse(
    "a different Instance is refused",
    gate_coordinator.ReleaseReconciliationGate(
      gate_proof,
      gate_anchor_state,
      gate_level_states,
      gate_positions,
      gate_entry_request,
      3999.0,
      4000.0));

  BuildGateProof(gate_proof, 1, 0);
  ENUM_TGK_GRID_LEVEL_STATE saved_level_state = gate_level_states[0].state;
  gate_level_states[0].state = TGK_GRID_LEVEL_WAIT_ACTIVATION;
  Tests.AssertFalse(
    "a different Level State is refused",
    gate_coordinator.ReleaseReconciliationGate(
      gate_proof,
      gate_anchor_state,
      gate_level_states,
      gate_positions,
      gate_entry_request,
      3999.0,
      4000.0));
  gate_level_states[0].state = saved_level_state;

  Tests.AssertFalse(
    "a different Anchor State is refused",
    gate_coordinator.ReleaseReconciliationGate(
      gate_proof,
      TGK_GRID_LEVEL_WAIT_ACTIVATION,
      gate_level_states,
      gate_positions,
      gate_entry_request,
      3999.0,
      4000.0));

  Tests.AssertFalse(
    "an invalid quote is refused",
    gate_coordinator.ReleaseReconciliationGate(
      gate_proof,
      gate_anchor_state,
      gate_level_states,
      gate_positions,
      gate_entry_request,
      0.0,
      0.0));

  Tests.AssertTrue(
    "every rejection keeps the Gate closed",
    gate_coordinator.IsReconciliationPending());
  Tests.EndTest();

  Tests.BeginTest("Gate release clears the Gate and refreshes the Quote Baseline");
  BuildGateProof(gate_proof, 1, 0);
  Tests.AssertTrue(
    "matching proof releases the Gate",
    gate_coordinator.ReleaseReconciliationGate(
      gate_proof,
      gate_anchor_state,
      gate_level_states,
      gate_positions,
      gate_entry_request,
      3999.0,
      4000.0));
  Tests.AssertFalse(
    "the Gate is open",
    gate_coordinator.IsReconciliationPending());
  Tests.AssertFalse(
    "the release creates no Anchor activation",
    gate_coordinator.HasPendingAnchorActivation());

  ENUM_TGK_GRID_COORDINATOR_RESULT release_result;
  STGKGridLevelCandidate release_candidate;
  Tests.AssertEqualInt(
    "the release itself emits no Candidate on the same quote",
    (int)gate_coordinator.UpdatePrice(
      3999.0,
      4000.0,
      release_result,
      release_candidate),
    (int)TGK_GRID_COORDINATOR_NO_CANDIDATE);
  Tests.AssertEqualInt(
    "no Level candidate is exposed",
    release_candidate.level_index,
    -1);
  Tests.AssertFalse("no Anchor candidate is exposed", release_candidate.is_anchor);

  Tests.AssertEqualInt(
    "Price Processing resumes against the released baseline",
    (int)gate_coordinator.UpdatePrice(
      3985.0,
      3986.0,
      release_result,
      release_candidate),
    (int)TGK_GRID_COORDINATOR_CANDIDATE_READY);
  Tests.AssertEqualInt(
    "lowest crossed Level is offered",
    release_candidate.level_index,
    2);
  Tests.AssertEqualDouble(
    "offered Level price",
    release_candidate.level_price,
    3990.0,
    0.000001);

  BuildGateProof(gate_proof, 2, 0);
  Tests.AssertFalse(
    "a released Gate cannot be released twice",
    gate_coordinator.ReleaseReconciliationGate(
      gate_proof,
      gate_anchor_state,
      gate_level_states,
      gate_positions,
      gate_entry_request,
      3999.0,
      4000.0));
  Tests.EndTest();

  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick()
{
}
