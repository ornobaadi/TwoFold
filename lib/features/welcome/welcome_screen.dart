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
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.l),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      const _Fan(),
                      const SizedBox(height: Space.xl),
                      Text(
                        'Read it. Hear it.\nNever lose your place.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontFamily: serifFont,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: Space.m),
                      Text(
                        "The great classics, free, each with a reader's voice. "
                        'Turn the page on the bus, listen on the walk home, '
                        'and pick up at the same line.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(color: c.muted, height: 1.45),
                      ),
                      const Spacer(),
                      const SizedBox(height: Space.xl),
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
                      const SizedBox(height: Space.s),
                      Text(
                        'No account. No ads. Online only when you ask.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Five first editions fanned out like books on a table, the middle one
/// with headphones: what the app is, before a word is read.
class _Fan extends StatelessWidget {
  const _Fan();

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    const w = 100.0;
    const h = w * 1.5;
    Widget cover(String name, double turn, double dx, double dy, {bool front = false}) {
      final scale = front ? 1.15 : 1.0;
      return Positioned(
        left: 0,
        right: 0,
        top: dy,
        child: Transform.translate(
          offset: Offset(dx, 0),
          child: Transform.rotate(
            angle: turn,
            alignment: Alignment.bottomCenter,
            child: Center(
              child: Container(
                width: w * scale,
                height: h * scale,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [
                    BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 8)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset('assets/covers/$name.jpg', fit: BoxFit.cover),
                      if (front)
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Container(
                            margin: const EdgeInsets.all(8),
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(color: s.primary, shape: BoxShape.circle),
                            child: Icon(Icons.headphones_rounded, size: 19, color: s.onPrimary),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ExcludeSemantics(
      child: SizedBox(
        height: h * 1.15 + 30,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            cover('alice', -0.30, -120, 30),
            cover('gatsby', 0.30, 120, 30),
            cover('dracula', -0.15, -62, 10),
            cover('holmes', 0.15, 62, 10),
            cover('pride', 0, 0, 0, front: true),
          ],
        ),
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
