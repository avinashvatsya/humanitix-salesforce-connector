@IsTest
private class HumanitixSyncMessagesTest {
    @IsTest
    static void missingCredentialRule() {
        System.assert(HumanitixSyncMessages.isMissingCredential('Field HumanitixAPI.ApiKey does not exist. Check spelling.'));
        System.assert(!HumanitixSyncMessages.isMissingCredential('Read timed out'));
        System.assert(!HumanitixSyncMessages.isMissingCredential(null));
    }

    @IsTest
    static void sentencesNameTheStatusAndAttempts() {
        System.assert(HumanitixSyncMessages.authRejected(401).contains('(HTTP 401)'));
        System.assert(HumanitixSyncMessages.authRejected(403).contains('Connection tab'));
        System.assert(HumanitixSyncMessages.busy(503, 6).contains('(HTTP 503) after 6 attempts'));
        System.assert(HumanitixSyncMessages.unreachable(6).contains('after 6 attempts'));
        System.assert(HumanitixSyncMessages.refused(400).contains('(HTTP 400)'));
        System.assert(HumanitixSyncMessages.eventNotFound().startsWith('This event no longer exists in Humanitix'));
        System.assert(String.isNotBlank(HumanitixSyncMessages.unexpected()));
    }

    @IsTest
    static void detailRoundTrip() {
        String msg = HumanitixSyncMessages.withDetail('Do this.', 'raw text');
        System.assertEquals('Do this. Details: raw text', msg);
        System.assertEquals('Do this.', HumanitixSyncMessages.sentenceOf(msg));
        System.assertEquals('Do this.', HumanitixSyncMessages.withDetail('Do this.', ' '));
        System.assertEquals('Old style text', HumanitixSyncMessages.sentenceOf('Old style text'));
        System.assertEquals(null, HumanitixSyncMessages.sentenceOf(null));
    }

    @IsTest
    static void httpDetailAbbreviatesBody() {
        System.assertEquals('HTTP 404', HumanitixSyncMessages.httpDetail(404, ''));
        System.assertEquals('HTTP 404: {"message":"Not found"}', HumanitixSyncMessages.httpDetail(404, '{"message":"Not found"}'));
        System.assertEquals(510, HumanitixSyncMessages.httpDetail(500, 'x'.repeat(2000)).length());
    }

    @IsTest
    static void noEmDashes() {
        List<String> all = new List<String>{
            HumanitixSyncMessages.MISSING_KEY, HumanitixSyncMessages.authRejected(401), HumanitixSyncMessages.eventNotFound(),
            HumanitixSyncMessages.busy(429, 2), HumanitixSyncMessages.unreachable(2), HumanitixSyncMessages.refused(400),
            HumanitixSyncMessages.unexpected()
        };
        for (String s : all) {
            System.assert(!s.contains('—'), s);
        }
    }
}
