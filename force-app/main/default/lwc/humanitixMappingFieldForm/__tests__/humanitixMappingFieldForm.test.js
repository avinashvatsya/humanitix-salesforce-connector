import { createElement } from 'lwc';
import HumanitixMappingFieldForm from 'c/humanitixMappingFieldForm';
import describeTargetFields from '@salesforce/apex/HumanitixMappingAdminController.describeTargetFields';

jest.mock(
  '@salesforce/apex/HumanitixMappingAdminController.describeTargetFields',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const TARGET_FIELDS = [
  { value: 'Humanitix_Id__c', label: 'Humanitix Id (Humanitix_Id__c)', type: 'STRING' },
  { value: 'Humanitix_Event__c', label: 'Event (Humanitix_Event__c)', type: 'REFERENCE' },
  { value: 'Name', label: 'Name (Name)', type: 'STRING' }
];

const EXISTING = {
  devName: 'Event_to_Event_05',
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
  fromDefaults: true
};

function flush() {
  return Promise.resolve();
}

// The describe call and the re-render of its options each resolve on their own
// microtask, so a few ticks are needed before the DOM settles.
async function settle() {
  for (let i = 0; i < 6; i++) {
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

function comboboxByLabel(element, label) {
  return byLabel(element, 'lightning-combobox', label);
}

function buttonByLabel(element, label) {
  return byLabel(element, 'lightning-button', label);
}

function text(element) {
  return element.shadowRoot.textContent;
}

function setInput(element, label, value) {
  const input = inputByLabel(element, label);
  input.value = value;
  input.dispatchEvent(new CustomEvent('change'));
}

function chooseCombobox(element, label, value) {
  const combobox = comboboxByLabel(element, label);
  combobox.value = value;
  combobox.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

function click(element, label) {
  buttonByLabel(element, label).dispatchEvent(new CustomEvent('click'));
}

async function create(props) {
  const element = createElement('c-humanitix-mapping-field-form', {
    is: HumanitixMappingFieldForm
  });
  Object.assign(element, { parentDevName: 'Event_to_Event', targetSObject: 'Humanitix_Event__c' });
  Object.assign(element, props || {});
  document.body.appendChild(element);
  await settle();
  return element;
}

function listenForQueue(element) {
  const handler = jest.fn();
  element.addEventListener('queue', handler);
  return handler;
}

describe('c-humanitix-mapping-field-form', () => {
  beforeEach(() => {
    describeTargetFields.mockResolvedValue([...TARGET_FIELDS]);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('renders the target field options returned by Apex', async () => {
    const element = await create();

    expect(describeTargetFields).toHaveBeenCalledWith({ sobjectApiName: 'Humanitix_Event__c' });
    const combobox = comboboxByLabel(element, 'Target Field');
    expect(combobox.options).toHaveLength(3);
    expect(combobox.options[0]).toEqual({
      label: 'Humanitix Id (Humanitix_Id__c)',
      value: 'Humanitix_Id__c'
    });
    expect(text(element)).toContain('New Field Mapping');
  });

  it('queues a create with a blank devName and the parent mapping', async () => {
    const element = await create();
    const queued = listenForQueue(element);

    setInput(element, 'Source Path', 'name');
    chooseCombobox(element, 'Target Field', 'Name');
    await settle();

    click(element, 'Queue change');
    await settle();

    expect(queued).toHaveBeenCalledTimes(1);
    const dto = queued.mock.calls[0][0].detail;
    expect(dto.devName).toBe('');
    expect(dto.objectMapping).toBe('Event_to_Event');
    expect(dto.sourcePath).toBe('name');
    expect(dto.targetField).toBe('Name');
    expect(dto.dataType).toBe('Text');
    expect(dto.transform).toBe('None');
    expect(dto.transformArg).toBeNull();
    expect(dto.defaultSourcePath).toBeNull();
    expect(dto.defaultValue).toBeNull();
    expect(dto.overwriteBlank).toBe(true);
    expect(dto.active).toBe(true);
  });

  it('pre-fills an edit and keeps the original devName', async () => {
    const element = await create({ mapping: { ...EXISTING } });

    expect(inputByLabel(element, 'Source Path').value).toBe('name');
    expect(comboboxByLabel(element, 'Target Field').value).toBe('Name');
    expect(comboboxByLabel(element, 'Transform').value).toBe('Trim');
    expect(text(element)).toContain('Edit Field Mapping');

    const queued = listenForQueue(element);
    setInput(element, 'Source Path', 'eventName');
    await settle();

    click(element, 'Queue change');
    await settle();

    const dto = queued.mock.calls[0][0].detail;
    expect(dto.devName).toBe('Event_to_Event_05');
    expect(dto.label).toBe('Event_to_Event :: Name');
    expect(dto.objectMapping).toBe('Event_to_Event');
    expect(dto.sourcePath).toBe('eventName');
  });

  it('blocks a queue with no target field and shows the problem', async () => {
    const element = await create();
    const queued = listenForQueue(element);

    setInput(element, 'Source Path', 'name');
    await settle();

    click(element, 'Queue change');
    await settle();

    expect(queued).not.toHaveBeenCalled();
    expect(text(element)).toContain('Choose a target field.');
  });

  it('hides the transform arg until it is needed and blocks a dotless reference arg', async () => {
    const element = await create();

    expect(inputByLabel(element, 'Transform Arg')).toBeNull();

    chooseCombobox(element, 'Transform', 'StaticValue');
    await settle();
    expect(inputByLabel(element, 'Transform Arg')).not.toBeNull();

    chooseCombobox(element, 'Transform', 'None');
    chooseCombobox(element, 'Data Type', 'Reference');
    await settle();
    // A Reference field carries its arg with no transform, so the box comes back.
    expect(inputByLabel(element, 'Transform Arg')).not.toBeNull();

    const queued = listenForQueue(element);
    setInput(element, 'Source Path', '$parent._id');
    chooseCombobox(element, 'Target Field', 'Humanitix_Event__c');
    setInput(element, 'Transform Arg', 'Humanitix_Event__c');
    await settle();

    click(element, 'Queue change');
    await settle();

    expect(queued).not.toHaveBeenCalled();
    expect(text(element)).toContain('Object.ExternalIdField');

    setInput(element, 'Transform Arg', 'Humanitix_Event__c.Humanitix_Id__c');
    await settle();

    click(element, 'Queue change');
    await settle();

    expect(queued).toHaveBeenCalledTimes(1);
    expect(queued.mock.calls[0][0].detail.transformArg).toBe(
      'Humanitix_Event__c.Humanitix_Id__c'
    );
  });

  it('dispatches cancel without queueing anything', async () => {
    const element = await create();
    const queued = listenForQueue(element);
    const cancelled = jest.fn();
    element.addEventListener('cancel', cancelled);

    click(element, 'Cancel');
    await settle();

    expect(cancelled).toHaveBeenCalledTimes(1);
    expect(queued).not.toHaveBeenCalled();
  });

  it('renders the default inputs and queues them trimmed in the DTO', async () => {
    const element = await create();
    const queued = listenForQueue(element);

    expect(inputByLabel(element, 'Default Source Path')).not.toBeNull();
    expect(inputByLabel(element, 'Default Value')).not.toBeNull();

    setInput(element, 'Source Path', 'organisation');
    chooseCombobox(element, 'Target Field', 'Name');
    setInput(element, 'Default Source Path', ' _id ');
    setInput(element, 'Default Value', ' Unknown ');
    await settle();

    click(element, 'Queue change');
    await settle();

    expect(queued).toHaveBeenCalledTimes(1);
    const dto = queued.mock.calls[0][0].detail;
    expect(dto.defaultSourcePath).toBe('_id');
    expect(dto.defaultValue).toBe('Unknown');
  });

  it('accepts a mapping with no source path when a default is set', async () => {
    const element = await create();
    const queued = listenForQueue(element);

    chooseCombobox(element, 'Target Field', 'Name');
    setInput(element, 'Default Value', 'Unknown');
    await settle();

    click(element, 'Queue change');
    await settle();

    expect(queued).toHaveBeenCalledTimes(1);
    const dto = queued.mock.calls[0][0].detail;
    expect(dto.sourcePath).toBeNull();
    expect(dto.defaultValue).toBe('Unknown');
  });

  it('still blocks a mapping with neither a source path nor a default', async () => {
    const element = await create();
    const queued = listenForQueue(element);

    chooseCombobox(element, 'Target Field', 'Name');
    await settle();

    click(element, 'Queue change');
    await settle();

    expect(queued).not.toHaveBeenCalled();
    expect(text(element)).toContain('Enter a source path');
  });

  it('pre-fills the defaults of an existing mapping', async () => {
    const element = await create({
      mapping: { ...EXISTING, defaultSourcePath: '_id', defaultValue: 'Unknown' }
    });

    expect(inputByLabel(element, 'Default Source Path').value).toBe('_id');
    expect(inputByLabel(element, 'Default Value').value).toBe('Unknown');
  });

  it('hides the default inputs for StaticValue, drops them from the DTO, and requires the literal', async () => {
    const element = await create({
      mapping: { ...EXISTING, defaultSourcePath: '_id', defaultValue: 'Unknown' }
    });
    const queued = listenForQueue(element);

    chooseCombobox(element, 'Transform', 'StaticValue');
    await settle();
    expect(inputByLabel(element, 'Default Source Path')).toBeNull();
    expect(inputByLabel(element, 'Default Value')).toBeNull();

    click(element, 'Queue change');
    await settle();
    expect(queued).not.toHaveBeenCalled();
    expect(text(element)).toContain('StaticValue writes the literal in Transform Arg');

    setInput(element, 'Transform Arg', 'In Progress');
    await settle();
    click(element, 'Queue change');
    await settle();

    expect(queued).toHaveBeenCalledTimes(1);
    const dto = queued.mock.calls[0][0].detail;
    expect(dto.transform).toBe('StaticValue');
    expect(dto.transformArg).toBe('In Progress');
    expect(dto.defaultSourcePath).toBeNull();
    expect(dto.defaultValue).toBeNull();
  });
});
