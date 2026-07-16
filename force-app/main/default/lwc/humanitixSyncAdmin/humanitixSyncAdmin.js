import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import runSyncNow from '@salesforce/apex/HumanitixSyncAdminController.runSyncNow';
import getRecentRuns from '@salesforce/apex/HumanitixSyncAdminController.getRecentRuns';
import isSyncEnabled from '@salesforce/apex/HumanitixSyncAdminController.isSyncEnabled';

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

export default class HumanitixSyncAdmin extends LightningElement {
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
      this.toast('Sync started', 'A Humanitix sync run has been queued.', 'success');
      await refreshApex(this.wiredRuns);
    } catch (error) {
      this.toast('Could not start sync', this.errorMessage(error), 'error');
    } finally {
      this.isRunning = false;
    }
  }

  handleRefresh() {
    return refreshApex(this.wiredRuns);
  }

  errorMessage(error) {
    return error && error.body && error.body.message ? error.body.message : 'Unexpected error';
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
