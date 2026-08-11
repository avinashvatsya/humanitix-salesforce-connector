import { LightningElement, api } from 'lwc';
import { errorMessage, showToast } from 'c/humanitixSetupUtils';
import describeTargetFields from '@salesforce/apex/HumanitixMappingAdminController.describeTargetFields';

const DATA_TYPE_OPTIONS = [
  { label: 'Text', value: 'Text' },
  { label: 'LongText', value: 'LongText' },
  { label: 'DateTime', value: 'DateTime' },
  { label: 'Date', value: 'Date' },
  { label: 'Decimal', value: 'Decimal' },
  { label: 'Currency', value: 'Currency' },
  { label: 'Integer', value: 'Integer' },
  { label: 'Boolean', value: 'Boolean' },
  { label: 'Email', value: 'Email' },
  { label: 'Phone', value: 'Phone' },
  { label: 'Url', value: 'Url' },
  { label: 'Reference', value: 'Reference' }
];

const TRANSFORM_OPTIONS = [
  { label: 'None', value: 'None' },
  { label: 'Trim', value: 'Trim' },
  { label: 'Upper', value: 'Upper' },
  { label: 'Lower', value: 'Lower' },
  { label: 'IsoToDateTime', value: 'IsoToDateTime' },
  { label: 'IsoToDateInTz', value: 'IsoToDateInTz' },
  { label: 'DecimalMoney', value: 'DecimalMoney' },
  { label: 'BoolMap', value: 'BoolMap' },
  { label: 'StaticValue', value: 'StaticValue' },
  { label: 'Concat', value: 'Concat' },
  { label: 'JoinArray', value: 'JoinArray' },
  { label: 'ToJson', value: 'ToJson' }
];

const NOTIFICATION_BASE = 'slds-scoped-notification slds-media slds-media_center';

const NO_TARGET_FIELD = 'Choose a target field.';
const NO_SOURCE_PATH = 'Enter a source path, or choose the StaticValue transform.';
const BAD_REFERENCE =
  'A Reference field needs a transform arg in the form Object.ExternalIdField, for example Humanitix_Event__c.Humanitix_Id__c.';

function hasText(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

function trimmedOrNull(value) {
  return hasText(value) ? value.trim() : null;
}

/**
 * Modal editor for one field mapping. It owns no data of its own: the parent
 * hands it a DTO (or nothing, for a create) and gets a ready-to-queue DTO back
 * on the queue event. Nothing here talks to the save API, so a cancelled edit
 * costs nothing.
 */
export default class HumanitixMappingFieldForm extends LightningElement {
  @api mapping;
  @api parentDevName;
  @api targetSObject;

  dataTypeOptions = DATA_TYPE_OPTIONS;
  transformOptions = TRANSFORM_OPTIONS;
  targetFieldOptions = [];

  isLoadingFields = true;
  problems = [];

  sourcePath = '';
  targetField = '';
  dataType = 'Text';
  transform = 'None';
  transformArg = '';
  isExternalId = false;
  overwriteBlank = true;
  active = true;

  connectedCallback() {
    this.applyMapping();
    this.loadTargetFields();
  }

  get isCreate() {
    return !this.mapping || !this.mapping.devName;
  }

  get heading() {
    return this.isCreate ? 'New Field Mapping' : 'Edit Field Mapping';
  }

  get subheading() {
    return 'Target object ' + (this.targetSObject || 'not set') + '.';
  }

  /**
   * The arg box follows the transform, but a Reference field carries its
   * Object.ExternalIdField arg even with no transform, so that data type has to
   * be able to reveal the box on its own.
   */
  get showTransformArg() {
    return this.transform !== 'None' || this.dataType === 'Reference';
  }

  get hasProblems() {
    return this.problems.length > 0;
  }

  get problemClass() {
    return NOTIFICATION_BASE + ' slds-theme_error slds-m-bottom_medium';
  }

  get loadingFieldsText() {
    return 'Loading the fields on ' + (this.targetSObject || 'the target object') + '.';
  }

  applyMapping() {
    const dto = this.mapping || {};
    this.sourcePath = dto.sourcePath || '';
    this.targetField = dto.targetField || '';
    this.dataType = dto.dataType || 'Text';
    this.transform = dto.transform || 'None';
    this.transformArg = dto.transformArg || '';
    this.isExternalId = dto.isExternalId === true;
    // Both flags default on for a new mapping, which is what Apex assumes for a
    // blank record too.
    this.overwriteBlank = this.mapping ? dto.overwriteBlank === true : true;
    this.active = this.mapping ? dto.active === true : true;
  }

  async loadTargetFields() {
    this.isLoadingFields = true;
    try {
      const fields = await describeTargetFields({ sobjectApiName: this.targetSObject });
      this.targetFieldOptions = (fields || []).map((f) => ({ label: f.label, value: f.value }));
    } catch (error) {
      this.targetFieldOptions = [];
      showToast(this, 'Could not read the target fields', errorMessage(error), 'error');
    } finally {
      this.isLoadingFields = false;
    }
  }

  handleSourcePathChange(event) {
    this.sourcePath = event.target.value;
  }

  handleTargetFieldChange(event) {
    this.targetField = event.detail ? event.detail.value : event.target.value;
  }

  handleDataTypeChange(event) {
    this.dataType = event.detail ? event.detail.value : event.target.value;
  }

  handleTransformChange(event) {
    this.transform = event.detail ? event.detail.value : event.target.value;
  }

  handleTransformArgChange(event) {
    this.transformArg = event.target.value;
  }

  handleExternalIdChange(event) {
    this.isExternalId = event.target.checked === true;
  }

  handleOverwriteBlankChange(event) {
    this.overwriteBlank = event.target.checked === true;
  }

  handleActiveChange(event) {
    this.active = event.target.checked === true;
  }

  /** Cheap client checks; the server validates the whole candidate config again. */
  validate() {
    const problems = [];
    if (!hasText(this.targetField)) {
      problems.push(NO_TARGET_FIELD);
    }
    if (this.transform !== 'StaticValue' && !hasText(this.sourcePath)) {
      problems.push(NO_SOURCE_PATH);
    }
    if (this.dataType === 'Reference' && this.transformArg.indexOf('.') < 1) {
      problems.push(BAD_REFERENCE);
    }
    return problems;
  }

  buildDto() {
    return {
      devName: this.isCreate ? '' : this.mapping.devName,
      label: this.mapping ? this.mapping.label : null,
      objectMapping: this.parentDevName,
      sourcePath: trimmedOrNull(this.sourcePath),
      targetField: trimmedOrNull(this.targetField),
      dataType: this.dataType,
      transform: this.transform,
      transformArg: trimmedOrNull(this.transformArg),
      isExternalId: this.isExternalId === true,
      overwriteBlank: this.overwriteBlank === true,
      active: this.active === true
    };
  }

  handleQueue() {
    this.problems = this.validate();
    if (this.problems.length > 0) {
      return;
    }
    this.dispatchEvent(new CustomEvent('queue', { detail: this.buildDto() }));
  }

  handleCancel() {
    this.dispatchEvent(new CustomEvent('cancel'));
  }
}
