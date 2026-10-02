# ==============================================================================
# tests/check_app_data.R -- data-contract and smoke checks for the companion app.
# Run from the app folder:   Rscript tests/check_app_data.R
# Exits non-zero on the first failing check. Needs sf, jsonlite, shiny (leaflet
# is stubbed if absent, so the server logic can be exercised without it).
# ==============================================================================
suppressPackageStartupMessages({ library(sf); library(jsonlite) })
fails <- character(0)
chk <- function(ok, msg) { if (!isTRUE(ok)) fails <<- c(fails, msg); invisible(ok) }

# ---- files and columns ---------------------------------------------------------
for (f in c("app.R", "data/districts.geojson", "data/facilities.geojson", "data/plants.geojson",
            "data/osm_check.geojson", "data/policies.csv", "data/policy_sources.csv", "data/headline.json"))
  chk(file.exists(f), paste("missing", f))
if (length(fails)) { cat(fails, sep = "\n"); quit(status = 1) }

d <- st_read("data/districts.geojson",  quiet = TRUE)
f <- st_read("data/facilities.geojson", quiet = TRUE)
p <- st_read("data/plants.geojson",     quiet = TRUE)
o <- st_read("data/osm_check.geojson",  quiet = TRUE)
pol <- read.csv("data/policies.csv", stringsAsFactors = FALSE)
src <- read.csv("data/policy_sources.csv", stringsAsFactors = FALSE)
H <- read_json("data/headline.json")

need_d <- c("zone_uid", "dist_name", "state_name", "dc_count", "dc_count_all", "dpm25", "dpm25_all",
            "pop_2020", "wealth_pct", "rwi_mean", "urban_share_2019", "share_scst_2019", "share_bpl_2019",
            "share_muslim_2019", "share_no_electricity_2019", "pm25_acag_local", "no2_surf", "o3_summer",
            "hot_days_peryr", "coal_mw", "dist_fossil_km", "bws_raw", "s1_water_ml", "s2_water_ml",
            "emis_so2_t", "emis_nox_t", "emis_pm25_t")
chk(all(need_d %in% names(d)), paste("districts.geojson missing:", paste(setdiff(need_d, names(d)), collapse = ", ")))
need_f <- c("name", "operator", "status", "dc_type", "dist_name", "state_name", "is_operating",
            "mw_it", "e_fac_gwh", "co2_kt", "scope1_ml", "scope2_ml",
            "mw_it_all", "e_fac_gwh_all", "co2_kt_all", "scope1_ml_all", "scope2_ml_all", "mw_reported")
chk(all(need_f %in% names(f)), paste("facilities.geojson missing:", paste(setdiff(need_f, names(f)), collapse = ", ")))
chk(all(c("name", "fuel", "capacity_mw", "so2_t", "nox_t", "pm25_t") %in% names(p)), "plants.geojson columns")
chk(all(c("label", "dist_name", "state_name") %in% names(o)), "osm_check.geojson columns")
chk(all(c("state", "policy_name", "policy_year", "has_policy", "dc_count", "dc_count_all") %in% names(pol)), "policies.csv columns")
chk(all(c("state", "claim", "url", "quote") %in% names(src)), "policy_sources.csv columns")

# ---- public sourced facility table (optional; built by scripts/24_public_inventory.R) ----
if (file.exists("data/india_datacentres_public.csv")) {
  pub <- read.csv("data/india_datacentres_public.csv", stringsAsFactors = FALSE)
  chk(nrow(pub) == nrow(f) && sum(pub$status == "operating") == sum(f$is_operating), "public table rows/status != facilities.geojson")
  chk(all(grepl("^https?://", pub$source_url)), "public table: every row needs a source_url")
  chk(!any(c("lon", "lat", "longitude", "latitude") %in% names(pub)), "public table must not carry coordinates")
  chk(abs(sum(pub$mw_it_used_in_paper, na.rm = TRUE) - sum(f$mw_it[f$is_operating])) < 0.5, "public table MW != facilities.geojson operating MW")
  chk(file.exists("data/india_datacentres_documented.zip"), "documented dataset ZIP missing (run scripts/22)")
  if (file.exists("data/india_datacentres_documented.zip"))
    chk(all(c("README.txt", "india_datacentres_public.csv", "DATA.md", "sources_and_archives.csv") %in% unzip("data/india_datacentres_documented.zip", list = TRUE)$Name),
        "documented dataset ZIP is missing a file")
}

# ---- district power interruptions (scripts/28, Prayas ESMI) ---------------------------
chk(file.exists("data/district_power_interruptions.csv") && file.exists("data/esmi_monitor_power_interruptions.csv"), "ESMI interruption files missing")
if (file.exists("data/district_power_interruptions.csv")) {
  es <- read.csv("data/district_power_interruptions.csv", stringsAsFactors = FALSE)
  chk(all(es$zone_uid %in% d$zone_uid) && !anyDuplicated(es$zone_uid), "ESMI districts not unique / not in the district layer")
  chk(nrow(es) == H$esmi$districts && sum(!is.na(d$esmi_h_yr)) == nrow(es), "ESMI district count != headline / district layer")
  chk(all(es$interruption_h_per_yr >= 0 & es$interruption_h_per_yr <= 8760), "ESMI hours outside 0-8760")
}

# ---- geometry and keys ----------------------------------------------------------
chk(nrow(d) == 642, sprintf("districts: %d rows, expected 642", nrow(d)))
chk(!anyDuplicated(d$zone_uid), "duplicate zone_uid")
chk(!anyDuplicated(paste(d$dist_name, d$state_name)), "duplicate (district, state) key")
chk(all(st_is_valid(d)), "invalid district geometries")
chk(all(!st_is_empty(f)), "facility with empty geometry")
TYPES <- c("hyperscale", "colocation", "telecom", "enterprise", "government")
chk(all(f$dc_type %in% TYPES), "unknown facility type")
chk(all(f$status %in% c("operating", "construction", "announced")), "unknown facility status")
chk(all((f$status == "operating") == f$is_operating), "status and is_operating disagree")
chk(all(paste(f$dist_name, f$state_name) %in% paste(d$dist_name, d$state_name)), "facility district not in the district layer")

# ---- counts agree across files and with headline.json ---------------------------
chk(nrow(f) == H$n_all, "facilities != headline n_all")
chk(sum(f$is_operating) == H$n_operating, "operating facilities != headline n_operating")
chk(sum(f$status == "construction") == H$n_construction && sum(f$status == "announced") == H$n_announced, "pipeline counts != headline")
chk(sum(d$dc_count) == H$n_operating && sum(d$dc_count_all) == H$n_all, "district counts do not sum to the facility counts")
chk(sum(d$dc_count > 0) == H$hosting_districts_operating && sum(d$dc_count_all > 0) == H$hosting_districts_all, "hosting-district counts != headline")
agg <- function(v, by) tapply(v, by, length)
op_by_d <- table(paste(f$dist_name, f$state_name)[f$is_operating]); key_d <- paste(d$dist_name, d$state_name)
chk(all(ifelse(key_d %in% names(op_by_d), op_by_d[key_d], 0) == d$dc_count), "dc_count != operating facilities per district")
chk(abs(sum(f$mw_it, na.rm = TRUE) - H$mw_operating) < 1, "operating MW != headline")
chk(abs(sum(f$mw_it_all) - H$mw_all) < 1, "build-out MW != headline")
chk(abs(sum(f$e_fac_gwh, na.rm = TRUE) / 1000 - H$twh_operating) < 0.1, "operating TWh != headline")
chk(all(is.na(f$mw_it[!f$is_operating])), "non-operating facility carries an operating-scope allocation")
chk(all(!is.na(f$mw_it[f$is_operating])), "operating facility without an operating-scope allocation")
chk(all(d$dc_count >= 0 & d$dc_count_all >= d$dc_count), "dc_count_all < dc_count")
chk(all(d$dpm25 >= 0 & d$dpm25_all >= 0, na.rm = TRUE), "negative PM2.5 increment")
chk(nrow(pol) == H$policy_states_reviewed && sum(as.logical(pol$has_policy)) == H$policy_states_dedicated, "policy counts != headline")
chk(sum(pol$dc_count[as.logical(pol$has_policy)]) == H$facilities_in_policy_states, "facilities in policy states != headline")
chk(all(grepl("^https?://", src$url)), "policy source url that is not http(s)")
chk(all(c("pwm_ugm3", "deaths_per_yr") %in% names(H$inmap_operating)) && all(c("pwm_ugm3", "deaths_per_yr") %in% names(H$inmap_all)), "headline inmap blocks")
chk(all(c("gen_total_twh", "per_capita_kwh", "peak_demand_gw", "india_fossil_co2_mt") %in% names(H$context)), "headline context constants")

# ---- HTML trust boundary: no markup in data-derived strings ----------------------
has_tag <- function(x) any(grepl("<[a-zA-Z/!]", x), na.rm = TRUE)
chk(!has_tag(f$name) && !has_tag(f$operator) && !has_tag(d$dist_name) && !has_tag(p$name) && !has_tag(o$label),
    "HTML-like markup in a name field (the app escapes it, but check the source)")

# ---- app parses; server logic runs with the scope/type filters -------------------
chk(!inherits(try(parse("app.R"), silent = TRUE), "try-error"), "app.R does not parse")
if (requireNamespace("shiny", quietly = TRUE)) {
  src_app <- readLines("app.R")
  if (!requireNamespace("leaflet", quietly = TRUE)) {
    stub <- 'leafletOutput <- function(...) shiny::div(); renderLeaflet <- function(expr) function() NULL; leafletProxy <- function(...) list(); leaflet <- function(...) list(); leafletOptions <- function(...) NULL; addProviderTiles <- setView <- clearShapes <- clearMarkers <- clearControls <- addPolygons <- addLegend <- addCircleMarkers <- function(m, ...) m; providers <- list(CartoDB.PositronNoLabels = 1); highlightOptions <- labelFormat <- function(...) NULL; colorNumeric <- function(pal, domain, ...) function(x) rep("#000", length(x))'
    src_app <- sub("^library\\(leaflet\\)$", stub, src_app)
  }
  tf <- tempfile(fileext = ".R"); writeLines(src_app, tf)
  env <- new.env(); suppressPackageStartupMessages(sys.source(tf, envir = env))
  shiny::testServer(env$server, {
    session$setInputs(scope = "operating", ind = "Data centres (count)", show_fac = TRUE, show_plants = TRUE,
                      show_osm = TRUE, state = "All India", types = TYPES)
    chk(output$vb_n == format(H$n_operating, big.mark = ","), "operating facility count in value box")
    chk(sum(dist_f()$dc_count_sel) == H$n_operating && all(dist_f()$dc_count_sel == dist_f()$dc_count), "district count layer != dc_count with all types")
    session$setInputs(types = "hyperscale")
    chk(sum(dist_f()$dc_count_sel) == as.integer(gsub(",", "", output$vb_n)), "type filter: district count layer != facilities shown")
    session$setInputs(scope = "all", types = TYPES)
    chk(output$vb_n == format(H$n_all, big.mark = ",") && all(dist_f()$dc_count_sel == dist_f()$dc_count_all), "build-out count layer != dc_count_all")
    for (o in c("dtab", "ftab", "ptab", "pstab", "esmitab", if (file.exists("data/india_datacentres_public.csv")) "srctab")) chk(nchar(output[[o]]) > 100, paste(o, "did not render"))
  })
}

if (length(fails)) { cat("FAILED:\n", paste(" -", fails, collapse = "\n"), "\n"); quit(status = 1) }
cat(sprintf("all checks passed: %d districts, %d facilities (%d operating), %d plants, %d OSM points, %d policy states, %d sourced claims\n",
            nrow(d), nrow(f), sum(f$is_operating), nrow(p), nrow(o), nrow(pol), nrow(src)))
