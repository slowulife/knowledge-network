/// 图谱画布（自绘版，借鉴 d3-force 聚类分组 + 防重叠思路）
/// 布局：按类型分块（工种/知识点/资源/比赛），块内网格排列 —— 纯加减法，
///       数学上不可能产生 NaN、不可能重叠（对应 d3 的 forceCluster + forceCollide）
/// ⭐ 自适应：画布尺寸按每类元素数量动态计算（内容变多不溢出、不裁剪）
/// 连线：CustomPaint 按突触类型着色 + 终点箭头（指向性明确：A→B = 流向 B）
/// 节点：Stack + Positioned 圆角卡片，点击选中
/// 缩放平移：InteractiveViewer（标准组件）
/// 交互：①类型筛选按钮（点击高亮对应类型）②选中聚焦（邻居亮其余淡）
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'models.dart';
import 'user_store.dart';

/// 元素类型 → 颜色
Color typeColor(String type) {
  switch (type) {
    case 'industry':
      return const Color(0xFF185FA5);
    case 'role':
      return const Color(0xFF378ADD);
    case 'knowledge':
      return const Color(0xFF1D9E75);
    case 'contest':
      return const Color(0xFFEF9F27);
    default:
      return const Color(0xFF8A6FBF); // 资源类统一紫色
  }
}

/// 突触类型 → 连线颜色
Color linkColor(String type) {
  switch (type) {
    case 'contains':
      return const Color(0xFF378ADD);
    case 'prereq':
      return const Color(0xFFEF9F27);
    case 'leads_to':
      return const Color(0xFF1D9E75);
    case 'resource':
      return const Color(0xFF8A6FBF);
    case 'participates':
      return const Color(0xFFE24B4A);
    default:
      return const Color(0xFF888780);
  }
}

/// 类型筛选定义（⭐ 由包的 blocks 动态生成，不再写死——保证任何行业包都可扩展）
class _TypeFilter {
  final String label;
  final IconData icon;
  final bool Function(String type) match;
  const _TypeFilter(this.label, this.icon, this.match);
}

/// ⭐ 按包的块定义动态生成筛选按钮（全部 + 每块一个）
List<_TypeFilter> _filtersFor(List<Block> blocks) => [
      _TypeFilter('全部', Icons.all_inclusive, (_) => true),
      for (final b in blocks)
        _TypeFilter(b.title, b.icon ?? Icons.circle, (t) => b.types.contains(t)),
    ];

/// 布局结果：节点位置 + 各块区域 + 画布尺寸
class _LayoutResult {
  final Map<String, Offset> positions;
  final Map<String, Rect> blocks; // 块key -> 区域
  final Size size; // 自适应画布
  _LayoutResult(this.positions, this.blocks, this.size);
}

/// 图谱页
class GraphPage extends StatefulWidget {
  final GraphData graph;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  // ⭐ 筛选索引由外部（main.dart 全宽工具栏）控制
  final int filterIndex;
  final ValueChanged<int> onFilterChanged;

  const GraphPage({
    super.key,
    required this.graph,
    required this.selectedId,
    required this.onSelect,
    this.filterIndex = 0,
    required this.onFilterChanged,
  });

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  final TransformationController _tc = TransformationController();
  Map<String, Offset> _positions = {};
  Map<String, Rect> _blocks = {};
  Size _canvas = const Size(2400, 1960);
  String _layoutFor = '';
  // ⭐ 块的拖动偏移（用户拖动块标题移动整块，节点/箭头实时跟随）
  final Map<String, Offset> _blockDrag = {};
  // ⭐ 节点 → 所属块 id 映射（兼容无 block 字段的旧包：拖动块时节点也能跟随）
  Map<String, String> _nodeBlock = {};
  // ⭐ 布局模式：隐藏连线 + 移动块（界面缩放/平移保留）
  bool _layoutMode = false;
  // ⭐ 正在拖块：临时禁用画布平移/缩放（Listener 原始事件驱动块，不被画布抢）
  bool _blockDragging = false;
  // ⭐ 画布原点偏移：把内容移到巨大画布中心（±10000），
  //   块往任何方向（含左上）拖都是正坐标，命中测试永不失效（修复"不能向上/向左拖"）
  static const double _dragExtend = 10000.0;
  // ⭐ 缓存：筛选定义（布局变化时重建）与节点文字样式（避免每帧新建对象）
  List<_TypeFilter> _filtersCache = [];
  // ⭐ 缓存：有效块定义（布局变化时重建，避免每次 build 新建 Block 列表）
  List<Block> _effectiveBlocksCache = [];
  static const TextStyle _nodeBaseStyle =
      TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.25);

  // 网格常量
  static const int _cols = 4;
  static const double _cellW = 265;
  static const double _cellH = 150;
  static const double _padL = 40;
  static const double _padT = 70;
  static const double _padB = 50;
  static const double _gapX = 150;
  static const double _gapY = 170;
  static const double _margin = 40;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitToView());
  }

  /// 布局：按类型分块 + 块内网格，画布尺寸自适应
  void _ensureLayout() {
    if (_layoutFor == widget.graph.id && _positions.isNotEmpty) return;
    _layoutFor = widget.graph.id;
    _effectiveBlocksCache = _effectiveBlocks(); // ⭐ 缓存有效块定义（避免每次 build 重建）
    _filtersCache = _filtersFor(_effectiveBlocksCache); // ⭐ 布局变化时重建筛选定义
    final r = _groupGridLayout(widget.graph);
    // ⭐ 内容坐标整体偏移到巨大画布中心：块往任何方向拖都是正坐标，可点可拖
    final shift = Offset(_dragExtend, _dragExtend);
    _positions = {
      for (final e in r.positions.entries) e.key: e.value + shift,
    };
    _blocks = {
      for (final e in r.blocks.entries) e.key: e.value.shift(shift),
    };
    _canvas = r.size;
    // ⭐ 加载该包保存的块布局位置（用户拖动过 → 恢复；没保存 → 用自动布局）
    _blockDrag.clear();
    final saved = UserStore.instance.blockLayoutOf(widget.graph.id);
    if (saved != null) {
      for (final e in saved.entries) {
        if (e.value.length == 2) {
          _blockDrag[e.key] = Offset(e.value[0], e.value[1]);
        }
      }
    }
    // ⭐ 节点 → 块映射（兼容无 block 字段的旧包：拖动块时节点跟随）
    _nodeBlock = {};
    for (final e in _allocateToBlocks(widget.graph, _effectiveBlocks()).entries) {
      for (final nid in e.value) {
        _nodeBlock[nid] = e.key;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitToView());
  }

  /// ⭐ 有效块定义：包声明优先，否则默认 4 块；
  ///   若所有块都没写位置（row=col=0），按声明顺序自动排成 2 列网格（容错，避免全叠左上角）
  List<Block> _effectiveBlocks() {
    final blocks = widget.graph.blocks.isNotEmpty
        ? widget.graph.blocks
        : _defaultBlocks();
    final allZero = blocks.length > 1 && blocks.every((b) => b.row == 0 && b.col == 0);
    if (!allZero) return blocks;
    // ⭐ 自动排布列数按块数自适应：≤4块→2列，≤6块→3列，更多→4列（避免行数过多画布过高）
    final cols = blocks.length <= 4 ? 2 : (blocks.length <= 6 ? 3 : 4);
    return [
      for (int i = 0; i < blocks.length; i++)
        Block(
          id: blocks[i].id,
          title: blocks[i].title,
          color: blocks[i].color,
          types: blocks[i].types,
          row: i ~/ cols,
          col: i % cols,
        ),
    ];
  }

  _LayoutResult _groupGridLayout(GraphData graph) {
    // ⭐ 布局模式分发：ring=环形分布；默认 grid=网格（含块级 offset 错位）
    if (graph.blockLayout == 'ring') return _ringLayout(graph);

    final result = <String, Offset>{};

    // ⭐ 有效块定义（含容错自动排布）
    final blocks = _effectiveBlocks();

    // 1. 把神经元分配到各块（优先显式 block，否则按 types，兜底第一块）
    final idsInBlock = _allocateToBlocks(graph, blocks);

    // 2. 计算网格布局：基于 blocks 的 row/col 自动排布
    // ⭐ 块宽预留行错位(0.5格)+节点半宽，错位节点不出边框
    final blockW = _padL + _cols * _cellW + _padL + _cellW * 0.5 + 20;
    // 计算每行最大高度、每列最大宽度
    final maxRow = blocks.fold<int>(0, (m, b) => b.row > m ? b.row : m);
    final maxCol = blocks.fold<int>(0, (m, b) => b.col > m ? b.col : m);
    // 自适应：按列宽 / 行高排
    final originX = _margin;
    final originY = _margin + 50.0; // 顶部给筛选按钮留位

    // 先算每行最大块高，每列最大块宽
    final rowHeight = <int, double>{};
    final colWidth = <int, double>{};
    for (final b in blocks) {
      final h = _blockHeight(b, idsInBlock);
      if (h > (rowHeight[b.row] ?? 0)) rowHeight[b.row] = h;
      colWidth[b.col] = blockW;
    }
    // 计算每行 Y 起点
    final rowY = <int, double>{0: originY};
    for (int r = 1; r <= maxRow; r++) {
      rowY[r] = (rowY[r - 1] ?? originY) + (rowHeight[r - 1] ?? 0) + _gapY;
    }
    // 计算每列 X 起点
    final colX = <int, double>{0: originX};
    for (int c = 1; c <= maxCol; c++) {
      colX[c] = (colX[c - 1] ?? originX) + (colWidth[c - 1] ?? blockW) + _gapX;
    }

    // 3. 块区域 + 网格内排布（⭐ 支持块级 offset 上下左右错位）
    final blockRects = <String, Rect>{};
    for (final b in blocks) {
      var x = colX[b.col] ?? originX;
      var y = rowY[b.row] ?? originY;
      // ⭐ 错位偏移：块声明的 offset 微调（让跨块连线不重叠）
      if (b.offset != null) {
        x += b.offset!.dx;
        y += b.offset!.dy;
      }
      final w = blockW;
      final h = _blockHeight(b, idsInBlock);
      blockRects[b.id] = Rect.fromLTWH(x, y, w, h);
      // 把这块的元素按网格排到画布（⭐ 奇数行右移半格：砖墙式错位，连线终点分散不重叠）
      final ids = idsInBlock[b.id]!;
      for (int i = 0; i < ids.length; i++) {
        final row = i ~/ _cols;
        final col = i % _cols;
        result[ids[i]] = _nodePosInBlock(x, y, row, col);
      }
    }

    // 4. 画布尺寸自适应（最右块的右边 / 最下块的下面 + margin）
    double maxRight = originX, maxBottom = originY;
    for (final b in blocks) {
      final r = blockRects[b.id]!;
      if (r.right > maxRight) maxRight = r.right;
      if (r.bottom > maxBottom) maxBottom = r.bottom;
    }
    final canvasSize = Size(maxRight + _margin, maxBottom + _margin);

    return _LayoutResult(result, blockRects, canvasSize);
  }

  /// ⭐ 环形布局：块绕圆心均匀分布（块多时连线从中心辐射，不重叠，更美观）
  _LayoutResult _ringLayout(GraphData graph) {
    final result = <String, Offset>{};
    final blocks = _effectiveBlocks();
    final idsInBlock = _allocateToBlocks(graph, blocks);

    // 每块尺寸（宽度统一，高度按节点数；⭐ 块宽预留行错位+节点半宽）
    final blockW = _padL + _cols * _cellW + _padL + _cellW * 0.5 + 20;
    final blockH = <String, double>{
      for (final b in blocks) b.id: _blockHeight(b, idsInBlock),
    };
    final maxDim = blocks.fold<double>(
        blockW, (m, b) => math.max(m, math.max(blockW, blockH[b.id]!)));

    // 半径：保证相邻块不重叠（弦长 = 2R·sin(π/n) ≥ maxDim + gap）
    final n = blocks.length;
    final gap = math.max(_gapX, _gapY);
    final minR = n <= 1 ? 0.0 : (maxDim + gap) / (2 * math.sin(math.pi / n));
    // 留出中心空间 + 避免 R 过大（块多时自然放大）
    final R = math.max(minR, maxDim * 1.15);

    // 圆心：画布中心（顶部给筛选按钮留位）
    final extent = R + maxDim / 2 + _margin;
    final center = Offset(extent + _margin, extent + 50.0);

    final blockRects = <String, Rect>{};
    for (int i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final angle = -math.pi / 2 + 2 * math.pi * i / n; // 从正上方开始顺时针
      final cx = center.dx + R * math.cos(angle);
      final cy = center.dy + R * math.sin(angle);
      final w = blockW;
      final h = blockH[b.id]!;
      final x = cx - w / 2;
      final y = cy - h / 2;
      blockRects[b.id] = Rect.fromLTWH(x, y, w, h);
      // 块内元素网格排布（⭐ 奇数行右移半格：砖墙式错位）
      final ids = idsInBlock[b.id]!;
      for (int j = 0; j < ids.length; j++) {
        final row = j ~/ _cols;
        final col = j % _cols;
        result[ids[j]] = _nodePosInBlock(x, y, row, col);
      }
    }

    final canvasSize = Size(extent * 2 + _margin * 2, extent * 2 + 50.0 + _margin * 2);
    return _LayoutResult(result, blockRects, canvasSize);
  }

  /// ⭐ 节点在块内网格的中心位置：上下左右都错位
  ///   行错位：奇数行右移半格 → 横向平行线不重叠
  ///   列错位：奇数列下移 0.3 格 → 纵向平行线不重叠（上下也有错位）
  Offset _nodePosInBlock(double blockX, double blockY, int row, int col) {
    final staggerX = row.isOdd ? _cellW * 0.5 : 0.0;
    final staggerY = col.isOdd ? _cellH * 0.3 : 0.0;
    return Offset(
      blockX + _padL + col * _cellW + _cellW / 2 + staggerX,
      blockY + _padT + row * _cellH + _cellH / 2 + staggerY,
    );
  }

  /// 块高度：按节点数算（空块也留一格）；⭐ 底部预留垂直错位余量（奇数列下移不超块底）
  double _blockHeight(Block b, Map<String, List<String>> idsInBlock) =>
      _padT +
      ((idsInBlock[b.id]!.isEmpty ? 1 : (idsInBlock[b.id]!.length + _cols - 1) ~/ _cols)) *
          _cellH +
      _padB +
      _cellH * 0.3;

  /// 节点分配到各块：优先显式 block，否则按 types 匹配第一个，兜底第一块
  Map<String, List<String>> _allocateToBlocks(GraphData graph, List<Block> blocks) {
    final idsInBlock = <String, List<String>>{for (final b in blocks) b.id: []};
    for (final n in graph.neurons.values) {
      if (n.type == 'industry') continue;
      String? target;
      // ⭐ 显式 block 归属优先（如考研包：7个知识块都含 knowledge 类型，靠 block 精确分块）
      if (n.block != null && idsInBlock.containsKey(n.block)) {
        target = n.block;
      } else {
        for (final b in blocks) {
          if (b.types.contains(n.type)) {
            target = b.id;
            break;
          }
        }
      }
      target ??= blocks.first.id;
      idsInBlock[target]!.add(n.id);
    }
    return idsInBlock;
  }

  /// ⭐ 默认 4 块（兼容未声明 blocks 的旧数据）
  List<Block> _defaultBlocks() => [
        Block(
            id: 'knowledge',
            title: '知识点',
            color: const Color(0xFF1D9E75),
            types: const ['knowledge'],
            row: 0,
            col: 0,
            icon: Icons.lightbulb_outline),
        Block(
            id: 'role',
            title: '工种',
            color: const Color(0xFF378ADD),
            types: const ['role'],
            row: 0,
            col: 1,
            icon: Icons.work_outline),
        Block(
            id: 'resource',
            title: '资源',
            color: const Color(0xFF8A6FBF),
            types: const [
              'book',
              'course',
              'tutorial',
              'docs',
              'video',
              'software',
              'project',
              'practice',
              'community',
              'certification',
              'job',
              'person',
              'website',
              'news',
              'file'
            ],
            row: 1,
            col: 0,
            icon: Icons.library_books_outlined),
        Block(
            id: 'contest',
            title: '比赛',
            color: const Color(0xFFEF9F27),
            types: const ['contest'],
            row: 1,
            col: 1,
            icon: Icons.emoji_events_outlined),
      ];

  /// 首帧后自动缩放适配全图（四周留白，内容真正居中）
  /// ⭐ 最小缩放 0.3：内容再多也不会缩到看不清字（超出视口可拖动/放大查看）
  void _fitToView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox) return;
      final vp = box.size;
      if (vp.isEmpty) return;
      final c = _canvas;
      final scale =
          math.min(vp.width / c.width, vp.height / c.height).clamp(0.3, 3.0) * 1.2;
      // ⭐ 内容已偏移 _dragExtend，平移补偿使内容区在视口居中
      final tx = (vp.width - c.width * scale) / 2 - _dragExtend * scale;
      final ty = (vp.height - c.height * scale) / 2 - _dragExtend * scale;
      _tc.value = Matrix4.identity()
        ..setEntry(0, 0, scale)
        ..setEntry(1, 1, scale)
        ..setEntry(0, 3, tx)
        ..setEntry(1, 3, ty);
      if (mounted) setState(() {}); // ⭐ 刷新外层块标题位置
    });
  }

  /// 以视口中心为锚点缩放（+/- 按钮微调，保留滚轮）
  void _zoom(double factor) {
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    final vp = box.size;
    if (vp.isEmpty) return;
    final m = _tc.value.clone();
    final cur = m.getMaxScaleOnAxis();
    final next = (cur * factor).clamp(0.15, 5.0);
    final ratio = next / cur;
    final cx = vp.width / 2;
    final cy = vp.height / 2;
    final s = Matrix4.identity()
      ..setEntry(0, 0, ratio)
      ..setEntry(1, 1, ratio)
      ..setEntry(0, 3, cx * (1 - ratio))
      ..setEntry(1, 3, cy * (1 - ratio));
    _tc.value = s.multiplied(m);
    if (mounted) setState(() {}); // ⭐ 刷新外层块标题位置
  }

  /// ⭐ 手动保存当前块位置（退出软件不丢，下次打开恢复）
  void _saveBlockLayout() {
    UserStore.instance.saveBlockLayout(widget.graph.id, {
      for (final e in _blockDrag.entries) e.key: [e.value.dx, e.value.dy],
    });
  }

  /// ⭐ 重置：清除保存的块位置，恢复默认自动布局
  void _resetBlockLayout() {
    UserStore.instance.clearBlockLayout(widget.graph.id);
    setState(() => _blockDrag.clear());
  }

  @override
  Widget build(BuildContext context) {
    _ensureLayout();
    final graph = widget.graph;
    final selectedId = widget.selectedId;
    // ⭐ 筛选按钮按当前包的块动态生成（换包后自动更新，缓存复用）
    final filters = _filtersCache;
    final filter = filters[widget.filterIndex.clamp(0, filters.length - 1)];

    final focusSet = <String>{};
    if (selectedId != null) {
      focusSet.add(selectedId);
      for (final nb in graph.neighborsOf(selectedId)) {
        focusSet.add(nb.id);
      }
    }

    // ⭐ 显示逻辑（锚点 + 相关节点模式）：
    //   ① 选中了节点 + 点了类型筛选 → 只显示【选中节点】+【与它直接关联且属于该类型的节点】
    //   ② 选中了节点 + "全部" → 显示全部（聚焦淡化交给 focusSet）
    //   ③ 没选中 + 类型筛选 → 显示该类型全部节点
    //   ④ 没选中 + "全部" → 全部节点
    final visibleIds = <String>{};
    if (selectedId != null) {
      visibleIds.add(selectedId);
      if (widget.filterIndex > 0) {
        // 筛选模式：只显示选中节点 + 邻居中属于该类型的
        for (final nb in graph.neighborsOf(selectedId)) {
          final n = graph.neurons[nb.id];
          if (n != null && n.type != 'industry' && filter.match(n.type)) {
            visibleIds.add(nb.id);
          }
        }
      } else {
        // 全部模式
        for (final n in graph.neurons.values) {
          if (n.type != 'industry') visibleIds.add(n.id);
        }
      }
    } else {
      // 无选中：按类型过滤
      for (final n in graph.neurons.values) {
        if (n.type == 'industry') continue;
        if (filter.match(n.type)) visibleIds.add(n.id);
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _tc,
                constrained: false,
                // ⭐ 拖块时临时禁用画布平移+缩放（Listener 驱动块，画布纹丝不动）
                panEnabled: !_blockDragging,
                scaleEnabled: !_blockDragging,
                // ⭐ 四向无边界：边界设很大，左/上/右/下都能无限拖动（不挡视野）
                boundaryMargin: const EdgeInsets.all(5000),
                minScale: 0.15,
                maxScale: 5,
                child: _buildCanvas(graph, focusSet, visibleIds, selectedId, filter),
              ),
            ),
            // 右侧：缩放微调按钮组（+ / − / 适应全图）
            Positioned(
              top: 8,
              right: 10,
              child: Column(
                children: [
                  _RoundBtn(icon: Icons.add, tooltip: '放大', onTap: () => _zoom(1.25)),
                  const SizedBox(height: 4),
                  _RoundBtn(icon: Icons.remove, tooltip: '缩小', onTap: () => _zoom(0.8)),
                  const SizedBox(height: 4),
                  _RoundBtn(icon: Icons.center_focus_strong, tooltip: '适应全图', onTap: _fitToView),
                ],
              ),
            ),
            // ⭐ 底部：布局模式按钮组
            //   普通模式：移动块；布局模式：保存布局 / 重置 / 完成
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_layoutMode) ...[
                      _layoutActionBtn(
                        icon: Icons.save,
                        label: '保存布局',
                        bg: Colors.white,
                        fg: const Color(0xFF185FA5),
                        onTap: _saveBlockLayout,
                      ),
                      const SizedBox(width: 10),
                      _layoutActionBtn(
                        icon: Icons.restart_alt,
                        label: '重置',
                        bg: Colors.white,
                        fg: const Color(0xFFE24B4A),
                        onTap: _resetBlockLayout,
                      ),
                      const SizedBox(width: 10),
                    ],
                    _layoutActionBtn(
                      icon: _layoutMode ? Icons.check : Icons.open_with,
                      label: _layoutMode ? '完成' : '移动块',
                      bg: _layoutMode ? const Color(0xFFEF9F27) : Colors.white,
                      fg: _layoutMode ? Colors.white : const Color(0xFF185FA5),
                      onTap: () => setState(() => _layoutMode = !_layoutMode),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 画布内容（块边框 + 标题 + 连线 + 节点）
  /// ⭐ 布局模式下不渲染连线（移动块时干净，移完退出模式再生成）
  /// ⭐ Clip.none：块标题/边框超出画布边缘不被裁剪（边缘块完整显示）
  /// ⭐ 画布区域外扩 ±_dragExtend：块可拖出画布 10000px 且仍可点击（与碰撞边界匹配）
  Widget _buildCanvas(GraphData graph, Set<String> focusSet,
      Set<String> visibleIds, String? selectedId, _TypeFilter filter) {
    final visibleNeurons =
        graph.neurons.values.where((n) => visibleIds.contains(n.id)).toList();
    return SizedBox(
      width: _canvas.width + _dragExtend * 2,
      height: _canvas.height + _dragExtend * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ..._buildBlockFrames(),
          ..._buildBlockTitles(),
          if (!_layoutMode) // ⭐ 布局模式：暂时隐藏连线
            Positioned.fill(
              // ⭐ RepaintBoundary：连线层独立重绘，不影响节点层（性能优化）
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _EdgePainter(
                    graph: graph,
                    // ⭐ 实时位置（布局 + 块拖动）：拖块时箭头实时跟随节点
                    positions: {
                      for (final e in _positions.entries)
                        e.key: e.value +
                            (_blockDrag[_nodeBlock[e.key]] ?? Offset.zero),
                    },
                    focusSet: focusSet,
                    visibleIds: visibleIds,
                    anchorId: selectedId, // ⭐ 选中节点：只画与它相连的线
                  ),
                ),
              ),
            ),
          for (final n in visibleNeurons) _buildNode(n, selectedId, focusSet, filter),
        ],
      ),
    );
  }

  /// 底部布局模式操作按钮（保存/重置/完成/移动块）
  Widget _layoutActionBtn({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bg,
      elevation: 3,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }

  /// 块边框（半透明彩色圆角框，外扩包住错位节点；拖动时跟随）
  List<Widget> _buildBlockFrames() {
    return [
      for (final b in _effectiveBlocksCache)
        if (_blocks.containsKey(b.id))
          Builder(builder: (context) {
            final r = _blocks[b.id]!;
            const pad = 26.0; // ⭐ 边框外扩：包住错位出的节点
            final drag = _blockDrag[b.id] ?? Offset.zero;
            return Positioned(
              left: r.left - pad + drag.dx,
              top: r.top - pad + drag.dy,
              width: r.width + pad * 2,
              height: r.height + pad * 2,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: b.color.withValues(alpha: 0.6), width: 3),
                  ),
                ),
              ),
            );
          }),
    ];
  }

  /// 块标题（⭐ Listener 原始事件拖动：不参与手势竞技场，配合拖动时禁用画布交互，
  /// 块拖动绝不与画布抢手势，普通模式/布局模式都有效）
  List<Widget> _buildBlockTitles() {
    return [
      for (final b in _effectiveBlocksCache)
        if (_blocks.containsKey(b.id))
          Positioned(
            left: _blocks[b.id]!.left + 12 + (_blockDrag[b.id]?.dx ?? 0),
            top: _blocks[b.id]!.top - 72 + (_blockDrag[b.id]?.dy ?? 0),
            child: Listener(
              onPointerDown: (_) => setState(() => _blockDragging = true),
              onPointerMove: (e) {
                final s = _tc.value.getMaxScaleOnAxis();
                if (s <= 0) return;
                // 屏幕 delta → 画布 delta（除以当前缩放）
                final canvasDelta =
                    Offset(e.delta.dx / s, e.delta.dy / s);
                setState(() {
                  final current = _blockDrag[b.id] ?? Offset.zero;
                  final next = current + canvasDelta;
                  // ⭐ 碰撞边界：块最多拖出画布 10000px（远大于画布本身，
                  //   实际感受"随便拖"），且始终在可点击范围内
                  const limit = 10000.0;
                  _blockDrag[b.id] = Offset(
                    next.dx.clamp(-limit, limit),
                    next.dy.clamp(-limit, limit),
                  );
                });
              },
              onPointerUp: (_) => setState(() => _blockDragging = false),
              onPointerCancel: (_) => setState(() => _blockDragging = false),
              // ⭐ behavior: opaque 让整个标题行（含空白区）都能命中拖动
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 18, height: 18, decoration: BoxDecoration(color: b.color, shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Text(b.title,
                        style: TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w700, color: b.color, letterSpacing: 2)),
                    const SizedBox(width: 10),
                    Icon(Icons.drag_indicator, size: 34, color: b.color.withValues(alpha: 0.6)),
                  ],
                ),
              ),
            ),
          ),
    ];
  }

  Widget _buildNode(
      Neuron n, String? selectedId, Set<String> focusSet, _TypeFilter filter) {
    final base = _positions[n.id] ?? Offset.zero;
    if (base.dx.isNaN || base.dy.isNaN) return const SizedBox.shrink();
    // ⭐ 实时位置 = 布局位置 + 块拖动偏移（拖块时节点跟着走，箭头自动跟随）
    final drag = _blockDrag[_nodeBlock[n.id]] ?? Offset.zero;
    final center = base + drag;
    final selected = n.id == selectedId;
    // ⭐ 淡化只取决于聚焦关系（筛选已由 visibleIds 处理，不再按类型淡化）
    final dimmed = focusSet.isNotEmpty && !focusSet.contains(n.id);
    final color = typeColor(n.type);
    final mainColor = selected ? Colors.orange : color;

    // ⭐ 可见度：未选中节点明显可见（背景/边框有足够对比度），选中更突出
    final bgAlpha = selected ? 0.42 : (dimmed ? 0.03 : 0.32);
    final borderAlpha = selected ? 1.0 : (dimmed ? 0.25 : 0.95);
    final borderW = selected ? 3.0 : 2.2;

    final textW = n.title.length * 17.0 + 36;
    // ⭐ 加宽（140-280）+ 加高（64）—— 长标题两行也能完整显示
    final w = textW.clamp(140.0, 280.0);
    const h = 64.0;

    return Positioned(
      left: center.dx - w / 2,
      top: center.dy - h / 2,
      child: GestureDetector(
        onTap: () => widget.onSelect(n.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: w,
          height: h,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: mainColor.withValues(alpha: bgAlpha),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: mainColor.withValues(alpha: borderAlpha),
              width: borderW,
            ),
          ),
          child: Opacity(
            opacity: dimmed ? 0.3 : 1,
            child: Text(
              n.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: _nodeBaseStyle.copyWith(color: mainColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// 圆形小按钮（缩放/适应全图用）
class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _RoundBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        elevation: 1,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: const Color(0xFF185FA5)),
          ),
        ),
      ),
    );
  }
}

/// 连线画笔（带方向箭头）
class _EdgePainter extends CustomPainter {
  final GraphData graph;
  final Map<String, Offset> positions;
  final Set<String> focusSet;
  final Set<String> visibleIds;
  final String? anchorId; // ⭐ 选中节点：只画与它直接相连的线

  // ⭐ 复用对象（避免每帧在 paint 内分配数百个 Paint/Path —— 性能优化）
  final Paint _paint = Paint()..strokeCap = StrokeCap.round;
  final Path _arrowPath = Path();

  _EdgePainter({
    required this.graph,
    required this.positions,
    required this.focusSet,
    required this.visibleIds,
    this.anchorId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final l in graph.links) {
      final a = positions[l.from];
      final b = positions[l.to];
      if (a == null || b == null) continue;
      if (a.dx.isNaN || a.dy.isNaN || b.dx.isNaN || b.dy.isNaN) continue;
      if (!visibleIds.contains(l.from) || !visibleIds.contains(l.to)) continue;
      // ⭐ 选中节点时：只画指向它的、或它指向别的的线（其他节点间的线不显示，避免混乱）
      if (anchorId != null && l.from != anchorId && l.to != anchorId) continue;

      final color = linkColor(l.type);
      var paintColor = color;
      var width = 1.0;
      if (focusSet.isNotEmpty && !(focusSet.contains(l.from) && focusSet.contains(l.to))) {
        paintColor = color.withValues(alpha: 0.15);
        width = 0.7;
      } else if (focusSet.isNotEmpty) {
        paintColor = color;
        width = 1.8;
      }
      // ⭐ 复用 Paint：改色改宽后立即绘制
      _paint.color = paintColor;
      _paint.strokeWidth = width;

      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1) continue;
      final ux = dx / len;
      final uy = dy / len;
      // ⭐ 纯连接：直线 + 端部收缩（箭头贴近节点边缘），实时跟随节点位置
      final a2 = Offset(a.dx + ux * 30, a.dy + uy * 30);
      final b2 = Offset(b.dx - ux * 42, b.dy - uy * 42);
      canvas.drawLine(a2, b2, _paint);
      _drawArrow(canvas, a2, b2);
    }
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1) return;
    final ux = dx / len;
    final uy = dy / len;
    const aLen = 10.0;
    const aHalf = 5.0;
    final base = Offset(to.dx - ux * aLen, to.dy - uy * aLen);
    final p1 = Offset(base.dx - uy * aHalf, base.dy + ux * aHalf);
    final p2 = Offset(base.dx + uy * aHalf, base.dy - ux * aHalf);
    // ⭐ 复用 Path：reset 后重画箭头（避免每帧新建）
    _arrowPath.reset();
    _arrowPath
      ..moveTo(to.dx, to.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(_arrowPath, _paint);
  }

  @override
  bool shouldRepaint(covariant _EdgePainter old) =>
      old.graph != graph ||
      old.positions != positions ||
      old.focusSet != focusSet ||
      old.visibleIds != visibleIds ||
      old.anchorId != anchorId;
}
