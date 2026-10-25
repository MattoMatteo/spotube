// The container's scheduler is internal to Riverpod
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Riverpod applies pending provider rebuilds in the next Flutter frame, but
/// Flutter draws no frames without a visible UI: when Android Auto starts the
/// app through its audio service, or while the app is in the background.
/// Whatever waits for such a rebuild then waits forever, e.g. the stream of
/// the restored track when the car presses play.
///
/// This registers one more vsync with the container, next to the one of the
/// [ProviderScope], that forces a frame when Flutter wouldn't draw one.
void useProviderRebuildsWithoutFrames(BuildContext context) {
  useEffect(() {
    final vsyncs = ProviderScope.containerOf(context, listen: false)
        .scheduler
        .flutterVsyncs;

    void forceFrame(void Function() task) {
      final scheduler = SchedulerBinding.instance;
      // The ProviderScope runs the task in its next build
      if (!scheduler.framesEnabled) scheduler.scheduleWarmUpFrame();
    }

    vsyncs.add(forceFrame);
    return () => vsyncs.remove(forceFrame);
  }, []);
}
