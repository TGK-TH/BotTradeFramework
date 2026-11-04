#ifndef BOTTRADE_GRID_LEVEL_ENGINE_MQH
#define BOTTRADE_GRID_LEVEL_ENGINE_MQH

#include <BotTrade/Grid/GridTypes.mqh>

// Pure Two-sided Grid level calculation and lifecycle decisions.
// This class never sends orders. The caller confirms entry/close outcomes
// through the Record* methods after execution and position reconciliation.
class CTGKGridLevelEngine
{
private:
  ENUM_TGK_GRID_MODE m_mode;
  double m_anchor_price;
  double m_grid_step_price;
  double m_lower_bound;
  double m_upper_bound;
  double m_level_prices[];
  ENUM_TGK_GRID_LEVEL_STATE m_level_states[];
  ENUM_TGK_GRID_LEVEL_STATE m_anchor_state;
  bool m_initialized;

  bool IsValidMode(ENUM_TGK_GRID_MODE mode)
  {
    return mode == TGK_GRID_MODE_BUY || mode == TGK_GRID_MODE_SELL;
  }

  bool IsValidLevelState(ENUM_TGK_GRID_LEVEL_STATE state)
  {
    return state == TGK_GRID_LEVEL_READY ||
           state == TGK_GRID_LEVEL_ACTIVE ||
           state == TGK_GRID_LEVEL_WAIT_RETURN ||
           state == TGK_GRID_LEVEL_WAIT_ACTIVATION;
  }

  bool IsValidQuote(
    double bid,
    double ask
  )
  {
    return bid > 0.0 && ask >= bid;
  }

  bool IsValidLevelIndex(int level_index)
  {
    return level_index >= 0 &&
           level_index < ArraySize(m_level_prices);
  }

  bool IsEntryEligible(ENUM_TGK_GRID_LEVEL_STATE state)
  {
    return state == TGK_GRID_LEVEL_READY ||
           state == TGK_GRID_LEVEL_WAIT_RETURN;
  }

  bool BuildLevels(int expected_level_count)
  {
    double lower_distance = m_anchor_price - m_lower_bound;
    double upper_distance = m_upper_bound - m_anchor_price;
    double epsilon = m_grid_step_price * 0.000000001;

    int lower_count = (int)MathFloor(
      (lower_distance + epsilon) / m_grid_step_price);
    int upper_count = (int)MathFloor(
      (upper_distance + epsilon) / m_grid_step_price);
    int total_count = lower_count + upper_count;

    if(total_count != expected_level_count ||
       ArrayResize(m_level_prices, total_count) != total_count ||
       ArrayResize(m_level_states, total_count) != total_count)
      return false;

    int output_index = 0;

    // Store lower-side levels from lowest price toward Anchor.
    for(int step_index = lower_count - 1; step_index >= 0; step_index--)
    {
      m_level_prices[output_index] =
        m_anchor_price - m_grid_step_price * (step_index + 1);
      output_index++;
    }

    // Store upper-side levels from Anchor toward highest price.
    for(int step_index = 0; step_index < upper_count; step_index++)
    {
      m_level_prices[output_index] =
        m_anchor_price + m_grid_step_price * (step_index + 1);
      output_index++;
    }

    return output_index == total_count;
  }

  void InitializeStates(double current_entry_price)
  {
    int total = ArraySize(m_level_prices);

    for(int index = 0; index < total; index++)
    {
      if(m_mode == TGK_GRID_MODE_BUY)
      {
        m_level_states[index] =
          (m_level_prices[index] >= current_entry_price)
          ? TGK_GRID_LEVEL_WAIT_ACTIVATION
          : TGK_GRID_LEVEL_READY;
      }
      else
      {
        m_level_states[index] =
          (m_level_prices[index] <= current_entry_price)
          ? TGK_GRID_LEVEL_WAIT_ACTIVATION
          : TGK_GRID_LEVEL_READY;
      }
    }

    // The Anchor represents the already-filled initial position.
    m_anchor_state = TGK_GRID_LEVEL_ACTIVE;
  }

  bool IsCrossedForActivation(
    double previous_price,
    double current_price,
    double level_price
  )
  {
    if(m_mode == TGK_GRID_MODE_BUY)
      return previous_price < level_price &&
             current_price >= level_price;

    return previous_price > level_price &&
           current_price <= level_price;
  }

  bool IsCrossedForEntry(
    double previous_price,
    double current_price,
    double level_price
  )
  {
    if(m_mode == TGK_GRID_MODE_BUY)
      return previous_price > level_price &&
             current_price <= level_price;

    return previous_price < level_price &&
           current_price >= level_price;
  }

  bool IsWrongSideAfterEntryMove(
    double level_price,
    double current_price
  )
  {
    if(m_mode == TGK_GRID_MODE_BUY)
      return level_price >= current_price;

    return level_price <= current_price;
  }

  ENUM_TGK_GRID_LEVEL_STATE StateAfterPositionClose(
    double level_price,
    bool closed_by_tp,
    double current_price
  )
  {
    if(IsWrongSideAfterEntryMove(level_price, current_price))
      return TGK_GRID_LEVEL_WAIT_ACTIVATION;

    if(closed_by_tp)
      return TGK_GRID_LEVEL_WAIT_RETURN;

    return TGK_GRID_LEVEL_READY;
  }

  ENUM_TGK_GRID_LEVEL_STATE StateAfterEntryFailure(
    double level_price,
    double current_price
  )
  {
    if(IsWrongSideAfterEntryMove(level_price, current_price))
      return TGK_GRID_LEVEL_WAIT_ACTIVATION;

    return TGK_GRID_LEVEL_READY;
  }

  void UpdateActivationStates(
    double previous_price,
    double current_price
  )
  {
    bool moving_to_activation =
      (m_mode == TGK_GRID_MODE_BUY)
      ? current_price > previous_price
      : current_price < previous_price;

    if(!moving_to_activation)
      return;

    for(int index = 0; index < ArraySize(m_level_prices); index++)
    {
      if(m_level_states[index] != TGK_GRID_LEVEL_WAIT_ACTIVATION)
        continue;

      if(IsCrossedForActivation(
        previous_price,
        current_price,
        m_level_prices[index]))
        m_level_states[index] = TGK_GRID_LEVEL_READY;
    }

    if(m_anchor_state == TGK_GRID_LEVEL_WAIT_ACTIVATION &&
       IsCrossedForActivation(
         previous_price,
         current_price,
         m_anchor_price))
      m_anchor_state = TGK_GRID_LEVEL_READY;
  }

  void UpdateUnselectedCrossedLevels(
    double previous_price,
    double current_price,
    bool selected_is_anchor,
    int selected_level_index
  )
  {
    for(int index = 0; index < ArraySize(m_level_prices); index++)
    {
      if(selected_level_index == index && !selected_is_anchor)
        continue;

      if(!IsEntryEligible(m_level_states[index]))
        continue;

      if(!IsCrossedForEntry(
        previous_price,
        current_price,
        m_level_prices[index]))
        continue;

      if(IsWrongSideAfterEntryMove(m_level_prices[index], current_price))
        m_level_states[index] = TGK_GRID_LEVEL_WAIT_ACTIVATION;
    }

    if(!selected_is_anchor &&
       IsEntryEligible(m_anchor_state) &&
       IsCrossedForEntry(previous_price, current_price, m_anchor_price) &&
       IsWrongSideAfterEntryMove(m_anchor_price, current_price))
      m_anchor_state = TGK_GRID_LEVEL_WAIT_ACTIVATION;
  }

public:
  CTGKGridLevelEngine()
  {
    m_mode = TGK_GRID_MODE_BUY;
    m_anchor_price = 0.0;
    m_grid_step_price = 0.0;
    m_lower_bound = 0.0;
    m_upper_bound = 0.0;
    m_anchor_state = TGK_GRID_LEVEL_ACTIVE;
    m_initialized = false;
  }

  bool Initialize(
    ENUM_TGK_GRID_MODE mode,
    double anchor_price,
    double grid_step_price,
    double lower_bound,
    double upper_bound,
    int level_count,
    double current_bid,
    double current_ask
  )
  {
    m_initialized = false;
    ArrayResize(m_level_prices, 0);
    ArrayResize(m_level_states, 0);

    if(!IsValidMode(mode) ||
       anchor_price <= 0.0 ||
       grid_step_price <= 0.0 ||
       lower_bound <= 0.0 ||
       upper_bound <= 0.0 ||
       lower_bound > upper_bound ||
       anchor_price < lower_bound ||
       anchor_price > upper_bound ||
       level_count <= 0 ||
       !IsValidQuote(current_bid, current_ask))
      return false;

    m_mode = mode;
    m_anchor_price = anchor_price;
    m_grid_step_price = grid_step_price;
    m_lower_bound = lower_bound;
    m_upper_bound = upper_bound;

    if(!BuildLevels(level_count))
      return false;

    double current_entry_price =
      (m_mode == TGK_GRID_MODE_BUY) ? current_ask : current_bid;
    InitializeStates(current_entry_price);

    m_initialized = true;
    return true;
  }

  bool IsInitialized()
  {
    return m_initialized;
  }

  int LevelCount()
  {
    if(!m_initialized)
      return 0;

    return ArraySize(m_level_prices);
  }

  double AnchorPrice()
  {
    return m_anchor_price;
  }

  bool GetLevelPrice(
    int level_index,
    double &price
  )
  {
    if(!m_initialized || !IsValidLevelIndex(level_index))
      return false;

    price = m_level_prices[level_index];
    return true;
  }

  bool GetLevelState(
    int level_index,
    ENUM_TGK_GRID_LEVEL_STATE &level_state
  )
  {
    if(!m_initialized || !IsValidLevelIndex(level_index))
      return false;

    level_state = m_level_states[level_index];
    return true;
  }

  bool SetLevelState(
    int level_index,
    ENUM_TGK_GRID_LEVEL_STATE level_state
  )
  {
    if(!m_initialized ||
       !IsValidLevelIndex(level_index) ||
       !IsValidLevelState(level_state))
      return false;

    m_level_states[level_index] = level_state;
    return true;
  }

  ENUM_TGK_GRID_LEVEL_STATE GetAnchorState()
  {
    return m_anchor_state;
  }

  bool SetAnchorState(ENUM_TGK_GRID_LEVEL_STATE level_state)
  {
    if(!m_initialized || !IsValidLevelState(level_state))
      return false;

    m_anchor_state = level_state;
    return true;
  }

  // Returns at most one candidate. BUY chooses the lowest crossed eligible
  // price; SELL chooses the highest. Equality is included at the current
  // price, while the previous price must be strictly on the approach side.
  bool UpdatePrice(
    double previous_bid,
    double previous_ask,
    double current_bid,
    double current_ask,
    bool &is_anchor,
    int &level_index,
    double &level_price
  )
  {
    is_anchor = false;
    level_index = -1;
    level_price = 0.0;

    if(!m_initialized ||
       !IsValidQuote(previous_bid, previous_ask) ||
       !IsValidQuote(current_bid, current_ask))
      return false;

    double previous_price =
      (m_mode == TGK_GRID_MODE_BUY) ? previous_ask : previous_bid;
    double current_price =
      (m_mode == TGK_GRID_MODE_BUY) ? current_ask : current_bid;

    UpdateActivationStates(previous_price, current_price);

    bool moving_to_entry =
      (m_mode == TGK_GRID_MODE_BUY)
      ? current_price < previous_price
      : current_price > previous_price;

    if(!moving_to_entry)
      return false;

    bool found = false;
    double best_price = 0.0;
    bool best_is_anchor = false;
    int best_index = -1;

    if(IsEntryEligible(m_anchor_state) &&
       IsCrossedForEntry(previous_price, current_price, m_anchor_price))
    {
      found = true;
      best_price = m_anchor_price;
      best_is_anchor = true;
    }

    for(int index = 0; index < ArraySize(m_level_prices); index++)
    {
      if(!IsEntryEligible(m_level_states[index]) ||
         !IsCrossedForEntry(
           previous_price,
           current_price,
           m_level_prices[index]))
        continue;

      double candidate_price = m_level_prices[index];
      bool is_better =
        !found ||
        (m_mode == TGK_GRID_MODE_BUY && candidate_price < best_price) ||
        (m_mode == TGK_GRID_MODE_SELL && candidate_price > best_price);

      if(is_better)
      {
        found = true;
        best_price = candidate_price;
        best_is_anchor = false;
        best_index = index;
      }
    }

    if(!found)
      return false;

    is_anchor = best_is_anchor;
    level_index = best_index;
    level_price = best_price;

    // Any other crossed eligible level now left behind the market must wait
    // for a fresh activation crossing before it can be selected again.
    UpdateUnselectedCrossedLevels(
      previous_price,
      current_price,
      is_anchor,
      level_index);

    return true;
  }

  bool RecordEntryConfirmed(
    bool is_anchor,
    int level_index
  )
  {
    if(!m_initialized)
      return false;

    if(is_anchor)
    {
      m_anchor_state = TGK_GRID_LEVEL_ACTIVE;
      return true;
    }

    if(!IsValidLevelIndex(level_index))
      return false;

    m_level_states[level_index] = TGK_GRID_LEVEL_ACTIVE;
    return true;
  }

  bool RecordEntryFailed(
    bool is_anchor,
    int level_index,
    double current_bid,
    double current_ask
  )
  {
    if(!m_initialized || !IsValidQuote(current_bid, current_ask))
      return false;

    double current_price =
      (m_mode == TGK_GRID_MODE_BUY) ? current_ask : current_bid;

    if(is_anchor)
    {
      m_anchor_state = StateAfterEntryFailure(
        m_anchor_price,
        current_price);
      return true;
    }

    if(!IsValidLevelIndex(level_index))
      return false;

    m_level_states[level_index] = StateAfterEntryFailure(
      m_level_prices[level_index],
      current_price);
    return true;
  }

  // Call only after reconciliation confirms that no position remains for
  // this logical Level. A partial close must leave the Level ACTIVE.
  bool RecordPositionClosed(
    bool is_anchor,
    int level_index,
    bool closed_by_tp,
    double current_bid,
    double current_ask
  )
  {
    if(!m_initialized || !IsValidQuote(current_bid, current_ask))
      return false;

    double current_price =
      (m_mode == TGK_GRID_MODE_BUY) ? current_ask : current_bid;

    if(is_anchor)
    {
      m_anchor_state = StateAfterPositionClose(
        m_anchor_price,
        closed_by_tp,
        current_price);
      return true;
    }

    if(!IsValidLevelIndex(level_index))
      return false;

    m_level_states[level_index] = StateAfterPositionClose(
      m_level_prices[level_index],
      closed_by_tp,
      current_price);
    return true;
  }
};

#endif
