import { createElement } from 'lwc';
import HumanitixSetupMappings from 'c/humanitixSetupMappings';
import getObjectMappings from '@salesforce/apex/HumanitixMappingAdminController.getObjectMappings';
import getFieldMappings from '@salesforce/apex/HumanitixMappingAdminController.getFieldMappings';
import validatePending from '@salesforce/apex/HumanitixMappingAdminController.validatePending';
import savePending from '@salesforce/apex/HumanitixMappingAdminController.savePending';
import getDeployStatus from '@salesforce/apex/HumanitixMappingAdminController.getDeployStatus';
import describeTargetFields from '@salesforce/apex/HumanitixMappingAdminController.describeTargetFields';

jest.mock(
  '@salesforce/apex/HumanitixMappingAdminController.getObjectMappings',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/HumanitixMappingAdminController.getFieldMappings',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/HumanitixMappingAdminController.validatePending',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/HumanitixMappingAdminController.savePending',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/HumanitixMappingAdminController.getDeployStatus',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
// The field form child reads the target fields as soon as it mounts.
jest.mock(
  '@salesforce/apex/HumanitixMappingAdminController.describeTargetFields',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const OBJECT_MAPPINGS = [
  {
    devName: 'Event_to_Event',
    label: 'Event to Humanitix Event',
    sourceResource: 'Event',
    collectionPath: null,
    targetSObject: 'Humanitix_Event__c',
    externalIdField: 'Humanitix_Id__c',
    matchStrategy: 'ExternalId',
    matchFieldSet: null,
    updateMode: 'Always',
    loadOrder: 10,
    active: true,
    fieldCount: 12,
    fromDefaults: false
  },
  {
    devName: 'Event_to_Campaign',
    label: 'Event to Campaign',
    sourceResource: 'Event',
    collectionPath: null,
    targetSObject: 'Campaign',
    externalIdField: 'Humanitix_Event_Id__c',
    matchStrategy: 'ExternalId',
    matchFieldSet: null,
    updateMode: 'BlanksOnly',
    loadOrder: 15,
    active: false,
    fieldCount: 6,
    fromDefaults: false
  }
];

const FIELD_MAPPINGS = [
  {
    devName: 'Event_to_Event_01',
    label: 'Event_to_Event :: Humanitix_Id__c',
    objectMapping: 'Event_to_Event',
    sourcePath: '_id',
    targetField: 'Humanitix_Id__c',
    dataType: 'Text',
    transform: 'None',
    transformArg: null,
    isExternalId: true,
    overwriteBlank: true,
    active: true,
    fromDefaults: false
  },
  {
    devName: 'Event_to_Event_02',
    label: 'Event_to_Event :: Name',
    objectMapping: 'Event_to_Event',
    sourcePath: 'name',
    targetField: 'Name',
    dataType: 'Text',
    transform: 'Trim',
    transformArg: null,
    isExternalId: false,
    overwriteBlank: true,
    active: true,
    fromDefaults: false
  }
];

const JOB_ID = '0Afxx0000000001CAA';

function flush() {
  return Promise.resolve();
}

// The list load, a save, the deploy poll and the follow-up re-fetch each
// resolve on their own microtask, so a few ticks are needed before the DOM
// settles.
async function settle() {
  for (let i = 0; i < 10; i++) {
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

function buttonByLabel(element, label) {
  return byLabel(element, 'lightning-button', label);
}

function comboboxByLabel(element, label) {
  return byLabel(element, 'lightning-combobox', label);
}

function datatable(element) {
  return element.shadowRoot.querySelector('lightning-datatable');
}

function fieldForm(element) {
  return element.shadowRoot.querySelector('c-humanitix-mapping-field-form');
}

function text(element) {
  return element.shadowRoot.textContent;
}

function click(element, label) {
  buttonByLabel(element, label).dispatchEvent(new CustomEvent('click'));
}

function rowAction(element, name, row) {
  datatable(element).dispatchEvent(
    new CustomEvent('rowaction', { detail: { action: { name }, row } })
  );
}

async function createAndLoad() {
  const element = createElement('c-humanitix-setup-mappings', { is: HumanitixSetupMappings });
  document.body.appendChild(element);
  await settle();
  return element;
}

// Opens the edit panel on the first mapping, changes the update mode and
// queues it: the shortest path to a pending change.
async function queueUpdateModeEdit(element, updateMode) {
  rowAction(element, 'edit', { ...OBJECT_MAPPINGS[0] });
  await settle();

  const combobox = comboboxByLabel(element, 'Update Mode');
  combobox.value = updateMode;
  combobox.dispatchEvent(new CustomEvent('change', { detail: { value: updateMode } }));
  await settle();

  click(element, 'Queue change');
  await settle();
}

describe('c-humanitix-setup-mappings', () => {
  beforeEach(() => {
    getObjectMappings.mockResolvedValue(OBJECT_MAPPINGS.map((m) => ({ ...m })));
    getFieldMappings.mockResolvedValue(FIELD_MAPPINGS.map((f) => ({ ...f })));
    validatePending.mockResolvedValue([]);
    savePending.mockResolvedValue(null);
    getDeployStatus.mockResolvedValue(null);
    describeTargetFields.mockResolvedValue([]);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.useRealTimers();
    jest.clearAllMocks();
  });

  it('renders the object mappings returned by Apex', async () => {
    const element = await createAndLoad();

    expect(getObjectMappings).toHaveBeenCalledTimes(1);
    const table = datatable(element);
    expect(table).not.toBeNull();
    expect(table.keyField).toBe('devName');
    expect(table.data).toHaveLength(2);
    expect(text(element)).toContain('Mappings cannot be deleted here.');
  });

  it('banners the shipped defaults only while the org has no records', async () => {
    const element = await createAndLoad();
    expect(text(element)).not.toContain('These are the shipped default mappings.');

    document.body.removeChild(element);
    getObjectMappings.mockResolvedValue(
      OBJECT_MAPPINGS.map((m) => ({ ...m, fromDefaults: true }))
    );

    const seeded = await createAndLoad();
    expect(text(seeded)).toContain(
      'These are the shipped default mappings. Your first save copies all defaults into this org as custom metadata records.'
    );
  });

  it('queues an object mapping edit from the inline panel', async () => {
    const element = await createAndLoad();
    expect(text(element)).not.toContain('change pending');

    rowAction(element, 'edit', { ...OBJECT_MAPPINGS[0] });
    await settle();

    expect(comboboxByLabel(element, 'Match Strategy').value).toBe('ExternalId');
    expect(comboboxByLabel(element, 'Update Mode').value).toBe('Always');
    expect(text(element)).toContain('Humanitix_Id__c');

    const combobox = comboboxByLabel(element, 'Update Mode');
    combobox.value = 'BlanksOnly';
    combobox.dispatchEvent(new CustomEvent('change', { detail: { value: 'BlanksOnly' } }));
    await settle();

    click(element, 'Queue change');
    await settle();

    expect(text(element)).toContain('1 change pending');
    // The panel closes once the change is queued.
    expect(comboboxByLabel(element, 'Update Mode')).toBeNull();
  });

  it('serializes the queued changes into pendingJson', async () => {
    const element = await createAndLoad();
    await queueUpdateModeEdit(element, 'BlanksOnly');

    // A second queued row: the deactivate action flips active on its own.
    rowAction(element, 'toggle', { ...OBJECT_MAPPINGS[1] });
    await settle();
    expect(text(element)).toContain('2 changes pending');

    click(element, 'Save All');
    await settle();

    expect(savePending).toHaveBeenCalledTimes(1);
    const payload = JSON.parse(savePending.mock.calls[0][0].pendingJson);
    expect(payload.fieldMappings).toEqual([]);
    expect(payload.objectMappings).toHaveLength(2);

    const edited = payload.objectMappings[0];
    expect(edited.devName).toBe('Event_to_Event');
    expect(edited.updateMode).toBe('BlanksOnly');
    expect(edited.matchStrategy).toBe('ExternalId');
    expect(edited.targetSObject).toBe('Humanitix_Event__c');
    expect(edited.loadOrder).toBe(10);
    expect(edited.active).toBe(true);
    // Read-only extras never travel: Apex deserializes into a typed DTO.
    expect(edited.fieldCount).toBeUndefined();

    expect(payload.objectMappings[1].devName).toBe('Event_to_Campaign');
    expect(payload.objectMappings[1].active).toBe(true);
  });

  it('polls the deploy, then clears the pending list and reloads', async () => {
    jest.useFakeTimers();
    savePending.mockResolvedValue(JOB_ID);
    getDeployStatus
      .mockResolvedValueOnce({ Status__c: 'Pending', Error_Detail__c: null })
      .mockResolvedValue({ Status__c: 'Succeeded', Error_Detail__c: null });

    const element = await createAndLoad();
    await queueUpdateModeEdit(element, 'Never');

    click(element, 'Save All');
    await settle();

    expect(getDeployStatus).toHaveBeenCalledWith({ jobId: JOB_ID });
    expect(text(element)).toContain('Saving mappings. Custom metadata deploys take a few seconds.');

    await jest.advanceTimersByTimeAsync(2000);
    await settle();

    expect(getObjectMappings).toHaveBeenCalledTimes(2);
    expect(text(element)).not.toContain('change pending');
    expect(text(element)).not.toContain('Saving mappings. Custom metadata deploys');
  });

  it('renders the problems returned by the validate call', async () => {
    validatePending.mockResolvedValue([
      'Object Mapping "Event_to_Event": unknown target field "Nope__c".',
      'Field Mapping on "Event_to_Event": needs a target field.'
    ]);

    const element = await createAndLoad();
    await queueUpdateModeEdit(element, 'BlanksOnly');

    click(element, 'Validate');
    await settle();

    expect(validatePending).toHaveBeenCalledTimes(1);
    expect(text(element)).toContain('unknown target field "Nope__c"');
    expect(text(element)).toContain('needs a target field');
    expect(savePending).not.toHaveBeenCalled();
  });

  it('drills into the field mappings and opens the create form', async () => {
    const element = await createAndLoad();

    rowAction(element, 'view', { ...OBJECT_MAPPINGS[0] });
    await settle();

    expect(getFieldMappings).toHaveBeenCalledWith({ objectMappingDevName: 'Event_to_Event' });
    expect(datatable(element).data).toHaveLength(2);
    expect(text(element)).toContain('Event to Humanitix Event');
    expect(fieldForm(element)).toBeNull();

    click(element, 'New Field Mapping');
    await settle();

    const form = fieldForm(element);
    expect(form).not.toBeNull();
    expect(form.parentDevName).toBe('Event_to_Event');
    expect(form.targetSObject).toBe('Humanitix_Event__c');
    expect(form.mapping).toBeNull();

    click(element, 'Back to mappings');
    await settle();
    expect(datatable(element).data).toHaveLength(2);
    expect(buttonByLabel(element, 'New Field Mapping')).toBeNull();
  });

  it('queues a field mapping from the child form', async () => {
    const element = await createAndLoad();

    rowAction(element, 'view', { ...OBJECT_MAPPINGS[0] });
    await settle();
    click(element, 'New Field Mapping');
    await settle();

    fieldForm(element).dispatchEvent(
      new CustomEvent('queue', {
        detail: {
          devName: '',
          label: null,
          objectMapping: 'Event_to_Event',
          sourcePath: 'eventName',
          targetField: 'Name',
          dataType: 'Text',
          transform: 'None',
          transformArg: null,
          isExternalId: false,
          overwriteBlank: true,
          active: true
        }
      })
    );
    await settle();

    expect(fieldForm(element)).toBeNull();
    expect(text(element)).toContain('1 change pending');

    click(element, 'Save All');
    await settle();

    const payload = JSON.parse(savePending.mock.calls[0][0].pendingJson);
    expect(payload.objectMappings).toEqual([]);
    expect(payload.fieldMappings).toHaveLength(1);
    expect(payload.fieldMappings[0].devName).toBe('');
    expect(payload.fieldMappings[0].objectMapping).toBe('Event_to_Event');
    expect(payload.fieldMappings[0].targetField).toBe('Name');
  });

  it('discards the pending list without calling Apex', async () => {
    const element = await createAndLoad();
    await queueUpdateModeEdit(element, 'BlanksOnly');

    click(element, 'Discard');
    await settle();

    expect(text(element)).not.toContain('change pending');
    expect(savePending).not.toHaveBeenCalled();
    expect(validatePending).not.toHaveBeenCalled();
  });

  it('reports a rejected save and keeps the pending list', async () => {
    savePending.mockRejectedValue({
      body: { message: 'Fix these problems before saving: unknown target field.' }
    });

    const element = await createAndLoad();
    await queueUpdateModeEdit(element, 'BlanksOnly');

    click(element, 'Save All');
    await settle();

    expect(getDeployStatus).not.toHaveBeenCalled();
    expect(getObjectMappings).toHaveBeenCalledTimes(1);
    expect(text(element)).toContain('1 change pending');
    expect(buttonByLabel(element, 'Save All').disabled).toBe(false);
  });

  it('surfaces the error detail when the deploy fails', async () => {
    jest.useFakeTimers();
    savePending.mockResolvedValue(JOB_ID);
    getDeployStatus
      .mockResolvedValueOnce({ Status__c: 'Pending', Error_Detail__c: null })
      .mockResolvedValue({
        Status__c: 'Failed',
        Error_Detail__c: 'Match_Field_Set__c: bad value for restricted picklist.'
      });

    const element = await createAndLoad();
    await queueUpdateModeEdit(element, 'BlanksOnly');

    click(element, 'Save All');
    await settle();
    await jest.advanceTimersByTimeAsync(2000);
    await settle();

    const notification = element.shadowRoot.querySelector('.slds-theme_error');
    expect(notification).not.toBeNull();
    expect(notification.textContent).toContain('bad value for restricted picklist');
    expect(getObjectMappings).toHaveBeenCalledTimes(1);
    expect(text(element)).toContain('1 change pending');
  });
});
