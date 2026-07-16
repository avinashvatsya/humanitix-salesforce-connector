/**
 * Thrown for non-retryable Humanitix API problems (e.g. 4xx other than 429,
 * or an exhausted retry budget). Retryable conditions are handled by
 * HumanitixRetryPolicy without raising this.
 */
public with sharing class HumanitixApiException extends Exception {}
