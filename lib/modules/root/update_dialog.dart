import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:spotube/collections/spotube_icons.dart';
import 'package:spotube/components/markdown/markdown.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/services/app_updater/app_updater.dart';
import 'package:spotube/services/logger/logger.dart';
import 'package:spotube/utils/platform.dart';
import 'package:url_launcher/url_launcher_string.dart';

class RootAppUpdateDialog extends HookWidget {
  final AppUpdate update;

  const RootAppUpdateDialog({super.key, required this.update});

  @override
  Widget build(BuildContext context) {
    // Download progress from 0 to 1, null when not downloading
    final progress = useState<double?>(null);
    final isUpdating = progress.value != null;

    void showError(String message) {
      showToast(
        context: context,
        builder: (context, overlay) {
          return SurfaceCard(
            child: Basic(
              leading: const Icon(SpotubeIcons.error, color: Colors.red),
              title: Text(message),
              leadingAlignment: Alignment.center,
              trailing: IconButton.ghost(
                size: ButtonSize.small,
                icon: const Icon(SpotubeIcons.close),
                onPressed: overlay.close,
              ),
            ),
          );
        },
      );
    }

    Future<void> install() async {
      progress.value = 0;
      try {
        final installer = await AppUpdater.download(
          update,
          (value) => progress.value = value,
        );
        // On Windows the app quits here
        await AppUpdater.install(installer);
        if (context.mounted) Navigator.of(context).pop();
      } on InstallPermissionDeniedException {
        if (context.mounted) showError(context.l10n.install_permission_needed);
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
        if (context.mounted) showError(context.l10n.update_failed);
      } finally {
        if (context.mounted) progress.value = null;
      }
    }

    return AlertDialog(
      title: Text(
        context.l10n.matubefy_update_available(update.version.toString()),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 400, maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            if (update.notes.isNotEmpty)
              Flexible(
                child: SingleChildScrollView(
                  child: AppMarkdown(data: update.notes),
                ),
              ),
            if (kIsWindows && update.canInstall)
              Text(context.l10n.update_closes_app).muted.small,
            if (isUpdating) ...[
              LinearProgressIndicator(value: progress.value),
              Text(
                context.l10n.downloading_update(
                  (progress.value! * 100).round(),
                ),
              ).small,
            ],
          ],
        ),
      ),
      actions: [
        SecondaryButton(
          enabled: !isUpdating,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.later),
        ),
        if (update.canInstall)
          PrimaryButton(
            enabled: !isUpdating,
            onPressed: install,
            child: Text(context.l10n.update),
          )
        else
          PrimaryButton(
            onPressed: () => launchUrlString(
              update.pageUrl,
              mode: LaunchMode.externalApplication,
            ),
            child: Text(context.l10n.open_release_page),
          ),
      ],
    );
  }
}
