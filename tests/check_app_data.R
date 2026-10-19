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
            "data/osm_check.geojson", "data/policies.csv", "data/policy_sources.csv", "data/headline.json", "data/ej_panel.json"))
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
            "diesel_nox_t", "emis_so2_t", "emis_nox_t", "emis_pm25_t", "deaths", "deaths_all")
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
  chk(all(c("latitude", "longitude") %in% names(pub)) && all(is.finite(pub$latitude) & is.finite(pub$longitude)),
      "public table must carry site coordinates for every row")
  fx <- sf::st_coordinates(f)[match(pub$facility_id, f$facility_id), , drop = FALSE]
  chk(all(abs(fx[, "X"] - pub$longitude) < 1e-6 & abs(fx[, "Y"] - pub$latitude) < 1e-6),
      "facilities.geojson points must equal the public table coordinates")
  chk(abs(sum(pub$mw_it_used_in_paper, na.rm = TRUE) - sum(f$mw_it[f$is_operating])) < 0.5, "public table MW != facilities.geojson operating MW")
  chk(file.exists("data/india_datacentres_documented.zip"), "documented dataset ZIP missing (run scripts/22)")
  if (file.exists("data/india_datacentres_documented.zip"))
    chk(all(c("README.txt", "india_datacentres_public.csv", "DATA.md", "sources_and_archives.csv") %in% unzip("data/india_datacentres_documented.zip", list = TRUE)$Name),
        "documented dataset ZIP is missing a file")
}

# ---- district power interruptions (scripts/28, Prayas ESMI) ---------------------------
chk(file.exists("data/district_power_interruptions.csv") && file.exists("data/esmi_monitor_power_interruptions.csv"), "ESMI interruption files missing")
chk(file.exists("data/power_interruptions_backup_diesel.csv") && file.exists("data/emission_factors.csv"), "download tables from scripts/30 missing")
if (file.exists("data/power_interruptions_backup_diesel.csv")) {
  pd <- read.csv("data/power_interruptions_backup_diesel.csv", stringsAsFactors = FALSE)
  chk(all(c("district", "state", "operating_facilities", "outage_hours_tier", "outage_hours_used_O_d", "diesel_nox_t_central", "notes") %in% names(pd)), "backup-diesel table columns")
  chk(sum(pd$district != "ALL HOSTING DISTRICTS") == H$hosting_districts_operating, "backup-diesel table: one row per hosting district")
  ef <- read.csv("data/emission_factors.csv", stringsAsFactors = FALSE)
  chk(all(c("factor", "category", "applies_to", "level", "value", "unit", "source", "how_used", "script") %in% names(ef)) && nrow(ef) > 100, "emission-factors table columns")
}
if (file.exists("data/district_power_interruptions.csv")) {
  es <- read.csv("data/district_power_interruptions.csv", stringsAsFactors = FALSE)
  chk(all(es$zone_uid %in% d$zone_uid) && !anyDuplicated(es$zone_uid), "ESMI districts not unique / not in the district layer")
  chk(nrow(es) == H$esmi$districts && sum(!is.na(d$esmi_h_yr)) == nrow(es), "ESMI district count != headline / district layer")
  chk(all(es$interruption_h_per_yr >= 0 & es$interruption_h_per_yr <= 8760), "ESMI hours outside 0-8760")
}

# ---- geometry and keys ----------------------------------------------------------
chk(nrow(d) == 641, sprintf("districts: %d rows, expected 641 (Census 2011 polygons joined to NFHS identifiers)", nrow(d)))
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

# ---- README quotes the current headline numbers (the public README must not drift from the app) ---
if (file.exists("README.md")) {
  rd <- paste(readLines("README.md", warn = FALSE), collapse = " ")
  has <- function(x) grepl(x, rd, fixed = TRUE)
  chk(has(sprintf("%d facilities in %d", H$n_operating, H$hosting_districts_operating)) && has(sprintf("%d districts)", H$hosting_districts_all)),
      "README: facility / hosting-district counts differ from headline.json")
  chk(has(sprintf("operating %.4f ug/m3, ~%s deaths/yr", H$inmap_operating$pwm_ugm3, format(H$inmap_operating$deaths_per_yr, big.mark = ","))) &&
      has(sprintf("stock plus pipeline %.4f ug/m3, ~%s", H$inmap_all$pwm_ugm3, format(H$inmap_all$deaths_per_yr, big.mark = ","))),
      "README: InMAP increment / deaths differ from headline.json")
  chk(has("641") && !has("642 districts") && !has("2015 district geography"), "README: district geography text is stale")
}

# ---- HTML trust boundary: no markup in data-derived strings ----------------------
has_tag <- function(x) any(grepl("<[a-zA-Z/!]", x), na.rm = TRUE)
chk(!has_tag(f$name) && !has_tag(f$operator) && !has_tag(d$dist_name) && !has_tag(p$name) && !has_tag(o$label),
    "HTML-like markup in a name field (the app escapes it, but check the source)")

# ---- app parses; server logic runs with the scope/type filters -------------------
chk(!inherits(try(parse("app.R"), silent = TRUE), "try-error"), "app.R does not parse")
chk(!any(grepl("CartoDB|stadiamaps|thunderforest", readLines("app.R"))), "app.R uses a basemap that needs an API key (use the keyless Esri / OSM tiles)")
if (requireNamespace("shiny", quietly = TRUE)) {
  src_app <- readLines("app.R")
  if (!requireNamespace("leaflet", quietly = TRUE)) {
    stub <- 'leafletOutput <- function(...) shiny::div(); renderLeaflet <- function(expr) function() NULL; leafletProxy <- function(...) list(); leaflet <- function(...) list(); leafletOptions <- function(...) NULL; addProviderTiles <- setView <- clearShapes <- clearMarkers <- clearControls <- removeControl <- addMapPane <- addTiles <- addLayersControl <- addScaleBar <- addPolygons <- addLegend <- addCircleMarkers <- clearGroup <- addRectangles <- fitBounds <- addPolylines <- function(m, ...) m; tileOptions <- layersControlOptions <- scaleBarOptions <- function(...) NULL; providers <- list(CartoDB.PositronNoLabels = 1); highlightOptions <- labelFormat <- function(...) NULL; colorNumeric <- function(pal, domain, ...) function(x) rep("#000", length(x))'
    src_app <- sub("^library\\(leaflet\\)$", stub, src_app)
  }
  tf <- tempfile(fileext = ".R"); writeLines(src_app, tf)
  env <- new.env(); suppressPackageStartupMessages(sys.source(tf, envir = env))
  # the step-by-step capacity calculation shown on the Facilities tab reproduces every facility's MW and the total
  chk(env$CAP$max_err < 0.01, "capacity walkthrough: a modelled facility MW is not class weight x MW per weight unit")
  chk(abs(env$CAP$total - H$mw_operating) < 0.5 && abs(env$CAP$vc + sum(env$CAP$tab$mw_mod[env$CAP$tab$type %in% c("hyperscale", "colocation")]) - H$anchor_commercial_mw) < 0.01,
      "capacity walkthrough: totals do not reproduce the headline / anchor")
  if (exists("pub")) chk(all(pub$mw_method[pub$status == "operating" & pub$mw_it_used_in_paper == 0 & is.na(pub$mw_it_reported_current)] %in%
                             grep("^not sized", pub$mw_method, value = TRUE)), "public table: a 0 MW operating row is not labelled 'not sized'")
  # the Air-quality model tab: emissions, plant allocation and deaths recomputed in the app reproduce the paper
  chk(abs(env$AQ$so2 / 1000 - H$so2_kt_operating) < 0.1 && abs(env$AQ$nox / 1000 - H$nox_kt_operating) < 0.1 && abs(env$AQ$pm / 1000 - H$pm25_kt_operating) < 0.1,
      "air-quality tab: state emissions do not reproduce the headline SO2 / NOx / PM2.5")
  chk(abs(env$AQ$gwh / 1000 - H$twh_operating) < 0.1, "air-quality tab: electricity != headline")
  chk(env$AQ$plant_err < 1, "air-quality tab: the plant SO2 allocation does not reproduce plants.geojson")
  chk(abs(env$AQ$deaths_1step - H$inmap_operating$deaths_per_yr) < 5 && abs(env$AQ$deaths_model - H$inmap_operating$deaths_per_yr) < 1,
      "air-quality tab: the GEMM calculation does not reproduce the headline deaths")
  chk(grepl("GEMM", paste(as.character(env$aq_walkthrough()), collapse = "")), "air-quality tab did not render")
  if (!is.null(env$AQG)) {
    pg <- env$AQG$pieces
    dm <- tapply(pg$popw * pg$pm, pg$zone_uid, sum) / tapply(pg$popw, pg$zone_uid, sum)
    chk(max(abs(dm - d$dpm25[match(names(dm), d$zone_uid)]), na.rm = TRUE) < 1e-4, "air-quality tab: grid pieces do not reproduce the district increments")
    chk(abs(sum(pg$deaths) - H$inmap_operating$deaths_per_yr) < 1, "air-quality tab: grid-piece deaths do not reproduce the headline")
  }
  wt <- paste(as.character(env$cap_walkthrough()), collapse = "")
  chk(grepl("weight unit", wt) && grepl(sprintf("%.2f", env$CAP$lam), wt), "capacity walkthrough did not render")
  shiny::testServer(env$server, {
    session$setInputs(scope = "operating", ind = "Data centres (count)", show_fac = TRUE, show_plants = TRUE,
                      show_osm = TRUE, state = "All India", types = TYPES)
    chk(output$vb_n == format(H$n_operating, big.mark = ","), "operating facility count in value box")
    chk(sum(dist_f()$dc_count_sel) == H$n_operating && all(dist_f()$dc_count_sel == dist_f()$dc_count), "district count layer != dc_count with all types")
    session$setInputs(types = "hyperscale")
    chk(sum(dist_f()$dc_count_sel) == as.integer(gsub(",", "", output$vb_n)), "type filter: district count layer != facilities shown")
    # "Who benefits, who bears": the panel's sums reproduce the headline and the paper's tables
    session$setInputs(types = TYPES, tabs = "Map", search = "")
    h <- ej_host(); q <- ej_quint(); m <- ej_disp()
    chk(abs(h$`Attributable deaths (/yr)`[3] - H$inmap_operating$deaths_per_yr) <= 1, "EJ panel: district deaths do not sum to the headline")
    chk(abs(h$`Pop-weighted increment (ug/m3)`[3] - H$inmap_operating$pwm_ugm3) < 5e-4, "EJ panel: all-India increment != headline district mean")
    chk(sum(q$tab$Facilities) + q$excluded_fac == H$n_operating, "EJ panel: quintile facilities do not sum to the operating inventory")
    chk(abs(q$tab$`Pop-weighted increment (ug/m3)`[1] / q$tab$`Pop-weighted increment (ug/m3)`[5] - m$`Increment: ratio`[m$Contrast == "Poorest quintile vs richest"]) < 0.02,
        "EJ panel: app quintile ratio disagrees with 20b's poorest/richest ratio")
    chk(nrow(m) == 10 && all(c("SC/ST vs General", "Rural vs urban") %in% m$Contrast), "EJ panel: disparity table")
    chk(all(c("operating", "all") %in% names(env$EJ$baseline)) && nrow(env$EJ$baseline$all) == 30, "EJ panel: siting contrasts must exist for both scopes")
    s_op <- m$`Siting: ratio, P(hosting)`; session$setInputs(scope = "all"); s_all <- ej_disp()$`Siting: ratio, P(hosting)`
    chk(any(abs(s_op - s_all) > 1e-6), "EJ panel: siting contrasts did not change with the scope switch"); session$setInputs(scope = "operating")
    for (nm in c("ej_interp_host", "ej_interp_quint", "ej_interp_disp")) chk(nchar(paste(as.character(output[[nm]]$html), collapse = "")) > 200, paste("EJ interpretation empty:", nm))
    chk(is.function(STORY[[1]]$text) && nzchar(STORY[[3]]$text()), "guided story text")
    for (xy in list(fac_xy[1, ], dist_xy[1, ])) {   # facility and district rows (named X/Y) through the production helper
      pl <- env$fly_payload(xy[2], xy[1], 9); js <- as.character(jsonlite::toJSON(pl, auto_unbox = TRUE))
      chk(is.null(names(pl$lat)) && is.numeric(pl$lat) && grepl('^\\{"lat":-?[0-9.]+,"lng":-?[0-9.]+,"zoom":9\\}$', js), paste("fly_to payload must serialise as plain numbers:", js))
      chk(pl$lat > 5 && pl$lat < 38 && pl$lng > 65 && pl$lng < 100, "fly_to payload: lat/lng outside India (swapped?)")
    }
    session$setInputs(scope = "all", types = TYPES)
    chk(output$vb_n == format(H$n_all, big.mark = ",") && all(dist_f()$dc_count_sel == dist_f()$dc_count_all), "build-out count layer != dc_count_all")
    session$setInputs(aq_dist = env$AQ$d$zone_uid[1])
    chk(grepl("Deaths a year", paste(as.character(output$aq_health$html), collapse = "")), "air-quality tab: district GEMM calculation did not render")
    for (stt in c("Maharashtra", "Kerala", "Chandigarh")) for (pp in c("SO2", "NOX", "PM2.5")) {
      session$setInputs(aq_state = stt, aq_pol = pp)
      chk(abs(sum(env$aq_alloc(stt, pp)$rows$t) - env$AQ$el[[paste0("t_", pp)]][env$AQ$el$load_state == stt]) < 1e-6, paste("plant allocation does not conserve", stt, pp))
      chk(grepl("t of", paste(as.character(output$aq_alloc_text$html), collapse = "")) && grepl("Plant by plant", paste(as.character(output$aq_alloc_tab$html), collapse = "")), paste("allocation text", stt, pp))
    }
    for (k in 1:4) { session$setInputs(aq_step = k); chk(nchar(paste(as.character(output$aq_grid_text$html), collapse = "")) > 100, paste("air-quality tab: step text", k)) }
    chk(grepl("All the numbers", paste(as.character(output$aq_pieces_tab$html), collapse = "")), "air-quality tab: pieces table did not render")
    # Follow one facility: its plant allocation conserves its emissions; the four step texts render
    fids <- env$facilities$facility_id[env$facilities$is_operating %in% TRUE & env$facilities$mw_it > 0]
    tot <- 0
    for (fid in fids) { session$setInputs(aq_fac = fid); x <- aq_fac(); tot <- tot + x$t[["SO2"]]
      chk(is.null(names(x$xy)) && is.numeric(x$xy) && length(x$xy) == 2, paste("facility coordinates must be plain numbers for Leaflet:", fid))
      chk(abs(sum(x$plants$t) - x$t[["SO2"]]) < 1e-6 && abs(sum(x$plants$t_nox) - x$t[["NOX"]]) < 1e-6, paste("facility allocation does not conserve emissions:", fid)) }
    chk(abs(tot - env$AQ$so2) < 1e-3, "facility emissions do not sum to the sector total")
    for (k in 1:4) { session$setInputs(aq_fstep = k); chk(nchar(paste(as.character(output$aq_fac_text$html), collapse = "")) > 150, paste("facility step text", k)) }
    for (o in c("dtab", "ftab", "ptab", "pstab", "esmitab", if (file.exists("data/india_datacentres_public.csv")) "srctab")) chk(nchar(output[[o]]) > 100, paste(o, "did not render"))
  })
}

if (length(fails)) { cat("FAILED:\n", paste(" -", fails, collapse = "\n"), "\n"); quit(status = 1) }
cat(sprintf("all checks passed: %d districts, %d facilities (%d operating), %d plants, %d OSM points, %d policy states, %d sourced claims\n",
            nrow(d), nrow(f), sum(f$is_operating), nrow(p), nrow(o), nrow(pol), nrow(src)))
