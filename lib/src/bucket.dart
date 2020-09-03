import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:meta/meta.dart';
import 'package:crypto/crypto.dart';
import 'package:http_client/console.dart' as http_client;
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

import 'client.dart';
import 'results.dart';
import 'stream_transformers.dart';

enum Permissions {
  private,
  public,
}

class Bucket extends Client {
  final int chunkSize;
  final String endpointUrl;
  Bucket(
      {@required String region,
      @required String accessKey,
      @required String secretKey,
      @required this.endpointUrl,
      String sessionToken,
      this.chunkSize = defaultChunkSize,
      http_client.Client httpClient})
      : super(
            region: region,
            accessKey: accessKey,
            secretKey: secretKey,
            service: "s3",
            sessionToken: sessionToken,
            httpClient: httpClient);

  /// List the Bucket's Content
  Stream<BucketContent> listContent(
      {String delimiter, String prefix, int maxKeys}) async* {
    bool isTruncated;
    String marker;
    do {
      Uri uri = Uri.parse(endpointUrl + '/');
      Map<String, dynamic> params = Map<String, dynamic>();
      if (delimiter != null) params['delimiter'] = delimiter;
      if (marker != null) {
        params['marker'] = marker;
        marker = null;
      }
      if (maxKeys != null) params['max-keys'] = "$maxKeys";
      if (prefix != null) params['prefix'] = prefix;
      uri = uri.replace(queryParameters: params);
      xml.XmlDocument doc = await getUri(uri);
      String lastKey;
      for (xml.XmlElement root in doc.findElements('ListBucketResult')) {
        for (xml.XmlNode node in root.children) {
          if (node is xml.XmlElement) {
            xml.XmlElement element = node;
            switch ('${element.name}') {
              case "NextMarker":
                marker = element.text;
                break;
              case "IsTruncated":
                isTruncated = element.text.toLowerCase() != "false" &&
                    element.text != "0";
                break;
              case "Contents":
                String key;
                DateTime lastModifiedUtc;
                String eTag;
                int size;
                for (xml.XmlNode node in element.children) {
                  if (node is xml.XmlElement) {
                    xml.XmlElement element = node;
                    switch ('${element.name}') {
                      case "Key":
                        key = element.text;
                        lastKey = key;
                        break;
                      case "LastModified":
                        lastModifiedUtc = DateTime.parse(element.text);
                        break;
                      case "ETag":
                        eTag = element.text;
                        break;
                      case "Size":
                        size = int.parse(element.text);
                        break;
                    }
                  }
                }
                yield BucketContent(
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
      if (isTruncated && lastKey != null) marker = lastKey;
    } while (isTruncated);
  }

  /// Uploads file stream. Returns Etag.
  Future<String> uploadFileStream(String key, Stream<List<int>> fileStream,
      int contentLength, String contentType, Permissions permissions,
      {Map<String, String> meta}) async {
    bool isFirstChunk = true;
    String signature;
    Uri uri = Uri.parse(endpointUrl + '/' + key);

    DateTime date = DateTime.now().toUtc();

    // String dateIso8601 = "20130524T000000Z";
    String dateIso8601 = date.toIso8601String();
    dateIso8601 = dateIso8601
            .substring(0, dateIso8601.indexOf('.'))
            .replaceAll(':', '')
            .replaceAll('-', '') +
        'Z';

    // String dateYYYYMMDD = "20130524";
    String dateYYYYMMDD = date.year.toString().padLeft(4, '0') +
        date.month.toString().padLeft(2, '0') +
        date.day.toString().padLeft(2, '0');

    int contentLengthWithMeta =
        calculateContentLengthWithMeta(contentLength, chunkSize);

    final headers = composeChunkRequestHeaders(
        uri: uri,
        dateYYYYMMDD: dateYYYYMMDD,
        dateIso8601: dateIso8601,
        contentLength: contentLength,
        contentType: contentType,
        permissions: permissions,
        chunkContentLengthWithMeta: contentLengthWithMeta,
        meta: meta);
    String canonicalRequestSignature =
        headers['Authorization'].split('Signature=').last;

    http.StreamedRequest request = http.StreamedRequest('PUT', uri);
    request.headers.addAll(headers);
    final futureRequest = request.send();

    Future<String> sendChunkRequest(List<int> data) async {
      signature = calculateChunkedSignature(
        data,
        isFirstChunk ? canonicalRequestSignature : signature,
        dateYYYYMMDD: dateYYYYMMDD,
        dateIso8601: dateIso8601,
      );
      if (isFirstChunk) {
        isFirstChunk = false;
      }
      request.sink.add(data.length.toRadixString(16).toString().codeUnits);
      request.sink.add(";chunk-signature=$signature\r\n".codeUnits);
      if (data.isNotEmpty) request.sink.add(data);
      request.sink.add("\r\n".codeUnits);
      if (data.isEmpty) {
        request.sink.close();
        final responseStream = await futureRequest;
        final response = await http.Response.fromStream(responseStream);
        // print(response.statusCode);
        // print(response.reasonPhrase);
        // print(response.headers);
        // print(await response.transform(utf8.decoder).first);
        return response.headers[HttpHeaders.etagHeader];
      }
      return '';
    }

    Future<String> sendChunkRequestSync(List<int> val,
        [Future previousChunk]) async {
      if (previousChunk != null) {
        await previousChunk;
      }
      return sendChunkRequest(val);
    }

    Future<dynamic> handleFileStream(Stream<List<int>> fileStream) {
      Future prevChunk;

      final completer = Completer();
      fileStream.listen((val) {
        prevChunk = sendChunkRequestSync(val, prevChunk);
      }, onDone: () {
        sendChunkRequestSync([], prevChunk).then((etag) {
          completer.complete(etag);
        });
      });
      return completer.future;
    }

    return await handleFileStream(
        fileStream.transform(ChunkTransformer(chunkSize: chunkSize)));
  }

  int calculateContentLengthWithMeta(int contentLength, int chunkSize) =>
      (chunkSize.toRadixString(16).codeUnits.length + 85) *
          (contentLength / chunkSize).floor() +
      (contentLength % chunkSize).toRadixString(16).codeUnits.length +
      85 +
      86 +
      contentLength;

  /// Upload file. Return Etag.
  Future<String> uploadFile(String key, Uint8List content, String contentType,
      Permissions permissions,
      {Map<String, String> meta}) async {
    int contentLength = content.lengthInBytes;

    Digest contentSha256 = sha256.convert(content);

    String uriStr = endpointUrl + '/' + key;
    http_client.Request request = http_client.Request('PUT', Uri.parse(uriStr),
        headers: http_client.Headers(), body: content);

    if (meta != null) {
      for (MapEntry<String, String> me in meta.entries) {
        request.headers.add("x-amz-meta-${me.key}", me.value);
      }
    }

    if (sessionToken != null) {
      request.headers.add('x-amz-security-token', sessionToken);
    }

    if (permissions == Permissions.public) {
      request.headers.add('x-amz-acl', 'public-read');
    }
    request.headers.add('Content-Length', contentLength);
    request.headers.add('Content-Type', contentType);
    signRequest(request, contentSha256: contentSha256);
    http_client.Response response = await httpClient.send(request);
    BytesBuilder builder = BytesBuilder(copy: false);
    await response.body.forEach(builder.add);
    String body = utf8.decode(builder.toBytes()); // Should be empty when OK
    if (response.statusCode != 200) {
      throw ClientException(response.statusCode, response.reasonPhrase,
          response.headers.toSimpleMap(), body);
    }
    return response.headers[HttpHeaders.etagHeader].first;
  }

  /// Delete file
  Future<void> delete(String key) async {
    String uriStr = endpointUrl + '/' + key;
    http_client.Request request = http_client.Request(
        'DELETE', Uri.parse(uriStr),
        headers: http_client.Headers());

    signRequest(request, contentSha256: sha256.convert([]));
    http_client.Response response = await httpClient.send(request);
    BytesBuilder builder = BytesBuilder(copy: false);
    await response.body.forEach(builder.add);
    String body = utf8.decode(builder.toBytes()); // Should be empty when OK
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw ClientException(response.statusCode, response.reasonPhrase,
          response.headers.toSimpleMap(), body);
    }
  }
}
