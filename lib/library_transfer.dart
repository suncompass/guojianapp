import 'dart:convert';
import 'dart:typed_data';

import 'core_bridge.dart';

const libraryExchangeKind = 'library';
const libraryExchangeVersion = 1;
const libraryExchangeMaxBytes = 32 << 20;
const libraryExchangeMaxEntries = 200000;

class LibraryImportResult {
  const LibraryImportResult({
    this.imported = 0,
    this.merged = 0,
    this.rejected = 0,
    this.denied = 0,
    this.total = 0,
    this.sources = const <String>{},
  });
  final int imported;
  final int merged;
  final int rejected;
  final int denied;
  final int total;
  final Set<String> sources;
  factory LibraryImportResult.fromJson(Map<String, dynamic> json) =>
      LibraryImportResult(
        imported: (json['imported'] as num?)?.toInt() ?? 0,
        merged: (json['merged'] as num?)?.toInt() ?? 0,
        rejected: (json['rejected'] as num?)?.toInt() ?? 0,
        denied: (json['denied'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
        sources:
            (json['sources'] as Map?)?.keys
                .map((key) => key.toString())
                .toSet() ??
            const <String>{},
      );
  String summary() {
    final parts = ['导入完成：新增 $imported 部，补全 $merged 部'];
    if (rejected > 0) parts.add('跳过无效条目 $rejected 条');
    if (denied > 0) parts.add('跳过无权站源 $denied 条');
    return '${parts.join('，')}；本地剧库共 $total 部。';
  }
}

const libraryPackageXZMagic = <int>[0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00];

String libraryPackageFileName(DateTime now) {
  String pad(int value) => value.toString().padLeft(2, '0');
  return '剧库-${now.year}-${pad(now.month)}-${pad(now.day)}.xz';
}

bool libraryPackageIsXZ(Uint8List payload) {
  if (payload.length < libraryPackageXZMagic.length) return false;
  for (var index = 0; index < libraryPackageXZMagic.length; index += 1) {
    if (payload[index] != libraryPackageXZMagic[index]) return false;
  }
  return true;
}

String encodeLibraryPackage(Map<String, dynamic> document) =>
    jsonEncode(document);

Map<String, dynamic> parseLibraryPackage(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) throw AppFailure('剧库文件是空的');
  if (trimmed.length > libraryExchangeMaxBytes) {
    throw AppFailure('剧库文件超过 32 MB，无法导入');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    throw AppFailure('剧库文件不是有效的 JSON');
  }
  if (decoded is! Map<String, dynamic>) {
    throw AppFailure('剧库文件的顶层必须是对象');
  }
  final document = decoded;
  final kind = document['kind'];
  if (kind != null && kind != libraryExchangeKind) {
    throw AppFailure('这不是剧库文件');
  }
  if ((document['version'] as num?)?.toInt() != libraryExchangeVersion) {
    throw AppFailure('剧库文件版本不兼容');
  }
  final dramas = document['dramas'];
  if (dramas != null && dramas is! List) {
    throw AppFailure('剧库文件缺少剧集条目');
  }
  if (dramas is List && dramas.length > libraryExchangeMaxEntries) {
    throw AppFailure('剧库文件条目超过 20 万条，无法导入');
  }
  document['dramas'] = dramas is List ? dramas : <dynamic>[];
  return document;
}
