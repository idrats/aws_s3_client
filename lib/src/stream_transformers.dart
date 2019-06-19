import 'dart:async';
import 'package:stream_transform/src/from_handlers.dart';

/// Creates a StreamTransformer which collects values until it will exceed [chunkSize].
/// Emits chunks of [chunkSize] except the last one, which can be smaller
StreamTransformer<List<T>, List<T>> chunkedBuffer<T>(int chunkSize) =>
    _chunkedAggregate(chunkSize, _collectToList);

List<T> _collectToList<T>(List<T> chunk, List<T> soFar) {
  soFar ??= <T>[];
  soFar.addAll(chunk);
  return soFar;
}

StreamTransformer<List<T>, List<T>> _chunkedAggregate<T>(
    int chunkLength, List<T> collect(List<T> chunk, List<T> soFar)) {
  var soFar = <T>[];
  return fromHandlers(handleData: (List<T> value, EventSink<List<T>> sink) {
    soFar = collect(value, soFar);

    while (soFar.length > chunkLength) {
      sink.add(soFar.sublist(0, chunkLength));
      soFar.removeRange(0, chunkLength);
    }
  }, handleDone: (EventSink<List<T>> sink) {
    while (soFar.length > chunkLength) {
      sink.add(soFar.sublist(0, chunkLength));
      soFar.removeRange(0, chunkLength);
    }
    if (soFar.isNotEmpty) {
      sink.add(soFar);
    }
    sink.close();
  });
}
