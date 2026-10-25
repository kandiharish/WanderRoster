/**
 * Applies currency conversion and travel policy rules to Expense records.
 * Runs in before insert / before update, so the values are saved with the record
 * and no extra DML is needed.
 *
 * Bulk safe: one query per object type, no SOQL inside loops.
 */
public with sharing class ExpenseTriggerHandler {

    private static final String BASE_CURRENCY = 'INR';
    private static final String HOTEL = 'Hotel';

    public static void applyPolicy(List<Expense__c> expenses) {
        Set<Id> tripIds = new Set<Id>();
        Set<String> foreignCurrencies = new Set<String>();

        for (Expense__c exp : expenses) {
            if (exp.Trip__c != null) {
                tripIds.add(exp.Trip__c);
            }
            if (exp.Currency_Code__c != null && exp.Currency_Code__c != BASE_CURRENCY) {
                foreignCurrencies.add(exp.Currency_Code__c);
            }
        }
        if (tripIds.isEmpty()) {
            return;
        }

        Map<Id, Trip__c> tripsById = new Map<Id, Trip__c>([
            SELECT Id, OwnerId
            FROM Trip__c
            WHERE Id IN :tripIds
        ]);

        // The trip owner's grade decides the policy. The owner is a User,
        // so we read the grade from User in a separate query.
        Set<Id> ownerIds = new Set<Id>();
        for (Trip__c trip : tripsById.values()) {
            ownerIds.add(trip.OwnerId);
        }
        Map<Id, User> ownersById = new Map<Id, User>([
            SELECT Id, Grade__c
            FROM User
            WHERE Id IN :ownerIds
        ]);

        Map<String, Decimal> ratesByCurrency = new Map<String, Decimal>();
        for (Currency_Rate__c rate : [
            SELECT Currency_Code__c, Rate_To_INR__c
            FROM Currency_Rate__c
            WHERE Currency_Code__c IN :foreignCurrencies
            WITH USER_MODE
        ]) {
            ratesByCurrency.put(rate.Currency_Code__c, rate.Rate_To_INR__c);
        }

        // Policy table is small custom metadata; getAll() reads it from cache without using a SOQL query.
        Map<String, Decimal> limitByGradeAndCategory = new Map<String, Decimal>();
        for (Travel_Policy__mdt policy : Travel_Policy__mdt.getAll().values()) {
            limitByGradeAndCategory.put(policy.Grade__c + '|' + policy.Category__c, policy.Limit_INR__c);
        }

        for (Expense__c exp : expenses) {
            Trip__c trip = tripsById.get(exp.Trip__c);
            if (trip == null || exp.Amount__c == null) {
                continue;
            }

            // 1. Currency conversion
            Decimal rate = (exp.Currency_Code__c == BASE_CURRENCY || exp.Currency_Code__c == null)
                ? 1
                : ratesByCurrency.get(exp.Currency_Code__c);
            if (rate == null) {
                exp.addError('No exchange rate found for ' + exp.Currency_Code__c
                    + '. Ask Finance to update Currency Rates.');
                continue;
            }
            exp.Amount_INR__c = exp.Amount__c * rate;

            // 2. Travel policy limit (hotel limit is per night)
            User owner = ownersById.get(trip.OwnerId);
            Decimal policyLimit = owner == null
                ? null
                : limitByGradeAndCategory.get(owner.Grade__c + '|' + exp.Category__c);
            if (policyLimit == null) {
                exp.Policy_Limit_INR__c = null;
                exp.Over_Policy__c = false;
                continue;
            }
            if (exp.Category__c == HOTEL) {
                policyLimit = policyLimit * (exp.Nights__c == null ? 1 : exp.Nights__c);
            }
            exp.Policy_Limit_INR__c = policyLimit;
            exp.Over_Policy__c = exp.Amount_INR__c > policyLimit;
        }
    }

    /**
     * Flags an expense as a possible duplicate when the same employee already has
     * an expense with the same date, category, amount and currency (on any trip).
     * Flags only; the manager decides during approval.
     */
    public static void flagDuplicates(List<Expense__c> expenses) {
        Set<Id> tripIds = new Set<Id>();
        Set<Date> dates = new Set<Date>();
        Set<Id> currentIds = new Set<Id>();
        for (Expense__c exp : expenses) {
            if (exp.Trip__c != null && exp.Expense_Date__c != null && exp.Amount__c != null) {
                tripIds.add(exp.Trip__c);
                dates.add(exp.Expense_Date__c);
            }
            if (exp.Id != null) {
                currentIds.add(exp.Id);
            }
        }
        if (tripIds.isEmpty()) {
            return;
        }

        Map<Id, Trip__c> tripsById = new Map<Id, Trip__c>([
            SELECT Id, OwnerId
            FROM Trip__c
            WHERE Id IN :tripIds
        ]);
        Set<Id> ownerIds = new Set<Id>();
        for (Trip__c trip : tripsById.values()) {
            ownerIds.add(trip.OwnerId);
        }

        Set<String> existingKeys = new Set<String>();
        for (Expense__c other : [
            SELECT Trip__r.OwnerId, Expense_Date__c, Category__c, Amount__c, Currency_Code__c
            FROM Expense__c
            WHERE Trip__r.OwnerId IN :ownerIds
              AND Expense_Date__c IN :dates
              AND Id NOT IN :currentIds
        ]) {
            existingKeys.add(duplicateKey(other.Trip__r.OwnerId, other));
        }

        // Also catch duplicates inside the same save (e.g. a bulk import).
        Set<String> keysInThisSave = new Set<String>();
        for (Expense__c exp : expenses) {
            Trip__c trip = tripsById.get(exp.Trip__c);
            if (trip == null || exp.Expense_Date__c == null || exp.Amount__c == null) {
                continue;
            }
            String key = duplicateKey(trip.OwnerId, exp);
            exp.Possible_Duplicate__c = existingKeys.contains(key) || keysInThisSave.contains(key);
            keysInThisSave.add(key);
        }
    }

    private static String duplicateKey(Id ownerId, Expense__c exp) {
        return ownerId + '|' + exp.Expense_Date__c + '|' + exp.Category__c + '|'
            + exp.Amount__c.setScale(2) + '|' + exp.Currency_Code__c;
    }

    /**
     * Validation rules do not run on delete, so this blocks deleting an expense
     * once its claim is submitted (unless the claim was rejected).
     */
    public static void preventLockedDeletes(List<Expense__c> expenses) {
        Set<Id> tripIds = new Set<Id>();
        for (Expense__c exp : expenses) {
            tripIds.add(exp.Trip__c);
        }
        Map<Id, Trip__c> tripsById = new Map<Id, Trip__c>([
            SELECT Id, Claim_Status__c
            FROM Trip__c
            WHERE Id IN :tripIds
        ]);
        for (Expense__c exp : expenses) {
            Trip__c trip = tripsById.get(exp.Trip__c);
            if (trip != null && !EDITABLE_CLAIM_STATUSES.contains(trip.Claim_Status__c)) {
                exp.addError('This claim is already submitted. Expenses cannot be deleted.');
            }
        }
    }

    private static final Set<String> EDITABLE_CLAIM_STATUSES = new Set<String>{
        null, 'Not Submitted', 'Rejected'
    };
}