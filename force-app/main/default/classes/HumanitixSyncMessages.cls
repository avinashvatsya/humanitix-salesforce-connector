/**
 * Every admin-facing sentence the connector shows about a sync problem: sync log
 * entries, the run summary, launch errors and the Dashboard readiness checklist.
 * A log message is "<sentence> Details: <raw>", so the sentence reads first and
 * the raw platform or HTTP text stays available for support.
 */
public with sharing class HumanitixSyncMessages {
    public static final String MISSING_KEY = 'No Humanitix API key is saved. Add it on the Connection tab.';
    public static final String DETAIL_SEPARATOR = ' Details: ';
    private static final Integer MAX_BODY = 500;

    /** The platform says "does not exist" when the external credential has no ApiKey parameter yet. */
    public static Boolean isMissingCredential(String platformMessage) {
        return platformMessage != null && platformMessage.contains('does not exist');
    }

    public static String authRejected(Integer status) {
        return 'Humanitix rejected the API key (HTTP ' + status + '). Check the key on the Connection tab and that '
            + 'the user running the sync has the Humanitix Integration Admin permission set.';
    }

    public static String eventNotFound() {
        return 'This event no longer exists in Humanitix and was skipped. Later runs skip it too.';
    }

    public static String busy(Integer status, Integer attempts) {
        return 'Humanitix was busy or unavailable (HTTP ' + status + ') after ' + attempts
            + ' attempts. The next run tries again.';
    }

    public static String unreachable(Integer attempts) {
        return 'Humanitix could not be reached after ' + attempts + ' attempts. The next run tries again.';
    }

    public static String refused(Integer status) {
        return 'Humanitix refused the request (HTTP ' + status + '). Send this log entry to support if it keeps happening.';
    }

    public static String unexpected() {
        return 'Something unexpected went wrong in this step. Send this log entry to support if it keeps happening.';
    }

    /** "HTTP <status>" plus the response body, abbreviated, when there is one. */
    public static String httpDetail(Integer status, String body) {
        String detail = 'HTTP ' + status;
        return String.isBlank(body) ? detail : detail + ': ' + body.abbreviate(MAX_BODY);
    }

    public static String withDetail(String sentence, String raw) {
        return String.isBlank(raw) ? sentence : sentence + DETAIL_SEPARATOR + raw;
    }

    /** The sentence part of a log message (the whole text for messages written before 1.3.1). */
    public static String sentenceOf(String entryMessage) {
        if (entryMessage == null) {
            return null;
        }
        Integer at = entryMessage.indexOf(DETAIL_SEPARATOR);
        return at < 0 ? entryMessage : entryMessage.left(at);
    }
}
