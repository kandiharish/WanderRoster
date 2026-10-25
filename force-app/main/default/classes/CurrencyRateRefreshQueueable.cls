/**
 * Fetches today's INR-based exchange rates from the FX API (via Named Credential)
 * and upserts them into Currency_Rate__c.
 *
 * Runs asynchronously (Queueable) because callouts are not allowed in triggers
 * or synchronous transactions. Failures are logged and leave the old rates in place.
 */
public with sharing class CurrencyRateRefreshQueueable implements Queueable, Database.AllowsCallouts {

    private static final Set<String> TRACKED_CURRENCIES = new Set<String>{ 'USD', 'EUR', 'GBP', 'AED', 'SGD' };

    public void execute(QueueableContext context) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:FX_API/v6/latest/INR');
        request.setMethod('GET');
        request.setTimeout(10000);

        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() != 200) {
            System.debug(LoggingLevel.ERROR, 'FX refresh failed with status ' + response.getStatusCode());
            return;
        }

        List<Currency_Rate__c> rates = parseRates(response.getBody());
        if (!rates.isEmpty()) {
            upsert rates Currency_Code__c;
        }
    }

    /**
     * The API gives "1 INR = X foreign". We store "1 foreign = Y INR", so Y = 1 / X.
     */
    @TestVisible
    private static List<Currency_Rate__c> parseRates(String body) {
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(body);
        Map<String, Object> rateMap = (Map<String, Object>) root.get('rates');

        List<Currency_Rate__c> result = new List<Currency_Rate__c>();
        if (rateMap == null) {
            return result;
        }
        for (String code : TRACKED_CURRENCIES) {
            Object raw = rateMap.get(code);
            if (raw == null) {
                continue;
            }
            Decimal inrPerUnit = Decimal.valueOf(String.valueOf(raw));
            result.add(new Currency_Rate__c(
                Currency_Code__c = code,
                Rate_To_INR__c = (1 / inrPerUnit).setScale(6),
                Last_Updated__c = Datetime.now()
            ));
        }
        return result;
    }
}