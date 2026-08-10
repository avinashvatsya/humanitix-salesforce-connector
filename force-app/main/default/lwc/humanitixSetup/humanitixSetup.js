import { LightningElement } from 'lwc';

/**
 * Humanitix Setup: tabbed admin console. Each tab body renders only after its
 * first activation so hidden tabs make no Apex calls.
 */
export default class HumanitixSetup extends LightningElement {
  visited = { dashboard: true };

  handleTabActive(event) {
    const value = event.target.value;
    if (!this.visited[value]) {
      this.visited = { ...this.visited, [value]: true };
    }
  }
}
