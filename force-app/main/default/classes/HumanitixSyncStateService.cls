/**
 * Reads and advances incremental-sync cursors stored in Humanitix_Sync_State__c.
 * A cursor's Last_Successful_Sync is the `since` watermark for the next run and is
 * only promoted after a resource/event completes successfully, so a record changed
 * mid-run is simply re-fetched next time rather than skipped.
 */
public with sharing class HumanitixSyncStateService {
    /** The `since` watermark for a cursor key, or null if never synced. */
    public static Datetime getCursor(String cursorKey) {
        for (Humanitix_Sync_State__c s : [
            SELECT Last_Successful_Sync__c
            FROM Humanitix_Sync_State__c
            WHERE Cursor_Key__c = :cursorKey
            LIMIT 1
        ]) {
            return s.Last_Successful_Sync__c;
        }
        return null;
    }

    /** Promote the watermark for a cursor after a successful pass. */
    public static void promote(String cursorKey, String resource, String eventExtId, String runId, Datetime watermark) {
        Humanitix_Sync_State__c s = new Humanitix_Sync_State__c(
            Name = cursorKey.abbreviate(80),
            Cursor_Key__c = cursorKey,
            Resource__c = resource,
            Event_External_Id__c = eventExtId,
            Last_Successful_Sync__c = watermark,
            Last_Run_Id__c = runId,
            Last_Status__c = 'Success',
            Consecutive_Failures__c = 0
        );
        upsert s Cursor_Key__c;
    }

    /** Record a failure for a cursor WITHOUT moving the watermark. */
    public static void recordFailure(String cursorKey, String resource, String eventExtId, String runId) {
        Decimal current = 0;
        Datetime existingWatermark = null;
        for (Humanitix_Sync_State__c s : [
            SELECT Consecutive_Failures__c, Last_Successful_Sync__c
            FROM Humanitix_Sync_State__c
            WHERE Cursor_Key__c = :cursorKey
            LIMIT 1
        ]) {
            current = s.Consecutive_Failures__c == null ? 0 : s.Consecutive_Failures__c;
            existingWatermark = s.Last_Successful_Sync__c;
        }
        Humanitix_Sync_State__c s = new Humanitix_Sync_State__c(
            Name = cursorKey.abbreviate(80),
            Cursor_Key__c = cursorKey,
            Resource__c = resource,
            Event_External_Id__c = eventExtId,
            Last_Successful_Sync__c = existingWatermark,
            Last_Run_Id__c = runId,
            Last_Status__c = 'Failed',
            Consecutive_Failures__c = current + 1
        );
        upsert s Cursor_Key__c;
    }

    /**
     * Keyset iteration over non-archived events for the Orders/Tickets phases.
     * Pass the last processed Humanitix event id to get the next one (null for the
     * first). Returns null when there are no more events.
     */
    public static String nextEventId(String afterId) {
        List<Humanitix_Event__c> rows;
        if (String.isBlank(afterId)) {
            rows = [
                SELECT Humanitix_Id__c
                FROM Humanitix_Event__c
                WHERE Is_Archived__c = false AND Humanitix_Id__c != null
                ORDER BY Humanitix_Id__c ASC
                LIMIT 1
            ];
        } else {
            rows = [
                SELECT Humanitix_Id__c
                FROM Humanitix_Event__c
                WHERE Is_Archived__c = false AND Humanitix_Id__c != null AND Humanitix_Id__c > :afterId
                ORDER BY Humanitix_Id__c ASC
                LIMIT 1
            ];
        }
        return rows.isEmpty() ? null : rows[0].Humanitix_Id__c;
    }
}
