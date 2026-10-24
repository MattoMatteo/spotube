import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrobblenaut/scrobblenaut.dart';
import 'package:spotube/collections/env.dart';
import 'package:spotube/models/database/database.dart';
import 'package:spotube/models/metadata/metadata.dart';
import 'package:spotube/provider/database/database.dart';
import 'package:spotube/services/kv_store/kv_store.dart';
import 'package:spotube/services/logger/logger.dart';

class ScrobblerNotifier extends AsyncNotifier<Scrobblenaut?> {
  /// Whether this build ships a Last.fm API key (.env), otherwise users must
  /// enter their own on the Last.fm login page.
  static bool get hasBuiltInApiKey =>
      Env.lastFmApiKey.isNotEmpty && Env.lastFmApiKey != "none";

  // A personal API key (saved on login) takes precedence over the built-in one
  static bool get _hasPersonalApiKey =>
      (KVStoreService.lastFmApiKey?.isNotEmpty ?? false) &&
      (KVStoreService.lastFmApiSecret?.isNotEmpty ?? false);
  static String get _apiKey =>
      _hasPersonalApiKey ? KVStoreService.lastFmApiKey! : Env.lastFmApiKey;
  static String get _apiSecret => _hasPersonalApiKey
      ? KVStoreService.lastFmApiSecret!
      : Env.lastFmApiSecret;

  final StreamController<SpotubeTrackObject> _scrobbleController =
      StreamController<SpotubeTrackObject>.broadcast();
  @override
  build() async {
    final database = ref.watch(databaseProvider);

    final loginInfo = await (database.select(database.scrobblerTable)
          ..where((t) => t.id.equals(0)))
        .getSingleOrNull();

    final subscription =
        database.select(database.scrobblerTable).watch().listen((event) async {
      try {
        if (event.isNotEmpty) {
          state = await AsyncValue.guard(
            () async => Scrobblenaut(
              lastFM: await LastFM.authenticateWithPasswordHash(
                apiKey: _apiKey,
                apiSecret: _apiSecret,
                username: event.first.username,
                passwordHash: event.first.passwordHash.value,
              ),
            ),
          );
        } else {
          state = const AsyncValue.data(null);
        }
      } catch (e, stack) {
        AppLogger.reportError(e, stack);
      }
    });

    final scrobblerSubscription =
        _scrobbleController.stream.listen((track) async {
      try {
        await state.asData?.value?.track.scrobble(
          artist: track.artists.first.name,
          track: track.name,
          album: track.album.name,
          chosenByUser: true,
          duration: Duration(milliseconds: track.durationMs),
          timestamp: DateTime.now().toUtc(),
        );
      } catch (e, stackTrace) {
        AppLogger.reportError(e, stackTrace);
      }
    });

    ref.onDispose(() {
      subscription.cancel();
      scrobblerSubscription.cancel();
    });

    if (loginInfo == null) {
      return null;
    }

    return Scrobblenaut(
      lastFM: await LastFM.authenticateWithPasswordHash(
        apiKey: _apiKey,
        apiSecret: _apiSecret,
        username: loginInfo.username,
        passwordHash: loginInfo.passwordHash.value,
      ),
    );
  }

  /// [apiKey] and [apiSecret] are an optional personal Last.fm API key,
  /// saved (and then used instead of the built-in one) if the login succeeds.
  Future<void> login(
    String username,
    String password, {
    String? apiKey,
    String? apiSecret,
  }) async {
    final database = ref.read(databaseProvider);

    final hasNewApiKey =
        (apiKey?.isNotEmpty ?? false) && (apiSecret?.isNotEmpty ?? false);

    final lastFm = await LastFM.authenticate(
      apiKey: hasNewApiKey ? apiKey! : _apiKey,
      apiSecret: hasNewApiKey ? apiSecret! : _apiSecret,
      username: username,
      password: password,
    );

    if (!lastFm.isAuth) throw Exception("Invalid credentials");

    // Before inserting the login: the table watcher re-authenticates with it
    if (hasNewApiKey) {
      await KVStoreService.setLastFmApiCredentials(apiKey!, apiSecret!);
    }

    await database.into(database.scrobblerTable).insert(
          ScrobblerTableCompanion.insert(
            id: const Value(0),
            username: username,
            passwordHash: DecryptedText(lastFm.passwordHash!),
          ),
        );
  }

  Future<void> logout() async {
    state = const AsyncValue.data(null);
    final database = ref.read(databaseProvider);
    await database.delete(database.scrobblerTable).go();
  }

  void scrobble(SpotubeTrackObject track) {
    _scrobbleController.add(track);
  }

  Future<void> love(SpotubeTrackObject track) async {
    await state.asData?.value?.track.love(
      artist: track.artists.asString(),
      track: track.name,
    );
  }

  Future<void> unlove(SpotubeTrackObject track) async {
    await state.asData?.value?.track.unLove(
      artist: track.artists.asString(),
      track: track.name,
    );
  }
}

final scrobblerProvider =
    AsyncNotifierProvider<ScrobblerNotifier, Scrobblenaut?>(
  () => ScrobblerNotifier(),
);
