/**
 * Runs once a day and queues the rate refresh.
 * Schedule it once with: System.schedule('Daily FX Rate Refresh', '0 0 1 * * ?', new CurrencyRateRefreshScheduler());
 */
public with sharing class CurrencyRateRefreshScheduler implements Schedulable {

    public void execute(SchedulableContext context) {
        System.enqueueJob(new CurrencyRateRefreshQueueable());
    }
}