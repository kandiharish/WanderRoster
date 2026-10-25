// Second run (separate transaction: setup vs non-setup DML): give the portal user the agency permission set.
User u = [SELECT Id FROM User WHERE Username = 'arjun.mehta@skyway.wrdemo'];
PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'WR_Travel_Agency'];
insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
