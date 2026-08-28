/// 知识网络软件 · M2 起步
/// 主界面：顶栏（含导入包）+ 图谱画布 + 神经元页面 + 底部功能栏（真实功能）
/// 新增：导入知识包、固定起始节点、收藏/流程/进度（用户数据层）
library;

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models.dart';
import 'loader.dart';
import 'graph_page.dart';
import 'neuron_page.dart';
import 'user_store.dart';
import 'flows_page.dart';

/// ⭐ 生成数据包的 AI 提示词（完整自包含，复制后发给任意 AI 即可生成）
const String kDataPackPrompt = '''
请为我生成一个【领域/行业】的知识网络数据包，直接输出一个完整的 graph.yaml 文件。

【格式】
format: '3.1'，顶层含 id(英文小写连字符)/title(中文)/description/version

【blocks 块定义】把领域按维度分成约8个块（每块一个主题），每个块写：
- id(英文)/title(中文)/color(#十六进制)/types(该块容纳的元素类型)/row/col(网格位置)

【elements 元素】每个元素是统一格式：
- id(英文小写连字符，唯一)/title(中文)/type(类型标签)/block(所属块id，必填！)
- summary(一句话简介)/tags(2-4个中文标签)/facts(键值信息，键用中文)/body(详细介绍)
- body 用 | 块语法写多行，信息参考型写具体数字和时间，知识学习型写要点和路径

【type 类型清单】knowledge知识点/industry行业/role工种/book/course/tutorial/docs/video/software/project/practice/community/certification/job/person/website/news/contest/file

【links 关联】from/to/type/tag：
- type 用 contains包含/part_of属于/prereq前置/leads_to顺序/related相关/resource资源/teaches教学/participates参加
- 每个关联只写一条（软件自动显示双向）
- tag 是可选标注（如"入门教程"）

【数量】共60个左右元素；每块5-15个；每个元素3-10条关联；总关联约为元素数1.2-2倍

【关键规则】
1. 每个元素必须写 block 字段（所属块id），且该id必须存在于blocks定义中
2. links 的 from/to 必须是已定义元素的 id（不能指向不存在的id）
3. 不能有孤立节点（每个元素至少被一条link连接）
4. 中文用全角标点；facts 键用中文
5. 生成后自查：元素id唯一、无幽灵引用、每块都有元素

请直接输出完整的 graph.yaml 文件内容。
''';

void main() {
  runApp(const KnowledgeNetworkApp());
}

class KnowledgeNetworkApp extends StatelessWidget {
  const KnowledgeNetworkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '知识网络',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF185FA5)),
        useMaterial3: true,
        // ⭐ 全局中文字体回退（修复部分字形渲染错误，如"门"字）
        fontFamilyFallback: const ['Microsoft YaHei', 'SimSun', 'Noto Sans CJK SC'],
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _settingsPath = r'D:\knowledge_network\user_data\settings.json';

  List<GraphData> _packages = [];
  List<String> _errors = [];
  bool _loading = true;
  int _currentPkg = 0;
  String? _selectedNeuronId;
  Map<String, List<PackageFile>> _pkgFiles = {};
  double _rightWidth = 400;
  bool _rightCollapsed = false; // ⭐ 右侧详情面板收起状态
  int _filterIndex = 0; // ⭐ 筛选索引（顶部全宽工具栏控制，0=全部）

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _load();
  }

  void _loadSettings() {
    try {
      final f = File(_settingsPath);
      if (f.existsSync()) {
        final raw = f.readAsStringSync();
        final m = RegExp(r'"rightWidth"\s*:\s*([\d.]+)').firstMatch(raw);
        if (m != null) {
          _rightWidth = double.parse(m.group(1)!).clamp(280, 700).toDouble();
        }
      }
    } catch (_) {}
  }

  void _saveSettings() {
    try {
      final dir = File(_settingsPath).parent;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File(_settingsPath)
          .writeAsStringSync('{"rightWidth": ${_rightWidth.toStringAsFixed(1)}}');
    } catch (_) {}
  }

  Future<void> _load() async {
    final result = await loadAllPackages();
    if (!mounted) return;
    final pkgFiles = <String, List<PackageFile>>{};
    for (final p in result.packages) {
      pkgFiles[p.id] = listPackageFiles(p);
    }
    setState(() {
      _packages = result.packages;
      _errors = result.errors;
      _pkgFiles = pkgFiles;
      _loading = false;
      _selectedNeuronId = null;
      if (_packages.isNotEmpty) {
        // ⭐ 固定起始节点优先；否则选第一个节点
        final store = UserStore.instance;
        final sp = store.startPkgId;
        final sn = store.startNeuronId;
        final idx = _packages.indexWhere((p) => p.id == sp);
        if (sn != null && idx >= 0 && _packages[idx].neurons.containsKey(sn)) {
          _currentPkg = idx;
          _selectedNeuronId = sn;
        } else {
          _currentPkg = 0;
          _selectedNeuronId = _packages[0].neurons.values.firstOrNull?.id;
        }
      }
    });
  }

  /// ⭐ 导入知识包：选文件夹 → 校验 graph.yaml → 复制到 D:\packages → 重载
  Future<void> _importPackage() async {
    final picked = await FilePicker.getDirectoryPath();
    if (picked == null || !mounted) return;
    final sep = Platform.pathSeparator;
    final graphFile = File('$picked${sep}graph.yaml');
    if (!graphFile.existsSync()) {
      _toast('所选文件夹里没有 graph.yaml，不是有效的知识包');
      return;
    }
    final name = picked.split(sep).last;
    final dst = Directory('$kPackagesDir$sep$name');
    try {
      if (dst.existsSync()) {
        // 同名牌：删除旧目标再复制（用户确认过的导入动作）
        dst.deleteSync(recursive: true);
      }
      dst.createSync(recursive: true);
      _copyDir(Directory(picked), dst);
      await _load();
      if (mounted) _toast('导入成功：$name');
    } catch (e) {
      if (mounted) _toast('导入失败：$e');
    }
  }

  void _copyDir(Directory src, Directory dst) {
    for (final e in src.listSync()) {
      final target = '${dst.path}${Platform.pathSeparator}${e.path.split(Platform.pathSeparator).last}';
      if (e is Directory) {
        Directory(target).createSync(recursive: true);
        _copyDir(e, Directory(target));
      } else if (e is File) {
        e.copySync(target);
      }
    }
  }

  GraphData? get _graph =>
      _packages.isEmpty ? null : _packages[_currentPkg.clamp(0, _packages.length - 1)];

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildHome(),
    );
  }

  Widget _buildHome() {
    final graph = _graph;
    if (graph == null) {
      return Column(
        children: [
          _buildTopBar(graph),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('没有可用的知识包\n\n请确认 D:\\packages 目录下有知识包文件夹，或点下面按钮导入',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF5F5E5A), fontSize: 13)),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _importPackage,
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: const Text('导入知识包'),
                    ),
                    if (_errors.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(_errors.join('\n'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF854F0B), fontSize: 11)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final selectedId = _selectedNeuronId;
    return Column(
      children: [
        _buildTopBar(graph),
        // ⭐ 顶部全宽筛选工具栏（像 Word 顶栏/底部工具栏一样横贯整行）
        _buildFilterToolbar(graph),
        if (_errors.isNotEmpty) _buildErrorBanner(),
        // ⭐ 添加模式横幅（向流程添加节点中）
        _buildAddModeBanner(graph),
        Expanded(
          child: Stack(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      color: const Color(0xFFF2F6FB),
                      child: GraphPage(
                        graph: graph,
                        selectedId: selectedId,
                        onSelect: _handleNodeTap,
                        filterIndex: _filterIndex,
                        onFilterChanged: (i) => setState(() => _filterIndex = i),
                      ),
                    ),
                  ),
                  if (!_rightCollapsed) ...[
                    _buildDivider(),
                    SizedBox(
                      width: _rightWidth,
                      child: Column(
                        children: [
                          // ⭐ 收起按钮栏
                          Container(
                            height: 36,
                            color: const Color(0xFFFAFBFC),
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              icon: const Icon(Icons.chevron_right, size: 22, color: Color(0xFF185FA5)),
                              tooltip: '收起详情',
                              onPressed: () => setState(() => _rightCollapsed = true),
                            ),
                          ),
                          Expanded(
                            child: selectedId != null
                                ? NeuronPage(
                                    graph: graph,
                                    neuronId: selectedId,
                                    onJumpTo: (id) => setState(() => _selectedNeuronId = id),
                                    packageFiles: _pkgFiles[graph.id] ?? const [],
                                  )
                                : const Center(
                                    child: Text('在图谱中点一个神经元查看详情',
                                        style: TextStyle(color: Color(0xFF888780)))),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              // ⭐ 右侧收起时：右边缘中部的展开按钮
              if (_rightCollapsed)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Material(
                      color: Colors.white,
                      elevation: 3,
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(Icons.chevron_left, size: 22, color: Color(0xFF185FA5)),
                        tooltip: '展开详情',
                        onPressed: () => setState(() => _rightCollapsed = false),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  /// ⭐ 节点点击：添加模式优先（点哪个加哪个），否则正常选中
  void _handleNodeTap(String id) {
    final store = UserStore.instance;
    final flowId = store.activeAddFlowId;
    if (flowId != null) {
      final flow = store.activeAddFlow;
      store.addNodeToFlow(flowId, id);
      _toast('已加入「${flow?.name ?? ''}」');
      return;
    }
    setState(() => _selectedNeuronId = id);
  }

  /// ⭐ 添加模式横幅
  Widget _buildAddModeBanner(GraphData? graph) {
    return ListenableBuilder(
      listenable: UserStore.instance,
      builder: (context, _) {
        final store = UserStore.instance;
        final flow = store.activeAddFlow;
        if (flow == null) return const SizedBox.shrink();
        return Material(
          color: const Color(0xFFE8F5EF),
          child: InkWell(
            onTap: () => store.setActiveAddFlow(null),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.touch_app, size: 16, color: Color(0xFF0F6E56)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '正在向「${flow.name}」添加节点（${flow.total} 个）：点图谱节点加入，点击此横幅完成',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF0F6E56)),
                    ),
                  ),
                  const Icon(Icons.check_circle, size: 16, color: Color(0xFF0F6E56)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDivider() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) {
          setState(() {
            _rightWidth = (_rightWidth - details.delta.dx).clamp(280, 700);
          });
          _saveSettings();
        },
        child: Container(
          width: 6,
          color: Colors.transparent,
          child: Center(
            child: Container(width: 3, height: 100, color: const Color(0xFFD3D1C7)),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: const Color(0xFFFBF7EE),
      child: Text(
        '⚠️ 部分知识包加载失败：${_errors.join('；')}',
        style: const TextStyle(fontSize: 11, color: Color(0xFF854F0B)),
      ),
    );
  }

  Widget _buildTopBar(GraphData? graph) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xFFF5F7FA),
      child: Row(
        children: [
          const Text('知识网络',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(width: 16),
          if (graph != null && _packages.length > 1)
            DropdownButton<int>(
              value: _currentPkg,
              underline: const SizedBox(),
              isDense: true,
              items: [
                for (int i = 0; i < _packages.length; i++)
                  DropdownMenuItem(value: i, child: Text(_packages[i].title)),
              ],
              onChanged: (v) => setState(() {
                _currentPkg = v ?? 0;
                final first = _graph?.neurons.values.firstOrNull;
                _selectedNeuronId = first?.id;
              }),
            )
          else if (graph != null)
            Text(graph.title,
                style: const TextStyle(fontSize: 13, color: Color(0xFF5F5E5A))),
          const Spacer(),
          // ⭐ 导入知识包按钮
          IconButton(
            onPressed: _importPackage,
            tooltip: '导入知识包（选择文件夹）',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.folder_open, size: 17, color: Color(0xFF185FA5)),
          ),
          const SizedBox(width: 8),
          Text('${graph?.neurons.length ?? 0} 神经元 · ${graph?.links.length ?? 0} 突触',
              style: const TextStyle(fontSize: 11, color: Color(0xFF888780))),
        ],
      ),
    );
  }

  /// ⭐ 底部功能栏：学习流程（=学习流程+进度+时间安排 三合一）
  Widget _buildBottomBar() {
    final graph = _graph;
    return ListenableBuilder(
      listenable: UserStore.instance,
      builder: (context, _) {
        final store = UserStore.instance;
        return Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          color: const Color(0xFFF5F7FA),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _bottomItem(Icons.route, '学习流程', () {
                if (graph == null) {
                  _toast('没有可用知识包');
                  return;
                }
                showFlowsSheet(context, graph: graph, onJumpTo: (id) => setState(() => _selectedNeuronId = id));
              }),
              _bottomItem(Icons.star, '收藏${store.favoritesCount > 0 ? ' ${store.favoritesCount}' : ''}',
                  _showFavorites),
              _bottomItem(Icons.info_outline, '关于', _showAbout),
            ],
          ),
        );
      },
    );
  }

  /// ⭐ 顶部全宽筛选工具栏（像 Word 顶栏/底部工具栏：横贯整行，覆盖在右详情上方）
  Widget _buildFilterToolbar(GraphData graph) {
    return Container(
      height: 40,
      color: const Color(0xFFF5F7FA),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.tune, size: 14, color: Color(0xFF2C2C2A)),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('全部', 0),
                  for (int i = 0; i < graph.blocks.length; i++)
                    _filterChip(graph.blocks[i].title, i + 1),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, int index) {
    final sel = _filterIndex == index;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => setState(() => _filterIndex = index),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: sel ? const Color(0xFFE8F1FB) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 12,
                color: sel ? const Color(0xFF185FA5) : const Color(0xFF2C2C2A),
                fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
              )),
        ),
      ),
    );
  }

  /// ⭐ 关于：软件介绍 + 数据包生成指令 + 版本信息
  void _showAbout() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3182CE), Color(0xFF0F3877)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.hub, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 10),
                    const Text('知识网络',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Color(0xFF888780)),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('版本 1.0.0 ｜ 发布日期 2026-08-18 ｜ 作者 慢尤悠',
                    style: TextStyle(fontSize: 12, color: Color(0xFF888780))),
                const Divider(height: 20),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _AboutSection(
                            title: '📖 这是什么',
                            body: '知识网络是一个"知识图谱阅读器 + 文件管理器"。'
                                '软件本身是空壳，知识内容全部来自"数据包"（一个文件夹，内含 graph.yaml）。'
                                '图谱里：节点=知识对象，箭头=关联（双向），点节点看详情。'),
                        const _AboutSection(
                            title: '🖱️ 怎么用',
                            body: '1. 看图谱：滚轮缩放，空白处拖动画布；\n'
                                '2. 筛选：顶部工具栏按"块"筛选（如考研总览/考试科目…）；\n'
                                '3. 看详情：点图谱上的节点，右侧面板显示内容和关联；\n'
                                '4. 移动布局：点底部"移动块"→ 拖动块调整位置 → "保存布局"记住；\n'
                                '5. 底部栏：学习流程 / 收藏 / 关于。'),
                        const _AboutSection(
                            title: '📦 生成数据包（发给 AI）',
                            body: '想让 AI 帮你做新数据包？点下方按钮复制提示词，发给任意 AI 即可。'
                                'AI 会输出 graph.yaml → 新建文件夹放入 D:\\packages\\ 下 → 重启软件加载。'
                                '桌面「知识网络数据包样例」有 IT 样例可参考。'),
                        const _AboutSection(
                            title: '🤖 AI 提示词（可直接复制）',
                            body: kDataPackPrompt,
                        ),
                        // ⭐ 一键复制提示词
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(const ClipboardData(text: kDataPackPrompt));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('提示词已复制，去发给 AI 吧！'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('复制提示词'),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: const Color(0xFF2C2C2A)),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF2C2C2A))),
          ],
        ),
      ),
    );
  }

  /// 收藏列表（底部弹层）
  void _showFavorites() {
    final store = UserStore.instance;
    // 跨包收集收藏的神经元
    final items = <(String title, String type, String pkgId, String id)>[];
    for (final id in store.favorites) {
      for (final p in _packages) {
        final n = p.neurons[id];
        if (n != null) {
          items.add((n.title, n.type, p.id, id));
          break;
        }
      }
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('我的收藏',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Text('还没有收藏\n\n在神经元页面点「☆ 收藏」把常用节点钉起来',
                    style: TextStyle(color: Colors.grey, fontSize: 13))
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final it in items)
                        ListTile(
                          dense: true,
                          leading: Icon(Icons.star, size: 16, color: const Color(0xFFEF9F27)),
                          title: Text(it.$1, style: const TextStyle(fontSize: 13)),
                          subtitle: Text(it.$2, style: const TextStyle(fontSize: 11)),
                          onTap: () {
                            Navigator.pop(ctx);
                            setState(() {
                              _currentPkg = _packages.indexWhere((p) => p.id == it.$3);
                              _selectedNeuronId = it.$4;
                            });
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

}

/// 关于弹窗里的分区（标题 + 正文）
class _AboutSection extends StatelessWidget {
  final String title;
  final String body;
  const _AboutSection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF185FA5))),
          const SizedBox(height: 6),
          Text(body,
              style: const TextStyle(
                  fontSize: 13, height: 1.6, color: Color(0xFF3A3A38))),
        ],
      ),
    );
  }
}
