/// The base currency the backend's aggregates are written in. It needs no conversion.
const String kBaseCurrency = 'PKR';

/// Whether the dashboard can render totals in [currency] without a conversion.
///
/// `GET /api/dashboard/*` multiplies each aggregate by
/// `COALESCE(exchange_rates->>currency, 1)`, so an empty rate map does not leave the figures
/// unconverted — it silently treats PKR amounts as the base currency. Labelling those with a
/// new symbol would be a lie, so the dashboard waits for a non-empty map instead. PKR is
/// exempt: it is the currency the figures are already in.
bool ratesReadyFor(String currency, Map<String, double>? rates) =>
    currency == kBaseCurrency || (rates?.isNotEmpty ?? false);
