import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:meta/meta.dart';
import 'package:crypto/crypto.dart';
import 'package:http_client/console.dart' as http;
import 'package:xml/xml.dart' as xml;

import 'client.dart';
import 'results.dart';

enum Permissions {
  private,
  public,
}

class Bucket extends Client {
  Bucket(
      {@required String region,
      @required String accessKey,
      @required String secretKey,
      String endpointUrl,
      http.Client httpClient})
      : super(
            region: region,
            accessKey: accessKey,
            secretKey: secretKey,
            service: "s3",
            endpointUrl: endpointUrl,
            httpClient: httpClient) {
    // ...
  }

  void bucket(String bucket) {
    if (endpointUrl == "https://s3.${region}.amazonaws.com") {
    } else {
      throw Exception(
          "Endpoint URL not supported. Create Bucket client manually.");
    }
  }

  /// List the Bucket's Contents.
  /// https://developers.digitalocean.com/documentation/spaces/#list-bucket-contents
  Stream<BucketContent> listContents(
      {String delimiter, String prefix, int maxKeys}) async* {
    bool isTruncated;
    String marker;
    do {
      Uri uri = Uri.parse(endpointUrl + '/');
      Map<String, dynamic> params = new Map<String, dynamic>();
      if (delimiter != null) params['delimiter'] = delimiter;
      if (marker != null) {
        params['marker'] = marker;
        marker = null;
      }
      if (maxKeys != null) params['max-keys'] = "${maxKeys}";
      if (prefix != null) params['prefix'] = prefix;
      uri = uri.replace(queryParameters: params);
      xml.XmlDocument doc = await getUri(uri);
      for (xml.XmlElement root in doc.findElements('ListBucketResult')) {
        for (xml.XmlNode node in root.children) {
          if (node is xml.XmlElement) {
            xml.XmlElement ele = node;
            switch ('${ele.name}') {
              case "NextMarker":
                marker = ele.text;
                break;
              case "IsTruncated":
                isTruncated =
                    ele.text.toLowerCase() != "false" && ele.text != "0";
                break;
              case "Contents":
                String key;
                DateTime lastModifiedUtc;
                String eTag;
                int size;
                for (xml.XmlNode node in ele.children) {
                  if (node is xml.XmlElement) {
                    xml.XmlElement ele = node;
                    switch ('${ele.name}') {
                      case "Key":
                        key = ele.text;
                        break;
                      case "LastModified":
                        lastModifiedUtc = DateTime.parse(ele.text);
                        break;
                      case "ETag":
                        eTag = ele.text;
                        break;
                      case "Size":
                        size = int.parse(ele.text);
                        break;
                    }
                  }
                }
                yield new BucketContent(
                  key: key,
                  lastModifiedUtc: lastModifiedUtc,
                  eTag: eTag,
                  size: size,
                );
                break;
            }
          }
        }
      }
    } while (isTruncated);
  }

  /// Uploads file stream. Returns Etag.
  Future<String> uploadFileStream(String key, Stream<List<int>> fileStream,
      String contentType, int contentLength, Permissions permissions,
      {Map<String, String> meta}) async {
    print('??????????????');
    var broadcast = StreamController<List<int>>.broadcast();
    fileStream.listen((val) {
      broadcast.add(val);
      print(val.length);
      print('----------');
    });
    wait15sec().then((_) => broadcast.sink.close());
    Digest contentSha256 = await sha256.bind(broadcast.stream).first;
    print('!!!!!!!!!!!!!!!!!');

    String uriStr = endpointUrl + '/' + key;
    http.Request request = new http.Request('PUT', Uri.parse(uriStr),
        headers: new http.Headers(), body: broadcast.stream);
    if (meta != null) {
      for (MapEntry<String, String> me in meta.entries) {
        request.headers.add("x-amz-meta-${me.key}", me.value);
      }
    }
    if (permissions == Permissions.public) {
      request.headers.add('x-amz-acl', 'public-read');
    }
    request.headers.add('Content-Length', contentLength);
    request.headers.add('Content-Type', contentType);
    signRequest(request, contentSha256: contentSha256);
    http.Response response = await httpClient.send(request);

    BytesBuilder builder = new BytesBuilder(copy: false);
    await response.body.forEach(builder.add);
    String body = utf8.decode(builder.toBytes()); // Should be empty when OK
    if (response.statusCode != 200) {
      throw new ClientException(response.statusCode, response.reasonPhrase,
          response.headers.toSimpleMap(), body);
    }
    String etag = response.headers['etag'].first;
    return etag;
  }

  Future wait15sec() async {
    await Future.delayed(Duration(seconds: 15));
  }

  /// Uploads file. Returns Etag.
  Future<String> uploadFile(
      String key, String filePath, String contentType, Permissions permissions,
      {Map<String, String> meta}) async {
    var input = new File(filePath);
    int contentLength = await input.length();
    Digest contentSha256 = await sha256.bind(input.openRead()).first;
    String uriStr = endpointUrl + '/' + key;
    http.Request request = new http.Request('PUT', Uri.parse(uriStr),
        headers: new http.Headers(), body: input.openRead());
    if (meta != null) {
      for (MapEntry<String, String> me in meta.entries) {
        request.headers.add("x-amz-meta-${me.key}", me.value);
      }
    }
    if (permissions == Permissions.public) {
      request.headers.add('x-amz-acl', 'public-read');
    }
    request.headers.add('Content-Length', contentLength);
    request.headers.add('Content-Type', contentType);
    signRequest(request, contentSha256: contentSha256);
    http.Response response = await httpClient.send(request);
    BytesBuilder builder = new BytesBuilder(copy: false);
    await response.body.forEach(builder.add);
    String body = utf8.decode(builder.toBytes()); // Should be empty when OK
    if (response.statusCode != 200) {
      throw new ClientException(response.statusCode, response.reasonPhrase,
          response.headers.toSimpleMap(), body);
    }
    String etag = response.headers['etag'].first;
    return etag;
  }
}
