#ifndef BOTTRADE_GRID_STATE_MACHINE_MQH
#define BOTTRADE_GRID_STATE_MACHINE_MQH

#include <BotTrade/Grid/GridTypes.mqh>

// Owns Grid lifecycle transitions only. It does not inspect market data,
// submit orders, close positions, or decide whether a price is within bounds.
// The caller supplies the confirmed number of remaining positions.
class CTGKGridStateMachine
{
private:
  bool IsValidMode(ENUM_TGK_GRID_MODE mode)
  {
    return mode == TGK_GRID_MODE_BUY || mode == TGK_GRID_MODE_SELL;
  }

  bool IsValidConfiguration(
    const STGKGridInstanceData &data,
    ENUM_TGK_GRID_MODE mode,
    double step,
    long magic_number
  )
  {
    if(!IsValidMode(mode) || step <= 0.0 || magic_number <= 0)
      return false;

    if(data.instance_id == "" || data.symbol == "" || data.fixed_lot <= 0.0)
      return false;

    return true;
  }

  void SetState(STGKGridInstanceData &data, ENUM_TGK_GRID_STATE state)
  {
    if(data.state == state)
      return;

    data.state = state;
    data.last_state_change = TimeLocal();
  }

  void SetPendingConfiguration(
    STGKGridInstanceData &data,
    ENUM_TGK_GRID_MODE mode,
    double step,
    long magic_number
  )
  {
    data.pending_mode = mode;
    data.pending_grid_step_price = step;
    data.pending_magic_number = magic_number;
  }

public:
  bool Initialize(STGKGridInstanceData &data)
  {
    if(data.instance_id == "" ||
       data.symbol == "" ||
       data.magic_number <= 0 ||
       !IsValidMode(data.mode) ||
       data.grid_step_price <= 0.0 ||
       data.fixed_lot <= 0.0)
      return false;

    if(data.state == TGK_GRID_STATE_WAIT_INITIAL_ENTRY &&
       data.anchor_price > 0.0)
      SetState(data, TGK_GRID_STATE_ACTIVE);
    else if(data.state == TGK_GRID_STATE_ACTIVE &&
            data.anchor_price <= 0.0)
      SetState(data, TGK_GRID_STATE_WAIT_INITIAL_ENTRY);

    if(data.reset_reason == TGK_GRID_RESET_NONE)
      SetPendingConfiguration(
        data,
        data.mode,
        data.grid_step_price,
        data.magic_number
      );

    return true;
  }

  // The anchor must be the actual execution fill price supplied by the
  // execution layer, not the quote or level that triggered the order.
  bool RecordInitialFill(STGKGridInstanceData &data, double fill_price)
  {
    if(data.state != TGK_GRID_STATE_WAIT_INITIAL_ENTRY ||
       fill_price <= 0.0 ||
       data.reset_reason != TGK_GRID_RESET_NONE)
      return false;

    data.anchor_price = fill_price;
    data.level_count = 0;
    SetState(data, TGK_GRID_STATE_ACTIVE);
    return true;
  }

  bool RequestConfiguration(
    STGKGridInstanceData &data,
    ENUM_TGK_GRID_MODE requested_mode,
    double requested_step,
    long requested_magic_number
  )
  {
    if(data.state == TGK_GRID_STATE_RECOVERY_ERROR ||
       (data.state != TGK_GRID_STATE_ACTIVE &&
        data.state != TGK_GRID_STATE_WAIT_INITIAL_ENTRY))
      return false;

    if(!IsValidConfiguration(
      data,
      requested_mode,
      requested_step,
      requested_magic_number))
      return false;

    bool mode_changed = requested_mode != data.mode;
    bool step_changed = MathAbs(requested_step - data.grid_step_price) > 0.0;
    bool magic_changed = requested_magic_number != data.magic_number;

    if(!mode_changed && !step_changed && !magic_changed)
      return true;

    if(mode_changed)
      data.reset_reason = TGK_GRID_RESET_MODE_CHANGED;
    else if(step_changed)
      data.reset_reason = TGK_GRID_RESET_STEP_CHANGED;
    else
      data.reset_reason = TGK_GRID_RESET_MAGIC_CHANGED;

    SetPendingConfiguration(
      data,
      requested_mode,
      requested_step,
      requested_magic_number
    );
    SetState(data, TGK_GRID_STATE_RESET_CLOSE_OLD);
    return true;
  }

  // remaining_positions must come from a fresh account scan filtered by this
  // Grid's symbol and Magic Number. A successful close request is not enough.
  bool AdvanceReset(
    STGKGridInstanceData &data,
    int remaining_positions
  )
  {
    if(remaining_positions < 0 ||
       data.state == TGK_GRID_STATE_RECOVERY_ERROR)
      return false;

    if(data.state == TGK_GRID_STATE_RESET_CLOSE_OLD)
    {
      if(remaining_positions > 0)
        return true;

      SetState(data, TGK_GRID_STATE_RESET_REBUILD);
      return true;
    }

    if(data.state != TGK_GRID_STATE_RESET_REBUILD ||
       remaining_positions > 0)
      return false;

    ENUM_TGK_GRID_RESET_REASON completed_reason = data.reset_reason;

    data.mode = data.pending_mode;
    data.grid_step_price = data.pending_grid_step_price;
    data.magic_number = data.pending_magic_number;

    // A mode change starts a new Grid cycle. The new Anchor is established
    // only after the first order in the new direction actually fills.
    if(completed_reason == TGK_GRID_RESET_MODE_CHANGED)
    {
      data.anchor_price = 0.0;
      data.level_count = 0;
    }

    data.reset_reason = TGK_GRID_RESET_NONE;
    SetPendingConfiguration(
      data,
      data.mode,
      data.grid_step_price,
      data.magic_number
    );

    SetState(
      data,
      data.anchor_price > 0.0
        ? TGK_GRID_STATE_ACTIVE
        : TGK_GRID_STATE_WAIT_INITIAL_ENTRY
    );
    return true;
  }

  void SetRecoveryError(STGKGridInstanceData &data)
  {
    SetState(data, TGK_GRID_STATE_RECOVERY_ERROR);
  }
};

#endif
