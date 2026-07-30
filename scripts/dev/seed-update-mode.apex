// Asserts the full shipped Order_to_Contact configuration via Metadata API,
// working around the Summer '26 gack on CustomMetadata record deploys. This
// script is the ONLY upgrade path for existing orgs, so it must set every
// value the record's own XML defines — not just Update_Mode__c — or an org
// seeded from an older version of this script silently keeps stale config.
// Run: sf apex run -f scripts/dev/seed-update-mode.apex -o <org>
Metadata.CustomMetadata rec = new Metadata.CustomMetadata();
rec.fullName = 'Humanitix_Object_Mapping.Order_to_Contact';
rec.label = 'Order to Contact (buyer)';

Metadata.CustomMetadataValue v;

v = new Metadata.CustomMetadataValue();
v.field = 'Match_Strategy__c';
v.value = 'MatchByFields';
rec.values.add(v);

v = new Metadata.CustomMetadataValue();
v.field = 'Match_Field_Set__c';
v.value = 'Email';
rec.values.add(v);

v = new Metadata.CustomMetadataValue();
v.field = 'Update_Mode__c';
v.value = 'BlanksOnly';
rec.values.add(v);

v = new Metadata.CustomMetadataValue();
v.field = 'Description__c';
v.value = 'Buyer becomes a Contact, matched to existing Contacts by Email (blanks-only updates: existing values are never overwritten). Orders without an email are skipped.';
rec.values.add(v);

Metadata.DeployContainer c = new Metadata.DeployContainer();
c.addMetadata(rec);
Id jobId = Metadata.Operations.enqueueDeployment(c, null);
System.debug('Enqueued CMT deployment job: ' + jobId);
