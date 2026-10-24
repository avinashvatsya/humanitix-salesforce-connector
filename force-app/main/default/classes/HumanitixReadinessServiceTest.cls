@IsTest
private class HumanitixReadinessServiceTest {
    private static HumanitixCredentialService.KeyStatus key(Boolean known, Boolean saved) {
        HumanitixCredentialService.KeyStatus st = new HumanitixCredentialService.KeyStatus();
        st.statusKnown = known;
        st.keySaved = saved;
        return st;
    }

    private static User fakeUser(String id, String name, Boolean marketing) {
        return (User) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{ 'Id' => id, 'Name' => name, 'UserPermissionsMarketingUser' => marketing }),
            User.class
        );
    }

    private static Map<String, HumanitixReadinessService.Item> byKey(List<HumanitixReadinessService.Item> items) {
        Map<String, HumanitixReadinessService.Item> m = new Map<String, HumanitixReadinessService.Item>();
        for (HumanitixReadinessService.Item i : items) {
            m.put(i.key, i);
        }
        return m;
    }

    @IsTest
    static void apiKeyItemStates() {
        System.assertEquals('ok', HumanitixReadinessService.apiKeyItem(key(true, true)).status);
        HumanitixReadinessService.Item missing = HumanitixReadinessService.apiKeyItem(key(true, false));
        System.assertEquals('error', missing.status);
        System.assertEquals(HumanitixSyncMessages.MISSING_KEY, missing.message);
        System.assertEquals('unknown', HumanitixReadinessService.apiKeyItem(key(false, false)).status);
    }

    @IsTest
    static void connectionSkippedWithoutKey() {
        HumanitixReadinessService.Item i = HumanitixReadinessService.connectionItem(key(true, false));
        System.assertEquals('unknown', i.status);
        System.assertEquals('Add the API key first.', i.message);
    }

    @IsTest
    static void connectionOkAndRejected() {
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(200, '{}').enqueue(401, ''));
        Test.startTest();
        HumanitixReadinessService.Item ok = HumanitixReadinessService.connectionItem(key(true, true));
        HumanitixReadinessService.Item rejected = HumanitixReadinessService.connectionItem(key(true, true));
        Test.stopTest();
        System.assertEquals('ok', ok.status);
        System.assertEquals('error', rejected.status);
        System.assertEquals(HumanitixSyncMessages.authRejected(401), rejected.message);
    }

    @IsTest
    static void connectionBusyIsAWarning() {
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(503, ''));
        Test.startTest();
        HumanitixReadinessService.Item i = HumanitixReadinessService.connectionItem(key(false, false));
        Test.stopTest();
        System.assertEquals('warning', i.status);
    }

    @IsTest
    static void marketingUserNamesTheFailingUsers() {
        User ok = fakeUser('005000000000001', 'Ana Admin', true);
        User bad = fakeUser('005000000000002', 'Sam Scheduler', false);
        System.assertEquals('ok', HumanitixReadinessService.marketingUserItem(new List<User>{ ok }).status);
        HumanitixReadinessService.Item i = HumanitixReadinessService.marketingUserItem(new List<User>{ ok, bad });
        System.assertEquals('error', i.status);
        System.assert(i.message.startsWith('Sam Scheduler is not a Marketing User'), i.message);
        System.assert(!i.message.contains('Ana Admin'), i.message);
    }

    @IsTest
    static void permissionSetNamesTheFailingUsers() {
        User a = fakeUser('005000000000001', 'Ana Admin', true);
        User b = fakeUser('005000000000002', 'Sam Scheduler', true);
        HumanitixReadinessService.Item ok = HumanitixReadinessService.permissionSetItem(new List<User>{ a, b }, new Set<Id>{ a.Id, b.Id });
        System.assertEquals('ok', ok.status);
        System.assert(ok.message.startsWith('Ana Admin, Sam Scheduler have'), ok.message);
        HumanitixReadinessService.Item i = HumanitixReadinessService.permissionSetItem(new List<User>{ a, b }, new Set<Id>{ a.Id });
        System.assertEquals('error', i.status);
        System.assert(i.message.startsWith('Sam Scheduler does not have the Humanitix Integration Admin permission set.'), i.message);
    }

    @IsTest
    static void scheduleWarnsWhenMissingAndPassesWhenSet() {
        HumanitixCredentialService.testStatus = key(true, false); // no callout in this test
        Map<String, HumanitixReadinessService.Item> before = byKey(HumanitixReadinessService.check());
        System.assertEquals('warning', before.get('schedule').status);
        HumanitixSyncScheduler.schedule('Humanitix Delta Sync 1', '0 0 2 * * ?', HumanitixSyncLauncher.MODE_DELTA);
        Map<String, HumanitixReadinessService.Item> after = byKey(HumanitixReadinessService.check());
        System.assertEquals('ok', after.get('schedule').status);
    }

    @IsTest
    static void checkReturnsFiveItemsInOrder() {
        HumanitixCredentialService.testStatus = key(true, false);
        List<HumanitixReadinessService.Item> items = HumanitixReadinessService.check();
        List<String> keys = new List<String>();
        for (HumanitixReadinessService.Item i : items) {
            keys.add(i.key);
            System.assert(String.isNotBlank(i.message), i.key);
            System.assert(!i.message.contains('—'), i.message);
        }
        System.assertEquals(new List<String>{ 'apiKey', 'connection', 'marketingUser', 'permissionSet', 'schedule' }, keys);
    }
}
