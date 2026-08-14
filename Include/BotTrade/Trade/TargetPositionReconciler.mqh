#ifndef BOTTRADE_TARGET_POSITION_RECONCILER_MQH
#define BOTTRADE_TARGET_POSITION_RECONCILER_MQH

#include <Trade/Trade.mqh>

#include <BotTrade/Position/Position.mqh>
#include <BotTrade/Trade/OrderExecution.mqh>

enum ENUM_DESIRED_POSITION {
   DESIRED_POSITION_NONE = 0,
   DESIRED_POSITION_BUY  = 1,
   DESIRED_POSITION_SELL = -1
};

// Keeps a strategy's intended direction until the account is actually in that
// direction. This separates a one-bar signal from the (possibly delayed)
// broker execution caused by a daily market break or a transient error.
class CTargetPositionReconciler {
private:
   string                m_symbol;
   long                  m_magic;
   string                m_strategyId;
   ENUM_DESIRED_POSITION m_target;
   datetime              m_signalBarTime;
   datetime              m_lastAttempt;
   bool                  m_blocked;
   int                   m_retrySeconds;

   string KeyPrefix() {
      // Terminal Global Variable names are limited in length, so keep this
      // stable namespace deliberately short.
      return StringFormat("BT.%I64d.%s.%I64d.%s",
                          AccountInfoInteger(ACCOUNT_LOGIN), m_symbol,
                          m_magic, m_strategyId);
   }

   string TargetKey() { return KeyPrefix() + ".direction"; }
   string SignalBarKey() { return KeyPrefix() + ".signal_bar"; }

   void Save() {
      if(m_target == DESIRED_POSITION_NONE) {
         GlobalVariableDel(TargetKey());
         GlobalVariableDel(SignalBarKey());
         return;
      }

      GlobalVariableSet(TargetKey(), (double)m_target);
      GlobalVariableSet(SignalBarKey(), (double)m_signalBarTime);
   }

   bool SessionIsOpen() {
      MqlDateTime now;
      datetime serverTime = TimeTradeServer();
      if(serverTime == 0)
         serverTime = TimeCurrent();
      TimeToStruct(serverTime, now);

      int nowSeconds = now.hour * 3600 + now.min * 60 + now.sec;
      bool foundSession = false;

      for(uint index = 0; ; index++) {
         datetime from;
         datetime to;
         if(!SymbolInfoSessionTrade(m_symbol, (ENUM_DAY_OF_WEEK)now.day_of_week,
                                    index, from, to))
            break;

         foundSession = true;
         // SymbolInfoSessionTrade returns these values as seconds from
         // midnight; their date component must be ignored.
         int fromSeconds = (int)from % 86400;
         int toSeconds = (int)to % 86400;

         // A zero-length session is how some brokers report a full trading day.
         if(fromSeconds == toSeconds)
            return true;

         if((fromSeconds < toSeconds && nowSeconds >= fromSeconds && nowSeconds <= toSeconds) ||
            (fromSeconds > toSeconds && (nowSeconds >= fromSeconds || nowSeconds <= toSeconds)))
            return true;
      }

      // If broker metadata is unavailable, let the trade server make the
      // authoritative decision and retain the target if it rejects the order.
      return !foundSession;
   }

   bool CanTrade(ENUM_DESIRED_POSITION direction, bool isClose) {
      long mode = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_MODE);
      if(mode == SYMBOL_TRADE_MODE_DISABLED)
         return false;
      if(isClose)
         return SessionIsOpen();

      if(!SessionIsOpen())
         return false;

      if(mode == SYMBOL_TRADE_MODE_FULL)
         return true;
      if(direction == DESIRED_POSITION_BUY)
         return mode == SYMBOL_TRADE_MODE_LONGONLY;
      return mode == SYMBOL_TRADE_MODE_SHORTONLY;
   }

   bool IsSuccessfulRetcode(uint retcode) {
      return retcode == TRADE_RETCODE_DONE ||
             retcode == TRADE_RETCODE_DONE_PARTIAL ||
             retcode == TRADE_RETCODE_PLACED;
   }

   bool IsRetryableRetcode(uint retcode) {
      return retcode == TRADE_RETCODE_MARKET_CLOSED ||
             retcode == TRADE_RETCODE_REQUOTE ||
             retcode == TRADE_RETCODE_PRICE_CHANGED ||
             retcode == TRADE_RETCODE_PRICE_OFF ||
             retcode == TRADE_RETCODE_CONNECTION ||
             retcode == TRADE_RETCODE_TIMEOUT ||
             retcode == TRADE_RETCODE_TOO_MANY_REQUESTS;
   }

   void RecordResult(CTrade &trader, string action, bool requestSent) {
      uint retcode = trader.ResultRetcode();
      if(requestSent && IsSuccessfulRetcode(retcode))
         return;

      PrintFormat("BotTrade reconcile %s failed: sent=%s retcode=%u (%s)",
                  action, requestSent ? "true" : "false", retcode,
                  trader.ResultRetcodeDescription());

      if(!IsRetryableRetcode(retcode)) {
         m_blocked = true;
         Print("BotTrade reconcile is blocked until a new signal or EA restart.");
      }
   }

   bool MayAttempt() {
      if(m_blocked)
         return false;

      datetime now = TimeCurrent();
      return m_lastAttempt == 0 || now - m_lastAttempt >= m_retrySeconds;
   }

public:
   void Initialize(string symbol, long magic, string strategyId, int retrySeconds = 5) {
      m_symbol = symbol;
      m_magic = magic;
      m_strategyId = strategyId;
      m_target = DESIRED_POSITION_NONE;
      m_signalBarTime = 0;
      m_lastAttempt = 0;
      m_blocked = false;
      m_retrySeconds = retrySeconds > 0 ? retrySeconds : 5;
   }

   bool Restore() {
      if(!GlobalVariableCheck(TargetKey()))
         return false;

      int savedTarget = (int)GlobalVariableGet(TargetKey());
      if(savedTarget != DESIRED_POSITION_BUY && savedTarget != DESIRED_POSITION_SELL) {
         Clear();
         return false;
      }

      m_target = (ENUM_DESIRED_POSITION)savedTarget;
      m_signalBarTime = GlobalVariableCheck(SignalBarKey())
                        ? (datetime)GlobalVariableGet(SignalBarKey()) : 0;
      PrintFormat("BotTrade restored pending target %s from %s",
                  m_target == DESIRED_POSITION_BUY ? "BUY" : "SELL",
                  TimeToString(m_signalBarTime));
      return true;
   }

   void SetTarget(ENUM_DESIRED_POSITION target, datetime signalBarTime) {
      m_target = target;
      m_signalBarTime = signalBarTime;
      m_lastAttempt = 0;
      m_blocked = false;
      Save();
      PrintFormat("BotTrade target set to %s at %s",
                  target == DESIRED_POSITION_BUY ? "BUY" : "SELL",
                  TimeToString(signalBarTime));
   }

   void Clear() {
      m_target = DESIRED_POSITION_NONE;
      m_signalBarTime = 0;
      m_lastAttempt = 0;
      m_blocked = false;
      Save();
   }

   ENUM_DESIRED_POSITION Target() { return m_target; }

   // A pending signal is valid only while the last closed EMA relationship is
   // still in its requested direction. Equality is deliberately not valid.
   void CancelIfTrendChanged(bool fastAboveSlow, bool fastBelowSlow) {
      if((m_target == DESIRED_POSITION_BUY && !fastAboveSlow) ||
         (m_target == DESIRED_POSITION_SELL && !fastBelowSlow)) {
         Print("BotTrade pending target cancelled because the EMA relationship changed.");
         Clear();
      }
   }

   // Call on every tick. Buy/Sell values are generated immediately before the
   // request so a delayed execution uses current price, SL and risk sizing.
   void Reconcile(CTrade &trader, double lot, double sl, double tp, string comment) {
      if(m_target == DESIRED_POSITION_NONE || !MayAttempt())
         return;

      if(HasForeignNettingPosition(m_symbol, m_magic)) {
         PrintFormat("BotTrade target is waiting: netting position on %s belongs to another magic number.", m_symbol);
         m_lastAttempt = TimeCurrent();
         return;
      }

      ENUM_POSITION_TYPE targetType = m_target == DESIRED_POSITION_BUY
                                      ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      ENUM_POSITION_TYPE oppositeType = m_target == DESIRED_POSITION_BUY
                                        ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;

      if(HasPositionOfType(m_symbol, m_magic, oppositeType)) {
         if(!CanTrade(m_target, true))
            return;

         m_lastAttempt = TimeCurrent();
         bool sent = ClosePositions(trader, m_symbol, m_magic, oppositeType);
         RecordResult(trader, "close opposite position", sent);
         // Do not open in the same call: wait for a freshly selected account
         // position on the next tick/transaction cycle.
         return;
      }

      if(HasPositionOfType(m_symbol, m_magic, targetType)) {
         Clear();
         return;
      }

      if(!CanTrade(m_target, false))
         return;

      m_lastAttempt = TimeCurrent();
      bool sent = m_target == DESIRED_POSITION_BUY
                  ? ExecuteBuy(trader, m_symbol, lot, sl, tp, comment)
                  : ExecuteSell(trader, m_symbol, lot, sl, tp, comment);
      RecordResult(trader, m_target == DESIRED_POSITION_BUY ? "open BUY" : "open SELL", sent);
   }
};

#endif // BOTTRADE_TARGET_POSITION_RECONCILER_MQH
