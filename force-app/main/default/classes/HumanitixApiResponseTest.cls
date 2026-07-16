@IsTest
private class HumanitixApiResponseTest {
    @IsTest
    static void parsesPaginatedBody() {
        String body = HumanitixTestDataFactory.pageBody('events', HumanitixTestDataFactory.eventJson(), 3, 1, 2);
        HumanitixApiResponse r = HumanitixApiResponse.parse(body, 'events', 200);
        System.assertEquals(200, r.statusCode);
        System.assertEquals(3, r.total);
        System.assertEquals(1, r.page);
        System.assertEquals(2, r.pageSize);
        System.assertEquals(1, r.records.size());
        System.assertEquals(true, r.hasNextPage(), 'page 1 of 3 items at size 2 => more pages');
        System.assertEquals(2, r.nextPage());
    }

    @IsTest
    static void lastPageHasNoNext() {
        String body = HumanitixTestDataFactory.pageBody('events', HumanitixTestDataFactory.eventJson(), 2, 1, 5);
        HumanitixApiResponse r = HumanitixApiResponse.parse(body, 'events', 200);
        System.assertEquals(false, r.hasNextPage());
    }

    @IsTest
    static void handlesBlankAndMalformedBody() {
        System.assertEquals(0, HumanitixApiResponse.parse('', 'events', 200).records.size());
        System.assertEquals(0, HumanitixApiResponse.parse('not json', 'events', 200).records.size());
        System.assertEquals(0, HumanitixApiResponse.parse('[1,2]', 'events', 200).records.size());
    }

    @IsTest
    static void missingTotalsFallBackToRecordHeuristic() {
        HumanitixApiResponse r = HumanitixApiResponse.parse('{"events":[' + HumanitixTestDataFactory.eventJson() + ']}', 'events', 200);
        System.assertEquals(true, r.hasNextPage(), 'with records but no totals, assume another page');
        HumanitixApiResponse empty = HumanitixApiResponse.parse('{"events":[]}', 'events', 200);
        System.assertEquals(false, empty.hasNextPage());
    }
}
