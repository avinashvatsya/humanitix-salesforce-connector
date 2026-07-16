/**
 * Flow / Agentforce action to start a Humanitix sync on demand. Returns the run
 * log Id, or an "ERROR: ..." string when the launch is rejected (disabled/overlap),
 * so a Flow can branch without an unhandled fault.
 */
public with sharing class HumanitixSyncInvocable {
    @InvocableMethod(
        label='Run Humanitix Sync'
        description='Starts a Humanitix -> Salesforce sync run and returns the run log Id.'
        category='Humanitix'
    )
    public static List<String> run() {
        List<String> out = new List<String>();
        try {
            out.add(String.valueOf(HumanitixSyncLauncher.start('Invocable')));
        } catch (Exception e) {
            out.add('ERROR: ' + e.getMessage());
        }
        return out;
    }
}
