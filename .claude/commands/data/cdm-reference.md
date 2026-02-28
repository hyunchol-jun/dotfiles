# CDM Reference Data

Reference tables for the `/analyze-customer-files` command. Read this file during Phases 5-7 for field mapping lookups.

## Common Column Name -> CDM Field Mappings

Use this lookup table when classifying columns. The left side shows common column names (already cleaned to snake_case) and the right shows the CDM field they map to:

| Common Column Name(s) | CDM Field |
|----------------------|-----------|
| `tracking_number`, `tracking_id`, `tracking`, `track_number`, `shipment_id`, `package_id`, `tracking_no` | tracking_number |
| `order_number`, `order_id`, `order`, `so_number`, `sales_order`, `po_number`, `reference_number`, `client_reference` | sales_order_number |
| `invoice_number`, `invoice_id`, `invoice`, `bill_number`, `invoice_no`, `inv_number` | invoice_number |
| `carrier`, `carrier_name`, `shipping_carrier`, `shipper`, `carrier_code` | carrier |
| `service_level`, `service`, `service_type`, `shipping_method`, `delivery_type`, `ship_method`, `service_name`, `product` | carrier_service_level |
| `zone`, `shipping_zone`, `delivery_zone`, `zone_number`, `rated_zone`, `billed_zone` | shipping_zone |
| `ship_date`, `label_date`, `label_create_time`, `create_time`, `ship_time`, `date_shipped`, `pickup_date` | label_create_time |
| `billed_weight`, `billable_weight`, `chargeable_weight`, `rated_weight` | chargeable_weight_oz (check units) |
| `actual_weight`, `weight`, `package_weight`, `pkg_weight`, `gross_weight` | assumed_actual_weight_oz (check units) |
| `dim_weight`, `dimensional_weight`, `volumetric_weight`, `dim_wt` | assumed_dimensional_weight_oz (check units) |
| `manifest_weight`, `declared_weight`, `entered_weight` | manifest_weight_oz (check units) |
| `height`, `pkg_height`, `package_height` | assumed_height_in |
| `length`, `pkg_length`, `package_length` | assumed_length_in |
| `width`, `pkg_width`, `package_width` | assumed_width_in |
| `address`, `ship_to_address`, `delivery_address`, `address_1`, `street`, `address_line_1`, `recipient_address` | ship_to_address_line_1 |
| `address_2`, `address_line_2`, `ship_to_address_2`, `apt`, `suite` | ship_to_address_line_2 |
| `city`, `ship_to_city`, `delivery_city`, `destination_city`, `recipient_city` | ship_to_city |
| `state`, `ship_to_state`, `delivery_state`, `destination_state`, `recipient_state`, `province` | ship_to_state |
| `zip`, `zip_code`, `postal_code`, `ship_to_zip`, `delivery_zip`, `destination_zip`, `recipient_postal_code` | ship_to_postal_code |
| `country`, `ship_to_country`, `delivery_country`, `destination_country`, `country_code` | ship_to_country |
| `warehouse`, `warehouse_code`, `fulfillment_center`, `fc`, `fc_code`, `origin`, `ship_from`, `origin_facility` | warehouse_code |
| `invoice_date`, `bill_date`, `statement_date` | invoice_date |

## Common Service Charge Type Mappings

When mapping charge columns to service_charge_type codes:

| Common Charge Column Name(s) | Service Charge Type |
|------------------------------|-------------------|
| `base_charge`, `base_freight`, `base_rate`, `freight_charge`, `transportation_charge`, `net_charge` | BASE_FREIGHT |
| `fuel`, `fuel_surcharge`, `fuel_charge`, `fsc` | FUEL_SURCHARGE |
| `residential`, `residential_fee`, `residential_surcharge`, `resi`, `res_delivery` | {Carrier} Residential Surcharge (e.g., "UPS Residential Surcharge") |
| `das`, `delivery_area_surcharge`, `delivery_area`, `das_fee` | {Carrier} Delivery Area Surcharge |
| `edas`, `extended_das`, `extended_delivery_area`, `extended_delivery_area_surcharge` | {Carrier} Extended Delivery Area Surcharge |
| `peak`, `peak_surcharge`, `demand_surcharge`, `peak_season` | {Carrier} Peak Season Surcharge |
| `oversize`, `oversize_surcharge`, `additional_handling`, `large_package` | {Carrier} Additional Handling / Large Package |
| `remote`, `remote_area`, `remote_surcharge` | {Carrier} Remote Area Surcharge |
| `signature`, `signature_required`, `signature_confirmation` | Signature Required |
| `insurance`, `declared_value`, `coverage` | Declared Value |
| `discount`, `adjustment`, `credit` | DISCOUNT (note: typically negative values) |
| `total`, `total_charge`, `net_amount` | ALL-IN (if this is the only charge column) |

**Rules:**
- `base_charge` and `fuel` ALWAYS map to global `BASE_FREIGHT` and `FUEL_SURCHARGE` (never carrier-specific)
- All other surcharges use carrier-prefixed names (e.g., "UPS Residential Surcharge", "FedEX Delivery Area Surcharge")
- If only a single total charge column exists with no breakdown, use `ALL-IN`

## Weight Unit Conversion

All CDM weight fields are stored in **ounces (oz)**:
- **Pounds to ounces**: multiply by 16 (e.g., `weight_lbs * 16`)
- **Kilograms to ounces**: multiply by 35.274 (e.g., `weight_kg * 35.274`)
- **Grams to ounces**: multiply by 0.035274

**How to detect weight units:**
- Column name contains "lb", "lbs", "pound" -> pounds
- Column name contains "kg", "kilo" -> kilograms
- Column name contains "oz", "ounce" -> already ounces
- Values mostly > 100 with a weight-looking column -> likely ounces already
- Values mostly 0.1-150 range -> likely pounds
- No unit indicator -> assume pounds (most common in US logistics), flag for user confirmation

## Filename Extraction Patterns

Common patterns for extracting invoice metadata from filenames:

| Pattern | Regex | Extracts |
|---------|-------|----------|
| "INV-01606" | `INV[-_]?(\d+)` | invoice_number |
| "Invoice 12345" | `Invoice\s*[-#]?\s*(\d+)` | invoice_number |
| "Aug 2024" | `(Jan\|Feb\|Mar\|Apr\|May\|Jun\|Jul\|Aug\|Sep\|Oct\|Nov\|Dec)\s*(\d{4})` | invoice_date (month+year) |
| "2024-01-15" | `(\d{4}-\d{2}-\d{2})` | invoice_date |
| "01-15-2024" | `(\d{2}-\d{2}-\d{4})` | invoice_date |
| "Week of 01/15" | `Week\s+of\s+(\d{1,2}/\d{1,2})` | period_start_date |

## CDM Required vs Optional Fields Quick Reference

**Required (NOT NULL):**
- ingestion_id (system-generated)
- invoice_number
- sales_order_number
- tracking_number
- biller
- invoice_date
- period_start_date
- period_end_date
- warehouse_code
- carrier
- carrier_service_level
- shipping_zone
- chargeable_weight_oz
- label_create_time
- service_charge_type
- cost

**Optional (NULL allowed):**
- ship_to_address_line_1/2
- ship_to_city, ship_to_state, ship_to_postal_code, ship_to_country
- assumed_actual_weight_oz, assumed_dimensional_weight_oz, manifest_weight_oz
- assumed_height_in, assumed_length_in, assumed_width_in
- additional_data (JSON)
