/**
 * Direct persister tests for the match strategies and guard rails the engine
 * tests don't reach. DML runs as the marketing admin so field access comes from
 * the Humanitix Integration Admin permission set, exactly like a real run.
 */
@IsTest
private class HumanitixPersisterTest {
    @TestSetup
    static void setup() {
        HumanitixTestDataFactory.insertMarketingAdmin();
    }

    private static HumanitixMappingConfig.ObjectMapping tagMapping(String strategy) {
        HumanitixMappingConfig.ObjectMapping om = new HumanitixMappingConfig.ObjectMapping();
        om.devName = 'Test_Tag_Mapping';
        om.targetSObject = 'Humanitix_Tag__c';
        om.externalIdField = 'Humanitix_Id__c';
        om.matchStrategy = strategy;
        return om;
    }

    private static Humanitix_Tag__c tag(String key) {
        return new Humanitix_Tag__c(Name = key, Humanitix_Id__c = key);
    }

    @IsTest
    static void emptyInputShortCircuits() {
        HumanitixPersister.PersistResult r = HumanitixPersister.persist(
            tagMapping('ExternalId'),
            new List<SObject>()
        );
        System.assertEquals(0, r.processed);
        System.assertEquals(0, r.failed);
    }

    @IsTest
    static void alwaysCreateInsertsEverything() {
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            HumanitixMappingConfig.ObjectMapping om = tagMapping('AlwaysCreate');
            om.updateMode = 'Never'; // AlwaysCreate must ignore Update Mode entirely
            Test.startTest();
            HumanitixPersister.PersistResult r = HumanitixPersister.persist(
                om,
                new List<SObject>{ tag('t1'), tag('t2') }
            );
            Test.stopTest();
            System.assertEquals(2, r.processed);
            System.assertEquals(2, [SELECT COUNT() FROM Humanitix_Tag__c]);
        }
    }

    @IsTest
    static void externalIdNeverSkipsExistingAndBlankInsertsNew() {
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            insert tag('EXISTING');
            HumanitixMappingConfig.ObjectMapping om = tagMapping('ExternalId');
            om.updateMode = 'Never';
            Test.startTest();
            HumanitixPersister.PersistResult r = HumanitixPersister.persist(
                om,
                new List<SObject>{
                    tag('existing'), // same key, different case -> must not re-insert
                    tag('brand-new'),
                    new Humanitix_Tag__c(Name = 'blank') // no key -> skipped
                }
            );
            Test.stopTest();
            System.assertEquals(1, r.processed, 'only the new key inserts');
            System.assertEquals(2, r.skipped, 'existing (case-insensitive) and blank key skip');
            System.assertEquals(2, [SELECT COUNT() FROM Humanitix_Tag__c]);
            System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Tag__c WHERE Name = 'EXISTING'], 'matched record is not modified');
        }
    }

    @IsTest
    static void matchByFieldsUpdatesExistingInsertsNew() {
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            insert new Humanitix_Tag__c(Name = 'old-name', Humanitix_Id__c = 'k1');
            HumanitixMappingConfig.ObjectMapping om = tagMapping('MatchByFields');
            om.matchFields = new List<String>{ 'Humanitix_Id__c' };
            Test.startTest();
            HumanitixPersister.PersistResult r = HumanitixPersister.persist(
                om,
                new List<SObject>{
                    new Humanitix_Tag__c(Name = 'new-name', Humanitix_Id__c = 'k1'),
                    new Humanitix_Tag__c(Name = 'fresh', Humanitix_Id__c = 'k2')
                }
            );
            Test.stopTest();
            System.assertEquals(2, r.processed, 'one update + one insert');
            System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Tag__c WHERE Name = 'new-name']);
            System.assertEquals(2, [SELECT COUNT() FROM Humanitix_Tag__c]);
        }
    }

    @IsTest
    static void matchByFieldsBlanksOnlyPreservesExistingValues() {
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            insert new List<Humanitix_Tag__c>{
                new Humanitix_Tag__c(Name = 'keep-me', Humanitix_Id__c = 'k1'), // User_Id__c blank
                new Humanitix_Tag__c(Name = 'full', Humanitix_Id__c = 'k3', User_Id__c = 'set')
            };
            HumanitixMappingConfig.ObjectMapping om = tagMapping('MatchByFields');
            om.matchFields = new List<String>{ 'Humanitix_Id__c' };
            om.updateMode = 'BlanksOnly';
            Test.startTest();
            HumanitixPersister.PersistResult r = HumanitixPersister.persist(
                om,
                new List<SObject>{
                    new Humanitix_Tag__c(Name = 'clobber-attempt', Humanitix_Id__c = 'k1', User_Id__c = 'u9'),
                    new Humanitix_Tag__c(Name = 'fresh', Humanitix_Id__c = 'k2'),
                    new Humanitix_Tag__c(Name = 'noop', Humanitix_Id__c = 'k3', User_Id__c = 'y')
                }
            );
            Test.stopTest();
            System.assertEquals(3, r.processed, 'blank-fill update + insert + matched no-op all count');
            Humanitix_Tag__c k1 = [SELECT Name, User_Id__c FROM Humanitix_Tag__c WHERE Humanitix_Id__c = 'k1'];
            System.assertEquals('keep-me', k1.Name, 'existing value is never overwritten');
            System.assertEquals('u9', k1.User_Id__c, 'blank field is filled');
            Humanitix_Tag__c k3 = [SELECT Name, User_Id__c FROM Humanitix_Tag__c WHERE Humanitix_Id__c = 'k3'];
            System.assertEquals('full', k3.Name);
            System.assertEquals('set', k3.User_Id__c);
            System.assertEquals(3, [SELECT COUNT() FROM Humanitix_Tag__c]);
        }
    }

    @IsTest
    static void externalIdBlanksOnlyFillsBlanksPreservesValues() {
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            insert new List<Humanitix_Tag__c>{
                new Humanitix_Tag__c(Name = 'keep-me', Humanitix_Id__c = 'k1'), // User_Id__c blank
                new Humanitix_Tag__c(Name = 'full', Humanitix_Id__c = 'k3', User_Id__c = 'set')
            };
            HumanitixMappingConfig.ObjectMapping om = tagMapping('ExternalId');
            om.updateMode = 'BlanksOnly';
            Test.startTest();
            HumanitixPersister.PersistResult r = HumanitixPersister.persist(
                om,
                new List<SObject>{
                    new Humanitix_Tag__c(Name = 'clobber-attempt', Humanitix_Id__c = 'k1', User_Id__c = 'u9'),
                    new Humanitix_Tag__c(Name = 'fresh', Humanitix_Id__c = 'k2'),
                    new Humanitix_Tag__c(Name = 'noop', Humanitix_Id__c = 'k3', User_Id__c = 'y')
                }
            );
            Test.stopTest();
            System.assertEquals(3, r.processed, 'blank-fill update + insert + matched no-op all count');
            Humanitix_Tag__c k1 = [SELECT Name, User_Id__c FROM Humanitix_Tag__c WHERE Humanitix_Id__c = 'k1'];
            System.assertEquals('keep-me', k1.Name, 'existing value is never overwritten');
            System.assertEquals('u9', k1.User_Id__c, 'blank field is filled');
            Humanitix_Tag__c k3 = [SELECT Name, User_Id__c FROM Humanitix_Tag__c WHERE Humanitix_Id__c = 'k3'];
            System.assertEquals('full', k3.Name);
            System.assertEquals('set', k3.User_Id__c);
            System.assertEquals(3, [SELECT COUNT() FROM Humanitix_Tag__c]);
        }
    }

    @IsTest
    static void matchByFieldsNeverLeavesMatchedUntouched() {
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            insert new Humanitix_Tag__c(Name = 'old-name', Humanitix_Id__c = 'k1');
            HumanitixMappingConfig.ObjectMapping om = tagMapping('MatchByFields');
            om.matchFields = new List<String>{ 'Humanitix_Id__c' };
            om.updateMode = 'Never';
            Test.startTest();
            HumanitixPersister.PersistResult r = HumanitixPersister.persist(
                om,
                new List<SObject>{
                    new Humanitix_Tag__c(Name = 'new-name', Humanitix_Id__c = 'k1'),
                    new Humanitix_Tag__c(Name = 'fresh', Humanitix_Id__c = 'k2')
                }
            );
            Test.stopTest();
            System.assertEquals(1, r.processed, 'only the unmatched row inserts');
            System.assertEquals(1, r.skipped, 'matched row is left untouched');
            System.assertEquals('old-name',
                [SELECT Name FROM Humanitix_Tag__c WHERE Humanitix_Id__c = 'k1'].Name,
                'matched record is not modified');
            System.assertEquals(2, [SELECT COUNT() FROM Humanitix_Tag__c]);
        }
    }

    @IsTest
    static void externalIdBlanksOnlyBulk251() {
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            List<Humanitix_Tag__c> seed = new List<Humanitix_Tag__c>();
            for (Integer i = 0; i < 100; i++) {
                seed.add(new Humanitix_Tag__c(Name = 'seed-' + i, Humanitix_Id__c = 'bulk-' + i));
            }
            insert seed;
            List<SObject> page = new List<SObject>();
            for (Integer i = 0; i < 251; i++) {
                // first 100 match existing rows (Name must be preserved), rest are new
                page.add(new Humanitix_Tag__c(
                    Name = 'incoming-' + i, Humanitix_Id__c = 'bulk-' + i, User_Id__c = 'u' + i
                ));
            }
            HumanitixMappingConfig.ObjectMapping om = tagMapping('ExternalId');
            om.updateMode = 'BlanksOnly';
            Test.startTest();
            HumanitixPersister.PersistResult r = HumanitixPersister.persist(om, page);
            Test.stopTest();
            System.assertEquals(251, r.processed, 'all rows process: 100 blank-fills + 151 inserts');
            System.assertEquals(0, r.failed);
            System.assertEquals(251, [SELECT COUNT() FROM Humanitix_Tag__c]);
            System.assertEquals(251, [SELECT COUNT() FROM Humanitix_Tag__c WHERE User_Id__c != null], 'blank User_Id__c was filled on all matched rows');
            System.assertEquals('seed-0',
                [SELECT Name FROM Humanitix_Tag__c WHERE Humanitix_Id__c = 'bulk-0'].Name,
                'existing names preserved at bulk scale');
        }
    }

    @IsTest
    static void partialDmlFailureIsTalliedNotThrown() {
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            Test.startTest();
            HumanitixPersister.PersistResult r = HumanitixPersister.persist(
                tagMapping('ExternalId'),
                // second row: 400-char key blows the field length -> row-level failure
                new List<SObject>{ tag('good'), tag('x'.repeat(400)) }
            );
            Test.stopTest();
            System.assertEquals(1, r.processed);
            System.assertEquals(1, r.failed);
            System.assert(!r.errors.isEmpty(), 'failure reason is recorded');
        }
    }

    @IsTest
    static void missingConfigThrowsClearErrors() {
        HumanitixMappingConfig.ObjectMapping noExt = tagMapping('ExternalId');
        noExt.externalIdField = null;
        try {
            HumanitixPersister.persist(noExt, new List<SObject>{ tag('t') });
            System.assert(false, 'expected HumanitixMappingException');
        } catch (HumanitixMappingException e) {
            System.assert(e.getMessage().contains('External Id Field'));
        }
        HumanitixMappingConfig.ObjectMapping noExtNever = tagMapping('ExternalId');
        noExtNever.externalIdField = null;
        noExtNever.updateMode = 'Never';
        try {
            HumanitixPersister.persist(noExtNever, new List<SObject>{ tag('t') });
            System.assert(false, 'expected HumanitixMappingException');
        } catch (HumanitixMappingException e) {
            System.assert(e.getMessage().contains('External Id Field'));
        }
        HumanitixMappingConfig.ObjectMapping noExtBlanksOnly = tagMapping('ExternalId');
        noExtBlanksOnly.externalIdField = null;
        noExtBlanksOnly.updateMode = 'BlanksOnly';
        try {
            HumanitixPersister.persist(noExtBlanksOnly, new List<SObject>{ tag('t') });
            System.assert(false, 'expected HumanitixMappingException');
        } catch (HumanitixMappingException e) {
            System.assert(e.getMessage().contains('External Id Field'));
        }
        HumanitixMappingConfig.ObjectMapping noMatch = tagMapping('MatchByFields');
        try {
            HumanitixPersister.persist(noMatch, new List<SObject>{ tag('t') });
            System.assert(false, 'expected HumanitixMappingException');
        } catch (HumanitixMappingException e) {
            System.assert(e.getMessage().contains('Match Field Set'));
        }
    }
}
