import { createElement } from 'lwc';
import HumanitixSetup from 'c/humanitixSetup';

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

function flush() {
  return Promise.resolve();
}

describe('c-humanitix-setup', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('renders the tabset with a Dashboard tab', async () => {
    const element = createElement('c-humanitix-setup', { is: HumanitixSetup });
    document.body.appendChild(element);
    await flush();

    const tabset = element.shadowRoot.querySelector('lightning-tabset');
    expect(tabset).not.toBeNull();
    const tabs = Array.from(element.shadowRoot.querySelectorAll('lightning-tab'));
    expect(tabs.map((t) => t.label)).toContain('Dashboard');
  });

  it('renders the dashboard child by default', async () => {
    const element = createElement('c-humanitix-setup', { is: HumanitixSetup });
    document.body.appendChild(element);
    await flush();

    const dashboard = element.shadowRoot.querySelector('c-humanitix-setup-dashboard');
    expect(dashboard).not.toBeNull();
  });

  it('marks a tab visited when it becomes active', async () => {
    const element = createElement('c-humanitix-setup', { is: HumanitixSetup });
    document.body.appendChild(element);
    await flush();

    const tab = element.shadowRoot.querySelector('lightning-tab');
    tab.dispatchEvent(new CustomEvent('active'));
    await flush();

    // Dashboard stays rendered after activation events.
    expect(element.shadowRoot.querySelector('c-humanitix-setup-dashboard')).not.toBeNull();
  });
});
