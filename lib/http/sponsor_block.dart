import 'dart:convert';

import 'package:PiliPlus/build_config.dart';
import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/sponsor_block_api.dart';
import 'package:PiliPlus/http/sponsor_block_cache.dart';
import 'package:PiliPlus/models/common/sponsor_block/post_segment_model.dart';
import 'package:PiliPlus/models/common/sponsor_block/segment_type.dart';
import 'package:PiliPlus/models_new/sponsor_block/segment_item.dart';
import 'package:PiliPlus/models_new/sponsor_block/user_info.dart';
import 'package:PiliPlus/models_new/sponsor_block/video_label.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

/// https://github.com/hanydd/BilibiliSponsorBlock/wiki/API
abstract final class SponsorBlock {
  static String get blockServer => Pref.blockServer;
  static final options = Options(
    followRedirects: true,
    // https://github.com/hanydd/BilibiliSponsorBlock/wiki/API#1-%E5%85%AC%E7%94%A8%E5%8F%82%E6%95%B0
    headers: kDebugMode
        ? null
        : {
            'origin': Constants.appName,
            'x-ext-version': BuildConfig.versionName,
          },
    validateStatus: (status) => true,
  );

  // Caches
  static final _segmentCache = SponsorBlockCache<List<SegmentItemModel>>(
    maxEntries: 1000,
  );
  static final _labelCache = SponsorBlockCache<List<VideoLabelModel>>(
    maxEntries: 5000,
  );

  /// SHA-256 hash prefix (first 4 hex chars) for privacy
  static String _hashPrefix(String bvid) {
    final bytes = utf8.encode(bvid);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 4);
  }

  static void clearCache() {
    _segmentCache.clear();
    _labelCache.clear();
  }

  static Error getErrMsg(Response res) {
    String statusMessage = switch (res.statusCode) {
      200 => '意料之外的响应',
      400 => '参数错误',
      403 => '被自动审核机制拒绝',
      404 => '未找到数据',
      409 => '重复提交',
      429 => '提交太快（触发速率控制）',
      500 => '服务器无法获取信息',
      -1 => res.data['message'].toString(), // DioException
      _ => res.statusMessage ?? res.statusCode.toString(),
    };
    if (res.statusCode != null && res.statusCode != -1) {
      final data = res.data;
      if (res.statusCode == 200 ||
          (data is String && data.isNotEmpty && data.length < 200)) {
        statusMessage = '$statusMessage：$data';
      }
    }
    return Error(statusMessage, code: res.statusCode);
  }

  static String _api(String url) => '$blockServer/api/$url';

  /// Uses hash-prefix privacy pattern: GET /api/skipSegments/{hash4}
  /// Filters results locally by bvid
  static Future<LoadingState<List<SegmentItemModel>>> getSkipSegments({
    required String bvid,
    required int cid,
  }) async {
    final cacheKey = '$bvid:$cid';
    final cached = _segmentCache.get(cacheKey);
    if (cached != null) {
      return Success(cached);
    }

    final hashPrefix = _hashPrefix(bvid);
    final res = await Request().get(
      _api('${SponsorBlockApi.skipSegments}/$hashPrefix'),
      queryParameters: {
        'cid': cid,
      },
      options: options,
    );

    if (res.statusCode == 200) {
      if (res.data case final List list) {
        // Hash-prefix response: [{videoID: "...", segments: [...]}, ...]
        final List<SegmentItemModel> segments = [];
        for (final item in list) {
          if (item case final Map<String, dynamic> map) {
            final videoID = map['videoID'];
            if (videoID == bvid) {
              if (map['segments'] case final List segList) {
                segments.addAll(
                  segList.map((i) => SegmentItemModel.fromJson(i)),
                );
              }
            }
          }
        }
        _segmentCache.put(cacheKey, segments);
        return Success(segments);
      }
    }
    return getErrMsg(res);
  }

  static Future<LoadingState<void>> voteOnSponsorTime({
    required String uuid,
    int? type,
    SegmentType? category,
  }) async {
    assert((type == null) == (category == null));
    final res = await Request().post(
      _api(SponsorBlockApi.voteOnSponsorTime),
      queryParameters: {
        'UUID': uuid,
        'type': ?type,
        'category': ?category?.name,
        'userID': Pref.blockUserID,
      },
      options: options,
    );
    return res.statusCode == 200 ? const Success(null) : getErrMsg(res);
  }

  static Future<LoadingState<void>> viewedVideoSponsorTime(String uuid) async {
    final res = await Request().post(
      _api(SponsorBlockApi.viewedVideoSponsorTime),
      data: {'UUID': uuid},
      options: options,
    );
    return res.statusCode == 200 ? const Success(null) : getErrMsg(res);
  }

  static Future<LoadingState<void>> uptimeStatus() async {
    final res = await Request().get(
      _api(SponsorBlockApi.uptimeStatus),
      options: options,
    );
    if (res.statusCode == 200 &&
        res.data is String &&
        Utils.isStringNumeric(res.data)) {
      return const Success(null);
    }
    return getErrMsg(res);
  }

  static Future<LoadingState<UserInfo>> userInfo(
    List<String> query, {
    String? userId,
  }) async {
    final res = await Request().get(
      _api(SponsorBlockApi.userInfo),
      queryParameters: {
        'userID': userId ?? Pref.blockUserID,
        'values': jsonEncode(query),
      },
      options: options,
    );
    if (res.statusCode == 200) {
      return Success(UserInfo.fromJson(res.data));
    }
    return getErrMsg(res);
  }

  static Future<LoadingState<List<SegmentItemModel>>> postSkipSegments({
    required String bvid,
    required int cid,
    required double videoDuration,
    required List<PostSegmentModel> segments,
  }) async {
    final res = await Request().post(
      _api(SponsorBlockApi.skipSegments),
      data: {
        'videoID': bvid,
        'cid': cid.toString(),
        'userID': Pref.blockUserID,
        'userAgent': kDebugMode
            ? Constants.userAgent
            : '${Constants.appName}/${BuildConfig.versionName}',
        'videoDuration': videoDuration,
        'segments': segments
            .map(
              (item) => {
                'segment': [item.segment.first, item.segment.second],
                'category': item.category.name,
                'actionType': item.actionType.name,
              },
            )
            .toList(),
      },
      options: options,
    );

    if (res.statusCode == 200) {
      if (res.data case final List list) {
        // Invalidate cache after posting
        _segmentCache.invalidate('$bvid:$cid');
        return Success(list.map((i) => SegmentItemModel.fromJson(i)).toList());
      }
    }
    return getErrMsg(res);
  }

  /// Uses hash-prefix privacy pattern: GET /api/portVideo/{hash4}
  static Future<LoadingState<Map<String, dynamic>>> getPortVideo({
    required String bvid,
    required int cid,
  }) async {
    final hashPrefix = _hashPrefix(bvid);
    final res = await Request().get(
      _api('${SponsorBlockApi.portVideo}/$hashPrefix'),
      queryParameters: {
        'cid': cid.toString(),
      },
      options: options,
    );

    if (res.statusCode == 200) {
      if (res.data case final List list) {
        // Hash-prefix response: [{bvID: "...", ...}, ...]
        for (final item in list) {
          if (item case final Map<String, dynamic> map) {
            if (map['bvID'] == bvid) {
              return Success(map);
            }
          }
        }
      } else if (res.data case final Map<String, dynamic> data) {
        // Direct response format
        return Success(data);
      }
    }
    return getErrMsg(res);
  }

  static Future<LoadingState<String>> postPortVideo({
    required String bvid,
    required int cid,
    required String ytbId,
    required int videoDuration,
  }) async {
    final res = await Request().post(
      _api(SponsorBlockApi.portVideo),
      data: {
        'bvID': bvid,
        'cid': cid.toString(),
        'ytbID': ytbId,
        'userID': Pref.blockUserID,
        'biliDuration': videoDuration,
      },
      options: options,
    );

    if (res.statusCode == 200) {
      if (res.data case final Map<String, dynamic> data) {
        if (data['UUID'] case String uuid) {
          return Success(uuid);
        }
      }
    }
    return getErrMsg(res);
  }

  /// GET /api/videoLabels/{hash4} — hash-prefix privacy
  static Future<LoadingState<List<VideoLabelModel>>> getVideoLabels(
    String bvid,
  ) async {
    final cached = _labelCache.get(bvid);
    if (cached != null) {
      return Success(cached);
    }

    final hashPrefix = _hashPrefix(bvid);
    final res = await Request().get(
      _api('${SponsorBlockApi.videoLabels}/$hashPrefix'),
      options: options,
    );

    if (res.statusCode == 200) {
      if (res.data case final List list) {
        final List<VideoLabelModel> labels = [];
        for (final item in list) {
          if (item case final Map<String, dynamic> map) {
            if (map['videoID'] == bvid) {
              labels.add(VideoLabelModel.fromJson(map));
            }
          }
        }
        _labelCache.put(bvid, labels);
        return Success(labels);
      }
    }
    return getErrMsg(res);
  }

  /// GET /api/lockCategories/{hash4} — hash-prefix privacy
  static Future<LoadingState<List<String>>> getLockCategories(
    String bvid,
  ) async {
    final hashPrefix = _hashPrefix(bvid);
    final res = await Request().get(
      _api('${SponsorBlockApi.lockCategories}/$hashPrefix'),
      options: options,
    );

    if (res.statusCode == 200) {
      if (res.data case final List list) {
        for (final item in list) {
          if (item case final Map<String, dynamic> map) {
            if (map['videoID'] == bvid) {
              if (map['categories'] case final List cats) {
                return Success(cats.cast<String>());
              }
            }
          }
        }
      }
    }
    return getErrMsg(res);
  }

  /// GET /api/chapterNames
  static Future<LoadingState<List<String>>> getChapterNames() async {
    final res = await Request().get(
      _api(SponsorBlockApi.chapterNames),
      options: options,
    );

    if (res.statusCode == 200) {
      if (res.data case final List list) {
        return Success(list.cast<String>());
      }
    }
    return getErrMsg(res);
  }

  /// POST /api/setUsername
  static Future<LoadingState<Null>> setUsername(String username) async {
    final res = await Request().post(
      _api(SponsorBlockApi.setUsername),
      queryParameters: {
        'userID': Pref.blockUserID,
        'username': username,
      },
      options: options,
    );
    return res.statusCode == 200 ? const Success(null) : getErrMsg(res);
  }

  /// GET /api/getUsername
  static Future<LoadingState<String>> getUsername() async {
    final res = await Request().get(
      _api(SponsorBlockApi.getUsername),
      queryParameters: {
        'userID': Pref.blockUserID,
      },
      options: options,
    );

    if (res.statusCode == 200) {
      if (res.data case final Map<String, dynamic> data) {
        if (data['userName'] case String name) {
          return Success(name);
        }
      }
    }
    return getErrMsg(res);
  }

  /// POST /api/votePort
  static Future<LoadingState<Null>> votePort({
    required String uuid,
    required String bvid,
    required int type,
  }) async {
    final res = await Request().post(
      _api(SponsorBlockApi.votePort),
      queryParameters: {
        'UUID': uuid,
        'bvID': bvid,
        'userID': Pref.blockUserID,
        'type': type,
      },
      options: options,
    );
    return res.statusCode == 200 ? const Success(null) : getErrMsg(res);
  }

  /// POST /api/updatePortedSegments
  static Future<LoadingState<Null>> updatePortedSegments({
    required String videoID,
    required String uuid,
    required int cid,
  }) async {
    final res = await Request().post(
      _api(SponsorBlockApi.updatePortedSegments),
      queryParameters: {
        'videoID': videoID,
        'UUID': uuid,
        'cid': cid,
        'userID': Pref.blockUserID,
      },
      options: options,
    );
    return res.statusCode == 200 ? const Success(null) : getErrMsg(res);
  }

  /// POST /api/warnUser — acknowledge warning
  static Future<LoadingState<Null>> warnUser() async {
    final res = await Request().post(
      _api(SponsorBlockApi.warnUser),
      data: {
        'userID': Pref.blockUserID,
        'enabled': false,
      },
      options: options,
    );
    return res.statusCode == 200 ? const Success(null) : getErrMsg(res);
  }
}
