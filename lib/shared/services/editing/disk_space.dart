// 职责: 查询临时目录所在卷的可用空间，在合成前拒绝超出容量的任务。
// 关联文件:
//   lib/shared/services/editing/render_service.dart
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

int editingFreeBytes(String directory) {
  if (Platform.isWindows) {
    final getSpace = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          Int32 Function(
            Pointer<Utf16>,
            Pointer<Uint64>,
            Pointer<Uint64>,
            Pointer<Uint64>,
          ),
          int Function(
            Pointer<Utf16>,
            Pointer<Uint64>,
            Pointer<Uint64>,
            Pointer<Uint64>,
          )
        >('GetDiskFreeSpaceExW');
    final path = directory.toNativeUtf16();
    final free = calloc<Uint64>();
    try {
      if (getSpace(path, free, nullptr, nullptr) == 0) {
        throw const FileSystemException('Cannot query available disk space');
      }
      return free.value;
    } finally {
      calloc.free(path);
      calloc.free(free);
    }
  }
  // macOS statvfs uses unsigned long sizes but 32-bit block counts.
  // Linux/Android statvfs64 uses 64-bit block counts on both word sizes.
  final stat = DynamicLibrary.process()
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Uint8>),
        int Function(Pointer<Utf8>, Pointer<Uint8>)
      >(Platform.isMacOS ? 'statvfs' : 'statvfs64');
  final path = directory.toNativeUtf8();
  final buffer = calloc<Uint8>(256);
  try {
    if (stat(path, buffer) != 0) {
      throw const FileSystemException('Cannot query available disk space');
    }
    final word = sizeOf<UnsignedLong>();
    final blockSize = word == 8
        ? buffer.cast<Uint64>()[1]
        : buffer.cast<Uint32>()[1];
    final available = Platform.isMacOS
        ? (buffer + word * 2 + 8).cast<Uint32>().value
        : (buffer + word * 2 + 16).cast<Uint64>().value;
    return blockSize * available;
  } finally {
    calloc.free(path);
    calloc.free(buffer);
  }
}
