import 'package:spotube/provider/metadata_plugin/metadata_plugin_provider.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/provider/user_preferences/user_preferences_provider.dart';
import 'package:spotube/services/audio_player/audio_player.dart';

void useEndlessPlayback(WidgetRef ref) {
  final playback = ref.watch(audioPlayerProvider.notifier);
  final audioPlayerState = ref.watch(audioPlayerProvider);
  final endlessPlayback =
      ref.watch(userPreferencesProvider.select((s) => s.endlessPlayback));
  final metadataPlugin = ref.watch(metadataPluginProvider.future);

  // Reaching the last track triggers the listener twice: from
  // currentIndexChangedStream and from this effect re-running on the new
  // currentIndex. Two concurrent radio() calls then interleaved the same
  // tracks into the queue. These refs outlive the effect re-runs.
  final isFetchingRadio = useRef(false);
  final lastRadioSeedId = useRef<String?>(null);

  // A different last track means the queue changed: allow a new radio fetch.
  if (audioPlayerState.tracks.lastOrNull?.id != lastRadioSeedId.value) {
    lastRadioSeedId.value = null;
  }

  useEffect(
    () {
      if (!endlessPlayback) return null;

      void listener(int index) async {
        try {
          final playlist = ref.read(audioPlayerProvider);
          if (index != playlist.tracks.length - 1) return;

          final track = playlist.tracks.last;

          // One fetch at a time, and once per seed track (also avoids
          // refetching when the radio had nothing new to add)
          if (isFetchingRadio.value || lastRadioSeedId.value == track.id) {
            return;
          }
          isFetchingRadio.value = true;
          lastRadioSeedId.value = track.id;

          final tracks = await (await metadataPlugin)?.track.radio(track.id);

          if (tracks == null || tracks.isEmpty) return;

          final seenIds = <String>{};
          await playback.addTracks(
            tracks.toList()
              ..removeWhere((e) {
                final playlist = ref.read(audioPlayerProvider);
                final isDuplicate = playlist.tracks.any((t) => t.id == e.id);
                return e.id == track.id || isDuplicate || !seenIds.add(e.id);
              }),
          );
        } catch (e, stack) {
          // Let a failed fetch be retried
          lastRadioSeedId.value = null;
          AppLogger.reportError(e, stack);
        } finally {
          isFetchingRadio.value = false;
        }
      }

      // Sometimes user can change settings for which the currentIndexChanged
      // might not be called. So we need to check if the current track is the
      // last track and if it is then we need to call the listener manually.
      if (audioPlayerState.currentIndex == audioPlayerState.tracks.length - 1 &&
          audioPlayer.isPlaying) {
        listener(audioPlayerState.currentIndex);
      }

      final subscription =
          audioPlayer.currentIndexChangedStream.listen(listener);

      return subscription.cancel;
    },
    [
      metadataPlugin,
      playback,
      audioPlayerState.tracks,
      audioPlayerState.currentIndex,
      endlessPlayback,
    ],
  );
}
