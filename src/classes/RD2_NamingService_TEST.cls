/*
    Copyright (c) 2019 Salesforce.org
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Salesforce.org nor the names of
      its contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/
/**
* @author Salesforce.org
* @date 2019
* @group Recurring Donations
* @description Recurring Donations Naming Service tests
*
*/
@isTest
public with sharing class RD2_NamingService_TEST {
    private static final Boolean isMultiCurrencyEnabled = UserInfo.isMultiCurrencyOrganization();
    private static final String currencyCodeOrSymbol = isMultiCurrencyEnabled
        ? UserInfo.getDefaultCurrency() + ' '
        : UTIL_Currency.getInstance().getCurrencySymbol(UserInfo.getDefaultCurrency());

    private static Account acc = getAccountMock();

    /***
    * @description Verifies Recurring Donation Name is not generated when automatic naming is not enabled
    */
    @isTest
    private static void shouldNotAutogenerateNameWhenAutomaticNamingIsNotEnabled() {
        String name = 'foo';
        npe03__Recurring_Donation__c rd = new RD2_TestRecurringDonationBuilder()
            .withName(name)
            .withAmount(100)
            .build();
        
        RD2_NamingService service = new RD2_NamingService();
        RD2_NamingService.settings = (RD2_Settings) Test.createStub(RD2_Settings.class, new RD2_Settings_TEST.Stub());

        service.autogenerateNames(new List<npe03__Recurring_Donation__c>{ rd });

        System.assertEquals(name, rd.Name, 'The name should not be generated.');
    }

    /***
    * @description Verifies Recurring Donation Name is generated when automatic naming is enabled
    */
    @isTest
    private static void shouldAutogenerateNameWhenAutomaticNamingIsEnabled() {
        String name = 'foo';
        npe03__Recurring_Donation__c rd = new RD2_TestRecurringDonationBuilder()
            .withName(name)
            .withAmount(100)
            .build();
        
        RD2_NamingService service = buildAutomaticNamingService();
        service.autogenerateNames(new List<npe03__Recurring_Donation__c>{ rd });

        System.assertNotEquals(name, rd.Name, 'The name should be generated.');
    }

    /***
    * @description Verifies generated Recurring Donation Name is constructed using 
    * Account Name, Amount and the suffix.
    */
    @isTest
    private static void shouldAutogenerateNameUsingProvidedAccountAndAmount() {
        npe03__Recurring_Donation__c rd = new RD2_TestRecurringDonationBuilder()
            .withName('foo')
            .withAccount(acc.Id)
            .withAmount(100.25)
            .withCurrencyIsoCode(UserInfo.getDefaultCurrency())
            .build();
        
        RD2_NamingService service = buildAutomaticNamingService(acc);
        service.autogenerateNames(new List<npe03__Recurring_Donation__c>{ rd });

        System.assertEquals(getExpectedName(acc, '100.25'), rd.Name, 'The name should match.');
    }

    /***
    * @description Verifies generated Recurring Donation Name is constructed using 
    * Contact Name, Amount and the suffix.
    */
    @isTest
    private static void shouldAutogenerateNameUsingProvidedContactAndAmount() {
        Contact contact = getContactMock();
        npe03__Recurring_Donation__c rd = new RD2_TestRecurringDonationBuilder()
            .withName('foo')
            .withAccount(acc.Id)
            .withContact(contact.Id)
            .withAmount(100.25)
            .withCurrencyIsoCode(UserInfo.getDefaultCurrency())
            .build();
        
        RD2_NamingService service = buildAutomaticNamingService(
            new List<Account>{ acc },
            new List<Contact>{ contact }
        );

        service.autogenerateNames(new List<npe03__Recurring_Donation__c>{ rd });

        System.assertEquals(getExpectedName(contact, '100.25'), rd.Name, 'The name should match.');
    }

    /***
    * @description Verifies formatted name contains currency symbol when multi-currency is enabled
    */
    @isTest
    private static void shouldUseCurrencySymbolInNameWhenMultiCurrencyIsEnabled() {
        if (!isMultiCurrencyEnabled) {
            return;
        }

        npe03__Recurring_Donation__c rd = new RD2_TestRecurringDonationBuilder()
            .withAccount(acc.Id)
            .withAmount(100.25)
            .withCurrencyIsoCode('CAD')
            .build();
        
        RD2_NamingService service = buildAutomaticNamingService(acc);        
        service.autogenerateNames(new List<npe03__Recurring_Donation__c>{ rd });

        String expectedName = acc.Name + ' CAD 100.25 - ' + System.Label.RecurringDonationNameSuffix;
        System.assertEquals(expectedName, rd.Name, 'The amount format should match.');
    }

    /***
    * @description Verifies formatted name amount does not contain .00 
    */
    @isTest
    private static void shouldReturnAmountWithoutTrailingZeros() {
        npe03__Recurring_Donation__c rd = new RD2_TestRecurringDonationBuilder()
            .withAccount(acc.Id)
            .withAmount(100.00)
            .withCurrencyIsoCode(UserInfo.getDefaultCurrency())
            .build();
        
        RD2_NamingService service = buildAutomaticNamingService(acc);        
        service.autogenerateNames(new List<npe03__Recurring_Donation__c>{ rd });

        System.assertEquals(getExpectedName(acc, '100'), rd.Name, 'The amount format should match.');
    }

    /***
    * @description Verifies donor name is abbreviated if total name construct is longer than max name length
    */
    @isTest
    private static void shouldAbbreviateDonorNameIfLengthIsOverMax() {
        final Integer maxLength = RD2_NamingService.MAX_NAME_LENGTH;
        String padding = 'ABC123';
        String origAccountName = acc.Name;

        acc.Name = String.valueOf(acc.Name).rightPad(maxLength, padding).left(maxLength);

        npe03__Recurring_Donation__c rd = new RD2_TestRecurringDonationBuilder()
            .withAccount(acc.Id)
            .withAmount(100.00)
            .withCurrencyIsoCode(UserInfo.getDefaultCurrency())
            .build();
        
        RD2_NamingService service = buildAutomaticNamingService(acc);        
        service.autogenerateNames(new List<npe03__Recurring_Donation__c>{ rd });

        String expectedSuffix = '... ' + currencyCodeOrSymbol + '100 - ' + System.Label.RecurringDonationNameSuffix;
        System.assert(rd.Name.startsWith(origAccountName), 'Donor name should be included: ' + rd.Name);
        System.assert(rd.Name.endsWith(expectedSuffix), 'Donor name should be abbreviated: ' + rd.Name);
    }

    /***
    * @description Should mark record as changed when Account has changed
    */
    @isTest
    private static void shouldReturnTrueWhenAccountHasChanged() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'foo'),
            new Account(Name = 'bar')
        };
        UTIL_UnitTestData_TEST.setMockIds(accounts);

        npe03__Recurring_Donation__c rd = new RD2_TestRecurringDonationBuilder()
            .withAccount(accounts[0].Id)
            .withAmount(100.00)
            .build();
        npe03__Recurring_Donation__c oldRd = new RD2_TestRecurringDonationBuilder()
            .withAccount(accounts[1].Id)
            .withAmount(100.00)
            .build();

        RD2_NamingService service = new RD2_NamingService();
        System.assertEquals(true, service.hasChanged(rd, oldRd), 'Service should indicate RD has changed');
    }

    /***
    * @description Should mark record as changed when Contact has changed
    */
    @isTest
    private static void shouldReturnTrueWhenContactHasChanged() {
        List<Contact> contacts = new List<Contact>{
            new Contact(LastName = 'foo'),
            new Contact(LastName = 'bar')
        };
        UTIL_UnitTestData_TEST.setMockIds(contacts);

        npe03__Recurring_Donation__c rd = new RD2_TestRecurringDonationBuilder()
            .withContact(contacts[0].Id)
            .withAmount(100.00)
            .build();
        npe03__Recurring_Donation__c oldRd = new RD2_TestRecurringDonationBuilder()
            .withContact(contacts[1].Id)
            .withAmount(100.00)
            .build();

        RD2_NamingService service = new RD2_NamingService();
        System.assertEquals(true, service.hasChanged(rd, oldRd), 'Service should indicate RD has changed');
    }

    /***
    * @description Should mark record as changed when Amount has changed
    */
    @isTest
    private static void shouldReturnTrueWhenAmountHasChanged() {
        npe03__Recurring_Donation__c rd = new RD2_TestRecurringDonationBuilder()
            .withAccount(acc.Id)
            .withAmount(100.00)
            .build();
        npe03__Recurring_Donation__c oldRd = new RD2_TestRecurringDonationBuilder()
            .withAccount(acc.Id)
            .withAmount(100.25)
            .build();

        RD2_NamingService service = new RD2_NamingService();
        System.assertEquals(true, service.hasChanged(rd, oldRd), 'Service should indicate RD has changed');
    }

    /***
    * @description Should mark record as changed when CurrencyIsoCode has changed
    */
    @isTest
    private static void shouldReturnTrueWhenCurrencyHasChanged() {
        if (!isMultiCurrencyEnabled) {
            return;
        }

        npe03__Recurring_Donation__c rd = new RD2_TestRecurringDonationBuilder()
            .withAccount(acc.Id)
            .withAmount(100.00)
            .withCurrencyIsoCode('USD')
            .build();
        npe03__Recurring_Donation__c oldRd = new RD2_TestRecurringDonationBuilder()
            .withAccount(acc.Id)
            .withAmount(100.00)
            .withCurrencyIsoCode('CAD')
            .build();

        RD2_NamingService service = new RD2_NamingService();
        System.assertEquals(true, service.hasChanged(rd, oldRd), 'Service should indicate RD has changed');
    }

    /***
    * @description Should mark record as changed when name contains REPLACE keyword has changed
    */
    @isTest
    private static void shouldReturnTrueWhenNameIsTheReplaceKeyword() {
        npe03__Recurring_Donation__c rd = new RD2_TestRecurringDonationBuilder()
            .withName(System.Label.npo02.NameReplacementText)
            .withAccount(acc.Id)
            .withAmount(100.00)
            .build();
        npe03__Recurring_Donation__c oldRd = new RD2_TestRecurringDonationBuilder()
            .withAccount(acc.Id)
            .withAmount(100.00)
            .build();

        RD2_NamingService service = new RD2_NamingService();
        System.assertEquals(true, service.hasChanged(rd, oldRd), 'Service should indicate RD has changed');
    }

    /***
    * @description Should not mark record as changed when no field used in the name construct has changed
    */
    @isTest
    private static void shouldReturnFalseWhenNameConstructKeyFieldsAreUnchanged() {
        npe03__Recurring_Donation__c rd = new RD2_TestRecurringDonationBuilder()
            .withName('foo')
            .withAccount(acc.Id)
            .withAmount(100.00)
            .build();
        npe03__Recurring_Donation__c oldRd = new RD2_TestRecurringDonationBuilder()
            .withName('bar')
            .withAccount(acc.Id)
            .withAmount(100.00)
            .build();

        RD2_NamingService service = new RD2_NamingService();
        System.assertEquals(false, service.hasChanged(rd, oldRd), 'Service should indicate RD is unchanged');
    }

    /***
    * @description Verifies name is auto-generated only for records having name construct fields changed
    */
    @isTest
    private static void shouldAutogenerateNameWhenNameConstructKeyFieldsAreChanged() {
        List<npe03__Recurring_Donation__c> rds = new List<npe03__Recurring_Donation__c>{
            new RD2_TestRecurringDonationBuilder()
                .withName('foo')
                .withAccount(acc.Id)
                .withAmount(100)
                .withCurrencyIsoCode(UserInfo.getDefaultCurrency())
                .build(),
            new RD2_TestRecurringDonationBuilder()
                .withName('bar')
                .withAccount(acc.Id)
                .withAmount(200)
                .withCurrencyIsoCode(UserInfo.getDefaultCurrency())
                .build()
        };
        UTIL_UnitTestData_TEST.setMockIds(rds);

        List<npe03__Recurring_Donation__c> oldRds = new List<npe03__Recurring_Donation__c>{
            rds[0].clone(),
            rds[1].clone()
        };
        oldRds[0].Id = rds[0].Id;
        oldRds[1].Id = rds[1].Id;
        oldRds[1].npe03__Amount__c = 180;
        
        RD2_NamingService service = buildAutomaticNamingService(acc);
        service.autogenerateNamesOnChange(rds, oldRds);

        System.assertEquals('foo', rds[0].Name, 'RD Name should not change when construct key fields are unchanged');

        System.assertEquals(getExpectedName(acc, '200'), rds[1].Name, 'RD Name should change when construct key fields are changed');
    }

    /***
    * @description Verifies Donor (Account/Contact) names are queried in order to construct the name
    */
    @isTest
    private static void shouldQueryForDonorInformation() {
        acc = new Account(Name = 'RD2 Query Account');
        insert acc;

        Contact contact = new Contact(
            FirstName = 'Jane',
            LastName = 'RD2 Query Contact'
        );
        insert contact;

        List<npe03__Recurring_Donation__c> rds = new List<npe03__Recurring_Donation__c>{
            new RD2_TestRecurringDonationBuilder()
                .withName('foo')
                .withAccount(acc.Id)
                .withAmount(100)
                .withCurrencyIsoCode(UserInfo.getDefaultCurrency())
                .build(),
            new RD2_TestRecurringDonationBuilder()
                .withName('bar')
                .withContact(contact.Id)
                .withAmount(200)
                .withCurrencyIsoCode(UserInfo.getDefaultCurrency())
                .build()
        };

        RD2_NamingService service = buildAutomaticNamingService();
        service.autogenerateNames(rds);

        System.assertEquals(getExpectedName(acc, '100'), rds[0].Name, 'The Account name should be queried and incorporated into the name');
        System.assertEquals(getExpectedName(contact, '200'), rds[1].Name, 'The Contact name should be queried and incorporated into the name');
    }



    // Helpers
    //////////////////


    /***
    * @description Builds expected name
    */
    public static String getExpectedName(Account acc, String amount) {
        return acc.Name + ' ' + currencyCodeOrSymbol + amount + ' - ' + System.Label.RecurringDonationNameSuffix;
    }

    /***
    * @description Builds expected name
    */
    public static String getExpectedName(Contact contact, String amount) {
        String contactName = (String.isBlank(contact.FirstName) ? '' : (contact.FirstName + ' ')) + contact.LastName;

        return contactName + ' ' + currencyCodeOrSymbol + amount + ' - ' + System.Label.RecurringDonationNameSuffix;
    }

    /***
    * @description Builds naming service instance with specified Account as donor
    */
    private static RD2_NamingService buildAutomaticNamingService(Account acc) {
        return buildAutomaticNamingService(new List<Account>{ acc }, new List<Contact>());
    }

    /***
    * @description Builds naming service instance with specified Accounts and Contacts as donors
    */
    private static RD2_NamingService buildAutomaticNamingService(List<Account> accounts, List<Contact> contacts) {
        RD2_NamingService service = buildAutomaticNamingService();

        RD2_Donor_TEST.GatewayMock donorGateway = new RD2_Donor_TEST.GatewayMock()
            .withDonors(accounts)
            .withDonors(contacts);
        service.donorGateway = donorGateway;

        return service;
    }

    /***
    * @description Constructs naming service with Automatic Naming Enabled
    */
    private static RD2_NamingService buildAutomaticNamingService() {
        enableAutomaticNaming();

        return new RD2_NamingService();
    }

    /***
    * @description Enables Automatic Naming Enabled for tests
    */
    public static void enableAutomaticNaming() {
        RD2_NamingService.settings = (RD2_Settings) Test.createStub(
            RD2_Settings.class, 
            new RD2_Settings_TEST.Stub().withAutomaticNamingEnabled()
        );
    }

    /***
    * @description Builds an Account and sets mock Id as the Id
    */
    private static Account getAccountMock() {
        return new Account(
            Name = 'Donor Company',
            Id = UTIL_UnitTestData_TEST.mockId(Account.SObjectType)
        );
    }

    /***
    * @description Builds a Contact and sets mock Id as the Id
    */
    private static Contact getContactMock() {
        return new Contact(
            LastName = 'Smith',
            Id = UTIL_UnitTestData_TEST.mockId(Contact.SObjectType)
        );
    }

}