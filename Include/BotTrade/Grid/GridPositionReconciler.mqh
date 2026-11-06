#ifndef BOTTRADE_GRID_POSITION_RECONCILER_MQH
#define BOTTRADE_GRID_POSITION_RECONCILER_MQH

// Testable position snapshot supplied by an account-reading adapter.
// This record is data only; this class never selects or modifies live positions.
struct STGKGridPositionRecord
{
  ulong ticket;
  string symbol;
  long magic_number;
};

enum ENUM_TGK_GRID_CLOSE_ATTEMPT_RESULT
{
  TGK_GRID_CLOSE_ATTEMPT_NONE = 0,
  TGK_GRID_CLOSE_ATTEMPT_ACCEPTED,
  TGK_GRID_CLOSE_ATTEMPT_MARKET_CLOSED,
  TGK_GRID_CLOSE_ATTEMPT_FAILED
};

enum ENUM_TGK_GRID_RECONCILE_STATUS
{
  TGK_GRID_RECONCILE_RETRY_REQUIRED = 0,
  TGK_GRID_RECONCILE_WAITING,
  TGK_GRID_RECONCILE_COMPLETE,
  TGK_GRID_RECONCILE_ERROR
};

// Owns the policy boundary between close-request outcomes and observed account
// state. It does not send close requests; the caller must reconcile fresh
// positions filtered by exact symbol + Magic Number on every update.
class CTGKGridPositionReconciler
{
private:
  bool m_close_request_pending;
  bool m_recovery_error;

public:
  CTGKGridPositionReconciler()
  {
    m_close_request_pending = false;
    m_recovery_error = false;
  }

  bool IsOwnedPosition(
    string expected_symbol,
    long expected_magic,
    string position_symbol,
    long position_magic
  )
  {
    if(expected_symbol == "" || expected_magic <= 0)
      return false;

    return position_symbol == expected_symbol &&
           position_magic == expected_magic;
  }

  // Read-only live account scan. Always call this again immediately before
  // advancing lifecycle/reset state; never reuse a stale position count.
  int CountLiveOwnedPositions(
    string expected_symbol,
    long expected_magic
  )
  {
    if(expected_symbol == "" || expected_magic <= 0)
      return -1;

    int count = 0;

    for(int index = PositionsTotal() - 1; index >= 0; index--)
    {
      ulong ticket = PositionGetTicket(index);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
        return -1;

      if(IsOwnedPosition(
        expected_symbol,
        expected_magic,
        PositionGetString(POSITION_SYMBOL),
        PositionGetInteger(POSITION_MAGIC)))
        count++;
    }

    return count;
  }

  int CountOwnedPositions(
    STGKGridPositionRecord &positions[],
    string expected_symbol,
    long expected_magic
  )
  {
    if(expected_symbol == "" || expected_magic <= 0)
      return -1;

    int count = 0;
    int total = ArraySize(positions);

    for(int index = 0; index < total; index++)
    {
      if(IsOwnedPosition(
        expected_symbol,
        expected_magic,
        positions[index].symbol,
        positions[index].magic_number))
        count++;
    }

    return count;
  }

  ENUM_TGK_GRID_RECONCILE_STATUS RecordCloseAttempt(
    ENUM_TGK_GRID_CLOSE_ATTEMPT_RESULT result
  )
  {
    if(m_recovery_error)
      return TGK_GRID_RECONCILE_ERROR;

    if(result == TGK_GRID_CLOSE_ATTEMPT_ACCEPTED)
    {
      // An accepted request is not proof that the server closed the position.
      m_close_request_pending = true;
      return TGK_GRID_RECONCILE_WAITING;
    }

    if(result == TGK_GRID_CLOSE_ATTEMPT_MARKET_CLOSED ||
       result == TGK_GRID_CLOSE_ATTEMPT_FAILED ||
       result == TGK_GRID_CLOSE_ATTEMPT_NONE)
    {
      m_close_request_pending = false;
      return TGK_GRID_RECONCILE_RETRY_REQUIRED;
    }

    m_close_request_pending = false;
    m_recovery_error = true;
    return TGK_GRID_RECONCILE_ERROR;
  }

  ENUM_TGK_GRID_RECONCILE_STATUS Reconcile(int remaining_positions)
  {
    if(m_recovery_error)
      return TGK_GRID_RECONCILE_ERROR;

    if(remaining_positions < 0)
    {
      m_close_request_pending = false;
      m_recovery_error = true;
      return TGK_GRID_RECONCILE_ERROR;
    }

    // Fresh account state is the source of truth, regardless of request result.
    if(remaining_positions == 0)
    {
      m_close_request_pending = false;
      return TGK_GRID_RECONCILE_COMPLETE;
    }

    if(m_close_request_pending)
    {
      // Allow one fresh observation after an accepted request. If positions
      // still remain on the next reconciliation, the caller must retry or
      // inspect the broker result instead of waiting forever.
      m_close_request_pending = false;
      return TGK_GRID_RECONCILE_WAITING;
    }

    return TGK_GRID_RECONCILE_RETRY_REQUIRED;
  }
};

#endif
