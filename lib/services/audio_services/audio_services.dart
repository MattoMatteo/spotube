import 'package:audio_service/audio_service.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotube/collections/env.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/audio_player/audio_player.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/services/audio_services/android_auto_library.dart';
import 'package:spotube/services/audio_services/mobile_audio_service.dart';
import 'package:spotube/services/audio_services/windows_audio_service.dart';
import 'package:spotube/utils/platform.dart';

class AudioServices with WidgetsBindingObserver {
  final MobileAudioService? mobile;
  final WindowsAudioService? smtc;

  AudioServices(this.mobile, this.smtc) {
    WidgetsBinding.instance.addObserver(this);
  }

  static Future<AudioServices> create(
    Ref ref,
    AudioPlayerNotifier playback,
  ) async {
    final mobile = kIsMobile || kIsMacOS || kIsLinux
        ? await AudioService.init(
            builder: () =>
                MobileAudioService(playback, AndroidAutoLibrary(ref)),
            config: AudioServiceConfig(
              androidNotificationChannelId: switch ((
                kIsLinux,
                Env.releaseChannel
              )) {
                (true, _) => "spotube",
                (_, ReleaseChannel.stable) => "oss.krtirtho.spotube",
                (_, ReleaseChannel.nightly) => "oss.krtirtho.spotube.nightly",
              },
              androidNotificationChannelName: 'Matubefy',
              androidNotificationOngoing: false,
              androidStopForegroundOnPause: false,
              androidNotificationChannelDescription: "Matubefy Media Controls",
              androidNotificationIcon: "drawable/ic_notification",
              androidBrowsableRootExtras: AndroidAutoLibrary.rootExtras,
            ),
          )
        : null;
    final smtc = kIsWindows ? WindowsAudioService(ref, playback) : null;

    return AudioServices(mobile, smtc);
  }

  Future<void> addTrack(SpotubeTrackObject track) async {
    await smtc?.addTrack(track);
    mobile?.addItem(track.toMediaItem());
  }

  void setTracksQueue(List<SpotubeTrackObject> tracks, int currentIndex) {
    mobile?.setTracksQueue(tracks, currentIndex);
  }

  void activateSession() {
    mobile?.session?.setActive(true);
  }

  void deactivateSession() {
    mobile?.session?.setActive(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.detached:
        deactivateSession();
        audioPlayer.pause();
        break;
      default:
        break;
    }
  }

  void dispose() {
    smtc?.dispose();
    WidgetsBinding.instance.removeObserver(this);
  }
}
