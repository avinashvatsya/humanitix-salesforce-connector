/**
 * Thin HTTP wrapper around the Humanitix REST API. Calls go through the
 * `HumanitixAPI` Named Credential, which injects the `x-api-key` header from the
 * encrypted External Credential store — this class never sees or sets the key.
 *
 * It only performs the callout; classification, pagination, and retry live in the
 * sync engine so callouts and DML stay cleanly separated.
 */
public with sharing class HumanitixHttpClient {
    @TestVisible
    private static final Integer TIMEOUT_MS = 120000;

    private final String namedCredential;

    public HumanitixHttpClient() {
        this('HumanitixAPI');
    }

    public HumanitixHttpClient(String namedCredentialName) {
        this.namedCredential = String.isBlank(namedCredentialName) ? 'HumanitixAPI' : namedCredentialName;
    }

    /**
     * GET a path relative to the API base, e.g. '/v1/events?page=1'. Returns the
     * raw HttpResponse so the caller can classify status and read Retry-After.
     */
    public HttpResponse get(String pathAndQuery) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + namedCredential + pathAndQuery);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(TIMEOUT_MS);
        return new Http().send(req);
    }

    /** Convenience GET + parse for a paginated list endpoint. */
    public HumanitixApiResponse getPage(String path, String arrayField, Map<String, String> query) {
        HttpResponse res = get(path + buildQuery(query));
        return HumanitixApiResponse.parse(res.getBody(), arrayField, res.getStatusCode());
    }

    public static String buildQuery(Map<String, String> params) {
        if (params == null || params.isEmpty()) {
            return '';
        }
        List<String> parts = new List<String>();
        for (String key : params.keySet()) {
            String v = params.get(key);
            if (String.isNotBlank(v)) {
                parts.add(EncodingUtil.urlEncode(key, 'UTF-8') + '=' + EncodingUtil.urlEncode(v, 'UTF-8'));
            }
        }
        return parts.isEmpty() ? '' : '?' + String.join(parts, '&');
    }
}
