#ifndef BOTTRADE_GRID_IDENTITY_MQH
#define BOTTRADE_GRID_IDENTITY_MQH

// Provides a stable identity for one Grid attached to one chart and allocates
// a terminal-wide Magic Number for that identity.
//
// The identity marker is a hidden chart object. It survives normal EA
// reinitialization and can survive closing/reopening a saved chart. ChartID()
// is used only when first creating the marker, not as the sole recovery key.
class CTGKGridIdentity
{
private:
  long   m_chart_id;
  string m_symbol;
  string m_instance_id;
  long   m_magic_number;
  string m_marker_prefix;
  string m_marker_name;
  long   m_marker_magic;

  string MagicRegistryKey()
  {
    return StringFormat(
      "TGK.M.%I64d.%s",
      AccountInfoInteger(ACCOUNT_LOGIN),
      m_instance_id
    );
  }

  string MagicSequenceKey()
  {
    return StringFormat(
      "TGK.MSEQ.%I64d",
      AccountInfoInteger(ACCOUNT_LOGIN)
    );
  }

  string MagicLockKey()
  {
    return StringFormat(
      "TGK.MLOCK.%I64d",
      AccountInfoInteger(ACCOUNT_LOGIN)
    );
  }

  bool IsMagicUsed(long magic)
  {
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
        continue;

      if((long)PositionGetInteger(POSITION_MAGIC) == magic)
        return true;
    }

    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
        continue;

      if((long)OrderGetInteger(ORDER_MAGIC) == magic)
        return true;
    }

    return false;
  }

  bool EnsureGlobalVariable(string key, double initial_value)
  {
    if(GlobalVariableCheck(key))
      return true;

    ResetLastError();
    if(GlobalVariableSet(key, initial_value) == 0)
    {
      // Another chart may have created it between our check and set.
      if(GlobalVariableCheck(key))
        return true;

      PrintFormat(
        "TGK Grid identity: cannot initialize %s (error=%d)",
        key,
        GetLastError()
      );
      return false;
    }

    return true;
  }

  bool AcquireLock(string key)
  {
    if(!EnsureGlobalVariable(key, 0.0))
      return false;

    // The terminal processes chart events serially in normal operation. The
    // bounded retry also protects against a concurrently held allocation lock.
    for(int attempt = 0; attempt < 100; attempt++)
    {
      if(GlobalVariableSetOnCondition(key, 1.0, 0.0))
        return true;
    }

    Print("TGK Grid identity: Magic Number allocator lock is busy.");
    return false;
  }

  void ReleaseLock(string key)
  {
    GlobalVariableSet(key, 0.0);
    GlobalVariablesFlush();
  }

  bool FindMarker(string &found_id)
  {
    int total = ObjectsTotal(m_chart_id, 0, -1);

    for(int i = 0; i < total; i++)
    {
      string name = ObjectName(m_chart_id, i, 0, -1);
      if(StringFind(name, m_marker_prefix) != 0)
        continue;

      string marker_data = StringSubstr(name, StringLen(m_marker_prefix));
      int magic_separator = StringFind(marker_data, "_M");
      if(magic_separator >= 0)
      {
        found_id = StringSubstr(marker_data, 0, magic_separator);
        string magic_text = StringSubstr(marker_data, magic_separator + 2);
        m_marker_magic = (long)StringToInteger(magic_text);
      }
      else
      {
        found_id = marker_data;
        m_marker_magic = 0;
      }

      m_marker_name = name;
      return StringLen(found_id) > 0;
    }

    return false;
  }

  bool CreateMarker()
  {
    // ChartID seeds the identity once. The final marker name also stores the
    // assigned Magic Number so it can be recovered if Terminal Global Variables
    // expire while the chart is closed.
    m_instance_id = "C" + IntegerToString(m_chart_id);
    m_marker_magic = 0;
    m_marker_name = m_marker_prefix + m_instance_id;

    if(ObjectFind(m_chart_id, m_marker_name) >= 0)
      return true;

    ResetLastError();
    if(!ObjectCreate(m_chart_id, m_marker_name, OBJ_LABEL, 0, 0, 0))
    {
      PrintFormat(
        "TGK Grid identity: cannot create chart marker (error=%d)",
        GetLastError()
      );
      m_instance_id = "";
      return false;
    }

    ObjectSetString(m_chart_id, m_marker_name, OBJPROP_TEXT, "");
    ObjectSetInteger(m_chart_id, m_marker_name, OBJPROP_HIDDEN, true);
    ObjectSetInteger(m_chart_id, m_marker_name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(m_chart_id, m_marker_name, OBJPROP_SELECTED, false);
    ChartRedraw(m_chart_id);

    return true;
  }

  bool UpdateMarkerMagic(long magic)
  {
    if(m_marker_name == "" || magic <= 0)
      return false;

    string new_name = m_marker_prefix + m_instance_id + "_M" +
                      IntegerToString(magic);
    if(new_name == m_marker_name)
    {
      m_marker_magic = magic;
      return true;
    }

    if(ObjectFind(m_chart_id, new_name) >= 0)
    {
      m_marker_name = new_name;
      m_marker_magic = magic;
      return true;
    }

    ResetLastError();
    if(!ObjectCreate(m_chart_id, new_name, OBJ_LABEL, 0, 0, 0))
    {
      PrintFormat(
        "TGK Grid identity: cannot create Magic Number marker (error=%d)",
        GetLastError()
      );
      return false;
    }

    ObjectSetString(m_chart_id, new_name, OBJPROP_TEXT, "");
    ObjectSetInteger(m_chart_id, new_name, OBJPROP_HIDDEN, true);
    ObjectSetInteger(m_chart_id, new_name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(m_chart_id, new_name, OBJPROP_SELECTED, false);

    ObjectDelete(m_chart_id, m_marker_name);
    m_marker_name = new_name;
    m_marker_magic = magic;
    ChartRedraw(m_chart_id);
    return true;
  }

  bool AllocateMagic()
  {
    string registry_key = MagicRegistryKey();

    // Prefer the Magic Number embedded in the chart marker. This allows
    // recovery even if terminal Global Variables expired while the chart was
    // closed for a long period.
    if(m_marker_magic > 0)
    {
      if(GlobalVariableCheck(registry_key))
      {
        long registered_magic = (long)GlobalVariableGet(registry_key);
        if(registered_magic != m_marker_magic)
        {
          Print("TGK Grid identity: chart marker and Magic registry disagree.");
          return false;
        }
      }
      else if(GlobalVariableSet(registry_key, (double)m_marker_magic) == 0)
      {
        Print("TGK Grid identity: cannot restore Magic Number registry.");
        return false;
      }

      m_magic_number = m_marker_magic;
      GlobalVariablesFlush();
      return true;
    }

    // Reuse the same Magic Number whenever this Grid identity is restored.
    if(GlobalVariableCheck(registry_key))
    {
      m_magic_number = (long)GlobalVariableGet(registry_key);
      if(m_magic_number <= 0)
      {
        Print("TGK Grid identity: saved Magic Number is invalid.");
        return false;
      }

      return UpdateMarkerMagic(m_magic_number);
    }

    string lock_key = MagicLockKey();
    if(!AcquireLock(lock_key))
      return false;

    // Recheck after taking the lock in case another initialization allocated
    // the number while this instance was waiting.
    if(GlobalVariableCheck(registry_key))
    {
      m_magic_number = (long)GlobalVariableGet(registry_key);
      ReleaseLock(lock_key);
      return m_magic_number > 0 && UpdateMarkerMagic(m_magic_number);
    }

    string sequence_key = MagicSequenceKey();
    if(!EnsureGlobalVariable(sequence_key, 710000.0))
    {
      ReleaseLock(lock_key);
      return false;
    }

    bool allocated = false;
    for(int attempt = 0; attempt < 10000; attempt++)
    {
      long candidate = (long)GlobalVariableGet(sequence_key) + 1;
      if(candidate <= 0 || candidate > 2147483000)
      {
        Print("TGK Grid identity: Magic Number sequence exhausted.");
        break;
      }

      if(!GlobalVariableSetOnCondition(sequence_key,
                                       (double)candidate,
                                       (double)(candidate - 1)))
        continue;

      if(IsMagicUsed(candidate))
        continue;

      if(GlobalVariableSet(registry_key, (double)candidate) == 0)
        break;

      m_magic_number = candidate;
      allocated = true;
      GlobalVariablesFlush();
      break;
    }

    ReleaseLock(lock_key);

    if(!allocated)
    {
      Print("TGK Grid identity: failed to allocate a unique Magic Number.");
      return false;
    }

    if(!UpdateMarkerMagic(m_magic_number))
      return false;

    return true;
  }

public:
  bool Initialize(long chart_id, string symbol)
  {
    m_chart_id = chart_id;
    m_symbol = symbol;
    m_instance_id = "";
    m_magic_number = 0;
    m_marker_prefix = "TGK_GID_";

    if(m_chart_id <= 0 || StringLen(m_symbol) == 0)
      return false;

    string found_id;
    if(FindMarker(found_id))
    {
      m_instance_id = found_id;
    }
    else if(!CreateMarker())
    {
      return false;
    }

    if(m_instance_id == "")
      return false;

    return AllocateMagic();
  }

  string InstanceId()
  {
    return m_instance_id;
  }

  long MagicNumber()
  {
    return m_magic_number;
  }

  string Symbol()
  {
    return m_symbol;
  }
};

#endif
