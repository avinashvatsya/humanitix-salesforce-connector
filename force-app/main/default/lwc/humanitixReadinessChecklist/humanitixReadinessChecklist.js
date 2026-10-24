import { LightningElement } from 'lwc';
import { errorMessage } from 'c/humanitixSetupUtils';
import getReadiness from '@salesforce/apex/HumanitixSyncAdminController.getReadiness';

const ICONS = {
  ok: { iconName: 'utility:success', iconVariant: 'success', statusText: 'Ready' },
  error: { iconName: 'utility:error', iconVariant: 'error', statusText: 'Needs action' },
  warning: { iconName: 'utility:warning', iconVariant: 'warning', statusText: 'Worth a look' },
  unknown: { iconName: 'utility:info', iconVariant: undefined, statusText: 'Not checked' }
};

export default class HumanitixReadinessChecklist extends LightningElement {
  items = [];
  isLoading = false;
  loadError;

  connectedCallback() {
    this.load();
  }

  get hasItems() {
    return this.items.length > 0;
  }

  get summary() {
    const open = this.items.filter((i) => i.status !== 'ok').length;
    if (open === 0) {
      return 'Everything is ready.';
    }
    return open === 1 ? '1 item needs attention.' : `${open} items need attention.`;
  }

  async load() {
    this.isLoading = true;
    this.loadError = undefined;
    try {
      const data = await getReadiness();
      this.items = (data || []).map((i) => ({ ...i, ...(ICONS[i.status] || ICONS.unknown) }));
    } catch (error) {
      this.items = [];
      this.loadError = errorMessage(error);
    } finally {
      this.isLoading = false;
    }
  }

  handleRefresh() {
    return this.load();
  }
}
