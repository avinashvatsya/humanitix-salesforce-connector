/**
 * Configurable HttpCalloutMock for connector tests. Enqueue a sequence of
 * (status, body) responses and optionally a Retry-After header; each callout
 * returns the next one (the last repeats once the queue is exhausted).
 */
@IsTest
public class HumanitixCalloutMock implements HttpCalloutMock {
    private List<Integer> statuses = new List<Integer>();
    private List<String> bodies = new List<String>();
    private List<String> retryAfters = new List<String>();
    private Integer idx = 0;
    public List<String> requestedEndpoints = new List<String>();

    public HumanitixCalloutMock enqueue(Integer status, String body) {
        return enqueue(status, body, null);
    }

    public HumanitixCalloutMock enqueue(Integer status, String body, String retryAfter) {
        statuses.add(status);
        bodies.add(body);
        retryAfters.add(retryAfter);
        return this;
    }

    public HTTPResponse respond(HTTPRequest req) {
        requestedEndpoints.add(req.getEndpoint());
        HttpResponse res = new HttpResponse();
        Integer i = statuses.isEmpty() ? -1 : Math.min(idx, statuses.size() - 1);
        if (i < 0) {
            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
        res.setStatusCode(statuses[i]);
        res.setBody(bodies[i] == null ? '' : bodies[i]);
        res.setHeader('Content-Type', 'application/json');
        if (String.isNotBlank(retryAfters[i])) {
            res.setHeader('Retry-After', retryAfters[i]);
        }
        idx++;
        return res;
    }
}
