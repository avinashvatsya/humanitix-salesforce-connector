#!/usr/bin/env python3
"""
Humanitix Connector — default mapping generator (developer helper).

Emits the packaged Custom Metadata *records* that define the connector's
out-of-the-box behaviour: Humanitix Object Mapping + Humanitix Field Mapping
records, plus the default Humanitix Sync Setting. These records are shipped
as metadata; because the CMT fields are SubscriberControlled, admin edits to
them survive package upgrades.

Run from the repo root:  python3 scripts/dev/generate-default-mappings.py

Writes force-app/main/default/customMetadata/*.md-meta.xml (idempotent).

Contract encoded here (kept in sync with the mapping engine, Phase 2):
  - Field mapping Source_Path is relative to the record being mapped.
    For collection mappings (Source_Collection_Path set) it is relative to
    the collection item; use the `$parent.` prefix to read the enclosing
    record and `$root.` for the top-level record.
  - Data_Type=Reference resolves a lookup: the raw value (after Transform,
    e.g. Lower to normalise an email) is matched against
    Transform_Arg = '<TargetObject>.<ExternalIdField>'. Unresolved => left
    null (never orphaned).
  - Money values from Humanitix are decimal major units => DecimalMoney is a
    pass-through Decimal (NO division).
"""
import os

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.normpath(os.path.join(ROOT, "force-app", "main", "default", "customMetadata"))

OBJ_TYPE = "Humanitix_Object_Mapping"
FIELD_TYPE = "Humanitix_Field_Mapping"


def esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace('"', "&quot;"))


def val(field, value, xsi):
    return (f"    <values>\n        <field>{field}</field>\n"
            f'        <value xsi:type="xsd:{xsi}">{esc(value)}</value>\n    </values>')


def record(dev_name, label, value_rows):
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" '
             'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">',
             f"    <label>{esc(label)}</label>",
             "    <protected>false</protected>"]
    lines.extend(value_rows)
    lines.append("</CustomMetadata>")
    return "\n".join(lines) + "\n"


def write(dev_name, content):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, dev_name + ".md-meta.xml"), "w") as fh:
        fh.write(content)


# ---- field-mapping spec ---------------------------------------------------

def fm(source, target, dtype="Text", transform="None", arg=None,
       extid=False, overwrite=True, active=True):
    return dict(source=source, target=target, dtype=dtype, transform=transform,
                arg=arg, extid=extid, overwrite=overwrite, active=active)


def om(dev, label, resource, target, ext_id_field=None, load=10,
       match="ExternalId", match_fields=None, collection=None, active=True,
       description=None, fields=None):
    return dict(dev=dev, label=label, resource=resource, target=target,
                ext_id_field=ext_id_field, load=load, match=match,
                match_fields=match_fields, collection=collection, active=active,
                description=description, fields=fields or [])


# ---- Registry -------------------------------------------------------------
MAPPINGS = []

# A) Event -> Humanitix_Event__c (faithful staging)
MAPPINGS.append(om(
    "Event_to_Event", "Event to Humanitix Event", "Event", "Humanitix_Event__c",
    ext_id_field="Humanitix_Id__c", load=10,
    description="Faithful staging record for each Humanitix event.",
    fields=[
        fm("_id", "Humanitix_Id__c", extid=True),
        fm("userId", "User_Id__c"), fm("organiserId", "Organiser_Id__c"),
        fm("name", "Name"), fm("slug", "Slug__c"),
        fm("url", "Event_URL__c", "Url"), fm("description", "Description__c", "LongText"),
        fm("currency", "Currency_Code__c"), fm("category", "Category__c"),
        fm("classification.type", "Classification_Type__c"),
        fm("classification.category", "Classification_Category__c"),
        fm("classification.subcategory", "Classification_Subcategory__c"),
        fm("public", "Is_Public__c", "Boolean"), fm("published", "Published__c", "Boolean"),
        fm("suspendSales", "Suspend_Sales__c", "Boolean"),
        fm("markedAsSoldOut", "Marked_As_Sold_Out__c", "Boolean"),
        fm("startDate", "Start_Date__c", "DateTime", "IsoToDateTime"),
        fm("endDate", "End_Date__c", "DateTime", "IsoToDateTime"),
        fm("timezone", "Timezone__c"), fm("totalCapacity", "Total_Capacity__c", "Integer"),
        fm("location", "Location_Country__c"),
        fm("isArchived", "Is_Archived__c", "Boolean"),
        fm("isPermanentlyArchived", "Is_Permanently_Archived__c", "Boolean"),
        fm("tagIds", "Tag_Ids__c", "LongText", "JoinArray"),
        fm("createdAt", "Created_At__c", "DateTime", "IsoToDateTime"),
        fm("updatedAt", "Updated_At__c", "DateTime", "IsoToDateTime"),
    ]))

# B) Event.ticketTypes[] -> Humanitix_Ticket_Type__c
MAPPINGS.append(om(
    "Event_Ticket_Types", "Event Ticket Types", "Event", "Humanitix_Ticket_Type__c",
    ext_id_field="Humanitix_Id__c", load=12, collection="ticketTypes",
    description="One record per ticket type nested in an event.",
    fields=[
        fm("_id", "Humanitix_Id__c", extid=True),
        fm("$parent._id", "Event_Humanitix_Id__c"),
        fm("$parent._id", "Humanitix_Event__c", "Reference", arg="Humanitix_Event__c.Humanitix_Id__c"),
        fm("name", "Name"), fm("price", "Price__c", "Currency", "DecimalMoney"),
        fm("quantity", "Quantity__c", "Integer"),
        fm("description", "Description__c", "LongText"),
        fm("disabled", "Disabled__c", "Boolean"), fm("deleted", "Deleted__c", "Boolean"),
        fm("isDonation", "Is_Donation__c", "Boolean"),
    ]))

# C) Event.dates[] -> Humanitix_Event_Date__c
MAPPINGS.append(om(
    "Event_Dates", "Event Dates", "Event", "Humanitix_Event_Date__c",
    ext_id_field="Humanitix_Id__c", load=12, collection="dates",
    description="One record per occurrence for multi-date events.",
    fields=[
        fm("_id", "Humanitix_Id__c", extid=True),
        fm("$parent._id", "Event_Humanitix_Id__c"),
        fm("$parent._id", "Humanitix_Event__c", "Reference", arg="Humanitix_Event__c.Humanitix_Id__c"),
        fm("startDate", "Start_Date__c", "DateTime", "IsoToDateTime"),
        fm("endDate", "End_Date__c", "DateTime", "IsoToDateTime"),
        fm("scheduleId", "Schedule_Id__c"),
        fm("disabled", "Disabled__c", "Boolean"), fm("deleted", "Deleted__c", "Boolean"),
    ]))

# D) Event -> Campaign (standard CRM)
MAPPINGS.append(om(
    "Event_to_Campaign", "Event to Campaign", "Event", "Campaign",
    ext_id_field="Humanitix_Event_Id__c", load=15,
    description="Standard-object mapping: each Humanitix event becomes a Campaign.",
    fields=[
        fm("_id", "Humanitix_Event_Id__c", extid=True),
        fm("name", "Name"),
        fm("startDate", "StartDate", "Date", "IsoToDateInTz", arg="timezone"),
        fm("endDate", "EndDate", "Date", "IsoToDateInTz", arg="timezone"),
        fm("startDate", "Humanitix_Start_DateTime__c", "DateTime", "IsoToDateTime"),
        fm("description", "Description", "LongText"),
        fm("published", "IsActive", "Boolean"),
        fm("totalCapacity", "Humanitix_Total_Capacity__c", "Integer"),
        fm("currency", "Humanitix_Currency__c"),
        fm("public", "Humanitix_Is_Public__c", "Boolean"),
        fm("url", "Humanitix_Event_URL__c", "Url"),
        fm("timezone", "Humanitix_Timezone__c"),
        fm("", "Status", "Text", "StaticValue", arg="In Progress"),
    ]))

# E) Order -> Contact (buyer identity, matched by normalized email)
MAPPINGS.append(om(
    "Order_to_Contact", "Order to Contact (buyer)", "Order", "Contact",
    ext_id_field="Humanitix_Contact_Key__c", load=18,
    description="Buyer becomes a Contact, matched on lower-cased email. Orders without an "
                "email are skipped (attendees without email cannot be de-duplicated).",
    fields=[
        fm("email", "Humanitix_Contact_Key__c", "Text", "Lower", extid=True),
        fm("firstName", "FirstName"), fm("lastName", "LastName"),
        fm("email", "Email", "Email", "Lower"), fm("mobile", "MobilePhone", "Phone"),
        fm("organisation", "Humanitix_Organisation__c"),
        fm("_id", "Humanitix_Last_Order_Id__c"),
    ]))

# F) Order -> Humanitix_Order__c (faithful staging + links to Event & buyer Contact)
MAPPINGS.append(om(
    "Order_to_Order", "Order to Humanitix Order", "Order", "Humanitix_Order__c",
    ext_id_field="Humanitix_Id__c", load=20,
    description="Faithful staging record for each order, with full financial totals.",
    fields=[
        fm("_id", "Humanitix_Id__c", extid=True),
        fm("eventId", "Event_Humanitix_Id__c"),
        fm("eventId", "Humanitix_Event__c", "Reference", arg="Humanitix_Event__c.Humanitix_Id__c"),
        fm("email", "Contact__c", "Reference", "Lower", arg="Contact.Humanitix_Contact_Key__c"),
        fm("eventDateId", "Event_Date_Id__c"), fm("userId", "User_Id__c"),
        fm("currency", "Currency_Code__c"), fm("status", "Status__c"),
        fm("financialStatus", "Financial_Status__c"),
        fm("firstName", "First_Name__c"), fm("lastName", "Last_Name__c"),
        fm("email", "Email__c", "Email"), fm("mobile", "Mobile__c", "Phone"),
        fm("organisation", "Organisation__c"), fm("businessName", "Business_Name__c"),
        fm("paymentType", "Payment_Type__c"), fm("paymentGateway", "Payment_Gateway__c"),
        fm("salesChannel", "Sales_Channel__c"), fm("manualOrder", "Manual_Order__c", "Boolean"),
        fm("clientDonation", "Client_Donation__c", "Currency", "DecimalMoney"),
        fm("notes", "Notes__c", "LongText"),
        fm("totals.total", "Total__c", "Currency", "DecimalMoney"),
        fm("totals.subtotal", "Subtotal__c", "Currency", "DecimalMoney"),
        fm("totals.grossSales", "Gross_Sales__c", "Currency", "DecimalMoney"),
        fm("totals.netSales", "Net_Sales__c", "Currency", "DecimalMoney"),
        fm("totals.totalTaxes", "Total_Taxes__c", "Currency", "DecimalMoney"),
        fm("totals.discounts", "Discounts__c", "Currency", "DecimalMoney"),
        fm("totals.refunds", "Refunds__c", "Currency", "DecimalMoney"),
        fm("totals.bookingFee", "Booking_Fee__c", "Currency", "DecimalMoney"),
        fm("totals.humanitixFee", "Humanitix_Fee__c", "Currency", "DecimalMoney"),
        fm("completedAt", "Completed_At__c", "DateTime", "IsoToDateTime"),
        fm("createdAt", "Created_At__c", "DateTime", "IsoToDateTime"),
        fm("updatedAt", "Updated_At__c", "DateTime", "IsoToDateTime"),
    ]))

# G) Order -> CampaignMember (buyer Contact linked to the event's Campaign)
MAPPINGS.append(om(
    "Order_to_CampaignMember", "Order to Campaign Member", "Order", "CampaignMember",
    load=24, match="MatchByFields", match_fields="CampaignId,ContactId",
    description="Links the buyer Contact to the event's Campaign (one member per Contact+Campaign, "
                "respecting the platform's native unique key). Skipped when Campaign or Contact "
                "cannot be resolved (e.g. order without an email).",
    fields=[
        fm("eventId", "CampaignId", "Reference", arg="Campaign.Humanitix_Event_Id__c"),
        fm("email", "ContactId", "Reference", "Lower", arg="Contact.Humanitix_Contact_Key__c"),
        fm("", "Status", "Text", "StaticValue", arg="Responded"),
    ]))

# H) Order.additionalFields[] -> Humanitix_Order_Attribute__c
MAPPINGS.append(om(
    "Order_Attributes", "Order Attributes", "Order", "Humanitix_Order_Attribute__c",
    ext_id_field="Humanitix_Id__c", load=26, collection="additionalFields",
    description="Checkout question responses attached to an order.",
    fields=[
        fm("questionId", "Humanitix_Id__c", "Text", "Concat", arg="$parent._id", extid=True),
        fm("$parent._id", "Order_Humanitix_Id__c"),
        fm("$parent._id", "Humanitix_Order__c", "Reference", arg="Humanitix_Order__c.Humanitix_Id__c"),
        fm("questionId", "Question_Id__c"),
        fm("value", "Field_Value__c", "LongText"),
        fm("details", "Details_JSON__c", "LongText", "ToJson"),
    ]))

# I) Ticket -> Humanitix_Ticket__c (faithful staging + links to Event & Order)
MAPPINGS.append(om(
    "Ticket_to_Ticket", "Ticket to Humanitix Ticket", "Ticket", "Humanitix_Ticket__c",
    ext_id_field="Humanitix_Id__c", load=20,
    description="Faithful per-ticket attendee record. Note: tickets carry no email, so the "
                "Contact link is provided transitively via the order.",
    fields=[
        fm("_id", "Humanitix_Id__c", extid=True),
        fm("eventId", "Event_Humanitix_Id__c"),
        fm("eventId", "Humanitix_Event__c", "Reference", arg="Humanitix_Event__c.Humanitix_Id__c"),
        fm("orderId", "Order_Humanitix_Id__c"),
        fm("orderId", "Humanitix_Order__c", "Reference", arg="Humanitix_Order__c.Humanitix_Id__c"),
        fm("orderName", "Order_Name__c"), fm("number", "Ticket_Number__c", "Integer"),
        fm("firstName", "First_Name__c"), fm("lastName", "Last_Name__c"),
        fm("organisation", "Organisation__c"), fm("eventDateId", "Event_Date_Id__c"),
        fm("ticketTypeName", "Ticket_Type_Name__c"), fm("ticketTypeId", "Ticket_Type_Id__c"),
        fm("currency", "Currency_Code__c"),
        fm("price", "Price__c", "Currency", "DecimalMoney"),
        fm("netPrice", "Net_Price__c", "Currency", "DecimalMoney"),
        fm("total", "Total__c", "Currency", "DecimalMoney"),
        fm("taxes", "Taxes__c", "Currency", "DecimalMoney"),
        fm("fee", "Fee__c", "Currency", "DecimalMoney"),
        fm("status", "Status__c"),
        fm("checkIn.checkedIn", "Checked_In__c", "Boolean"),
        fm("checkIn.date", "Check_In_Date__c", "DateTime", "IsoToDateTime"),
        fm("seatingLocation.name", "Seating_Name__c"),
        fm("seatingLocation.section", "Seating_Section__c"),
        fm("seatingLocation.table", "Seating_Table__c"),
        fm("seatingLocation.seat", "Seating_Seat__c"),
        fm("salesChannel", "Sales_Channel__c"), fm("isDonation", "Is_Donation__c", "Boolean"),
        fm("cancelledAt", "Cancelled_At__c", "DateTime", "IsoToDateTime"),
        fm("createdAt", "Created_At__c", "DateTime", "IsoToDateTime"),
        fm("updatedAt", "Updated_At__c", "DateTime", "IsoToDateTime"),
    ]))

# J) Ticket.additionalFields[] -> Humanitix_Ticket_Attribute__c
MAPPINGS.append(om(
    "Ticket_Attributes", "Ticket Attributes", "Ticket", "Humanitix_Ticket_Attribute__c",
    ext_id_field="Humanitix_Id__c", load=22, collection="additionalFields",
    description="Checkout question responses attached to a ticket/attendee.",
    fields=[
        fm("questionId", "Humanitix_Id__c", "Text", "Concat", arg="$parent._id", extid=True),
        fm("$parent._id", "Ticket_Humanitix_Id__c"),
        fm("$parent._id", "Humanitix_Ticket__c", "Reference", arg="Humanitix_Ticket__c.Humanitix_Id__c"),
        fm("questionId", "Question_Id__c"),
        fm("value", "Field_Value__c", "LongText"),
        fm("details", "Details_JSON__c", "LongText", "ToJson"),
    ]))

# K) Tag -> Humanitix_Tag__c
MAPPINGS.append(om(
    "Tag_to_Tag", "Tag to Humanitix Tag", "Tag", "Humanitix_Tag__c",
    ext_id_field="Humanitix_Id__c", load=10,
    description="Faithful staging record for each Humanitix tag.",
    fields=[
        fm("_id", "Humanitix_Id__c", extid=True), fm("name", "Name"),
        fm("userId", "User_Id__c"), fm("location", "Location_Country__c"),
        fm("createdAt", "Created_At__c", "DateTime", "IsoToDateTime"),
        fm("updatedAt", "Updated_At__c", "DateTime", "IsoToDateTime"),
    ]))

# L) Order -> Lead (OPTIONAL, inactive by default)
MAPPINGS.append(om(
    "Order_to_Lead", "Order to Lead (optional)", "Order", "Lead",
    ext_id_field="Humanitix_Contact_Key__c", load=30, active=False,
    description="OPTIONAL: activate to route buyers to Leads instead of / as well as Contacts. "
                "Lead.Company is required, so a fallback static value is applied when blank.",
    fields=[
        fm("email", "Humanitix_Contact_Key__c", "Text", "Lower", extid=True),
        fm("firstName", "FirstName"), fm("lastName", "LastName"),
        fm("email", "Email", "Email", "Lower"), fm("mobile", "MobilePhone", "Phone"),
        fm("organisation", "Company"),
        fm("", "Company", "Text", "StaticValue", arg="Unknown", overwrite=False),
        fm("_id", "Humanitix_Last_Order_Id__c"),
    ]))

# M) Order -> Account (OPTIONAL, inactive by default)
MAPPINGS.append(om(
    "Order_to_Account", "Order to Account (optional)", "Order", "Account",
    ext_id_field="Humanitix_Organisation_Key__c", load=28, active=False,
    description="OPTIONAL: activate to create Accounts from order organisations. Orders without "
                "an organisation are skipped.",
    fields=[
        fm("organisation", "Humanitix_Organisation_Key__c", "Text", "Lower", extid=True),
        fm("organisation", "Name"),
    ]))


# ---- Emit -----------------------------------------------------------------

def emit_object_mapping(m):
    rows = [
        val("Source_Resource__c", m["resource"], "string"),
        val("Target_SObject__c", m["target"], "string"),
        val("Match_Strategy__c", m["match"], "string"),
        val("Load_Order__c", f"{float(m['load'])}", "double"),
        val("Is_Active__c", "true" if m["active"] else "false", "boolean"),
    ]
    if m["ext_id_field"]:
        rows.append(val("External_Id_Field__c", m["ext_id_field"], "string"))
    if m["match_fields"]:
        rows.append(val("Match_Field_Set__c", m["match_fields"], "string"))
    if m["collection"]:
        rows.append(val("Source_Collection_Path__c", m["collection"], "string"))
    if m["description"]:
        rows.append(val("Description__c", m["description"][:255], "string"))
    dev = f"{OBJ_TYPE}.{m['dev']}"
    write(dev, record(dev, m["label"], rows))


def emit_field_mapping(parent_dev, idx, f):
    rows = [
        val("Object_Mapping__c", parent_dev, "string"),
        val("Target_Field__c", f["target"], "string"),
        val("Data_Type__c", f["dtype"], "string"),
        val("Transform__c", f["transform"], "string"),
        val("Is_External_Id__c", "true" if f["extid"] else "false", "boolean"),
        val("Overwrite_Blank__c", "true" if f["overwrite"] else "false", "boolean"),
        val("Is_Active__c", "true" if f["active"] else "false", "boolean"),
    ]
    if f["source"]:
        rows.insert(1, val("Source_Path__c", f["source"], "string"))
    if f["arg"] is not None:
        rows.append(val("Transform_Arg__c", f["arg"], "string"))
    dev_name = f"{parent_dev}_{idx:02d}"
    dev = f"{FIELD_TYPE}.{dev_name}"
    label = f"{parent_dev} :: {f['target']}"
    write(dev, record(dev, label[:40], rows))


def emit_sync_setting():
    rows = [
        val("Page_Size__c", "100.0", "double"),
        val("Max_Pages_Per_Transaction__c", "20.0", "double"),
        val("Max_Events_Per_Transaction__c", "25.0", "double"),
        val("Enabled_Resources__c", "Events,Orders,Tickets,Tags", "string"),
        val("In_Future_Only__c", "false", "boolean"),
        val("Max_Retries__c", "5.0", "double"),
        val("Retry_Delay_Minutes__c", "5.0", "double"),
        val("Since_Mode__c", "Modified", "string"),
        val("Named_Credential_Name__c", "HumanitixAPI", "string"),
        val("Consecutive_Failure_Threshold__c", "5.0", "double"),
    ]
    dev = "Humanitix_Sync_Setting.Default"
    write(dev, record(dev, "Default", rows))


def main():
    n_fields = 0
    for m in MAPPINGS:
        emit_object_mapping(m)
        for i, f in enumerate(m["fields"], 1):
            emit_field_mapping(m["dev"], i, f)
            n_fields += 1
    emit_sync_setting()
    print(f"Generated {len(MAPPINGS)} object mappings, {n_fields} field mappings, "
          f"1 sync setting -> {OUT}")


if __name__ == "__main__":
    main()
