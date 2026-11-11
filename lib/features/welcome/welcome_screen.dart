import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/home_shell.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/book_repo.dart';
import '../../import/samples.dart';
import '../../audio/player_controller.dart';

/// Set once the welcome has been answered, so it shows only on first launch.
const welcomedKey = 'welcomed';

/// Whether to greet: a new install, not someone who already has books.
Future<bool> shouldWelcome(BookRepo repo) async {
  if (await repo.getSetting(welcomedKey) != null) return false;
  final own = (await repo.allBooks())
      .where((b) => !sampleBooks.any((s) => s.id == b.id));
  if (own.isNotEmpty) {
    await repo.setSetting(welcomedKey, 'true');
    return false;
  }
  return true;
}

/// First launch: what TwoFold is, and one question with three answers.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  Future<void> _done(BuildContext context, WidgetRef ref, Widget next) async {
    await ref.read(bookRepoProvider).setSetting(welcomedKey, 'true');
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => next),
    );
  }

  Future<void> _own(BuildContext context, WidgetRef ref) async {
    final book = await openNewBook(context);
    if (!context.mounted || book == null) return;
    await _done(context, ref, HomeShell(resumeBookId: book.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = context.twofold;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.xl, 56, Space.xl, Space.xl),
          children: [
            const _Books(),
            const SizedBox(height: Space.xl),
            Text(
              'Read it. Hear it.\nNever lose your place.',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontFamily: serifFont,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
            const SizedBox(height: Space.m),
            Text(
              'Thousands of classics come free with a recording. Read on the '
              'bus, listen on the walk home, and pick up at the same line.',
              style: theme.textTheme.bodyLarge?.copyWith(color: c.muted),
            ),
            const SizedBox(height: Space.xl),
            Text(
              'HOW WOULD YOU LIKE TO START?',
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Space.s),
            _Choice(
              primary: true,
              icon: Icons.headphones_rounded,
              title: 'Get a free book with audio',
              subtitle: 'Pride and Prejudice, Dracula, Sherlock Holmes…',
              onTap: () => _done(context, ref, const HomeShell(initialTab: 1)),
            ),
            _Choice(
              icon: Icons.description_outlined,
              title: 'Open my own book and audio',
              subtitle: 'EPUB or PDF, with MP3 or M4B files',
              onTap: () => _own(context, ref),
            ),
            _Choice(
              icon: Icons.play_arrow_rounded,
              title: 'Try a 10-minute story',
              subtitle: 'The Story of an Hour, already on your phone',
              onTap: () async {
                final id = sampleBooks.first.id;
                final there = await ref.read(bookRepoProvider).getBook(id);
                if (!context.mounted) return;
                await _done(
                  context,
                  ref,
                  HomeShell(resumeBookId: there == null ? null : id),
                );
              },
            ),
            const SizedBox(height: Space.xl),
            Text(
              'No account. No ads. Online only when you ask.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Books extends StatelessWidget {
  const _Books();

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    Widget book(int i, double turn, {bool ear = false}) {
      final (bg, fg) = clothFor(['Pride', 'Dracula', 'Oz'][i]);
      return Transform.rotate(
        angle: turn,
        child: Container(
          width: 58,
          height: 84,
          decoration: BoxDecoration(
            color: ear ? s.primary : bg,
            borderRadius: BorderRadius.circular(5),
          ),
          child: ear
              ? Icon(Icons.headphones_rounded, color: s.onPrimary, size: 26)
              : null,
        ),
      );
    }

    return ExcludeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          book(0, -0.1),
          const SizedBox(width: 10),
          book(1, 0),
          const SizedBox(width: 10),
          book(2, 0.09, ear: true),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final fg = primary ? s.surface : s.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Material(
        color: primary ? s.onSurface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: primary ? BorderSide.none : BorderSide(color: s.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Row(
              children: [
                Icon(icon, color: fg),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: fg.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
