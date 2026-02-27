import 'dart:async' show StreamSubscription, Timer;
import 'dart:collection' show HashMap;
import 'dart:math' as math;

import 'package:PiliPlus/common/widgets/progress_bar/segment_progress_bar.dart';
import 'package:PiliPlus/grpc/dm.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/sponsor_block.dart';
import 'package:PiliPlus/models/common/sponsor_block/action_type.dart';
import 'package:PiliPlus/models/common/sponsor_block/segment_model.dart';
import 'package:PiliPlus/models/common/sponsor_block/segment_type.dart';
import 'package:PiliPlus/models/common/sponsor_block/skip_type.dart';
import 'package:PiliPlus/models_new/sponsor_block/segment_item.dart';
import 'package:PiliPlus/pages/danmaku/controller.dart' show PlDanmakuController;
import 'package:PiliPlus/pages/sponsor_block/port_video_dialog.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/danmaku_time_parser.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:media_kit/media_kit.dart';

mixin BlockConfigMixin {
  late final pgcSkipType = Pref.pgcSkipType;
  late final enablePgcSkip = pgcSkipType != SkipType.disable;
  late final enableSponsorBlock = Pref.enableSponsorBlock;
  late final enableBlock = enableSponsorBlock || enablePgcSkip;
  late final blockColor = Pref.blockColor;
  late final blockLimit = Pref.blockLimit;
  late final blockSettings = Pref.blockSettings;
  late final enableList = blockSettings
      .where((item) => item.second != SkipType.disable)
      .map((item) => item.first.name)
      .toSet();

  Color _getColor(SegmentType segment) => blockColor[segment.index];
}

/// Wraps a segment + pre-skip position for the unskip button
class UnskipItem {
  final SegmentModel segment;
  final Duration preSkipPosition;

  const UnskipItem({required this.segment, required this.preSkipPosition});
}

mixin BlockMixin on GetxController {
  int? _lastBlockPos;
  BlockConfigMixin get blockConfig;
  StreamSubscription<Duration>? _blockListener;
  StreamSubscription<Duration>? get blockListener => _blockListener;
  late final List<SegmentModel> _segmentList = <SegmentModel>[];
  late final RxList<Segment> segmentProgressList = <Segment>[].obs;

  Timer? _skipTimer;
  late final listKey = GlobalKey<AnimatedListState>();
  late final List<Object> listData = [];

  // Mute tracking
  SegmentModel? _activeMuteSegment;
  double? _preMuteVolume;

  // Category pill observable
  final Rxn<SegmentModel> currentSegment = Rxn();

  RxString? get videoLabel => null;
  Player? get player;
  bool get autoPlay;
  int? get timeLength;
  bool get preInitPlayer;
  int get currPosInMilliseconds;
  bool get isFullScreen => false;

  /// Override in controllers for port video dialog
  String? get sbBvid => null;
  int? get sbCid => null;
  int? get sbVideoDuration => null;

  bool get isUgc;
  late final isBlock = isUgc || !blockConfig.enablePgcSkip;

  /// Override in controllers that have owner info
  int? get ownerMid => null;
  String? get ownerName => null;

  bool get isWhitelisted {
    final mid = ownerMid;
    if (mid == null) return false;
    return Pref.blockWhitelistedChannels.any((e) => e['id'] == mid);
  }

  void toggleWhitelist() {
    final mid = ownerMid;
    final name = ownerName;
    if (mid == null) return;
    final list = Pref.blockWhitelistedChannels;
    final idx = list.indexWhere((e) => e['id'] == mid);
    if (idx >= 0) {
      list.removeAt(idx);
      SmartDialog.showToast('已从白名单移除');
    } else {
      list.add({'id': mid, 'name': name ?? mid.toString()});
      SmartDialog.showToast('已添加到白名单');
    }
    Pref.setBlockWhitelistedChannels(list);
  }

  Future<void> querySponsorBlock({
    required String bvid,
    required int cid,
  }) async {
    resetBlock();

    if (isWhitelisted) return;

    final result = await SponsorBlock.getSkipSegments(bvid: bvid, cid: cid);
    switch (result) {
      case Success<List<SegmentItemModel>>(:final response):
        handleSBData(response);
      case Error(:final code) when code != 404:
        if (kDebugMode) {
          result.toast();
        }
      default:
    }
  }

  Future<void> parseDanmakuPOI({
    required int cid,
    required int videoDuration,
  }) async {
    if (!Pref.enableDanmakuTimeParsing || videoDuration <= 0) return;
    try {
      final totalSegments =
          (videoDuration / PlDanmakuController.segmentLength).ceil();
      // Collect all timestamps from all danmaku segments
      final timestamps = <int>[];
      for (int i = 0; i < totalSegments; i++) {
        if (isClosed) return;
        final res = await DmGrpc.dmSegMobile(cid: cid, segmentIndex: i + 1);
        if (res case Success(:final response)) {
          for (final elem in response.elems) {
            timestamps.addAll(DanmakuTimeParser.parse(elem.content));
          }
        }
      }
      if (timestamps.isEmpty || isClosed) return;

      // Group timestamps by ±3s buckets
      timestamps.sort();
      final buckets = HashMap<int, int>(); // bucket key -> count
      for (final ts in timestamps) {
        final key = (ts / 3000).round() * 3000;
        buckets[key] = (buckets[key] ?? 0) + 1;
      }

      // Filter by consensus threshold (≥3 references)
      final poiTimestamps =
          buckets.entries.where((e) => e.value >= 3).map((e) => e.key).toList()
            ..sort();
      if (poiTimestamps.isEmpty || isClosed) return;

      final color = blockConfig._getColor(SegmentType.poi_highlight);
      for (final ts in poiTimestamps) {
        final segment = SegmentModel(
          uuid: 'danmaku-poi-$ts',
          segmentType: SegmentType.poi_highlight,
          segment: (ts, ts),
          skipType: SkipType.showOnly,
          actionType: ActionType.poi,
        );
        _segmentList.add(segment);
        segmentProgressList.add(
          Segment(
            start: (ts / videoDuration).clamp(0.0, 1.0),
            end: (ts / videoDuration).clamp(0.0, 1.0),
            color: color,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('parseDanmakuPOI: $e');
    }
  }

  void initSkip() {
    if (isClosed) return;
    if (_segmentList.isNotEmpty) {
      _blockListener?.cancel();
      _blockListener = player?.stream.position.listen((position) {
        int currentPos = position.inSeconds;
        if (currentPos != _lastBlockPos) {
          _lastBlockPos = currentPos;
          final msPos = currentPos * 1000;

          // Update category pill
          _updateCurrentSegment(msPos);

          // Handle mute segment exit
          _checkMuteExit(msPos);

          for (SegmentModel item in _segmentList) {
            if (msPos <= item.segment.$1 && item.segment.$1 <= msPos + 1000) {
              // Handle mute action
              if (item.actionType == ActionType.mute) {
                _handleMuteEnter(item);
                break;
              }

              switch (item.skipType) {
                case SkipType.alwaysSkip:
                  onSkip(item, isSeek: false);
                  break;
                case SkipType.skipOnce:
                  if (!item.hasSkipped) {
                    item.hasSkipped = true;
                    onSkip(item, isSeek: false);
                  }
                  break;
                case SkipType.skipManually:
                  onAddItem(item);
                  break;
                default:
                  break;
              }
              break;
            }
          }
        }
      });
    }
  }

  /// Update the current segment for the category pill
  void _updateCurrentSegment(int msPos) {
    SegmentModel? active;
    for (final item in _segmentList) {
      if (item.segment.contains(msPos) && !item.segment.isEq) {
        active = item;
        break;
      }
    }
    if (currentSegment.value != active) {
      currentSegment.value = active;
    }
  }

  /// Enter mute segment: store volume and set to 0
  void _handleMuteEnter(SegmentModel item) {
    if (_activeMuteSegment != null) return;
    _activeMuteSegment = item;
    _preMuteVolume = PlPlayerController.getVolumeIfExists();
    PlPlayerController.setVolumeIfExists(0);
    if (autoPlay && Pref.blockToast) {
      _showBlockToast('已静音${item.segmentType.shortTitle}片段');
    }
    if (isBlock && Pref.blockTrack) {
      SponsorBlock.viewedVideoSponsorTime(item.uuid);
    }
  }

  /// Check if we've exited the active mute segment
  void _checkMuteExit(int msPos) {
    if (_activeMuteSegment != null) {
      if (!_activeMuteSegment!.segment.contains(msPos)) {
        _restoreMuteVolume();
      }
    }
  }

  /// Restore volume after mute segment
  void _restoreMuteVolume() {
    if (_preMuteVolume != null) {
      PlPlayerController.setVolumeIfExists(_preMuteVolume!);
    }
    _activeMuteSegment = null;
    _preMuteVolume = null;
  }

  Future<void> handleSBData(List<SegmentItemModel> list) async {
    if (list.isNotEmpty) {
      try {
        Future<void>? future;
        final duration = list.first.videoDuration ?? timeLength!;
        // segmentList
        _segmentList.addAll(
          list
              .where(
                (item) =>
                    blockConfig.enableList.contains(item.category) &&
                    item.segment[1] >= item.segment[0],
              )
              .map(
                (item) {
                  final segmentModel = SegmentModel.fromItemModel(
                    item,
                    isBlock ? blockConfig : null,
                  );
                  if (segmentModel.segment == const (0, 0)) {
                    videoLabel?.value +=
                        '${videoLabel!.value.isNotEmpty ? '/' : ''}${segmentModel.segmentType.title}';
                  }

                  if (_blockListener == null && autoPlay && player != null) {
                    final currPos = currPosInMilliseconds;

                    if (segmentModel.segment.contains(currPos)) {
                      _lastBlockPos = currPos;

                      // Handle mute action on initial load
                      if (segmentModel.actionType == ActionType.mute) {
                        _handleMuteEnter(segmentModel);
                      } else {
                        switch (segmentModel.skipType) {
                          case SkipType.alwaysSkip:
                          case SkipType.skipOnce:
                            segmentModel.hasSkipped = true;
                            if (player!.state.playing) {
                              future = onSkip(
                                segmentModel,
                              );
                            } else {
                              player!.stream.playing.firstWhere((e) {
                                if (e) {
                                  future = onSkip(segmentModel);
                                  return true;
                                }
                                return false;
                              }, orElse: () => false);
                            }
                            break;
                          case SkipType.skipManually:
                            onAddItem(segmentModel);
                            break;
                          default:
                            break;
                        }
                      }
                    }
                  }

                  return segmentModel;
                },
              ),
        );

        // _segmentProgressList
        segmentProgressList.addAll(
          _segmentList.map((e) {
            double start = (e.segment.$1 / duration).clamp(0.0, 1.0);
            double end = (e.segment.$2 / duration).clamp(0.0, 1.0);
            return Segment(
              start: start,
              end: end,
              color: blockConfig._getColor(e.segmentType),
            );
          }),
        );

        if (_blockListener == null && (autoPlay || preInitPlayer)) {
          await future;
          initSkip();
        }
      } catch (e) {
        if (kDebugMode) debugPrint('failed to parse sponsorblock: $e');
      }
    }
  }

  void onAddItem(Object item) {
    if (listData.contains(item)) return;
    listData.insert(0, item);
    listKey.currentState?.insertItem(0);
    _skipTimer ??= Timer.periodic(const Duration(seconds: 4), (_) {
      if (listData.isNotEmpty) {
        onRemoveItem(listData.length - 1, listData.last);
      }
    });
  }

  void onRemoveItem(int index, Object item) {
    EasyThrottle.throttle(
      'onRemoveItem',
      const Duration(milliseconds: 500),
      () {
        try {
          listData.removeAt(index);
          if (listData.isEmpty) {
            _stopSkipTimer();
          }
          listKey.currentState?.removeItem(
            index,
            (context, animation) => buildItem(item, animation),
          );
        } catch (_) {}
      },
    );
  }

  Widget buildItem(Object item, Animation<double> animation) =>
      throw UnimplementedError();

  void _stopSkipTimer() {
    if (_skipTimer != null) {
      _skipTimer!.cancel();
      _skipTimer = null;
    }
  }

  Future<void>? seekTo(Duration duration, {required bool isSeek});

  void _skipToast(SegmentModel item) {
    if (autoPlay && Pref.blockToast) {
      // Add unskip item instead of plain toast
      final preSkipPos = Duration(milliseconds: currPosInMilliseconds);
      onAddItem(UnskipItem(segment: item, preSkipPosition: preSkipPos));
    }
    if (isBlock && Pref.blockTrack) {
      SponsorBlock.viewedVideoSponsorTime(item.uuid);
    }
    // Track local stats
    _incrementLocalStats(item);
  }

  void _incrementLocalStats(SegmentModel item) {
    final count = Pref.blockSkipCount;
    Pref.setBlockSkipCount(count + 1);
    final minutes = Pref.blockMinutesSaved;
    Pref.setBlockMinutesSaved(minutes + item.segment.length / 1000 / 60);
  }

  Future<void> onSkip(
    SegmentModel item, {
    bool isSkip = true,
    bool isSeek = true,
  }) async {
    try {
      await seekTo(
        Duration(milliseconds: item.segment.$2),
        isSeek: isSeek,
      );
      if (isSkip) {
        _skipToast(item);
      } else {
        _showBlockToast('已跳至${item.segmentType.shortTitle}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('failed to skip: $e');
      if (isSkip) {
        _showBlockToast('${item.segmentType.shortTitle}片段跳过失败');
      } else {
        _showBlockToast('跳转失败');
      }
    }
  }

  void _showBlockToast(String msg) {
    SmartDialog.showToast(
      msg,
      alignment: isFullScreen ? const Alignment(0, 0.7) : null,
    );
  }

  void _showVoteDialog(SegmentModel segment) {
    showDialog(
      context: Get.context!,
      builder: (context) => AlertDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                dense: true,
                title: const Text('赞成票', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Get.back();
                  _doVote(segment.uuid, 1);
                },
              ),
              ListTile(
                dense: true,
                title: const Text('反对票', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Get.back();
                  _doVote(segment.uuid, 0);
                },
              ),
              ListTile(
                dense: true,
                title: const Text('更改类别', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Get.back();
                  _showCategoryDialog(segment);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _doVote(String uuid, int type) => SponsorBlock.voteOnSponsorTime(
    uuid: uuid,
    type: type,
  ).then((i) => SmartDialog.showToast(i.isSuccess ? '投票成功' : '投票失败: $i'));

  void _showCategoryDialog(SegmentModel segment) {
    showDialog(
      context: Get.context!,
      builder: (context) => AlertDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: SegmentType.values
                .map(
                  (item) => ListTile(
                    dense: true,
                    onTap: () {
                      Get.back();
                      SponsorBlock.voteOnSponsorTime(
                        uuid: segment.uuid,
                        category: item,
                      ).then((i) {
                        SmartDialog.showToast(
                          '类别更改${i.isSuccess ? '成功' : '失败: $i'}',
                        );
                      });
                    },
                    title: Text.rich(
                      TextSpan(
                        children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Container(
                              height: 10,
                              width: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: blockConfig._getColor(item),
                              ),
                            ),
                            style: const TextStyle(fontSize: 14, height: 1),
                          ),
                          TextSpan(
                            text: ' ${item.title}',
                            style: const TextStyle(fontSize: 14, height: 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  void showSBDetail() {
    showDialog(
      context: Get.context!,
      builder: (context) => AlertDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ownerMid != null)
                ListTile(
                  dense: true,
                  leading: Icon(
                    isWhitelisted
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                    size: 20,
                  ),
                  title: Text(
                    isWhitelisted ? '已在白名单中' : '添加到白名单',
                    style: const TextStyle(fontSize: 14),
                  ),
                  onTap: () {
                    Get.back();
                    toggleWhitelist();
                  },
                ),
              if (sbBvid != null && sbCid != null)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.link, size: 20),
                  title: const Text(
                    '搬运视频绑定',
                    style: TextStyle(fontSize: 14),
                  ),
                  onTap: () {
                    Get.back();
                    showDialog(
                      context: Get.context!,
                      builder: (_) => PortVideoDialog(
                        bvid: sbBvid!,
                        cid: sbCid!,
                        videoDuration: sbVideoDuration ?? 0,
                      ),
                    );
                  },
                ),
              ..._segmentList
                .map(
                  (item) => ListTile(
                    onTap: () {
                      Get.back();
                      if (isBlock) {
                        _showVoteDialog(item);
                      }
                    },
                    dense: true,
                    title: Text.rich(
                      TextSpan(
                        children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Container(
                              height: 10,
                              width: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: blockConfig._getColor(item.segmentType),
                              ),
                            ),
                            style: const TextStyle(fontSize: 14, height: 1),
                          ),
                          TextSpan(
                            text: ' ${item.segmentType.title}',
                            style: const TextStyle(fontSize: 14, height: 1),
                          ),
                        ],
                      ),
                    ),
                    contentPadding: const EdgeInsets.only(left: 16, right: 8),
                    subtitle: Text(
                      '${DurationUtils.formatDuration(item.segment.$1 / 1000)} 至 ${DurationUtils.formatDuration(item.segment.$2 / 1000)}'
                      '${item.actionType == ActionType.mute ? ' (静音)' : ''}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.skipType.label,
                          style: const TextStyle(fontSize: 13),
                        ),
                        if (item.segment.$2 != 0)
                          SizedBox(
                            width: 36,
                            height: 36,
                            child: IconButton(
                              tooltip: item.skipType == SkipType.showOnly
                                  ? '跳至此片段'
                                  : '跳过此片段',
                              onPressed: () {
                                Get.back();
                                onSkip(
                                  item,
                                  isSkip: item.skipType != SkipType.showOnly,
                                  isSeek: false,
                                );
                              },
                              style: IconButton.styleFrom(
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: Icon(
                                item.skipType == SkipType.showOnly
                                    ? Icons.my_location
                                    : MdiIcons.debugStepOver,
                                size: 18,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          )
                        else
                          const SizedBox(width: 10),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void cancelBlockListener() {
    if (_blockListener != null) {
      _blockListener!.cancel();
      _blockListener = null;
    }
  }

  void resetBlock() {
    cancelBlockListener();
    _lastBlockPos = null;
    videoLabel?.value = '';
    _segmentList.clear();
    segmentProgressList.clear();
    _restoreMuteVolume();
    currentSegment.value = null;
  }

  Duration? getFirstSegment([int pos = 0]) {
    for (var i in _segmentList..sort()) {
      final (start, end) = i.segment;
      if (start == end) {
        continue;
      } else if (start - pos < 100) {
        // Skip mute segments in getFirstSegment — they don't need seeking
        if (i.actionType == ActionType.mute) continue;
        if (switch (i.skipType) {
          .alwaysSkip => true,
          .skipOnce => !i.hasSkipped,
          _ => false,
        }) {
          _skipToast(i);
          pos = math.max(pos, i.segment.$2);
        }
      } else {
        break;
      }
    }
    if (pos != 0) {
      return Duration(milliseconds: pos);
    }
    return null;
  }

  @override
  void onClose() {
    _stopSkipTimer();
    if (blockConfig.enableBlock) {
      resetBlock();
    }
    super.onClose();
  }
}
