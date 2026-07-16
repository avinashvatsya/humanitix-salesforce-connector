@IsTest
private class HumanitixTypeCoercerTest {
    private static Object coerce(Object raw, String type, String transform, String arg) {
        return HumanitixTypeCoercer.coerce(
            raw, type, transform, arg, new Map<String, Object>(), null, new Map<String, Object>()
        );
    }

    @IsTest
    static void isoToDateTimeParsesUtc() {
        Object v = coerce('2021-02-01T23:26:13.485Z', 'DateTime', 'IsoToDateTime', null);
        System.assert(v instanceof Datetime, 'Expected a Datetime');
        Datetime dt = (Datetime) v;
        System.assertEquals(2021, dt.yearGmt());
        System.assertEquals(2, dt.monthGmt());
        System.assertEquals(1, dt.dayGmt());
        System.assertEquals(23, dt.hourGmt());
    }

    @IsTest
    static void isoToDateInTzAvoidsOffByOne() {
        // 13:30Z on Mar 1 is 00:30 Mar 2 in Sydney (UTC+11) -> local date must be Mar 2.
        Map<String, Object> rec = new Map<String, Object>{ 'timezone' => 'Australia/Sydney' };
        Object v = HumanitixTypeCoercer.coerce(
            '2026-03-01T13:30:00.000Z', 'Date', 'IsoToDateInTz', 'timezone', rec, null, rec
        );
        System.assert(v instanceof Date, 'Expected a Date');
        System.assertEquals(Date.newInstance(2026, 3, 2), (Date) v, 'Timezone-local date should be Mar 2, not the UTC Mar 1');
    }

    @IsTest
    static void isoToDateInTzFallsBackToUtcOnBadTz() {
        Map<String, Object> rec = new Map<String, Object>{ 'timezone' => 'Not/AZone' };
        Object v = HumanitixTypeCoercer.coerce(
            '2026-03-01T13:30:00.000Z', 'Date', 'IsoToDateInTz', 'timezone', rec, null, rec
        );
        System.assertEquals(Date.newInstance(2026, 3, 1), (Date) v, 'Unknown tz should fall back to the UTC date');
    }

    @IsTest
    static void decimalMoneyIsPassThrough() {
        System.assertEquals(53.98, (Decimal) coerce(53.98, 'Currency', 'DecimalMoney', null));
        System.assertEquals(100, (Decimal) coerce(100, 'Decimal', 'DecimalMoney', null));
    }

    @IsTest
    static void lowerTrimsAndLowercases() {
        System.assertEquals('frodo@shire.com', (String) coerce('  Frodo@Shire.com ', 'Text', 'Lower', null));
    }

    @IsTest
    static void joinArrayJoinsWithComma() {
        List<Object> tags = new List<Object>{ 'a', 'b', 'c' };
        System.assertEquals('a,b,c', (String) coerce(tags, 'Text', 'JoinArray', null));
    }

    @IsTest
    static void concatPrefixesWithParentPath() {
        Map<String, Object> parent = new Map<String, Object>{ '_id' => 'ord_9' };
        Object v = HumanitixTypeCoercer.coerce(
            'q_diet', 'Text', 'Concat', '$parent._id', new Map<String, Object>(), parent, parent
        );
        System.assertEquals('ord_9:q_diet', (String) v);
    }

    @IsTest
    static void toJsonSerializesObjects() {
        Map<String, Object> details = new Map<String, Object>{ 'city' => 'Matamata' };
        String v = (String) coerce(details, 'LongText', 'ToJson', null);
        System.assert(v.contains('Matamata'), 'Expected serialized JSON to contain the value');
    }

    @IsTest
    static void boolMapAndStaticValue() {
        System.assertEquals(true, (Boolean) coerce('true', 'Boolean', 'BoolMap', null));
        System.assertEquals(false, (Boolean) coerce('no', 'Boolean', 'BoolMap', null));
        System.assertEquals('In Progress', (String) coerce(null, 'Text', 'StaticValue', 'In Progress'));
    }

    @IsTest
    static void nullRawYieldsNull() {
        System.assertEquals(null, coerce(null, 'Text', 'None', null));
        System.assertEquals(null, coerce(null, 'DateTime', 'IsoToDateTime', null));
    }

    @IsTest
    static void integerCoercionHandlesJsonNumbers() {
        Object v = coerce(1000, 'Integer', 'None', null);
        System.assertEquals(1000, (Decimal) v);
    }
}
