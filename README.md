# India Data Centre Environmental Justice Explorer

Interactive companion to *"Data centers in India locate in affluent districts while
their environmental impacts extend through shared regional systems."*

An India map with 373 data centres over 642 districts, where the district layer can be
switched between 17 social, environmental and energy indicators — including the modelled
PM2.5 increment produced by the sector's own electricity demand. The point of the app is
that the two layers can be read against each other: the facilities sit in one geography,
the pollution their electricity causes appears in another.

## Run it locally

```r
install.packages(c("shiny", "bslib", "leaflet", "sf", "dplyr", "DT"))
shiny::runApp()
```

## Publishing it

**Posit Connect Cloud** is the right target as of 2026. Posit is migrating shinyapps.io
into Connect Cloud — a self-migration tool arrives September 2026 and automatic migration
begins early 2027 — so publishing to Connect Cloud now avoids being moved later. The free
plan allows 5 applications with 4 GB RAM and 1 CPU, against 1 GB and a 25-active-hour
monthly cap on the old shinyapps.io free plan. Connect Cloud deploys from a public GitHub
repository.

1. Put this folder in its own public GitHub repo (`app.R`, `README.md`, `data/`). Keep it
   separate from the analysis repo, which is far too large to deploy.
2. Generate the dependency manifest from inside the app folder:

   ```r
   install.packages("rsconnect")
   rsconnect::writeManifest()
   ```

   Commit the resulting `manifest.json`. It pins the R version and package versions, and
   Connect Cloud rebuilds the environment from it.
3. Sign in at connect.posit.cloud, click Publish, choose Shiny, pick the repo and branch,
   set `app.R` as the primary file, and publish. Build logs stream live.

The `data/` folder is committed with the app, so there is no runtime dependency on the
analysis pipeline and the whole deployment is about 1.7 MB.

### If you use shinyapps.io instead

Still works, and existing URLs will keep redirecting after migration, but the free tier
gives 25 active hours per month with a 15-minute idle timeout, no password protection, and
a "Powered by RStudio" badge. Twenty-five hours is not much for a paper companion: a single
sustained burst of readers can exhaust it, after which the app goes offline until the next
month.

```r
install.packages("rsconnect")
rsconnect::setAccountInfo(name = "<account>", token = "<token>", secret = "<secret>")
rsconnect::deployApp(appName = "india-datacentre-ej")
```

### For the paper

Journal reviewers and readers need a link that does not rot. Archive the repo to Zenodo to
mint a DOI, cite that DOI in the data-availability statement, and give the live Connect
Cloud URL as the interactive companion. If the hosted app ever lapses, the DOI still
resolves to a runnable copy.

## What's in the app

**Map.** District choropleth plus facility points, optionally with the 321 coal and gas
plants that carry the sector's attributable emissions and the 19-point OpenStreetMap
cross-check (black rings). Hovering a district gives a profile
card; hovering a facility gives its type, imputed capacity, electricity, carbon
and both water terms.

**District layers.** Data-centre count · PM2.5 increment from data centres (log scale) ·
ambient PM2.5 · surface NO2 · summer ozone · extreme-heat days · NFHS wealth score ·
Relative Wealth Index · urban share · SC/ST share · below-poverty-line share · Muslim
share · no-electricity share · coal capacity · distance to nearest fossil plant · baseline
water stress · population.

**Filters.** State and facility type. All four value boxes and both tables respond.

**Tables.** District and facility tables with column filters and CSV/Excel export.

## Data provenance

| File | Rows | Source |
|---|---|---|
| `data/districts.geojson` | 642 | district geography joined to the analysis layer and the InMAP receiving field; geometry simplified to 0.01° for the browser |
| `data/facilities.geojson` | 373 | 335 India facilities from the open [Global Data Center Map](https://github.com/Ringmast4r/Global-Data-Center-Map) inventory (ATLAS; 342 rows before de-duplication), plus 38 hand-compiled press-verified major campuses (Yotta, AdaniConneX, STT GDC, NTT, CtrlS, Nxtra, Princeton Digital, Sify, GPX/Equinix, AWS, Google), joined to the facility-level footprint accounting |
| `data/plants.geojson` | 321 | WRI Global Power Plant Database, coal and gas only |
| `data/osm_check.geojson` | 19 | OpenStreetMap cross-check layer: Overpass `telecom=data_center` + `building=data_center`, screened to records identifiable as data centres, disputed-territory spillover removed |

The 38 hand-compiled campuses are a tenth of the facility count but about a third of
national IT capacity, because they are the large hyperscale and colocation projects; 31 of
the 38 have no ATLAS counterpart at all. They were found by searching operator press rooms,
state investment-promotion announcements, and the data-center trade press (Data Center
Dynamics, Baxtel, Business Standard, Voice&Data, VARIndia, Digital Infra), with a source
citation recorded for every row.

Only 8 facilities disclose IT capacity (164 MW in total). Everything else is imputed:
each facility gets a class weight (telecom 0.5, enterprise 1, colocation 3, hyperscale
10), and those weights are scaled by a single common factor so the inventory sums to an
assumed national total — the *anchor*. The paper evaluates 750, 1,000 and 1,500 MW; the
app uses the central 1,000 MW anchor, so it reconciles exactly with the paper's central
scenario (9.8 TWh/yr, 7.0 Mt CO2e). Individual facility megawatts are allocations, not
measurements.

## Caveats carried into the interface

These are stated in the app's About tab as well, because a map invites over-reading:

- Coordinates are town-, suburb- or postal-area centroids. Of the 38 press-compiled
  campuses, 21 sit at the locality named in the reporting and 17 at a GeoNames city
  centroid; none is a site-level pin. A point locates a facility in its town, not at its
  site. No sub-district inference is supportable.
- OpenStreetMap is a coverage check only. The raw Overpass extraction returns 238 features,
  but the tags are badly misapplied in India — Kerala Akshaya e-service kiosks, Aadhaar
  enrolment points, computer shops — and only 20 survive screening, 19 after removing a
  Gilgit-Baltistan facility inside the clipping boundary. Those 19 are drawn as a separate
  layer and are counted in no total; nothing in the inventory depends on OSM completeness.
- Most facilities do not disclose capacity. It is imputed by operator class and scaled to
  a national anchor, so individual facility values are allocations, not measurements.
- District values are means and hide within-district variation.
- The PM2.5 increment is modelled, not measured, and cannot be attributed to any
  individual facility.

## Rebuilding the data

The GeoJSON layers are derived from the pipeline outputs (`districts_zones.gpkg`,
`analysis_district.csv`, `tab16_inmap_districts.csv`, `dc_current_inventory.gpkg`,
`tab15_facilities.csv`, `gppd_india.csv`, `dc_osm_points.rds`). Regenerate them after any
pipeline rerun so the app does not drift from the paper. The OSM cross-check layer applies
the same screening rule as `11_inventory_current.R` (`OSM_DC_PAT` / `OSM_KIOSK_PAT`).
