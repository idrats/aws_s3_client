import 'dart:async';

import 'package:aws_s3_client/src/client.dart';

/// StreamTransformer which collects values until it will exceed [chunkSize].
/// Emits chunks of [chunkSize] except the last one, which can be smaller
class ChunkTransformer implements StreamTransformer<List<int>, List<int>> {
  int _chunkSize;
  StreamController _controller;
  StreamSubscription _subscription;
  bool cancelOnError;
  Stream<List<int>> _stream;
  final _buffer = <int>[];

  ChunkTransformer(
      {int chunkSize = defaultChunkSize,
      bool sync = false,
      this.cancelOnError}) {
    _chunkSize = chunkSize;
    _controller = StreamController<List<int>>(
        onListen: _onListen,
        onCancel: _onCancel,
        onPause: () {
          _subscription.pause();
        },
        onResume: () {
          _subscription.resume();
        },
        sync: sync);
  }

  ChunkTransformer.broadcast(
      {int chunkSize = defaultChunkSize,
      bool sync = false,
      this.cancelOnError}) {
    _chunkSize = chunkSize;
    _controller = StreamController<List<int>>.broadcast(
        onListen: _onListen, onCancel: _onCancel, sync: sync);
  }

  void _onListen() {
    _subscription = _stream.listen(onData,
        onError: _controller.addError,
        onDone: _onDone,
        cancelOnError: cancelOnError);
  }

  void _onCancel() {
    _subscription.cancel();
    _subscription = null;
  }

  void onData(List<int> data) {
    _buffer.addAll(data);
    _emitData();
  }

  void _onDone() {
    if (_buffer.isNotEmpty) {
      _controller.add(_buffer);
    }
    _controller.close();
  }

  void _emitData() {
    if (_buffer.length >= _chunkSize) {
      _controller.add(_buffer.sublist(0, _chunkSize));
      _buffer.removeRange(0, _chunkSize);
      _emitData();
    }
  }

  Stream<List<int>> bind(Stream<List<int>> stream) {
    this._stream = stream;
    return _controller.stream;
  }

  StreamTransformer<RS, RT> cast<RS, RT>() => StreamTransformer.castFrom(this);
}
