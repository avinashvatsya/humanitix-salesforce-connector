import { createElement } from 'lwc';
import HumanitixSetupConnection from 'c/humanitixSetupConnection';
import getConnectionStatus from '@salesforce/apex/HumanitixConnectionController.getConnectionStatus';
import saveApiKey from '@salesforce/apex/HumanitixConnectionController.saveApiKey';
import testConnection from '@salesforce/apex/HumanitixConnectionController.testConnection';

jest.mock(
  '@salesforce/apex/HumanitixConnectionController.getConnectionStatus',
  () => ({
    default: jest.fn(() =>
      Promise.resolve({ keySaved: false, statusKnown: true, detail: 'No key' })
    )
  }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/HumanitixConnectionController.saveApiKey',
  () => ({ default: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/HumanitixConnectionController.testConnection',
  () => ({
    default: jest.fn(() => Promise.resolve({ ok: true, statusCode: 200, message: 'Connected.' }))
  }),
  { virtual: true }
);

function flush() {
  return Promise.resolve();
}

// The status load, a save and the follow-up re-fetch each resolve on their own
// microtask, so a few ticks are needed before the DOM settles.
async function settle() {
  await flush();
  await flush();
  await flush();
  await flush();
}

// The Jest stubs receive `label` as a JS property, which never reflects to a
// DOM attribute, so an attribute selector can't find the button.
function buttonByLabel(element, label) {
  return (
    Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find(
      (b) => b.label === label
    ) || null
  );
}

function keyInput(element) {
  return element.shadowRoot.querySelector('lightning-input');
}

function text(element) {
  return element.shadowRoot.textContent;
}

function create() {
  const element = createElement('c-humanitix-setup-connection', { is: HumanitixSetupConnection });
  document.body.appendChild(element);
  return element;
}

describe('c-humanitix-setup-connection', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('reports a saved key once the status resolves', async () => {
    getConnectionStatus.mockResolvedValue({
      keySaved: true,
      statusKnown: true,
      detail: 'Key present'
    });

    const element = create();
    await settle();

    expect(getConnectionStatus).toHaveBeenCalled();
    expect(text(element)).toContain('A key is saved for principal Humanitix_Named_Principal.');
    const icon = element.shadowRoot.querySelector('lightning-icon');
    expect(icon.iconName).toBe('utility:success');
    expect(icon.variant).toBe('success');
    expect(text(element)).not.toContain('Enter the key manually in Setup');
  });

  it('reports that no key is saved yet', async () => {
    getConnectionStatus.mockResolvedValue({
      keySaved: false,
      statusKnown: true,
      detail: 'No key'
    });

    const element = create();
    await settle();

    expect(text(element)).toContain('No key saved yet.');
    expect(element.shadowRoot.querySelector('lightning-icon').iconName).toBe('utility:warning');
    expect(text(element)).not.toContain('Enter the key manually in Setup');
  });

  it('reveals the manual steps when the key status is unknown', async () => {
    getConnectionStatus.mockResolvedValue({
      keySaved: false,
      statusKnown: false,
      detail: 'ConnectApi is not available.'
    });

    const element = create();
    await settle();

    expect(text(element)).toContain('Key status is unavailable in this org.');
    expect(text(element)).toContain('Enter the key manually in Setup');
    expect(text(element)).toContain('Humanitix_Named_Principal');
    expect(text(element)).toContain('ApiKey');
  });

  it('enables Save Key once a key is typed and saves it', async () => {
    const element = create();
    await settle();

    expect(buttonByLabel(element, 'Save Key').disabled).toBe(true);

    const input = keyInput(element);
    input.value = 'htx-secret';
    input.dispatchEvent(new CustomEvent('change'));
    await settle();

    const save = buttonByLabel(element, 'Save Key');
    expect(save.disabled).toBe(false);

    save.dispatchEvent(new CustomEvent('click'));
    await settle();

    expect(saveApiKey).toHaveBeenCalledWith({ apiKey: 'htx-secret' });
    expect(keyInput(element).value).toBe('');
  });

  it('reveals the manual steps when saving the key fails', async () => {
    saveApiKey.mockRejectedValue({ body: { message: 'nope' } });

    const element = create();
    await settle();

    const input = keyInput(element);
    input.value = 'htx-secret';
    input.dispatchEvent(new CustomEvent('change'));
    await settle();

    buttonByLabel(element, 'Save Key').dispatchEvent(new CustomEvent('click'));
    await settle();

    expect(text(element)).toContain('Enter the key manually in Setup');
  });

  it('renders a successful test result', async () => {
    testConnection.mockResolvedValue({ ok: true, statusCode: 200, message: 'Connected.' });

    const element = create();
    await settle();

    buttonByLabel(element, 'Test Connection').dispatchEvent(new CustomEvent('click'));
    await settle();

    expect(testConnection).toHaveBeenCalled();
    const notification = element.shadowRoot.querySelector('.slds-scoped-notification');
    expect(notification.className).toContain('slds-theme_success');
    expect(notification.textContent).toContain('Connected.');
    expect(notification.textContent).toContain('HTTP 200');
  });

  it('renders a failed test result', async () => {
    testConnection.mockResolvedValue({ ok: false, statusCode: 401, message: 'Unauthorized.' });

    const element = create();
    await settle();

    buttonByLabel(element, 'Test Connection').dispatchEvent(new CustomEvent('click'));
    await settle();

    const notification = element.shadowRoot.querySelector('.slds-scoped-notification');
    expect(notification.className).toContain('slds-theme_error');
    expect(notification.textContent).toContain('Unauthorized.');
    expect(notification.textContent).toContain('HTTP 401');
  });
});
