#ifndef BOTTRADE_GRID_ENTRY_EXECUTION_RESOLVER_MQH
#define BOTTRADE_GRID_ENTRY_EXECUTION_RESOLVER_MQH

#include <BotTrade/Grid/GridEntryExecutionPolicy.mqh>
#include <BotTrade/Grid/GridEntryMappingReducer.mqh>
#include <BotTrade/Grid/GridLevelRuntimeCoordinator.mqh>

// Resolves fresh level and mapping context from the Candidate's exact
// Instance/Target key. A failed resolve must not be passed to the Policy.
class CTGKGridEntryExecutionResolver
{
public:
  bool Resolve(
    const STGKGridEntryExecutionCandidate &candidate,
    CTGKGridLevelRuntimeCoordinator &coordinator,
    CTGKGridEntryMappingReducer &reducer,
    STGKGridEntryExecutionLevelContext &level_context
  )
  {
    if(!reducer.MatchesContext(
      candidate.instance_id,
      candidate.symbol,
      candidate.magic_number,
      candidate.mode,
      candidate.config_epoch) ||
       !coordinator.MatchesGridContext(
         candidate.symbol,
         candidate.magic_number,
         candidate.mode,
         candidate.config_epoch))
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

    ENUM_TGK_GRID_LEVEL_STATE level_state;
    if(candidate.target_level.is_anchor)
      level_state = coordinator.GetAnchorState();
    else if(!coordinator.GetLevelState(
      candidate.target_level.level_index,
      level_state))
      return false;

    bool has_position_mapping = false;
    if(!reducer.TryGetPositionMapping(
      candidate.target_level.is_anchor,
      candidate.target_level.level_index,
      has_position_mapping))
      return false;

    if(!candidate.target_level.is_anchor &&
       reducer.LevelStateAt(candidate.target_level.level_index) !=
       (int)level_state)
      return false;

    // ACTIVE and mapped must agree for both Anchor and normal Levels.
    if((level_state == TGK_GRID_LEVEL_ACTIVE) != has_position_mapping)
      return false;

    level_context.level_exists = true;
    level_context.level_state = level_state;
    level_context.has_position_mapping = has_position_mapping;
    return true;
  }
};

// Couples Resolver and Policy. Returns false on resolution failure and leaves
// result untouched; otherwise Policy evaluates the freshly resolved inputs.
class CTGKGridEntryExecutionCaller
{
private:
  CTGKGridEntryExecutionResolver m_resolver;
  CTGKGridEntryExecutionPolicy m_policy;

public:
  bool Evaluate(
    const STGKGridEntryExecutionCandidate &candidate,
    CTGKGridLevelRuntimeCoordinator &coordinator,
    CTGKGridEntryMappingReducer &reducer,
    ENUM_TGK_GRID_ENTRY_EXECUTION_STATE execution_state,
    STGKGridEntryExecutionResult &result
  )
  {
    STGKGridEntryExecutionLevelContext level_context;
    if(!m_resolver.Resolve(
      candidate,
      coordinator,
      reducer,
      level_context))
      return false;

    bool coordinator_has_unresolved = coordinator.IsRequestUnresolved();
    bool reducer_has_unresolved = reducer.HasUnresolvedRequest();
    if(coordinator_has_unresolved != reducer_has_unresolved)
      return false;

    STGKGridEntryExecutionContext execution_context;
    execution_context.has_unresolved_request = reducer_has_unresolved;
    execution_context.identity_valid = true;
    execution_context.execution_state = execution_state;

    m_policy.Evaluate(
      candidate,
      level_context,
      execution_context,
      result);
    return true;
  }
};

#endif
