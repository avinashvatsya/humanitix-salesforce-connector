/**
 * All ConnectApi access to the Humanitix external credential lives here so the
 * write-only API key contract is enforced in one place: the key is accepted as
 * a parameter, handed straight to ConnectApi, and never logged, returned, or
 * stored. Reads only report whether a key exists (ConnectApi returns credential
 * values masked).
 *
 * ConnectApi is unavailable in Apex tests, so every method short-circuits under
 * Test.isRunningTest() through @TestVisible seams (the same pattern
 * HumanitixMappingSeeder uses for Metadata.Operations).
 */
public with sharing class HumanitixCredentialService {
    public class CredentialException extends Exception {}

    public static final String EXTERNAL_CREDENTIAL = 'HumanitixAPI';
    public static final String PRINCIPAL_NAME = 'Humanitix_Named_Principal';
    public static final String AUTH_PARAMETER = 'ApiKey';

    public class KeyStatus {
        @AuraEnabled public Boolean keySaved;
        @AuraEnabled public Boolean statusKnown;
        @AuraEnabled public String detail;
    }

    // Test seams. ConnectApi cannot execute in tests; these let tests script the
    // status and observe a save without the key value ever being retained.
    @TestVisible private static KeyStatus testStatus;
    @TestVisible private static Integer lastSavedKeyLength;
    @TestVisible private static Boolean lastSaveWasPatch;

    /** Whether an ApiKey value exists on the principal; never exposes the value. */
    public static KeyStatus getKeyStatus() {
        if (Test.isRunningTest()) {
            return testStatus != null ? testStatus : unknownStatus(null);
        }
        KeyStatus status = new KeyStatus();
        try {
            ConnectApi.Credential cred = ConnectApi.NamedCredentials.getCredential(
                EXTERNAL_CREDENTIAL,
                PRINCIPAL_NAME,
                ConnectApi.CredentialPrincipalType.NamedPrincipal
            );
            status.statusKnown = true;
            status.keySaved = cred != null && cred.credentials != null && cred.credentials.containsKey(AUTH_PARAMETER);
        } catch (Exception e) {
            // No access, or the credential/principal doesn't exist in this org.
            return unknownStatus(e.getMessage());
        }
        return status;
    }

    /** Creates or updates the ApiKey auth parameter on the named principal. */
    public static void saveApiKey(String apiKey) {
        if (String.isBlank(apiKey)) {
            throw new CredentialException('Enter an API key before saving.');
        }
        Boolean exists = getKeyStatus().keySaved == true;
        if (Test.isRunningTest()) {
            lastSavedKeyLength = apiKey.length();
            lastSaveWasPatch = exists;
            return;
        }
        ConnectApi.CredentialInput input = new ConnectApi.CredentialInput();
        input.externalCredential = EXTERNAL_CREDENTIAL;
        input.principalName = PRINCIPAL_NAME;
        input.principalType = ConnectApi.CredentialPrincipalType.NamedPrincipal;
        input.authenticationProtocol = ConnectApi.CredentialAuthenticationProtocol.Custom;
        ConnectApi.CredentialValueInput keyValue = new ConnectApi.CredentialValueInput();
        keyValue.value = apiKey;
        keyValue.encrypted = true;
        input.credentials = new Map<String, ConnectApi.CredentialValueInput>{ AUTH_PARAMETER => keyValue };
        if (exists) {
            ConnectApi.NamedCredentials.patchCredential(input);
        } else {
            ConnectApi.NamedCredentials.createCredential(input);
        }
    }

    private static KeyStatus unknownStatus(String detail) {
        KeyStatus status = new KeyStatus();
        status.keySaved = false;
        status.statusKnown = false;
        status.detail = detail;
        return status;
    }
}
