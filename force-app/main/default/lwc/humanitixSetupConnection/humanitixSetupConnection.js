import { LightningElement } from 'lwc';
import { errorMessage, showToast } from 'c/humanitixSetupUtils';
import getConnectionStatus from '@salesforce/apex/HumanitixConnectionController.getConnectionStatus';
import saveApiKey from '@salesforce/apex/HumanitixConnectionController.saveApiKey';
import testConnection from '@salesforce/apex/HumanitixConnectionController.testConnection';

const KEY_SAVED = 'A key is saved for principal Humanitix_Named_Principal.';
const NO_KEY = 'No key saved yet.';
const STATUS_UNKNOWN = 'Key status is unavailable in this org. Use the manual steps below.';
const NOTIFICATION_BASE = 'slds-scoped-notification slds-media slds-media_center slds-m-bottom_medium';

/**
 * Connection tab: stores the Humanitix API key on the external credential
 * principal and probes the API. When the org can't report or accept the key,
 * the manual Setup steps are revealed as a fallback.
 */
export default class HumanitixSetupConnection extends LightningElement {
  isLoadingStatus = true;
  isSaving = false;
  isTesting = false;
  keySaved = false;
  statusKnown = true;
  statusDetail;
  saveFailed = false;
  apiKey = '';
  testResult;

  connectedCallback() {
    this.loadStatus();
  }

  get statusIcon() {
    return this.showsSavedKey ? 'utility:success' : 'utility:warning';
  }

  get statusVariant() {
    return this.showsSavedKey ? 'success' : 'warning';
  }

  get statusText() {
    if (!this.statusKnown) {
      return STATUS_UNKNOWN;
    }
    return this.keySaved ? KEY_SAVED : NO_KEY;
  }

  // A key can only be reported as saved when the status read succeeded.
  get showsSavedKey() {
    return this.statusKnown && this.keySaved;
  }

  get showStatusDetail() {
    return !this.statusKnown && !!this.statusDetail;
  }

  get saveDisabled() {
    return this.isSaving || !this.apiKey || this.apiKey.trim().length === 0;
  }

  get showManualSteps() {
    return this.statusKnown === false || this.saveFailed;
  }

  get hasTestResult() {
    return !!this.testResult;
  }

  get testNotificationClass() {
    const theme = this.testResult && this.testResult.ok ? 'slds-theme_success' : 'slds-theme_error';
    return NOTIFICATION_BASE + ' ' + theme;
  }

  get testMessage() {
    if (!this.testResult) {
      return '';
    }
    const message = this.testResult.message || '';
    const statusCode = this.testResult.statusCode;
    return statusCode > 0 ? 'HTTP ' + statusCode + ': ' + message : message;
  }

  async loadStatus() {
    this.isLoadingStatus = true;
    try {
      const status = (await getConnectionStatus()) || {};
      this.keySaved = status.keySaved === true;
      this.statusKnown = status.statusKnown !== false;
      this.statusDetail = status.detail;
    } catch (error) {
      // An unreadable status behaves like statusKnown = false: offer the manual steps.
      this.keySaved = false;
      this.statusKnown = false;
      this.statusDetail = errorMessage(error);
    } finally {
      this.isLoadingStatus = false;
    }
  }

  handleKeyChange(event) {
    this.apiKey = event.target.value;
  }

  async handleSave() {
    this.isSaving = true;
    try {
      await saveApiKey({ apiKey: this.apiKey });
      this.apiKey = '';
      this.saveFailed = false;
      showToast(
        this,
        'API key saved',
        'The key is stored on the external credential principal.',
        'success'
      );
      await this.loadStatus();
    } catch (error) {
      this.saveFailed = true;
      showToast(this, 'Could not save the key', errorMessage(error), 'error');
    } finally {
      this.isSaving = false;
    }
  }

  async handleTest() {
    this.isTesting = true;
    this.testResult = undefined;
    try {
      this.testResult = await testConnection();
    } catch (error) {
      // The controller reports failures in its payload; this is belt and braces.
      this.testResult = { ok: false, statusCode: 0, message: errorMessage(error) };
    } finally {
      this.isTesting = false;
    }
  }
}
