import 'dart:convert';

import 'package:file_picker/file_picker.dart';

import 'core_bridge.dart';
import 'library_transfer.dart';

/// 剧库导入导出的共享实现。
///
/// 网页版把入口放在管理员设置里，需要先登录；APP 是本机应用，剧库文件属于本机用户，
/// 因此在未解锁的情况下也允许导入导出，解锁页和设置页共用这里的逻辑。
class LibraryTransferOutcome {
  const LibraryTransferOutcome({required this.message, this.importedSources});

  final String message;
  final Set<String>? importedSources;
}

class LibraryTransfer {
  const LibraryTransfer(this.repository);

  final AppRepository repository;

  Future<LibraryTransferOutcome> exportLibrary() async {
    final payload = await repository.exportLibraryPackage();
    final saved = await FilePicker.saveFile(
      fileName: libraryPackageFileName(DateTime.now()),
      bytes: payload,
      mimeType: 'application/x-xz',
    );
    if (saved == null) {
      return const LibraryTransferOutcome(message: '已取消导出。');
    }
    final count = repository.libraryPackageCount;
    return LibraryTransferOutcome(
      message: '已导出 $count 部剧库条目（XZ 压缩包），可在「果果剧库」或网页版中导入。',
    );
  }

  Future<LibraryTransferOutcome> importLibrary() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xz', 'json'],
    );
    if (file == null) {
      return const LibraryTransferOutcome(message: '已取消导入。');
    }
    final size = await file.length();
    if (size == null || size > libraryExchangeMaxBytes) {
      throw const FormatException('剧库文件过大或无法读取');
    }
    final payload = await file.readAsBytes();
    final LibraryImportResult result;
    final Set<String> sources;
    if (libraryPackageIsXZ(payload)) {
      result = await repository.importLibraryPackage(payload);
      sources = result.sources;
    } else {
      final document = parseLibraryPackage(utf8.decode(payload));
      final dramas = document['dramas'] as List;
      sources = dramas
          .map((item) => item is Map ? (item['source'] as String? ?? '') : '')
          .where((source) => source.isNotEmpty)
          .toSet();
      result = await repository.importLibrary(document);
    }
    return LibraryTransferOutcome(
      message: result.summary(),
      importedSources: sources,
    );
  }
}
