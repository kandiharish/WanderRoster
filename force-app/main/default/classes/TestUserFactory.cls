@IsTest
public class TestUserFactory {

    // Creates an employee with a known grade and the WR Employee permission set,
    // so tests don't depend on the grade of whoever runs them.
    public static User createEmployee(String grade, String uniqueName) {
        Profile baseProfile = [SELECT Id FROM Profile WHERE Name = 'WanderRoster Base User'];
        User emp = new User(
            FirstName = 'Test', LastName = uniqueName, Alias = uniqueName.left(8),
            Username = uniqueName + '@wanderroster.test', Email = uniqueName + '@wanderroster.test',
            ProfileId = baseProfile.Id, Grade__c = grade,
            TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        PermissionSet employeeAccess = [SELECT Id FROM PermissionSet WHERE Name = 'WR_Employee'];
        // runAs gives the setup DML (User, permission set) its own context, avoiding MIXED_DML_OPERATION
        // when the calling test also inserts normal records.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert emp;
            insert new PermissionSetAssignment(AssigneeId = emp.Id, PermissionSetId = employeeAccess.Id);
        }
        return emp;
    }

    public static User getEmployee(String uniqueName) {
        return [SELECT Id FROM User WHERE Username = :(uniqueName + '@wanderroster.test')];
    }
}
