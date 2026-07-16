/**
 * Schedulable entry point for recurring syncs. Schedule with a cron expression;
 * each fire launches a run. Overlap/disabled conditions are swallowed so a skipped
 * fire is not treated as a job failure.
 *
 * Example (daily at 02:00):
 *   HumanitixSyncScheduler.schedule('Humanitix Nightly Sync', '0 0 2 * * ?');
 */
public with sharing class HumanitixSyncScheduler implements Schedulable {
    public void execute(SchedulableContext ctx) {
        try {
            HumanitixSyncLauncher.start('Scheduled');
        } catch (HumanitixSyncLauncher.LaunchException e) {
            // disabled or already running — not an error for a scheduled fire
            System.debug(LoggingLevel.INFO, 'Humanitix scheduled sync skipped: ' + e.getMessage());
        }
    }

    public static Id schedule(String jobName, String cronExpression) {
        return System.schedule(jobName, cronExpression, new HumanitixSyncScheduler());
    }
}
