@IsTest
private class HumanitixScheduleControllerTest {
    private static Integer managedJobCount() {
        Set<String> names = new Set<String>(HumanitixScheduleController.DELTA_JOB_NAMES);
        names.add(HumanitixScheduleController.DAILY_JOB_NAME);
        return [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name IN :names];
    }

    @IsTest
    static void fifteenMinutePresetCreatesFourDeltaJobsPlusDaily() {
        HumanitixScheduleController.ScheduleDto dto = HumanitixScheduleController.saveSchedule(15, '02:05');

        System.assertEquals(5, dto.managedJobs.size());
        Map<String, String> cronsByName = new Map<String, String>();
        for (HumanitixScheduleController.JobDto job : dto.managedJobs) {
            cronsByName.put(job.name, job.cron);
        }
        System.assertEquals('0 0 * * * ?', cronsByName.get('Humanitix Delta Sync 1'));
        System.assertEquals('0 15 * * * ?', cronsByName.get('Humanitix Delta Sync 2'));
        System.assertEquals('0 30 * * * ?', cronsByName.get('Humanitix Delta Sync 3'));
        System.assertEquals('0 45 * * * ?', cronsByName.get('Humanitix Delta Sync 4'));
        System.assertEquals('0 5 2 * * ?', cronsByName.get('Humanitix Daily Full Sync'));
        System.assertEquals(false, dto.drift, 'Fresh save must not drift');

        Humanitix_Sync_Toggle__c toggle = Humanitix_Sync_Toggle__c.getOrgDefaults();
        System.assertEquals(15, toggle.Delta_Interval_Minutes__c);
        System.assertEquals('02:05', toggle.Daily_Full_Sync_Time__c);
    }

    @IsTest
    static void savingANewPresetReplacesTheOldJobs() {
        HumanitixScheduleController.saveSchedule(15, null);
        System.assertEquals(4, managedJobCount());

        HumanitixScheduleController.ScheduleDto dto = HumanitixScheduleController.saveSchedule(120, '01:30');

        System.assertEquals(2, managedJobCount(), 'Old delta jobs must be aborted');
        Map<String, String> cronsByName = new Map<String, String>();
        for (HumanitixScheduleController.JobDto job : dto.managedJobs) {
            cronsByName.put(job.name, job.cron);
        }
        System.assertEquals('0 0 0/2 * * ?', cronsByName.get('Humanitix Delta Sync 1'));
        System.assertEquals('0 30 1 * * ?', cronsByName.get('Humanitix Daily Full Sync'));
    }

    @IsTest
    static void offRemovesAllManagedJobs() {
        HumanitixScheduleController.saveSchedule(30, '03:00');
        System.assertEquals(3, managedJobCount());

        HumanitixScheduleController.ScheduleDto dto = HumanitixScheduleController.saveSchedule(null, null);

        System.assertEquals(0, managedJobCount());
        System.assertEquals(0, dto.managedJobs.size());
        System.assertEquals(null, dto.deltaIntervalMinutes);
        System.assertEquals(null, dto.dailyFullSyncTime);
        System.assertEquals(false, dto.drift);
    }

    @IsTest
    static void rejectsNonPresetIntervalAndBadTime() {
        Boolean threwInterval = false;
        try {
            HumanitixScheduleController.saveSchedule(45, null);
        } catch (AuraHandledException e) {
            threwInterval = true;
        }
        System.assert(threwInterval, '45 is not a preset');

        Boolean threwTime = false;
        try {
            HumanitixScheduleController.saveSchedule(60, '25:00');
        } catch (AuraHandledException e) {
            threwTime = true;
        }
        System.assert(threwTime, '25:00 is not a valid time');
        System.assertEquals(0, managedJobCount(), 'Nothing may be scheduled on validation failure');
    }

    @IsTest
    static void parseTimeAcceptsSingleDigitHourOnly() {
        System.assertEquals(new List<Integer>{ 2, 5 }, HumanitixScheduleController.parseTime('2:05'));
        System.assertEquals(new List<Integer>{ 23, 59 }, HumanitixScheduleController.parseTime('23:59'));
        System.assertEquals(null, HumanitixScheduleController.parseTime('24:00'));
        System.assertEquals(null, HumanitixScheduleController.parseTime('2:5'));
        System.assertEquals(null, HumanitixScheduleController.parseTime('nope'));
    }

    @IsTest
    static void driftIsReportedWhenAManagedJobDisappears() {
        HumanitixScheduleController.saveSchedule(60, null);
        for (CronTrigger ct : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = 'Humanitix Delta Sync 1'
        ]) {
            System.abortJob(ct.Id);
        }

        HumanitixScheduleController.ScheduleDto dto = HumanitixScheduleController.getSchedule();

        System.assertEquals(true, dto.drift, 'Stored interval with no matching job is drift');
    }

    @IsTest
    static void unmanagedHumanitixJobsAreListedSeparately() {
        HumanitixSyncScheduler.schedule('Humanitix Nightly Sync', '0 0 2 * * ?');

        HumanitixScheduleController.ScheduleDto dto = HumanitixScheduleController.getSchedule();

        System.assertEquals(1, dto.unmanagedJobs.size());
        System.assertEquals('Humanitix Nightly Sync', dto.unmanagedJobs[0].name);
        System.assertEquals(0, dto.managedJobs.size());
    }
}
