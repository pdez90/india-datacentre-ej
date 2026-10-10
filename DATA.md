# India data-centre facility table: data dictionary and methods

File: `data/india_datacentres_public.csv` has 340 rows, one per facility in the revised
(v2) inventory. This is the inventory the paper analyses.

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
| operator, company, government or press record | 29 (18) | Sites missing from the directory that were first noticed during the cross-check against the Atlas of Data Center Politics. Each rests on the cited primary source, not on the Atlas |

The Atlas of Data Center Politics and OpenStreetMap are used only as cross-checks, never as a
source for a row.

## What a row is

- **A row is one facility as its source lists it.** This is usually one building. A few rows are whole
  campuses, where the operator lists the campus as one entry. The `mw_basis` column says which.
- **Each building is counted once.** When the same building appears twice, the listings are merged.
  For example, 11 old Tata Communications listings are buildings now run by STT, and two tenant suites
  sit inside another operator's building. The merged listing's URL is kept in `source_note`.
- **`facility_id` is stable.**
  - IN001–IN297 come from the original (1 September 2026) inventory.
  - IN298–IN360 were added in this revision.
  - Gaps are merged or dropped rows; see `inventory_corrections_v2.csv`.
- **Status:**
  - `operating`: 246 rows in 52 districts. The paper's main results use these.
  - `under construction`: 56 rows.
  - `announced (planned)`: 38 rows.
  - The pipeline scenario covers all 340 facilities in 57 districts.
- **Location is given at city, district and state level only.** There are no coordinates.
- **District and state use the 2015 NFHS-5 geography,** so that each facility joins the survey data.
  - Hyderabad-area districts sit in Andhra Pradesh; `state_current` gives Telangana.
  - Metro conventions, applied to every row in the same metro:
    - Chennai (including Ambattur, Perungudi, Siruseri) → Kancheepuram;
    - Hyderabad → Rangareddy;
    - Kolkata (including Salt Lake, New Town) → South Twenty Four Parganas;
    - Delhi → North West;
    - Mumbai → Mumbai Suburban;
    - Navi Mumbai → Thane;
    - Panvel and Uran → Raigarh;
    - Bengaluru → Bangalore.
  - The Chennai and Hyderabad districts have no NFHS-5 data in the 2015 frame, which is why they are
    mapped this way.
  - A facility in a separate town is placed in that town's district. Examples: Hoskote → Bangalore
    Rural, Bidadi → Ramanagara, Patancheru → Medak, Cherthala → Alappuzha.

## Sources, confidence and what we are unsure of

Every row has a `source_url`. 286 rows also have an independent `source_url_2`.
`source_url_archive` and `source_url_2_archive` give archived copies, from the Internet Archive or
(for sites that refuse it) archive.today, filled by `scripts/25_archive_sources.py`. All 340
facilities have at least one archived source, and 546 of the 552 cited URLs have a copy. The 76 Data
Center Map pages and 5 IndiaMART pages, which the Internet Archive refuses, were archived on
archive.today by hand on 10 October 2026. The 6 unarchived links are on Indian government servers
and one company site that were unreachable from the archives. `sources_and_archives.csv` in the
downloadable bundle lists every cited URL with its archived copy, snapshot date and status.

- **On 30 September 2026, the 145 Data Center Map rows that had no independent source were each
  checked** against the operator's site, PeeringDB, Baxtel or the press. The other 68 directory rows
  already had one. Of the 145:
  - 82 were confirmed;
  - 41 are likely (the operator confirms a data centre in that city);
  - 22 have no trace beyond the directory listing. These are kept, as directory listings, and rated
    low confidence.
- **Every other row was double-checked** against its cited pages.

`source_verification` records how each row was checked:

| Value | Rows | Meaning |
|---|---|---|
| `confirmed` | 272 | Facility matched on a fetched page, with an independent second source |
| `partial` | 41 | Listed in the directory; the operator confirms a data centre in that city but not this exact building |
| `directory_only` | 22 | Listed in the directory only; no independent source found |
| `single_source` | 5 | One primary source only (the operator's or a government body's own page) |

**`confidence`** (high 241, medium 63, low 36) summarises this for each row:

- **high:** confirmed, with no open issue;
- **low:** no independent trace, or an open question about whether the site operates as recorded;
- **medium:** everything else.

**`confidence_note`** says in plain language what is uncertain for that row.

## Capacity: what the MW numbers are

- **Two published-load columns:** `mw_it_reported_current` and `mw_it_reported_buildout` hold
  published IT loads, current and at full build-out.
  - 96 operating facilities report a current load, totalling 1,246.5 MW.
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
- **`mw_it_used_in_pipeline_scenario`** sizes all 340 facilities. It uses published build-outs where
  they exist and today's MW per weight unit otherwise.
  - It sums to 6,302 MW. This is a scenario, not an estimate.
  - Counting the 75 unsized planned sites as zero gives a lower bound of 5,096 MW.

**Modelled capacities are allocations, not measurements.**

## Revisions in v2 (see `correction_applied` and `correction_evidence`)

Every edit is in `inventory_corrections_v2.csv`, with the old value, new value, reason and evidence URL.
The edits are grouped in four batches:

1. The first source pass.
2. Duplicates; operator statuses and IT loads (Nxtra, STT, NTT, Sify, Yotta, CtrlS); district fixes.
3. The independent check of the directory rows: types (AirTrunk, ESR, L&T, Digital Connexion and others
   are colocation), statuses (Nxtra Kolkata live, Google Rambilli under construction), towns, and merged
   duplicates.
4. The double-check of the other rows: NTT, STT and CtrlS IT loads; Nxtra Mahape 2 and CtrlS Patna DC2
   are live; Sify Bengaluru 02's 22 MW is design capacity.

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
- **Changelog:**
  - 2026-09-30: v2, the first public release. It re-found and archived sources, independently checked
    the directory rows, double-checked the other rows, added government data centres and confidence
    ratings, and documented every edit.
- **Cite as:** de Souza, P. et al. (2026). India data-centre inventory (public facility table), version
  2026-09-30. https://github.com/pdez90/india-datacentre-ej
- **Licence:** [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/). The licence covers our
  compilation and annotations. Facility facts remain those of the cited sources, including Data Center
  Map.
