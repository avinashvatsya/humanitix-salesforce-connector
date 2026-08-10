import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { errorMessage, showToast } from 'c/humanitixSetupUtils';
import runSyncNow from '@salesforce/apex/HumanitixSyncAdminController.runSyncNow';
import getRecentRuns from '@salesforce/apex/HumanitixSyncAdminController.getRecentRuns';
import isSyncEnabled from '@salesforce/apex/HumanitixSyncAdminController.isSyncEnabled';
import ensureDefaultMappings from '@salesforce/apex/HumanitixSyncAdminController.ensureDefaultMappings';

const COLUMNS = [
  { label: 'Run', fieldName: 'Name' },
  { label: 'Status', fieldName: 'Status__c' },
  { label: 'Trigger', fieldName: 'Trigger_Source__c' },
  {
    label: 'Started',
    fieldName: 'Started_At__c',
    type: 'date',
    typeAttributes: {
      year: 'numeric',
      month: 'short',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit'
    }
  },
  { label: 'Processed', fieldName: 'Total_Records_Processed__c', type: 'number' },
  { label: 'Failed', fieldName: 'Total_Records_Failed__c', type: 'number' },
  { label: 'Errors', fieldName: 'Total_Errors__c', type: 'number' }
];

export default class HumanitixSetupDashboard extends LightningElement {
  columns = COLUMNS;
  isRunning = false;
  syncEnabled = true;
  runs;
  wiredRuns;

  @wire(isSyncEnabled)
  wiredEnabled({ data }) {
    if (data !== undefined && data !== null) {
      this.syncEnabled = data;
    }
  }

  @wire(getRecentRuns)
  wiredRunsHandler(result) {
    this.wiredRuns = result;
    if (result.data) {
      this.runs = result.data;
    }
  }

  connectedCallback() {
    // Unlocked packages can't run post-install scripts, so a fresh install has
    // no mapping records until this first panel load kicks off the seeder.
    ensureDefaultMappings()
      .then((seedingStarted) => {
        if (seedingStarted) {
          showToast(
            this,
            'Installing default mappings',
            'The default Humanitix mapping metadata is being created. It appears under Setup, Custom Metadata Types, within a minute.',
            'info'
          );
        }
      })
      .catch(() => {
        // Non-fatal: the panel still works; seeding can be run manually.
      });
  }

  get hasRuns() {
    return Array.isArray(this.runs) && this.runs.length > 0;
  }

  get runDisabled() {
    return this.isRunning || !this.syncEnabled;
  }

  async handleRun() {
    this.isRunning = true;
    try {
      await runSyncNow();
      showToast(this, 'Sync started', 'A Humanitix sync run has been queued.', 'success');
      await refreshApex(this.wiredRuns);
    } catch (error) {
      showToast(this, 'Could not start sync', errorMessage(error), 'error');
    } finally {
      this.isRunning = false;
    }
  }

  handleRefresh() {
    return refreshApex(this.wiredRuns);
  }
}
