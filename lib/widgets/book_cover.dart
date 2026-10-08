import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// A book's cover art, falling back to a generated Tokyo Night placeholder.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.title,
    this.author,
    this.filePath,
    this.imageUrl,
    this.radius = 14,
    this.busy = false,
  });

  BookCover.of(
    Book book, {
    super.key,
    this.radius = 14,
    this.busy = false,
  }) : title = book.title,
       author = book.author,
       filePath = book.coverPath,
       imageUrl = null;

  final String title;
  final String? author;
  final String? filePath;
  final String? imageUrl;
  final double radius;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final placeholder = GeneratedCover(title: title, author: author);

    Widget image = placeholder;
    final path = filePath;
    final url = imageUrl;

    if (path != null && File(path).existsSync()) {
      image = Image.file(
        File(path),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder,
      );
    } else if (url != null && url.isNotEmpty) {
      image = Image.network(
        url,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : placeholder,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHigh, child: image),
          // A subtle inner edge keeps light covers from bleeding into the page.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.black.withValues(alpha: 0.25)),
            ),
          ),
          if (busy)
            DecoratedBox(
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45)),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The fallback cover: a tinted gradient carrying the title and author.
///
/// The hue is derived from the title, so a book always looks the same.
class GeneratedCover extends StatelessWidget {
  const GeneratedCover({super.key, required this.title, this.author});

  final String title;
  final String? author;

  @override
  Widget build(BuildContext context) {
    final accent = TokyoNight.accents[title.hashCode.abs() % TokyoNight.accents.length];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(TokyoNight.nightBgDark, accent, 0.30)!,
            Color.lerp(TokyoNight.nightBgDark, accent, 0.08)!,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // A soft glow so the flat gradient reads as artwork.
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.16),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 26, height: 3, color: accent),
                const Spacer(),
                Text(
                  title,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TokyoNight.fg,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    height: 1.25,
                    letterSpacing: -0.2,
                  ),
                ),
                if (author != null && author!.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    author!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A thin progress bar drawn along the bottom of a cover.
class CoverProgressBar extends StatelessWidget {
  const CoverProgressBar({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 3,
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45)),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress.clamp(0.0, 1.0),
        child: ColoredBox(color: scheme.primary),
      ),
    );
  }
}

/// A small pill used for source names, formats and counts.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.filled = false,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? c.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: filled ? Colors.transparent : scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// The empty-state block used across the app.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, size: 34, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 22), action!],
          ],
        ),
      ),
    );
  }
}
