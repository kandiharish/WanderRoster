// Creates the SkyWay Travels partner account, contact and portal user (run once).
User kali = [SELECT Id FROM User WHERE Username = 'kali.iyer@upquotient.wrdemo'];
Account acc = new Account(Name = 'SkyWay Travels', OwnerId = kali.Id, Description = 'External travel agency that books tickets for approved WanderRoster trips.');
insert acc;
acc.IsPartner = true;
update acc;
Contact con = new Contact(FirstName = 'Arjun', LastName = 'Mehta', AccountId = acc.Id, Email = 'kandiharish2005@gmail.com', Title = 'Booking Agent');
insert con;
Profile p = [SELECT Id FROM Profile WHERE Name = 'WR Travel Agency User'];
User u = new User(
    FirstName = 'Arjun', LastName = 'Mehta', Alias = 'amehta',
    Username = 'arjun.mehta@skyway.wrdemo', Email = 'kandiharish2005@gmail.com',
    CommunityNickname = 'arjun.skyway', ContactId = con.Id, ProfileId = p.Id,
    TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_IN',
    EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
insert u;
System.debug('PARTNER USER ' + u.Id);
