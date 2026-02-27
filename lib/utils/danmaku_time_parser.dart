/// Parses time references from danmaku (bullet comments) text.
/// Supports:
/// - Numeric formats: "MM:SS", "HH:MM:SS", "M:SS"
/// - Chinese numeral times: "两分三十秒", "一小时二十分"
/// - Arrow references: "向右3下" (3 * 5s forward)
class DanmakuTimeParser {
  DanmakuTimeParser._();

  static const _chineseDigits = {
    '零': 0, '〇': 0,
    '一': 1, '壹': 1,
    '二': 2, '贰': 2, '两': 2,
    '三': 3, '叁': 3,
    '四': 4, '肆': 4,
    '五': 5, '伍': 5,
    '六': 6, '陆': 6,
    '七': 7, '柒': 7,
    '八': 8, '捌': 8,
    '九': 9, '玖': 9,
    '十': 10, '拾': 10,
  };

  /// Numeric time pattern: 1:23, 01:23, 1:02:03
  static final _numericPattern = RegExp(
    r'\b(\d{1,2}):(\d{2})(?::(\d{2}))?\b',
  );

  /// Chinese time pattern: X分X秒, X小时X分
  static final _chinesePattern = RegExp(
    r'([零一二三四五六七八九两壹贰叁肆伍陆柒捌玖十百\d]+)\s*'
    r'(小时|时|分钟|分|秒)'
    r'(?:([零一二三四五六七八九两壹贰叁肆伍陆柒捌玖十百\d]+)\s*'
    r'(分钟|分|秒))?'
    r'(?:([零一二三四五六七八九两壹贰叁肆伍陆柒捌玖十百\d]+)\s*'
    r'(秒))?',
  );

  /// Arrow reference: 向右X下 (each = 5s forward)
  static final _arrowPattern = RegExp(
    r'向右\s*(\d+)\s*下',
  );

  /// Parse a Chinese number string to int
  static int _parseChineseNum(String s) {
    // Try as regular digit first
    final parsed = int.tryParse(s);
    if (parsed != null) return parsed;

    int result = 0;
    int current = 0;

    for (int i = 0; i < s.length; i++) {
      final char = s[i];
      final digit = _chineseDigits[char];
      if (digit == null) continue;

      if (digit == 10) {
        // 十
        if (current == 0) {
          current = 1; // 十 at start means 10
        }
        result += current * 10;
        current = 0;
      } else if (digit == 100) {
        result += current * 100;
        current = 0;
      } else {
        current = digit;
      }
    }
    result += current;
    return result;
  }

  /// Parse all time references from a danmaku text.
  /// Returns list of timestamps in milliseconds.
  static List<int> parse(String text) {
    final results = <int>[];

    // Numeric: "1:23" or "1:02:03"
    for (final match in _numericPattern.allMatches(text)) {
      int hours = 0;
      int minutes;
      int seconds;
      if (match.group(3) != null) {
        hours = int.parse(match.group(1)!);
        minutes = int.parse(match.group(2)!);
        seconds = int.parse(match.group(3)!);
      } else {
        minutes = int.parse(match.group(1)!);
        seconds = int.parse(match.group(2)!);
      }
      if (seconds < 60 && minutes < 60) {
        results.add((hours * 3600 + minutes * 60 + seconds) * 1000);
      }
    }

    // Chinese: "两分三十秒"
    for (final match in _chinesePattern.allMatches(text)) {
      int totalSeconds = 0;
      final num1 = _parseChineseNum(match.group(1)!);
      final unit1 = match.group(2)!;
      switch (unit1) {
        case '小时' || '时':
          totalSeconds += num1 * 3600;
        case '分钟' || '分':
          totalSeconds += num1 * 60;
        case '秒':
          totalSeconds += num1;
      }
      if (match.group(3) != null && match.group(4) != null) {
        final num2 = _parseChineseNum(match.group(3)!);
        final unit2 = match.group(4)!;
        switch (unit2) {
          case '分钟' || '分':
            totalSeconds += num2 * 60;
          case '秒':
            totalSeconds += num2;
        }
      }
      if (match.group(5) != null && match.group(6) != null) {
        totalSeconds += _parseChineseNum(match.group(5)!);
      }
      if (totalSeconds > 0) {
        results.add(totalSeconds * 1000);
      }
    }

    // Arrow: "向右3下" = 3 * 5s
    for (final match in _arrowPattern.allMatches(text)) {
      final count = int.parse(match.group(1)!);
      results.add(count * 5 * 1000);
    }

    return results;
  }
}
