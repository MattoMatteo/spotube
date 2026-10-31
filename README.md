# Matubefy

Matubefy is a personal fork of **[Spotube](https://github.com/KRTirtho/spotube) 5.1.2** (the
Flutter version) by Kingkor Roy Tirtho, with fixes and a few changes on top.

> This product includes software developed by Kingkor Roy Tirtho.

Matubefy is **not affiliated with, endorsed by or supported by** Spotube, its author, Spotify or
YouTube. Please don't report Matubefy issues to the original Spotube project: use
[this repository's issues](https://github.com/MattoMatteo/spotube/issues) instead.

The original Spotube README is kept in [README.spotube.md](README.spotube.md).

## What's different from Spotube 5.1.2

- **Endless playback (radio)**: no more duplicated tracks when the queue reaches its end.
- **YouTube matching (NewPipe engine)**:
  - searches YouTube Music songs first (official album tracks, right duration), falling back to
    YouTube videos;
  - doesn't fail on reduced YouTube responses or on results with missing fields;
  - uses [NewPipeCLI](https://github.com/MattoMatteo/NewPipeCLI) built with NewPipeExtractor
    v0.26.5 (audio-only streams again), on Android too;
  - searches with accented/non-latin characters work on Windows.
- **Plugins**: ships the patched [Spotify plugin](https://github.com/MattoMatteo/spotube-plugin-spotify)
  (Hetu, works with this app version) and lists it instead of the upstream one, whose latest release
  targets the new Kotlin Spotube.
- **Last.fm**: you can use your own Last.fm API key (Settings → Scrobbling).
- **New installs** default to the NewPipe engine.
- **Android**: application id `io.github.mattomatteo.matubefy`, installs next to the official app.
- **Android Auto**: browse home, library, recently played and search from the car, with the queue
  and voice requests; the app also starts and plays when the car launches it.
- **Own look**: Matubefy icon and splash, and a default color scheme with the logo's gradient.
- **Windows**: closing the app is instant (it used to freeze for seconds on a crash at exit).
- **Updates**: the app checks this repository's releases and updates itself (see below).

## Downloads and updates

Windows installer and Android APK: [latest release](https://github.com/MattoMatteo/spotube/releases/latest).
They are not signed by a known publisher, so Windows SmartScreen and Android will warn you before
installing.

Once installed, the app checks for a newer release at startup (Settings → About → Check for
updates, which also has a button to check right away) and offers to update:

- **Android** downloads the new APK and opens the system installer. The first time, Android asks to
  allow Matubefy to install apps. The app's data is kept.
- **Windows** downloads the new installer and runs it (UAC prompt): Matubefy closes, updates and
  opens again.

Builds started by hand from the Actions tab go to the `test-build` pre-release, which the app never
offers as an update.

## Releasing

1. Set the new version in `pubspec.yaml`, e.g. `version: 1.0.1+47`: the build number after `+`
   must always grow, or Android refuses the update.
2. Commit, then tag and push: `git tag matubefy-v1.0.1 && git push origin main matubefy-v1.0.1`.
   The `matubefy-` prefix keeps the tags apart from the `v1.0.0`…`v5.1.2` ones inherited from
   Spotube's history.

The [Release workflow](.github/workflows/release.yml) builds the APK and the Windows installer,
attaches them to a draft release with the generated notes and publishes it once both are there.

## Related forks

| Repository | What it is |
|---|---|
| [MattoMatteo/spotube](https://github.com/MattoMatteo/spotube) | This app |
| [MattoMatteo/spotube-plugin-spotify](https://github.com/MattoMatteo/spotube-plugin-spotify) | Spotify metadata plugin |
| [MattoMatteo/spotify-gql-client](https://github.com/MattoMatteo/spotify-gql-client) | Spotify GraphQL client used by the plugin |
| [MattoMatteo/flutter_new_pipe_extractor](https://github.com/MattoMatteo/flutter_new_pipe_extractor) | Flutter bridge to NewPipe |
| [MattoMatteo/NewPipeCLI](https://github.com/MattoMatteo/NewPipeCLI) | NewPipeExtractor as a desktop executable |

## License

- The original Spotube code is under the **BSD-4-Clause** license, see [LICENSE](LICENSE)
  (© Kingkor Roy Tirtho). It stays under that license.
- The changes made in this fork are released under the **MIT License**, see
  [licenses/MIT-fork-changes.txt](licenses/MIT-fork-changes.txt).
- Bundled third-party components keep their own licenses, see [NOTICE.md](NOTICE.md).

This app uses unofficial access to Spotify and YouTube; use it at your own risk and in accordance
with the terms of the services you use.
