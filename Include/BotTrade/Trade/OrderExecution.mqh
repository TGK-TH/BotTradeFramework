#include <Trade/Trade.mqh>

bool ExecuteBuy(
  CTrade &trader,
  string symbol,
  double lot,
  double sl,
  double tp,
  string comment = ""
) {
  return trader.Buy(
    lot,
    symbol,
    0,
    sl,
    tp,
    comment
  );
}

bool ExecuteSell(
  CTrade &trader,
  string symbol,
  double lot,
  double sl,
  double tp,
  string comment = ""
) {
  return trader.Sell(
    lot,
    symbol,
    0,
    sl,
    tp,
    comment
  );
}
