const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
  ...jestConfig,
  moduleNameMapper: {
    '^@salesforce/apex$': '<rootDir>/force-app/test/jest-mocks/apex',
    '^lightning/platformShowToastEvent$':
      '<rootDir>/force-app/test/jest-mocks/lightning/platformShowToastEvent'
  }
};
