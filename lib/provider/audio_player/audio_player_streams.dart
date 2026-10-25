import 'dart:async';
import 'dart:math';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/provider/discord_provider.dart';
import 'package:spotube/provider/history/history.dart';
import 'package:spotube/provider/metadata_plugin/core/scrobble.dart';
import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/provider/server/sourced_track_provider.dart';
import 'package:spotube/provider/skip_segments/skip_segments.dart';
import 'package:spotube/provider/scrobbler/scrobbler.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/audio_services/audio_services.dart';
import 'package:spotube/services/logger/logger.dart';

class AudioPlayerStreamListeners {
  final Ref ref;
  late final AudioServices notificationService;
  AudioPlayerStreamListeners(this.ref) {
    AudioServices.create(ref, ref.read(audioPlayerProvider.notifier)).then(
      (value) => notificationService = value,
    );

    final subscriptions = [
      subscribeToPlaylist(),
      subscribeToSkipSponsor(),
      subscribeToScrobbleChanged(),
      subscribeToPosition(),
      subscribeToPlayerError(),
      ...subscribeToEndlessPlayback(),
    ];

    ref.onDispose(() {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
    });
  }

  ScrobblerNotifier get scrobbler => ref.read(scrobblerProvider.notifier);
  UserPreferences get preferences => ref.read(userPreferencesProvider);
  DiscordNotifier get discord => ref.read(discordProvider.notifier);
  AudioPlayerState get audioPlayerState => ref.read(audioPlayerProvider);
  PlaybackHistoryActions get history =>
      ref.read(playbackHistoryActionsProvider);

  StreamSubscription subscribeToPlaylist() {
    return audioPlayer.playlistStream.listen((mpvPlaylist) {
      try {
        if (audioPlayerState.activeTrack == null) return;
        notificationService.addTrack(audioPlayerState.activeTrack!);
        notificationService.setTracksQueue(
          audioPlayerState.tracks,
          audioPlayerState.currentIndex,
        );
        discord.updatePresence(audioPlayerState.activeTrack!);
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    });
  }

  StreamSubscription subscribeToSkipSponsor() {
    return audioPlayer.positionStream.listen((position) async {
      try {
        final currentSegments = await ref.read(segmentProvider.future);

        if (currentSegments?.segments.isNotEmpty != true ||
            position < const Duration(seconds: 3)) {
          return;
        }

        for (final segment in currentSegments!.segments) {
          final seconds = position.inSeconds;

          if (seconds < segment.start || seconds >= segment.end) continue;

          await audioPlayer.seek(Duration(seconds: segment.end + 1));
        }
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    });
  }

  StreamSubscription subscribeToScrobbleChanged() {
    String? lastScrobbled;
    return audioPlayer.positionStream.listen((position) async {
      try {
        final uid = audioPlayerState.activeTrack is SpotubeLocalTrackObject
            ? (audioPlayerState.activeTrack as SpotubeLocalTrackObject).path
            : audioPlayerState.activeTrack?.id;

        /// According to Listenbrainz and Last.fm, a scrobble should be sent
        /// after 4 minutes of listening or 50% of the track duration,
        /// whichever is less.
        final minimumListenTime = min(audioPlayer.duration.inSeconds ~/ 2, 240);

        if (audioPlayerState.activeTrack == null ||
            lastScrobbled == uid ||
            position.inSeconds < minimumListenTime ||
            audioPlayer.duration == Duration.zero ||
            position == Duration.zero) {
          return;
        }

        scrobbler.scrobble(audioPlayerState.activeTrack!);
        ref
            .read(metadataPluginScrobbleProvider.notifier)
            .scrobble(audioPlayerState.activeTrack!);
        lastScrobbled = uid;

        /// The [Track] from Playlist.getTracks doesn't contain artist images
        /// so we need to fetch them from the API
        var activeTrack = audioPlayerState.activeTrack!;
        if (activeTrack.artists.any((a) => a.images == null)) {
          final metadataPlugin = await ref.read(metadataPluginProvider.future);
          final artists = await Future.wait(
            activeTrack.artists
                .map((artist) => metadataPlugin!.artist.getArtist(artist.id)),
          );
          activeTrack = activeTrack.copyWith(
            artists: artists
                .map((e) => SpotubeSimpleArtistObject.fromJson(e.toJson()))
                .toList(),
          );
        }

        await history.addTrack(activeTrack);
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    });
  }

  StreamSubscription subscribeToPosition() {
    String lastTrack = ""; // used to prevent multiple calls to the same track
    return audioPlayer.positionStream.listen((event) async {
      final percentProgress =
          (event.inSeconds / max(audioPlayer.duration.inSeconds, 1)) * 100;
      try {
        if (percentProgress < 80 ||
            audioPlayerState.currentIndex == -1 ||
            audioPlayerState.currentIndex ==
                audioPlayerState.tracks.length - 1) {
          return;
        }
        final nextTrack = audioPlayerState.tracks
            .elementAtOrNull(audioPlayerState.currentIndex + 1);

        if (nextTrack == null ||
            lastTrack == nextTrack.id ||
            nextTrack is SpotubeLocalTrackObject) {
          return;
        }

        try {
          await ref.read(
            sourcedTrackProvider(nextTrack as SpotubeFullTrackObject).future,
          );
        } finally {
          lastTrack = nextTrack.id;
        }
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    });
  }

  StreamSubscription subscribeToPlayerError() {
    return audioPlayer.errorStream.listen((event) {});
  }

  /// Endless playback: when the queue is about to end, adds the radio of its
  /// last track. It lives here rather than in the UI so it also works when the
  /// app runs in the background or is started by Android Auto.
  ///
  /// Only while playing: the queue restored at startup is left alone, and the
  /// first track of a new queue gets loaded before the radio is appended
  List<StreamSubscription> subscribeToEndlessPlayback() {
    // Fetching a few tracks before the end leaves no gap on slow networks,
    // and a single track starts its radio right away
    const remainingTracks = 2;
    // Several events arrive for the same queue: one fetch at a time, and once
    // per seed track (also when its radio had nothing new to add)
    bool isFetching = false;
    String? lastSeedId;

    // When the app was just started, e.g. by Android Auto, the plugin may
    // still be refreshing its token and fail (or find nothing): with a single
    // track no other queue change would trigger another try, so retry here
    Future<List<SpotubeFullTrackObject>> fetchRadio(
      SpotubeFullTrackObject seed,
    ) async {
      for (var attempt = 1;; attempt++) {
        AppLogger.log.i(
          "Endless playback: fetching the radio of ${seed.name} "
          "(attempt $attempt)",
        );
        try {
          final metadataPlugin = await ref.read(metadataPluginProvider.future);
          final radio = await metadataPlugin?.track.radio(seed.id) ?? [];
          if (radio.isNotEmpty || attempt == 3) return radio;
        } catch (e) {
          if (attempt == 3) rethrow;
          AppLogger.log.w("Endless playback: radio failed: $e");
        }
        await Future.delayed(Duration(seconds: 5 * attempt));
      }
    }

    Future<void> fillQueue() async {
      try {
        final state = audioPlayerState;
        final seed = state.tracks.lastOrNull;
        if (!preferences.endlessPlayback ||
            !audioPlayer.isPlaying ||
            state.loopMode != PlaylistMode.none ||
            seed is! SpotubeFullTrackObject ||
            state.tracks.length - 1 - state.currentIndex > remainingTracks ||
            isFetching ||
            lastSeedId == seed.id) {
          return;
        }
        isFetching = true;
        lastSeedId = seed.id;

        final radio = await fetchRadio(seed);
        // The queue may have changed meanwhile
        if (radio.isEmpty ||
            audioPlayerState.tracks.lastOrNull?.id != seed.id) {
          return;
        }

        final queuedIds = audioPlayerState.tracks.map((t) => t.id).toSet();
        final newTracks =
            radio.where((track) => queuedIds.add(track.id)).toList();
        AppLogger.log.i(
          "Endless playback: adding ${newTracks.length} tracks from the radio "
          "of ${seed.name}",
        );
        await ref.read(audioPlayerProvider.notifier).addTracks(newTracks);
      } catch (e, stack) {
        // Let the next queue change try again
        lastSeedId = null;
        AppLogger.reportError(e, stack);
      } finally {
        isFetching = false;
      }
    }

    // The player reports every track it appends, so while tracks are added
    // the queue briefly looks almost over: wait for it to settle
    Timer? settle;
    void scheduleFill() {
      settle?.cancel();
      settle = Timer(const Duration(seconds: 2), fillQueue);
    }

    ref.onDispose(() => settle?.cancel());

    // Turning the setting on while the last track plays
    ref.listen(
      userPreferencesProvider.select((s) => s.endlessPlayback),
      (_, __) => scheduleFill(),
    );

    return [
      audioPlayer.playlistStream.listen((_) => scheduleFill()),
      audioPlayer.playingStream.listen((_) => scheduleFill()),
    ];
  }
}

final audioPlayerStreamListenersProvider =
    Provider<AudioPlayerStreamListeners>(AudioPlayerStreamListeners.new);
