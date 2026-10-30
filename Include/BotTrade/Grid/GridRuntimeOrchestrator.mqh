#ifndef BOTTRADE_GRID_RUNTIME_ORCHESTRATOR_MQH
#define BOTTRADE_GRID_RUNTIME_ORCHESTRATOR_MQH

#include <BotTrade/Grid/GridLifecycle.mqh>
#include <BotTrade/Grid/GridPositionReconciler.mqh>

// Result of one orchestration update. CLOSE_REQUIRED is a signal to the
// execution adapter; this class never sends a close request itself.
enum ENUM_TGK_GRID_RUNTIME_STATUS
{
  TGK_GRID_RUNTIME_ERROR = 0,
  TGK_GRID_RUNTIME_WAIT_INITIAL_ENTRY,
  TGK_GRID_RUNTIME_ACTIVE,
  TGK_GRID_RUNTIME_CLOSE_REQUIRED,
  TGK_GRID_RUNTIME_WAIT_CLOSE_CONFIRMATION
};

// Coordinates one already-identified Grid Instance. Identity allocation,
// order execution, market data, and price-level decisions remain outside.
class CTGKGridRuntimeOrchestrator
{
private:
  CTGKGridLifecycle m_lifecycle;
  CTGKGridPositionReconciler m_reconciler;
  string m_instance_id;
  string m_symbol;
  long m_magic_number;
  bool m_initialized;

  ENUM_TGK_GRID_RUNTIME_STATUS StatusFromData(
    const STGKGridInstanceData &data
  )
  {
    if(data.state == TGK_GRID_STATE_RECOVERY_ERROR)
      return TGK_GRID_RUNTIME_ERROR;

    if(data.state == TGK_GRID_STATE_WAIT_INITIAL_ENTRY)
      return TGK_GRID_RUNTIME_WAIT_INITIAL_ENTRY;

    if(data.state == TGK_GRID_STATE_ACTIVE)
      return TGK_GRID_RUNTIME_ACTIVE;

    if(data.state == TGK_GRID_STATE_RESET_CLOSE_OLD)
      return TGK_GRID_RUNTIME_CLOSE_REQUIRED;

    return TGK_GRID_RUNTIME_ERROR;
  }

  bool InitializeWithCount(
    string instance_id,
    string symbol,
    long magic_number,
    ENUM_TGK_GRID_MODE mode,
    double step,
    double fixed_lot,
    int remaining_positions
  )
  {
    m_initialized = false;

    if(instance_id == "" ||
       symbol == "" ||
       magic_number <= 0 ||
       remaining_positions < 0)
      return false;

    if(!m_lifecycle.Initialize(
      instance_id,
      symbol,
      magic_number,
      mode,
      step,
      fixed_lot,
      remaining_positions))
      return false;

    m_instance_id = instance_id;
    m_symbol = symbol;
    m_magic_number = magic_number;
    m_initialized = true;
    return true;
  }

  ENUM_TGK_GRID_RUNTIME_STATUS UpdateWithCount(int remaining_positions)
  {
    if(!m_initialized)
      return TGK_GRID_RUNTIME_ERROR;

    ENUM_TGK_GRID_RECONCILE_STATUS reconcile_status =
      m_reconciler.Reconcile(remaining_positions);

    if(reconcile_status == TGK_GRID_RECONCILE_ERROR)
    {
      m_lifecycle.SetRecoveryError();
      return TGK_GRID_RUNTIME_ERROR;
    }

    STGKGridInstanceData data;
    if(!m_lifecycle.GetData(data))
      return TGK_GRID_RUNTIME_ERROR;

    if(data.state == TGK_GRID_STATE_RECOVERY_ERROR)
      return TGK_GRID_RUNTIME_ERROR;

    if(data.state == TGK_GRID_STATE_RESET_CLOSE_OLD)
    {
      if(reconcile_status == TGK_GRID_RECONCILE_RETRY_REQUIRED)
        return TGK_GRID_RUNTIME_CLOSE_REQUIRED;

      if(reconcile_status == TGK_GRID_RECONCILE_WAITING)
        return TGK_GRID_RUNTIME_WAIT_CLOSE_CONFIRMATION;

      if(reconcile_status == TGK_GRID_RECONCILE_COMPLETE)
      {
        if(!m_lifecycle.AdvanceReset(0))
          return TGK_GRID_RUNTIME_ERROR;

        if(!m_lifecycle.AdvanceReset(0))
          return TGK_GRID_RUNTIME_ERROR;

        if(!m_lifecycle.GetData(data))
          return TGK_GRID_RUNTIME_ERROR;
      }
    }
    else if(data.state == TGK_GRID_STATE_RESET_REBUILD)
    {
      if(remaining_positions != 0)
      {
        m_lifecycle.SetRecoveryError();
        return TGK_GRID_RUNTIME_ERROR;
      }

      if(!m_lifecycle.AdvanceReset(0))
        return TGK_GRID_RUNTIME_ERROR;

      if(!m_lifecycle.GetData(data))
        return TGK_GRID_RUNTIME_ERROR;
    }

    return StatusFromData(data);
  }

public:
  CTGKGridRuntimeOrchestrator()
  {
    m_instance_id = "";
    m_symbol = "";
    m_magic_number = 0;
    m_initialized = false;
  }

  // Production initialization: caller must initialize CTGKGridIdentity first.
  // The initial position count is obtained from a fresh live account scan.
  bool InitializeLive(
    string instance_id,
    string symbol,
    long magic_number,
    ENUM_TGK_GRID_MODE mode,
    double step,
    double fixed_lot
  )
  {
    int count = m_reconciler.CountLiveOwnedPositions(symbol, magic_number);
    if(count < 0)
      return false;

    return InitializeWithCount(
      instance_id,
      symbol,
      magic_number,
      mode,
      step,
      fixed_lot,
      count);
  }

  // Snapshot entry point for deterministic tests; records are filtered by
  // exact Symbol + Magic Number inside the reconciler.
  bool InitializeFromSnapshot(
    string instance_id,
    string symbol,
    long magic_number,
    ENUM_TGK_GRID_MODE mode,
    double step,
    double fixed_lot,
    STGKGridPositionRecord &positions[]
  )
  {
    int count = m_reconciler.CountOwnedPositions(
      positions,
      symbol,
      magic_number);
    if(count < 0)
      return false;

    return InitializeWithCount(
      instance_id,
      symbol,
      magic_number,
      mode,
      step,
      fixed_lot,
      count);
  }

  ENUM_TGK_GRID_RUNTIME_STATUS UpdateLive()
  {
    if(!m_initialized)
      return TGK_GRID_RUNTIME_ERROR;

    int count = m_reconciler.CountLiveOwnedPositions(
      m_symbol,
      m_magic_number);
    return UpdateWithCount(count);
  }

  ENUM_TGK_GRID_RUNTIME_STATUS UpdateFromSnapshot(
    STGKGridPositionRecord &positions[]
  )
  {
    if(!m_initialized)
      return TGK_GRID_RUNTIME_ERROR;

    int count = m_reconciler.CountOwnedPositions(
      positions,
      m_symbol,
      m_magic_number);
    return UpdateWithCount(count);
  }

  bool RequestConfiguration(
    ENUM_TGK_GRID_MODE requested_mode,
    double requested_step
  )
  {
    return m_initialized &&
           m_lifecycle.RequestConfiguration(
             requested_mode,
             requested_step);
  }

  ENUM_TGK_GRID_RECONCILE_STATUS RecordCloseAttempt(
    ENUM_TGK_GRID_CLOSE_ATTEMPT_RESULT result
  )
  {
    if(!m_initialized)
      return TGK_GRID_RECONCILE_ERROR;

    return m_reconciler.RecordCloseAttempt(result);
  }

  bool RecordInitialFill(double actual_fill_price)
  {
    return m_initialized &&
           m_lifecycle.RecordInitialFill(actual_fill_price);
  }

  bool GetData(STGKGridInstanceData &data)
  {
    return m_initialized && m_lifecycle.GetData(data);
  }

  bool IsInitialized()
  {
    return m_initialized;
  }
};

#endif
