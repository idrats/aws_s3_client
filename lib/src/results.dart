class BucketContent {
  /// The object's key.
  late final String key;

  /// The date and time that the object was last modified in the format: %Y-%m-%dT%H:%M:%S.%3NZ (e.g. 2017-06-23T18:37:48.157Z)
  late final DateTime lastModifiedUtc;

  /// The entity tag containing an MD5 hash of the object.
  late final String eTag;

  /// The size of the object in bytes.
  late final int size;

  @override
  String toString() {
    return 'key: $key\neTag: $eTag\nsize: $size\nlastModifiedUtc: $lastModifiedUtc';
  }

  BucketContent({
    required this.key,
    required this.lastModifiedUtc,
    required this.eTag,
    required this.size,
  });
}
