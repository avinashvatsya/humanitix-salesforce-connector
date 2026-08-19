/**
 * Applies a transform then coerces a raw JSON value into the Apex type expected
 * by a target Salesforce field. Pure and side-effect free so it is trivial to unit
 * test with static fixtures.
 *
 * Field-mapping fallbacks: when the transformed Humanitix value is blank, the
 * value at the mapping's Default Source Path is tried, then its fixed Default
 * Value; the winner goes through the same transform and data type (see the
 * fallback-aware coerce overload and resolve()).
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
    /** Transform + coerce with no fallbacks (callers and tests that hold no field mapping). */
    public static Object coerce(
        Object raw,
        String dataType,
        String transform,
        String transformArg,
        Map<String, Object> record,
        Map<String, Object> parent,
        Map<String, Object> root
    ) {
        return coerce(raw, dataType, transform, transformArg, null, null, record, parent, root);
    }

    /**
     * Transform + coerce with the field-mapping fallbacks. When the transformed
     * Humanitix value is blank (null or a whitespace-only string), the value at
     * defaultSourcePath is transformed and used instead; when that is blank too,
     * the fixed defaultValue is transformed and used. Blankness is judged after
     * the transform and before type coercion, so a Trim/JoinArray result of ""
     * still triggers the fallback and a Boolean default is honoured (null is not
     * turned into false first). StaticValue ignores both fallbacks.
     */
    public static Object coerce(
        Object raw,
        String dataType,
        String transform,
        String transformArg,
        String defaultSourcePath,
        String defaultValue,
        Map<String, Object> record,
        Map<String, Object> parent,
        Map<String, Object> root
    ) {
        String t = String.isBlank(transform) ? 'None' : transform;
        if (t == 'StaticValue') {
            return coerceType(transformArg, dataType);
        }
        Object v = applyTransform(raw, t, transformArg, record, parent, root);
        if (isBlankValue(v) && String.isNotBlank(defaultSourcePath)) {
            Object fallback = HumanitixJsonNavigator.valueAt(defaultSourcePath, record, parent, root);
            v = applyTransform(fallback, t, transformArg, record, parent, root);
        }
        if (isBlankValue(v) && String.isNotBlank(defaultValue)) {
            v = applyTransform(defaultValue, t, transformArg, record, parent, root);
        }
        return coerceType(v, dataType);
    }

    /**
     * Resolves what one field mapping writes for a record context: the value at
     * its Source Path with the fallbacks applied, transformed and coerced. A
     * Reference mapping's Transform Arg is the Object.ExternalIdField the
     * RelationshipResolver matches on, never a transform argument, so it is
     * withheld from the transform here (Reference values coerce as text).
     */
    public static Object resolve(
        HumanitixMappingConfig.FieldMapping f,
        Map<String, Object> record,
        Map<String, Object> parent,
        Map<String, Object> root
    ) {
        return coerce(
            HumanitixJsonNavigator.valueAt(f.sourcePath, record, parent, root),
            f.dataType,
            f.transform,
            f.dataType == 'Reference' ? null : f.transformArg,
            f.defaultSourcePath,
            f.defaultValue,
            record,
            parent,
            root
        );
    }

    /** Blank means "Humanitix has nothing here": null, or a whitespace-only string. */
    private static Boolean isBlankValue(Object v) {
        if (v == null) {
            return true;
        }
        return (v instanceof String) && String.isBlank((String) v);
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
        String dt0 = String.isBlank(dataType) ? 'Text' : dataType;
        if (dt0 == 'Boolean') {
            // Checkbox fields are non-nillable: writing null trips
            // INVALID_TYPE_ON_FIELD_IN_RECORD at DML. A missing/null source
            // value maps to unchecked.
            Boolean b = toBool(v);
            return b == null ? false : b;
        }
        if (v == null) {
            return null;
        }
        String dt = dt0;
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
