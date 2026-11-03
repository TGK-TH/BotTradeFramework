#ifndef BOTTRADE_GRID_LEVEL_ENGINE_MQH
#define BOTTRADE_GRID_LEVEL_ENGINE_MQH

#include <BotTrade/Grid/GridTypes.mqh>

// Pure Grid level calculation and entry-candidate selection.
// This class does not send orders and does not mutate level state when it
// selects a candidate. The caller updates state after its execution workflow
// confirms the corresponding lifecycle event.
class CTGKGridLevelEngine
{
private:
  ENUM_TGK_GRID_MODE m_mode;
  double m_anchor_price;
  double m_grid_step_price;
  double m_lower_bound;
  double m_upper_bound;
  int m_level_count;
  ENUM_TGK_GRID_LEVEL_STATE m_level_states[];
  bool m_initialized;

  bool IsValidMode(ENUM_TGK_GRID_MODE mode)
  {
    return mode == TGK_GRID_MODE_BUY || mode == TGK_GRID_MODE_SELL;
  }

  bool IsValidLevelState(ENUM_TGK_GRID_LEVEL_STATE state)
  {
    return state >= TGK_GRID_LEVEL_READY &&
           state <= TGK_GRID_LEVEL_WAIT_RETURN;
  }

  double CalculateRawLevelPrice(int level_index)
  {
    double distance = m_grid_step_price * (level_index + 1);

    if(m_mode == TGK_GRID_MODE_BUY)
      return m_anchor_price - distance;

    return m_anchor_price + distance;
  }

public:
  CTGKGridLevelEngine()
  {
    m_mode = TGK_GRID_MODE_BUY;
    m_anchor_price = 0.0;
    m_grid_step_price = 0.0;
    m_lower_bound = 0.0;
    m_upper_bound = 0.0;
    m_level_count = 0;
    m_initialized = false;
  }

  bool Initialize(
    ENUM_TGK_GRID_MODE mode,
    double anchor_price,
    double grid_step_price,
    double lower_bound,
    double upper_bound,
    int level_count
  )
  {
    m_initialized = false;
    ArrayResize(m_level_states, 0);

    if(!IsValidMode(mode) ||
       anchor_price <= 0.0 ||
       grid_step_price <= 0.0 ||
       lower_bound <= 0.0 ||
       upper_bound <= 0.0 ||
       lower_bound > upper_bound ||
       anchor_price < lower_bound ||
       anchor_price > upper_bound ||
       level_count <= 0)
      return false;

    m_mode = mode;
    m_anchor_price = anchor_price;
    m_grid_step_price = grid_step_price;
    m_lower_bound = lower_bound;
    m_upper_bound = upper_bound;
    m_level_count = level_count;

    if(ArrayResize(m_level_states, m_level_count) != m_level_count)
    {
      m_level_count = 0;
      return false;
    }

    for(int index = 0; index < m_level_count; index++)
      m_level_states[index] = TGK_GRID_LEVEL_READY;

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

    return m_level_count;
  }

  bool GetLevelPrice(int level_index, double &price)
  {
    if(!m_initialized ||
       level_index < 0 ||
       level_index >= m_level_count)
      return false;

    double candidate = CalculateRawLevelPrice(level_index);
    if(candidate < m_lower_bound || candidate > m_upper_bound)
      return false;

    price = candidate;
    return true;
  }

  bool GetLevelState(
    int level_index,
    ENUM_TGK_GRID_LEVEL_STATE &level_state
  )
  {
    if(!m_initialized ||
       level_index < 0 ||
       level_index >= m_level_count)
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
       level_index < 0 ||
       level_index >= m_level_count ||
       !IsValidLevelState(level_state))
      return false;

    m_level_states[level_index] = level_state;
    return true;
  }

  // BUY candidates use Ask and are approached from above (downward).
  // SELL candidates use Bid and are approached from below (upward).
  // Levels are checked from nearest to farthest from Anchor, so a price gap
  // crossing several levels selects only the first level crossed.
  bool FindEntryLevel(
    double previous_bid,
    double previous_ask,
    double current_bid,
    double current_ask,
    int &level_index,
    double &level_price
  )
  {
    level_index = -1;
    level_price = 0.0;

    if(!m_initialized ||
       previous_bid <= 0.0 ||
       previous_ask <= 0.0 ||
       current_bid <= 0.0 ||
       current_ask <= 0.0)
      return false;

    double previous_entry_price =
      (m_mode == TGK_GRID_MODE_BUY) ? previous_ask : previous_bid;
    double current_entry_price =
      (m_mode == TGK_GRID_MODE_BUY) ? current_ask : current_bid;

    if(current_entry_price > previous_entry_price)
    {
      if(m_mode == TGK_GRID_MODE_BUY)
        return false;
    }
    else if(current_entry_price < previous_entry_price)
    {
      if(m_mode == TGK_GRID_MODE_SELL)
        return false;
    }

    for(int index = 0; index < m_level_count; index++)
    {
      double candidate = CalculateRawLevelPrice(index);
      if(candidate < m_lower_bound || candidate > m_upper_bound)
        continue;

      if(m_level_states[index] != TGK_GRID_LEVEL_READY)
        continue;

      bool touched_or_crossed = false;
      if(m_mode == TGK_GRID_MODE_BUY)
        touched_or_crossed =
          previous_entry_price >= candidate &&
          current_entry_price <= candidate;
      else
        touched_or_crossed =
          previous_entry_price <= candidate &&
          current_entry_price >= candidate;

      if(!touched_or_crossed)
        continue;

      level_index = index;
      level_price = candidate;
      return true;
    }

    return false;
  }
};

#endif
