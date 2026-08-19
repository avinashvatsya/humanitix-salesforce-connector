/**
 * End-to-end mapping tests that exercise the SHIPPED default mappings. The
 * defaults are injected from the packaged Humanitix_Default_Mappings static
 * resource (via HumanitixTestDataFactory.useShippedMappings) rather than read
 * from org CMT records, because the package cannot ship the records while the
 * Summer '26 platform bug gacks CMT-record deploys — the package-build org
 * therefore has none. The tests assert the correctness properties that the
 * adversarial design review called out: timezone-correct dates, decimal money,
 * email-based Contact identity, reference resolution, nested-collection
 * expansion, and idempotency.
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
        HumanitixTestDataFactory.useShippedMappings();
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
        HumanitixTestDataFactory.useShippedMappings();
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
        HumanitixTestDataFactory.useShippedMappings();
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
        HumanitixTestDataFactory.useShippedMappings();
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
        HumanitixTestDataFactory.useShippedMappings();
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
        HumanitixTestDataFactory.useShippedMappings();
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
    static void worksWithoutInjectionViaOrgRecordsOrShippedFallback() {
        // Deliberately NO useShippedMappings() here: in a dev org this loads
        // the seeded CMT records; in the bare package-build org (no records)
        // it exercises the shipped-defaults fallback in HumanitixMappingConfig.
        // Either way the connector must map out of the box.
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            Test.startTest();
            HumanitixMappingEngine.run('Tag', HumanitixTestDataFactory.tags());
            Test.stopTest();
        }
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Humanitix_Tag__c WHERE Humanitix_Id__c = 'tag_1'],
            'a sync with no injected config must map via org records or the shipped defaults'
        );
    }

    @IsTest
    static void emptyInputIsNoOp() {
        Test.startTest();
        HumanitixMappingEngine.MappingResult r = HumanitixMappingEngine.run('Event', new List<Object>());
        Test.stopTest();
        System.assertEquals(0, r.recordsProcessed);
    }

    @IsTest
    static void validateRejectsUnknownUpdateMode() {
        HumanitixMappingConfig cfg = new HumanitixMappingConfig();
        HumanitixMappingConfig.ObjectMapping m = new HumanitixMappingConfig.ObjectMapping();
        m.devName = 'Bad_Mode_Mapping';
        m.sourceResource = 'Tag';
        m.targetSObject = 'Humanitix_Tag__c';
        m.externalIdField = 'Humanitix_Id__c';
        m.matchStrategy = 'ExternalId';
        m.loadOrder = 1;
        m.active = true;
        m.updateMode = 'Sometimes';
        cfg.objectMappings.add(m);
        List<String> errors = cfg.validate();
        Boolean found = false;
        for (String e : errors) {
            if (e.contains('unknown Update Mode "Sometimes"')) {
                found = true;
            }
        }
        System.assert(found, 'validate() must flag an unknown Update Mode; got: ' + errors);
    }

    @IsTest
    static void validateRejectsUnknownMatchStrategy() {
        HumanitixMappingConfig cfg = new HumanitixMappingConfig();
        HumanitixMappingConfig.ObjectMapping m = new HumanitixMappingConfig.ObjectMapping();
        m.devName = 'Bad_Strategy_Mapping';
        m.sourceResource = 'Tag';
        m.targetSObject = 'Humanitix_Tag__c';
        m.externalIdField = 'Humanitix_Id__c';
        m.matchStrategy = 'MatchNoUpdate';
        m.loadOrder = 1;
        m.active = true;
        m.updateMode = 'Always';
        cfg.objectMappings.add(m);
        List<String> errors = cfg.validate();
        Boolean found = false;
        for (String e : errors) {
            if (e.contains('unknown Match Strategy "MatchNoUpdate"')) {
                found = true;
            }
        }
        System.assert(found, 'validate() must flag an unknown Match Strategy; got: ' + errors);
    }

    @IsTest
    static void fromRecordsCarriesTheDefaultSettings() {
        Humanitix_Object_Mapping__mdt om = new Humanitix_Object_Mapping__mdt(
            DeveloperName = 'Tag_Test',
            Source_Resource__c = 'Tag',
            Target_SObject__c = 'Humanitix_Tag__c',
            External_Id_Field__c = 'Humanitix_Id__c',
            Match_Strategy__c = 'ExternalId',
            Is_Active__c = true
        );
        Humanitix_Field_Mapping__mdt fm = new Humanitix_Field_Mapping__mdt(
            DeveloperName = 'Tag_Test_01',
            Object_Mapping__c = 'Tag_Test',
            Source_Path__c = 'name',
            Target_Field__c = 'Name',
            Data_Type__c = 'Text',
            Transform__c = 'Trim',
            Default_Source_Path__c = '_id',
            Default_Value__c = 'Unknown',
            Is_Active__c = true
        );

        HumanitixMappingConfig cfg = HumanitixMappingConfig.fromRecords(
            new List<Humanitix_Object_Mapping__mdt>{ om },
            new List<Humanitix_Field_Mapping__mdt>{ fm }
        );

        HumanitixMappingConfig.FieldMapping f = cfg.objectMappings[0].fields[0];
        System.assertEquals('_id', f.defaultSourcePath, 'Default_Source_Path__c must load into defaultSourcePath');
        System.assertEquals('Unknown', f.defaultValue, 'Default_Value__c must load into defaultValue');
    }

    @IsTest
    static void validateRejectsADefaultValueTheDataTypeCannotCoerce() {
        HumanitixMappingConfig cfg = new HumanitixMappingConfig();
        HumanitixMappingConfig.ObjectMapping m = new HumanitixMappingConfig.ObjectMapping();
        m.devName = 'Bad_Default_Mapping';
        m.sourceResource = 'Event';
        m.targetSObject = 'Humanitix_Event__c';
        m.externalIdField = 'Humanitix_Id__c';
        m.matchStrategy = 'ExternalId';
        m.loadOrder = 1;
        m.active = true;
        HumanitixMappingConfig.FieldMapping id = new HumanitixMappingConfig.FieldMapping();
        id.sourcePath = '_id';
        id.targetField = 'Humanitix_Id__c';
        id.dataType = 'Text';
        id.transform = 'None';
        id.active = true;
        HumanitixMappingConfig.FieldMapping cap = new HumanitixMappingConfig.FieldMapping();
        cap.sourcePath = 'totalCapacity';
        cap.targetField = 'Total_Capacity__c';
        cap.dataType = 'Integer';
        cap.transform = 'None';
        cap.defaultValue = 'lots';
        cap.active = true;
        m.fields.add(id);
        m.fields.add(cap);
        cfg.objectMappings.add(m);

        List<String> errors = cfg.validate();

        Boolean found = false;
        for (String e : errors) {
            if (e.contains('Default Value "lots"') && e.contains('Integer')) {
                found = true;
            }
        }
        System.assert(found, 'validate() must flag a default the Data Type cannot coerce; got: ' + errors);

        cap.defaultValue = '250';
        List<String> clean = cfg.validate();
        System.assertEquals(0, clean.size(), 'a coercible default must validate cleanly; got: ' + clean);
    }

    @IsTest
    static void contactLastNameDefaultsToUnknownWhenTheOrderHasNone() {
        HumanitixTestDataFactory.useShippedMappings();
        List<Object> orders = (List<Object>) JSON.deserializeUntyped(
            '[' + HumanitixTestDataFactory.orderJson().replace('"lastName":"Baggins",', '') + ']'
        );
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            Test.startTest();
            HumanitixMappingEngine.run('Event', HumanitixTestDataFactory.events());
            HumanitixMappingEngine.run('Order', orders);
            Contact placeholder = [SELECT LastName FROM Contact WHERE Humanitix_Contact_Key__c = 'frodo@shire.com'];
            System.assertEquals('Unknown', placeholder.LastName, 'the shipped Contact.LastName default must fill a missing last name');

            // A later order carrying the real surname replaces the placeholder even
            // though Order_to_Contact runs BlanksOnly.
            HumanitixMappingEngine.run('Order', HumanitixTestDataFactory.orders());
            Test.stopTest();
        }
        Contact c = [SELECT LastName FROM Contact WHERE Humanitix_Contact_Key__c = 'frodo@shire.com'];
        System.assertEquals('Baggins', c.LastName, 'a connector placeholder must yield to a later real value under BlanksOnly');
    }

    @IsTest
    static void leadCompanyUsesOrganisationOrDefaultsToUnknown() {
        HumanitixTestDataFactory.useShippedMappings();
        for (HumanitixMappingConfig.ObjectMapping om : HumanitixMappingConfig.getInstance().objectMappings) {
            if (om.devName == 'Order_to_Lead') {
                om.active = true; // ships inactive; the fixture flips it on in memory only
            }
        }
        String withOrg = HumanitixTestDataFactory.orderJson();
        String withoutOrg = withOrg
            .replace('"organisation":"Fellowship",', '')
            .replace('"email":"Frodo@Shire.com"', '"email":"Sam@Shire.com"')
            .replace('"_id":"' + HumanitixTestDataFactory.ORDER_ID + '"', '"_id":"ord_sam_1"');
        List<Object> orders = (List<Object>) JSON.deserializeUntyped('[' + withOrg + ',' + withoutOrg + ']');

        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            Test.startTest();
            HumanitixMappingEngine.run('Event', HumanitixTestDataFactory.events());
            HumanitixMappingEngine.run('Order', orders);
            Test.stopTest();
        }

        Map<String, Lead> byKey = new Map<String, Lead>();
        for (Lead l : [
            SELECT Company, Humanitix_Contact_Key__c
            FROM Lead
            WHERE Humanitix_Contact_Key__c IN ('frodo@shire.com', 'sam@shire.com')
        ]) {
            byKey.put(l.Humanitix_Contact_Key__c, l);
        }
        System.assertEquals(2, byKey.size(), 'both orders must produce a Lead');
        System.assertEquals('Fellowship', byKey.get('frodo@shire.com').Company, 'a present organisation wins');
        System.assertEquals('Unknown', byKey.get('sam@shire.com').Company, 'a missing organisation falls back to the shipped default');
    }

    @IsTest
    static void validateRejectsAStaticValueLiteralTheDataTypeCannotCoerce() {
        HumanitixMappingConfig cfg = new HumanitixMappingConfig();
        HumanitixMappingConfig.ObjectMapping m = new HumanitixMappingConfig.ObjectMapping();
        m.devName = 'Bad_Static_Mapping';
        m.sourceResource = 'Event';
        m.targetSObject = 'Humanitix_Event__c';
        m.externalIdField = 'Humanitix_Id__c';
        m.matchStrategy = 'ExternalId';
        m.loadOrder = 1;
        m.active = true;
        HumanitixMappingConfig.FieldMapping id = new HumanitixMappingConfig.FieldMapping();
        id.sourcePath = '_id';
        id.targetField = 'Humanitix_Id__c';
        id.dataType = 'Text';
        id.transform = 'None';
        id.active = true;
        HumanitixMappingConfig.FieldMapping cap = new HumanitixMappingConfig.FieldMapping();
        cap.targetField = 'Total_Capacity__c';
        cap.dataType = 'Integer';
        cap.transform = 'StaticValue';
        cap.transformArg = 'abc';
        cap.defaultValue = '5'; // ignored by StaticValue and must not be blamed
        cap.active = true;
        m.fields.add(id);
        m.fields.add(cap);
        cfg.objectMappings.add(m);

        List<String> errors = cfg.validate();

        System.assertEquals(1, errors.size(), 'exactly one problem expected; got: ' + errors);
        System.assert(errors[0].contains('Transform Arg "abc"'), 'the StaticValue literal is the culprit: ' + errors[0]);
        System.assert(!errors[0].contains('Default Value'), 'the ignored default must not be blamed: ' + errors[0]);

        cap.transformArg = '250';
        System.assertEquals(0, cfg.validate().size(), 'a coercible literal validates cleanly');
    }
}
