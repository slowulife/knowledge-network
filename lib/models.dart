/// 知识网络 · v3.1 数据模型（统一神经元模型）
/// 万物皆元素：名片(id/title/type/summary/tags) + 事实(facts) + 正文(body) + 附件(files)
/// 关联全部在 links（突触，存储单向、显示双向）
/// v2.2：图谱块定义（Block）由包声明，模块化布局
library;

import 'package:flutter/material.dart' hide Flow;

/// 附件（神经元挂的本地文件）
class FileRef {
  final String path; // 相对包目录路径
  final String note; // 说明

  FileRef({required this.path, this.note = ''});

  factory FileRef.fromYaml(Map<String, dynamic> m) => FileRef(
        path: (m['path'] ?? '').toString(),
        note: (m['note'] ?? '').toString(),
      );
}

/// 神经元（元素）——所有知识对象统一格式
class Neuron {
  final String id;
  final String title;
  final String type; // 类型标签（role/knowledge/book/contest...）
  final String? block; // ⭐ 可选：显式归属块（包可精确控制节点进哪个块；不写则按 type 匹配）
  final String summary; // 一句话
  final List<String> tags;
  final Map<String, dynamic> facts; // 关键信息（键值）
  final String body; // 详细介绍
  final List<FileRef> files; // 附件

  Neuron({
    required this.id,
    required this.title,
    required this.type,
    this.block,
    required this.summary,
    required this.tags,
    required this.facts,
    required this.body,
    required this.files,
  });

  factory Neuron.fromYaml(Map<String, dynamic> m) {
    final tags = (m['tags'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final facts = Map<String, dynamic>.from(m['facts'] as Map? ?? {});
    final files = (m['files'] as List?)
            ?.map((e) => FileRef.fromYaml(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        [];
    final blockRaw = (m['block'] ?? '').toString();
    return Neuron(
      id: (m['id'] ?? '').toString(),
      title: (m['title'] ?? '').toString(),
      type: (m['type'] ?? '').toString(),
      block: blockRaw.isEmpty ? null : blockRaw,
      summary: (m['summary'] ?? '').toString(),
      tags: tags,
      facts: facts,
      body: (m['body'] ?? '').toString(),
      files: files,
    );
  }

  /// 事实的显示名（中文化）
  static const Map<String, String> factLabels = {
    'salary': '薪资',
    'prospects': '前景',
    'difficulty': '难度',
    'status': '行业状态',
    'overview': '概览',
    'mainstream': '是否主流',
    'source': '来源',
    'cost': '费用',
    'note': '备注',
    'level': '级别',
    'prestige': '含金量',
    'benefit': '作用',
    'organizer': '主办方',
    'frequency': '频率',
    'url': '网址',
  };

  String factLabel(String key) => factLabels[key] ?? key;
}

/// 突触（双向关联，存储单向显示双向）
class Link {
  final String from; // 出发神经元
  final String to; // 到达神经元
  final String type; // contains/prereq/leads_to/resource/participates/related
  final String tag; // 标注（可选）

  Link({required this.from, required this.to, required this.type, this.tag = ''});

  factory Link.fromYaml(Map<String, dynamic> m) => Link(
        from: (m['from'] ?? '').toString(),
        to: (m['to'] ?? '').toString(),
        type: (m['type'] ?? 'related').toString(),
        tag: (m['tag'] ?? '').toString(),
      );

  /// 突触类型的中文名（显示用）
  static const Map<String, String> typeLabels = {
    'contains': '包含',
    'prereq': '前置',
    'leads_to': '后续',
    'resource': '资源',
    'participates': '参加',
    'related': '相关',
  };

  String typeLabel() => typeLabels[type] ?? type;
}

/// 图谱块定义（模块化布局：包可以自定义块的数量、颜色、包含的 type、位置）
/// v2.2 新增：包可声明自己的块结构（不再写死 4 块）
/// v3.1.1 新增：块级 offset 错位（网格模式下微调上下左右）；顶层 blockLayout 环形布局
class Block {
  final String id; // 块标识
  final String title; // 块标题（显示用，如"知识点"）
  final Color color; // 块主题色
  final List<String> types; // 块包含的元素 type（如 ['knowledge']）
  final int row; // 在网格中的行（0-based）
  final int col; // 在网格中的列（0-based）
  final IconData? icon; // 可选图标
  final Offset? offset; // ⭐ 可选：网格模式下额外错位（上下左右微调，避免连线重叠）

  Block({
    required this.id,
    required this.title,
    required this.color,
    required this.types,
    required this.row,
    required this.col,
    this.icon,
    this.offset,
  });

  factory Block.fromYaml(Map<String, dynamic> m) {
    // ⭐ 修复：缺失(row/col)时为 null，必须先取局部变量再判断（避免 null as num 崩溃）
    final rv = m['row'];
    final cv = m['col'];
    final off = m['offset'];
    return Block(
      id: (m['id'] ?? '').toString(),
      title: (m['title'] ?? '').toString(),
      color: _parseColor((m['color'] ?? '').toString()),
      types: (m['types'] as List?)?.map((e) => e.toString()).toList() ?? [],
      row: rv is num ? rv.toInt() : 0,
      col: cv is num ? cv.toInt() : 0,
      icon: _parseIcon((m['icon'] ?? '').toString()),
      offset: off is List && off.length == 2 && off[0] is num && off[1] is num
          ? Offset((off[0] as num).toDouble(), (off[1] as num).toDouble())
          : null,
    );
  }

  static Color _parseColor(String hex) {
    if (hex.isEmpty) return const Color(0xFF888780);
    try {
      var v = hex.replaceFirst('#', '');
      if (v.length == 6) v = 'FF$v';
      return Color(int.parse(v, radix: 16));
    } catch (_) {
      return const Color(0xFF888780);
    }
  }

  static IconData? _parseIcon(String name) {
    // 简化版：只支持几个常见图标，避免循环依赖
    switch (name) {
      case 'knowledge':
      case 'lightbulb':
        return Icons.lightbulb_outline;
      case 'role':
      case 'work':
        return Icons.work_outline;
      case 'resource':
      case 'library':
        return Icons.library_books_outlined;
      case 'contest':
      case 'trophy':
        return Icons.emoji_events_outlined;
      default:
        return null;
    }
  }
}

/// 一个知识包（GraphData）
class GraphData {
  final String format;
  final String id;
  final String title;
  final String description;
  final String blockLayout; // ⭐ 块布局模式：'grid'(默认网格) | 'ring'(环形)
  final Map<String, Neuron> neurons;
  final List<Link> links;
  final List<Block> blocks; // ⭐ 块定义（包可自定义，未声明时 loader 生成默认 4 块）
  String packageDir = '';

  GraphData({
    required this.format,
    required this.id,
    required this.title,
    required this.description,
    this.blockLayout = 'grid',
    required this.neurons,
    required this.links,
    this.blocks = const [],
  });

  factory GraphData.fromYaml(Map<String, dynamic> yaml) {
    final neurons = <String, Neuron>{};
    for (final item in (yaml['elements'] as List?) ?? []) {
      final n = Neuron.fromYaml(Map<String, dynamic>.from(item as Map));
      if (n.id.isNotEmpty) neurons[n.id] = n;
    }
    final links = (yaml['links'] as List?)
            ?.map((e) => Link.fromYaml(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        [];
    final blocks = (yaml['blocks'] as List?)
            ?.map((e) => Block.fromYaml(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        [];
    return GraphData(
      format: (yaml['format'] ?? '').toString(),
      id: (yaml['id'] ?? '').toString(),
      title: (yaml['title'] ?? '').toString(),
      description: (yaml['description'] ?? '').toString(),
      blockLayout: (yaml['blockLayout'] ?? 'grid').toString(),
      neurons: neurons,
      links: links,
      blocks: blocks,
    );
  }

  /// 某神经元的邻居：[神经元id, 突触类型, 标注, 方向(当前神经元是from还是to)]
  /// 直接遍历 links（双向），不经过中间列表（删除了未使用的 linksOf 死代码）
  List<Neighbor> neighborsOf(String neuronId) {
    final result = <Neighbor>[];
    for (final l in links) {
      if (l.from == neuronId) {
        result.add(Neighbor(l.to, l.type, l.tag, out: true));
      } else if (l.to == neuronId) {
        result.add(Neighbor(l.from, l.type, l.tag, out: false));
      }
    }
    return result;
  }

  /// 类型的中文名（显示/图谱用）
  static const Map<String, String> typeNames = {
    'industry': '行业',
    'role': '工种',
    'knowledge': '知识点',
    'book': '课本',
    'course': '课程',
    'tutorial': '教程',
    'docs': '文档',
    'video': '视频',
    'software': '软件',
    'project': '项目',
    'practice': '题库',
    'community': '社区',
    'certification': '认证',
    'job': '就业',
    'person': '人物',
    'website': '网站',
    'news': '资讯',
    'contest': '比赛',
    'file': '文件',
    'note': '笔记',
  };

  String typeName(String type) => typeNames[type] ?? type;
}

/// 邻居（双向突触的一头）
class Neighbor {
  final String id;
  final String linkType;
  final String tag;
  final bool out; // true=当前神经元是突触的 from；false=是 to

  Neighbor(this.id, this.linkType, this.tag, {required this.out});
}
