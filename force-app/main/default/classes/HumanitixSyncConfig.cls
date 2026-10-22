/**
 * Typed, null-safe accessor over the connector's runtime configuration:
 * the `Default` Humanitix Sync Setting (CMT) and the Humanitix Sync Toggle
 * hierarchy custom setting (the kill switch).
 */
public with sharing class HumanitixSyncConfig {
    public static final List<String> CANONICAL_ORDER = new List<String>{ 'Tags', 'Events', 'Orders', 'Tickets' };
    public static final String SELECTION_ALL = 'All';
    public static final String SELECTION_FUTURE_ONLY = 'FutureOnly';
    public static final String SELECTION_SELECTED = 'Selected';
    public static final Set<String> EVENT_SELECTIONS = new Set<String>{
        SELECTION_ALL, SELECTION_FUTURE_ONLY, SELECTION_SELECTED
    };

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

    /**
     * Which events the sync handles. A blank (or unknown) Event Selection falls
     * back to the legacy In Future Only checkbox, so orgs upgraded from 1.2
     * behave exactly as before until an admin picks a value.
     */
    public static String eventSelection() {
        String m = cfg().Event_Selection__c;
        if (m != null && EVENT_SELECTIONS.contains(m)) {
            return m;
        }
        return cfg().In_Future_Only__c == true ? SELECTION_FUTURE_ONLY : SELECTION_ALL;
    }

    public static Boolean inFutureOnly() {
        return eventSelection() == SELECTION_FUTURE_ONLY;
    }

    /**
     * Selected Humanitix event ids in saved order. Read with SOQL (not
     * getInstance) so the full Long Text Area value is always returned.
     */
    public static List<String> selectedEventIds() {
        if (overrideSetting != null) {
            return parseIds(overrideSetting.Selected_Event_Ids__c);
        }
        for (Humanitix_Sync_Setting__mdt s : [
            SELECT Selected_Event_Ids__c
            FROM Humanitix_Sync_Setting__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ]) {
            return parseIds(s.Selected_Event_Ids__c);
        }
        return new List<String>();
    }

    /** Comma-separated ids to a trimmed, de-duplicated list in first-seen order. */
    public static List<String> parseIds(String raw) {
        List<String> out = new List<String>();
        if (String.isBlank(raw)) {
            return out;
        }
        Set<String> seen = new Set<String>();
        for (String part : raw.split(',')) {
            String id = part.trim();
            if (String.isNotBlank(id) && seen.add(id)) {
                out.add(id);
            }
        }
        return out;
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
        // Org-level kill switch. getOrgDefaults() returns an empty instance
        // (Id == null) when no toggle record has been saved; checkbox fields on
        // that empty instance read false regardless of the field's declared
        // default, so "no record" must be treated as enabled explicitly.
        // (getInstance() is unsuitable here: it merges levels and returns a
        // null-Id instance even when an org-default record exists.)
        Humanitix_Sync_Toggle__c t = Humanitix_Sync_Toggle__c.getOrgDefaults();
        return t == null || t.Id == null || t.Sync_Enabled__c != false;
    }

    private static Integer intOf(Decimal d, Integer fallback) {
        return d == null ? fallback : (Integer) d;
    }
}
