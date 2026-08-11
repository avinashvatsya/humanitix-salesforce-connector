import { LightningElement } from 'lwc';
import { errorMessage, showToast, pollDeploy } from 'c/humanitixSetupUtils';
import getObjectMappings from '@salesforce/apex/HumanitixMappingAdminController.getObjectMappings';
import getFieldMappings from '@salesforce/apex/HumanitixMappingAdminController.getFieldMappings';
import validatePending from '@salesforce/apex/HumanitixMappingAdminController.validatePending';
import savePending from '@salesforce/apex/HumanitixMappingAdminController.savePending';
import getDeployStatus from '@salesforce/apex/HumanitixMappingAdminController.getDeployStatus';

const MATCH_STRATEGY_OPTIONS = [
  { label: 'ExternalId', value: 'ExternalId' },
  { label: 'MatchByFields', value: 'MatchByFields' },
  { label: 'AlwaysCreate', value: 'AlwaysCreate' }
];

const UPDATE_MODE_OPTIONS = [
  { label: 'Always', value: 'Always' },
  { label: 'BlanksOnly', value: 'BlanksOnly' },
  { label: 'Never', value: 'Never' }
];

/** Built per row so the toggle reads Deactivate on an active mapping. */
function objectRowActions(row, doneCallback) {
  doneCallback([
    { label: 'View fields', name: 'view' },
    { label: 'Edit', name: 'edit' },
    { label: row.active ? 'Deactivate' : 'Activate', name: 'toggle' }
  ]);
}

function fieldRowActions(row, doneCallback) {
  doneCallback([
    { label: 'Edit', name: 'edit' },
    { label: row.active ? 'Deactivate' : 'Activate', name: 'toggle' }
  ]);
}

const OBJECT_COLUMNS = [
  { label: 'Mapping', fieldName: 'label' },
  { label: 'Resource', fieldName: 'sourceResource' },
  { label: 'Target', fieldName: 'targetSObject' },
  { label: 'Strategy', fieldName: 'matchStrategy' },
  { label: 'Update Mode', fieldName: 'updateMode' },
  { label: 'Order', fieldName: 'loadOrder', type: 'number' },
  { label: 'Fields', fieldName: 'fieldCount', type: 'number' },
  { label: 'Active', fieldName: 'active', type: 'boolean' },
  { type: 'action', typeAttributes: { rowActions: objectRowActions } }
];

const FIELD_COLUMNS = [
  { label: 'Field', fieldName: 'label' },
  { label: 'Source Path', fieldName: 'sourcePath' },
  { label: 'Target Field', fieldName: 'targetField' },
  { label: 'Type', fieldName: 'dataType' },
  { label: 'Transform', fieldName: 'transform' },
  { label: 'Active', fieldName: 'active', type: 'boolean' },
  { type: 'action', typeAttributes: { rowActions: fieldRowActions } }
];

const DEFAULTS_BANNER =
  'These are the shipped default mappings. Your first save copies all defaults into this org as custom metadata records.';
const DEPLOYING = 'Saving mappings. Custom metadata deploys take a few seconds.';
const SAVED = 'The mapping metadata has been updated.';
const STILL_DEPLOYING =
  'The deployment is taking longer than expected. Check Setup, Deployment Status.';
const DEPLOY_FAILED = 'The mapping deployment did not complete. Check Setup, Deployment Status.';
const NO_PROBLEMS = 'The pending changes are ready to save.';
const NOTIFICATION_BASE = 'slds-scoped-notification slds-media slds-media_center';

/** Number inputs hand back strings; an empty box means "no value", not zero. */
function toNumber(value) {
  if (value === '' || value === null || value === undefined) {
    return null;
  }
  const parsed = Number(value);
  return isNaN(parsed) ? null : parsed;
}

function blankToNull(value) {
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : null;
}

/**
 * Only the keys Apex knows about may travel in pendingJson: the controller
 * deserializes it into a typed DTO, so a stray UI-only key fails the parse.
 */
function objectDto(row, overrides) {
  return {
    devName: row.devName,
    label: row.label,
    sourceResource: row.sourceResource,
    collectionPath: row.collectionPath,
    targetSObject: row.targetSObject,
    externalIdField: row.externalIdField,
    matchStrategy: row.matchStrategy,
    matchFieldSet: row.matchFieldSet,
    updateMode: row.updateMode,
    loadOrder: row.loadOrder,
    active: row.active === true,
    ...(overrides || {})
  };
}

function fieldDto(row, overrides) {
  return {
    devName: row.devName,
    label: row.label,
    objectMapping: row.objectMapping,
    sourcePath: row.sourcePath,
    targetField: row.targetField,
    dataType: row.dataType,
    transform: row.transform,
    transformArg: row.transformArg,
    isExternalId: row.isExternalId === true,
    overwriteBlank: row.overwriteBlank === true,
    active: row.active === true,
    ...(overrides || {})
  };
}

/**
 * Mappings tab: browse the object mappings, drill into their field mappings,
 * and edit either. Edits are queued locally rather than saved one at a time,
 * because every save is a custom metadata deployment: one deploy for a batch of
 * changes is both faster and safer than one deploy per row. Nothing here can
 * delete a mapping, since custom metadata records cannot be deleted from Apex
 * and a deleted shipped record comes back on the next upgrade anyway.
 */
export default class HumanitixSetupMappings extends LightningElement {
  matchStrategyOptions = MATCH_STRATEGY_OPTIONS;
  updateModeOptions = UPDATE_MODE_OPTIONS;
  objectColumns = OBJECT_COLUMNS;
  fieldColumns = FIELD_COLUMNS;
  pollOptions = { intervalMs: 2000, timeoutMs: 120000 };

  isLoading = true;
  isLoadingFields = false;
  isSaving = false;
  isValidating = false;

  objectMappings = [];
  fieldMappings = [];
  selectedMapping;

  pendingObjects = [];
  pendingFields = [];
  problems = [];
  deployStatus;
  deployError;

  showEditPanel = false;
  showFieldForm = false;
  fieldFormMapping = null;

  editBase;
  editMatchStrategy = 'ExternalId';
  editMatchFieldSet = '';
  editUpdateMode = 'Always';
  editLoadOrder;
  editActive = true;

  // The mapping controller exposes the ledger read as getDeployStatus(jobId),
  // while pollDeploy hands its fetcher a { deployJobId } bag.
  fetchDeployStatus = ({ deployJobId }) => getDeployStatus({ jobId: deployJobId });

  connectedCallback() {
    this.loadObjectMappings();
  }

  // ---- derived state -----------------------------------------------------

  get isFieldView() {
    return !!this.selectedMapping;
  }

  get hasObjectMappings() {
    return this.objectMappings.length > 0;
  }

  get hasFieldMappings() {
    return this.fieldMappings.length > 0;
  }

  get showDefaultsBanner() {
    return this.objectMappings.some((m) => m.fromDefaults === true);
  }

  get defaultsBannerText() {
    return DEFAULTS_BANNER;
  }

  get pendingCount() {
    return this.pendingObjects.length + this.pendingFields.length;
  }

  get hasPending() {
    return this.pendingCount > 0;
  }

  get pendingLabel() {
    const count = this.pendingCount;
    return count === 1 ? '1 change pending' : count + ' changes pending';
  }

  get isBusy() {
    return this.isSaving || this.isValidating;
  }

  get hasProblems() {
    return this.problems.length > 0;
  }

  get hasDeployError() {
    return !!this.deployError;
  }

  get bannerClass() {
    return NOTIFICATION_BASE + ' slds-theme_info slds-m-bottom_medium';
  }

  get problemClass() {
    return NOTIFICATION_BASE + ' slds-theme_warning slds-m-bottom_medium';
  }

  get deployErrorClass() {
    return NOTIFICATION_BASE + ' slds-theme_error slds-m-bottom_medium';
  }

  get fieldViewTitle() {
    return 'Mappings > ' + (this.selectedMapping ? this.selectedMapping.label : '');
  }

  get selectedDevName() {
    return this.selectedMapping ? this.selectedMapping.devName : '';
  }

  get selectedTargetSObject() {
    return this.selectedMapping ? this.selectedMapping.targetSObject : '';
  }

  get editHeading() {
    return this.editBase ? 'Edit ' + this.editBase.label : 'Edit mapping';
  }

  get editResource() {
    return this.editBase ? this.editBase.sourceResource : '';
  }

  get editTargetSObject() {
    return this.editBase ? this.editBase.targetSObject : '';
  }

  get editExternalIdField() {
    return this.editBase && this.editBase.externalIdField ? this.editBase.externalIdField : 'None';
  }

  // ---- loading -----------------------------------------------------------

  async loadObjectMappings() {
    this.isLoading = true;
    try {
      this.objectMappings = (await getObjectMappings()) || [];
    } catch (error) {
      showToast(this, 'Could not load the mappings', errorMessage(error), 'error');
    } finally {
      this.isLoading = false;
    }
  }

  async loadFieldMappings(devName) {
    this.isLoadingFields = true;
    try {
      this.fieldMappings = (await getFieldMappings({ objectMappingDevName: devName })) || [];
    } catch (error) {
      this.fieldMappings = [];
      showToast(this, 'Could not load the field mappings', errorMessage(error), 'error');
    } finally {
      this.isLoadingFields = false;
    }
  }

  async reload() {
    await this.loadObjectMappings();
    if (this.selectedMapping) {
      const devName = this.selectedMapping.devName;
      const fresh = this.objectMappings.find((m) => m.devName === devName);
      if (fresh) {
        this.selectedMapping = fresh;
      }
      await this.loadFieldMappings(devName);
    }
  }

  // ---- object mapping rows -----------------------------------------------

  handleObjectRowAction(event) {
    const action = event.detail.action;
    const row = event.detail.row;
    if (action.name === 'view') {
      this.openFieldView(row);
    } else if (action.name === 'edit') {
      this.openEditPanel(row);
    } else if (action.name === 'toggle') {
      const base = this.pendingObjectFor(row.devName) || row;
      this.queueObject(objectDto(base, { active: !(base.active === true) }));
    }
  }

  openFieldView(row) {
    this.selectedMapping = row;
    this.showEditPanel = false;
    this.fieldMappings = [];
    this.loadFieldMappings(row.devName);
  }

  handleBack() {
    this.selectedMapping = undefined;
    this.fieldMappings = [];
    this.showFieldForm = false;
    this.fieldFormMapping = null;
  }

  /** A queued edit is the truer starting point than the row from the server. */
  openEditPanel(row) {
    const base = this.pendingObjectFor(row.devName) || row;
    this.editBase = objectDto(row);
    this.editMatchStrategy = base.matchStrategy || 'ExternalId';
    this.editMatchFieldSet = base.matchFieldSet || '';
    this.editUpdateMode = base.updateMode || 'Always';
    this.editLoadOrder = base.loadOrder;
    this.editActive = base.active === true;
    this.showEditPanel = true;
  }

  handleMatchStrategyChange(event) {
    this.editMatchStrategy = event.detail ? event.detail.value : event.target.value;
  }

  handleMatchFieldSetChange(event) {
    this.editMatchFieldSet = event.target.value;
  }

  handleUpdateModeChange(event) {
    this.editUpdateMode = event.detail ? event.detail.value : event.target.value;
  }

  handleLoadOrderChange(event) {
    this.editLoadOrder = toNumber(event.target.value);
  }

  handleActiveChange(event) {
    this.editActive = event.target.checked === true;
  }

  handleQueueObject() {
    this.queueObject(
      objectDto(this.editBase, {
        matchStrategy: this.editMatchStrategy,
        matchFieldSet: blankToNull(this.editMatchFieldSet),
        updateMode: this.editUpdateMode,
        loadOrder: this.editLoadOrder,
        active: this.editActive === true
      })
    );
    this.closeEditPanel();
  }

  handleCancelEdit() {
    this.closeEditPanel();
  }

  closeEditPanel() {
    this.showEditPanel = false;
    this.editBase = undefined;
  }

  // ---- field mapping rows ------------------------------------------------

  handleFieldRowAction(event) {
    const action = event.detail.action;
    const row = event.detail.row;
    if (action.name === 'edit') {
      this.fieldFormMapping = this.pendingFieldFor(row.devName) || fieldDto(row);
      this.showFieldForm = true;
    } else if (action.name === 'toggle') {
      const base = this.pendingFieldFor(row.devName) || row;
      this.queueField(fieldDto(base, { active: !(base.active === true) }));
    }
  }

  handleNewField() {
    this.fieldFormMapping = null;
    this.showFieldForm = true;
  }

  handleFieldQueue(event) {
    this.queueField(event.detail);
    this.closeFieldForm();
  }

  handleFieldFormCancel() {
    this.closeFieldForm();
  }

  closeFieldForm() {
    this.showFieldForm = false;
    this.fieldFormMapping = null;
  }

  // ---- pending list ------------------------------------------------------

  pendingObjectFor(devName) {
    return this.pendingObjects.find((m) => m.devName === devName);
  }

  pendingFieldFor(devName) {
    return devName ? this.pendingFields.find((f) => f.devName === devName) : undefined;
  }

  queueObject(dto) {
    const next = [...this.pendingObjects];
    const index = next.findIndex((m) => m.devName === dto.devName);
    if (index >= 0) {
      next[index] = dto;
    } else {
      next.push(dto);
    }
    this.pendingObjects = next;
  }

  /** Creates carry a blank devName, so each one is its own pending entry. */
  queueField(dto) {
    const next = [...this.pendingFields];
    const index = dto.devName ? next.findIndex((f) => f.devName === dto.devName) : -1;
    if (index >= 0) {
      next[index] = dto;
    } else {
      next.push(dto);
    }
    this.pendingFields = next;
  }

  clearPending() {
    this.pendingObjects = [];
    this.pendingFields = [];
    this.problems = [];
  }

  handleDiscard() {
    this.clearPending();
    this.deployError = undefined;
  }

  buildPendingJson() {
    return JSON.stringify({
      objectMappings: this.pendingObjects,
      fieldMappings: this.pendingFields
    });
  }

  // ---- validate and save -------------------------------------------------

  async handleValidate() {
    this.isValidating = true;
    this.problems = [];
    try {
      const problems = await validatePending({ pendingJson: this.buildPendingJson() });
      if (Array.isArray(problems) && problems.length > 0) {
        this.problems = problems;
      } else {
        showToast(this, 'No problems found', NO_PROBLEMS, 'success');
      }
    } catch (error) {
      showToast(this, 'Could not validate the changes', errorMessage(error), 'error');
    } finally {
      this.isValidating = false;
    }
  }

  async handleSaveAll() {
    this.isSaving = true;
    this.problems = [];
    this.deployError = undefined;
    this.deployStatus = undefined;

    let deployJobId;
    try {
      deployJobId = await savePending({ pendingJson: this.buildPendingJson() });
    } catch (error) {
      this.isSaving = false;
      showToast(this, 'Could not save the mappings', errorMessage(error), 'error');
      return;
    }

    try {
      if (!deployJobId) {
        // Orgs that can't run a real deploy (tests, some sandboxes) save inline.
        showToast(this, 'Mappings saved', SAVED, 'success');
        this.clearPending();
        await this.reload();
        return;
      }
      this.deployStatus = DEPLOYING;
      const { done, row } = await pollDeploy(this.fetchDeployStatus, deployJobId, this.pollOptions);
      if (done && row.Status__c === 'Succeeded') {
        showToast(this, 'Mappings saved', SAVED, 'success');
        this.clearPending();
        await this.reload();
      } else if (done) {
        this.deployError = row.Error_Detail__c || DEPLOY_FAILED;
        showToast(this, 'Mapping deployment failed', this.deployError, 'error');
      } else {
        showToast(this, 'Still deploying', STILL_DEPLOYING, 'warning');
      }
    } finally {
      this.deployStatus = undefined;
      this.isSaving = false;
    }
  }
}
