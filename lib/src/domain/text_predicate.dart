/// A question about a piece of text.
library;

/// A pattern of the configuration, reduced to the one question a check asks
/// of it: does this text match?
///
/// `stagelatch.yaml` holds globs (a branch such as `release/*`, a path such
/// as `assets/videos/**`). Checks may not depend on the glob package, so the
/// configuration loader hands them these instead.
typedef TextPredicate = bool Function(String text);
