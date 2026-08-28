/// 知识包加载器：扫描扩展包目录 → 解析 graph.yaml → 建内存索引
/// 容错：单个包失败不影响其他包；坏文件显示占位不崩溃（Postel 原则）
library;

import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';
import 'models.dart';

/// 扩展包根目录（软件读取的位置，英文路径）
const String kPackagesDir = r'D:\packages';

/// 加载结果
class LoadResult {
  final List<GraphData> packages;
  final List<String> errors; // 失败的包及原因

  LoadResult(this.packages, this.errors);

  bool get hasErrors => errors.isNotEmpty;
}

/// 加载所有知识包
Future<LoadResult> loadAllPackages([String? dir]) async {
  final packages = <GraphData>[];
  final errors = <String>[];
  final root = dir ?? kPackagesDir;

  final rootDir = Directory(root);
  if (!rootDir.existsSync()) {
    return LoadResult(packages, ['扩展包目录不存在: $root']);
  }

  // 每个子目录 = 一个知识包
  for (final entry in rootDir.listSync()) {
    if (entry is! Directory) continue;
    // 跳过隐藏目录（如 .git）
    if (entry.path.split(Platform.pathSeparator).last.startsWith('.')) continue;

    final graphFile = File('${entry.path}${Platform.pathSeparator}graph.yaml');
    if (!graphFile.existsSync()) {
      errors.add('${entry.path}: 缺少 graph.yaml');
      continue;
    }
    try {
      final content = graphFile.readAsStringSync(encoding: utf8);
      final yaml = loadYaml(content);
      final graph = GraphData.fromYaml(Map<String, dynamic>.from(yaml as Map));
      graph.packageDir = entry.path; // 记录包目录（文件管理用）
      // 基本校验：有元素才算有效包
      if (graph.neurons.isEmpty) {
        errors.add('${entry.path}: 包内没有元素（elements 为空）');
        continue;
      }
      packages.add(graph);
    } catch (e) {
      errors.add('${entry.path}: 解析失败（$e）');
    }
  }
  return LoadResult(packages, errors);
}

/// 包内文件（资源库里的实体文件）
class PackageFile {
  final String name; // 文件名
  final String relPath; // 相对包目录（如 resources/课本/x.pdf）
  final String fullPath; // 绝对路径
  final String ext; // 扩展名（小写）

  PackageFile({
    required this.name,
    required this.relPath,
    required this.fullPath,
    required this.ext,
  });
}

/// 列出知识包 resources/ 下的所有文件（递归）
List<PackageFile> listPackageFiles(GraphData pkg) {
  final sep = Platform.pathSeparator;
  final files = <PackageFile>[];
  if (pkg.packageDir.isEmpty) return files;
  final resDir = Directory('${pkg.packageDir}${sep}resources');
  if (!resDir.existsSync()) return files;
  for (final e in resDir.listSync(recursive: true)) {
    if (e is! File) continue;
    final full = e.path;
    final name = full.split(sep).last;
    files.add(PackageFile(
      name: name,
      relPath: full.substring(pkg.packageDir.length + 1),
      fullPath: full,
      ext: name.contains('.') ? name.split('.').last.toLowerCase() : '',
    ));
  }
  return files;
}

/// 用系统默认程序打开本地文件（Windows: start 命令）
Future<void> openLocalFile(String fullPath) async {
  try {
    await Process.start('cmd', ['/c', 'start', '', fullPath]);
  } catch (_) {
    // 打开失败静默（容错）
  }
}
