/// 学习流程管理（v3：阶段取消，节点直接挂时间）
///   - 每节点挂时间安排（开始日期 + 结束日期）
///   - 状态按今日日期自动推算（未开始/在学/已学）
///   - 节点支持跳转、设时间、标完成、删除、调序（↑↓）
///   - 添加节点：新建流程自动进入"添加模式"（点图谱节点逐个加入）
/// ⭐ 节点显示中文标题（不再显示英文 id）
library;

import 'package:flutter/material.dart' hide Flow;
import 'models.dart';
import 'user_store.dart';

/// 中文标题解析
String _titleOf(GraphData graph, String id) => graph.neurons[id]?.title ?? id;

/// 打开学习流程管理面板
Future<void> showFlowsSheet(
  BuildContext context, {
  required GraphData graph,
  required void Function(String neuronId) onJumpTo,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _FlowsSheet(graph: graph, onJumpTo: onJumpTo),
  );
}

/// 把当前节点加入某个流程（选择或新建）
Future<void> showAddToFlowDialog(BuildContext context, String neuronId, GraphData graph) async {
  final store = UserStore.instance;
  final flowId = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _PickFlowSheet(neuronId: neuronId, graph: graph),
  );
  if (flowId != null && context.mounted) {
    store.addNodeToFlow(flowId, neuronId);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('已加入流程'), duration: Duration(seconds: 1)));
    }
  }
}

// =====================================================
// 选择流程加入节点
// =====================================================

class _PickFlowSheet extends StatefulWidget {
  final String neuronId;
  final GraphData graph;
  const _PickFlowSheet({required this.neuronId, required this.graph});

  @override
  State<_PickFlowSheet> createState() => _PickFlowSheetState();
}

class _PickFlowSheetState extends State<_PickFlowSheet> {
  final _store = UserStore.instance;

  Future<void> _createAndAdd() async {
    final name = await _promptName(context, '新建学习流程', '流程名称');
    if (name == null || name.isEmpty || !mounted) return;
    final f = _store.createFlow(name);
    Navigator.pop(context, f.id);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('加入学习流程 · ${_titleOf(widget.graph, widget.neuronId)}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            if (_store.flows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('还没有流程，先新建一个吧', style: TextStyle(fontSize: 13, color: Colors.grey)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final f in _store.flows)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.route, color: Color(0xFF185FA5)),
                        title: Text(f.name, style: const TextStyle(fontSize: 14)),
                        subtitle: Text('${f.done}/${f.total} 已完成',
                            style: const TextStyle(fontSize: 11)),
                        onTap: () => Navigator.pop(context, f.id),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _createAndAdd,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建流程并加入'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// 流程管理面板
// =====================================================

class _FlowsSheet extends StatefulWidget {
  final GraphData graph;
  final void Function(String neuronId) onJumpTo;
  const _FlowsSheet({required this.graph, required this.onJumpTo});

  @override
  State<_FlowsSheet> createState() => _FlowsSheetState();
}

class _FlowsSheetState extends State<_FlowsSheet> {
  final _store = UserStore.instance;

  /// 新建流程后自动进入"添加模式"
  Future<void> _createFlow() async {
    final name = await _promptName(context, '新建学习流程', '流程名称（如：前端学习计划）');
    if (name == null || name.isEmpty || !mounted) return;
    final f = _store.createFlow(name);
    _store.setActiveAddFlow(f.id);
    if (context.mounted) Navigator.pop(context);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('「${f.name}」已创建！点图谱节点加入（顶部横幅可完成）'),
          duration: const Duration(seconds: 3),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) => ListenableBuilder(
          listenable: _store,
          builder: (context, _) {
            final flows = _store.flows;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.route, size: 18, color: Color(0xFF185FA5)),
                      const SizedBox(width: 6),
                      const Text('学习流程',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _createFlow,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('新建流程'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: flows.isEmpty
                      ? const Center(
                          child: Text('还没有学习流程\n\n点右上角「新建流程」开始规划',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey, fontSize: 13)))
                      : ListView(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.all(12),
                          children: [
                            for (final f in flows) _FlowCard(f, graph: widget.graph, onJumpTo: widget.onJumpTo),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// =====================================================
// 流程卡片（v3：无阶段，节点直接挂时间）
// =====================================================

class _FlowCard extends StatefulWidget {
  final Flow flow;
  final GraphData graph;
  final void Function(String neuronId) onJumpTo;
  const _FlowCard(this.flow, {required this.graph, required this.onJumpTo});

  @override
  State<_FlowCard> createState() => _FlowCardState();
}

class _FlowCardState extends State<_FlowCard> {
  late Flow _f;

  @override
  void initState() {
    super.initState();
    _f = widget.flow;
  }

  @override
  void didUpdateWidget(covariant _FlowCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flow != widget.flow) {
      _f = widget.flow;
    }
  }

  Future<void> _renameFlow() async {
    final name = await _promptName(context, '重命名流程', '流程名称', initial: _f.name);
    if (name == null || name.isEmpty || !mounted) return;
    setState(() => _f.name = name);
    UserStore.instance.updateFlow(_f);
  }

  void _start() {
    final id = _f.firstUnlearned;
    if (id == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('全部学完啦 🎉'), duration: Duration(seconds: 1)));
      return;
    }
    Navigator.pop(context);
    widget.onJumpTo(id);
  }

  /// 主界面点选添加（点图谱节点即加入）
  void _enterAddMode() {
    UserStore.instance.setActiveAddFlow(_f.id);
    Navigator.pop(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('正在向「${_f.name}」添加节点：点图谱节点加入'),
        duration: const Duration(seconds: 3),
      ));
  }

  /// 排序：按 startDate 升序，无时间的在最后
  List<String> _sortedIds() {
    final ids = _f.plans.keys.toList();
    ids.sort((a, b) {
      final pa = _f.plans[a]!;
      final pb = _f.plans[b]!;
      if (pa.startDate == null && pb.startDate == null) return 0;
      if (pa.startDate == null) return 1;
      if (pb.startDate == null) return -1;
      return pa.startDate!.compareTo(pb.startDate!);
    });
    return ids;
  }

  @override
  Widget build(BuildContext context) {
    final store = UserStore.instance;
    final ids = _sortedIds();
    return Card(
      elevation: 0,
      color: const Color(0xFFF7F9FC),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _renameFlow,
                    child: Text(_f.name,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
                Text('${_f.done} / ${_f.total}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF5F5E5A))),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Color(0xFFE24B4A)),
                  tooltip: '删除流程',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    store.deleteFlow(_f.id);
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                        content: Text('已删除「${_f.name}」'),
                        duration: const Duration(seconds: 1),
                      ));
                  },
                ),
              ],
            ),
            // 进度条
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _f.progress,
                minHeight: 8,
                color: const Color(0xFF1D9E75),
                backgroundColor: const Color(0xFFE8F0EA),
              ),
            ),
            // 开始/继续 + 主界面添加按钮
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _f.total == 0 ? null : _start,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: Text(_f.done > 0
                        ? (_f.firstUnlearned == null ? '已完成 🎉' : '继续学习')
                        : '开始学习'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1D9E75),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 32),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.touch_app, size: 17, color: Color(0xFF1D9E75)),
                    tooltip: '主界面点选添加',
                    visualDensity: VisualDensity.compact,
                    onPressed: _enterAddMode,
                  ),
                ],
              ),
            ),
            // 节点列表（按时间排序）
            if (_f.total == 0)
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 8, 0, 0),
                child: Text('（空，点上面"主界面点选添加"按钮，点图谱节点即可加入）',
                    style: TextStyle(fontSize: 11, color: Color(0xFFB4B2A9))),
              )
            else ...[
              const SizedBox(height: 4),
              for (int i = 0; i < ids.length; i++)
                _PlanRow(
                  flow: _f,
                  graph: widget.graph,
                  nodeId: ids[i],
                  index: i,
                  total: ids.length,
                  onJump: () => widget.onJumpTo(ids[i]),
                  onSetPlan: (plan) {
                    setState(() => _f.setNodePlan(ids[i], plan));
                    UserStore.instance.updateFlow(_f);
                  },
                  onMarkDone: () {
                    final old = _f.plans[ids[i]] ?? NodePlan();
                    setState(() => _f.setNodePlan(
                        ids[i],
                        NodePlan(
                            startDate: old.startDate,
                            endDate: old.endDate,
                            completedDate: DateTime.now())));
                    UserStore.instance.updateFlow(_f);
                  },
                  onRemove: () {
                    setState(() => _f.removeNode(ids[i]));
                    UserStore.instance.updateFlow(_f);
                  },
                  onMoveUp: i > 0
                      ? () {
                          final list = _f.plans;
                          final keys = list.keys.toList();
                          final a = keys[i - 1];
                          final b = keys[i];
                          // 交换两个 plan
                          final pa = list[a]!;
                          list[a] = list[b]!;
                          list[b] = pa;
                          setState(() {});
                          UserStore.instance.updateFlow(_f);
                        }
                      : null,
                  onMoveDown: i < ids.length - 1
                      ? () {
                          final list = _f.plans;
                          final keys = list.keys.toList();
                          final a = keys[i];
                          final b = keys[i + 1];
                          final pa = list[a]!;
                          list[a] = list[b]!;
                          list[b] = pa;
                          setState(() {});
                          UserStore.instance.updateFlow(_f);
                        }
                      : null,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 节点计划行（v3：时间段 + 自动状态）
class _PlanRow extends StatefulWidget {
  final Flow flow;
  final GraphData graph;
  final String nodeId;
  final int index;
  final int total;
  final VoidCallback onJump;
  final void Function(NodePlan plan) onSetPlan;
  final VoidCallback onMarkDone;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  const _PlanRow({
    required this.flow,
    required this.graph,
    required this.nodeId,
    required this.index,
    required this.total,
    required this.onJump,
    required this.onSetPlan,
    required this.onMarkDone,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  @override
  State<_PlanRow> createState() => _PlanRowState();
}

class _PlanRowState extends State<_PlanRow> {
  /// 弹时间设置对话框（先选 start，再选 end）
  Future<void> _pickDateRange() async {
    final cur = widget.flow.plans[widget.nodeId] ?? NodePlan();
    final start = await showDatePicker(
      context: context,
      initialDate: cur.startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '选择学习开始日期',
    );
    if (start == null || !mounted) return;
    final end = await showDatePicker(
      context: context,
      initialDate: cur.endDate ?? start.add(const Duration(days: 6)),
      firstDate: start,
      lastDate: DateTime(2100),
      helpText: '选择学习结束日期',
    );
    if (end == null || !mounted) return;
    widget.onSetPlan(NodePlan(
        startDate: start, endDate: end, completedDate: cur.completedDate));
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.flow.plans[widget.nodeId] ?? NodePlan();
    final status = plan.status;
    final color = _statusColor(status);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text('${widget.index + 1}',
                style: const TextStyle(fontSize: 10, color: Color(0xFF888780))),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: widget.onJump,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(_titleOf(widget.graph, widget.nodeId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: color, fontWeight: FontWeight.w500)),
                  ),
                ),
                Row(
                  children: [
                    // 状态（自动按时间推算）
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(status,
                          style: TextStyle(
                              fontSize: 10, color: color, fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(width: 6),
                    // 时间段（点击设置）
                    InkWell(
                      onTap: _pickDateRange,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: plan.startDate != null
                              ? const Color(0xFFE8F1FB)
                              : const Color(0xFFF2F1ED),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          plan.startDate != null
                              ? '${_fmt(plan.startDate!)} → ${_fmt(plan.endDate!)}'
                              : '设时间',
                          style: TextStyle(
                              fontSize: 10,
                              color: plan.startDate != null
                                  ? const Color(0xFF185FA5)
                                  : const Color(0xFF888780)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 标记完成
          IconButton(
            icon: Icon(Icons.check_circle_outline, size: 14, color: const Color(0xFF1D9E75)),
            tooltip: '标记完成',
            visualDensity: VisualDensity.compact,
            onPressed: status == '已学' ? null : widget.onMarkDone,
          ),
          // 上移
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 13, color: Color(0xFF5F5E5A)),
            tooltip: '上移',
            visualDensity: VisualDensity.compact,
            onPressed: widget.onMoveUp,
          ),
          // 下移
          IconButton(
            icon: const Icon(Icons.arrow_downward, size: 13, color: Color(0xFF5F5E5A)),
            tooltip: '下移',
            visualDensity: VisualDensity.compact,
            onPressed: widget.onMoveDown,
          ),
          // 删除
          IconButton(
            icon: const Icon(Icons.close, size: 13, color: Color(0xFFB4B2A9)),
            tooltip: '移除',
            visualDensity: VisualDensity.compact,
            onPressed: widget.onRemove,
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) => '${d.month}/${d.day}';

  static Color _statusColor(String s) {
    switch (s) {
      case '已学':
        return const Color(0xFF1D9E75);
      case '在学':
        return const Color(0xFFEF9F27);
      default:
        return const Color(0xFFB4B2A9);
    }
  }
}

Future<String?> _promptName(BuildContext context, String title, String hint, {String initial = ''}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint, isDense: true),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
