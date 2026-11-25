#property strict
#property version "1.00"
#property description "Grid Entry Mapping Snapshot and Rotation tests; no trading."

#include <BotTrade/Testing/TestRunner.mqh>
#include <BotTrade/Grid/GridEntryMappingSnapshotStorage.mqh>

CTGKTestRunner Tests;

void AddReducerRecord(
  STGKGridMappingJournalRecord &records[],
  long sequence,
  ENUM_TGK_GRID_MAPPING_RECORD_TYPE record_type,
  string payload)
{
  int index = ArraySize(records);
  ArrayResize(records, index + 1);
  records[index].sequence = sequence;
  records[index].record_type = record_type;
  records[index].payload = payload;
}

void BuildMappedReducerFixture(
  STGKGridMappingJournalRecord &records[],
  string symbol,
  long magic_number,
  string instance_id)
{
  AddReducerRecord(
    records,
    1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|RESET_COMMITTED|1|BUY|1.0|3900.0|4100.0|4000.0|201");
  AddReducerRecord(
    records,
    2,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|LEVEL_STATE|1|1|READY");
  AddReducerRecord(
    records,
    3,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    StringFormat(
      "v1|REQ-SNAPSHOT-1|%s|%I64d|BUY|LEVEL|1|0.10|1|%s",
      symbol,
      magic_number,
      instance_id));
  AddReducerRecord(
    records,
    4,
    TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
    "v1|REQ-SNAPSHOT-1|DONE|9007199254740995|9007199254740997");
  AddReducerRecord(
    records,
    5,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    "v1|REQ-SNAPSHOT-1|9007199254740997|18446744073709551613|0.10");
  AddReducerRecord(
    records,
    6,
    TGK_GRID_MAPPING_RECORD_POSITION_MAPPING,
    StringFormat(
      "v1|REQ-SNAPSHOT-1|%s|%I64d|LEVEL|1|18446744073709551613|18446744073709551614|0.10|1|%s",
      symbol,
      magic_number,
      instance_id));
}

void BuildAnchorPersistenceFixture(
  STGKGridMappingJournalRecord &records[],
  string symbol,
  long magic_number,
  string instance_id,
  ENUM_TGK_GRID_LEVEL_STATE anchor_state)
{
  AddReducerRecord(
    records,
    1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|RESET_COMMITTED|1|BUY|1.0|3900.0|4100.0|4000.0|201");
  AddReducerRecord(
    records,
    2,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|LEVEL_STATE|1|1|READY");

  if(anchor_state == TGK_GRID_LEVEL_READY)
    return;

  AddReducerRecord(
    records,
    3,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    StringFormat(
      "v1|REQ-A3-ANCHOR|%s|%I64d|BUY|ANCHOR|-1|0.12|1|%s",
      symbol,
      magic_number,
      instance_id));
  AddReducerRecord(
    records,
    4,
    TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
    "v1|REQ-A3-ANCHOR|DONE|50005001|50005002");
  AddReducerRecord(
    records,
    5,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    "v1|REQ-A3-ANCHOR|50005002|30005001|0.12");
  AddReducerRecord(
    records,
    6,
    TGK_GRID_MAPPING_RECORD_POSITION_MAPPING,
    StringFormat(
      "v1|REQ-A3-ANCHOR|%s|%I64d|ANCHOR|-1|30005001|40005001|0.12|1|%s",
      symbol,
      magic_number,
      instance_id));

  if(anchor_state == TGK_GRID_LEVEL_WAIT_ACTIVATION)
    AddReducerRecord(
      records,
      7,
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      "v1|POSITION_CLOSED|30005001|WAIT_ACTIVATION");
}

void AssertAnchorPersistenceState(
  CTGKGridEntryMappingReducer &reducer,
  ENUM_TGK_GRID_LEVEL_STATE expected_state,
  bool expect_mapping,
  string label)
{
  ENUM_TGK_GRID_LEVEL_STATE actual_state = TGK_GRID_LEVEL_READY;
  Tests.AssertTrue(
    label + " Anchor State is queryable",
    reducer.TryGetAnchorState(actual_state));
  Tests.AssertEqualInt(
    label + " Anchor State",
    (int)actual_state,
    (int)expected_state);

  bool has_anchor_mapping = !expect_mapping;
  Tests.AssertTrue(
    label + " Anchor mapping query succeeds",
    reducer.TryGetPositionMapping(true, -1, has_anchor_mapping));
  Tests.AssertEqualInt(
    label + " Anchor Mapping count",
    reducer.PositionCount(),
    expect_mapping ? 1 : 0);
  Tests.AssertEqualInt(
    label + " Anchor mapping presence",
    has_anchor_mapping ? 1 : 0,
    expect_mapping ? 1 : 0);

  if(expect_mapping)
  {
    Tests.AssertEqualString(
      label + " Anchor Position Identifier",
      reducer.PositionIdentifierAt(0),
      "30005001");
    Tests.AssertEqualString(
      label + " Anchor Position Ticket",
      reducer.PositionTicketAt(0),
      "40005001");
    Tests.AssertEqualDouble(
      label + " Anchor Remaining Volume",
      reducer.PositionVolumeAt(0),
      0.12);
  }
}

void AssertRejectedAnchorSnapshot(
  string instance_id,
  string snapshot_instance_id,
  string snapshot_payload,
  long checkpoint_sequence,
  string label)
{
  CTGKGridEntryMappingSnapshotStorage storage;
  Tests.AssertTrue(
    label + " initialize isolated storage",
    storage.Initialize(_Symbol, instance_id));
  Tests.AssertTrue(
    label + " bootstrap corrupt-contract fixture",
    storage.Bootstrap(snapshot_payload, checkpoint_sequence));

  CTGKGridEntryMappingSnapshotStorage restarted_storage;
  Tests.AssertTrue(
    label + " restart storage",
    restarted_storage.Initialize(_Symbol, instance_id));
  string persisted_payload;
  long persisted_checkpoint = -1;
  STGKGridMappingJournalRecord persisted_records[];
  int persisted_record_count = 0;
  long persisted_next_sequence = 0;
  Tests.AssertTrue(
    label + " storage replays committed bytes",
    restarted_storage.Replay(
      persisted_payload,
      persisted_checkpoint,
      persisted_records,
      persisted_record_count,
      persisted_next_sequence));

  CTGKGridEntryMappingReducer reducer;
  Tests.AssertTrue(
    label + " initialize Reducer",
    reducer.Initialize(_Symbol, 710001, snapshot_instance_id));
  Tests.AssertFalse(
    label + " Reducer rejects invalid Anchor Snapshot",
    reducer.RestoreSnapshot(persisted_payload, persisted_checkpoint));
  Tests.AssertEqualInt(
    label + " Reducer fails closed",
    (int)reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);
  Tests.AssertTrue(
    label + " isolated files are cleaned",
    restarted_storage.DeleteAllFilesForTest());
}

void RunAnchorPersistenceIntegrationTests(string instance_id)
{
  Tests.BeginTest("A3-01 READY Anchor Snapshot survives storage restart");
  STGKGridMappingJournalRecord ready_records[];
  BuildAnchorPersistenceFixture(
    ready_records,
    _Symbol,
    710001,
    instance_id + "_A301",
    TGK_GRID_LEVEL_READY);
  CTGKGridEntryMappingReducer ready_source;
  Tests.AssertTrue(
    "A3-01 initialize READY Reducer",
    ready_source.Initialize(_Symbol, 710001, instance_id + "_A301"));
  Tests.AssertTrue(
    "A3-01 replay READY fixture",
    ready_source.Replay(ready_records, ArraySize(ready_records)));
  AssertAnchorPersistenceState(
    ready_source,
    TGK_GRID_LEVEL_READY,
    false,
    "A3-01 source READY");
  string ready_payload;
  Tests.AssertTrue("A3-01 export READY Snapshot", ready_source.ExportSnapshot(ready_payload));

  CTGKGridEntryMappingSnapshotStorage ready_storage;
  Tests.AssertTrue(
    "A3-01 initialize dedicated READY storage",
    ready_storage.Initialize(_Symbol, instance_id + "_A301"));
  Tests.AssertTrue(
    "A3-01 Bootstrap Reducer Snapshot",
    ready_storage.Bootstrap(ready_payload, ready_source.LastSequence()));
  CTGKGridEntryMappingSnapshotStorage ready_restart_storage;
  Tests.AssertTrue(
    "A3-01 restart storage",
    ready_restart_storage.Initialize(_Symbol, instance_id + "_A301"));
  string recovered_payload;
  long recovered_checkpoint = -1;
  STGKGridMappingJournalRecord recovered_records[];
  int recovered_record_count = 0;
  long recovered_next_sequence = 0;
  Tests.AssertTrue(
    "A3-01 replay READY Snapshot after restart",
    ready_restart_storage.Replay(
      recovered_payload,
      recovered_checkpoint,
      recovered_records,
      recovered_record_count,
      recovered_next_sequence));
  CTGKGridEntryMappingReducer ready_restored;
  Tests.AssertTrue(
    "A3-01 initialize restored READY Reducer",
    ready_restored.Initialize(_Symbol, 710001, instance_id + "_A301"));
  Tests.AssertTrue(
    "A3-01 restore through canonical persistence path",
    ready_restored.RestoreSnapshot(recovered_payload, recovered_checkpoint));
  AssertAnchorPersistenceState(
    ready_restored,
    TGK_GRID_LEVEL_READY,
    false,
    "A3-01 restored READY");
  Tests.AssertEqualLong("A3-01 checkpoint", recovered_checkpoint, 2);
  Tests.AssertEqualLong("A3-01 last sequence", ready_restart_storage.LastSequence(), 2);
  Tests.AssertEqualLong("A3-01 next sequence", recovered_next_sequence, 3);
  Tests.AssertTrue("A3-01 clean READY storage", ready_restart_storage.DeleteAllFilesForTest());
  Tests.EndTest();

  Tests.BeginTest("A3-02 ACTIVE Anchor mapping survives storage restart");
  STGKGridMappingJournalRecord active_records[];
  BuildAnchorPersistenceFixture(
    active_records,
    _Symbol,
    710001,
    instance_id + "_A302",
    TGK_GRID_LEVEL_ACTIVE);
  CTGKGridEntryMappingReducer active_source;
  Tests.AssertTrue(
    "A3-02 initialize ACTIVE Reducer",
    active_source.Initialize(_Symbol, 710001, instance_id + "_A302"));
  Tests.AssertTrue(
    "A3-02 replay ACTIVE Anchor mapping",
    active_source.Replay(active_records, ArraySize(active_records)));
  string active_payload;
  Tests.AssertTrue("A3-02 export ACTIVE Snapshot", active_source.ExportSnapshot(active_payload));
  AssertAnchorPersistenceState(active_source, TGK_GRID_LEVEL_ACTIVE, true, "A3-02 source ACTIVE");
  CTGKGridEntryMappingSnapshotStorage active_storage;
  Tests.AssertTrue(
    "A3-02 initialize dedicated ACTIVE storage",
    active_storage.Initialize(_Symbol, instance_id + "_A302"));
  Tests.AssertTrue(
    "A3-02 Bootstrap ACTIVE Snapshot",
    active_storage.Bootstrap(active_payload, active_source.LastSequence()));
  CTGKGridEntryMappingSnapshotStorage active_restart_storage;
  Tests.AssertTrue(
    "A3-02 restart ACTIVE storage",
    active_restart_storage.Initialize(_Symbol, instance_id + "_A302"));
  Tests.AssertTrue(
    "A3-02 replay ACTIVE Snapshot",
    active_restart_storage.Replay(
      recovered_payload,
      recovered_checkpoint,
      recovered_records,
      recovered_record_count,
      recovered_next_sequence));
  CTGKGridEntryMappingReducer active_restored;
  Tests.AssertTrue(
    "A3-02 initialize restored ACTIVE Reducer",
    active_restored.Initialize(_Symbol, 710001, instance_id + "_A302"));
  Tests.AssertTrue(
    "A3-02 restore ACTIVE mapping atomically",
    active_restored.RestoreSnapshot(recovered_payload, recovered_checkpoint));
  AssertAnchorPersistenceState(
    active_restored,
    TGK_GRID_LEVEL_ACTIVE,
    true,
    "A3-02 restored ACTIVE");
  Tests.AssertEqualLong("A3-02 checkpoint", recovered_checkpoint, 6);
  Tests.AssertEqualLong("A3-02 next sequence", recovered_next_sequence, 7);
  Tests.AssertTrue("A3-02 clean ACTIVE storage", active_restart_storage.DeleteAllFilesForTest());
  Tests.EndTest();

  Tests.BeginTest("A3-03 reason-free Full Close persists WAIT_ACTIVATION");
  STGKGridMappingJournalRecord waiting_records[];
  BuildAnchorPersistenceFixture(
    waiting_records,
    _Symbol,
    710001,
    instance_id + "_A303",
    TGK_GRID_LEVEL_WAIT_ACTIVATION);
  CTGKGridEntryMappingReducer waiting_source;
  Tests.AssertTrue(
    "A3-03 initialize Full Close Reducer",
    waiting_source.Initialize(_Symbol, 710001, instance_id + "_A303"));
  Tests.AssertTrue(
    "A3-03 replay reason-free Full Close",
    waiting_source.Replay(waiting_records, ArraySize(waiting_records)));
  string waiting_payload;
  Tests.AssertTrue(
    "A3-03 export WAIT_ACTIVATION Snapshot",
    waiting_source.ExportSnapshot(waiting_payload));
  AssertAnchorPersistenceState(
    waiting_source,
    TGK_GRID_LEVEL_WAIT_ACTIVATION,
    false,
    "A3-03 source WAIT_ACTIVATION");
  CTGKGridEntryMappingSnapshotStorage waiting_storage;
  Tests.AssertTrue(
    "A3-03 initialize dedicated Full Close storage",
    waiting_storage.Initialize(_Symbol, instance_id + "_A303"));
  Tests.AssertTrue(
    "A3-03 Bootstrap post-close Snapshot",
    waiting_storage.Bootstrap(waiting_payload, waiting_source.LastSequence()));
  CTGKGridEntryMappingSnapshotStorage waiting_restart_storage;
  Tests.AssertTrue(
    "A3-03 restart Full Close storage",
    waiting_restart_storage.Initialize(_Symbol, instance_id + "_A303"));
  Tests.AssertTrue(
    "A3-03 replay post-close Snapshot",
    waiting_restart_storage.Replay(
      recovered_payload,
      recovered_checkpoint,
      recovered_records,
      recovered_record_count,
      recovered_next_sequence));
  CTGKGridEntryMappingReducer waiting_restored;
  Tests.AssertTrue(
    "A3-03 initialize restored Full Close Reducer",
    waiting_restored.Initialize(_Symbol, 710001, instance_id + "_A303"));
  Tests.AssertTrue(
    "A3-03 restore Full Close state",
    waiting_restored.RestoreSnapshot(recovered_payload, recovered_checkpoint));
  AssertAnchorPersistenceState(
    waiting_restored,
    TGK_GRID_LEVEL_WAIT_ACTIVATION,
    false,
    "A3-03 restored WAIT_ACTIVATION");
  Tests.AssertEqualLong("A3-03 checkpoint", recovered_checkpoint, 7);
  Tests.AssertTrue("A3-03 clean Full Close storage", waiting_restart_storage.DeleteAllFilesForTest());
  Tests.EndTest();

  Tests.BeginTest("A3-04 Anchor READY Journal replay continues after checkpoint");
  STGKGridMappingJournalRecord activation_waiting_records[];
  BuildAnchorPersistenceFixture(
    activation_waiting_records,
    _Symbol,
    710001,
    instance_id + "_A304",
    TGK_GRID_LEVEL_WAIT_ACTIVATION);
  CTGKGridEntryMappingReducer activation_waiting_source;
  Tests.AssertTrue(
    "A3-04 initialize matching WAIT_ACTIVATION fixture",
    activation_waiting_source.Initialize(_Symbol, 710001, instance_id + "_A304"));
  Tests.AssertTrue(
    "A3-04 replay matching WAIT_ACTIVATION fixture",
    activation_waiting_source.Replay(
      activation_waiting_records,
      ArraySize(activation_waiting_records)));
  string activation_waiting_payload;
  Tests.AssertTrue(
    "A3-04 export matching WAIT_ACTIVATION Snapshot",
    activation_waiting_source.ExportSnapshot(activation_waiting_payload));

  CTGKGridEntryMappingSnapshotStorage activation_storage;
  Tests.AssertTrue(
    "A3-04 initialize activation storage",
    activation_storage.Initialize(_Symbol, instance_id + "_A304"));
  Tests.AssertTrue(
    "A3-04 Bootstrap WAIT_ACTIVATION checkpoint",
    activation_storage.Bootstrap(
      activation_waiting_payload,
      activation_waiting_source.LastSequence()));
  Tests.AssertTrue(
    "A3-04 append READY lifecycle event",
    activation_storage.Append(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      "v1|ANCHOR_STATE|1|READY"));
  CTGKGridEntryMappingSnapshotStorage activation_restart_storage;
  Tests.AssertTrue(
    "A3-04 restart activation storage",
    activation_restart_storage.Initialize(_Symbol, instance_id + "_A304"));
  Tests.AssertTrue(
    "A3-04 replay checkpoint and READY tail",
    activation_restart_storage.Replay(
      recovered_payload,
      recovered_checkpoint,
      recovered_records,
      recovered_record_count,
      recovered_next_sequence));
  Tests.AssertEqualLong("A3-04 checkpoint remains close sequence", recovered_checkpoint, 7);
  Tests.AssertEqualInt("A3-04 one post-checkpoint event", recovered_record_count, 1);
  Tests.AssertEqualLong("A3-04 READY event sequence is N+1", recovered_records[0].sequence, 8);
  Tests.AssertEqualLong("A3-04 next sequence follows READY", recovered_next_sequence, 9);
  CTGKGridEntryMappingReducer activation_restored;
  Tests.AssertTrue(
    "A3-04 initialize activation Reducer",
    activation_restored.Initialize(_Symbol, 710001, instance_id + "_A304"));
  Tests.AssertTrue(
    "A3-04 restore WAIT_ACTIVATION checkpoint",
    activation_restored.RestoreSnapshot(recovered_payload, recovered_checkpoint));
  Tests.AssertTrue(
    "A3-04 replay READY after checkpoint",
    activation_restored.Replay(recovered_records, recovered_record_count));
  AssertAnchorPersistenceState(
    activation_restored,
    TGK_GRID_LEVEL_READY,
    false,
    "A3-04 replayed READY");
  Tests.AssertEqualLong("A3-04 Reducer last sequence", activation_restored.LastSequence(), 8);

  Tests.BeginTest("A3-05 Anchor lifecycle rotates and restarts on one generation");
  string ready_after_activation_payload;
  Tests.AssertTrue(
    "A3-05 export post-activation READY Snapshot",
    activation_restored.ExportSnapshot(ready_after_activation_payload));
  Tests.AssertTrue(
    "A3-05 rotate at READY event sequence",
    activation_restart_storage.Rotate(
      ready_after_activation_payload,
      activation_restored.LastSequence()));
  Tests.AssertEqualLong(
    "A3-05 new checkpoint commits READY event",
    activation_restart_storage.CheckpointSequence(),
    8);
  Tests.AssertTrue(
    "A3-05 generation 2 Snapshot and Journal exist",
    FileIsExist(activation_restart_storage.FileStem() + "_snapshot_2.dat") &&
    FileIsExist(activation_restart_storage.FileStem() + "_journal_2.log"));
  Tests.AssertFalse(
    "A3-05 no old generation file remains",
    FileIsExist(activation_restart_storage.FileStem() + "_snapshot_1.dat") ||
    FileIsExist(activation_restart_storage.FileStem() + "_journal_1.log"));
  CTGKGridEntryMappingSnapshotStorage rotated_restart_storage;
  Tests.AssertTrue(
    "A3-05 restart rotated generation",
    rotated_restart_storage.Initialize(_Symbol, instance_id + "_A304"));
  Tests.AssertTrue(
    "A3-05 replay new committed generation",
    rotated_restart_storage.Replay(
      recovered_payload,
      recovered_checkpoint,
      recovered_records,
      recovered_record_count,
      recovered_next_sequence));
  Tests.AssertEqualLong("A3-05 rotated checkpoint", recovered_checkpoint, 8);
  Tests.AssertEqualInt("A3-05 new Journal is empty", recovered_record_count, 0);
  Tests.AssertEqualLong("A3-05 next sequence is checkpoint plus one", recovered_next_sequence, 9);
  CTGKGridEntryMappingReducer rotated_ready;
  Tests.AssertTrue(
    "A3-05 initialize rotated Reducer",
    rotated_ready.Initialize(_Symbol, 710001, instance_id + "_A304"));
  Tests.AssertTrue(
    "A3-05 restore rotated READY Snapshot",
    rotated_ready.RestoreSnapshot(recovered_payload, recovered_checkpoint));
  AssertAnchorPersistenceState(rotated_ready, TGK_GRID_LEVEL_READY, false, "A3-05 rotated READY");
  Tests.AssertTrue("A3-05 clean rotated storage", rotated_restart_storage.DeleteAllFilesForTest());

  Tests.BeginTest("A3-06 pre-commit rotation failure preserves Anchor generation");
  CTGKGridEntryMappingSnapshotStorage precommit_storage;
  Tests.AssertTrue(
    "A3-06 initialize pre-commit storage",
    precommit_storage.Initialize(_Symbol, instance_id + "_A306"));
  STGKGridMappingJournalRecord precommit_waiting_records[];
  BuildAnchorPersistenceFixture(
    precommit_waiting_records,
    _Symbol,
    710001,
    instance_id + "_A306",
    TGK_GRID_LEVEL_WAIT_ACTIVATION);
  CTGKGridEntryMappingReducer precommit_waiting_source;
  Tests.AssertTrue(
    "A3-06 initialize matching WAIT_ACTIVATION fixture",
    precommit_waiting_source.Initialize(_Symbol, 710001, instance_id + "_A306"));
  Tests.AssertTrue(
    "A3-06 replay matching WAIT_ACTIVATION fixture",
    precommit_waiting_source.Replay(
      precommit_waiting_records,
      ArraySize(precommit_waiting_records)));
  string precommit_waiting_payload;
  Tests.AssertTrue(
    "A3-06 export matching WAIT_ACTIVATION Snapshot",
    precommit_waiting_source.ExportSnapshot(precommit_waiting_payload));
  Tests.AssertTrue(
    "A3-06 Bootstrap WAIT_ACTIVATION generation",
    precommit_storage.Bootstrap(
      precommit_waiting_payload,
      precommit_waiting_source.LastSequence()));
  Tests.AssertTrue(
    "A3-06 append post-checkpoint activation",
    precommit_storage.Append(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      "v1|ANCHOR_STATE|1|READY"));
  CTGKGridEntryMappingReducer precommit_candidate;
  Tests.AssertTrue(
    "A3-06 initialize candidate Reducer",
    precommit_candidate.Initialize(_Symbol, 710001, instance_id + "_A306"));
  Tests.AssertTrue(
    "A3-06 restore prior WAIT checkpoint",
    precommit_candidate.RestoreSnapshot(
      precommit_waiting_payload,
      precommit_waiting_source.LastSequence()));
  STGKGridMappingJournalRecord precommit_activation[];
  ArrayResize(precommit_activation, 1);
  precommit_activation[0].sequence = 8;
  precommit_activation[0].record_type = TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE;
  precommit_activation[0].payload = "v1|ANCHOR_STATE|1|READY";
  Tests.AssertTrue(
    "A3-06 apply pending activation before candidate Snapshot",
    precommit_candidate.Replay(precommit_activation, 1));
  string precommit_candidate_payload;
  Tests.AssertTrue(
    "A3-06 export candidate READY Snapshot",
    precommit_candidate.ExportSnapshot(precommit_candidate_payload));
  AssertAnchorPersistenceState(
    precommit_candidate,
    TGK_GRID_LEVEL_READY,
    false,
    "A3-06 pre-commit candidate READY");
  precommit_storage.SetFailurePointForTest(TGK_GRID_SNAPSHOT_FAIL_AFTER_GENERATION_VALIDATION);
  Tests.AssertFalse(
    "A3-06 injected pre-commit rotation fails",
    precommit_storage.Rotate(precommit_candidate_payload, 8));
  Tests.AssertEqualInt(
    "A3-06 failure enters MAINTENANCE_ERROR",
    (int)precommit_storage.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR);
  CTGKGridEntryMappingSnapshotStorage precommit_restart;
  Tests.AssertTrue(
    "A3-06 restart selects previous committed generation",
    precommit_restart.Initialize(_Symbol, instance_id + "_A306"));
  Tests.AssertEqualInt(
    "A3-06 recovered generation is NORMAL",
    (int)precommit_restart.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_NORMAL);
  Tests.AssertTrue(
    "A3-06 previous checkpoint and Journal recover",
    precommit_restart.Replay(
      recovered_payload,
      recovered_checkpoint,
      recovered_records,
      recovered_record_count,
      recovered_next_sequence));
  Tests.AssertEqualLong("A3-06 old checkpoint is retained", recovered_checkpoint, 7);
  Tests.AssertEqualInt("A3-06 READY Journal tail is retained", recovered_record_count, 1);
  Tests.AssertEqualLong("A3-06 Journal sequence remains eight", recovered_records[0].sequence, 8);
  Tests.AssertTrue(
    "A3-06 previous generation files remain after pre-commit failure",
    FileIsExist(precommit_restart.FileStem() + "_snapshot_1.dat") &&
    FileIsExist(precommit_restart.FileStem() + "_journal_1.log"));
  CTGKGridEntryMappingReducer precommit_recovered;
  Tests.AssertTrue(
    "A3-06 initialize recovered Reducer",
    precommit_recovered.Initialize(_Symbol, 710001, instance_id + "_A306"));
  Tests.AssertTrue(
    "A3-06 restore old Snapshot",
    precommit_recovered.RestoreSnapshot(recovered_payload, recovered_checkpoint));
  Tests.AssertTrue(
    "A3-06 replay preserved activation Journal record",
    precommit_recovered.Replay(recovered_records, recovered_record_count));
  AssertAnchorPersistenceState(
    precommit_recovered,
    TGK_GRID_LEVEL_READY,
    false,
    "A3-06 recovered READY");
  Tests.AssertTrue("A3-06 cleanup removes candidate generation", !FileIsExist(
    precommit_restart.FileStem() + "_snapshot_2.dat"));
  Tests.AssertTrue("A3-06 clean preserved storage", precommit_restart.DeleteAllFilesForTest());

  Tests.BeginTest("A3-07 post-commit cleanup failure recovers Anchor generation");
  STGKGridMappingJournalRecord postcommit_active_records[];
  BuildAnchorPersistenceFixture(
    postcommit_active_records,
    _Symbol,
    710001,
    instance_id + "_A307",
    TGK_GRID_LEVEL_ACTIVE);
  CTGKGridEntryMappingReducer postcommit_active_source;
  Tests.AssertTrue(
    "A3-07 initialize matching ACTIVE fixture",
    postcommit_active_source.Initialize(_Symbol, 710001, instance_id + "_A307"));
  Tests.AssertTrue(
    "A3-07 replay matching ACTIVE fixture",
    postcommit_active_source.Replay(
      postcommit_active_records,
      ArraySize(postcommit_active_records)));
  string postcommit_active_payload;
  Tests.AssertTrue(
    "A3-07 export matching ACTIVE Snapshot",
    postcommit_active_source.ExportSnapshot(postcommit_active_payload));
  AssertAnchorPersistenceState(
    postcommit_active_source,
    TGK_GRID_LEVEL_ACTIVE,
    true,
    "A3-07 source ACTIVE");

  CTGKGridEntryMappingSnapshotStorage postcommit_storage;
  Tests.AssertTrue(
    "A3-07 initialize post-commit storage",
    postcommit_storage.Initialize(_Symbol, instance_id + "_A307"));
  Tests.AssertTrue(
    "A3-07 Bootstrap ACTIVE Anchor generation",
    postcommit_storage.Bootstrap(
      postcommit_active_payload,
      postcommit_active_source.LastSequence()));
  postcommit_storage.SetFailurePointForTest(TGK_GRID_SNAPSHOT_FAIL_BEFORE_CLEANUP);
  Tests.AssertFalse(
    "A3-07 failure after Manifest commit is reported",
    postcommit_storage.Rotate(
      postcommit_active_payload,
      postcommit_active_source.LastSequence()));
  Tests.AssertEqualLong(
    "A3-07 committed checkpoint advances",
    postcommit_storage.CheckpointSequence(),
    6);
  CTGKGridEntryMappingSnapshotStorage postcommit_restart;
  Tests.AssertTrue(
    "A3-07 restart repeats cleanup",
    postcommit_restart.Initialize(_Symbol, instance_id + "_A307"));
  Tests.AssertEqualInt(
    "A3-07 restarted storage is NORMAL",
    (int)postcommit_restart.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_NORMAL);
  Tests.AssertTrue(
    "A3-07 new Manifest generation is replayed",
    postcommit_restart.Replay(
      recovered_payload,
      recovered_checkpoint,
      recovered_records,
      recovered_record_count,
      recovered_next_sequence));
  Tests.AssertEqualLong("A3-07 committed checkpoint is six", recovered_checkpoint, 6);
  Tests.AssertEqualInt("A3-07 committed Journal is empty", recovered_record_count, 0);
  Tests.AssertTrue(
    "A3-07 new generation is active after cleanup retry",
    FileIsExist(postcommit_restart.FileStem() + "_snapshot_2.dat") &&
    FileIsExist(postcommit_restart.FileStem() + "_journal_2.log"));
  Tests.AssertFalse(
    "A3-07 previous generation is removed after cleanup retry",
    FileIsExist(postcommit_restart.FileStem() + "_snapshot_1.dat") ||
    FileIsExist(postcommit_restart.FileStem() + "_journal_1.log"));
  CTGKGridEntryMappingReducer postcommit_recovered;
  Tests.AssertTrue(
    "A3-07 initialize restored ACTIVE Reducer",
    postcommit_recovered.Initialize(_Symbol, 710001, instance_id + "_A307"));
  Tests.AssertTrue(
    "A3-07 restore ACTIVE Snapshot after cleanup retry",
    postcommit_recovered.RestoreSnapshot(recovered_payload, recovered_checkpoint));
  AssertAnchorPersistenceState(
    postcommit_recovered,
    TGK_GRID_LEVEL_ACTIVE,
    true,
    "A3-07 recovered ACTIVE");
  Tests.AssertTrue("A3-07 clean post-commit storage", postcommit_restart.DeleteAllFilesForTest());

  Tests.BeginTest("A3-08 malformed and conflicting Anchor snapshots fail closed");
  string missing_state_payload = ready_payload;
  Tests.AssertEqualInt(
    "A3-08 remove required Anchor State field",
    StringReplace(missing_state_payload, "|200|0", "|200"),
    1);
  AssertRejectedAnchorSnapshot(
    instance_id + "_A308_MISSING",
    instance_id + "_A301",
    missing_state_payload,
    ready_source.LastSequence(),
    "A3-08 missing Anchor State");

  string invalid_state_payload = ready_payload;
  Tests.AssertEqualInt(
    "A3-08 set invalid Anchor State value",
    StringReplace(invalid_state_payload, "|200|0", "|200|99"),
    1);
  AssertRejectedAnchorSnapshot(
    instance_id + "_A308_INVALID",
    instance_id + "_A301",
    invalid_state_payload,
    ready_source.LastSequence(),
    "A3-08 invalid Anchor State");

  string active_without_mapping_payload = ready_payload;
  Tests.AssertEqualInt(
    "A3-08 set ACTIVE without a Mapping",
    StringReplace(active_without_mapping_payload, "|200|0", "|200|1"),
    1);
  AssertRejectedAnchorSnapshot(
    instance_id + "_A308_ACTIVE_NO_MAP",
    instance_id + "_A301",
    active_without_mapping_payload,
    ready_source.LastSequence(),
    "A3-08 ACTIVE without Mapping");

  string ready_with_mapping_payload = active_payload;
  Tests.AssertEqualInt(
    "A3-08 set READY while Mapping remains serialized",
    StringReplace(ready_with_mapping_payload, "|200|1|R", "|200|0|R"),
    1);
  AssertRejectedAnchorSnapshot(
    instance_id + "_A308_READY_MAPPED",
    instance_id + "_A302",
    ready_with_mapping_payload,
    active_source.LastSequence(),
    "A3-08 READY with Mapping");
  Tests.EndTest();

  Tests.BeginTest("A3-09 replay and repeated rotation preserve one activation result");
  STGKGridMappingJournalRecord repeated_waiting_records[];
  BuildAnchorPersistenceFixture(
    repeated_waiting_records,
    _Symbol,
    710001,
    instance_id + "_A309",
    TGK_GRID_LEVEL_WAIT_ACTIVATION);
  CTGKGridEntryMappingReducer repeated_waiting_source;
  Tests.AssertTrue(
    "A3-09 initialize matching WAIT_ACTIVATION fixture",
    repeated_waiting_source.Initialize(_Symbol, 710001, instance_id + "_A309"));
  Tests.AssertTrue(
    "A3-09 replay matching WAIT_ACTIVATION fixture",
    repeated_waiting_source.Replay(
      repeated_waiting_records,
      ArraySize(repeated_waiting_records)));
  string repeated_waiting_payload;
  Tests.AssertTrue(
    "A3-09 export matching WAIT_ACTIVATION Snapshot",
    repeated_waiting_source.ExportSnapshot(repeated_waiting_payload));

  CTGKGridEntryMappingSnapshotStorage repeated_storage;
  Tests.AssertTrue(
    "A3-09 initialize repeated-activation storage",
    repeated_storage.Initialize(_Symbol, instance_id + "_A309"));
  Tests.AssertTrue(
    "A3-09 Bootstrap WAIT checkpoint",
    repeated_storage.Bootstrap(
      repeated_waiting_payload,
      repeated_waiting_source.LastSequence()));
  Tests.AssertTrue(
    "A3-09 append one READY transition",
    repeated_storage.Append(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      "v1|ANCHOR_STATE|1|READY"));
  CTGKGridEntryMappingSnapshotStorage repeated_restart;
  Tests.AssertTrue(
    "A3-09 restart after activation append",
    repeated_restart.Initialize(_Symbol, instance_id + "_A309"));
  Tests.AssertTrue(
    "A3-09 replay activation tail",
    repeated_restart.Replay(
      recovered_payload,
      recovered_checkpoint,
      recovered_records,
      recovered_record_count,
      recovered_next_sequence));
  CTGKGridEntryMappingReducer repeated_reducer;
  Tests.AssertTrue(
    "A3-09 initialize repeated Reducer",
    repeated_reducer.Initialize(_Symbol, 710001, instance_id + "_A309"));
  Tests.AssertTrue(
    "A3-09 restore WAIT checkpoint",
    repeated_reducer.RestoreSnapshot(recovered_payload, recovered_checkpoint));
  Tests.AssertTrue(
    "A3-09 replay activation exactly once",
    repeated_reducer.Replay(recovered_records, recovered_record_count));
  AssertAnchorPersistenceState(
    repeated_reducer,
    TGK_GRID_LEVEL_READY,
    false,
    "A3-09 after first activation replay");
  string repeated_ready_payload;
  Tests.AssertTrue(
    "A3-09 export resulting READY Snapshot",
    repeated_reducer.ExportSnapshot(repeated_ready_payload));

  CTGKGridEntryMappingReducer duplicate_reducer;
  Tests.AssertTrue(
    "A3-09 initialize isolated duplicate-check Reducer",
    duplicate_reducer.Initialize(_Symbol, 710001, instance_id + "_A309"));
  Tests.AssertTrue(
    "A3-09 restore duplicate-check WAIT checkpoint",
    duplicate_reducer.RestoreSnapshot(recovered_payload, recovered_checkpoint));
  Tests.AssertTrue(
    "A3-09 replay activation before duplicate attempt",
    duplicate_reducer.Replay(recovered_records, recovered_record_count));
  STGKGridMappingJournalRecord duplicate_activation[];
  ArrayResize(duplicate_activation, 1);
  duplicate_activation[0].sequence = 9;
  duplicate_activation[0].record_type = TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE;
  duplicate_activation[0].payload = "v1|ANCHOR_STATE|1|READY";
  Tests.AssertFalse(
    "A3-09 duplicate activation is rejected",
    duplicate_reducer.Replay(duplicate_activation, ArraySize(duplicate_activation)));
  Tests.AssertEqualLong(
    "A3-09 rejected duplicate does not advance sequence",
    duplicate_reducer.LastSequence(),
    8);
  Tests.AssertEqualInt(
    "A3-09 rejected duplicate enters RECOVERY_ERROR",
    (int)duplicate_reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);
  Tests.AssertEqualInt(
    "A3-09 rejected duplicate creates no Anchor mapping",
    duplicate_reducer.PositionCount(),
    0);
  Tests.AssertTrue(
    "A3-09 first rotation commits activation",
    repeated_restart.Rotate(repeated_ready_payload, repeated_reducer.LastSequence()));
  Tests.AssertTrue(
    "A3-09 repeated rotation is idempotent",
    repeated_restart.Rotate(repeated_ready_payload, repeated_reducer.LastSequence()));
  CTGKGridEntryMappingSnapshotStorage repeated_final_storage;
  Tests.AssertTrue(
    "A3-09 restart after repeated rotation",
    repeated_final_storage.Initialize(_Symbol, instance_id + "_A309"));
  Tests.AssertTrue(
    "A3-09 replay final committed generation",
    repeated_final_storage.Replay(
      recovered_payload,
      recovered_checkpoint,
      recovered_records,
      recovered_record_count,
      recovered_next_sequence));
  Tests.AssertEqualLong("A3-09 checkpoint has no duplicate sequence", recovered_checkpoint, 8);
  Tests.AssertEqualInt("A3-09 no duplicate Journal events", recovered_record_count, 0);
  CTGKGridEntryMappingReducer repeated_final_reducer;
  Tests.AssertTrue(
    "A3-09 initialize final Reducer",
    repeated_final_reducer.Initialize(_Symbol, 710001, instance_id + "_A309"));
  Tests.AssertTrue(
    "A3-09 restore final READY state",
    repeated_final_reducer.RestoreSnapshot(recovered_payload, recovered_checkpoint));
  AssertAnchorPersistenceState(
    repeated_final_reducer,
    TGK_GRID_LEVEL_READY,
    false,
    "A3-09 final READY");
  Tests.AssertTrue("A3-09 clean final storage", repeated_final_storage.DeleteAllFilesForTest());
}

void RunPreCommitFailureCase(
  string instance_id,
  string test_name,
  ENUM_TGK_GRID_SNAPSHOT_FAILURE_POINT failure_point)
{
  Tests.BeginTest(test_name);

  CTGKGridEntryMappingSnapshotStorage storage;
  Tests.AssertTrue(
    "initialize isolated failure-test storage",
    storage.Initialize(_Symbol, instance_id));
  Tests.AssertTrue(
    "bootstrap known committed generation",
    storage.Bootstrap("v1|state|committed", 0));
  Tests.AssertTrue(
    "append event before interrupted Rotation",
    storage.Append(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      "v1|LEVEL_STATE|1|1|READY"));

  storage.SetFailurePointForTest(failure_point);
  Tests.AssertFalse(
    "injected pre-commit interruption is reported",
    storage.Rotate("v1|state|uncommitted", 1));
  Tests.AssertEqualInt(
    "pre-commit failure enters MAINTENANCE_ERROR",
    (int)storage.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR);
  Tests.AssertFalse(
    "MAINTENANCE_ERROR blocks a new Entry Intent",
    storage.Append(
      TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
      "v1|REQ-BLOCKED|XAUUSD|710001|BUY|LEVEL|1|0.10|1|UT-INSTANCE"));
  Tests.AssertTrue(
    "MAINTENANCE_ERROR still permits an existing-state update",
    storage.Append(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      "v1|LEVEL_STATE|1|1|READY"));

  CTGKGridEntryMappingSnapshotStorage recovered;
  Tests.AssertTrue(
    "restart recovers the previous Manifest",
    recovered.Initialize(_Symbol, instance_id));
  Tests.AssertEqualInt(
    "previous committed generation remains NORMAL",
    (int)recovered.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_NORMAL);

  string snapshot_payload;
  long checkpoint_sequence = -1;
  STGKGridMappingJournalRecord records[];
  int record_count = 0;
  long next_sequence = 0;
  Tests.AssertTrue(
    "previous Snapshot and Journal remain recoverable",
    recovered.Replay(
      snapshot_payload,
      checkpoint_sequence,
      records,
      record_count,
      next_sequence));
  Tests.AssertEqualString(
    "uncommitted Snapshot is never selected",
    snapshot_payload,
    "v1|state|committed");
  Tests.AssertEqualLong("previous checkpoint remains zero", checkpoint_sequence, 0);
  Tests.AssertEqualInt("previous and reconciliation Journal events are retained", record_count, 2);
  if(record_count == 2)
    Tests.AssertEqualLong("reconciliation event follows existing Journal", records[1].sequence, 2);
  Tests.AssertTrue(
    "startup cleanup removes uncommitted generation and temporary files",
    !FileIsExist(recovered.FileStem() + "_snapshot_2.dat") &&
    !FileIsExist(recovered.FileStem() + "_journal_2.log") &&
    !FileIsExist(recovered.FileStem() + "_snapshot_2.tmp") &&
    !FileIsExist(recovered.FileStem() + "_journal_2.tmp") &&
    !FileIsExist(recovered.FileStem() + "_manifest_B.tmp"));

  Tests.AssertTrue("clean isolated failure-test files", recovered.DeleteAllFilesForTest());
  Tests.EndTest();
}

int OnInit()
{
  Tests.BeginSuite("TGK Grid Entry Mapping Snapshot Storage");

  string instance_id = StringFormat(
    "UTSNAP%d_%I64d",
    (int)ChartID(),
    (long)TimeLocal());
  string broken_instance_id = instance_id + "_BROKEN";
  string oversized_instance_id = instance_id + "_OVERSIZED";
  string journal_full_instance_id = instance_id + "_JOURNAL_FULL";
  string reducer_instance_id = instance_id + "_REDUCER";

  RunAnchorPersistenceIntegrationTests(instance_id);

  Tests.BeginTest("Reducer Current State Snapshot round-trips and resumes from checkpoint");
  STGKGridMappingJournalRecord reducer_fixture[];
  BuildMappedReducerFixture(
    reducer_fixture,
    _Symbol,
    710001,
    reducer_instance_id);

  CTGKGridEntryMappingReducer source_reducer;
  Tests.AssertTrue(
    "initialize source Reducer",
    source_reducer.Initialize(_Symbol, 710001, reducer_instance_id));
  Tests.AssertTrue(
    "build source Current State",
    source_reducer.Replay(reducer_fixture, ArraySize(reducer_fixture)));

  string reducer_snapshot_payload;
  Tests.AssertTrue(
    "serialize Reducer Current State",
    source_reducer.ExportSnapshot(reducer_snapshot_payload));
  Tests.AssertEqualInt(
    "source Snapshot includes every non-anchor Grid Level",
    source_reducer.LevelCount(),
    200);
  Tests.AssertTrue(
    "serialized snapshot contains no Deal Association history",
    source_reducer.DealCount() == 0);

  CTGKGridEntryMappingReducer restored_reducer;
  Tests.AssertTrue(
    "initialize destination Reducer",
    restored_reducer.Initialize(_Symbol, 710001, reducer_instance_id));
  Tests.AssertTrue(
    "restore typed Current State Snapshot",
    restored_reducer.RestoreSnapshot(
      reducer_snapshot_payload,
      source_reducer.LastSequence()));
  Tests.AssertEqualLong(
    "restored Reducer checkpoint",
    restored_reducer.LastSequence(),
    source_reducer.LastSequence());
  Tests.AssertEqualInt("restored active Position count", restored_reducer.PositionCount(), 1);
  Tests.AssertEqualInt("restored Grid Level State count", restored_reducer.LevelCount(), 200);
  Tests.AssertEqualInt("restored Deal history count", restored_reducer.DealCount(), 0);
  Tests.AssertEqualInt(
    "restored Level State remains ACTIVE",
    restored_reducer.LevelStateAt(1),
    (int)TGK_GRID_LEVEL_ACTIVE);
  Tests.AssertEqualString(
    "restored large Position Identifier",
    restored_reducer.PositionIdentifierAt(0),
    "18446744073709551613");

  CTGKGridEntryMappingReducer wrong_identity_reducer;
  Tests.AssertTrue(
    "initialize wrong-identity Reducer",
    wrong_identity_reducer.Initialize(
      _Symbol,
      710001,
      reducer_instance_id + "_WRONG"));
  Tests.AssertFalse(
    "Snapshot from another Instance is rejected",
    wrong_identity_reducer.RestoreSnapshot(
      reducer_snapshot_payload,
      source_reducer.LastSequence()));
  Tests.AssertEqualInt(
    "wrong Snapshot identity enters RECOVERY_ERROR",
    (int)wrong_identity_reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);

  CTGKGridEntryMappingReducer wrong_checkpoint_reducer;
  Tests.AssertTrue(
    "initialize wrong-checkpoint Reducer",
    wrong_checkpoint_reducer.Initialize(_Symbol, 710001, reducer_instance_id));
  Tests.AssertFalse(
    "Snapshot checkpoint mismatch is rejected",
    wrong_checkpoint_reducer.RestoreSnapshot(
      reducer_snapshot_payload,
      source_reducer.LastSequence() - 1));
  Tests.AssertEqualInt(
    "checkpoint mismatch enters RECOVERY_ERROR",
    (int)wrong_checkpoint_reducer.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);

  STGKGridMappingJournalRecord pending_fixture[];
  AddReducerRecord(
    pending_fixture,
    1,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|RESET_COMMITTED|1|BUY|1.0|3900.0|4100.0|4000.0|201");
  AddReducerRecord(
    pending_fixture,
    2,
    TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
    "v1|LEVEL_STATE|1|1|READY");
  AddReducerRecord(
    pending_fixture,
    3,
    TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
    StringFormat(
      "v1|REQ-PENDING-SNAPSHOT|%s|710001|BUY|LEVEL|1|0.10|1|%s",
      _Symbol,
      reducer_instance_id));
  AddReducerRecord(
    pending_fixture,
    4,
    TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
    "v1|REQ-PENDING-SNAPSHOT|PLACED|9007199254740995|0");
  AddReducerRecord(
    pending_fixture,
    5,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    "v1|REQ-PENDING-SNAPSHOT|9007199254740997|18446744073709551613|0.04");
  AddReducerRecord(
    pending_fixture,
    6,
    TGK_GRID_MAPPING_RECORD_DEAL_ASSOCIATION,
    "v1|REQ-PENDING-SNAPSHOT|9007199254740998|18446744073709551613|0.06");

  CTGKGridEntryMappingReducer pending_reducer;
  Tests.AssertTrue(
    "initialize pending Request Reducer",
    pending_reducer.Initialize(_Symbol, 710001, reducer_instance_id));
  Tests.AssertTrue(
    "replay unresolved Request with partial-fill Deals",
    pending_reducer.Replay(pending_fixture, ArraySize(pending_fixture)));
  string pending_snapshot_payload;
  Tests.AssertTrue(
    "serialize unresolved Request and its Deal Associations",
    pending_reducer.ExportSnapshot(pending_snapshot_payload));

  CTGKGridEntryMappingReducer restored_pending_reducer;
  Tests.AssertTrue(
    "initialize pending Snapshot destination",
    restored_pending_reducer.Initialize(_Symbol, 710001, reducer_instance_id));
  Tests.AssertTrue(
    "restore unresolved Request Snapshot",
    restored_pending_reducer.RestoreSnapshot(pending_snapshot_payload, 6));
  Tests.AssertTrue(
    "unresolved Request remains pending after Snapshot",
    restored_pending_reducer.HasUnresolvedRequest());
  Tests.AssertEqualString(
    "unresolved Request ID survives Snapshot",
    restored_pending_reducer.UnresolvedRequestId(),
    "REQ-PENDING-SNAPSHOT");
  Tests.AssertEqualInt(
    "both recovery-critical Deal Associations survive Snapshot",
    restored_pending_reducer.DealCount(),
    2);
  Tests.AssertEqualInt(
    "unresolved Request does not become a Position",
    restored_pending_reducer.PositionCount(),
    0);

  CTGKGridEntryMappingSnapshotStorage reducer_storage;
  Tests.AssertTrue(
    "initialize storage for typed Reducer Snapshot",
    reducer_storage.Initialize(_Symbol, reducer_instance_id));
  Tests.AssertTrue(
    "bootstrap storage with serialized Current State",
    reducer_storage.Bootstrap(
      reducer_snapshot_payload,
      source_reducer.LastSequence()));
  Tests.AssertTrue(
    "append event after Snapshot checkpoint",
    reducer_storage.Append(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      "v1|POSITION_TICKET|18446744073709551613|18446744073709551610"));

  CTGKGridEntryMappingSnapshotStorage reducer_storage_recovered;
  Tests.AssertTrue(
    "recover typed Snapshot storage",
    reducer_storage_recovered.Initialize(_Symbol, reducer_instance_id));
  string recovered_reducer_payload;
  long recovered_reducer_checkpoint = 0;
  STGKGridMappingJournalRecord recovered_reducer_records[];
  int recovered_reducer_record_count = 0;
  long recovered_reducer_next_sequence = 0;
  Tests.AssertTrue(
    "read typed Snapshot and post-checkpoint Journal",
    reducer_storage_recovered.Replay(
      recovered_reducer_payload,
      recovered_reducer_checkpoint,
      recovered_reducer_records,
      recovered_reducer_record_count,
      recovered_reducer_next_sequence));

  CTGKGridEntryMappingReducer fully_restored_reducer;
  Tests.AssertTrue(
    "initialize fully restored Reducer",
    fully_restored_reducer.Initialize(_Symbol, 710001, reducer_instance_id));
  Tests.AssertTrue(
    "restore Reducer Snapshot",
    fully_restored_reducer.RestoreSnapshot(
      recovered_reducer_payload,
      recovered_reducer_checkpoint));
  Tests.AssertTrue(
    "replay Journal from checkpoint plus one",
    fully_restored_reducer.Replay(
      recovered_reducer_records,
      recovered_reducer_record_count));
  Tests.AssertEqualString(
    "Position Ticket update after checkpoint is applied",
    fully_restored_reducer.PositionTicketAt(0),
    "18446744073709551610");
  Tests.AssertTrue(
    "clean typed Reducer Snapshot files",
    reducer_storage_recovered.DeleteAllFilesForTest());
  Tests.EndTest();

  CTGKGridEntryMappingSnapshotStorage storage;
  Tests.BeginTest("Bootstrap creates a committed Snapshot, Journal and Manifest");
  Tests.AssertTrue(
    "initialize new storage identity",
    storage.Initialize(_Symbol, instance_id));
  Tests.AssertFalse(
    "new storage has no committed generation",
    storage.HasCommittedState());
  Tests.AssertTrue(
    "bootstrap initial generation",
    storage.Bootstrap("v1|current_state|initial", 0));
  Tests.AssertTrue("generation is committed", storage.HasCommittedState());
  Tests.AssertEqualLong("initial checkpoint", storage.CheckpointSequence(), 0);
  Tests.AssertEqualLong("initial last sequence", storage.LastSequence(), 0);

  string stem = storage.FileStem();
  Tests.AssertTrue(
    "generation 1 Snapshot exists",
    FileIsExist(stem + "_snapshot_1.dat"));
  Tests.AssertTrue(
    "generation 1 Journal exists",
    FileIsExist(stem + "_journal_1.log"));
  Tests.AssertTrue(
    "Manifest A exists",
    FileIsExist(stem + "_manifest_A.dat"));
  Tests.AssertFalse(
    "Manifest B is not needed for initial commit",
    FileIsExist(stem + "_manifest_B.dat"));
  Tests.EndTest();

  Tests.BeginTest("Append and Replay use the Snapshot checkpoint as Journal base");
  Tests.AssertTrue(
    "append first post-bootstrap event",
    storage.Append(
      TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
      "v1|REQ-1|XAUUSD|710001|BUY|ANCHOR|-1|0.10|1|UT-INSTANCE"));

  string snapshot_payload;
  long checkpoint_sequence = -1;
  STGKGridMappingJournalRecord records[];
  int record_count = 0;
  long next_sequence = 0;

  int tail_handle = FileOpen(
    stem + "_journal_1.log",
    FILE_READ | FILE_WRITE | FILE_BIN);
  bool partial_tail_written = false;
  if(tail_handle != INVALID_HANDLE)
  {
    FileSeek(tail_handle, 0, SEEK_END);
    uchar partial_tail[];
    int partial_count = StringToCharArray(
      "TGKJ|1|2|",
      partial_tail,
      0,
      WHOLE_ARRAY,
      CP_UTF8);
    if(partial_count > 1)
    {
      ArrayResize(partial_tail, partial_count - 1);
      partial_tail_written = FileWriteArray(
        tail_handle,
        partial_tail,
        0,
        (uint)ArraySize(partial_tail)) == ArraySize(partial_tail);
      if(partial_tail_written)
      {
        ResetLastError();
        FileFlush(tail_handle);
        partial_tail_written = GetLastError() == 0;
      }
    }
    FileClose(tail_handle);
  }
  Tests.AssertTrue("incomplete final bytes are written", partial_tail_written);
  Tests.AssertTrue(
    "Replay ignores an incomplete final Journal record",
    storage.Replay(
      snapshot_payload,
      checkpoint_sequence,
      records,
      record_count,
      next_sequence));
  Tests.AssertEqualInt("incomplete tail is not applied", record_count, 1);
  Tests.AssertEqualLong("next sequence remains two", next_sequence, 2);

  Tests.AssertTrue(
    "next Append repairs incomplete tail and succeeds",
    storage.Append(
      TGK_GRID_MAPPING_RECORD_EXECUTION_RESULT,
      "v1|REQ-1|PLACED|9007199254740995|0"));
  Tests.AssertTrue(
    "Replay current generation",
    storage.Replay(
      snapshot_payload,
      checkpoint_sequence,
      records,
      record_count,
      next_sequence));
  Tests.AssertEqualString(
    "Snapshot payload round-trips",
    snapshot_payload,
    "v1|current_state|initial");
  Tests.AssertEqualLong("checkpoint remains zero", checkpoint_sequence, 0);
  Tests.AssertEqualInt("two Journal events restored", record_count, 2);
  Tests.AssertEqualLong("next sequence is three", next_sequence, 3);
  if(record_count == 2)
  {
    Tests.AssertEqualLong("first event sequence", records[0].sequence, 1);
    Tests.AssertEqualLong("second event sequence", records[1].sequence, 2);
  }
  Tests.EndTest();

  Tests.BeginTest("Rotation commits Snapshot N and starts Journal at N+1");
  Tests.AssertTrue(
    "rotate at the latest applied sequence",
    storage.Rotate("v1|current_state|checkpoint-2", 2));
  Tests.AssertEqualLong("checkpoint advances to two", storage.CheckpointSequence(), 2);
  Tests.AssertEqualLong("next sequence remains three", storage.LastSequence() + 1, 3);
  Tests.AssertTrue(
    "new generation 2 Snapshot exists",
    FileIsExist(stem + "_snapshot_2.dat"));
  Tests.AssertTrue(
    "new generation 2 Journal exists",
    FileIsExist(stem + "_journal_2.log"));
  Tests.AssertFalse(
    "old generation 1 Snapshot cleaned",
    FileIsExist(stem + "_snapshot_1.dat"));
  Tests.AssertFalse(
    "old generation 1 Journal cleaned",
    FileIsExist(stem + "_journal_1.log"));
  Tests.AssertTrue(
    "both fixed Manifest slots exist",
    FileIsExist(stem + "_manifest_A.dat") &&
    FileIsExist(stem + "_manifest_B.dat"));

  ArrayFree(records);
  record_count = 0;
  Tests.AssertTrue(
    "Replay rotated generation",
    storage.Replay(
      snapshot_payload,
      checkpoint_sequence,
      records,
      record_count,
      next_sequence));
  Tests.AssertEqualString(
    "rotated Snapshot payload restored",
    snapshot_payload,
    "v1|current_state|checkpoint-2");
  Tests.AssertEqualLong("rotated checkpoint restored", checkpoint_sequence, 2);
  Tests.AssertEqualInt("new Journal starts empty", record_count, 0);
  Tests.AssertEqualLong("new Journal base sequence is three", next_sequence, 3);
  Tests.EndTest();

  Tests.BeginTest("Restart restores Snapshot and replays only events after checkpoint");
  Tests.AssertTrue(
    "append event after rotation",
    storage.Append(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      "v1|LEVEL_STATE|1|1|READY"));

  CTGKGridEntryMappingSnapshotStorage restored_storage;
  Tests.AssertTrue(
    "initialize restored storage",
    restored_storage.Initialize(_Symbol, instance_id));
  Tests.AssertEqualInt(
    "recovery status is NORMAL",
    (int)restored_storage.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_NORMAL);
  Tests.AssertTrue(
    "restore Snapshot and Journal",
    restored_storage.Replay(
      snapshot_payload,
      checkpoint_sequence,
      records,
      record_count,
      next_sequence));
  Tests.AssertEqualString(
    "restored checkpoint payload",
    snapshot_payload,
    "v1|current_state|checkpoint-2");
  Tests.AssertEqualLong("restored checkpoint sequence", checkpoint_sequence, 2);
  Tests.AssertEqualInt("only post-checkpoint event is replayed", record_count, 1);
  Tests.AssertEqualLong("post-checkpoint event starts at sequence three", records[0].sequence, 3);
  Tests.AssertEqualLong("next sequence is four", next_sequence, 4);
  Tests.EndTest();

  Tests.BeginTest("Crash before Manifest Commit preserves the previous Generation");
  restored_storage.SetFailurePointForTest(
    TGK_GRID_SNAPSHOT_FAIL_AFTER_SNAPSHOT_TEMP_WRITE);
  Tests.AssertFalse(
    "interrupted Rotation reports failure",
    restored_storage.Rotate("v1|current_state|uncommitted", 3));
  Tests.AssertEqualInt(
    "interrupted Rotation enters MAINTENANCE_ERROR",
    (int)restored_storage.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR);

  CTGKGridEntryMappingSnapshotStorage precommit_recovery;
  Tests.AssertTrue(
    "restart after pre-commit interruption",
    precommit_recovery.Initialize(_Symbol, instance_id));
  Tests.AssertEqualInt(
    "previous committed generation remains NORMAL",
    (int)precommit_recovery.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_NORMAL);
  Tests.AssertTrue(
    "previous committed state is recoverable",
    precommit_recovery.Replay(
      snapshot_payload,
      checkpoint_sequence,
      records,
      record_count,
      next_sequence));
  Tests.AssertEqualString(
    "uncommitted Snapshot is not selected",
    snapshot_payload,
    "v1|current_state|checkpoint-2");
  Tests.AssertEqualLong("previous checkpoint remains two", checkpoint_sequence, 2);
  Tests.AssertEqualInt("previous Journal event remains available", record_count, 1);
  Tests.AssertTrue(
    "retry Rotation reuses and replaces orphan candidate generation",
    precommit_recovery.Rotate("v1|current_state|retry-3", 3));
  Tests.EndTest();

  Tests.BeginTest("Crash after Manifest Commit recovers the new Generation");
  Tests.AssertTrue(
    "append event to generation 3",
    precommit_recovery.Append(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      "v1|POSITION_TICKET|18446744073709551613|18446744073709551610"));
  precommit_recovery.SetFailurePointForTest(
    TGK_GRID_SNAPSHOT_FAIL_BEFORE_CLEANUP);
  Tests.AssertFalse(
    "post-commit interruption reports incomplete maintenance",
    precommit_recovery.Rotate("v1|current_state|committed-4", 4));
  Tests.AssertEqualInt(
    "post-commit interruption enters MAINTENANCE_ERROR",
    (int)precommit_recovery.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR);

  CTGKGridEntryMappingSnapshotStorage postcommit_recovery;
  Tests.AssertTrue(
    "restart after Manifest Commit",
    postcommit_recovery.Initialize(_Symbol, instance_id));
  Tests.AssertEqualInt(
    "new committed generation recovers NORMAL after cleanup",
    (int)postcommit_recovery.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_NORMAL);
  Tests.AssertTrue(
    "new committed Snapshot is selected",
    postcommit_recovery.Replay(
      snapshot_payload,
      checkpoint_sequence,
      records,
      record_count,
      next_sequence));
  Tests.AssertEqualString(
    "post-commit Snapshot wins",
    snapshot_payload,
    "v1|current_state|committed-4");
  Tests.AssertEqualLong("post-commit checkpoint is four", checkpoint_sequence, 4);
  Tests.AssertEqualInt("post-commit Journal starts empty", record_count, 0);
  Tests.EndTest();

  Tests.BeginTest("Crash during Cleanup is repeatable after Restart");
  postcommit_recovery.SetFailurePointForTest(
    TGK_GRID_SNAPSHOT_FAIL_AFTER_OLD_SNAPSHOT_DELETE);
  Tests.AssertFalse(
    "interrupted Cleanup reports failure",
    postcommit_recovery.Rotate("v1|current_state|cleanup-4", 4));
  Tests.AssertEqualInt(
    "Cleanup interruption enters MAINTENANCE_ERROR",
    (int)postcommit_recovery.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR);

  CTGKGridEntryMappingSnapshotStorage cleanup_recovery;
  Tests.AssertTrue(
    "restart during Cleanup",
    cleanup_recovery.Initialize(_Symbol, instance_id));
  Tests.AssertEqualInt(
    "Cleanup retry returns to NORMAL",
    (int)cleanup_recovery.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_NORMAL);
  Tests.AssertTrue(
    "committed state survives interrupted Cleanup",
    cleanup_recovery.Replay(
      snapshot_payload,
      checkpoint_sequence,
      records,
      record_count,
      next_sequence));
  Tests.AssertEqualString(
    "latest committed Snapshot restored",
    snapshot_payload,
    "v1|current_state|cleanup-4");
  Tests.AssertTrue(
    "latest Snapshot remains",
    FileIsExist(stem + "_snapshot_5.dat"));
  Tests.AssertTrue(
    "latest Journal remains",
    FileIsExist(stem + "_journal_5.log"));
  Tests.AssertFalse(
    "previous Snapshot is removed after retry",
    FileIsExist(stem + "_snapshot_4.dat"));
  Tests.AssertFalse(
    "previous Journal is removed after retry",
    FileIsExist(stem + "_journal_4.log"));
  for(long old_generation = 1; old_generation < 5; old_generation++)
  {
    Tests.AssertFalse(
      StringFormat("old Snapshot generation %I64d is absent", old_generation),
      FileIsExist(StringFormat("%s_snapshot_%I64d.dat", stem, old_generation)));
    Tests.AssertFalse(
      StringFormat("old Journal generation %I64d is absent", old_generation),
      FileIsExist(StringFormat("%s_journal_%I64d.log", stem, old_generation)));
    Tests.AssertFalse(
      StringFormat("old Snapshot temp generation %I64d is absent", old_generation),
      FileIsExist(StringFormat("%s_snapshot_%I64d.tmp", stem, old_generation)));
    Tests.AssertFalse(
      StringFormat("old Journal temp generation %I64d is absent", old_generation),
      FileIsExist(StringFormat("%s_journal_%I64d.tmp", stem, old_generation)));
    Tests.AssertFalse(
      StringFormat("old Journal repair temp generation %I64d is absent", old_generation),
      FileIsExist(StringFormat("%s_journal_%I64d.repair.tmp", stem, old_generation)));
  }
  Tests.AssertFalse(
    "no Snapshot temporary file remains after Cleanup",
    FileIsExist(stem + "_snapshot_5.tmp"));
  Tests.AssertFalse(
    "no Journal temporary file remains after Cleanup",
    FileIsExist(stem + "_journal_5.tmp"));
  Tests.AssertFalse(
    "no Journal repair temporary file remains after Cleanup",
    FileIsExist(stem + "_journal_5.repair.tmp"));
  Tests.EndTest();

  Tests.BeginTest("String Field and Serialized Record limits reject without truncation");
  string field_4k;
  Tests.AssertTrue("create 4 KiB field", StringInit(field_4k, 4096, 'X'));
  Tests.AssertTrue(
    "exactly 4 KiB String Field is accepted",
    cleanup_recovery.Append(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      "v1|" + field_4k));

  string large_record_under_limit = "v1";
  for(int i = 0; i < 7; i++)
    large_record_under_limit += "|" + field_4k;
  Tests.AssertTrue(
    "large Serialized Record below 64 KiB is accepted",
    cleanup_recovery.Append(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      large_record_under_limit));

  string field_over_4k;
  Tests.AssertTrue("create 4 KiB plus one field", StringInit(field_over_4k, 4097, 'Y'));
  Tests.AssertFalse(
    "4 KiB plus one String Field is rejected",
    cleanup_recovery.Append(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      "v1|" + field_over_4k));

  string oversized_record = "v1";
  string field_for_record;
  StringInit(field_for_record, 4096, 'Z');
  for(int i = 0; i < 16; i++)
    oversized_record += "|" + field_for_record;
  Tests.AssertFalse(
    "Serialized Record larger than 64 KiB is rejected",
    cleanup_recovery.Append(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      oversized_record));
  Tests.EndTest();

  Tests.BeginTest("Active Journal reaching 16 MiB requests Rotation before the next Append");
  CTGKGridEntryMappingSnapshotStorage journal_full_storage;
  Tests.AssertTrue(
    "initialize Journal capacity test identity",
    journal_full_storage.Initialize(_Symbol, journal_full_instance_id));
  Tests.AssertTrue(
    "bootstrap Journal capacity test",
    journal_full_storage.Bootstrap("v1|state|journal-full-start", 0));

  string journal_field;
  Tests.AssertTrue("create 4 KiB Journal field", StringInit(journal_field, 4096, 'J'));
  string large_valid_record = "v1";
  for(int field_index = 0; field_index < 6; field_index++)
    large_valid_record += "|" + journal_field;

  int journal_append_count = 0;
  while(journal_append_count < 400 &&
        !journal_full_storage.NeedsRotation(
          TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
          large_valid_record))
  {
    if(!journal_full_storage.Append(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      large_valid_record))
      break;
    journal_append_count++;
  }

  Tests.AssertTrue(
    "Journal fills close to the configured 16 MiB limit",
    journal_append_count > 0);
  Tests.AssertTrue(
    "next record signals Rotation before exceeding 16 MiB",
    journal_full_storage.NeedsRotation(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      large_valid_record));
  Tests.AssertFalse(
    "Append beyond Journal capacity is rejected",
    journal_full_storage.Append(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      large_valid_record));
  Tests.AssertEqualInt(
    "Journal full alone does not corrupt committed state",
    (int)journal_full_storage.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_NORMAL);
  Tests.AssertTrue(
    "Rotation checkpoints the full Journal",
    journal_full_storage.Rotate(
      "v1|state|journal-full-checkpoint",
      journal_full_storage.LastSequence()));
  Tests.AssertFalse(
    "new Journal has capacity after Rotation",
    journal_full_storage.NeedsRotation(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      "v1|LEVEL_STATE|1|1|READY"));
  Tests.AssertTrue(
    "Append resumes on the new Journal generation",
    journal_full_storage.Append(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      "v1|LEVEL_STATE|1|1|READY"));
  Tests.AssertTrue(
    "clean Journal capacity test files",
    journal_full_storage.DeleteAllFilesForTest());
  Tests.EndTest();

  Tests.BeginTest("Snapshot larger than 16 MiB is rejected before Commit and preserves prior Generation");
  CTGKGridEntryMappingSnapshotStorage oversized_storage;
  Tests.AssertTrue(
    "initialize oversized Snapshot test identity",
    oversized_storage.Initialize(_Symbol, oversized_instance_id));
  Tests.AssertTrue(
    "bootstrap previous valid Generation",
    oversized_storage.Bootstrap("v1|state|last-valid-generation", 0));
  string snapshot_field;
  Tests.AssertTrue("create maximum String Field", StringInit(snapshot_field, 4096, 'S'));
  string oversized_snapshot = "v1";
  for(int i = 0; i < 2049; i++)
    oversized_snapshot += "|" + snapshot_field;
  Tests.AssertFalse(
    "Snapshot serialization above 16 MiB is rejected",
    oversized_storage.Rotate(oversized_snapshot, 0));
  Tests.AssertTrue(
    "last valid Generation remains committed",
    oversized_storage.HasCommittedState());
  Tests.AssertEqualInt(
    "oversized Rotation enters MAINTENANCE_ERROR",
    (int)oversized_storage.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_MAINTENANCE_ERROR);
  Tests.AssertTrue(
    "previous Snapshot and Journal remain intact",
    FileIsExist(oversized_storage.FileStem() + "_snapshot_1.dat") &&
    FileIsExist(oversized_storage.FileStem() + "_journal_1.log") &&
    FileIsExist(oversized_storage.FileStem() + "_manifest_A.dat"));

  CTGKGridEntryMappingSnapshotStorage oversized_recovery;
  Tests.AssertTrue(
    "restart recovers last valid Generation after oversized Rotation",
    oversized_recovery.Initialize(_Symbol, oversized_instance_id));
  Tests.AssertEqualInt(
    "recovered prior Generation is NORMAL",
    (int)oversized_recovery.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_NORMAL);
  Tests.AssertTrue(
    "recovered Snapshot payload is the last valid state",
    oversized_recovery.SnapshotPayload() == "v1|state|last-valid-generation");
  Tests.AssertFalse(
    "oversized candidate generation was never committed",
    FileIsExist(oversized_recovery.FileStem() + "_snapshot_2.dat"));
  Tests.AssertTrue(
    "clean oversized Snapshot test files",
    oversized_recovery.DeleteAllFilesForTest());
  Tests.EndTest();

  Tests.BeginTest("Missing committed data enters RECOVERY_ERROR instead of trading");
  CTGKGridEntryMappingSnapshotStorage broken_storage;
  Tests.AssertTrue(
    "initialize isolated recovery test identity",
    broken_storage.Initialize(_Symbol, broken_instance_id));
  Tests.AssertTrue(
    "bootstrap isolated recovery test",
    broken_storage.Bootstrap("v1|current_state|must_exist", 0));
  string broken_stem = broken_storage.FileStem();
  Tests.AssertTrue(
    "remove required Snapshot to simulate storage loss",
    FileDelete(broken_stem + "_snapshot_1.dat"));

  CTGKGridEntryMappingSnapshotStorage broken_recovery;
  Tests.AssertTrue(
    "initialize detects damaged committed generation",
    broken_recovery.Initialize(_Symbol, broken_instance_id));
  Tests.AssertEqualInt(
    "damaged generation enters RECOVERY_ERROR",
    (int)broken_recovery.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);
  Tests.AssertFalse(
    "damaged generation cannot Replay",
    broken_recovery.Replay(
      snapshot_payload,
      checkpoint_sequence,
      records,
      record_count,
      next_sequence));
  Tests.AssertFalse(
    "RECOVERY_ERROR blocks new Entry Intent",
    broken_recovery.Append(
      TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
      "v1|REQ-RECOVERY-BLOCKED|XAUUSD|710001|BUY|LEVEL|0|0.10|1|UT-INSTANCE"));
  Tests.EndTest();

  Tests.BeginTest("Orphan generation files without either Manifest enter RECOVERY_ERROR");
  string orphan_instance_id = instance_id + "_ORPHAN";
  CTGKGridEntryMappingSnapshotStorage orphan_setup;
  Tests.AssertTrue(
    "initialize fresh orphan-file test identity",
    orphan_setup.Initialize(_Symbol, orphan_instance_id));
  int orphan_handle = FileOpen(
    orphan_setup.FileStem() + "_snapshot_1.dat",
    FILE_WRITE | FILE_BIN);
  bool orphan_written = false;
  if(orphan_handle != INVALID_HANDLE)
  {
    uchar orphan_bytes[];
    int orphan_byte_count = StringToCharArray(
      "orphan",
      orphan_bytes,
      0,
      WHOLE_ARRAY,
      CP_UTF8);
    if(orphan_byte_count > 1)
    {
      ArrayResize(orphan_bytes, orphan_byte_count - 1);
      orphan_written = FileWriteArray(
        orphan_handle,
        orphan_bytes,
        0,
        (uint)ArraySize(orphan_bytes)) == ArraySize(orphan_bytes);
    }
    FileClose(orphan_handle);
  }
  Tests.AssertTrue("write orphan Snapshot file", orphan_written);

  CTGKGridEntryMappingSnapshotStorage orphan_recovery;
  Tests.AssertTrue(
    "initialize with orphan generation but no Manifest",
    orphan_recovery.Initialize(_Symbol, orphan_instance_id));
  Tests.AssertEqualInt(
    "orphan data enters RECOVERY_ERROR",
    (int)orphan_recovery.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_RECOVERY_ERROR);
  Tests.AssertFalse(
    "orphan data cannot accept a new Entry Intent",
    orphan_recovery.Append(
      TGK_GRID_MAPPING_RECORD_ENTRY_INTENT,
      "v1|REQ-ORPHAN-BLOCKED|XAUUSD|710001|BUY|LEVEL|0|0.10|1|UT-INSTANCE"));
  Tests.AssertTrue(
    "clean orphan-file test",
    orphan_recovery.DeleteAllFilesForTest());
  Tests.EndTest();

  RunPreCommitFailureCase(
    instance_id + "_FAIL_SNAPSHOT_TEMP",
    "Crash after Snapshot temporary write preserves old generation",
    TGK_GRID_SNAPSHOT_FAIL_AFTER_SNAPSHOT_TEMP_WRITE);
  RunPreCommitFailureCase(
    instance_id + "_FAIL_SNAPSHOT_READBACK",
    "Crash after Snapshot read-back preserves old generation",
    TGK_GRID_SNAPSHOT_FAIL_AFTER_SNAPSHOT_READBACK);
  RunPreCommitFailureCase(
    instance_id + "_FAIL_JOURNAL_TEMP",
    "Crash after Journal temporary write preserves old generation",
    TGK_GRID_SNAPSHOT_FAIL_AFTER_JOURNAL_TEMP_WRITE);
  RunPreCommitFailureCase(
    instance_id + "_FAIL_JOURNAL_READBACK",
    "Crash after Journal read-back preserves old generation",
    TGK_GRID_SNAPSHOT_FAIL_AFTER_JOURNAL_READBACK);
  RunPreCommitFailureCase(
    instance_id + "_FAIL_MANIFEST_TEMP",
    "Crash after Manifest temporary write preserves old generation",
    TGK_GRID_SNAPSHOT_FAIL_AFTER_MANIFEST_TEMP_WRITE);
  RunPreCommitFailureCase(
    instance_id + "_FAIL_MANIFEST_READBACK",
    "Crash after Manifest read-back preserves old generation",
    TGK_GRID_SNAPSHOT_FAIL_AFTER_MANIFEST_READBACK);
  RunPreCommitFailureCase(
    instance_id + "_FAIL_GENERATION_VALIDATION",
    "Crash after complete Generation validation preserves old generation",
    TGK_GRID_SNAPSHOT_FAIL_AFTER_GENERATION_VALIDATION);

  Tests.BeginTest("Recovery selects the older valid Manifest when the newer data set is damaged");
  string fallback_instance_id = instance_id + "_FALLBACK";
  CTGKGridEntryMappingSnapshotStorage fallback_storage;
  Tests.AssertTrue(
    "initialize fallback test identity",
    fallback_storage.Initialize(_Symbol, fallback_instance_id));
  Tests.AssertTrue(
    "bootstrap old valid Generation",
    fallback_storage.Bootstrap("v1|state|older-valid", 0));
  Tests.AssertTrue(
    "append old-generation Journal event",
    fallback_storage.Append(
      TGK_GRID_MAPPING_RECORD_LIFECYCLE_UPDATE,
      "v1|LEVEL_STATE|1|1|READY"));
  fallback_storage.SetFailurePointForTest(
    TGK_GRID_SNAPSHOT_FAIL_AFTER_MANIFEST_COMMIT);
  Tests.AssertFalse(
    "simulate interruption after new Manifest Commit",
    fallback_storage.Rotate("v1|state|newer-committed", 1));
  Tests.AssertTrue(
    "damage newer Snapshot while older data is still retained",
    FileDelete(fallback_storage.FileStem() + "_snapshot_2.dat"));

  CTGKGridEntryMappingSnapshotStorage fallback_recovery;
  Tests.AssertTrue(
    "initialize fallback Recovery",
    fallback_recovery.Initialize(_Symbol, fallback_instance_id));
  Tests.AssertEqualInt(
    "older valid Generation recovers NORMAL",
    (int)fallback_recovery.RecoveryStatus(),
    (int)TGK_GRID_MAPPING_STATUS_NORMAL);
  Tests.AssertTrue(
    "Replay older valid Snapshot and Journal",
    fallback_recovery.Replay(
      snapshot_payload,
      checkpoint_sequence,
      records,
      record_count,
      next_sequence));
  Tests.AssertEqualString(
    "older valid Snapshot is selected",
    snapshot_payload,
    "v1|state|older-valid");
  Tests.AssertEqualLong("older checkpoint remains zero", checkpoint_sequence, 0);
  Tests.AssertEqualInt("older Journal event remains available", record_count, 1);
  Tests.AssertFalse(
    "damaged newer Journal is cleaned after fallback",
    FileIsExist(fallback_recovery.FileStem() + "_journal_2.log"));
  Tests.AssertTrue(
    "clean fallback test files",
    fallback_recovery.DeleteAllFilesForTest());
  Tests.EndTest();

  Tests.AssertTrue("clean primary test files", cleanup_recovery.DeleteAllFilesForTest());
  Tests.AssertTrue("clean oversized test files", oversized_storage.DeleteAllFilesForTest());
  Tests.AssertTrue("clean damaged test files", broken_recovery.DeleteAllFilesForTest());

  Tests.EndSuite();
  return INIT_SUCCEEDED;
}

void OnTick()
{
}
