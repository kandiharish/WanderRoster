/**
 * Writes Error_Log__c records for problems that happen in background work
 * (queueable callouts, batch jobs, notifications) where no user sees an error.
 *
 * Logging must never break the work it reports on, so every method swallows
 * its own failures. Logs are written in system mode on purpose: the user whose
 * action caused the problem usually has no access to Error_Log__c.
 */
public with sharing class ErrorLogger {

    public static final String ERROR = 'Error';
    public static final String WARNING = 'Warning';

    private static final Integer MESSAGE_MAX = 32000;

    public static void log(String source, Exception ex, Id recordId) {
        String message = ex.getTypeName() + ': ' + ex.getMessage() + '\n' + ex.getStackTraceString();
        log(source, message, recordId, ERROR);
    }

    public static void log(String source, String message, Id recordId, String severity) {
        insertLogs(new List<Error_Log__c>{ build(source, message, recordId, severity) });
    }

    /**
     * Logs every failed row of a partial-success DML and returns how many failed.
     * The results list and the records list are in the same order.
     */
    public static Integer logFailures(String source, List<Database.SaveResult> results, List<SObject> records) {
        List<Error_Log__c> logs = new List<Error_Log__c>();
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                logs.add(build(source, describe(results[i].getErrors()), records[i].Id, ERROR));
            }
        }
        insertLogs(logs);
        return logs.size();
    }

    /** Same as above for upserts, which return UpsertResult instead of SaveResult. */
    public static Integer logFailures(String source, List<Database.UpsertResult> results, List<SObject> records) {
        List<Error_Log__c> logs = new List<Error_Log__c>();
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                logs.add(build(source, describe(results[i].getErrors()), records[i].Id, ERROR));
            }
        }
        insertLogs(logs);
        return logs.size();
    }

    private static Error_Log__c build(String source, String message, Id recordId, String severity) {
        return new Error_Log__c(
            Source__c = source == null ? 'Unknown' : source.left(100),
            Message__c = message == null ? null : message.left(MESSAGE_MAX),
            Record_Id__c = recordId,
            Severity__c = severity
        );
    }

    private static String describe(List<Database.Error> errors) {
        List<String> parts = new List<String>();
        for (Database.Error err : errors) {
            parts.add(err.getStatusCode() + ': ' + err.getMessage());
        }
        return String.join(parts, '\n');
    }

    private static void insertLogs(List<Error_Log__c> logs) {
        if (logs.isEmpty()) {
            return;
        }
        try {
            // System mode on purpose: the user whose action failed usually has no access to Error_Log__c.
            Database.insert(logs, false, AccessLevel.SYSTEM_MODE);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'ErrorLogger could not write logs: ' + ex.getMessage());
        }
    }
}
