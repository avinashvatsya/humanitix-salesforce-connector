/**
 * Schedulable entry point for recurring syncs. Each fire launches a run;
 * overlap/disabled conditions are swallowed so a skipped fire is not treated
 * as a job failure.
 *
 * The optional mode (HumanitixSyncLauncher.MODE_FULL / MODE_DELTA) is
 * serialized with the job when it is scheduled: the Schedule tab creates
 * interval jobs as Delta and the daily job as Full. Jobs scheduled before the
 * mode existed (or via the no-arg path) deserialize with a null mode and keep
 * following Since_Mode__c, exactly as before.
 *
 * Example (daily at 02:00):
 *   HumanitixSyncScheduler.schedule('Humanitix Nightly Sync', '0 0 2 * * ?');
 */
public with sharing class HumanitixSyncScheduler implements Schedulable {
    @TestVisible
    private String mode;

    public HumanitixSyncScheduler() {
        this(null);
    }

    public HumanitixSyncScheduler(String mode) {
        this.mode = mode;
    }

    public void execute(SchedulableContext ctx) {
        try {
            HumanitixSyncLauncher.start('Scheduled', mode);
        } catch (HumanitixSyncLauncher.LaunchException e) {
            // disabled or already running — not an error for a scheduled fire
            System.debug(LoggingLevel.INFO, 'Humanitix scheduled sync skipped: ' + e.getMessage());
        }
    }

    public static Id schedule(String jobName, String cronExpression) {
        return schedule(jobName, cronExpression, null);
    }

    public static Id schedule(String jobName, String cronExpression, String mode) {
        return System.schedule(jobName, cronExpression, new HumanitixSyncScheduler(mode));
    }
}
