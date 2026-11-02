import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/player_controller.dart';
import '../../import/importer.dart';
import 'book_card.dart';

final importerProvider = Provider<Importer>(
  (ref) => Importer(ref.watch(bookRepoProvider)),
);

final libraryProvider = FutureProvider<List<LibraryEntry>>((ref) async {
  final repo = ref.watch(bookRepoProvider);
  final books = await repo.allBooks();
  return [
    for (final b in books)
      LibraryEntry(b, await repo.getProgress(b.id), await repo.tracksFor(b.id)),
  ];
});
