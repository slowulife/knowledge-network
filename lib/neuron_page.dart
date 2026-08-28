/// 神经元页面（三分区：①文字 ②操作 ③自定义操作+敬请期待）
/// ① 文字部分：名片 + 事实 + 正文 + 📝我的笔记（用户自由标注，存本地）
/// ② 操作部分：关联分组导航（含当前节点标注）+ 📁我的附件（用户自定义文件夹/快捷方式）
/// ③ 自定义操作部分：收藏/加入学习计划/进度/固定为主界面（M2 已落地）+ 敬请期待
library;

import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models.dart';
import 'loader.dart';
import 'user_store.dart';
import 'flows_page.dart';

/// 用户笔记数据目录
const String kUserDataDir = r'D:\knowledge_network\user_data';

class NeuronPage extends StatefulWidget {
  final GraphData graph;
  final String neuronId;
  final ValueChanged<String> onJumpTo;
  final List<PackageFile> packageFiles;

  const NeuronPage({
    super.key,
    required this.graph,
    required this.neuronId,
    required this.onJumpTo,
    this.packageFiles = const [],
  });

  @override
  State<NeuronPage> createState() => _NeuronPageState();
}

class _NeuronPageState extends State<NeuronPage> {
  late TextEditingController _noteCtrl;
  bool _noteSaved = false;
  String _notePath = '';

  @override
  void initState() {
    super.initState();
    _initNote();
  }

  @override
  void didUpdateWidget(covariant NeuronPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.neuronId != widget.neuronId) {
      _initNote();
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  void _initNote() {
    try {
      final dir = Directory('$kUserDataDir${Platform.pathSeparator}notes');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _notePath =
          '$kUserDataDir${Platform.pathSeparator}notes${Platform.pathSeparator}${widget.neuronId}.md';
      final f = File(_notePath);
      _noteCtrl = TextEditingController(
          text: f.existsSync() ? (f.readAsStringSync(encoding: utf8)) : '');
      _noteSaved = false;
    } catch (_) {
      _noteCtrl = TextEditingController();
      _noteSaved = false;
    }
  }

  void _saveNote() {
    try {
      final dir = Directory('$kUserDataDir${Platform.pathSeparator}notes');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File(_notePath).writeAsStringSync(_noteCtrl.text, encoding: utf8);
      setState(() => _noteSaved = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _noteSaved = false);
      });
    } catch (_) {
      _toast('笔记保存失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final graph = widget.graph;
    final neuron = graph.neurons[widget.neuronId];
    if (neuron == null) {
      return const Center(child: Text('未知神经元（幽灵引用）'));
    }
    final typeName = graph.typeName(neuron.type);
    final neighbors = graph.neighborsOf(widget.neuronId);

    return ListenableBuilder(
      listenable: UserStore.instance,
      builder: (context, _) {
        final store = UserStore.instance;
        final isFav = store.isFavorite(neuron.id);
        final isStart = store.startPkgId == graph.id && store.startNeuronId == neuron.id;

        return Container(
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: Color(0xFFE3E1D9))),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ===== ① 文字部分 =====
                _SectionTitle('① 文字部分', const Color(0xFF185FA5)),
                const SizedBox(height: 8),
                Text(neuron.title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    _TagChip(typeName, const Color(0xFF185FA5)),
                    for (final t in neuron.tags)
                      _TagChip('#$t', const Color(0xFF5F5E5A)),
                  ],
                ),
                const SizedBox(height: 10),
                if (neuron.facts.isNotEmpty)
                  _FactsCard(facts: neuron.facts, neuron: neuron),
                if (neuron.body.isNotEmpty) _BodyCard(body: neuron.body),
                _NoteCard(
                  controller: _noteCtrl,
                  saved: _noteSaved,
                  onSave: _saveNote,
                ),

                const Divider(height: 32),

                // ===== ② 操作部分 =====
                _SectionTitle('② 操作部分', const Color(0xFF0F6E56)),
                const SizedBox(height: 8),
                if (neuron.facts['url'] != null) ...[
                  Wrap(
                    spacing: 6,
                    children: [
                      InkWell(
                        onTap: () => _openUrl(neuron.facts['url'].toString()),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1D9E75),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.link, size: 13, color: Colors.white),
                              SizedBox(width: 4),
                              Text('🔗 打开链接',
                                  style: TextStyle(fontSize: 12, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                // ⭐ 关联分组（含当前节点标注）
                _GroupedLinks(
                  graph: graph,
                  neuronId: widget.neuronId,
                  currentTitle: neuron.title,
                  neighbors: neighbors,
                  onJumpTo: widget.onJumpTo,
                ),
                // 📁 我的附件（只显示用户自己设置的）
                _FileManager(neuron: neuron),

                const Divider(height: 32),

                // ===== ③ 自定义操作部分 =====
                _SectionTitle('③ 自定义操作部分', const Color(0xFF534AB7)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // ⭐ 收藏（真实）
                    _ActionButton(
                      icon: isFav ? Icons.star : Icons.star_border,
                      label: isFav ? '已收藏' : '收藏',
                      active: isFav,
                      onTap: () => store.toggleFavorite(neuron.id),
                    ),
                    // 🚩 加入学习计划（真实）
                    _ActionButton(
                      icon: Icons.flag_outlined,
                      label: '加入学习计划',
                      onTap: () => showAddToFlowDialog(context, neuron.id, graph),
                    ),
                    // 📌 固定为主界面（真实）
                    _ActionButton(
                      icon: isStart ? Icons.push_pin : Icons.push_pin_outlined,
                      label: isStart ? '已固定为主界面' : '固定为主界面',
                      active: isStart,
                      onTap: () {
                        if (isStart) {
                          store.setStart('', '');
                        } else {
                          store.setStart(graph.id, neuron.id);
                          _toast('已设为启动主界面');
                        }
                      },
                    ),
                    _ActionButton(
                      icon: Icons.more_horiz,
                      label: '敬请期待',
                      onTap: () => _toast('更多功能即将上线'),
                      dashed: true,
                    ),
                    _ActionButton(
                      icon: Icons.more_horiz,
                      label: '敬请期待',
                      onTap: () => _toast('更多功能即将上线'),
                      dashed: true,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _toast('无效链接: $url');
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) _toast('无法打开链接');
    } catch (_) {
      if (context.mounted) _toast('无法打开链接: $url');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ));
  }
}

// ================= 区块组件 =================

class _SectionTitle extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionTitle(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 4, height: 14, color: color),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color)),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  final String text;
  final Color color;
  const _TagChip(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

class _FactsCard extends StatelessWidget {
  final Map<String, dynamic> facts;
  final Neuron neuron;
  const _FactsCard({required this.facts, required this.neuron});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in facts.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(neuron.factLabel(entry.key),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF5F5E5A))),
                  ),
                  Expanded(
                    child: Text(entry.value.toString(),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF2C2C2A))),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BodyCard extends StatelessWidget {
  final String body;
  const _BodyCard({required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Text(body,
          style: const TextStyle(fontSize: 13, height: 1.6, color: Color(0xFF2C2C2A))),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final TextEditingController controller;
  final bool saved;
  final VoidCallback onSave;
  const _NoteCard({
    required this.controller,
    required this.saved,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF7EE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEF9F27).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note, size: 16, color: Color(0xFF854F0B)),
              const SizedBox(width: 4),
              const Text('我的笔记',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF633806))),
              const Spacer(),
              if (saved)
                const Text('已保存 ✓',
                    style: TextStyle(fontSize: 11, color: Color(0xFF0F6E56))),
              TextButton(
                onPressed: onSave,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text('保存', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          TextField(
            controller: controller,
            maxLines: 4,
            minLines: 2,
            style: const TextStyle(fontSize: 12, height: 1.5),
            decoration: const InputDecoration(
              hintText: '写点心得、计划、链接…（自动保存到本地）',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.all(8),
            ),
          ),
        ],
      ),
    );
  }
}

/// 关联分组（前置/后续/包含/资源/比赛）—— ⭐ 显示当前节点
class _GroupedLinks extends StatelessWidget {
  final GraphData graph;
  final String neuronId;
  final String currentTitle;
  final List<Neighbor> neighbors;
  final ValueChanged<String> onJumpTo;

  const _GroupedLinks({
    required this.graph,
    required this.neuronId,
    required this.currentTitle,
    required this.neighbors,
    required this.onJumpTo,
  });

  static const _groupMeta = [
    ('prereq', '⬆️ 前置（要先学）', Color(0xFFEF9F27)),
    ('leads_to', '➡️ 后续方向', Color(0xFF1D9E75)),
    ('contains', '📦 包含', Color(0xFF378ADD)),
    ('resource', '📎 关联资源', Color(0xFF7F77DD)),
    ('participates', '🏆 参加比赛', Color(0xFFE24B4A)),
    ('related', '🔗 相关', Color(0xFF888780)),
  ];

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Neighbor>>{};
    for (final nb in neighbors) {
      groups.putIfAbsent(nb.linkType, () => []).add(nb);
    }
    if (groups.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ⭐ 当前节点标注（在关联网络中的位置）
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F1FB),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('当前节点：$currentTitle',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF185FA5))),
        ),
        for (final (type, label, color) in _groupMeta)
          if (groups.containsKey(type))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final nb in groups[type]!)
                        _NeighborChip(
                          label: graph.neurons[nb.id]?.title ?? nb.id,
                          tag: nb.tag,
                          onTap: () => onJumpTo(nb.id),
                        ),
                    ],
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _NeighborChip extends StatelessWidget {
  final String label;
  final String tag;
  final VoidCallback onTap;
  const _NeighborChip({required this.label, required this.onTap, this.tag = ''});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F5F2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF9FE1CB)),
        ),
        child: Text(
          tag.isEmpty ? label : '$label（$tag）',
          style: const TextStyle(fontSize: 12, color: Color(0xFF0F6E56)),
        ),
      ),
    );
  }
}

/// 📁 我的附件（只显示用户自己添加的文件夹/快捷方式，不显示包内文件）
class _FileManager extends StatefulWidget {
  final Neuron neuron;
  const _FileManager({required this.neuron});

  @override
  State<_FileManager> createState() => _FileManagerState();
}

class _FileManagerState extends State<_FileManager> {
  bool _expanded = true; // ⭐ 默认展开（用户要求）

  Future<void> _addFolder() async {
    final picked = await FilePicker.getDirectoryPath();
    if (picked == null || !mounted) return;
    UserStore.instance.addAttachment(widget.neuron.id, picked);
    setState(() => _expanded = true);
  }

  Future<void> _addFile() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty || !mounted) return;
    final path = picked.first.path;
    if (path != null) {
      // ⭐ .lnk 快捷方式：解析指向的软件名作为显示名（修复显示英文名 bug）
      var note = '';
      if (path.toLowerCase().endsWith('.lnk')) {
        note = await _lnkDisplayName(path);
      }
      UserStore.instance.addAttachment(widget.neuron.id, path, note: note);
      setState(() => _expanded = true);
    }
  }

  /// 用 PowerShell 解析 .lnk 快捷方式指向的软件名
  Future<String> _lnkDisplayName(String lnkPath) async {
    try {
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        // 注意：\$ 是 PowerShell 变量（Dart 需转义），$lnkPath 是 Dart 插值
        'try { \$sh = New-Object -ComObject WScript.Shell; '
            '\$t = \$sh.CreateShortcut("$lnkPath").TargetPath; '
            'if (\$t) { [System.IO.Path]::GetFileNameWithoutExtension(\$t) } } catch { }',
      ]);
      if (res.exitCode == 0) {
        final name = (res.stdout as String).trim();
        if (name.isNotEmpty && !name.contains('lnkPath')) return name;
      }
    } catch (_) {}
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final myAtts = UserStore.instance.attachmentsOf(widget.neuron.id);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                const Icon(Icons.folder_open, size: 15, color: Color(0xFF0F6E56)),
                const SizedBox(width: 4),
                Text('📁 我的附件（${myAtts.length}）',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF0F6E56))),
                const Spacer(),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: const Color(0xFF5F5E5A)),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _addFolder,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 14),
                  label: const Text('添加文件夹', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 32)),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _addFile,
                  icon: const Icon(Icons.add_link, size: 14),
                  label: const Text('添加快捷方式', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 32)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (myAtts.isNotEmpty)
              _MyAttachments(
                attachments: myAtts,
                onRemove: (i) => UserStore.instance.removeAttachment(widget.neuron.id, i),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('（还没有附件，点上面按钮选择你自己的文件夹/快捷方式）',
                    style: TextStyle(fontSize: 11, color: Color(0xFFB4B2A9))),
              ),
          ],
        ],
      ),
    );
  }
}

/// 📁 我的附件列表（节点风格自适应卡片：双击打开 / 类型图标 / 右侧 × 删除）
class _MyAttachments extends StatelessWidget {
  final List<UserAttachment> attachments;
  final void Function(int index) onRemove;
  const _MyAttachments({required this.attachments, required this.onRemove});
  static IconData _iconFor(String path) {
    if (File(path).existsSync() &&
        File(path).statSync().type == FileSystemEntityType.directory) {
      return Icons.folder;
    }
    final p = path.toLowerCase();
    if (p.endsWith('.lnk')) return Icons.shortcut;
    if (p.endsWith('.url')) return Icons.public;
    if (p.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (p.endsWith('.exe') || p.endsWith('.msi') || p.endsWith('.bat')) return Icons.apps;
    if (p.endsWith('.doc') || p.endsWith('.docx')) return Icons.description;
    if (p.endsWith('.xls') || p.endsWith('.xlsx') || p.endsWith('.csv')) return Icons.table_chart;
    if (p.endsWith('.ppt') || p.endsWith('.pptx')) return Icons.slideshow;
    if (p.endsWith('.txt') || p.endsWith('.md')) return Icons.notes;
    if (p.endsWith('.png') || p.endsWith('.jpg') || p.endsWith('.jpeg') ||
        p.endsWith('.gif') || p.endsWith('.bmp')) {
      return Icons.image;
    }
    if (p.endsWith('.mp4') || p.endsWith('.avi') || p.endsWith('.mkv')) return Icons.movie;
    if (p.endsWith('.mp3') || p.endsWith('.wav')) return Icons.music_note;
    if (p.endsWith('.zip') || p.endsWith('.rar') || p.endsWith('.7z')) return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (int i = 0; i < attachments.length; i++)
          // ⭐ 自适应宽度卡片（名称短则短、长则到上限换行）
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: GestureDetector(
              // ⭐ 双击打开
              onDoubleTap: () => openLocalFile(attachments[i].path),
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 6, 2, 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F5F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF9FE1CB)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 类型图标（不突兀，浅色）
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1D9E75).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(
                        _iconFor(attachments[i].path),
                        size: 14,
                        color: const Color(0xFF1D9E75),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 名称（tooltip 显示完整路径）
                    Flexible(
                      child: Tooltip(
                        message: attachments[i].path,
                        child: Text(
                          attachments[i].note.isNotEmpty
                              ? attachments[i].note
                              : _fileName(attachments[i].path),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF0F6E56)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    // ⭐ 右侧 × 删除
                    IconButton(
                      onPressed: () => onRemove(i),
                      tooltip: '移除',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(3),
                      icon: const Icon(Icons.close, size: 14, color: Color(0xFFE24B4A)),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _fileName(String path) {
    final parts = path.split(Platform.pathSeparator);
    return parts.isNotEmpty ? parts.last : path;
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool dashed;
  final bool active; // 已激活状态（收藏/进度/固定）
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.dashed = false,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = dashed
        ? const Color(0xFF888780)
        : (active ? const Color(0xFF1D9E75) : const Color(0xFF534AB7));
    final bg = dashed
        ? const Color(0xFFF7F7F5)
        : (active ? const Color(0xFFE8F5EF) : const Color(0xFFEEEDFE));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: dashed ? const Color(0xFFB4B2A9) : color,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}
