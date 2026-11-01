// 职责: 验证 S3 SigV4 预签名链接与官方示例一致，以及寻址方式、请求签名头和错误码解析。
// 关联文件:
//   lib/shared/services/object_storage/s3.dart
//   lib/shared/models/object_storage_config.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reveric/shared/models/object_storage_config.dart';
import 'package:reveric/shared/services/object_storage/s3.dart';

void main() {
  const awsExample = ObjectStorageConfig(
    endpoint: 'https://s3.amazonaws.com',
    region: 'us-east-1',
    bucket: 'examplebucket',
    accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
    secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
  );
  final exampleTime = DateTime.utc(2013, 5, 24);

  test('presigned GET matches the AWS SigV4 documentation example', () {
    final client = S3Client(
      awsExample,
      MockClient((_) async => http.Response('', 200)),
      now: () => exampleTime,
    );

    final url = client.presignGet('test.txt', const Duration(days: 1));

    expect(
      url.toString(),
      'https://examplebucket.s3.amazonaws.com/test.txt'
      '?X-Amz-Algorithm=AWS4-HMAC-SHA256'
      '&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request'
      '&X-Amz-Date=20130524T000000Z'
      '&X-Amz-Expires=86400'
      '&X-Amz-SignedHeaders=host'
      '&X-Amz-Signature='
      'aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404',
    );
  });

  test('path-style keeps the endpoint port and encodes key segments', () {
    final client = S3Client(
      const ObjectStorageConfig(
        endpoint: 'http://127.0.0.1:9000',
        bucket: 'media',
        accessKeyId: 'a',
        secretAccessKey: 's',
        pathStyle: true,
      ),
      MockClient((_) async => http.Response('', 200)),
    );

    expect(
      client.objectUri('ref/中 文+.png').toString(),
      'http://127.0.0.1:9000/media/ref/%E4%B8%AD%20%E6%96%87%2B.png',
    );
  });

  test('PUT signs payload hash, date and host headers', () async {
    late http.BaseRequest sent;
    final client = S3Client(
      awsExample,
      MockClient((request) async {
        sent = request;
        expect(request.body, 'hello');
        return http.Response('', 200);
      }),
      now: () => exampleTime,
    );

    await client.putBytes(
      'a.txt',
      utf8.encode('hello'),
      contentType: 'text/plain',
    );

    expect(sent.method, 'PUT');
    expect(sent.headers['x-amz-date'], '20130524T000000Z');
    expect(
      sent.headers['x-amz-content-sha256'],
      '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
    );
    expect(sent.headers['content-type'], 'text/plain');
    expect(
      sent.headers['authorization'],
      startsWith(
        'AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/'
        's3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, '
        'Signature=',
      ),
    );
  });

  test('error responses expose the S3 error code', () async {
    final client = S3Client(
      awsExample,
      MockClient(
        (_) async => http.Response(
          '<Error><Code>NoSuchBucket</Code><Message>x</Message></Error>',
          404,
        ),
      ),
    );

    await expectLater(
      client.putBytes('a', const [1], contentType: 'text/plain'),
      throwsA(
        isA<S3Exception>()
            .having((e) => e.statusCode, 'status', 404)
            .having((e) => e.code, 'code', 'NoSuchBucket'),
      ),
    );
  });
}
