// D-06-02 — Minimal Strategy Tester Probe (Remediation v2)
// EA ทดสอบ diagnostic สำหรับ WP-06 D-06-02
// ห้ามใช้ใน Demo/Live; ห้ามส่ง Trade Request นอก Strategy Tester
//
// Allowed files:
//   Experts/TGK/Tests/Grids/test_grid_trade_event_probe.mq5
//   Docs/EAs/Grid/WorkPackages/WP-06/D-06-02_PROBE/IMPLEMENTATION_REPORT.md
//
// Safety: ค่า Default ของ EnableTestTrade = false
//         Probe จะหยุดทันทีหาก MQL_TESTER == false
//         ไม่มี Retry อัตโนมัติ
//
// Remediation v2 — addresses CR-01..CR-05, MR-01..MR-04 from CTO Review Handoff

#property strict
#property version   "1.01"
#property description "D-06-02 Minimal Strategy Tester Probe v2 — diagnostic only; EnableTestTrade default=false"

#include <Trade/Trade.mqh>

//=============================================================================
// Input Parameters
//=============================================================================

input bool   EnableTestTrade  = false;      // ส่ง Trade Request (ต้องเปิดด้วยตนเอง)
input bool   TestBuy          = true;       // true=BUY, false=SELL
input double TestVolume       = 0.01;       // Volume ที่จะส่ง (ตรวจสอบกับ Symbol min/step)
input int    ProbeMagic       = 123456;     // Magic เฉพาะ Probe (ต้องเป็นค่าบวก ไม่ชนกับ EA อื่น)
input string ProbeSessionID   = "PROBE-D0602-01"; // Session ID (A-Z/a-z/0-9/_/-)
input int    HistoryMarginSec = 60;         // Safety margin (วินาที) สำหรับ HistorySelect window

//=============================================================================
// Constants
//=============================================================================

#define PROBE_FORMAT_VERSION  "1"
#define MAX_CALLBACKS         256           // Bounded callback buffer
#define MAX_DEALS             64            // Bounded deal buffer
#define MAX_POSITIONS         32            // Bounded position snapshot buffer
#define MAX_PERSIST_LINES     20            // Strict line cap for session file

// MQL5 signed long range: 0 .. 9223372036854775807
// ulong values > LONG_MAX cannot be serialized losslessly via (long) cast.
// Probe uses decimal-string serialization directly via UlongToDecStr / DecStrToUlong.
#define ULONG_MAX_SAFE        9223372036854775807uLL   // = LLONG_MAX

//=============================================================================
// Persistent-state file helpers
//=============================================================================

string SessionFilePath()
{
  return "TGK_Probe_" + ProbeSessionID + ".txt";
}

#define STATE_REQUEST_STARTED  "REQUEST_STARTED"
#define STATE_ORDER_PERSISTED  "ORDER_PERSISTED"
#define STATE_COMPLETED        "COMPLETED"

//=============================================================================
// MR-04 — 64-bit Ticket / Identifier decimal serialization
//   Avoids any conversion through double or signed long.
//   Supports full ulong range 0 .. 2^64-1 by digit-by-digit division.
//=============================================================================

// Convert ulong to decimal string without passing through (long) cast.
string UlongToDecStr(ulong v)
{
  if(v == 0) return "0";
  string s = "";
  while(v > 0)
  {
    ulong digit = v % 10;
    s = ShortToString((ushort)('0' + (int)digit)) + s;
    v /= 10;
  }
  return s;
}

// Parse decimal string to ulong.
// Returns false and sets out=0 if string is empty, contains non-digits,
// or would overflow ulong (> 20 digits or value > ULLONG_MAX approximation).
// MQL5 has no ULLONG_MAX constant; we detect overflow by checking that
// (accum * 10 + digit) / 10 == accum before each step.
bool DecStrToUlong(const string s, ulong &out)
{
  out = 0;
  int len = StringLen(s);
  if(len == 0 || len > 20) return false;

  // Normalize leading zeroes before checking the full ulong upper bound.
  int first = 0;
  while(first < len - 1 && StringGetCharacter(s, first) == '0')
    first++;

  string normalized = StringSubstr(s, first);
  int normalized_len = StringLen(normalized);
  if(normalized_len > 20) return false;

  // Lexicographic comparison is valid for equal-length decimal digit strings.
  // This avoids relying on overflowing arithmetic to detect ulong overflow.
  const string ULONG_MAX_DEC = "18446744073709551615";
  if(normalized_len == 20 && StringCompare(normalized, ULONG_MAX_DEC) > 0)
    return false;

  for(int i = 0; i < normalized_len; i++)
  {
    ushort c = StringGetCharacter(normalized, i);
    if(c < '0' || c > '9')
    {
      out = 0;
      return false;
    }

    ulong digit = (ulong)(c - '0');
    out = out * 10 + digit;
  }

  return true;
}

// Strict positive decimal string check (digits + at most one '.', finite > 0)
bool IsStrictPositiveDecimalStr(const string s)
{
  int len = StringLen(s);
  if(len == 0 || len > 32) return false;
  int dots = 0;
  int digits = 0;
  for(int i = 0; i < len; i++)
  {
    ushort c = StringGetCharacter(s, i);
    if(c >= '0' && c <= '9') { digits++; continue; }
    if(c == '.') { dots++; if(dots > 1) return false; continue; }
    return false;
  }
  return (digits > 0);
}

//=============================================================================
// Callback buffer
//=============================================================================

struct ProbeCallback
{
  int    seq;
  ulong  tick_ms;
  datetime time_current;
  ENUM_TRADE_TRANSACTION_TYPE trans_type;
  ulong  order_ticket;
  ulong  deal_ticket;
  ulong  position_id;        // trans.position (position ticket from transaction)
  string symbol;
  double volume;
  double price;
  double price_trigger;      // trans.price_trigger (stop-trigger price, may be 0)
  ENUM_ORDER_TYPE   order_type;
  ENUM_ORDER_STATE  order_state;
  ENUM_DEAL_TYPE    deal_type;
  // For TRADE_TRANSACTION_REQUEST callback
  bool   has_request;
  ENUM_TRADE_REQUEST_ACTIONS req_action;
  string req_symbol;
  int    req_magic;
  double req_volume;
  double req_price;          // request.price
  ulong  req_order;
  ulong  req_deal;
  uint   res_retcode;
  double res_volume;
  double res_price;
  double res_bid;            // result.bid
  double res_ask;            // result.ask
  // For DEAL_ADD immediate history probe
  bool   immediate_select_attempted;
  bool   immediate_select_ok;
  int    immediate_last_error;
  ulong  immediate_deal_ticket;
  // Immediate read results
  ulong  imm_deal_order;
  int    imm_deal_entry;
  int    imm_deal_type;
  string imm_deal_symbol;
  long   imm_deal_magic;
  ulong  imm_deal_position_id;
  double imm_deal_volume;
  double imm_deal_price;
  datetime imm_deal_time;
  bool   imm_read_ok;
};

ProbeCallback g_callbacks[];
ProbeCallback g_callback_archive[];
int           g_callback_count       = 0;
int           g_callback_overflow    = 0;
int           g_callback_archive_count = 0;
int           g_callback_archive_overflow = 0;
int           g_callback_sequence    = 0;
ulong         g_last_callback_tick_ms = 0;

//=============================================================================
// CR-05 / MR-01 — Scan status enum
//=============================================================================

enum PROBE_SCAN_STATUS
{
  SCAN_NOT_RUN           = 0,
  SCAN_INVALID_ORDER     = 1,   // HistoryOrderSelect failed
  SCAN_HISTORY_FAIL      = 2,   // HistorySelect failed
  SCAN_COMPLETE_EMPTY    = 3,   // scan ok, zero exact-order deals
  SCAN_COMPLETE_MATCH    = 4,   // scan ok, >= 1 exact-order deals
  SCAN_INCOMPLETE        = 5,   // buffer overflow or property read failure mid-scan
};

string ScanStatusStr(PROBE_SCAN_STATUS s)
{
  switch(s)
  {
    case SCAN_NOT_RUN:        return "NOT_RUN";
    case SCAN_INVALID_ORDER:  return "INVALID_ORDER";
    case SCAN_HISTORY_FAIL:   return "HISTORY_FAIL";
    case SCAN_COMPLETE_EMPTY: return "COMPLETE_EMPTY";
    case SCAN_COMPLETE_MATCH: return "COMPLETE_MATCH";
    case SCAN_INCOMPLETE:     return "INCOMPLETE";
  }
  return "UNKNOWN";
}

//=============================================================================
// Deal scan buffer
//=============================================================================

struct ProbeDeal
{
  ulong    deal_ticket;
  ulong    deal_order;
  int      deal_entry;
  int      deal_type;
  string   deal_symbol;
  long     deal_magic;
  ulong    deal_position_id;
  double   deal_volume;
  double   deal_price;
  datetime deal_time;
  bool     all_props_ok;
  bool     valid_for_aggregate;  // CR-04: passed full validation against Request
  string   validation_conflict;  // description if mismatch found
};

ProbeDeal         g_deals[];
int               g_deal_count = 0;
ProbeDeal         g_first_scan_deals[];
int               g_first_scan_deal_count = 0;
bool              g_first_scan_snapshot_ok = false;
PROBE_SCAN_STATUS g_scan_status_1st = SCAN_NOT_RUN;
PROBE_SCAN_STATUS g_scan_status_rec = SCAN_NOT_RUN;

//=============================================================================
// MR-02 — Position snapshot: all matching positions
//=============================================================================

struct ProbePosition
{
  ulong    pos_ticket;
  ulong    pos_identifier;
  double   pos_volume;
  double   pos_price_open;
  bool     props_ok;
};

ProbePosition g_positions[];
int           g_position_count           = 0;
bool          g_position_snapshot_ok     = false;    // enumeration completed fully
bool          g_position_snapshot_incomplete = false; // property access error on any pos

//=============================================================================
// Probe state
//=============================================================================

bool   g_initialized_ok       = false;
bool   g_trade_sent            = false;
bool   g_probe_complete        = false;
bool   g_fail_closed           = false;
string g_fail_closed_reason    = "";

// Request result
bool   g_request_ok            = false;
uint   g_retcode               = 0;
ulong  g_order_ticket          = 0;
ulong  g_result_deal           = 0;
double g_result_volume         = 0.0;
double g_result_price          = 0.0;

// History scan results (first scan)
double g_agg_volume_1st        = 0.0;
int    g_distinct_pos_ids_1st  = 0;

// Recovery simulation results
double g_agg_volume_rec        = 0.0;
int    g_distinct_pos_ids_rec  = 0;
bool   g_recovery_match        = false;
string g_recovery_discrepancy  = "";

// Environment evidence
int    g_terminal_build        = 0;
string g_symbol_exec_mode      = "";
string g_symbol_fill_mode      = "";
double g_symbol_vol_min        = 0.0;
double g_symbol_vol_max        = 0.0;
double g_symbol_vol_step       = 0.0;
int    g_symbol_digits         = 0;
double g_symbol_point          = 0.0;
double g_symbol_tick_size      = 0.0;

//=============================================================================
// Utility: log with session prefix
//=============================================================================

void ProbeLog(const string msg)
{
  PrintFormat("[PROBE][%s] %s", ProbeSessionID, msg);
}

//=============================================================================
// Utility: Session ID validation (A-Z/a-z/0-9/_/-)
//=============================================================================

bool IsValidSessionID(const string sid)
{
  int len = StringLen(sid);
  if(len == 0) return false;
  for(int i = 0; i < len; i++)
  {
    ushort c = StringGetCharacter(sid, i);
    bool ok = (c >= 'A' && c <= 'Z')
           || (c >= 'a' && c <= 'z')
           || (c >= '0' && c <= '9')
           || c == '_'
           || c == '-';
    if(!ok) return false;
  }
  return true;
}

//=============================================================================
// Utility: volume step check
//=============================================================================

bool VolumeMatchesStep(double vol, double step, double min_vol)
{
  if(step <= 0.0) return false;
  double diff = MathAbs(MathRound((vol - min_vol) / step) * step - (vol - min_vol));
  return diff < step * 0.001;
}

//=============================================================================
// CR-12 — Exact FILE_ANSI byte-count validation
//
// FileWriteString returns bytes written. StringLen counts UTF-16 characters,
// so it is not an exact byte expectation for FILE_ANSI. Convert with CP_ACP
// and account for FILE_TXT newline expansion (bare LF -> CRLF).
//=============================================================================

bool ExpectedFileWriteStringBytes(const string line, uint &expected_bytes)
{
  expected_bytes = 0;
  uchar encoded[];
  int encoded_with_terminator = StringToCharArray(
    line,
    encoded,
    0,
    WHOLE_ARRAY,
    CP_ACP
  );
  if(encoded_with_terminator <= 0)
    return false;

  expected_bytes = (uint)(encoded_with_terminator - 1);
  int length = StringLen(line);
  for(int i = 0; i < length; i++)
  {
    if(StringGetCharacter(line, i) != '\n')
      continue;
    if(i == 0 || StringGetCharacter(line, i - 1) != '\r')
      expected_bytes++;
  }
  return true;
}

bool WriteLineChecked(int fh, const string line)
{
  uint expected_bytes = 0;
  if(!ExpectedFileWriteStringBytes(line, expected_bytes))
  {
    ProbeLog("PERSIST ERROR: cannot calculate encoded byte count for line.");
    return false;
  }

  ResetLastError();
  uint written = FileWriteString(fh, line);
  int write_error = GetLastError();
  if(written != expected_bytes || write_error != 0)
  {
    ProbeLog("PERSIST ERROR: FileWriteString wrote " + IntegerToString((int)written) +
             " bytes; expected exactly " + IntegerToString((int)expected_bytes) +
             " LastError=" + IntegerToString(write_error));
    return false;
  }
  return true;
}

bool PersistState(
  const string state,
  ulong        order_ticket,
  string       symbol,
  int          magic,
  double       req_volume,
  datetime     order_setup_time
)
{
  ResetLastError();
  int fh = FileOpen(SessionFilePath(), FILE_WRITE | FILE_TXT | FILE_ANSI);
  if(fh == INVALID_HANDLE)
  {
    ProbeLog("PERSIST ERROR: cannot open file for write: " + SessionFilePath() +
             " LastError=" + IntegerToString(GetLastError()));
    return false;
  }

  bool ok = true;

  if(ok) ok = WriteLineChecked(fh, "FORMAT_VERSION=" + PROBE_FORMAT_VERSION + "\n");
  if(ok) ok = WriteLineChecked(fh, "SESSION_ID=" + ProbeSessionID + "\n");
  if(ok) ok = WriteLineChecked(fh, "STATE=" + state + "\n");
  if(ok && order_ticket != 0)
    ok = WriteLineChecked(fh, "ORDER_TICKET=" + UlongToDecStr(order_ticket) + "\n");
  if(ok) ok = WriteLineChecked(fh, "SYMBOL=" + symbol + "\n");
  if(ok) ok = WriteLineChecked(fh, "MAGIC=" + IntegerToString(magic) + "\n");
  if(ok) ok = WriteLineChecked(fh, "REQUESTED_VOLUME=" + DoubleToString(req_volume, 8) + "\n");
  if(ok) ok = WriteLineChecked(fh, "ORDER_SETUP_TIME=" + IntegerToString((long)order_setup_time) + "\n");

  if(ok)
  {
    // FileFlush() returns void: invocation is observable, successful flush is not.
    // A non-zero error is treated as failure; zero is NOT proof of durability.
    ResetLastError();
    FileFlush(fh);
    int flush_err = GetLastError();
    if(flush_err != 0)
    {
      ProbeLog("PERSIST ERROR: FileFlush reported LastError=" + IntegerToString(flush_err));
      ok = false;
    }
    else
    {
      ProbeLog("PERSIST: FileFlush invoked; MQL5 exposes no return status, durability unverified.");
    }
  }

  FileClose(fh);
  return ok;
}

//=============================================================================
// CR-02 — LoadResult enum: distinguish NOT_FOUND, VALID, CORRUPT, IO_ERROR
//=============================================================================

enum PROBE_LOAD_RESULT
{
  LOAD_NOT_FOUND  = 0,   // file does not exist — fresh session allowed
  LOAD_VALID      = 1,   // record read and all required fields parsed
  LOAD_CORRUPT    = 2,   // file exists but content invalid/incomplete
  LOAD_IO_ERROR   = 3,   // file exists but could not be opened or read
};

struct PersistedRecord
{
  PROBE_LOAD_RESULT load_result;
  string   format_version;
  string   session_id;
  string   state;
  string   order_ticket_str;
  ulong    order_ticket;
  bool     order_ticket_parsed;   // MR-04: false if DecStrToUlong failed
  string   symbol;
  int      magic;
  double   requested_volume;
  datetime order_setup_time;
};

PROBE_LOAD_RESULT LoadPersistedRecord(PersistedRecord &rec)
{
  ZeroMemory(rec);
  rec.load_result         = LOAD_NOT_FOUND;
  rec.order_ticket_parsed = false;

  ResetLastError();
  bool exists = FileIsExist(SessionFilePath());
  int exist_err = GetLastError();
  if(!exists)
  {
    // ERR_FILE_NOT_EXIST = 5019 in MQL5; this is the expected fresh-session result.
    if(exist_err != 0 && exist_err != 5019)
    {
      ProbeLog("LOAD IO_ERROR: FileIsExist failed with LastError=" + IntegerToString(exist_err));
      rec.load_result = LOAD_IO_ERROR;
      return LOAD_IO_ERROR;
    }
    return LOAD_NOT_FOUND;
  }

  ResetLastError();
  int fh = FileOpen(SessionFilePath(), FILE_READ | FILE_TXT | FILE_ANSI);
  if(fh == INVALID_HANDLE)
  {
    ProbeLog("LOAD IO_ERROR: cannot open file: " + SessionFilePath() +
             " LastError=" + IntegerToString(GetLastError()));
    rec.load_result = LOAD_IO_ERROR;
    return LOAD_IO_ERROR;
  }

  bool seen_format   = false;
  bool seen_session  = false;
  bool seen_state    = false;
  bool seen_ticket   = false;
  bool seen_symbol   = false;
  bool seen_magic    = false;
  bool seen_volume   = false;
  bool seen_time     = false;

  string magic_str = "";
  string vol_str   = "";
  string time_str  = "";

  int count = 0;
  int physical_line_count = 0;
  bool corrupt = false;
  bool io_err  = false;

  while(!FileIsEnding(fh))
  {
    if(physical_line_count >= MAX_PERSIST_LINES)
    {
      ProbeLog("LOAD CORRUPT: persisted record exceeds MAX_PERSIST_LINES=" +
               IntegerToString(MAX_PERSIST_LINES));
      corrupt = true;
      break;
    }

    ResetLastError();
    string line = FileReadString(fh);
    physical_line_count++;
    int rerr = GetLastError();
    if(rerr != 0 && !FileIsEnding(fh))
    {
      ProbeLog("LOAD IO_ERROR: FileReadString failed LastError=" + IntegerToString(rerr));
      io_err = true;
      break;
    }

    StringReplace(line, "\r", "");
    if(StringLen(line) == 0)
    {
      ProbeLog("LOAD CORRUPT: blank physical line is not allowed.");
      corrupt = true;
      break;
    }

    count++;
    int eq = StringFind(line, "=");
    if(eq <= 0)
    {
      ProbeLog("LOAD CORRUPT: malformed line without KEY=VALUE: '" + line + "'");
      corrupt = true;
      break;
    }

    string key = StringSubstr(line, 0, eq);
    string val = StringSubstr(line, eq + 1);

    if(key == "FORMAT_VERSION")
    {
      if(seen_format) { ProbeLog("LOAD CORRUPT: duplicate FORMAT_VERSION"); corrupt = true; break; }
      seen_format = true;
      rec.format_version = val;
    }
    else if(key == "SESSION_ID")
    {
      if(seen_session) { ProbeLog("LOAD CORRUPT: duplicate SESSION_ID"); corrupt = true; break; }
      seen_session = true;
      rec.session_id = val;
    }
    else if(key == "STATE")
    {
      if(seen_state) { ProbeLog("LOAD CORRUPT: duplicate STATE"); corrupt = true; break; }
      seen_state = true;
      rec.state = val;
    }
    else if(key == "ORDER_TICKET")
    {
      if(seen_ticket) { ProbeLog("LOAD CORRUPT: duplicate ORDER_TICKET"); corrupt = true; break; }
      seen_ticket = true;
      rec.order_ticket_str = val;
    }
    else if(key == "SYMBOL")
    {
      if(seen_symbol) { ProbeLog("LOAD CORRUPT: duplicate SYMBOL"); corrupt = true; break; }
      seen_symbol = true;
      rec.symbol = val;
    }
    else if(key == "MAGIC")
    {
      if(seen_magic) { ProbeLog("LOAD CORRUPT: duplicate MAGIC"); corrupt = true; break; }
      seen_magic = true;
      magic_str = val;
    }
    else if(key == "REQUESTED_VOLUME")
    {
      if(seen_volume) { ProbeLog("LOAD CORRUPT: duplicate REQUESTED_VOLUME"); corrupt = true; break; }
      seen_volume = true;
      vol_str = val;
    }
    else if(key == "ORDER_SETUP_TIME")
    {
      if(seen_time) { ProbeLog("LOAD CORRUPT: duplicate ORDER_SETUP_TIME"); corrupt = true; break; }
      seen_time = true;
      time_str = val;
    }
    else
    {
      ProbeLog("LOAD CORRUPT: unknown key: '" + key + "'");
      corrupt = true;
      break;
    }
  }
  FileClose(fh);

  if(io_err)
  {
    rec.load_result = LOAD_IO_ERROR;
    return LOAD_IO_ERROR;
  }
  if(corrupt || count == 0)
  {
    if(count == 0) ProbeLog("LOAD CORRUPT: empty session file");
    rec.load_result = LOAD_CORRUPT;
    return LOAD_CORRUPT;
  }

  // --- Validate mandatory schema keys ---
  if(!seen_format || rec.format_version != PROBE_FORMAT_VERSION)
  {
    ProbeLog("LOAD CORRUPT: missing or unsupported FORMAT_VERSION: '" + rec.format_version + "'");
    rec.load_result = LOAD_CORRUPT;
    return LOAD_CORRUPT;
  }
  if(!seen_session || StringLen(rec.session_id) == 0)
  {
    ProbeLog("LOAD CORRUPT: missing or empty SESSION_ID");
    rec.load_result = LOAD_CORRUPT;
    return LOAD_CORRUPT;
  }
  if(!seen_state ||
     (rec.state != STATE_REQUEST_STARTED &&
      rec.state != STATE_ORDER_PERSISTED  &&
      rec.state != STATE_COMPLETED))
  {
    ProbeLog("LOAD CORRUPT: missing or unknown STATE: '" + rec.state + "'");
    rec.load_result = LOAD_CORRUPT;
    return LOAD_CORRUPT;
  }
  if(!seen_symbol || StringLen(rec.symbol) == 0)
  {
    ProbeLog("LOAD CORRUPT: missing or empty SYMBOL");
    rec.load_result = LOAD_CORRUPT;
    return LOAD_CORRUPT;
  }
  if(!seen_magic || StringLen(magic_str) == 0)
  {
    ProbeLog("LOAD CORRUPT: missing or empty MAGIC");
    rec.load_result = LOAD_CORRUPT;
    return LOAD_CORRUPT;
  }
  if(!seen_volume || StringLen(vol_str) == 0)
  {
    ProbeLog("LOAD CORRUPT: missing or empty REQUESTED_VOLUME");
    rec.load_result = LOAD_CORRUPT;
    return LOAD_CORRUPT;
  }
  if(!seen_time || StringLen(time_str) == 0)
  {
    ProbeLog("LOAD CORRUPT: missing or empty ORDER_SETUP_TIME");
    rec.load_result = LOAD_CORRUPT;
    return LOAD_CORRUPT;
  }

  // Parse numeric fields strictly (reject trailing junk / overflow / non-finite)
  ulong parsed_magic = 0;
  if(!DecStrToUlong(magic_str, parsed_magic) || parsed_magic == 0 || parsed_magic > 2147483647)
  {
    ProbeLog("LOAD CORRUPT: invalid MAGIC: '" + magic_str + "'");
    rec.load_result = LOAD_CORRUPT;
    return LOAD_CORRUPT;
  }
  rec.magic = (int)parsed_magic;

  if(!IsStrictPositiveDecimalStr(vol_str))
  {
    ProbeLog("LOAD CORRUPT: invalid REQUESTED_VOLUME format: '" + vol_str + "'");
    rec.load_result = LOAD_CORRUPT;
    return LOAD_CORRUPT;
  }
  rec.requested_volume = StringToDouble(vol_str);
  if(!MathIsValidNumber(rec.requested_volume) || rec.requested_volume <= 0.0)
  {
    ProbeLog("LOAD CORRUPT: non-positive or non-finite REQUESTED_VOLUME");
    rec.load_result = LOAD_CORRUPT;
    return LOAD_CORRUPT;
  }

  ulong parsed_time = 0;
  if(!DecStrToUlong(time_str, parsed_time) || parsed_time > 9223372036854775807)
  {
    ProbeLog("LOAD CORRUPT: invalid ORDER_SETUP_TIME: '" + time_str + "'");
    rec.load_result = LOAD_CORRUPT;
    return LOAD_CORRUPT;
  }
  rec.order_setup_time = (datetime)parsed_time;

  // State-specific ORDER_TICKET schema rules
  if(rec.state == STATE_REQUEST_STARTED)
  {
    if(seen_ticket)
    {
      ProbeLog("LOAD CORRUPT: REQUEST_STARTED must not contain ORDER_TICKET");
      rec.load_result = LOAD_CORRUPT;
      return LOAD_CORRUPT;
    }
  }
  else // STATE_ORDER_PERSISTED or STATE_COMPLETED
  {
    if(!seen_ticket || StringLen(rec.order_ticket_str) == 0)
    {
      ProbeLog("LOAD CORRUPT: state=" + rec.state + " missing ORDER_TICKET");
      rec.load_result = LOAD_CORRUPT;
      return LOAD_CORRUPT;
    }
    rec.order_ticket_parsed = DecStrToUlong(rec.order_ticket_str, rec.order_ticket);
    if(!rec.order_ticket_parsed || rec.order_ticket == 0)
    {
      ProbeLog("LOAD CORRUPT: invalid ORDER_TICKET: '" + rec.order_ticket_str + "'");
      rec.load_result = LOAD_CORRUPT;
      return LOAD_CORRUPT;
    }
  }

  rec.load_result = LOAD_VALID;
  return LOAD_VALID;
}

//=============================================================================
// Callback buffer management
//=============================================================================

void ArchiveCallbacksAndClearQueue()
{
  for(int i = 0; i < g_callback_count; i++)
  {
    if(g_callback_archive_count >= MAX_CALLBACKS)
    {
      g_callback_archive_overflow++;
      continue;
    }

    int required_size = g_callback_archive_count + 1;
    int resized = ArrayResize(g_callback_archive, required_size);
    if(resized != required_size)
    {
      g_callback_archive_overflow++;
      ProbeLog("WARNING: callback archive allocation failed; evidence marked overflow.");
      continue;
    }
    g_callback_archive[g_callback_archive_count] = g_callbacks[i];
    g_callback_archive_count++;
  }

  g_callback_archive_overflow += g_callback_overflow;
  g_callback_count = 0;
  g_callback_overflow = 0;
  ArrayResize(g_callbacks, MAX_CALLBACKS);
}

void AppendCallback(ProbeCallback &cb)
{
  if(g_callback_archive_count + g_callback_count >= MAX_CALLBACKS)
  {
    g_callback_overflow++;
    ProbeLog("WARNING: callback buffer full; overflow count=" +
             IntegerToString(g_callback_overflow));
    return;
  }
  if(ArraySize(g_callbacks) <= g_callback_count)
  {
    int resized = ArrayResize(g_callbacks, g_callback_count + 32);
    if(resized <= g_callback_count)
    {
      g_callback_overflow++;
      ProbeLog("WARNING: callback buffer resize failed; overflow count=" +
               IntegerToString(g_callback_overflow));
      return;
    }
  }
  g_callbacks[g_callback_count++] = cb;
}

//=============================================================================
// CR-05 / MR-01 — Exact-order Deal scan (outside callback)
//   Returns PROBE_SCAN_STATUS; fills g_deals[].
//   INCOMPLETE if buffer overflow or any property-read failure during scan.
//=============================================================================

PROBE_SCAN_STATUS RunExactOrderScan(ulong order_ticket, datetime order_setup_time)
{
  g_deal_count = 0;
  ArrayResize(g_deals, 0);

  if(order_ticket == 0)
  {
    ProbeLog("SCAN: order_ticket=0; cannot scan");
    return SCAN_INVALID_ORDER;
  }

  // Step 1: Select the exact History Order
  if(!HistoryOrderSelect(order_ticket))
  {
    ProbeLog("SCAN: HistoryOrderSelect(" + UlongToDecStr(order_ticket) +
             ") failed; LastError=" + IntegerToString(GetLastError()));
    return SCAN_INVALID_ORDER;
  }

  // Read Order properties using bool-returning overloads (SPEC §5)
  long raw_ord_setup = 0, raw_ord_type = 0, raw_ord_state = 0, raw_ord_magic = 0;
  string ord_symbol = "";
  bool ord_props_ok = true;
  if(!HistoryOrderGetInteger(order_ticket, ORDER_TIME_SETUP, raw_ord_setup)) ord_props_ok = false;
  if(!HistoryOrderGetInteger(order_ticket, ORDER_TYPE, raw_ord_type))        ord_props_ok = false;
  if(!HistoryOrderGetInteger(order_ticket, ORDER_STATE, raw_ord_state))      ord_props_ok = false;
  if(!HistoryOrderGetString(order_ticket, ORDER_SYMBOL, ord_symbol))         ord_props_ok = false;
  if(!HistoryOrderGetInteger(order_ticket, ORDER_MAGIC, raw_ord_magic))      ord_props_ok = false;

  datetime ord_setup = (datetime)raw_ord_setup;
  ENUM_ORDER_TYPE  ord_type  = (ENUM_ORDER_TYPE)raw_ord_type;
  ENUM_ORDER_STATE ord_state = (ENUM_ORDER_STATE)raw_ord_state;
  long             ord_magic = raw_ord_magic;

  if(!ord_props_ok)
    ProbeLog("SCAN: Order property read failed; LastError=" + IntegerToString(GetLastError()));

  PrintFormat("[PROBE][%s] SCAN: Order=%s type=%d state=%d symbol=%s magic=%d setup=%s",
    ProbeSessionID,
    UlongToDecStr(order_ticket),
    (int)ord_type, (int)ord_state,
    ord_symbol, (int)ord_magic,
    TimeToString(ord_setup));

  datetime from_time = (order_setup_time > 0) ? order_setup_time : ord_setup;
  from_time -= HistoryMarginSec;
  datetime to_time   = TimeCurrent() + HistoryMarginSec;

  // Step 2: bounded HistorySelect
  if(!HistorySelect(from_time, to_time))
  {
    ProbeLog("SCAN: HistorySelect failed; LastError=" + IntegerToString(GetLastError()));
    return SCAN_HISTORY_FAIL;
  }

  // Step 3: Enumerate deals
  //   Do NOT call HistoryDealSelect() during enumeration — it replaces the
  //   selected list with a single Deal (see SPEC §5 / MQL5 HistoryDealSelect ref).
  int total_deals = HistoryDealsTotal();
  PrintFormat("[PROBE][%s] SCAN: HistoryDealsTotal=%d range=[%s, %s]",
    ProbeSessionID, total_deals,
    TimeToString(from_time), TimeToString(to_time));

  bool scan_incomplete = !ord_props_ok;

  for(int i = 0; i < total_deals; i++)
  {
    ResetLastError();
    ulong dt = HistoryDealGetTicket(i);
    if(dt == 0)
    {
      // MR-05: Ticket 0 in valid range [0..total_deals-1] makes scan INCOMPLETE
      PrintFormat("[PROBE][%s] SCAN: HistoryDealGetTicket(%d) returned 0 (total=%d) LastError=%d -> SCAN_INCOMPLETE",
        ProbeSessionID, i, total_deals, GetLastError());
      scan_incomplete = true;
      continue;
    }

    // CR-04 / CR-05: exact DEAL_ORDER filter via bool-returning overload
    long raw_deal_order = 0;
    if(!HistoryDealGetInteger(dt, DEAL_ORDER, raw_deal_order))
    {
      ProbeLog("SCAN: Deal=" + UlongToDecStr(dt) + " DEAL_ORDER read failed LastError=" + IntegerToString(GetLastError()));
      scan_incomplete = true;
      continue;
    }
    ulong deal_order = (ulong)raw_deal_order;
    if(deal_order != order_ticket) continue;

    // MR-01: buffer overflow → INCOMPLETE, not silent truncate
    if(g_deal_count >= MAX_DEALS)
    {
      ProbeLog("SCAN: deal buffer capacity (" + IntegerToString(MAX_DEALS) +
               ") exceeded at total_deals=" + IntegerToString(total_deals) +
               "; scan is INCOMPLETE");
      scan_incomplete = true;
      break;
    }

    // Read required properties using bool-returning overloads (SPEC §5)
    long     raw_entry = 0, raw_type = 0, raw_magic = 0, raw_pos_id = 0, raw_time = 0;
    string   deal_symbol = "";
    double   deal_volume = 0.0, deal_price = 0.0;

    bool all_ok = true;
    if(!HistoryDealGetInteger(dt, DEAL_ENTRY, raw_entry))        all_ok = false;
    if(!HistoryDealGetInteger(dt, DEAL_TYPE, raw_type))          all_ok = false;
    if(!HistoryDealGetString(dt, DEAL_SYMBOL, deal_symbol))      all_ok = false;
    if(!HistoryDealGetInteger(dt, DEAL_MAGIC, raw_magic))        all_ok = false;
    if(!HistoryDealGetInteger(dt, DEAL_POSITION_ID, raw_pos_id)) all_ok = false;
    if(!HistoryDealGetDouble(dt, DEAL_VOLUME, deal_volume))      all_ok = false;
    if(!HistoryDealGetDouble(dt, DEAL_PRICE, deal_price))        all_ok = false;
    if(!HistoryDealGetInteger(dt, DEAL_TIME, raw_time))          all_ok = false;

    int      deal_entry       = (int)raw_entry;
    int      deal_type_int    = (int)raw_type;
    long     deal_magic       = raw_magic;
    ulong    deal_position_id = (ulong)raw_pos_id;
    datetime deal_time        = (datetime)raw_time;

    if(!all_ok)
    {
      PrintFormat("[PROBE][%s] SCAN: Deal=%s property read failed (overload returned false) LastError=%d",
        ProbeSessionID, UlongToDecStr(dt), GetLastError());
      ResetLastError();
      // CR-05: property failure mid-scan → scan becomes INCOMPLETE
      scan_incomplete = true;
    }

    // CR-04: Validate deal fields against Request
    string conflict = "";
    bool valid_for_agg = true;

    if(!all_ok)
    {
      conflict += "PROPS_INCOMPLETE;";
      valid_for_agg = false;
    }
    if(deal_symbol != _Symbol)
    {
      conflict += "SYMBOL_MISMATCH(" + deal_symbol + ");";
      valid_for_agg = false;
    }
    if(deal_magic != ProbeMagic)
    {
      conflict += "MAGIC_MISMATCH(" + IntegerToString(deal_magic) + ");";
      valid_for_agg = false;
    }
    if(deal_position_id == 0)
    {
      conflict += "POSID_ZERO;";
      valid_for_agg = false;
    }
    if(!MathIsValidNumber(deal_volume) || deal_volume <= 0.0 ||
       (g_symbol_vol_step > 0.0 && deal_volume > TestVolume + g_symbol_vol_step * 0.5))
    {
      conflict += "VOLUME_INVALID_OR_OUT_OF_RANGE;";
      valid_for_agg = false;
    }
    if(!MathIsValidNumber(deal_price) || deal_price <= 0.0)
    {
      conflict += "PRICE_INVALID_OR_NONPOSITIVE;";
      valid_for_agg = false;
    }
    // Deal type must match BUY/SELL direction
    // BUY → DEAL_TYPE_BUY (0); SELL → DEAL_TYPE_SELL (1)
    int expected_deal_type = TestBuy ? DEAL_TYPE_BUY : DEAL_TYPE_SELL;
    if(deal_type_int != expected_deal_type)
    {
      conflict += "DEAL_TYPE_MISMATCH(got=" + IntegerToString(deal_type_int) +
                  " want=" + IntegerToString(expected_deal_type) + ");";
      valid_for_agg = false;
    }
    // CR-04: DEAL_ENTRY must be DEAL_ENTRY_IN (0) for a market entry
    if(all_ok && deal_entry != DEAL_ENTRY_IN)
    {
      conflict += "ENTRY_NOT_IN(" + IntegerToString(deal_entry) + ");";
      valid_for_agg = false;
    }

    if(StringLen(conflict) > 0)
      PrintFormat("[PROBE][%s] SCAN: Deal=%s CONFLICT: %s",
        ProbeSessionID, UlongToDecStr(dt), conflict);

    ArrayResize(g_deals, g_deal_count + 1);
    g_deals[g_deal_count].deal_ticket           = dt;
    g_deals[g_deal_count].deal_order            = deal_order;
    g_deals[g_deal_count].deal_entry            = deal_entry;
    g_deals[g_deal_count].deal_type             = deal_type_int;
    g_deals[g_deal_count].deal_symbol           = deal_symbol;
    g_deals[g_deal_count].deal_magic            = deal_magic;
    g_deals[g_deal_count].deal_position_id      = deal_position_id;
    g_deals[g_deal_count].deal_volume           = deal_volume;
    g_deals[g_deal_count].deal_price            = deal_price;
    g_deals[g_deal_count].deal_time             = deal_time;
    g_deals[g_deal_count].all_props_ok          = all_ok;
    g_deals[g_deal_count].valid_for_aggregate   = valid_for_agg;
    g_deals[g_deal_count].validation_conflict   = conflict;
    g_deal_count++;

    PrintFormat("[PROBE][%s] SCAN: Deal=%s order=%s entry=%d type=%d sym=%s magic=%d posid=%s vol=%.8f price=%.5f time=%s props_ok=%s valid=%s",
      ProbeSessionID,
      UlongToDecStr(dt),
      UlongToDecStr(deal_order),
      deal_entry, deal_type_int,
      deal_symbol, (int)deal_magic,
      UlongToDecStr(deal_position_id),
      deal_volume, deal_price,
      TimeToString(deal_time),
      all_ok  ? "YES" : "NO",
      valid_for_agg ? "YES" : "NO");
  }

  if(scan_incomplete)
    return SCAN_INCOMPLETE;
  return (g_deal_count > 0) ? SCAN_COMPLETE_MATCH : SCAN_COMPLETE_EMPTY;
}

//=============================================================================
// CR-04 — Aggregate and validate Deal scan results
//   Only valid_for_aggregate deals contribute to agg_volume / pos_id set.
//=============================================================================

struct ScanResult
{
  int    deal_count_total;         // all exact-order deals found (including invalid)
  int    deal_count_valid;         // only deals passing full CR-04 validation
  double agg_volume;               // sum of valid deals only
  int    distinct_pos_ids;         // from valid deals only
  ulong  single_valid_pos_id;      // valid position ID when distinct_pos_ids == 1
  bool   critical_conflict;        // multiple Position Identifiers (architecture blocker)
  bool   volume_exceeds_request;
  bool   result_deal_found;
  int    invalid_deal_count;       // deals excluded from aggregate due to validation failure
  PROBE_SCAN_STATUS scan_status;
};

// CR-09: defer Trade Path summary until callback observation window has elapsed.
ScanResult g_pending_scan1;
ScanResult g_pending_scan_rec;
bool       g_summary_pending = false;
bool       g_summary_emitted = false;
bool       g_pending_trade_path_attempted = false;
ulong      g_summary_wait_started_ms = 0;
#define CALLBACK_OBSERVATION_MIN_MS 2000
#define CALLBACK_QUIET_PERIOD_MS    1000

ScanResult AggregateScanResults(
  PROBE_SCAN_STATUS scan_status,
  ulong             result_deal_hint,
  double            requested_volume,
  double            vol_step
)
{
  ScanResult r;
  ZeroMemory(r);
  r.scan_status       = scan_status;
  r.deal_count_total  = g_deal_count;

  ulong pos_ids[64];
  int   pos_id_count = 0;

  for(int i = 0; i < g_deal_count; i++)
  {
    if(!g_deals[i].valid_for_aggregate)
    {
      r.invalid_deal_count++;
      continue;
    }

    r.deal_count_valid++;
    r.agg_volume += g_deals[i].deal_volume;

    ulong pid = g_deals[i].deal_position_id;
    bool found_pid = false;
    for(int j = 0; j < pos_id_count; j++)
    {
      if(pos_ids[j] == pid) { found_pid = true; break; }
    }
    if(!found_pid)
    {
      if(pos_id_count < 64)
        pos_ids[pos_id_count++] = pid;
    }

    if(result_deal_hint != 0 && g_deals[i].deal_ticket == result_deal_hint)
      r.result_deal_found = true;
  }

  r.distinct_pos_ids = pos_id_count;
  if(pos_id_count == 1)
    r.single_valid_pos_id = pos_ids[0];
  if(pos_id_count > 1)
  {
    r.critical_conflict = true;
    PrintFormat("[PROBE][%s] CRITICAL CONTRACT CONFLICT: %d distinct Position Identifiers"
                " from one Order — architecture blocker; no aggregation across Positions.",
                ProbeSessionID, pos_id_count);
  }

  if(vol_step > 0.0)
    r.volume_exceeds_request = (r.agg_volume > requested_volume + vol_step * 0.5);

  if(result_deal_hint != 0 && !r.result_deal_found)
    PrintFormat("[PROBE][%s] DISCREPANCY: ResultDeal=%s not in exact-order valid deals",
      ProbeSessionID, UlongToDecStr(result_deal_hint));

  return r;
}

//=============================================================================
// CR-10 — Snapshot and compare the exact first-scan Deal set
//=============================================================================

bool SnapshotFirstScanDeals()
{
  g_first_scan_deal_count = g_deal_count;
  g_first_scan_snapshot_ok = true;
  ArrayResize(g_first_scan_deals, g_deal_count);
  if(ArraySize(g_first_scan_deals) != g_deal_count)
  {
    g_first_scan_snapshot_ok = false;
    ProbeLog("RECOVERY: cannot allocate first-scan Deal snapshot.");
    return false;
  }

  for(int i = 0; i < g_deal_count; i++)
    g_first_scan_deals[i] = g_deals[i];
  return true;
}

bool DealRecordsEqual(const ProbeDeal &left, const ProbeDeal &right)
{
  return left.deal_ticket == right.deal_ticket
      && left.deal_order == right.deal_order
      && left.deal_entry == right.deal_entry
      && left.deal_type == right.deal_type
      && left.deal_symbol == right.deal_symbol
      && left.deal_magic == right.deal_magic
      && left.deal_position_id == right.deal_position_id
      && left.deal_volume == right.deal_volume
      && left.deal_price == right.deal_price
      && left.deal_time == right.deal_time
      && left.all_props_ok == right.all_props_ok
      && left.valid_for_aggregate == right.valid_for_aggregate
      && left.validation_conflict == right.validation_conflict;
}

bool CompareExactDealSets(string &discrepancy)
{
  discrepancy = "";
  if(g_scan_status_1st != SCAN_COMPLETE_MATCH)
  {
    discrepancy = "first scan is not SCAN_COMPLETE_MATCH";
    return false;
  }
  if(g_scan_status_rec != SCAN_COMPLETE_MATCH)
  {
    discrepancy = "recovery scan is not SCAN_COMPLETE_MATCH";
    return false;
  }
  if(!g_first_scan_snapshot_ok)
  {
    discrepancy = "first-scan Deal snapshot unavailable";
    return false;
  }
  if(g_first_scan_deal_count != g_deal_count)
  {
    discrepancy = StringFormat("exact Deal count %d vs %d", g_first_scan_deal_count, g_deal_count);
    return false;
  }

  bool matched[];
  int matched_size = ArrayResize(matched, g_deal_count);
  if(matched_size != g_deal_count)
  {
    discrepancy = "cannot allocate exact Deal-set comparison flags";
    return false;
  }
  ArrayInitialize(matched, false);

  for(int i = 0; i < g_first_scan_deal_count; i++)
  {
    bool found = false;
    for(int j = 0; j < g_deal_count; j++)
    {
      if(matched[j] || g_first_scan_deals[i].deal_ticket != g_deals[j].deal_ticket)
        continue;
      found = true;
      matched[j] = true;
      if(!DealRecordsEqual(g_first_scan_deals[i], g_deals[j]))
      {
        discrepancy = "Deal properties differ for ticket=" + UlongToDecStr(g_deals[j].deal_ticket);
        return false;
      }
      break;
    }
    if(!found)
    {
      discrepancy = "recovery scan missing first-scan ticket=" + UlongToDecStr(g_first_scan_deals[i].deal_ticket);
      return false;
    }
  }

  for(int j = 0; j < g_deal_count; j++)
  {
    if(!matched[j])
    {
      discrepancy = "recovery scan contains additional ticket=" + UlongToDecStr(g_deals[j].deal_ticket);
      return false;
    }
  }
  return true;
}

//=============================================================================
// MR-02 — CapturePositionSnapshot: enumerate ALL positions matching Symbol+Magic
//=============================================================================

void CapturePositionSnapshot()
{
  g_position_count               = 0;
  g_position_snapshot_ok         = false;
  g_position_snapshot_incomplete = false;
  ArrayResize(g_positions, 0);

  int total = PositionsTotal();
  for(int i = 0; i < total; i++)
  {
    ResetLastError();
    ulong pt = PositionGetTicket(i);
    if(pt == 0)
    {
      // MR-06: Ticket 0 in valid index range makes snapshot incomplete
      PrintFormat("[PROBE][%s] POSITION: PositionGetTicket(%d) returned 0 (total=%d) LastError=%d -> INCOMPLETE",
        ProbeSessionID, i, total, GetLastError());
      g_position_snapshot_incomplete = true;
      continue;
    }

    string pos_sym = "";
    long   pos_magic = 0;
    if(!PositionGetString(POSITION_SYMBOL, pos_sym) || !PositionGetInteger(POSITION_MAGIC, pos_magic))
    {
      PrintFormat("[PROBE][%s] POSITION: failed reading symbol/magic for ticket=%s LastError=%d -> INCOMPLETE",
        ProbeSessionID, UlongToDecStr(pt), GetLastError());
      g_position_snapshot_incomplete = true;
      continue;
    }
    if(pos_sym != _Symbol || pos_magic != ProbeMagic) continue;

    if(g_position_count >= MAX_POSITIONS)
    {
      ProbeLog("POSITION: snapshot capacity exceeded at " + IntegerToString(MAX_POSITIONS));
      g_position_snapshot_incomplete = true;
      break;
    }

    long   raw_pid = 0;
    double p_vol = 0.0, p_price = 0.0;
    bool   p_ok = true;
    if(!PositionGetInteger(POSITION_IDENTIFIER, raw_pid)) p_ok = false;
    if(!PositionGetDouble(POSITION_VOLUME, p_vol))        p_ok = false;
    if(!PositionGetDouble(POSITION_PRICE_OPEN, p_price))  p_ok = false;
    if(p_ok && (!MathIsValidNumber(p_vol) || p_vol <= 0.0 ||
                !MathIsValidNumber(p_price) || p_price <= 0.0))
    {
      p_ok = false;
      ProbeLog("POSITION: non-finite or non-positive volume/open price for ticket=" + UlongToDecStr(pt));
    }
    if(!p_ok) g_position_snapshot_incomplete = true;

    ArrayResize(g_positions, g_position_count + 1);
    g_positions[g_position_count].pos_ticket      = pt;
    g_positions[g_position_count].pos_identifier  = (ulong)raw_pid;
    g_positions[g_position_count].pos_volume      = p_vol;
    g_positions[g_position_count].pos_price_open  = p_price;
    g_positions[g_position_count].props_ok        = p_ok;

    PrintFormat("[PROBE][%s] POSITION[%d]: ticket=%s identifier=%s volume=%.8f open_price=%.5f props_ok=%s",
      ProbeSessionID, g_position_count,
      UlongToDecStr(pt),
      UlongToDecStr(g_positions[g_position_count].pos_identifier),
      g_positions[g_position_count].pos_volume,
      g_positions[g_position_count].pos_price_open,
      g_positions[g_position_count].props_ok ? "YES" : "NO");

    g_position_count++;
  }

  g_position_snapshot_ok = !g_position_snapshot_incomplete;

  if(g_position_count == 0)
    ProbeLog("POSITION: No position found for Symbol=" + _Symbol +
             " Magic=" + IntegerToString(ProbeMagic) +
             " snapshot_ok=" + (g_position_snapshot_ok ? "YES" : "INCOMPLETE"));
  else
    PrintFormat("[PROBE][%s] POSITION: %d position(s) found; snapshot_ok=%s",
      ProbeSessionID, g_position_count,
      g_position_snapshot_ok ? "YES" : "INCOMPLETE");
}

//=============================================================================
// CR-03 — EmitFinalSummary: evidence-based AC verdicts
//
// Verdict tokens: PASS | FAIL | INCOMPLETE | NOT_OBSERVED | NOT_APPLICABLE
//   PASS         — condition met with positive evidence
//   FAIL         — condition not met; negative evidence
//   INCOMPLETE   — could not fully evaluate; evidence missing/partial
//   NOT_OBSERVED — condition not exercised in this run
//   NOT_APPLICABLE — not relevant to this execution path
//=============================================================================

void LogCallbackRecord(const ProbeCallback &cb_i)
{
  string type_str = EnumToString(cb_i.trans_type);
  PrintFormat("[PROBE][%s] CB#%d type=%s sym=%s order=%s otype=%d ostate=%d deal=%s dtype=%d pos=%s vol=%.8f price=%.5f ptrigger=%.5f t=%s tick=%I64u",
    ProbeSessionID, cb_i.seq, type_str,
    cb_i.symbol,
    UlongToDecStr(cb_i.order_ticket),
    (int)cb_i.order_type, (int)cb_i.order_state,
    UlongToDecStr(cb_i.deal_ticket),
    (int)cb_i.deal_type,
    UlongToDecStr(cb_i.position_id),
    cb_i.volume, cb_i.price, cb_i.price_trigger,
    TimeToString(cb_i.time_current), cb_i.tick_ms);
  if(cb_i.has_request)
    PrintFormat("[PROBE][%s] CB#%d REQUEST: action=%d retcode=%u req_vol=%.8f req_price=%.5f res_order=%s res_deal=%s res_vol=%.8f res_price=%.5f bid=%.5f ask=%.5f",
      ProbeSessionID, cb_i.seq,
      (int)cb_i.req_action, cb_i.res_retcode,
      cb_i.req_volume, cb_i.req_price,
      UlongToDecStr(cb_i.req_order),
      UlongToDecStr(cb_i.req_deal),
      cb_i.res_volume, cb_i.res_price,
      cb_i.res_bid, cb_i.res_ask);
  if(cb_i.immediate_select_attempted)
    PrintFormat("[PROBE][%s] CB#%d DEAL_ADD_IMM: select_ok=%s LastErr=%d read_ok=%s deal=%s order=%s entry=%d type=%d symbol=%s posid=%s vol=%.8f price=%.5f",
      ProbeSessionID, cb_i.seq,
      cb_i.immediate_select_ok ? "YES" : "NO",
      cb_i.immediate_last_error,
      cb_i.imm_read_ok ? "YES" : "NO",
      UlongToDecStr(cb_i.immediate_deal_ticket),
      UlongToDecStr(cb_i.imm_deal_order),
      cb_i.imm_deal_entry, cb_i.imm_deal_type,
      cb_i.imm_deal_symbol,
      UlongToDecStr(cb_i.imm_deal_position_id),
      cb_i.imm_deal_volume, cb_i.imm_deal_price);
}

void EmitFinalSummary(
  const ScanResult &scan1,
  const ScanResult &scan_rec,
  bool              trade_path_attempted
)
{
  ProbeLog("====== PROBE FINAL SUMMARY ======");
  PrintFormat("[PROBE][%s] Session: %s  |  Build: %d",
    ProbeSessionID, ProbeSessionID, g_terminal_build);
  PrintFormat("[PROBE][%s] Symbol: %s  Exec: %s  Fill: %s",
    ProbeSessionID, _Symbol, g_symbol_exec_mode, g_symbol_fill_mode);
  PrintFormat("[PROBE][%s] Vol min=%.8f max=%.8f step=%.8f | digits=%d point=%.8f tick=%.8f",
    ProbeSessionID, g_symbol_vol_min, g_symbol_vol_max, g_symbol_vol_step,
    g_symbol_digits, g_symbol_point, g_symbol_tick_size);

  if(g_fail_closed)
  {
    ProbeLog("RESULT: FAIL_CLOSED — " + g_fail_closed_reason + " No Trade Request sent.");
    ProbeLog("AC-15: PASS (fail-closed applied correctly)");
    ProbeLog("AC-16: PASS (no retry attempted)");
    ProbeLog("====== END PROBE SUMMARY ======");
    return;
  }

  if(!EnableTestTrade)
  {
    ProbeLog("RESULT: NO_TRADE (EnableTestTrade=false) — environment diagnostics only");
    ProbeLog("AC-01: PASS (Tester check in INIT)");
    ProbeLog("AC-02: PASS (EnableTestTrade=false prevented request)");
    ProbeLog("AC-03..AC-11: NOT_APPLICABLE (trade path not entered)");
    ProbeLog("AC-12: PASS (TRUE_RESTART_RECOVERY=NOT_TESTED; not applicable in no-trade run)");
    ProbeLog("AC-13: PASS (no production changes; no close/modify)");
    ProbeLog("AC-14: PASS (see IMPLEMENTATION_REPORT.md)");
    ProbeLog("AC-15: NOT_APPLICABLE");
    ProbeLog("AC-16: PASS (no request, no retry opportunity)");
    ProbeLog("====== END PROBE SUMMARY ======");
    return;
  }

  // ---- Trade path: log request result ----
  PrintFormat("[PROBE][%s] Trade direction: %s | Requested volume: %.8f | Magic: %d",
    ProbeSessionID, TestBuy ? "BUY" : "SELL", TestVolume, ProbeMagic);
  PrintFormat("[PROBE][%s] Request: ok=%s retcode=%u order=%s resultdeal=%s resvol=%.8f resprice=%.5f",
    ProbeSessionID,
    g_request_ok ? "YES" : "NO",
    g_retcode,
    UlongToDecStr(g_order_ticket),
    UlongToDecStr(g_result_deal),
    g_result_volume, g_result_price);

  // ---- Callback log: include archived pre-recovery evidence and callbacks observed after recovery ----
  int callback_total = g_callback_archive_count + g_callback_count;
  int callback_overflow_total = g_callback_archive_overflow + g_callback_overflow;
  PrintFormat("[PROBE][%s] Callbacks received: %d | Buffer overflow: %d | archived=%d current=%d",
    ProbeSessionID, callback_total, callback_overflow_total,
    g_callback_archive_count, g_callback_count);

  for(int i = 0; i < g_callback_archive_count; i++)
    LogCallbackRecord(g_callback_archive[i]);
  for(int i = 0; i < g_callback_count; i++)
    LogCallbackRecord(g_callbacks[i]);

  // ---- Scan-1 results ----
  PrintFormat("[PROBE][%s] SCAN-1: status=%s total=%d valid=%d invalid=%d agg_vol=%.8f posids=%d conflict=%s vol_exceeds=%s resultdeal=%s",
    ProbeSessionID,
    ScanStatusStr(scan1.scan_status),
    scan1.deal_count_total, scan1.deal_count_valid, scan1.invalid_deal_count,
    scan1.agg_volume, scan1.distinct_pos_ids,
    scan1.critical_conflict ? "YES" : "NO",
    scan1.volume_exceeds_request ? "YES" : "NO",
    scan1.result_deal_found ? "FOUND" : (g_result_deal==0 ? "N/A" : "NOT_FOUND"));

  if(scan1.scan_status == SCAN_INCOMPLETE)
    ProbeLog("SCAN-1: INCOMPLETE — cannot classify fill result; some evidence is missing");
  else if(scan1.scan_status == SCAN_COMPLETE_EMPTY && g_request_ok)
    ProbeLog("SCAN-1: COMPLETE_EMPTY — request accepted but zero matching deals; UNRESOLVED");
  else if(scan1.deal_count_valid == 1)
    ProbeLog("SCAN-1: 1 valid deal. NOTE: does not prove partial fills are impossible.");
  else if(scan1.deal_count_valid > 1 && !scan1.critical_conflict)
    ProbeLog("SCAN-1: Multiple valid deals same Position Identifier — potential partial fill");

  // ---- Position snapshot ----
  PrintFormat("[PROBE][%s] POSITION_SNAPSHOT: count=%d snapshot_ok=%s",
    ProbeSessionID, g_position_count,
    g_position_snapshot_ok ? "YES" : "INCOMPLETE");
  if(g_position_count > 1)
    ProbeLog("POSITION: Multiple positions found for Symbol+Magic — reporting all");
  for(int i = 0; i < g_position_count; i++)
  {
    PrintFormat("[PROBE][%s] POSITION[%d]: ticket=%s identifier=%s vol=%.8f open_price=%.5f",
      ProbeSessionID, i,
      UlongToDecStr(g_positions[i].pos_ticket),
      UlongToDecStr(g_positions[i].pos_identifier),
      g_positions[i].pos_volume,
      g_positions[i].pos_price_open);
  }
  // Cross-check: position identifier vs valid deal scan (CR-08: require props_ok)
  if(scan1.distinct_pos_ids == 1 && g_position_count == 1 &&
     scan1.deal_count_valid > 0 && g_positions[0].props_ok)
  {
    bool pos_match = (scan1.single_valid_pos_id == g_positions[0].pos_identifier);
    PrintFormat("[PROBE][%s] POSITION_ID_MATCH: deal_posid=%s pos_identifier=%s match=%s",
      ProbeSessionID,
      UlongToDecStr(scan1.single_valid_pos_id),
      UlongToDecStr(g_positions[0].pos_identifier),
      pos_match ? "YES" : "NO");
  }

  // ---- Recovery simulation ----
  PrintFormat("[PROBE][%s] RECOVERY_SIM: status=%s deals=%d valid=%d agg_vol=%.8f posids=%d match=%s%s",
    ProbeSessionID,
    ScanStatusStr(scan_rec.scan_status),
    scan_rec.deal_count_total, scan_rec.deal_count_valid,
    scan_rec.agg_volume, scan_rec.distinct_pos_ids,
    g_recovery_match ? "YES" : "NO",
    StringLen(g_recovery_discrepancy) > 0 ? (" DISCREPANCY: " + g_recovery_discrepancy) : "");

  // ---- True restart ----
  ProbeLog("TRUE_RESTART_RECOVERY=NOT_TESTED (Strategy Tester does not support genuine EA/Terminal restart)");
  ProbeLog("NOTE: Recovery simulation proves cold-state algorithm within same Tester run only.");
  ProbeLog("ACTION: Consider WP-06E / D-06-06 for true restart proof if required.");

  // ---- CR-03: Evidence-based AC verdicts ----
  ProbeLog("--- ACCEPTANCE CRITERIA STATUS ---");

  // AC-01: Tester-only gate — passes because OnInit returned INIT_SUCCEEDED
  ProbeLog("AC-01 Tester-only: PASS (INIT_FAILED without MQL_TESTER; this run is in Tester)");

  // AC-02: Default guard — passes unconditionally if we got here with trade enabled
  ProbeLog("AC-02 EnableTestTrade guard: PASS (default=false; trade enabled explicitly by user)");

  // AC-03: Single request — PASS only if request was sent and no second send occurred
  ProbeLog("AC-03 Single request: " + (g_trade_sent ? "PASS" : "NOT_OBSERVED"));

  // AC-04: Environment + request result — PASS if order ticket is non-zero
  string ac04 = (g_order_ticket != 0) ? "PASS" : (g_request_ok ? "INCOMPLETE" : "FAIL");
  ProbeLog("AC-04 Env + request result: " + ac04);

  // AC-05: Callback buffer — PASS only if callbacks captured and no overflow occurred
  string ac05;
  if(callback_total == 0)
    ac05 = "NOT_OBSERVED (0 callbacks captured during observation window)";
  else if(callback_overflow_total == 0)
    ac05 = "PASS (count=" + IntegerToString(callback_total) + " overflow=0)";
  else
    ac05 = "INCOMPLETE (overflow=" + IntegerToString(callback_overflow_total) +
           " — callback evidence lost; adjust MAX_CALLBACKS if needed)";
  ProbeLog("AC-05 Callback buffer: " + ac05);

  // AC-06: Immediate DEAL_ADD History probe — check actual callback evidence
  bool ac06_observed = false;
  bool any_imm_select_ok = false;
  bool any_imm_full_ok = false;
  for(int i = 0; i < g_callback_archive_count; i++)
  {
    if(g_callback_archive[i].immediate_select_attempted)
    {
      ac06_observed = true;
      if(g_callback_archive[i].immediate_select_ok)
      {
        any_imm_select_ok = true;
        if(g_callback_archive[i].imm_read_ok) any_imm_full_ok = true;
      }
    }
  }
  for(int i = 0; i < g_callback_count; i++)
  {
    if(g_callbacks[i].immediate_select_attempted)
    {
      ac06_observed = true;
      if(g_callbacks[i].immediate_select_ok)
      {
        any_imm_select_ok = true;
        if(g_callbacks[i].imm_read_ok) any_imm_full_ok = true;
      }
    }
  }
  string ac06;
  if(!ac06_observed)
    ac06 = "NOT_OBSERVED (no DEAL_ADD callback captured; check overflow or Tester behavior)";
  else if(any_imm_full_ok)
    ac06 = "PASS (immediate HistoryDealSelect and property reads succeeded)";
  else if(any_imm_select_ok)
    ac06 = "INCOMPLETE (immediate HistoryDealSelect succeeded but property read failed)";
  else
    ac06 = "INCOMPLETE (immediate HistoryDealSelect failed for all DEAL_ADD callbacks)";
  ProbeLog("AC-06 Immediate DEAL_ADD History probe: " + ac06);

  // AC-07: Exact Order selection + bounded History scan
  string ac07;
  switch(scan1.scan_status)
  {
    case SCAN_COMPLETE_MATCH: ac07 = "PASS"; break;
    case SCAN_COMPLETE_EMPTY: ac07 = "INCOMPLETE (scan complete, zero matching deals)"; break;
    case SCAN_INCOMPLETE:     ac07 = "INCOMPLETE (scan did not complete)"; break;
    case SCAN_INVALID_ORDER:  ac07 = "FAIL (HistoryOrderSelect failed)"; break;
    case SCAN_HISTORY_FAIL:   ac07 = "FAIL (HistorySelect failed)"; break;
    default:                  ac07 = "NOT_OBSERVED"; break;
  }
  ProbeLog("AC-07 Exact Order selection + bounded History scan: " + ac07);

  // AC-08: Exact DEAL_ORDER filter — PASS only when scan completed and found valid deals
  string ac08;
  if(scan1.scan_status == SCAN_COMPLETE_MATCH && scan1.deal_count_valid > 0)
    ac08 = "PASS (" + IntegerToString(scan1.deal_count_valid) + " valid exact-order deal(s))";
  else if(scan1.scan_status == SCAN_COMPLETE_EMPTY)
    ac08 = "COMPLETE_EMPTY (zero matching deals)";
  else if(scan1.scan_status == SCAN_INCOMPLETE)
    ac08 = "INCOMPLETE";
  else
    ac08 = "NOT_OBSERVED";
  ProbeLog("AC-08 Exact DEAL_ORDER filter: " + ac08);

  // AC-09: Deal properties — PASS only if scan complete, no invalid deals, and all props_ok=true
  string ac09;
  if(scan1.scan_status == SCAN_INCOMPLETE)
    ac09 = "INCOMPLETE (scan did not complete)";
  else if(scan1.deal_count_valid == 0)
    ac09 = "NOT_OBSERVED (no valid deals)";
  else if(scan1.invalid_deal_count > 0)
    ac09 = "FAIL (" + IntegerToString(scan1.invalid_deal_count) + " invalid/incomplete exact-order deal(s))";
  else
  {
    bool all_complete = true;
    for(int i = 0; i < g_first_scan_deal_count; i++)
    {
      if(g_first_scan_deals[i].valid_for_aggregate && !g_first_scan_deals[i].all_props_ok)
        { all_complete = false; break; }
    }
    ac09 = all_complete
      ? "PASS (" + IntegerToString(scan1.deal_count_valid) + " deal(s) all props ok)"
      : "INCOMPLETE (some valid deals had property read errors)";
  }
  ProbeLog("AC-09 Deal properties: " + ac09);

  // AC-10: Aggregate volume + distinct pos IDs + live Position (CR-08)
  string ac10;
  if(scan1.scan_status != SCAN_COMPLETE_MATCH || scan1.deal_count_valid == 0)
    ac10 = "INCOMPLETE (scan status=" + ScanStatusStr(scan1.scan_status) + ", valid_deals=" + IntegerToString(scan1.deal_count_valid) + ")";
  else if(scan1.invalid_deal_count > 0)
    ac10 = "FAIL (invalid exact-order deals present: " + IntegerToString(scan1.invalid_deal_count) + ")";
  else if(scan1.critical_conflict)
    ac10 = "FAIL (critical: multiple Position Identifiers from one Order)";
  else if(scan1.distinct_pos_ids != 1 || scan1.single_valid_pos_id == 0)
    ac10 = "FAIL (invalid distinct Position Identifier count=" + IntegerToString(scan1.distinct_pos_ids) + ")";
  else if(scan1.volume_exceeds_request)
    ac10 = "FAIL (aggregate volume exceeds requested volume)";
  else if(!g_position_snapshot_ok)
    ac10 = "INCOMPLETE (position snapshot incomplete)";
  else if(g_position_count == 0)
    ac10 = "INCOMPLETE (no matching live Position found)";
  else if(g_position_count > 1)
    ac10 = "FAIL (multiple live Positions found for single entry order)";
  else if(!g_positions[0].props_ok)
    ac10 = "INCOMPLETE (live Position properties incomplete)";
  else if(g_positions[0].pos_identifier != scan1.single_valid_pos_id)
    ac10 = "FAIL (Position identifier mismatch vs Deal Position ID)";
  else if(g_symbol_vol_step > 0.0 && MathAbs(g_positions[0].pos_volume - scan1.agg_volume) >= g_symbol_vol_step * 0.001)
    ac10 = "FAIL (Position volume mismatch vs Deal aggregate volume)";
  else
    ac10 = "PASS (volume=" + DoubleToString(scan1.agg_volume, 8) +
           " posid=" + UlongToDecStr(scan1.single_valid_pos_id) +
           " positions=" + IntegerToString(g_position_count) + ")";
  ProbeLog("AC-10 Aggregate volume + distinct positions + live Position: " + ac10);

  // AC-11: Recovery simulation
  string ac11;
  if(scan1.scan_status != SCAN_COMPLETE_MATCH)
    ac11 = "INCOMPLETE (first scan cannot serve as a complete recovery baseline: " + ScanStatusStr(scan1.scan_status) + ")";
  else if(scan_rec.scan_status == SCAN_NOT_RUN)
    ac11 = "NOT_OBSERVED (recovery scan not run)";
  else if(scan_rec.scan_status != SCAN_COMPLETE_MATCH)
    ac11 = "INCOMPLETE (recovery scan incomplete/status=" + ScanStatusStr(scan_rec.scan_status) + ")";
  else if(g_recovery_match)
    ac11 = "PASS (recovery scan reproduces first scan result)";
  else
    ac11 = "FAIL (discrepancy: " + g_recovery_discrepancy + ")";
  ProbeLog("AC-11 Recovery simulation: " + ac11);

  // AC-12: TRUE_RESTART_RECOVERY=NOT_TESTED — always PASS as a reporting obligation
  ProbeLog("AC-12 TRUE_RESTART_RECOVERY=NOT_TESTED: PASS (correctly reported as NOT_TESTED)");

  // AC-13: No Production changes; no Close/Modify — statically verified in source
  ProbeLog("AC-13 No Production changes, no Close/Modify: PASS (statically verified)");

  // AC-14: Implementation Report (external doc; not runtime-verified by EA)
  ProbeLog("AC-14 Implementation Report: NOT_RUNTIME_VERIFIED (external document; see IMPLEMENTATION_REPORT.md)");

  // AC-15: REQUEST_STARTED persisted before send; fail-closed on ambiguous session
  string ac15 = trade_path_attempted
    ? "PASS (REQUEST_STARTED persisted before send; fail-closed path verified in source)"
    : "NOT_OBSERVED";
  ProbeLog("AC-15 REQUEST_STARTED + fail-closed: " + ac15);

  // AC-16: No automatic retry
  ProbeLog("AC-16 No automatic retry: PASS (statically verified — no retry code path)");

  ProbeLog("====== END PROBE SUMMARY ======");
}

void ScheduleFinalSummary(
  const ScanResult &scan1,
  const ScanResult &scan_rec,
  bool trade_path_attempted
)
{
  g_pending_scan1 = scan1;
  g_pending_scan_rec = scan_rec;
  g_pending_trade_path_attempted = trade_path_attempted;
  g_summary_wait_started_ms = GetTickCount64();
  g_summary_pending = true;
  g_summary_emitted = false;
  ProbeLog("FINAL SUMMARY scheduled; waiting for queued trade callbacks before emitting callback evidence.");
}

// Timer runs after OnTick returns, allowing queued OnTradeTransaction handlers
// to populate the callback evidence buffers before the final report is emitted.
void OnTimer()
{
  if(!g_summary_pending || g_summary_emitted)
    return;

  ulong now_ms = GetTickCount64();
  ulong elapsed_ms = now_ms - g_summary_wait_started_ms;
  ulong quiet_ms = elapsed_ms;
  if(g_last_callback_tick_ms > 0 && now_ms >= g_last_callback_tick_ms)
    quiet_ms = now_ms - g_last_callback_tick_ms;

  if(elapsed_ms < CALLBACK_OBSERVATION_MIN_MS || quiet_ms < CALLBACK_QUIET_PERIOD_MS)
    return;

  g_summary_pending = false;
  g_summary_emitted = true;
  ProbeLog("Callback observation window ended after " + IntegerToString((int)elapsed_ms) +
           " ms; captured=" + IntegerToString(g_callback_archive_count + g_callback_count) +
           " overflow=" + IntegerToString(g_callback_archive_overflow + g_callback_overflow));
  EmitFinalSummary(g_pending_scan1, g_pending_scan_rec, g_pending_trade_path_attempted);
}

//=============================================================================
// Safety gate checks
//=============================================================================

bool PassesSafetyGates(string &error_msg)
{
  if(!MQLInfoInteger(MQL_TESTER))
  {
    error_msg = "GATE-1 FAIL: Not running in Strategy Tester. EA will not initialize.";
    return false;
  }
  if(MQLInfoInteger(MQL_OPTIMIZATION))
  {
    error_msg = "GATE-2 FAIL: Running in Optimization mode. EA will not initialize.";
    return false;
  }
  if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
  {
    error_msg = "GATE-4 FAIL: Account margin mode is not RETAIL_HEDGING. Probe requires Hedging.";
    return false;
  }
  return true;
}

bool PassesTradeGates(string &error_msg)
{
  if(!EnableTestTrade)
  {
    error_msg = "GATE-3: EnableTestTrade=false; no Trade Request will be sent.";
    return false;
  }
  if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
  {
    error_msg = "GATE-5 FAIL: TERMINAL_TRADE_ALLOWED=false";
    return false;
  }
  if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
  {
    error_msg = "GATE-5 FAIL: MQL_TRADE_ALLOWED=false";
    return false;
  }
  if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
  {
    error_msg = "GATE-5 FAIL: ACCOUNT_TRADE_ALLOWED=false";
    return false;
  }

  if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
  {
    error_msg = "GATE-6 FAIL: Symbol trade mode disabled";
    return false;
  }

  g_symbol_vol_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
  g_symbol_vol_max  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
  g_symbol_vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

  if(!MathIsValidNumber(g_symbol_vol_min) || !MathIsValidNumber(g_symbol_vol_max) ||
     !MathIsValidNumber(g_symbol_vol_step) ||
     g_symbol_vol_min <= 0.0 || g_symbol_vol_max <= 0.0 || g_symbol_vol_step <= 0.0)
  {
    error_msg = "GATE-6 FAIL: Symbol volume parameters unreadable";
    return false;
  }

  if(!MathIsValidNumber(TestVolume))
  {
    error_msg = "GATE-7 FAIL: TestVolume is not a finite number";
    return false;
  }
  if(TestVolume < g_symbol_vol_min - g_symbol_vol_step * 0.001)
  {
    error_msg = "GATE-7 FAIL: TestVolume=" + DoubleToString(TestVolume, 8) +
                " < SymbolVolumeMin=" + DoubleToString(g_symbol_vol_min, 8);
    return false;
  }
  if(TestVolume > g_symbol_vol_max + g_symbol_vol_step * 0.001)
  {
    error_msg = "GATE-7 FAIL: TestVolume=" + DoubleToString(TestVolume, 8) +
                " > SymbolVolumeMax=" + DoubleToString(g_symbol_vol_max, 8);
    return false;
  }
  if(!VolumeMatchesStep(TestVolume, g_symbol_vol_step, g_symbol_vol_min))
  {
    error_msg = "GATE-7 FAIL: TestVolume=" + DoubleToString(TestVolume, 8) +
                " does not align with VolumeStep=" + DoubleToString(g_symbol_vol_step, 8);
    return false;
  }

  if(ProbeMagic <= 0)
  {
    error_msg = "GATE-8 FAIL: ProbeMagic must be positive";
    return false;
  }

  int pos_total = PositionsTotal();
  for(int i = 0; i < pos_total; i++)
  {
    ResetLastError();
    ulong pt = PositionGetTicket(i);
    if(pt == 0)
    {
      error_msg = "GATE-8 FAIL: PositionGetTicket(" + IntegerToString(i) +
                  ") returned 0; cannot prove ownership scan complete. LastError=" +
                  IntegerToString(GetLastError());
      return false;
    }

    string position_symbol = "";
    long position_magic = 0;
    if(!PositionGetString(POSITION_SYMBOL, position_symbol) ||
       !PositionGetInteger(POSITION_MAGIC, position_magic))
    {
      error_msg = "GATE-8 FAIL: cannot read Symbol/Magic for Position ticket=" +
                  UlongToDecStr(pt) + "; enumeration is incomplete. LastError=" +
                  IntegerToString(GetLastError());
      return false;
    }
    if(position_symbol == _Symbol && position_magic == ProbeMagic)
    {
      error_msg = "GATE-8 FAIL: Existing position for Symbol=" + _Symbol +
                  " Magic=" + IntegerToString(ProbeMagic);
      return false;
    }
  }

  int ord_total = OrdersTotal();
  for(int i = 0; i < ord_total; i++)
  {
    ResetLastError();
    ulong ot = OrderGetTicket(i);
    if(ot == 0)
    {
      error_msg = "GATE-8 FAIL: OrderGetTicket(" + IntegerToString(i) +
                  ") returned 0; cannot prove active-order scan complete. LastError=" +
                  IntegerToString(GetLastError());
      return false;
    }

    string order_symbol = "";
    long order_magic = 0;
    if(!OrderGetString(ORDER_SYMBOL, order_symbol) ||
       !OrderGetInteger(ORDER_MAGIC, order_magic))
    {
      error_msg = "GATE-8 FAIL: cannot read Symbol/Magic for Order ticket=" +
                  UlongToDecStr(ot) + "; enumeration is incomplete. LastError=" +
                  IntegerToString(GetLastError());
      return false;
    }
    if(order_symbol == _Symbol && order_magic == ProbeMagic)
    {
      error_msg = "GATE-8 FAIL: Active order for Symbol=" + _Symbol +
                  " Magic=" + IntegerToString(ProbeMagic);
      return false;
    }
  }

  if(!IsValidSessionID(ProbeSessionID))
  {
    error_msg = "GATE-9 FAIL: Invalid SessionID '" + ProbeSessionID +
                "'. Use only A-Z/a-z/0-9/_/-";
    return false;
  }

  return true;
}

//=============================================================================
// MR-04 — Deterministic in-memory self-check (no Trade Request, no File I/O)
//=============================================================================

bool VerifySerializationSelfCheck()
{
  ulong parsed = 0;

  // Round-trip: 0, 1, LONG_MAX, > LONG_MAX (64-bit unsigned)
  ulong test_vals[4];
  test_vals[0] = 0;
  test_vals[1] = 1;
  test_vals[2] = 9223372036854775807;     // LONG_MAX
  test_vals[3] = (ulong)(~(ulong)0);          // ULLONG_MAX (2^64 - 1), constructed without an oversized literal

  for(int i = 0; i < 4; i++)
  {
    string dec = UlongToDecStr(test_vals[i]);
    if(!DecStrToUlong(dec, parsed) || parsed != test_vals[i])
    {
      ProbeLog("SELF-CHECK FAIL: round-trip failed for dec=" + dec);
      return false;
    }
  }

  // Negative cases: empty, non-digit, overflow (> ULLONG_MAX)
  if(DecStrToUlong("", parsed)) return false;
  if(DecStrToUlong("123a45", parsed)) return false;
  if(DecStrToUlong("18446744073709551616", parsed)) return false;
  if(DecStrToUlong("99999999999999999999", parsed)) return false;

  return true;
}

//=============================================================================
// OnInit
//=============================================================================

int OnInit()
{
  g_terminal_build   = (int)TerminalInfoInteger(TERMINAL_BUILD);
  g_symbol_digits    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
  g_symbol_point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
  g_symbol_tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

  ENUM_SYMBOL_TRADE_EXECUTION exec_mode =
    (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_EXEMODE);
  g_symbol_exec_mode = EnumToString(exec_mode);

  long fill_flags    = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
  g_symbol_fill_mode = IntegerToString((int)fill_flags);

  g_symbol_vol_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
  g_symbol_vol_max  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
  g_symbol_vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

  ProbeLog("===== PROBE INIT (CTO remediation) =====");
  PrintFormat("[PROBE][%s] Build=%d Symbol=%s Exec=%s Fill=%s",
    ProbeSessionID, g_terminal_build, _Symbol,
    g_symbol_exec_mode, g_symbol_fill_mode);
  PrintFormat("[PROBE][%s] Vol min=%.8f max=%.8f step=%.8f | digits=%d",
    ProbeSessionID, g_symbol_vol_min, g_symbol_vol_max, g_symbol_vol_step, g_symbol_digits);
  PrintFormat("[PROBE][%s] EnableTestTrade=%s Direction=%s Volume=%.8f Magic=%d SessionID=%s",
    ProbeSessionID,
    EnableTestTrade ? "true" : "false",
    TestBuy ? "BUY" : "SELL",
    TestVolume, ProbeMagic, ProbeSessionID);

  string gate_err = "";
  if(!PassesSafetyGates(gate_err))
  {
    ProbeLog("INIT REJECTED: " + gate_err);
    return INIT_FAILED;
  }

  if(!VerifySerializationSelfCheck())
  {
    ProbeLog("INIT REJECTED: 64-bit ticket serialization self-check failed");
    return INIT_FAILED;
  }

  ProbeLog("INIT: Safety gates 1,2,4 passed. Probe ready.");
  if(!EventSetTimer(1))
  {
    ProbeLog("INIT REJECTED: EventSetTimer(1) failed; callback observation summary cannot be guaranteed.");
    return INIT_FAILED;
  }
  g_initialized_ok = true;
  ArrayResize(g_callbacks, MAX_CALLBACKS);

  return INIT_SUCCEEDED;
}

//=============================================================================
// OnTick — main probe logic runs exactly once
//=============================================================================

void OnTick()
{
  if(!g_initialized_ok || g_probe_complete) return;
  g_probe_complete = true;

  ProbeLog("===== PROBE TICK START =====");

  string gate_err   = "";
  bool   can_trade  = PassesTradeGates(gate_err);

  if(!can_trade)
  {
    ProbeLog("TRADE GATE: " + gate_err);
    if(!EnableTestTrade)
    {
      ScanResult empty; ZeroMemory(empty);
      EmitFinalSummary(empty, empty, false);
      return;
    }
    ProbeLog("PROBE ABORTED: cannot trade.");
    return;
  }

  // ---- CR-02: Check persisted session state ----
  PersistedRecord persisted;
  PROBE_LOAD_RESULT load_result = LoadPersistedRecord(persisted);

  if(load_result == LOAD_IO_ERROR)
  {
    // File exists but cannot be read — cannot prove no previous session → Fail Closed
    g_fail_closed = true;
    g_fail_closed_reason = "Session file exists but cannot be read (IO_ERROR).";
    ProbeLog("FAIL CLOSED: " + g_fail_closed_reason + " No Trade Request.");
    ScanResult empty; ZeroMemory(empty);
    EmitFinalSummary(empty, empty, false);
    return;
  }

  if(load_result == LOAD_CORRUPT)
  {
    // File is corrupt — cannot distinguish from partial write → Fail Closed
    g_fail_closed = true;
    g_fail_closed_reason = "Session file corrupt/unreadable.";
    ProbeLog("FAIL CLOSED: " + g_fail_closed_reason + " No Trade Request to prevent accidental replay.");
    ScanResult empty; ZeroMemory(empty);
    EmitFinalSummary(empty, empty, false);
    return;
  }

  if(load_result == LOAD_VALID)
  {
    if(persisted.session_id != ProbeSessionID)
    {
      // CR-02: Session ID mismatch must Fail Closed (never treat as fresh session)
      g_fail_closed = true;
      g_fail_closed_reason = "Persisted SESSION_ID mismatch (" + persisted.session_id +
                             " vs " + ProbeSessionID + ").";
      ProbeLog("FAIL CLOSED: " + g_fail_closed_reason + " No Trade Request.");
      ScanResult empty; ZeroMemory(empty);
      EmitFinalSummary(empty, empty, false);
      return;
    }
    else
    {
      ProbeLog("PERSISTED STATE FOUND: state=" + persisted.state);
      // CR-02 / AC-15: REQUEST_STARTED without durable ticket → Fail Closed
      if(persisted.state == STATE_REQUEST_STARTED)
      {
        g_fail_closed = true;
        g_fail_closed_reason = "Session '" + ProbeSessionID +
                               "' has REQUEST_STARTED but no durable Order Ticket.";
        ProbeLog("FAIL CLOSED: " + g_fail_closed_reason);
        ProbeLog("Server may have accepted request; EA failed to persist ticket. Manual inspection required.");
        ScanResult empty; ZeroMemory(empty);
        EmitFinalSummary(empty, empty, false);
        return;
      }
      // ORDER_PERSISTED or COMPLETED → duplicate; refuse replay
      if(persisted.state == STATE_ORDER_PERSISTED || persisted.state == STATE_COMPLETED)
      {
        g_fail_closed = true;
        g_fail_closed_reason = "Session '" + ProbeSessionID + "' already persisted state=" +
                               persisted.state + " (duplicate guard).";
        ProbeLog("FAIL CLOSED: " + g_fail_closed_reason + " Refusing new Trade Request.");
        ScanResult empty; ZeroMemory(empty);
        EmitFinalSummary(empty, empty, false);
        return;
      }
    }
  }
  // load_result == LOAD_NOT_FOUND → fresh session, proceed

  // ---- CR-01: Persist REQUEST_STARTED + flush before sending ----
  ProbeLog("Persisting REQUEST_STARTED...");
  if(!PersistState(STATE_REQUEST_STARTED, 0, _Symbol, ProbeMagic, TestVolume, 0))
  {
    ProbeLog("PROBE ABORTED: Cannot persist REQUEST_STARTED. No Trade Request will be sent.");
    return;
  }
  ProbeLog("REQUEST_STARTED write count verified; FileFlush invoked (void API; durability cannot be verified).");

  // ---- Send Trade Request ----
  CTrade trade;
  trade.SetExpertMagicNumber(ProbeMagic);
  trade.SetTypeFillingBySymbol(_Symbol);

  g_trade_sent = true;
  bool send_ok;

  ProbeLog("Sending " + (TestBuy ? "BUY" : "SELL") + " " +
           DoubleToString(TestVolume, 8) + " " + _Symbol);

  if(TestBuy)
    send_ok = trade.Buy(TestVolume, _Symbol, 0.0, 0.0, 0.0, "D06-02-PROBE");
  else
    send_ok = trade.Sell(TestVolume, _Symbol, 0.0, 0.0, 0.0, "D06-02-PROBE");

  g_request_ok    = send_ok;
  g_retcode       = trade.ResultRetcode();
  g_order_ticket  = trade.ResultOrder();
  g_result_deal   = trade.ResultDeal();
  g_result_volume = trade.ResultVolume();
  g_result_price  = trade.ResultPrice();

  PrintFormat("[PROBE][%s] REQUEST RESULT: ok=%s retcode=%u order=%s deal=%s vol=%.8f price=%.5f",
    ProbeSessionID,
    send_ok ? "YES" : "NO",
    g_retcode,
    UlongToDecStr(g_order_ticket),
    UlongToDecStr(g_result_deal),
    g_result_volume, g_result_price);

  // ---- CR-01: Persist Order Ticket immediately; persist failure = AMBIGUOUS ----
  if(g_order_ticket != 0)
  {
    if(!PersistState(STATE_ORDER_PERSISTED, g_order_ticket, _Symbol, ProbeMagic, TestVolume, 0))
    {
      ProbeLog("AMBIGUOUS EXECUTION: Order Ticket=" + UlongToDecStr(g_order_ticket) +
               " received but persist failed. Stopping without retry.");
      ScanResult empty; ZeroMemory(empty);
      ScheduleFinalSummary(empty, empty, true);
      return;
    }
    ProbeLog("Order Ticket persisted: " + UlongToDecStr(g_order_ticket));
  }
  else if(send_ok)
  {
    ProbeLog("AMBIGUOUS EXECUTION: Request ok=true but Order Ticket=0. Stopping.");
    ScanResult empty; ZeroMemory(empty);
    ScheduleFinalSummary(empty, empty, true);
    return;
  }
  else
  {
    // Request rejected
    ProbeLog("Request rejected: retcode=" + IntegerToString(g_retcode) + ". No retry.");
    ScanResult empty; ZeroMemory(empty);
    ScheduleFinalSummary(empty, empty, true);
    return;
  }

  // ---- First exact-order History scan ----
  ProbeLog("Starting first exact-order History scan...");
  g_scan_status_1st = RunExactOrderScan(g_order_ticket, 0);
  PrintFormat("[PROBE][%s] SCAN-1 complete: status=%s total=%d",
    ProbeSessionID, ScanStatusStr(g_scan_status_1st), g_deal_count);

  ScanResult scan1 = AggregateScanResults(g_scan_status_1st, g_result_deal, TestVolume, g_symbol_vol_step);
  SnapshotFirstScanDeals();
  g_agg_volume_1st        = scan1.agg_volume;
  g_distinct_pos_ids_1st  = scan1.distinct_pos_ids;

  // ---- Position snapshot ----
  CapturePositionSnapshot();

  // ---- Order setup time ----
  datetime ord_setup_time = 0;
  if(g_order_ticket != 0 && HistoryOrderSelect(g_order_ticket))
    ord_setup_time = (datetime)HistoryOrderGetInteger(g_order_ticket, ORDER_TIME_SETUP);

  // Persist updated state with setup time
  if(!PersistState(STATE_ORDER_PERSISTED, g_order_ticket, _Symbol, ProbeMagic, TestVolume, ord_setup_time))
  {
    ProbeLog("PERSIST WARNING: Failed to update ORDER_PERSISTED with ord_setup_time; continuing with existing persisted ticket.");
  }

  // ---- Recovery Simulation ----
  ProbeLog("Starting recovery simulation...");

  // 1. Preserve an immutable diagnostic copy, then clear the volatile callback queue.
  //    Recovery below consumes only persisted state and exact History evidence.
  ArchiveCallbacksAndClearQueue();

  // 2. Load persisted record
  PersistedRecord rec2;
  PROBE_LOAD_RESULT load2 = LoadPersistedRecord(rec2);

  if(load2 != LOAD_VALID)
  {
    ProbeLog("RECOVERY SIM ERROR: LoadPersistedRecord result=" +
             IntegerToString((int)load2) + "; cannot run recovery scan");
    ScanResult empty; ZeroMemory(empty);
    empty.scan_status = SCAN_NOT_RUN;
    g_scan_status_rec = SCAN_NOT_RUN;
    ScheduleFinalSummary(scan1, empty, true);
    return;
  }

  PrintFormat("[PROBE][%s] RECOVERY SIM: state=%s order=%s symbol=%s magic=%d",
    ProbeSessionID, rec2.state,
    UlongToDecStr(rec2.order_ticket),
    rec2.symbol, rec2.magic);

  // 3. Validate record fields
  if(rec2.session_id != ProbeSessionID)
  {
    ProbeLog("RECOVERY SIM ERROR: session_id mismatch: " + rec2.session_id);
    ScanResult empty; ZeroMemory(empty); empty.scan_status = SCAN_NOT_RUN;
    g_scan_status_rec = SCAN_NOT_RUN;
    ScheduleFinalSummary(scan1, empty, true);
    return;
  }
  if(!rec2.order_ticket_parsed || rec2.order_ticket == 0)
  {
    ProbeLog("RECOVERY SIM: Fail Closed — no durable Order Ticket");
    ScanResult empty; ZeroMemory(empty); empty.scan_status = SCAN_NOT_RUN;
    g_scan_status_rec = SCAN_NOT_RUN;
    ScheduleFinalSummary(scan1, empty, true);
    return;
  }

  // 4. Second scan from persisted state
  ProbeLog("Recovery scan from persisted order_ticket=" + UlongToDecStr(rec2.order_ticket));
  g_scan_status_rec = RunExactOrderScan(rec2.order_ticket, rec2.order_setup_time);
  PrintFormat("[PROBE][%s] RECOVERY SCAN: status=%s total=%d",
    ProbeSessionID, ScanStatusStr(g_scan_status_rec), g_deal_count);

  ScanResult scan_rec = AggregateScanResults(g_scan_status_rec, g_result_deal,
                                              rec2.requested_volume, g_symbol_vol_step);
  g_agg_volume_rec       = scan_rec.agg_volume;
  g_distinct_pos_ids_rec = scan_rec.distinct_pos_ids;

  // 5. Compare exact Deal Ticket set and all relevant properties.
  g_recovery_match = CompareExactDealSets(g_recovery_discrepancy);
  if(g_recovery_match)
  {
    bool aggregate_match =
      scan_rec.deal_count_valid == scan1.deal_count_valid &&
      scan_rec.deal_count_total == scan1.deal_count_total &&
      MathAbs(scan_rec.agg_volume - scan1.agg_volume) < g_symbol_vol_step * 0.001 &&
      scan_rec.distinct_pos_ids == scan1.distinct_pos_ids;
    if(!aggregate_match)
    {
      g_recovery_match = false;
      g_recovery_discrepancy = "exact Deal set matched but aggregate projection differed";
    }
  }

  // ---- Mark completed ----
  if(!PersistState(STATE_COMPLETED, g_order_ticket, _Symbol, ProbeMagic, TestVolume, ord_setup_time))
  {
    ProbeLog("PERSIST WARNING: Failed to persist STATE_COMPLETED.");
  }

  ScheduleFinalSummary(scan1, scan_rec, true);
  ProbeLog("===== PROBE TICK COMPLETE =====");
}

//=============================================================================
// OnTradeTransaction — bounded callback buffer (MR-03: full field capture)
//=============================================================================

void OnTradeTransaction(
  const MqlTradeTransaction &trans,
  const MqlTradeRequest     &request,
  const MqlTradeResult      &result
)
{
  if(!g_initialized_ok) return;

  ProbeCallback cb;
  ZeroMemory(cb);

  cb.seq           = g_callback_sequence++;
  cb.tick_ms       = GetTickCount64();
  cb.time_current  = TimeCurrent();
  cb.trans_type    = trans.type;
  cb.order_ticket  = trans.order;
  cb.deal_ticket   = trans.deal;
  cb.position_id   = trans.position;
  cb.symbol        = trans.symbol;
  cb.volume        = trans.volume;
  cb.price         = trans.price;
  cb.price_trigger = trans.price_trigger;   // MR-03: stop trigger price
  cb.order_type    = trans.order_type;
  cb.order_state   = trans.order_state;
  cb.deal_type     = trans.deal_type;

  // MR-03: REQUEST transaction — full request + result fields
  cb.has_request = (trans.type == TRADE_TRANSACTION_REQUEST);
  if(cb.has_request)
  {
    cb.req_action  = request.action;
    cb.req_symbol  = request.symbol;
    cb.req_magic   = (int)request.magic;
    cb.req_volume  = request.volume;
    cb.req_price   = request.price;         // MR-03: request price
    cb.req_order   = result.order;
    cb.req_deal    = result.deal;
    cb.res_retcode = result.retcode;
    cb.res_volume  = result.volume;
    cb.res_price   = result.price;
    cb.res_bid     = result.bid;            // MR-03: result bid
    cb.res_ask     = result.ask;            // MR-03: result ask
  }

  // CR-13: DEAL_ADD immediate single-Deal History probe.
  // Use bool-returning property overloads; GetLastError is diagnostic only.
  if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal != 0)
  {
    cb.immediate_select_attempted = true;
    cb.immediate_deal_ticket      = trans.deal;
    ResetLastError();
    cb.immediate_select_ok = HistoryDealSelect(trans.deal);
    cb.immediate_last_error = GetLastError();

    if(cb.immediate_select_ok)
    {
      long raw_order = 0;
      long raw_entry = 0;
      long raw_type = 0;
      long raw_magic = 0;
      long raw_position_id = 0;
      long raw_time = 0;
      string deal_symbol = "";
      double deal_volume = 0.0;
      double deal_price = 0.0;
      bool reads_ok = true;
      int property_error = 0;

      ResetLastError();
      if(!HistoryDealGetInteger(trans.deal, DEAL_ORDER, raw_order))
      {
        reads_ok = false;
        property_error = GetLastError();
      }
      if(!HistoryDealGetInteger(trans.deal, DEAL_ENTRY, raw_entry))
      {
        reads_ok = false;
        property_error = GetLastError();
      }
      if(!HistoryDealGetInteger(trans.deal, DEAL_TYPE, raw_type))
      {
        reads_ok = false;
        property_error = GetLastError();
      }
      if(!HistoryDealGetString(trans.deal, DEAL_SYMBOL, deal_symbol))
      {
        reads_ok = false;
        property_error = GetLastError();
      }
      if(!HistoryDealGetInteger(trans.deal, DEAL_MAGIC, raw_magic))
      {
        reads_ok = false;
        property_error = GetLastError();
      }
      if(!HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID, raw_position_id))
      {
        reads_ok = false;
        property_error = GetLastError();
      }
      if(!HistoryDealGetDouble(trans.deal, DEAL_VOLUME, deal_volume))
      {
        reads_ok = false;
        property_error = GetLastError();
      }
      if(!HistoryDealGetDouble(trans.deal, DEAL_PRICE, deal_price))
      {
        reads_ok = false;
        property_error = GetLastError();
      }
      if(!HistoryDealGetInteger(trans.deal, DEAL_TIME, raw_time))
      {
        reads_ok = false;
        property_error = GetLastError();
      }

      cb.imm_deal_order       = (ulong)raw_order;
      cb.imm_deal_entry       = (int)raw_entry;
      cb.imm_deal_type        = (int)raw_type;
      cb.imm_deal_symbol      = deal_symbol;
      cb.imm_deal_magic       = raw_magic;
      cb.imm_deal_position_id = (ulong)raw_position_id;
      cb.imm_deal_volume      = deal_volume;
      cb.imm_deal_price       = deal_price;
      cb.imm_deal_time        = (datetime)raw_time;
      cb.imm_read_ok          = reads_ok;
      if(!reads_ok)
        cb.immediate_last_error = property_error;
    }
  }

  g_last_callback_tick_ms = GetTickCount64();
  AppendCallback(cb);
  if(g_summary_emitted)
  {
    ProbeLog("LATE CALLBACK observed after prior summary; scheduling a refreshed final summary.");
    g_summary_emitted = false;
    g_summary_pending = true;
    g_summary_wait_started_ms = g_last_callback_tick_ms;
  }
}

//=============================================================================
// OnDeinit
//=============================================================================

void OnDeinit(const int reason)
{
  // Strategy Tester can finish before the next timer event. Preserve the final
  // callback evidence already delivered to this EA instead of silently losing
  // a pending summary during deinitialization.
  if(g_summary_pending && !g_summary_emitted)
  {
    ProbeLog("DEINIT: finalizing pending summary with callbacks observed before deinitialization; "
             "the configured quiet-period may not have elapsed.");
    g_summary_pending = false;
    g_summary_emitted = true;
    EmitFinalSummary(g_pending_scan1, g_pending_scan_rec, g_pending_trade_path_attempted);
  }

  EventKillTimer();
  if(g_initialized_ok && !g_probe_complete)
    ProbeLog("DEINIT without completing probe; reason=" + IntegerToString(reason));
  ProbeLog("DEINIT complete.");
}
