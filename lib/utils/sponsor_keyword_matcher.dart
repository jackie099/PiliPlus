import 'package:PiliPlus/utils/storage_pref.dart';

class SponsorKeywordMatcher {
  SponsorKeywordMatcher._();

  static final _defaultPattern = RegExp(
    r'(广告|赞助|推广|恰饭|品牌合作|商务合作|商业推广|付费推广|sponsored)',
    caseSensitive: false,
  );

  static RegExp? _customPattern;
  static String? _cachedKeywords;

  static RegExp get _pattern {
    final keywords = Pref.blockDynSponsorKeywords;
    if (keywords.isNotEmpty) {
      if (keywords != _cachedKeywords) {
        _cachedKeywords = keywords;
        try {
          _customPattern = RegExp(keywords, caseSensitive: false);
        } catch (_) {
          _customPattern = null;
        }
      }
      return _customPattern ?? _defaultPattern;
    }
    return _defaultPattern;
  }

  /// Check if a dynamic item is likely sponsored content
  /// [text] is the dynamic content text
  /// [hasGoodsCard] indicates whether the dynamic has a goods/product card
  static bool isSponsor({
    required String text,
    bool hasGoodsCard = false,
  }) {
    if (!Pref.enableDynSponsorDetection) return false;
    if (hasGoodsCard) return true;
    return _pattern.hasMatch(text);
  }
}
