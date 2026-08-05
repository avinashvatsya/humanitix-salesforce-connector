const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
  ...jestConfig,
  // hidden tool directories can hold full repo checkouts; without this their test copies run twice
  testPathIgnorePatterns: [...(jestConfig.testPathIgnorePatterns || []), '<rootDir>/\\..+/'],
  moduleNameMapper: {
    '^@salesforce/apex$': '<rootDir>/force-app/test/jest-mocks/apex',
    '^lightning/platformShowToastEvent$':
      '<rootDir>/force-app/test/jest-mocks/lightning/platformShowToastEvent'
  }
};
