import { createElement } from 'lwc';
import HumanitixEventPicker from 'c/humanitixEventPicker';
import fetchHumanitixEvents from '@salesforce/apex/HumanitixSyncSettingsController.fetchHumanitixEvents';

jest.mock(
  '@salesforce/apex/HumanitixSyncSettingsController.fetchHumanitixEvents',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const FUTURE = '2099-01-01T10:00:00.000Z';
const PAST = '2020-01-01T10:00:00.000Z';

function ev(id, name, extra) {
  return {
    id,
    name,
    startDate: FUTURE,
    endDate: FUTURE,
    timezone: 'Australia/Sydney',
    isArchived: false,
    published: true,
    ...(extra || {})
  };
}

async function settle(ticks = 10) {
  for (let i = 0; i < ticks; i++) {
    await Promise.resolve();
  }
}

async function create(props) {
  const element = createElement('c-humanitix-event-picker', { is: HumanitixEventPicker });
  Object.assign(element, props || {});
  document.body.appendChild(element);
  await settle();
  return element;
}

function table(element) {
  return element.shadowRoot.querySelector('lightning-datatable');
}

function pills(element) {
  return element.shadowRoot.querySelector('lightning-pill-container');
}

function text(element) {
  return element.shadowRoot.textContent;
}

function listen(element) {
  const handler = jest.fn();
  element.addEventListener('change', handler);
  return handler;
}

describe('c-humanitix-event-picker', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('loads every page until the last one and labels each status', async () => {
    fetchHumanitixEvents
      .mockResolvedValueOnce({ page: 1, hasNextPage: true, events: [ev('e1', 'Alpha')] })
      .mockResolvedValueOnce({
        page: 2,
        hasNextPage: false,
        events: [
          ev('e2', 'Bravo', { startDate: PAST, endDate: PAST }),
          ev('e3', 'Charlie', { published: false }),
          ev('e4', 'Delta', { isArchived: true })
        ]
      });

    const element = await create();

    expect(fetchHumanitixEvents).toHaveBeenCalledTimes(2);
    expect(fetchHumanitixEvents).toHaveBeenNthCalledWith(1, { page: 1 });
    expect(fetchHumanitixEvents).toHaveBeenNthCalledWith(2, { page: 2 });
    const statuses = Object.fromEntries(table(element).data.map((r) => [r.id, r.status]));
    expect(statuses).toEqual({ e1: 'Upcoming', e2: 'Past', e3: 'Draft', e4: 'Archived' });
    expect(table(element).keyField).toBe('id');
  });

  it('stops at 50 pages and says the list was cut', async () => {
    fetchHumanitixEvents.mockImplementation(({ page }) =>
      Promise.resolve({ page, hasNextPage: true, events: [ev('e' + page, 'Event ' + page)] })
    );

    const element = await create();
    await settle(1000);

    expect(fetchHumanitixEvents).toHaveBeenCalledTimes(50);
    expect(text(element)).toContain('Only the first 5,000 events are listed.');
  });

  it('shows saved ids as pills, naming unknown ones', async () => {
    fetchHumanitixEvents.mockResolvedValue({ page: 1, hasNextPage: false, events: [ev('e1', 'Alpha')] });

    const element = await create({ selectedIds: ['e1', 'gone'] });

    expect(pills(element).items).toEqual([
      { label: 'Alpha', name: 'e1' },
      { label: 'Unknown event (gone)', name: 'gone' }
    ]);
    expect(table(element).selectedRows).toEqual(['e1', 'gone']);
  });

  it('filters by name and keeps selections hidden by the filter', async () => {
    fetchHumanitixEvents.mockResolvedValue({
      page: 1,
      hasNextPage: false,
      events: [ev('e1', 'Alpha Gala'), ev('e2', 'Bravo Ball')]
    });
    const element = await create({ selectedIds: ['e1'] });
    const changed = listen(element);

    const search = element.shadowRoot.querySelector('lightning-input');
    search.value = 'bravo';
    search.dispatchEvent(new CustomEvent('change'));
    await settle();
    expect(table(element).data.map((r) => r.id)).toEqual(['e2']);

    table(element).dispatchEvent(
      new CustomEvent('rowselection', { detail: { selectedRows: [{ id: 'e2' }] } })
    );
    await settle();

    expect(changed).toHaveBeenCalledTimes(1);
    expect(changed.mock.calls[0][0].detail.selectedIds).toEqual(['e1', 'e2']);
  });

  it('removes a selection when its pill is removed', async () => {
    fetchHumanitixEvents.mockResolvedValue({ page: 1, hasNextPage: false, events: [ev('e1', 'Alpha')] });
    const element = await create({ selectedIds: ['e1', 'gone'] });
    const changed = listen(element);

    pills(element).dispatchEvent(new CustomEvent('itemremove', { detail: { item: { name: 'gone' } } }));
    await settle();

    expect(changed.mock.calls[0][0].detail.selectedIds).toEqual(['e1']);
  });

  it('shows a load failure, keeps the pills, and retries on Refresh', async () => {
    fetchHumanitixEvents.mockRejectedValueOnce({ body: { message: 'Humanitix returned HTTP 401.' } });
    const element = await create({ selectedIds: ['e1'] });

    expect(text(element)).toContain('Humanitix returned HTTP 401.');
    expect(table(element)).toBeNull();
    expect(pills(element).items).toEqual([{ label: 'Unknown event (e1)', name: 'e1' }]);

    fetchHumanitixEvents.mockResolvedValue({ page: 1, hasNextPage: false, events: [ev('e1', 'Alpha')] });
    const refresh = Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find(
      (b) => b.label === 'Refresh'
    );
    refresh.dispatchEvent(new CustomEvent('click'));
    await settle();

    expect(text(element)).not.toContain('Humanitix returned HTTP 401.');
    expect(pills(element).items).toEqual([{ label: 'Alpha', name: 'e1' }]);
  });
});
