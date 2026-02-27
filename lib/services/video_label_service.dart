import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/sponsor_block.dart';
import 'package:PiliPlus/models/common/sponsor_block/segment_type.dart';
import 'package:PiliPlus/models_new/sponsor_block/video_label.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

class VideoLabelService {
  VideoLabelService._();
  static final instance = VideoLabelService._();

  /// Get the primary label for a video (cached, non-blocking)
  Future<String?> getLabel(String? bvid) async {
    if (bvid == null || !Pref.enableSponsorBlock) return null;
    final result = await SponsorBlock.getVideoLabels(bvid);
    if (result case Success<List<VideoLabelModel>>(:final response)) {
      if (response.isNotEmpty) {
        try {
          final type = SegmentType.values.byName(response.first.category);
          return type.shortTitle;
        } catch (_) {
          return response.first.category;
        }
      }
    }
    return null;
  }
}
