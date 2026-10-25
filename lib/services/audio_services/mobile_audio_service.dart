import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:collection/collection.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/audio_player/state.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:spotube/services/audio_player/playback_state.dart';
import 'package:spotube/services/audio_services/android_auto_library.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/platform.dart';

extension SpotubeTrackObjectToMediaItem on SpotubeTrackObject {
  MediaItem toMediaItem() {
    return MediaItem(
      id: id,
      album: album.name,
      title: name,
      artist: artists.asString(),
      duration: Duration(milliseconds: durationMs),
      artUri: album.images.asUri(placeholder: ImagePlaceholder.albumArt),
      playable: true,
    );
  }
}

class MobileAudioService extends BaseAudioHandler {
  AudioSession? session;
  final AudioPlayerNotifier audioPlayerNotifier;
  final AndroidAutoLibrary library;

  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  AudioPlayerState get playlist => audioPlayerNotifier.state;

  MobileAudioService(this.audioPlayerNotifier, this.library) {
    AudioSession.instance.then((s) {
      session = s;
      session?.configure(const AudioSessionConfiguration.music());

      bool wasPausedByBeginEvent = false;

      s.interruptionEventStream.listen((event) async {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              await audioPlayer.setVolume(0.5);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              {
                wasPausedByBeginEvent = audioPlayer.isPlaying;
                await audioPlayer.pause();
                break;
              }
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              await audioPlayer.setVolume(1.0);
              break;
            case AudioInterruptionType.pause when wasPausedByBeginEvent:
            case AudioInterruptionType.unknown when wasPausedByBeginEvent:
              await audioPlayer.resume();
              wasPausedByBeginEvent = false;
              break;
            default:
              break;
          }
        }
      });

      s.becomingNoisyEventStream.listen((_) {
        audioPlayer.pause();
      });
    });
    audioPlayer.playerStateStream.listen((state) async {
      if (state == AudioPlaybackState.playing) {
        await session?.setActive(true);
      }
      playbackState.add(await _transformEvent());
    });

    audioPlayer.currentIndexChangedStream.listen((index) async {
      playbackState.add(await _transformEvent());
    });

    // The position isn't broadcast on every tick: clients extrapolate it from
    // the last state, and every new state made Android Auto scroll its queue
    // view back to the active track. Only jumps (seeks, stalls) need a state
    audioPlayer.positionStream.listen((position) async {
      final expected = playbackState.value.position;
      if ((position - expected).abs() > const Duration(seconds: 1)) {
        playbackState.add(await _transformEvent());
      }
    });
  }

  void addItem(MediaItem item) {
    session?.setActive(true);
    mediaItem.add(item);
  }

  @override
  Future<void> play() => audioPlayer.resume();

  @override
  Future<void> pause() => audioPlayer.pause();

  @override
  Future<void> seek(Duration position) => audioPlayer.seek(position);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await super.setShuffleMode(shuffleMode);

    audioPlayer.setShuffle(shuffleMode == AudioServiceShuffleMode.all);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    super.setRepeatMode(repeatMode);
    audioPlayer.setLoopMode(switch (repeatMode) {
      AudioServiceRepeatMode.all ||
      AudioServiceRepeatMode.group =>
        PlaylistMode.loop,
      AudioServiceRepeatMode.one => PlaylistMode.single,
      _ => PlaylistMode.none,
    });
  }

  @override
  Future<void> stop() async {
    await audioPlayerNotifier.stop();
  }

  @override
  Future<void> skipToNext() async {
    await audioPlayer.skipToNext();
    await super.skipToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await audioPlayer.skipToPrevious();
    await super.skipToPrevious();
  }

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) {
    return library.getChildren(parentMediaId);
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    try {
      await library.play(mediaId);
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }
  }

  @override
  Future<List<MediaItem>> search(
    String query, [
    Map<String, dynamic>? extras,
  ]) {
    return library.search(query);
  }

  @override
  Future<void> playFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    try {
      await library.playFromSearch(query, extras);
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await audioPlayer.jumpTo(index + _queueOffset);
  }

  // The queue shown by the car is a window around the active track: a queue of
  // thousands of tracks wouldn't fit in a binder transaction
  static const _queueWindow = 300;
  static const _queueHistory = 50;
  int _queueOffset = 0;
  List<String> _queueIds = const [];

  /// Publishes the queue only when it changed: every update scrolls the car's
  /// queue view back to the top, and the player reports each appended track
  void setTracksQueue(List<SpotubeTrackObject> tracks, int currentIndex) {
    // Moves the window only when the active track gets close to its edges
    final position = currentIndex - _queueOffset;
    if (position < 0 || position >= _queueWindow - _queueHistory) {
      _queueOffset = max(
        0,
        min(currentIndex - _queueHistory, tracks.length - _queueWindow),
      );
    }

    final window = tracks.skip(_queueOffset).take(_queueWindow).toList();
    final ids = window.map((track) => track.id).toList();
    if (const ListEquality<String>().equals(ids, _queueIds)) return;
    _queueIds = ids;

    queueTitle.add(library.queueTitle);
    queue.add(window.map((track) => track.toMediaItem()).toList());
  }

  @override
  Future<void> onTaskRemoved() async {
    await audioPlayer.pause();
    if (kIsAndroid) exit(0);
  }

  Future<PlaybackState> _transformEvent() async {
    try {
      return PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          audioPlayer.isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: {
          MediaAction.seek,
        },
        androidCompactActionIndices: const [0, 1, 2],
        playing: audioPlayer.isPlaying,
        updatePosition: audioPlayer.position,
        bufferedPosition: audioPlayer.bufferedPosition,
        shuffleMode: audioPlayer.isShuffled == true
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: switch (audioPlayer.loopMode) {
          PlaylistMode.loop => AudioServiceRepeatMode.all,
          PlaylistMode.single => AudioServiceRepeatMode.one,
          _ => AudioServiceRepeatMode.none,
        },
        processingState: audioPlayer.isBuffering
            ? AudioProcessingState.loading
            : AudioProcessingState.ready,
        queueIndex: playlist.currentIndex - _queueOffset,
      );
    } catch (e, stack) {
      AppLogger.reportError(e, stack);
      rethrow;
    }
  }
}
