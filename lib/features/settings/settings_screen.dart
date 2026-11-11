import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings.dart';
import '../../app/theme.dart';
import '../../audio/player_controller.dart';
import '../../import/samples.dart';
import '../library/providers.dart';
import '../../audio/downloads.dart' show formatSize;
import 'settings_sheet.dart';

const appVersion = '0.3.0';

/// Settings for the whole app. Text options live in the reader's sheet too.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.l,
          Space.s,
          Space.l,
          Space.xxl,
        ),
        children: [
          const _Heading('Look'),
          _Group(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Background', style: theme.textTheme.bodyLarge),
                    const SizedBox(height: Space.m),
                    const ThemeChooser(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Accent', style: theme.textTheme.bodyLarge),
                    Text(
                      'Used for play, progress and your current choice.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: Space.xs),
                    const PaletteChooser(),
                  ],
                ),
              ),
            ],
          ),
          const _Heading('Reading'),
          _Group(
            children: [
              SwitchListTile(
                title: const Text('Keep the screen on'),
                subtitle: const Text('While a book is open'),
                value: s.keepScreenOn,
                onChanged: (v) => notifier.change(s.copyWith(keepScreenOn: v)),
              ),
            ],
          ),
          const _Heading('Listening'),
          _Group(
            children: [
              Padding(
                padding: const EdgeInsets.all(Space.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Skip back and forward',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: Space.m),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: [
                        for (final v in [5, 10, 15, 30])
                          ButtonSegment(value: v, label: Text('$v s')),
                      ],
                      selected: {s.skipSeconds},
                      onSelectionChanged: (v) =>
                          notifier.change(s.copyWith(skipSeconds: v.first)),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                title: const Text('Save free audiobooks on Wi-Fi only'),
                subtitle: const _SavedSpace(),
                value: s.wifiOnlyDownloads,
                onChanged: (v) => notifier.change(s.copyWith(wifiOnlyDownloads: v)),
              ),
              SwitchListTile(
                title: const Text('Rewind after a long pause'),
                subtitle: const Text(
                  'Go back 3 seconds after a pause of over a minute',
                ),
                value: s.autoRewind,
                onChanged: (v) => notifier.change(s.copyWith(autoRewind: v)),
              ),
            ],
          ),
          const _Heading('About'),
          _Group(
            children: [
              ListTile(
                title: const Text('Sample stories'),
                subtitle:
                    const Text('Free stories with audio, and who read them'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showSamples(context, ref),
              ),
              const ListTile(
                title: Text('Your books stay on this phone'),
                subtitle: Text(
                  'TwoFold has no account. It uses the internet only when you find free books.',
                ),
              ),
              ListTile(
                title: const Text('Open source licences'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'TwoFold',
                  applicationVersion: appVersion,
                ),
              ),
            ],
          ),
          const MadeBy(),
        ],
      ),
    );
  }
}

void _showSamples(BuildContext context, WidgetRef ref) => showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Sample stories'),
        content: SingleChildScrollView(
          child: Text([
            for (final s in sampleBooks)
              '${s.title} by ${s.author}. Read by ${s.reader}.',
            'Public domain recordings from LibriVox (librivox.org), '
                'compressed to save space.',
          ].join('\n\n')),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final added = await addSampleBooks(
                  ref.read(bookRepoProvider),
                  again: true);
              ref.invalidate(libraryProvider);
              if (!dialog.mounted) return;
              Navigator.of(dialog).pop();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(added == 0
                    ? 'They are already in your library.'
                    : 'Added to your library.'),
              ));
            },
            child: const Text('Add to library'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, Space.xs, Space.s),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
        ),
      );
}

/// Rows in one hairline card, divided by thin rules.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(indent: Space.l),
              children[i],
            ],
          ],
        ),
      );
}

/// The sign-off at the end of Settings, the same as in the author's other
/// apps: who made it, the version, and what the app does and doesn't do.
class MadeBy extends StatelessWidget {
  const MadeBy({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;
    // Small caps, widely spaced: quiet but still readable (11 sp).
    // Set in Literata, the book face, like the rest of TwoFold's voice:
    // small serif capitals, widely spaced.
    TextStyle? caps(Color c) => theme.textTheme.labelSmall?.copyWith(
      fontFamily: serifFont,
      color: c,
      fontSize: 11.5,
      letterSpacing: 1.8,
      fontWeight: FontWeight.w500,
      height: 1.8,
    );
    return Semantics(
      container: true,
      label: 'Handcrafted by Ornob Aadi. TwoFold version $appVersion. '
          'No account, no ads, no tracking. Online only when you ask.',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.s,
            Space.xl,
            Space.s,
            Space.l,
          ),
          child: Column(
            children: [
              Text('HANDCRAFTED BY', style: caps(muted)),
              const SizedBox(height: Space.s),
              // White ink on transparent, tinted to the page's text colour.
              Image.asset(
                'assets/brand/signature.png',
                height: 48,
                color: ink,
                colorBlendMode: BlendMode.srcIn,
                filterQuality: FilterQuality.medium,
              ),
              const SizedBox(height: Space.m),
              // Shrinks on narrow phones instead of breaking the line.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('TWOFOLD • VERSION $appVersion', style: caps(muted)),
              ),
              // Shrinks on narrow phones instead of breaking the line.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('NO ACCOUNT • NO ADS • NO TRACKING', style: caps(muted)),
              ),
              // Shrinks on narrow phones instead of breaking the line.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('ONLINE ONLY WHEN YOU ASK', style: caps(muted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Space the saved free audiobooks use, under the Wi-Fi switch.
class _SavedSpace extends ConsumerWidget {
  const _SavedSpace();

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<int>(
    future: ref.read(downloadsProvider).savedBytes(),
    builder: (context, snap) {
      final bytes = snap.data ?? 0;
      return Text(
        bytes == 0
            ? 'Mobile data is never used for saving'
            : 'Saved audiobooks use ${formatSize(bytes)}',
      );
    },
  );
}
