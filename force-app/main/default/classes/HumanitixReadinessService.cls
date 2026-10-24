/**
 * The Dashboard's "Ready to sync" checklist. Each check says in one sentence
 * what to do and where when it is not ok; a check that cannot run reports
 * unknown instead of hiding the others.
 *
 * Users checked: the current user (manual runs run as them) and the owners of
 * active Humanitix scheduled jobs (scheduled runs run as the user who scheduled
 * them).
 */
public with sharing class HumanitixReadinessService {
    public static final String OK = 'ok';
    public static final String ERROR = 'error';
    public static final String WARNING = 'warning';
    public static final String UNKNOWN = 'unknown';
    @TestVisible
    private static final String ADMIN_PERMISSION_SET = 'Humanitix_Integration_Admin';
    private static final Set<String> ACTIVE_JOB_STATES = new Set<String>{ 'WAITING', 'ACQUIRED', 'EXECUTING' };

    public class Item {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String status;
        @AuraEnabled public String message;

        public Item(String key, String label, String status, String message) {
            this.key = key;
            this.label = label;
            this.status = status;
            this.message = message;
        }
    }

    public static List<Item> check() {
        List<Item> items = new List<Item>();
        HumanitixCredentialService.KeyStatus key = null;
        try {
            key = HumanitixCredentialService.getKeyStatus();
            items.add(apiKeyItem(key));
        } catch (Exception e) {
            items.add(apiKeyItem(null));
        }
        items.add(connectionItem(key));

        Set<Id> jobOwners = null;
        try {
            jobOwners = activeJobOwners();
        } catch (Exception e) {
            jobOwners = null;
        }
        try {
            List<User> users = usersToCheck(jobOwners == null ? new Set<Id>() : jobOwners);
            items.add(marketingUserItem(users));
            items.add(permissionSetItem(users, permissionSetHolders(users)));
        } catch (Exception e) {
            items.add(new Item('marketingUser', 'Marketing User', UNKNOWN, 'The users could not be checked: ' + e.getMessage()));
            items.add(new Item('permissionSet', 'Permission set', UNKNOWN, 'The users could not be checked: ' + e.getMessage()));
        }
        items.add(scheduleItem(jobOwners));
        return items;
    }

    @TestVisible
    private static Item apiKeyItem(HumanitixCredentialService.KeyStatus key) {
        if (key == null || key.statusKnown != true) {
            return new Item(
                'apiKey', 'API key saved', UNKNOWN,
                'The key could not be checked from this page. Use Test Connection on the Connection tab.'
            );
        }
        return key.keySaved == true
            ? new Item('apiKey', 'API key saved', OK, 'An API key is saved.')
            : new Item('apiKey', 'API key saved', ERROR, HumanitixSyncMessages.MISSING_KEY);
    }

    @TestVisible
    private static Item connectionItem(HumanitixCredentialService.KeyStatus key) {
        String label = 'Connection to Humanitix';
        if (key != null && key.statusKnown == true && key.keySaved != true) {
            return new Item('connection', label, UNKNOWN, 'Add the API key first.');
        }
        try {
            HttpResponse res = new HumanitixHttpClient(HumanitixSyncConfig.namedCredentialName())
                .get('/v1/events?page=1&pageSize=1');
            Integer s = res.getStatusCode();
            if (s >= 200 && s < 300) {
                return new Item('connection', label, OK, 'Humanitix accepted the API key.');
            }
            if (s == 401 || s == 403) {
                return new Item('connection', label, ERROR, HumanitixSyncMessages.authRejected(s));
            }
            if (HumanitixRetryPolicy.isRetryable(s)) {
                return new Item('connection', label, WARNING, 'Humanitix is busy or unavailable right now. Refresh in a minute.');
            }
            return new Item(
                'connection', label, ERROR,
                'Humanitix returned HTTP ' + s + '. Use Test Connection on the Connection tab for details.'
            );
        } catch (Exception e) {
            if (HumanitixSyncMessages.isMissingCredential(e.getMessage())) {
                return new Item('connection', label, ERROR, HumanitixSyncMessages.MISSING_KEY);
            }
            return new Item(
                'connection', label, ERROR,
                'Humanitix could not be reached (' + e.getMessage() + '). Use Test Connection on the Connection tab for details.'
            );
        }
    }

    @TestVisible
    private static Item marketingUserItem(List<User> users) {
        List<String> all = new List<String>();
        List<String> failing = new List<String>();
        for (User u : users) {
            all.add(u.Name);
            if (u.UserPermissionsMarketingUser != true) {
                failing.add(u.Name);
            }
        }
        if (failing.isEmpty()) {
            return new Item('marketingUser', 'Marketing User', OK, String.join(all, ', ') + ' can create Campaigns.');
        }
        return new Item(
            'marketingUser', 'Marketing User', ERROR,
            String.join(failing, ', ') + (failing.size() == 1 ? ' is not a Marketing User' : ' are not Marketing Users')
                + ', so Campaigns cannot be created. Tick Marketing User on the user record in Setup, Users.'
        );
    }

    @TestVisible
    private static Item permissionSetItem(List<User> users, Set<Id> holders) {
        List<String> all = new List<String>();
        List<String> failing = new List<String>();
        for (User u : users) {
            all.add(u.Name);
            if (!holders.contains(u.Id)) {
                failing.add(u.Name);
            }
        }
        if (failing.isEmpty()) {
            return new Item(
                'permissionSet', 'Permission set', OK,
                String.join(all, ', ') + (all.size() == 1 ? ' has' : ' have') + ' the Humanitix Integration Admin permission set.'
            );
        }
        return new Item(
            'permissionSet', 'Permission set', ERROR,
            String.join(failing, ', ') + (failing.size() == 1 ? ' does not have' : ' do not have')
                + ' the Humanitix Integration Admin permission set. Assign it in Setup, Permission Sets.'
        );
    }

    @TestVisible
    private static Item scheduleItem(Set<Id> jobOwners) {
        if (jobOwners == null) {
            return new Item('schedule', 'Schedule', UNKNOWN, 'The schedule could not be checked. Open the Schedule tab.');
        }
        return jobOwners.isEmpty()
            ? new Item(
                'schedule', 'Schedule', WARNING,
                'No schedule is set, so syncs run only when you click Run Sync Now. Set one on the Schedule tab.'
            )
            : new Item('schedule', 'Schedule', OK, 'A sync schedule is set.');
    }

    private static Set<Id> activeJobOwners() {
        Set<Id> owners = new Set<Id>();
        for (CronTrigger ct : [
            SELECT OwnerId
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Humanitix%' AND State IN :ACTIVE_JOB_STATES
        ]) {
            owners.add(ct.OwnerId);
        }
        return owners;
    }

    private static List<User> usersToCheck(Set<Id> jobOwners) {
        Set<Id> ids = new Set<Id>(jobOwners);
        ids.add(UserInfo.getUserId());
        return [SELECT Id, Name, UserPermissionsMarketingUser FROM User WHERE Id IN :ids ORDER BY Name];
    }

    private static Set<Id> permissionSetHolders(List<User> users) {
        Set<Id> holders = new Set<Id>();
        for (PermissionSetAssignment a : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name = :ADMIN_PERMISSION_SET AND AssigneeId IN :users
        ]) {
            holders.add(a.AssigneeId);
        }
        return holders;
    }
}
