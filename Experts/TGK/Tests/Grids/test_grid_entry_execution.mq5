#property strict
#property version "1.00"
#property description "Grid Entry Execution Adapter tests; fake ports only, no trading."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridEntryExecutionAdapter.mqh>

CTGKTestRunner Tests;

class CTGKGridEntryExecutionFakePort : public ITGKGridEntryExecutionPort
{
public:
  bool fail_intent;
  bool fail_result;
  bool fail_intent_after_write;
  bool send_return;
  uint retcode;
  string order_ticket;
  string deal_ticket;
  int call_count;
  int send_count;
  string call_order;
  string intent_payload;
  string result_payload;
  string last_comment;
  bool last_is_buy;
  string last_symbol;
  double last_volume;
  long next_sequence;

  CTGKGridEntryExecutionFakePort()
  {
    fail_intent = false;
    fail_result = false;
    fail_intent_after_write = false;
    send_return = true;
    retcode = TRADE_RETCODE_DONE;
    order_ticket = "90071992547409931";
    deal_ticket = "90071992547409932";
    call_count = 0;
    send_count = 0;
    call_order = "";
    intent_payload = "";
    result_payload = "";
    last_comment = "";
    last_is_buy = true;
    last_symbol = "";
    last_volume = 0.0;
    next_sequence = 2;
  }

  virtual bool NextSequence(long &sequence)
  {
    sequence = next_sequence;
    return true;
  }

  virtual bool AppendRecord(
    ENUM_TGK_GRID_MAPPING_RECORD_TYPE record_type,
    const string payload
  )
  {
    call_count++;
    call_order += record_type == TGK_GRID_MAPPING_RECORD_ENTRY_INTENT
                  ? "I"
                  : "R";
    if(record_type == TGK_GRID_MAPPING_RECORD_ENTRY_INTENT)
    {
      intent_payload = payload;
      if(fail_intent)
      {
        if(fail_intent_after_write)
          next_sequence++;
        return false;
      }
      next_sequence++;
      return true;
    }
    result_payload = payload;
    if(fail_result)
    {
      next_sequence++;
      return false;
    }
    next_sequence++;
    return true;
  }

  virtual bool SendMarketOrder(
    bool is_buy,
    string symbol,
    double volume,
    long magic_number,
    string comment,
    uint &result_retcode,
    string &order_ticket_result,
    string &deal_ticket_result
  )
  {
    send_count++;
    call_order += "T";
    last_is_buy = is_buy;
    last_symbol = symbol;
    last_volume = volume;
    last_comment = comment;
    result_retcode = retcode;
    order_ticket_result = order_ticket;
    deal_ticket_result = deal_ticket;
    return send_return;
  }
};

void AddConfiguration(STGKGridMappingJournalRecord &records[])
{
  ArrayResize(records, 1);
  records[0].sequence = 1;
  records[0].record_type = TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE;
  records[0].payload = "v1|RESET_COMMITTED|1|BUY|5.0|3960.0|4040.0|4000.0|17";
}

// A committed configuration, a mapped Anchor, and its close record. The close
// leaves the canonical Anchor at WAIT_ACTIVATION with no Position Mapping.
// Usage: truncate to 5 records when the Anchor mapping must still be present.
void AddAnchorActivationRecords(STGKGridMappingJournalRecord &records[])
{
  ArrayResize(records, 6);

  records[0].sequence = 1;
  records[0].record_type = TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE;
  records[0].payload = "v1|RESET_COMMITTED|1|BUY|5.0|3960.0|4040.0|4000.0|17";

  records[1].sequence = 2;
  records[1].record_type = TGK_GRID_MAPPING_RECORD_ENTRY_INTENT;
  records[1].payload =
    "v1|REQ-CR01-ANCHOR|XAUUSD|710001|BUY|ANCHOR|-1|0.01|1|UT_INSTANCE";

  records[2].sequence = 3;
  records[2].record_type = TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT;
  records[2].payload = "v1|REQ-CR01-ANCHOR|DONE|1009981|0";

  records[3].sequence = 4;
  records[3].record_type = TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION;
  records[3].payload = "v1|REQ-CR01-ANCHOR|2009981|3009981|0.01";

  records[4].sequence = 5;
  records[4].record_type = TGK_GRID_MAPPING_RECORD_POSITION_MAPPING;
  records[4].payload =
    "v1|REQ-CR01-ANCHOR|XAUUSD|710001|ANCHOR|-1|3009981|4009981|0.01|1|UT_INSTANCE";

  records[5].sequence = 6;
  records[5].record_type = TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE;
  records[5].payload = "v1|POSITION_CLOSED|3009981|WAIT_ACTIVATION";
}

bool InitializeReducer(CTGKGridEntryMappingReducer &reducer)
{
  STGKGridMappingJournalRecord records[];
  AddConfiguration(records);
  bool initialized = reducer.Initialize("XAUUSD", 710001, "UT_INSTANCE");
  return initialized && reducer.Replay(records, ArraySize(records));
}

// Drives a BUY Anchor from ACTIVE to a pending WAIT_ACTIVATION -> READY
// activation crossing, so the durable transition can be exercised.
bool PrepareAnchorActivation(
  CTGKGridEntryMappingReducer &reducer,
  CTGKGridLevelRuntimeCoordinator &coordinator)
{
  if(!reducer.Initialize("XAUUSD", 710001, "UT_INSTANCE"))
    return false;

  STGKGridMappingJournalRecord records[];
  AddAnchorActivationRecords(records);
  if(!reducer.Replay(records, ArraySize(records)))
    return false;

  if(!coordinator.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3960.0,
    4040.0,
    16,
    "XAUUSD",
    710001,
    3999.0,
    4000.0) ||
     !coordinator.BindConfigEpoch(1))
    return false;

  STGKGridLevelPositionRecord anchor_position;
  anchor_position.ticket = 6001;
  anchor_position.symbol = "XAUUSD";
  anchor_position.magic_number = 710001;
  anchor_position.is_anchor = true;
  anchor_position.level_index = -1;
  anchor_position.volume = 0.01;
  if(!coordinator.RegisterInitialAnchorPosition(anchor_position))
    return false;

  STGKGridLevelPositionRecord positions[];
  STGKGridLevelCloseEvent close_events[];
  STGKGridLevelCandidate candidate;
  ENUM_TGK_GRID_COORDINATOR_RESULT result;
  ArrayResize(close_events, 1);
  close_events[0].is_anchor = true;
  close_events[0].level_index = -1;
  if(coordinator.Reconcile(
    positions,
    close_events,
    TGK_GRID_ENTRY_RESOLUTION_PENDING,
    3999.0,
    4000.0,
    result,
    candidate) != TGK_GRID_COORDINATOR_NO_CANDIDATE)
    return false;

  if(coordinator.GetAnchorState() != TGK_GRID_LEVEL_WAIT_ACTIVATION)
    return false;

  // Ask moves below the Anchor, then crosses it upward, which is the BUY
  // activation direction.
  coordinator.UpdatePrice(3998.0, 3999.0, result, candidate);
  coordinator.UpdatePrice(3999.0, 4000.0, result, candidate);
  return coordinator.HasPendingAnchorActivation();
}

void RunAnchorActivationPersistence()
{
  Tests.BeginTest("CR01-02 Anchor activation is journaled before READY is accepted");
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionFakePort port;
  CTGKGridLevelRuntimeCoordinator coordinator;
  ENUM_TGK_GRID_LEVEL_STATE anchor_state = TGK_GRID_LEVEL_ACTIVE;

  bool ready = PrepareAnchorActivation(reducer, coordinator) &&
               adapter.Initialize();
  port.next_sequence = reducer.LastSequence() + 1;
  Tests.AssertTrue("activation fixture is ready", ready);
  Tests.AssertTrue(
    "canonical Anchor State is queryable before append",
    reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "canonical Anchor State waits activation",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);

  bool recorded = ready && adapter.RecordAnchorActivation(
    "UT_INSTANCE",
    "XAUUSD",
    710001,
    TGK_GRID_MODE_BUY,
    1,
    coordinator,
    reducer,
    port);
  Tests.AssertTrue("activation transition is recorded", recorded);
  Tests.AssertEqualString(
    "canonical activation payload",
    port.result_payload,
    "v1|ANCHOR_STATE|1|READY");
  Tests.AssertTrue(
    "canonical Anchor State is queryable after append",
    reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "canonical Anchor State becomes READY",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertFalse(
    "activation is no longer pending",
    coordinator.HasPendingAnchorActivation());
  Tests.AssertEqualInt(
    "activation creates no Position Mapping",
    reducer.PositionCount(),
    0);
  Tests.AssertEqualInt("no trade request was sent", port.send_count, 0);
  Tests.EndTest();
}

void RunAnchorActivationPersistenceFailure()
{
  Tests.BeginTest("CR01-12 activation append failure leaves WAIT_ACTIVATION canonical");
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionFakePort port;
  CTGKGridLevelRuntimeCoordinator coordinator;
  ENUM_TGK_GRID_LEVEL_STATE anchor_state = TGK_GRID_LEVEL_READY;

  bool ready = PrepareAnchorActivation(reducer, coordinator) &&
               adapter.Initialize();
  port.next_sequence = reducer.LastSequence() + 1;
  Tests.AssertTrue("activation fixture is ready", ready);
  port.fail_result = true;

  bool recorded = ready && adapter.RecordAnchorActivation(
    "UT_INSTANCE",
    "XAUUSD",
    710001,
    TGK_GRID_MODE_BUY,
    1,
    coordinator,
    reducer,
    port);
  Tests.AssertFalse("append failure reports failure", recorded);
  Tests.AssertTrue(
    "append failure requires recovery",
    adapter.IsRecoveryRequired());
  Tests.AssertTrue(
    "canonical Anchor State remains queryable",
    reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "canonical Anchor State remains WAIT_ACTIVATION",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);
  Tests.AssertTrue(
    "activation remains pending",
    coordinator.HasPendingAnchorActivation());
  Tests.AssertEqualInt("no trade request was sent", port.send_count, 0);
  Tests.EndTest();
}

// Proves CR-02: an invalid activation is rejected before any Journal append,
// so no durable record, Reducer state or Coordinator confirmation changes.
void RunAnchorActivationRejectedWhenCanonicalReady()
{
  Tests.BeginTest("CR02-01 activation rejected when canonical state is already READY");
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionFakePort port;
  CTGKGridLevelRuntimeCoordinator coordinator;
  ENUM_TGK_GRID_LEVEL_STATE anchor_state = TGK_GRID_LEVEL_WAIT_ACTIVATION;
  bool has_anchor_mapping = true;

  bool ready = PrepareAnchorActivation(reducer, coordinator) &&
               adapter.Initialize();

  // The Reducer already accepted READY while the Coordinator still reports a
  // pending activation: this disagreement must fail closed.
  STGKGridMappingJournalRecord records[];
  ArrayResize(records, 1);
  records[0].sequence = reducer.LastSequence() + 1;
  records[0].record_type = TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE;
  records[0].payload = "v1|ANCHOR_STATE|1|READY";
  bool canonical_ready = ready && reducer.Replay(records, 1);
  long journal_sequence = reducer.LastSequence();
  port.next_sequence = journal_sequence + 1;

  Tests.AssertTrue("fixture prepares a pending activation", ready);
  Tests.AssertTrue("canonical state is READY before the attempt", canonical_ready);
  Tests.AssertTrue(
    "coordinator still reports a pending activation",
    coordinator.HasPendingAnchorActivation());

  bool recorded = adapter.RecordAnchorActivation(
    "UT_INSTANCE",
    "XAUUSD",
    710001,
    TGK_GRID_MODE_BUY,
    1,
    coordinator,
    reducer,
    port);
  Tests.AssertFalse("activation is rejected", recorded);
  Tests.AssertFalse(
    "rejection is a state conflict, not a recovery lock",
    adapter.IsRecoveryRequired());
  Tests.AssertEqualInt("journal append count unchanged", port.call_count, 0);
  Tests.AssertEqualInt(
    "journal sequence unchanged",
    (int)reducer.LastSequence(),
    (int)journal_sequence);
  Tests.AssertTrue(
    "canonical Anchor State remains queryable",
    reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "canonical Anchor State remains READY",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertTrue(
    "Anchor mapping query remains healthy",
    reducer.TryGetPositionMapping(true, -1, has_anchor_mapping));
  Tests.AssertFalse("no Anchor mapping exists", has_anchor_mapping);
  Tests.AssertEqualInt(
    "still no Position Mapping",
    reducer.PositionCount(),
    0);
  Tests.AssertTrue(
    "activation remains pending for recovery",
    coordinator.HasPendingAnchorActivation());
  Tests.AssertEqualInt("no trade request was sent", port.send_count, 0);
  Tests.EndTest();
}

void RunAnchorActivationRejectedWhenMappingExists()
{
  Tests.BeginTest("CR02-02 activation rejected while an Anchor mapping exists");
  CTGKGridEntryMappingReducer prepared_reducer;
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionFakePort port;
  CTGKGridLevelRuntimeCoordinator coordinator;
  ENUM_TGK_GRID_LEVEL_STATE anchor_state = TGK_GRID_LEVEL_WAIT_ACTIVATION;
  bool has_anchor_mapping = false;

  bool ready = PrepareAnchorActivation(prepared_reducer, coordinator) &&
               adapter.Initialize();

  // A conflicting canonical state: the Anchor is mapped and ACTIVE, not an
  // unmapped Anchor that waits activation.
  STGKGridMappingJournalRecord records[];
  AddAnchorActivationRecords(records);
  ArrayResize(records, 5);
  bool mapped = reducer.Initialize("XAUUSD", 710001, "UT_INSTANCE") &&
                reducer.Replay(records, ArraySize(records));
  long journal_sequence = reducer.LastSequence();
  port.next_sequence = journal_sequence + 1;

  Tests.AssertTrue("fixture prepares a pending activation", ready);
  Tests.AssertTrue("conflicting reducer fixture is replayed", mapped);
  Tests.AssertTrue(
    "Anchor mapping is present",
    reducer.TryGetPositionMapping(true, -1, has_anchor_mapping) &&
      has_anchor_mapping);
  Tests.AssertEqualInt("mapping count is one", reducer.PositionCount(), 1);
  Tests.AssertTrue(
    "canonical Anchor State is queryable",
    reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "canonical Anchor State is ACTIVE",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_ACTIVE);

  bool recorded = adapter.RecordAnchorActivation(
    "UT_INSTANCE",
    "XAUUSD",
    710001,
    TGK_GRID_MODE_BUY,
    1,
    coordinator,
    reducer,
    port);
  Tests.AssertFalse("activation is rejected", recorded);
  Tests.AssertEqualInt("journal append count unchanged", port.call_count, 0);
  Tests.AssertEqualInt(
    "journal sequence unchanged",
    (int)reducer.LastSequence(),
    (int)journal_sequence);
  Tests.AssertTrue(
    "canonical Anchor State remains queryable",
    reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "canonical Anchor State remains ACTIVE",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.AssertEqualInt(
    "Position Mapping count unchanged",
    reducer.PositionCount(),
    1);
  Tests.AssertTrue(
    "activation remains pending",
    coordinator.HasPendingAnchorActivation());
  Tests.AssertEqualInt("no trade request was sent", port.send_count, 0);
  Tests.EndTest();
}

void RunAnchorActivationValidControl()
{
  Tests.BeginTest("CR02-03 valid activation appends exactly one durable record");
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionFakePort port;
  CTGKGridLevelRuntimeCoordinator coordinator;
  ENUM_TGK_GRID_LEVEL_STATE anchor_state = TGK_GRID_LEVEL_ACTIVE;

  bool ready = PrepareAnchorActivation(reducer, coordinator) &&
               adapter.Initialize();
  long journal_sequence = reducer.LastSequence();
  port.next_sequence = journal_sequence + 1;
  Tests.AssertTrue("fixture prepares a pending activation", ready);

  bool recorded = adapter.RecordAnchorActivation(
    "UT_INSTANCE",
    "XAUUSD",
    710001,
    TGK_GRID_MODE_BUY,
    1,
    coordinator,
    reducer,
    port);
  Tests.AssertTrue("activation is recorded", recorded);
  Tests.AssertEqualInt("exactly one journal append", port.call_count, 1);
  Tests.AssertEqualString("append is a lifecycle record", port.call_order, "R");
  Tests.AssertEqualString(
    "canonical activation payload",
    port.result_payload,
    "v1|ANCHOR_STATE|1|READY");
  Tests.AssertEqualInt(
    "journal sequence advanced once",
    (int)reducer.LastSequence(),
    (int)journal_sequence + 1);
  Tests.AssertTrue(
    "canonical Anchor State is queryable",
    reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "canonical Anchor State becomes READY",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertFalse(
    "activation is confirmed after durable success",
    coordinator.HasPendingAnchorActivation());
  Tests.AssertEqualInt("no trade request was sent", port.send_count, 0);
  Tests.EndTest();
}

void RunAnchorActivationDuplicateRejected()
{
  Tests.BeginTest("CR02-04 repeated activation appends no duplicate record");
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionFakePort port;
  CTGKGridLevelRuntimeCoordinator coordinator;
  ENUM_TGK_GRID_LEVEL_STATE anchor_state = TGK_GRID_LEVEL_ACTIVE;

  bool ready = PrepareAnchorActivation(reducer, coordinator) &&
               adapter.Initialize();
  port.next_sequence = reducer.LastSequence() + 1;
  Tests.AssertTrue("fixture prepares a pending activation", ready);

  bool first = adapter.RecordAnchorActivation(
    "UT_INSTANCE",
    "XAUUSD",
    710001,
    TGK_GRID_MODE_BUY,
    1,
    coordinator,
    reducer,
    port);
  long journal_sequence = reducer.LastSequence();

  // The reachable duplicate path: the Coordinator already confirmed the one
  // durable activation, so a repeated request has no pending activation.
  bool second = adapter.RecordAnchorActivation(
    "UT_INSTANCE",
    "XAUUSD",
    710001,
    TGK_GRID_MODE_BUY,
    1,
    coordinator,
    reducer,
    port);

  Tests.AssertTrue("first activation succeeds", first);
  Tests.AssertFalse("repeated activation is rejected", second);
  Tests.AssertEqualInt("only one journal append", port.call_count, 1);
  Tests.AssertEqualInt(
    "journal sequence unchanged by the repeat",
    (int)reducer.LastSequence(),
    (int)journal_sequence);
  Tests.AssertTrue(
    "canonical Anchor State is queryable",
    reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "canonical Anchor State remains READY",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertFalse(
    "no activation is left pending",
    coordinator.HasPendingAnchorActivation());
  Tests.AssertEqualInt("no trade request was sent", port.send_count, 0);
  Tests.EndTest();
}

// SELL context fixture: the same lifecycle in SELL mode, so the durable path
// is exercised for the downward activation direction.
void AddSellAnchorActivationRecords(STGKGridMappingJournalRecord &records[])
{
  ArrayResize(records, 6);

  records[0].sequence = 1;
  records[0].record_type = TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE;
  records[0].payload = "v1|RESET_COMMITTED|1|SELL|5.0|3960.0|4040.0|4000.0|17";

  records[1].sequence = 2;
  records[1].record_type = TGK_GRID_MAPPING_RECORD_ENTRY_INTENT;
  records[1].payload =
    "v1|REQ-CR03-ANCHOR|XAUUSD|710001|SELL|ANCHOR|-1|0.01|1|UT_INSTANCE";

  records[2].sequence = 3;
  records[2].record_type = TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT;
  records[2].payload = "v1|REQ-CR03-ANCHOR|DONE|1009981|0";

  records[3].sequence = 4;
  records[3].record_type = TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION;
  records[3].payload = "v1|REQ-CR03-ANCHOR|2009981|3009981|0.01";

  records[4].sequence = 5;
  records[4].record_type = TGK_GRID_MAPPING_RECORD_POSITION_MAPPING;
  records[4].payload =
    "v1|REQ-CR03-ANCHOR|XAUUSD|710001|ANCHOR|-1|3009981|4009981|0.01|1|UT_INSTANCE";

  records[5].sequence = 6;
  records[5].record_type = TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE;
  records[5].payload = "v1|POSITION_CLOSED|3009981|WAIT_ACTIVATION";
}

// Drives a SELL Anchor from ACTIVE to a pending WAIT_ACTIVATION -> READY
// activation crossing on the Bid, which is the SELL activation direction.
bool PrepareSellAnchorActivation(
  CTGKGridEntryMappingReducer &reducer,
  CTGKGridLevelRuntimeCoordinator &coordinator)
{
  if(!reducer.Initialize("XAUUSD", 710001, "UT_INSTANCE"))
    return false;

  STGKGridMappingJournalRecord records[];
  AddSellAnchorActivationRecords(records);
  if(!reducer.Replay(records, ArraySize(records)))
    return false;

  if(!coordinator.Initialize(
    TGK_GRID_MODE_SELL,
    4000.0,
    5.0,
    3960.0,
    4040.0,
    16,
    "XAUUSD",
    710001,
    4001.0,
    4002.0) ||
     !coordinator.BindConfigEpoch(1))
    return false;

  STGKGridLevelPositionRecord anchor_position;
  anchor_position.ticket = 6002;
  anchor_position.symbol = "XAUUSD";
  anchor_position.magic_number = 710001;
  anchor_position.is_anchor = true;
  anchor_position.level_index = -1;
  anchor_position.volume = 0.01;
  if(!coordinator.RegisterInitialAnchorPosition(anchor_position))
    return false;

  STGKGridLevelPositionRecord positions[];
  STGKGridLevelCloseEvent close_events[];
  STGKGridLevelCandidate candidate;
  ENUM_TGK_GRID_COORDINATOR_RESULT result;
  ArrayResize(close_events, 1);
  close_events[0].is_anchor = true;
  close_events[0].level_index = -1;
  if(coordinator.Reconcile(
    positions,
    close_events,
    TGK_GRID_ENTRY_RESOLUTION_PENDING,
    4001.0,
    4002.0,
    result,
    candidate) != TGK_GRID_COORDINATOR_NO_CANDIDATE)
    return false;

  if(coordinator.GetAnchorState() != TGK_GRID_LEVEL_WAIT_ACTIVATION)
    return false;

  // The Bid moves down to the Anchor price, which is the SELL activation
  // direction (equality included at the current price).
  coordinator.UpdatePrice(4000.0, 4001.0, result, candidate);
  return coordinator.HasPendingAnchorActivation();
}

// Proves CR-03: the SELL activation uses the same durable
// Adapter -> Journal -> Reducer path as the BUY case.
void RunSellAnchorActivationPersistence()
{
  Tests.BeginTest("CR03-01 SELL Anchor activation is journaled through the durable path");
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionFakePort port;
  CTGKGridLevelRuntimeCoordinator coordinator;
  ENUM_TGK_GRID_LEVEL_STATE anchor_state = TGK_GRID_LEVEL_ACTIVE;
  bool has_anchor_mapping = true;

  bool ready = PrepareSellAnchorActivation(reducer, coordinator) &&
               adapter.Initialize();
  long journal_sequence = reducer.LastSequence();
  port.next_sequence = journal_sequence + 1;
  Tests.AssertTrue("SELL activation fixture is ready", ready);
  Tests.AssertTrue(
    "SELL activation is pending after the downward crossing",
    coordinator.HasPendingAnchorActivation());
  Tests.AssertTrue(
    "canonical Anchor State waits activation before append",
    reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "canonical Anchor State is WAIT_ACTIVATION",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_WAIT_ACTIVATION);

  bool recorded = adapter.RecordAnchorActivation(
    "UT_INSTANCE",
    "XAUUSD",
    710001,
    TGK_GRID_MODE_SELL,
    1,
    coordinator,
    reducer,
    port);
  Tests.AssertTrue("SELL activation is recorded", recorded);
  Tests.AssertEqualInt("exactly one journal append", port.call_count, 1);
  Tests.AssertEqualString("append is a lifecycle record", port.call_order, "R");
  Tests.AssertEqualString(
    "single ANCHOR_STATE|READY lifecycle payload",
    port.result_payload,
    "v1|ANCHOR_STATE|1|READY");
  Tests.AssertEqualInt(
    "journal sequence advanced once",
    (int)reducer.LastSequence(),
    (int)journal_sequence + 1);
  Tests.AssertTrue(
    "canonical Anchor State is queryable after append",
    reducer.TryGetAnchorState(anchor_state));
  Tests.AssertEqualInt(
    "canonical Anchor State becomes READY",
    (int)anchor_state,
    (int)TGK_GRID_LEVEL_READY);
  Tests.AssertFalse(
    "activation is cleared only after durable success",
    coordinator.HasPendingAnchorActivation());
  Tests.AssertTrue(
    "Anchor mapping query remains healthy",
    reducer.TryGetPositionMapping(true, -1, has_anchor_mapping));
  Tests.AssertFalse("activation creates no Anchor mapping", has_anchor_mapping);
  Tests.AssertEqualInt(
    "activation creates no Position Mapping",
    reducer.PositionCount(),
    0);

  bool repeated = adapter.RecordAnchorActivation(
    "UT_INSTANCE",
    "XAUUSD",
    710001,
    TGK_GRID_MODE_SELL,
    1,
    coordinator,
    reducer,
    port);
  Tests.AssertFalse("repeated SELL activation is rejected", repeated);
  Tests.AssertEqualInt("no duplicate journal append", port.call_count, 1);
  Tests.AssertEqualInt(
    "journal sequence unchanged by the repeat",
    (int)reducer.LastSequence(),
    (int)journal_sequence + 1);
  Tests.AssertEqualInt("no trade request was sent", port.send_count, 0);
  Tests.EndTest();
}

void SetCandidate(STGKGridEntryExecutionCandidate &candidate)
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

void SetAllowedResult(
  STGKGridEntryExecutionResult &policy_result,
  STGKGridEntryExecutionCandidate &candidate
)
{
  policy_result.decision = TGK_GRID_ENTRY_DECISION_ALLOW;
  policy_result.reason_code = TGK_GRID_ENTRY_REASON_ELIGIBLE;
  policy_result.target_level = candidate.target_level;
}

void RunSuccessfulBuy()
{
  Tests.BeginTest("E01 persists intent before sending BUY and result");
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionFakePort port;
  STGKGridEntryExecutionCandidate candidate;
  STGKGridEntryExecutionResult policy_result;
  STGKGridEntryExecutionOutcome outcome;
  SetCandidate(candidate);
  SetAllowedResult(policy_result, candidate);
  bool ready = InitializeReducer(reducer) && adapter.Initialize();
  bool executed = ready && adapter.Execute(
    candidate,
    0.01,
    policy_result,
    reducer,
    port,
    outcome);
  Tests.AssertTrue("fixture ready and Execute succeeds", executed);
  Tests.AssertEqualString("call order intent, trade, result", port.call_order, "ITR");
  Tests.AssertEqualInt("trade seam called once", port.send_count, 1);
  Tests.AssertTrue("accepted request requires reconciliation", outcome.requires_reconciliation);
  Tests.AssertEqualString("outcome is DONE", outcome.execution_outcome, "DONE");
  Tests.AssertTrue("reducer retains unresolved request", reducer.HasUnresolvedRequest());
  Tests.EndTest();
}

void RunPolicyRejectHasNoEffects()
{
  Tests.BeginTest("E02 policy rejection causes no persistence or trade");
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionFakePort port;
  STGKGridEntryExecutionCandidate candidate;
  STGKGridEntryExecutionResult policy_result;
  STGKGridEntryExecutionOutcome outcome;
  SetCandidate(candidate);
  SetAllowedResult(policy_result, candidate);
  policy_result.decision = TGK_GRID_ENTRY_DECISION_REJECT;
  policy_result.reason_code = TGK_GRID_ENTRY_REASON_EXECUTION_BLOCKED;
  bool ready = InitializeReducer(reducer) && adapter.Initialize();
  bool executed = ready && adapter.Execute(
    candidate,
    0.01,
    policy_result,
    reducer,
    port,
    outcome);
  Tests.AssertFalse("Execute rejects", executed);
  Tests.AssertEqualInt("no port calls", port.call_count, 0);
  Tests.AssertEqualInt("no trade calls", port.send_count, 0);
  Tests.EndTest();
}

void RunIntentPersistenceFailure()
{
  Tests.BeginTest("E03 failed intent persistence blocks trade and adapter");
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionFakePort port;
  STGKGridEntryExecutionCandidate candidate;
  STGKGridEntryExecutionResult policy_result;
  STGKGridEntryExecutionOutcome outcome;
  SetCandidate(candidate);
  SetAllowedResult(policy_result, candidate);
  port.fail_intent = true;
  bool ready = InitializeReducer(reducer) && adapter.Initialize();
  bool executed = ready && adapter.Execute(
    candidate,
    0.01,
    policy_result,
    reducer,
    port,
    outcome);
  Tests.AssertFalse("Execute fails closed", executed);
  Tests.AssertEqualInt("intent attempted once", port.call_count, 1);
  Tests.AssertEqualInt("trade not called", port.send_count, 0);
  Tests.AssertTrue("adapter requires recovery", outcome.recovery_required);
  Tests.AssertFalse("repeated call remains blocked", adapter.Execute(
    candidate,
    0.01,
    policy_result,
    reducer,
    port,
    outcome));
  Tests.AssertEqualInt("trade still not called", port.send_count, 0);
  Tests.EndTest();
}

void RunAcceptedTicketPrecision()
{
  Tests.BeginTest("E04 accepted result retains ticket decimal strings");
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionFakePort port;
  STGKGridEntryExecutionCandidate candidate;
  STGKGridEntryExecutionResult policy_result;
  STGKGridEntryExecutionOutcome outcome;
  SetCandidate(candidate);
  SetAllowedResult(policy_result, candidate);
  bool ready = InitializeReducer(reducer) && adapter.Initialize();
  bool executed = ready && adapter.Execute(
    candidate,
    0.01,
    policy_result,
    reducer,
    port,
    outcome);
  Tests.AssertTrue("Execute succeeds", executed);
  Tests.AssertEqualString(
    "order ticket kept as decimal string",
    outcome.order_ticket,
    "90071992547409931");
  Tests.AssertEqualString(
    "deal ticket kept as decimal string",
    outcome.deal_ticket,
    "90071992547409932");
  Tests.AssertEqualString(
    "request id uses next journal sequence",
    outcome.request_id,
    "UT_INSTANCE-REQ-2");
  Tests.AssertTrue(
    "Order Ticket remains exact in journal payload",
    StringFind(port.result_payload, "90071992547409931") >= 0);
  Tests.AssertTrue(
    "Deal Ticket remains exact in journal payload",
    StringFind(port.result_payload, "90071992547409932") >= 0);
  Tests.EndTest();
}

void RunDuplicateBlocked()
{
  Tests.BeginTest("E05 unresolved request prevents duplicate trade");
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionFakePort port;
  STGKGridEntryExecutionCandidate candidate;
  STGKGridEntryExecutionResult policy_result;
  STGKGridEntryExecutionOutcome outcome;
  SetCandidate(candidate);
  SetAllowedResult(policy_result, candidate);
  bool ready = InitializeReducer(reducer) && adapter.Initialize();
  bool first = ready && adapter.Execute(
    candidate,
    0.01,
    policy_result,
    reducer,
    port,
    outcome);
  bool second = first && adapter.Execute(
    candidate,
    0.01,
    policy_result,
    reducer,
    port,
    outcome);
  Tests.AssertTrue("first request succeeds", first);
  Tests.AssertFalse("second request rejected", second);
  Tests.AssertEqualInt("only one trade sent", port.send_count, 1);
  Tests.EndTest();
}

void RunMarketClosed()
{
  Tests.BeginTest("E06 MARKET_CLOSED resolves request without mapping");
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionFakePort port;
  STGKGridEntryExecutionCandidate candidate;
  STGKGridEntryExecutionResult policy_result;
  STGKGridEntryExecutionOutcome outcome;
  SetCandidate(candidate);
  SetAllowedResult(policy_result, candidate);
  port.retcode = TRADE_RETCODE_MARKET_CLOSED;
  bool ready = InitializeReducer(reducer) && adapter.Initialize();
  bool executed = ready && adapter.Execute(
    candidate,
    0.01,
    policy_result,
    reducer,
    port,
    outcome);
  Tests.AssertTrue("request is recorded", executed);
  Tests.AssertEqualString(
    "classified as MARKET_CLOSED",
    outcome.execution_outcome,
    "MARKET_CLOSED");
  Tests.AssertFalse("request is resolved", reducer.HasUnresolvedRequest());
  bool has_mapping = true;
  bool mapping_query_ok = reducer.TryGetPositionMapping(false, 0, has_mapping);
  Tests.AssertTrue("mapping query remains healthy", mapping_query_ok);
  Tests.AssertFalse("no position mapping created", has_mapping);
  Tests.AssertFalse("reconciliation not required", outcome.requires_reconciliation);
  Tests.EndTest();
}

void RunSendFailureCanRetryWithNewId()
{
  Tests.BeginTest("E07 failed trade request resolves and retry gets next ID");
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionFakePort port;
  STGKGridEntryExecutionCandidate candidate;
  STGKGridEntryExecutionResult policy_result;
  STGKGridEntryExecutionOutcome outcome;
  SetCandidate(candidate);
  SetAllowedResult(policy_result, candidate);
  port.send_return = false;
  bool ready = InitializeReducer(reducer) && adapter.Initialize();
  bool first = ready && adapter.Execute(
    candidate,
    0.01,
    policy_result,
    reducer,
    port,
    outcome);
  string first_request_id = outcome.request_id;
  string first_outcome = outcome.execution_outcome;
  port.send_return = true;
  bool second = first && adapter.Execute(
    candidate,
    0.01,
    policy_result,
    reducer,
    port,
    outcome);
  Tests.AssertTrue("failed trade result is persisted", first);
  Tests.AssertEqualString("first result is FAILED", first_outcome, "FAILED");
  Tests.AssertEqualString(
    "retry uses different ID",
    outcome.request_id == first_request_id ? "same-id" : "new-id",
    "new-id");
  Tests.AssertTrue("new request allowed after persisted failure", second);
  Tests.AssertEqualString(
    "retry ID advances monotonically",
    outcome.request_id,
    "UT_INSTANCE-REQ-4");
  Tests.EndTest();
}

void RunResultPersistenceFailure()
{
  Tests.BeginTest("E08 result persistence failure locks execution");
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionFakePort port;
  STGKGridEntryExecutionCandidate candidate;
  STGKGridEntryExecutionResult policy_result;
  STGKGridEntryExecutionOutcome outcome;
  SetCandidate(candidate);
  SetAllowedResult(policy_result, candidate);
  port.fail_result = true;
  bool ready = InitializeReducer(reducer) && adapter.Initialize();
  bool executed = ready && adapter.Execute(
    candidate,
    0.01,
    policy_result,
    reducer,
    port,
    outcome);
  Tests.AssertFalse("Execute reports persistence failure", executed);
  Tests.AssertEqualInt("trade was sent once", port.send_count, 1);
  Tests.AssertTrue("unresolved intent remains", reducer.HasUnresolvedRequest());
  Tests.AssertTrue("recovery flag is set", outcome.recovery_required);
  port.fail_result = false;
  Tests.AssertFalse("retry blocked until recovery", adapter.Execute(
    candidate,
    0.01,
    policy_result,
    reducer,
    port,
    outcome));
  Tests.AssertEqualInt("no duplicate trade", port.send_count, 1);
  Tests.EndTest();
}

void RunSellAndPayloadBoundary()
{
  Tests.BeginTest("E09 SELL uses mode and logical target metadata");
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionFakePort port;
  STGKGridEntryExecutionCandidate candidate;
  STGKGridEntryExecutionResult policy_result;
  STGKGridEntryExecutionOutcome outcome;
  SetCandidate(candidate);
  candidate.mode = TGK_GRID_MODE_SELL;
  candidate.target_level.is_anchor = true;
  candidate.target_level.level_index = -1;
  SetAllowedResult(policy_result, candidate);
  STGKGridMappingJournalRecord records[];
  ArrayResize(records, 1);
  records[0].sequence = 1;
  records[0].record_type = TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE;
  records[0].payload = "v1|RESET_COMMITTED|1|SELL|5.0|3960.0|4040.0|4000.0|17";
  bool initialized = reducer.Initialize("XAUUSD", 710001, "UT_INSTANCE") &&
                     reducer.Replay(records, 1) && adapter.Initialize();
  bool executed = initialized && adapter.Execute(
    candidate,
    0.01,
    policy_result,
    reducer,
    port,
    outcome);
  Tests.AssertTrue("SELL request succeeds", executed);
  Tests.AssertFalse("SELL direction sent", port.last_is_buy);
  Tests.AssertEqualString("chart symbol passed", port.last_symbol, "XAUUSD");
  Tests.AssertTrue(
    "comment remains readable metadata",
    StringFind(port.last_comment, "ANCHOR") >= 0);
  Tests.EndTest();
}

void RunInvalidVolume()
{
  Tests.BeginTest("E10 invalid volume causes no persistence or trade");
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionFakePort port;
  STGKGridEntryExecutionCandidate candidate;
  STGKGridEntryExecutionResult policy_result;
  STGKGridEntryExecutionOutcome outcome;
  SetCandidate(candidate);
  SetAllowedResult(policy_result, candidate);
  bool ready = InitializeReducer(reducer) && adapter.Initialize();
  bool executed = ready && adapter.Execute(
    candidate,
    0.0,
    policy_result,
    reducer,
    port,
    outcome);
  Tests.AssertFalse("invalid volume rejected", executed);
  Tests.AssertEqualInt("no persistence or trade", port.call_count + port.send_count, 0);
  Tests.EndTest();
}

void RunAcceptedPartialAndPlaced()
{
  Tests.BeginTest("E11 DONE_PARTIAL and PLACED remain unresolved");
  uint accepted_codes[2] =
  {
    TRADE_RETCODE_DONE_PARTIAL,
    TRADE_RETCODE_PLACED
  };
  string expected_outcomes[2] = {"DONE_PARTIAL", "PLACED"};
  for(int index = 0; index < 2; index++)
  {
    CTGKGridEntryMappingReducer reducer;
    CTGKGridEntryExecutionAdapter adapter;
    CTGKGridEntryExecutionFakePort port;
    STGKGridEntryExecutionCandidate candidate;
    STGKGridEntryExecutionResult policy_result;
    STGKGridEntryExecutionOutcome outcome;
    SetCandidate(candidate);
    SetAllowedResult(policy_result, candidate);
    port.retcode = accepted_codes[index];
    bool ready = InitializeReducer(reducer) && adapter.Initialize();
    bool executed = ready && adapter.Execute(
      candidate,
      0.01,
      policy_result,
      reducer,
      port,
      outcome);
    Tests.AssertTrue("accepted result recorded", executed);
    Tests.AssertEqualString(
      "accepted outcome classified",
      outcome.execution_outcome,
      expected_outcomes[index]);
    Tests.AssertTrue("reconciliation remains required", outcome.requires_reconciliation);
    Tests.AssertTrue("request remains unresolved", reducer.HasUnresolvedRequest());
  }
  Tests.EndTest();
}

void RunIdentityMismatch()
{
  Tests.BeginTest("E12 identity mismatch fails before persistence");
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionFakePort port;
  STGKGridEntryExecutionCandidate candidate;
  STGKGridEntryExecutionResult policy_result;
  STGKGridEntryExecutionOutcome outcome;
  SetCandidate(candidate);
  candidate.magic_number++;
  SetAllowedResult(policy_result, candidate);
  bool ready = InitializeReducer(reducer) && adapter.Initialize();
  bool executed = ready && adapter.Execute(
    candidate,
    0.01,
    policy_result,
    reducer,
    port,
    outcome);
  Tests.AssertFalse("Execute fails identity gate", executed);
  Tests.AssertEqualInt("no persistence or trade", port.call_count + port.send_count, 0);
  Tests.EndTest();
}

void RunJournalReducerSequenceMismatch()
{
  Tests.BeginTest("E13 journal sequence mismatch blocks trade after uncertain write");
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionFakePort port;
  STGKGridEntryExecutionCandidate candidate;
  STGKGridEntryExecutionResult policy_result;
  STGKGridEntryExecutionOutcome outcome;
  SetCandidate(candidate);
  SetAllowedResult(policy_result, candidate);
  bool ready = InitializeReducer(reducer) && adapter.Initialize();
  port.fail_intent = true;
  port.fail_intent_after_write = true;
  bool first = ready && adapter.Execute(
    candidate,
    0.01,
    policy_result,
    reducer,
    port,
    outcome);
  Tests.AssertFalse("uncertain Intent write reports failure", first);
  Tests.AssertTrue("recovery is required", outcome.recovery_required);
  port.fail_intent = false;
  bool reinitialized = adapter.Initialize();
  bool retry = reinitialized && adapter.Execute(
    candidate,
    0.01,
    policy_result,
    reducer,
    port,
    outcome);
  Tests.AssertFalse("journal and stale reducer mismatch blocks retry", retry);
  Tests.AssertEqualInt("no second append or trade", port.call_count + port.send_count, 1);
  Tests.AssertEqualInt("trade never sent", port.send_count, 0);
  Tests.EndTest();
}

int OnInit()
{
  Tests.BeginSuite("Grid Entry Execution Adapter");
  RunSuccessfulBuy();
  RunPolicyRejectHasNoEffects();
  RunIntentPersistenceFailure();
  RunAcceptedTicketPrecision();
  RunDuplicateBlocked();
  RunMarketClosed();
  RunSendFailureCanRetryWithNewId();
  RunResultPersistenceFailure();
  RunSellAndPayloadBoundary();
  RunInvalidVolume();
  RunAcceptedPartialAndPlaced();
  RunIdentityMismatch();
  RunJournalReducerSequenceMismatch();
  RunAnchorActivationPersistence();
  RunAnchorActivationPersistenceFailure();
  RunAnchorActivationRejectedWhenCanonicalReady();
  RunAnchorActivationRejectedWhenMappingExists();
  RunAnchorActivationValidControl();
  RunAnchorActivationDuplicateRejected();
  RunSellAnchorActivationPersistence();
  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick() {}
