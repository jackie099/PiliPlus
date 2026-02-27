import 'package:PiliPlus/common/widgets/pair.dart';
import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/sponsor_block.dart';
import 'package:PiliPlus/models/common/sponsor_block/segment_type.dart';
import 'package:PiliPlus/models/common/sponsor_block/skip_type.dart';
import 'package:PiliPlus/models_new/sponsor_block/user_info.dart';
import 'package:PiliPlus/pages/setting/slide_color_picker.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

class SponsorBlockPage extends StatefulWidget {
  const SponsorBlockPage({super.key});

  @override
  State<SponsorBlockPage> createState() => _SponsorBlockPageState();
}

class _SponsorBlockPageState extends State<SponsorBlockPage> {
  final _url = 'https://github.com/hanydd/BilibiliSponsorBlock';
  final _textController = TextEditingController();
  double _blockLimit = Pref.blockLimit;
  final _blockSettings = Pref.blockSettings;
  final List<Color> _blockColor = Pref.blockColor;
  String _userId = Pref.blockUserID;
  bool _blockToast = Pref.blockToast;
  String _blockServer = Pref.blockServer;
  bool _blockTrack = Pref.blockTrack;
  bool _enableDynSponsorDetection = Pref.enableDynSponsorDetection;
  bool _enableDanmakuTimeParsing = Pref.enableDanmakuTimeParsing;
  final _serverStatus = Rxn<bool>();
  final _userInfo = LoadingState<UserInfo>.loading().obs;

  Box setting = GStorage.setting;

  @override
  void initState() {
    super.initState();
    _checkServerStatus();
    _getUserInfo();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _checkServerStatus() async {
    _serverStatus.value = (await SponsorBlock.uptimeStatus()).isSuccess;
  }

  Future<void> _getUserInfo() async {
    _userInfo.value = await SponsorBlock.userInfo(const [
      'viewCount',
      'minutesSaved',
      'segmentCount',
      'warnings',
      'warningReason',
    ], userId: _userId);
  }

  Widget _blockLimitItem(
    ThemeData theme,
    TextStyle titleStyle,
    TextStyle subTitleStyle,
  ) => Builder(
    builder: (context) {
      return ListTile(
        dense: true,
        onTap: () {
          _textController.text = _blockLimit.toString();
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: Text('最短片段时长', style: titleStyle),
              content: TextFormField(
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                controller: _textController,
                autofocus: true,
                decoration: const InputDecoration(suffixText: 's'),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d\.]+')),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: Get.back,
                  child: Text(
                    '取消',
                    style: TextStyle(color: theme.colorScheme.outline),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    try {
                      _blockLimit = double.parse(_textController.text);
                      Get.back();
                      setting.put(SettingBoxKey.blockLimit, _blockLimit);
                      (context as Element).markNeedsBuild();
                    } catch (e) {
                      SmartDialog.showToast(e.toString());
                    }
                  },
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        },
        title: Text('最短片段时长', style: titleStyle),
        subtitle: Text(
          '忽略短于此时长的片段',
          style: subTitleStyle,
        ),
        trailing: Text(
          '${_blockLimit}s',
          style: const TextStyle(fontSize: 13),
        ),
      );
    },
  );

  Widget _aboutItem(TextStyle titleStyle, TextStyle subTitleStyle) => ListTile(
    dense: true,
    title: Text('关于空降助手', style: titleStyle),
    subtitle: Text(_url, style: subTitleStyle),
    onTap: () => PageUtils.launchURL(_url),
  );

  Widget _userIdItem(
    ThemeData theme,
    TextStyle titleStyle,
    TextStyle subTitleStyle,
  ) => Builder(
    builder: (context) {
      return ListTile(
        dense: true,
        title: Text('用户ID', style: titleStyle),
        subtitle: Text(_userId, style: subTitleStyle),
        onTap: () {
          final key = GlobalKey<FormFieldState<String>>();
          _textController.text = _userId;
          showDialog(
            context: context,
            builder: (_) {
              return AlertDialog(
                title: Text('用户ID', style: titleStyle),
                content: TextFormField(
                  key: key,
                  minLines: 1,
                  maxLines: 4,
                  autofocus: true,
                  controller: _textController,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\d]+')),
                  ],
                  decoration: const InputDecoration(errorMaxLines: 2),
                  validator: (value) {
                    if ((value?.length ?? -1) < 30) {
                      return '用户ID要求至少为30个字符长度的纯字符串';
                    }
                    return null;
                  },
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Get.back();
                      _userId = Digest(
                        List.generate(16, (_) => Utils.random.nextInt(256)),
                      ).toString();
                      setting.put(SettingBoxKey.blockUserID, _userId);
                      (context as Element).markNeedsBuild();
                    },
                    child: const Text('随机'),
                  ),
                  TextButton(
                    onPressed: Get.back,
                    child: Text(
                      '取消',
                      style: TextStyle(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      if (key.currentState?.validate() == true) {
                        Get.back();
                        _userId = _textController.text;
                        setting.put(SettingBoxKey.blockUserID, _userId);
                        (context as Element).markNeedsBuild();
                      }
                    },
                    child: const Text('确定'),
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );

  Widget _blockToastItem(TextStyle titleStyle) => Builder(
    builder: (context) {
      void update() {
        _blockToast = !_blockToast;
        setting.put(SettingBoxKey.blockToast, _blockToast);
        (context as Element).markNeedsBuild();
      }

      return ListTile(
        dense: true,
        onTap: update,
        title: Text(
          '显示跳过Toast',
          style: titleStyle,
        ),
        trailing: Transform.scale(
          alignment: Alignment.centerRight,
          scale: 0.8,
          child: Switch(
            value: _blockToast,
            onChanged: (val) => update(),
          ),
        ),
      );
    },
  );

  Widget _blockTrackItem(
    TextStyle titleStyle,
    TextStyle subTitleStyle,
  ) => Builder(
    builder: (context) {
      void update() {
        _blockTrack = !_blockTrack;
        setting.put(SettingBoxKey.blockTrack, _blockTrack);
        (context as Element).markNeedsBuild();
      }

      return ListTile(
        dense: true,
        onTap: update,
        title: Text(
          '跳过次数统计跟踪',
          style: titleStyle,
        ),
        subtitle: Text(
          // from origin extension
          '此功能追踪您跳过了哪些片段，让用户知道他们提交的片段帮助了多少人。同时点赞会作为依据，确保垃圾信息不会污染数据库。在您每次跳过片段时，我们都会向服务器发送一条消息。希望大家开启此项设置，以便得到更准确的统计数据。:)',
          style: subTitleStyle,
        ),
        trailing: Transform.scale(
          alignment: Alignment.centerRight,
          scale: 0.8,
          child: Switch(
            value: _blockTrack,
            onChanged: (val) => update(),
          ),
        ),
      );
    },
  );

  Widget _blockUserInfo(
    ThemeData theme,
    TextStyle titleStyle,
    TextStyle subTitleStyle,
  ) => Obx(
    () {
      return ListTile(
        dense: true,
        onTap: () {
          _userInfo.value = LoadingState.loading();
          _getUserInfo();
        },
        title: Text(
          '您的信息',
          style: titleStyle,
        ),
        subtitle: switch (_userInfo.value) {
          Loading() => const SizedBox.shrink(),
          Success<UserInfo>(:final response) => Text(
            response.toString(),
            style: subTitleStyle,
          ),
          Error(:final errMsg) => Text(
            errMsg ?? '服务器错误',
            style: subTitleStyle.copyWith(color: theme.colorScheme.error),
          ),
        },
      );
    },
  );

  Widget _blockServerItem(
    ThemeData theme,
    TextStyle titleStyle,
    TextStyle subTitleStyle,
  ) => Builder(
    builder: (context) {
      return ListTile(
        dense: true,
        onTap: () {
          _textController.text = _blockServer;
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: Text('服务器地址', style: titleStyle),
              content: TextFormField(
                keyboardType: TextInputType.url,
                controller: _textController,
                autofocus: true,
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Get.back();
                    _blockServer = HttpString.sponsorBlockBaseUrl;
                    setting.put(SettingBoxKey.blockServer, _blockServer);
                    Request.accountManager.blockServer = _blockServer;
                    (context as Element).markNeedsBuild();
                  },
                  child: const Text('重置'),
                ),
                TextButton(
                  onPressed: Get.back,
                  child: Text(
                    '取消',
                    style: TextStyle(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Get.back();
                    _blockServer = _textController.text;
                    setting.put(SettingBoxKey.blockServer, _blockServer);
                    Request.accountManager.blockServer = _blockServer;
                    _checkServerStatus();
                    _getUserInfo();
                    (context as Element).markNeedsBuild();
                  },
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        },
        title: Text(
          '服务器地址',
          style: titleStyle,
        ),
        subtitle: Text(
          _blockServer,
          style: subTitleStyle,
        ),
      );
    },
  );

  Widget _serverStatusItem(ThemeData theme, TextStyle titleStyle) => Obx(
    () {
      String status;
      Color? color;
      switch (_serverStatus.value) {
        case null:
          status = '——';
        case true:
          status = '正常';
          color = theme.colorScheme.primary;
        case false:
          status = '错误';
          color = theme.colorScheme.error;
      }
      return ListTile(
        dense: true,
        onTap: () {
          _serverStatus.value = null;
          _checkServerStatus();
        },
        title: Text('服务器状态', style: titleStyle),
        trailing: Text(
          status,
          style: TextStyle(fontSize: 13, color: color),
        ),
      );
    },
  );

  void onSelectColor(
    BuildContext context,
    int index,
    Color color,
    Pair<SegmentType, SkipType> item,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        title: Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'Color Picker ',
                style: TextStyle(fontSize: 15),
              ),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  height: 10,
                  width: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
                style: const TextStyle(fontSize: 13, height: 1),
              ),
              TextSpan(
                text: ' ${item.first.title}',
                style: const TextStyle(fontSize: 13, height: 1),
              ),
            ],
          ),
        ),
        content: SlideColorPicker(
          color: color,
          showResetBtn: true,
          onChanged: (Color? color) {
            _blockColor[index] = color ?? item.first.color;
            setting.put(
              SettingBoxKey.blockColor,
              _blockColor
                  .map((item) => item.toARGB32().toRadixString(16).substring(2))
                  .toList(),
            );
            (context as Element).markNeedsBuild();
          },
        ),
      ),
    );
  }

  Widget _warningBanner(ThemeData theme) => Obx(
    () {
      if (_userInfo.value case Success<UserInfo>(:final response)) {
        if (response.warningReason != null) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '警告: ${response.warningReason}',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final res = await SponsorBlock.warnUser();
                    SmartDialog.showToast(
                      res.isSuccess ? '已确认' : '确认失败: $res',
                    );
                    if (res.isSuccess) {
                      _userInfo.value = LoadingState.loading();
                      _getUserInfo();
                    }
                  },
                  child: const Text('知道了'),
                ),
              ],
            ),
          );
        }
      }
      return const SizedBox.shrink();
    },
  );

  Widget _whitelistItem(
    ThemeData theme,
    TextStyle titleStyle,
    TextStyle subTitleStyle,
  ) => Builder(
    builder: (context) {
      final channels = Pref.blockWhitelistedChannels;
      return ListTile(
        dense: true,
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => StatefulBuilder(
              builder: (context, setDialogState) {
                final list = Pref.blockWhitelistedChannels;
                return AlertDialog(
                  title: Text('频道白名单', style: titleStyle),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: list.isEmpty
                        ? const Text('暂无白名单频道')
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: list.length,
                            itemBuilder: (_, index) {
                              final item = list[index];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  item['name']?.toString() ?? '',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 20),
                                  onPressed: () {
                                    list.removeAt(index);
                                    Pref.setBlockWhitelistedChannels(list);
                                    setDialogState(() {});
                                    (context as Element).markNeedsBuild();
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                  actions: [
                    if (list.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          Pref.setBlockWhitelistedChannels([]);
                          setDialogState(() {});
                          (context as Element).markNeedsBuild();
                        },
                        child: Text(
                          '清除全部',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    TextButton(
                      onPressed: Get.back,
                      child: const Text('关闭'),
                    ),
                  ],
                );
              },
            ),
          );
        },
        title: Text('频道白名单', style: titleStyle),
        subtitle: Text(
          '白名单中的频道不会加载片段',
          style: subTitleStyle,
        ),
        trailing: Text(
          '${channels.length}个频道',
          style: const TextStyle(fontSize: 13),
        ),
      );
    },
  );

  Widget _localStatsItem(TextStyle titleStyle, TextStyle subTitleStyle) {
    final skipCount = Pref.blockSkipCount;
    final minutesSaved = Pref.blockMinutesSaved;
    return ListTile(
      dense: true,
      title: Text('本地统计', style: titleStyle),
      subtitle: Text(
        '已跳过 $skipCount 个片段，节省 ${minutesSaved.toStringAsFixed(1)} 分钟',
        style: subTitleStyle,
      ),
    );
  }

  Widget _dynSponsorDetectionItem(
    ThemeData theme,
    TextStyle titleStyle,
    TextStyle subTitleStyle,
  ) => Builder(
    builder: (context) {
      void update() {
        _enableDynSponsorDetection = !_enableDynSponsorDetection;
        setting.put(
          SettingBoxKey.enableDynSponsorDetection,
          _enableDynSponsorDetection,
        );
        (context as Element).markNeedsBuild();
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            dense: true,
            onTap: update,
            title: Text('动态赞助检测', style: titleStyle),
            subtitle: Text(
              '自动检测动态中的赞助/广告内容',
              style: subTitleStyle,
            ),
            trailing: Transform.scale(
              alignment: Alignment.centerRight,
              scale: 0.8,
              child: Switch(
                value: _enableDynSponsorDetection,
                onChanged: (val) => update(),
              ),
            ),
          ),
          if (_enableDynSponsorDetection)
            ListTile(
              dense: true,
              onTap: () {
                _textController.text = Pref.blockDynSponsorKeywords;
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text('自定义关键词正则', style: titleStyle),
                    content: TextFormField(
                      controller: _textController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: '留空使用默认关键词',
                      ),
                      maxLines: 3,
                    ),
                    actions: [
                      TextButton(
                        onPressed: Get.back,
                        child: Text(
                          '取消',
                          style: TextStyle(color: theme.colorScheme.outline),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Get.back();
                          setting.put(
                            SettingBoxKey.blockDynSponsorKeywords,
                            _textController.text,
                          );
                        },
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                );
              },
              title: Text('自定义关键词', style: subTitleStyle),
              trailing: const Icon(Icons.chevron_right, size: 20),
            ),
        ],
      );
    },
  );

  Widget _danmakuTimeParsingItem(TextStyle titleStyle) => Builder(
    builder: (context) {
      void update() {
        _enableDanmakuTimeParsing = !_enableDanmakuTimeParsing;
        setting.put(
          SettingBoxKey.enableDanmakuTimeParsing,
          _enableDanmakuTimeParsing,
        );
        (context as Element).markNeedsBuild();
      }

      return ListTile(
        dense: true,
        onTap: update,
        title: Text('弹幕时间解析', style: titleStyle),
        trailing: Transform.scale(
          alignment: Alignment.centerRight,
          scale: 0.8,
          child: Switch(
            value: _enableDanmakuTimeParsing,
            onChanged: (val) => update(),
          ),
        ),
      );
    },
  );

  Widget _usernameItem(
    ThemeData theme,
    TextStyle titleStyle,
    TextStyle subTitleStyle,
  ) => Builder(
    builder: (context) {
      return ListTile(
        dense: true,
        onTap: () async {
          SmartDialog.showLoading();
          final result = await SponsorBlock.getUsername();
          SmartDialog.dismiss();
          final currentName = result.dataOrNull ?? '';
          _textController.text = currentName;
          if (!context.mounted) return;
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: Text('显示名称', style: titleStyle),
              content: TextFormField(
                controller: _textController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '输入显示名称',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: Get.back,
                  child: Text(
                    '取消',
                    style: TextStyle(color: theme.colorScheme.outline),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final name = _textController.text.trim();
                    if (name.isNotEmpty) {
                      Get.back();
                      final res = await SponsorBlock.setUsername(name);
                      SmartDialog.showToast(
                        res.isSuccess ? '设置成功' : '设置失败: $res',
                      );
                    }
                  },
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        },
        title: Text('显示名称', style: titleStyle),
        subtitle: Text('设置您的公开显示名称', style: subTitleStyle),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const titleStyle = TextStyle(fontSize: 15);

    final subTitleStyle = TextStyle(
      fontSize: 13,
      color: theme.colorScheme.outline,
    );

    final divider = Divider(
      height: 1,
      color: theme.colorScheme.outline.withValues(alpha: 0.1),
    );

    final sliverDivider = SliverToBoxAdapter(child: divider);

    final dividerL = SliverToBoxAdapter(
      child: Divider(
        thickness: 16,
        color: theme.colorScheme.outline.withValues(alpha: 0.1),
      ),
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text('空降助手')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _warningBanner(theme)),
          dividerL,
          SliverToBoxAdapter(child: _serverStatusItem(theme, titleStyle)),
          dividerL,
          SliverToBoxAdapter(
            child: _blockLimitItem(theme, titleStyle, subTitleStyle),
          ),
          sliverDivider,
          SliverToBoxAdapter(child: _blockToastItem(titleStyle)),
          sliverDivider,
          SliverToBoxAdapter(child: _blockTrackItem(titleStyle, subTitleStyle)),
          sliverDivider,
          SliverToBoxAdapter(
            child: _blockUserInfo(theme, titleStyle, subTitleStyle),
          ),
          dividerL,
          SliverList.separated(
            itemCount: _blockSettings.length,
            itemBuilder: (context, index) =>
                _buildItem(theme, index, _blockSettings[index]),
            separatorBuilder: (context, index) => divider,
          ),
          dividerL,
          SliverToBoxAdapter(
            child: _whitelistItem(theme, titleStyle, subTitleStyle),
          ),
          sliverDivider,
          SliverToBoxAdapter(
            child: _localStatsItem(titleStyle, subTitleStyle),
          ),
          dividerL,
          SliverToBoxAdapter(
            child: _usernameItem(theme, titleStyle, subTitleStyle),
          ),
          sliverDivider,
          SliverToBoxAdapter(
            child: _userIdItem(theme, titleStyle, subTitleStyle),
          ),
          sliverDivider,
          SliverToBoxAdapter(
            child: _blockServerItem(theme, titleStyle, subTitleStyle),
          ),
          dividerL,
          SliverToBoxAdapter(child: _aboutItem(titleStyle, subTitleStyle)),
          dividerL,
          SliverToBoxAdapter(
            child: _dynSponsorDetectionItem(theme, titleStyle, subTitleStyle),
          ),
          sliverDivider,
          SliverToBoxAdapter(
            child: _danmakuTimeParsingItem(titleStyle),
          ),
          dividerL,
          SliverToBoxAdapter(
            child: SizedBox(
              height: 55 + MediaQuery.viewPaddingOf(context).bottom,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    ThemeData theme,
    int index,
    Pair<SegmentType, SkipType> item,
  ) {
    return Builder(
      builder: (context) {
        Color color = _blockColor[index];
        final isDisable = item.second == SkipType.disable;
        return ListTile(
          dense: true,
          enabled: item.second != SkipType.disable,
          onTap: () => onSelectColor(context, index, color, item),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Container(
                        height: 10,
                        width: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                      ),
                      style: const TextStyle(fontSize: 14, height: 1),
                    ),
                    TextSpan(
                      text: ' ${item.first.title}',
                      style: const TextStyle(fontSize: 14, height: 1),
                    ),
                  ],
                ),
              ),
              Builder(
                builder: (btnContext) {
                  return PopupMenuButton<SkipType>(
                    initialValue: item.second,
                    onSelected: (e) {
                      final updateItem = isDisable || e == SkipType.disable;
                      item.second = e;
                      setting.put(
                        SettingBoxKey.blockSettings,
                        _blockSettings.map((e) => e.second.index).toList(),
                      );
                      if (updateItem) {
                        (context as Element).markNeedsBuild();
                      } else {
                        (btnContext as Element).markNeedsBuild();
                      }
                    },
                    itemBuilder: (context) => SkipType.values
                        .map(
                          (item) => PopupMenuItem<SkipType>(
                            value: item,
                            child: Text(item.label),
                          ),
                        )
                        .toList(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text.rich(
                        style: TextStyle(
                          height: 1,
                          fontSize: 14,
                          color: isDisable
                              ? theme.colorScheme.outline.withValues(
                                  alpha: 0.7,
                                )
                              : theme.colorScheme.secondary,
                        ),
                        strutStyle: const StrutStyle(
                          height: 1,
                          leading: 0,
                          fontSize: 14,
                        ),
                        TextSpan(
                          children: [
                            TextSpan(text: item.second.label),
                            WidgetSpan(
                              alignment: .middle,
                              child: Icon(
                                size: 14,
                                MdiIcons.unfoldMoreHorizontal,
                                color: isDisable
                                    ? theme.colorScheme.outline.withValues(
                                        alpha: 0.7,
                                      )
                                    : theme.colorScheme.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          subtitle: Text(
            item.first.description,
            style: TextStyle(
              fontSize: 12,
              color: isDisable ? null : theme.colorScheme.outline,
            ),
          ),
        );
      },
    );
  }
}
