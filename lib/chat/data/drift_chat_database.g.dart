// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drift_chat_database.dart';

// ignore_for_file: type=lint
class $ChatRecordsTable extends ChatRecords
    with TableInfo<$ChatRecordsTable, ChatRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recordTypeMeta =
      const VerificationMeta('recordType');
  @override
  late final GeneratedColumn<String> recordType = GeneratedColumn<String>(
      'record_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _conversationIdMeta =
      const VerificationMeta('conversationId');
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
      'conversation_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _clientMessageIdMeta =
      const VerificationMeta('clientMessageId');
  @override
  late final GeneratedColumn<String> clientMessageId = GeneratedColumn<String>(
      'client_message_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _sealedRecordMeta =
      const VerificationMeta('sealedRecord');
  @override
  late final GeneratedColumn<Uint8List> sealedRecord =
      GeneratedColumn<Uint8List>('sealed_record', aliasedName, false,
          type: DriftSqlType.blob, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        recordType,
        conversationId,
        clientMessageId,
        updatedAt,
        sealedRecord
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_records';
  @override
  VerificationContext validateIntegrity(Insertable<ChatRecord> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('record_type')) {
      context.handle(
          _recordTypeMeta,
          recordType.isAcceptableOrUnknown(
              data['record_type']!, _recordTypeMeta));
    } else if (isInserting) {
      context.missing(_recordTypeMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
          _conversationIdMeta,
          conversationId.isAcceptableOrUnknown(
              data['conversation_id']!, _conversationIdMeta));
    }
    if (data.containsKey('client_message_id')) {
      context.handle(
          _clientMessageIdMeta,
          clientMessageId.isAcceptableOrUnknown(
              data['client_message_id']!, _clientMessageIdMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('sealed_record')) {
      context.handle(
          _sealedRecordMeta,
          sealedRecord.isAcceptableOrUnknown(
              data['sealed_record']!, _sealedRecordMeta));
    } else if (isInserting) {
      context.missing(_sealedRecordMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatRecord(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      recordType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}record_type'])!,
      conversationId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}conversation_id']),
      clientMessageId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}client_message_id']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      sealedRecord: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}sealed_record'])!,
    );
  }

  @override
  $ChatRecordsTable createAlias(String alias) {
    return $ChatRecordsTable(attachedDatabase, alias);
  }
}

class ChatRecord extends DataClass implements Insertable<ChatRecord> {
  final String id;
  final String recordType;
  final String? conversationId;
  final String? clientMessageId;
  final DateTime updatedAt;
  final Uint8List sealedRecord;
  const ChatRecord(
      {required this.id,
      required this.recordType,
      this.conversationId,
      this.clientMessageId,
      required this.updatedAt,
      required this.sealedRecord});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['record_type'] = Variable<String>(recordType);
    if (!nullToAbsent || conversationId != null) {
      map['conversation_id'] = Variable<String>(conversationId);
    }
    if (!nullToAbsent || clientMessageId != null) {
      map['client_message_id'] = Variable<String>(clientMessageId);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['sealed_record'] = Variable<Uint8List>(sealedRecord);
    return map;
  }

  ChatRecordsCompanion toCompanion(bool nullToAbsent) {
    return ChatRecordsCompanion(
      id: Value(id),
      recordType: Value(recordType),
      conversationId: conversationId == null && nullToAbsent
          ? const Value.absent()
          : Value(conversationId),
      clientMessageId: clientMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(clientMessageId),
      updatedAt: Value(updatedAt),
      sealedRecord: Value(sealedRecord),
    );
  }

  factory ChatRecord.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatRecord(
      id: serializer.fromJson<String>(json['id']),
      recordType: serializer.fromJson<String>(json['recordType']),
      conversationId: serializer.fromJson<String?>(json['conversationId']),
      clientMessageId: serializer.fromJson<String?>(json['clientMessageId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      sealedRecord: serializer.fromJson<Uint8List>(json['sealedRecord']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'recordType': serializer.toJson<String>(recordType),
      'conversationId': serializer.toJson<String?>(conversationId),
      'clientMessageId': serializer.toJson<String?>(clientMessageId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'sealedRecord': serializer.toJson<Uint8List>(sealedRecord),
    };
  }

  ChatRecord copyWith(
          {String? id,
          String? recordType,
          Value<String?> conversationId = const Value.absent(),
          Value<String?> clientMessageId = const Value.absent(),
          DateTime? updatedAt,
          Uint8List? sealedRecord}) =>
      ChatRecord(
        id: id ?? this.id,
        recordType: recordType ?? this.recordType,
        conversationId:
            conversationId.present ? conversationId.value : this.conversationId,
        clientMessageId: clientMessageId.present
            ? clientMessageId.value
            : this.clientMessageId,
        updatedAt: updatedAt ?? this.updatedAt,
        sealedRecord: sealedRecord ?? this.sealedRecord,
      );
  ChatRecord copyWithCompanion(ChatRecordsCompanion data) {
    return ChatRecord(
      id: data.id.present ? data.id.value : this.id,
      recordType:
          data.recordType.present ? data.recordType.value : this.recordType,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      clientMessageId: data.clientMessageId.present
          ? data.clientMessageId.value
          : this.clientMessageId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      sealedRecord: data.sealedRecord.present
          ? data.sealedRecord.value
          : this.sealedRecord,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatRecord(')
          ..write('id: $id, ')
          ..write('recordType: $recordType, ')
          ..write('conversationId: $conversationId, ')
          ..write('clientMessageId: $clientMessageId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sealedRecord: $sealedRecord')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, recordType, conversationId,
      clientMessageId, updatedAt, $driftBlobEquality.hash(sealedRecord));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatRecord &&
          other.id == this.id &&
          other.recordType == this.recordType &&
          other.conversationId == this.conversationId &&
          other.clientMessageId == this.clientMessageId &&
          other.updatedAt == this.updatedAt &&
          $driftBlobEquality.equals(other.sealedRecord, this.sealedRecord));
}

class ChatRecordsCompanion extends UpdateCompanion<ChatRecord> {
  final Value<String> id;
  final Value<String> recordType;
  final Value<String?> conversationId;
  final Value<String?> clientMessageId;
  final Value<DateTime> updatedAt;
  final Value<Uint8List> sealedRecord;
  final Value<int> rowid;
  const ChatRecordsCompanion({
    this.id = const Value.absent(),
    this.recordType = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.clientMessageId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.sealedRecord = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatRecordsCompanion.insert({
    required String id,
    required String recordType,
    this.conversationId = const Value.absent(),
    this.clientMessageId = const Value.absent(),
    required DateTime updatedAt,
    required Uint8List sealedRecord,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        recordType = Value(recordType),
        updatedAt = Value(updatedAt),
        sealedRecord = Value(sealedRecord);
  static Insertable<ChatRecord> custom({
    Expression<String>? id,
    Expression<String>? recordType,
    Expression<String>? conversationId,
    Expression<String>? clientMessageId,
    Expression<DateTime>? updatedAt,
    Expression<Uint8List>? sealedRecord,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (recordType != null) 'record_type': recordType,
      if (conversationId != null) 'conversation_id': conversationId,
      if (clientMessageId != null) 'client_message_id': clientMessageId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (sealedRecord != null) 'sealed_record': sealedRecord,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatRecordsCompanion copyWith(
      {Value<String>? id,
      Value<String>? recordType,
      Value<String?>? conversationId,
      Value<String?>? clientMessageId,
      Value<DateTime>? updatedAt,
      Value<Uint8List>? sealedRecord,
      Value<int>? rowid}) {
    return ChatRecordsCompanion(
      id: id ?? this.id,
      recordType: recordType ?? this.recordType,
      conversationId: conversationId ?? this.conversationId,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      updatedAt: updatedAt ?? this.updatedAt,
      sealedRecord: sealedRecord ?? this.sealedRecord,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (recordType.present) {
      map['record_type'] = Variable<String>(recordType.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (clientMessageId.present) {
      map['client_message_id'] = Variable<String>(clientMessageId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (sealedRecord.present) {
      map['sealed_record'] = Variable<Uint8List>(sealedRecord.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatRecordsCompanion(')
          ..write('id: $id, ')
          ..write('recordType: $recordType, ')
          ..write('conversationId: $conversationId, ')
          ..write('clientMessageId: $clientMessageId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sealedRecord: $sealedRecord, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$DriftChatDatabase extends GeneratedDatabase {
  _$DriftChatDatabase(QueryExecutor e) : super(e);
  $DriftChatDatabaseManager get managers => $DriftChatDatabaseManager(this);
  late final $ChatRecordsTable chatRecords = $ChatRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [chatRecords];
}

typedef $$ChatRecordsTableCreateCompanionBuilder = ChatRecordsCompanion
    Function({
  required String id,
  required String recordType,
  Value<String?> conversationId,
  Value<String?> clientMessageId,
  required DateTime updatedAt,
  required Uint8List sealedRecord,
  Value<int> rowid,
});
typedef $$ChatRecordsTableUpdateCompanionBuilder = ChatRecordsCompanion
    Function({
  Value<String> id,
  Value<String> recordType,
  Value<String?> conversationId,
  Value<String?> clientMessageId,
  Value<DateTime> updatedAt,
  Value<Uint8List> sealedRecord,
  Value<int> rowid,
});

class $$ChatRecordsTableFilterComposer
    extends Composer<_$DriftChatDatabase, $ChatRecordsTable> {
  $$ChatRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get recordType => $composableBuilder(
      column: $table.recordType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get clientMessageId => $composableBuilder(
      column: $table.clientMessageId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get sealedRecord => $composableBuilder(
      column: $table.sealedRecord, builder: (column) => ColumnFilters(column));
}

class $$ChatRecordsTableOrderingComposer
    extends Composer<_$DriftChatDatabase, $ChatRecordsTable> {
  $$ChatRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get recordType => $composableBuilder(
      column: $table.recordType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get clientMessageId => $composableBuilder(
      column: $table.clientMessageId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get sealedRecord => $composableBuilder(
      column: $table.sealedRecord,
      builder: (column) => ColumnOrderings(column));
}

class $$ChatRecordsTableAnnotationComposer
    extends Composer<_$DriftChatDatabase, $ChatRecordsTable> {
  $$ChatRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get recordType => $composableBuilder(
      column: $table.recordType, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
      column: $table.conversationId, builder: (column) => column);

  GeneratedColumn<String> get clientMessageId => $composableBuilder(
      column: $table.clientMessageId, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<Uint8List> get sealedRecord => $composableBuilder(
      column: $table.sealedRecord, builder: (column) => column);
}

class $$ChatRecordsTableTableManager extends RootTableManager<
    _$DriftChatDatabase,
    $ChatRecordsTable,
    ChatRecord,
    $$ChatRecordsTableFilterComposer,
    $$ChatRecordsTableOrderingComposer,
    $$ChatRecordsTableAnnotationComposer,
    $$ChatRecordsTableCreateCompanionBuilder,
    $$ChatRecordsTableUpdateCompanionBuilder,
    (
      ChatRecord,
      BaseReferences<_$DriftChatDatabase, $ChatRecordsTable, ChatRecord>
    ),
    ChatRecord,
    PrefetchHooks Function()> {
  $$ChatRecordsTableTableManager(
      _$DriftChatDatabase db, $ChatRecordsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> recordType = const Value.absent(),
            Value<String?> conversationId = const Value.absent(),
            Value<String?> clientMessageId = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<Uint8List> sealedRecord = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ChatRecordsCompanion(
            id: id,
            recordType: recordType,
            conversationId: conversationId,
            clientMessageId: clientMessageId,
            updatedAt: updatedAt,
            sealedRecord: sealedRecord,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String recordType,
            Value<String?> conversationId = const Value.absent(),
            Value<String?> clientMessageId = const Value.absent(),
            required DateTime updatedAt,
            required Uint8List sealedRecord,
            Value<int> rowid = const Value.absent(),
          }) =>
              ChatRecordsCompanion.insert(
            id: id,
            recordType: recordType,
            conversationId: conversationId,
            clientMessageId: clientMessageId,
            updatedAt: updatedAt,
            sealedRecord: sealedRecord,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ChatRecordsTableProcessedTableManager = ProcessedTableManager<
    _$DriftChatDatabase,
    $ChatRecordsTable,
    ChatRecord,
    $$ChatRecordsTableFilterComposer,
    $$ChatRecordsTableOrderingComposer,
    $$ChatRecordsTableAnnotationComposer,
    $$ChatRecordsTableCreateCompanionBuilder,
    $$ChatRecordsTableUpdateCompanionBuilder,
    (
      ChatRecord,
      BaseReferences<_$DriftChatDatabase, $ChatRecordsTable, ChatRecord>
    ),
    ChatRecord,
    PrefetchHooks Function()>;

class $DriftChatDatabaseManager {
  final _$DriftChatDatabase _db;
  $DriftChatDatabaseManager(this._db);
  $$ChatRecordsTableTableManager get chatRecords =>
      $$ChatRecordsTableTableManager(_db, _db.chatRecords);
}
