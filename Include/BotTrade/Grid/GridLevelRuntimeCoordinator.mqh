#ifndef BOTTRADE_GRID_LEVEL_RUNTIME_COORDINATOR_MQH
#define BOTTRADE_GRID_LEVEL_RUNTIME_COORDINATOR_MQH

#include <BotTrade/Grid/GridLevelEngine.mqh>

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

enum ENUM_TGK_GRID_LEVEL_CLOSE_REASON
{
  TGK_GRID_LEVEL_CLOSE_REASON_UNKNOWN = 0,
  TGK_GRID_LEVEL_CLOSE_REASON_TP,
  TGK_GRID_LEVEL_CLOSE_REASON_NON_TP
};

// Integration Layer must provide explicit mapping. The Coordinator never
// infers a Level from an approximate fill price.
struct STGKGridLevelPositionRecord
{
  ulong ticket;
  string symbol;
  long magic_number;
  bool is_anchor;
  int level_index;
  double volume;
};

struct STGKGridLevelCloseEvent
{
  bool is_anchor;
  int level_index;
  ENUM_TGK_GRID_LEVEL_CLOSE_REASON reason;
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
  double m_previous_bid;
  double m_previous_ask;
  double m_current_bid;
  double m_current_ask;
  bool m_initialized;

  bool m_candidate_offered;
  STGKGridLevelCandidate m_offered_candidate;

  bool m_request_unresolved;
  STGKGridLevelCandidate m_pending_candidate;

  bool m_has_deferred_candidate;
  STGKGridLevelCandidate m_deferred_candidate;

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
  // The trade-entry-ready states are READY and WAIT_RETURN.
  bool IsCandidateEligible(STGKGridLevelCandidate &candidate)
  {
    ENUM_TGK_GRID_LEVEL_STATE state;

    if(candidate.is_anchor)
      state = m_engine.GetAnchorState();
    else if(!m_engine.GetLevelState(candidate.level_index, state))
      return false;

    return state == TGK_GRID_LEVEL_READY ||
           state == TGK_GRID_LEVEL_WAIT_RETURN;
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

  // Validates that each close event has a valid mapping and a TP or NON_TP
  // reason, refers to a position in the previous snapshot that is disappear
  // from the current snapshot, and is not duplicated. Also requires a close
  // event for every position that disappeared from the previous snapshot.
  bool ValidateCloseEvents(
    STGKGridLevelPositionRecord &positions[],
    STGKGridLevelCloseEvent &close_events[]
  )
  {
    for(int index = 0; index < ArraySize(close_events); index++)
    {
      if(!IsValidMapping(
        close_events[index].is_anchor,
        close_events[index].level_index) ||
         (close_events[index].reason != TGK_GRID_LEVEL_CLOSE_REASON_TP &&
          close_events[index].reason != TGK_GRID_LEVEL_CLOSE_REASON_NON_TP))
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

      if(close_index < 0 ||
         close_events[close_index].reason == TGK_GRID_LEVEL_CLOSE_REASON_UNKNOWN)
        return false;

      bool closed_by_tp =
        close_events[close_index].reason == TGK_GRID_LEVEL_CLOSE_REASON_TP;

      if(!m_engine.RecordPositionClosed(
        m_positions[index].is_anchor,
        m_positions[index].level_index,
        closed_by_tp,
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
    m_previous_bid = 0.0;
    m_previous_ask = 0.0;
    m_current_bid = 0.0;
    m_current_ask = 0.0;
    m_initialized = false;
    m_candidate_offered = false;
    m_request_unresolved = false;
    m_has_deferred_candidate = false;
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
    m_previous_bid = current_bid;
    m_previous_ask = current_ask;
    m_current_bid = current_bid;
    m_current_ask = current_ask;
    m_candidate_offered = false;
    m_request_unresolved = false;
    m_has_deferred_candidate = false;
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

    if(!m_initialized ||
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

  ENUM_TGK_GRID_LEVEL_STATE GetAnchorState()
  {
    return m_engine.GetAnchorState();
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
};

#endif
