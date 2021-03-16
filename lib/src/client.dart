import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:meta/meta.dart';
import 'package:crypto/crypto.dart';
import 'package:http_client/console.dart' as http;
import 'package:xml/xml.dart' as xml;

import 'bucket.dart';

const defaultChunkSize = 65536;

class ClientException implements Exception {
  final int statusCode;
  final String reasonPhrase;
  final Map<String, String> responseHeaders;
  final String responseBody;
  const ClientException(this.statusCode, this.reasonPhrase,
      this.responseHeaders, this.responseBody);
  String toString() {
    return "DOException { statusCode: ${statusCode}, reasonPhrase: \"${reasonPhrase}\", responseBody: \"${responseBody}\" }";
  }
}

class Client {
  final String region;
  final String accessKey;
  final String secretKey;
  final String? sessionToken;
  final String service;

  @protected
  final http.Client httpClient;

  Client(
      {required this.region,
      required this.accessKey,
      required this.secretKey,
      required this.service,
      this.sessionToken,
      http.Client? httpClient})
      : this.httpClient =
            httpClient == null ? http.ConsoleClient() : httpClient {}

  @protected
  Future<xml.XmlDocument> getUri(Uri uri) async {
    http.Request request = http.Request('GET', uri, headers: http.Headers());
    signRequest(request, contentSha256: await sha256.convert(''.codeUnits));
    http.Response response = await httpClient.send(request);
    BytesBuilder builder = BytesBuilder(copy: false);
    await response.body.forEach(builder.add);
    String body = utf8.decode(builder.toBytes());
    if (response.statusCode != 200) {
      throw ClientException(response.statusCode, response.reasonPhrase,
          response.headers.toSimpleMap(), body);
    }
    xml.XmlDocument doc = xml.XmlDocument.parse(body);
    return doc;
  }

  String _uriEncode(String str) {
    return Uri.encodeQueryComponent(str).replaceAll('+', '%20');
  }

  String _trimAll(String str) {
    String res = str.trim();
    int len;
    do {
      len = res.length;
      res = res.replaceAll('  ', ' ');
    } while (res.length != len);
    return res;
  }

  @protected
  void signRequest(http.Request request,
      {Digest? contentSha256, int expires = 86400}) {
    // Build canonical request
    String httpMethod = request.method;
    String canonicalURI = request.uri.path;
    String host = request.uri.host;
    // String service = 's3';

    DateTime date = DateTime.now().toUtc();
    String dateIso8601 = date.toIso8601String();
    dateIso8601 = dateIso8601
            .substring(0, dateIso8601.indexOf('.'))
            .replaceAll(':', '')
            .replaceAll('-', '') +
        'Z';
    String dateYYYYMMDD = date.year.toString().padLeft(4, '0') +
        date.month.toString().padLeft(2, '0') +
        date.day.toString().padLeft(2, '0');

    /*dateIso8601 = "20130524T000000Z";
    dateYYYYMMDD = "20130524";
    hashedPayload = null;*/
    String hashedPayloadStr =
        contentSha256 == null ? 'UNSIGNED-PAYLOAD' : '$contentSha256';

    String credential =
        '${accessKey}/${dateYYYYMMDD}/${region}/${service}/aws4_request';
    // Build canonical headers string
    Map<String, List<String>> headers = Map<String, List<String>>();
    request.headers.add('x-amz-date', dateIso8601); // Set date in header
    if (contentSha256 != null) {
      request.headers.add('x-amz-content-sha256',
          hashedPayloadStr); // Set payload hash in header
    }
    request.headers.keys.forEach((String name) =>
        (headers[name.toLowerCase()] = request.headers[name]!));
    headers['host'] = [host]; // Host is a builtin header
    List<String> headerNames = headers.keys.toList()..sort();
    String canonicalHeaders = headerNames
        .map((s) =>
            (headers[s]!.map((v) => ('${s}:${_trimAll(v)}')).join('\n') + '\n'))
        .join();

    String signedHeaders = headerNames.join(';');

    // Build canonical query string
    Map<String, String> queryParameters = Map<String, String>()
      ..addAll(request.uri.queryParameters);
    List<String> queryKeys = queryParameters.keys.toList()..sort();
    String canonicalQueryString = queryKeys
        .map((s) => '${_uriEncode(s)}=${_uriEncode(queryParameters[s]!)}')
        .join('&');

    // Sign headers
    String canonicalRequest =
        '${httpMethod}\n${canonicalURI}\n${canonicalQueryString}\n${canonicalHeaders}\n${signedHeaders}\n$hashedPayloadStr';
    // print('\n>>>>>> canonical request \n' + canonicalRequest + '\n<<<<<<\n');

    Digest canonicalRequestHash = sha256.convert(utf8.encode(
        canonicalRequest)); //_hmacSha256.convert(utf8.encode(canonicalRequest));

    String stringToSign =
        'AWS4-HMAC-SHA256\n${dateIso8601}\n${dateYYYYMMDD}/${region}/${service}/aws4_request\n$canonicalRequestHash';
    // print('\n>>>>>> string to sign \n' + stringToSign + '\n<<<<<<\n');

    Digest dateKey = Hmac(sha256, utf8.encode("AWS4${secretKey}"))
        .convert(utf8.encode(dateYYYYMMDD));
    Digest dateRegionKey =
        Hmac(sha256, dateKey.bytes).convert(utf8.encode(region));
    Digest dateRegionServiceKey =
        Hmac(sha256, dateRegionKey.bytes).convert(utf8.encode(service));
    Digest signingKey = Hmac(sha256, dateRegionServiceKey.bytes)
        .convert(utf8.encode("aws4_request"));

    Digest signature =
        Hmac(sha256, signingKey.bytes).convert(utf8.encode(stringToSign));

    // Set signature in header
    request.headers.add('Authorization',
        'AWS4-HMAC-SHA256 Credential=${credential}, SignedHeaders=${signedHeaders}, Signature=$signature');
  }

  @protected
  Map<String, String> composeChunkRequestHeaders(
      {required Uri uri,
      required String dateIso8601,
      required String dateYYYYMMDD,
      required String contentType,
      required int contentLength,
      required int chunkContentLengthWithMeta,
      Permissions? permissions,
      Map<String, String>? meta}) {
    // Build canonical request
    String httpMethod = 'PUT';
    String canonicalURI = uri.path;
    String host = uri.host;

    String credential =
        '${accessKey}/${dateYYYYMMDD}/${region}/${service}/aws4_request';
    Map<String, String> resultHeaders = {
      'x-amz-date': dateIso8601, // Set date in header
      'x-amz-content-sha256':
          'STREAMING-AWS4-HMAC-SHA256-PAYLOAD', // Set payload hash in header
      'Content-Encoding': 'aws-chunked',
      'Content-Type': contentType,
      // 'Expect': '100-continue',
      // 'x-amz-storage-class': 'REDUCED_REDUNDANCY',
      'Content-Length': chunkContentLengthWithMeta.toString(),
      'x-amz-decoded-content-length': contentLength.toString()
    };

    if (meta != null) {
      for (MapEntry<String, String> me in meta.entries) {
        resultHeaders["x-amz-meta-${me.key}"] = me.value;
      }
    }
    if (permissions == Permissions.public) {
      resultHeaders['x-amz-acl'] = 'public-read';
    }
    // Build canonical headers string
    Map<String, List<String>> headers = Map<String, List<String>>();
    resultHeaders.keys.forEach((String name) => (headers[name.toLowerCase()] =
        resultHeaders[name] is List
            ? resultHeaders[name] as List<String>
            : [resultHeaders[name]!]));
    headers['host'] = [host]; // Host is a builtin header
    List<String> headerNames = headers.keys.toList()..sort();
    String canonicalHeaders = headerNames
        .map((s) =>
            (headers[s]!.map((v) => ('${s}:${_trimAll(v)}')).join('\n') + '\n'))
        .join();

    String signedHeaders = headerNames.join(';');

    // Build canonical query string
    Map<String, String> queryParameters = Map<String, String>()
      ..addAll(uri.queryParameters);
    List<String> queryKeys = queryParameters.keys.toList()..sort();
    String canonicalQueryString = queryKeys
        .map((s) => '${_uriEncode(s)}=${_uriEncode(queryParameters[s]!)}')
        .join('&');

    // Sign headers
    String canonicalRequest =
        '${httpMethod}\n${canonicalURI}\n${canonicalQueryString}\n${canonicalHeaders}\n${signedHeaders}\nSTREAMING-AWS4-HMAC-SHA256-PAYLOAD';
    // print('\n>>>>>> canonical request \n' + canonicalRequest + '\n<<<<<<\n');

    Digest canonicalRequestHash = sha256.convert(utf8.encode(
        canonicalRequest)); //_hmacSha256.convert(utf8.encode(canonicalRequest));

    String stringToSign =
        'AWS4-HMAC-SHA256\n${dateIso8601}\n${dateYYYYMMDD}/${region}/${service}/aws4_request\n$canonicalRequestHash';
    // print('\n>>>>>> string to sign \n' + stringToSign + '\n<<<<<<\n');

    Digest dateKey = Hmac(sha256, utf8.encode("AWS4${secretKey}"))
        .convert(utf8.encode(dateYYYYMMDD));
    Digest dateRegionKey =
        Hmac(sha256, dateKey.bytes).convert(utf8.encode(region));
    Digest dateRegionServiceKey =
        Hmac(sha256, dateRegionKey.bytes).convert(utf8.encode(service));
    Digest signingKey = Hmac(sha256, dateRegionServiceKey.bytes)
        .convert(utf8.encode("aws4_request"));

    Digest signature =
        Hmac(sha256, signingKey.bytes).convert(utf8.encode(stringToSign));

    // Set signature in header
    resultHeaders['Authorization'] =
        'AWS4-HMAC-SHA256 Credential=${credential}, SignedHeaders=${signedHeaders}, Signature=$signature';

    return resultHeaders;
  }

  String calculateChunkedSignature(
    List<int> data,
    String prevSignature, {
    required String dateIso8601,
    required String dateYYYYMMDD,
  }) {
    String stringToSign =
        'AWS4-HMAC-SHA256-PAYLOAD\n${dateIso8601}\n${dateYYYYMMDD}/${region}/${service}/aws4_request\n$prevSignature\n${sha256.convert([])}\n${sha256.convert(data)}';
    // print('\n>>>>>> chunk string to sign \n' + stringToSign + '\n<<<<<<\n');

    Digest dateKey = Hmac(sha256, utf8.encode("AWS4${secretKey}"))
        .convert(utf8.encode(dateYYYYMMDD));
    Digest dateRegionKey =
        Hmac(sha256, dateKey.bytes).convert(utf8.encode(region));
    Digest dateRegionServiceKey =
        Hmac(sha256, dateRegionKey.bytes).convert(utf8.encode(service));
    Digest signingKey = Hmac(sha256, dateRegionServiceKey.bytes)
        .convert(utf8.encode("aws4_request"));

    Digest signature =
        Hmac(sha256, signingKey.bytes).convert(utf8.encode(stringToSign));

    return '$signature';
  }
}
