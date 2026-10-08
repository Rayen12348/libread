# Libread

[![release](https://img.shields.io/github/v/release/Rayen12348/libread)](https://github.com/Rayen12348/libread/releases/latest)
![platform](https://img.shields.io/badge/platform-Android-3DDC84)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A library, book installer and reader for Android. Reads **PDF and EPUB**,
installs free books from open catalogs, and is themed in **Tokyo Night**.

## Download

**[⬇ Download the latest APK](https://github.com/Rayen12348/libread/releases/latest/download/libread.apk)**,
open it on your phone, and allow installing from your browser when asked.

## Features

- **Library**: grid or list shelf with cover art, reading progress, favourites,
  tags, search and sorting.
- **Discover**: search Project Gutenberg, Standard Ebooks, Internet Archive,
  Open Library, Feedbooks and arXiv at once, add your own OPDS feeds, or paste
  any PDF/EPUB link.
- **Reader**: PDF with zoom, table of contents and page slider; EPUB with
  adjustable text size and chapter navigation.
- **Markup**: highlights in seven colours, notes, and translation of a
  selection into 12 languages.
- **Notebook**: tagged, searchable notes that can link back to a book and page.
- **Themes**: Night, Storm and Day, or follow the system.

Every built-in catalog offers public-domain or open-access books only.

## Build from source

Requires Flutter (stable) with the Android SDK, NDK and CMake.

```bash
git clone https://github.com/Rayen12348/libread.git
cd libread
flutter pub get
flutter build apk --release   # → build/app/outputs/flutter-apk/app-release.apk
```

Release builds are signed with the key in `android/key.properties` (never
commit it) and fall back to the debug key if it is missing. Pushing a `v*` tag
builds the APK and publishes it as a GitHub Release.

## License

[MIT](LICENSE)
