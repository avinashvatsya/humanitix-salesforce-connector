/**
 * Serializable run state carried through the Queueable chain. Kept deliberately
 * small (a phase list + a keyset cursor for events, not the full event list) so
 * it scales to orgs with many events without bloating the async job payload.
 */
public class HumanitixSyncState {
    public String runId;
    public Id logId;
    public String triggerSource;
    public Datetime runStart;

    // ordered phases still to process (subset of Tags/Events/Orders/Tickets)
    public List<String> phases = new List<String>();
    public Integer phaseIndex = 0;

    // per-phase progress
    public Integer page = 1;
    public Integer attempt = 0;
    public Integer retryDelay = 0; // minutes to wait before the next attempt
    public String currentEventId; // for Orders/Tickets phases (keyset cursor over events)

    // settings snapshot (taken at launch so a mid-run config change can't corrupt a run)
    public Integer pageSize = 100;
    public Boolean inFutureOnly = false;
    public String ticketStatusFilter;
    public Integer maxRetries = 5;
    public Integer retryDelayMinutes = 5;
    public Boolean incremental = true;
    public String namedCredential = 'HumanitixAPI';

    public String currentPhase() {
        return (phaseIndex >= 0 && phaseIndex < phases.size()) ? phases[phaseIndex] : null;
    }

    public Boolean isDone() {
        return currentPhase() == null;
    }

    public void advancePhase() {
        phaseIndex++;
        page = 1;
        attempt = 0;
        currentEventId = null;
    }
}
