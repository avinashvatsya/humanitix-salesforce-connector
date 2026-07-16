/**
 * Creates and maintains the run header (Humanitix_Sync_Log__c) and its per
 * resource/event/page children (Humanitix_Sync_Log_Entry__c), and rolls the
 * children up into the header on finalize.
 */
public with sharing class HumanitixSyncLogService {
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
            Total_Errors__c = failedEntries
        );
    }

    public static Boolean hasRunningSince(Datetime since) {
        return [
            SELECT COUNT()
            FROM Humanitix_Sync_Log__c
            WHERE Status__c = 'Running' AND Started_At__c >= :since
        ] > 0;
    }

    private static Decimal nz(Object o) {
        return o == null ? 0 : (Decimal) o;
    }
}
