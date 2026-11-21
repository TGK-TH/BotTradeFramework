#ifndef BOTTRADE_GRID_LIFECYCLE_MQH
#define BOTTRADE_GRID_LIFECYCLE_MQH

#include <BotTrade/Grid/GridPersistence.mqh>
#include <BotTrade/Grid/GridStateMachine.mqh>

// Coordinates persistence and lifecycle transitions for one already-identified
// Grid Instance. The EA initializes CTGKGridIdentity first and passes its
// stable Instance ID and Magic Number here. This class never sends trade orders.
// The caller supplies a fresh count of positions filtered by symbol and magic.
class CTGKGridLifecycle
{
private:
  CTGKGridPersistence m_persistence;
  CTGKGridStateMachine m_state_machine;
  STGKGridInstanceData m_data;
  bool m_initialized;

  bool IsValidMode(ENUM_TGK_GRID_MODE mode)
  {
    return mode == TGK_GRID_MODE_BUY || mode == TGK_GRID_MODE_SELL;
  }

  void InitializeData(
    string instance_id,
    string symbol,
    long magic_number,
    ENUM_TGK_GRID_MODE mode,
    double step,
    double fixed_lot
  )
  {
    m_data.instance_id = instance_id;
    m_data.symbol = symbol;
    m_data.magic_number = magic_number;
    m_data.mode = mode;
    m_data.state = TGK_GRID_STATE_WAIT_INITIAL_ENTRY;
    m_data.anchor_price = 0.0;
    m_data.grid_step_price = step;
    m_data.fixed_lot = fixed_lot;
    m_data.reset_reason = TGK_GRID_RESET_NONE;
    m_data.pending_mode = mode;
    m_data.pending_grid_step_price = step;
    m_data.pending_magic_number = magic_number;
    m_data.level_count = 0;
    m_data.last_state_change = TimeLocal();
  }

  bool SaveCurrentState()
  {
    if(!m_persistence.Save(m_data))
    {
      m_state_machine.SetRecoveryError(m_data);
      return false;
    }

    return true;
  }

  bool MatchesPendingConfiguration(
    ENUM_TGK_GRID_MODE requested_mode,
    double requested_step
  )
  {
    return m_data.pending_mode == requested_mode &&
           MathAbs(m_data.pending_grid_step_price - requested_step) <= 0.0;
  }

public:
  CTGKGridLifecycle()
  {
    m_initialized = false;
  }

  // A missing/invalid snapshot with remaining positions is unsafe to adopt.
  // Such an instance is kept in RECOVERY_ERROR instead of starting a new grid.
  bool Initialize(
    string instance_id,
    string symbol,
    long magic_number,
    ENUM_TGK_GRID_MODE requested_mode,
    double requested_step,
    double requested_lot,
    int remaining_positions
  )
  {
    m_initialized = false;

    if(instance_id == "" ||
       symbol == "" ||
       magic_number <= 0 ||
       !IsValidMode(requested_mode) ||
       requested_step <= 0.0 ||
       requested_lot <= 0.0 ||
       remaining_positions < 0)
      return false;

    if(!m_persistence.Initialize(symbol, instance_id))
      return false;

    bool snapshot_exists = m_persistence.HasSnapshot();
    bool restored_ok = m_persistence.Restore(m_data);

    if(snapshot_exists && !restored_ok)
    {
      InitializeData(
        instance_id,
        symbol,
        magic_number,
        requested_mode,
        requested_step,
        requested_lot);
      m_state_machine.SetRecoveryError(m_data);
      m_initialized = true;
      PrintFormat(
        "TGK Grid lifecycle: snapshot exists but is invalid for %s; recovery required.",
        instance_id);
      return true;
    }

    if(restored_ok)
    {
      if(m_data.instance_id != instance_id ||
         m_data.symbol != symbol ||
         m_data.magic_number != magic_number ||
         MathAbs(m_data.fixed_lot - requested_lot) > 0.0)
      {
        m_state_machine.SetRecoveryError(m_data);
        SaveCurrentState();
        m_initialized = true;
        PrintFormat(
          "TGK Grid lifecycle: restored identity or fixed lot does not match current configuration for %s.",
          instance_id);
        return true;
      }

      if(!m_state_machine.Initialize(m_data))
      {
        m_state_machine.SetRecoveryError(m_data);
        SaveCurrentState();
        m_initialized = true;
        PrintFormat(
          "TGK Grid lifecycle: restored state is invalid for %s; recovery required.",
          instance_id);
        return true;
      }

      if(m_data.state == TGK_GRID_STATE_RECOVERY_ERROR)
      {
        m_initialized = true;
        return true;
      }

      if(m_data.state == TGK_GRID_STATE_RESET_CLOSE_OLD ||
         m_data.state == TGK_GRID_STATE_RESET_REBUILD)
      {
        if(!MatchesPendingConfiguration(requested_mode, requested_step))
        {
          m_state_machine.SetRecoveryError(m_data);
          SaveCurrentState();
          m_initialized = true;
          PrintFormat(
            "TGK Grid lifecycle: requested inputs changed during a pending reset for %s.",
            instance_id);
          return true;
        }
      }
      else if(!m_state_machine.RequestConfiguration(
        m_data,
        requested_mode,
        requested_step,
        magic_number))
      {
        m_state_machine.SetRecoveryError(m_data);
        m_initialized = true;
        return true;
      }

      if(!SaveCurrentState())
      {
        m_initialized = true;
        return true;
      }

      m_initialized = true;
      return true;
    }

    InitializeData(
      instance_id,
      symbol,
      magic_number,
      requested_mode,
      requested_step,
      requested_lot);

    if(remaining_positions > 0)
    {
      m_state_machine.SetRecoveryError(m_data);
      // Persist the error state so a restart does not silently start a new grid.
      SaveCurrentState();
      m_initialized = true;
      PrintFormat(
        "TGK Grid lifecycle: no snapshot but %d positions remain for %s; recovery required.",
        remaining_positions,
        instance_id);
      return true;
    }

    if(!m_state_machine.Initialize(m_data))
      return false;

    if(!SaveCurrentState())
      return false;

    m_initialized = true;
    return true;
  }

  bool GetData(STGKGridInstanceData &data)
  {
    if(!m_initialized)
      return false;

    data = m_data;
    return true;
  }

  bool RecordInitialFill(double fill_price)
  {
    if(!m_initialized ||
       !m_state_machine.RecordInitialFill(m_data, fill_price))
      return false;

    return SaveCurrentState();
  }

  bool RequestConfiguration(
    ENUM_TGK_GRID_MODE requested_mode,
    double requested_step
  )
  {
    if(!m_initialized)
      return false;

    if(!m_state_machine.RequestConfiguration(
      m_data,
      requested_mode,
      requested_step,
      m_data.magic_number))
      return false;

    if(!SaveCurrentState())
      return false;

    // The caller must close positions and later supply a fresh count to
    // AdvanceReset(). This class does not issue close requests.
    return true;
  }

  bool AdvanceReset(int remaining_positions)
  {
    if(!m_initialized ||
       !m_state_machine.AdvanceReset(m_data, remaining_positions))
      return false;

    return SaveCurrentState();
  }

  bool SetRecoveryError()
  {
    if(!m_initialized)
      return false;

    m_state_machine.SetRecoveryError(m_data);
    return SaveCurrentState();
  }

  bool IsInitialized()
  {
    return m_initialized;
  }
};

#endif
