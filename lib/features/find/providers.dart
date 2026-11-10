import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../find/find_service.dart';

/// The one place TwoFold uses the internet. Tests replace it.
final findServiceProvider = Provider<FindService>((ref) {
  final service = FindService();
  ref.onDispose(service.web.close);
  return service;
});
