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
    static void nullBooleanCoercesToFalseNotNull() {
        // Checkbox targets are non-nillable; a missing source value must map to
        // unchecked, never null (null trips INVALID_TYPE_ON_FIELD_IN_RECORD at DML).
        System.assertEquals(false, (Boolean) coerce(null, 'Boolean', 'None', null));
        System.assertEquals(false, (Boolean) coerce(null, 'Boolean', 'BoolMap', null));
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

    private static Object coerceWithDefaults(
        Object raw,
        String type,
        String transform,
        String defaultPath,
        String defaultValue,
        Map<String, Object> rec
    ) {
        return HumanitixTypeCoercer.coerce(raw, type, transform, null, defaultPath, defaultValue, rec, null, rec);
    }

    @IsTest
    static void defaultsPreferValueThenPathThenFixed() {
        Map<String, Object> rec = new Map<String, Object>{ '_id' => 'ord_1' };
        System.assertEquals('Fellowship', coerceWithDefaults('Fellowship', 'Text', 'None', '_id', 'Unknown', rec), 'a present value wins');
        System.assertEquals('ord_1', coerceWithDefaults(null, 'Text', 'None', '_id', 'Unknown', rec), 'the default path is tried next');
        System.assertEquals('Unknown', coerceWithDefaults(null, 'Text', 'None', 'missing', 'Unknown', rec), 'the fixed value is last');
        System.assertEquals(null, coerceWithDefaults(null, 'Text', 'None', 'missing', null, rec), 'no default means null, as before');
    }

    @IsTest
    static void blankAfterTransformFallsThroughToTheDefault() {
        Map<String, Object> rec = new Map<String, Object>();
        System.assertEquals('Unknown', coerceWithDefaults('   ', 'Text', 'Trim', null, 'Unknown', rec), 'Trim to "" is blank');
        System.assertEquals('Unknown', coerceWithDefaults(new List<Object>(), 'Text', 'JoinArray', null, 'Unknown', rec), 'JoinArray of [] is blank');
        System.assertEquals('', coerceWithDefaults('', 'Text', 'None', null, null, rec), 'without a default an empty string is written as is');
    }

    @IsTest
    static void defaultGoesThroughTheTransformAndDataType() {
        Map<String, Object> rec = new Map<String, Object>();
        System.assertEquals('unknown', coerceWithDefaults(null, 'Text', 'Lower', null, 'UNKNOWN', rec), 'the transform applies to the default');
        Object dt = coerceWithDefaults(null, 'DateTime', 'IsoToDateTime', null, '2026-01-01T00:00:00.000Z', rec);
        System.assert(dt instanceof Datetime, 'the default must parse like a source value');
        System.assertEquals(2026, ((Datetime) dt).yearGmt());
        System.assertEquals(250, (Decimal) coerceWithDefaults(null, 'Integer', 'None', null, '250', rec), 'the data type coerces the default');
    }

    @IsTest
    static void booleanDefaultIsHonouredInsteadOfFalse() {
        Map<String, Object> rec = new Map<String, Object>();
        System.assertEquals(true, (Boolean) coerceWithDefaults(null, 'Boolean', 'BoolMap', null, 'true', rec));
        System.assertEquals(true, (Boolean) coerceWithDefaults(null, 'Boolean', 'None', null, 'yes', rec));
        System.assertEquals(false, (Boolean) coerceWithDefaults(null, 'Boolean', 'None', null, null, rec), 'no default keeps the unchecked fallback');
        System.assertEquals(false, (Boolean) coerceWithDefaults(false, 'Boolean', 'None', null, 'true', rec), 'an explicit false is a value, not a blank');
    }

    @IsTest
    static void staticValueIgnoresDefaults() {
        Map<String, Object> rec = new Map<String, Object>();
        Object v = HumanitixTypeCoercer.coerce(null, 'Text', 'StaticValue', 'In Progress', 'missing', 'Unknown', rec, null, rec);
        System.assertEquals('In Progress', (String) v, 'StaticValue short-circuits before the fallbacks');
    }

    @IsTest
    static void uncoercibleDefaultThrowsLikeAnyBadValue() {
        Boolean threw = false;
        try {
            coerceWithDefaults(null, 'Decimal', 'None', null, 'abc', new Map<String, Object>());
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'a default the Data Type cannot coerce must surface as an exception');
    }

    @IsTest
    static void resolveReadsTheMappingAndTreatsReferenceAsText() {
        HumanitixMappingConfig.FieldMapping f = new HumanitixMappingConfig.FieldMapping();
        f.sourcePath = 'eventId';
        f.targetField = 'Humanitix_Event__c';
        f.dataType = 'Reference';
        f.transform = 'None';
        f.transformArg = 'Humanitix_Event__c.Humanitix_Id__c';
        f.defaultSourcePath = '$parent._id';
        Map<String, Object> parent = new Map<String, Object>{ '_id' => 'evt_1' };
        Map<String, Object> rec = new Map<String, Object>{ '_id' => 'tt_1' };

        System.assertEquals('evt_1', (String) HumanitixTypeCoercer.resolve(f, rec, parent, parent), 'the reference key falls back to the default path');

        rec.put('eventId', 'evt_2');
        System.assertEquals('evt_2', (String) HumanitixTypeCoercer.resolve(f, rec, parent, parent), 'a present key wins');
    }
}
