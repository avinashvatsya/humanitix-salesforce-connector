/**
 * The single entry point that starts a sync run. Enforces the kill switch and an
 * overlap guard, snapshots settings, creates the run log, and enqueues the first
 * Queueable step. Used by the scheduler, the Flow invocable, and the admin LWC.
 */
public with sharing class HumanitixSyncLauncher {
    public class LaunchException extends Exception {}

    public static Id start(String triggerSource) {
        if (!HumanitixSyncConfig.syncEnabled()) {
            throw new LaunchException('Humanitix sync is disabled (Humanitix Sync Toggle > Sync Enabled).');
        }
        // Overlap guard: don't stack runs. A Running log older than 6h is treated as
        // stale (a crashed run) and does not block.
        if (HumanitixSyncLogService.hasRunningSince(Datetime.now().addHours(-6))) {
            throw new LaunchException('A Humanitix sync is already running.');
        }
        List<String> resources = HumanitixSyncConfig.enabledResources();
        if (resources.isEmpty()) {
            throw new LaunchException('No resources are enabled for sync (Humanitix Sync Setting > Enabled Resources).');
        }

        Datetime runStart = Datetime.now();
        String runId =
            triggerSource + '-' + String.valueOf(runStart.getTime()) + '-' + String.valueOf(Math.abs(Crypto.getRandomLong()));
        Humanitix_Sync_Log__c log = HumanitixSyncLogService.start(runId, triggerSource, String.join(resources, ','));

        HumanitixSyncState st = new HumanitixSyncState();
        st.runId = runId;
        st.logId = log.Id;
        st.triggerSource = triggerSource;
        st.runStart = runStart;
        st.phases = resources;
        st.phaseIndex = 0;
        st.page = 1;
        st.attempt = 0;
        st.pageSize = HumanitixSyncConfig.pageSize();
        st.inFutureOnly = HumanitixSyncConfig.inFutureOnly();
        st.ticketStatusFilter = HumanitixSyncConfig.ticketStatusFilter();
        st.maxRetries = HumanitixSyncConfig.maxRetries();
        st.retryDelayMinutes = HumanitixSyncConfig.retryDelayMinutes();
        st.incremental = HumanitixSyncConfig.incrementalEnabled();
        st.namedCredential = HumanitixSyncConfig.namedCredentialName();

        if (!Test.isRunningTest()) {
            System.enqueueJob(new HumanitixSyncQueueable(st));
        }
        return log.Id;
    }
}
