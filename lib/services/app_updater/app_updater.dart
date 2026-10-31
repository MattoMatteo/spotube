import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:spotube/services/dio/dio.dart';
import 'package:spotube/utils/exit_app.dart';
import 'package:spotube/utils/platform.dart';
import 'package:version/version.dart';

/// The GitHub repository Matubefy is released from
const matubefyRepository = "MattoMatteo/spotube";

/// A release newer than the running app
class AppUpdate {
  final Version version;

  /// Release notes, in Markdown
  final String notes;

  /// The release's page on GitHub
  final String pageUrl;

  /// The installer for this platform, null where the app can't update itself
  final String? assetUrl;
  final String? assetName;

  const AppUpdate({
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.assetUrl,
    this.assetName,
  });

  bool get canInstall => assetUrl != null && assetName != null;
}

class InstallPermissionDeniedException implements Exception {}

/// Updates the app from its GitHub releases: releases/latest skips drafts and
/// pre-releases, so test builds are never offered
abstract class AppUpdater {
  static Future<AppUpdate?> fetchNewer() async {
    final Response response;
    try {
      response = await globalDio.getUri(
        Uri.parse(
          "https://api.github.com/repos/$matubefyRepository/releases/latest",
        ),
      );
    } on DioException catch (e) {
      // No release published yet
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }

    final data = response.data as Map<String, dynamic>;
    final version = Version.parse(
      (data["tag_name"] as String).replaceFirst(RegExp("^v"), ""),
    );
    final current = Version.parse((await PackageInfo.fromPlatform()).version);
    if (version <= current) return null;

    // The release workflow names them Matubefy-<version>-android.apk and
    // Matubefy-<version>-windows-setup.exe
    final suffix = kIsAndroid
        ? ".apk"
        : kIsWindows
            ? "-setup.exe"
            : null;
    final asset = suffix == null
        ? null
        : (data["assets"] as List)
            .cast<Map<String, dynamic>>()
            .firstWhereOrNull(
              (asset) => (asset["name"] as String).endsWith(suffix),
            );

    return AppUpdate(
      version: version,
      notes: data["body"] as String? ?? "",
      pageUrl: data["html_url"] as String,
      assetUrl: asset?["browser_download_url"] as String?,
      assetName: asset?["name"] as String?,
    );
  }

  /// Downloads the installer of [update], reporting the progress from 0 to 1
  static Future<File> download(
    AppUpdate update,
    void Function(double progress) onProgress,
  ) async {
    final file = File(
      join((await getTemporaryDirectory()).path, update.assetName!),
    );
    await globalDio.download(
      update.assetUrl!,
      file.path,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress(received / total);
      },
    );
    return file;
  }

  /// Hands [installer] to the system. On Windows the app quits right after,
  /// so the installer can replace its files, and the installer reopens it
  static Future<void> install(File installer) async {
    if (kIsAndroid) {
      // "Install unknown apps", asked once: Android shows its own toggle
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) throw InstallPermissionDeniedException();

      final result = await OpenFile.open(
        installer.path,
        type: "application/vnd.android.package-archive",
      );
      if (result.type != ResultType.done) throw Exception(result.message);
    } else if (kIsWindows) {
      // Start-Process goes through ShellExecute, which shows the UAC prompt
      // the installer needs to write to Program Files
      final path = installer.path.replaceAll("'", "''");
      final result = await Process.run("powershell", [
        "-NoProfile",
        "-Command",
        "Start-Process -FilePath '$path' -Verb RunAs "
            "-ArgumentList '/SILENT','/SUPPRESSMSGBOXES','/NORESTART'",
      ]);
      // Non-zero when the UAC prompt was refused: the app stays open
      if (result.exitCode != 0) throw Exception(result.stderr);
      exitApp();
    } else {
      throw UnsupportedError("The app can't update itself on this platform");
    }
  }
}
