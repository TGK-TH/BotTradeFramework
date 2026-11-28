#ifndef BOTTRADE_GRID_ENTRY_EXECUTION_POLICY_MQH
#define BOTTRADE_GRID_ENTRY_EXECUTION_POLICY_MQH

#include <BotTrade/Grid/GridTypes.mqh>

enum ENUM_TGK_GRID_ENTRY_DECISION
{
  TGK_GRID_ENTRY_DECISION_ALLOW = 0,
  TGK_GRID_ENTRY_DECISION_REJECT = 1
};

enum ENUM_TGK_GRID_ENTRY_REASON
{
  TGK_GRID_ENTRY_REASON_INVALID_CANDIDATE = 0,
  TGK_GRID_ENTRY_REASON_IDENTITY_MISMATCH = 1,
  TGK_GRID_ENTRY_REASON_EXECUTION_BLOCKED = 2,
  TGK_GRID_ENTRY_REASON_UNRESOLVED_REQUEST = 3,
  TGK_GRID_ENTRY_REASON_LEVEL_NOT_FOUND = 4,
  TGK_GRID_ENTRY_REASON_LEVEL_NOT_ELIGIBLE = 5,
  TGK_GRID_ENTRY_REASON_ALREADY_MAPPED = 6,
  TGK_GRID_ENTRY_REASON_ELIGIBLE = 7
};

enum ENUM_TGK_GRID_ENTRY_EXECUTION_STATE
{
  TGK_GRID_ENTRY_EXECUTION_NORMAL = 0,
  TGK_GRID_ENTRY_EXECUTION_MAINTENANCE_ERROR = 1,
  TGK_GRID_ENTRY_EXECUTION_RECOVERY_ERROR = 2
};

struct STGKGridEntryTargetLevel
{
  bool is_anchor;
  int level_index;
};

struct STGKGridEntryExecutionCandidate
{
  string instance_id;
  string symbol;
  long magic_number;
  ENUM_TGK_GRID_MODE mode;
  long config_epoch;
  STGKGridEntryTargetLevel target_level;
  double entry_price;
};

struct STGKGridEntryExecutionLevelContext
{
  bool level_exists;
  ENUM_TGK_GRID_LEVEL_STATE level_state;
  bool has_position_mapping;
};

struct STGKGridEntryExecutionContext
{
  bool has_unresolved_request;
  bool identity_valid;
  ENUM_TGK_GRID_ENTRY_EXECUTION_STATE execution_state;
};

struct STGKGridEntryExecutionResult
{
  ENUM_TGK_GRID_ENTRY_DECISION decision;
  ENUM_TGK_GRID_ENTRY_REASON reason_code;
  STGKGridEntryTargetLevel target_level;
};

class CTGKGridEntryExecutionPolicy
{
private:
  bool IsCandidateValid(
    const STGKGridEntryExecutionCandidate &candidate
  )
  {
    if(candidate.instance_id == "" ||
       candidate.symbol == "" ||
       candidate.magic_number <= 0 ||
       (candidate.mode != TGK_GRID_MODE_BUY &&
        candidate.mode != TGK_GRID_MODE_SELL) ||
       candidate.config_epoch <= 0)
      return false;

    if(candidate.target_level.is_anchor)
    {
      if(candidate.target_level.level_index != -1)
        return false;
    }
    else if(candidate.target_level.level_index < 0)
    {
      return false;
    }

    return MathIsValidNumber(candidate.entry_price) &&
           candidate.entry_price > 0.0;
  }

  void SetResult(
    const STGKGridEntryExecutionCandidate &candidate,
    ENUM_TGK_GRID_ENTRY_DECISION decision,
    ENUM_TGK_GRID_ENTRY_REASON reason_code,
    STGKGridEntryExecutionResult &result
  )
  {
    result.decision = decision;
    result.reason_code = reason_code;
    result.target_level.is_anchor = candidate.target_level.is_anchor;
    result.target_level.level_index = candidate.target_level.level_index;
  }

public:
  void Evaluate(
    const STGKGridEntryExecutionCandidate &candidate,
    const STGKGridEntryExecutionLevelContext &level_context,
    const STGKGridEntryExecutionContext &execution_context,
    STGKGridEntryExecutionResult &result
  )
  {
    if(!IsCandidateValid(candidate))
    {
      SetResult(
        candidate,
        TGK_GRID_ENTRY_DECISION_REJECT,
        TGK_GRID_ENTRY_REASON_INVALID_CANDIDATE,
        result);
      return;
    }

    if(!execution_context.identity_valid)
    {
      SetResult(
        candidate,
        TGK_GRID_ENTRY_DECISION_REJECT,
        TGK_GRID_ENTRY_REASON_IDENTITY_MISMATCH,
        result);
      return;
    }

    if(execution_context.execution_state != TGK_GRID_ENTRY_EXECUTION_NORMAL)
    {
      SetResult(
        candidate,
        TGK_GRID_ENTRY_DECISION_REJECT,
        TGK_GRID_ENTRY_REASON_EXECUTION_BLOCKED,
        result);
      return;
    }

    if(execution_context.has_unresolved_request)
    {
      SetResult(
        candidate,
        TGK_GRID_ENTRY_DECISION_REJECT,
        TGK_GRID_ENTRY_REASON_UNRESOLVED_REQUEST,
        result);
      return;
    }

    if(!level_context.level_exists)
    {
      SetResult(
        candidate,
        TGK_GRID_ENTRY_DECISION_REJECT,
        TGK_GRID_ENTRY_REASON_LEVEL_NOT_FOUND,
        result);
      return;
    }

    if(TGKGridNormalizeLevelState(level_context.level_state) !=
       TGK_GRID_LEVEL_READY)
    {
      SetResult(
        candidate,
        TGK_GRID_ENTRY_DECISION_REJECT,
        TGK_GRID_ENTRY_REASON_LEVEL_NOT_ELIGIBLE,
        result);
      return;
    }

    if(level_context.has_position_mapping)
    {
      SetResult(
        candidate,
        TGK_GRID_ENTRY_DECISION_REJECT,
        TGK_GRID_ENTRY_REASON_ALREADY_MAPPED,
        result);
      return;
    }

    SetResult(
      candidate,
      TGK_GRID_ENTRY_DECISION_ALLOW,
      TGK_GRID_ENTRY_REASON_ELIGIBLE,
      result);
  }
};

#endif
