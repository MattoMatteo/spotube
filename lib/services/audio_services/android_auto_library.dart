import 'dart:math';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:spotube/l10n/generated/app_localizations.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/history/history.dart';
import 'package:spotube/provider/history/recent.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/services/metadata/errors/exceptions.dart';
import 'package:spotube/services/metadata/metadata.dart';

/// Browsable media tree served to Android Auto (and any other MediaBrowser
/// client) through [MobileAudioService].
///
/// Media ids are paths whose segments are URI-encoded:
/// - `browse`, `library`, `recent`: root tabs
/// - `library/playlists|albums|artists`
/// - `playlist/<id>`, `album/<id>`: tracks of a collection, playing
///   `playlist/<id>/<trackId>` starts the whole collection from that track and
///   `playlist/<id>/_shuffle` shuffles it
/// - `artist/<id>`: top tracks and albums of an artist
/// - `artist/<id>/top/<trackId>`, `artist/<id>/top/_shuffle`
/// - `search/<query>/<trackId>`: a track found by [search]
class AndroidAutoLibrary {
  static const browseId = 'browse';
  static const libraryId = 'library';
  static const recentId = 'recent';
  static const likedTracksId = 'user-liked-tracks';

  static const _shuffle = '_shuffle';
  // Any id that isn't a track of the collection plays it from the start
  static const _first = '_first';

  // Car screens can't scroll through huge lists, and big results risk
  // exceeding the binder transaction limit
  static const _maxItems = 300;
  static const _cacheDuration = Duration(minutes: 5);

  static const _contentStyleSupported =
      'android.media.browse.CONTENT_STYLE_SUPPORTED';
  static const _contentStyleBrowsable =
      'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT';
  static const _contentStylePlayable =
      'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT';
  static const _contentStyleGroupTitle =
      'android.media.browse.CONTENT_STYLE_GROUP_TITLE_HINT';
  static const _styleList = 1;
  static const _styleGrid = 2;

  /// Extras of the browsable root: search enabled, collections as grid, tracks
  /// as list
  static const rootExtras = <String, dynamic>{
    'android.media.browse.SEARCH_SUPPORTED': true,
    _contentStyleSupported: true,
    _contentStyleBrowsable: _styleGrid,
    _contentStylePlayable: _styleList,
  };

  final Ref ref;

  AndroidAutoLibrary(this.ref);

  String? _packageName;
  final _tracksCache = <String, (DateTime, List<SpotubeFullTrackObject>)>{};
  final _searchCache = <String, (DateTime, SpotubeSearchResponseObject)>{};
  final _playlists = <String, SpotubeSimplePlaylistObject>{};
  final _albums = <String, SpotubeSimpleAlbumObject>{};

  AppLocalizations get _l10n {
    final locale = ref.read(userPreferencesProvider).locale;
    try {
      return lookupAppLocalizations(
        locale.languageCode == 'system'
            ? PlatformDispatcher.instance.locale
            : locale,
      );
    } catch (_) {
      return lookupAppLocalizations(const Locale('en'));
    }
  }

  String get queueTitle => _l10n.queue;

  Future<MetadataPlugin> get _plugin async {
    final plugin = await ref.read(metadataPluginProvider.future);
    if (plugin == null) {
      throw MetadataPluginException.noDefaultMetadataPlugin();
    }
    return plugin;
  }

  static String _path(List<String> segments) =>
      segments.map(Uri.encodeComponent).join('/');

  static List<String> _segments(String mediaId) =>
      mediaId.split('/').map(Uri.decodeComponent).toList();

  /// Never throws: Android doesn't let a MediaBrowserService send an error, so
  /// failures become a single "something went wrong" item
  Future<List<MediaItem>> getChildren(String parentMediaId) async {
    try {
      _packageName ??= (await PackageInfo.fromPlatform()).packageName;
      return await _children(_segments(parentMediaId));
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      return [
        MediaItem(
          id: _path(['error', parentMediaId]),
          title: _l10n.something_went_wrong,
          artUri: _icon('error'),
          playable: false,
        ),
      ];
    }
  }

  Future<List<MediaItem>> _children(List<String> segments) async {
    switch (segments) {
      case [AudioService.browsableRootId]:
        return _root();
      case [recentId]:
        return await _recent();
      case [browseId]:
        return await _browse();
      case [libraryId]:
        return _library();
      case [libraryId, 'playlists']:
        return await _savedPlaylists();
      case [libraryId, 'albums']:
        return await _savedAlbums();
      case [libraryId, 'artists']:
        return await _savedArtists();
      case ['playlist', final id]:
        return _collectionTracks(segments, await _playlistTracks(id));
      case ['album', final id]:
        return _collectionTracks(segments, await _albumTracks(id));
      case ['artist', final id]:
        return _artist(id);
      case ['artist', final id, 'top']:
        return _collectionTracks(segments, await _artistTopTracks(id));
      case ['artist', final id, 'albums']:
        return await _artistAlbums(id);
      default:
        return [];
    }
  }

  /// Plays the item with [mediaId]. Returns false when the id isn't playable
  Future<bool> play(String mediaId) async {
    final segments = _segments(mediaId);
    if (segments.length < 2) return false;

    final trackId = segments.last;
    final parent = segments.sublist(0, segments.length - 1);

    switch (parent) {
      case ['playlist', final id]:
        await _playCollection(trackId, await _playlistTracks(id));
        await _player.addCollection(id);
        final playlist = _playlists[id];
        if (playlist != null) {
          await ref.read(playbackHistoryActionsProvider).addPlaylists(
            [playlist],
          );
        }
        return true;
      case ['album', final id]:
        await _playCollection(trackId, await _albumTracks(id));
        await _player.addCollection(id);
        final album = _albums[id];
        if (album != null) {
          await ref.read(playbackHistoryActionsProvider).addAlbums([album]);
        }
        return true;
      case ['artist', final id, 'top']:
        await _playCollection(trackId, await _artistTopTracks(id));
        return true;
      case ['search', final query]:
        // Like the app's search: only the chosen track
        final results = await _searchResults(query);
        final track = results.tracks.firstWhereOrNull((t) => t.id == trackId);
        if (track == null) return false;
        await _player.load([track], autoPlay: true);
        return true;
      default:
        return false;
    }
  }

  /// Search results grouped by type. Never throws, like [getChildren]
  Future<List<MediaItem>> search(String query) async {
    try {
      _packageName ??= (await PackageInfo.fromPlatform()).packageName;
      final results = await _searchResults(query);
      final l10n = _l10n;

      MediaItem grouped(MediaItem item, String group) => item.copyWith(
            extras: {...?item.extras, _contentStyleGroupTitle: group},
          );

      return [
        for (final track in results.tracks)
          grouped(_trackItem(['search', query], track), l10n.songs),
        for (final item in [
          ...results.artists,
          ...results.albums,
          ...results.playlists,
        ])
          if (_collectionItem(item) case final mediaItem?)
            grouped(
                mediaItem,
                switch (item) {
                  SpotubeFullArtistObject() => l10n.artists,
                  SpotubeSimpleAlbumObject() => l10n.albums,
                  _ => l10n.playlists,
                }),
      ];
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      return [];
    }
  }

  /// Voice requests like "play <query> on Spotube". [extras] may tell whether
  /// the user asked for an artist, an album or a playlist
  Future<void> playFromSearch(
    String query,
    Map<String, dynamic>? extras,
  ) async {
    if (query.trim().isEmpty) {
      await play(_path(['playlist', likedTracksId, _shuffle]));
      return;
    }

    final results = await _searchResults(query);
    final focus = extras?['android.intent.extra.focus'] as String?;

    final String? collection;
    switch (focus) {
      case 'vnd.android.cursor.item/artist' when results.artists.isNotEmpty:
        collection = _path(['artist', results.artists.first.id, 'top', _first]);
      case 'vnd.android.cursor.item/album' when results.albums.isNotEmpty:
        // Remembered for the history
        _collectionItem(results.albums.first);
        collection = _path(['album', results.albums.first.id, _first]);
      case 'vnd.android.cursor.item/playlist' when results.playlists.isNotEmpty:
        _collectionItem(results.playlists.first);
        collection = _path(['playlist', results.playlists.first.id, _first]);
      default:
        collection = null;
    }

    if (collection != null) {
      await play(collection);
    } else if (results.tracks.isNotEmpty) {
      await play(_path(['search', query, results.tracks.first.id]));
    }
  }

  Future<SpotubeSearchResponseObject> _searchResults(String query) async {
    final cached = _searchCache[query];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < _cacheDuration) {
      return cached.$2;
    }
    final results = await _retry(() async => (await _plugin).search.all(query));
    _searchCache[query] = (DateTime.now(), results);
    return results;
  }

  AudioPlayerNotifier get _player => ref.read(audioPlayerProvider.notifier);

  Future<void> _playCollection(
    String trackId,
    List<SpotubeFullTrackObject> tracks,
  ) async {
    if (tracks.isEmpty) return;

    final shuffle = trackId == _shuffle;
    final index = shuffle
        ? Random().nextInt(tracks.length)
        : max(tracks.indexWhere((track) => track.id == trackId), 0);

    await _player.load(tracks, initialIndex: index, autoPlay: true);
    await audioPlayer.setShuffle(shuffle);
  }

  // Tree levels

  List<MediaItem> _root() {
    final l10n = _l10n;
    return [
      _folder(browseId, l10n.browse, artUri: _icon('browse')),
      _folder(libraryId, l10n.library, artUri: _icon('library')),
      _folder(recentId, l10n.recently_played, artUri: _icon('recent')),
    ];
  }

  Future<List<MediaItem>> _browse() async {
    final sections = await _retry(
      () async => (await _plugin).browse.sections(limit: 20),
    );

    return [
      for (final section in sections.items)
        for (final item in section.items)
          if (_collectionItem(item) case final mediaItem?)
            mediaItem.copyWith(
              extras: {
                ...?mediaItem.extras,
                _contentStyleGroupTitle: section.title,
              },
            ),
    ].take(_maxItems).toList();
  }

  List<MediaItem> _library() {
    final l10n = _l10n;
    return [
      _folder(
        _path(['playlist', likedTracksId]),
        l10n.liked_tracks,
        artUri: _icon('liked'),
        style: _styleList,
      ),
      _folder(
        _path([libraryId, 'playlists']),
        l10n.playlists,
        artUri: _icon('playlists'),
      ),
      _folder(
        _path([libraryId, 'albums']),
        l10n.albums,
        artUri: _icon('albums'),
      ),
      _folder(
        _path([libraryId, 'artists']),
        l10n.artists,
        artUri: _icon('artists'),
      ),
    ];
  }

  Future<List<MediaItem>> _recent() async {
    final history = await ref.read(recentlyPlayedItems.future);
    return [
      for (final entry in history)
        if (_collectionItem(entry.playlist ?? entry.album) case final item?)
          item,
    ];
  }

  Future<List<MediaItem>> _savedPlaylists() async {
    final playlists = await _fetchAll(
      (offset, limit) async =>
          (await _plugin).user.savedPlaylists(offset: offset, limit: limit),
    );
    return playlists.map(_collectionItem).nonNulls.toList();
  }

  Future<List<MediaItem>> _savedAlbums() async {
    final albums = await _fetchAll(
      (offset, limit) async =>
          (await _plugin).user.savedAlbums(offset: offset, limit: limit),
    );
    return albums.map(_collectionItem).nonNulls.toList();
  }

  Future<List<MediaItem>> _savedArtists() async {
    final artists = await _fetchAll(
      (offset, limit) async =>
          (await _plugin).user.savedArtists(offset: offset, limit: limit),
    );
    return artists.map(_collectionItem).nonNulls.toList();
  }

  List<MediaItem> _artist(String id) {
    final l10n = _l10n;
    return [
      _folder(
        _path(['artist', id, 'top']),
        l10n.top_tracks,
        artUri: _icon('top_tracks'),
        style: _styleList,
      ),
      _folder(
        _path(['artist', id, 'albums']),
        l10n.albums,
        artUri: _icon('albums'),
      ),
    ];
  }

  Future<List<MediaItem>> _artistAlbums(String id) async {
    final albums = await _fetchAll(
      (offset, limit) async =>
          (await _plugin).artist.albums(id, offset: offset, limit: limit),
    );
    return albums.map(_collectionItem).nonNulls.toList();
  }

  List<MediaItem> _collectionTracks(
    List<String> parent,
    List<SpotubeFullTrackObject> tracks,
  ) {
    if (tracks.isEmpty) return [];
    return [
      MediaItem(
        id: _path([...parent, _shuffle]),
        title: _l10n.shuffle,
        artUri: _icon('shuffle'),
        playable: true,
      ),
      for (final track in tracks.take(_maxItems)) _trackItem(parent, track),
    ];
  }

  // Data, cached for a while so that playing right after browsing doesn't
  // fetch everything again

  Future<List<SpotubeFullTrackObject>> _cachedTracks(
    String key,
    Future<List<SpotubeFullTrackObject>> Function() fetch,
  ) async {
    final cached = _tracksCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < _cacheDuration) {
      return cached.$2;
    }
    final tracks = await fetch();
    _tracksCache[key] = (DateTime.now(), tracks);
    return tracks;
  }

  Future<List<SpotubeFullTrackObject>> _playlistTracks(String id) {
    return _cachedTracks(
      'playlist/$id',
      () => _fetchAll(
        (offset, limit) async => id == likedTracksId
            ? (await _plugin).user.savedTracks(offset: offset, limit: limit)
            : (await _plugin).playlist.tracks(
                  id,
                  offset: offset,
                  limit: limit,
                ),
        maxItems: 2000,
      ),
    );
  }

  Future<List<SpotubeFullTrackObject>> _albumTracks(String id) {
    return _cachedTracks(
      'album/$id',
      () => _fetchAll(
        (offset, limit) async =>
            (await _plugin).album.tracks(id, offset: offset, limit: limit),
        maxItems: 2000,
      ),
    );
  }

  Future<List<SpotubeFullTrackObject>> _artistTopTracks(String id) {
    return _cachedTracks(
      'artist/$id/top',
      () async => (await _retry(
        () async => (await _plugin).artist.topTracks(id, limit: 20),
      ))
          .items,
    );
  }

  /// Android Auto can start the app and browse right away, while the plugin is
  /// still refreshing an expired token: those first requests fail with 401
  Future<T> _retry<T>(Future<T> Function() fetch) async {
    for (var attempt = 1;; attempt++) {
      try {
        return await fetch();
      } catch (e) {
        if (attempt == 3) rethrow;
        await Future.delayed(Duration(seconds: 2 * attempt));
      }
    }
  }

  Future<List<T>> _fetchAll<T>(
    Future<SpotubePaginationResponseObject<T>> Function(int offset, int limit)
        fetch, {
    int maxItems = _maxItems,
  }) async {
    final items = <T>[];
    int? offset = 0;
    while (offset != null && items.length < maxItems) {
      final page = await _retry(() => fetch(offset!, 50));
      items.addAll(page.items);
      offset = page.hasMore && page.items.isNotEmpty ? page.nextOffset : null;
    }
    return items;
  }

  // Items

  /// Also remembers playlists and albums, to add them to the history once
  /// played
  MediaItem? _collectionItem(Object? item) {
    switch (item) {
      case SpotubeSimplePlaylistObject():
        _playlists[item.id] = item;
        return _folder(
          _path(['playlist', item.id]),
          item.name,
          subtitle: item.owner.name,
          artUri: _artUri(item.images),
          style: _styleList,
        );
      case SpotubeSimpleAlbumObject():
        _albums[item.id] = item;
        return _folder(
          _path(['album', item.id]),
          item.name,
          subtitle: item.artists.asString(),
          artUri: _artUri(item.images),
          style: _styleList,
        );
      case SpotubeFullArtistObject():
        return _folder(
          _path(['artist', item.id]),
          item.name,
          artUri: _artUri(item.images),
        );
      default:
        return null;
    }
  }

  /// A track that, when played, starts [parent] from it
  MediaItem _trackItem(List<String> parent, SpotubeFullTrackObject track) {
    return MediaItem(
      id: _path([...parent, track.id]),
      title: track.name,
      artist: track.artists.asString(),
      album: track.album.name,
      duration: Duration(milliseconds: track.durationMs),
      artUri: _artUri(track.album.images),
      playable: true,
    );
  }

  /// A browsable item. [style] is how its children are shown
  MediaItem _folder(
    String id,
    String title, {
    String? subtitle,
    Uri? artUri,
    int style = _styleGrid,
  }) {
    return MediaItem(
      id: id,
      title: title,
      artist: subtitle,
      displaySubtitle: subtitle,
      artUri: artUri,
      playable: false,
      extras: {
        _contentStyleBrowsable: style,
        _contentStylePlayable: style,
      },
    );
  }

  /// One of the ic_auto_* drawables, which the car loads from this package
  Uri _icon(String name) {
    return Uri.parse(
      'android.resource://$_packageName/drawable/ic_auto_$name',
    );
  }

  /// Only remote images: the bundled placeholders aren't reachable by the car
  Uri? _artUri(List<SpotubeImageObject>? images) {
    if (images == null || images.isEmpty) return null;
    final url = images.from200PxTo300PxOrSmallestImage();
    return url.startsWith('http') ? Uri.parse(url) : null;
  }
}
