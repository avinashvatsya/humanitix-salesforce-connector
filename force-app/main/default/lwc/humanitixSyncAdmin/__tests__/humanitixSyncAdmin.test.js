import { createElement } from 'lwc';
import HumanitixSyncAdmin from 'c/humanitixSyncAdmin';

// The dashboard child imports these Apex modules on mount.
jest.mock(
  '@salesforce/apex/HumanitixSyncAdminController.runSyncNow',
  () => ({ default: jest.fn(() => Promise.resolve('a01000000000001')) }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/HumanitixSyncAdminController.ensureDefaultMappings',
  () => ({ default: jest.fn(() => Promise.resolve(false)) }),
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

describe('c-humanitix-sync-admin (deprecated wrapper)', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('renders the setup dashboard', async () => {
    const element = createElement('c-humanitix-sync-admin', { is: HumanitixSyncAdmin });
    document.body.appendChild(element);
    await Promise.resolve();

    expect(element.shadowRoot.querySelector('c-humanitix-setup-dashboard')).not.toBeNull();
  });
});
