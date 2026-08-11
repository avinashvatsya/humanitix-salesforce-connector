import { LightningElement } from 'lwc';
import { errorMessage, showToast, pollDeploy } from 'c/humanitixSetupUtils';
import getSyncSettings from '@salesforce/apex/HumanitixSyncSettingsController.getSyncSettings';
import saveSyncSettings from '@salesforce/apex/HumanitixSyncSettingsController.saveSyncSettings';
import getSyncEnabled from '@salesforce/apex/HumanitixSyncSettingsController.getSyncEnabled';
import setSyncEnabled from '@salesforce/apex/HumanitixSyncSettingsController.setSyncEnabled';
import getDeployStatus from '@salesforce/apex/HumanitixMetadataWriter.getDeployStatus';

const RESOURCE_OPTIONS = [
  { label: 'Tags', value: 'Tags' },
  { label: 'Events', value: 'Events' },
  { label: 'Orders', value: 'Orders' },
  { label: 'Tickets', value: 'Tickets' }
];

const SINCE_MODE_OPTIONS = [
  { label: 'Modified (incremental sync)', value: 'Modified' },
  { label: 'FullPull (fetch everything each run)', value: 'FullPull' }
];

const DEPLOYING = 'Saving settings. Custom metadata deploys take a few seconds.';
const SAVED = 'The sync settings have been updated.';
const STILL_DEPLOYING =
  'The deployment is taking longer than expected. Check Setup, Deployment Status.';
const DEPLOY_FAILED = 'The settings deployment did not complete. Check Setup, Deployment Status.';
const NOTIFICATION_BASE = 'slds-scoped-notification slds-media slds-media_center';

/** Number inputs hand back strings; an empty box means "no value", not zero. */
function toInt(value) {
  if (value === '' || value === null || value === undefined) {
    return null;
  }
  const parsed = parseInt(value, 10);
  return isNaN(parsed) ? null : parsed;
}

function blankToNull(value) {
  return value && value.trim().length > 0 ? value.trim() : null;
}

/**
 * Sync Settings tab: edits the Default Humanitix Sync Setting record. Saving is
 * an async custom metadata deploy, so the save resolves a job id that this
 * component polls to completion. The Sync Enabled kill switch is separate and
 * takes effect immediately.
 */
export default class HumanitixSetupSyncSettings extends LightningElement {
  resourceOptions = RESOURCE_OPTIONS;
  sinceModeOptions = SINCE_MODE_OPTIONS;
  pollOptions = { intervalMs: 2000, timeoutMs: 120000 };

  isLoading = true;
  isSaving = false;
  syncEnabled = false;
  recordExists = true;
  deployStatus;
  deployError;

  pageSize;
  enabledResources = [];
  inFutureOnly = false;
  ticketStatusFilter = '';
  maxRetries;
  retryDelayMinutes;
  sinceMode = 'Modified';
  namedCredentialName = '';

  connectedCallback() {
    this.load();
  }

  get showNewRecordBanner() {
    return this.recordExists === false;
  }

  get hasDeployError() {
    return !!this.deployError;
  }

  get deployErrorClass() {
    return NOTIFICATION_BASE + ' slds-theme_error slds-m-top_medium';
  }

  get bannerClass() {
    return NOTIFICATION_BASE + ' slds-theme_info slds-m-bottom_medium';
  }

  async load() {
    this.isLoading = true;
    try {
      await Promise.all([this.loadSettings(), this.loadSyncEnabled()]);
    } finally {
      this.isLoading = false;
    }
  }

  async loadSettings() {
    try {
      const settings = (await getSyncSettings()) || {};
      this.pageSize = settings.pageSize;
      this.enabledResources = Array.isArray(settings.enabledResources)
        ? [...settings.enabledResources]
        : [];
      this.inFutureOnly = settings.inFutureOnly === true;
      this.ticketStatusFilter = settings.ticketStatusFilter || '';
      this.maxRetries = settings.maxRetries;
      this.retryDelayMinutes = settings.retryDelayMinutes;
      this.sinceMode = settings.sinceMode || 'Modified';
      this.namedCredentialName = settings.namedCredentialName || '';
      this.recordExists = settings.recordExists === true;
    } catch (error) {
      showToast(this, 'Could not load the settings', errorMessage(error), 'error');
    }
  }

  async loadSyncEnabled() {
    try {
      this.syncEnabled = (await getSyncEnabled()) === true;
    } catch (error) {
      showToast(this, 'Could not read the sync toggle', errorMessage(error), 'error');
    }
  }

  async handleSyncEnabledChange(event) {
    const enabled = event.target.checked === true;
    try {
      await setSyncEnabled({ enabled });
      this.syncEnabled = enabled;
      showToast(
        this,
        enabled ? 'Sync enabled' : 'Sync disabled',
        enabled ? 'Runs can start again.' : 'Scheduled and manual runs will not start.',
        'success'
      );
    } catch (error) {
      // The user already flipped the switch in the DOM and syncEnabled never
      // moved, so nothing re-renders: put the toggle back by hand.
      const toggle = this.template.querySelector('[data-id="sync-enabled"]');
      if (toggle) {
        toggle.checked = this.syncEnabled;
      }
      showToast(this, 'Could not change the sync toggle', errorMessage(error), 'error');
    }
  }

  handlePageSizeChange(event) {
    this.pageSize = toInt(event.target.value);
  }

  handleResourcesChange(event) {
    const value = event.detail ? event.detail.value : event.target.value;
    this.enabledResources = Array.isArray(value) ? value : [];
  }

  handleInFutureOnlyChange(event) {
    this.inFutureOnly = event.target.checked === true;
  }

  handleTicketStatusFilterChange(event) {
    this.ticketStatusFilter = event.target.value;
  }

  handleMaxRetriesChange(event) {
    this.maxRetries = toInt(event.target.value);
  }

  handleRetryDelayChange(event) {
    this.retryDelayMinutes = toInt(event.target.value);
  }

  handleSinceModeChange(event) {
    this.sinceMode = event.detail ? event.detail.value : event.target.value;
  }

  handleNamedCredentialChange(event) {
    this.namedCredentialName = event.target.value;
  }

  buildDto() {
    return {
      pageSize: this.pageSize,
      enabledResources: Array.isArray(this.enabledResources) ? [...this.enabledResources] : [],
      inFutureOnly: this.inFutureOnly === true,
      ticketStatusFilter: blankToNull(this.ticketStatusFilter),
      maxRetries: this.maxRetries,
      retryDelayMinutes: this.retryDelayMinutes,
      sinceMode: this.sinceMode,
      namedCredentialName: blankToNull(this.namedCredentialName)
    };
  }

  async handleSave() {
    this.isSaving = true;
    this.deployError = undefined;
    this.deployStatus = undefined;

    let deployJobId;
    try {
      deployJobId = await saveSyncSettings({ settingsJson: JSON.stringify(this.buildDto()) });
    } catch (error) {
      this.isSaving = false;
      showToast(this, 'Could not save the settings', errorMessage(error), 'error');
      return;
    }

    try {
      if (!deployJobId) {
        // Orgs that can't run a real deploy (tests, some sandboxes) save inline.
        showToast(this, 'Settings saved', SAVED, 'success');
        await this.loadSettings();
        return;
      }
      this.deployStatus = DEPLOYING;
      const { done, row } = await pollDeploy(getDeployStatus, deployJobId, this.pollOptions);
      if (done && row.Status__c === 'Succeeded') {
        showToast(this, 'Settings saved', SAVED, 'success');
        await this.loadSettings();
      } else if (done) {
        this.deployError = row.Error_Detail__c || DEPLOY_FAILED;
        showToast(this, 'Settings deployment failed', this.deployError, 'error');
      } else {
        showToast(this, 'Still deploying', STILL_DEPLOYING, 'warning');
      }
    } finally {
      this.deployStatus = undefined;
      this.isSaving = false;
    }
  }
}
