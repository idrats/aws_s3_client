import 'dart:async';
@TestOn('vm')
import 'dart:io';

import 'package:aws_s3_client/aws_s3.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as pathInfo;
import 'package:test/test.dart';

import './test_config.dart';

void main() {
  final spaces = Spaces(
      region: TestConfig.region,
      accessKey: TestConfig.accessKey,
      secretKey: TestConfig.secretKey,
      provider: Provider.yandex);
  final bucket = spaces.bucket(TestConfig.bucket);

  setUpAll(() async {});

  test('List buckets', () async {
    final buckets = await spaces.listAllBuckets();
    expect(buckets, contains(TestConfig.bucket));
  });

  test('List content', () async {
    final file = File('test/squirrel.jpeg');
    final file2 = File('test/earth.jpeg');
    final keys = ['squirrel.jpeg', 'earth.jpeg'];
    await bucket.uploadFile(pathInfo.basename(file.path),
        file.readAsBytesSync(), lookupMimeType(file.path), Permissions.public);
    await bucket.uploadFile(
        pathInfo.basename(file2.path),
        file2.readAsBytesSync(),
        lookupMimeType(file2.path),
        Permissions.public);

    var content = await bucket.listContent().toList();
    expect(content.length, 2);
    content = await bucket.listContent(prefix: 'squirrel').toList();
    expect(content.length, 1);
    content = await bucket.listContent(prefix: 'earth').toList();
    expect(content.length, 1);

    final completer = Completer();
    bucket
        .listContent(
          maxKeys: 1,
        )
        .listen((data) => expect(keys, contains(data.key)),
            onDone: () => completer.complete());
    await completer.future;
  });

  test('upload file to bucket', () async {
    final file = File('test/squirrel.jpeg');
    final eTag = await bucket.uploadFile(pathInfo.basename(file.path),
        file.readAsBytesSync(), lookupMimeType(file.path), Permissions.public);
    expect(eTag, isNotEmpty);

    final content = await bucket.listContent(prefix: 'squirrel').toList();
    expect(content.first.key, pathInfo.basename(file.path));
    expect(content.first.eTag, eTag);
    expect(content.first.size, file.lengthSync());
  });

  test('Delete file', () async {
    final file = File('test/squirrel.jpeg');
    await bucket.uploadFile(pathInfo.basename(file.path),
        file.readAsBytesSync(), lookupMimeType(file.path), Permissions.public);

    var content = await bucket.listContent(prefix: 'squirrel').toList();
    expect(content.length, 1);
    await bucket.delete(pathInfo.basename(file.path));
    content = await bucket.listContent(prefix: 'squirrel').toList();
    expect(content.length, 0);
  });

  test('Upload file as stream to bucket', () async {
    final file = File('test/earth.jpeg');
    final eTag = await bucket.uploadFileStream(
        pathInfo.basename(file.path),
        file.openRead(),
        file.lengthSync(),
        lookupMimeType(file.path),
        Permissions.public);
    expect(eTag, isNotEmpty);

    final content = await bucket.listContent(prefix: 'earth').toList();
    expect(content.first.key, pathInfo.basename(file.path));
    expect(content.first.eTag, eTag);
    expect(content.first.size, file.lengthSync());

    await bucket.delete(pathInfo.basename(file.path));
    expect(await bucket.listContent(prefix: 'earth').toList(), []);
  });
}
