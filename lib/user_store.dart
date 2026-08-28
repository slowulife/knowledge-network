/// 用户数据层（v3：阶段取消，节点直挂时间）
/// 收藏、学习流程（节点级时间安排 + 自动状态）、自定义附件、固定起始节点
/// 设计：单例 + ChangeNotifier，setState 后自动落盘
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// 用户数据文件
const String kUserDataFile = r'D:\knowledge_network\user_data\user_data.json';

/// ⭐ 节点学习计划（直接挂到节点上，无阶段）
class NodePlan {
  DateTime? startDate; // 计划开始日期
  DateTime? endDate; // 计划结束日期
  DateTime? completedDate; // 实际完成日期（可选，不填则按时间推算）

  NodePlan({this.startDate, this.endDate, this.completedDate});

  /// ⭐ 自动状态：按今天日期推算
  ///   实际完成 → 已学
  ///   计划时间到了（today > endDate）→ 已学
  ///   计划时间内 → 在学
  ///   未开始 → 未学
  ///   未设时间 → 未学
  String get status {
    if (completedDate != null) return '已学';
    if (startDate == null || endDate == null) return '未学';
    final today = DateTime.now();
    final t = DateTime(today.year, today.month, today.day);
    final s = DateTime(startDate!.year, startDate!.month, startDate!.day);
    final e = DateTime(endDate!.year, endDate!.month, endDate!.day);
    if (t.isBefore(s)) return '未学';
    if (t.isAfter(e)) return '已学';
    return '在学';
  }

  /// 计划天数
  int get planDays {
    if (startDate == null || endDate == null) return 0;
    return endDate!.difference(startDate!).inDays + 1;
  }

  Map<String, dynamic> toJson() => {
        'start': startDate?.toIso8601String(),
        'end': endDate?.toIso8601String(),
        'done': completedDate?.toIso8601String(),
      };

  factory NodePlan.fromJson(Map<String, dynamic> m) => NodePlan(
        startDate: _parseDate(m['start']),
        endDate: _parseDate(m['end']),
        completedDate: _parseDate(m['done']),
      );

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}

/// ⭐ 一条学习流程（v3：阶段取消，节点直接挂时间）
class Flow {
  String id;
  String name;
  /// ⭐ 节点级时间安排：id → 学习计划
  Map<String, NodePlan> plans;

  Flow({required this.id, required this.name, Map<String, NodePlan>? plans})
      : plans = plans ?? {};

  /// 全部节点 id
  Iterable<String> get allNodeIds => plans.keys;

  /// 进度统计（状态由 NodePlan 按今日推算）
  int get total => plans.length;
  int get done => plans.values.where((p) => p.status == '已学').length;
  int get learning => plans.values.where((p) => p.status == '在学').length;
  double get progress => total == 0 ? 0.0 : done / total;

  /// 第一个未完成节点（用于"开始/继续"按钮）
  String? get firstUnlearned {
    for (final e in plans.entries) {
      if (e.value.status != '已学') return e.key;
    }
    return null;
  }

  /// ⭐ 取得某节点的状态（按今日推算）
  String statusOf(String id) => plans[id]?.status ?? '未学';

  /// 节点计划信息
  NodePlan? planOf(String id) => plans[id];

  /// ⭐ 添加节点到流程（默认无时间安排）
  void addNode(String id) {
    if (plans.containsKey(id)) return;
    plans[id] = NodePlan();
  }

  /// 设置节点时间安排
  void setNodePlan(String id, NodePlan plan) {
    plans[id] = plan;
  }

  /// 移除节点
  void removeNode(String id) {
    plans.remove(id);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'plans': {for (final e in plans.entries) e.key: e.value.toJson()},
      };

  factory Flow.fromJson(Map<String, dynamic> m) {
    final f = Flow(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
    );
    // 兼容 v2 旧数据：phases 里的节点 id 全部加入（无时间安排）
    final oldPhases = (m['phases'] as List?) ?? [];
    for (final p in oldPhases) {
      for (final id in ((p as Map)['nodeIds'] as List?) ?? []) {
        f.addNode(id.toString());
      }
    }
    // 新格式：plans 字典
    final plans = (m['plans'] as Map?) ?? {};
    for (final e in plans.entries) {
      f.plans[e.key.toString()] =
          NodePlan.fromJson(Map<String, dynamic>.from(e.value as Map));
    }
    return f;
  }
}

/// 自定义附件（用户自己选的文件夹/快捷方式）
class UserAttachment {
  String path;
  String note;
  UserAttachment({required this.path, this.note = ''});

  Map<String, dynamic> toJson() => {'path': path, 'note': note};
  factory UserAttachment.fromJson(Map<String, dynamic> m) => UserAttachment(
        path: (m['path'] ?? '').toString(),
        note: (m['note'] ?? '').toString(),
      );
}

/// 全局用户数据仓库
class UserStore extends ChangeNotifier {
  static final UserStore instance = UserStore._();
  UserStore._() {
    _load();
  }

  final Set<String> _favorites = {};
  final List<Flow> _flows = [];
  final Map<String, List<UserAttachment>> _attachments = {};
  String? _startPkgId;
  String? _startNeuronId;
  String? _activeAddFlowId; // ⭐ 添加模式：正在往哪个流程加节点（null=关闭）
  // ⭐ 块布局位置（包id → 块id → [dx, dy]）：用户拖动块后的位置，退出软件不丢
  final Map<String, Map<String, List<double>>> _blockLayouts = {};

  // ---- 访问 ----
  bool isFavorite(String id) => _favorites.contains(id);
  int get favoritesCount => _favorites.length;
  List<String> get favorites => _favorites.toList();
  List<Flow> get flows => List.unmodifiable(_flows);
  List<UserAttachment> attachmentsOf(String id) =>
      List.unmodifiable(_attachments[id] ?? const []);
  String? get startPkgId => _startPkgId;
  String? get startNeuronId => _startNeuronId;

  // ⭐ 添加模式
  String? get activeAddFlowId => _activeAddFlowId;
  Flow? get activeAddFlow {
    if (_activeAddFlowId == null) return null;
    for (final f in _flows) {
      if (f.id == _activeAddFlowId) return f;
    }
    return null;
  }

  void setActiveAddFlow(String? flowId) {
    _activeAddFlowId = flowId;
    notifyListeners();
  }

  // ---- 收藏 ----
  void toggleFavorite(String id) {
    if (!_favorites.remove(id)) _favorites.add(id);
    _save();
    notifyListeners();
  }

  // ---- 流程操作 ----
  Flow createFlow(String name) {
    final f = Flow(id: 'f${DateTime.now().millisecondsSinceEpoch}', name: name);
    _flows.add(f);
    _save();
    notifyListeners();
    return f;
  }

  void updateFlow(Flow f) {
    final i = _flows.indexWhere((x) => x.id == f.id);
    if (i >= 0) {
      _flows[i] = f;
      _save();
      notifyListeners();
    }
  }

  void deleteFlow(String id) {
    _flows.removeWhere((f) => f.id == id);
    _save();
    notifyListeners();
  }

  /// 把节点加入流程（无时间安排占位）
  void addNodeToFlow(String flowId, String neuronId) {
    final f = _flows.firstWhere((x) => x.id == flowId, orElse: () => createFlow('未命名流程'));
    if (f.id == flowId) {
      f.addNode(neuronId);
      updateFlow(f);
    }
  }

  /// 设置节点学习计划（startDate / endDate / completedDate）
  void setNodePlan(String flowId, String neuronId, NodePlan plan) {
    final f = _flows.firstWhere((x) => x.id == flowId, orElse: () => createFlow('未命名流程'));
    if (f.id == flowId) {
      f.setNodePlan(neuronId, plan);
      updateFlow(f);
    }
  }

  /// 删除节点
  void removeNodeFromFlow(String flowId, String neuronId) {
    final f = _flows.firstWhere((x) => x.id == flowId, orElse: () => createFlow('未命名流程'));
    if (f.id == flowId) {
      f.removeNode(neuronId);
      updateFlow(f);
    }
  }

  // ---- 附件 ----
  void addAttachment(String neuronId, String path, {String note = ''}) {
    final list = _attachments.putIfAbsent(neuronId, () => []);
    list.add(UserAttachment(path: path, note: note));
    _save();
    notifyListeners();
  }

  void removeAttachment(String neuronId, int index) {
    final list = _attachments[neuronId];
    if (list != null && index >= 0 && index < list.length) {
      list.removeAt(index);
      if (list.isEmpty) _attachments.remove(neuronId);
      _save();
      notifyListeners();
    }
  }

  // ---- 固定起始节点 ----
  void setStart(String pkgId, String neuronId) {
    _startPkgId = pkgId.isEmpty ? null : pkgId;
    _startNeuronId = neuronId.isEmpty ? null : neuronId;
    _save();
    notifyListeners();
  }

  // ---- 块布局位置（手动保存/重置，退出软件不丢） ----
  Map<String, List<double>>? blockLayoutOf(String pkgId) => _blockLayouts[pkgId];

  void saveBlockLayout(String pkgId, Map<String, List<double>> layouts) {
    _blockLayouts[pkgId] = layouts;
    _save();
    notifyListeners();
  }

  /// ⭐ 重置：清除该包保存的块位置（恢复默认自动布局）
  void clearBlockLayout(String pkgId) {
    _blockLayouts.remove(pkgId);
    _save();
    notifyListeners();
  }

  // ---- 持久化 ----
  void _load() {
    try {
      final f = File(kUserDataFile);
      if (!f.existsSync()) return;
      final data = jsonDecode(f.readAsStringSync(encoding: utf8)) as Map<String, dynamic>;
      for (final id in (data['favorites'] as List?) ?? []) {
        _favorites.add(id.toString());
      }
      for (final item in (data['flows'] as List?) ?? []) {
        _flows.add(Flow.fromJson(Map<String, dynamic>.from(item as Map)));
      }
      final att = (data['attachments'] as Map?) ?? {};
      for (final e in att.entries) {
        _attachments[e.key.toString()] = [
          for (final it in (e.value as List?) ?? [])
            UserAttachment.fromJson(Map<String, dynamic>.from(it as Map))
        ];
      }
      _startPkgId = (data['startPkgId'] ?? '').toString().isEmpty
          ? null
          : data['startPkgId'].toString();
      _startNeuronId = (data['startNeuronId'] ?? '').toString().isEmpty
          ? null
          : data['startNeuronId'].toString();
      final bl = (data['blockLayouts'] as Map?) ?? {};
      for (final e in bl.entries) {
        _blockLayouts[e.key.toString()] = {
          for (final fe in ((e.value as Map?) ?? {}).entries)
            fe.key.toString(): [
              for (final v in (fe.value as List? ?? [])) (v as num).toDouble()
            ],
        };
      }
    } catch (_) {
      // 数据损坏不影响启动（Postel 原则）
    }
  }

  void _save() {
    try {
      final f = File(kUserDataFile);
      if (!f.parent.existsSync()) f.parent.createSync(recursive: true);
      f.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
            'favorites': _favorites.toList(),
            'flows': [for (final fl in _flows) fl.toJson()],
            'attachments': {
              for (final e in _attachments.entries) e.key: [for (final a in e.value) a.toJson()]
            },
            'startPkgId': _startPkgId,
            'startNeuronId': _startNeuronId,
            'blockLayouts': _blockLayouts,
          }),
          encoding: utf8);
    } catch (_) {}
  }
}
