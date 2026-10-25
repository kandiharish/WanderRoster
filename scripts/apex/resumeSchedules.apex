// Re-creates the two daily jobs with their standard times (org time zone).
System.schedule('Daily FX Rate Refresh', '0 0 1 * * ?', new CurrencyRateRefreshScheduler());
System.schedule('Daily Claim Reminder', '0 0 7 * * ?', new ClaimReminderBatch());
