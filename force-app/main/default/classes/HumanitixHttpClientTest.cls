@IsTest
private class HumanitixHttpClientTest {
    @IsTest
    static void getReturnsMockedResponse() {
        String body = HumanitixTestDataFactory.pageBody('events', HumanitixTestDataFactory.eventJson(), 1, 1, 100);
        HumanitixCalloutMock mock = new HumanitixCalloutMock().enqueue(200, body);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        HttpResponse res = new HumanitixHttpClient().get('/v1/events?page=1');
        Test.stopTest();

        System.assertEquals(200, res.getStatusCode());
        System.assert(res.getBody().contains('Hobbit Dance Off'));
        System.assert(mock.requestedEndpoints[0].startsWith('callout:HumanitixAPI/v1/events'), 'should call through the named credential');
    }

    @IsTest
    static void getPageParsesBody() {
        String body = HumanitixTestDataFactory.pageBody('tags', HumanitixTestDataFactory.tagJson(), 1, 1, 100);
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(200, body));

        Test.startTest();
        HumanitixApiResponse r = new HumanitixHttpClient('HumanitixAPI')
            .getPage('/v1/tags', 'tags', new Map<String, String>{ 'page' => '1', 'pageSize' => '100' });
        Test.stopTest();

        System.assertEquals(200, r.statusCode);
        System.assertEquals(1, r.records.size());
    }

    @IsTest
    static void buildQueryEncodesAndSkipsBlanks() {
        String qs = HumanitixHttpClient.buildQuery(
            new Map<String, String>{ 'page' => '1', 'since' => '2026-01-01T00:00:00Z', 'blank' => '' }
        );
        System.assert(qs.startsWith('?'));
        System.assert(qs.contains('page=1'));
        System.assert(qs.contains('since=2026-01-01T00%3A00%3A00Z'), 'colon should be URL-encoded');
        System.assert(!qs.contains('blank='), 'blank params are skipped');
    }

    @IsTest
    static void buildQueryEmptyForNoParams() {
        System.assertEquals('', HumanitixHttpClient.buildQuery(null));
        System.assertEquals('', HumanitixHttpClient.buildQuery(new Map<String, String>()));
    }
}
