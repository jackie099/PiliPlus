import 'package:PiliPlus/models/common/sponsor_block/action_type.dart';
import 'package:PiliPlus/models/common/sponsor_block/segment_type.dart';
import 'package:PiliPlus/models/common/sponsor_block/skip_type.dart';
import 'package:PiliPlus/models_new/sponsor_block/segment_item.dart';
import 'package:PiliPlus/pages/sponsor_block/block_mixin.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

class SegmentModel implements Comparable<SegmentModel> {
  SegmentModel({
    required this.uuid,
    required this.segmentType,
    required this.segment,
    required this.skipType,
    required this.actionType,
  });
  final String uuid;
  final SegmentType segmentType;
  final (int, int) segment;
  final SkipType skipType;
  final ActionType actionType;
  bool hasSkipped = false;

  factory SegmentModel.fromItemModel(
    SegmentItemModel model,
    BlockConfigMixin? config,
  ) {
    final segmentType = SegmentType.values.byName(model.category);
    final segment = (model.segment[0], model.segment[1]);
    final actionType = model.actionType != null
        ? ActionType.values.byName(model.actionType!)
        : ActionType.skip;
    SkipType skipType;
    if (config != null) {
      skipType = config.blockSettings[segmentType.index].second;
      if (skipType != SkipType.showOnly) {
        if (segment.isEq || segment.length < config.blockLimit) {
          skipType = SkipType.showOnly;
        }
      }
    } else {
      skipType = Pref.pgcSkipType;
    }

    return SegmentModel(
      uuid: model.uuid,
      segmentType: segmentType,
      segment: segment,
      skipType: skipType,
      actionType: actionType,
    );
  }

  @override
  int compareTo(SegmentModel other) => segment.$1.compareTo(other.segment.$1);
}

extension IntRecordExt on (int, int) {
  bool get isEq => $1 == $2;
  int get length => $2 - $1;
  bool contains(num other) => $1 <= other && other < $2;
}
