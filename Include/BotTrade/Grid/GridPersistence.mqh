#ifndef BOTTRADE_GRID_PERSISTENCE_MQH
#define BOTTRADE_GRID_PERSISTENCE_MQH

#include <BotTrade/Grid/GridTypes.mqh>

// Persists one Grid Instance using MT5 Terminal Global Variables.
// instance_id must be short and stable across EA restarts. Identity allocation
// is deliberately separate from this storage class.
class CTGKGridPersistence
{
private:
  string m_symbol;
  string m_instance_id;
  string m_prefix;

  string Key(string suffix)
  {
    return m_prefix + "." + suffix;
  }

  bool WriteValue(string suffix, double value)
  {
    ResetLastError();
    datetime modified = GlobalVariableSet(Key(suffix), value);
    if(modified == 0)
    {
      PrintFormat(
        "TGK Grid persistence: failed to save %s (error=%d)",
        Key(suffix),
        GetLastError()
      );
      return false;
    }

    return true;
  }

  bool ReadValue(string suffix, double &value)
  {
    string key = Key(suffix);
    if(!GlobalVariableCheck(key))
      return false;

    value = GlobalVariableGet(key);
    return true;
  }

public:
  // Uses a short namespace to stay within MT5's Terminal Global Variable
  // name-length limit. The caller owns the lifecycle of instance_id.
  bool Initialize(string symbol, string instance_id)
  {
    if(StringLen(symbol) == 0 || StringLen(instance_id) == 0)
      return false;

    m_symbol = symbol;
    m_instance_id = instance_id;

    // The instance id is included in the namespace so separate charts using
    // the same symbol do not share persisted state.
    m_prefix = StringFormat("TGK.G.%I64d.%s.%s",
                            AccountInfoInteger(ACCOUNT_LOGIN),
                            m_symbol,
                            m_instance_id);

    if(StringLen(m_prefix) + StringLen(".pending_magic") > 63)
    {
      PrintFormat(
        "TGK Grid persistence: key prefix too long (%d characters)",
        StringLen(m_prefix) + StringLen(".pending_magic")
      );
      m_prefix = "";
      return false;
    }

    return true;
  }

  string InstanceId()
  {
    return m_instance_id;
  }

  // Distinguishes a missing snapshot from a present but invalid snapshot.
  bool HasSnapshot()
  {
    return m_prefix != "" && GlobalVariableCheck(Key("commit"));
  }

  // Writes the commit marker last. A failed or interrupted save should not be
  // treated as a complete snapshot by Restore().
  bool Save(const STGKGridInstanceData &data)
  {
    if(m_prefix == "" || data.instance_id != m_instance_id ||
       data.symbol != m_symbol)
      return false;

    // Invalidate the previous snapshot before updating fields. If a save fails
    // halfway through, Restore() must not accept a mixture of old and new values.
    GlobalVariableDel(Key("commit"));
    GlobalVariablesFlush();

    if(!WriteValue("schema", 1))
      return false;
    if(!WriteValue("magic", (double)data.magic_number))
      return false;
    if(!WriteValue("mode", (double)data.mode))
      return false;
    if(!WriteValue("state", (double)data.state))
      return false;
    if(!WriteValue("anchor", data.anchor_price))
      return false;
    if(!WriteValue("step", data.grid_step_price))
      return false;
    if(!WriteValue("lot", data.fixed_lot))
      return false;
    if(!WriteValue("reset_reason", (double)data.reset_reason))
      return false;
    if(!WriteValue("pending_mode", (double)data.pending_mode))
      return false;
    if(!WriteValue("pending_step", data.pending_grid_step_price))
      return false;
    if(!WriteValue("pending_magic", (double)data.pending_magic_number))
      return false;
    if(!WriteValue("level_count", (double)data.level_count))
      return false;
    if(!WriteValue("state_time", (double)data.last_state_change))
      return false;

    // Commit marker is updated only after all required fields are written.
    if(!WriteValue("commit", (double)TimeLocal()))
      return false;

    GlobalVariablesFlush();
    return true;
  }

  bool Restore(STGKGridInstanceData &data)
  {
    double schema;
    double value;

    if(m_prefix == "" || !ReadValue("commit", value))
      return false;
    if(!ReadValue("schema", schema) || (int)schema != 1)
    {
      PrintFormat(
        "TGK Grid persistence: missing or unsupported schema for %s",
        m_instance_id
      );
      return false;
    }

    data.instance_id = m_instance_id;
    data.symbol = m_symbol;

    if(!ReadValue("magic", value))
      return false;
    data.magic_number = (long)value;

    if(!ReadValue("mode", value))
      return false;
    if((int)value != TGK_GRID_MODE_BUY && (int)value != TGK_GRID_MODE_SELL)
      return false;
    data.mode = (ENUM_TGK_GRID_MODE)(int)value;

    if(!ReadValue("state", value))
      return false;
    if((int)value < TGK_GRID_STATE_WAIT_INITIAL_ENTRY ||
       (int)value > TGK_GRID_STATE_RECOVERY_ERROR)
      return false;
    data.state = (ENUM_TGK_GRID_STATE)(int)value;

    if(!ReadValue("anchor", data.anchor_price) ||
       !ReadValue("step", data.grid_step_price) ||
       !ReadValue("lot", data.fixed_lot))
      return false;

    if(!ReadValue("reset_reason", value))
      return false;
    if((int)value < TGK_GRID_RESET_NONE ||
       (int)value > TGK_GRID_RESET_MAGIC_CHANGED)
      return false;
    data.reset_reason = (ENUM_TGK_GRID_RESET_REASON)(int)value;

    if(!ReadValue("pending_mode", value))
      return false;
    if((int)value != TGK_GRID_MODE_BUY && (int)value != TGK_GRID_MODE_SELL)
      return false;
    data.pending_mode = (ENUM_TGK_GRID_MODE)(int)value;

    if(!ReadValue("pending_step", data.pending_grid_step_price) ||
       !ReadValue("pending_magic", value))
      return false;
    data.pending_magic_number = (long)value;

    if(!ReadValue("level_count", value))
      return false;
    data.level_count = (int)value;
    if(data.level_count < 0)
      return false;

    if(!ReadValue("state_time", value))
      return false;
    data.last_state_change = (datetime)value;

    return true;
  }

  bool SaveLevelState(int level_index, ENUM_TGK_GRID_LEVEL_STATE level_state)
  {
    if(m_prefix == "" || level_index < 0 ||
       level_state < TGK_GRID_LEVEL_READY ||
       level_state > TGK_GRID_LEVEL_WAIT_RETURN)
      return false;

    if(!WriteValue(StringFormat("lv.%d", level_index), (double)level_state))
      return false;

    GlobalVariablesFlush();
    return true;
  }

  bool RestoreLevelState(int level_index, ENUM_TGK_GRID_LEVEL_STATE &level_state)
  {
    double value;
    if(m_prefix == "" || level_index < 0 ||
       !ReadValue(StringFormat("lv.%d", level_index), value))
      return false;

    if((int)value < TGK_GRID_LEVEL_READY ||
       (int)value > TGK_GRID_LEVEL_WAIT_RETURN)
      return false;

    level_state = (ENUM_TGK_GRID_LEVEL_STATE)(int)value;
    return true;
  }

  bool DeleteState(int level_count)
  {
    if(m_prefix == "")
      return false;

    string keys[] =
    {
      "schema", "magic", "mode", "state", "anchor", "step", "lot",
      "reset_reason", "pending_mode", "pending_step", "pending_magic",
      "level_count", "state_time", "commit"
    };

    for(int i = 0; i < ArraySize(keys); i++)
      GlobalVariableDel(Key(keys[i]));

    for(int level = 0; level < level_count; level++)
      GlobalVariableDel(Key(StringFormat("lv.%d", level)));

    GlobalVariablesFlush();
    return true;
  }
};

#endif
