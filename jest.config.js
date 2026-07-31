const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
  ...jestConfig,
  // .claude/worktrees holds full checkouts; without this their test copies run twice
  testPathIgnorePatterns: [...(jestConfig.testPathIgnorePatterns || []), '/.claude/'],
  moduleNameMapper: {
    '^@salesforce/apex$': '<rootDir>/force-app/test/jest-mocks/apex',
    '^lightning/platformShowToastEvent$':
      '<rootDir>/force-app/test/jest-mocks/lightning/platformShowToastEvent'
  }
};
