import 'package:flutter/material.dart';

import '../data/models.dart';
import 'home_shell.dart';
import '../features/find/find_screen.dart';
import '../features/library/book_details_screen.dart';
import '../features/library/new_book_screen.dart';
import '../features/listen/listen_screen.dart';
import '../features/reader/reader_screen.dart';
import '../features/settings/settings_screen.dart';

/// A short rise and fade. Instant when the system asks for no animation.
Route<T> fadeRoute<T>(Widget page, {bool instant = false}) => PageRouteBuilder<T>(
      transitionDuration:
          instant ? Duration.zero : const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (context, animation, _, child) {
        if (MediaQuery.disableAnimationsOf(context)) return child;
        final eased =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: eased,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.03), end: Offset.zero)
                .animate(eased),
            child: child,
          ),
        );
      },
    );

Future<void> openReader(BuildContext context, Book book, {bool instant = false}) =>
    Navigator.of(context).push(fadeRoute(ReaderScreen(book: book), instant: instant));

Future<void> openListen(BuildContext context, Book book, {bool fromReader = false}) =>
    Navigator.of(context).push(fadeRoute(ListenScreen(book: book, fromReader: fromReader)));

/// Returns the new book, if one was added and should open.
Future<Book?> openNewBook(BuildContext context) =>
    Navigator.of(context).push<Book>(fadeRoute(const NewBookScreen()));

Future<void> openEditBook(BuildContext context, Book book) =>
    Navigator.of(context).push(fadeRoute(NewBookScreen(editing: book)));

Future<void> openBookDetails(BuildContext context, Book book) =>
    Navigator.of(context).push(fadeRoute(BookDetailsScreen(bookId: book.id)));

Future<void> openFind(BuildContext context) =>
    Navigator.of(context).push(fadeRoute(const FindScreen()));

Future<void> openSettings(BuildContext context) =>
    Navigator.of(context).push(fadeRoute(const SettingsScreen()));

Widget homeScreen({String? resumeBookId}) =>
    HomeShell(resumeBookId: resumeBookId);
