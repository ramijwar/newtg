import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

/// A read cache with enough metadata to tell the UI exactly when it was last
/// synchronised. `changed` is false when the server response is byte-for-byte
/// identical, so an unchanged response does not rewrite local content.
final class CachedEntry {
  const CachedEntry({
    required this.payload,
    required this.lastSyncedAt,
    required this.lastCheckedAt,
    this.revision,
  });

  final Map<String, dynamic> payload;
  final DateTime lastSyncedAt;
  final DateTime lastCheckedAt;
  final String? revision;
}

/// A non-financial mutation that can safely be retried with its idempotency
/// key. Payments, withdrawals, order completion and proof uploads are never
/// put into this queue.
final class PendingOperation {
  const PendingOperation({
    required this.id,
    required this.method,
    required this.apiPath,
    required this.payload,
    required this.idempotencyKey,
    required this.createdAt,
    required this.attempts,
  });

  final int id;
  final String method;
  final String apiPath;
  final Map<String, dynamic> payload;
  final String? idempotencyKey;
  final DateTime createdAt;
  final int attempts;
}

/// SQLite holds cache and retryable non-financial operations only.
/// Orders, payments, balances, credentials and authorization remain
/// server-authoritative and are deliberately excluded from this database.
final class LocalDatabase {
  LocalDatabase._();
  static final instance = LocalDatabase._();

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    final root = await getDatabasesPath();
    final opened = await openDatabase(
      path.join(root, 'tijarti_mobile.db'),
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cache_entries (
            cache_key TEXT PRIMARY KEY,
            payload_json TEXT NOT NULL,
            revision TEXT,
            updated_at_ms INTEGER NOT NULL,
            checked_at_ms INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE pending_operations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            method TEXT NOT NULL,
            path TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            idempotency_key TEXT,
            created_at_ms INTEGER NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_attempt_at_ms INTEGER,
            last_error TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE cache_entries ADD COLUMN revision TEXT',
          );
          await db.execute(
            'ALTER TABLE cache_entries ADD COLUMN checked_at_ms INTEGER',
          );
          await db.execute(
            'UPDATE cache_entries SET checked_at_ms = updated_at_ms WHERE checked_at_ms IS NULL',
          );
          await db.execute(
            'ALTER TABLE pending_operations ADD COLUMN last_attempt_at_ms INTEGER',
          );
          await db.execute(
            'ALTER TABLE pending_operations ADD COLUMN last_error TEXT',
          );
        }
      },
    );
    _database = opened;
    return opened;
  }

  /// Upserts in one SQLite command instead of the former read-then-write pair.
  /// `updated_at_ms` changes only for new content; every server check still
  /// refreshes `checked_at_ms` for an honest offline freshness label.
  Future<bool> putCache(String key, Object payload, {String? revision}) async {
    final db = await database;
    final encoded = jsonEncode(payload);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawInsert(
      '''INSERT INTO cache_entries (cache_key, payload_json, revision, updated_at_ms, checked_at_ms)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(cache_key) DO UPDATE SET
           payload_json = CASE WHEN cache_entries.payload_json IS excluded.payload_json
                                   AND cache_entries.revision IS excluded.revision
                                THEN cache_entries.payload_json ELSE excluded.payload_json END,
           revision = CASE WHEN cache_entries.payload_json IS excluded.payload_json
                              AND cache_entries.revision IS excluded.revision
                           THEN cache_entries.revision ELSE excluded.revision END,
           updated_at_ms = CASE WHEN cache_entries.payload_json IS excluded.payload_json
                                  AND cache_entries.revision IS excluded.revision
                               THEN cache_entries.updated_at_ms ELSE excluded.updated_at_ms END,
           checked_at_ms = excluded.checked_at_ms''',
      [key, encoded, revision, now, now],
    );
    // No current caller branches on this value. Returning true keeps the method
    // conservative without a second query solely to distinguish an unchanged row.
    return true;
  }

  /// Logging out must not leave another account's catalogue cache or deferred
  /// mutations on this device. This intentionally clears the two local tables
  /// but does not delete the database file or any protected OS-level session data.
  Future<void> clearLocalData() async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete('cache_entries');
      await transaction.delete('pending_operations');
    });
  }

  Future<CachedEntry?> readCacheEntry(String key) async {
    final db = await database;
    final rows = await db.query(
      'cache_entries',
      columns: const [
        'payload_json',
        'revision',
        'updated_at_ms',
        'checked_at_ms',
      ],
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    try {
      final decoded = jsonDecode(row['payload_json']! as String);
      if (decoded is! Map) return null;
      final syncAt = (row['updated_at_ms'] as num?)?.toInt();
      if (syncAt == null) return null;
      final checkedAt = (row['checked_at_ms'] as num?)?.toInt() ?? syncAt;
      return CachedEntry(
        payload: Map<String, dynamic>.from(decoded),
        revision: row['revision'] as String?,
        lastSyncedAt: DateTime.fromMillisecondsSinceEpoch(syncAt),
        lastCheckedAt: DateTime.fromMillisecondsSinceEpoch(checkedAt),
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> readCache(String key) async =>
      (await readCacheEntry(key))?.payload;

  Future<DateTime?> lastSyncedAt(String key) async =>
      (await readCacheEntry(key))?.lastSyncedAt;

  Future<void> enqueueOperation({
    required String method,
    required String apiPath,
    required Map<String, dynamic> payload,
    String? idempotencyKey,
  }) async {
    const allowedMethods = {'POST', 'PATCH', 'DELETE'};
    if (!allowedMethods.contains(method.toUpperCase()) ||
        !apiPath.startsWith('/') ||
        idempotencyKey == null ||
        idempotencyKey.isEmpty) {
      throw ArgumentError(
        'العملية المؤجلة يجب أن تكون POST/PATCH/DELETE مع مسار ومفتاح تكرار.',
      );
    }
    final db = await database;
    await db.insert('pending_operations', {
      'method': method.toUpperCase(),
      'path': apiPath,
      'payload_json': jsonEncode(payload),
      'idempotency_key': idempotencyKey,
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
    });
  }

  Future<List<PendingOperation>> pendingOperations({int limit = 25}) async {
    final db = await database;
    final rows = await db.query(
      'pending_operations',
      orderBy: 'id ASC',
      limit: limit.clamp(1, 100),
    );
    return rows
        .map((row) {
          final decoded = jsonDecode(row['payload_json']! as String);
          return PendingOperation(
            id: row['id']! as int,
            method: row['method']! as String,
            apiPath: row['path']! as String,
            payload: decoded is Map
                ? Map<String, dynamic>.from(decoded)
                : const <String, dynamic>{},
            idempotencyKey: row['idempotency_key'] as String?,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              (row['created_at_ms']! as num).toInt(),
            ),
            attempts: (row['attempts']! as num).toInt(),
          );
        })
        .toList(growable: false);
  }

  Future<void> completeOperation(int id) async {
    final db = await database;
    await db.delete('pending_operations', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> recordOperationFailure(int id, Object error) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE pending_operations SET attempts = attempts + 1, last_attempt_at_ms = ?, last_error = ? WHERE id = ?',
      [
        DateTime.now().millisecondsSinceEpoch,
        error.toString().substring(0, 500),
        id,
      ],
    );
  }
}
