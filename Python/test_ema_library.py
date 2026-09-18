import pandas as pd
import pandas_ta_classic as ta

df = pd.DataFrame({
  "close": [100, 101, 102, 103, 104, 105]
})

df["ema_3"] = ta.ema(df["close"], length=3)

print(df)
