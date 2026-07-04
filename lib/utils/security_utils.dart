import 'dart:convert';

String hashPrivateKey(String rawKey) {
  final bytes = utf8.encode(rawKey.trim());
  var hash = 0x811C9DC5;
  const fnvPrime = 0x01000193;

  for (final unit in bytes) {
    hash ^= unit;
    hash = (hash * fnvPrime) & 0xFFFFFFFF;
  }

  return hash.toRadixString(16).padLeft(8, '0');
}
