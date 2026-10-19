# India Data Centre Environmental Justice Explorer

Interactive companion to *"The Environmental Geography of Data Centers in India."*

For more information contact Dr Priyanka deSouza (<priyanka.desouza@ucdenver.edu>).

An India map of the country's data centres over the 641 Census 2011 districts, where the district layer
can be switched between 28 social, environmental and energy indicators, including the
modelled PM2.5 increment produced by the sector's own electricity demand. The point of the
app is that the two layers can be read against each other: the facilities sit in one
geography, the pollution their electricity causes appears in another. A State policies tab
tracks the state incentive policies that are steering the build-out, and two forms let
readers submit data centres and policies we have missed.

## Run it locally

```r
install.packages(c("shiny", "bslib", "leaflet", "sf", "dplyr", "DT", "jsonlite"))
shiny::runApp()
```

## What's in the app

**Two scopes, as in the paper.** The *operating inventory* (246 facilities in 61
districts; inventory of 30 September 2026) is the basis of every result in the paper.
The *stock-plus-pipeline* scenario adds the 56 under-construction and 38 announced facilities
(340 in all, 66 districts), sized at their reported build-out loads or the operating allocation. The sidebar switch changes the facility
points, the value boxes, the district count layer and the PM2.5 increment layer together;
the Scope 1 / Scope 2 chain layers are for the operating inventory. Pipeline facilities are
drawn with a dark outline (dashed for announced) and lighter fill.

**Who benefits, who bears.** The distributional comparison the paper is about, for the scope
chosen in the sidebar: hosting districts versus the districts that receive the pollution (shares of
facilities, population, person-ug exposure and modelled deaths; population-weighted increment,
baseline PM2.5, wealth, urban, SC/ST and BPL shares, coal capacity); siting and exposure by
population-weighted district wealth quintile (facilities, per-capita increment and absolute deaths,
which rank the quintiles differently); the paper's group contrasts (SI Tables S6.2 and S4.1.1) with
siting and burden side by side; the zonal table; and the state policies against the burden
geography. District sums are computed in the app from `districts.geojson`; the contrasts are read
verbatim from `data/ej_panel.json`. Every quantity on the tab follows the scope switch (the siting
contrasts are computed for both inventories by `scripts/20a_disparity.R`), and each section opens
with a one-paragraph reading generated from the numbers shown: descriptive, never causal, and
explicit when the bootstrap leaves a contrast undecided.

**Air-quality model.** A step-by-step walk from electricity to health, with every number: electricity per
state, marginal emissions per state (Sengupta et al. 2022), the split of each state's emissions between coal and
gas plants and among plants by capacity (pick a state and pollutant), what InMAP does and the make-up of the
increment, the cut of the InMAP grid into district pieces (pick a district and press play), and the GEMM
calculation of deaths for that district. Each step is recomputed in the app from its own data and checked
against the headline numbers by `tests/check_app_data.R`.

**Follow the electricity.** A four-step guided walk (demand, emissions, exposure, governance) that
sets the map for each step and leaves a one-line reading with Next / Back above the map.

**Find and share.** A search box (facility, operator or district) flies the map to the place; the
district layer picker is grouped into five families; the address bar always carries the current
view (inventory, layer, state, position, tab), so the URL can be copied to share exactly what is
shown. Clicking a facility point opens its documentary record: reported versus allocated capacity
and the basis for it, geocode precision, both sources with their archived copies, verification
and confidence, the Atlas cross-check, and any corrections made during verification.

**Map.** District choropleth plus facility points, optionally with the 321 coal and gas
plants that carry the sector's attributable emissions (hover for each plant's attributable
SO2, NOx and PM2.5) and the screened OpenStreetMap cross-check (black rings). Hovering a
district gives a profile card; hovering a facility gives its type, status, reported and
allocated capacity, electricity, carbon and both water terms.

**The Scope 1 / Scope 2 chain.** Six layers trace one footprint across three geographies:
Scope 1 on-site cooling water and backup-diesel NOx in the hosting districts (diesel from
measured district supply interruptions, `scripts/29_backup_diesel.R`); Scope 2 SO2,
NOx and PM2.5 mapped where they are physically released, at the plants; and the modelled
PM2.5 increment where the concentration settles. Scope 2 *water* is charged to the consuming
district rather than mapped to its source, because more than a third of it (about 37%) is hydropower
reservoir evaporation and only the coal and gas fleet is geolocated; it uses average grid
water intensities and is an upper estimate.

**District layers.** Data-centre count · PM2.5 increment from data centres (log scale; also operating only, stock plus pipeline, and the increment added by the pipeline) ·
Scope 1/2 chain (six layers) · ambient PM2.5 · surface NO2 · summer ozone · extreme-heat
days · NFHS asset wealth (district percentile) · Relative Wealth Index (Chi et al. 2022) ·
urban share · SC/ST share · below-poverty-line share · Muslim share · no-electricity share ·
coal capacity · distance to nearest fossil plant · baseline water stress · power interruptions (ESMI; all monitors and urban monitors) · population.

**Value boxes with context.** Facilities shown, allocated IT capacity, electricity and CO2
for the current selection, each with a context line: districts covered; facility load (IT load
x PUE 1.6) as a share of India's peak demand in FY2025-26 (242.49 GW, CEA); electricity as
a share of national generation (1,826 TWh, CEA FY2024-25) and as the average annual use of N
million Indians (1,460 kWh per capita, CEA FY2024-25); CO2 as a share of India's fossil CO2
(about 3.0 Gt, Global Carbon Budget 2024). The constants and their sources live in
`data/headline.json`.

**Modelled exposure for both scopes.** Three InMAP layers: the operating field, the
stock-plus-pipeline field and the increment the pipeline adds; the legend of each carries the
population-weighted mean, the population above 0.01 ug/m3 and GEMM attributable deaths for that
scope (district-mean population-weighted increment: operating 0.0603 ug/m3, ~2,078 deaths/yr;
stock plus pipeline 0.1636 ug/m3, ~5,649). These are modelled, scenario-consistent estimates
(GEMM concentration-response function applied to the InMAP increment), not observed mortality.

**Power interruptions.** A tab with measured grid-supply interruption hours for the 79
districts that have Prayas ESMI voltage monitors (2014-2019), with a table and CSV downloads
(district and monitor level); two map layers show the same values.

**Filters.** Scope, state and facility type (hyperscale, colocation, telecom, enterprise, government). All four value boxes and both tables respond.
The facility-type filter applies to the points, the value boxes, the *Data centres (count)*
layer and the district table's count; every other district layer, including the PM2.5
increment, is an all-type aggregate (it cannot be recomputed from facility rows) and is
labelled as such in the sidebar. On log-scaled layers, districts with a true zero are drawn
grey rather than as a tiny positive value.

**Tables.** District and facility tables with column filters and CSV/Excel export.

**State policies.** The 18-state compilation of data-centre incentive policies (dedicated
policy and year; capital subsidy, stamp-duty and electricity-duty exemptions, land
incentive, single-window clearance, environmental-assessment requirement) joined to each
state's facility counts and the water stress and pollution of its hosting districts, and a
second table with the source, verbatim passage and retrieval date behind every cell.

**Submit a data centre / Submit a policy.** Two Google Forms, embedded. See *Setting up
the submission forms* below.

## Data provenance

Everything in `data/` is written by the analysis repository's scripts from the pipeline's outputs
(`scripts/22_build_shiny_data.py`, with `30_app_download_tables.R` for the backup-diesel and
emission-factor tables and `22b_inmap_grid.R` for `inmap_grid.rds`), so the app has no runtime dependency on the
pipeline and the numbers in the interface cannot drift from the paper's tables.

| File | Rows | Source |
|---|---|---|
| `data/districts.geojson` | 641 | Census 2011 district geography (joined to the NFHS-5 district identifiers; `scripts/00a_districts.R`) joined to the analysis layer (`analysis_district.csv`, both scopes' counts), the InMAP receiving field and GEMM deaths (`tab16_inmap_district.csv`, both scopes), the InMAP source field aggregated to plant districts (`tab16b_emissions_points.csv`), facility Scope 1 and Scope 2 water (`tab15_facilities.csv`); geometry simplified to 0.004° (about 400 m) |
| `data/facilities.geojson` | 340 | `dc_current_inventory.csv` (stock plus pipeline) with `facility_id`, status, reported IT load and site geocodes (unrounded; precision class in the public table); operating-scope allocations (`mw_it`, `e_fac_gwh`, `co2_kt`, `scope1_ml`, `scope2_ml`) for the 246 operating facilities and build-out allocations (`*_all`) for all 340, from `tab15_facilities.csv` in each scope |
| `data/plants.geojson` | 321 | WRI Global Power Plant Database coal and gas plants that receive an allocation of the sector's marginal emissions, with the attributable tonnes for both scopes (`tab16b_emissions_points.csv`; `*_all` = stock plus pipeline) |
| `data/osm_check.geojson` | 20 | OpenStreetMap cross-check: Overpass `telecom=data_center` + `building=data_center`, screened to records identifiable as data centres and to the study geography (50-km tolerance) |
| `data/policies.csv` | 18 | `tab14_policy_burden.csv`: policy compilation joined to hosting-district burden, both scopes' facility counts |
| `data/policy_sources.csv` | 140 | `data/state_dc_policies_sources.csv`: one row per state × claim with URL, verbatim passage and retrieval date |
| `data/ej_panel.json` | – | the paper's distributional tables, verbatim: `tab20b_inmap_disparity_national.csv` (both scopes), `tab20a_disparity_national.csv` (siting and baseline-exposure contrasts, both scopes), `tab20a_group_exposure_S61.csv`, `tab1_dc_vs_nodc_profile.csv`, `tab16_receiving_profile.csv`, `tab20b_inmap_regional.csv` |
| `data/headline.json` | – | the numbers the interface text quotes (facility and district counts, anchors, TWh, CO2, kt, diesel share, policy counts), taken from `tab15_national.csv`, `tab15b_marginal_totals.csv`, `tab16b_emissions_points.csv`, `tab16_inmap_summary.txt`, `tab29_diesel_scenarios.csv` and `tab14_policy_burden.csv` |
| `data/india_datacentres_public.csv` | 340 | the sourced facility table (`scripts/24_public_inventory.R`); data dictionary in `DATA.md` |
| `data/district_power_interruptions.csv` | 79 | `tab28_esmi_district_outages.csv` (`scripts/28_esmi_outages.py`): supply-interruption hours per year (minutes below 80 V, 2014-2019) from the Prayas ESMI monitors, per Census 2011 district, for all, urban and rural monitors; offered for download on the *Power interruptions* tab. Source: Prayas (Energy Group), ESMI, doi:10.7910/DVN/CLLZZM (non-commercial use with acknowledgement) |
| `data/esmi_monitor_power_interruptions.csv` | 528 | the same, monitor by monitor (`esmi_monitor_outages.csv`) |
| `data/power_interruptions_backup_diesel.csv` | 62 | one row per hosting district: its ESMI monitors and measured hours, the outage-hour value the backup-diesel model used and why, and the resulting generator hours; plus one total row whose notes give the scenario range (`scripts/30_app_download_tables.R`, from `tab29_*`); README alongside |
| `data/emission_factors.csv` | 169 | every emission and water factor used, one row per factor and level, with unit, source, how it is used and the script (`scripts/30_app_download_tables.R`); README alongside |
| `data/inmap_grid.rds` | 36,164 cells | the operating-scope InMAP field behind the *Air-quality model* tab: one row per grid cell touching a district (lon/lat box, gridded population, increment by species) and one per cell-district piece (`scripts/22b_inmap_grid.R`, which checks that the pieces reproduce `tab16_inmap_district.csv`) |
| `data/india_datacentres_documented.zip` | – | the download offered on the Facilities tab: the facility table, `DATA.md`, `sources_and_archives.csv` (every cited URL, the facilities citing it, its archived copy and snapshot date), the backup-diesel and emission-factor tables with their READMEs, and a README with licence and citation |

**How the inventory is built.** The backbone is the Data Center Map directory, whose India
listing is read entry by entry for status and reported IT load (213 rows). Three other kinds of
record add facilities the directory misses: operators' own published facility lists (66 rows),
a census of government data centres (32 rows) and operator, company, government or press
records for sites found during the cross-check (29 rows). The Atlas of Data Center Politics
and a screened OpenStreetMap query are cross-checks only. `DATA.md` documents every step.

**What the capacity numbers are.** Only a minority of facilities disclose IT load. Reported
loads are held fixed; the rest is allocated by operator class (telecom 0.5, enterprise and
government 1, colocation 3, hyperscale 10) and the commercial subset is scaled to a national
anchor of 1,800 MW of commercial IT load (2,059 MW across the operating inventory). The
pipeline scenario keeps that per-weight allocation and uses published build-out loads where
they exist, and current published loads where only those exist (6,302 MW). An individual facility's megawatts are an allocation, not a
measurement; state and national aggregates are the meaningful quantities. The CO2 value
box uses the average grid factor (the paper's scenario-table value); the paper's headline
uses state marginal factors. Both appear on the About tab.

## The submission forms

Submissions are collected with two Google Forms created by `create_forms.gs` (responses land in
the Sheets "India DC inventory – facility submissions" and "India DC policy tracker –
submissions"), so no credentials live in the app:

- **India data centre inventory – submit a facility** — new facility or correction, name/operator,
  address or best location, capacity if known, status, how the submitter found it, source link(s),
  optional name and email.
- **India data centre policy tracker – submit a policy** — state (dropdown), policy name and year,
  link to the notification or official summary (required), incentives offered, whether an
  environmental assessment or water/energy conditions apply, notes, optional name and email.

Their embed URLs are the defaults of `FORM_DC_URL` / `FORM_POLICY_URL` at the top of `app.R`;
setting either as an environment variable on Connect Cloud overrides the default. New entries are
checked against the source they cite before they enter the inventory (`data/public/inventory_additions_v2.csv` or
`inventory_corrections_v2.csv`) or `data/state_dc_policies.csv` in the analysis repository; nothing changes the map automatically.

## Checks

`Rscript tests/check_app_data.R` (from the app folder) verifies the data contract and smoke-runs
the server: required columns in every file, 641 valid district geometries with unique keys, the README's headline numbers against `headline.json`,
facility statuses and `is_operating` in agreement, district counts summing to the facility
counts, MW/TWh totals and policy counts agreeing with `headline.json`, only http(s) URLs in the
policy sources, no HTML markup in name fields, and that the scope and type filters keep the
count layer and the value boxes consistent. Run it after every `22_build_shiny_data.py`; GitHub
Actions (`.github/workflows/check-app-data.yml`) runs the same script on every push or pull
request that touches `app.R`, `data/` or `tests/`.

Every data-derived string that reaches the browser (facility, operator, district, plant and
OSM names; policy sources) is HTML-escaped; in the policy-source table only the generated
Link column is rendered as HTML, and only `http(s)://` URLs become links.

## Publishing it

**Posit Connect Cloud** is the target. It deploys from this public GitHub repository.

1. `manifest.json` pins the R version and package versions, and Connect Cloud rebuilds the
   environment from it. Regenerate it (`rsconnect::writeManifest()` inside the app folder)
   only when a package is added, and **keep `terra` pinned at 1.8-54 from Posit Package
   Manager** — a freshly captured manifest records whatever terra the Mac has (1.9-x), which
   does not build against Connect Cloud's GDAL 3.4.1 and fails the publish. terra enters only
   through leaflet → raster.
2. Sign in at connect.posit.cloud, open the application, and republish from the branch (or
   Publish → Shiny → pick the repo and branch, `app.R` as the primary file, for a first
   deployment). Build logs stream live.
3. The two Google Forms are embedded by default; override with the `FORM_DC_URL` /
   `FORM_POLICY_URL` environment variables only if the forms are ever replaced.

The `data/` folder is committed with the app, so there is no runtime dependency on the
analysis pipeline.

### For the paper

Archive the repository to Zenodo to mint a DOI, cite that DOI in the data-availability
statement, and give the live Connect Cloud URL as the interactive companion. If the hosted
app ever lapses, the DOI still resolves to a runnable copy.

## Caveats carried into the interface

These are stated in the app's About tab as well, because a map invites over-reading:

- Facility points are the site geocodes, graded building / campus / locality / city
  placeholder in the public table (35 of 340 rest on a city placeholder, so their point is the
  city, not the building).
- Most facilities do not disclose capacity; it is allocated by operator class and scaled to
  a national anchor.
- The pipeline scenario counts announcements; not all of them will be built.
- District values are Census 2011 district totals or averages and hide within-district variation.
  Districts created after 2011 are not split out; Telangana's districts are labelled under
  Telangana although the 2011 geography predates the state.
- The PM2.5 increment is modelled, scenario-consistent, and cannot be attributed to any
  individual facility.
- OpenStreetMap is a coverage check only and enters no total.
