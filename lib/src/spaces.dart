import 'dart:async';
import 'package:meta/meta.dart';
import 'package:http_client/console.dart' as http;
import 'package:xml/xml.dart' as xml;

import 'client.dart';
import 'bucket.dart';

enum Provider {
  amazon,
  yandex,
}

class Spaces extends Client {
  final Provider provider;
  String _endpointUrl;
  Spaces(
      {@required String region,
      @required String accessKey,
      @required String secretKey,
      String sessionToken,
      http.Client httpClient,
      this.provider = Provider.amazon})
      : super(
            region: region,
            accessKey: accessKey,
            secretKey: secretKey,
            sessionToken: sessionToken,
            service: "s3",
            httpClient: httpClient);

  Bucket bucket(String bucket) {
    switch (provider) {
      case Provider.amazon:
        _endpointUrl = "https://s3.${region}.amazonaws.com";
        break;
      case Provider.yandex:
        _endpointUrl = "https://storage.yandexcloud.net";
        break;
      default:
        throw Exception(
            "Endpoint URL not supported. Create Bucket client manually.");
    }
    return Bucket(
        region: region,
        accessKey: accessKey,
        secretKey: secretKey,
        endpointUrl: "$_endpointUrl/${bucket}",
        sessionToken: sessionToken,
        httpClient: httpClient);
  }

  Future<List<String>> listAllBuckets() async {
    xml.XmlDocument doc = await getUri(Uri.parse(_endpointUrl + '/'));
    List<String> res = List<String>();
    for (xml.XmlElement root in doc.findElements('ListAllMyBucketsResult')) {
      for (xml.XmlElement buckets in root.findElements('Buckets')) {
        for (xml.XmlElement bucket in buckets.findElements('Bucket')) {
          for (xml.XmlElement name in bucket.findElements('Name')) {
            res.add(name.text);
          }
        }
      }
    }
    return res;
  }
}
