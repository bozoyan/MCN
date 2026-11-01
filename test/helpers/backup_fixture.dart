// 职责: 为备份测试创建真实当前 schema 的数据库快照并填充客户端时间戳。
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/database/novel_content_database.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:sqlite3/sqlite3.dart';

class BackupDatabases {
  const BackupDatabases(this.main, this.content);

  final Uint8List main;
  final Uint8List content;

  static Future<BackupDatabases> create() async {
    final directory = await Directory.systemTemp.createTemp('backup-schema-');
    final mainFile = File('${directory.path}/main.sqlite');
    final contentFile = File('${directory.path}/content.sqlite');
    try {
      final main = AppDatabase.forTest(NativeDatabase(mainFile));
      final content = NovelContentDatabase.forTest(NativeDatabase(contentFile));
      try {
        await main.customSelect('SELECT 1').get();
        await content.customSelect('SELECT 1').get();
      } finally {
        await main.close();
        await content.close();
      }
      return BackupDatabases(
        await mainFile.readAsBytes(),
        await contentFile.readAsBytes(),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  }

  Database writeMain(String path) => _write(path, main);
  Database writeContent(String path) => _write(path, content);

  Database _write(String path, Uint8List bytes) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return sqlite3.open(path);
  }
}

/// Raw SQLite inserts need the timestamps normally supplied by Drift clients.
void insertBackupRow(
  Database database,
  String table,
  Map<String, Object?> fields,
) {
  final columns = database
      .select('PRAGMA table_info("$table")')
      .map((row) => row['name'])
      .toSet();
  final values = {
    if (columns.contains('created_at')) 'created_at': 100,
    if (columns.contains('updated_at')) 'updated_at': 100,
    ...fields,
  };
  database.execute(
    'INSERT INTO "$table" (${values.keys.map((key) => '"$key"').join(',')}) '
    'VALUES (${List.filled(values.length, '?').join(',')})',
    values.values.toList(),
  );
}
