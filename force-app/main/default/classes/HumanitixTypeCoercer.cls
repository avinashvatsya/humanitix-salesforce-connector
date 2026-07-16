/**
 * Applies a transform then coerces a raw JSON value into the Apex type expected
 * by a target Salesforce field. Pure and side-effect free so it is trivial to unit
 * test with static fixtures.
 *
 * Transforms: None, Trim, Upper, Lower, IsoToDateTime, IsoToDateInTz, DecimalMoney,
 * BoolMap, StaticValue, Concat, JoinArray, ToJson.
 * Data types:  Text, LongText, Email, Phone, Url, DateTime, Date, Decimal, Currency,
 * Integer, Boolean, Reference (Reference values are returned as normalized strings —
 * the RelationshipResolver turns them into Ids).
 *
 * Money note: Humanitix returns decimal major units (e.g. 53.98), so DecimalMoney is
 * a straight Decimal pass-through — never divide by 100.
 */
public with sharing class HumanitixTypeCoercer {
    public static Object coerce(
        Object raw,
        String dataType,
        String transform,
        String transformArg,
        Map<String, Object> record,
        Map<String, Object> parent,
        Map<String, Object> root
    ) {
        String t = String.isBlank(transform) ? 'None' : transform;
        if (t == 'StaticValue') {
            return coerceType(transformArg, dataType);
        }
        Object v = applyTransform(raw, t, transformArg, record, parent, root);
        return coerceType(v, dataType);
    }

    private static Object applyTransform(
        Object raw,
        String t,
        String arg,
        Map<String, Object> record,
        Map<String, Object> parent,
        Map<String, Object> root
    ) {
        switch on t {
            when 'None' {
                return raw;
            }
            when 'Trim' {
                return raw == null ? null : String.valueOf(raw).trim();
            }
            when 'Upper' {
                return raw == null ? null : String.valueOf(raw).toUpperCase();
            }
            when 'Lower' {
                return raw == null ? null : String.valueOf(raw).trim().toLowerCase();
            }
            when 'IsoToDateTime' {
                return parseIso(asString(raw));
            }
            when 'IsoToDateInTz' {
                String tz = asString(HumanitixJsonNavigator.valueAt(arg, record, parent, root));
                return isoToDateInTz(asString(raw), tz);
            }
            when 'DecimalMoney' {
                return raw == null ? null : Decimal.valueOf(String.valueOf(raw));
            }
            when 'BoolMap' {
                return toBool(raw);
            }
            when 'Concat' {
                if (raw == null) {
                    return null;
                }
                String prefix = resolvePrefix(arg, record, parent, root);
                return prefix + ':' + String.valueOf(raw);
            }
            when 'JoinArray' {
                if (!(raw instanceof List<Object>)) {
                    return raw == null ? null : String.valueOf(raw);
                }
                List<String> parts = new List<String>();
                for (Object o : (List<Object>) raw) {
                    if (o != null) {
                        parts.add(String.valueOf(o));
                    }
                }
                String sep = String.isBlank(arg) ? ',' : arg;
                return String.join(parts, sep);
            }
            when 'ToJson' {
                return raw == null ? null : JSON.serialize(raw);
            }
            when else {
                return raw;
            }
        }
    }

    private static Object coerceType(Object v, String dataType) {
        if (v == null) {
            return null;
        }
        String dt = String.isBlank(dataType) ? 'Text' : dataType;
        switch on dt {
            when 'Text', 'LongText', 'Email', 'Phone', 'Url', 'Reference' {
                return String.valueOf(v);
            }
            when 'DateTime' {
                return (v instanceof Datetime) ? (Datetime) v : parseIso(asString(v));
            }
            when 'Date' {
                if (v instanceof Date) {
                    return (Date) v;
                }
                if (v instanceof Datetime) {
                    return ((Datetime) v).dateGmt();
                }
                return Date.valueOf(String.valueOf(v));
            }
            when 'Decimal', 'Currency' {
                return (v instanceof Decimal) ? (Decimal) v : Decimal.valueOf(String.valueOf(v));
            }
            when 'Integer' {
                return (v instanceof Decimal)
                    ? (Decimal) v
                    : Decimal.valueOf(String.valueOf(v));
            }
            when 'Boolean' {
                return toBool(v);
            }
            when else {
                return String.valueOf(v);
            }
        }
    }

    // ---- helpers ----------------------------------------------------------

    private static String asString(Object o) {
        return o == null ? null : String.valueOf(o);
    }

    @TestVisible
    private static Datetime parseIso(String s) {
        if (String.isBlank(s)) {
            return null;
        }
        // Humanitix emits ISO-8601 UTC, e.g. 2021-02-01T23:26:13.485Z
        return (Datetime) JSON.deserialize('"' + s + '"', Datetime.class);
    }

    @TestVisible
    private static Date isoToDateInTz(String s, String tz) {
        Datetime dt = parseIso(s);
        if (dt == null) {
            return null;
        }
        if (String.isBlank(tz)) {
            return dt.dateGmt();
        }
        try {
            return Date.valueOf(dt.format('yyyy-MM-dd', tz));
        } catch (Exception e) {
            // Unknown timezone id -> fall back to the UTC calendar date.
            return dt.dateGmt();
        }
    }

    private static Boolean toBool(Object v) {
        if (v == null) {
            return null;
        }
        if (v instanceof Boolean) {
            return (Boolean) v;
        }
        String s = String.valueOf(v).trim().toLowerCase();
        return s == 'true' || s == '1' || s == 'yes';
    }

    private static String resolvePrefix(
        String arg,
        Map<String, Object> record,
        Map<String, Object> parent,
        Map<String, Object> root
    ) {
        if (String.isBlank(arg)) {
            return '';
        }
        if (arg.startsWith('$') || arg.contains('.')) {
            Object resolved = HumanitixJsonNavigator.valueAt(arg, record, parent, root);
            return resolved == null ? '' : String.valueOf(resolved);
        }
        return arg;
    }
}
