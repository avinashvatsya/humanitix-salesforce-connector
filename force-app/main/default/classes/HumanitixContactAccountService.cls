/**
 * The Contact account choice on the Sync Settings tab: which Account a
 * Humanitix buyer is linked to. Nothing new is stored. The choice IS the
 * active state of these mapping records, so the Mappings tab and the Sync
 * Settings tab can never disagree:
 *
 *   Record                   None   EventAccount   PersonAccount
 *   Order_to_Contact          on        on             off
 *   Order_to_Contact_08       off       on             off    (Contact.AccountId)
 *   Event_to_Account          off       on             off
 *   Order_to_PersonAccount    off       off            on
 *
 * Any other combination reads as Custom. A record that does not ship in this
 * version counts as inactive.
 *
 * Person Accounts exist only in some orgs, and the package build org has
 * none, so every Person Account name here is dynamic (describe and
 * Database.query), never static Apex or SOQL.
 */
public with sharing class HumanitixContactAccountService {
    public static final String MODE_NONE = 'None';
    public static final String MODE_EVENT_ACCOUNT = 'EventAccount';
    public static final String MODE_PERSON_ACCOUNT = 'PersonAccount';
    public static final String MODE_CUSTOM = 'Custom';
    public static final Set<String> ALL_MODES = new Set<String>{
        MODE_NONE, MODE_EVENT_ACCOUNT, MODE_PERSON_ACCOUNT, MODE_CUSTOM
    };
    private static final Set<String> SETTABLE_MODES = new Set<String>{
        MODE_NONE, MODE_EVENT_ACCOUNT, MODE_PERSON_ACCOUNT
    };

    public static final String CONTACT_MAPPING = 'Order_to_Contact';
    public static final String EVENT_ACCOUNT_MAPPING = 'Event_to_Account';
    public static final String CONTACT_ACCOUNT_FIELD = 'Order_to_Contact_08';
    public static final String PERSON_MAPPING = 'Order_to_PersonAccount';
    public static final String PERSON_RECORD_TYPE_FIELD = 'Order_to_PersonAccount_08';

    public class RecordTypeOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
    }

    /** The option the Sync Settings tab shows, read from the effective mapping records. */
    public static String currentMode() {
        return modeFrom(
            objectActive(CONTACT_MAPPING),
            objectActive(EVENT_ACCOUNT_MAPPING),
            fieldActive(CONTACT_ACCOUNT_FIELD),
            objectActive(PERSON_MAPPING)
        );
    }

    @TestVisible
    private static String modeFrom(Boolean contactOn, Boolean eventOn, Boolean linkOn, Boolean personOn) {
        if (personOn && !contactOn && !eventOn && !linkOn) {
            return MODE_PERSON_ACCOUNT;
        }
        if (contactOn && eventOn && linkOn && !personOn) {
            return MODE_EVENT_ACCOUNT;
        }
        if (contactOn && !eventOn && !linkOn && !personOn) {
            return MODE_NONE;
        }
        return MODE_CUSTOM;
    }

    public static Boolean personAccountsEnabled() {
        return Schema.SObjectType.Account.fields.getMap().containsKey('ispersonaccount');
    }

    /** Active person record types the running user can use, by name; empty without Person Accounts. */
    public static List<RecordTypeOption> personRecordTypes() {
        List<RecordTypeOption> out = new List<RecordTypeOption>();
        if (!personAccountsEnabled()) {
            return out;
        }
        Map<Id, Schema.RecordTypeInfo> infos = Schema.SObjectType.Account.getRecordTypeInfosById();
        for (SObject rt : Database.query(
            'SELECT Id, Name FROM RecordType WHERE SobjectType = \'Account\' AND IsActive = true AND IsPersonType = true ORDER BY Name'
        )) {
            Schema.RecordTypeInfo info = infos.get(rt.Id);
            if (info != null && info.isAvailable()) {
                RecordTypeOption o = new RecordTypeOption();
                o.value = String.valueOf(rt.Id);
                o.label = (String) rt.get('Name');
                out.add(o);
            }
        }
        return out;
    }

    /** The record type saved on Order_to_PersonAccount_08, or the only one available. */
    public static String currentPersonRecordTypeId() {
        HumanitixMappingAdminController.FieldMappingDto f = HumanitixMappingAdminController.effectiveFieldMapping(PERSON_RECORD_TYPE_FIELD);
        String current = f == null ? null : toId18(f.defaultValue);
        if (current == null) {
            List<RecordTypeOption> types = personRecordTypes();
            if (types.size() == 1) {
                return types[0].value;
            }
        }
        return current;
    }

    public static HumanitixMappingAdminController.PendingChanges changesFor(String mode) {
        return changesFor(mode, null);
    }

    /**
     * The mapping edits that put the org in the given mode: only records whose
     * state differs from the table above, each copied from its effective
     * record. For Person account the chosen record type (or the saved or only
     * one) becomes Order_to_PersonAccount_08's Default Value.
     */
    public static HumanitixMappingAdminController.PendingChanges changesFor(String mode, String personRecordTypeId) {
        if (mode == null || !SETTABLE_MODES.contains(mode)) {
            throw new HumanitixMappingException('Unknown Contact account option: ' + mode + '.');
        }
        if (mode == MODE_PERSON_ACCOUNT && !personAccountsEnabled()) {
            throw new HumanitixMappingException('Person Accounts are not enabled in this org.');
        }
        HumanitixMappingAdminController.PendingChanges pending = new HumanitixMappingAdminController.PendingChanges();
        setObject(pending, CONTACT_MAPPING, mode != MODE_PERSON_ACCOUNT);
        setObject(pending, EVENT_ACCOUNT_MAPPING, mode == MODE_EVENT_ACCOUNT);
        setObject(pending, PERSON_MAPPING, mode == MODE_PERSON_ACCOUNT);
        setField(pending, CONTACT_ACCOUNT_FIELD, mode == MODE_EVENT_ACCOUNT);
        if (mode == MODE_PERSON_ACCOUNT) {
            applyPersonRecordType(pending, personRecordTypeId);
        }
        return pending;
    }

    private static void applyPersonRecordType(HumanitixMappingAdminController.PendingChanges pending, String requested) {
        String chosen = String.isBlank(requested) ? currentPersonRecordTypeId() : toId18(requested);
        Set<String> allowed = new Set<String>();
        for (RecordTypeOption o : personRecordTypes()) {
            allowed.add(o.value);
        }
        if (chosen == null || !allowed.contains(chosen)) {
            throw new HumanitixMappingException('Choose a person account record type.');
        }
        HumanitixMappingAdminController.FieldMappingDto dto = HumanitixMappingAdminController.effectiveFieldMapping(PERSON_RECORD_TYPE_FIELD);
        if (dto == null) {
            throw new HumanitixMappingException('The ' + PERSON_RECORD_TYPE_FIELD + ' field mapping does not ship with this version.');
        }
        if (toId18(dto.defaultValue) != chosen || dto.active != true) {
            dto.defaultValue = chosen;
            dto.active = true;
            pending.fieldMappings.add(dto);
        }
    }

    private static void setObject(HumanitixMappingAdminController.PendingChanges pending, String devName, Boolean wanted) {
        HumanitixMappingAdminController.ObjectMappingDto dto = HumanitixMappingAdminController.effectiveObjectMapping(devName);
        if (dto == null) {
            if (wanted) {
                throw new HumanitixMappingException('The ' + devName + ' mapping does not ship with this version.');
            }
            return;
        }
        if ((dto.active == true) != wanted) {
            dto.active = wanted;
            pending.objectMappings.add(dto);
        }
    }

    private static void setField(HumanitixMappingAdminController.PendingChanges pending, String devName, Boolean wanted) {
        HumanitixMappingAdminController.FieldMappingDto dto = HumanitixMappingAdminController.effectiveFieldMapping(devName);
        if (dto == null) {
            if (wanted) {
                throw new HumanitixMappingException('The ' + devName + ' field mapping does not ship with this version.');
            }
            return;
        }
        if ((dto.active == true) != wanted) {
            dto.active = wanted;
            pending.fieldMappings.add(dto);
        }
    }

    private static Boolean objectActive(String devName) {
        HumanitixMappingAdminController.ObjectMappingDto dto = HumanitixMappingAdminController.effectiveObjectMapping(devName);
        return dto != null && dto.active == true;
    }

    private static Boolean fieldActive(String devName) {
        HumanitixMappingAdminController.FieldMappingDto dto = HumanitixMappingAdminController.effectiveFieldMapping(devName);
        return dto != null && dto.active == true;
    }

    private static String toId18(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return String.valueOf(Id.valueOf(value.trim()));
        } catch (Exception e) {
            return null;
        }
    }
}
