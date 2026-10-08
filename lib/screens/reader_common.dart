import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/translate.dart';
import '../store.dart';

/// The floating top bar shared by both readers.
class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.96),
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.maybePop(context),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

/// The floating bottom bar: a seek slider over the page count.
class ReaderBottomBar extends StatelessWidget {
  const ReaderBottomBar({
    super.key,
    required this.page,
    required this.pageCount,
    required this.onSeek,
    required this.onJump,
    this.trailing,
    this.unitLabel = 'page',
  });

  final int page;
  final int pageCount;
  final Future<void> Function(int page) onSeek;
  final VoidCallback onJump;
  final Widget? trailing;
  final String unitLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = pageCount <= 1 ? 1.0 : pageCount.toDouble();

    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.96),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
          ),
          child: Row(
            children: [
              TextButton(
                onPressed: onJump,
                child: Text('$page / ${pageCount == 0 ? '…' : pageCount}'),
              ),
              Expanded(
                child: Slider(
                  value: page.clamp(1, pageCount == 0 ? 1 : pageCount).toDouble(),
                  min: 1,
                  max: max,
                  divisions: pageCount > 1 ? pageCount - 1 : null,
                  label: '$unitLabel $page',
                  onChanged: pageCount <= 1 ? null : (v) => onSeek(v.round()),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Lets the reader pick which colour new highlights use.
Future<void> pickHighlightColor(BuildContext context) async {
  final store = LibraryStore.instance;

  final chosen = await showModalBottomSheet<int>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Highlight colour',
              style: Theme.of(sheetContext).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final c in kHighlightColors)
                  GestureDetector(
                    onTap: () => Navigator.pop(sheetContext, c),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Color(c | 0xFF000000),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: store.highlightColor == c
                              ? Theme.of(sheetContext).colorScheme.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (chosen != null) await store.setHighlightColor(chosen);
}

// --------------------------------------------------------------- translate

/// Translates a selection and optionally saves it as a highlight.
class TranslateSheet extends StatefulWidget {
  const TranslateSheet({super.key, required this.text, required this.onSave});

  final String text;
  final Future<void> Function(String translation, String lang) onSave;

  @override
  State<TranslateSheet> createState() => _TranslateSheetState();
}

class _TranslateSheetState extends State<TranslateSheet> {
  final _store = LibraryStore.instance;
  late String _lang = _store.targetLang;

  bool _loading = true;
  String? _error;
  TranslationResult? _result;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await TranslateService.translate(widget.text, _lang);
      if (!mounted) return;
      setState(() {
        _result = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.text,
                style: theme.textTheme.bodyMedium,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.translate, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: _lang,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(12),
                  items: [
                    for (final e in kLanguages.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _lang = v);
                    _store.setTargetLang(v);
                    _run();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 26),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Row(
                children: [
                  Expanded(
                    child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
                  TextButton(onPressed: _run, child: const Text('Retry')),
                ],
              )
            else if (_result != null) ...[
              SelectableText(
                _result!.text,
                style: theme.textTheme.headlineSmall?.copyWith(height: 1.4),
                textDirection: isRtl(_lang) ? TextDirection.rtl : TextDirection.ltr,
              ),
              const SizedBox(height: 8),
              Text(
                'from ${_result!.sourceLang} · ${_result!.provider}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _result == null
                      ? null
                      : () async {
                          Navigator.pop(context);
                          await widget.onSave(_result!.text, _lang);
                        },
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Save & highlight'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// True for languages that read right-to-left.
bool isRtl(String lang) =>
    const {'ar', 'he', 'fa', 'ur'}.contains(lang.split('-').first);

// ------------------------------------------------------------- reading mode

/// Fires [onTripleTap] on three quick taps anywhere over [child].
///
/// Uses a raw [Listener] so it only *observes* pointer events — it never enters
/// the gesture arena, so the reader's own scrolling, pinch-zoom and text
/// selection keep working untouched. Anything that isn't a clean, stationary
/// tap (a scroll, a drag, a long press) resets the count, so ordinary reading
/// never trips it.
class TripleTapDetector extends StatefulWidget {
  const TripleTapDetector({
    super.key,
    required this.onTripleTap,
    required this.child,
  });

  final VoidCallback onTripleTap;
  final Widget child;

  @override
  State<TripleTapDetector> createState() => _TripleTapDetectorState();
}

class _TripleTapDetectorState extends State<TripleTapDetector> {
  static const _slop = 18.0; // most a finger may travel and still be a "tap"
  static const _tapMs = 320; // longest a tap may be held
  static const _gap = Duration(milliseconds: 700); // window between taps

  Offset? _downPos;
  int _downMs = 0;
  int _taps = 0;
  Timer? _reset;

  void _onDown(PointerDownEvent e) {
    _downPos = e.position;
    _downMs = DateTime.now().millisecondsSinceEpoch;
  }

  void _onUp(PointerUpEvent e) {
    final down = _downPos;
    _downPos = null;
    if (down == null) return;

    final moved = (e.position - down).distance;
    final elapsed = DateTime.now().millisecondsSinceEpoch - _downMs;
    if (moved > _slop || elapsed > _tapMs) {
      _taps = 0; // a scroll or long press breaks the run
      _reset?.cancel();
      return;
    }

    _taps++;
    _reset?.cancel();
    if (_taps >= 3) {
      _taps = 0;
      widget.onTripleTap();
    } else {
      _reset = Timer(_gap, () => _taps = 0);
    }
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: _onDown,
      onPointerUp: _onUp,
      onPointerCancel: (_) => _downPos = null,
      child: widget.child,
    );
  }
}

bool _readingHintShown = false;

/// Tells the reader, once per app run, how to bring the toolbar back.
void showReadingModeHintOnce(BuildContext context) {
  if (_readingHintShown) return;
  _readingHintShown = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Reading mode — triple-tap anywhere to show the toolbar'),
          duration: Duration(seconds: 3),
        ),
      );
  });
}

// -------------------------------------------------------------------- note

/// Asks for a note against a quoted passage.
class NoteDialog extends StatefulWidget {
  const NoteDialog({super.key, required this.quote});

  final String quote;

  @override
  State<NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<NoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Add note'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                widget.quote,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Your note…'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
