/**
 * Parses a Humanitix paginated list response: `{ total, page, pageSize, <array> }`.
 * The array field name differs per resource (events/orders/tickets/tags) and is
 * supplied by the caller.
 */
public with sharing class HumanitixApiResponse {
    public Integer statusCode;
    public Integer total;
    public Integer page;
    public Integer pageSize;
    public List<Object> records = new List<Object>();

    public static HumanitixApiResponse parse(String body, String arrayField, Integer statusCode) {
        HumanitixApiResponse r = new HumanitixApiResponse();
        r.statusCode = statusCode;
        if (String.isBlank(body)) {
            return r;
        }
        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(body);
        } catch (Exception e) {
            return r;
        }
        if (!(parsed instanceof Map<String, Object>)) {
            return r;
        }
        Map<String, Object> m = (Map<String, Object>) parsed;
        r.total = toInt(m.get('total'));
        r.page = toInt(m.get('page'));
        r.pageSize = toInt(m.get('pageSize'));
        Object arr = m.get(arrayField);
        if (arr instanceof List<Object>) {
            r.records = (List<Object>) arr;
        }
        return r;
    }

    /**
     * True when the reported total implies at least one more page. Falls back to
     * "this page had records" when the totals are missing.
     */
    public Boolean hasNextPage() {
        Integer size = records == null ? 0 : records.size();
        if (size == 0) {
            return false;
        }
        if (total != null && page != null && pageSize != null && pageSize > 0) {
            return (page * pageSize) < total;
        }
        // Pagination metadata missing: only assume another page when this page was
        // full. Never loop indefinitely on a response that omits totals.
        return pageSize != null && pageSize > 0 && size >= pageSize;
    }

    public Integer nextPage() {
        return (page == null ? 1 : page) + 1;
    }

    private static Integer toInt(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof Integer) {
            return (Integer) o;
        }
        if (o instanceof Long) {
            return ((Long) o).intValue();
        }
        if (o instanceof Decimal) {
            return ((Decimal) o).intValue();
        }
        try {
            return Integer.valueOf(String.valueOf(o));
        } catch (Exception e) {
            return null;
        }
    }
}
