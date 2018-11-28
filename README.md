# AWS_S3_client

Client library to interact with the AWS S3 API

## Usage

A simple usage example:

```
import 'package:aws_s3_client/aws_s3.dart';

main() async {
  Spaces spaces = new Spaces(
    region: "region",
    accessKey: "accessKey",
    secretKey: "secretKey",
  );
  for (String name in await spaces.listAllBuckets()) {
    print('bucket: ${name}');
    if (name == 'yourBucket') {
      Bucket bucket = spaces.bucket(name);
      await for (BucketContent content
          in bucket.listContents(prefix: 'test')) {
        print('key: ${content.key}; size: ${content.size}');
      }
    }
  }
  Bucket bucket = spaces.bucket('yourBucket');

  String etag = await bucket.uploadFile(
      'test/test.md', 'README.md', 'text/plain', Permissions.public);
  print('upload: $etag');

  print('done');
}
```

## References

* https://github.com/nbspou/dospace
* https://github.com/agilord/aws_client
* https://github.com/gjersvik/awsdart
* https://docs.aws.amazon.com/general/latest/gr/signature-version-4.html
* https://docs.aws.amazon.com/general/latest/gr/sigv4_signing.html
* https://docs.aws.amazon.com/general/latest/gr/sigv4-signed-request-examples.html
* https://docs.aws.amazon.com/general/latest/gr/signature-v4-test-suite.html
