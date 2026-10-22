import { LightningElement, api } from 'lwc';
import { errorMessage } from 'c/humanitixSetupUtils';
import fetchHumanitixEvents from '@salesforce/apex/HumanitixSyncSettingsController.fetchHumanitixEvents';

const MAX_PAGES = 50;
const COLUMNS = [
  { label: 'Event', fieldName: 'name' },
  {
    label: 'Starts',
    fieldName: 'startDate',
    type: 'date',
    typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' }
  },
  { label: 'Status', fieldName: 'status' }
];
const NOTIFICATION_BASE = 'slds-scoped-notification slds-media slds-media_center';

function statusOf(event, now) {
  if (event.isArchived === true) {
    return 'Archived';
  }
  if (event.published === false) {
    return 'Draft';
  }
  if (event.endDate && Date.parse(event.endDate) < now) {
    return 'Past';
  }
  return 'Upcoming';
}

/**
 * Lists the org's Humanitix events live from the API and lets the admin pick
 * which ones Event Selection = Selected syncs. It owns only the selection; the
 * parent saves it. Selection survives search filtering.
 */
export default class HumanitixEventPicker extends LightningElement {
  @api disabled = false;

  columns = COLUMNS;
  events = [];
  searchTerm = '';
  isLoading = false;
  loadError;
  capped = false;
  selected = [];

  @api
  get selectedIds() {
    return this.selected;
  }
  set selectedIds(value) {
    this.selected = Array.isArray(value) ? [...value] : [];
  }

  connectedCallback() {
    this.loadAll();
  }

  async loadAll() {
    this.isLoading = true;
    this.loadError = undefined;
    this.capped = false;
    const byId = new Map();
    try {
      let page = 1;
      let more = true;
      while (more && page <= MAX_PAGES) {
        // Pages load one after another: each needs the previous hasNextPage.
        // eslint-disable-next-line no-await-in-loop
        const result = await fetchHumanitixEvents({ page });
        const rows = result && Array.isArray(result.events) ? result.events : [];
        rows.forEach((row) => byId.set(row.id, row));
        more = !!(result && result.hasNextPage === true);
        page += 1;
      }
      this.capped = more;
      const now = Date.now();
      this.events = Array.from(byId.values())
        .map((row) => ({ ...row, status: statusOf(row, now) }))
        .sort((a, b) => (Date.parse(b.startDate) || 0) - (Date.parse(a.startDate) || 0));
    } catch (error) {
      this.loadError = errorMessage(error);
    } finally {
      this.isLoading = false;
    }
  }

  get filteredEvents() {
    const term = (this.searchTerm || '').trim().toLowerCase();
    if (!term) {
      return this.events;
    }
    return this.events.filter((e) => (e.name || '').toLowerCase().includes(term));
  }

  get pills() {
    const nameById = new Map(this.events.map((e) => [e.id, e.name]));
    return this.selected.map((id) => ({
      label: nameById.get(id) || `Unknown event (${id})`,
      name: id
    }));
  }

  get hasPills() {
    return this.selected.length > 0;
  }

  get hasError() {
    return !!this.loadError;
  }

  get showTable() {
    return !this.isLoading && !this.loadError;
  }

  get errorClass() {
    return NOTIFICATION_BASE + ' slds-theme_error slds-m-bottom_small';
  }

  get noticeClass() {
    return NOTIFICATION_BASE + ' slds-theme_warning slds-m-bottom_small';
  }

  handleSearch(event) {
    this.searchTerm = event.target.value;
  }

  handleRefresh() {
    this.loadAll();
  }

  handleRowSelection(event) {
    if (this.disabled) {
      return;
    }
    const visible = new Set(this.filteredEvents.map((e) => e.id));
    const kept = this.selected.filter((id) => !visible.has(id));
    const picked = (event.detail.selectedRows || []).map((row) => row.id);
    this.updateSelection([...kept, ...picked.filter((id) => !kept.includes(id))]);
  }

  handleRemove(event) {
    if (this.disabled) {
      return;
    }
    const name = event.detail.item.name;
    this.updateSelection(this.selected.filter((id) => id !== name));
  }

  updateSelection(ids) {
    this.selected = ids;
    this.dispatchEvent(new CustomEvent('change', { detail: { selectedIds: [...ids] } }));
  }
}
