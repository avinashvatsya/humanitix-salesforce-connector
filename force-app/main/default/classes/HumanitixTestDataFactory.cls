/**
 * Shared fixtures for Humanitix connector tests: realistic, real-shaped JSON for
 * events, orders and tickets (deserialized to List<Object> the way the sync engine
 * feeds the mapping engine), and small builders.
 */
@IsTest
public class HumanitixTestDataFactory {
    public static final String EVENT_ID = 'evt_hobbit_1';
    public static final String ORDER_ID = 'ord_frodo_1';
    public static final String TICKET_ID = 'tkt_frodo_1';

    /** An evening (UTC) event whose local Sydney date is the NEXT calendar day. */
    public static String eventJson() {
        return '{' +
            '"_id":"' + EVENT_ID + '","userId":"user_1","organiserId":"org_1",' +
            '"name":"Hobbit Dance Off","description":"Show your moves","slug":"hobbit-dance-off",' +
            '"url":"https://events.humanitix.com/hobbit-dance-off","currency":"AUD",' +
            '"category":"community","classification":{"type":"event","category":"Community","subcategory":"Cultural"},' +
            '"public":true,"published":true,"suspendSales":false,"markedAsSoldOut":false,' +
            '"startDate":"2026-03-01T13:30:00.000Z","endDate":"2026-03-01T16:00:00.000Z",' +
            '"timezone":"Australia/Sydney","totalCapacity":1000,"location":"AU","isArchived":false,' +
            '"isPermanentlyArchived":false,"tagIds":["tag_1","tag_2"],' +
            '"ticketTypes":[{"_id":"tt_adult","name":"Adult","price":100,"quantity":500,' +
            '"description":"Admits one hobbit","disabled":false,"deleted":false,"isDonation":false}],' +
            '"dates":[{"_id":"date_1","startDate":"2026-03-01T13:30:00.000Z",' +
            '"endDate":"2026-03-01T16:00:00.000Z","scheduleId":"sch_1","disabled":false,"deleted":false}],' +
            '"createdAt":"2025-01-01T00:00:00.000Z","updatedAt":"2025-02-01T00:00:00.000Z"}';
    }

    public static String orderJson() {
        return '{' +
            '"_id":"' + ORDER_ID + '","eventId":"' + EVENT_ID + '","currency":"AUD",' +
            '"status":"complete","financialStatus":"paid","firstName":"Frodo","lastName":"Baggins",' +
            '"organisation":"Fellowship","mobile":"+61400000000","email":"Frodo@Shire.com",' +
            '"paymentType":"other","paymentGateway":"stripe","salesChannel":"online","manualOrder":false,' +
            '"completedAt":"2026-02-15T10:00:00.000Z","createdAt":"2026-02-15T09:00:00.000Z",' +
            '"updatedAt":"2026-02-15T10:00:00.000Z",' +
            '"totals":{"subtotal":100,"grossSales":109.98,"netSales":100,"total":109.98,' +
            '"totalTaxes":0,"discounts":0,"refunds":0,"bookingFee":9.98,"humanitixFee":9.98},' +
            '"additionalFields":[{"questionId":"q_diet","value":"Gluten Free"}]}';
    }

    public static String ticketJson() {
        return '{' +
            '"_id":"' + TICKET_ID + '","eventId":"' + EVENT_ID + '","orderId":"' + ORDER_ID + '",' +
            '"orderName":"OGZ123","number":1,"firstName":"Frodo","lastName":"Baggins",' +
            '"organisation":"Fellowship","ticketTypeName":"Adult","ticketTypeId":"tt_adult","currency":"AUD",' +
            '"price":100,"netPrice":100,"total":109.98,"taxes":0,"fee":9.98,"status":"complete",' +
            '"checkIn":{"checkedIn":true,"date":"2026-03-01T14:00:00.000Z"},' +
            '"seatingLocation":{"name":"Table 1 Seat 1","section":"A","table":"1","seat":"1"},' +
            '"salesChannel":"online","isDonation":false,' +
            '"createdAt":"2026-02-15T09:00:00.000Z","updatedAt":"2026-02-15T10:00:00.000Z",' +
            '"additionalFields":[{"questionId":"q_diet","value":"Gluten Free"}]}';
    }

    public static String tagJson() {
        return '{"_id":"tag_1","name":"People & Culture","userId":"user_1","location":"AU",' +
            '"createdAt":"2025-01-01T00:00:00.000Z","updatedAt":"2025-01-01T00:00:00.000Z"}';
    }

    public static List<Object> events() {
        return (List<Object>) JSON.deserializeUntyped('[' + eventJson() + ']');
    }
    public static List<Object> orders() {
        return (List<Object>) JSON.deserializeUntyped('[' + orderJson() + ']');
    }
    public static List<Object> tickets() {
        return (List<Object>) JSON.deserializeUntyped('[' + ticketJson() + ']');
    }
    public static List<Object> tags() {
        return (List<Object>) JSON.deserializeUntyped('[' + tagJson() + ']');
    }

    /** A single paginated API page body, as Humanitix returns it. */
    public static String pageBody(String arrayField, String recordsJson, Integer total, Integer page, Integer pageSize) {
        return '{"total":' + total + ',"page":' + page + ',"pageSize":' + pageSize + ',' +
            '"' + arrayField + '":[' + recordsJson + ']}';
    }

    // ---- Marketing User for Campaign/Campaign Member tests ----------------
    // Creating Campaigns requires the running user to be a Marketing User, so the
    // Campaign-producing tests run under System.runAs(marketingAdmin()). Insert the
    // user in @TestSetup (isolated to avoid MIXED_DML) and query it in each method.

    public static User buildMarketingAdmin() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String unique = 'htxmkt.' + Math.abs(Crypto.getRandomLong()) + '@humanitix.connector.test';
        return new User(
            FirstName = 'Humanitix',
            LastName = 'Admin',
            Alias = 'htxmkt',
            Email = 'htxadmin@humanitix.connector.test',
            Username = unique,
            ProfileId = p.Id,
            UserPermissionsMarketingUser = true,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    /** Insert the marketing admin, isolating the setup-object DML (MIXED_DML). */
    public static void insertMarketingAdmin() {
        User u = buildMarketingAdmin();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
    }

    public static User marketingAdmin() {
        return [SELECT Id FROM User WHERE Alias = 'htxmkt' ORDER BY CreatedDate DESC LIMIT 1];
    }
}
