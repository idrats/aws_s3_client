# AWS_S3_client

Client library to interact with the AWS S3 API (and other compatible S3 services, such as Yandex Cloud Storage)

## Usage

A simple usage example:

```
import 'package:aws_s3_client/aws_s3.dart';

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

For more usage examples please see tests

## References

* https://docs.aws.amazon.com/general/latest/gr/Welcome.html
* https://cloud.yandex.ru/docs/storage/s3/api-ref/

Thanks https://github.com/nbspou for inspiration of creating this package
