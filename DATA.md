# India data-centre facility table: data dictionary and methods

File: `data/india_datacentres_public.csv` has 329 rows, one per facility in the
inventory the paper analyses (snapshot of 30 September 2026). Only this version is released.

- It covers all data centres: commercial, enterprise, telecom and government. Sites known to be
  closed are excluded.
- Built 30 September 2026, then re-verified row by row between 21 and 26 October 2026 (see *Verification history*).
- Licence: [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/).

## Where rows come from

**The backbone is the Data Center Map directory** (datacentermap.com), the industry's standard
facility directory. Every facility it lists for India is kept, unless it is closed, is a second
listing of the same building, or turned out on review to be a hosting reseller or office rather than a
data centre. The directory is where a row comes from, not evidence that it exists (see *Source types*).
Three other kinds of record add facilities the directory does not list.

| `inventory_source` | Rows (operating) | Meaning |
|---|---|---|
| Data Center Map directory | 202 (123) | The directory's India listing, read entry by entry |
| operator census | 66 (62) | Operators' own published facility lists (NTT, STT GDC, Sify, CtrlS, Nxtra, Yotta, Equinix and others) |
| government data-centre census | 32 (32) | NIC/NICSI national data centres, UIDAI, ISRO, CRIS (railways), and the State Data Centres of 21 states and union territories |
| operator, company, government or press record | 29 (16) | Sites missing from the directory that were found during the cross-check against the Atlas of Data Center Politics: 26 are listed in the Atlas; IN306 (CtrlS Rambilli) and IN325-IN326 (Yotta TB1, TB2) were found on the press and operator pages consulted for it and have no Atlas record. Each rests on the cited primary source, not on the Atlas |

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
  are not duplicates. A suite's load apportioned from a company-wide figure (ESDS, 2.12 MW, tier T4) may overstate it.
- **`facility_id` is stable.**
  - IDs run from IN001 to IN360.
  - Gaps are merged or dropped rows (29 in all, 11 of them dropped in the October review); `correction_applied` records each correction.
- **Status:**
  - `operating`: 233 rows in 61 districts. The paper's main results use these. A row is operating only
    with dated evidence of go-live, inauguration or operational capacity on or before 30 September 2026.
  - `under construction`: 60 rows.
  - `announced (planned)`: 36 rows.
  - The pipeline scenario covers all 329 facilities in 66 districts.
- **Location:** `latitude` and `longitude` give the site geocode used to assign the district (WGS84 decimal
  degrees), with city, district and state. `location_precision` says what the point is: the building (66 rows),
  a campus or IT park (126), a named locality (105), or a city placeholder (32).
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

Every row has a `source_url`. 283 rows (189 operating) also have a second source (`source_url_2`); for 49
directory-only rows that second source (another listing site, a general company page or PeeringDB) does not
independently document the facility.

### Source types: listing sites are not evidence

`source_type` and `source_type_2` classify each cited page. Listing and aggregator sites (Data Center Map, Baxtel,
Ocolo, Datacenterhawk, Cloudscene, IndiaMART and similar; `source_type` = `directory`) copy one another and state no
basis, so since 21 October 2026 they are **not counted as independent evidence** that a facility exists or operates,
and a capacity figure that appears only on a listing site is **never used** (it may be listed in
`mw_published_figures`). A row whose only support is such listings is `directory_only`.

`source_verification` records how each row is supported:

| Value | Rows | Meaning |
|---|---|---|
| `confirmed` | 211 | Facility documented by a source independent of the listing sites, and a second source is listed |
| `partial` | 21 | Listed in the directory; the operator confirms a data centre in that city but not this exact building |
| `directory_only` | 85 | Listed on listing sites only; no independent source found |
| `single_source` | 12 | One independent source only (an operator, government, PeeringDB or press page), not the directory |

Of the 202 directory rows, 96 are confirmed, 21 partial and 85 directory-only. All directory-only rows are kept,
as directory listings, and rated low confidence.

### Confidence

**`confidence`** (high 176, medium 34, low 119; operating rows 119, 29, 85) summarises this for each row:

- **high:** confirmed by a source independent of the directory, with a second source and no open issue;
- **low:** directory listing only (no independent trace), or an open question about whether the site exists or
  operates as recorded (`[existence]` or `[status]` in `open_issue`);
- **medium:** everything else (confirmed with an open capacity, source or duplicate question; partial; single source).

**`confidence_note`** says in plain language what is uncertain for that row.

### Verification history

1. **30 September 2026, first build.** Every source was re-found and read; 145 directory rows were checked against
   the operator's site, PeeringDB or the press, and every other row was double-checked against its cited pages.
2. **21 October 2026.** Listing sites were judged not to be independent evidence, and rows resting only on them
   were reclassified `directory_only`; shared-building geocodes and India-only pages were checked (batch 6).
3. **22-25 October 2026, row-by-row source review of all 340 rows** (flagged rows on 24 October, batch 7; the rest
   on 25 October, batch 8). 11 rows were removed (8 hosting resellers or offices, 3 second rows for one building);
   status was corrected for 16 rows (for example AdaniConneX Noida and Pune, NTT Navi Mumbai 2 and Sify Lucknow were
   found operating before the cutoff; Sify Bengaluru 02 is not operating); published capacities were added or corrected.
4. **26 October 2026, independent adversarial re-check of all 329 rows.** Reviewers saw each row without the earlier
   verdicts and tried to fault it: 241 rows drew no fault and 88 a challenge; accepted challenges were corrected in
   batch 9, together with the tiered capacity method (below).
5. **What remains open.** 75 rows (54 of them operating, carrying 237.3 MW of the operating allocation and 11.7% of
   the attributable SO2) can be neither confirmed nor refuted from public sources. Each carries an open issue naming the
   evidence that would settle it and is rated low confidence; they are listed in
   `data/public/unresolved_facilities_20261025.csv` of the analysis repository, and the paper's `unresolved_zero`
   sensitivity run sets their load to zero.

### Evidence stores

`source_url_archive` and `source_url_2_archive` give archived copies, from the Internet Archive or (for sites that
refuse it) archive.today, filled by `scripts/25_archive_sources.py`. All 329 facilities have an archived primary
source, and 529 of the 530 URLs cited in the table have a copy (408 Internet Archive, 121 archive.today); across all
the analysis repository's data files, 641 of 649 cited URLs have one. Of the 234 cited Data Center Map pages, 154 are in
the Internet Archive; the other 80, and 4 IndiaMART pages, which the Internet Archive refused, were archived on
archive.today by hand by 10 October 2026. Some pages are reachable only from Indian networks; a co-author in India
checked them on 20-22 October 2026. Where a page could not be archived, the authors hold a dated copy: the WTL page cited
for IN360 (the one table URL without an archive), the OCAC page for IN353, the Lok Sabha answer for IN347, the Anant Raj
NSE investor presentation (10 November 2025) and the L&T FY2026 annual report among them. These author-held snapshots are
listed with their dates and SHA-256 hashes in `data/public/source_snapshots.csv`; the files themselves are kept outside
the public repository and are available from the authors. `source_note` records this for each row.
`sources_and_archives.csv` in the downloadable bundle lists every cited URL with its archived copy, snapshot date and status.

## Other columns

| Column | Meaning |
|---|---|
| `facility_type` | Operator class used for the class weight: colocation, hyperscale, enterprise, government or telecom |
| `opened_year` | Year the facility opened, where a source gives it (blank otherwise) |
| `mw_flag` | Why the published capacity is uncertain (conflicting figures, unclear measure); blank if none |
| `source_title`, `source_type`, `source_title_2`, `source_type_2` | Title and kind of each cited source. `source_type` is one of: `directory` (Data Center Map, Baxtel, Ocolo, Datacenterhawk, Cloudscene, IndiaMART and similar listings; not independent evidence), `peeringdb`, `operator` (the operator's own site or report), `government` (incl. parliamentary answers), `press`, `press release`, `certification registry` (Uptime Institute) or `contractor or vendor` |
| `url_checked` | Whether the cited page was fetched and read (`fetched`) or seen only as a search result (`search_result`) |
| `status_in_source`, `status_agrees_with_inventory` | The status the cited source gives, and whether it matches the row's status (blank where the source gives none or the comparison is ambiguous) |
| `sources_retrieved` | Date the sources were retrieved (30 September 2026) and the dates each row was re-checked in October 2026 |
| `adp_match`, `adp_campus_name`, `adp_status`, `adp_stage`, `adp_size_bucket`, `adp_source_urls` | The cross-check against the Atlas of Data Center Politics: how the row was matched (or `none`), and the Atlas's campus name, status, stage, size class and source links. The Atlas is a cross-check only, never a source of rows |
| `inventory_version` | Inventory release date (2026-09-30) |

## Capacity: what the MW numbers are

Each facility's IT capacity is set by one fixed, tiered method (26 October 2026; `CAPACITY_METHOD.md` in the analysis
repository's `data/public/`). Only admissible sources count: operator pages and fact sheets, filings, annual reports,
investor presentations, rating rationales, government pages and tenders, and dated reputable trade press. Listing-site
figures are never used. Where admissible sources disagree, a figure for the facility beats one for the operator or
campus, a dated source beats an undated one (and a later one an earlier one, up to the 30 September 2026 cutoff), a fact
sheet beats running prose, and operator or filing beats press; a remaining conflict keeps the existing figure and is
recorded in `mw_flag`. The first tier with an admissible figure is used:

| Tier | What is published | How the IT load is set |
|---|---|---|
| T1 | Live IT load for this facility | Used as published |
| T2 | Live "operational capacity", "capacity" or MVA, basis not stated | Used as IT load (1 MVA = 1 MW) |
| T3 | Total facility or utility power for this facility | Total power / 1.6 (the paper's PUE) |
| T4 | A company-wide or campus-wide figure | Facilities with their own figure keep it; the rest is shared equally among the operator's other operating facilities |
| T5 | Rack count only (government and NIC data centres) | Racks x 4 kW (installed racks where published, otherwise design racks) |
| T6 | Nothing admissible | Class-weight imputation (below) |

- **`mw_basis` starts with the tier.** For every operating row with a published capacity, the current-figure entry
  of `mw_basis` begins with its tier and source (for example `T1: STT GDC India Mumbai 2 fact sheet (May 2025): IT
  Load Capacity 1.7 MW`, or `current 19.2 MW: T2: Adani Q1 FY27 release ...`), followed by the build-out entry where one exists.
- **Two published-load columns:** `mw_it_reported_current` and `mw_it_reported_buildout` hold the IT load set by
  tiers T1-T5, current and at full build-out.
  - 123 operating facilities have a current capacity used directly, totalling 1,383.2 MW: 93 an IT load as
    published (T1) and 30 derived (T2 13, T3 6, T4 3, T5 8; T5 uses installed racks for 3 and design capacity for 5).
  - 165 rows have a published load of some kind.
  - "Potential", master-plan and campus-ambition figures, investment sums and listing-site figures are listed in
    `mw_published_figures` but not used.
- **`mw_certainty`** gives the status of the power figure for each row: reported IT load (106 rows; 74 operating),
  reported but uncertain (57; 49 operating: every T2-T5 row, and T1 rows with a capacity flag or open issue), or not
  published, so modelled (166; 110 operating).
- **`mw_note`** says what the figure is, and why it is uncertain where it is.
- **`mw_it_used_in_paper`** is the IT capacity each operating facility carries in the central case.
  - Published (T1-T5) loads are held fixed.
  - Commercial facilities (colocation and hyperscale) without one (T6) are anchored to 1,800 MW of national
    commercial IT capacity (Savills, H1 2026), shared out by class weight: hyperscale 10, colocation 3.
  - Enterprise (1), government (1) and telecom (0.5) facilities use the same MW per weight unit
    (3.91 MW), without rescaling to a national total.
  - The column sums to 2,051 MW.
- **`mw_method`** says, row by row, how the MW figure that matters for the row was set (the paper's figure for an
  operating row, the scenario figure for a planned one), with the arithmetic:
  - `reported`: a published capacity (tiers T1-T5) is used; `mw_basis` gives the tier and any conversion;
  - `modelled`: no published IT load (T6), so class weight x MW per weight unit, e.g. "colocation weight 3 x 3.91 MW per
    weight unit = 11.72 MW". The 3.91 MW is set so that the commercial facilities (colocation and hyperscale) sum to
    the 1,800 MW anchor: (1,800 - 1,374.1 MW published by 114 commercial facilities) / 109 weight units held by the
    20 commercial facilities without a published load. Non-commercial facilities take the same 3.91 MW per unit;
  - `not sized`: the 18 operating directory listings that could not be confirmed as separate buildings with their own load
    carry 0 MW (three of them, IN014, IN127 and IN272, are confirmed or partly confirmed facilities whose listings are not confirmed as separate buildings with their own load; IN127 is a suite in the Boomerang complex).
  The app's Facilities tab walks through this calculation step by step.
- **`class_weight`** is the weight used for the row (hyperscale 10, colocation 3, enterprise 1, government 1,
  telecom 0.5; 0 for a row that is not sized).
- **`mw_it_used_in_pipeline_scenario`** sizes all 329 facilities. It uses published build-outs where
  they exist, the current published load where only that exists, and today's MW per weight unit otherwise.
  - It sums to 8,114 MW (8,114.4 if the column, rounded to 0.001 MW per row, is added up). This is a scenario, not an estimate.
  - Counting the 56 planned sites with no published load (modelled) as zero gives a lower bound of 6,848 MW.

**Modelled capacities are allocations, not measurements.**

## Corrections (see `correction_applied` and `correction_evidence`)

Every correction made during verification is listed in `correction_applied` (field, old value, new value and reason) with its
evidence URL in `correction_evidence`; 168 rows of the table carry one. The analysis repository's
`inventory_corrections_v2.csv` has 339 correction rows (29 removals and 310 field edits on 170 facilities), made in nine batches:

1. The first source pass.
2. Duplicates; operator statuses and IT loads (Nxtra, STT, NTT, Sify, Yotta, CtrlS); district fixes.
3. The independent check of the directory rows: types (AirTrunk, ESR, L&T, Digital Connexion and others
   are colocation), statuses (Nxtra Kolkata live, Google Rambilli under construction), towns, and merged
   duplicates.
4. The double-check of the other rows: NTT, STT and CtrlS IT loads; Nxtra Mahape 2 and CtrlS Patna DC2
   are live; Sify Bengaluru 02's 22 MW is design capacity.
5. 19 October 2026: Iron Mountain HYD-1 current IT load set to the operator's own figure (5.7 MW; the directory and
   trade press give 5.5 MW).
6. 21 October 2026: final checks of statuses and capacities (for example Digital Edge BOM1 operating; CtrlS Bhubaneswar
   under construction; capacity figures not labelled as IT load withdrawn).
7. 24 October 2026: the row-by-row review of flagged rows (statuses, published capacities, 6 removals).
8. 25 October 2026: the row-by-row review of the remaining rows (build-out loads, types, statuses, 5 removals).
9. 26 October 2026: the adversarial re-check and the tiered capacity method (T1-T5 figures and their conversions).

## Open issues (`open_issue`)

Open issues are flagged, not resolved; `confidence_note` gives them for each row. There are 109 on 104 rows
(status 58, existence 27, capacity 15, source 5, possible duplicate 4); 75 of these rows are the unresolved facilities
described above. They include:

- Data Center Map listings with no independent trace;
- status questions: Reliance IDC sites (operator insolvent), AWS TTC, Digital Connexion BOM10, Nxtra
  Hyderabad, Sify Lucknow, CtrlS Bhubaneswar, the Karnataka SDC;
- capacity figures that sources disagree on or do not label as IT load;
- possible overlaps between AWS Hyderabad buildings, between AWS Mumbai MIDC and TTC, and between ESR Rabale and Sify Rabale.

## Updating, citing, licence

- **Report an error or a missing facility:** use the app's *Submit a data centre* tab, or open an issue on
  the repository.
- **Release:** snapshot of 30 September 2026, re-verified 21-26 October 2026. Sources were re-found and archived,
  every row was reviewed against its sources and then re-checked independently, listing sites were set aside as
  evidence, capacities were set by one tiered method, government data centres and confidence ratings added, and every
  correction documented. Only this version is released.
- **Cite as:** deSouza, P. et al. (2026). India data-centre inventory (public facility table), version
  2026-09-30. https://github.com/pdez90/india-datacentre-ej
- **Licence:** [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/). The licence covers our
  compilation and annotations. Facility facts remain those of the cited sources, including Data Center
  Map.
