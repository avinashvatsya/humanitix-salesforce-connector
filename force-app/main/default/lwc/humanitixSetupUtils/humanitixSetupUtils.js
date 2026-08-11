import { ShowToastEvent } from 'lightning/platformShowToastEvent';

/** Human-readable message from an Apex/wire error. */
export function errorMessage(error) {
  return error && error.body && error.body.message ? error.body.message : 'Unexpected error';
}

/** Dispatch a toast from the given component. */
export function showToast(component, title, message, variant) {
  component.dispatchEvent(new ShowToastEvent({ title, message, variant }));
}

/**
 * Poll an async metadata deployment until its ledger row reports Succeeded or
 * Failed. fetchStatus is the imperative HumanitixMetadataWriter.getDeployStatus
 * import; resolves { done, row } where done=false means the timeout elapsed
 * (the deploy may still finish in Setup).
 */
export function pollDeploy(fetchStatus, deployJobId, { intervalMs = 2000, timeoutMs = 120000 } = {}) {
  if (!deployJobId) {
    return Promise.resolve({ done: false, row: null });
  }
  const startedAt = Date.now();
  return new Promise((resolve) => {
    const tick = async () => {
      let row = null;
      try {
        row = await fetchStatus({ deployJobId });
      } catch (e) {
        row = null;
      }
      if (row && (row.Status__c === 'Succeeded' || row.Status__c === 'Failed')) {
        resolve({ done: true, row });
        return;
      }
      if (Date.now() - startedAt >= timeoutMs) {
        resolve({ done: false, row });
        return;
      }
      setTimeout(tick, intervalMs);
    };
    tick();
  });
}
