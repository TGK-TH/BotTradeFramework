#ifndef BOTTRADE_GRID_TYPES_MQH
#define BOTTRADE_GRID_TYPES_MQH

// Grid direction is the requested direction for this Grid Instance.
// V1 receives it from Inputs; V2 can update it from an EMA strategy.
enum ENUM_TGK_GRID_MODE
{
  TGK_GRID_MODE_BUY = 0,
  TGK_GRID_MODE_SELL = 1
};

// High-level lifecycle state. Order execution is intentionally not implemented here.
enum ENUM_TGK_GRID_STATE
{
  TGK_GRID_STATE_WAIT_INITIAL_ENTRY = 0,
  TGK_GRID_STATE_ACTIVE,
  TGK_GRID_STATE_RESET_CLOSE_OLD,
  TGK_GRID_STATE_RESET_REBUILD,
  TGK_GRID_STATE_RECOVERY_ERROR
};

// Why a running Grid is being reset.
enum ENUM_TGK_GRID_RESET_REASON
{
  TGK_GRID_RESET_NONE = 0,
  TGK_GRID_RESET_MODE_CHANGED,
  TGK_GRID_RESET_STEP_CHANGED,
  TGK_GRID_RESET_MAGIC_CHANGED
};

// State for one price level in the Grid.
enum ENUM_TGK_GRID_LEVEL_STATE
{
  TGK_GRID_LEVEL_READY = 0,
  TGK_GRID_LEVEL_ACTIVE,
  TGK_GRID_LEVEL_WAIT_RETURN
};

// Persisted state for one Grid Instance.
// Keep this structure strategy-neutral so V1 and V2 can share the Grid Engine.
struct STGKGridInstanceData
{
  string instance_id;
  string symbol;
  long magic_number;

  ENUM_TGK_GRID_MODE mode;
  ENUM_TGK_GRID_STATE state;

  double anchor_price;
  double grid_step_price;
  double fixed_lot;

  ENUM_TGK_GRID_RESET_REASON reset_reason;
  ENUM_TGK_GRID_MODE pending_mode;
  double pending_grid_step_price;
  long pending_magic_number;

  int level_count;
  datetime last_state_change;
};

#endif
