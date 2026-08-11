/**
 * Backs the Schedule tab of the Humanitix Setup console. The desired schedule
 * (delta interval preset + daily full-run time) is stored on the org-default
 * Humanitix Sync Toggle custom setting; the actual schedule is a set of
 * managed CronTriggers this class creates and aborts by exact name. Interval
 * jobs launch forced-delta and the daily job forced-full via the scheduler's
 * mode (manual and Flow runs keep following Since_Mode__c).
 *
 * Sub-hourly intervals need one CronTrigger per fire minute (Apex cron fires
 * at most once per hour per job), hence Humanitix Delta Sync 1..4.
 */
public with sharing class HumanitixScheduleController {
    private static final Set<Integer> INTERVAL_PRESETS = new Set<Integer>{ 15, 30, 60, 120, 240, 360, 720 };
    @TestVisible
    private static final List<String> DELTA_JOB_NAMES = new List<String>{
        'Humanitix Delta Sync 1',
        'Humanitix Delta Sync 2',
        'Humanitix Delta Sync 3',
        'Humanitix Delta Sync 4'
    };
    @TestVisible
    private static final String DAILY_JOB_NAME = 'Humanitix Daily Full Sync';

    public class JobDto {
        @AuraEnabled public String name;
        @AuraEnabled public String cron;
        @AuraEnabled public Datetime nextFireTime;
        @AuraEnabled public String state;
    }

    public class ScheduleDto {
        @AuraEnabled public Integer deltaIntervalMinutes;
        @AuraEnabled public String dailyFullSyncTime;
        @AuraEnabled public List<JobDto> managedJobs;
        @AuraEnabled public List<JobDto> unmanagedJobs;
        @AuraEnabled public Boolean drift;
    }

    private class JobSpec {
        String cron;
        String mode;
        JobSpec(String cron, String mode) {
            this.cron = cron;
            this.mode = mode;
        }
    }

    @AuraEnabled
    public static ScheduleDto getSchedule() {
        try {
            return buildSchedule();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Aborts the managed jobs, recreates them from the requested state, and
     * stores the desired state on the toggle setting. deltaMinutes null or 0
     * means no interval; dailyTime null or blank means no daily run.
     */
    @AuraEnabled
    public static ScheduleDto saveSchedule(Integer deltaMinutes, String dailyTime) {
        Integer interval = deltaMinutes == null || deltaMinutes == 0 ? null : deltaMinutes;
        if (interval != null && !INTERVAL_PRESETS.contains(interval)) {
            throw new AuraHandledException('The delta interval must be 15, 30, 60, 120, 240, 360, or 720 minutes.');
        }
        String timeOfDay = String.isBlank(dailyTime) ? null : dailyTime.trim();
        List<Integer> hourMinute = null;
        if (timeOfDay != null) {
            hourMinute = parseTime(timeOfDay);
            if (hourMinute == null) {
                throw new AuraHandledException('The daily run time must use 24 hour HH:mm format, for example 02:05.');
            }
        }
        try {
            abortManagedJobs();
            Map<String, JobSpec> desired = desiredJobs(interval, hourMinute);
            for (String name : desired.keySet()) {
                HumanitixSyncScheduler.schedule(name, desired.get(name).cron, desired.get(name).mode);
            }
            saveDesiredState(interval, timeOfDay);
            return buildSchedule();
        } catch (Exception e) {
            throw new AuraHandledException('The schedule could not be saved: ' + e.getMessage());
        }
    }

    private static ScheduleDto buildSchedule() {
        ScheduleDto dto = new ScheduleDto();
        Humanitix_Sync_Toggle__c toggle = Humanitix_Sync_Toggle__c.getOrgDefaults();
        dto.deltaIntervalMinutes = toggle == null || toggle.Delta_Interval_Minutes__c == null
            ? null
            : Integer.valueOf(toggle.Delta_Interval_Minutes__c);
        dto.dailyFullSyncTime = toggle == null || String.isBlank(toggle.Daily_Full_Sync_Time__c)
            ? null
            : toggle.Daily_Full_Sync_Time__c;
        dto.managedJobs = new List<JobDto>();
        dto.unmanagedJobs = new List<JobDto>();

        Set<String> managedNames = new Set<String>(DELTA_JOB_NAMES);
        managedNames.add(DAILY_JOB_NAME);
        Map<String, String> actualCrons = new Map<String, String>();
        for (CronTrigger ct : [
            SELECT Id, CronExpression, NextFireTime, State, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Humanitix%' AND State != 'DELETED'
            ORDER BY CronJobDetail.Name
        ]) {
            JobDto job = new JobDto();
            job.name = ct.CronJobDetail.Name;
            job.cron = ct.CronExpression;
            job.nextFireTime = ct.NextFireTime;
            job.state = ct.State;
            if (managedNames.contains(job.name)) {
                dto.managedJobs.add(job);
                actualCrons.put(job.name, job.cron);
            } else {
                dto.unmanagedJobs.add(job);
            }
        }

        Map<String, JobSpec> desired = desiredJobs(
            dto.deltaIntervalMinutes,
            dto.dailyFullSyncTime == null ? null : parseTime(dto.dailyFullSyncTime)
        );
        Map<String, String> desiredCrons = new Map<String, String>();
        for (String name : desired.keySet()) {
            desiredCrons.put(name, desired.get(name).cron);
        }
        dto.drift = !desiredCrons.equals(actualCrons);
        return dto;
    }

    /** Managed job names to cron + run mode for the requested state. */
    private static Map<String, JobSpec> desiredJobs(Integer interval, List<Integer> dailyHourMinute) {
        Map<String, JobSpec> jobs = new Map<String, JobSpec>();
        if (interval != null) {
            if (interval < 60) {
                Integer perHour = 60 / interval;
                for (Integer i = 0; i < perHour; i++) {
                    jobs.put(
                        DELTA_JOB_NAMES[i],
                        new JobSpec('0 ' + String.valueOf(i * interval) + ' * * * ?', HumanitixSyncLauncher.MODE_DELTA)
                    );
                }
            } else if (interval == 60) {
                jobs.put(DELTA_JOB_NAMES[0], new JobSpec('0 0 * * * ?', HumanitixSyncLauncher.MODE_DELTA));
            } else {
                jobs.put(
                    DELTA_JOB_NAMES[0],
                    new JobSpec('0 0 0/' + String.valueOf(interval / 60) + ' * * ?', HumanitixSyncLauncher.MODE_DELTA)
                );
            }
        }
        if (dailyHourMinute != null) {
            jobs.put(
                DAILY_JOB_NAME,
                new JobSpec(
                    '0 ' + String.valueOf(dailyHourMinute[1]) + ' ' + String.valueOf(dailyHourMinute[0]) + ' * * ?',
                    HumanitixSyncLauncher.MODE_FULL
                )
            );
        }
        return jobs;
    }

    private static void abortManagedJobs() {
        Set<String> managedNames = new Set<String>(DELTA_JOB_NAMES);
        managedNames.add(DAILY_JOB_NAME);
        for (CronTrigger ct : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name IN :managedNames
        ]) {
            System.abortJob(ct.Id);
        }
    }

    private static void saveDesiredState(Integer interval, String timeOfDay) {
        Humanitix_Sync_Toggle__c toggle = Humanitix_Sync_Toggle__c.getOrgDefaults();
        if (toggle == null || toggle.Id == null) {
            toggle = new Humanitix_Sync_Toggle__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        toggle.Delta_Interval_Minutes__c = interval;
        toggle.Daily_Full_Sync_Time__c = timeOfDay;
        upsert toggle;
    }

    /** Returns {hour, minute} for 24h "H:mm"/"HH:mm" input, or null when invalid. */
    @TestVisible
    private static List<Integer> parseTime(String value) {
        if (value == null || !Pattern.matches('^([01]?\\d|2[0-3]):([0-5]\\d)$', value.trim())) {
            return null;
        }
        List<String> parts = value.trim().split(':');
        return new List<Integer>{ Integer.valueOf(parts[0]), Integer.valueOf(parts[1]) };
    }
}
