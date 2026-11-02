import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings.dart';
import '../../app/theme.dart';
import 'settings_sheet.dart';

const appVersion = '0.1.0-beta';

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
          const _Heading('Colour'),
          const PaletteChooser(),
          const _Heading('Background'),
          const ThemeChooser(),
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
              const ListTile(
                title: Text('Your books stay on this phone'),
                subtitle: Text(
                  'TwoFold has no account and no internet access.',
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
              const ListTile(
                title: Text('Version'),
                trailing: Text(appVersion),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.xs, Space.xl, Space.xs, Space.s),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// Rows joined into one card: large outer corners, thin gaps between.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(Space.xl),
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: children[i],
            ),
          ),
      ],
    ),
  );
}
