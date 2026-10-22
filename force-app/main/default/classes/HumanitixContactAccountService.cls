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

    /**
     * The mapping edits that put the org in the given mode: only records whose
     * active state differs from the table above, each copied from its
     * effective record. Empty when the org is already in that mode.
     */
    public static HumanitixMappingAdminController.PendingChanges changesFor(String mode) {
        if (mode == null || !SETTABLE_MODES.contains(mode)) {
            throw new HumanitixMappingException('Unknown Contact account option: ' + mode + '.');
        }
        if (mode == MODE_PERSON_ACCOUNT) {
            throw new HumanitixMappingException('Person account is not available in this version.');
        }
        HumanitixMappingAdminController.PendingChanges pending = new HumanitixMappingAdminController.PendingChanges();
        setObject(pending, CONTACT_MAPPING, mode != MODE_PERSON_ACCOUNT);
        setObject(pending, EVENT_ACCOUNT_MAPPING, mode == MODE_EVENT_ACCOUNT);
        setObject(pending, PERSON_MAPPING, mode == MODE_PERSON_ACCOUNT);
        setField(pending, CONTACT_ACCOUNT_FIELD, mode == MODE_EVENT_ACCOUNT);
        return pending;
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
}
