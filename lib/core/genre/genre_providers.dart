import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../genre/genre_enrichment_service.dart';

/// Public access to the shared [GenreEnrichmentService] instance.
///
/// Tests can override this with a service built from a fake [http.Client].
final genreEnrichmentServiceProvider = Provider<GenreEnrichmentService>(
  (ref) => GenreEnrichmentService(),
);
