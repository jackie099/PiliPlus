import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/num_utils.dart';

class UserInfo {
  final int viewCount;
  final double minutesSaved;
  final int segmentCount;
  final String? warningReason;

  const UserInfo({
    required this.viewCount,
    required this.minutesSaved,
    required this.segmentCount,
    this.warningReason,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) => UserInfo(
    viewCount: json['viewCount'] ?? 0,
    minutesSaved: (json['minutesSaved'] as num?)?.toDouble() ?? 0,
    segmentCount: json['segmentCount'] ?? 0,
    warningReason: json['warnings'] is int && json['warnings'] > 0
        ? (json['warningReason'] ?? '未知原因').toString()
        : null,
  );

  @override
  String toString() {
    String minutes = DurationUtils.formatTimeDuration(
      Duration(minutes: minutesSaved.round()),
    );
    if (minutes.isEmpty) {
      minutes = '0分钟';
    }
    return ('您提交了 ${NumUtils.formatPositiveDecimal(segmentCount)} 片段\n'
        '您为大家节省了 ${NumUtils.formatPositiveDecimal(viewCount)} 片段\n'
        '($minutes 的生命)');
  }
}
