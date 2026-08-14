//+------------------------------------------------------------------+
//|                                                     Position.mqh |
//|                                               Tatchagon Koonkoei |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Tatchagon Koonkoei"
#property link      "https://www.mql5.com"

#include <Trade/Trade.mqh>

//=====================================================
// POSITION EXISTS
//=====================================================

bool HasPosition() {
  return PositionSelect(_Symbol);
}

// Returns true only for positions owned by this EA. In a hedging account there
// can be several positions for one symbol, so PositionSelect(symbol) is not
// sufficient.
bool HasPosition(string symbol, long magic) {
   for(int index = PositionsTotal() - 1; index >= 0; index--) {
      ulong ticket = PositionGetTicket(index);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic)
         return true;
   }

   return false;
}

bool HasPositionOfType(string symbol, long magic, ENUM_POSITION_TYPE type) {
   for(int index = PositionsTotal() - 1; index >= 0; index--) {
      ulong ticket = PositionGetTicket(index);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic &&
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type)
         return true;
   }

   return false;
}

bool HasForeignNettingPosition(string symbol, long magic) {
   long marginMode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      return false;

   if(!PositionSelect(symbol))
      return false;

   return PositionGetInteger(POSITION_MAGIC) != magic;
}

void ClosePosition(
  CTrade &trader,
  string symbol,
  ENUM_POSITION_TYPE type
) {
   if(!PositionSelect(symbol))
      return;

   if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type) {
      trader.PositionClose(symbol);
   }
}

// Closes every matching position on hedging accounts, and the single matching
// position on netting accounts. A caller must inspect CTrade::ResultRetcode()
// to know whether the server executed the request.
bool ClosePositions(
  CTrade &trader,
  string symbol,
  long magic,
  ENUM_POSITION_TYPE type
) {
   bool requested = false;

   for(int index = PositionsTotal() - 1; index >= 0; index--) {
      ulong ticket = PositionGetTicket(index);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != symbol ||
         PositionGetInteger(POSITION_MAGIC) != magic ||
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type)
         continue;

      requested = trader.PositionClose(ticket) || requested;
   }

   return requested;
}
