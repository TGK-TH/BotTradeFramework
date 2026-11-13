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
  close_events[0].reason = TGK_GRID_LEVEL_CLOSE_REASON_TP;
  Tests.AssertEqualInt(
    "full close applies explicit TP event",
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
  Tests.AssertEqualInt("TP close transitions to WAIT_RETURN", (int)state, (int)TGK_GRID_LEVEL_WAIT_RETURN);
  Tests.AssertTrue("unrelated Level state remains readable", closing.GetLevelState(1, state));
  Tests.AssertEqualInt(
    "closing one Level does not alter another Level",
    (int)state,
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.EndTest();

  Tests.BeginTest("Unknown close reason and unexpected unmapped position enter ERROR");
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
  close_events[0].level_index = 0;
  close_events[0].reason = TGK_GRID_LEVEL_CLOSE_REASON_UNKNOWN;
  Tests.AssertEqualInt(
    "unknown close reason is not guessed",
    (int)unknown_close.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      4000.0,
      4001.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_ERROR);
  Tests.AssertTrue("unknown close leaves Level state readable", unknown_close.GetLevelState(0, state));
  Tests.AssertEqualInt(
    "unknown close reason does not change ACTIVE state",
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
  close_events[0].reason = TGK_GRID_LEVEL_CLOSE_REASON_TP;
  Tests.AssertEqualInt(
    "Anchor full close applies explicit TP event",
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
    "Anchor TP above Entry becomes WAIT_RETURN",
    (int)anchor_validation.GetAnchorState(),
    (int)TGK_GRID_LEVEL_WAIT_RETURN);
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

  Tests.BeginTest("Non-TP full close returns Level to READY when price is above BUY Entry");
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
  close_events[0].reason = TGK_GRID_LEVEL_CLOSE_REASON_NON_TP;
  Tests.AssertEqualInt(
    "explicit non-TP close reconciles",
    (int)non_tp.Reconcile(
      positions,
      close_events,
      TGK_GRID_ENTRY_RESOLUTION_PENDING,
      4000.0,
      4001.0,
      result,
      candidate),
    (int)TGK_GRID_COORDINATOR_NO_CANDIDATE);
  Tests.AssertTrue("non-TP closed state readable", non_tp.GetLevelState(0, state));
  Tests.AssertEqualInt(
    "non-TP above BUY Entry returns READY",
    (int)state,
    (int)TGK_GRID_LEVEL_READY);
  Tests.EndTest();

  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick()
{
}
