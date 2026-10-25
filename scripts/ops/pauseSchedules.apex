// Run before deploying classes used by the daily jobs (Salesforce blocks the deploy while they are scheduled).
// sf apex run --file scripts/ops/pauseSchedules.apex   then deploy, then run scripts/ops/resumeSchedules.apex
for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name IN ('Daily Claim Reminder', 'Daily FX Rate Refresh')]) {
    System.abortJob(ct.Id);
}
