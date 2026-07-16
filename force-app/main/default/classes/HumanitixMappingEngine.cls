/**
 * Orchestrates mapping a page of Humanitix records for one resource into all of
 * its active target objects. This is the sole persistence entry point the sync
 * engine calls: it never does DML itself, it delegates to the persister.
 *
 * Flow per resource: load config -> validate once (fail fast on bad references) ->
 * for each active Object Mapping in Load Order: expand -> build -> resolve
 * references -> persist -> tally. Object mappings run in Load Order so parents
 * (e.g. Contact, Campaign) are committed before children (CampaignMember, Ticket)
 * try to resolve them.
 *
 * TRANSACTIONAL CONTRACT: run() issues its own SOQL/DML and is meant to process
 * ONE page in ONE transaction. The sync engine calls it once per Queueable
 * execution; do not loop run() over many pages in a single Apex transaction or you
 * will accumulate against the SOQL/DML governor limits.
 */
public with sharing class HumanitixMappingEngine {
    public class MappingResult {
        public Integer recordsProcessed = 0;
        public Integer recordsFailed = 0;
        public Integer recordsSkipped = 0;
        public List<String> errors = new List<String>();
        public Map<String, Integer> processedByTarget = new Map<String, Integer>();

        public Boolean hasErrors() {
            return recordsFailed > 0 || !errors.isEmpty();
        }
    }

    private static Boolean validated = false;

    public static MappingResult run(String resource, List<Object> records) {
        MappingResult result = new MappingResult();
        if (records == null || records.isEmpty()) {
            return result;
        }
        HumanitixMappingConfig cfg = HumanitixMappingConfig.getInstance();
        ensureValid(cfg);

        for (HumanitixMappingConfig.ObjectMapping om : cfg.activeForResource(resource)) {
            List<HumanitixRecordBuilder.RecordContext> ctxs = HumanitixRecordBuilder.contextsFor(om, records);
            if (ctxs.isEmpty()) {
                continue;
            }
            HumanitixRecordBuilder.BuildOutput bo = HumanitixRecordBuilder.build(om, ctxs);
            HumanitixRelationshipResolver.resolve(bo.refs);
            HumanitixPersister.PersistResult pr = HumanitixPersister.persist(om, bo.records);

            result.recordsProcessed += pr.processed;
            result.recordsFailed += pr.failed;
            result.recordsSkipped += pr.skipped;
            for (String e : pr.errors) {
                if (result.errors.size() < 50) {
                    result.errors.add(om.devName + ' -> ' + om.targetSObject + ': ' + e);
                }
            }
            Integer prev = result.processedByTarget.containsKey(om.targetSObject)
                ? result.processedByTarget.get(om.targetSObject)
                : 0;
            result.processedByTarget.put(om.targetSObject, prev + pr.processed);
        }
        return result;
    }

    private static void ensureValid(HumanitixMappingConfig cfg) {
        if (validated) {
            return;
        }
        List<String> errs = cfg.validate();
        if (!errs.isEmpty()) {
            throw new HumanitixMappingException(
                'Invalid Humanitix mapping configuration: ' + String.join(errs, ' | ')
            );
        }
        validated = true;
    }

    @TestVisible
    private static void resetValidation() {
        validated = false;
    }
}
