@IsTest
private class HumanitixRetryPolicyTest {
    @IsTest
    static void classifiesStatusCodes() {
        System.assertEquals(HumanitixRetryPolicy.Outcome.SUCCESS, HumanitixRetryPolicy.classify(200));
        System.assertEquals(HumanitixRetryPolicy.Outcome.SUCCESS, HumanitixRetryPolicy.classify(201));
        System.assertEquals(HumanitixRetryPolicy.Outcome.RETRY, HumanitixRetryPolicy.classify(429));
        System.assertEquals(HumanitixRetryPolicy.Outcome.RETRY, HumanitixRetryPolicy.classify(500));
        System.assertEquals(HumanitixRetryPolicy.Outcome.RETRY, HumanitixRetryPolicy.classify(503));
        System.assertEquals(HumanitixRetryPolicy.Outcome.RETRY, HumanitixRetryPolicy.classify(null));
        System.assertEquals(HumanitixRetryPolicy.Outcome.FATAL, HumanitixRetryPolicy.classify(400));
        System.assertEquals(HumanitixRetryPolicy.Outcome.FATAL, HumanitixRetryPolicy.classify(401));
        System.assertEquals(HumanitixRetryPolicy.Outcome.FATAL, HumanitixRetryPolicy.classify(404));
        System.assert(HumanitixRetryPolicy.isRetryable(429));
        System.assert(HumanitixRetryPolicy.isSuccess(200));
    }

    @IsTest
    static void delayHonorsRetryAfterHeader() {
        // 90 seconds -> ceil to 2 minutes
        System.assertEquals(2, HumanitixRetryPolicy.delayMinutes(1, 1, '90'));
        // 30 seconds -> ceil to 1 minute
        System.assertEquals(1, HumanitixRetryPolicy.delayMinutes(1, 1, '30'));
    }

    @IsTest
    static void delayBacksOffAndClamps() {
        System.assertEquals(1, HumanitixRetryPolicy.delayMinutes(1, 1, null));
        System.assertEquals(3, HumanitixRetryPolicy.delayMinutes(3, 1, null));
        System.assertEquals(10, HumanitixRetryPolicy.delayMinutes(50, 1, null), 'clamped to 10 minutes');
        System.assertEquals(4, HumanitixRetryPolicy.delayMinutes(2, 2, null));
    }

    @IsTest
    static void ignoresNonNumericRetryAfter() {
        // HTTP-date form is unsupported -> falls back to backoff on the base
        System.assertEquals(2, HumanitixRetryPolicy.delayMinutes(2, 1, 'Wed, 21 Oct 2026 07:28:00 GMT'));
    }
}
