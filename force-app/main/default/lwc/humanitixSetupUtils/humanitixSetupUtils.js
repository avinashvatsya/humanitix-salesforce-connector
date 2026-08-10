import { ShowToastEvent } from 'lightning/platformShowToastEvent';

/** Human-readable message from an Apex/wire error. */
export function errorMessage(error) {
  return error && error.body && error.body.message ? error.body.message : 'Unexpected error';
}

/** Dispatch a toast from the given component. */
export function showToast(component, title, message, variant) {
  component.dispatchEvent(new ShowToastEvent({ title, message, variant }));
}
