#ifndef BOTTRADE_GRID_ORDER_EXECUTION_ADAPTER_MQH
#define BOTTRADE_GRID_ORDER_EXECUTION_ADAPTER_MQH

#include <Trade/Trade.mqh>

#include <BotTrade/Grid/GridOrderExecutionPolicy.mqh>

enum ENUM_TGK_GRID_EXECUTION_RESULT
{
  TGK_GRID_EXECUTION_NO_ACTION = 0,
  TGK_GRID_EXECUTION_BATCH_SUBMITTED,
  TGK_GRID_EXECUTION_NO_POSITIONS,
  TGK_GRID_EXECUTION_SCAN_FAILED,
  TGK_GRID_EXECUTION_INVALID_IDENTITY
};

// Live adapter for reset/close execution. It only closes positions owned by
// the configured Symbol + Magic Number and only when Runtime says CLOSE_REQUIRED.
class CTGKGridOrderExecutionAdapter
{
private:
  CTGKGridOrderExecutionPolicy m_policy;
  string m_symbol;
  long m_magic_number;
  bool m_initialized;

  int ReadOwnedPositionSnapshot(STGKGridPositionRecord &positions[])
  {
    ArrayResize(positions, 0);

    int total = PositionsTotal();
    for(int index = total - 1; index >= 0; index--)
    {
      ulong ticket = PositionGetTicket(index);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
        return -1;

      int next = ArraySize(positions);
      ArrayResize(positions, next + 1);
      positions[next].ticket = ticket;
      positions[next].symbol = PositionGetString(POSITION_SYMBOL);
      positions[next].magic_number = PositionGetInteger(POSITION_MAGIC);
    }

    return ArraySize(positions);
  }

public:
  CTGKGridOrderExecutionAdapter()
  {
    m_symbol = "";
    m_magic_number = 0;
    m_initialized = false;
  }

  bool Initialize(string symbol, long magic_number)
  {
    m_initialized = false;

    if(symbol == "" || magic_number <= 0)
      return false;

    m_symbol = symbol;
    m_magic_number = magic_number;
    m_initialized = true;
    return true;
  }

  // One call attempts every currently observed owned ticket. The aggregate
  // result is reported once; Runtime must perform a fresh account scan later.
  ENUM_TGK_GRID_EXECUTION_RESULT ExecuteCloseIfRequired(
    ENUM_TGK_GRID_RUNTIME_STATUS runtime_status,
    CTGKGridRuntimeOrchestrator &runtime,
    CTrade &trader
  )
  {
    if(runtime_status != TGK_GRID_RUNTIME_CLOSE_REQUIRED)
      return TGK_GRID_EXECUTION_NO_ACTION;

    if(!m_initialized || !runtime.MatchesIdentity(m_symbol, m_magic_number))
      return TGK_GRID_EXECUTION_INVALID_IDENTITY;

    STGKGridPositionRecord positions[];
    if(ReadOwnedPositionSnapshot(positions) < 0)
    {
      runtime.RecordCloseAttempt(TGK_GRID_CLOSE_ATTEMPT_FAILED);
      return TGK_GRID_EXECUTION_SCAN_FAILED;
    }

    ulong tickets[];
    if(!m_policy.BuildCloseBatch(
      runtime_status,
      positions,
      m_symbol,
      m_magic_number,
      tickets))
    {
      runtime.RecordCloseAttempt(TGK_GRID_CLOSE_ATTEMPT_FAILED);
      return TGK_GRID_EXECUTION_INVALID_IDENTITY;
    }

    int ticket_count = ArraySize(tickets);
    if(ticket_count == 0)
    {
      // The snapshot is fresh and contains no owned positions. Let Runtime
      // reconcile that observation instead of recording a fictitious request.
      if(runtime.UpdateLive() == TGK_GRID_RUNTIME_ERROR)
        return TGK_GRID_EXECUTION_SCAN_FAILED;

      return TGK_GRID_EXECUTION_NO_POSITIONS;
    }

    ENUM_TGK_GRID_CLOSE_ATTEMPT_RESULT outcomes[];
    ArrayResize(outcomes, ticket_count);

    for(int index = 0; index < ticket_count; index++)
    {
      bool request_sent = trader.PositionClose(tickets[index]);
      uint retcode = trader.ResultRetcode();
      outcomes[index] = m_policy.ClassifyCloseResult(
        request_sent,
        retcode);

      if(!request_sent)
      {
        PrintFormat(
          "TGK Grid close failed: symbol=%s magic=%I64d ticket=%I64u retcode=%u (%s)",
          m_symbol,
          m_magic_number,
          tickets[index],
          retcode,
          trader.ResultRetcodeDescription());
      }
    }

    ENUM_TGK_GRID_CLOSE_ATTEMPT_RESULT batch_result =
      m_policy.CombineCloseResults(outcomes);
    runtime.RecordCloseAttempt(batch_result);

    return TGK_GRID_EXECUTION_BATCH_SUBMITTED;
  }

  bool IsInitialized()
  {
    return m_initialized;
  }
};

#endif
