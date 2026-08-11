@IsTest
private class HumanitixConnectionControllerTest {
    @IsTest
    static void testConnectionReportsSuccessOn200() {
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(200, '{"events":[],"total":0}'));

        Test.startTest();
        HumanitixConnectionController.TestResult result = HumanitixConnectionController.testConnection();
        Test.stopTest();

        System.assertEquals(200, result.statusCode);
        System.assertEquals(true, result.ok);
        System.assert(result.message.contains('succeeded'), result.message);
    }

    @IsTest
    static void testConnectionExplains401() {
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(401, '{"error":"unauthorized"}'));

        Test.startTest();
        HumanitixConnectionController.TestResult result = HumanitixConnectionController.testConnection();
        Test.stopTest();

        System.assertEquals(false, result.ok);
        System.assert(result.message.contains('key'), 'Should point at the key: ' + result.message);
    }

    @IsTest
    static void testConnectionReportsOtherStatuses() {
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(500, ''));

        Test.startTest();
        HumanitixConnectionController.TestResult result = HumanitixConnectionController.testConnection();
        Test.stopTest();

        System.assertEquals(500, result.statusCode);
        System.assertEquals(false, result.ok);
    }

    @IsTest
    static void saveApiKeyWrapsBlankKeyInAuraException() {
        Boolean threw = false;
        try {
            HumanitixConnectionController.saveApiKey('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Blank key must surface as AuraHandledException');
    }

    @IsTest
    static void saveApiKeyDelegatesToService() {
        HumanitixConnectionController.saveApiKey('valid-key');
        System.assertEquals(9, HumanitixCredentialService.lastSavedKeyLength);
    }

    @IsTest
    static void getConnectionStatusReturnsServiceStatus() {
        HumanitixCredentialService.KeyStatus scripted = new HumanitixCredentialService.KeyStatus();
        scripted.keySaved = true;
        scripted.statusKnown = true;
        HumanitixCredentialService.testStatus = scripted;

        HumanitixCredentialService.KeyStatus status = HumanitixConnectionController.getConnectionStatus();
        System.assertEquals(true, status.keySaved);
        System.assertEquals(true, status.statusKnown);
    }
}
