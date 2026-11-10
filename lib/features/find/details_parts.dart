import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../find/book_info.dart';

/// Small capitals heading used in book details.
TextStyle? overline(ThemeData theme) => theme.textTheme.labelMedium?.copyWith(
  letterSpacing: 1.2,
  fontWeight: FontWeight.w600,
);

class Stars extends StatelessWidget {
  const Stars(this.rating, {super.key});

  final double rating;
  static const size = 16.0;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(
              rating >= i
                  ? Icons.star_rounded
                  : rating >= i - 0.5
                  ? Icons.star_half_rounded
                  : Icons.star_outline_rounded,
              size: size,
              color: c,
            ),
        ],
      ),
    );
  }
}

/// Stars, the average, how many rated, and how many want to read it.
class RatingLine extends StatelessWidget {
  const RatingLine({
    super.key,
    required this.rating,
    required this.count,
    required this.wantToRead,
    this.empty = 'No ratings yet',
  });

  final double? rating;
  final int count;
  final int wantToRead;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = rating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (r != null)
          Semantics(
            label:
                'Rated ${r.toStringAsFixed(1)} out of 5 by $count Open Library readers',
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.xs,
              children: [
                Stars(r),
                Text(r.toStringAsFixed(1), style: theme.textTheme.titleSmall),
                Text(
                  '(${groupDigits(count)})',
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
          )
        else
          Text(empty, style: theme.textTheme.labelMedium),
        if (wantToRead > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${groupDigits(wantToRead)} want to read it',
              style: theme.textTheme.labelMedium,
            ),
          ),
      ],
    );
  }
}

/// Facts as a quiet two-column table in a hairline card.
class FactsCard extends StatelessWidget {
  const FactsCard(this.facts, {super.key});

  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.twofold;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.l,
          vertical: Space.s,
        ),
        child: Column(
          children: [
            for (final (i, (k, v)) in facts.indexed) ...[
              if (i > 0) const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        k,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: c.muted,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        v,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ABOUT heading and the description, six lines with Read more.
class AboutText extends StatefulWidget {
  const AboutText(this.text, {super.key});

  final String text;

  @override
  State<AboutText> createState() => _AboutTextState();
}

class _AboutTextState extends State<AboutText> {
  bool _more = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ABOUT', style: overline(theme)),
        const SizedBox(height: Space.s),
        Text(
          widget.text,
          maxLines: _more ? null : 6,
          overflow: _more ? null : TextOverflow.fade,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontFamily: serifFont,
            height: 1.5,
          ),
        ),
        if (widget.text.length > 320)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _more = !_more),
              child: Text(_more ? 'Show less' : 'Read more'),
            ),
          ),
      ],
    );
  }
}

/// SUBJECTS heading and outlined tags.
class SubjectTags extends StatelessWidget {
  const SubjectTags(this.subjects, {super.key});

  final List<String> subjects;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SUBJECTS', style: overline(theme)),
        const SizedBox(height: Space.s),
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          children: [
            for (final s in subjects)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s,
                  vertical: Space.xs,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(s, style: theme.textTheme.labelMedium),
              ),
          ],
        ),
      ],
    );
  }
}

const openLibraryNote =
    'Rating and details from Open Library, matched by title and author, '
    'so they may describe another edition.';
