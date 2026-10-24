/**
 * Creates and maintains the run header (Humanitix_Sync_Log__c) and its per
 * resource/event/page children (Humanitix_Sync_Log_Entry__c), and rolls the
 * children up into the header on finalize.
 */
public with sharing class HumanitixSyncLogService {
    public static final String PARTIAL_SENTENCE = 'Some records could not be saved. Open the run\'s log entries for the row errors.';
    private static final Integer MAX_SUMMARY = 1000;

    public static Humanitix_Sync_Log__c start(String runId, String triggerSource, String resources) {
        Humanitix_Sync_Log__c log = new Humanitix_Sync_Log__c(
            Run_Id__c = runId,
            Trigger_Source__c = triggerSource,
            Status__c = 'Running',
            Started_At__c = Datetime.now(),
            Resources_Requested__c = resources
        );
        insert log;
        return log;
    }

    public static void addEntry(
        Id logId,
        String resource,
        String eventExtId,
        String status,
        Integer processed,
        Integer failed,
        Integer pages,
        Integer httpStatus,
        Integer retryCount,
        String errorMsg
    ) {
        insert new Humanitix_Sync_Log_Entry__c(
            Humanitix_Sync_Log__c = logId,
            Resource__c = resource,
            Event_External_Id__c = eventExtId,
            Status__c = status,
            Records_Processed__c = processed,
            Records_Failed__c = failed,
            Pages__c = pages,
            Http_Status__c = httpStatus,
            Retry_Count__c = retryCount,
            Error_Message__c = errorMsg == null ? null : errorMsg.abbreviate(30000),
            Started_At__c = Datetime.now(),
            Finished_At__c = Datetime.now()
        );
    }

    public static void finalizeRun(Id logId) {
        AggregateResult ar = [
            SELECT SUM(Records_Processed__c) p, SUM(Records_Failed__c) f, SUM(Pages__c) pg,
                SUM(Retry_Count__c) rt, COUNT(Id) c
            FROM Humanitix_Sync_Log_Entry__c
            WHERE Humanitix_Sync_Log__c = :logId
        ];
        Integer totalEntries = (Integer) ar.get('c');
        Integer failedEntries = [
            SELECT COUNT()
            FROM Humanitix_Sync_Log_Entry__c
            WHERE Humanitix_Sync_Log__c = :logId AND Status__c = 'Failed'
        ];
        Integer degradedEntries = [
            SELECT COUNT()
            FROM Humanitix_Sync_Log_Entry__c
            WHERE Humanitix_Sync_Log__c = :logId AND Status__c IN ('Partial', 'Failed')
        ];
        String status;
        if (totalEntries == 0 || (degradedEntries == 0)) {
            status = 'Success';
        } else if (failedEntries == totalEntries) {
            status = 'Failed';
        } else {
            status = 'Partial';
        }
        update new Humanitix_Sync_Log__c(
            Id = logId,
            Status__c = status,
            Finished_At__c = Datetime.now(),
            Total_Records_Processed__c = nz(ar.get('p')),
            Total_Records_Failed__c = nz(ar.get('f')),
            Total_Pages__c = nz(ar.get('pg')),
            Total_Retries__c = nz(ar.get('rt')),
            Total_Errors__c = failedEntries,
            Error_Summary__c = summarize(logId)
        );
    }

    public static Boolean hasRunningSince(Datetime since) {
        return [
            SELECT COUNT()
            FROM Humanitix_Sync_Log__c
            WHERE Status__c = 'Running' AND Started_At__c >= :since
        ] > 0;
    }

    /**
     * Plain-language reason for a degraded run: the distinct sentences of its
     * Failed entries (raw details stripped), one line for row-level errors, and
     * a count of events skipped because Humanitix no longer has them.
     */
    @TestVisible
    private static String summarize(Id logId) {
        List<String> sentences = new List<String>();
        Integer skipped = 0;
        for (Humanitix_Sync_Log_Entry__c e : [
            SELECT Status__c, Error_Message__c
            FROM Humanitix_Sync_Log_Entry__c
            WHERE Humanitix_Sync_Log__c = :logId AND Status__c IN ('Failed', 'Partial', 'Skipped')
            ORDER BY CreatedDate, Id
        ]) {
            if (e.Status__c == 'Skipped') {
                skipped++;
                continue;
            }
            String s = e.Status__c == 'Partial' ? PARTIAL_SENTENCE : HumanitixSyncMessages.sentenceOf(e.Error_Message__c);
            if (String.isBlank(s)) {
                s = 'A step failed.';
            }
            if (!sentences.contains(s)) {
                sentences.add(s);
            }
        }
        if (skipped == 1) {
            sentences.add('1 event no longer exists in Humanitix and was skipped.');
        } else if (skipped > 1) {
            sentences.add(skipped + ' events no longer exist in Humanitix and were skipped.');
        }
        return sentences.isEmpty() ? null : String.join(sentences, ' ').abbreviate(MAX_SUMMARY);
    }

    private static Decimal nz(Object o) {
        return o == null ? 0 : (Decimal) o;
    }
}
