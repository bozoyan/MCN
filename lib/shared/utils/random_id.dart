import 'dart:math';

const String _randomIdAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

final Random _randomIdRandom = Random.secure();

String buildRandomId(String prefix, {int length = 16}) {
  final buffer = StringBuffer(prefix)..write('_');
  for (var i = 0; i < length; i++) {
    final index = _randomIdRandom.nextInt(_randomIdAlphabet.length);
    buffer.write(_randomIdAlphabet[index]);
  }
  return buffer.toString();
}
