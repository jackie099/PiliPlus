class _CacheEntry<T> {
  final T data;
  final DateTime expiry;

  _CacheEntry(this.data, this.expiry);

  bool get isExpired => DateTime.now().isAfter(expiry);
}

class SponsorBlockCache<T> {
  final Duration ttl;
  final int maxEntries;
  final _cache = <String, _CacheEntry<T>>{};

  SponsorBlockCache({
    this.ttl = const Duration(hours: 1),
    this.maxEntries = 1000,
  });

  T? get(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _cache.remove(key);
      return null;
    }
    return entry.data;
  }

  void put(String key, T data) {
    if (_cache.length >= maxEntries) {
      // Remove oldest expired entries first, then oldest by insertion
      _cache.removeWhere((_, v) => v.isExpired);
      if (_cache.length >= maxEntries) {
        _cache.remove(_cache.keys.first);
      }
    }
    _cache[key] = _CacheEntry(data, DateTime.now().add(ttl));
  }

  void invalidate(String key) => _cache.remove(key);

  void clear() => _cache.clear();
}
