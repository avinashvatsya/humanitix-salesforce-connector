/**
 * The Contact account choice is the active state of four mapping records.
 * These tests assume the shipped state (None) in the org they run in: a fresh
 * scratch org or the bare package-build org. Reset any manual walkthrough to
 * None before re-running them in a dev org.
 */
@IsTest
private class HumanitixContactAccountServiceTest {
    @IsTest
    static void modeFromCoversTheStateTable() {
        System.assertEquals('None', HumanitixContactAccountService.modeFrom(true, false, false, false));
        System.assertEquals('EventAccount', HumanitixContactAccountService.modeFrom(true, true, true, false));
        System.assertEquals('PersonAccount', HumanitixContactAccountService.modeFrom(false, false, false, true));
        System.assertEquals('Custom', HumanitixContactAccountService.modeFrom(true, true, false, false), 'Account mapping without the Contact link');
        System.assertEquals('Custom', HumanitixContactAccountService.modeFrom(true, false, false, true), 'Contacts and Person Accounts together');
        System.assertEquals('Custom', HumanitixContactAccountService.modeFrom(false, false, false, false), 'No buyer mapping at all');
    }

    @IsTest
    static void shippedDefaultsReadAsNone() {
        System.assertEquals('None', HumanitixContactAccountService.currentMode());
    }

    @IsTest
    static void choosingTheCurrentModeChangesNothing() {
        HumanitixMappingAdminController.PendingChanges pending = HumanitixContactAccountService.changesFor('None');
        System.assertEquals(0, pending.objectMappings.size());
        System.assertEquals(0, pending.fieldMappings.size());
    }

    @IsTest
    static void eventAccountActivatesTheAccountMappingAndTheContactLink() {
        HumanitixMappingAdminController.PendingChanges pending = HumanitixContactAccountService.changesFor('EventAccount');

        System.assertEquals(1, pending.objectMappings.size(), 'Order_to_Contact is already on');
        System.assertEquals('Event_to_Account', pending.objectMappings[0].devName);
        System.assertEquals(true, pending.objectMappings[0].active);
        System.assertEquals('Account', pending.objectMappings[0].targetSObject, 'Every other value is copied from the effective record');
        System.assertEquals(1, pending.fieldMappings.size());
        System.assertEquals('Order_to_Contact_08', pending.fieldMappings[0].devName);
        System.assertEquals(true, pending.fieldMappings[0].active);

        Set<String> names = new Set<String>();
        for (Metadata.CustomMetadata cmt : HumanitixMappingAdminController.deployRecordsFor(pending)) {
            names.add(cmt.fullName);
        }
        System.assert(names.contains('Humanitix_Object_Mapping.Event_to_Account'), names.toString());
        System.assert(names.contains('Humanitix_Field_Mapping.Order_to_Contact_08'), names.toString());
    }

    @IsTest
    static void unknownModesAreRejected() {
        for (String mode : new List<String>{ null, 'Household', 'Custom' }) {
            Boolean threw = false;
            try {
                HumanitixContactAccountService.changesFor(mode);
            } catch (HumanitixMappingException e) {
                threw = true;
                System.assert(e.getMessage().startsWith('Unknown Contact account option'), e.getMessage());
            }
            System.assert(threw, 'expected a rejection for ' + mode);
        }
    }

    private static Boolean personAccountsOn() {
        return Schema.SObjectType.Account.fields.getMap().containsKey('ispersonaccount');
    }

    @IsTest
    static void personAccountNeedsPersonAccountsEnabled() {
        if (personAccountsOn()) {
            return; // covered by the enabled-org tests below
        }
        System.assertEquals(false, HumanitixContactAccountService.personAccountsEnabled());
        System.assertEquals(0, HumanitixContactAccountService.personRecordTypes().size());
        String message;
        try {
            HumanitixContactAccountService.changesFor('PersonAccount', null);
        } catch (HumanitixMappingException e) {
            message = e.getMessage();
        }
        System.assertEquals('Person Accounts are not enabled in this org.', message);
    }

    @IsTest
    static void personAccountSwitchesTheBuyerMappingAndSetsTheRecordType() {
        if (!personAccountsOn()) {
            return; // runs in the htx-pa scratch org
        }
        List<HumanitixContactAccountService.RecordTypeOption> types = HumanitixContactAccountService.personRecordTypes();
        System.assert(!types.isEmpty(), 'A Person Account org has a person record type');
        String rt = types[0].value;

        HumanitixMappingAdminController.PendingChanges pending = HumanitixContactAccountService.changesFor('PersonAccount', rt);

        Map<String, Boolean> objects = new Map<String, Boolean>();
        for (HumanitixMappingAdminController.ObjectMappingDto o : pending.objectMappings) {
            objects.put(o.devName, o.active);
        }
        System.assertEquals(new Map<String, Boolean>{ 'Order_to_Contact' => false, 'Order_to_PersonAccount' => true }, objects);
        System.assertEquals(1, pending.fieldMappings.size());
        System.assertEquals('Order_to_PersonAccount_08', pending.fieldMappings[0].devName);
        System.assertEquals(rt, pending.fieldMappings[0].defaultValue);

        Set<String> names = new Set<String>();
        for (Metadata.CustomMetadata cmt : HumanitixMappingAdminController.deployRecordsFor(pending)) {
            names.add(cmt.fullName);
        }
        System.assert(names.contains('Humanitix_Object_Mapping.Order_to_PersonAccount'), 'The __pc targets validate in a Person Account org');
    }

    @IsTest
    static void personAccountRejectsARecordTypeThatIsNotAPersonType() {
        if (!personAccountsOn()) {
            return;
        }
        String message;
        try {
            HumanitixContactAccountService.changesFor('PersonAccount', 'not-an-id');
        } catch (HumanitixMappingException e) {
            message = e.getMessage();
        }
        System.assertEquals('Choose a person account record type.', message);
    }
}
