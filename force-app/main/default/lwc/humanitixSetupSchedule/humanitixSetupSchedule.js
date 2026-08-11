import { LightningElement } from 'lwc';
import { errorMessage, showToast } from 'c/humanitixSetupUtils';
import getSchedule from '@salesforce/apex/HumanitixScheduleController.getSchedule';
import saveSchedule from '@salesforce/apex/HumanitixScheduleController.saveSchedule';

const INTERVAL_OPTIONS = [
  { label: 'Off', value: '0' },
  { label: 'Every 15 minutes', value: '15' },
  { label: 'Every 30 minutes', value: '30' },
  { label: 'Every hour', value: '60' },
  { label: 'Every 2 hours', value: '120' },
  { label: 'Every 4 hours', value: '240' },
  { label: 'Every 6 hours', value: '360' },
  { label: 'Every 12 hours', value: '720' }
];

const COLUMNS = [
  { label: 'Job', fieldName: 'name' },
  { label: 'Cron', fieldName: 'cron' },
  {
    label: 'Next run',
    fieldName: 'nextFireTime',
    type: 'date',
    typeAttributes: {
      year: 'numeric',
      month: 'short',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit'
    }
  },
  { label: 'State', fieldName: 'state' }
];

const SAVED = 'The scheduled jobs now match the schedule on this page.';
const NOTIFICATION_BASE = 'slds-scoped-notification slds-media slds-media_center';

/**
 * lightning-input type="time" hands back 'HH:mm:ss.SSS' in some browsers, but
 * the controller only accepts 'HH:mm'. An empty box means "no daily run".
 */
function normalizeTime(value) {
  if (value === null || value === undefined) {
    return null;
  }
  const trimmed = String(value).trim();
  return trimmed.length === 0 ? null : trimmed.slice(0, 5);
}

/**
 * Schedule tab: edits the delta sync interval and the daily full sync time.
 * Saving hands both values to the controller, which aborts and recreates the
 * managed cron jobs, so the table below always shows what the org will really
 * run. Sub-hourly intervals become several jobs, which is why the interval is
 * a preset list rather than a free number.
 */
export default class HumanitixSetupSchedule extends LightningElement {
  intervalOptions = INTERVAL_OPTIONS;
  columns = COLUMNS;

  isLoading = true;
  isSaving = false;
  deltaValue = '0';
  dailyTime = '';
  managedJobs = [];
  unmanagedJobs = [];
  drift = false;

  connectedCallback() {
    this.load();
  }

  /** The combobox works in strings; the controller wants a number or null. */
  get selectedIntervalMinutes() {
    const parsed = parseInt(this.deltaValue, 10);
    return isNaN(parsed) || parsed === 0 ? null : parsed;
  }

  get normalizedDailyTime() {
    return normalizeTime(this.dailyTime);
  }

  get hasManagedJobs() {
    return Array.isArray(this.managedJobs) && this.managedJobs.length > 0;
  }

  get hasUnmanagedJobs() {
    return Array.isArray(this.unmanagedJobs) && this.unmanagedJobs.length > 0;
  }

  /**
   * Both runs firing on the same minute means one of them is skipped, so warn
   * before the save rather than after. Sub-hourly intervals fire every N
   * minutes from minute 0; hourly and slower intervals only fire on minute 0.
   */
  get showCollisionWarning() {
    const interval = this.selectedIntervalMinutes;
    const time = this.normalizedDailyTime;
    if (!interval || !time) {
      return false;
    }
    const parts = time.split(':');
    const minute = parts.length > 1 ? parseInt(parts[1], 10) : NaN;
    if (isNaN(minute)) {
      return false;
    }
    return minute % (interval < 60 ? interval : 60) === 0;
  }

  get driftClass() {
    return NOTIFICATION_BASE + ' slds-theme_warning slds-m-bottom_medium';
  }

  get collisionClass() {
    return NOTIFICATION_BASE + ' slds-theme_warning slds-m-top_small';
  }

  get unmanagedClass() {
    return NOTIFICATION_BASE + ' slds-theme_info slds-m-top_medium';
  }

  async load() {
    this.isLoading = true;
    try {
      this.applySchedule(await getSchedule());
    } catch (error) {
      showToast(this, 'Could not load the schedule', errorMessage(error), 'error');
    } finally {
      this.isLoading = false;
    }
  }

  applySchedule(dto) {
    const schedule = dto || {};
    const interval = schedule.deltaIntervalMinutes;
    this.deltaValue = interval === null || interval === undefined ? '0' : String(interval);
    this.dailyTime = schedule.dailyFullSyncTime || '';
    this.managedJobs = Array.isArray(schedule.managedJobs) ? schedule.managedJobs : [];
    this.unmanagedJobs = Array.isArray(schedule.unmanagedJobs) ? schedule.unmanagedJobs : [];
    this.drift = schedule.drift === true;
  }

  handleIntervalChange(event) {
    this.deltaValue = event.detail ? event.detail.value : event.target.value;
  }

  handleDailyTimeChange(event) {
    // Kept raw so the input keeps whatever precision the browser gave it; the
    // value is only trimmed to HH:mm on the way to Apex.
    this.dailyTime = event.target.value || '';
  }

  handleSave() {
    return this.save();
  }

  // Repairing is the same save with the values already on screen.
  handleRepair() {
    return this.save();
  }

  async save() {
    this.isSaving = true;
    try {
      const dto = await saveSchedule({
        deltaMinutes: this.selectedIntervalMinutes,
        dailyTime: this.normalizedDailyTime
      });
      this.applySchedule(dto);
      showToast(this, 'Schedule saved', SAVED, 'success');
    } catch (error) {
      showToast(this, 'Could not save the schedule', errorMessage(error), 'error');
    } finally {
      this.isSaving = false;
    }
  }
}
