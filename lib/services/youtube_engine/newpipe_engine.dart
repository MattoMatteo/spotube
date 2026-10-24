import 'package:flutter_new_pipe_extractor/flutter_new_pipe_extractor.dart'
    hide Engagement;
import 'package:spotube/services/youtube_engine/youtube_engine.dart';
import 'package:spotube/utils/platform.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:http_parser/http_parser.dart';

class NewPipeEngine implements YouTubeEngine {
  static bool get isAvailableForPlatform => kIsAndroid || kIsDesktop;

  AudioOnlyStreamInfo _parseAudioStream(AudioStream stream, String videoId) {
    return AudioOnlyStreamInfo(
      VideoId(videoId),
      stream.itag,
      Uri.parse(stream.content),
      StreamContainer.parse(stream.mediaFormat!.mimeType.split("/").last),
      FileSize.unknown,
      Bitrate(stream.bitrate),
      stream.codec,
      switch (stream.bitrate) {
        > 130 * 1024 => "high",
        > 64 * 1024 => "medium",
        _ => "low",
      },
      [],
      MediaType.parse(stream.mediaFormat!.mimeType),
      null,
    );
  }

  AudioOnlyStreamInfo _parseVideoStream(VideoStream stream, String videoId) {
    return AudioOnlyStreamInfo(
      VideoId(videoId),
      stream.itag,
      Uri.parse(stream.content),
      StreamContainer.parse(stream.mediaFormat!.mimeType.split("/").last),
      FileSize.unknown,
      Bitrate(stream.bitrate),
      stream.codec,
      switch (stream.bitrate) {
        > 130 * 1024 => "high",
        > 64 * 1024 => "medium",
        _ => "low",
      },
      [],
      MediaType.parse(stream.mediaFormat!.mimeType),
      null,
    );
  }

  Video _parseVideo(VideoInfo info) {
    return Video(
      VideoId(info.id),
      info.name,
      info.uploaderName,
      _channelIdOf(info.uploaderUrl),
      // uploadDate/description may be missing in reduced YouTube responses
      info.uploadDate?.offsetDateTime,
      info.uploadDate?.offsetDateTime.toString(),
      info.uploadDate?.offsetDateTime,
      info.description?.content ?? "",
      Duration(seconds: info.duration),
      ThumbnailSet(info.id),
      info.tags,
      Engagement(
        info.viewCount,
        info.likeCount,
        info.dislikeCount,
      ),
      !info.streamType.name.toLowerCase().contains("live"),
    );
  }

  // Placeholder for results without a channel: YouTube Music songs by artists
  // without a YouTube channel have no uploaderUrl, and ChannelId("") throws.
  // The channel is only informative, it isn't used for playback.
  static final _unknownChannelId = ChannelId("UC${"0" * 22}");

  static ChannelId _channelIdOf(String uploaderUrl) =>
      ChannelId.parseChannelId(uploaderUrl) != null
          ? ChannelId(uploaderUrl)
          : _unknownChannelId;

  Video _parseVideoResult(VideoSearchResultItem info) {
    final id = Uri.parse(info.url).queryParameters["v"]!;
    return Video(
      VideoId(id),
      info.name,
      info.uploaderName,
      _channelIdOf(info.uploaderUrl),
      info.uploadDate?.offsetDateTime,
      info.uploadDate?.offsetDateTime.toString(),
      info.uploadDate?.offsetDateTime,
      info.shortDescription ?? "",
      Duration(seconds: info.duration),
      ThumbnailSet(id),
      [],
      Engagement(info.viewCount, null, null),
      !info.streamType.name.toLowerCase().contains("live"),
    );
  }

  @override
  Future<StreamManifest> getStreamManifest(String videoId) async {
    final video = await NewPipeExtractor.getVideoInfo(videoId);

    final streams =
        video.audioStreams.map((stream) => _parseAudioStream(stream, videoId));

    if (streams.isEmpty) {
      final videoStreams = video.videoStreams
          .map((stream) => _parseVideoStream(stream, videoId));
      if (videoStreams.isNotEmpty) {
        return StreamManifest(videoStreams);
      }
    }

    return StreamManifest(streams);
  }

  @override
  Future<Video> getVideo(String videoId) async {
    final video = await NewPipeExtractor.getVideoInfo(videoId);

    return _parseVideo(video);
  }

  @override
  Future<(Video, StreamManifest)> getVideoWithStreamInfo(String videoId) async {
    final video = await NewPipeExtractor.getVideoInfo(videoId);

    final streams =
        video.audioStreams.map((stream) => _parseAudioStream(stream, videoId));

    if (streams.isEmpty) {
      final videoStreams = video.videoStreams
          .map((stream) => _parseVideoStream(stream, videoId));
      if (videoStreams.isNotEmpty) {
        return (_parseVideo(video), StreamManifest(videoStreams));
      }
    }

    return (_parseVideo(video), StreamManifest(streams));
  }

  /// Prefers YouTube Music songs: they are the official album tracks (right
  /// length, no music video intros or third-party uploads) and aren't
  /// filtered like YouTube's anonymous video search, which e.g. returns
  /// nothing for queries containing "X-Rated". On 60 real tracks the first
  /// song matched Spotify's duration (within 10s) 59 times, the first video
  /// 47. Falls back to videos when the first song doesn't match the query.
  @override
  Future<List<Video>> searchVideos(String query) async {
    final songs = await _search(query, SearchContentFilters.musicSongs);
    if (songs.isNotEmpty && _songMatchesQuery(songs.first, query)) {
      return songs;
    }

    final videos = await _search(query, SearchContentFilters.videos);
    return videos.isNotEmpty ? videos : songs;
  }

  Future<List<Video>> _search(
    String query,
    SearchContentFilters contentFilter,
  ) async {
    final results = await NewPipeExtractor.search(
      query,
      contentFilters: [contentFilter],
    );

    return results
        .whereType<VideoSearchResultItem>()
        .map((e) => _parseVideoResult(e))
        .toList();
  }

  static final _isrcRegex = RegExp(r'^[A-Z]{2}[A-Z0-9]{3}\d{7}$');

  /// The audio source plugin searches either a track's ISRC (an exact lookup)
  /// or "<title> <artists>". For the latter, YouTube Music still returns
  /// songs when the track isn't there, so require the song's title and
  /// artist to be in the query.
  static bool _songMatchesQuery(Video song, String query) {
    if (_isrcRegex.hasMatch(query.trim())) return true;

    String normalize(String text) => text
        .toLowerCase()
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ') // (feat. x), [Remastered]
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .trim();

    final normalizedQuery = normalize(query);
    final title = normalize(song.title);
    final artist = normalize(song.author).replaceFirst(RegExp(r'^the '), '');

    return title.isNotEmpty &&
        artist.isNotEmpty &&
        normalizedQuery.contains(title) &&
        normalizedQuery.contains(artist);
  }

  @override
  void dispose() {}
}
