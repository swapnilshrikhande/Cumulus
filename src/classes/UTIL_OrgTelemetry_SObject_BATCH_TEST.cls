/*
    Copyright (c) 2018, Salesforce.org
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
* @date 2018
* @group Utilities
* @description Unit Tests related to the org telemetry class
*/
@IsTest(IsParallel=true)
private class UTIL_OrgTelemetry_SObject_BATCH_TEST {

    private static UTIL_FeatureManagement_TEST.Mock featureManagementMock = new UTIL_FeatureManagement_TEST.Mock();
    private static Integer NUM_OPPS_WITH_MULTIPLE_PAYMENTS = 10;
    private static Integer NUM_OPPS_WITH_SINGLE_PAYMENT = 5;

    /**
     * @description Create test data needed for the unit tests in this class
     */
    @TestSetup
    private static void testDataSetup() {
        TDTM_Config_API.disableAllTriggers();

        npe03__Recurring_Donation__c openRd = new npe03__Recurring_Donation__c(
            npe03__Amount__c = 100,
            npe03__Open_Ended_Status__c = System.Label.npe03.RecurringDonationOpenStatus
        );

        npe03__Recurring_Donation__c closedRd = new npe03__Recurring_Donation__c(
            npe03__Amount__c = 1200,
            npe03__Open_Ended_Status__c = System.Label.npe03.RecurringDonationClosedStatus
        );

        insert new List<npe03__Recurring_Donation__c>{ openRd, closedRd };

        Map<Schema.SObjectField, Object> fieldValues = new Map<Schema.SObjectField, Object> {
            Opportunity.Amount => 100,
            Opportunity.npe03__Recurring_Donation__c => openRd.Id
        };

        //Build opps for open recurring donation
        List<Opportunity> opps = buildOpps(1, fieldValues);

        //Build opps for closed recurring donation
        fieldValues.put(Opportunity.npe03__Recurring_Donation__c, closedRd.Id);
        opps.addAll(buildOpps(12, fieldValues));

        insert opps;

        setupOppsWithPayments();
    }

    /**
     * @description Creates opportunities with single and multiple payments
     */
    private static void setupOppsWithPayments() {
        Map<Schema.SObjectField, Object> fieldValues = new Map<Schema.SObjectField, Object> {
            Opportunity.Amount => 100
        };

        List<Opportunity> opps = new List<Opportunity>();

        List<Opportunity> oppsWithMultiplePayments = buildOpps(NUM_OPPS_WITH_MULTIPLE_PAYMENTS, fieldValues);
        opps.addAll(oppsWithMultiplePayments);

        List<Opportunity> oppsWithSinglePayment = buildOpps(NUM_OPPS_WITH_SINGLE_PAYMENT, fieldValues);
        opps.addAll(oppsWithSinglePayment);

        insert opps;

        List<npe01__OppPayment__c> payments = buildPaymentsForOpps(oppsWithMultiplePayments, 2);
        payments.addAll(buildPaymentsForOpps(oppsWithSinglePayment, 1));

        insert payments;
    }


    /**
     * @description Provide coverage test for the executed batch job. There's no way to verify that the
     * job executed; and the job itself modifies no data that can be validated against.
     * The lack of a failed test itself is an implicit assert that the batch job completed.
     */
    @IsTest
    private static void testSObjectBatchJob() {
        UTIL_OrgTelemetry_SObject_BATCH oppBatch =
            new UTIL_OrgTelemetry_SObject_BATCH(UTIL_OrgTelemetry_SObject_BATCH.TelemetryBatchJobMode.OPPORTUNITIES);
        oppBatch.featureManager = (UTIL_FeatureManagement) Test.createStub(UTIL_FeatureManagement.class, featureManagementMock);

        UTIL_OrgTelemetry_SObject_BATCH rdBatch =
            new UTIL_OrgTelemetry_SObject_BATCH(UTIL_OrgTelemetry_SObject_BATCH.TelemetryBatchJobMode.RECURRING_DONATIONS);
        rdBatch.featureManager = (UTIL_FeatureManagement) Test.createStub(UTIL_FeatureManagement.class, featureManagementMock);

        Test.startTest();
        Database.executeBatch(oppBatch);
        Database.executeBatch(rdBatch);
        Test.stopTest();
    }

    /**
     * @description Confirms OPPORTUNITIES job mode queries for the correct SObject type with the correct limit
     */
    @IsTest
    private static void opportunitiesJobModeShouldReturnCorrectQueryWhenThereIsNoLastProcessedId() {
        UTIL_OrgTelemetry_SObject_BATCH oppBatch =
            new UTIL_OrgTelemetry_SObject_BATCH(UTIL_OrgTelemetry_SObject_BATCH.TelemetryBatchJobMode.OPPORTUNITIES);

        String oppBatchQuery = oppBatch.start(null).getQuery();
        System.assert(oppBatchQuery.endsWith('LIMIT 10000000'), 'The query should be limited with the default chunk size');

        List<SObject> actualRecords = Database.query(oppBatchQuery);
        System.assert(actualRecords instanceof List<Opportunity>,
            'OPPORTUNITIES job mode should query Opportunities');

        assertOnOrderedSObjects(queryOpportunitiesInIdOrder(), actualRecords);
    }

    /**
     * @description Confirms RECURRING_DONATIONS job mode queries for the correct SObject type with the correct limit
     */
    @IsTest
    private static void recurringDonationsJobModeShouldReturnCorrectQueryWhenThereIsNoLastProcessedId() {
        UTIL_OrgTelemetry_SObject_BATCH rdBatch =
            new UTIL_OrgTelemetry_SObject_BATCH(UTIL_OrgTelemetry_SObject_BATCH.TelemetryBatchJobMode.RECURRING_DONATIONS);
        rdBatch.chunkSize = 100;

        String rdBatchQuery = rdBatch.start(null).getQuery();
        System.assert(rdBatchQuery.endsWith('LIMIT 100'), 'The query should be limited with the specified chunk size');

        List<SObject> actualRecords = Database.query(rdBatchQuery);
        System.assert(Database.query(rdBatchQuery) instanceof List<npe03__Recurring_Donation__c>,
            'RECURRING_DONATIONS job mode should query Recurring Donations');

        assertOnOrderedSObjects(queryRecurringDonationsInIdOrder(), actualRecords);
    }

    /**
     * @description Confirms OPPORTUNITIES job modes query for the correct SObject type with the correct Id offset
     */
    @IsTest
    private static void opportunitiesJobModeShouldReturnCorrectQueryWhenThereIsALastProcessedId() {
        List<SObject> expectedRecords = queryOpportunitiesInIdOrder();

        UTIL_OrgTelemetry_SObject_BATCH oppBatch =
            new UTIL_OrgTelemetry_SObject_BATCH(UTIL_OrgTelemetry_SObject_BATCH.TelemetryBatchJobMode.OPPORTUNITIES);

        //offset the first Id
        oppBatch.lastProcessedId = expectedRecords[0].Id;
        expectedRecords.remove(0);

        String oppBatchQuery = oppBatch.start(null).getQuery();

        List<SObject> actualRecords = Database.query(oppBatchQuery);

        assertOnOrderedSObjects(expectedRecords, actualRecords);
    }

    /**
     * @description Confirms RECURRING_DONATIONS job modes query for the correct SObject type with the correct Id offset
     */
    @IsTest
    private static void recurringDonationsJobModeShouldReturnCorrectQueryWhenThereIsALastProcessedId() {
        List<SObject> expectedRecords = queryRecurringDonationsInIdOrder();

        UTIL_OrgTelemetry_SObject_BATCH rdBatch =
            new UTIL_OrgTelemetry_SObject_BATCH(UTIL_OrgTelemetry_SObject_BATCH.TelemetryBatchJobMode.RECURRING_DONATIONS);

        //offset the first Id
        rdBatch.lastProcessedId = expectedRecords[0].Id;
        expectedRecords.remove(0);

        String rdBatchQuery = rdBatch.start(null).getQuery();

        List<SObject> actualRecords = Database.query(rdBatchQuery);

        assertOnOrderedSObjects(expectedRecords, actualRecords);
    }

    /**
     * @description Confirms Recurring Donation Opportunity counts are calculated correctly
     */
    @IsTest
    private static void shouldCalculateCorrectRecurringDonationOppMetrics() {
        UTIL_OrgTelemetry_SObject_BATCH oppBatch =
            new UTIL_OrgTelemetry_SObject_BATCH(UTIL_OrgTelemetry_SObject_BATCH.TelemetryBatchJobMode.OPPORTUNITIES);

        String oppBatchQuery = oppBatch.start(null).getQuery();
        List<Opportunity> opps = Database.query(oppBatchQuery);

        Test.startTest();
        oppBatch.execute(null, opps);
        Test.stopTest();

        System.assertEquals(opps[opps.size() - 1 ].Id, oppBatch.lastProcessedId,
            'The lastProcessedId should be cached correctly');

        System.assertEquals(13, oppBatch.rdAllOppsCount,
            'The number of opps should be tracked correctly');
        System.assertEquals(1, oppBatch.rdOpenStatusOppsCount,
            'The number of open ended opps should be tracked correctly');
    }

    /**
     * @description Confirms Recurring Donation counts are calculated correctly
     */
    @IsTest
    private static void shouldCalculateCorrectRecurringDonationMetrics() {
        UTIL_OrgTelemetry_SObject_BATCH rdBatch =
            new UTIL_OrgTelemetry_SObject_BATCH(UTIL_OrgTelemetry_SObject_BATCH.TelemetryBatchJobMode.RECURRING_DONATIONS);

        String rdBatchQuery = rdBatch.start(null).getQuery();
        List<npe03__Recurring_Donation__c> recurringDonations = Database.query(rdBatchQuery);

        Test.startTest();
        rdBatch.execute(null, recurringDonations);
        Test.stopTest();

        System.assertEquals(recurringDonations[recurringDonations.size() - 1 ].Id, rdBatch.lastProcessedId,
            'The lastProcessedId should be cached correctly'
        );

        System.assertEquals(2, rdBatch.rdAllCount,
            'The number of Recurring Donations should be tracked correctly');

        System.assertEquals(1, rdBatch.rdDiffCount,
            'The number of Recurring Donations with an amount differing from its opportunities should be tracked correctly');
    }

    /**
     * @description Confirms Opps with Payments counts are calculated correctly
     */
    @IsTest
    private static void shouldCalculateOppPaymentMetrics() {
        UTIL_OrgTelemetry_SObject_BATCH paymentBatch =
            new UTIL_OrgTelemetry_SObject_BATCH(UTIL_OrgTelemetry_SObject_BATCH.TelemetryBatchJobMode.OPPORTUNITIES);

        String paymentBatchQuery = paymentBatch.start(null).getQuery();
        List<Opportunity> opps = Database.query(paymentBatchQuery);

        Test.startTest();
        paymentBatch.execute(null, opps);
        Test.stopTest();

        System.assertEquals(opps[opps.size() - 1 ].Id, paymentBatch.lastProcessedId,
            'The lastProcessedId should be cached correctly'
        );

        System.assertEquals(NUM_OPPS_WITH_MULTIPLE_PAYMENTS, paymentBatch.oppsWithMultiplePaymentsCount,
            'The number of Opportunities with multiple payments should be tracked correctly');

        System.assertEquals(
            NUM_OPPS_WITH_MULTIPLE_PAYMENTS + NUM_OPPS_WITH_SINGLE_PAYMENT,
            paymentBatch.oppsWithPayments,
            'The number of Opportunities with payments should be tracked correctly'
        );
    }

    /**
     * @description Confirms Recurring Donation Opportunity metrics are captured in FeatureManagement
     * at the end of the batch
     */
    @isTest
    private static void shouldCaptureRecurringDonationOppMetricsInFeatureManagement() {
        UTIL_OrgTelemetry_SObject_BATCH oppBatch =
            new UTIL_OrgTelemetry_SObject_BATCH(UTIL_OrgTelemetry_SObject_BATCH.TelemetryBatchJobMode.OPPORTUNITIES);
        oppBatch.featureManager = (UTIL_FeatureManagement) Test.createStub(UTIL_FeatureManagement.class, featureManagementMock);

        oppBatch.rdAllOppsCount = 2;
        oppBatch.rdOpenStatusOppsCount = 1;

        oppBatch.rdAllCount = 4;
        oppBatch.rdDiffCount = 3;

        Test.startTest();
        oppBatch.finish(null);
        Test.stopTest();

        System.assertEquals(
            oppBatch.rdAllOppsCount,
            featureManagementMock.packageIntegerValuesByName.get(
                UTIL_OrgTelemetry_SVC.TelemetryParameterName.Data_CountRdOppsAll.name()
            ),
            'setPackageIntegerValue should have been called with the feature Data_CountRdOppsAll and set correctly'
        );

        System.assertEquals(
            oppBatch.rdOpenStatusOppsCount,
            featureManagementMock.packageIntegerValuesByName.get(
                UTIL_OrgTelemetry_SVC.TelemetryParameterName.Data_CountRdOppsOpenEnded.name()
            ),
            'setPackageIntegerValue should have been called with the feature Data_CountRdOppsOpenEnded and set correctly'
        );
    }

    /**
     * @description Confirms Recurring Donation metrics are captured in FeatureManagement at the end of the batch
     */
    @isTest
    private static void shouldCaptureRecurringDonationMetricsInFeatureManagement() {
        UTIL_OrgTelemetry_SObject_BATCH rdBatch =
            new UTIL_OrgTelemetry_SObject_BATCH(UTIL_OrgTelemetry_SObject_BATCH.TelemetryBatchJobMode.RECURRING_DONATIONS);
        rdBatch.featureManager = (UTIL_FeatureManagement) Test.createStub(UTIL_FeatureManagement.class, featureManagementMock);

        rdBatch.rdAllOppsCount = 2;
        rdBatch.rdOpenStatusOppsCount = 1;

        rdBatch.rdAllCount = 4;
        rdBatch.rdDiffCount = 3;

        Test.startTest();
        rdBatch.finish(null);
        Test.stopTest();

        System.assertEquals(
            rdBatch.rdAllCount,
            featureManagementMock.packageIntegerValuesByName.get(
                UTIL_OrgTelemetry_SVC.TelemetryParameterName.Data_CountRecurringDonationsAll.name()
            ),
            'setPackageIntegerValue should have been called with the feature Data_CountRecurringDonationsAll and set correctly'
        );

        System.assertEquals(
            rdBatch.rdDiffCount,
            featureManagementMock.packageIntegerValuesByName.get(
                UTIL_OrgTelemetry_SVC.TelemetryParameterName.Data_CountRdsWithDiffAmount.name()
            ),
            'setPackageIntegerValue should have been called with the feature Data_CountRdsWithDiffAmount and set correctly'
        );
    }

    /**
     * @description Confirms Opportunity Payment metrics are captured in FeatureManagement at the end of the batch
     * when Auto Payments are enabled
     */
    /* TODO: Holding on Data_OppPaymentsWithoutPaymentsEnabled metric, reenable test when
             you move forward with Data_OppPaymentsWithoutPaymentsEnabled
    @isTest
    private static void shouldCaptureOppPaymentMetricsInFeatureManagementWhenAutoPaymentsEnabled() {
        UTIL_CustomSettingsFacade.getContactsSettingsForTests(
            new npe01__Contacts_And_Orgs_Settings__c(npe01__Payments_Enabled__c = true)
        );

        UTIL_OrgTelemetry_SObject_BATCH paymentBatch =
            new UTIL_OrgTelemetry_SObject_BATCH(UTIL_OrgTelemetry_SObject_BATCH.TelemetryBatchJobMode.OPPORTUNITIES);
        paymentBatch.featureManager = (UTIL_FeatureManagement) Test.createStub(UTIL_FeatureManagement.class, featureManagementMock);

        paymentBatch.oppsWithMultiplePaymentsCount = NUM_OPPS_WITH_MULTIPLE_PAYMENTS;

        Test.startTest();
        paymentBatch.finish(null);
        Test.stopTest();

        System.assertEquals(
            NUM_OPPS_WITH_MULTIPLE_PAYMENTS,
            featureManagementMock.packageIntegerValuesByName.get(
                UTIL_OrgTelemetry_SVC.TelemetryParameterName.Data_CountOppsWithMultiplePayments.name()
            ),
            'setPackageIntegerValue should have been called with the feature Data_CountOppsWithMultiplePayments and set correctly'
        );

        System.assertEquals(
            0,
            featureManagementMock.packageIntegerValuesByName.get(
                UTIL_OrgTelemetry_SVC.TelemetryParameterName.Data_OppPaymentsWithoutPaymentsEnabled.name()
            ),
            'setPackageIntegerValue should have been called with the feature Data_OppPaymentsWithoutPaymentsEnabled and set correctly'
        );
    }
    */

    /**
     * @description Confirms Opportunity Payment metrics are captured in FeatureManagement at the end of the batch
     * when Auto Payments are not enabled
     */

    /* TODO: Holding on Data_OppPaymentsWithoutPaymentsEnabled metric, reenable test when
             you move forward with Data_OppPaymentsWithoutPaymentsEnabled

    @isTest
    private static void shouldCaptureOppPaymentMetricsInFeatureManagementWhenAutoPaymentsNotEnabled() {
        UTIL_CustomSettingsFacade.getContactsSettingsForTests(
            new npe01__Contacts_And_Orgs_Settings__c(npe01__Payments_Enabled__c = false)
        );

        UTIL_OrgTelemetry_SObject_BATCH paymentBatch =
            new UTIL_OrgTelemetry_SObject_BATCH(UTIL_OrgTelemetry_SObject_BATCH.TelemetryBatchJobMode.OPPORTUNITIES);
        paymentBatch.featureManager = (UTIL_FeatureManagement) Test.createStub(UTIL_FeatureManagement.class, featureManagementMock);

        paymentBatch.oppsWithMultiplePaymentsCount = NUM_OPPS_WITH_MULTIPLE_PAYMENTS;
        paymentBatch.oppsWithPayments = NUM_OPPS_WITH_MULTIPLE_PAYMENTS + NUM_OPPS_WITH_SINGLE_PAYMENT;

        Test.startTest();
        paymentBatch.finish(null);
        Test.stopTest();

        System.assertEquals(
            NUM_OPPS_WITH_MULTIPLE_PAYMENTS,
            featureManagementMock.packageIntegerValuesByName.get(
                UTIL_OrgTelemetry_SVC.TelemetryParameterName.Data_CountOppsWithMultiplePayments.name()
            ),
            'setPackageIntegerValue should have been called with the feature Data_CountOppsWithMultiplePayments and set correctly'
        );

        System.assertEquals(
            NUM_OPPS_WITH_MULTIPLE_PAYMENTS + NUM_OPPS_WITH_SINGLE_PAYMENT,
            featureManagementMock.packageIntegerValuesByName.get(
                UTIL_OrgTelemetry_SVC.TelemetryParameterName.Data_OppPaymentsWithoutPaymentsEnabled.name()
            ),
            'setPackageIntegerValue should have been called with the feature Data_OppPaymentsWithoutPaymentsEnabled and set correctly'
        );
    }
    */

    /**
     * @description Confirms batch is not run again if lastProcessedId is null
     */
    @isTest
    private static void shouldNotChainNextBatchIfLastProcessedIdIsNull() {
        UTIL_OrgTelemetry_SObject_BATCH batch =
            new UTIL_OrgTelemetry_SObject_BATCH(UTIL_OrgTelemetry_SObject_BATCH.TelemetryBatchJobMode.OPPORTUNITIES);
        batch.featureManager = (UTIL_FeatureManagement) Test.createStub(UTIL_FeatureManagement.class, featureManagementMock);

        Test.startTest();
        batch.finish(null);
        Test.stopTest();

        List<AsyncApexJob> jobs = queryOrgTelemetrySObjectBatchJobs();

        System.assert(jobs.isEmpty(), 'The telemetry batch should not be started again');
    }

    /**
     * @description Confirms that the finish method does not chain the next batch
     * if there are no more records to process
     */
    @isTest
    private static void shouldNotChainNextBatchIfThereAreNoMoreRecordsToProcess() {
        List<Opportunity> testOpps = queryOpportunitiesInIdOrder();

        UTIL_OrgTelemetry_SObject_BATCH batch =
            new UTIL_OrgTelemetry_SObject_BATCH(UTIL_OrgTelemetry_SObject_BATCH.TelemetryBatchJobMode.OPPORTUNITIES);
        batch.lastProcessedId = testOpps[testOpps.size() - 1].Id;
        batch.featureManager = (UTIL_FeatureManagement) Test.createStub(UTIL_FeatureManagement.class, featureManagementMock);

        Test.startTest();
        batch.finish(null);
        Test.stopTest();

        List<AsyncApexJob> jobs = queryOrgTelemetrySObjectBatchJobs();

        System.assert(jobs.isEmpty(), 'The telemetry batch should not be started again');
    }

    /**
     * @description Confirms that the finish method chains the next batch with an offset of the last Id processed.
     * Cannot assert on much else other than that job was ran. During the test, state on batch is reverted
     * after the batch is executed. For example, rdCountAll = 0 on the batch instance before the test runs.
     * The finish() method chains the next batch and rdCountAll is incremented to 1. After stopTest(), rdCountAll is
     * reset to 0. This can be confirmed by putting a failing assertion in the batch class itself where rdCountAll is
     * actually incremented and outputing rdCountAll
     */
    @isTest
    private static void shouldChainNextBatchOffsetByLastRecordProcessed() {
        List<npe03__Recurring_Donation__c> recurringDonations = queryRecurringDonationsInIdOrder();

        UTIL_OrgTelemetry_SObject_BATCH batch =
            new UTIL_OrgTelemetry_SObject_BATCH(UTIL_OrgTelemetry_SObject_BATCH.TelemetryBatchJobMode.RECURRING_DONATIONS);
        batch.lastProcessedId = recurringDonations[0].Id;
        batch.featureManager = (UTIL_FeatureManagement) Test.createStub(UTIL_FeatureManagement.class, featureManagementMock);

        Test.startTest();
        batch.finish(null);
        Test.stopTest();

        List<AsyncApexJob> jobs = queryOrgTelemetrySObjectBatchJobs();

        System.assertEquals(1, jobs.size(), 'The telemetry batch should have been started again');

        System.assertEquals(
            null,
            featureManagementMock.packageIntegerValuesByName.get(
                UTIL_OrgTelemetry_SVC.TelemetryParameterName.Data_CountRecurringDonationsAll.name()
            ),
            'setPackageIntegerValue should not have been called'
        );

        System.assertEquals(
            null,
            featureManagementMock.packageIntegerValuesByName.get(
                UTIL_OrgTelemetry_SVC.TelemetryParameterName.Data_CountRdsWithDiffAmount.name()
            ),
            'setPackageIntegerValue should not have been called'
        );
    }

    /**
     * @description Builds test opportunity records with the given field values
     * @param numOpps: number of opportunities to build
     * @param fieldValues: map of values by SObjectField to set on the opportunities
     * @return List of uninserted Opportunities
     */
    private static List<Opportunity> buildOpps(Integer numOpps, Map<Schema.SObjectField, Object> fieldValues) {
        List<Opportunity> opps = new List<Opportunity>();

        for (Integer i = 0; i < numOpps; i++) {
            Opportunity opp = new Opportunity(
                Name = 'Test Opp ' + i,
                StageName = UTIL_UnitTestData_TEST.getClosedWonStage(),
                CloseDate = Date.today()
            );

            for (Schema.SObjectField field : fieldValues.keySet()) {
                opp.put(field, fieldValues.get(field));
            }

            opps.add(opp);
        }

        return opps;
    }

    /**
     * @description Builds test payments records for given opportunities
     * @param opps: Parent opportunities to build payments for
     * @param numPayments: Number of payments for each parent opportunity
     * @return List of uninserted npe01__OppPayment__c records
     */
    private static List<npe01__OppPayment__c> buildPaymentsForOpps(List<Opportunity> opps, Integer numPayments) {
        List<npe01__OppPayment__c> payments = new List<npe01__OppPayment__c>();
        for (Opportunity opp : opps) {
            for (Integer i = 0; i < numPayments; i++) {
                payments.add(new npe01__OppPayment__c(npe01__Payment_Amount__c = 100, npe01__Opportunity__c = opp.Id));
            }
        }
        return payments;
    }


    /**
     * @description Queries opportunities in order of Id
     * @return List of Opportunity ordered by Id
     */
    private static List<Opportunity> queryOpportunitiesInIdOrder() {
        return [SELECT Id FROM Opportunity ORDER BY Id];
    }

    /**
     * @description Queries recurring donations in order of Id
     * @return List of npe03__Recurring_Donation__c ordered by Id
     */
    private static List<npe03__Recurring_Donation__c> queryRecurringDonationsInIdOrder() {
        return [SELECT Id FROM npe03__Recurring_Donation__c ORDER BY Id];
    }

    /**
     * @description Confirms records are in the same order and are the same size
     * @param expectedRecords: list of expected, ordered SObjects to validate against
     * @param actualRecords: list of actual, ordered SObjects to validate
     */
    private static void assertOnOrderedSObjects(List<SObject> expectedRecords, List<SObject> actualRecords) {
        System.assertEquals(expectedRecords.size(), actualRecords.size(),
            'The correct number of records should be returned');

        for (Integer i = 0; i < expectedRecords.size(); i++) {
            System.assertEquals(expectedRecords[i].Id, actualRecords[i].Id,
                'The records should be returned in the correct order');
        }
    }

    /**
     * @description Retrieves UTIL_OrgTelemetry_SObject_BATCH batch jobs
     * @return List of AsyncApexJob for class UTIL_OrgTelemetry_SObject_BATCH
     */
    private static List<AsyncApexJob> queryOrgTelemetrySObjectBatchJobs() {
        return [
            SELECT Id FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            AND ApexClass.Name = 'UTIL_OrgTelemetry_SObject_BATCH'
        ];
    }
}