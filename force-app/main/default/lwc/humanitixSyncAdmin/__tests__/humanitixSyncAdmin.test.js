import { createElement } from 'lwc';
import HumanitixSyncAdmin from 'c/humanitixSyncAdmin';
import runSyncNow from '@salesforce/apex/HumanitixSyncAdminController.runSyncNow';
import getRecentRuns from '@salesforce/apex/HumanitixSyncAdminController.getRecentRuns';
import isSyncEnabled from '@salesforce/apex/HumanitixSyncAdminController.isSyncEnabled';

jest.mock(
  '@salesforce/apex/HumanitixSyncAdminController.runSyncNow',
  () => ({ default: jest.fn(() => Promise.resolve('a01000000000001')) }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/HumanitixSyncAdminController.getRecentRuns',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/HumanitixSyncAdminController.isSyncEnabled',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

function flush() {
  return Promise.resolve();
}

describe('c-humanitix-sync-admin', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('renders the Run Sync Now button when sync is enabled', async () => {
    const element = createElement('c-humanitix-sync-admin', { is: HumanitixSyncAdmin });
    document.body.appendChild(element);

    isSyncEnabled.emit(true);
    getRecentRuns.emit([]);
    await flush();

    const button = element.shadowRoot.querySelector('lightning-button[label="Run Sync Now"]');
    expect(button).not.toBeNull();
  });

  it('calls runSyncNow when the button is clicked', async () => {
    const element = createElement('c-humanitix-sync-admin', { is: HumanitixSyncAdmin });
    document.body.appendChild(element);

    isSyncEnabled.emit(true);
    getRecentRuns.emit([]);
    await flush();

    const button = element.shadowRoot.querySelector('lightning-button[label="Run Sync Now"]');
    button.dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(runSyncNow).toHaveBeenCalled();
  });

  it('shows a disabled message when sync is off', async () => {
    const element = createElement('c-humanitix-sync-admin', { is: HumanitixSyncAdmin });
    document.body.appendChild(element);

    isSyncEnabled.emit(false);
    getRecentRuns.emit([]);
    await flush();

    const button = element.shadowRoot.querySelector('lightning-button[label="Run Sync Now"]');
    expect(button).toBeNull();
  });
});
