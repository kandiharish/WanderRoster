/**
 * Agentforce action: "Can I expense this?"
 * Checks an amount for an expense category against the running user's travel
 * policy (by Grade), converting foreign currency to INR with the cached rates.
 * Runs as the user talking to the agent, so their own grade is used.
 */
public with sharing class PolicyCheckAction {

    private static final String BASE_CURRENCY = 'INR';
    private static final Map<String, String> CATEGORY_BY_KEY = new Map<String, String>{
        'flight' => 'Flight', 'hotel' => 'Hotel', 'meals' => 'Meals', 'meal' => 'Meals', 'food' => 'Meals',
        'local transport' => 'Local Transport', 'cab' => 'Local Transport', 'taxi' => 'Local Transport',
        'other' => 'Other'
    };

    public class Request {
        @InvocableVariable(label='Expense Category' description='Expense type: Flight, Hotel, Meals, Local Transport or Other.' required=true)
        public String category;
        @InvocableVariable(label='Amount' description='The amount the employee wants to spend or claim.' required=true)
        public Decimal amount;
        @InvocableVariable(label='Currency Code' description='ISO currency code such as INR, USD, EUR, GBP, AED or SGD. Use INR if not stated.')
        public String currencyCode;
        @InvocableVariable(label='Nights' description='Number of nights. Only for Hotel; use 1 if not stated.')
        public Integer nights;
    }

    public class Result {
        @InvocableVariable(label='Answer' description='Plain-language answer to show the employee.')
        public String answer;
        @InvocableVariable(label='Within Policy')
        public Boolean withinPolicy;
        @InvocableVariable(label='Policy Limit INR')
        public Decimal limitInr;
        @InvocableVariable(label='Amount INR')
        public Decimal amountInr;
        @InvocableVariable(label='Receipt Required')
        public Boolean receiptRequired;
        @InvocableVariable(label='Grade')
        public String grade;
    }

    @InvocableMethod(label='Check Expense Against Travel Policy'
        description='Checks whether an expense amount for a category is within the current employee\'s travel policy limit for their grade. Converts foreign currency to INR and says whether a receipt is required.')
    public static List<Result> check(List<Request> requests) {
        String grade = [SELECT Grade__c FROM User WHERE Id = :UserInfo.getUserId()].Grade__c;

        Map<String, Travel_Policy__mdt> policyByCategory = new Map<String, Travel_Policy__mdt>();
        // getAll() reads the cached metadata (no SOQL); a SOQL bind on this picklist fails for non-admin users.
        for (Travel_Policy__mdt policy : Travel_Policy__mdt.getAll().values()) {
            if (policy.Grade__c == grade) {
                policyByCategory.put(policy.Category__c, policy);
            }
        }

        Map<String, Decimal> rateByCurrency = new Map<String, Decimal>{ BASE_CURRENCY => 1 };
        for (Currency_Rate__c rate : [SELECT Currency_Code__c, Rate_To_INR__c FROM Currency_Rate__c WITH USER_MODE]) {
            rateByCurrency.put(rate.Currency_Code__c.toUpperCase(), rate.Rate_To_INR__c);
        }

        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(evaluate(req, grade, policyByCategory, rateByCurrency));
        }
        return results;
    }

    private static Result evaluate(Request req, String grade, Map<String, Travel_Policy__mdt> policyByCategory,
                                   Map<String, Decimal> rateByCurrency) {
        Result res = new Result();
        res.grade = grade;

        String category = req.category == null ? null : CATEGORY_BY_KEY.get(req.category.trim().toLowerCase());
        if (category == null) {
            res.answer = 'I could not match "' + req.category + '" to a category. Please use Flight, Hotel, Meals, Local Transport or Other.';
            return res;
        }
        Travel_Policy__mdt policy = policyByCategory.get(category);
        if (grade == null || policy == null) {
            res.answer = 'I could not find a travel policy for your grade. Please contact Finance.';
            return res;
        }

        String code = String.isBlank(req.currencyCode) ? BASE_CURRENCY : req.currencyCode.trim().toUpperCase();
        Decimal rate = rateByCurrency.get(code);
        if (rate == null) {
            res.answer = 'There is no exchange rate for ' + code + ' yet. Supported: ' + String.join(new List<String>(rateByCurrency.keySet()), ', ') + '.';
            return res;
        }

        Integer nights = (category == 'Hotel' && req.nights != null && req.nights > 0) ? req.nights : 1;
        res.amountInr = (req.amount * rate).setScale(2);
        res.limitInr = (category == 'Hotel' ? policy.Limit_INR__c * nights : policy.Limit_INR__c).setScale(2);
        res.withinPolicy = res.amountInr <= res.limitInr;
        res.receiptRequired = res.amountInr > policy.Receipt_Required_Above__c;

        String amountText = (code == BASE_CURRENCY)
            ? res.amountInr.format() + ' INR'
            : req.amount.format() + ' ' + code + ' (about ' + res.amountInr.format() + ' INR)';
        String limitText = res.limitInr.format() + ' INR' + (category == 'Hotel' ? ' for ' + nights + ' night(s)' : '');

        res.answer = (res.withinPolicy
                ? 'Yes. ' + amountText + ' for ' + category + ' is within your ' + grade + ' limit of ' + limitText + '.'
                : 'No. ' + amountText + ' for ' + category + ' is above your ' + grade + ' limit of ' + limitText
                  + '. You can still claim it, but you must add a justification and your manager will review it.')
            + (res.receiptRequired ? ' Please keep the receipt and upload it to the expense.' : ' A receipt is not required for this amount.');
        return res;
    }
}