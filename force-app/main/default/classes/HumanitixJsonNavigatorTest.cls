@IsTest
private class HumanitixJsonNavigatorTest {
    private static Map<String, Object> record() {
        return (Map<String, Object>) JSON.deserializeUntyped(
            '{"_id":"e1","name":"Party","checkIn":{"checkedIn":true},"totals":{"grossSales":53.98},"tagIds":["a","b"]}'
        );
    }

    @IsTest
    static void readsTopLevelAndNested() {
        Map<String, Object> r = record();
        System.assertEquals('e1', HumanitixJsonNavigator.valueAt('_id', r, null, r));
        System.assertEquals('Party', HumanitixJsonNavigator.valueAt('name', r, null, r));
        System.assertEquals(true, HumanitixJsonNavigator.valueAt('checkIn.checkedIn', r, null, r));
        System.assertEquals(53.98, HumanitixJsonNavigator.valueAt('totals.grossSales', r, null, r));
    }

    @IsTest
    static void missingSegmentsReturnNull() {
        Map<String, Object> r = record();
        System.assertEquals(null, HumanitixJsonNavigator.valueAt('nope', r, null, r));
        System.assertEquals(null, HumanitixJsonNavigator.valueAt('checkIn.date', r, null, r));
        System.assertEquals(null, HumanitixJsonNavigator.valueAt('totals.grossSales.deep', r, null, r));
    }

    @IsTest
    static void parentAndRootPrefixes() {
        Map<String, Object> parent = new Map<String, Object>{ '_id' => 'evt_1' };
        Map<String, Object> item = new Map<String, Object>{ 'name' => 'Adult' };
        System.assertEquals('evt_1', HumanitixJsonNavigator.valueAt('$parent._id', item, parent, parent));
        System.assertEquals('evt_1', HumanitixJsonNavigator.valueAt('$root._id', item, parent, parent));
        System.assertEquals(parent, HumanitixJsonNavigator.valueAt('$parent', item, parent, parent));
    }

    @IsTest
    static void blankPathReturnsNull() {
        Map<String, Object> r = record();
        System.assertEquals(null, HumanitixJsonNavigator.valueAt('', r, null, r));
        System.assertEquals(null, HumanitixJsonNavigator.valueAt(null, r, null, r));
    }
}
