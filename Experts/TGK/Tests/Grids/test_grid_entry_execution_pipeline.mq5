#property strict
#property version "1.00"
#property description "Grid Entry Pipeline tests; fake port only, no trading."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridEntryExecutionPipeline.mqh>

CTGKTestRunner Tests;

class CTGKGridEntryPipelineFakePort : public ITGKGridEntryExecutionPort
{
public:
  long next_sequence;
  bool fail_intent;
  bool fail_result;
  bool send_return;
  uint retcode;
  string order_ticket;
  string deal_ticket;
  int intent_count;
  int result_count;
  int send_count;

  CTGKGridEntryPipelineFakePort()
  {
    next_sequence = 2;
    fail_intent = false;
    fail_result = false;
    send_return = true;
    retcode = TRADE_RETCODE_DONE;
    order_ticket = "90071992547409931";
    deal_ticket = "90071992547409932";
    intent_count = 0;
    result_count = 0;
    send_count = 0;
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
    if(record_type == TGK_GRID_MAPPING_RECORD_ENTRY_INTENT)
    {
      intent_count++;
      if(fail_intent)
        return false;
    }
    else
    {
      result_count++;
      if(fail_result)
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
    result_retcode = retcode;
    order_ticket_result = order_ticket;
    deal_ticket_result = deal_ticket;
    return send_return;
  }
};

bool InitializeFixture(
  CTGKGridLevelRuntimeCoordinator &coordinator,
  CTGKGridEntryMappingReducer &reducer,
  STGKGridLevelCandidate &grid_candidate,
  STGKGridEntryExecutionCandidate &execution_candidate
)
{
  if(!coordinator.Initialize(
    TGK_GRID_MODE_BUY,
    4000.0,
    5.0,
    3960.0,
    4040.0,
    16,
    "XAUUSD",
    710001,
    3995.0,
    3996.0) ||
     !coordinator.BindConfigEpoch(1))
    return false;

  ENUM_TGK_GRID_COORDINATOR_RESULT coordinator_result;
  if(coordinator.UpdatePrice(
    3994.0,
    3995.0,
    coordinator_result,
    grid_candidate) != TGK_GRID_COORDINATOR_CANDIDATE_READY)
    return false;

  execution_candidate.instance_id = "UT_INSTANCE";
  execution_candidate.symbol = "XAUUSD";
  execution_candidate.magic_number = 710001;
  execution_candidate.mode = TGK_GRID_MODE_BUY;
  execution_candidate.config_epoch = 1;
  execution_candidate.target_level.is_anchor = grid_candidate.is_anchor;
  execution_candidate.target_level.level_index = grid_candidate.level_index;
  execution_candidate.entry_price = grid_candidate.level_price;

  STGKGridMappingJournalRecord records[];
  ArrayResize(records, 1);
  records[0].sequence = 1;
  records[0].record_type = TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE;
  records[0].payload =
    "v1|RESET_COMMITTED|1|BUY|5.0|3960.0|4040.0|4000.0|17";
  return reducer.Initialize("XAUUSD", 710001, "UT_INSTANCE") &&
         reducer.Replay(records, ArraySize(records));
}

void RunAcceptedRequestRemainsUnresolved()
{
  Tests.BeginTest("P01 accepted request persists and waits for reconciliation");
  CTGKGridLevelRuntimeCoordinator coordinator;
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionPipeline pipeline;
  CTGKGridEntryPipelineFakePort port;
  STGKGridLevelCandidate grid_candidate;
  STGKGridEntryExecutionCandidate execution_candidate;
  STGKGridEntryPipelineOutcome outcome;

  bool ready = InitializeFixture(
    coordinator,
    reducer,
    grid_candidate,
    execution_candidate) &&
    adapter.Initialize() &&
    pipeline.Initialize();
  bool processed = ready && pipeline.ProcessCandidate(
    grid_candidate,
    execution_candidate,
    0.01,
    TGK_GRID_ENTRY_EXECUTION_NORMAL,
    coordinator,
    reducer,
    adapter,
    port,
    outcome);

  Tests.AssertTrue("fixture and accepted candidate processed", processed);
  Tests.AssertEqualInt("intent persisted once", port.intent_count, 1);
  Tests.AssertEqualInt("fake send called once", port.send_count, 1);
  Tests.AssertEqualInt("result persisted once", port.result_count, 1);
  Tests.AssertTrue("coordinator holds unresolved request",
    coordinator.IsRequestUnresolved());
  Tests.AssertTrue("reducer holds unresolved request",
    reducer.HasUnresolvedRequest());
  Tests.AssertEqualString("large deal ticket stays exact decimal string",
    outcome.execution_outcome.deal_ticket,
    "90071992547409932");
  Tests.AssertTrue("accepted result requires reconciliation",
    outcome.execution_outcome.requires_reconciliation);
  Tests.AssertEqualInt("Position Mapping waits for reconciliation",
    reducer.PositionCount(), 0);
  ENUM_TGK_GRID_LEVEL_STATE level_state;
  bool state_read = coordinator.GetLevelState(
    grid_candidate.level_index,
    level_state);
  Tests.AssertTrue("Level is not ACTIVE before reconciliation",
    state_read && level_state != TGK_GRID_LEVEL_ACTIVE);
  STGKGridLevelCandidate deferred_candidate;
  ENUM_TGK_GRID_COORDINATOR_RESULT deferred_result;
  ENUM_TGK_GRID_COORDINATOR_RESULT tick_result = coordinator.UpdatePrice(
    3993.0,
    3994.0,
    deferred_result,
    deferred_candidate);
  Tests.AssertEqualInt("new price is blocked by unresolved request",
    (int)tick_result, (int)TGK_GRID_COORDINATOR_REQUEST_UNRESOLVED);
  Tests.AssertEqualInt("no duplicate execution on next price check",
    port.send_count, 1);
  Tests.EndTest();
}

void RunPolicyRejectDoesNotSend()
{
  Tests.BeginTest("P02 recovery error blocks adapter and trade seam");
  CTGKGridLevelRuntimeCoordinator coordinator;
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionPipeline pipeline;
  CTGKGridEntryPipelineFakePort port;
  STGKGridLevelCandidate grid_candidate;
  STGKGridEntryExecutionCandidate execution_candidate;
  STGKGridEntryPipelineOutcome outcome;

  bool ready = InitializeFixture(
    coordinator,
    reducer,
    grid_candidate,
    execution_candidate) &&
    adapter.Initialize() &&
    pipeline.Initialize();
  bool processed = ready && pipeline.ProcessCandidate(
    grid_candidate,
    execution_candidate,
    0.01,
    TGK_GRID_ENTRY_EXECUTION_RECOVERY_ERROR,
    coordinator,
    reducer,
    adapter,
    port,
    outcome);

  Tests.AssertTrue("policy rejection is handled", processed);
  Tests.AssertTrue("policy evaluated and denied",
    outcome.policy_evaluated && !outcome.policy_allowed);
  Tests.AssertEqualInt("no intent on policy reject", port.intent_count, 0);
  Tests.AssertEqualInt("no fake trade request on policy reject",
    port.send_count, 0);
  Tests.AssertTrue("rejected offer cleared from coordinator",
    !coordinator.IsRequestUnresolved());
  Tests.EndTest();
}

void RunIntentFailureLocksCoordinator()
{
  Tests.BeginTest("P05 uncertain intent persistence locks future entries");
  CTGKGridLevelRuntimeCoordinator coordinator;
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionPipeline pipeline;
  CTGKGridEntryPipelineFakePort port;
  STGKGridLevelCandidate grid_candidate;
  STGKGridEntryExecutionCandidate execution_candidate;
  STGKGridEntryPipelineOutcome outcome;
  port.fail_intent = true;

  bool ready = InitializeFixture(
    coordinator,
    reducer,
    grid_candidate,
    execution_candidate) &&
    adapter.Initialize() &&
    pipeline.Initialize();
  bool processed = ready && pipeline.ProcessCandidate(
    grid_candidate,
    execution_candidate,
    0.01,
    TGK_GRID_ENTRY_EXECUTION_NORMAL,
    coordinator,
    reducer,
    adapter,
    port,
    outcome);

  Tests.AssertTrue("uncertain execution returns failure", !processed);
  Tests.AssertEqualInt("no fake trade after intent failure",
    port.send_count, 0);
  Tests.AssertTrue("Coordinator blocks duplicate request",
    coordinator.IsRequestUnresolved());
  Tests.AssertTrue("Pipeline stays fail-closed",
    pipeline.IsRecoveryRequired());
  Tests.EndTest();
}

void RunMismatchedTargetDoesNotMutate()
{
  Tests.BeginTest("P03 mismatched target does not reach execution");
  CTGKGridLevelRuntimeCoordinator coordinator;
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionPipeline pipeline;
  CTGKGridEntryPipelineFakePort port;
  STGKGridLevelCandidate grid_candidate;
  STGKGridEntryExecutionCandidate execution_candidate;
  STGKGridEntryPipelineOutcome outcome;

  bool ready = InitializeFixture(
    coordinator,
    reducer,
    grid_candidate,
    execution_candidate) &&
    adapter.Initialize() &&
    pipeline.Initialize();
  execution_candidate.target_level.level_index++;
  bool processed = ready && pipeline.ProcessCandidate(
    grid_candidate,
    execution_candidate,
    0.01,
    TGK_GRID_ENTRY_EXECUTION_NORMAL,
    coordinator,
    reducer,
    adapter,
    port,
    outcome);

  Tests.AssertTrue("mismatch is rejected", !processed);
  Tests.AssertEqualInt("no intent on target mismatch", port.intent_count, 0);
  Tests.AssertEqualInt("no trade on target mismatch", port.send_count, 0);
  Tests.EndTest();
}

void RunStaleConfigDoesNotExecute()
{
  Tests.BeginTest("P04 stale config epoch fails before policy or execution");
  CTGKGridLevelRuntimeCoordinator coordinator;
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionPipeline pipeline;
  CTGKGridEntryPipelineFakePort port;
  STGKGridLevelCandidate grid_candidate;
  STGKGridEntryExecutionCandidate execution_candidate;
  STGKGridEntryPipelineOutcome outcome;

  bool ready = InitializeFixture(
    coordinator,
    reducer,
    grid_candidate,
    execution_candidate) &&
    adapter.Initialize() &&
    pipeline.Initialize();
  execution_candidate.config_epoch++;
  bool processed = ready && pipeline.ProcessCandidate(
    grid_candidate,
    execution_candidate,
    0.01,
    TGK_GRID_ENTRY_EXECUTION_NORMAL,
    coordinator,
    reducer,
    adapter,
    port,
    outcome);

  Tests.AssertTrue("stale candidate fails closed", !processed);
  Tests.AssertTrue("Policy was not reached",
    !outcome.policy_evaluated);
  Tests.AssertEqualInt("no Intent on stale Config Epoch",
    port.intent_count, 0);
  Tests.AssertEqualInt("no execution request on stale Config Epoch",
    port.send_count, 0);
  Tests.EndTest();
}

void RunResultFailureKeepsRequestLocked()
{
  Tests.BeginTest("P07 result persistence failure prevents duplicate entry");
  CTGKGridLevelRuntimeCoordinator coordinator;
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionPipeline pipeline;
  CTGKGridEntryPipelineFakePort port;
  STGKGridLevelCandidate grid_candidate;
  STGKGridEntryExecutionCandidate execution_candidate;
  STGKGridEntryPipelineOutcome outcome;
  port.fail_result = true;

  bool ready = InitializeFixture(
    coordinator,
    reducer,
    grid_candidate,
    execution_candidate) &&
    adapter.Initialize() &&
    pipeline.Initialize();
  bool processed = ready && pipeline.ProcessCandidate(
    grid_candidate,
    execution_candidate,
    0.01,
    TGK_GRID_ENTRY_EXECUTION_NORMAL,
    coordinator,
    reducer,
    adapter,
    port,
    outcome);

  Tests.AssertTrue("result persistence failure is surfaced", !processed);
  Tests.AssertEqualInt("request was sent once before result write failure",
    port.send_count, 1);
  Tests.AssertTrue("Coordinator locks unresolved request",
    coordinator.IsRequestUnresolved());
  Tests.AssertTrue("Reducer retains persisted Intent unresolved",
    reducer.HasUnresolvedRequest());
  Tests.AssertTrue("Pipeline enters recovery-required state",
    pipeline.IsRecoveryRequired());
  Tests.EndTest();
}

void RunMarketClosedReleasesCandidate()
{
  Tests.BeginTest("P06 terminal market rejection releases offered candidate");
  CTGKGridLevelRuntimeCoordinator coordinator;
  CTGKGridEntryMappingReducer reducer;
  CTGKGridEntryExecutionAdapter adapter;
  CTGKGridEntryExecutionPipeline pipeline;
  CTGKGridEntryPipelineFakePort port;
  STGKGridLevelCandidate grid_candidate;
  STGKGridEntryExecutionCandidate execution_candidate;
  STGKGridEntryPipelineOutcome outcome;
  port.retcode = TRADE_RETCODE_MARKET_CLOSED;

  bool ready = InitializeFixture(
    coordinator,
    reducer,
    grid_candidate,
    execution_candidate) &&
    adapter.Initialize() &&
    pipeline.Initialize();
  bool processed = ready && pipeline.ProcessCandidate(
    grid_candidate,
    execution_candidate,
    0.01,
    TGK_GRID_ENTRY_EXECUTION_NORMAL,
    coordinator,
    reducer,
    adapter,
    port,
    outcome);

  Tests.AssertTrue("terminal rejection is safely recorded", processed);
  Tests.AssertEqualString("market-closed outcome",
    outcome.execution_outcome.execution_outcome,
    "MARKET_CLOSED");
  Tests.AssertTrue("Coordinator does not retain unresolved request",
    !coordinator.IsRequestUnresolved());
  Tests.AssertTrue("Reducer does not retain unresolved request",
    !reducer.HasUnresolvedRequest());
  Tests.EndTest();
}

int OnInit()
{
  Tests.BeginSuite("Grid Entry Execution Pipeline");
  RunAcceptedRequestRemainsUnresolved();
  RunPolicyRejectDoesNotSend();
  RunIntentFailureLocksCoordinator();
  RunMismatchedTargetDoesNotMutate();
  RunStaleConfigDoesNotExecute();
  RunResultFailureKeepsRequestLocked();
  RunMarketClosedReleasesCandidate();
  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
}
