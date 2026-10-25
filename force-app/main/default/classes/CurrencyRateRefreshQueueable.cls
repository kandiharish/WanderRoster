/**
 * Fetches today's INR-based exchange rates from the FX API (via Named Credential)
 * and upserts them into Currency_Rate__c.
 *
 * Runs asynchronously (Queueable) because callouts are not allowed in triggers
 * or synchronous transactions. Any failure (HTTP error, timeout, bad JSON, save
 * error) is written to Error_Log__c and leaves yesterday's rates in place.
 */
public with sharing class CurrencyRateRefreshQueueable implements Queueable, Database.AllowsCallouts {

    private static final String SOURCE = 'CurrencyRateRefreshQueueable';
    private static final Set<String> TRACKED_CURRENCIES = new Set<String>{ 'USD', 'EUR', 'GBP', 'AED', 'SGD' };

    public void execute(QueueableContext context) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:FX_API/v6/latest/INR');
        request.setMethod('GET');
        request.setTimeout(10000);

        try {
            HttpResponse response = new Http().send(request);
            if (response.getStatusCode() != 200) {
                ErrorLogger.log(SOURCE, 'FX API returned HTTP ' + response.getStatusCode()
                    + '. Existing rates were kept.', null, ErrorLogger.WARNING);
                return;
            }

            List<Currency_Rate__c> rates = parseRates(response.getBody());
            if (rates.isEmpty()) {
                ErrorLogger.log(SOURCE, 'FX API response had no tracked currencies. Existing rates were kept.',
                    null, ErrorLogger.WARNING);
                return;
            }
            ErrorLogger.logFailures(SOURCE, Database.upsert(rates, Currency_Rate__c.Currency_Code__c, false), rates);
        } catch (CalloutException ex) {
            // Timeout, DNS failure or Named Credential problem.
            ErrorLogger.log(SOURCE, ex, null);
        } catch (JSONException ex) {
            ErrorLogger.log(SOURCE, ex, null);
        } catch (TypeException ex) {
            // JSON was valid but not in the expected shape.
            ErrorLogger.log(SOURCE, ex, null);
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