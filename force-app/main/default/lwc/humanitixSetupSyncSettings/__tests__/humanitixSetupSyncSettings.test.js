import { createElement } from 'lwc';
import HumanitixSetupSyncSettings from 'c/humanitixSetupSyncSettings';
import getSyncSettings from '@salesforce/apex/HumanitixSyncSettingsController.getSyncSettings';
import saveSyncSettings from '@salesforce/apex/HumanitixSyncSettingsController.saveSyncSettings';
import getSyncEnabled from '@salesforce/apex/HumanitixSyncSettingsController.getSyncEnabled';
import setSyncEnabled from '@salesforce/apex/HumanitixSyncSettingsController.setSyncEnabled';
import getDeployStatus from '@salesforce/apex/HumanitixMetadataWriter.getDeployStatus';

jest.mock(
  '@salesforce/apex/HumanitixSyncSettingsController.getSyncSettings',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/HumanitixSyncSettingsController.saveSyncSettings',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/HumanitixSyncSettingsController.getSyncEnabled',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/HumanitixSyncSettingsController.setSyncEnabled',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/HumanitixMetadataWriter.getDeployStatus',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const SETTINGS = {
  pageSize: 100,
  enabledResources: ['Tags', 'Events'],
  inFutureOnly: true,
  ticketStatusFilter: 'complete',
  maxRetries: 5,
  retryDelayMinutes: 5,
  sinceMode: 'Modified',
  namedCredentialName: 'HumanitixAPI',
  recordExists: true
};

const JOB_ID = '0Afxx0000000001CAA';

function flush() {
  return Promise.resolve();
}

// The two loads, a save, the deploy poll and the follow-up re-fetch each
// resolve on their own microtask, so a few ticks are needed before the DOM
// settles.
async function settle() {
  for (let i = 0; i < 8; i++) {
    await flush();
  }
}

// The Jest stubs receive `label` as a JS property, which never reflects to a
// DOM attribute, so an attribute selector can't find these elements.
function byLabel(element, tag, label) {
  return (
    Array.from(element.shadowRoot.querySelectorAll(tag)).find((e) => e.label === label) || null
  );
}

function inputByLabel(element, label) {
  return byLabel(element, 'lightning-input', label);
}

function buttonByLabel(element, label) {
  return byLabel(element, 'lightning-button', label);
}

function checkboxGroup(element) {
  return element.shadowRoot.querySelector('lightning-checkbox-group');
}

function combobox(element) {
  return element.shadowRoot.querySelector('lightning-combobox');
}

function text(element) {
  return element.shadowRoot.textContent;
}

function change(node) {
  node.dispatchEvent(new CustomEvent('change'));
}

function create() {
  const element = createElement('c-humanitix-setup-sync-settings', {
    is: HumanitixSetupSyncSettings
  });
  document.body.appendChild(element);
  return element;
}

async function createAndLoad() {
  const element = create();
  await settle();
  return element;
}

async function save(element) {
  buttonByLabel(element, 'Save Settings').dispatchEvent(new CustomEvent('click'));
  await settle();
}

describe('c-humanitix-setup-sync-settings', () => {
  beforeEach(() => {
    getSyncSettings.mockResolvedValue({ ...SETTINGS });
    getSyncEnabled.mockResolvedValue(true);
    setSyncEnabled.mockResolvedValue(undefined);
    saveSyncSettings.mockResolvedValue(null);
    getDeployStatus.mockResolvedValue(null);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.useRealTimers();
    jest.clearAllMocks();
  });

  it('renders the settings returned by Apex', async () => {
    const element = await createAndLoad();

    expect(getSyncSettings).toHaveBeenCalled();
    expect(getSyncEnabled).toHaveBeenCalled();

    expect(inputByLabel(element, 'Sync Enabled').checked).toBe(true);
    expect(inputByLabel(element, 'Page Size').value).toBe(100);
    expect(checkboxGroup(element).value).toEqual(['Tags', 'Events']);
    expect(inputByLabel(element, 'Future events only').checked).toBe(true);
    expect(inputByLabel(element, 'Ticket Status Filter').value).toBe('complete');
    expect(inputByLabel(element, 'Max Retries').value).toBe(5);
    expect(inputByLabel(element, 'Retry Delay Minutes').value).toBe(5);
    expect(combobox(element).value).toBe('Modified');
    expect(inputByLabel(element, 'Named Credential Name').value).toBe('HumanitixAPI');
    expect(text(element)).not.toContain('No settings record exists yet.');
  });

  it('warns when no settings record exists yet', async () => {
    getSyncSettings.mockResolvedValue({ ...SETTINGS, recordExists: false });

    const element = await createAndLoad();

    expect(text(element)).toContain('No settings record exists yet. Saving this form creates it.');
    const banner = element.shadowRoot.querySelector('.slds-scoped-notification');
    expect(banner.className).toContain('slds-theme_info');
  });

  it('saves the kill switch and reverts the toggle when the save fails', async () => {
    const element = await createAndLoad();

    const toggle = inputByLabel(element, 'Sync Enabled');
    toggle.checked = false;
    change(toggle);
    await settle();

    expect(setSyncEnabled).toHaveBeenCalledWith({ enabled: false });
    expect(inputByLabel(element, 'Sync Enabled').checked).toBe(false);

    setSyncEnabled.mockRejectedValue({ body: { message: 'no permission' } });
    const flipped = inputByLabel(element, 'Sync Enabled');
    flipped.checked = true;
    change(flipped);
    await settle();

    expect(setSyncEnabled).toHaveBeenLastCalledWith({ enabled: true });
    expect(inputByLabel(element, 'Sync Enabled').checked).toBe(false);
  });

  it('serializes the edited form into settingsJson', async () => {
    const element = await createAndLoad();

    const pageSize = inputByLabel(element, 'Page Size');
    pageSize.value = '250';
    change(pageSize);

    const resources = checkboxGroup(element);
    resources.value = ['Tags', 'Events', 'Orders', 'Tickets'];
    change(resources);

    const filter = inputByLabel(element, 'Ticket Status Filter');
    filter.value = '   ';
    change(filter);

    const mode = combobox(element);
    mode.value = 'FullPull';
    change(mode);

    await settle();
    await save(element);

    expect(saveSyncSettings).toHaveBeenCalledTimes(1);
    const dto = JSON.parse(saveSyncSettings.mock.calls[0][0].settingsJson);
    expect(dto.pageSize).toBe(250);
    expect(dto.enabledResources).toEqual(['Tags', 'Events', 'Orders', 'Tickets']);
    expect(dto.ticketStatusFilter).toBeNull();
    expect(dto.inFutureOnly).toBe(true);
    expect(dto.maxRetries).toBe(5);
    expect(dto.retryDelayMinutes).toBe(5);
    expect(dto.sinceMode).toBe('FullPull');
    expect(dto.namedCredentialName).toBe('HumanitixAPI');
  });

  it('re-fetches the settings when a save needs no deploy', async () => {
    const element = await createAndLoad();
    expect(getSyncSettings).toHaveBeenCalledTimes(1);

    await save(element);

    expect(getDeployStatus).not.toHaveBeenCalled();
    expect(getSyncSettings).toHaveBeenCalledTimes(2);
  });

  it('polls a pending deploy until it succeeds, then re-fetches', async () => {
    jest.useFakeTimers();
    saveSyncSettings.mockResolvedValue(JOB_ID);
    getDeployStatus
      .mockResolvedValueOnce({ Status__c: 'Pending', Error_Detail__c: null })
      .mockResolvedValue({ Status__c: 'Succeeded', Error_Detail__c: null });

    const element = await createAndLoad();
    expect(getSyncSettings).toHaveBeenCalledTimes(1);

    await save(element);

    expect(getDeployStatus).toHaveBeenCalledWith({ deployJobId: JOB_ID });
    expect(text(element)).toContain('Saving settings. Custom metadata deploys take a few seconds.');

    await jest.advanceTimersByTimeAsync(2000);
    await settle();

    expect(getDeployStatus).toHaveBeenCalledTimes(2);
    expect(getSyncSettings).toHaveBeenCalledTimes(2);
    expect(text(element)).not.toContain('Saving settings. Custom metadata deploys');
    expect(buttonByLabel(element, 'Save Settings').disabled).toBe(false);
  });

  it('renders the deploy error detail when the deploy fails', async () => {
    jest.useFakeTimers();
    saveSyncSettings.mockResolvedValue(JOB_ID);
    getDeployStatus
      .mockResolvedValueOnce({ Status__c: 'Pending', Error_Detail__c: null })
      .mockResolvedValue({
        Status__c: 'Failed',
        Error_Detail__c: 'Page_Size__c: bad value for type number.'
      });

    const element = await createAndLoad();
    await save(element);
    await jest.advanceTimersByTimeAsync(2000);
    await settle();

    const notification = element.shadowRoot.querySelector('.slds-theme_error');
    expect(notification).not.toBeNull();
    expect(notification.textContent).toContain('Page_Size__c: bad value for type number.');
    expect(getSyncSettings).toHaveBeenCalledTimes(1);
  });

  it('reports a rejected save without polling', async () => {
    saveSyncSettings.mockRejectedValue({
      body: { message: 'Page Size must be between 1 and 1000.' }
    });

    const element = await createAndLoad();
    await save(element);

    expect(getDeployStatus).not.toHaveBeenCalled();
    expect(getSyncSettings).toHaveBeenCalledTimes(1);
    expect(buttonByLabel(element, 'Save Settings').disabled).toBe(false);
    expect(element.shadowRoot.querySelector('.slds-theme_error')).toBeNull();
  });
});
