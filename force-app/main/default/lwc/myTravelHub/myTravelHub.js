import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import canViewPolicyAlerts from '@salesforce/customPermission/View_Policy_Alerts';
import getMyTrips from '@salesforce/apex/TravelHubController.getMyTrips';
import getSummary from '@salesforce/apex/TravelHubController.getSummary';

const CHANNEL = '/event/Policy_Violation__e';
const MAX_ALERTS = 10;

const COLUMNS = [
    { label: 'Trip', fieldName: 'url', type: 'url', typeAttributes: { label: { fieldName: 'Name' } } },
    { label: 'Destination', fieldName: 'Destination_City__c' },
    { label: 'Start', fieldName: 'Start_Date__c', type: 'date-local' },
    { label: 'Trip Status', fieldName: 'Status__c' },
    { label: 'Claim Status', fieldName: 'Claim_Status__c' },
    {
        label: 'Spent (INR)', fieldName: 'Total_Spent_INR__c', type: 'currency',
        typeAttributes: { currencyCode: 'INR' }, cellAttributes: { alignment: 'left' }
    }
];

export default class MyTravelHub extends NavigationMixin(LightningElement) {
    columns = COLUMNS;
    trips = [];
    summary;
    error;
    alerts = [];
    subscription;

    wiredTripsResult;
    wiredSummaryResult;

    @wire(getMyTrips)
    wiredTrips(result) {
        this.wiredTripsResult = result;
        if (result.data) {
            this.trips = result.data.map((trip) => ({ ...trip, url: `/${trip.Id}` }));
            this.error = undefined;
        } else if (result.error) {
            this.error = this.reduceError(result.error);
        }
    }

    @wire(getSummary)
    wiredSummary(result) {
        this.wiredSummaryResult = result;
        if (result.data) {
            this.summary = result.data;
        } else if (result.error) {
            this.error = this.reduceError(result.error);
        }
    }

    get showAlerts() {
        return canViewPolicyAlerts;
    }

    get hasTrips() {
        return this.trips.length > 0;
    }

    get hasAlerts() {
        return this.alerts.length > 0;
    }

    get budgetPercent() {
        if (!this.summary || !this.summary.totalEstimated) {
            return 0;
        }
        return Math.round((this.summary.totalSpent / this.summary.totalEstimated) * 100);
    }

    get budgetBarValue() {
        return Math.min(this.budgetPercent, 100);
    }

    get budgetMessage() {
        const percent = this.budgetPercent;
        if (percent > 100) {
            return `Over your estimates by ${percent - 100}%`;
        }
        return `${percent}% of your estimated trip budget used this year`;
    }

    get budgetClass() {
        return this.budgetPercent > 100 ? 'slds-text-color_error' : 'slds-text-color_weak';
    }

    connectedCallback() {
        if (!canViewPolicyAlerts) {
            return;
        }
        onError((err) => {
            // Streaming errors are logged; the rest of the hub keeps working.
            console.error('Policy alert stream error', JSON.stringify(err));
        });
        subscribe(CHANNEL, -1, (message) => this.handleViolation(message)).then((response) => {
            this.subscription = response;
        });
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
        }
    }

    handleViolation(message) {
        const p = message.data.payload;
        const alert = {
            key: `${p.Expense_Id__c}-${message.data.event.replayId}`,
            url: `/${p.Expense_Id__c}`,
            expenseName: p.Expense_Name__c,
            text: `${p.Employee_Name__c} · ${p.Category__c} · ${p.Trip_Name__c}`,
            amount: p.Amount_INR__c,
            limit: p.Limit_INR__c
        };
        this.alerts = [alert, ...this.alerts].slice(0, MAX_ALERTS);
        this.dispatchEvent(new ShowToastEvent({
            title: 'Over-policy expense',
            message: `${p.Employee_Name__c} claimed ${p.Amount_INR__c} INR for ${p.Category__c} (limit ${p.Limit_INR__c} INR)`,
            variant: 'warning'
        }));
    }

    handleNewTrip() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'Trip__c', actionName: 'new' }
        });
    }

    handleRefresh() {
        return Promise.all([refreshApex(this.wiredTripsResult), refreshApex(this.wiredSummaryResult)]);
    }

    reduceError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return 'Something went wrong while loading your travel data.';
    }
}
