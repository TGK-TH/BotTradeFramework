#ifndef BOTTRADE_GRID_ENTRY_MAPPING_STORAGE_MQH
#define BOTTRADE_GRID_ENTRY_MAPPING_STORAGE_MQH
#define TGK_GRID_ENTRY_MAPPING_SCHEMA_VERSION 1

enum ENUM_TGK_GRID_MAPPING_RECORD_TYPE
{
  TGK_GRID_MAPPING_RECORD_ENTRY_INTENT = 1,
  TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
  TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
  TGK_GRID_MAPPING_RECORD_POSITION_MAPPING,
  TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE
};

struct STGKGridMappingJournalRecord
{
  long sequence;
  ENUM_TGK_GRID_MAPPING_RECORD_TYPE record_type;
  string payload;
};

// Append-only journal for one account / symbol / Grid Instance.
// Payload is opaque to this class; identifiers inside it must remain decimal
// strings. The journal never interprets Order Comments or trading semantics.
class CTGKGridEntryMappingStorage
{
private:
  string m_symbol;
  string m_instance_id;
  string m_file_name;
  long m_account_login;
  bool m_initialized;

  // รับ string value เข้ามา เพื่อแปลงเป็น string
  // ที่มีแค่ A-Z, a-z, 0-9, _ หรือ -
  // ถ้ามีตัวอักษรอื่น ๆ จะถูกแทนที่ด้วย _
  string SafeFilePart(string value)
  {
    string result = "";
    for(int i = 0; i < StringLen(value); i++)
    {
      ushort c = StringGetCharacter(value, i);
      bool safe = (c >= 'A' && c <= 'Z') ||
                  (c >= 'a' && c <= 'z') ||
                  (c >= '0' && c <= '9') ||
                  c == '_' || c == '-';
      result += safe ? ShortToString(c) : "_";
    }
    return result;
  }

  // แปลง Payload ที่รับเข้ามา เป็น String ของเลขฐาน 16
  // โดย 1 ตัวอักษรของ Payload จะแทนด้วยเลขฐาน 16 จำนวน 2 ตัวอักษร
  string EncodePayload(string payload)
  {
    uchar bytes[];
    int count = StringToCharArray(
      payload,
      bytes,
      0,
      WHOLE_ARRAY,
      CP_UTF8);
    if(count <= 0)
      return "";

    // คำสั่ง StringToChartArray
    // จะใส่ Byte จบ string ที่เป็น \0 มาด้วย
    // เราจึงต้อง Resize bytes เพื่อตัดตัวท้ายทิ้ง
    ArrayResize(bytes, count - 1);
    string encoded = "";
    for(int i = 0; i < ArraySize(bytes); i++)
      encoded += StringFormat("%02X", (int)bytes[i]);

    return encoded;
  }

  // เช็คว่าตัวอักษร c คือ 0-9, A-F หรือ a-f หรือไม่
  bool IsHexDigit(ushort c)
  {
    return (c >= '0' && c <= '9') ||
           (c >= 'A' && c <= 'F') ||
           (c >= 'a' && c <= 'f');
  }


  // แปลง string encoded กลับเป็นข้อความ string ปกติ
  // แล้วส่ง output กลับไปให้ผ่าน payload
  // ถ้าทำไม่สำเร็จ return false
  bool DecodePayload(string encoded, string &payload)
  {
    int length = StringLen(encoded);
    if((length % 2) != 0)
      return false;

    uchar bytes[];
    ArrayResize(bytes, length / 2);
    for(int i = 0; i < length; i += 2)
    {
      ushort high = StringGetCharacter(encoded, i);
      ushort low = StringGetCharacter(encoded, i + 1);
      if(!IsHexDigit(high) || !IsHexDigit(low))
        return false;

      int high_value = (high >= '0' && high <= '9')
                       ? (int)(high - '0')
                       : ((high >= 'A' && high <= 'F')
                          ? (int)(high - 'A' + 10)
                          : (int)(high - 'a' + 10));
      int low_value = (low >= '0' && low <= '9')
                      ? (int)(low - '0')
                      : ((low >= 'A' && low <= 'F')
                         ? (int)(low - 'A' + 10)
                         : (int)(low - 'a' + 10));
      bytes[i / 2] = (uchar)(high_value * 16 + low_value);
    }

    payload = CharArrayToString(
      bytes,
      0,
      ArraySize(bytes),
      CP_UTF8);
    return true;
  }

  // รับ string value เข้ามา
  // แล้วแปรงเป็นตัวเลข hash
  // ใช้เพื่อตรวจสอบว่าข้อมูลมีการเปลี่ยนแปลงไหม
  // ถ้าข้อมูลเดียวกันก็จะได้ hash เดียวกัน
  ulong Checksum(string value)
  {
    ulong hash = 5381;
    for(int i = 0; i < StringLen(value); i++)
    {
      hash = (hash * 33 + (ulong)StringGetCharacter(value, i)) % 2147483647;
    }
    return hash;
  }

  // รับข้อมความที่ encoded คือ line พร้อมกับ expected_sequence
  // แล้วตรวจเช็คข้อมูล และแปลงกลับเป็นข้อความปกติ
  // ถ้าสำเร็จจะส่ง output ผ่าน record
  // ถ้าไม่สำเร็จ return false
  bool ParseRecord(
    string line,
    long expected_sequence,
    STGKGridMappingJournalRecord &record)
  {
    string fields[];
    int count = StringSplit(line, '|', fields);
    if(count != 6 || fields[0] != "TGKJ")
      return false;

    if(StringToInteger(fields[1]) != TGK_GRID_ENTRY_MAPPING_SCHEMA_VERSION)
      return false;

    long sequence = StringToInteger(fields[2]);
    if(sequence <= 0 || sequence != expected_sequence)
      return false;

    int type = (int)StringToInteger(fields[3]);
    if(type < TGK_GRID_MAPPING_RECORD_ENTRY_INTENT ||
       type > TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE)
      return false;

    string body = StringSubstr(line, 0, StringLen(line) -
                               StringLen(fields[5]) - 1);
    if(Checksum(body) != (ulong)StringToInteger(fields[5]))
      return false;

    string payload;
    if(!DecodePayload(fields[4], payload))
      return false;

    record.sequence = sequence;
    record.record_type = (ENUM_TGK_GRID_MAPPING_RECORD_TYPE)type;
    record.payload = payload;
    return true;
  }

  // ข้อมูลแต่ละอันที่เราเขียนจะจบด้วย \n เสมอ
  // ถ้าในไฟล์ ข้อมูลไม่ได้จบด้วย \n
  // เราจะตัดส่วนท้ายที่ไม่สมบูรณ์ออก
  // เอาเฉพาะที่จบด้วย \n ล่าสุด
  bool TrimIncompleteTail()
  {
    ResetLastError();
    int handle = FileOpen(
      m_file_name,
      FILE_READ | FILE_BIN);
    if(handle == INVALID_HANDLE)
    {
      if(!FileIsExist(m_file_name))
        return true;

      PrintFormat(
        "TGK Grid mapping: cannot open journal for tail recovery (error=%d)",
        GetLastError());
      return false;
    }

    ulong size = FileSize(handle);
    if(size == 0)
    {
      FileClose(handle);
      return true;
    }

    if(size > 16777216)
    {
      FileClose(handle);
      Print("TGK Grid mapping: journal exceeds the 16 MiB safety limit.");
      return false;
    }

    uchar bytes[];
    ArrayResize(bytes, (int)size);
    uint read_count = FileReadArray(handle, bytes, 0, (uint)size);
    FileClose(handle);
    if(read_count != size)
      return false;

    int last_newline = -1;
    for(int i = ArraySize(bytes) - 1; i >= 0; i--)
    {
      // 10 คือ \n (ขึ้นบรรทัดใหม่)
      if(bytes[i] == 10)
      {
        last_newline = i;
        break;
      }
    }

    // เช็คว่าข้อมูลจบด้วย \n หรือไม่
    // ถ้าใช่แสดงว่าเขียนเขียนข้อมูลครบ
    // เพราะข้อมูลแต่ละ record ของเราจะจบด้วย \n
    if(last_newline == ArraySize(bytes) - 1)
      return true;

    int valid_size = last_newline + 1;
    string temp_file_name = m_file_name + ".tmp";

    ResetLastError();
    int temp_handle = FileOpen(
      temp_file_name,
      FILE_WRITE | FILE_BIN);
    if(temp_handle == INVALID_HANDLE)
    {
      PrintFormat(
        "TGK Grid mapping: cannot create temporary journal (error=%d)",
        GetLastError());
      return false;
    }

    uint written = 0;
    if(valid_size > 0)
      written = FileWriteArray(
        temp_handle,
        bytes,
        0,
        (uint)valid_size);

    int write_error = GetLastError();
    if(written != valid_size || write_error != 0)
    {
      FileClose(temp_handle);
      FileDelete(temp_file_name);
      PrintFormat(
        "TGK Grid mapping: cannot write recovered journal (written=%u, expected=%d, error=%d)",
        written,
        valid_size,
        write_error);
      return false;
    }

    ResetLastError();
    FileFlush(temp_handle);
    int flush_error = GetLastError();
    FileClose(temp_handle);
    if(flush_error != 0)
    {
      FileDelete(temp_file_name);
      PrintFormat(
        "TGK Grid mapping: cannot flush recovered journal (error=%d)",
        flush_error);
      return false;
    }

    ResetLastError();
    if(!FileMove(
      temp_file_name,
      0,
      m_file_name,
      FILE_REWRITE))
    {
      int move_error = GetLastError();
      FileDelete(temp_file_name);
      PrintFormat(
        "TGK Grid mapping: cannot replace journal after tail recovery (error=%d)",
        move_error);
      return false;
    }

    return true;
  }

  // อ่านข้อมูลจากไฟล์ที่บันทึกไว้ แล้วส่ง output ผ่าน records
  // ส่วน record_count คือจำนวน record ทั้งหมด
  // และ next_sequence คือ sequence ถัดไปถ้าต้องการบันทึกข้อมูลใหม่เพิ่ม
  bool ReadJournal(
    STGKGridMappingJournalRecord &records[],
    int &record_count,
    long &next_sequence)
  {
    record_count = 0;
    next_sequence = 1;
    ArrayResize(records, 0);

    ResetLastError();
    int handle = FileOpen(
      m_file_name,
      FILE_READ | FILE_BIN | FILE_SHARE_READ);
    if(handle == INVALID_HANDLE)
    {
      // A missing journal is a valid empty state.
      if(!FileIsExist(m_file_name))
        return true;

      PrintFormat(
        "TGK Grid mapping: cannot open journal for read (file=%s, error=%d)",
        m_file_name,
        GetLastError());
      return false;
    }

    ulong size = FileSize(handle);
    if(size == 0)
    {
      FileClose(handle);
      return true;
    }

    if(size > 16777216)
    {
      FileClose(handle);
      Print("TGK Grid mapping: journal exceeds the 16 MiB safety limit.");
      return false;
    }

    uchar bytes[];
    ArrayResize(bytes, (int)size);
    uint read_count = FileReadArray(handle, bytes, 0, (uint)size);
    FileClose(handle);
    if(read_count != size)
      return false;

    string content = CharArrayToString(
      bytes,
      0,
      ArraySize(bytes),
      CP_UTF8);
    int content_length = StringLen(content);
    int complete_length = content_length;
    if(content_length > 0 &&
       StringGetCharacter(content, content_length - 1) != '\n')
    {
      int last_newline = -1;
      for(int i = content_length - 1; i >= 0; i--)
      {
        if(StringGetCharacter(content, i) == '\n')
        {
          last_newline = i;
          break;
        }
      }
      complete_length = last_newline + 1;
    }

    if(complete_length == 0)
      return true;

    string complete_content = StringSubstr(content, 0, complete_length);
    string lines[];
    int line_count = StringSplit(complete_content, '\n', lines);
    long expected_sequence = 1;

    for(int i = 0; i < line_count; i++)
    {
      string line = lines[i];
      if(line == "")
        continue;
      // บางระบบเวลาขึ้นบรรทัดใหม่จะใช้ \r\n ถ้ายังมี \r อยู่ก็ให้ตัดทิ้ง
      if(StringLen(line) > 0 &&
         StringGetCharacter(line, StringLen(line) - 1) == '\r')
        line = StringSubstr(line, 0, StringLen(line) - 1);

      STGKGridMappingJournalRecord record;
      if(!ParseRecord(line, expected_sequence, record))
      {
        PrintFormat(
          "TGK Grid mapping: invalid journal record at sequence %I64d",
          expected_sequence);
        return false;
      }

      int index = ArraySize(records);
      if(ArrayResize(records, index + 1) != index + 1)
        return false;
      records[index] = record;
      expected_sequence++;
    }

    record_count = ArraySize(records);
    next_sequence = expected_sequence;
    return true;
  }

public:
  CTGKGridEntryMappingStorage()
  {
    m_symbol = "";
    m_instance_id = "";
    m_file_name = "";
    m_account_login = 0;
    m_initialized = false;
  }

  bool Initialize(string symbol, string instance_id)
  {
    m_initialized = false;
    m_symbol = "";
    m_instance_id = "";
    m_file_name = "";

    if(StringLen(symbol) == 0 || StringLen(instance_id) == 0)
      return false;

    long account_login = AccountInfoInteger(ACCOUNT_LOGIN);
    string server = AccountInfoString(ACCOUNT_SERVER);
    if(account_login <= 0 || StringLen(server) == 0)
      return false;

    m_symbol = symbol;
    m_instance_id = instance_id;
    m_account_login = account_login;
    m_file_name = StringFormat(
      "TGK_EntryMap_%I64d_%s_%s_%s.jrn",
      account_login,
      SafeFilePart(server),
      SafeFilePart(symbol),
      SafeFilePart(instance_id));

    if(StringLen(m_file_name) == 0)
      return false;

    STGKGridMappingJournalRecord records[];
    int record_count = 0;
    long next_sequence = 0;
    if(!ReadJournal(records, record_count, next_sequence))
    {
      m_file_name = "";
      return false;
    }

    m_initialized = true;
    return true;
  }

  bool IsInitialized()
  {
    return m_initialized;
  }

  string FileName()
  {
    return m_file_name;
  }

  bool Replay(
    STGKGridMappingJournalRecord &records[],
    int &record_count,
    long &next_sequence)
  {
    if(!m_initialized)
      return false;

    return ReadJournal(records, record_count, next_sequence);
  }

  // เขียนข้อมูลต่อท้ายลงในไฟล์
  // ด้วยข้อมูล record_type และ payload
  bool Append(
    ENUM_TGK_GRID_MAPPING_RECORD_TYPE record_type,
    string payload)
  {
    if(!m_initialized ||
       record_type < TGK_GRID_MAPPING_RECORD_ENTRY_INTENT ||
       record_type > TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE)
      return false;

    if(!TrimIncompleteTail())
      return false;

    STGKGridMappingJournalRecord records[];
    int record_count = 0;
    long next_sequence = 0;
    if(!ReadJournal(records, record_count, next_sequence))
      return false;

    string encoded_payload = EncodePayload(payload);
    if(payload != "" && encoded_payload == "")
      return false;

    string body = StringFormat(
      "TGKJ|%d|%I64d|%d|%s",
      TGK_GRID_ENTRY_MAPPING_SCHEMA_VERSION,
      next_sequence,
      (int)record_type,
      encoded_payload);
    string line = body + "|" + StringFormat("%I64d", (long)Checksum(body)) + "\n";

    uchar bytes[];
    int byte_count = StringToCharArray(
      line,
      bytes,
      0,
      WHOLE_ARRAY,
      CP_UTF8);
    if(byte_count <= 1)
      return false;

    // คำสั่ง StringToChartArray
    // จะใส่ Byte จบ string ที่เป็น \0 มาด้วย
    // เราจึงต้อง Resize bytes เพื่อตัดตัวท้ายทิ้ง
    ArrayResize(bytes, byte_count - 1);

    ResetLastError();
    int handle = FileOpen(
      m_file_name,
      FILE_READ | FILE_WRITE | FILE_BIN | FILE_SHARE_READ);
    if(handle == INVALID_HANDLE)
    {
      PrintFormat(
        "TGK Grid mapping: cannot open journal for append (file=%s, error=%d)",
        m_file_name,
        GetLastError());
      return false;
    }

    if(!FileSeek(handle, 0, SEEK_END))
    {
      int seek_error = GetLastError();
      FileClose(handle);
      PrintFormat(
        "TGK Grid mapping: cannot seek to journal end (error=%d)",
        seek_error);
      return false;
    }

    uint written = FileWriteArray(handle, bytes, 0, (uint)ArraySize(bytes));
    int write_error = GetLastError();
    if(written != ArraySize(bytes) || write_error != 0)
    {
      FileClose(handle);
      PrintFormat(
        "TGK Grid mapping: journal append failed (written=%u, expected=%d, error=%d)",
        written,
        ArraySize(bytes),
        write_error);
      return false;
    }

    ResetLastError();
    FileFlush(handle);
    int flush_error = GetLastError();
    FileClose(handle);
    if(flush_error != 0)
    {
      PrintFormat(
        "TGK Grid mapping: journal flush failed (error=%d)",
        flush_error);
      return false;
    }

    return true;
  }

  // ลบไฟล์ที่เก็บ Journal ทิ้ง
  bool DeleteJournal()
  {
    if(!m_initialized)
      return false;

    ResetLastError();
    if(!FileIsExist(m_file_name))
      return true;

    if(!FileDelete(m_file_name))
    {
      PrintFormat(
        "TGK Grid mapping: cannot delete test journal (file=%s, error=%d)",
        m_file_name,
        GetLastError());
      return false;
    }

    return true;
  }
};

#endif
