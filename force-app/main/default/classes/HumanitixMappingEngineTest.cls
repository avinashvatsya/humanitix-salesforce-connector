/**
 * End-to-end mapping tests that exercise the SHIPPED default Custom Metadata
 * mappings (visible in tests without seeAllData). They assert the correctness
 * properties that the adversarial design review called out: timezone-correct
 * dates, decimal money, email-based Contact identity, reference resolution,
 * nested-collection expansion, and idempotency.
 *
 * Runs under a Marketing User (via System.runAs) because the default Event ->
 * Campaign and Order -> Campaign Member mappings create Campaign records.
 */
@IsTest
private class HumanitixMappingEngineTest {
    @TestSetup
    static void setup() {
        HumanitixTestDataFactory.insertMarketingAdmin();
    }

    @IsTest
    static void eventMapsToCampaignAndStaging() {
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            Test.startTest();
            HumanitixMappingEngine.run('Event', HumanitixTestDataFactory.events());
            Test.stopTest();
        }

        Campaign camp = [
            SELECT Name, StartDate, IsActive, Humanitix_Is_Public__c, Humanitix_Total_Capacity__c,
                Humanitix_Start_DateTime__c
            FROM Campaign
            WHERE Humanitix_Event_Id__c = :HumanitixTestDataFactory.EVENT_ID
        ];
        System.assertEquals('Hobbit Dance Off', camp.Name);
        System.assertEquals(true, camp.IsActive, 'published=true should map to IsActive');
        System.assertEquals(true, camp.Humanitix_Is_Public__c);
        System.assertEquals(1000, camp.Humanitix_Total_Capacity__c);
        System.assertEquals(
            Date.newInstance(2026, 3, 2),
            camp.StartDate,
            'StartDate must be the Sydney-local date (Mar 2), not the UTC date (Mar 1)'
        );

        Humanitix_Event__c evt = [
            SELECT Name, Total_Capacity__c, Tag_Ids__c, Is_Public__c
            FROM Humanitix_Event__c
            WHERE Humanitix_Id__c = :HumanitixTestDataFactory.EVENT_ID
        ];
        System.assertEquals('Hobbit Dance Off', evt.Name);
        System.assertEquals('tag_1,tag_2', evt.Tag_Ids__c, 'tagIds array should be joined');

        Humanitix_Ticket_Type__c tt = [
            SELECT Name, Price__c, Humanitix_Event__c, Event_Humanitix_Id__c
            FROM Humanitix_Ticket_Type__c
            WHERE Humanitix_Id__c = 'tt_adult'
        ];
        System.assertEquals('Adult', tt.Name);
        System.assertEquals(100, tt.Price__c);
        System.assertEquals(HumanitixTestDataFactory.EVENT_ID, tt.Event_Humanitix_Id__c, '$parent._id should populate');
        System.assertNotEquals(null, tt.Humanitix_Event__c, 'Ticket type should resolve its parent event lookup');
        System.assertEquals(evt.Id, tt.Humanitix_Event__c);

        System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Event_Date__c WHERE Humanitix_Id__c = 'date_1']);
    }

    @IsTest
    static void orderMapsToContactOrderAndCampaignMember() {
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            Test.startTest();
            HumanitixMappingEngine.run('Event', HumanitixTestDataFactory.events());
            HumanitixMappingEngine.run('Order', HumanitixTestDataFactory.orders());
            Test.stopTest();
        }

        Contact c = [
            SELECT FirstName, LastName, Email, Humanitix_Contact_Key__c, Humanitix_Organisation__c
            FROM Contact
            WHERE Humanitix_Contact_Key__c = 'frodo@shire.com'
        ];
        System.assertEquals('Frodo', c.FirstName);
        System.assertEquals('frodo@shire.com', c.Email, 'Email should be lower-cased');
        System.assertEquals('Fellowship', c.Humanitix_Organisation__c);

        Humanitix_Order__c o = [
            SELECT Total__c, Gross_Sales__c, Financial_Status__c, Humanitix_Event__c, Contact__c
            FROM Humanitix_Order__c
            WHERE Humanitix_Id__c = :HumanitixTestDataFactory.ORDER_ID
        ];
        System.assertEquals(109.98, o.Total__c, 'Money is decimal major units — no /100');
        System.assertEquals(109.98, o.Gross_Sales__c);
        System.assertEquals('paid', o.Financial_Status__c);
        System.assertNotEquals(null, o.Humanitix_Event__c, 'Order should resolve its event lookup');
        System.assertEquals(c.Id, o.Contact__c, 'Order should resolve the buyer Contact by email');

        List<CampaignMember> members = [SELECT Status FROM CampaignMember WHERE ContactId = :c.Id];
        System.assertEquals(1, members.size(), 'One CampaignMember per Contact+Campaign');
        System.assertEquals('Responded', members[0].Status);

        System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Order_Attribute__c WHERE Question_Id__c = 'q_diet']);
    }

    @IsTest
    static void ticketMapsToStagingWithResolvedParents() {
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            Test.startTest();
            HumanitixMappingEngine.run('Event', HumanitixTestDataFactory.events());
            HumanitixMappingEngine.run('Order', HumanitixTestDataFactory.orders());
            HumanitixMappingEngine.run('Ticket', HumanitixTestDataFactory.tickets());
            Test.stopTest();
        }

        Humanitix_Ticket__c t = [
            SELECT Checked_In__c, Total__c, Status__c, Humanitix_Event__c, Humanitix_Order__c, Seating_Section__c
            FROM Humanitix_Ticket__c
            WHERE Humanitix_Id__c = :HumanitixTestDataFactory.TICKET_ID
        ];
        System.assertEquals(true, t.Checked_In__c);
        System.assertEquals(109.98, t.Total__c);
        System.assertEquals('A', t.Seating_Section__c);
        System.assertNotEquals(null, t.Humanitix_Event__c, 'Ticket should resolve its event lookup');
        System.assertNotEquals(null, t.Humanitix_Order__c, 'Ticket should resolve its order lookup');
    }

    @IsTest
    static void tagMapsToStaging() {
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            Test.startTest();
            HumanitixMappingEngine.run('Tag', HumanitixTestDataFactory.tags());
            Test.stopTest();
        }
        Humanitix_Tag__c tag = [SELECT Name FROM Humanitix_Tag__c WHERE Humanitix_Id__c = 'tag_1'];
        System.assertEquals('People & Culture', tag.Name);
    }

    @IsTest
    static void reRunIsIdempotent() {
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            Test.startTest();
            HumanitixMappingEngine.run('Event', HumanitixTestDataFactory.events());
            HumanitixMappingEngine.run('Event', HumanitixTestDataFactory.events());
            Test.stopTest();
        }
        System.assertEquals(1, [SELECT COUNT() FROM Campaign WHERE Humanitix_Event_Id__c = :HumanitixTestDataFactory.EVENT_ID]);
        System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Event__c WHERE Humanitix_Id__c = :HumanitixTestDataFactory.EVENT_ID]);
        System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Ticket_Type__c WHERE Humanitix_Id__c = 'tt_adult']);
    }

    @IsTest
    static void inPageDuplicateKeysCollapse() {
        List<Object> two = (List<Object>) JSON.deserializeUntyped(
            '[' + HumanitixTestDataFactory.eventJson() + ',' + HumanitixTestDataFactory.eventJson() + ']'
        );
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            Test.startTest();
            HumanitixMappingEngine.run('Event', two);
            Test.stopTest();
        }
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Campaign WHERE Humanitix_Event_Id__c = :HumanitixTestDataFactory.EVENT_ID],
            'Two source rows with the same key in one page should collapse to a single upsert'
        );
    }

    @IsTest
    static void emptyInputIsNoOp() {
        Test.startTest();
        HumanitixMappingEngine.MappingResult r = HumanitixMappingEngine.run('Event', new List<Object>());
        Test.stopTest();
        System.assertEquals(0, r.recordsProcessed);
    }
}
