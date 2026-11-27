#ifndef BOTTRADE_GRID_LEVEL_RUNTIME_COORDINATOR_MQH
#define BOTTRADE_GRID_LEVEL_RUNTIME_COORDINATOR_MQH

#include <BotTrade/Grid/GridLevelEngine.mqh>
#include <BotTrade/Grid/GridEntryMappingReducer.mqh>

// Public outcome from one coordinator operation.
enum ENUM_TGK_GRID_COORDINATOR_RESULT
{
  TGK_GRID_COORDINATOR_ERROR = 0,
  TGK_GRID_COORDINATOR_NO_CANDIDATE,
  TGK_GRID_COORDINATOR_CANDIDATE_READY,
  TGK_GRID_COORDINATOR_REQUEST_UNRESOLVED
};

enum ENUM_TGK_GRID_ENTRY_REQUEST_RESULT
{
  TGK_GRID_ENTRY_REQUEST_FAILED = 0,
  TGK_GRID_ENTRY_REQUEST_ACCEPTED
};

enum ENUM_TGK_GRID_ENTRY_RESOLUTION
{
  TGK_GRID_ENTRY_RESOLUTION_PENDING = 0,
  TGK_GRID_ENTRY_RESOLUTION_TERMINAL_NO_POSITION_NO_ORDER
};

// Integration Layer must provide explicit mapping. The Coordinator never
// infers a Level from an approximate fill price.
// The Identifier is the canonical logical Position identity; the Ticket is
// only its current operational handle.
struct STGKGridLevelPositionRecord
{
  ulong ticket;
  string symbol;
  long magic_number;
  bool is_anchor;
  int level_index;
  double volume;
  string position_identifier;
};

// Full Close is keyed by the logical mapping only. Close reason, close price
// and Deal History are not part of the Grid state transition contract.
struct STGKGridLevelCloseEvent
{
  bool is_anchor;
  int level_index;
};

// Persisted state of one normal Level handed to Runtime Hydration. The array
// must cover every Engine Level exactly once.
struct STGKGridLevelStateHydration
{
  int level_index;
  ENUM_TGK_GRID_LEVEL_STATE state;
};

// The single unresolved Entry Request persisted by the Reducer. It is restored
// as pending evidence only; it never creates a Mapping or an ACTIVE Level.
struct STGKGridEntryRequestHydration
{
  bool present;
  string request_id;
  bool is_anchor;
  int level_index;
  double requested_volume;
};

// Proof of the Latest Accepted Complete/Stable Live Position Snapshot handed
// to the explicit Reconciliation Gate release. It carries the Instance
// identity, the committed configuration context and the Snapshot freshness
// tokens, so a release can never be inferred from the Snapshot alone.
struct STGKGridReconciliationGateProof
{
  string instance_id;
  string symbol;
  long magic_number;
  ENUM_TGK_GRID_MODE mode;
  long config_epoch;
  long snapshot_generation;
  long base_sequence;
};

// Runtime Restore outcome. A hydrated Runtime starts in
// PENDING_RECONCILIATION and keeps the Candidate/Entry gate closed until a
// Complete/Stable Live Position Snapshot confirms ownership.
enum ENUM_TGK_GRID_RUNTIME_RESTORE_STATUS
{
  TGK_GRID_RUNTIME_RESTORE_NONE = 0,
  TGK_GRID_RUNTIME_RESTORE_PENDING_RECONCILIATION,
  TGK_GRID_RUNTIME_RESTORE_ERROR
};

struct STGKGridLevelCandidate
{
  bool is_anchor;
  int level_index;
  double level_price;
};

class CTGKGridLevelRuntimeCoordinator
{
private:
  CTGKGridLevelEngine m_engine;
  ENUM_TGK_GRID_MODE m_mode;
  string m_symbol;
  long m_magic_number;
  long m_config_epoch;
  string m_instance_id;
  double m_previous_bid;
  double m_previous_ask;
  double m_current_bid;
  double m_current_ask;
  bool m_anchor_activation_pending;
  bool m_initialized;

  bool m_candidate_offered;
  STGKGridLevelCandidate m_offered_candidate;

  bool m_request_unresolved;
  STGKGridLevelCandidate m_pending_candidate;

  bool m_has_deferred_candidate;
  STGKGridLevelCandidate m_deferred_candidate;

  ENUM_TGK_GRID_RUNTIME_RESTORE_STATUS m_restore_status;
  bool m_reconciliation_pending;
  long m_released_snapshot_generation;
  long m_released_base_sequence;
  string m_pending_request_id;
  double m_pending_request_volume;

  STGKGridLevelPositionRecord m_positions[];

  // Check whether the Bid and Ask prices are valid and make sense.
  bool IsValidQuote(double bid, double ask)
  {
    return MathIsValidNumber(bid) &&
           MathIsValidNumber(ask) &&
           bid > 0.0 &&
           ask >= bid;
  }

  // Check whether level_index is valid.
  // For an anchor, level_index must be -1.
  // For a non-anchor, level_index must be between 0 and engine.LevelCount() - 1.
  bool IsValidMapping(bool is_anchor, int level_index)
  {
    if(is_anchor)
      return level_index == -1;

    return level_index >= 0 &&
           level_index < m_engine.LevelCount();
  }

  // Runtime Hydration validates against the persisted Level count, because the
  // Engine has not been built yet when the projection is checked.
  bool IsValidHydratedMapping(
    bool is_anchor,
    int level_index,
    int normal_level_count
  )
  {
    if(is_anchor)
      return level_index == -1;

    return level_index >= 0 &&
           level_index < normal_level_count;
  }

  // Only operationally meaningful Level States are accepted for a Restore.
  // The legacy WAIT_RETURN slot is never written by new state transitions.
  bool IsValidHydrationState(ENUM_TGK_GRID_LEVEL_STATE state)
  {
    return state == TGK_GRID_LEVEL_READY ||
           state == TGK_GRID_LEVEL_ACTIVE ||
           state == TGK_GRID_LEVEL_WAIT_ACTIVATION;
  }

  // Canonical Position Identifier and Ticket literals are decimal strings.
  // "0" is never a valid identity.
  bool IsDecimalIdentity(string value)
  {
    int length = StringLen(value);
    if(length <= 0)
      return false;

    for(int index = 0; index < length; index++)
    {
      ushort character = StringGetCharacter(value, index);
      if(character < '0' || character > '9')
        return false;
    }

    return value != "0";
  }

  // Request identifiers use the same token alphabet as the Reducer.
  bool IsTokenLiteral(string value)
  {
    int length = StringLen(value);
    if(length <= 0)
      return false;

    for(int index = 0; index < length; index++)
    {
      ushort character = StringGetCharacter(value, index);
      bool valid = (character >= 'A' && character <= 'Z') ||
                   (character >= 'a' && character <= 'z') ||
                   (character >= '0' && character <= '9') ||
                   character == '_' || character == '-';
      if(!valid)
        return false;
    }

    return true;
  }

  // Compares the requested Runtime configuration with the committed Persisted
  // Configuration Projection before any Runtime state is applied. Level
  // geometry uses the same epsilon as the Engine's Level build, so a different
  // Anchor cannot silently relocate Levels while keeping the same Level count.
  // "normal_level_count" is the Engine Level count, which is the persisted
  // Level count minus one (the Anchor is not an Engine Level).
  bool ValidatePersistedConfig(
    ENUM_TGK_GRID_MODE mode,
    double anchor_price,
    double grid_step_price,
    double lower_bound,
    double upper_bound,
    int normal_level_count,
    string symbol,
    long magic_number,
    long config_epoch,
    STGKGridPersistedConfigProjection &persisted_config
  )
  {
    if(!IsTokenLiteral(persisted_config.instance_id) ||
       persisted_config.symbol == "" ||
       persisted_config.magic_number <= 0 ||
       persisted_config.config_epoch <= 0 ||
       persisted_config.persisted_level_count <= 1 ||
       !MathIsValidNumber(persisted_config.anchor_price) ||
       !MathIsValidNumber(persisted_config.grid_step) ||
       !MathIsValidNumber(persisted_config.lower_bound) ||
       !MathIsValidNumber(persisted_config.upper_bound) ||
       persisted_config.grid_step <= 0.0 ||
       persisted_config.lower_bound > persisted_config.anchor_price ||
       persisted_config.anchor_price > persisted_config.upper_bound)
      return false;

    if(!MathIsValidNumber(anchor_price) ||
       !MathIsValidNumber(grid_step_price) ||
       !MathIsValidNumber(lower_bound) ||
       !MathIsValidNumber(upper_bound) ||
       grid_step_price <= 0.0)
      return false;

    if(symbol != persisted_config.symbol ||
       magic_number != persisted_config.magic_number ||
       config_epoch != persisted_config.config_epoch ||
       mode != persisted_config.mode)
      return false;

    if(normal_level_count != persisted_config.persisted_level_count - 1)
      return false;

    double epsilon = persisted_config.grid_step * 0.000000001;
    if(MathAbs(anchor_price - persisted_config.anchor_price) > epsilon ||
       MathAbs(grid_step_price - persisted_config.grid_step) > epsilon ||
       MathAbs(lower_bound - persisted_config.lower_bound) > epsilon ||
       MathAbs(upper_bound - persisted_config.upper_bound) > epsilon)
      return false;

    return true;
  }

  // Validates the complete persisted projection without mutating any state, so
  // a rejected Restore can never release partial Runtime state.
  bool ValidateHydrationProjection(
    string symbol,
    long magic_number,
    long config_epoch,
    int normal_level_count,
    ENUM_TGK_GRID_LEVEL_STATE anchor_state,
    STGKGridLevelStateHydration &level_states[],
    STGKGridLevelPositionRecord &positions[],
    STGKGridEntryRequestHydration &entry_request,
    int &level_state_values[]
  )
  {
    ArrayResize(level_state_values, 0);

    if(symbol == "" ||
       magic_number <= 0 ||
       config_epoch <= 0 ||
       normal_level_count <= 0 ||
       !IsValidHydrationState(anchor_state) ||
       ArraySize(level_states) != normal_level_count)
      return false;

    if(ArrayResize(level_state_values, normal_level_count) != normal_level_count)
      return false;

    for(int index = 0; index < normal_level_count; index++)
      level_state_values[index] = -1;

    // Every normal Level must be Hydrated exactly once.
    for(int index = 0; index < ArraySize(level_states); index++)
    {
      int level_index = level_states[index].level_index;
      if(level_index < 0 ||
         level_index >= normal_level_count ||
         !IsValidHydrationState(level_states[index].state) ||
         level_state_values[level_index] != -1)
        return false;

      level_state_values[level_index] = (int)level_states[index].state;
    }

    for(int index = 0; index < normal_level_count; index++)
    {
      if(level_state_values[index] == -1)
        return false;
    }

    bool anchor_mapped = false;
    for(int index = 0; index < ArraySize(positions); index++)
    {
      if(positions[index].symbol != symbol ||
         positions[index].magic_number != magic_number ||
         positions[index].ticket == 0 ||
         !IsDecimalIdentity(positions[index].position_identifier) ||
         !MathIsValidNumber(positions[index].volume) ||
         positions[index].volume <= 0.0 ||
         !IsValidHydratedMapping(
           positions[index].is_anchor,
           positions[index].level_index,
           normal_level_count))
        return false;

      // A Mapping exists only for an ACTIVE target.
      if(positions[index].is_anchor)
      {
        if(anchor_mapped || anchor_state != TGK_GRID_LEVEL_ACTIVE)
          return false;
        anchor_mapped = true;
      }
      else if(level_state_values[positions[index].level_index] !=
              (int)TGK_GRID_LEVEL_ACTIVE)
        return false;

      for(int previous = 0; previous < index; previous++)
      {
        if(positions[previous].ticket == positions[index].ticket ||
           positions[previous].position_identifier ==
             positions[index].position_identifier ||
           SameMapping(
             positions[previous].is_anchor,
             positions[previous].level_index,
             positions[index].is_anchor,
             positions[index].level_index))
          return false;
      }
    }

    // An ACTIVE Level or Anchor must own its Mapping, and a Mapping may never
    // be inferred from a Level State or from an Entry Request.
    if((anchor_state == TGK_GRID_LEVEL_ACTIVE) != anchor_mapped)
      return false;

    for(int level_index = 0; level_index < normal_level_count; level_index++)
    {
      bool mapped = false;
      for(int index = 0; index < ArraySize(positions); index++)
      {
        if(!positions[index].is_anchor &&
           positions[index].level_index == level_index)
        {
          mapped = true;
          break;
        }
      }

      if((level_state_values[level_index] == (int)TGK_GRID_LEVEL_ACTIVE) != mapped)
        return false;
    }

    // The unresolved Entry Request stays unresolved evidence: it must not own a
    // Mapping and must not leave its Target ACTIVE.
    if(entry_request.present)
    {
      if(!IsTokenLiteral(entry_request.request_id) ||
         !MathIsValidNumber(entry_request.requested_volume) ||
         entry_request.requested_volume <= 0.0 ||
         !IsValidHydratedMapping(
           entry_request.is_anchor,
           entry_request.level_index,
           normal_level_count))
        return false;

      if(entry_request.is_anchor)
      {
        if(anchor_state == TGK_GRID_LEVEL_ACTIVE)
          return false;
      }
      else if(level_state_values[entry_request.level_index] ==
              (int)TGK_GRID_LEVEL_ACTIVE)
        return false;
    }

    return true;
  }

  // Commits a projection that already passed ValidateHydrationProjection().
  // Every failure path leaves the Coordinator unusable instead of partially
  // activated.
  bool ApplyHydratedState(
    ENUM_TGK_GRID_LEVEL_STATE anchor_state,
    int &level_state_values[],
    STGKGridLevelPositionRecord &positions[],
    STGKGridEntryRequestHydration &entry_request
  )
  {
    for(int level_index = 0; level_index < ArraySize(level_state_values); level_index++)
    {
      if(!m_engine.SetLevelState(
        level_index,
        (ENUM_TGK_GRID_LEVEL_STATE)level_state_values[level_index]))
        return false;
    }

    if(!m_engine.SetAnchorState(anchor_state))
      return false;

    int total = ArraySize(positions);
    if(ArrayResize(m_positions, total) != total)
      return false;

    for(int index = 0; index < total; index++)
    {
      m_positions[index].ticket = positions[index].ticket;
      m_positions[index].symbol = positions[index].symbol;
      m_positions[index].magic_number = positions[index].magic_number;
      m_positions[index].is_anchor = positions[index].is_anchor;
      m_positions[index].level_index = positions[index].level_index;
      m_positions[index].volume = positions[index].volume;
      m_positions[index].position_identifier = positions[index].position_identifier;
    }

    if(!entry_request.present)
      return true;

    double request_level_price = 0.0;
    if(entry_request.is_anchor)
      request_level_price = m_engine.AnchorPrice();
    else if(!m_engine.GetLevelPrice(
      entry_request.level_index,
      request_level_price))
      return false;

    if(!MathIsValidNumber(request_level_price) || request_level_price <= 0.0)
      return false;

    m_pending_candidate.is_anchor = entry_request.is_anchor;
    m_pending_candidate.level_index = entry_request.level_index;
    m_pending_candidate.level_price = request_level_price;
    m_request_unresolved = true;
    m_pending_request_id = entry_request.request_id;
    m_pending_request_volume = entry_request.requested_volume;
    return true;
  }

  // Check whether two candidates map to the same level index.
  bool SameMapping(
    bool left_is_anchor,
    int left_index,
    bool right_is_anchor,
    int right_index
  )
  {
    return left_is_anchor == right_is_anchor &&
           left_index == right_index;
  }

  // Compare two candidates to see whether they have the same values.
  // Based on both level_index and level_price.
  bool SameCandidate(
    STGKGridLevelCandidate &left,
    STGKGridLevelCandidate &right
  )
  {
    return SameMapping(
      left.is_anchor,
      left.level_index,
      right.is_anchor,
      right.level_index) &&
      MathAbs(left.level_price - right.level_price) <= 0.000000001;
  }

  // Determines whether the candidate price is better than the current price.
  // @param candidate The candidate whose price is being evaluated.
  // @param current The current candidate used as the comparison baseline.
  bool IsBetterCandidate(
    STGKGridLevelCandidate &candidate,
    STGKGridLevelCandidate &current
  )
  {
    if(MathAbs(candidate.level_price - current.level_price) <= 0.000000001)
      return false;

    // The Engine already chooses BUY-lowest / SELL-highest within one tick.
    // The same rule is applied when candidates are deferred across ticks.
    return (m_mode == TGK_GRID_MODE_BUY)
      ? candidate.level_price < current.level_price
      : candidate.level_price > current.level_price;
  }

  // Checks whether this candidate is in a state ready to enter a trade.
  // READY is the only operational entry-eligible state.
  bool IsCandidateEligible(STGKGridLevelCandidate &candidate)
  {
    // An Anchor activation is not entry evidence until it is durable.
    if(candidate.is_anchor && m_anchor_activation_pending)
      return false;

    ENUM_TGK_GRID_LEVEL_STATE state;

    if(candidate.is_anchor)
      state = m_engine.GetAnchorState();
    else if(!m_engine.GetLevelState(candidate.level_index, state))
      return false;

    return TGKGridNormalizeLevelState(state) == TGK_GRID_LEVEL_READY;
  }

  // Checks whether the positions data is valid and contains no duplicates.
  // Returns false if any data is invalid or a ticket or level mapping is duplicated.
  // Returns true if all data is valid and unique.
  bool ValidateSnapshot(
    STGKGridLevelPositionRecord &positions[]
  )
  {
    int total = ArraySize(positions);

    for(int index = 0; index < total; index++)
    {
      if(positions[index].ticket == 0 ||
         positions[index].symbol != m_symbol ||
         positions[index].magic_number != m_magic_number ||
         !IsValidMapping(
           positions[index].is_anchor,
           positions[index].level_index) ||
         !MathIsValidNumber(positions[index].volume) ||
         positions[index].volume <= 0.0)
        return false;

      for(int previous = 0; previous < index; previous++)
      {
        if(positions[previous].ticket == positions[index].ticket ||
           SameMapping(
             positions[previous].is_anchor,
             positions[previous].level_index,
             positions[index].is_anchor,
             positions[index].level_index))
          return false;
      }
    }

    return true;
  }

  // Finds a position using is_anchor and level_index.
  // Returns the position's index in positions if found.
  // Returns -1 if no matching position is found.
  int FindPositionByMapping(
    STGKGridLevelPositionRecord &positions[],
    bool is_anchor,
    int level_index
  )
  {
    for(int index = 0; index < ArraySize(positions); index++)
    {
      if(SameMapping(
        positions[index].is_anchor,
        positions[index].level_index,
        is_anchor,
        level_index))
        return index;
    }

    return -1;
  }

  // Finds a close event using is_anchor and level_index.
  // Returns the event's index in close_events if found.
  // Returns -1 if no matching event is found.
  // Returns -2 if the data is invalid or more than one close event matches.
  int FindCloseEvent(
    STGKGridLevelCloseEvent &close_events[],
    bool is_anchor,
    int level_index
  )
  {
    int found = -1;

    for(int index = 0; index < ArraySize(close_events); index++)
    {
      if(!IsValidMapping(
        close_events[index].is_anchor,
        close_events[index].level_index))
        return -2;

      if(!SameMapping(
        close_events[index].is_anchor,
        close_events[index].level_index,
        is_anchor,
        level_index))
        continue;

      if(found >= 0)
        return -2;

      found = index;
    }

    return found;
  }

  // Validates that each close event has a valid mapping, refers to a position
  // in the previous snapshot that is absent from the current snapshot, and is
  // not duplicated. Also requires a close event for every position that
  // disappeared from the previous snapshot.
  bool ValidateCloseEvents(
    STGKGridLevelPositionRecord &positions[],
    STGKGridLevelCloseEvent &close_events[]
  )
  {
    for(int index = 0; index < ArraySize(close_events); index++)
    {
      if(!IsValidMapping(
        close_events[index].is_anchor,
        close_events[index].level_index))
        return false;

      int position_index = FindPositionByMapping(
        positions,
        close_events[index].is_anchor,
        close_events[index].level_index);

      // A close event and a still-present position are contradictory.
      if(position_index >= 0)
        return false;

      bool was_tracked = false;

      for(int previous = 0; previous < ArraySize(m_positions); previous++)
      {
        if(SameMapping(
          m_positions[previous].is_anchor,
          m_positions[previous].level_index,
          close_events[index].is_anchor,
          close_events[index].level_index))
        {
          was_tracked = true;
          break;
        }
      }

      // A close event must correspond to a position in the prior snapshot.
      if(!was_tracked)
        return false;

      for(int previous = 0; previous < index; previous++)
      {
        if(SameMapping(
          close_events[previous].is_anchor,
          close_events[previous].level_index,
          close_events[index].is_anchor,
          close_events[index].level_index))
          return false;
      }
    }

    // Every disappeared logical position needs an explicit close reason.
    for(int index = 0; index < ArraySize(m_positions); index++)
    {
      int position_index = FindPositionByMapping(
        positions,
        m_positions[index].is_anchor,
        m_positions[index].level_index);

      if(position_index >= 0)
        continue;

      bool has_close_event = false;

      for(int close_index = 0; close_index < ArraySize(close_events); close_index++)
      {
        if(SameMapping(
          close_events[close_index].is_anchor,
          close_events[close_index].level_index,
          m_positions[index].is_anchor,
          m_positions[index].level_index))
        {
          has_close_event = true;
          break;
        }
      }

      if(!has_close_event)
        return false;
    }

    return true;
  }

  // Updates the internal positions to match the positions parameter.
  bool StoreCurrentPositions(
    STGKGridLevelPositionRecord &positions[]
  )
  {
    int total = ArraySize(positions);

    if(ArrayResize(m_positions, total) != total)
      return false;

    for(int index = 0; index < total; index++)
    {
      m_positions[index].ticket = positions[index].ticket;
      m_positions[index].symbol = positions[index].symbol;
      m_positions[index].magic_number = positions[index].magic_number;
      m_positions[index].is_anchor = positions[index].is_anchor;
      m_positions[index].level_index = positions[index].level_index;
      m_positions[index].volume = positions[index].volume;
      m_positions[index].position_identifier = positions[index].position_identifier;
    }

    return true;
  }

  // Checks whether this position matches the pending candidate.
  bool IsPendingPosition(
    STGKGridLevelPositionRecord &position
  )
  {
    return SameMapping(
      position.is_anchor,
      position.level_index,
      m_pending_candidate.is_anchor,
      m_pending_candidate.level_index);
  }

  // Clears the offered candidate data.
  void ClearOfferedCandidate()
  {
    m_candidate_offered = false;
    m_offered_candidate.is_anchor = false;
    m_offered_candidate.level_index = -1;
    m_offered_candidate.level_price = 0.0;
  }

  // Clears the deferred candidate data.
  void ClearDeferredCandidate()
  {
    m_has_deferred_candidate = false;
    m_deferred_candidate.is_anchor = false;
    m_deferred_candidate.level_index = -1;
    m_deferred_candidate.level_price = 0.0;
  }

  // Fail-closed Runtime invalidation. Everything a previous initialization or
  // Hydration produced is dropped, and the Engine is reset, so a Restore that
  // fails can neither expose nor reuse stale Anchor, Level, Position, Request,
  // Candidate or Instance state. The Restore Status is left for the caller to
  // set, because it carries the reason the Restore ended.
  void InvalidateRuntimeState()
  {
    m_engine.Reset();
    m_mode = TGK_GRID_MODE_BUY;
    m_symbol = "";
    m_magic_number = 0;
    m_config_epoch = 0;
    m_instance_id = "";
    m_previous_bid = 0.0;
    m_previous_ask = 0.0;
    m_current_bid = 0.0;
    m_current_ask = 0.0;
    m_anchor_activation_pending = false;
    m_initialized = false;
    m_request_unresolved = false;
    m_pending_candidate.is_anchor = false;
    m_pending_candidate.level_index = -1;
    m_pending_candidate.level_price = 0.0;
    ClearOfferedCandidate();
    ClearDeferredCandidate();
    m_restore_status = TGK_GRID_RUNTIME_RESTORE_NONE;
    m_reconciliation_pending = false;
    m_released_snapshot_generation = 0;
    m_released_base_sequence = 0;
    m_pending_request_id = "";
    m_pending_request_volume = 0.0;
    ArrayResize(m_positions, 0);
  }

  // Retains the candidate if its price is better than the current deferred
  // candidate, while preventing candidates from being processed more than once.
  void RetainDeferredCandidate(STGKGridLevelCandidate &candidate)
  {
    if(m_candidate_offered &&
       SameCandidate(candidate, m_offered_candidate))
      return;

    if(m_request_unresolved &&
       SameCandidate(candidate, m_pending_candidate))
      return;

    if(!m_has_deferred_candidate ||
       IsBetterCandidate(candidate, m_deferred_candidate))
    {
      m_deferred_candidate.is_anchor = candidate.is_anchor;
      m_deferred_candidate.level_index = candidate.level_index;
      m_deferred_candidate.level_price = candidate.level_price;
      m_has_deferred_candidate = true;
    }
  }

  // If a deferred candidate exists and its state is ready for trade entry,
  // updates the candidate parameter and offered candidate to equal deferred candidate, then
  // returns CANDIDATE_READY. Otherwise, returns NO_CANDIDATE.
  ENUM_TGK_GRID_COORDINATOR_RESULT OfferDeferredCandidate(
    STGKGridLevelCandidate &candidate
  )
  {
    if(!m_has_deferred_candidate)
      return TGK_GRID_COORDINATOR_NO_CANDIDATE;

    if(!IsCandidateEligible(m_deferred_candidate))
    {
      // Keep a crossed Anchor candidate until its activation is durable.
      if(!(m_deferred_candidate.is_anchor && m_anchor_activation_pending))
        ClearDeferredCandidate();
      return TGK_GRID_COORDINATOR_NO_CANDIDATE;
    }

    candidate.is_anchor = m_deferred_candidate.is_anchor;
    candidate.level_index = m_deferred_candidate.level_index;
    candidate.level_price = m_deferred_candidate.level_price;
    m_offered_candidate.is_anchor = candidate.is_anchor;
    m_offered_candidate.level_index = candidate.level_index;
    m_offered_candidate.level_price = candidate.level_price;
    m_candidate_offered = true;
    ClearDeferredCandidate();
    return TGK_GRID_COORDINATOR_CANDIDATE_READY;
  }

  // Updates the state of a level in close_events
  // to indicate it is ready to trade again.
  bool ApplyClosedPositions(
    STGKGridLevelPositionRecord &positions[],
    STGKGridLevelCloseEvent &close_events[]
  )
  {
    for(int index = 0; index < ArraySize(m_positions); index++)
    {
      int current_index = FindPositionByMapping(
        positions,
        m_positions[index].is_anchor,
        m_positions[index].level_index);

      if(current_index >= 0)
        continue;

      int close_index = FindCloseEvent(
        close_events,
        m_positions[index].is_anchor,
        m_positions[index].level_index);

      if(close_index < 0)
        return false;

      if(!m_engine.RecordPositionClosed(
        m_positions[index].is_anchor,
        m_positions[index].level_index,
        m_current_bid,
        m_current_ask))
        return false;
    }

    // A close event for a Level not present in the previous snapshot is
    // inconsistent; do not silently apply a state transition.
    for(int index = 0; index < ArraySize(close_events); index++)
    {
      bool was_tracked = false;

      for(int previous = 0; previous < ArraySize(m_positions); previous++)
      {
        if(SameMapping(
          m_positions[previous].is_anchor,
          m_positions[previous].level_index,
          close_events[index].is_anchor,
          close_events[index].level_index))
        {
          was_tracked = true;
          break;
        }
      }

      if(!was_tracked)
        return false;
    }

    return true;
  }

  // Used to confirm that if there is a new position
  // m_request_unresolved must be true
  // and the pending candidate must match the new position
  bool ValidateNewPositions(
    STGKGridLevelPositionRecord &positions[]
  )
  {
    for(int index = 0; index < ArraySize(positions); index++)
    {
      int previous_index = FindPositionByMapping(
        m_positions,
        positions[index].is_anchor,
        positions[index].level_index);

      if(previous_index >= 0)
        continue;

      if(!m_request_unresolved ||
         !IsPendingPosition(positions[index]))
        return false;
    }

    return true;
  }

public:
  CTGKGridLevelRuntimeCoordinator()
  {
    m_mode = TGK_GRID_MODE_BUY;
    m_symbol = "";
    m_magic_number = 0;
    m_config_epoch = 0;
    m_previous_bid = 0.0;
    m_previous_ask = 0.0;
    m_current_bid = 0.0;
    m_current_ask = 0.0;
    m_anchor_activation_pending = false;
    m_initialized = false;
    m_candidate_offered = false;
    m_request_unresolved = false;
    m_has_deferred_candidate = false;
    m_restore_status = TGK_GRID_RUNTIME_RESTORE_NONE;
    m_reconciliation_pending = false;
    m_released_snapshot_generation = 0;
    m_released_base_sequence = 0;
    m_pending_request_id = "";
    m_pending_request_volume = 0.0;
    m_instance_id = "";
    m_offered_candidate.is_anchor = false;
    m_offered_candidate.level_index = -1;
    m_offered_candidate.level_price = 0.0;
    m_pending_candidate.is_anchor = false;
    m_pending_candidate.level_index = -1;
    m_pending_candidate.level_price = 0.0;
    m_deferred_candidate.is_anchor = false;
    m_deferred_candidate.level_index = -1;
    m_deferred_candidate.level_price = 0.0;
  }

  bool Initialize(
    ENUM_TGK_GRID_MODE mode,
    double anchor_price,
    double grid_step_price,
    double lower_bound,
    double upper_bound,
    int level_count,
    string symbol,
    long magic_number,
    double current_bid,
    double current_ask
  )
  {
    m_initialized = false;

    if(symbol == "" ||
       magic_number <= 0 ||
       !IsValidQuote(current_bid, current_ask))
      return false;

    if(!m_engine.Initialize(
      mode,
      anchor_price,
      grid_step_price,
      lower_bound,
      upper_bound,
      level_count,
      current_bid,
      current_ask))
      return false;

    m_mode = mode;
    m_symbol = symbol;
    m_magic_number = magic_number;
    m_config_epoch = 0;
    m_previous_bid = current_bid;
    m_previous_ask = current_ask;
    m_current_bid = current_bid;
    m_current_ask = current_ask;
    m_candidate_offered = false;
    m_request_unresolved = false;
    m_has_deferred_candidate = false;
    m_anchor_activation_pending = false;
    m_restore_status = TGK_GRID_RUNTIME_RESTORE_NONE;
    m_reconciliation_pending = false;
    m_released_snapshot_generation = 0;
    m_released_base_sequence = 0;
    m_pending_request_id = "";
    m_pending_request_volume = 0.0;
    m_instance_id = "";
    ArrayResize(m_positions, 0);
    m_initialized = true;
    return true;
  }

  // Use the current price to check for a new candidate.
  // Process it if one is available; otherwise, process the pending candidate.
  ENUM_TGK_GRID_COORDINATOR_RESULT UpdatePrice(
    double current_bid,
    double current_ask,
    ENUM_TGK_GRID_COORDINATOR_RESULT &result,
    STGKGridLevelCandidate &candidate
  )
  {
    result = TGK_GRID_COORDINATOR_ERROR;
    candidate.is_anchor = false;
    candidate.level_index = -1;
    candidate.level_price = 0.0;

    if(!m_initialized || !IsValidQuote(current_bid, current_ask))
      return TGK_GRID_COORDINATOR_ERROR;

    // A hydrated Runtime stays dormant: the current quote only refreshes the
    // Baseline. No Candidate or Entry Request may exist before a
    // Complete/Stable Live Position Snapshot confirms ownership.
    if(m_reconciliation_pending)
    {
      m_previous_bid = current_bid;
      m_previous_ask = current_ask;
      m_current_bid = current_bid;
      m_current_ask = current_ask;
      result = TGK_GRID_COORDINATOR_NO_CANDIDATE;
      return result;
    }

    bool is_anchor = false;
    int level_index = -1;
    double level_price = 0.0;

    bool has_candidate = m_engine.UpdatePrice(
      m_previous_bid,
      m_previous_ask,
      current_bid,
      current_ask,
      is_anchor,
      level_index,
      level_price);

    if(m_engine.HasPendingAnchorActivation())
      m_anchor_activation_pending = true;

    // Do not offer an Anchor entry while its activation record is uncommitted.
    if(has_candidate && is_anchor && m_anchor_activation_pending)
    {
      STGKGridLevelCandidate deferred_anchor;
      deferred_anchor.is_anchor = true;
      deferred_anchor.level_index = -1;
      deferred_anchor.level_price = level_price;
      RetainDeferredCandidate(deferred_anchor);
      has_candidate = false;
    }

    m_previous_bid = current_bid;
    m_previous_ask = current_ask;
    m_current_bid = current_bid;
    m_current_ask = current_ask;

    if(has_candidate)
    {
      STGKGridLevelCandidate next_candidate;
      next_candidate.is_anchor = is_anchor;
      next_candidate.level_index = level_index;
      next_candidate.level_price = level_price;

      if(m_request_unresolved || m_candidate_offered)
        RetainDeferredCandidate(next_candidate);
      else if(m_has_deferred_candidate)
      {
        RetainDeferredCandidate(next_candidate);
        result = OfferDeferredCandidate(candidate);
        return result;
      }
      else
      {
        m_offered_candidate.is_anchor = next_candidate.is_anchor;
        m_offered_candidate.level_index = next_candidate.level_index;
        m_offered_candidate.level_price = next_candidate.level_price;
        m_candidate_offered = true;
        candidate.is_anchor = next_candidate.is_anchor;
        candidate.level_index = next_candidate.level_index;
        candidate.level_price = next_candidate.level_price;
        result = TGK_GRID_COORDINATOR_CANDIDATE_READY;
        return result;
      }
    }

    if(m_request_unresolved)
      result = TGK_GRID_COORDINATOR_REQUEST_UNRESOLVED;
    else if(m_candidate_offered)
      result = TGK_GRID_COORDINATOR_NO_CANDIDATE;
    else
      result = OfferDeferredCandidate(candidate);

    return result;
  }

  // The received candidate must match offered_candidate and must not have been processed yet.
  // For REQUEST_FAILED, update the candidate's level to WAIT_ACTIVATION or READY.
  // For REQUEST_ACCEPTED, set the pending candidate to the received candidate
  // and set request_unresolved to true.
  bool RecordEntryRequest(
    STGKGridLevelCandidate &candidate,
    ENUM_TGK_GRID_ENTRY_REQUEST_RESULT request_result
  )
  {
    if(!m_initialized ||
       !m_candidate_offered ||
       !SameCandidate(candidate, m_offered_candidate) ||
       m_request_unresolved)
      return false;

    if(request_result == TGK_GRID_ENTRY_REQUEST_FAILED)
    {
      if(!m_engine.RecordEntryFailed(
        candidate.is_anchor,
        candidate.level_index,
        m_current_bid,
        m_current_ask))
        return false;

      ClearOfferedCandidate();
      return true;
    }

    if(request_result != TGK_GRID_ENTRY_REQUEST_ACCEPTED)
      return false;

    m_pending_candidate.is_anchor = candidate.is_anchor;
    m_pending_candidate.level_index = candidate.level_index;
    m_pending_candidate.level_price = candidate.level_price;
    m_request_unresolved = true;
    ClearOfferedCandidate();
    return true;
  }

  ENUM_TGK_GRID_COORDINATOR_RESULT Reconcile(
    STGKGridLevelPositionRecord &positions[],
    STGKGridLevelCloseEvent &close_events[],
    ENUM_TGK_GRID_ENTRY_RESOLUTION entry_resolution,
    double current_bid,
    double current_ask,
    ENUM_TGK_GRID_COORDINATOR_RESULT &result,
    STGKGridLevelCandidate &candidate
  )
  {
    result = TGK_GRID_COORDINATOR_ERROR;
    candidate.is_anchor = false;
    candidate.level_index = -1;
    candidate.level_price = 0.0;

    // Reconcile is never an implicit gate release. WP-05C defines the explicit
    // release after a Complete/Stable Live Position Snapshot, so a pending Gate
    // rejects the call before any state mutation or side effect.
    if(!m_initialized ||
       m_reconciliation_pending ||
       !IsValidQuote(current_bid, current_ask) ||
       !ValidateSnapshot(positions) ||
       (entry_resolution != TGK_GRID_ENTRY_RESOLUTION_PENDING &&
        entry_resolution != TGK_GRID_ENTRY_RESOLUTION_TERMINAL_NO_POSITION_NO_ORDER))
      return TGK_GRID_COORDINATOR_ERROR;

    if(!ValidateNewPositions(positions) ||
       !ValidateCloseEvents(positions, close_events))
      return TGK_GRID_COORDINATOR_ERROR;

    int matching_pending_position = -1;

    if(m_request_unresolved)
    {
      for(int index = 0; index < ArraySize(positions); index++)
      {
        if(IsPendingPosition(positions[index]))
        {
          matching_pending_position = index;
          break;
        }
      }

      if(matching_pending_position >= 0 &&
         entry_resolution == TGK_GRID_ENTRY_RESOLUTION_TERMINAL_NO_POSITION_NO_ORDER)
        return TGK_GRID_COORDINATOR_ERROR;
    }
    else if(entry_resolution != TGK_GRID_ENTRY_RESOLUTION_PENDING)
      return TGK_GRID_COORDINATOR_ERROR;

    m_current_bid = current_bid;
    m_current_ask = current_ask;
    m_previous_bid = current_bid;
    m_previous_ask = current_ask;

    if(m_request_unresolved)
    {
      if(matching_pending_position >= 0)
      {
        if(!m_engine.RecordEntryConfirmed(
          m_pending_candidate.is_anchor,
          m_pending_candidate.level_index))
          return TGK_GRID_COORDINATOR_ERROR;

        m_request_unresolved = false;
        m_pending_request_id = "";
        m_pending_request_volume = 0.0;
        m_pending_candidate.is_anchor = false;
        m_pending_candidate.level_index = -1;
        m_pending_candidate.level_price = 0.0;
      }
      else if(entry_resolution == TGK_GRID_ENTRY_RESOLUTION_TERMINAL_NO_POSITION_NO_ORDER)
      {
        if(!m_engine.RecordEntryFailed(
          m_pending_candidate.is_anchor,
          m_pending_candidate.level_index,
          current_bid,
          current_ask))
          return TGK_GRID_COORDINATOR_ERROR;

        m_request_unresolved = false;
        m_pending_request_id = "";
        m_pending_request_volume = 0.0;
        m_pending_candidate.is_anchor = false;
        m_pending_candidate.level_index = -1;
        m_pending_candidate.level_price = 0.0;
      }
    }

    if(!ApplyClosedPositions(positions, close_events) ||
       !StoreCurrentPositions(positions))
      return TGK_GRID_COORDINATOR_ERROR;

    if(m_request_unresolved)
      result = TGK_GRID_COORDINATOR_REQUEST_UNRESOLVED;
    else
      result = OfferDeferredCandidate(candidate);

    return result;
  }

  // Register the already-open initial Anchor position after the first fill.
  // This is the one initial Position that exists before Coordinator entry requests.
  bool RegisterInitialAnchorPosition(
    STGKGridLevelPositionRecord &position
  )
  {
    if(!m_initialized ||
       ArraySize(m_positions) != 0 ||
       m_candidate_offered ||
       m_request_unresolved ||
       m_has_deferred_candidate ||
       m_reconciliation_pending ||
       position.ticket == 0 ||
       position.symbol != m_symbol ||
       position.magic_number != m_magic_number ||
       !position.is_anchor ||
       position.level_index != -1 ||
       !MathIsValidNumber(position.volume) ||
       position.volume <= 0.0 ||
       m_engine.GetAnchorState() != TGK_GRID_LEVEL_ACTIVE)
      return false;

    if(ArrayResize(m_positions, 1) != 1)
      return false;

    m_positions[0].ticket = position.ticket;
    m_positions[0].symbol = position.symbol;
    m_positions[0].magic_number = position.magic_number;
    m_positions[0].is_anchor = position.is_anchor;
    m_positions[0].level_index = position.level_index;
    m_positions[0].volume = position.volume;
    return true;
  }

  bool GetLevelState(
    int level_index,
    ENUM_TGK_GRID_LEVEL_STATE &state
  )
  {
    return m_initialized && m_engine.GetLevelState(level_index, state);
  }

  // Canonical Level Price of the restored Grid. False while the Runtime is not
  // initialized or the Level Index is invalid.
  bool GetLevelPrice(
    int level_index,
    double &price)
  {
    if(!m_initialized)
      return false;

    return m_engine.GetLevelPrice(level_index, price);
  }

  // An uninitialized Runtime (including after a failed Restore) reports the
  // non-entry-eligible WAIT_ACTIVATION placeholder instead of a stale Anchor
  // State, so a caller that ignores initialization cannot act on old evidence.
  ENUM_TGK_GRID_LEVEL_STATE GetAnchorState()
  {
    if(!m_initialized)
      return TGK_GRID_LEVEL_WAIT_ACTIVATION;

    return m_engine.GetAnchorState();
  }

  // Canonical Anchor Price of the restored Grid. Zero while the Runtime is not
  // initialized.
  double AnchorPrice()
  {
    if(!m_initialized)
      return 0.0;

    return m_engine.AnchorPrice();
  }

  // True while an observed Anchor activation still needs its durable record.
  bool HasPendingAnchorActivation()
  {
    return m_initialized && m_anchor_activation_pending;
  }

  // Called only after the activation transition is durably appended/applied.
  bool ConfirmAnchorActivation()
  {
    if(!m_initialized || !m_anchor_activation_pending)
      return false;

    if(!m_engine.ConfirmAnchorActivation())
      return false;

    m_anchor_activation_pending = false;
    return true;
  }

  bool IsRequestUnresolved()
  {
    return m_initialized && m_request_unresolved;
  }

  bool MatchesIdentity(string symbol, long magic_number)
  {
    return m_initialized &&
           symbol == m_symbol &&
           magic_number == m_magic_number;
  }

  bool MatchesModeContext(
    string symbol,
    long magic_number,
    ENUM_TGK_GRID_MODE mode
  )
  {
    return m_initialized &&
           symbol == m_symbol &&
           magic_number == m_magic_number &&
           mode == m_mode;
  }

  // Bind the runtime state to its committed persistent configuration once.
  // A different epoch requires a freshly initialized Coordinator.
  bool BindConfigEpoch(long config_epoch)
  {
    if(!m_initialized || config_epoch <= 0 ||
       (m_config_epoch != 0 && m_config_epoch != config_epoch))
      return false;

    m_config_epoch = config_epoch;
    return true;
  }

  bool MatchesGridContext(
    string symbol,
    long magic_number,
    ENUM_TGK_GRID_MODE mode,
    long config_epoch
  )
  {
    return MatchesModeContext(symbol, magic_number, mode) &&
           config_epoch > 0 &&
           config_epoch == m_config_epoch;
  }

  // Bulk Runtime Hydration of the committed Reducer projection. The requested
  // configuration is first validated against the committed Persisted
  // Configuration Projection (identity, Mode, Epoch and Level geometry with the
  // Engine's epsilon); nothing is applied unless it matches. It builds the
  // Engine/Coordinator from the persisted Grid configuration, restores the
  // Anchor State, every normal Level State, every Position Mapping and the
  // unresolved Entry Request, and finishes in
  // PENDING_RECONCILIATION. It never appends the Journal, never reads the
  // account and never creates a Candidate. Any invalid, missing, duplicated or
  // conflicting piece rejects the whole Restore and leaves the Coordinator
  // unusable.
  // "normal_level_count" is the Engine Level count (Anchor excluded), which is
  // the persisted level count minus one.
  bool HydrateRuntimeState(
    ENUM_TGK_GRID_MODE mode,
    double anchor_price,
    double grid_step_price,
    double lower_bound,
    double upper_bound,
    int normal_level_count,
    string symbol,
    long magic_number,
    long config_epoch,
    STGKGridPersistedConfigProjection &persisted_config,
    double current_bid,
    double current_ask,
    ENUM_TGK_GRID_LEVEL_STATE anchor_state,
    STGKGridLevelStateHydration &level_states[],
    STGKGridLevelPositionRecord &positions[],
    STGKGridEntryRequestHydration &entry_request
  )
  {
    // Invalidate first: a Restore that fails anywhere below must leave the
    // Coordinator fail-closed instead of exposing the previous Runtime.
    InvalidateRuntimeState();
    m_restore_status = TGK_GRID_RUNTIME_RESTORE_ERROR;

    if(!ValidatePersistedConfig(
      mode,
      anchor_price,
      grid_step_price,
      lower_bound,
      upper_bound,
      normal_level_count,
      symbol,
      magic_number,
      config_epoch,
      persisted_config))
      return false;

    int level_state_values[];
    if(!ValidateHydrationProjection(
      symbol,
      magic_number,
      config_epoch,
      normal_level_count,
      anchor_state,
      level_states,
      positions,
      entry_request,
      level_state_values))
      return false;

    if(!IsValidQuote(current_bid, current_ask))
      return false;

    // The persisted projection is the canonical configuration; the requested
    // arguments above are validation inputs only. Building the Engine from the
    // committed values keeps the Runtime Geometry identical to the Geometry the
    // Mappings were persisted against, even when the request differs inside the
    // Engine epsilon.
    if(!m_engine.Initialize(
      persisted_config.mode,
      persisted_config.anchor_price,
      persisted_config.grid_step,
      persisted_config.lower_bound,
      persisted_config.upper_bound,
      persisted_config.persisted_level_count - 1,
      current_bid,
      current_ask))
      return false;

    if(!ApplyHydratedState(
      anchor_state,
      level_state_values,
      positions,
      entry_request))
    {
      InvalidateRuntimeState();
      m_restore_status = TGK_GRID_RUNTIME_RESTORE_ERROR;
      return false;
    }

    // Identity and Mode come from the validated persisted configuration, which
    // the request matched exactly; the request never installs Runtime state.
    m_mode = persisted_config.mode;
    m_symbol = persisted_config.symbol;
    m_magic_number = persisted_config.magic_number;
    m_config_epoch = persisted_config.config_epoch;
    m_instance_id = persisted_config.instance_id;
    m_previous_bid = current_bid;
    m_previous_ask = current_ask;
    m_current_bid = current_bid;
    m_current_ask = current_ask;
    m_initialized = true;
    m_restore_status = TGK_GRID_RUNTIME_RESTORE_PENDING_RECONCILIATION;
    m_reconciliation_pending = true;
    return true;
  }

  ENUM_TGK_GRID_RUNTIME_RESTORE_STATUS RestoreStatus()
  {
    return m_restore_status;
  }

  // True until the Reconciliation Gate is released after a Complete/Stable
  // Live Position Snapshot. While pending, no Candidate or Entry Request may
  // be offered, and RegisterInitialAnchorPosition is refused.
  bool IsReconciliationPending()
  {
    return m_initialized && m_reconciliation_pending;
  }

  // Read-only preview of the post-close state of one mapped target. The
  // durable transition is encoded at Consume time so the state can never be
  // computed from a stale quote.
  bool TryGetPostCloseState(
    bool is_anchor,
    int level_index,
    double current_bid,
    double current_ask,
    ENUM_TGK_GRID_LEVEL_STATE &state)
  {
    state = TGK_GRID_LEVEL_READY;
    if(!m_initialized)
      return false;

    return m_engine.TryGetPostCloseState(
      is_anchor,
      level_index,
      current_bid,
      current_ask,
      state);
  }

  // Explicit Reconciliation Gate release.
  //
  // The Caller must supply the proof of the Latest Accepted Complete/Stable
  // Live Position Snapshot and the Canonical Hydration Projection it built from
  // the Reducer. The release succeeds only when the proof matches the committed
  // Identity/Configuration, the freshness tokens advance, and the supplied
  // Projection is exactly the Runtime Projection. It never emits a Candidate:
  // it only refreshes the Quote Baseline and re-enables Price Processing.
  bool ReleaseReconciliationGate(
    STGKGridReconciliationGateProof &proof,
    ENUM_TGK_GRID_LEVEL_STATE anchor_state,
    STGKGridLevelStateHydration &level_states[],
    STGKGridLevelPositionRecord &positions[],
    STGKGridEntryRequestHydration &entry_request,
    double current_bid,
    double current_ask)
  {
    if(!m_initialized ||
       !m_reconciliation_pending ||
       !IsValidQuote(current_bid, current_ask))
      return false;

    if(!IsTokenLiteral(proof.instance_id) ||
       proof.instance_id != m_instance_id ||
       proof.symbol != m_symbol ||
       proof.magic_number != m_magic_number ||
       proof.mode != m_mode ||
       proof.config_epoch <= 0 ||
       proof.config_epoch != m_config_epoch ||
       proof.snapshot_generation <= m_released_snapshot_generation ||
       proof.base_sequence < 0 ||
       proof.base_sequence < m_released_base_sequence)
      return false;

    // A Gate release never emits or retains a Candidate.
    if(m_candidate_offered ||
       m_has_deferred_candidate ||
       m_anchor_activation_pending)
      return false;

    int normal_level_count = m_engine.LevelCount();
    if(normal_level_count <= 0 ||
       ArraySize(level_states) != normal_level_count)
      return false;

    int level_state_values[];
    if(ArrayResize(level_state_values, normal_level_count) !=
       normal_level_count)
      return false;

    for(int level_index = 0; level_index < normal_level_count; level_index++)
      level_state_values[level_index] = -1;

    for(int index = 0; index < ArraySize(level_states); index++)
    {
      int level_index = level_states[index].level_index;
      if(level_index < 0 ||
         level_index >= normal_level_count ||
         !IsValidHydrationState(level_states[index].state) ||
         level_state_values[level_index] != -1)
        return false;

      level_state_values[level_index] = (int)level_states[index].state;
    }

    for(int level_index = 0; level_index < normal_level_count; level_index++)
    {
      ENUM_TGK_GRID_LEVEL_STATE runtime_state;
      if(level_state_values[level_index] == -1 ||
         !m_engine.GetLevelState(level_index, runtime_state) ||
         (int)TGKGridNormalizeLevelState(runtime_state) !=
           level_state_values[level_index])
        return false;
    }

    if(TGKGridNormalizeLevelState(anchor_state) !=
       TGKGridNormalizeLevelState(m_engine.GetAnchorState()))
      return false;

    if(ArraySize(positions) != ArraySize(m_positions))
      return false;

    for(int index = 0; index < ArraySize(positions); index++)
    {
      int runtime_index = -1;
      for(int previous = 0; previous < ArraySize(m_positions); previous++)
      {
        if(m_positions[previous].position_identifier ==
           positions[index].position_identifier)
        {
          runtime_index = previous;
          break;
        }
      }

      if(runtime_index < 0 ||
         m_positions[runtime_index].ticket != positions[index].ticket ||
         m_positions[runtime_index].symbol != positions[index].symbol ||
         m_positions[runtime_index].magic_number !=
           positions[index].magic_number ||
         m_positions[runtime_index].is_anchor != positions[index].is_anchor ||
         m_positions[runtime_index].level_index !=
           positions[index].level_index ||
         MathAbs(m_positions[runtime_index].volume - positions[index].volume) >
           0.00000001)
        return false;
    }

    if(entry_request.present)
    {
      if(!m_request_unresolved ||
         entry_request.request_id != m_pending_request_id ||
         MathAbs(entry_request.requested_volume - m_pending_request_volume) >
           0.00000001 ||
         entry_request.is_anchor != m_pending_candidate.is_anchor ||
         entry_request.level_index != m_pending_candidate.level_index)
        return false;
    }
    else if(m_request_unresolved)
      return false;

    m_previous_bid = current_bid;
    m_previous_ask = current_ask;
    m_current_bid = current_bid;
    m_current_ask = current_ask;
    m_released_snapshot_generation = proof.snapshot_generation;
    m_released_base_sequence = proof.base_sequence;
    m_reconciliation_pending = false;
    return true;
  }

  // The persisted Entry Request Identifier restored by Runtime Hydration.
  // It is cleared once Reconciliation resolves the Request.
  string PendingRequestId()
  {
    if(!m_initialized)
      return "";

    return m_pending_request_id;
  }

  // The persisted Requested Volume of the restored unresolved Entry Request.
  // It is evidence only: it never activates the Request Target. Zero when no
  // Request was restored or after Reconciliation resolves it.
  double PendingRequestVolume()
  {
    if(!m_initialized)
      return 0.0;

    return m_pending_request_volume;
  }

  // The Instance identity of the committed configuration validated by the last
  // Hydration. Empty before a successful Restore.
  string PersistedInstanceId()
  {
    if(!m_initialized)
      return "";

    return m_instance_id;
  }

  int PositionCount()
  {
    if(!m_initialized)
      return 0;

    return ArraySize(m_positions);
  }

  bool TryGetPositionAt(
    int index,
    STGKGridLevelPositionRecord &position
  )
  {
    if(!m_initialized || index < 0 || index >= ArraySize(m_positions))
      return false;

    position = m_positions[index];
    return true;
  }
};

#endif
