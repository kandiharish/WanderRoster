// Adds the SkyWay Travels partner role to the Travel Agencies public group (run once per new agency).
Group agencies = [SELECT Id FROM Group WHERE DeveloperName = 'Travel_Agencies'];
Group roleGroup = [SELECT Id FROM Group WHERE Type = 'Role' AND RelatedId IN (SELECT Id FROM UserRole WHERE DeveloperName = 'kiyerPartnerPersonAccount')];
insert new GroupMember(GroupId = agencies.Id, UserOrGroupId = roleGroup.Id);
