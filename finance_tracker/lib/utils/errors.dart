import '../services/api_client.dart';

/// Extract a human-readable message from an error object.
///
/// [ApiException]s already carry a clean message; anything else is
/// stringified with the default `Exception: ` prefix stripped.
String errorMessage(Object e) {
  if (e is ApiException) return e.message;
  return e.toString().replaceFirst('Exception: ', '');
}
