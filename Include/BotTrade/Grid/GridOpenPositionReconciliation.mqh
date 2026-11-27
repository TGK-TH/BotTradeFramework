#ifndef BOTTRADE_GRID_OPEN_POSITION_RECONCILIATION_MQH
#define BOTTRADE_GRID_OPEN_POSITION_RECONCILIATION_MQH

#include <BotTrade/Grid/GridOpenPositionSnapshot.mqh>
#include <BotTrade/Grid/GridEntryMappingSnapshotStorage.mqh>
#include <BotTrade/Grid/GridLevelRuntimeCoordinator.mqh>

// Authoritative Open Positions Reconciliation.
//
// A Complete/Stable Live Position Snapshot becomes a single durable Lifecycle
// Journal record, the canonical Reducer applies it transactionally, the
// Coordinator is rebuilt from the Reducer Projection, and the Reconciliation
// Gate is released explicitly.
//
// This module never sends, opens or closes a trade. It has no CTrade, no
// OrderSend, no PositionClose and never reads Closing Deal History, Close
// Price, Close Reason, TP/NON_TP or SL classification.

enum ENUM_TGK_GRID_RECONCILIATION_STATUS
{
  // The accepted Snapshot implies no Durable change: nothing was written.
  TGK_GRID_RECONCILIATION_NO_CHANGE = 0,
  // The Durable batch was appended, applied and the Gate was released.
  TGK_GRID_RECONCILIATION_APPLIED,
  // The Snapshot, its freshness tokens or the context were unusable.
  TGK_GRID_RECONCILIATION_INVALID,
  // Conflicting Evidence: a mapped Position Identifier grew in volume.
  TGK_GRID_RECONCILIATION_CONFLICT,
  // An Owned Live Position could not be proven to belong to this Grid.
  TGK_GRID_RECONCILIATION_ORPHAN,
  // The Journal could not accept the batch; no state changed.
  TGK_GRID_RECONCILIATION_STORAGE_FAILED,
  // The batch was appended but not applied. Recovery Required: rebuild from
  // the Journal only.
  TGK_GRID_RECONCILIATION_APPLY_FAILED,
  // The Coordinator could not be rebuilt from the Reducer Projection.
  TGK_GRID_RECONCILIATION_HYDRATION_FAILED,
  // The Projection proof did not match the Runtime, so the Gate stays closed.
  TGK_GRID_RECONCILIATION_GATE_FAILED,
  // An earlier Run() left the Runtime unreleased after a Durable commit or a
  // failed Finalization. This instance refuses further work until the Runtime
  // is rebuilt from the canonical Reducer/Journal.
  TGK_GRID_RECONCILIATION_RECOVERY_REQUIRED
};

// Minimal Mapping Journal port. Production wraps the canonical Snapshot
// Storage; tests keep records in memory and inject append failure.
class CTGKGridMappingJournalPort
{
public:
  virtual bool ReadNextSequence(long &next_sequence)
  {
    next_sequence = 0;
    return false;
  }

  virtual bool AppendOne(
    ENUM_TGK_GRID_MAPPING_RECORD_TYPE record_type,
    string payload)
  {
    return false;
  }
};

// Production adapter. It only appends through CTGKGridEntryMappingSnapshotStorage,
// so Journal Sequence continuity and Snapshot Rotation behavior stay unchanged.
class CTGKGridSnapshotStorageJournalPort : public CTGKGridMappingJournalPort
{
private:
  CTGKGridEntryMappingSnapshotStorage *m_storage;

public:
  CTGKGridSnapshotStorageJournalPort()
  {
    m_storage = NULL;
  }

  bool Bind(CTGKGridEntryMappingSnapshotStorage &storage)
  {
    m_storage = GetPointer(storage);
    return CheckPointer(m_storage) != POINTER_INVALID;
  }

  virtual bool ReadNextSequence(long &next_sequence)
  {
    next_sequence = 0;
    if(CheckPointer(m_storage) == POINTER_INVALID ||
       !m_storage.IsInitialized())
      return false;

    next_sequence = m_storage.LastSequence() + 1;
    return true;
  }

  virtual bool AppendOne(
    ENUM_TGK_GRID_MAPPING_RECORD_TYPE record_type,
    string payload)
  {
    if(CheckPointer(m_storage) == POINTER_INVALID)
      return false;

    return m_storage.Append(record_type, payload);
  }
};

// Pure Diff/Policy. It compares an accepted Snapshot with the canonical Reducer
// Projection, validates the whole Diff before anything is persisted, and
// produces the one-record Reconciliation Batch payload.
class CTGKGridOpenPositionReconciler
{
private:
  bool m_initialized;
  string m_symbol;
  long m_magic_number;
  string m_instance_id;
  ENUM_TGK_GRID_MODE m_mode;
  long m_config_epoch;

  bool IsValidQuote(double bid, double ask)
  {
    return MathIsValidNumber(bid) &&
           MathIsValidNumber(ask) &&
           bid > 0.0 &&
           ask >= bid;
  }

  bool IsValidVolume(double volume)
  {
    return MathIsValidNumber(volume) && volume > 0.0;
  }

  int FindLiveIndex(
    STGKGridOpenPositionRecord &records[],
    string position_identifier)
  {
    for(int index = 0; index < ArraySize(records); index++)
    {
      if(records[index].position_identifier == position_identifier)
        return index;
    }
    return -1;
  }

  bool AppendEvent(string &events[], string event)
  {
    if(event == "")
      return false;

    int index = ArraySize(events);
    if(index >= TGK_GRID_MAPPING_MAX_RECONCILIATION_EVENTS)
      return false;

    if(ArrayResize(events, index + 1) != index + 1)
      return false;

    events[index] = event;
    return true;
  }

  // A Mapped Identifier that is absent from the Complete/Stable Snapshot is a
  // reason-free Full Close. The post-close state comes from the Engine rule at
  // Consume time, never from a Close Price, Close Reason or Deal History.
  bool AppendCloseEvent(
    CTGKGridLevelRuntimeCoordinator &coordinator,
    STGKGridPositionMappingProjection &projection,
    double current_bid,
    double current_ask,
    string &events[])
  {
    bool is_anchor = projection.target_kind == "ANCHOR";
    if(!is_anchor && projection.target_kind != "LEVEL")
      return false;

    ENUM_TGK_GRID_LEVEL_STATE next_state;
    if(!coordinator.TryGetPostCloseState(
      is_anchor,
      projection.level_index,
      current_bid,
      current_ask,
      next_state))
      return false;

    if(next_state != TGK_GRID_LEVEL_READY &&
       next_state != TGK_GRID_LEVEL_WAIT_ACTIVATION)
      return false;

    string state_token = next_state == TGK_GRID_LEVEL_READY
                         ? "READY"
                         : "WAIT_ACTIVATION";

    return AppendEvent(
      events,
      StringFormat(
        "POSITION_CLOSED|%s|%s",
        projection.position_identifier,
        state_token));
  }

  // An Owned Live Position without a Mapping is never adopted. It may only
  // remain as unresolved evidence when its Position Identifier is provably
  // tied to the single unresolved Entry Request by a durable Deal Association.
  bool IsUnresolvedEntryEvidence(
    CTGKGridEntryMappingReducer &reducer,
    STGKGridOpenPositionRecord &position,
    bool has_unresolved_request,
    STGKGridMappingRequestState &unresolved_request)
  {
    if(!has_unresolved_request)
      return false;

    if(position.volume >
       unresolved_request.requested_volume +
         TGK_GRID_OPEN_POSITION_VOLUME_EPSILON)
      return false;

    bool has_association = false;
    string request_id = "";
    double associated_volume = 0.0;
    if(!reducer.TryGetDealAssociationProjection(
      position.position_identifier,
      has_association,
      request_id,
      associated_volume))
      return false;

    if(!has_association ||
       request_id != unresolved_request.request_id ||
       position.volume >
         associated_volume + TGK_GRID_OPEN_POSITION_VOLUME_EPSILON)
      return false;

    return true;
  }

  bool BuildBatchPayload(string &events[], string &payload)
  {
    payload = "";

    int total = ArraySize(events);
    if(total <= 0 || total > TGK_GRID_MAPPING_MAX_RECONCILIATION_EVENTS)
      return false;

    payload = StringFormat(
      "%s|RECONCILIATION_BATCH|%d",
      TGK_GRID_MAPPING_PAYLOAD_VERSION,
      total);

    for(int index = 0; index < total; index++)
    {
      if(events[index] == "")
        return false;
      payload += "|" + events[index];
    }

    uchar bytes[];
    int byte_count = StringToCharArray(
      payload,
      bytes,
      0,
      WHOLE_ARRAY,
      CP_UTF8);
    if(byte_count <= 0)
      return false;

    return byte_count - 1 <= TGK_GRID_MAPPING_MAX_RECORD_BYTES;
  }

  // Builds and validates the whole Diff. Nothing is persisted here, so an
  // unusable Snapshot, a Conflict or an Orphan leaves no Durable trace. This
  // method is private: the only entry point is TryBuildBatch(), which requires
  // the Acquirer's single-use grant.
  ENUM_TGK_GRID_RECONCILIATION_STATUS BuildBatch(
    CTGKGridEntryMappingReducer &reducer,
    CTGKGridLevelRuntimeCoordinator &coordinator,
    STGKGridOpenPositionSnapshot &snapshot,
    STGKGridOpenPositionRecord &live_positions[],
    double current_bid,
    double current_ask,
    string &payload,
    int &event_count)
  {
    payload = "";
    event_count = 0;

    // Token freshness (single use, latest generation) is enforced by
    // CTGKGridOpenPositionAcquirer before this policy runs, through the
    // Acquirer-owned grant taken by TryBuildBatch(). The Snapshot's
    // caller-writable "consumed" field is never trusted. What this policy
    // validates is the Snapshot's data and its Base Sequence against the
    // current Reducer, which is what makes a stale observation unusable.
    if(!m_initialized ||
       !IsValidQuote(current_bid, current_ask) ||
       snapshot.status != TGK_GRID_OPEN_POSITION_COMPLETE ||
       snapshot.symbol != m_symbol ||
       snapshot.magic_number != m_magic_number ||
       snapshot.base_sequence != reducer.LastSequence() ||
       !reducer.MatchesContext(
         m_instance_id,
         m_symbol,
         m_magic_number,
         m_mode,
         m_config_epoch))
      return TGK_GRID_RECONCILIATION_INVALID;

    int live_count = ArraySize(live_positions);
    for(int index = 0; index < live_count; index++)
    {
      if(live_positions[index].ticket == 0 ||
         live_positions[index].symbol != m_symbol ||
         live_positions[index].magic_number != m_magic_number ||
         !IsValidVolume(live_positions[index].volume) ||
         !TGKGridIsDecimalPositionIdentifier(
           live_positions[index].position_identifier))
        return TGK_GRID_RECONCILIATION_INVALID;

      for(int previous = 0; previous < index; previous++)
      {
        if(live_positions[previous].ticket == live_positions[index].ticket ||
           live_positions[previous].position_identifier ==
             live_positions[index].position_identifier)
          return TGK_GRID_RECONCILIATION_INVALID;
      }
    }

    string events[];
    ArrayResize(events, 0);

    int mapping_count = reducer.PositionCount();
    for(int index = 0; index < mapping_count; index++)
    {
      STGKGridPositionMappingProjection projection;
      if(!reducer.TryGetPositionMappingAt(index, projection))
        return TGK_GRID_RECONCILIATION_INVALID;

      int live_index = FindLiveIndex(
        live_positions,
        projection.position_identifier);

      if(live_index < 0)
      {
        if(!AppendCloseEvent(
          coordinator,
          projection,
          current_bid,
          current_ask,
          events))
          return TGK_GRID_RECONCILIATION_INVALID;
        continue;
      }

      double live_volume = live_positions[live_index].volume;
      if(live_volume >
         projection.remaining_volume + TGK_GRID_OPEN_POSITION_VOLUME_EPSILON)
        return TGK_GRID_RECONCILIATION_CONFLICT;

      bool volume_changed =
        MathAbs(live_volume - projection.remaining_volume) >
          TGK_GRID_OPEN_POSITION_VOLUME_EPSILON;
      string live_ticket = StringFormat(
        "%I64u",
        live_positions[live_index].ticket);
      bool ticket_changed = live_ticket != projection.position_ticket;

      if(!volume_changed && !ticket_changed)
        continue;

      if(!AppendEvent(
        events,
        StringFormat(
          "POSITION_METADATA|%s|%s|%s",
          projection.position_identifier,
          DoubleToString(live_volume, 16),
          live_ticket)))
        return TGK_GRID_RECONCILIATION_INVALID;
    }

    bool has_unresolved_request = false;
    STGKGridMappingRequestState unresolved_request;
    if(!reducer.TryGetUnresolvedRequest(
      has_unresolved_request,
      unresolved_request))
      return TGK_GRID_RECONCILIATION_INVALID;

    for(int index = 0; index < live_count; index++)
    {
      bool is_mapped = false;
      for(int mapping_index = 0; mapping_index < mapping_count; mapping_index++)
      {
        STGKGridPositionMappingProjection projection;
        if(!reducer.TryGetPositionMappingAt(mapping_index, projection))
          return TGK_GRID_RECONCILIATION_INVALID;

        if(projection.position_identifier ==
           live_positions[index].position_identifier)
        {
          is_mapped = true;
          break;
        }
      }

      if(is_mapped)
        continue;

      if(!IsUnresolvedEntryEvidence(
        reducer,
        live_positions[index],
        has_unresolved_request,
        unresolved_request))
        return TGK_GRID_RECONCILIATION_ORPHAN;
    }

    event_count = ArraySize(events);
    if(event_count == 0)
      return TGK_GRID_RECONCILIATION_NO_CHANGE;

    if(!BuildBatchPayload(events, payload))
      return TGK_GRID_RECONCILIATION_INVALID;

    return TGK_GRID_RECONCILIATION_APPLIED;
  }

public:
  CTGKGridOpenPositionReconciler()
  {
    m_initialized = false;
    m_symbol = "";
    m_magic_number = 0;
    m_instance_id = "";
    m_mode = TGK_GRID_MODE_BUY;
    m_config_epoch = 0;
  }

  bool Initialize(
    string symbol,
    long magic_number,
    string instance_id,
    ENUM_TGK_GRID_MODE mode,
    long config_epoch)
  {
    m_initialized = false;
    if(symbol == "" ||
       magic_number <= 0 ||
       instance_id == "" ||
       config_epoch <= 0 ||
       (mode != TGK_GRID_MODE_BUY && mode != TGK_GRID_MODE_SELL))
      return false;

    m_symbol = symbol;
    m_magic_number = magic_number;
    m_instance_id = instance_id;
    m_mode = mode;
    m_config_epoch = config_epoch;
    m_initialized = true;
    return true;
  }

  bool IsInitialized()
  {
    return m_initialized;
  }

  // The only way to reach the Diff. The Acquirer owns the grant, so a
  // Snapshot that was never acquired, never consumed, already replayed, or
  // built by the Caller cannot be diffed even when every DTO field looks
  // valid. The Acquirer transfers and clears the grant before Diff validation,
  // so one accepted Snapshot produces at most one Batch attempt.
  ENUM_TGK_GRID_RECONCILIATION_STATUS TryBuildBatch(
    CTGKGridOpenPositionAcquirer *acquirer,
    CTGKGridEntryMappingReducer &reducer,
    CTGKGridLevelRuntimeCoordinator &coordinator,
    STGKGridOpenPositionSnapshot &snapshot,
    double current_bid,
    double current_ask,
    string &payload,
    int &event_count)
  {
    payload = "";
    event_count = 0;

    if(CheckPointer(acquirer) == POINTER_INVALID)
      return TGK_GRID_RECONCILIATION_INVALID;

    STGKGridOpenPositionRecord trusted_live_positions[];
    if(!acquirer.TakeConsumedSnapshot(snapshot, trusted_live_positions))
      return TGK_GRID_RECONCILIATION_INVALID;

    // The Diff receives no caller-supplied Position array. Only the exact
    // Owned Position Set copied from the Acquirer in the same operation can
    // drive Full Close or metadata decisions.
    return BuildBatch(
      reducer,
      coordinator,
      snapshot,
      trusted_live_positions,
      current_bid,
      current_ask,
      payload,
      event_count);
  }
};

// Durable Batch Coordination plus Coordinator Hydration and Gate Release.
class CTGKGridOpenPositionReconciliation
{
private:
  CTGKGridOpenPositionAcquirer *m_acquirer;
  CTGKGridMappingJournalPort *m_journal;
  CTGKGridOpenPositionReconciler m_policy;
  bool m_recovery_required;
  bool m_fail_projection_for_test;
  bool m_fail_hydration_for_test;
  bool m_fail_gate_for_test;

  // Complete Canonical Hydration Projection built from the Reducer only. The
  // Reconciliation adapter never re-derives Mapping, Anchor or Level state, and
  // it takes the operational Ticket from the accepted Snapshot instead of
  // parsing a persisted ticket string.
  bool BuildCoordinatorProjection(
    CTGKGridEntryMappingReducer &reducer,
    STGKGridOpenPositionRecord &live_positions[],
    STGKGridPersistedConfigProjection &config,
    ENUM_TGK_GRID_LEVEL_STATE &anchor_state,
    STGKGridLevelStateHydration &level_states[],
    STGKGridLevelPositionRecord &positions[],
    STGKGridEntryRequestHydration &entry_request)
  {
    ArrayResize(level_states, 0);
    ArrayResize(positions, 0);
    entry_request.present = false;
    entry_request.request_id = "";
    entry_request.is_anchor = false;
    entry_request.level_index = -1;
    entry_request.requested_volume = 0.0;
    anchor_state = TGK_GRID_LEVEL_READY;

    if(!reducer.TryGetPersistedConfig(config))
      return false;

    if(!reducer.TryGetAnchorState(anchor_state))
      return false;

    int normal_level_count = config.persisted_level_count - 1;
    if(normal_level_count <= 0 ||
       reducer.LevelCount() != normal_level_count)
      return false;

    if(ArrayResize(level_states, normal_level_count) != normal_level_count)
      return false;

    for(int level_index = 0; level_index < normal_level_count; level_index++)
    {
      int state_value = reducer.LevelStateAt(level_index);
      if(state_value < (int)TGK_GRID_LEVEL_READY ||
         state_value > (int)TGK_GRID_LEVEL_WAIT_ACTIVATION)
        return false;

      level_states[level_index].level_index = level_index;
      level_states[level_index].state = (ENUM_TGK_GRID_LEVEL_STATE)state_value;
    }

    int mapping_count = reducer.PositionCount();
    if(ArrayResize(positions, mapping_count) != mapping_count)
      return false;

    for(int index = 0; index < mapping_count; index++)
    {
      STGKGridPositionMappingProjection projection;
      if(!reducer.TryGetPositionMappingAt(index, projection))
        return false;

      int live_index = -1;
      for(int live = 0; live < ArraySize(live_positions); live++)
      {
        if(live_positions[live].position_identifier ==
           projection.position_identifier)
        {
          live_index = live;
          break;
        }
      }

      // Every mapped Identifier must still be present in the accepted Snapshot
      // with the committed Ticket and Volume; anything else means the Diff and
      // the Reducer projection disagree.
      if(live_index < 0)
        return false;

      if(StringFormat("%I64u", live_positions[live_index].ticket) !=
         projection.position_ticket)
        return false;

      if(MathAbs(live_positions[live_index].volume -
                 projection.remaining_volume) >
         TGK_GRID_OPEN_POSITION_VOLUME_EPSILON)
        return false;

      positions[index].ticket = live_positions[live_index].ticket;
      positions[index].symbol = projection.symbol;
      positions[index].magic_number = projection.magic_number;
      positions[index].is_anchor = projection.target_kind == "ANCHOR";
      positions[index].level_index = projection.level_index;
      positions[index].volume = projection.remaining_volume;
      positions[index].position_identifier = projection.position_identifier;
    }

    bool has_unresolved_request = false;
    STGKGridMappingRequestState request_state;
    if(!reducer.TryGetUnresolvedRequest(
      has_unresolved_request,
      request_state))
      return false;

    if(has_unresolved_request)
    {
      entry_request.present = true;
      entry_request.request_id = request_state.request_id;
      entry_request.is_anchor = request_state.target_kind == "ANCHOR";
      entry_request.level_index = request_state.level_index;
      entry_request.requested_volume = request_state.requested_volume;
    }

    return true;
  }

public:
  CTGKGridOpenPositionReconciliation()
  {
    m_acquirer = NULL;
    m_journal = NULL;
    m_recovery_required = false;
    m_fail_projection_for_test = false;
    m_fail_hydration_for_test = false;
    m_fail_gate_for_test = false;
  }

  bool Initialize(
    CTGKGridOpenPositionAcquirer &acquirer,
    CTGKGridMappingJournalPort &journal,
    string symbol,
    long magic_number,
    string instance_id,
    ENUM_TGK_GRID_MODE mode,
    long config_epoch)
  {
    m_recovery_required = false;
    m_fail_projection_for_test = false;
    m_fail_hydration_for_test = false;
    m_fail_gate_for_test = false;
    m_acquirer = GetPointer(acquirer);
    m_journal = GetPointer(journal);

    if(CheckPointer(m_acquirer) == POINTER_INVALID ||
       CheckPointer(m_journal) == POINTER_INVALID)
      return false;

    return m_policy.Initialize(
      symbol,
      magic_number,
      instance_id,
      mode,
      config_epoch);
  }

  // True after a Durable append that could not be applied in memory, or after
  // a Post-Commit Finalization that could not release the Gate. The Runtime
  // must stay gated and be rebuilt from the canonical Reducer/Journal; no
  // Rollback or compensating state is produced here.
  bool IsRecoveryRequired()
  {
    return m_recovery_required;
  }

  // Test seams for the Post-Commit failure paths. Production never enables
  // them; they exist so the Fail Closed guarantee can be verified without
  // inducing an allocation failure.
  bool SetProjectionFailureInjectionForTest(bool enabled)
  {
    m_fail_projection_for_test = enabled;
    return true;
  }

  bool SetHydrationFailureInjectionForTest(bool enabled)
  {
    m_fail_hydration_for_test = enabled;
    return true;
  }

  bool SetGateFailureInjectionForTest(bool enabled)
  {
    m_fail_gate_for_test = enabled;
    return true;
  }

  // Acquire -> Consume -> Diff -> one-record Append -> transactional Apply ->
  // Reducer Projection Hydration -> explicit Gate Release.
  //
  // The Durable mutation and the Post-Reconciliation Finalization are separate
  // phases. A NO_CHANGE observation skips the Durable phase entirely but is
  // still validated, hydrated and released, so a Runtime that already agrees
  // with its Durable Mapping can never stay gated after a restart. Any failure
  // in the Finalization leaves the Gate closed and puts this instance into
  // Recovery Required: the Runtime must then be rebuilt from the canonical
  // Reducer/Journal, never resumed from this instance.
  ENUM_TGK_GRID_RECONCILIATION_STATUS Run(
    CTGKGridEntryMappingReducer &reducer,
    CTGKGridLevelRuntimeCoordinator &coordinator,
    double current_bid,
    double current_ask)
  {
    if(m_recovery_required)
      return TGK_GRID_RECONCILIATION_RECOVERY_REQUIRED;

    if(CheckPointer(m_acquirer) == POINTER_INVALID ||
       CheckPointer(m_journal) == POINTER_INVALID)
      return TGK_GRID_RECONCILIATION_INVALID;

    if(!coordinator.IsReconciliationPending())
      return TGK_GRID_RECONCILIATION_INVALID;

    long base_sequence = reducer.LastSequence();

    STGKGridOpenPositionSnapshot snapshot;
    if(!m_acquirer.Acquire(base_sequence, snapshot))
      return TGK_GRID_RECONCILIATION_INVALID;

    // Preserve the Acquirer-owned Position Set for post-Diff Coordinator
    // hydration. This copy is not passed into the Diff policy; TryBuildBatch
    // independently takes its own trusted, single-use hand-off from Acquirer.
    STGKGridOpenPositionRecord live_positions[];
    if(!m_acquirer.CopyOwnedPositions(live_positions))
      return TGK_GRID_RECONCILIATION_INVALID;

    // Consume is validated against the current Reducer sequence, so an Entry or
    // Mapping transition between Acquire and Consume rejects the Snapshot.
    if(!m_acquirer.Consume(snapshot, reducer.LastSequence()))
      return TGK_GRID_RECONCILIATION_INVALID;

    string payload = "";
    int event_count = 0;
    ENUM_TGK_GRID_RECONCILIATION_STATUS status = m_policy.TryBuildBatch(
      m_acquirer,
      reducer,
      coordinator,
      snapshot,
      current_bid,
      current_ask,
      payload,
      event_count);

    if(status != TGK_GRID_RECONCILIATION_APPLIED &&
       status != TGK_GRID_RECONCILIATION_NO_CHANGE)
      return status;

    // Durable phase: exactly one Journal record, and only for a real change.
    // A NO_CHANGE observation writes nothing and leaves the Sequence untouched.
    if(status == TGK_GRID_RECONCILIATION_APPLIED)
    {
      long next_sequence = 0;
      if(!m_journal.ReadNextSequence(next_sequence) ||
         next_sequence != reducer.LastSequence() + 1)
        return TGK_GRID_RECONCILIATION_STORAGE_FAILED;

      if(!m_journal.AppendOne(
        TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
        payload))
        return TGK_GRID_RECONCILIATION_STORAGE_FAILED;

      if(!reducer.ApplyCommittedRecord(
        TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
        payload))
      {
        m_recovery_required = true;
        return TGK_GRID_RECONCILIATION_APPLY_FAILED;
      }
    }

    // Post-Reconciliation Finalization, shared by APPLIED and NO_CHANGE. It
    // never mutates the Journal and never rolls Durable state back.
    STGKGridPersistedConfigProjection config;
    ENUM_TGK_GRID_LEVEL_STATE anchor_state = TGK_GRID_LEVEL_READY;
    STGKGridLevelStateHydration level_states[];
    STGKGridLevelPositionRecord positions[];
    STGKGridEntryRequestHydration entry_request;

    if(m_fail_projection_for_test ||
       !BuildCoordinatorProjection(
         reducer,
         live_positions,
         config,
         anchor_state,
         level_states,
         positions,
         entry_request))
    {
      m_recovery_required = true;
      return TGK_GRID_RECONCILIATION_HYDRATION_FAILED;
    }

    if(m_fail_hydration_for_test ||
       !coordinator.HydrateRuntimeState(
         config.mode,
         config.anchor_price,
         config.grid_step,
         config.lower_bound,
         config.upper_bound,
         config.persisted_level_count - 1,
         config.symbol,
         config.magic_number,
         config.config_epoch,
         config,
         current_bid,
         current_ask,
         anchor_state,
         level_states,
         positions,
         entry_request))
    {
      m_recovery_required = true;
      return TGK_GRID_RECONCILIATION_HYDRATION_FAILED;
    }

    STGKGridReconciliationGateProof proof;
    proof.instance_id = config.instance_id;
    proof.symbol = config.symbol;
    proof.magic_number = config.magic_number;
    proof.mode = config.mode;
    proof.config_epoch = config.config_epoch;
    proof.snapshot_generation = snapshot.generation;
    proof.base_sequence = snapshot.base_sequence;

    if(m_fail_gate_for_test ||
       !coordinator.ReleaseReconciliationGate(
         proof,
         anchor_state,
         level_states,
         positions,
         entry_request,
         current_bid,
         current_ask))
    {
      m_recovery_required = true;
      return TGK_GRID_RECONCILIATION_GATE_FAILED;
    }

    return status;
  }
};

#endif
