/**
 * Typed, null-safe accessor over the connector's runtime configuration:
 * the `Default` Humanitix Sync Setting (CMT) and the Humanitix Sync Toggle
 * hierarchy custom setting (the kill switch).
 */
public with sharing class HumanitixSyncConfig {
    public static final List<String> CANONICAL_ORDER = new List<String>{ 'Tags', 'Events', 'Orders', 'Tickets' };

    @TestVisible
    private static Humanitix_Sync_Setting__mdt overrideSetting;

    private static Humanitix_Sync_Setting__mdt cfg() {
        if (overrideSetting != null) {
            return overrideSetting;
        }
        Humanitix_Sync_Setting__mdt s = Humanitix_Sync_Setting__mdt.getInstance('Default');
        return s == null ? new Humanitix_Sync_Setting__mdt() : s;
    }

    public static Integer pageSize() {
        return intOf(cfg().Page_Size__c, 100);
    }

    public static List<String> enabledResources() {
        String raw = cfg().Enabled_Resources__c;
        if (String.isBlank(raw)) {
            return new List<String>(CANONICAL_ORDER);
        }
        Set<String> requested = new Set<String>();
        for (String s : raw.split(',')) {
            if (String.isNotBlank(s)) {
                requested.add(s.trim());
            }
        }
        // return in canonical processing order (Tags, Events, Orders, Tickets)
        List<String> ordered = new List<String>();
        for (String r : CANONICAL_ORDER) {
            if (requested.contains(r)) {
                ordered.add(r);
            }
        }
        return ordered;
    }

    public static Boolean inFutureOnly() {
        return cfg().In_Future_Only__c == true;
    }

    public static String ticketStatusFilter() {
        return cfg().Ticket_Status_Filter__c;
    }

    public static Integer maxRetries() {
        return intOf(cfg().Max_Retries__c, 5);
    }

    public static Integer retryDelayMinutes() {
        return intOf(cfg().Retry_Delay_Minutes__c, 5);
    }

    public static String sinceMode() {
        String m = cfg().Since_Mode__c;
        return String.isBlank(m) ? 'Modified' : m;
    }

    public static Boolean incrementalEnabled() {
        return sinceMode() == 'Modified';
    }

    public static String namedCredentialName() {
        String n = cfg().Named_Credential_Name__c;
        return String.isBlank(n) ? 'HumanitixAPI' : n;
    }

    public static Integer consecutiveFailureThreshold() {
        return intOf(cfg().Consecutive_Failure_Threshold__c, 5);
    }

    public static Boolean syncEnabled() {
        Humanitix_Sync_Toggle__c t = Humanitix_Sync_Toggle__c.getInstance();
        // Hierarchy custom setting defaults Sync_Enabled__c to true when no record exists.
        return t == null || t.Sync_Enabled__c != false;
    }

    private static Integer intOf(Decimal d, Integer fallback) {
        return d == null ? fallback : (Integer) d;
    }
}
