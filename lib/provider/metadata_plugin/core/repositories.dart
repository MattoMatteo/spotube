import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/metadata_plugin/utils/paginated.dart';
import 'package:spotube/services/dio/dio.dart';

class MetadataPluginRepositoriesNotifier
    extends PaginatedAsyncNotifier<MetadataPluginRepository> {
  MetadataPluginRepositoriesNotifier() : super();

  /// Upstream's latest release is the Kotlin rewrite, which this (Hetu based)
  /// Spotube can't run: hide it and list the patched Hetu fork instead.
  /// GitHub search never returns the fork itself (it excludes forks).
  static const _replacedRepoUrl =
      "https://github.com/sonic-liberation/spotube-plugin-spotify";
  static final _patchedSpotifyPlugin = MetadataPluginRepository(
    name: "spotube-plugin-spotify",
    owner: "MattoMatteo",
    description:
        "Spotify metadata plugin (patched Hetu version, compatible with Spotube 5.1.2)",
    // Same as plugin.json's "repository", so it's hidden once installed
    repoUrl: "https://github.com/MattoMatteo/spotube-plugin-spotify",
    topics: ["spotube", "spotube-plugin", "spotube-metadata-plugin"],
  );

  Map<String, bool> _hasMore = {};

  @override
  fetch(int offset, int limit) async {
    final gitubSearch = globalDio.get(
      "https://api.github.com/search/repositories",
      queryParameters: {
        "q": "topic:spotube-plugin",
        "sort": "stars",
        "order": "desc",
        "page": offset,
        "per_page": limit,
      },
    );

    final codebergSearch = globalDio.get(
      "https://codeberg.org/api/v1/repos/search",
      queryParameters: {
        "q": "spotube-plugin",
        "topic": "true",
        "sort": "stars",
        "order": "desc",
        "page": offset,
        "limit": limit,
      },
    );

    final responses = await Future.wait([
      if (_hasMore["github.com"] ?? true) gitubSearch,
      if (_hasMore["codeberg.org"] ?? true) codebergSearch,
    ]);

    final repos = responses
        .expand(
      (response) => response.data["data"] ?? response.data["items"] ?? [],
    )
        .map((repo) {
      return MetadataPluginRepository(
        name: repo["name"] ?? "",
        owner: repo["owner"]["login"] ?? "",
        description: repo["description"] ?? "",
        repoUrl: repo["html_url"] ?? "",
        topics: repo["topics"].cast<String>() ?? [],
      );
    }).toList();

    final replacedCount =
        repos.where((repo) => repo.repoUrl == _replacedRepoUrl).length;
    repos.removeWhere((repo) => repo.repoUrl == _replacedRepoUrl);
    final isFirstPage = offset == 0;
    if (isFirstPage) {
      repos.insert(0, _patchedSpotifyPlugin);
    }

    final hasMore = responses.any((response) {
      final items =
          (response.data["data"] ?? response.data["items"] ?? []) as List;
      _hasMore[response.requestOptions.uri.host] =
          items.length >= limit && items.isNotEmpty;

      return _hasMore[response.requestOptions.uri.host] ?? false;
    });

    return SpotubePaginationResponseObject(
      items: repos,
      total: responses.fold<int>(
            0,
            (previousValue, response) => previousValue +
                (response.data["total_count"] ??
                    int.tryParse(response.headers["x-total-count"]?[0] ?? "") ??
                    0) as int,
          ) -
          replacedCount +
          (isFirstPage ? 1 : 0),
      hasMore: hasMore,
      nextOffset: hasMore ? offset + 1 : null,
      limit: limit,
    );
  }

  @override
  build() async {
    return await fetch(0, 10);
  }
}

final metadataPluginRepositoriesProvider = AsyncNotifierProvider<
    MetadataPluginRepositoriesNotifier,
    SpotubePaginationResponseObject<MetadataPluginRepository>>(
  () => MetadataPluginRepositoriesNotifier(),
);
