// Seeds Update_Mode__c on the Order_to_Contact mapping record via Metadata API,
// working around the Summer '26 gack on CustomMetadata record deploys.
// Run: sf apex run -f scripts/dev/seed-update-mode.apex -o <org>
Metadata.CustomMetadata rec = new Metadata.CustomMetadata();
rec.fullName = 'Humanitix_Object_Mapping.Order_to_Contact';
rec.label = 'Order to Contact (buyer)';
Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
v.field = 'Update_Mode__c';
v.value = 'BlanksOnly';
rec.values.add(v);
Metadata.DeployContainer c = new Metadata.DeployContainer();
c.addMetadata(rec);
Id jobId = Metadata.Operations.enqueueDeployment(c, null);
System.debug('Enqueued CMT deployment job: ' + jobId);
