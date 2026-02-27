import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/sponsor_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class PortVideoDialog extends StatefulWidget {
  const PortVideoDialog({
    super.key,
    required this.bvid,
    required this.cid,
    required this.videoDuration,
  });

  final String bvid;
  final int cid;
  final int videoDuration;

  @override
  State<PortVideoDialog> createState() => _PortVideoDialogState();
}

class _PortVideoDialogState extends State<PortVideoDialog> {
  final _ytbController = TextEditingController();
  Map<String, dynamic>? _portData;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPortVideo();
  }

  @override
  void dispose() {
    _ytbController.dispose();
    super.dispose();
  }

  Future<void> _loadPortVideo() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await SponsorBlock.getPortVideo(
      bvid: widget.bvid,
      cid: widget.cid,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Success(:final response):
          _portData = response;
          _ytbController.text = response['ytbID']?.toString() ?? '';
        case Error(:final errMsg, :final code):
          if (code != 404) {
            _error = errMsg;
          }
          _portData = null;
        case Loading():
          break;
      }
    });
  }

  Future<void> _submitPort() async {
    final ytbId = _ytbController.text.trim();
    if (ytbId.isEmpty) {
      SmartDialog.showToast('请输入YouTube视频ID');
      return;
    }
    SmartDialog.showLoading();
    final res = await SponsorBlock.postPortVideo(
      bvid: widget.bvid,
      cid: widget.cid,
      ytbId: ytbId,
      videoDuration: widget.videoDuration,
    );
    SmartDialog.dismiss();
    if (res.isSuccess) {
      SmartDialog.showToast('绑定成功');
      _loadPortVideo();
    } else {
      SmartDialog.showToast('绑定失败: $res');
    }
  }

  Future<void> _votePort(int type) async {
    final uuid = _portData?['UUID']?.toString();
    if (uuid == null) return;
    final res = await SponsorBlock.votePort(
      uuid: uuid,
      bvid: widget.bvid,
      type: type,
    );
    SmartDialog.showToast(res.isSuccess ? '投票成功' : '投票失败: $res');
    if (res.isSuccess) _loadPortVideo();
  }

  Future<void> _updateSegments() async {
    final uuid = _portData?['UUID']?.toString();
    if (uuid == null) return;
    SmartDialog.showLoading();
    final res = await SponsorBlock.updatePortedSegments(
      videoID: widget.bvid,
      uuid: uuid,
      cid: widget.cid,
    );
    SmartDialog.dismiss();
    SmartDialog.showToast(res.isSuccess ? '更新成功' : '更新失败: $res');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('搬运视频绑定', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    if (_portData != null) ...[
                      Text(
                        'YouTube ID: ${_portData!['ytbID'] ?? '无'}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '投票数: ${_portData!['votes'] ?? 0}'
                        '${_portData!['locked'] == 1 ? ' (已锁定)' : ''}',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        spacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () => _votePort(1),
                            icon: const Icon(Icons.thumb_up_outlined, size: 16),
                            label: const Text('赞成'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _votePort(0),
                            icon:
                                const Icon(Icons.thumb_down_outlined, size: 16),
                            label: const Text('反对'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _updateSegments,
                        child: const Text('更新片段'),
                      ),
                      const Divider(height: 24),
                    ],
                    TextField(
                      controller: _ytbController,
                      decoration: const InputDecoration(
                        labelText: 'YouTube视频ID',
                        hintText: '例如: dQw4w9WgXcQ',
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '关闭',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ),
        if (!_loading)
          TextButton(
            onPressed: _submitPort,
            child: const Text('绑定'),
          ),
      ],
    );
  }
}
