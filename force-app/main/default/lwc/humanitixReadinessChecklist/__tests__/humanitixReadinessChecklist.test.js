import { createElement } from 'lwc';
import HumanitixReadinessChecklist from 'c/humanitixReadinessChecklist';
import getReadiness from '@salesforce/apex/HumanitixSyncAdminController.getReadiness';

jest.mock(
  '@salesforce/apex/HumanitixSyncAdminController.getReadiness',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const ALL_OK = [
  { key: 'apiKey', label: 'API key saved', status: 'ok', message: 'An API key is saved.' },
  { key: 'schedule', label: 'Schedule', status: 'ok', message: 'A sync schedule is set.' }
];

function flush() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function mount() {
  const element = createElement('c-humanitix-readiness-checklist', { is: HumanitixReadinessChecklist });
  document.body.appendChild(element);
  return element;
}

describe('c-humanitix-readiness-checklist', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says everything is ready when all items pass', async () => {
    getReadiness.mockResolvedValue(ALL_OK);
    const element = mount();
    await flush();

    expect(element.shadowRoot.querySelector('.summary').textContent).toBe('Everything is ready.');
    expect(element.shadowRoot.querySelectorAll('.checklist-item')).toHaveLength(2);
  });

  it('counts and shows the items that need attention', async () => {
    getReadiness.mockResolvedValue([
      ALL_OK[0],
      { key: 'connection', label: 'Connection to Humanitix', status: 'error', message: 'Humanitix rejected the API key.' },
      { key: 'schedule', label: 'Schedule', status: 'warning', message: 'No schedule is set.' }
    ]);
    const element = mount();
    await flush();

    expect(element.shadowRoot.querySelector('.summary').textContent).toBe('2 items need attention.');
    const failing = element.shadowRoot.querySelector('[data-key="connection"]');
    expect(failing.dataset.status).toBe('error');
    expect(failing.querySelector('.item-message').textContent).toBe('Humanitix rejected the API key.');
    expect(failing.querySelector('lightning-icon').iconName).toBe('utility:error');
  });

  it('uses the singular for one item', async () => {
    getReadiness.mockResolvedValue([{ key: 'schedule', label: 'Schedule', status: 'warning', message: 'x' }]);
    const element = mount();
    await flush();

    expect(element.shadowRoot.querySelector('.summary').textContent).toBe('1 item needs attention.');
  });

  it('shows the load error', async () => {
    getReadiness.mockRejectedValue({ body: { message: 'Insufficient access' } });
    const element = mount();
    await flush();

    expect(element.shadowRoot.querySelector('.load-error').textContent).toBe('Insufficient access');
    expect(element.shadowRoot.querySelectorAll('.checklist-item')).toHaveLength(0);
  });

  it('checks again on Refresh', async () => {
    getReadiness.mockResolvedValue(ALL_OK);
    const element = mount();
    await flush();
    element.shadowRoot.querySelector('lightning-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(getReadiness).toHaveBeenCalledTimes(2);
  });
});
