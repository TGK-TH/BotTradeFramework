#ifndef BOTTRADE_GRID_ENTRY_MAPPING_REDUCER_MQH
#define BOTTRADE_GRID_ENTRY_MAPPING_REDUCER_MQH

#include <BotTrade/Grid/GridTypes.mqh>
#include <BotTrade/Grid/GridEntryMappingStorage.mqh>

// Typed payload version is independent from the outer Journal record schema.
#define TGK_GRID_MAPPING_PAYLOAD_VERSION "v1"

struct STGKGridMappingRequestState
{
  string request_id;
  string mode;
  string target_kind;
  int level_index;
  double requested_volume;
  long config_epoch;
  string execution_outcome;
  string order_ticket;
  string deal_ticket;
  bool has_execution_result;
  bool unresolved;
};

struct STGKGridMappingDealState
{
  string request_id;
  string deal_ticket;
  string position_identifier;
  double volume;
};

struct STGKGridMappingPositionState
{
  string request_id;
  string symbol;
  long magic_number;
  string target_kind;
  int level_index;
  string position_identifier;
  string position_ticket;
  double volume;
  long config_epoch;
};

struct STGKGridMappingLevelState
{
  long config_epoch;
  int level_index;
  ENUM_TGK_GRID_LEVEL_STATE state;
};

// Deterministically reduces typed Journal events into the current mapping state.
// It has no Trade API dependency and never reads Order Comments.
class CTGKGridEntryMappingReducer
{
private:
  string m_symbol;
  string m_instance_id;
  long m_magic_number;
  long m_last_sequence;
  long m_config_epoch;
  string m_mode;
  double m_grid_step;
  double m_lower_bound;
  double m_upper_bound;
  double m_anchor_price;
  int m_level_count;
  bool m_initialized;
  bool m_failed;

  STGKGridMappingRequestState m_requests[];
  STGKGridMappingDealState m_deals[];
  STGKGridMappingPositionState m_positions[];
  STGKGridMappingLevelState m_levels[];

  bool IsToken(string value)
  {
    int length = StringLen(value);
    if(length <= 0)
      return false;

    for(int i = 0; i < length; i++)
    {
      ushort c = StringGetCharacter(value, i);
      bool valid = (c >= 'A' && c <= 'Z') ||
                   (c >= 'a' && c <= 'z') ||
                   (c >= '0' && c <= '9') ||
                   c == '_' || c == '-';
      if(!valid)
        return false;
    }
    return true;
  }

  bool IsDecimalString(string value, bool allow_zero = false)
  {
    int length = StringLen(value);
    if(length <= 0)
      return false;
    if(length > 1 && StringGetCharacter(value, 0) == '0')
      return false;

    for(int i = 0; i < length; i++)
    {
      ushort c = StringGetCharacter(value, i);
      if(c < '0' || c > '9')
        return false;
    }

    if(!allow_zero && value == "0")
      return false;
    return true;
  }

  bool IsSignedIntegerString(string value)
  {
    int length = StringLen(value);
    if(length <= 0)
      return false;

    int start = 0;
    if(StringGetCharacter(value, 0) == '-')
    {
      if(length == 1)
        return false;
      start = 1;
    }

    if(length - start > 1 && StringGetCharacter(value, start) == '0')
      return false;

    for(int i = start; i < length; i++)
    {
      ushort c = StringGetCharacter(value, i);
      if(c < '0' || c > '9')
        return false;
    }
    return true;
  }

  bool IsNumberString(string value, bool allow_negative = false)
  {
    int length = StringLen(value);
    if(length <= 0)
      return false;

    int start = 0;
    if(StringGetCharacter(value, 0) == '-')
    {
      if(!allow_negative || length == 1)
        return false;
      start = 1;
    }

    bool has_digit = false;
    bool has_dot = false;
    for(int i = start; i < length; i++)
    {
      ushort c = StringGetCharacter(value, i);
      if(c >= '0' && c <= '9')
      {
        has_digit = true;
        continue;
      }
      if(c == '.' && !has_dot)
      {
        has_dot = true;
        continue;
      }
      return false;
    }
    return has_digit;
  }

  bool ParsePositiveDouble(string value, double &parsed)
  {
    if(!IsNumberString(value))
      return false;
    parsed = StringToDouble(value);
    return MathIsValidNumber(parsed) && parsed > 0.0;
  }

  bool ParseSignedInteger(string value, int &parsed)
  {
    if(!IsSignedIntegerString(value))
      return false;
    long parsed_long = StringToInteger(value);
    if(parsed_long < -2147483647 || parsed_long > 2147483647)
      return false;
    parsed = (int)parsed_long;
    return StringFormat("%d", parsed) == value;
  }

  bool ParsePositiveLong(string value, long &parsed)
  {
    if(!IsDecimalString(value))
      return false;
    parsed = StringToInteger(value);
    return parsed > 0 && StringFormat("%I64d", parsed) == value;
  }

  bool ParseMagic(string value, long &parsed)
  {
    if(!IsDecimalString(value, true))
      return false;
    parsed = StringToInteger(value);
    return parsed > 0 && StringFormat("%I64d", parsed) == value;
  }

  bool SplitPayload(
    string payload,
    string &fields[],
    int expected_count)
  {
    ArrayResize(fields, 0);
    int count = StringSplit(payload, '|', fields);
    if(count != expected_count)
      return false;
    if(fields[0] != TGK_GRID_MAPPING_PAYLOAD_VERSION)
      return false;
    for(int i = 0; i < count; i++)
    {
      if(fields[i] == "")
        return false;
    }
    return true;
  }

  int FindRequest(string request_id)
  {
    for(int i = 0; i < ArraySize(m_requests); i++)
    {
      if(m_requests[i].request_id == request_id)
        return i;
    }
    return -1;
  }

  int FindDeal(string deal_ticket)
  {
    for(int i = 0; i < ArraySize(m_deals); i++)
    {
      if(m_deals[i].deal_ticket == deal_ticket)
        return i;
    }
    return -1;
  }

  int FindPositionByIdentifier(string position_identifier)
  {
    for(int i = 0; i < ArraySize(m_positions); i++)
    {
      if(m_positions[i].position_identifier == position_identifier)
        return i;
    }
    return -1;
  }

  int FindPositionByTarget(string target_kind, int level_index)
  {
    for(int i = 0; i < ArraySize(m_positions); i++)
    {
      if(m_positions[i].target_kind == target_kind &&
         m_positions[i].level_index == level_index)
        return i;
    }
    return -1;
  }

  int FindPositionByTicket(string position_ticket)
  {
    for(int i = 0; i < ArraySize(m_positions); i++)
    {
      if(m_positions[i].position_ticket == position_ticket)
        return i;
    }
    return -1;
  }

  int FindLevel(int level_index)
  {
    for(int i = 0; i < ArraySize(m_levels); i++)
    {
      if(m_levels[i].config_epoch == m_config_epoch &&
         m_levels[i].level_index == level_index)
        return i;
    }
    return -1;
  }

  bool HasUnresolvedRequestInternal()
  {
    for(int i = 0; i < ArraySize(m_requests); i++)
    {
      if(m_requests[i].unresolved)
        return true;
    }
    return false;
  }

  void RemoveRequestAt(int index)
  {
    int count = ArraySize(m_requests);
    for(int i = index; i < count - 1; i++)
      m_requests[i] = m_requests[i + 1];
    ArrayResize(m_requests, count - 1);
  }

  void RemoveDealAt(int index)
  {
    int count = ArraySize(m_deals);
    for(int i = index; i < count - 1; i++)
      m_deals[i] = m_deals[i + 1];
    ArrayResize(m_deals, count - 1);
  }

  void RemovePositionAt(int index)
  {
    int count = ArraySize(m_positions);
    for(int i = index; i < count - 1; i++)
      m_positions[i] = m_positions[i + 1];
    ArrayResize(m_positions, count - 1);
  }

  void RemoveDealsForRequest(string request_id)
  {
    for(int i = ArraySize(m_deals) - 1; i >= 0; i--)
    {
      if(m_deals[i].request_id == request_id)
        RemoveDealAt(i);
    }
  }

  bool SetLevelState(int level_index, ENUM_TGK_GRID_LEVEL_STATE state)
  {
    int index = FindLevel(level_index);
    if(index < 0)
    {
      index = ArraySize(m_levels);
      if(ArrayResize(m_levels, index + 1) != index + 1)
        return false;
      m_levels[index].config_epoch = m_config_epoch;
      m_levels[index].level_index = level_index;
    }
    m_levels[index].state = state;
    return true;
  }

  bool IsAcceptedOutcome(string outcome)
  {
    return outcome == "ACCEPTED" ||
           outcome == "PLACED" ||
           outcome == "DONE" ||
           outcome == "DONE_PARTIAL";
  }

  bool IsFailedOutcome(string outcome)
  {
    return outcome == "FAILED" ||
           outcome == "REJECTED" ||
           outcome == "MARKET_CLOSED";
  }

  bool ParseLevelState(
    string value,
    ENUM_TGK_GRID_LEVEL_STATE &state)
  {
    if(value == "READY")
      state = TGK_GRID_LEVEL_READY;
    else if(value == "ACTIVE")
      state = TGK_GRID_LEVEL_ACTIVE;
    else if(value == "WAIT_RETURN")
      state = TGK_GRID_LEVEL_WAIT_RETURN;
    else if(value == "WAIT_ACTIVATION")
      state = TGK_GRID_LEVEL_WAIT_ACTIVATION;
    else
      return false;
    return true;
  }

  bool ApplyEntryIntent(string payload)
  {
    string fields[];
    if(!SplitPayload(payload, fields, 10))
      return false;

    string request_id = fields[1];
    string symbol = fields[2];
    long magic = 0;
    long config_epoch = 0;
    int level_index = 0;
    double volume = 0.0;

    if(!IsToken(request_id) ||
       symbol != m_symbol ||
       !ParseMagic(fields[3], magic) ||
       magic != m_magic_number ||
       (fields[4] != "BUY" && fields[4] != "SELL") ||
       (fields[5] != "ANCHOR" && fields[5] != "LEVEL") ||
       !ParseSignedInteger(fields[6], level_index) ||
       !ParsePositiveDouble(fields[7], volume) ||
       !ParsePositiveLong(fields[8], config_epoch) ||
       fields[9] != m_instance_id)
      return false;

    if(config_epoch != m_config_epoch ||
       fields[4] != m_mode ||
       FindRequest(request_id) >= 0 ||
       HasUnresolvedRequestInternal())
      return false;

    if(fields[5] == "ANCHOR")
    {
      if(level_index != -1 ||
         FindPositionByTarget("ANCHOR", -1) >= 0)
        return false;
    }
    else
    {
      int level_state_index = FindLevel(level_index);
      if(level_index == -1 ||
         MathAbs(level_index) > m_level_count ||
         level_state_index < 0 ||
         (m_levels[level_state_index].state != TGK_GRID_LEVEL_READY &&
          m_levels[level_state_index].state != TGK_GRID_LEVEL_WAIT_RETURN) ||
         FindPositionByTarget("LEVEL", level_index) >= 0)
        return false;
    }

    int index = ArraySize(m_requests);
    if(ArrayResize(m_requests, index + 1) != index + 1)
      return false;

    m_requests[index].request_id = request_id;
    m_requests[index].mode = fields[4];
    m_requests[index].target_kind = fields[5];
    m_requests[index].level_index = level_index;
    m_requests[index].requested_volume = volume;
    m_requests[index].config_epoch = config_epoch;
    m_requests[index].execution_outcome = "";
    m_requests[index].order_ticket = "0";
    m_requests[index].deal_ticket = "0";
    m_requests[index].has_execution_result = false;
    m_requests[index].unresolved = true;
    return true;
  }

  bool ApplyExecutionResult(string payload)
  {
    string fields[];
    if(!SplitPayload(payload, fields, 5))
      return false;

    int request_index = FindRequest(fields[1]);
    if(request_index < 0 ||
       !m_requests[request_index].unresolved ||
       m_requests[request_index].has_execution_result ||
       !IsToken(fields[1]))
      return false;

    string outcome = fields[2];
    if(!IsAcceptedOutcome(outcome) && !IsFailedOutcome(outcome))
      return false;

    if(!IsDecimalString(fields[3], true) ||
       !IsDecimalString(fields[4], true))
      return false;

    if(IsFailedOutcome(outcome))
    {
      for(int i = 0; i < ArraySize(m_deals); i++)
      {
        if(m_deals[i].request_id == fields[1])
          return false;
      }
      m_requests[request_index].unresolved = false;
    }

    m_requests[request_index].execution_outcome = outcome;
    m_requests[request_index].order_ticket = fields[3];
    m_requests[request_index].deal_ticket = fields[4];
    m_requests[request_index].has_execution_result = true;
    if(IsFailedOutcome(outcome))
      RemoveRequestAt(request_index);
    return true;
  }

  bool ApplyDealAssociation(string payload)
  {
    string fields[];
    if(!SplitPayload(payload, fields, 5))
      return false;

    int request_index = FindRequest(fields[1]);
    if(request_index < 0 ||
       !m_requests[request_index].unresolved ||
       !m_requests[request_index].has_execution_result ||
       !IsAcceptedOutcome(m_requests[request_index].execution_outcome) ||
       !IsToken(fields[1]) ||
       !IsDecimalString(fields[2]) ||
       !IsDecimalString(fields[3]))
      return false;

    double volume = 0.0;
    if(!ParsePositiveDouble(fields[4], volume) ||
       FindDeal(fields[2]) >= 0 ||
       FindPositionByIdentifier(fields[3]) >= 0)
      return false;

    double associated_volume = volume;
    for(int i = 0; i < ArraySize(m_deals); i++)
    {
      if(m_deals[i].position_identifier == fields[3] &&
         m_deals[i].request_id != fields[1])
        return false;
      if(m_deals[i].request_id == fields[1])
      {
        if(m_deals[i].position_identifier != fields[3])
          return false;
        associated_volume += m_deals[i].volume;
      }
    }
    if(associated_volume > m_requests[request_index].requested_volume + 0.00000001)
      return false;

    int index = ArraySize(m_deals);
    if(ArrayResize(m_deals, index + 1) != index + 1)
      return false;

    m_deals[index].request_id = fields[1];
    m_deals[index].deal_ticket = fields[2];
    m_deals[index].position_identifier = fields[3];
    m_deals[index].volume = volume;
    return true;
  }

  bool ApplyPositionMapping(string payload)
  {
    string fields[];
    if(!SplitPayload(payload, fields, 11))
      return false;

    int request_index = FindRequest(fields[1]);
    if(request_index < 0 ||
       !m_requests[request_index].unresolved ||
       !m_requests[request_index].has_execution_result ||
       !IsAcceptedOutcome(m_requests[request_index].execution_outcome) ||
       !IsToken(fields[1]))
      return false;

    long magic = 0;
    long config_epoch = 0;
    int level_index = 0;
    double volume = 0.0;

    if(fields[2] != m_symbol ||
       !ParseMagic(fields[3], magic) ||
       magic != m_magic_number ||
       (fields[4] != "ANCHOR" && fields[4] != "LEVEL") ||
       !ParseSignedInteger(fields[5], level_index) ||
       !IsDecimalString(fields[6]) ||
       !IsDecimalString(fields[7]) ||
       !ParsePositiveDouble(fields[8], volume) ||
       !ParsePositiveLong(fields[9], config_epoch) ||
       fields[10] != m_instance_id)
      return false;

    if(config_epoch != m_config_epoch ||
       m_requests[request_index].config_epoch != config_epoch ||
       m_requests[request_index].target_kind != fields[4] ||
       m_requests[request_index].level_index != level_index)
      return false;

    if(fields[4] == "ANCHOR" && level_index != -1)
      return false;
    if(fields[4] == "LEVEL" &&
       (level_index == -1 || MathAbs(level_index) > m_level_count))
      return false;

    if(FindPositionByIdentifier(fields[6]) >= 0 ||
       FindPositionByTicket(fields[7]) >= 0 ||
       FindPositionByTarget(fields[4], level_index) >= 0 ||
       volume > m_requests[request_index].requested_volume + 0.00000001)
      return false;

    int matching_deals = 0;
    double associated_volume = 0.0;
    for(int i = 0; i < ArraySize(m_deals); i++)
    {
      if(m_deals[i].request_id != fields[1])
        continue;
      if(m_deals[i].position_identifier != fields[6])
        return false;
      matching_deals++;
      associated_volume += m_deals[i].volume;
    }
    if(matching_deals == 0 ||
       volume > associated_volume + 0.00000001)
      return false;

    if(fields[4] == "LEVEL")
    {
      int level_index_in_state = FindLevel(level_index);
      if(level_index_in_state < 0 ||
         (m_levels[level_index_in_state].state != TGK_GRID_LEVEL_READY &&
          m_levels[level_index_in_state].state != TGK_GRID_LEVEL_WAIT_RETURN))
        return false;
    }

    int index = ArraySize(m_positions);
    if(ArrayResize(m_positions, index + 1) != index + 1)
      return false;

    m_positions[index].request_id = fields[1];
    m_positions[index].symbol = fields[2];
    m_positions[index].magic_number = magic;
    m_positions[index].target_kind = fields[4];
    m_positions[index].level_index = level_index;
    m_positions[index].position_identifier = fields[6];
    m_positions[index].position_ticket = fields[7];
    m_positions[index].volume = volume;
    m_positions[index].config_epoch = config_epoch;

    if(fields[4] == "LEVEL" &&
       !SetLevelState(level_index, TGK_GRID_LEVEL_ACTIVE))
      return false;

    m_requests[request_index].unresolved = false;
    return true;
  }

  bool ApplyLevelState(string &fields[])
  {
    if(fields[1] != "LEVEL_STATE" || ArraySize(fields) != 5)
      return false;

    long config_epoch = 0;
    int level_index = 0;
    ENUM_TGK_GRID_LEVEL_STATE state;
    if(!ParsePositiveLong(fields[2], config_epoch) ||
       config_epoch != m_config_epoch ||
       !ParseSignedInteger(fields[3], level_index) ||
       level_index == -1 ||
       MathAbs(level_index) > m_level_count ||
       !ParseLevelState(fields[4], state))
      return false;

    int position_index = FindPositionByTarget("LEVEL", level_index);
    if(state == TGK_GRID_LEVEL_ACTIVE && position_index < 0)
      return false;
    if(state != TGK_GRID_LEVEL_ACTIVE && position_index >= 0)
      return false;

    return SetLevelState(level_index, state);
  }

  bool ApplyPositionVolume(string &fields[])
  {
    if(ArraySize(fields) != 4 || fields[1] != "POSITION_VOLUME")
      return false;

    int position_index = FindPositionByIdentifier(fields[2]);
    double volume = 0.0;
    if(position_index < 0 ||
       !ParsePositiveDouble(fields[3], volume) ||
       volume >= m_positions[position_index].volume)
      return false;

    m_positions[position_index].volume = volume;
    return true;
  }

  bool ApplyPositionTicket(string &fields[])
  {
    if(ArraySize(fields) != 4 || fields[1] != "POSITION_TICKET")
      return false;

    int position_index = FindPositionByIdentifier(fields[2]);
    if(position_index < 0 || !IsDecimalString(fields[3]))
      return false;

    int existing_ticket_index = FindPositionByTicket(fields[3]);
    if(existing_ticket_index >= 0 && existing_ticket_index != position_index)
      return false;

    m_positions[position_index].position_ticket = fields[3];
    return true;
  }

  bool ApplyPositionClosed(string &fields[])
  {
    if(ArraySize(fields) != 5 || fields[1] != "POSITION_CLOSED")
      return false;

    int position_index = FindPositionByIdentifier(fields[2]);
    if(position_index < 0)
      return false;

    string request_id = m_positions[position_index].request_id;
    string target_kind = m_positions[position_index].target_kind;
    int level_index = m_positions[position_index].level_index;
    ENUM_TGK_GRID_LEVEL_STATE next_state;

    if(fields[3] != "TP" && fields[3] != "NON_TP")
      return false;
    if(target_kind == "LEVEL")
    {
      if(!ParseLevelState(fields[4], next_state) ||
         next_state == TGK_GRID_LEVEL_ACTIVE)
        return false;
      if(fields[3] == "TP" && next_state != TGK_GRID_LEVEL_WAIT_RETURN)
        return false;
      if(fields[3] == "NON_TP" &&
         next_state != TGK_GRID_LEVEL_READY &&
         next_state != TGK_GRID_LEVEL_WAIT_ACTIVATION)
        return false;
    }
    else if(fields[4] != "NONE")
    {
      return false;
    }

    RemovePositionAt(position_index);
    RemoveDealsForRequest(request_id);
    int request_index = FindRequest(request_id);
    if(request_index >= 0)
      RemoveRequestAt(request_index);

    if(target_kind == "LEVEL")
      return SetLevelState(level_index, next_state);
    return true;
  }

  bool ApplyResetCommitted(string &fields[])
  {
    if(ArraySize(fields) != 9 || fields[1] != "RESET_COMMITTED")
      return false;

    long config_epoch = 0;
    double grid_step = 0.0;
    double lower_bound = 0.0;
    double upper_bound = 0.0;
    double anchor = 0.0;
    long level_count = 0;

    if(!ParsePositiveLong(fields[2], config_epoch) ||
       config_epoch <= m_config_epoch ||
       (fields[3] != "BUY" && fields[3] != "SELL") ||
       !ParsePositiveDouble(fields[4], grid_step) ||
       !IsNumberString(fields[5], true) ||
       !IsNumberString(fields[6], true) ||
       !ParsePositiveDouble(fields[7], anchor) ||
       !ParsePositiveLong(fields[8], level_count) ||
       level_count > 100000)
      return false;

    lower_bound = StringToDouble(fields[5]);
    upper_bound = StringToDouble(fields[6]);
    if(!MathIsValidNumber(lower_bound) ||
       !MathIsValidNumber(upper_bound) ||
       lower_bound > upper_bound ||
       anchor < lower_bound ||
       anchor > upper_bound)
      return false;

    if(ArraySize(m_positions) > 0 || HasUnresolvedRequestInternal())
      return false;

    ArrayResize(m_levels, 0);
    ArrayResize(m_deals, 0);
    ArrayResize(m_requests, 0);

    m_config_epoch = config_epoch;
    m_mode = fields[3];
    m_grid_step = grid_step;
    m_lower_bound = lower_bound;
    m_upper_bound = upper_bound;
    m_anchor_price = anchor;
    m_level_count = (int)level_count;
    return true;
  }

  bool ApplyLifecycleUpdate(string payload)
  {
    string fields[];
    int count = StringSplit(payload, '|', fields);
    if(count < 2 || fields[0] != TGK_GRID_MAPPING_PAYLOAD_VERSION)
      return false;

    if(fields[1] == "LEVEL_STATE")
      return ApplyLevelState(fields);
    if(fields[1] == "POSITION_VOLUME")
      return ApplyPositionVolume(fields);
    if(fields[1] == "POSITION_TICKET")
      return ApplyPositionTicket(fields);
    if(fields[1] == "POSITION_CLOSED")
      return ApplyPositionClosed(fields);
    if(fields[1] == "RESET_COMMITTED")
      return ApplyResetCommitted(fields);
    return false;
  }

  bool ApplyRecord(STGKGridMappingJournalRecord &record)
  {
    if(record.sequence != m_last_sequence + 1)
      return false;

    bool applied = false;
    switch(record.record_type)
    {
      case TGK_GRID_MAPPING_RECORD_ENTRY_INTENT:
        applied = ApplyEntryIntent(record.payload);
        break;
      case TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT:
        applied = ApplyExecutionResult(record.payload);
        break;
      case TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION:
        applied = ApplyDealAssociation(record.payload);
        break;
      case TGK_GRID_MAPPING_RECORD_POSITION_MAPPING:
        applied = ApplyPositionMapping(record.payload);
        break;
      case TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE:
        applied = ApplyLifecycleUpdate(record.payload);
        break;
      default:
        return false;
    }

    if(!applied)
      return false;
    m_last_sequence = record.sequence;
    return true;
  }

public:
  CTGKGridEntryMappingReducer()
  {
    m_symbol = "";
    m_instance_id = "";
    m_magic_number = 0;
    m_last_sequence = 0;
    m_config_epoch = 0;
    m_mode = "";
    m_grid_step = 0.0;
    m_lower_bound = 0.0;
    m_upper_bound = 0.0;
    m_anchor_price = 0.0;
    m_level_count = 0;
    m_initialized = false;
    m_failed = false;
  }

  bool Initialize(
    string symbol,
    long magic_number,
    string instance_id)
  {
    m_initialized = false;
    m_failed = false;
    if(symbol == "" ||
       magic_number <= 0 ||
       !IsToken(instance_id))
      return false;

    m_symbol = symbol;
    m_instance_id = instance_id;
    m_magic_number = magic_number;
    m_last_sequence = 0;
    m_config_epoch = 0;
    m_mode = "";
    m_grid_step = 0.0;
    m_lower_bound = 0.0;
    m_upper_bound = 0.0;
    m_anchor_price = 0.0;
    m_level_count = 0;
    m_failed = false;
    ArrayResize(m_requests, 0);
    ArrayResize(m_deals, 0);
    ArrayResize(m_positions, 0);
    ArrayResize(m_levels, 0);
    m_initialized = true;
    return true;
  }

  bool Replay(
    STGKGridMappingJournalRecord &records[],
    int record_count)
  {
    if(!m_initialized || m_failed ||
       record_count < 0 ||
       record_count != ArraySize(records))
      return false;

    for(int i = 0; i < record_count; i++)
    {
      if(!ApplyRecord(records[i]))
      {
        m_failed = true;
        return false;
      }
    }
    return true;
  }

  long LastSequence()
  {
    return m_last_sequence;
  }

  int RequestCount()
  {
    return ArraySize(m_requests);
  }

  int DealCount()
  {
    return ArraySize(m_deals);
  }

  int PositionCount()
  {
    return ArraySize(m_positions);
  }

  int LevelCount()
  {
    return ArraySize(m_levels);
  }

  bool HasUnresolvedRequest()
  {
    return HasUnresolvedRequestInternal();
  }

  string UnresolvedRequestId()
  {
    for(int i = 0; i < ArraySize(m_requests); i++)
    {
      if(m_requests[i].unresolved)
        return m_requests[i].request_id;
    }
    return "";
  }

  string PositionIdentifierAt(int index)
  {
    if(index < 0 || index >= ArraySize(m_positions))
      return "";
    return m_positions[index].position_identifier;
  }

  string PositionTicketAt(int index)
  {
    if(index < 0 || index >= ArraySize(m_positions))
      return "";
    return m_positions[index].position_ticket;
  }

  double PositionVolumeAt(int index)
  {
    if(index < 0 || index >= ArraySize(m_positions))
      return 0.0;
    return m_positions[index].volume;
  }

  int LevelStateAt(int level_index)
  {
    int index = FindLevel(level_index);
    if(index < 0)
      return -1;
    return (int)m_levels[index].state;
  }
};

#endif
