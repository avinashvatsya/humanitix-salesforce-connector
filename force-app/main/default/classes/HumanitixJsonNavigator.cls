/**
 * Reads values out of a deserialized Humanitix JSON record by path.
 *
 * Paths are dotted (e.g. `totals.grossSales`, `checkIn.checkedIn`). Two prefixes
 * reach beyond the current record when mapping nested collections:
 *   - `$parent.` reads from the enclosing record (e.g. the event that owns a ticket type)
 *   - `$root.`   reads from the top-level record of the mapping pass
 * `$parent` / `$root` on their own return the whole enclosing/root map.
 *
 * Returns null for any missing segment rather than throwing, so partial payloads
 * map cleanly.
 */
public with sharing class HumanitixJsonNavigator {
    public static Object valueAt(
        String path,
        Map<String, Object> record,
        Map<String, Object> parent,
        Map<String, Object> root
    ) {
        if (String.isBlank(path)) {
            return null;
        }
        Map<String, Object> base = record;
        String p = path;
        if (p == '$parent') {
            return parent;
        }
        if (p == '$root') {
            return root;
        }
        if (p.startsWith('$parent.')) {
            base = parent;
            p = p.substring('$parent.'.length());
        } else if (p.startsWith('$root.')) {
            base = root;
            p = p.substring('$root.'.length());
        }
        if (base == null) {
            return null;
        }
        Object current = base;
        for (String seg : p.split('\\.')) {
            if (!(current instanceof Map<String, Object>)) {
                return null;
            }
            current = ((Map<String, Object>) current).get(seg);
            if (current == null) {
                return null;
            }
        }
        return current;
    }
}
