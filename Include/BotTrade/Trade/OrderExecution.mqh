#include <Trade/Trade.mqh>

bool ExecuteBuy(
  CTrade &trade,
  string symbol,
  double lot,
  double sl,
  double tp,
  string comment = ""
) {
  return trade.Buy(
    lot,
    symbol,
    0,
    sl,
    tp,
    comment
  );
}

bool ExecuteSell(
  CTrade &trade,
  string symbol,
  double lot,
  double sl,
  double tp,
  string comment = ""
) {
  return trade.Sell(
    lot,
    symbol,
    0,
    sl,
    tp,
    comment
  );
}
