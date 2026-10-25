"""Generate WanderRoster report types, report/dashboard folders, reports and CFO dashboard."""
import os, sys
ROOT = sys.argv[1] + '/force-app/main/default'
NS = 'xmlns="http://soap.sforce.com/2006/04/metadata"'
RUNNING_USER = 'kandiharish2005.a66aced8fcba@agentforce.com'

def w(path, body):
    p = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w', encoding='utf-8', newline='\n') as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n' + body.strip() + '\n')
    print('wrote', path)

# ---------- Report types ----------
TRIP_FIELDS = ['Name', 'Owner', 'Purpose__c', 'Trip_Type__c', 'Destination_City__c', 'Start_Date__c',
               'End_Date__c', 'Trip_Duration__c', 'Status__c', 'Claim_Status__c', 'Estimated_Cost__c',
               'Total_Spent_INR__c', 'Budget_Variance__c', 'Over_Policy_Count__c', 'Payment_Reference__c',
               'Reimbursed_On__c', 'CreatedDate']
EXP_FIELDS = ['Name', 'Category__c', 'Expense_Date__c', 'Amount__c', 'Currency_Code__c', 'Amount_INR__c',
              'Policy_Limit_INR__c', 'Over_Policy__c', 'Justification__c', 'Has_Receipt__c',
              'Possible_Duplicate__c', 'Nights__c', 'Description__c']

def section(label, table, fields):
    cols = ''.join(f'<columns><checkedByDefault>true</checkedByDefault><field>{f}</field>'
                   f'<table>{table}</table></columns>' for f in fields)
    return f'<sections>{cols}<masterLabel>{label}</masterLabel></sections>'

w('reportTypes/WR_Trips.reportType-meta.xml', f'''
<ReportType {NS}>
    <baseObject>Trip__c</baseObject>
    <category>other</category>
    <deployed>true</deployed>
    <description>WanderRoster trips with budget, approval and claim status.</description>
    <label>WR Trips</label>
    {section('Trips', 'Trip__c', TRIP_FIELDS)}
</ReportType>''')

w('reportTypes/WR_Trips_with_Expenses.reportType-meta.xml', f'''
<ReportType {NS}>
    <baseObject>Trip__c</baseObject>
    <category>other</category>
    <deployed>true</deployed>
    <description>WanderRoster trips and their expense lines (INR, policy and duplicate flags).</description>
    <join>
        <outerJoin>false</outerJoin>
        <relationship>Expenses__r</relationship>
    </join>
    <label>WR Trips with Expenses</label>
    {section('Trips', 'Trip__c', TRIP_FIELDS)}
    {section('Expenses', 'Trip__c.Expenses__r', EXP_FIELDS)}
</ReportType>''')

# ---------- Folders ----------
w('reports/WanderRoster_Reports.reportFolder-meta.xml', f'''
<ReportFolder {NS}>
    <folderShares>
        <accessLevel>View</accessLevel>
        <sharedTo>CFO</sharedTo>
        <sharedToType>RoleAndSubordinates</sharedToType>
    </folderShares>
    <folderShares>
        <accessLevel>View</accessLevel>
        <sharedTo>Sales_Manager</sharedTo>
        <sharedToType>Role</sharedToType>
    </folderShares>
    <name>WanderRoster Reports</name>
</ReportFolder>''')

w('dashboards/WanderRoster_Dashboards.dashboardFolder-meta.xml', f'''
<DashboardFolder {NS}>
    <folderShares>
        <accessLevel>View</accessLevel>
        <sharedTo>CFO</sharedTo>
        <sharedToType>RoleAndSubordinates</sharedToType>
    </folderShares>
    <name>WanderRoster Dashboards</name>
</DashboardFolder>''')

# ---------- Reports ----------
T = 'Trip__c$'          # trip column prefix
E = 'Trip__c.Expenses__r$'  # expense column prefix

def summ_xml(col, agg='Sum'):
    a = '' if col == 'RowCount' else f'<aggregate>{agg}</aggregate>'
    return f'<chartSummaries>{a}<axisBinding>y</axisBinding><column>{col}</column></chartSummaries>'

def chart(ctype, group, summ_col, summ_agg='Sum', extra='', extra_sum=''):
    return f'''<chart>
        <backgroundColor1>#FFFFFF</backgroundColor1>
        <backgroundColor2>#FFFFFF</backgroundColor2>
        <backgroundFadeDir>Diagonal</backgroundFadeDir>
        {summ_xml(summ_col, summ_agg)}{extra_sum}
        <chartType>{ctype}</chartType>
        <enableHoverLabels>true</enableHoverLabels>
        <expandOthers>true</expandOthers>
        <groupingColumn>{group}</groupingColumn>
        {'<legendPosition>Right</legendPosition>' if (ctype == 'Donut' or extra_sum) else ''}
        <location>CHART_TOP</location>
        <showAxisLabels>true</showAxisLabels>
        <showPercentage>false</showPercentage>
        <showTotal>{'true' if ctype == 'Donut' else 'false'}</showTotal>
        <showValues>true</showValues>
        <size>Medium</size>
        <summaryAxisRange>Auto</summaryAxisRange>
        <textColor>#000000</textColor>
        <textSize>12</textSize>
        <titleColor>#000000</titleColor>
        <titleSize>18</titleSize>{extra}
    </chart>'''

def report(api, name, desc, rtype, cols, sums, groups=(), filters=(), ch='', date_col=None, gran=None):
    colxml = ''.join(
        f'<columns>{"".join(f"<aggregateTypes>Sum</aggregateTypes>" for _ in [0] if c in sums)}<field>{c}</field></columns>'
        for c in cols)
    grp = ''.join(
        f'<groupingsDown><dateGranularity>{gran if (gran and g == date_col) else "Day"}</dateGranularity>'
        f'<field>{g}</field><sortOrder>Asc</sortOrder></groupingsDown>' for g in groups)
    flt = ''
    if filters:
        items = ''.join(f'<criteriaItems><column>{c}</column>'
                        f'<isUnlocked>true</isUnlocked><operator>{op}</operator><value>{v}</value></criteriaItems>'
                        for c, op, v in filters)
        flt = f'<filter>{items}</filter>'
    fmt = 'Summary' if groups else 'Tabular'
    base = T if rtype == 'WR_Trips__c' else T
    w(f'reports/WanderRoster_Reports/{api}.report-meta.xml', f'''
<Report {NS}>
    {ch}
    {colxml}
    <description>{desc}</description>
    {flt}
    <format>{fmt}</format>
    {grp}
    <name>{name}</name>
    <params><name>co</name><value>1</value></params>
    <reportType>{rtype}</reportType>
    <scope>organization</scope>
    <showDetails>true</showDetails>
    <showGrandTotal>true</showGrandTotal>
    <showSubTotals>true</showSubTotals>
    <timeFrameFilter>
        <dateColumn>{base}Start_Date__c</dateColumn>
        <interval>INTERVAL_CUSTOM</interval>
    </timeFrameFilter>
</Report>''')

RTE = 'WR_Trips_with_Expenses__c'
RTT = 'WR_Trips__c'

report('Spend_by_Category', 'Spend by Category',
       'Where the travel money goes: total INR spend per expense category.', RTE,
       [E + 'Name', T + 'Name', T + 'Owner', E + 'Expense_Date__c', E + 'Amount_INR__c'],
       {E + 'Amount_INR__c'}, groups=[E + 'Category__c'],
       ch=chart('Donut', E + 'Category__c', E + 'Amount_INR__c'))

report('Monthly_Spend_Trend', 'Monthly Spend Trend',
       'Travel spend (INR) by expense month.', RTE,
       [E + 'Name', T + 'Name', E + 'Category__c', E + 'Amount_INR__c'],
       {E + 'Amount_INR__c'}, groups=[E + 'Expense_Date__c'], date_col=E + 'Expense_Date__c', gran='Month',
       ch=chart('Line', E + 'Expense_Date__c', E + 'Amount_INR__c'))

report('Over_Policy_Expenses', 'Over-Policy Expenses',
       'Expenses above the grade limit, by employee, with justification.', RTE,
       [E + 'Name', T + 'Name', E + 'Category__c', E + 'Amount_INR__c', E + 'Policy_Limit_INR__c',
        E + 'Justification__c'],
       {E + 'Amount_INR__c'}, groups=[T + 'Owner'],
       filters=[(E + 'Over_Policy__c', 'equals', '1')],
       ch=chart('HorizontalBar', T + 'Owner', 'RowCount', 'Sum'))

report('Possible_Duplicate_Expenses', 'Possible Duplicate Expenses',
       'Expenses flagged by the duplicate check (same owner, date, category, amount, currency).', RTE,
       [E + 'Name', T + 'Name', E + 'Expense_Date__c', E + 'Category__c', E + 'Amount__c',
        E + 'Currency_Code__c', E + 'Amount_INR__c'],
       {E + 'Amount_INR__c'}, groups=[T + 'Owner'], filters=[(E + 'Possible_Duplicate__c', 'equals', '1')])

report('Claims_Pipeline', 'Claims Pipeline',
       'Submitted claims by claim status with INR value - what Finance still has to process.', RTT,
       [T + 'Name', T + 'Owner', T + 'Destination_City__c', T + 'Total_Spent_INR__c'],
       {T + 'Total_Spent_INR__c'}, groups=[T + 'Claim_Status__c'],
       filters=[(T + 'Claim_Status__c', 'notEqual', 'Not Submitted')],
       ch=chart('Funnel', T + 'Claim_Status__c', T + 'Total_Spent_INR__c'))

report('Budget_vs_Actual_by_Employee', 'Budget vs Actual by Employee',
       'Estimated cost vs actual spend per employee.', RTT,
       [T + 'Name', T + 'Destination_City__c', T + 'Status__c', T + 'Estimated_Cost__c',
        T + 'Total_Spent_INR__c', T + 'Budget_Variance__c'],
       {T + 'Estimated_Cost__c', T + 'Total_Spent_INR__c', T + 'Budget_Variance__c'}, groups=[T + 'Owner'],
       ch=chart('VerticalColumn', T + 'Owner', T + 'Estimated_Cost__c', 'Sum',
                extra_sum=summ_xml(T + 'Total_Spent_INR__c')))

report('Trips_by_Destination', 'Trips by Destination',
       'Number of trips and spend per destination city, split Domestic / International.', RTT,
       [T + 'Name', T + 'Owner', T + 'Trip_Type__c', T + 'Status__c', T + 'Total_Spent_INR__c'],
       {T + 'Total_Spent_INR__c'}, groups=[T + 'Destination_City__c'],
       ch=chart('VerticalColumn', T + 'Destination_City__c', 'RowCount'))

# ---------- Dashboard ----------
R = 'WanderRoster_Reports/'

def metric(header, rep, col, agg, label, bp1, bp2, low, high):
    return f'''<dashboardComponent>
                <autoselectColumnsFromReport>false</autoselectColumnsFromReport>
                <chartSummary>{'' if col == 'RowCount' else f'<aggregate>{agg}</aggregate>'}<axisBinding>y</axisBinding><column>{col}</column></chartSummary>
                <componentType>Metric</componentType>
                <displayUnits>Auto</displayUnits>
                <header>{header}</header>
                <indicatorBreakpoint1>{bp1}</indicatorBreakpoint1>
                <indicatorBreakpoint2>{bp2}</indicatorBreakpoint2>
                <indicatorHighColor>{high}</indicatorHighColor>
                <indicatorLowColor>{low}</indicatorLowColor>
                <indicatorMiddleColor>#C2C254</indicatorMiddleColor>
                <metricLabel>{label}</metricLabel>
                <report>{R}{rep}</report>
                <showRange>false</showRange>
            </dashboardComponent>'''

def chartc(ctype, header, rep, footer=''):
    return f'''<dashboardComponent>
                <autoselectColumnsFromReport>true</autoselectColumnsFromReport>
                <chartAxisRange>Auto</chartAxisRange>
                <componentType>{ctype}</componentType>
                <displayUnits>Auto</displayUnits>
                <footer>{footer}</footer>
                <header>{header}</header>
                <legendPosition>Right</legendPosition>
                <report>{R}{rep}</report>
                <showPercentage>false</showPercentage>
                <showTotal>{'true' if ctype == 'Donut' else 'false'}</showTotal>
                <showValues>true</showValues>
                <sortBy>RowLabelAscending</sortBy>
                <useReportChart>true</useReportChart>
            </dashboardComponent>'''

def table(header, rep):
    return f'''<dashboardComponent>
                <autoselectColumnsFromReport>true</autoselectColumnsFromReport>
                <componentType>Table</componentType>
                <displayUnits>Auto</displayUnits>
                <header>{header}</header>
                <indicatorHighColor>#54C254</indicatorHighColor>
                <indicatorLowColor>#C25454</indicatorLowColor>
                <indicatorMiddleColor>#C2C254</indicatorMiddleColor>
                <maxValuesDisplayed>10</maxValuesDisplayed>
                <report>{R}{rep}</report>
                <sortBy>RowValueDescending</sortBy>
            </dashboardComponent>'''

# (col, row, colSpan, rowSpan, component) on a 12-column grid
LAYOUT = [
    (0, 0, 4, 4, metric('Total Travel Spend', 'Spend_by_Category', E + 'Amount_INR__c', 'Sum', 'INR',
                        100000, 300000, '#54C254', '#C25454')),
    (4, 0, 4, 4, metric('Over-Policy Expenses', 'Over_Policy_Expenses', 'RowCount', 'Sum', 'expenses',
                        2, 5, '#54C254', '#C25454')),
    (8, 0, 4, 4, metric('Claims Waiting / In Pipeline', 'Claims_Pipeline', 'RowCount', 'Sum', 'claims',
                        3, 6, '#54C254', '#C25454')),
    (0, 4, 4, 8, chartc('Donut', 'Spend by Category', 'Spend_by_Category')),
    (4, 4, 4, 8, chartc('Funnel', 'Claims Pipeline (INR)', 'Claims_Pipeline')),
    (8, 4, 4, 8, chartc('Line', 'Monthly Spend Trend', 'Monthly_Spend_Trend')),
    (0, 12, 6, 8, chartc('Column', 'Budget vs Actual by Employee', 'Budget_vs_Actual_by_Employee')),
    (6, 12, 6, 8, chartc('Bar', 'Over-Policy Expenses by Employee', 'Over_Policy_Expenses')),
    (0, 20, 6, 8, chartc('Column', 'Trips by Destination', 'Trips_by_Destination')),
    (6, 20, 6, 8, table('Possible Duplicate Expenses', 'Possible_Duplicate_Expenses')),
]
grid = ''.join(f'''
        <dashboardGridComponents>
            <colSpan>{cs}</colSpan>
            <columnIndex>{c}</columnIndex>
            {comp}
            <rowIndex>{r}</rowIndex>
            <rowSpan>{rs}</rowSpan>
        </dashboardGridComponents>''' for c, r, cs, rs, comp in LAYOUT)

w('dashboards/WanderRoster_Dashboards/CFO_Travel_Spend.dashboard-meta.xml', f'''
<Dashboard {NS}>
    <backgroundEndColor>#FFFFFF</backgroundEndColor>
    <backgroundFadeDirection>Diagonal</backgroundFadeDirection>
    <backgroundStartColor>#FFFFFF</backgroundStartColor>
    <dashboardGridLayout>{grid}
        <numberOfColumns>12</numberOfColumns>
        <rowHeight>36</rowHeight>
    </dashboardGridLayout>
    <dashboardType>SpecifiedUser</dashboardType>
    <description>CFO view of company travel spend, policy compliance and the claims pipeline.</description>
    <isGridLayout>true</isGridLayout>
    <runningUser>{RUNNING_USER}</runningUser>
    <textColor>#000000</textColor>
    <title>CFO Travel Spend</title>
    <titleColor>#000000</titleColor>
    <titleSize>12</titleSize>
</Dashboard>''')
