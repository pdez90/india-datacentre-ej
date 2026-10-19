# India data-centre facility table: data dictionary and methods

File: `data/india_datacentres_public.csv` has 340 rows, one per facility in the
inventory the paper analyses (30 September 2026). Only this version is released.

- It covers all data centres: commercial, enterprise, telecom and government. Sites known to be
  closed are excluded.
- Revised and checked 30 September 2026.
- Licence: [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/).

## Where rows come from

**The backbone is the Data Center Map directory** (datacentermap.com), the industry's standard
facility directory. Every facility it lists for India is kept, unless it is closed or is a second
listing of the same building. Three other kinds of record add facilities the directory does not list.
Each was double-checked against the cited pages on 30 September 2026.

| `inventory_source` | Rows (operating) | Meaning |
|---|---|---|
| Data Center Map directory | 213 (135) | The directory's India listing, read entry by entry |
| operator census | 66 (61) | Operators' own published facility lists (NTT, STT GDC, Sify, CtrlS, Nxtra, Yotta, Equinix and others) |
| government data-centre census | 32 (32) | NIC/NICSI national data centres, UIDAI, ISRO, CRIS (railways), and the State Data Centres of 21 states and union territories |
| operator, company, government or press record | 29 (18) | Sites missing from the directory that were found during the cross-check against the Atlas of Data Center Politics: 26 are listed in the Atlas; IN306 (CtrlS Rambilli) and IN325-IN326 (Yotta TB1, TB2) were found on the press and operator pages consulted for it and have no Atlas record. Each rests on the cited primary source, not on the Atlas |

The Atlas of Data Center Politics and OpenStreetMap are used only as cross-checks, never as a
source for a row.

## What a row is

- **A row is one facility as its source lists it.** This is usually one building. A few rows are whole
  campuses, where the operator lists the campus as one entry. The `mw_basis` column says which.
- **Each facility is counted once.** When the same facility appears twice, the listings are merged.
  For example, 11 old Tata Communications listings are buildings now run by STT, and two tenant suites
  sat inside another listed operator's data centre. The merged listing's URL is kept in `source_note`.
- **Separate operators in one multi-tenant building stay separate rows** and share the building's
  geocode: the Boomerang complex in Chandivali, Mumbai (IN090 Digital Connexion BOM10, IN127 Ishan
  DC1; Equinix MB1, IN102, is next door) and the STPI building in Cyber Park, Electronic City,
  Bengaluru (IN096 ESDS, IN257 Sify Bengaluru 01). Each `source_note` gives the units and why the rows
  are not duplicates. A modelled load for such a suite (ESDS, 9.7 MW) may overstate it.
- **`facility_id` is stable.**
  - IDs run from IN001 to IN360.
  - Gaps are merged or dropped rows; `correction_applied` records each correction.
- **Status:**
  - `operating`: 246 rows in 61 districts. The paper's main results use these.
  - `under construction`: 56 rows.
  - `announced (planned)`: 38 rows.
  - The pipeline scenario covers all 340 facilities in 66 districts.
- **Location:** `latitude` and `longitude` give the site geocode used to assign the district (WGS84 decimal
  degrees), with city, district and state. `location_precision` says what the point is: the building (68 rows),
  a campus or IT park (125), a named locality (112), or a city placeholder (35).
- **District and state:** `district_2015` and `state_2015` give the district and state the analysis uses: the
  Census 2011 district polygons (641 districts), joined to the NFHS-5 district identifiers so that each facility
  joins the survey data.
  - Each facility is assigned by its site coordinates to the polygon that contains it (a point outside every
    polygon would take the nearest one within 3 km; none did). Three facilities (IN177, IN179, IN360) are
    assigned by hand to the district their address names, where the generalised boundary splits the address;
    their `source_note` says so (SI section S1.1.5).
  - The site coordinates separate Chennai, Hyderabad, Kolkata and Mumbai from their neighbouring districts; a
    facility in a suburb or IT park is placed in the district where it actually sits (for example, Siruseri in
    Kancheepuram and Salt Lake in North Twenty Four Parganas).
  - The Census 2011 frame predates Telangana, so Hyderabad-area districts sit in Andhra Pradesh in
    `state_2015`; `state_current` gives Telangana.

## Sources, confidence and what we are unsure of

Every row has a `source_url`. 289 rows also have a second source (`source_url_2`); for 16 directory-only rows that second
source (another directory, a reseller listing or a lapsed operator domain) does not independently document the facility.
`source_url_archive` and `source_url_2_archive` give archived copies, from the Internet Archive or
(for sites that refuse it) archive.today, filled by `scripts/25_archive_sources.py`. All 340
facilities have an archived primary source, and 548 of the 551 cited URLs have a copy. Of the 245 cited Data
Center Map pages, 164 are in the Internet Archive; the other 81, and 5 IndiaMART pages, which the
Internet Archive refused, were archived on archive.today by hand by 10 October 2026. Six cited pages were first found to be reachable only from
Indian networks. A co-author in India checked them on 20 October 2026: three are also published at
addresses reachable from outside India, which are now cited and archived (IN331, IN348, IN350). The
other three (second sources for IN347, IN353 and IN360) remain reachable only from India, so neither
archive could capture them; the authors hold dated PDF copies of the IN353 and IN360 pages.
`source_note` records this for each. For IN353 and IN360 the archived primary source is less detailed
than the India-only page. `sources_and_archives.csv` in the
downloadable bundle lists every cited URL with its archived copy, snapshot date and status.

- **On 30 September 2026, 145 Data Center Map rows were checked** against the operator's site, PeeringDB,
  Baxtel or the press. Of the 145:
  - 82 were confirmed by an independent source;
  - 41 are likely (the operator confirms a data centre in that city);
  - 22 have no trace beyond the directory listing.
- **Of the other 68 directory rows**, 33 already had an independent source. The remaining 35 had been
  recorded as confirmed only because they were matched on the directory's own city index; on 21 October
  2026 they were reclassified as directory-only, since the directory is not an independent source. All
  57 directory-only rows are kept, as directory listings, and rated low confidence.
- **Every other row was double-checked** against its cited pages.

`source_verification` records how each row was checked:

| Value | Rows | Meaning |
|---|---|---|
| `confirmed` | 232 | Facility documented by a source independent of the directory, and a second source is listed |
| `partial` | 41 | Listed in the directory; the operator confirms a data centre in that city but not this exact building |
| `directory_only` | 57 | Listed in the directory only; no independent source found |
| `single_source` | 10 | One source only (an operator, government, PeeringDB or press page), not the directory |

**`confidence`** (high 202, medium 67, low 71) summarises this for each row:

- **high:** confirmed by a source independent of the directory, with a second source and no open issue;
- **low:** directory listing only (no independent trace), or an open question about whether the site operates as recorded;
- **medium:** everything else.

**`confidence_note`** says in plain language what is uncertain for that row.

## Other columns

| Column | Meaning |
|---|---|
| `facility_type` | Operator class used for the class weight: colocation, hyperscale, enterprise, government or telecom |
| `opened_year` | Year the facility opened, where a source gives it (blank otherwise) |
| `mw_flag` | Why the published capacity is uncertain (conflicting figures, unclear measure); blank if none |
| `source_title`, `source_type`, `source_title_2`, `source_type_2` | Title and kind of each cited source. `source_type` is one of: `directory` (Data Center Map, Baxtel, IndiaMART and similar listings), `peeringdb`, `operator` (the operator's own site or report), `government` (incl. parliamentary answers), `press`, `press release`, `certification registry` (Uptime Institute) or `contractor or vendor` |
| `url_checked` | Whether the cited page was fetched and read (`fetched`) or seen only as a search result (`search_result`) |
| `status_in_source`, `status_agrees_with_inventory` | The status the cited source gives, and whether it matches the row's status (blank where the source gives none or the comparison is ambiguous) |
| `sources_retrieved` | Date the sources were retrieved |
| `adp_match`, `adp_campus_name`, `adp_status`, `adp_stage`, `adp_size_bucket`, `adp_source_urls` | The cross-check against the Atlas of Data Center Politics: how the row was matched (or `none`), and the Atlas's campus name, status, stage, size class and source links. The Atlas is a cross-check only, never a source of rows |
| `inventory_version` | Inventory release date (2026-09-30) |

## Capacity: what the MW numbers are

- **Two published-load columns:** `mw_it_reported_current` and `mw_it_reported_buildout` hold
  published IT loads, current and at full build-out.
  - 96 operating facilities report a current load, totalling 1,246.7 MW.
  - 118 rows report a load of some kind.
  - Only figures that a source labels (or clearly means) as IT load are used. Total power, MVA, an
    unlabelled "capacity" or an investment sum is listed in `mw_published_figures` but not used.
- **`mw_certainty`** gives the status of the power figure for each row: reported IT load (85 rows),
  reported but uncertain (30), or not published, so modelled (225).
- **`mw_note`** says what the figure is, and why it is uncertain where it is.
- **`mw_it_used_in_paper`** is the IT capacity each operating facility carries in the central case.
  - Reported loads are held fixed.
  - Commercial facilities (colocation and hyperscale) without one are anchored to 1,800 MW of national
    commercial IT capacity (Savills, H1 2026), shared out by class weight: hyperscale 10, colocation 3.
  - Enterprise (1), government (1) and telecom (0.5) facilities use the same MW per weight unit
    (3.22 MW), without rescaling to a national total.
  - The column sums to 2,059 MW.
- **`mw_method`** says, row by row, how the MW figure that matters for the row was set (the paper's figure for an
  operating row, the scenario figure for a planned one), with the arithmetic:
  - `reported`: the published IT load, used as published;
  - `modelled`: no published IT load, so class weight x MW per weight unit, e.g. "colocation weight 3 x 3.22 MW per
    weight unit = 9.67 MW". The 3.22 MW is set so that the commercial facilities (colocation and hyperscale) sum to
    the 1,800 MW anchor: (1,800 - 1,216.7 MW published by 93 commercial facilities) / 181 weight units held by the
    44 commercial facilities without a published load. Non-commercial facilities take the same 3.22 MW per unit;
  - `not sized`: the 25 operating directory listings that could not be confirmed as separate buildings with their own load
    carry 0 MW (two of them, IN014 and IN127, are confirmed facilities whose listings are not confirmed as separate buildings with their own load; IN127 is a suite in the Boomerang complex).
  The app's Facilities tab walks through this calculation step by step.
- **`class_weight`** is the weight used for the row (hyperscale 10, colocation 3, enterprise 1, government 1,
  telecom 0.5; 0 for a row that is not sized).
- **`mw_it_used_in_pipeline_scenario`** sizes all 340 facilities. It uses published build-outs where
  they exist, the current published load where only that exists, and today's MW per weight unit otherwise.
  - It sums to 6,302 MW (6,301.4 if the column, rounded to 0.001 MW per row, is added up). This is a scenario, not an estimate.
  - Counting the 75 planned sites with no published load (modelled) as zero gives a lower bound of 5,096 MW.

**Modelled capacities are allocations, not measurements.**

## Corrections (see `correction_applied` and `correction_evidence`)

Every correction made during verification is listed in `correction_applied` (field, old value, new value and reason) with its
evidence URL in `correction_evidence`.
The corrections were made in five batches:

1. The first source pass.
2. Duplicates; operator statuses and IT loads (Nxtra, STT, NTT, Sify, Yotta, CtrlS); district fixes.
3. The independent check of the directory rows: types (AirTrunk, ESR, L&T, Digital Connexion and others
   are colocation), statuses (Nxtra Kolkata live, Google Rambilli under construction), towns, and merged
   duplicates.
4. The double-check of the other rows: NTT, STT and CtrlS IT loads; Nxtra Mahape 2 and CtrlS Patna DC2
   are live; Sify Bengaluru 02's 22 MW is design capacity.
5. 19 October 2026: Iron Mountain HYD-1 current IT load set to the operator's own figure (5.7 MW; the directory and
   trade press give 5.5 MW).

## Open issues (`open_issue`)

Open issues are flagged, not resolved; `confidence_note` gives them for each row. They include:

- Data Center Map listings with no independent trace;
- status questions: Reliance IDC sites (operator insolvent), AWS TTC, Digital Connexion BOM10, Nxtra
  Hyderabad, Sify Lucknow, CtrlS Bhubaneswar, the Karnataka SDC;
- capacity figures that sources disagree on or do not label as IT load;
- possible overlaps between AWS Hyderabad buildings, and between ESR Rabale and Sify Rabale.

## Updating, citing, licence

- **Report an error or a missing facility:** use the app's *Submit a data centre* tab, or open an issue on
  the repository.
- **Release:** 30 September 2026. Sources were re-found and archived, the directory rows were independently
  checked, the other rows double-checked, government data centres and confidence ratings added, and every
  correction documented. Only this version is released.
- **Cite as:** deSouza, P. et al. (2026). India data-centre inventory (public facility table), version
  2026-09-30. https://github.com/pdez90/india-datacentre-ej
- **Licence:** [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/). The licence covers our
  compilation and annotations. Facility facts remain those of the cited sources, including Data Center
  Map.
