// 职责: 验证 WebDAV HTTP 方法、路径拼接、远端枚举及文件传输。
// 关联文件:
//   lib/shared/services/webdav_transport.dart
//   lib/shared/models/webdav_backup_config.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/webdav_backup_config.dart';
import 'package:reveric/shared/services/webdav_transport.dart';

void main() {
  test('creates folders, uploads, lists, and downloads backups', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <({String method, String path})>[];
    final uploadedBytes = <int>[];
    const expectedAuthorization = 'Basic YXV0aG9yOnNlY3JldA==';

    server.listen((request) async {
      requests.add((method: request.method, path: request.uri.path));
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        expectedAuthorization,
      );
      switch (request.method) {
        case 'MKCOL':
          await request.drain<void>();
          request.response.statusCode = HttpStatus.created;
        case 'PUT':
          await for (final chunk in request) {
            uploadedBytes.addAll(chunk);
          }
          request.response.statusCode = HttpStatus.created;
        case 'GET':
          await request.drain<void>();
          request.response.add(const <int>[4, 5, 6]);
        case 'PROPFIND':
          await request.drain<void>();
          request.response.statusCode = 207;
          request.response.headers.contentType = ContentType(
            'application',
            'xml',
            charset: 'utf-8',
          );
          request.response.write(_listingXml);
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final root = await Directory.systemTemp.createTemp('webdav_transport_');
    addTearDown(() => root.delete(recursive: true));
    final uploadFile = File('${root.path}/reveric_backup_20260806.zip');
    await uploadFile.writeAsBytes(const <int>[1, 2, 3]);
    final downloadFile = File('${root.path}/download.zip');
    final config = WebDavBackupConfig(
      enabled: true,
      serverUrl: 'http://${server.address.host}:${server.port}/dav/',
      username: 'author',
      remoteDirectory: '/Reveric/Backups',
    );
    const credentials = WebDavCredentials(
      username: 'author',
      password: 'secret',
    );
    const transport = WebDavTransport();

    await transport.ensureDirectory(config: config, credentials: credentials);
    await transport.upload(
      config: config,
      credentials: credentials,
      localFile: uploadFile,
    );
    final files = await transport.listBackups(
      config: config,
      credentials: credentials,
    );
    await transport.download(
      config: config,
      credentials: credentials,
      remotePath: files.single.remotePath,
      destination: downloadFile,
    );

    expect(uploadedBytes, const <int>[1, 2, 3]);
    expect(files, hasLength(1));
    expect(files.single.name, 'reveric_backup_20260806.zip');
    expect(files.single.size, 3);
    expect(
      files.single.remotePath,
      '/Reveric/Backups/reveric_backup_20260806.zip',
    );
    expect(await downloadFile.readAsBytes(), const <int>[4, 5, 6]);
    expect(
      requests,
      contains((
        method: 'PUT',
        path: '/dav/Reveric/Backups/reveric_backup_20260806.zip',
      )),
    );
  });
}

final _listingXml =
    '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/Reveric/Backups/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection /></d:resourcetype></d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Reveric/Backups/reveric_backup_20260806.zip</d:href>
    <d:propstat><d:prop>
      <d:getcontentlength>3</d:getcontentlength>
      <d:getlastmodified>${HttpDate.format(DateTime.utc(2026, 8, 6, 10))}</d:getlastmodified>
    </d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/Reveric/Backups/notes.txt</d:href>
    <d:propstat><d:prop><d:getcontentlength>20</d:getcontentlength></d:prop></d:propstat>
  </d:response>
</d:multistatus>''';
