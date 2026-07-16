#!/usr/bin/env python3
"""
Humanitix Connector — metadata generator (developer helper).

Single source of truth for the connector's custom objects, custom fields
(on both custom and standard objects), the Custom Metadata Types + custom
setting, and the two permission sets. Generating objects/fields *and* the
permission-set FLS from one registry guarantees field-level security can
never drift from the fields that exist — a common cause of broken packages.

Run from the repo root:  python3 scripts/dev/generate-metadata.py

It writes into force-app/main/default/{objects,permissionsets}. It is
idempotent: re-running overwrites the generated files. Hand-authored
metadata (credentials, CMT *records*, apps, tabs, LWC, Apex) is never
touched. When you add a field, add it here and re-run.
"""
import os

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
BASE = os.path.normpath(os.path.join(ROOT, "force-app", "main", "default"))
OBJ_DIR = os.path.join(BASE, "objects")
PS_DIR = os.path.join(BASE, "permissionsets")

# Apex classes + tabs to grant on the admin permission set. Populated as later
# phases add them; kept here so the permission set stays consistent. Deploys of
# just the objects (Phase 1) work because these lists start empty.
ADMIN_APEX_CLASSES = [
    "HumanitixApiException", "HumanitixMappingException",
    "HumanitixJsonNavigator", "HumanitixTypeCoercer", "HumanitixMappingConfig",
    "HumanitixRecordBuilder", "HumanitixRelationshipResolver", "HumanitixPersister",
    "HumanitixMappingEngine",
    "HumanitixApiResponse", "HumanitixRetryPolicy", "HumanitixHttpClient",
    "HumanitixSyncConfig", "HumanitixSyncState", "HumanitixSyncStateService",
    "HumanitixSyncLogService", "HumanitixSyncQueueable", "HumanitixSyncLauncher",
    "HumanitixSyncScheduler", "HumanitixSyncInvocable", "HumanitixSyncAdminController",
]
ADMIN_TABS = ["Humanitix_Sync_Log__c", "Humanitix_Setup"]
USER_TABS = ["Humanitix_Sync_Log__c"]

# ---------------------------------------------------------------------------
# Field DSL: build one <CustomField> block from a spec dict.
# ---------------------------------------------------------------------------

def esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def field_xml(f, cmt=False):
    api = f["api"]
    label = f.get("label") or api.replace("__c", "").replace("_", " ")
    t = f["type"]
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">',
             f"    <fullName>{api}</fullName>"]
    # externalId/unique/required only apply to non-CMT scalar fields
    if cmt:
        lines.append("    <fieldManageability>SubscriberControlled</fieldManageability>")
    lines.append(f"    <label>{esc(label)}</label>")
    if f.get("description"):
        lines.append(f"    <description>{esc(f['description'])}</description>")
    if f.get("helpText"):
        lines.append(f"    <inlineHelpText>{esc(f['helpText'])}</inlineHelpText>")

    if t == "text":
        lines.append("    <type>Text</type>")
        lines.append(f"    <length>{f.get('length', 255)}</length>")
        if f.get("externalId"):
            lines.append("    <externalId>true</externalId>")
        if f.get("unique"):
            lines.append("    <unique>true</unique>")
        lines.append(f"    <required>{'true' if f.get('required') else 'false'}</required>")
    elif t == "longtext":
        lines.append("    <type>LongTextArea</type>")
        lines.append(f"    <length>{f.get('length', 32768)}</length>")
        lines.append(f"    <visibleLines>{f.get('visibleLines', 5)}</visibleLines>")
    elif t == "number":
        lines.append("    <type>Number</type>")
        lines.append(f"    <precision>{f.get('precision', 18)}</precision>")
        lines.append(f"    <scale>{f.get('scale', 0)}</scale>")
        lines.append(f"    <required>{'true' if f.get('required') else 'false'}</required>")
    elif t == "currency":
        lines.append("    <type>Currency</type>")
        lines.append(f"    <precision>{f.get('precision', 16)}</precision>")
        lines.append(f"    <scale>{f.get('scale', 2)}</scale>")
        lines.append(f"    <required>{'true' if f.get('required') else 'false'}</required>")
    elif t == "checkbox":
        lines.append("    <type>Checkbox</type>")
        lines.append(f"    <defaultValue>{'true' if f.get('default') else 'false'}</defaultValue>")
    elif t == "datetime":
        lines.append("    <type>DateTime</type>")
        lines.append(f"    <required>{'true' if f.get('required') else 'false'}</required>")
    elif t == "date":
        lines.append("    <type>Date</type>")
    elif t == "url":
        lines.append("    <type>Url</type>")
    elif t == "email":
        lines.append("    <type>Email</type>")
        if f.get("externalId"):
            lines.append("    <externalId>true</externalId>")
        if f.get("unique"):
            lines.append("    <unique>true</unique>")
    elif t == "phone":
        lines.append("    <type>Phone</type>")
    elif t == "picklist":
        lines.append("    <type>Picklist</type>")
        lines.append("    <valueSet>")
        lines.append("        <valueSetDefinition>")
        lines.append("            <sorted>false</sorted>")
        for i, v in enumerate(f["values"]):
            is_def = "true" if f.get("default") == v else "false"
            lines.append("            <value>")
            lines.append(f"                <fullName>{esc(v)}</fullName>")
            lines.append(f"                <default>{is_def}</default>")
            lines.append(f"                <label>{esc(v)}</label>")
            lines.append("            </value>")
        lines.append("        </valueSetDefinition>")
        lines.append("    </valueSet>")
    elif t == "lookup":
        lines.append("    <type>Lookup</type>")
        lines.append(f"    <referenceTo>{f['refTo']}</referenceTo>")
        lines.append(f"    <relationshipName>{f['relName']}</relationshipName>")
        lines.append(f"    <relationshipLabel>{esc(f.get('relLabel', f['relName'].replace('_', ' ')))}</relationshipLabel>")
        lines.append("    <required>false</required>")
        lines.append("    <deleteConstraint>SetNull</deleteConstraint>")
    elif t == "masterdetail":
        lines.append("    <type>MasterDetail</type>")
        lines.append(f"    <referenceTo>{f['refTo']}</referenceTo>")
        lines.append(f"    <relationshipName>{f['relName']}</relationshipName>")
        lines.append(f"    <relationshipLabel>{esc(f.get('relLabel', f['relName'].replace('_', ' ')))}</relationshipLabel>")
        lines.append("    <reparentableMasterDetail>true</reparentableMasterDetail>")
        lines.append("    <writeRequiresMasterRead>false</writeRequiresMasterRead>")
    else:
        raise ValueError("unknown type " + t)

    if t in ("text", "longtext", "url", "email", "phone", "picklist") and f.get("trackTrending") is None:
        pass
    lines.append("</CustomField>")
    return "\n".join(lines) + "\n"


def write_file(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(content)


def object_xml(o):
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">']
    if o.get("customSetting"):
        lines.append("    <customSettingsType>Hierarchy</customSettingsType>")
        lines.append(f"    <label>{esc(o['label'])}</label>")
        lines.append("    <visibility>Public</visibility>")
        lines.append("</CustomObject>")
        return "\n".join(lines) + "\n"
    if o.get("cmt"):
        lines.append(f"    <label>{esc(o['label'])}</label>")
        lines.append(f"    <pluralLabel>{esc(o['plural'])}</pluralLabel>")
        lines.append("    <visibility>Public</visibility>")
        lines.append("</CustomObject>")
        return "\n".join(lines) + "\n"
    lines.append("    <deploymentStatus>Deployed</deploymentStatus>")
    lines.append("    <enableActivities>false</enableActivities>")
    lines.append("    <enableHistory>false</enableHistory>")
    lines.append("    <enableReports>true</enableReports>")
    lines.append("    <enableSearch>true</enableSearch>")
    lines.append(f"    <label>{esc(o['label'])}</label>")
    lines.append(f"    <pluralLabel>{esc(o['plural'])}</pluralLabel>")
    nf = o["nameField"]
    lines.append("    <nameField>")
    if nf["type"] == "AutoNumber":
        lines.append(f"        <displayFormat>{nf['format']}</displayFormat>")
        lines.append(f"        <label>{esc(nf.get('label', 'Name'))}</label>")
        lines.append("        <type>AutoNumber</type>")
    else:
        lines.append(f"        <label>{esc(nf.get('label', 'Name'))}</label>")
        lines.append("        <type>Text</type>")
    lines.append("    </nameField>")
    lines.append("    <sharingModel>ReadWrite</sharingModel>")
    lines.append("</CustomObject>")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

def T(api, length=255, label=None, **kw):
    return dict(api=api, type="text", length=length, label=label, **kw)

def extid(api, label=None):
    return dict(api=api, type="text", length=255, externalId=True, unique=True,
                label=label, helpText="Humanitix identifier. Used as the idempotent upsert key.")

def LT(api, label=None, length=32768):
    return dict(api=api, type="longtext", length=length, label=label)

def NUM(api, precision=18, scale=0, label=None):
    return dict(api=api, type="number", precision=precision, scale=scale, label=label)

def CUR(api, label=None):
    return dict(api=api, type="currency", precision=16, scale=2, label=label)

def CB(api, label=None):
    return dict(api=api, type="checkbox", default=False, label=label)

def DT(api, label=None):
    return dict(api=api, type="datetime", label=label)

def look(api, refTo, relName, label=None, relLabel=None):
    return dict(api=api, type="lookup", refTo=refTo, relName=relName, label=label, relLabel=relLabel)

def md(api, refTo, relName, label=None, relLabel=None):
    return dict(api=api, type="masterdetail", refTo=refTo, relName=relName, label=label, relLabel=relLabel)

def PICK(api, values, default=None, label=None):
    return dict(api=api, type="picklist", values=values, default=default, label=label)


OBJECTS = {}

OBJECTS["Humanitix_Event__c"] = dict(
    label="Humanitix Event", plural="Humanitix Events",
    nameField=dict(type="Text", label="Event Name"),
    fields=[
        extid("Humanitix_Id__c", "Humanitix Event Id"),
        T("User_Id__c", label="User Id"), T("Organiser_Id__c", label="Organiser Id"),
        T("Slug__c"), dict(api="Event_URL__c", type="url", label="Event URL"),
        LT("Description__c"), T("Currency_Code__c", length=10),
        T("Category__c"), T("Classification_Type__c"), T("Classification_Category__c"),
        T("Classification_Subcategory__c"),
        CB("Is_Public__c", "Is Public"), CB("Published__c"), CB("Suspend_Sales__c"),
        CB("Marked_As_Sold_Out__c"),
        DT("Start_Date__c"), DT("End_Date__c"), T("Timezone__c", length=80),
        NUM("Total_Capacity__c"), T("Location_Country__c", length=2),
        CB("Is_Archived__c"), CB("Is_Permanently_Archived__c"),
        LT("Tag_Ids__c", length=4096), T("Tag_Names__c"),
        DT("Created_At__c"), DT("Updated_At__c"),
        look("Campaign__c", "Campaign", "Humanitix_Events", relLabel="Humanitix Events"),
    ])

OBJECTS["Humanitix_Ticket_Type__c"] = dict(
    label="Humanitix Ticket Type", plural="Humanitix Ticket Types",
    nameField=dict(type="Text", label="Ticket Type Name"),
    fields=[
        extid("Humanitix_Id__c", "Humanitix Ticket Type Id"),
        look("Humanitix_Event__c", "Humanitix_Event__c", "Ticket_Types", relLabel="Ticket Types"),
        T("Event_Humanitix_Id__c", label="Event Humanitix Id"),
        CUR("Price__c"), NUM("Quantity__c"), LT("Description__c"),
        CB("Disabled__c"), CB("Deleted__c"), CB("Is_Donation__c"),
    ])

OBJECTS["Humanitix_Event_Date__c"] = dict(
    label="Humanitix Event Date", plural="Humanitix Event Dates",
    nameField=dict(type="AutoNumber", label="Event Date Number", format="ED-{000000}"),
    fields=[
        extid("Humanitix_Id__c", "Humanitix Event Date Id"),
        look("Humanitix_Event__c", "Humanitix_Event__c", "Event_Dates", relLabel="Event Dates"),
        T("Event_Humanitix_Id__c", label="Event Humanitix Id"),
        DT("Start_Date__c"), DT("End_Date__c"), T("Schedule_Id__c"),
        CB("Disabled__c"), CB("Deleted__c"),
    ])

OBJECTS["Humanitix_Order__c"] = dict(
    label="Humanitix Order", plural="Humanitix Orders",
    nameField=dict(type="AutoNumber", label="Order Number", format="HTX-O-{000000}"),
    fields=[
        extid("Humanitix_Id__c", "Humanitix Order Id"),
        look("Humanitix_Event__c", "Humanitix_Event__c", "Orders", relLabel="Orders"),
        T("Event_Humanitix_Id__c", label="Event Humanitix Id"),
        T("Event_Date_Id__c"), T("User_Id__c"), T("Currency_Code__c", length=10),
        T("Status__c", length=40), T("Financial_Status__c", length=40),
        T("First_Name__c"), T("Last_Name__c"),
        dict(api="Email__c", type="email"), dict(api="Mobile__c", type="phone"),
        T("Organisation__c"), T("Business_Name__c"),
        T("Payment_Type__c", length=40), T("Payment_Gateway__c", length=40),
        T("Sales_Channel__c", length=40),
        CB("Manual_Order__c"), CUR("Client_Donation__c"), LT("Notes__c"),
        CUR("Total__c"), CUR("Subtotal__c"), CUR("Gross_Sales__c"), CUR("Net_Sales__c"),
        CUR("Total_Taxes__c"), CUR("Discounts__c"), CUR("Refunds__c"),
        CUR("Booking_Fee__c"), CUR("Humanitix_Fee__c"),
        DT("Completed_At__c"), DT("Created_At__c"), DT("Updated_At__c"),
        look("Contact__c", "Contact", "Humanitix_Orders", relLabel="Humanitix Orders"),
    ])

OBJECTS["Humanitix_Ticket__c"] = dict(
    label="Humanitix Ticket", plural="Humanitix Tickets",
    nameField=dict(type="AutoNumber", label="Ticket Number", format="HTX-T-{000000}"),
    fields=[
        extid("Humanitix_Id__c", "Humanitix Ticket Id"),
        look("Humanitix_Event__c", "Humanitix_Event__c", "Tickets", relLabel="Tickets"),
        T("Event_Humanitix_Id__c", label="Event Humanitix Id"),
        look("Humanitix_Order__c", "Humanitix_Order__c", "Tickets", relLabel="Tickets"),
        T("Order_Humanitix_Id__c", label="Order Humanitix Id"),
        T("Order_Name__c"), NUM("Ticket_Number__c"),
        T("First_Name__c"), T("Last_Name__c"), T("Organisation__c"),
        T("Event_Date_Id__c"), T("Ticket_Type_Name__c"), T("Ticket_Type_Id__c"),
        T("Currency_Code__c", length=10),
        CUR("Price__c"), CUR("Net_Price__c"), CUR("Total__c"), CUR("Taxes__c"), CUR("Fee__c"),
        T("Status__c", length=40),
        CB("Checked_In__c"), DT("Check_In_Date__c"),
        T("Seating_Name__c"), T("Seating_Section__c"), T("Seating_Table__c"), T("Seating_Seat__c"),
        T("Sales_Channel__c", length=40), CB("Is_Donation__c"), DT("Cancelled_At__c"),
        DT("Created_At__c"), DT("Updated_At__c"),
        look("Contact__c", "Contact", "Humanitix_Tickets", relLabel="Humanitix Tickets"),
    ])

OBJECTS["Humanitix_Order_Attribute__c"] = dict(
    label="Humanitix Order Attribute", plural="Humanitix Order Attributes",
    nameField=dict(type="AutoNumber", label="Order Attribute Number", format="HTX-OA-{000000}"),
    fields=[
        extid("Humanitix_Id__c", "Humanitix Order Attribute Id"),
        look("Humanitix_Order__c", "Humanitix_Order__c", "Order_Attributes", relLabel="Order Attributes"),
        T("Order_Humanitix_Id__c", label="Order Humanitix Id"),
        T("Question_Id__c"), T("Question_Name__c"), LT("Field_Value__c", length=4096), LT("Details_JSON__c", length=4096),
    ])

OBJECTS["Humanitix_Ticket_Attribute__c"] = dict(
    label="Humanitix Ticket Attribute", plural="Humanitix Ticket Attributes",
    nameField=dict(type="AutoNumber", label="Ticket Attribute Number", format="HTX-TA-{000000}"),
    fields=[
        extid("Humanitix_Id__c", "Humanitix Ticket Attribute Id"),
        look("Humanitix_Ticket__c", "Humanitix_Ticket__c", "Ticket_Attributes", relLabel="Ticket Attributes"),
        T("Ticket_Humanitix_Id__c", label="Ticket Humanitix Id"),
        T("Question_Id__c"), T("Question_Name__c"), LT("Field_Value__c", length=4096), LT("Details_JSON__c", length=4096),
    ])

OBJECTS["Humanitix_Tag__c"] = dict(
    label="Humanitix Tag", plural="Humanitix Tags",
    nameField=dict(type="Text", label="Tag Name"),
    fields=[
        extid("Humanitix_Id__c", "Humanitix Tag Id"),
        T("User_Id__c"), T("Location_Country__c", length=2),
        DT("Created_At__c"), DT("Updated_At__c"),
    ])

OBJECTS["Humanitix_Sync_Log__c"] = dict(
    label="Humanitix Sync Log", plural="Humanitix Sync Logs",
    nameField=dict(type="AutoNumber", label="Sync Run", format="RUN-{000000}"),
    fields=[
        dict(api="Run_Id__c", type="text", length=255, externalId=True, unique=True, label="Run Id"),
        PICK("Trigger_Source__c", ["Scheduled", "Manual", "Invocable", "Chained"], label="Trigger Source"),
        PICK("Status__c", ["Running", "Success", "Partial", "Failed"], default="Running"),
        DT("Started_At__c"), DT("Finished_At__c"),
        T("Resources_Requested__c"),
        NUM("Total_Records_Processed__c"), NUM("Total_Records_Failed__c"),
        NUM("Total_Pages__c"), NUM("Total_Callouts__c"),
        NUM("Total_Retries__c"), NUM("Total_Errors__c"),
        LT("Error_Summary__c"),
    ])

OBJECTS["Humanitix_Sync_Log_Entry__c"] = dict(
    label="Humanitix Sync Log Entry", plural="Humanitix Sync Log Entries",
    nameField=dict(type="AutoNumber", label="Entry", format="ENT-{000000}"),
    fields=[
        md("Humanitix_Sync_Log__c", "Humanitix_Sync_Log__c", "Entries", relLabel="Entries"),
        T("Resource__c", length=40),
        T("Event_External_Id__c"),
        PICK("Status__c", ["Success", "Partial", "Failed", "Skipped"], default="Success"),
        NUM("Records_Processed__c"), NUM("Records_Failed__c"), NUM("Pages__c"),
        NUM("Http_Status__c", precision=5), NUM("Retry_Count__c", precision=5),
        LT("Error_Message__c"), DT("Started_At__c"), DT("Finished_At__c"),
    ])

OBJECTS["Humanitix_Sync_State__c"] = dict(
    label="Humanitix Sync State", plural="Humanitix Sync States",
    nameField=dict(type="Text", label="Cursor Key"),
    fields=[
        dict(api="Cursor_Key__c", type="text", length=255, externalId=True, unique=True, label="Cursor Key",
             helpText="Stable key, e.g. 'events' or 'orders:{eventId}'."),
        T("Resource__c", length=40), T("Event_External_Id__c"),
        DT("Last_Successful_Sync__c"), DT("In_Progress_Watermark__c"),
        T("Last_Run_Id__c"), T("Last_Status__c", length=40),
        NUM("Records_Synced_Total__c"), NUM("Consecutive_Failures__c", precision=5),
        NUM("Last_Page__c", precision=9),
    ])

# ---- Custom setting -------------------------------------------------------
SETTING = dict(
    label="Humanitix Sync Toggle", customSetting=True,
    fields=[
        dict(api="Sync_Enabled__c", type="checkbox", default=True, label="Sync Enabled"),
        T("Schedule_Cron__c", length=80, label="Schedule Cron"),
    ])

# ---- Custom Metadata Types ------------------------------------------------
CMTS = {}
CMTS["Humanitix_Object_Mapping__mdt"] = dict(
    label="Humanitix Object Mapping", plural="Humanitix Object Mappings",
    fields=[
        PICK("Source_Resource__c", ["Event", "Order", "Ticket", "Tag"], label="Source Resource"),
        T("Source_Collection_Path__c", label="Source Collection Path",
          helpText="For nested arrays, e.g. ticketTypes, dates, additionalFields. Blank = the record itself."),
        T("Target_SObject__c", label="Target SObject",
          helpText="API name of the object to write, e.g. Campaign, Contact, Humanitix_Event__c."),
        T("External_Id_Field__c", label="External Id Field",
          helpText="Upsert key field API name. Blank when Match Strategy is MatchByFields/AlwaysCreate."),
        PICK("Match_Strategy__c", ["ExternalId", "MatchByFields", "MatchNoUpdate", "AlwaysCreate"],
             default="ExternalId", label="Match Strategy"),
        T("Match_Field_Set__c", label="Match Field Set",
          helpText="Comma-separated target field API names used when Match Strategy is MatchByFields."),
        NUM("Load_Order__c", precision=4, label="Load Order"),
        dict(api="Is_Active__c", type="checkbox", default=True, label="Is Active"),
        T("Description__c", length=255),
    ])
CMTS["Humanitix_Field_Mapping__mdt"] = dict(
    label="Humanitix Field Mapping", plural="Humanitix Field Mappings",
    fields=[
        T("Object_Mapping__c", label="Object Mapping",
          helpText="DeveloperName of the parent Humanitix Object Mapping."),
        T("Source_Path__c", label="Source Path", helpText="Dotted/bracketed JSON path, e.g. totals.grossSales."),
        T("Target_Field__c", label="Target Field", helpText="Target field API name."),
        PICK("Data_Type__c",
             ["Text", "LongText", "DateTime", "Date", "Decimal", "Currency", "Integer",
              "Boolean", "Email", "Phone", "Url", "Reference"], default="Text", label="Data Type"),
        PICK("Transform__c",
             ["None", "Trim", "Upper", "Lower", "IsoToDateTime", "IsoToDateInTz",
              "DecimalMoney", "BoolMap", "StaticValue", "Concat", "JoinArray", "ToJson"],
             default="None", label="Transform"),
        T("Transform_Arg__c", label="Transform Arg",
          helpText="Optional argument. For Reference data type: '<TargetObject>.<ExternalIdField>'. "
                   "For IsoToDateInTz: the timezone path. For Concat: the prefix path/literal. "
                   "For StaticValue: the literal value."),
        dict(api="Is_External_Id__c", type="checkbox", default=False, label="Is External Id"),
        dict(api="Overwrite_Blank__c", type="checkbox", default=True, label="Overwrite With Blank"),
        dict(api="Is_Active__c", type="checkbox", default=True, label="Is Active"),
    ])
CMTS["Humanitix_Sync_Setting__mdt"] = dict(
    label="Humanitix Sync Setting", plural="Humanitix Sync Settings",
    fields=[
        NUM("Page_Size__c", precision=4, label="Page Size"),
        NUM("Max_Pages_Per_Transaction__c", precision=4, label="Max Pages Per Transaction"),
        NUM("Max_Events_Per_Transaction__c", precision=4, label="Max Events Per Transaction"),
        T("Enabled_Resources__c", label="Enabled Resources",
          helpText="Comma-separated: Events,Orders,Tickets,Tags."),
        dict(api="In_Future_Only__c", type="checkbox", default=False, label="In Future Only"),
        T("Ticket_Status_Filter__c", length=40, label="Ticket Status Filter"),
        NUM("Max_Retries__c", precision=4, label="Max Retries"),
        NUM("Retry_Delay_Minutes__c", precision=4, label="Retry Delay Minutes"),
        PICK("Since_Mode__c", ["Modified", "FullPull"], default="Modified", label="Since Mode"),
        T("Named_Credential_Name__c", label="Named Credential Name"),
        NUM("Consecutive_Failure_Threshold__c", precision=4, label="Consecutive Failure Threshold"),
    ])

# ---- Fields to add to standard objects ------------------------------------
STANDARD_FIELDS = {
    "Campaign": [
        extid("Humanitix_Event_Id__c", "Humanitix Event Id"),
        DT("Humanitix_Start_DateTime__c", "Humanitix Start Date/Time"),
        NUM("Humanitix_Total_Capacity__c", label="Humanitix Total Capacity"),
        CUR("Humanitix_Gross_Sales__c", "Humanitix Gross Sales"),
        CUR("Humanitix_Net_Sales__c", "Humanitix Net Sales"),
        T("Humanitix_Currency__c", length=10, label="Humanitix Currency"),
        CB("Humanitix_Is_Public__c", "Humanitix Is Public"),
        dict(api="Humanitix_Event_URL__c", type="url", label="Humanitix Event URL"),
        T("Humanitix_Tags__c", label="Humanitix Tags"),
        T("Humanitix_Timezone__c", length=80, label="Humanitix Timezone"),
        DT("Humanitix_Last_Sync__c", "Humanitix Last Sync"),
    ],
    "Contact": [
        dict(api="Humanitix_Contact_Key__c", type="text", length=255, externalId=True, unique=True,
             label="Humanitix Contact Key",
             helpText="Normalized email (lower-cased) used as the idempotent match key for Humanitix syncs."),
        T("Humanitix_Organisation__c", label="Humanitix Organisation"),
        T("Humanitix_Last_Order_Id__c", label="Humanitix Last Order Id"),
        T("Humanitix_Last_Ticket_Id__c", label="Humanitix Last Ticket Id"),
    ],
    "CampaignMember": [
        # Not externalId/unique: CampaignMember matching is done by (CampaignId, ContactId)
        # to respect the platform's native unique constraint.
        T("Humanitix_Member_Key__c", label="Humanitix Member Key",
          helpText="Logical key {eventId}:{contactKey} for traceability. Matching uses Campaign + Contact."),
        NUM("Humanitix_Ticket_Count__c", precision=9, label="Humanitix Ticket Count"),
        T("Humanitix_Ticket_Types__c", label="Humanitix Ticket Types"),
    ],
    "Lead": [
        dict(api="Humanitix_Contact_Key__c", type="text", length=255, externalId=True, unique=True,
             label="Humanitix Contact Key",
             helpText="Optional: enable the Lead mappings to route attendees/buyers to Leads."),
        T("Humanitix_Last_Order_Id__c", label="Humanitix Last Order Id"),
    ],
    "Account": [
        dict(api="Humanitix_Organisation_Key__c", type="text", length=255, externalId=True, unique=True,
             label="Humanitix Organisation Key",
             helpText="Optional: enable the Account mapping to create Accounts from order organisations."),
    ],
}


# ---------------------------------------------------------------------------
# Emit
# ---------------------------------------------------------------------------

def emit_object(api, o):
    d = os.path.join(OBJ_DIR, api)
    write_file(os.path.join(d, api + ".object-meta.xml"), object_xml(o))
    for f in o.get("fields", []):
        write_file(os.path.join(d, "fields", f["api"] + ".field-meta.xml"), field_xml(f))


def emit_cmt(api, o):
    d = os.path.join(OBJ_DIR, api)
    write_file(os.path.join(d, api + ".object-meta.xml"), object_xml(dict(cmt=True, **o)))
    for f in o.get("fields", []):
        write_file(os.path.join(d, "fields", f["api"] + ".field-meta.xml"), field_xml(f, cmt=True))


def emit_standard_fields(sobj, fields):
    d = os.path.join(OBJ_DIR, sobj)
    for f in fields:
        write_file(os.path.join(d, "fields", f["api"] + ".field-meta.xml"), field_xml(f))


def fls_entries(obj_api, fields, editable):
    """Return list of (field, editable) skipping fields that can't take FLS."""
    out = []
    for f in fields:
        if f["type"] == "masterdetail":
            continue  # MD fields don't take FLS
        if f.get("required"):
            continue
        out.append((obj_api + "." + f["api"], editable))
    return out


def permission_set(api, label, description, objects, standard, tabs,
                   apex_classes, ext_cred_access, cmt_edit, user_read_only=False, app=None):
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">',
             f"    <label>{esc(label)}</label>",
             "    <hasActivationRequired>false</hasActivationRequired>",
             f"    <description>{esc(description)}</description>"]
    if app:
        lines.append("    <applicationVisibilities>")
        lines.append(f"        <application>{app}</application>")
        lines.append("        <visible>true</visible>")
        lines.append("    </applicationVisibilities>")
    # object + field permissions for custom objects
    for obj_api in objects:
        o = OBJECTS[obj_api]
        c = "false" if user_read_only else "true"
        lines.append("    <objectPermissions>")
        lines.append(f"        <object>{obj_api}</object>")
        lines.append(f"        <allowCreate>{c}</allowCreate>")
        lines.append("        <allowRead>true</allowRead>")
        lines.append(f"        <allowEdit>{c}</allowEdit>")
        lines.append(f"        <allowDelete>{c}</allowDelete>")
        lines.append(f"        <viewAllRecords>{'true' if user_read_only else 'true'}</viewAllRecords>")
        lines.append(f"        <modifyAllRecords>{c}</modifyAllRecords>")
        lines.append("    </objectPermissions>")
        for field, _ in fls_entries(obj_api, o["fields"], not user_read_only):
            lines.append("    <fieldPermissions>")
            lines.append(f"        <field>{field}</field>")
            lines.append(f"        <readable>true</readable>")
            lines.append(f"        <editable>{'false' if user_read_only else 'true'}</editable>")
            lines.append("    </fieldPermissions>")
    # field permissions for standard-object custom fields (admin only)
    if not user_read_only:
        for sobj, fields in standard.items():
            for field, _ in fls_entries(sobj, fields, True):
                lines.append("    <fieldPermissions>")
                lines.append(f"        <field>{field}</field>")
                lines.append("        <readable>true</readable>")
                lines.append("        <editable>true</editable>")
                lines.append("    </fieldPermissions>")
    for cls in apex_classes:
        lines.append("    <classAccesses>")
        lines.append(f"        <apexClass>{cls}</apexClass>")
        lines.append("        <enabled>true</enabled>")
        lines.append("    </classAccesses>")
    for tab in tabs:
        lines.append("    <tabSettings>")
        lines.append(f"        <tab>{tab}</tab>")
        lines.append("        <visibility>Visible</visibility>")
        lines.append("    </tabSettings>")
    if ext_cred_access:
        lines.append("    <externalCredentialPrincipalAccesses>")
        lines.append(f"        <externalCredentialPrincipal>{ext_cred_access}</externalCredentialPrincipal>")
        lines.append("        <enabled>true</enabled>")
        lines.append("    </externalCredentialPrincipalAccesses>")
    lines.append("</PermissionSet>")
    return "\n".join(lines) + "\n"


def main():
    for api, o in OBJECTS.items():
        emit_object(api, o)
    emit_object("Humanitix_Sync_Toggle__c", SETTING)
    for api, o in CMTS.items():
        emit_cmt(api, o)
    for sobj, fields in STANDARD_FIELDS.items():
        emit_standard_fields(sobj, fields)

    all_custom_objs = list(OBJECTS.keys())
    user_visible_objs = ["Humanitix_Sync_Log__c", "Humanitix_Sync_Log_Entry__c"]

    write_file(os.path.join(PS_DIR, "Humanitix_Integration_Admin.permissionset-meta.xml"),
               permission_set(
                   "Humanitix_Integration_Admin", "Humanitix Integration Admin",
                   "Full access to configure and run the Humanitix connector. Assigning this activates the API callout principal.",
                   all_custom_objs, STANDARD_FIELDS, ADMIN_TABS, ADMIN_APEX_CLASSES,
                   "HumanitixAPI-Humanitix_Named_Principal", True, user_read_only=False,
                   app="Humanitix_Integration"))
    write_file(os.path.join(PS_DIR, "Humanitix_Integration_User.permissionset-meta.xml"),
               permission_set(
                   "Humanitix_Integration_User", "Humanitix Integration User",
                   "Read-only visibility into Humanitix sync logs.",
                   user_visible_objs, {}, USER_TABS, [], None, False, user_read_only=True,
                   app="Humanitix_Integration"))

    total_fields = sum(len(o.get("fields", [])) for o in OBJECTS.values())
    total_fields += sum(len(f) for f in STANDARD_FIELDS.values())
    total_fields += sum(len(o["fields"]) for o in CMTS.values()) + len(SETTING["fields"])
    print(f"Generated {len(OBJECTS)} custom objects, 1 custom setting, {len(CMTS)} CMTs, "
          f"{sum(len(f) for f in STANDARD_FIELDS.values())} standard-object fields, "
          f"2 permission sets, ~{total_fields} fields total.")


if __name__ == "__main__":
    main()
