/**
 * Backs the Connection tab of the Humanitix Setup console: API key entry
 * (write-only, via HumanitixCredentialService) and a connection test through
 * the Named Credential.
 */
public with sharing class HumanitixConnectionController {
    public class TestResult {
        @AuraEnabled public Integer statusCode;
        @AuraEnabled public Boolean ok;
        @AuraEnabled public String message;
    }

    @AuraEnabled
    public static HumanitixCredentialService.KeyStatus getConnectionStatus() {
        try {
            return HumanitixCredentialService.getKeyStatus();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void saveApiKey(String apiKey) {
        try {
            HumanitixCredentialService.saveApiKey(apiKey);
        } catch (HumanitixCredentialService.CredentialException e) {
            throw new AuraHandledException(e.getMessage());
        } catch (Exception e) {
            throw new AuraHandledException(
                'Could not save the key from this page. Use the manual steps in Setup instead. Details: ' + e.getMessage()
            );
        }
    }

    @AuraEnabled
    public static TestResult testConnection() {
        TestResult result = new TestResult();
        try {
            HttpResponse res = new HumanitixHttpClient(HumanitixSyncConfig.namedCredentialName())
                .get('/v1/events?page=1');
            result.statusCode = res.getStatusCode();
            result.ok = result.statusCode >= 200 && result.statusCode < 300;
            if (result.ok) {
                result.message = 'Connection succeeded. The API key is valid.';
            } else if (result.statusCode == 401 || result.statusCode == 403) {
                result.message = 'The API rejected the key. The key is wrong, or the permission set callout principal is not assigned.';
            } else {
                result.message = 'The API returned an unexpected response.';
            }
        } catch (Exception e) {
            // Typically a missing ApiKey parameter on the principal.
            result.statusCode = 0;
            result.ok = false;
            result.message = 'The connection attempt failed: ' + e.getMessage();
        }
        return result;
    }
}
