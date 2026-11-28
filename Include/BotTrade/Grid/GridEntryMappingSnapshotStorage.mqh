#ifndef BOTTRADE_GRID_ENTRY_MAPPING_SNAPSHOT_STORAGE_MQH
#define BOTTRADE_GRID_ENTRY_MAPPING_SNAPSHOT_STORAGE_MQH

#include <BotTrade/Grid/GridEntryMappingReducer.mqh>

#define TGK_GRID_MAPPING_SNAPSHOT_SCHEMA_VERSION 1
#define TGK_GRID_MAPPING_MAX_SNAPSHOT_BYTES 16777216
#define TGK_GRID_MAPPING_MAX_JOURNAL_BYTES 16777216

enum ENUM_TGK_GRID_SNAPSHOT_FAILURE_POINT
{
  TGK_GRID_SNAPSHOT_FAIL_NONE = 0,
  TGK_GRID_SNAPSHOT_FAIL_AFTER_SNAPSHOT_TEMP_WRITE,
  TGK_GRID_SNAPSHOT_FAIL_AFTER_SNAPSHOT_READBACK,
  TGK_GRID_SNAPSHOT_FAIL_AFTER_JOURNAL_TEMP_WRITE,
  TGK_GRID_SNAPSHOT_FAIL_AFTER_JOURNAL_READBACK,
  TGK_GRID_SNAPSHOT_FAIL_AFTER_MANIFEST_TEMP_WRITE,
  TGK_GRID_SNAPSHOT_FAIL_AFTER_MANIFEST_READBACK,
  TGK_GRID_SNAPSHOT_FAIL_AFTER_GENERATION_VALIDATION,
  TGK_GRID_SNAPSHOT_FAIL_AFTER_MANIFEST_COMMIT,
  TGK_GRID_SNAPSHOT_FAIL_BEFORE_CLEANUP,
  TGK_GRID_SNAPSHOT_FAIL_AFTER_OLD_SNAPSHOT_DELETE
};

struct STGKGridMappingManifest
{
  bool valid;
  string slot;
  long commit_epoch;
  long snapshot_generation;
  long journal_generation;
  long checkpoint_sequence;
};

class CTGKGridEntryMappingSnapshotStorage
{
private:
  string m_symbol;
  string m_instance_id;
  string m_server;
  string m_identity;
  string m_identity_hex;
  string m_file_stem;
  long m_account_login;
  bool m_initialized;
  bool m_has_committed_state;
  bool m_append_blocked;
  ENUM_TGK_GRID_MAPPING_RECOVERY_STATUS m_recovery_status;
  ENUM_TGK_GRID_SNAPSHOT_FAILURE_POINT m_failure_point;
  string m_active_slot;
  long m_commit_epoch;
  long m_snapshot_generation;
  long m_journal_generation;
  long m_checkpoint_sequence;
  long m_next_sequence;
  string m_snapshot_payload;

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

  ulong Checksum(string value)
  {
    ulong hash = 5381;
    for(int i = 0; i < StringLen(value); i++)
      hash = (hash * 33 + (ulong)StringGetCharacter(value, i)) % 2147483647;
    return hash;
  }

  bool ToBytes(string value, uchar &bytes[], int &byte_count)
  {
    byte_count = StringToCharArray(
      value,
      bytes,
      0,
      WHOLE_ARRAY,
      CP_UTF8);
    if(byte_count <= 0)
      return false;

    byte_count--;
    if(ArrayResize(bytes, byte_count) != byte_count)
      return false;

    return byte_count <= TGK_GRID_MAPPING_MAX_SERIALIZATION_BUFFER_BYTES;
  }

  string FromBytes(uchar &bytes[])
  {
    return CharArrayToString(
      bytes,
      0,
      ArraySize(bytes),
      CP_UTF8);
  }

  string EncodeHex(string value)
  {
    uchar bytes[];
    int byte_count = 0;
    if(!ToBytes(value, bytes, byte_count))
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

  bool IsHexDigit(ushort value)
  {
    return (value >= '0' && value <= '9') ||
           (value >= 'A' && value <= 'F') ||
           (value >= 'a' && value <= 'f');
  }

  bool DecodeHex(string encoded, string &value)
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

    value = FromBytes(bytes);
    return true;
  }

  bool ValidateStringFields(string payload)
  {
    string fields[];
    int count = StringSplit(payload, '|', fields);
    if(payload == "")
      return true;
    if(count <= 0)
      return false;

    for(int i = 0; i < count; i++)
    {
      uchar bytes[];
      int byte_count = 0;
      if(!ToBytes(fields[i], bytes, byte_count) ||
         byte_count > TGK_GRID_MAPPING_MAX_STRING_FIELD_BYTES)
        return false;
    }
    return true;
  }

  string SnapshotFileName(long generation)
  {
    return StringFormat(
      "%s_snapshot_%I64d.dat",
      m_file_stem,
      generation);
  }

  string SnapshotTempFileName(long generation)
  {
    return StringFormat(
      "%s_snapshot_%I64d.tmp",
      m_file_stem,
      generation);
  }

  string JournalFileName(long generation)
  {
    return StringFormat(
      "%s_journal_%I64d.log",
      m_file_stem,
      generation);
  }

  string JournalTempFileName(long generation)
  {
    return StringFormat(
      "%s_journal_%I64d.tmp",
      m_file_stem,
      generation);
  }

  string JournalRepairTempFileName(long generation)
  {
    return StringFormat(
      "%s_journal_%I64d.repair.tmp",
      m_file_stem,
      generation);
  }

  string ManifestFileName(string slot)
  {
    return m_file_stem + "_manifest_" + slot + ".dat";
  }

  string ManifestTempFileName(string slot)
  {
    return m_file_stem + "_manifest_" + slot + ".tmp";
  }

  bool ReadTextFile(string file_name, string &content, int max_bytes)
  {
    content = "";
    ResetLastError();
    int handle = FileOpen(
      file_name,
      FILE_READ | FILE_BIN | FILE_SHARE_READ);
    if(handle == INVALID_HANDLE)
      return false;

    ulong size = FileSize(handle);
    if(size > (ulong)max_bytes)
    {
      FileClose(handle);
      return false;
    }

    uchar bytes[];
    if(ArrayResize(bytes, (int)size) != (int)size)
    {
      FileClose(handle);
      return false;
    }

    uint read_count = 0;
    if(size > 0)
      read_count = FileReadArray(handle, bytes, 0, (uint)size);
    FileClose(handle);
    if(read_count != size)
      return false;

    content = FromBytes(bytes);
    return true;
  }

  bool WriteTextFile(string file_name, string content, int max_bytes)
  {
    uchar bytes[];
    int byte_count = 0;
    if(!ToBytes(content, bytes, byte_count) ||
       byte_count > max_bytes)
      return false;

    ResetLastError();
    int handle = FileOpen(
      file_name,
      FILE_WRITE | FILE_BIN);
    if(handle == INVALID_HANDLE)
      return false;

    uint written = 0;
    if(byte_count > 0)
      written = FileWriteArray(handle, bytes, 0, (uint)byte_count);
    int write_error = GetLastError();
    if(written != byte_count || write_error != 0)
    {
      FileClose(handle);
      return false;
    }

    ResetLastError();
    FileFlush(handle);
    int flush_error = GetLastError();
    FileClose(handle);
    return flush_error == 0;
  }

  bool MoveReplace(string temp_name, string final_name)
  {
    ResetLastError();
    if(FileMove(temp_name, 0, final_name, FILE_REWRITE))
      return true;

    PrintFormat(
      "TGK Grid snapshot: cannot replace file %s (error=%d)",
      final_name,
      GetLastError());
    return false;
  }

  bool DeleteIfExists(string file_name)
  {
    if(!FileIsExist(file_name))
      return true;

    ResetLastError();
    if(FileDelete(file_name))
      return true;

    PrintFormat(
      "TGK Grid snapshot: cannot delete file %s (error=%d)",
      file_name,
      GetLastError());
    return false;
  }

  bool HasFilesMatching(string pattern)
  {
    string file_name;
    long search_handle = FileFindFirst(pattern, file_name);
    if(search_handle == INVALID_HANDLE)
      return false;
    FileFindClose(search_handle);
    return true;
  }

  bool HasUncommittedGenerationFiles()
  {
    return HasFilesMatching(m_file_stem + "_snapshot_*.dat") ||
           HasFilesMatching(m_file_stem + "_journal_*.log") ||
           HasFilesMatching(m_file_stem + "_snapshot_*.tmp") ||
           HasFilesMatching(m_file_stem + "_journal_*.tmp") ||
           HasFilesMatching(m_file_stem + "_journal_*.repair.tmp") ||
           HasFilesMatching(m_file_stem + "_manifest_*.tmp");
  }

  bool BuildSnapshotText(
    long generation,
    long checkpoint_sequence,
    string payload,
    string &content)
  {
    uchar payload_bytes[];
    int payload_byte_count = 0;
    if(!ToBytes(payload, payload_bytes, payload_byte_count))
      return false;

    string metadata = StringFormat(
      "TGKS|%d|%s|%I64d|%I64d|",
      TGK_GRID_MAPPING_SNAPSHOT_SCHEMA_VERSION,
      m_identity_hex,
      generation,
      checkpoint_sequence);
    if(StringLen(metadata) + payload_byte_count * 2 + 12 >
       TGK_GRID_MAPPING_MAX_SNAPSHOT_BYTES)
      return false;

    string payload_hex = EncodeHex(payload);
    if(payload != "" && payload_hex == "")
      return false;

    string body = StringFormat(
      "TGKS|%d|%s|%I64d|%I64d|%s",
      TGK_GRID_MAPPING_SNAPSHOT_SCHEMA_VERSION,
      m_identity_hex,
      generation,
      checkpoint_sequence,
      payload_hex);
    content = body + "|" +
              StringFormat("%I64d", (long)Checksum(body)) +
              "\n";

    if(StringLen(content) > TGK_GRID_MAPPING_MAX_SNAPSHOT_BYTES)
      return false;

    uchar bytes[];
    int byte_count = 0;
    if(!ToBytes(content, bytes, byte_count))
      return false;

    return byte_count <= TGK_GRID_MAPPING_MAX_SNAPSHOT_BYTES;
  }

  bool ValidateSnapshotText(
    string content,
    long expected_generation,
    long expected_checkpoint,
    string &payload)
  {
    payload = "";
    if(StringLen(content) == 0 ||
       StringGetCharacter(content, StringLen(content) - 1) != '\n')
      return false;

    string line = StringSubstr(content, 0, StringLen(content) - 1);
    string fields[];
    if(StringSplit(line, '|', fields) != 7 ||
       fields[0] != "TGKS" ||
       StringToInteger(fields[1]) != TGK_GRID_MAPPING_SNAPSHOT_SCHEMA_VERSION ||
       fields[2] != m_identity_hex ||
       StringToInteger(fields[3]) != expected_generation ||
       StringToInteger(fields[4]) != expected_checkpoint)
      return false;

    string body = StringSubstr(
      line,
      0,
      StringLen(line) - StringLen(fields[6]) - 1);
    if(Checksum(body) != (ulong)StringToInteger(fields[6]))
      return false;

    return DecodeHex(fields[5], payload);
  }

  string BuildJournalHeader(long generation, long base_sequence)
  {
    string body = StringFormat(
      "TGKJH|%d|%s|%I64d|%I64d",
      TGK_GRID_MAPPING_SNAPSHOT_SCHEMA_VERSION,
      m_identity_hex,
      generation,
      base_sequence);
    return body + "|" +
           StringFormat("%I64d", (long)Checksum(body)) +
           "\n";
  }

  bool ParseJournalRecord(
    string line,
    long expected_sequence,
    STGKGridMappingJournalRecord &record)
  {
    string fields[];
    if(StringSplit(line, '|', fields) != 6 ||
       fields[0] != "TGKJ" ||
       StringToInteger(fields[1]) != TGK_GRID_ENTRY_MAPPING_SCHEMA_VERSION)
      return false;

    long sequence = StringToInteger(fields[2]);
    int type = (int)StringToInteger(fields[3]);
    if(sequence != expected_sequence ||
       sequence <= 0 ||
       type < TGK_GRID_MAPPING_RECORD_ENTRY_INTENT ||
       type > TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE)
      return false;

    string body = StringSubstr(
      line,
      0,
      StringLen(line) - StringLen(fields[5]) - 1);
    if(Checksum(body) != (ulong)StringToInteger(fields[5]))
      return false;

    string payload;
    if(!DecodeHex(fields[4], payload) ||
       !ValidateStringFields(payload))
      return false;

    record.sequence = sequence;
    record.record_type = (ENUM_TGK_GRID_MAPPING_RECORD_TYPE)type;
    record.payload = payload;
    return true;
  }

  string BuildJournalRecord(
    long sequence,
    ENUM_TGK_GRID_MAPPING_RECORD_TYPE record_type,
    string payload)
  {
    string encoded_payload = EncodeHex(payload);
    if(payload != "" && encoded_payload == "")
      return "";

    string body = StringFormat(
      "TGKJ|%d|%I64d|%d|%s",
      TGK_GRID_ENTRY_MAPPING_SCHEMA_VERSION,
      sequence,
      (int)record_type,
      encoded_payload);
    return body + "|" +
           StringFormat("%I64d", (long)Checksum(body)) +
           "\n";
  }

  bool ValidateJournalText(
    string content,
    long generation,
    long base_sequence,
    STGKGridMappingJournalRecord &records[],
    int &record_count,
    long &next_sequence)
  {
    record_count = 0;
    next_sequence = base_sequence;
    ArrayResize(records, 0);

    if(StringLen(content) == 0)
      return false;

    int last_newline = -1;
    for(int i = StringLen(content) - 1; i >= 0; i--)
    {
      if(StringGetCharacter(content, i) == '\n')
      {
        last_newline = i;
        break;
      }
    }
    if(last_newline < 0)
      return false;

    string complete_content = StringSubstr(content, 0, last_newline + 1);
    string lines[];
    int line_count = StringSplit(complete_content, '\n', lines);
    if(line_count < 1)
      return false;

    string header_fields[];
    if(StringSplit(lines[0], '|', header_fields) != 6 ||
       header_fields[0] != "TGKJH" ||
       StringToInteger(header_fields[1]) != TGK_GRID_MAPPING_SNAPSHOT_SCHEMA_VERSION ||
       header_fields[2] != m_identity_hex ||
       StringToInteger(header_fields[3]) != generation ||
       StringToInteger(header_fields[4]) != base_sequence)
      return false;

    string header_body = StringSubstr(
      lines[0],
      0,
      StringLen(lines[0]) - StringLen(header_fields[5]) - 1);
    if(Checksum(header_body) != (ulong)StringToInteger(header_fields[5]))
      return false;

    long expected_sequence = base_sequence;
    for(int i = 1; i < line_count; i++)
    {
      if(lines[i] == "")
        continue;

      STGKGridMappingJournalRecord record;
      if(!ParseJournalRecord(lines[i], expected_sequence, record))
        return false;

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

  bool TrimIncompleteJournalTail()
  {
    string file_name = JournalFileName(m_journal_generation);
    ResetLastError();
    int tail_handle = FileOpen(
      file_name,
      FILE_READ | FILE_BIN | FILE_SHARE_READ);
    if(tail_handle == INVALID_HANDLE)
      return false;

    ulong file_size = FileSize(tail_handle);
    if(file_size == 0 || !FileSeek(tail_handle, -1, SEEK_END))
    {
      FileClose(tail_handle);
      return false;
    }

    uchar last_byte[];
    ArrayResize(last_byte, 1);
    uint tail_read = FileReadArray(tail_handle, last_byte, 0, 1);
    FileClose(tail_handle);
    if(tail_read != 1)
      return false;
    if(last_byte[0] == 10)
      return true;

    string content;
    if(!ReadTextFile(
      file_name,
      content,
      TGK_GRID_MAPPING_MAX_JOURNAL_BYTES))
      return false;

    if(StringLen(content) == 0)
      return false;

    int last_newline = -1;
    for(int i = StringLen(content) - 1; i >= 0; i--)
    {
      if(StringGetCharacter(content, i) == '\n')
      {
        last_newline = i;
        break;
      }
    }
    if(last_newline < 0)
      return false;

    string complete_content = StringSubstr(content, 0, last_newline + 1);
    STGKGridMappingJournalRecord records[];
    int record_count = 0;
    long next_sequence = 0;
    if(!ValidateJournalText(
      complete_content,
      m_journal_generation,
      m_checkpoint_sequence + 1,
      records,
      record_count,
      next_sequence))
      return false;

    string temp_name = JournalRepairTempFileName(m_journal_generation);
    if(!DeleteIfExists(temp_name) ||
       !WriteTextFile(
         temp_name,
         complete_content,
         TGK_GRID_MAPPING_MAX_JOURNAL_BYTES))
      return false;

    string readback;
    STGKGridMappingJournalRecord readback_records[];
    int readback_count = 0;
    long readback_next_sequence = 0;
    if(!ReadTextFile(
      temp_name,
      readback,
      TGK_GRID_MAPPING_MAX_JOURNAL_BYTES) ||
       !ValidateJournalText(
         readback,
         m_journal_generation,
         m_checkpoint_sequence + 1,
         readback_records,
         readback_count,
         readback_next_sequence) ||
       readback_count != record_count ||
       readback_next_sequence != next_sequence)
      return false;

    if(!MoveReplace(temp_name, file_name))
      return false;

    string final_readback;
    STGKGridMappingJournalRecord final_records[];
    int final_count = 0;
    long final_next_sequence = 0;
    return ReadTextFile(
      file_name,
      final_readback,
      TGK_GRID_MAPPING_MAX_JOURNAL_BYTES) &&
      ValidateJournalText(
        final_readback,
        m_journal_generation,
        m_checkpoint_sequence + 1,
        final_records,
        final_count,
        final_next_sequence) &&
      final_count == record_count &&
      final_next_sequence == next_sequence;
  }

  string BuildManifestText(
    long commit_epoch,
    long snapshot_generation,
    long journal_generation,
    long checkpoint_sequence)
  {
    string body = StringFormat(
      "TGKM|%d|%s|%I64d|%I64d|%I64d|%I64d",
      TGK_GRID_MAPPING_SNAPSHOT_SCHEMA_VERSION,
      m_identity_hex,
      commit_epoch,
      snapshot_generation,
      journal_generation,
      checkpoint_sequence);
    return body + "|" +
           StringFormat("%I64d", (long)Checksum(body)) +
           "\n";
  }

  bool ReadManifest(string slot, STGKGridMappingManifest &manifest)
  {
    manifest.valid = false;
    manifest.slot = slot;
    manifest.commit_epoch = 0;
    manifest.snapshot_generation = 0;
    manifest.journal_generation = 0;
    manifest.checkpoint_sequence = 0;

    string content;
    if(!ReadTextFile(ManifestFileName(slot), content, 4096))
      return false;
    if(StringLen(content) == 0 ||
       StringGetCharacter(content, StringLen(content) - 1) != '\n')
      return false;

    string line = StringSubstr(content, 0, StringLen(content) - 1);
    string fields[];
    if(StringSplit(line, '|', fields) != 8 ||
       fields[0] != "TGKM" ||
       StringToInteger(fields[1]) != TGK_GRID_MAPPING_SNAPSHOT_SCHEMA_VERSION ||
       fields[2] != m_identity_hex)
      return false;

    string body = StringSubstr(
      line,
      0,
      StringLen(line) - StringLen(fields[7]) - 1);
    if(Checksum(body) != (ulong)StringToInteger(fields[7]))
      return false;

    manifest.commit_epoch = StringToInteger(fields[3]);
    manifest.snapshot_generation = StringToInteger(fields[4]);
    manifest.journal_generation = StringToInteger(fields[5]);
    manifest.checkpoint_sequence = StringToInteger(fields[6]);
    if(manifest.commit_epoch <= 0 ||
       manifest.snapshot_generation <= 0 ||
       manifest.journal_generation <= 0 ||
       manifest.checkpoint_sequence < 0)
      return false;

    manifest.valid = true;
    return true;
  }

  bool ValidateManifestData(
    STGKGridMappingManifest &manifest,
    string &snapshot_payload,
    STGKGridMappingJournalRecord &records[],
    int &record_count,
    long &next_sequence)
  {
    string snapshot_text;
    if(!ReadTextFile(
      SnapshotFileName(manifest.snapshot_generation),
      snapshot_text,
      TGK_GRID_MAPPING_MAX_SNAPSHOT_BYTES))
      return false;

    if(!ValidateSnapshotText(
      snapshot_text,
      manifest.snapshot_generation,
      manifest.checkpoint_sequence,
      snapshot_payload))
      return false;

    string journal_text;
    if(!ReadTextFile(
      JournalFileName(manifest.journal_generation),
      journal_text,
      TGK_GRID_MAPPING_MAX_JOURNAL_BYTES))
      return false;

    return ValidateJournalText(
      journal_text,
      manifest.journal_generation,
      manifest.checkpoint_sequence + 1,
      records,
      record_count,
      next_sequence);
  }

  bool WriteGeneration(
    long generation,
    long checkpoint_sequence,
    string snapshot_payload)
  {
    string snapshot_content;
    if(!BuildSnapshotText(
      generation,
      checkpoint_sequence,
      snapshot_payload,
      snapshot_content))
      return false;

    string snapshot_temp = SnapshotTempFileName(generation);
    string snapshot_final = SnapshotFileName(generation);
    if(!WriteTextFile(
      snapshot_temp,
      snapshot_content,
      TGK_GRID_MAPPING_MAX_SNAPSHOT_BYTES))
      return false;
    if(m_failure_point == TGK_GRID_SNAPSHOT_FAIL_AFTER_SNAPSHOT_TEMP_WRITE)
      return false;

    string snapshot_readback;
    string snapshot_payload_readback;
    if(!ReadTextFile(
      snapshot_temp,
      snapshot_readback,
      TGK_GRID_MAPPING_MAX_SNAPSHOT_BYTES) ||
       !ValidateSnapshotText(
         snapshot_readback,
         generation,
         checkpoint_sequence,
         snapshot_payload_readback) ||
       snapshot_payload_readback != snapshot_payload)
      return false;

    if(m_failure_point == TGK_GRID_SNAPSHOT_FAIL_AFTER_SNAPSHOT_READBACK)
      return false;

    if(!MoveReplace(snapshot_temp, snapshot_final))
      return false;

    string final_snapshot_readback;
    string final_snapshot_payload;
    if(!ReadTextFile(
      snapshot_final,
      final_snapshot_readback,
      TGK_GRID_MAPPING_MAX_SNAPSHOT_BYTES) ||
       !ValidateSnapshotText(
         final_snapshot_readback,
         generation,
         checkpoint_sequence,
         final_snapshot_payload) ||
       final_snapshot_payload != snapshot_payload)
      return false;

    string journal_header = BuildJournalHeader(
      generation,
      checkpoint_sequence + 1);
    string journal_temp = JournalTempFileName(generation);
    string journal_final = JournalFileName(generation);
    if(!WriteTextFile(
      journal_temp,
      journal_header,
      TGK_GRID_MAPPING_MAX_JOURNAL_BYTES))
      return false;
    if(m_failure_point == TGK_GRID_SNAPSHOT_FAIL_AFTER_JOURNAL_TEMP_WRITE)
      return false;

    string journal_readback;
    STGKGridMappingJournalRecord empty_records[];
    int empty_count = 0;
    long empty_next_sequence = 0;
    if(!ReadTextFile(
      journal_temp,
      journal_readback,
      TGK_GRID_MAPPING_MAX_JOURNAL_BYTES) ||
       !ValidateJournalText(
         journal_readback,
         generation,
         checkpoint_sequence + 1,
         empty_records,
         empty_count,
         empty_next_sequence) ||
       empty_count != 0 ||
       empty_next_sequence != checkpoint_sequence + 1)
      return false;

    if(m_failure_point == TGK_GRID_SNAPSHOT_FAIL_AFTER_JOURNAL_READBACK)
      return false;

    if(!MoveReplace(journal_temp, journal_final))
      return false;

    string final_journal_readback;
    STGKGridMappingJournalRecord final_records[];
    int final_record_count = 0;
    long final_next_sequence = 0;
    if(!ReadTextFile(
      journal_final,
      final_journal_readback,
      TGK_GRID_MAPPING_MAX_JOURNAL_BYTES) ||
       !ValidateJournalText(
         final_journal_readback,
         generation,
         checkpoint_sequence + 1,
         final_records,
         final_record_count,
         final_next_sequence) ||
       final_record_count != 0 ||
       final_next_sequence != checkpoint_sequence + 1)
      return false;

    return true;
  }

  bool CommitManifest(
    string slot,
    long commit_epoch,
    long snapshot_generation,
    long journal_generation,
    long checkpoint_sequence)
  {
    string content = BuildManifestText(
      commit_epoch,
      snapshot_generation,
      journal_generation,
      checkpoint_sequence);
    string temp_name = ManifestTempFileName(slot);
    string final_name = ManifestFileName(slot);

    if(!WriteTextFile(temp_name, content, 4096))
      return false;
    if(m_failure_point == TGK_GRID_SNAPSHOT_FAIL_AFTER_MANIFEST_TEMP_WRITE)
      return false;

    string readback;
    if(!ReadTextFile(temp_name, readback, 4096) ||
       readback != content)
      return false;
    if(m_failure_point == TGK_GRID_SNAPSHOT_FAIL_AFTER_MANIFEST_READBACK)
      return false;

    if(!MoveReplace(temp_name, final_name))
      return false;

    if(!ReadTextFile(final_name, readback, 4096) ||
       readback != content)
      return false;

    return true;
  }

  bool CleanupOldGeneration(
    long old_snapshot_generation,
    long old_journal_generation)
  {
    if(old_snapshot_generation > 0 &&
       old_snapshot_generation != m_snapshot_generation &&
       !DeleteIfExists(SnapshotFileName(old_snapshot_generation)))
      return false;

    if(m_failure_point == TGK_GRID_SNAPSHOT_FAIL_AFTER_OLD_SNAPSHOT_DELETE)
      return false;

    if(old_snapshot_generation > 0 &&
       old_snapshot_generation != m_snapshot_generation &&
       !DeleteIfExists(SnapshotTempFileName(old_snapshot_generation)))
      return false;

    if(old_journal_generation > 0 &&
       old_journal_generation != m_journal_generation &&
       (!DeleteIfExists(JournalFileName(old_journal_generation)) ||
        !DeleteIfExists(JournalTempFileName(old_journal_generation)) ||
        !DeleteIfExists(JournalRepairTempFileName(old_journal_generation))))
      return false;

    if(!DeleteIfExists(SnapshotTempFileName(m_snapshot_generation)) ||
       !DeleteIfExists(JournalTempFileName(m_journal_generation)) ||
       !DeleteIfExists(JournalRepairTempFileName(m_journal_generation)) ||
       !DeleteIfExists(ManifestTempFileName("A")) ||
       !DeleteIfExists(ManifestTempFileName("B")))
      return false;

    return true;
  }

  bool RecoverInternal()
  {
    STGKGridMappingManifest manifest_a;
    STGKGridMappingManifest manifest_b;
    bool parsed_a = ReadManifest("A", manifest_a);
    bool parsed_b = ReadManifest("B", manifest_b);

    string payload_a;
    string payload_b;
    STGKGridMappingJournalRecord records_a[];
    STGKGridMappingJournalRecord records_b[];
    int count_a = 0;
    int count_b = 0;
    long next_a = 0;
    long next_b = 0;

    bool valid_a = parsed_a &&
      ValidateManifestData(
        manifest_a,
        payload_a,
        records_a,
        count_a,
        next_a);
    bool valid_b = parsed_b &&
      ValidateManifestData(
        manifest_b,
        payload_b,
        records_b,
        count_b,
        next_b);

    if(!valid_a && !valid_b)
    {
      bool has_manifest = FileIsExist(ManifestFileName("A")) ||
                          FileIsExist(ManifestFileName("B"));
      if(has_manifest || HasUncommittedGenerationFiles())
      {
        m_recovery_status = TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR;
        m_has_committed_state = false;
        return false;
      }

      m_has_committed_state = false;
      m_recovery_status = TGK_GRID_MAPPING_STATUS_NORMAL;
      return true;
    }

    if(valid_a && valid_b &&
       manifest_a.commit_epoch == manifest_b.commit_epoch &&
       (manifest_a.snapshot_generation != manifest_b.snapshot_generation ||
        manifest_a.journal_generation != manifest_b.journal_generation ||
        manifest_a.checkpoint_sequence != manifest_b.checkpoint_sequence))
    {
      m_recovery_status = TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR;
      m_has_committed_state = false;
      return false;
    }

    STGKGridMappingManifest selected;
    if(valid_a && (!valid_b || manifest_a.commit_epoch >= manifest_b.commit_epoch))
    {
      selected = manifest_a;
      m_snapshot_payload = payload_a;
      m_next_sequence = next_a;
    }
    else
    {
      selected = manifest_b;
      m_snapshot_payload = payload_b;
      m_next_sequence = next_b;
    }

    m_active_slot = selected.slot;
    m_commit_epoch = selected.commit_epoch;
    m_snapshot_generation = selected.snapshot_generation;
    m_journal_generation = selected.journal_generation;
    m_checkpoint_sequence = selected.checkpoint_sequence;
    m_has_committed_state = true;
    m_append_blocked = false;
    m_recovery_status = TGK_GRID_MAPPING_STATUS_NORMAL;

    string inactive_slot = m_active_slot == "A" ? "B" : "A";
    STGKGridMappingManifest inactive_manifest;
    bool cleanup_ok = true;
    if(ReadManifest(inactive_slot, inactive_manifest))
    {
      if(!CleanupOldGeneration(
        inactive_manifest.snapshot_generation,
        inactive_manifest.journal_generation))
        cleanup_ok = false;
    }
    else
    {
      long previous_snapshot_generation = m_snapshot_generation - 1;
      long previous_journal_generation = m_journal_generation - 1;
      if(!CleanupOldGeneration(
        previous_snapshot_generation,
        previous_journal_generation))
        cleanup_ok = false;
    }

    if(!DeleteIfExists(SnapshotTempFileName(m_snapshot_generation)) ||
       !DeleteIfExists(JournalTempFileName(m_journal_generation)) ||
       !DeleteIfExists(JournalRepairTempFileName(m_journal_generation)) ||
       !DeleteIfExists(ManifestTempFileName("A")) ||
       !DeleteIfExists(ManifestTempFileName("B")))
      cleanup_ok = false;

    long orphan_generation = m_snapshot_generation > m_journal_generation
                              ? m_snapshot_generation
                              : m_journal_generation;
    orphan_generation++;
    if(!DeleteIfExists(SnapshotFileName(orphan_generation)) ||
       !DeleteIfExists(JournalFileName(orphan_generation)) ||
       !DeleteIfExists(SnapshotTempFileName(orphan_generation)) ||
       !DeleteIfExists(JournalTempFileName(orphan_generation)) ||
       !DeleteIfExists(JournalRepairTempFileName(orphan_generation)) ||
       !DeleteIfExists(ManifestTempFileName("A")) ||
       !DeleteIfExists(ManifestTempFileName("B")))
      cleanup_ok = false;

    if(!cleanup_ok)
      m_recovery_status = TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR;

    return true;
  }

  bool IsValidRecordType(ENUM_TGK_GRID_MAPPING_RECORD_TYPE record_type)
  {
    return record_type >= TGK_GRID_MAPPING_RECORD_ENTRY_INTENT &&
           record_type <= TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE;
  }

public:
  CTGKGridEntryMappingSnapshotStorage()
  {
    m_symbol = "";
    m_instance_id = "";
    m_server = "";
    m_identity = "";
    m_identity_hex = "";
    m_file_stem = "";
    m_account_login = 0;
    m_initialized = false;
    m_has_committed_state = false;
    m_append_blocked = false;
    m_recovery_status = TGK_GRID_MAPPING_STATUS_NORMAL;
    m_failure_point = TGK_GRID_SNAPSHOT_FAIL_NONE;
    m_active_slot = "";
    m_commit_epoch = 0;
    m_snapshot_generation = 0;
    m_journal_generation = 0;
    m_checkpoint_sequence = 0;
    m_next_sequence = 1;
    m_snapshot_payload = "";
  }

  bool Initialize(string symbol, string instance_id)
  {
    m_initialized = false;
    m_has_committed_state = false;
    m_append_blocked = false;
    m_recovery_status = TGK_GRID_MAPPING_STATUS_NORMAL;
    m_active_slot = "";
    m_commit_epoch = 0;
    m_snapshot_generation = 0;
    m_journal_generation = 0;
    m_checkpoint_sequence = 0;
    m_next_sequence = 1;
    m_snapshot_payload = "";

    if(symbol == "" || instance_id == "")
      return false;

    long account_login = AccountInfoInteger(ACCOUNT_LOGIN);
    string server = AccountInfoString(ACCOUNT_SERVER);
    if(account_login <= 0 || server == "")
      return false;

    m_symbol = symbol;
    m_instance_id = instance_id;
    m_server = server;
    m_account_login = account_login;
    m_identity = StringFormat(
      "%I64d|%s|%s|%s",
      account_login,
      server,
      symbol,
      instance_id);
    m_identity_hex = EncodeHex(m_identity);
    if(m_identity_hex == "")
      return false;

    string identity_suffix = StringFormat(
      "%I64d",
      (long)Checksum(m_identity));
    m_file_stem = StringFormat(
      "TGK_EntryMap_%I64d_%s_%s_%s_%s",
      account_login,
      SafeFilePart(server),
      SafeFilePart(symbol),
      SafeFilePart(instance_id),
      identity_suffix);

    if(!RecoverInternal() &&
       m_recovery_status != TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR)
      return false;

    m_initialized = true;
    return true;
  }

  bool IsInitialized()
  {
    return m_initialized;
  }

  bool HasCommittedState()
  {
    return m_has_committed_state;
  }

  ENUM_TGK_GRID_MAPPING_RECOVERY_STATUS RecoveryStatus()
  {
    return m_recovery_status;
  }

  long LastSequence()
  {
    return m_next_sequence - 1;
  }

  long CheckpointSequence()
  {
    return m_checkpoint_sequence;
  }

  string SnapshotPayload()
  {
    return m_snapshot_payload;
  }

  string FileStem()
  {
    return m_file_stem;
  }

  void SetFailurePointForTest(ENUM_TGK_GRID_SNAPSHOT_FAILURE_POINT failure_point)
  {
    m_failure_point = failure_point;
  }

  bool Bootstrap(string snapshot_payload, long checkpoint_sequence)
  {
    if(!m_initialized ||
       m_has_committed_state ||
       m_recovery_status != TGK_GRID_MAPPING_STATUS_NORMAL ||
       checkpoint_sequence < 0)
      return false;

    long generation = 1;
    if(!WriteGeneration(generation, checkpoint_sequence, snapshot_payload))
    {
      m_recovery_status = TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR;
      return false;
    }

    if(!CommitManifest(
      "A",
      1,
      generation,
      generation,
      checkpoint_sequence))
    {
      m_recovery_status = TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR;
      return false;
    }

    m_active_slot = "A";
    m_commit_epoch = 1;
    m_snapshot_generation = generation;
    m_journal_generation = generation;
    m_checkpoint_sequence = checkpoint_sequence;
    m_next_sequence = checkpoint_sequence + 1;
    m_snapshot_payload = snapshot_payload;
    m_has_committed_state = true;
    m_append_blocked = false;

    if(m_failure_point == TGK_GRID_SNAPSHOT_FAIL_AFTER_MANIFEST_COMMIT)
    {
      m_recovery_status = TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR;
      return false;
    }

    if(m_failure_point == TGK_GRID_SNAPSHOT_FAIL_BEFORE_CLEANUP)
    {
      m_recovery_status = TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR;
      return false;
    }

    m_recovery_status = TGK_GRID_MAPPING_STATUS_NORMAL;
    return true;
  }

  bool Append(
    ENUM_TGK_GRID_MAPPING_RECORD_TYPE record_type,
    string payload)
  {
    if(!m_initialized ||
       !m_has_committed_state ||
       m_append_blocked ||
       m_recovery_status == TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR ||
       (m_recovery_status == TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR &&
        record_type == TGK_GRID_MAPPING_RECORD_ENTRY_INTENT) ||
       !IsValidRecordType(record_type) ||
       !ValidateStringFields(payload))
      return false;

    string line = BuildJournalRecord(m_next_sequence, record_type, payload);
    if(line == "")
      return false;

    if(StringLen(line) > TGK_GRID_MAPPING_MAX_RECORD_BYTES)
      return false;

    uchar bytes[];
    int byte_count = 0;
    if(!ToBytes(line, bytes, byte_count) ||
       byte_count > TGK_GRID_MAPPING_MAX_RECORD_BYTES)
      return false;

    if(!TrimIncompleteJournalTail())
    {
      m_append_blocked = true;
      m_recovery_status = TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR;
      return false;
    }

    string file_name = JournalFileName(m_journal_generation);
    ResetLastError();
    int handle = FileOpen(
      file_name,
      FILE_READ | FILE_WRITE | FILE_BIN | FILE_SHARE_READ);
    if(handle == INVALID_HANDLE)
    {
      m_append_blocked = true;
      m_recovery_status = TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR;
      return false;
    }

    ulong current_size = FileSize(handle);
    if(current_size + (ulong)byte_count > TGK_GRID_MAPPING_MAX_JOURNAL_BYTES)
    {
      FileClose(handle);
      return false;
    }

    if(!FileSeek(handle, 0, SEEK_END))
    {
      FileClose(handle);
      m_append_blocked = true;
      m_recovery_status = TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR;
      return false;
    }

    ResetLastError();
    uint written = FileWriteArray(handle, bytes, 0, (uint)byte_count);
    int write_error = GetLastError();
    if(written != byte_count || write_error != 0)
    {
      FileClose(handle);
      m_append_blocked = true;
      m_recovery_status = TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR;
      return false;
    }

    ResetLastError();
    FileFlush(handle);
    int flush_error = GetLastError();
    FileClose(handle);
    if(flush_error != 0)
    {
      m_append_blocked = true;
      m_recovery_status = TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR;
      return false;
    }

    m_next_sequence++;
    return true;
  }

  bool NeedsRotation(
    ENUM_TGK_GRID_MAPPING_RECORD_TYPE record_type,
    string payload)
  {
    if(!m_initialized ||
       !m_has_committed_state ||
       m_append_blocked ||
       !IsValidRecordType(record_type) ||
       !ValidateStringFields(payload))
      return false;

    string line = BuildJournalRecord(m_next_sequence, record_type, payload);
    if(line == "")
      return false;

    if(StringLen(line) > TGK_GRID_MAPPING_MAX_RECORD_BYTES)
      return false;

    uchar bytes[];
    int byte_count = 0;
    if(!ToBytes(line, bytes, byte_count) ||
       byte_count > TGK_GRID_MAPPING_MAX_RECORD_BYTES)
      return false;

    int handle = FileOpen(
      JournalFileName(m_journal_generation),
      FILE_READ | FILE_BIN | FILE_SHARE_READ);
    if(handle == INVALID_HANDLE)
      return true;

    ulong size = FileSize(handle);
    FileClose(handle);
    return size + (ulong)byte_count > TGK_GRID_MAPPING_MAX_JOURNAL_BYTES;
  }

  bool Rotate(string snapshot_payload, long checkpoint_sequence)
  {
    if(!m_initialized ||
       !m_has_committed_state ||
       m_recovery_status != TGK_GRID_MAPPING_STATUS_NORMAL ||
       checkpoint_sequence != LastSequence())
      return false;

    long new_generation = m_commit_epoch + 1;
    if(new_generation <= m_snapshot_generation ||
       new_generation <= m_journal_generation)
    {
      new_generation = m_snapshot_generation > m_journal_generation
                       ? m_snapshot_generation
                       : m_journal_generation;
      new_generation++;
    }

    if(!DeleteIfExists(SnapshotTempFileName(new_generation)) ||
       !DeleteIfExists(JournalTempFileName(new_generation)) ||
       !DeleteIfExists(SnapshotFileName(new_generation)) ||
       !DeleteIfExists(JournalFileName(new_generation)))
    {
      m_recovery_status = TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR;
      return false;
    }

    if(!WriteGeneration(
      new_generation,
      checkpoint_sequence,
      snapshot_payload))
    {
      m_recovery_status = TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR;
      return false;
    }
    if(m_failure_point == TGK_GRID_SNAPSHOT_FAIL_AFTER_GENERATION_VALIDATION)
    {
      m_recovery_status = TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR;
      return false;
    }

    string inactive_slot = m_active_slot == "A" ? "B" : "A";
    if(!CommitManifest(
      inactive_slot,
      m_commit_epoch + 1,
      new_generation,
      new_generation,
      checkpoint_sequence))
    {
      m_recovery_status = TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR;
      return false;
    }

    long old_snapshot_generation = m_snapshot_generation;
    long old_journal_generation = m_journal_generation;

    m_active_slot = inactive_slot;
    m_commit_epoch++;
    m_snapshot_generation = new_generation;
    m_journal_generation = new_generation;
    m_checkpoint_sequence = checkpoint_sequence;
    m_next_sequence = checkpoint_sequence + 1;
    m_snapshot_payload = snapshot_payload;
    m_append_blocked = false;

    if(m_failure_point == TGK_GRID_SNAPSHOT_FAIL_AFTER_MANIFEST_COMMIT ||
       m_failure_point == TGK_GRID_SNAPSHOT_FAIL_BEFORE_CLEANUP)
    {
      m_recovery_status = TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR;
      return false;
    }

    if(!CleanupOldGeneration(
      old_snapshot_generation,
      old_journal_generation))
    {
      m_recovery_status = TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR;
      return false;
    }

    m_recovery_status = TGK_GRID_MAPPING_STATUS_NORMAL;
    return true;
  }

  bool Replay(
    string &snapshot_payload,
    long &checkpoint_sequence,
    STGKGridMappingJournalRecord &records[],
    int &record_count,
    long &next_sequence)
  {
    snapshot_payload = "";
    checkpoint_sequence = 0;
    record_count = 0;
    next_sequence = 1;
    ArrayResize(records, 0);

    if(!m_initialized ||
       !m_has_committed_state ||
       m_recovery_status == TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR)
      return false;

    string snapshot_text;
    if(!ReadTextFile(
      SnapshotFileName(m_snapshot_generation),
      snapshot_text,
      TGK_GRID_MAPPING_MAX_SNAPSHOT_BYTES) ||
       !ValidateSnapshotText(
         snapshot_text,
         m_snapshot_generation,
         m_checkpoint_sequence,
         snapshot_payload))
    {
      m_recovery_status = TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR;
      return false;
    }

    string journal_text;
    if(!ReadTextFile(
      JournalFileName(m_journal_generation),
      journal_text,
      TGK_GRID_MAPPING_MAX_JOURNAL_BYTES) ||
       !ValidateJournalText(
         journal_text,
         m_journal_generation,
         m_checkpoint_sequence + 1,
         records,
         record_count,
         next_sequence))
    {
      m_recovery_status = TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR;
      return false;
    }

    checkpoint_sequence = m_checkpoint_sequence;
    return true;
  }

  bool DeleteAllFilesForTest()
  {
    if(!m_initialized)
      return false;

    bool ok = true;
    for(long generation = 1; generation <= m_commit_epoch + 2; generation++)
    {
      if(!DeleteIfExists(SnapshotFileName(generation)))
        ok = false;
      if(!DeleteIfExists(JournalFileName(generation)))
        ok = false;
      if(!DeleteIfExists(SnapshotTempFileName(generation)))
        ok = false;
      if(!DeleteIfExists(JournalTempFileName(generation)))
        ok = false;
      if(!DeleteIfExists(JournalRepairTempFileName(generation)))
        ok = false;
    }

    if(!DeleteIfExists(ManifestFileName("A")) ||
       !DeleteIfExists(ManifestFileName("B")) ||
       !DeleteIfExists(ManifestTempFileName("A")) ||
       !DeleteIfExists(ManifestTempFileName("B")))
      ok = false;

    return ok;
  }
};

#endif
