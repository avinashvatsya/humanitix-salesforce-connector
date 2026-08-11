@IsTest
private class HumanitixCredentialServiceTest {
    @IsTest
    static void blankKeyIsRejected() {
        Boolean threw = false;
        try {
            HumanitixCredentialService.saveApiKey('   ');
        } catch (HumanitixCredentialService.CredentialException e) {
            threw = true;
            System.assert(e.getMessage().contains('API key'), 'Message should explain the blank key: ' + e.getMessage());
        }
        System.assert(threw, 'Blank key must throw CredentialException');
        System.assertEquals(null, HumanitixCredentialService.lastSavedKeyLength, 'Nothing should be recorded for a rejected save');
    }

    @IsTest
    static void statusIsUnknownInTestContextByDefault() {
        HumanitixCredentialService.KeyStatus status = HumanitixCredentialService.getKeyStatus();
        System.assertEquals(false, status.statusKnown);
        System.assertEquals(false, status.keySaved);
    }

    @IsTest
    static void saveCreatesWhenNoKeyExists() {
        HumanitixCredentialService.KeyStatus scripted = new HumanitixCredentialService.KeyStatus();
        scripted.keySaved = false;
        scripted.statusKnown = true;
        HumanitixCredentialService.testStatus = scripted;

        Test.startTest();
        HumanitixCredentialService.saveApiKey('key-abc-123');
        Test.stopTest();

        System.assertEquals(11, HumanitixCredentialService.lastSavedKeyLength);
        System.assertEquals(false, HumanitixCredentialService.lastSaveWasPatch, 'No existing key means create, not patch');
    }

    @IsTest
    static void savePatchesWhenKeyExists() {
        HumanitixCredentialService.KeyStatus scripted = new HumanitixCredentialService.KeyStatus();
        scripted.keySaved = true;
        scripted.statusKnown = true;
        HumanitixCredentialService.testStatus = scripted;

        Test.startTest();
        HumanitixCredentialService.saveApiKey('replacement');
        Test.stopTest();

        System.assertEquals(true, HumanitixCredentialService.lastSaveWasPatch, 'Existing key means patch');
    }
}
