/**
 * Classifies Humanitix HTTP responses and decides retry timing. Queueables cannot
 * sleep, so a retry is always a RE-ENQUEUE with a whole-minute delay (never an
 * in-place loop). 429 and 5xx/408 are retryable; other 4xx are fatal.
 */
public with sharing class HumanitixRetryPolicy {
    public enum Outcome { SUCCESS, RETRY, FATAL }

    public static Outcome classify(Integer statusCode) {
        if (statusCode == null) {
            return Outcome.RETRY; // e.g. a callout exception surfaced as no status
        }
        if (statusCode >= 200 && statusCode < 300) {
            return Outcome.SUCCESS;
        }
        if (statusCode == 429 || statusCode == 408 || statusCode >= 500) {
            return Outcome.RETRY;
        }
        return Outcome.FATAL;
    }

    public static Boolean isRetryable(Integer statusCode) {
        return classify(statusCode) == Outcome.RETRY;
    }

    public static Boolean isSuccess(Integer statusCode) {
        return classify(statusCode) == Outcome.SUCCESS;
    }

    /**
     * Whole-minute delay before re-enqueue. Honors a numeric Retry-After (seconds,
     * rounded up to minutes) when present; otherwise a capped linear backoff on the
     * configured base delay. Result is clamped to [1, 10] minutes — the practical
     * range for Queueable minimum-delay scheduling.
     */
    public static Integer delayMinutes(Integer attempt, Integer baseMinutes, String retryAfterHeader) {
        Integer fromHeader = retryAfterToMinutes(retryAfterHeader);
        if (fromHeader != null) {
            return clamp(fromHeader);
        }
        Integer base = (baseMinutes == null || baseMinutes < 1) ? 1 : baseMinutes;
        Integer att = (attempt == null || attempt < 1) ? 1 : attempt;
        return clamp(base * att);
    }

    @TestVisible
    private static Integer retryAfterToMinutes(String header) {
        if (String.isBlank(header)) {
            return null;
        }
        try {
            Integer seconds = Integer.valueOf(header.trim());
            if (seconds <= 0) {
                return 1;
            }
            return (Integer) Math.ceil(seconds / 60.0);
        } catch (Exception e) {
            return null; // HTTP-date form not supported; fall back to backoff
        }
    }

    private static Integer clamp(Integer minutes) {
        if (minutes < 1) {
            return 1;
        }
        if (minutes > 10) {
            return 10;
        }
        return minutes;
    }
}
