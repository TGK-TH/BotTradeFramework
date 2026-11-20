#ifndef BOTTRADE_GRID_ENTRY_EXECUTION_PIPELINE_MQH
#define BOTTRADE_GRID_ENTRY_EXECUTION_PIPELINE_MQH

#include <BotTrade/Grid/GridEntryExecutionAdapter.mqh>
#include <BotTrade/Grid/GridEntryExecutionResolver.mqh>

struct STGKGridEntryPipelineOutcome
{
  bool handled;
  bool policy_evaluated;
  bool policy_allowed;
  bool adapter_called;
  bool coordinator_updated;
  bool recovery_required;
  STGKGridEntryExecutionResult policy_result;
  STGKGridEntryExecutionOutcome execution_outcome;
};

// Orchestrates an already offered Coordinator candidate through fresh
// resolution, policy, durable entry execution, and Coordinator request state.
class CTGKGridEntryExecutionPipeline
{
private:
  CTGKGridEntryExecutionCaller m_caller;
  bool m_recovery_required;

  void ResetOutcome(STGKGridEntryPipelineOutcome &outcome)
  {
    outcome.handled = false;
    outcome.policy_evaluated = false;
    outcome.policy_allowed = false;
    outcome.adapter_called = false;
    outcome.coordinator_updated = false;
    outcome.recovery_required = false;
    outcome.policy_result.decision = TGK_GRID_ENTRY_DECISION_REJECT;
    outcome.policy_result.reason_code =
      TGK_GRID_ENTRY_REASON_INVALID_CANDIDATE;
    outcome.policy_result.target_level.is_anchor = false;
    outcome.policy_result.target_level.level_index = -1;
    outcome.execution_outcome.request_id = "";
    outcome.execution_outcome.execution_outcome = "";
    outcome.execution_outcome.order_ticket = "0";
    outcome.execution_outcome.deal_ticket = "0";
    outcome.execution_outcome.retcode = 0;
    outcome.execution_outcome.trade_return = false;
    outcome.execution_outcome.requires_reconciliation = false;
    outcome.execution_outcome.recovery_required = false;
    outcome.execution_outcome.status =
      TGK_GRID_ENTRY_EXECUTION_STATUS_NOT_SENT;
  }

  bool RecordCoordinatorResult(
    STGKGridLevelCandidate &grid_candidate,
    bool request_accepted,
    CTGKGridLevelRuntimeCoordinator &coordinator,
    STGKGridEntryPipelineOutcome &outcome
  )
  {
    ENUM_TGK_GRID_ENTRY_REQUEST_RESULT request_result =
      request_accepted
      ? TGK_GRID_ENTRY_REQUEST_ACCEPTED
      : TGK_GRID_ENTRY_REQUEST_FAILED;
    if(!coordinator.RecordEntryRequest(grid_candidate, request_result))
    {
      m_recovery_required = true;
      outcome.recovery_required = true;
      return false;
    }

    outcome.coordinator_updated = true;
    return true;
  }

public:
  CTGKGridEntryExecutionPipeline()
  {
    m_recovery_required = false;
  }

  bool Initialize()
  {
    m_recovery_required = false;
    return true;
  }

  bool IsRecoveryRequired()
  {
    return m_recovery_required;
  }

  // grid_candidate must be the exact candidate returned by Coordinator;
  // execution_candidate carries the matching identity/config provenance.
  bool ProcessCandidate(
    STGKGridLevelCandidate &grid_candidate,
    const STGKGridEntryExecutionCandidate &execution_candidate,
    double requested_volume,
    ENUM_TGK_GRID_ENTRY_EXECUTION_STATE execution_state,
    CTGKGridLevelRuntimeCoordinator &coordinator,
    CTGKGridEntryMappingReducer &reducer,
    CTGKGridEntryExecutionAdapter &adapter,
    ITGKGridEntryExecutionPort &port,
    STGKGridEntryPipelineOutcome &outcome
  )
  {
    ResetOutcome(outcome);
    if(!m_recovery_required &&
       ((grid_candidate.is_anchor &&
         grid_candidate.level_index == -1 &&
         execution_candidate.target_level.is_anchor &&
         execution_candidate.target_level.level_index == -1) ||
        (!grid_candidate.is_anchor &&
         grid_candidate.level_index >= 0 &&
         !execution_candidate.target_level.is_anchor &&
         execution_candidate.target_level.level_index ==
           grid_candidate.level_index)) &&
       grid_candidate.level_price == execution_candidate.entry_price)
    {
      if(!m_caller.Evaluate(
        execution_candidate,
        coordinator,
        reducer,
        execution_state,
        outcome.policy_result))
        return false;

      outcome.policy_evaluated = true;
      outcome.policy_allowed =
        outcome.policy_result.decision == TGK_GRID_ENTRY_DECISION_ALLOW &&
        outcome.policy_result.reason_code == TGK_GRID_ENTRY_REASON_ELIGIBLE;
      if(!outcome.policy_allowed)
      {
        if(!RecordCoordinatorResult(
          grid_candidate,
          false,
          coordinator,
          outcome))
          return false;

        outcome.handled = true;
        return true;
      }

      outcome.adapter_called = true;
      bool executed = adapter.Execute(
        execution_candidate,
        requested_volume,
        outcome.policy_result,
        reducer,
        port,
        outcome.execution_outcome);

      bool request_accepted =
        outcome.execution_outcome.requires_reconciliation ||
        outcome.execution_outcome.recovery_required;
      if(!RecordCoordinatorResult(
        grid_candidate,
        request_accepted,
        coordinator,
        outcome))
        return false;

      if(outcome.execution_outcome.recovery_required)
      {
        m_recovery_required = true;
        outcome.recovery_required = true;
      }

      outcome.handled = executed;
      return executed;
    }

    return false;
  }
};

#endif
