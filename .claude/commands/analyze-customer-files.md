---
argument-hint: <directory-path-to-customer-files>
description: Analyze customer invoice files to discover structure, map fields to CDM requirements, and identify cross-file relationships
allowed-tools: Bash(*), Read(*), Write(*), Glob(*), Grep(*), Task(*), AskUserQuestion
---

# Customer File Analysis for `$1`

I'll analyze the customer's invoice files to discover their structure, map fields to CDM requirements, identify cross-file relationships, and produce an actionable report. This runs **before** the ingestion pipeline (`/invoice-ingest-command` -> `/cdm-view-creation` -> `/create-mappings`).

Only pause execution at points explicitly marked with `**PAUSE**`. For all other steps, execute them automatically without pausing.

### Fast Mode

If the user passes `--fast` as an argument, reduce pauses to only:
- **Phase 0** (context gathering - always required)
- **Phase 8** (final review - always required)

Skip all intermediate `**PAUSE**` points (Phase 1 file classification, Phase 6 gap review) and proceed automatically with best-guess defaults.

---

## Phase 0: Context Gathering

**PAUSE - Customer Context Required**

Before analyzing any files, use `AskUserQuestion` to collect all of the following:

1. **Brand name/slug** - The brand identifier used in the system (e.g., "goodr", "misen")
2. **Biller/3PL name** - Who bills this customer for shipping (e.g., "ShipBob", "Stord", "FedEx direct")
3. **Known carriers** - Which carriers does this brand use? (e.g., "UPS and FedEx", or "unknown - please discover from data")
4. **Special notes** - Anything unusual about these files (e.g., "weight is in kg", "two invoice periods mixed together", "some files are duplicates")

Store these answers as context variables for all subsequent phases:
- `BRAND_NAME` - brand slug
- `BILLER_NAME` - biller/3PL
- `KNOWN_CARRIERS` - carrier list or "unknown"
- `SPECIAL_NOTES` - any notes

---

## Phase 1: File Discovery & Classification

Scan the provided directory `$1` for all data files using the **Glob tool** (not bash `find`):

- `**/*.pdf`
- `**/*.xlsx`
- `**/*.xls`
- `**/*.csv`
- `**/*.tsv`

Run all five glob patterns in parallel against the `$1` directory.

For each file found, build a catalog table:

| # | Filename | Type | Size | Role Guess |
|---|----------|------|------|------------|
| 1 | ... | XLSX | ... | ... |

**Role classification rules** (based on filename keywords):
- Contains "invoice", "bill", "statement" -> `invoice_summary` (PDF typically) or `invoice_detail`
- Contains "detail", "line", "item", "charge" -> `charge_detail`
- Contains "support", "supplemental", "additional" -> `supplemental_data`
- Contains "zone" -> `zone_reference`
- Contains "freight", "shipping" -> `freight_charges`
- Contains "summary", "recap" -> `summary`
- Contains "tracking", "shipment" -> `shipment_detail`
- Contains "adjust", "credit", "dispute" -> `adjustments`
- No keyword match -> `unknown`

**PAUSE - File Classification Confirmation**

Present the catalog table to the user. Ask them to:
1. Confirm or correct the role classification for each file
2. Flag any files that should be ignored (duplicates, irrelevant, corrupted)
3. Identify the primary charge file (the one with per-tracking-number costs)

---

## Phase 2: Excel/CSV File Deep Analysis

### Pre-Processing Checks

Before processing each file, check for edge cases:
- **Password-protected Excel** - if openpyxl raises an error, flag the file and skip it
- **Empty files** (0 data rows after header) - flag and skip
- **Very large files** (>100K rows) - sample the first 1000 rows + last 100 rows instead of reading the full file
- **Encoding issues** (CSV/TSV) - try utf-8 first, then latin-1, then cp1252

### Excel Parsing Strategy

Claude Code **cannot natively parse `.xlsx`/`.xls` files** - they appear as binary data. Use Python with openpyxl to extract content:

```bash
python3 -c "
import openpyxl, sys
wb = openpyxl.load_workbook(sys.argv[1], read_only=True)
for sheet in wb.sheetnames:
    ws = wb[sheet]
    print(f'=== Sheet: {sheet} ({ws.max_row} rows x {ws.max_column} cols) ===')
    for i, row in enumerate(ws.iter_rows(values_only=True)):
        if i >= 20: break
        print('\t'.join(str(c) if c is not None else '' for c in row))
" "$FILE"
```

To sample a larger range (e.g., for data type detection), adjust the row limit or add tail sampling:

```bash
python3 -c "
import openpyxl, sys
wb = openpyxl.load_workbook(sys.argv[1], read_only=True)
ws = wb[wb.sheetnames[0]]
rows = list(ws.iter_rows(values_only=True))
print(f'Total rows: {len(rows)}')
# Print first 15 rows (header detection) + 10 sampled data rows
for row in rows[:15]:
    print('\t'.join(str(c) if c is not None else '' for c in row))
print('--- sampled data rows ---')
import random
sample_indices = sorted(random.sample(range(15, len(rows)), min(10, len(rows)-15))) if len(rows) > 15 else []
for i in sample_indices:
    print(f'[row {i}]\t' + '\t'.join(str(c) if c is not None else '' for c in rows[i]))
" "$FILE"
```

For each non-ignored Excel/CSV file, perform the following analysis:

### 2a. Sheet Discovery (Excel only)
- List all sheets and their dimensions (rows x columns)
- Identify which sheets contain actual data vs. metadata/instructions

### 2b. Header Row Detection
- Read the first 15 rows of each sheet/file
- Identify the actual header row (not metadata rows like "Account: XXXXX" or "Invoice Period: ...")
- Metadata rows typically have values in column A only; header rows have values across many columns
- Look for patterns: if a row has 5+ non-empty cells and the next row has similar density, the first is likely the header

### 2c. Column Header Extraction & Normalization
For each column header found, apply the system's `cleanColumnName` logic:
- Trim whitespace
- Convert to snake_case using lodash-style conversion (handles PascalCase, camelCase, spaces, hyphens)
- Prefix with underscore if result starts with a number
- Empty headers become `unnamed_column`

**Examples of cleanColumnName transformation:**
- `"Tracking Number"` -> `tracking_number`
- `"Ship Date"` -> `ship_date`
- `"FedEx Ground"` -> `fed_ex_ground`
- `"3PLServiceLevel"` -> `_3_pl_service_level`
- `"DAS (Residential)"` -> `das_residential`
- `"Weight (lbs)"` -> `weight_lbs`

### 2d. Data Sampling & Type Classification
Sample 5-10 data rows per sheet. For each column, classify by data pattern:

| Pattern | Detection Rule | CDM Candidate |
|---------|---------------|---------------|
| Tracking number | Alphanumeric 12-34 chars, often starts with 1Z (UPS), digits (FedEx/USPS) | tracking_number |
| Date | ISO format, MM/DD/YYYY, or date-like strings | label_create_time, invoice_date |
| Currency/cost | Numeric with 2 decimal places, possibly with $ prefix | cost, service charge columns |
| Carrier name | Matches known carrier names (UPS, FedEx, DHL, etc.) | carrier |
| ZIP/postal code | 5-digit number or 5+4 format | ship_to_postal_code |
| Zone | Single digit 1-9 or two digits | shipping_zone |
| Weight | Numeric, often with 1-2 decimal places | chargeable_weight_oz (needs unit check) |
| State | 2-letter code or full state name | ship_to_state |
| Service level | Contains "Ground", "Express", "Priority", etc. | carrier_service_level |
| Boolean/flag | Y/N, Yes/No, True/False, 0/1 | supplemental flag |

### 2e. Per-File Summary
Produce a table for each file:

| Raw Header | Cleaned Name | Data Type | CDM Candidate | Sample Values |
|------------|-------------|-----------|---------------|---------------|
| Tracking Number | tracking_number | tracking_number | tracking_number | 1Z999AA10123456784 |
| Ship Date | ship_date | date | label_create_time | 2024-01-15, 2024-01-16 |
| ... | ... | ... | ... | ... |

---

## Phase 3: PDF Analysis

For each PDF file, use the Read tool (Claude Code reads PDFs natively).

Extract and document:

### 3a. Invoice Metadata
- **Invoice number**: Look for "Invoice #", "Invoice Number", "Bill Number"
- **Invoice date**: Look for "Invoice Date", "Bill Date", "Statement Date"
- **Billing period**: Look for "Period", "Service Period", "From/To" dates
- **Account info**: Account number, customer name, billing address
- **Biller name**: Company name at top of invoice

### 3b. Summary Tables
- Carrier/service breakdowns with totals
- Charge category subtotals (freight, surcharges, adjustments)
- Grand total and any credits/adjustments

### 3c. PDF-Unique Data
Document what the PDF provides that Excel files may NOT:
- Typically: invoice_number, invoice_date, period_start_date, period_end_date, biller
- These values often need to be hardcoded or extracted from filenames during ingestion

---

## Phase 4: Cross-File Relationship Discovery

### 4a. Shared Column Detection
Compare cleaned column names across all Excel/CSV files. Find columns that appear in multiple files:

| Column Name | Found In Files | Likely Role |
|-------------|---------------|-------------|
| tracking_number | file_a.xlsx, file_b.csv | Primary join key |
| order_number | file_a.xlsx, file_c.xlsx | Secondary join key |

### 4b. Join Key Validation
For the most likely join key (usually `tracking_number`):
- Count distinct values in each file
- Calculate overlap percentage between file pairs
- Sample 5-10 matching records to verify the join produces sensible results

```
File A tracking_numbers: 15,432 distinct
File B tracking_numbers: 15,430 distinct
Overlap: 15,428 (99.97%) -> Strong join candidate
```

### 4c. Relationship Map
Document the file relationships:

```
PRIMARY: charges.xlsx (has costs per tracking number)
  |-- LEFT JOIN --> support.csv ON tracking_number (adds zone, dimensions)
  |-- LEFT JOIN --> adjustments.csv ON tracking_number (adds credit amounts)

STANDALONE: invoice_summary.pdf (provides invoice metadata - hardcode into view)
```

---

## Phase 5: CDM Field Mapping

Map every discovered field to the CDM target schema. Work through each category systematically.

### 5a. Required Key Identifiers (NOT NULL)

| CDM Field | Type | Source Column | Source File | Transformation |
|-----------|------|---------------|-------------|----------------|
| ingestion_id | varchar | (system-generated) | N/A | Auto-populated by ingestion pipeline |
| invoice_number | varchar | ? | ? | May come from filename extraction or PDF |
| sales_order_number | varchar | ? | ? | Look for order_number, order_id, so_number |
| tracking_number | varchar | ? | ? | Usually the primary key in charge files |

### 5b. Required Invoice Metadata (NOT NULL)

| CDM Field | Type | Source Column | Source File | Transformation |
|-----------|------|---------------|-------------|----------------|
| biller | varchar | ? | ? | Often hardcoded from BILLER_NAME context |
| invoice_date | date | ? | ? | From PDF or filename extraction |
| period_start_date | date | ? | ? | `MIN(ship_date) OVER (PARTITION BY ingestion_id, invoice_number)` |
| period_end_date | date | ? | ? | `MAX(ship_date) OVER (PARTITION BY ingestion_id, invoice_number)` |

### 5c. Required Fulfillment Data (NOT NULL)

| CDM Field | Type | Source Column | Source File | Transformation |
|-----------|------|---------------|-------------|----------------|
| warehouse_code | varchar | ? | ? | Look for warehouse, fulfillment_center, fc, origin, ship_from |

### 5d. Required Package/Shipping Data (NOT NULL)

| CDM Field | Type | Source Column | Source File | Transformation |
|-----------|------|---------------|-------------|----------------|
| carrier | varchar | ? | ? | Needs mapping to normalized carrier names |
| carrier_service_level | varchar | ? | ? | Needs mapping to normalized service levels |
| shipping_zone | varchar | ? | ? | Usually single digit 1-9 |
| chargeable_weight_oz | DECIMAL(18,2) | ? | ? | **Check units** - if lbs, multiply by 16 |
| label_create_time | timestamp | ? | ? | Look for ship_date, label_date, create_time |

### 5e. Required Charge Data (NOT NULL)

| CDM Field | Type | Source Column | Source File | Transformation |
|-----------|------|---------------|-------------|----------------|
| service_charge_type | varchar | (derived) | ? | From UNPIVOT column names or existing column |
| cost | DECIMAL(18,2) | (derived) | ? | From UNPIVOT values or existing column |

**Charge Structure Analysis** - Determine which pattern applies:

1. **Column-based (needs UNPIVOT)**: Multiple charge columns like `base_charge`, `fuel_surcharge`, `residential`, `das` -> each becomes a row via UNPIVOT
2. **Row-based**: Each row already represents a single charge type with `charge_type` and `amount` columns
3. **All-in**: Single total charge per tracking number, use `ALL-IN` as service_charge_type

Identify all charge columns and map them to service charge type codes:

| Charge Column | Cleaned Name | Service Charge Type |
|---------------|-------------|-------------------|
| Base Charge | base_charge | BASE_FREIGHT |
| Fuel Surcharge | fuel_surcharge | FUEL_SURCHARGE |
| Residential Fee | residential_fee | {Carrier} Residential Surcharge |
| DAS | das | {Carrier} Delivery Area Surcharge |

### 5f. Optional Address Data (NULL allowed)

Map any available address fields: ship_to_address_line_1, ship_to_address_line_2, ship_to_city, ship_to_state, ship_to_postal_code, ship_to_country.

### 5g. Optional Weight/Dimension Data (NULL allowed)

Map any available weight/dimension fields. **Critical unit considerations:**
- `assumed_actual_weight_oz` - if source is in lbs, multiply by 16
- `assumed_dimensional_weight_oz` - if source is in lbs, multiply by 16
- `manifest_weight_oz` - if source is in lbs, multiply by 16
- `chargeable_weight_oz` - typically `billed_weight` or `billable_weight`; if in lbs, multiply by 16
- `assumed_height_in`, `assumed_length_in`, `assumed_width_in` - usually already in inches

**Common weight field name patterns:**
- `billed_weight`, `billable_weight`, `chargeable_weight` -> chargeable_weight_oz
- `actual_weight`, `package_weight`, `weight` -> assumed_actual_weight_oz
- `dim_weight`, `dimensional_weight`, `volumetric_weight` -> assumed_dimensional_weight_oz
- `manifest_weight`, `declared_weight` -> manifest_weight_oz

---

## Phase 6: Gap Analysis

### 6a. Missing Required Fields

List every CDM required field that could NOT be mapped from any source file:

| CDM Field | Status | Suggested Resolution |
|-----------|--------|---------------------|
| invoice_number | MISSING | Extract from filename (regex pattern) |
| biller | MISSING | Hardcode as `'{BILLER_NAME}'` from context |
| period_start_date | MISSING | Calculate: `MIN(ship_date) OVER (PARTITION BY ingestion_id, invoice_number)` |
| warehouse_code | MISSING | Ask customer to provide or hardcode if single warehouse |

**Resolution strategies** (try in this order):
1. **Calculate from existing data** - e.g., period dates from MIN/MAX of ship_date
2. **Hardcode from context** - e.g., biller name from Phase 0 context
3. **Extract from filename** - e.g., invoice number using regex
4. **Auto-determine** - e.g., zone from origin/destination ZIP pair
5. **Request from customer** - last resort, document exactly what's needed

### 6b. Data Quality Issues

Flag issues found during sampling:
- NULL values in critical columns (tracking_number, cost) - what percentage?
- Inconsistent date formats within the same column
- Non-US shipments that will need filtering (ship_to_country != US, non-US states)
- Zero or negative charges (are negative charges credits/adjustments?)
- Weight values that are 0 or suspiciously uniform
- Duplicate tracking numbers within the same file
- Mixed carriers in a single file vs. carrier-per-file structure

### 6c. US-Only Filtering Assessment

The `/cdm-view-creation` command filters to US-only shipments. Assess the data for this:
- **Does the data have a `ship_to_country` column?** What distinct values does it contain? (Look for US, USA, UNITED STATES, CA, MX, GB, etc.)
- **If `ship_to_country` is frequently NULL**, is `ship_to_state` available as a fallback? The CDM view uses US state abbreviations and full names to infer country when country is NULL.
- **Are there non-US records that need filtering?** Estimate the percentage of non-US shipments.
- **Document the recommended filtering strategy** for `/cdm-view-creation`:
  - If country column exists with reliable values: filter on country
  - If country is mostly NULL but state is available: use state-based fallback
  - If neither exists: note that all records will be assumed US (flag for user confirmation)

**PAUSE - Gap Review**

Present the gap analysis to the user. Ask:
1. Can they provide any of the missing data?
2. Do the transformation suggestions look correct?
3. Are there any data quality issues they're already aware of?
4. For hardcoded values (biller, warehouse), confirm the exact values to use

---

## Phase 7: Carrier & Service Level Discovery

### 7a. Extract Distinct Carriers
Query distinct carrier values from the data. For each carrier found, list:
- Raw carrier value as it appears in data
- Suggested normalized carrier name
- Count of records

### 7b. Validate Against Supported Carriers

**Supported carriers in the system:**
- Amazon, BetterTrucks, DHL, DoorDash, Endicia, FedEx, GLS, OnTrac, RJW, ShipBob, UPS, USPS, UniUni, ZoneJump, VEHO, ShipMonk, Stord, SpeedX, FLEXPORT, OSM

**Carrier normalization rules** (from `getNormalizedCarrierName`):
- Case-insensitive matching, strip spaces/hyphens/underscores
- "FEDEX", "FEDERAL EXPRESS", "Federal Express" -> `FedEx`
- "UPS", "United Parcel Service" -> `UPS`
- "DHL", "DHL Express", "DHL eCommerce" -> `DHL`
- "ONTRAC", "On Trac", "OnTrac" -> `OnTrac`
- "USPS", "US Postal", "United States Postal Service" -> `USPS`

Flag any carriers that don't match the supported list.

### 7c. Extract Service Levels Per Carrier
For each carrier, list distinct service level values:

| Carrier | Raw Service Level | Record Count | Suggested Normalized Level |
|---------|------------------|-------------|---------------------------|
| FedEx | FEDEX_GROUND | 5,432 | GROUND |
| FedEx | FEDEX HOME DELIVERY | 2,100 | HOME_DELIVERY |
| UPS | UPS GROUND | 8,900 | GROUND |
| UPS | UPS SUREPOST | 1,200 | SUREPOST |

### 7d. Virtual Carrier Detection
Check if the biller is a virtual carrier (e.g., Stord, ShipBob). If so, note that `additional_data` JSON should include:
```json
{
  "virtualCarrier": "{BILLER_NAME}",
  "virtualCarrierServiceLevel": "{virtual_service_level_column}"
}
```

---

## Phase 8: Report Generation

Write a comprehensive analysis report to `$1/file-analysis-report.md` with the following sections:

### Report Structure

```markdown
# File Analysis Report: {BRAND_NAME}

**Generated:** {current_date}
**Biller:** {BILLER_NAME}
**Directory:** $1

---

## 1. Executive Summary
- Number of files analyzed
- Primary charge file identified
- Charge structure type (column-based/row-based/all-in)
- Carriers found
- CDM coverage percentage (mapped fields / total required fields)
- Key gaps and risks

## 2. File Inventory
Table of all files with role, type, size, sheet count, row count

## 3. Structure Details
Per-file breakdown: headers, cleaned names, data types, sample values

## 4. Cross-File Relationships
Join key analysis, overlap percentages, relationship diagram

## 5. CDM Field Mapping
Complete mapping table: CDM field -> source column -> source file -> transformation needed

## 6. Charge Structure
- Charge type (column-based/row-based/all-in)
- Charge columns identified
- Service charge type mappings
- UNPIVOT configuration if needed

## 7. Carrier & Service Levels
- Carrier mapping table
- Service level mapping table per carrier
- Virtual carrier configuration if applicable

## 8. Gap Analysis
- Missing required fields with resolution strategies
- Data quality issues found
- Estimated effort to resolve each gap

## 9. Recommended Configuration
This section maps directly to inputs needed for downstream commands:

### For /invoice-ingest-command:
- Brand name: {BRAND_NAME}
- Header row positions per file
- Files to process and their roles

### For /cdm-view-creation:
- Charge structure type and UNPIVOT columns
- Join strategy between files
- Hardcoded values (biller, invoice metadata)
- Calculated fields (period dates)
- Weight unit conversions needed
- US-only filtering strategy (country column availability, state fallback, non-US percentage)

#### ingestion_id Isolation (Critical)
All window functions (e.g., period date calculations) and cross-file joins MUST include `ingestion_id` as the **FIRST** partition/join column to prevent cross-ingestion data contamination. Document any calculated fields with their full partition specification:
- Example: `MIN(ship_date) OVER (PARTITION BY ingestion_id, invoice_number)`
- Example JOIN: `ON a.ingestion_id = b.ingestion_id AND a.tracking_number = b.tracking_number`

### For /create-mappings:
- Carrier name mappings (raw -> normalized)
- Service level mappings per carrier
- Service charge type mappings
- Warehouse code mappings

Present mappings in the carrier-grouped structure expected by `/create-mappings`:
```json
{
  "carriers": {
    "UPS": {
      "serviceLevels": {
        "UPS GROUND": "GROUND",
        "UPS SUREPOST": "SUREPOST"
      },
      "serviceChargeTypes": {
        "base_charge": "BASE_FREIGHT",
        "fuel_surcharge": "FUEL_SURCHARGE",
        "residential_fee": "UPS Residential Surcharge"
      }
    },
    "FedEx": {
      "serviceLevels": {
        "FEDEX_GROUND": "GROUND",
        "FEDEX HOME DELIVERY": "HOME_DELIVERY"
      },
      "serviceChargeTypes": {
        "base_charge": "BASE_FREIGHT",
        "fuel_surcharge": "FUEL_SURCHARGE",
        "das": "FedEx Delivery Area Surcharge"
      }
    }
  },
  "warehouses": {
    "ATLANTA_FC": "Atlanta",
    "LAX_WAREHOUSE": "Los Angeles"
  }
}
```
Replace the example values above with actual source values discovered during analysis.

## 10. Next Steps
Ordered list of actions to take

## 11. Open Questions
Unresolved items requiring customer or team input
```

**PAUSE - Final Review**

Present a summary of the report to the user:
- Key findings (charge structure, carrier count, CDM coverage %)
- Top 3 gaps or risks
- Recommended next step

Ask if any adjustments are needed before finalizing.

---

## Reference Data

**Loaded on demand to save context window.** Read the CDM reference tables from `~/.claude/commands/data/cdm-reference.md` when you reach Phases 5-7 and need field mapping lookups, charge type mappings, weight conversions, filename extraction patterns, or the required/optional fields list.
