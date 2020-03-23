import 'dart:io';
import 'package:aws_s3_client/aws_s3_client.dart';

main() async {
  Spaces spaces = Spaces(
    region: "region",
    accessKey: "accessKey",
    secretKey: "secretKey",
  );
  for (String name in await spaces.listAllBuckets()) {
    print('bucket: ${name}');
    if (name == 'yourBucket') {
      Bucket bucket = spaces.bucket(name);
      await for (BucketContent content in bucket.listContent(prefix: 'test')) {
        print('key: ${content.key}; size: ${content.size}');
      }
    }
  }
  Bucket bucket = spaces.bucket('yourBucket');

  File file = File('README.md');

  String etag = await bucket.uploadFile(
      'test/test.md', file.readAsBytesSync(), 'text/plain', Permissions.public);
  print('upload: $etag');

  print('done');
}
