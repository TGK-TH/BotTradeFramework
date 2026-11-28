#ifndef BOTTRADE_GRID_ORDER_EXECUTION_POLICY_MQH
#define BOTTRADE_GRID_ORDER_EXECUTION_POLICY_MQH

#include <Trade/Trade.mqh>

#include <BotTrade/Grid/GridRuntimeOrchestrator.mqh>

// Pure decision logic shared by Unit Tests and the live execution adapter.
// It selects tickets and classifies outcomes but never sends trade requests.
class CTGKGridOrderExecutionPolicy
{
public:
  bool BuildCloseBatch(
    ENUM_TGK_GRID_RUNTIME_STATUS runtime_status,
    STGKGridPositionRecord &positions[],
    string expected_symbol,
    long expected_magic,
    ulong &tickets[]
  )
  {
    ArrayResize(tickets, 0);

    if(runtime_status != TGK_GRID_RUNTIME_CLOSE_REQUIRED ||
       expected_symbol == "" ||
       expected_magic <= 0)
      return false;

    int total = ArraySize(positions);
    for(int index = 0; index < total; index++)
    {
      if(positions[index].ticket == 0)
      {
        ArrayResize(tickets, 0);
        return false;
      }

      if(positions[index].symbol != expected_symbol ||
         positions[index].magic_number != expected_magic)
        continue;

      int next = ArraySize(tickets);
      ArrayResize(tickets, next + 1);
      tickets[next] = positions[index].ticket;
    }

    return true;
  }

  ENUM_TGK_GRID_CLOSE_ATTEMPT_RESULT ClassifyCloseResult(
    bool request_sent,
    uint retcode
  )
  {
    if(!request_sent)
      return TGK_GRID_CLOSE_ATTEMPT_FAILED;

    if(retcode == TRADE_RETCODE_DONE ||
       retcode == TRADE_RETCODE_DONE_PARTIAL ||
       retcode == TRADE_RETCODE_PLACED)
      return TGK_GRID_CLOSE_ATTEMPT_ACCEPTED;

    if(retcode == TRADE_RETCODE_MARKET_CLOSED)
      return TGK_GRID_CLOSE_ATTEMPT_MARKET_CLOSED;

    return TGK_GRID_CLOSE_ATTEMPT_FAILED;
  }

  ENUM_TGK_GRID_CLOSE_ATTEMPT_RESULT CombineCloseResults(
    ENUM_TGK_GRID_CLOSE_ATTEMPT_RESULT &results[]
  )
  {
    int total = ArraySize(results);
    if(total == 0)
      return TGK_GRID_CLOSE_ATTEMPT_FAILED;

    bool has_market_closed = false;
    bool has_failed = false;

    for(int index = 0; index < total; index++)
    {
      if(results[index] == TGK_GRID_CLOSE_ATTEMPT_FAILED ||
         results[index] == TGK_GRID_CLOSE_ATTEMPT_NONE)
        has_failed = true;
      else if(results[index] == TGK_GRID_CLOSE_ATTEMPT_MARKET_CLOSED)
        has_market_closed = true;
      else if(results[index] != TGK_GRID_CLOSE_ATTEMPT_ACCEPTED)
        has_failed = true;
    }

    if(has_failed)
      return TGK_GRID_CLOSE_ATTEMPT_FAILED;

    if(has_market_closed)
      return TGK_GRID_CLOSE_ATTEMPT_MARKET_CLOSED;

    return TGK_GRID_CLOSE_ATTEMPT_ACCEPTED;
  }
};

#endif
