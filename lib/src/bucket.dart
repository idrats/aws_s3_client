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

  int i = 0;

  /// Uploads file stream. Returns Etag.
  Future<String> uploadFileStream(String key, Stream<List<int>> fileStream,
      String contentType, int contentLength, Permissions permissions,
      {Map<String, String> meta}) async {
    // int chunkSize = 155894;
    int chunkSize = 65536;
    bool isFirstChunk = true;
    String signature;
    Uri uri = Uri.parse(endpointUrl + '/' + key);
    int contentLengthWithMeta =
        calculateContentLengthWithMeta(contentLength, chunkSize);
    // Map<String, dynamic> headers = {
    //   'Content-Encoding': 'aws-chunked',
    //   'Content-Type': contentType,
    //   'Content-Length': contentLengthWithMeta,
    //   'x-amz-decoded-content-length': contentLength
    // };
    // if (meta != null) {
    //   for (MapEntry<String, String> me in meta.entries) {
    //     headers["x-amz-meta-${me.key}"] = me.value;
    //   }
    // }
    // if (permissions == Permissions.public) {
    //   headers['x-amz-acl'] = 'public-read';
    // }
    // print(headers);
    // final signedHeaders = composeChunkRequestHeaders(headers, uri);
    // String canonicalRequestSignature =
    //     (headers['Authorization'] as String).split('Signature=').last;
    // print(signedHeaders);
    // print(canonicalRequestSignature);

    http.Request tmpRequest = http.Request('PUT', uri, headers: http.Headers());
    tmpRequest.headers.add('Content-Encoding', 'aws-chunked');
    tmpRequest.headers.add('Content-Type', contentType);
    tmpRequest.headers.add('Content-Length', contentLengthWithMeta);
    tmpRequest.headers.add('x-amz-decoded-content-length', contentLength);
    if (meta != null) {
      for (MapEntry<String, String> me in meta.entries) {
        tmpRequest.headers.add("x-amz-meta-${me.key}", me.value);
      }
    }
    if (permissions == Permissions.public) {
      tmpRequest.headers.add('x-amz-acl', 'public-read');
    }
    String canonicalRequestSignature = signFirstChunkRequest(tmpRequest);
    http.Headers headers = tmpRequest.headers;

    sendChunkRequest(List<int> data, int i) async {
      http.Request request;
      if (isFirstChunk) {
        signature = calculateChunkedSignature(data, canonicalRequestSignature);
        isFirstChunk = false;
      } else {
        signature = calculateChunkedSignature(data, signature);
      }
      print(data.length);
      print((data.length.toRadixString(16).toString() +
              ";chunk-signature=$signature\r\n" +
              (data.isEmpty ? '' : data.toString()) +
              "\r\n")
          .length);
      print('******************');
      request = new http.Request('PUT', uri,
          body: data.length.toRadixString(16).toString() +
              ";chunk-signature=$signature\r\n" +
              (data.isEmpty ? '' : data.toString()) +
              "\r\n",
          headers: headers);
      try {
        await httpClient.send(request);
      } catch (e, s) {
        print(e.toString().length > 200 ? e.toString().substring(0, 200) : e);
      }
    }

    Future sendChunkRequestSync(List<int> val,
        [Future previousChunk, int i]) async {
      final completer = Completer();
      if (previousChunk == null) {
        sendChunkRequest(val, i).then((_) {
          print('**********completed first ($i) future=========');
          completer.complete();
        });
      } else {
        previousChunk.then((_) {
          sendChunkRequest(val, i).then((_) {
            print('**********completed other ($i) future=========');

            completer.complete();
          });
        });
      }

      return completer.future;
    }

    Future prevChunk;
    Future lastChunk;
    int i = 0;
    fileStream.listen((val) {
      // var utf8val = utf8.encode(val.toString());
      // int contentLength = utf8val.length;
      // print(contentLength);
      // print(val.length);
      if (val.length != chunkSize)
        print('======ALARM======${val.length} != $chunkSize');
      prevChunk = sendChunkRequestSync(val, prevChunk, i);
      i++;
    }, onDone: () {
      print('onDone!');
      lastChunk = sendChunkRequestSync([], prevChunk, i);
    });
    await lastChunk;
    // await Future.delayed(Duration(seconds: 10));
    print('!!!!!!!');
    return 'ok';
  }

  int calculateContentLengthWithMeta(int contentLength, int chunkSize) =>
      (chunkSize.toRadixString(16).codeUnits.length + 85) *
          (contentLength / chunkSize).floor() +
      (contentLength % chunkSize).toRadixString(16).codeUnits.length +
      85 +
      86 +
      contentLength;

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
