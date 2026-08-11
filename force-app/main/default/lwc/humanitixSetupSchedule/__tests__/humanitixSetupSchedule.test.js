import { createElement } from 'lwc';
import HumanitixSetupSchedule from 'c/humanitixSetupSchedule';
import getSchedule from '@salesforce/apex/HumanitixScheduleController.getSchedule';
import saveSchedule from '@salesforce/apex/HumanitixScheduleController.saveSchedule';

jest.mock(
  '@salesforce/apex/HumanitixScheduleController.getSchedule',
  () => ({
    default: jest.fn(() =>
      Promise.resolve({
        deltaIntervalMinutes: null,
        dailyFullSyncTime: null,
        managedJobs: [],
        unmanagedJobs: [],
        drift: false
      })
    )
  }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/HumanitixScheduleController.saveSchedule',
  () => ({
    default: jest.fn(() =>
      Promise.resolve({
        deltaIntervalMinutes: null,
        dailyFullSyncTime: null,
        managedJobs: [],
        unmanagedJobs: [],
        drift: false
      })
    )
  }),
  { virtual: true }
);

const OFF_SCHEDULE = {
  deltaIntervalMinutes: null,
  dailyFullSyncTime: null,
  managedJobs: [],
  unmanagedJobs: [],
  drift: false
};

function schedule(overrides) {
  return { ...OFF_SCHEDULE, ...overrides };
}

function flush() {
  return Promise.resolve();
}

// The schedule load, a save and the re-render of the fresh DTO each resolve on
// their own microtask, so a few ticks are needed before the DOM settles.
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

function intervalCombobox(element) {
  return element.shadowRoot.querySelector('lightning-combobox');
}

function timeInput(element) {
  return element.shadowRoot.querySelector('lightning-input');
}

function text(element) {
  return element.shadowRoot.textContent;
}

async function chooseInterval(element, value) {
  const combobox = intervalCombobox(element);
  combobox.value = value;
  combobox.dispatchEvent(new CustomEvent('change', { detail: { value } }));
  await settle();
}

async function setTime(element, value) {
  const input = timeInput(element);
  input.value = value;
  input.dispatchEvent(new CustomEvent('change'));
  await settle();
}

function create() {
  const element = createElement('c-humanitix-setup-schedule', { is: HumanitixSetupSchedule });
  document.body.appendChild(element);
  return element;
}

// ShowToastEvent is composed and bubbles, so the host element sees it.
function listenForToasts(element) {
  const handler = jest.fn();
  element.addEventListener('lightning__showtoast', handler);
  return handler;
}

describe('c-humanitix-setup-schedule', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('renders the saved interval and daily time', async () => {
    getSchedule.mockResolvedValue(
      schedule({
        deltaIntervalMinutes: 60,
        dailyFullSyncTime: '02:05',
        managedJobs: [
          {
            name: 'Humanitix Delta Sync 1',
            cron: '0 0 * * * ?',
            nextFireTime: '2026-08-12T02:00:00.000Z',
            state: 'WAITING'
          }
        ]
      })
    );

    const element = create();
    await settle();

    expect(getSchedule).toHaveBeenCalled();
    expect(intervalCombobox(element).value).toBe('60');
    expect(timeInput(element).value).toBe('02:05');

    const table = element.shadowRoot.querySelector('lightning-datatable');
    expect(table).not.toBeNull();
    expect(table.keyField).toBe('name');
    expect(table.data).toHaveLength(1);
  });

  it('renders the off state and the empty jobs message', async () => {
    getSchedule.mockResolvedValue(schedule({}));

    const element = create();
    await settle();

    expect(intervalCombobox(element).value).toBe('0');
    expect(timeInput(element).value).toBe('');
    expect(element.shadowRoot.querySelector('lightning-datatable')).toBeNull();
    expect(text(element)).toContain(
      'No scheduled jobs. Save an interval or daily time to create them.'
    );
  });

  it('sends nulls when the interval is Off and the time is empty', async () => {
    getSchedule.mockResolvedValue(schedule({}));
    saveSchedule.mockResolvedValue(schedule({}));

    const element = create();
    await settle();

    buttonByLabel(element, 'Save Schedule').dispatchEvent(new CustomEvent('click'));
    await settle();

    expect(saveSchedule).toHaveBeenCalledWith({ deltaMinutes: null, dailyTime: null });
  });

  it('sends the chosen preset as a number and the time as HH:mm', async () => {
    getSchedule.mockResolvedValue(schedule({}));
    saveSchedule.mockResolvedValue(
      schedule({ deltaIntervalMinutes: 30, dailyFullSyncTime: '02:05' })
    );

    const element = create();
    await settle();

    await chooseInterval(element, '30');
    await setTime(element, '02:05');

    buttonByLabel(element, 'Save Schedule').dispatchEvent(new CustomEvent('click'));
    await settle();

    expect(saveSchedule).toHaveBeenCalledWith({ deltaMinutes: 30, dailyTime: '02:05' });
    // The fresh DTO from the save is what gets rendered.
    expect(intervalCombobox(element).value).toBe('30');
    expect(timeInput(element).value).toBe('02:05');
  });

  it('trims a browser time of HH:mm:ss.SSS down to HH:mm before saving', async () => {
    getSchedule.mockResolvedValue(schedule({}));
    saveSchedule.mockResolvedValue(schedule({ dailyFullSyncTime: '02:05' }));

    const element = create();
    await settle();

    await setTime(element, '02:05:00.000');

    buttonByLabel(element, 'Save Schedule').dispatchEvent(new CustomEvent('click'));
    await settle();

    expect(saveSchedule).toHaveBeenCalledWith({ deltaMinutes: null, dailyTime: '02:05' });
  });

  it('shows the drift banner and repairs the schedule from the current values', async () => {
    getSchedule.mockResolvedValue(
      schedule({ deltaIntervalMinutes: 60, dailyFullSyncTime: '03:10', drift: true })
    );
    saveSchedule.mockResolvedValue(
      schedule({ deltaIntervalMinutes: 60, dailyFullSyncTime: '03:10', drift: false })
    );

    const element = create();
    await settle();

    expect(text(element)).toContain(
      'The scheduled jobs do not match the saved schedule. Save again to repair them.'
    );

    buttonByLabel(element, 'Repair schedule').dispatchEvent(new CustomEvent('click'));
    await settle();

    expect(saveSchedule).toHaveBeenCalledWith({ deltaMinutes: 60, dailyTime: '03:10' });
    expect(buttonByLabel(element, 'Repair schedule')).toBeNull();
  });

  it('warns when the daily time lands on the interval grid', async () => {
    getSchedule.mockResolvedValue(schedule({}));

    const element = create();
    await settle();

    await chooseInterval(element, '30');
    await setTime(element, '02:30');

    expect(text(element)).toContain('fire at the same minute');
  });

  it('does not warn when the daily time is offset from the interval grid', async () => {
    getSchedule.mockResolvedValue(schedule({}));

    const element = create();
    await settle();

    await chooseInterval(element, '30');
    await setTime(element, '02:05');

    expect(text(element)).not.toContain('fire at the same minute');
  });

  it('lists jobs that were scheduled outside this page', async () => {
    getSchedule.mockResolvedValue(
      schedule({
        unmanagedJobs: [
          {
            name: 'Humanitix Legacy Nightly',
            cron: '0 30 1 * * ?',
            nextFireTime: '2026-08-12T01:30:00.000Z',
            state: 'WAITING'
          }
        ]
      })
    );

    const element = create();
    await settle();

    expect(text(element)).toContain('Humanitix Legacy Nightly');
    expect(text(element)).toContain('0 30 1 * * ?');
    expect(text(element)).toContain('This job was scheduled outside this page.');
  });

  it('toasts an error when the save is rejected', async () => {
    getSchedule.mockResolvedValue(schedule({}));
    saveSchedule.mockRejectedValue({ body: { message: 'The delta interval must be a preset.' } });

    const element = create();
    await settle();

    const toasts = listenForToasts(element);
    buttonByLabel(element, 'Save Schedule').dispatchEvent(new CustomEvent('click'));
    await settle();

    expect(saveSchedule).toHaveBeenCalled();
    expect(toasts).toHaveBeenCalled();
    const { title, message, variant } = toasts.mock.calls[0][0].detail;
    expect(title).toBe('Could not save the schedule');
    expect(message).toBe('The delta interval must be a preset.');
    expect(variant).toBe('error');
    expect(buttonByLabel(element, 'Save Schedule').disabled).toBe(false);
  });
});
