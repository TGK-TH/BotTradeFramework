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

enum ENUM_TGK_GRID_MAPPING_RECOVERY_STATUS
{
  TGK_GRID_MAPPING_STATUS_NORMAL = 0,
  TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR,
  TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR
};

#define TGK_GRID_MAPPING_MAX_LEVELS 1000
#define TGK_GRID_MAPPING_MAX_POSITIONS 1000
#define TGK_GRID_MAPPING_MAX_DEALS_PER_REQUEST 100
#define TGK_GRID_MAPPING_MAX_SERIALIZATION_BUFFER_BYTES 16777216
#define TGK_GRID_MAPPING_MAX_STRING_FIELD_BYTES 4096
#define TGK_GRID_MAPPING_MAX_RECORD_BYTES 65536

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
  int m_lower_level_count;
  int m_upper_level_count;
  bool m_initialized;
  bool m_failed;
  ENUM_TGK_GRID_MAPPING_RECOVERY_STATUS m_recovery_status;

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

  bool IsSnapshotStringFieldValid(string value)
  {
    uchar bytes[];
    int byte_count = StringToCharArray(
      value,
      bytes,
      0,
      WHOLE_ARRAY,
      CP_UTF8);
    if(byte_count <= 0)
      return false;
    return byte_count - 1 <= TGK_GRID_MAPPING_MAX_STRING_FIELD_BYTES;
  }

  bool ValidateSnapshotRecordFields(string record)
  {
    string fields[];
    int field_count = StringSplit(record, '|', fields);
    if(field_count <= 0)
      return false;
    for(int i = 0; i < field_count; i++)
    {
      if(!IsSnapshotStringFieldValid(fields[i]))
        return false;
    }
    return true;
  }

  string EncodeSnapshotRecord(string record)
  {
    if(!ValidateSnapshotRecordFields(record))
      return "";
    uchar bytes[];
    int byte_count = StringToCharArray(
      record,
      bytes,
      0,
      WHOLE_ARRAY,
      CP_UTF8);
    if(byte_count <= 0)
      return "";

    byte_count--;
    if(ArrayResize(bytes, byte_count) != byte_count)
      return "";
    if(byte_count * 2 + 1 > TGK_GRID_MAPPING_MAX_RECORD_BYTES)
      return "";

    string encoded;
    if(!StringInit(encoded, byte_count * 2, '0'))
      return "";

    string digits = "0123456789ABCDEF";
    for(int i = 0; i < byte_count; i++)
    {
      int value_byte = (int)bytes[i];
      StringSetCharacter(
        encoded,
        i * 2,
        StringGetCharacter(digits, value_byte >> 4));
      StringSetCharacter(
        encoded,
        i * 2 + 1,
        StringGetCharacter(digits, value_byte & 15));
    }
    return encoded;
  }

  bool DecodeSnapshotRecord(string encoded, string &record)
  {
    int length = StringLen(encoded);
    if((length % 2) != 0)
      return false;

    uchar bytes[];
    if(ArrayResize(bytes, length / 2) != length / 2)
      return false;

    for(int i = 0; i < length; i += 2)
    {
      ushort high = StringGetCharacter(encoded, i);
      ushort low = StringGetCharacter(encoded, i + 1);
      int high_value = (high >= '0' && high <= '9')
                       ? (int)(high - '0')
                       : ((high >= 'A' && high <= 'F')
                          ? (int)(high - 'A' + 10)
                          : ((high >= 'a' && high <= 'f')
                             ? (int)(high - 'a' + 10)
                             : -1));
      int low_value = (low >= '0' && low <= '9')
                      ? (int)(low - '0')
                      : ((low >= 'A' && low <= 'F')
                         ? (int)(low - 'A' + 10)
                         : ((low >= 'a' && low <= 'f')
                            ? (int)(low - 'a' + 10)
                            : -1));
      if(high_value < 0 || low_value < 0)
        return false;
      bytes[i / 2] = (uchar)(high_value * 16 + low_value);
    }

    record = CharArrayToString(bytes, 0, ArraySize(bytes), CP_UTF8);
    return true;
  }

  bool IsBooleanToken(string value)
  {
    return value == "0" || value == "1";
  }

  bool ComputeLevelCounts(
    double lower_bound,
    double upper_bound,
    double anchor_price,
    double grid_step,
    int &lower_count,
    int &upper_count,
    int &total_count)
  {
    lower_count = 0;
    upper_count = 0;
    total_count = 0;
    if(!MathIsValidNumber(lower_bound) ||
       !MathIsValidNumber(upper_bound) ||
       !MathIsValidNumber(anchor_price) ||
       !MathIsValidNumber(grid_step) ||
       grid_step <= 0.0 ||
       lower_bound > anchor_price ||
       anchor_price > upper_bound)
      return false;

    double lower_steps = (anchor_price - lower_bound) / grid_step;
    double upper_steps = (upper_bound - anchor_price) / grid_step;
    if(!MathIsValidNumber(lower_steps) ||
       !MathIsValidNumber(upper_steps) ||
       lower_steps > TGK_GRID_MAPPING_MAX_LEVELS - 1 + 0.0000001 ||
       upper_steps > TGK_GRID_MAPPING_MAX_LEVELS - 1 + 0.0000001)
      return false;

    lower_count = (int)MathFloor(lower_steps + 0.0000000001);
    upper_count = (int)MathFloor(upper_steps + 0.0000000001);
    total_count = lower_count + upper_count + 1;
    return total_count > 0 && total_count <= TGK_GRID_MAPPING_MAX_LEVELS;
  }

  bool IsValidGridLevelIndexForCounts(
    int level_index,
    int lower_count,
    int upper_count)
  {
    if(level_index < 0)
      return false;
    return level_index < lower_count + upper_count;
  }

  bool IsValidGridLevelIndex(int level_index)
  {
    return IsValidGridLevelIndexForCounts(
      level_index,
      m_lower_level_count,
      m_upper_level_count);
  }

  int FindRequestInSnapshot(
    STGKGridMappingRequestState &requests[],
    string request_id)
  {
    for(int i = 0; i < ArraySize(requests); i++)
    {
      if(requests[i].request_id == request_id)
        return i;
    }
    return -1;
  }

  int FindPositionByIdentifierInSnapshot(
    STGKGridMappingPositionState &positions[],
    string position_identifier)
  {
    for(int i = 0; i < ArraySize(positions); i++)
    {
      if(positions[i].position_identifier == position_identifier)
        return i;
    }
    return -1;
  }

  int FindPositionByTicketInSnapshot(
    STGKGridMappingPositionState &positions[],
    string position_ticket)
  {
    for(int i = 0; i < ArraySize(positions); i++)
    {
      if(positions[i].position_ticket == position_ticket)
        return i;
    }
    return -1;
  }

  int FindPositionByTargetInSnapshot(
    STGKGridMappingPositionState &positions[],
    string target_kind,
    int level_index)
  {
    for(int i = 0; i < ArraySize(positions); i++)
    {
      if(positions[i].target_kind == target_kind &&
         positions[i].level_index == level_index)
        return i;
    }
    return -1;
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
      if(index >= TGK_GRID_MAPPING_MAX_LEVELS - 1)
      {
        m_recovery_status = TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR;
        return false;
      }
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
      if(!IsValidGridLevelIndex(level_index) ||
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
    int request_deal_count = 0;
    for(int i = 0; i < ArraySize(m_deals); i++)
    {
      if(m_deals[i].position_identifier == fields[3] &&
         m_deals[i].request_id != fields[1])
        return false;
      if(m_deals[i].request_id == fields[1])
      {
        if(m_deals[i].position_identifier != fields[3])
          return false;
        request_deal_count++;
        associated_volume += m_deals[i].volume;
      }
    }
    if(request_deal_count >= TGK_GRID_MAPPING_MAX_DEALS_PER_REQUEST)
    {
      m_recovery_status = TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR;
      return false;
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
    if(fields[4] == "LEVEL" && !IsValidGridLevelIndex(level_index))
      return false;

    if(FindPositionByIdentifier(fields[6]) >= 0 ||
       FindPositionByTicket(fields[7]) >= 0 ||
       FindPositionByTarget(fields[4], level_index) >= 0 ||
       volume > m_requests[request_index].requested_volume + 0.00000001)
      return false;

    if(ArraySize(m_positions) >= TGK_GRID_MAPPING_MAX_POSITIONS)
    {
      m_recovery_status = TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR;
      return false;
    }

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
    RemoveDealsForRequest(fields[1]);
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
       !IsValidGridLevelIndex(level_index) ||
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
       level_count > TGK_GRID_MAPPING_MAX_LEVELS)
      return false;

    lower_bound = StringToDouble(fields[5]);
    upper_bound = StringToDouble(fields[6]);
    int lower_level_count = 0;
    int upper_level_count = 0;
    int computed_level_count = 0;
    if(!ComputeLevelCounts(
      lower_bound,
      upper_bound,
      anchor,
      grid_step,
      lower_level_count,
      upper_level_count,
      computed_level_count) ||
       computed_level_count != level_count)
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
    m_lower_level_count = lower_level_count;
    m_upper_level_count = upper_level_count;

    int new_level_state_count = m_level_count - 1;
    if(ArrayResize(m_levels, new_level_state_count) != new_level_state_count)
    {
      m_recovery_status = TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR;
      return false;
    }
    for(int level_index = 0; level_index < new_level_state_count; level_index++)
    {
      m_levels[level_index].config_epoch = m_config_epoch;
      m_levels[level_index].level_index = level_index;
      m_levels[level_index].state = TGK_GRID_LEVEL_READY;
    }
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
    m_lower_level_count = 0;
    m_upper_level_count = 0;
    m_initialized = false;
    m_failed = false;
    m_recovery_status = TGK_GRID_MAPPING_STATUS_NORMAL;
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
    m_lower_level_count = 0;
    m_upper_level_count = 0;
    m_failed = false;
    m_recovery_status = TGK_GRID_MAPPING_STATUS_NORMAL;
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
        m_recovery_status = TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR;
        return false;
      }
    }
    return true;
  }

  bool ExportSnapshot(string &payload)
  {
    payload = "";
    int request_count = ArraySize(m_requests);
    int deal_count = ArraySize(m_deals);
    int position_count = ArraySize(m_positions);
    int level_state_count = ArraySize(m_levels);

    if(!m_initialized ||
       m_failed ||
       !IsSnapshotStringFieldValid(m_symbol) ||
       !IsSnapshotStringFieldValid(m_instance_id) ||
       !IsSnapshotStringFieldValid(m_mode == "" ? "-" : m_mode) ||
       request_count > TGK_GRID_MAPPING_MAX_POSITIONS + 1 ||
       deal_count > TGK_GRID_MAPPING_MAX_DEALS_PER_REQUEST ||
       position_count > TGK_GRID_MAPPING_MAX_POSITIONS ||
       level_state_count > TGK_GRID_MAPPING_MAX_LEVELS - 1 ||
       m_level_count > TGK_GRID_MAPPING_MAX_LEVELS ||
       (m_config_epoch > 0 && level_state_count != m_level_count - 1) ||
       (m_config_epoch == 0 && level_state_count != 0))
      return false;

    string mode = m_mode == "" ? "-" : m_mode;
    payload = StringFormat(
      "%s|STATE|%s|%I64d|%s|%I64d|%I64d|%s|%s|%s|%s|%s|%d|%d|%d|%d|%d",
      TGK_GRID_MAPPING_PAYLOAD_VERSION,
      m_symbol,
      m_magic_number,
      m_instance_id,
      m_last_sequence,
      m_config_epoch,
      mode,
      DoubleToString(m_grid_step, 16),
      DoubleToString(m_lower_bound, 16),
      DoubleToString(m_upper_bound, 16),
      DoubleToString(m_anchor_price, 16),
      m_level_count,
      request_count,
      deal_count,
      position_count,
      level_state_count);

    for(int i = 0; i < request_count; i++)
    {
      string outcome = m_requests[i].has_execution_result
                       ? m_requests[i].execution_outcome
                       : "-";
      string record = StringFormat(
        "%s|%s|%s|%d|%s|%I64d|%s|%s|%s|%d|%d",
        m_requests[i].request_id,
        m_requests[i].mode,
        m_requests[i].target_kind,
        m_requests[i].level_index,
        DoubleToString(m_requests[i].requested_volume, 16),
        m_requests[i].config_epoch,
        outcome,
        m_requests[i].order_ticket,
        m_requests[i].deal_ticket,
        m_requests[i].has_execution_result ? 1 : 0,
        m_requests[i].unresolved ? 1 : 0);
      string encoded = EncodeSnapshotRecord(record);
      if(encoded == "")
        return false;
      payload += "|R" + encoded;
      if(StringLen(payload) > TGK_GRID_MAPPING_MAX_SERIALIZATION_BUFFER_BYTES)
        return false;
    }

    for(int i = 0; i < deal_count; i++)
    {
      string record = StringFormat(
        "%s|%s|%s|%s",
        m_deals[i].request_id,
        m_deals[i].deal_ticket,
        m_deals[i].position_identifier,
        DoubleToString(m_deals[i].volume, 16));
      string encoded = EncodeSnapshotRecord(record);
      if(encoded == "")
        return false;
      payload += "|D" + encoded;
      if(StringLen(payload) > TGK_GRID_MAPPING_MAX_SERIALIZATION_BUFFER_BYTES)
        return false;
    }

    for(int i = 0; i < position_count; i++)
    {
      string record = StringFormat(
        "%s|%s|%I64d|%s|%d|%s|%s|%s|%I64d",
        m_positions[i].request_id,
        m_positions[i].symbol,
        m_positions[i].magic_number,
        m_positions[i].target_kind,
        m_positions[i].level_index,
        m_positions[i].position_identifier,
        m_positions[i].position_ticket,
        DoubleToString(m_positions[i].volume, 16),
        m_positions[i].config_epoch);
      string encoded = EncodeSnapshotRecord(record);
      if(encoded == "")
        return false;
      payload += "|P" + encoded;
      if(StringLen(payload) > TGK_GRID_MAPPING_MAX_SERIALIZATION_BUFFER_BYTES)
        return false;
    }

    for(int i = 0; i < level_state_count; i++)
    {
      string record = StringFormat(
        "%I64d|%d|%d",
        m_levels[i].config_epoch,
        m_levels[i].level_index,
        (int)m_levels[i].state);
      string encoded = EncodeSnapshotRecord(record);
      if(encoded == "")
        return false;
      payload += "|L" + encoded;
      if(StringLen(payload) > TGK_GRID_MAPPING_MAX_SERIALIZATION_BUFFER_BYTES)
        return false;
    }

    if(StringLen(payload) > TGK_GRID_MAPPING_MAX_SERIALIZATION_BUFFER_BYTES)
      return false;

    uchar bytes[];
    int byte_count = StringToCharArray(
      payload,
      bytes,
      0,
      WHOLE_ARRAY,
      CP_UTF8);
    if(byte_count <= 0)
      return false;
    return byte_count - 1 <= TGK_GRID_MAPPING_MAX_SERIALIZATION_BUFFER_BYTES;
  }

  bool RestoreSnapshotInternal(string payload, long checkpoint_sequence)
  {
    if(!m_initialized ||
       m_failed ||
       checkpoint_sequence < 0 ||
       StringLen(payload) > TGK_GRID_MAPPING_MAX_SERIALIZATION_BUFFER_BYTES)
      return false;

    uchar snapshot_bytes[];
    int snapshot_byte_count = StringToCharArray(
      payload,
      snapshot_bytes,
      0,
      WHOLE_ARRAY,
      CP_UTF8);
    if(snapshot_byte_count <= 0 ||
       snapshot_byte_count - 1 > TGK_GRID_MAPPING_MAX_SERIALIZATION_BUFFER_BYTES)
      return false;

    string fields[];
    int field_count = StringSplit(payload, '|', fields);
    if(field_count < 17 ||
       fields[0] != TGK_GRID_MAPPING_PAYLOAD_VERSION ||
       fields[1] != "STATE" ||
       fields[2] != m_symbol ||
       !IsSnapshotStringFieldValid(fields[2]) ||
       !IsSnapshotStringFieldValid(fields[4]) ||
       !IsSnapshotStringFieldValid(fields[7]))
      return false;

    long snapshot_magic = 0;
    long last_sequence = 0;
    long config_epoch = 0;
    long level_count_long = 0;
    long request_count_long = 0;
    long deal_count_long = 0;
    long position_count_long = 0;
    long level_state_count_long = 0;
    if(!ParseMagic(fields[3], snapshot_magic) ||
       snapshot_magic != m_magic_number ||
       fields[4] != m_instance_id ||
       !IsDecimalString(fields[5], true) ||
       !IsDecimalString(fields[6], true) ||
       !IsDecimalString(fields[12], true) ||
       !IsDecimalString(fields[13], true) ||
       !IsDecimalString(fields[14], true) ||
       !IsDecimalString(fields[15], true) ||
       !IsDecimalString(fields[16], true))
      return false;

    last_sequence = StringToInteger(fields[5]);
    config_epoch = StringToInteger(fields[6]);
    level_count_long = StringToInteger(fields[12]);
    request_count_long = StringToInteger(fields[13]);
    deal_count_long = StringToInteger(fields[14]);
    position_count_long = StringToInteger(fields[15]);
    level_state_count_long = StringToInteger(fields[16]);

    if(StringFormat("%I64d", last_sequence) != fields[5] ||
       StringFormat("%I64d", config_epoch) != fields[6] ||
       StringFormat("%I64d", level_count_long) != fields[12] ||
       StringFormat("%I64d", request_count_long) != fields[13] ||
       StringFormat("%I64d", deal_count_long) != fields[14] ||
       StringFormat("%I64d", position_count_long) != fields[15] ||
       StringFormat("%I64d", level_state_count_long) != fields[16] ||
       last_sequence != checkpoint_sequence ||
       level_count_long > TGK_GRID_MAPPING_MAX_LEVELS ||
       request_count_long > TGK_GRID_MAPPING_MAX_POSITIONS + 1 ||
       deal_count_long > TGK_GRID_MAPPING_MAX_DEALS_PER_REQUEST ||
       position_count_long > TGK_GRID_MAPPING_MAX_POSITIONS ||
       level_state_count_long > TGK_GRID_MAPPING_MAX_LEVELS - 1 ||
       field_count != 17 + request_count_long + deal_count_long +
                      position_count_long + level_state_count_long)
      return false;

    double grid_step = 0.0;
    double lower_bound = 0.0;
    double upper_bound = 0.0;
    double anchor_price = 0.0;
    if(!IsNumberString(fields[8], true) ||
       !IsNumberString(fields[9], true) ||
       !IsNumberString(fields[10], true) ||
       !IsNumberString(fields[11], true))
      return false;

    grid_step = StringToDouble(fields[8]);
    lower_bound = StringToDouble(fields[9]);
    upper_bound = StringToDouble(fields[10]);
    anchor_price = StringToDouble(fields[11]);
    if(!MathIsValidNumber(grid_step) ||
       !MathIsValidNumber(lower_bound) ||
       !MathIsValidNumber(upper_bound) ||
       !MathIsValidNumber(anchor_price))
      return false;

    string mode = fields[7] == "-" ? "" : fields[7];
    int snapshot_lower_level_count = 0;
    int snapshot_upper_level_count = 0;
    int snapshot_computed_level_count = 0;
    if(config_epoch == 0)
    {
      if(mode != "" ||
         level_count_long != 0 ||
         request_count_long != 0 ||
         deal_count_long != 0 ||
         position_count_long != 0 ||
         level_state_count_long != 0 ||
         grid_step != 0.0 ||
         lower_bound != 0.0 ||
         upper_bound != 0.0 ||
         anchor_price != 0.0)
        return false;
    }
    else if((mode != "BUY" && mode != "SELL") ||
            !ComputeLevelCounts(
              lower_bound,
              upper_bound,
              anchor_price,
              grid_step,
              snapshot_lower_level_count,
              snapshot_upper_level_count,
              snapshot_computed_level_count) ||
            snapshot_computed_level_count != level_count_long ||
            level_state_count_long != level_count_long - 1)
    {
      return false;
    }

    STGKGridMappingRequestState snapshot_requests[];
    STGKGridMappingDealState snapshot_deals[];
    STGKGridMappingPositionState snapshot_positions[];
    STGKGridMappingLevelState snapshot_levels[];
    if(ArrayResize(snapshot_requests, (int)request_count_long) != request_count_long ||
       ArrayResize(snapshot_deals, (int)deal_count_long) != deal_count_long ||
       ArrayResize(snapshot_positions, (int)position_count_long) != position_count_long ||
       ArrayResize(snapshot_levels, (int)level_state_count_long) != level_state_count_long)
      return false;

    int request_index = 0;
    int deal_index = 0;
    int position_index = 0;
    int level_state_index = 0;
    int unresolved_count = 0;

    for(int i = 17; i < field_count; i++)
    {
      if(StringLen(fields[i]) < 2)
        return false;

      ushort record_type = StringGetCharacter(fields[i], 0);
      string record;
      if(!DecodeSnapshotRecord(StringSubstr(fields[i], 1), record) ||
         !ValidateSnapshotRecordFields(record))
        return false;

      string values[];
      int value_count = StringSplit(record, '|', values);
      if(record_type == 'R')
      {
        if(value_count != 11 ||
           request_index >= (int)request_count_long)
          return false;

        STGKGridMappingRequestState request;
        int level_index = 0;
        double requested_volume = 0.0;
        long request_epoch = 0;
        if(!IsToken(values[0]) ||
           (values[1] != "BUY" && values[1] != "SELL") ||
           (values[2] != "ANCHOR" && values[2] != "LEVEL") ||
           !ParseSignedInteger(values[3], level_index) ||
           !ParsePositiveDouble(values[4], requested_volume) ||
           !ParsePositiveLong(values[5], request_epoch) ||
           request_epoch != config_epoch ||
           !IsDecimalString(values[7], true) ||
           !IsDecimalString(values[8], true) ||
           !IsBooleanToken(values[9]) ||
           !IsBooleanToken(values[10]) ||
           values[1] != mode)
          return false;

        bool has_execution_result = values[9] == "1";
        bool unresolved = values[10] == "1";
        string outcome = values[6] == "-" ? "" : values[6];
        if((values[2] == "ANCHOR" && level_index != -1) ||
           (values[2] == "LEVEL" &&
            !IsValidGridLevelIndexForCounts(
              level_index,
              snapshot_lower_level_count,
              snapshot_upper_level_count)) ||
           (has_execution_result && !IsAcceptedOutcome(outcome)) ||
           (!has_execution_result &&
            (outcome != "" || values[7] != "0" || values[8] != "0" || !unresolved)) ||
           (has_execution_result && outcome == "-"))
          return false;

        for(int j = 0; j < request_index; j++)
        {
          if(snapshot_requests[j].request_id == values[0])
            return false;
        }

        request.request_id = values[0];
        request.mode = values[1];
        request.target_kind = values[2];
        request.level_index = level_index;
        request.requested_volume = requested_volume;
        request.config_epoch = request_epoch;
        request.execution_outcome = outcome;
        request.order_ticket = values[7];
        request.deal_ticket = values[8];
        request.has_execution_result = has_execution_result;
        request.unresolved = unresolved;
        snapshot_requests[request_index++] = request;
        if(unresolved)
          unresolved_count++;
      }
      else if(record_type == 'D')
      {
        if(value_count != 4 ||
           deal_index >= (int)deal_count_long)
          return false;

        int request_position = FindRequestInSnapshot(snapshot_requests, values[0]);
        double deal_volume = 0.0;
        if(request_position < 0 ||
           !snapshot_requests[request_position].unresolved ||
           !snapshot_requests[request_position].has_execution_result ||
           !IsAcceptedOutcome(snapshot_requests[request_position].execution_outcome) ||
           !IsDecimalString(values[1]) ||
           !IsDecimalString(values[2]) ||
           !ParsePositiveDouble(values[3], deal_volume))
          return false;

        int request_deal_count = 0;
        double associated_volume = deal_volume;
        for(int j = 0; j < deal_index; j++)
        {
          if(snapshot_deals[j].deal_ticket == values[1])
            return false;
          if(snapshot_deals[j].request_id == values[0])
          {
            if(snapshot_deals[j].position_identifier != values[2])
              return false;
            request_deal_count++;
            associated_volume += snapshot_deals[j].volume;
          }
        }
        if(request_deal_count >= TGK_GRID_MAPPING_MAX_DEALS_PER_REQUEST ||
           associated_volume >
             snapshot_requests[request_position].requested_volume + 0.00000001)
          return false;

        snapshot_deals[deal_index].request_id = values[0];
        snapshot_deals[deal_index].deal_ticket = values[1];
        snapshot_deals[deal_index].position_identifier = values[2];
        snapshot_deals[deal_index].volume = deal_volume;
        deal_index++;
      }
      else if(record_type == 'P')
      {
        if(value_count != 9 ||
           position_index >= (int)position_count_long)
          return false;

        int request_position = FindRequestInSnapshot(snapshot_requests, values[0]);
        long position_magic = 0;
        int level_index = 0;
        double position_volume = 0.0;
        long position_epoch = 0;
        if(request_position < 0 ||
           snapshot_requests[request_position].unresolved ||
           !snapshot_requests[request_position].has_execution_result ||
           !IsAcceptedOutcome(snapshot_requests[request_position].execution_outcome) ||
           values[1] != m_symbol ||
           !ParseMagic(values[2], position_magic) ||
           position_magic != m_magic_number ||
           (values[3] != "ANCHOR" && values[3] != "LEVEL") ||
           !ParseSignedInteger(values[4], level_index) ||
           !IsDecimalString(values[5]) ||
           !IsDecimalString(values[6]) ||
           !ParsePositiveDouble(values[7], position_volume) ||
           !ParsePositiveLong(values[8], position_epoch) ||
           position_epoch != config_epoch ||
           snapshot_requests[request_position].target_kind != values[3] ||
           snapshot_requests[request_position].level_index != level_index ||
           position_volume >
             snapshot_requests[request_position].requested_volume + 0.00000001 ||
           (values[3] == "ANCHOR" && level_index != -1) ||
           (values[3] == "LEVEL" &&
            !IsValidGridLevelIndexForCounts(
              level_index,
              snapshot_lower_level_count,
              snapshot_upper_level_count)))
          return false;

        for(int j = 0; j < position_index; j++)
        {
          if(snapshot_positions[j].request_id == values[0] ||
             snapshot_positions[j].position_identifier == values[5] ||
             snapshot_positions[j].position_ticket == values[6] ||
             (snapshot_positions[j].target_kind == values[3] &&
              snapshot_positions[j].level_index == level_index))
            return false;
        }

        for(int j = 0; j < deal_index; j++)
        {
          if(snapshot_deals[j].request_id == values[0])
            return false;
        }

        snapshot_positions[position_index].request_id = values[0];
        snapshot_positions[position_index].symbol = values[1];
        snapshot_positions[position_index].magic_number = position_magic;
        snapshot_positions[position_index].target_kind = values[3];
        snapshot_positions[position_index].level_index = level_index;
        snapshot_positions[position_index].position_identifier = values[5];
        snapshot_positions[position_index].position_ticket = values[6];
        snapshot_positions[position_index].volume = position_volume;
        snapshot_positions[position_index].config_epoch = position_epoch;
        position_index++;
      }
      else if(record_type == 'L')
      {
        if(value_count != 3 ||
           level_state_index >= (int)level_state_count_long)
          return false;

        long level_epoch = 0;
        int level_index = 0;
        int state_value = (int)StringToInteger(values[2]);
        if(!ParsePositiveLong(values[0], level_epoch) ||
           level_epoch != config_epoch ||
           !ParseSignedInteger(values[1], level_index) ||
           !IsValidGridLevelIndexForCounts(
             level_index,
             snapshot_lower_level_count,
             snapshot_upper_level_count) ||
           state_value < (int)TGK_GRID_LEVEL_READY ||
           state_value > (int)TGK_GRID_LEVEL_WAIT_ACTIVATION ||
           StringFormat("%d", state_value) != values[2])
          return false;

        for(int j = 0; j < level_state_index; j++)
        {
          if(snapshot_levels[j].level_index == level_index)
            return false;
        }

        snapshot_levels[level_state_index].config_epoch = level_epoch;
        snapshot_levels[level_state_index].level_index = level_index;
        snapshot_levels[level_state_index].state =
          (ENUM_TGK_GRID_LEVEL_STATE)state_value;
        level_state_index++;
      }
      else
      {
        return false;
      }
    }

    if(request_index != request_count_long ||
       deal_index != deal_count_long ||
       position_index != position_count_long ||
       level_state_index != level_state_count_long ||
       unresolved_count > 1)
      return false;

    for(int i = 0; i < request_index; i++)
    {
      if(snapshot_requests[i].unresolved &&
         FindPositionByTargetInSnapshot(
           snapshot_positions,
           snapshot_requests[i].target_kind,
           snapshot_requests[i].level_index) >= 0)
        return false;

      int mapped_position = -1;
      for(int j = 0; j < position_index; j++)
      {
        if(snapshot_positions[j].request_id == snapshot_requests[i].request_id)
        {
          mapped_position = j;
          break;
        }
      }
      if(snapshot_requests[i].unresolved == (mapped_position >= 0))
        return false;
    }

    for(int i = 0; i < position_index; i++)
    {
      if(snapshot_positions[i].target_kind != "LEVEL")
        continue;

      bool has_active_level = false;
      for(int j = 0; j < level_state_index; j++)
      {
        if(snapshot_levels[j].level_index == snapshot_positions[i].level_index &&
           snapshot_levels[j].state == TGK_GRID_LEVEL_ACTIVE)
        {
          has_active_level = true;
          break;
        }
      }
      if(!has_active_level)
        return false;
    }

    for(int i = 0; i < level_state_index; i++)
    {
      int mapped_position = FindPositionByTargetInSnapshot(
        snapshot_positions,
        "LEVEL",
        snapshot_levels[i].level_index);
      if((snapshot_levels[i].state == TGK_GRID_LEVEL_ACTIVE) !=
         (mapped_position >= 0))
        return false;
    }

    if(ArrayResize(m_requests, request_index) != request_index ||
       ArrayResize(m_deals, deal_index) != deal_index ||
       ArrayResize(m_positions, position_index) != position_index ||
       ArrayResize(m_levels, level_state_index) != level_state_index)
      return false;

    for(int i = 0; i < request_index; i++)
      m_requests[i] = snapshot_requests[i];
    for(int i = 0; i < deal_index; i++)
      m_deals[i] = snapshot_deals[i];
    for(int i = 0; i < position_index; i++)
      m_positions[i] = snapshot_positions[i];
    for(int i = 0; i < level_state_index; i++)
      m_levels[i] = snapshot_levels[i];

    m_last_sequence = last_sequence;
    m_config_epoch = config_epoch;
    m_mode = mode;
    m_grid_step = grid_step;
    m_lower_bound = lower_bound;
    m_upper_bound = upper_bound;
    m_anchor_price = anchor_price;
    m_level_count = (int)level_count_long;
    m_lower_level_count = snapshot_lower_level_count;
    m_upper_level_count = snapshot_upper_level_count;
    m_failed = false;
    m_recovery_status = TGK_GRID_MAPPING_STATUS_NORMAL;
    return true;
  }

  bool RestoreSnapshot(string payload, long checkpoint_sequence)
  {
    if(!RestoreSnapshotInternal(payload, checkpoint_sequence))
    {
      m_failed = true;
      m_recovery_status = TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR;
      return false;
    }
    return true;
  }

  long LastSequence()
  {
    return m_last_sequence;
  }

  ENUM_TGK_GRID_MAPPING_RECOVERY_STATUS RecoveryStatus()
  {
    return m_recovery_status;
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
