# =============================================================================
# India Data Centre Environmental Justice Explorer
# Companion app to: "Data centers in India locate in affluent districts while
# their environmental impacts extend through shared regional systems"
#
# Data in data/ are baked by scripts/22_build_shiny_data.R from the pipeline
# outputs (operating inventory in outputs/, stock-plus-pipeline in outputs_all/).
# Run locally:  shiny::runApp()
# =============================================================================

library(shiny)
library(bslib)
library(leaflet)
library(sf)
library(dplyr)
library(DT)
library(jsonlite)

# ---- configuration -----------------------------------------------------------
# Community submissions are collected with two Google Forms owned by the author
# (responses land in her Google Sheet). Paste each form's EMBED url here
# (Google Forms > Send > < > > copy the src of the iframe; it ends in
# ?embedded=true). While a url is empty the tab shows the questions and a
# mailto fallback instead.
FORM_DC_URL     <- Sys.getenv("FORM_DC_URL",
  unset = "https://docs.google.com/forms/d/e/1FAIpQLSdNP3OSogFFzASsXARiPFmM3w3x-AwG4CqwZLqmpk3pjbKMpQ/viewform?embedded=true")
FORM_POLICY_URL <- Sys.getenv("FORM_POLICY_URL",
  unset = "https://docs.google.com/forms/d/e/1FAIpQLSdiz78rLfXpWlFf9HT6tnoUo5kyzXAt5Sfpf79Qz6EaSlU_dQ/viewform?embedded=true")
CONTACT_EMAIL   <- "priyanka.desouza@ucdenver.edu"
REPO_URL        <- "https://github.com/pdez90/india-datacentre-ej"

# ---- data -------------------------------------------------------------------
districts  <- sf::st_read("data/districts.geojson",  quiet = TRUE)
facilities <- sf::st_read("data/facilities.geojson", quiet = TRUE)
plants     <- sf::st_read("data/plants.geojson",     quiet = TRUE)
osm_check  <- sf::st_read("data/osm_check.geojson",  quiet = TRUE)
# Public, sourced facility table (scripts/24_public_inventory.R; data dictionary in DATA.md)
PUB_CSV    <- "data/india_datacentres_public.csv"
PUB_ZIP    <- "data/india_datacentres_documented.zip"   # table + data dictionary + every cited URL with its archived copy (scripts/22)
pubtab     <- if (file.exists(PUB_CSV)) read.csv(PUB_CSV, stringsAsFactors = FALSE) else NULL
policies   <- read.csv("data/policies.csv", stringsAsFactors = FALSE)
pol_src    <- read.csv("data/policy_sources.csv", stringsAsFactors = FALSE)
H          <- jsonlite::read_json("data/headline.json")

facilities$status <- factor(facilities$status, levels = c("operating", "construction", "announced"))
districts$dpm25_added <- pmax(districts$dpm25_all - districts$dpm25, 0)
policies$has_policy <- as.logical(policies$has_policy)

# indicator registry: column, palette, digits, unit. Columns ending in *_all
# have a build-out twin that the scope switch selects.
IND <- list(
  "Data centres (count)"                 = list(col="dc_count_sel", pal="Reds",    fmt=0, unit="facilities (current scope and type filter)"),
  "PM2.5 increment from data centres"    = list(col="dpm25",      alt="dpm25_all",    pal="Purples", fmt=4, unit="ug/m3", log=TRUE, inmap=TRUE),
  "PM2.5 increment: operating only"      = list(col="dpm25",      pal="Purples", fmt=4, unit="ug/m3", log=TRUE, inmap="operating"),
  "PM2.5 increment: stock plus pipeline" = list(col="dpm25_all",  pal="Purples", fmt=4, unit="ug/m3", log=TRUE, inmap="all"),
  "PM2.5 increment added by the pipeline"= list(col="dpm25_added",pal="Purples", fmt=4, unit="ug/m3", log=TRUE, inmap="added"),
  # --- the Scope 1 / Scope 2 chain (operating inventory): consumed here, released there, breathed elsewhere
  "Scope 1 water: on-site cooling"       = list(col="s1_water_ml",  pal="Blues",   fmt=0, unit="ML/yr",  grp="chain"),
  "Scope 2 water (charged to consumer)"  = list(col="s2_water_ml",  pal="Blues",   fmt=0, unit="ML/yr",  grp="chain"),
  "Scope 2 SO2 released at plants"       = list(col="emis_so2_t",   pal="YlOrRd",  fmt=0, unit="t/yr",   grp="chain", log=TRUE),
  "Scope 2 NOx released at plants"       = list(col="emis_nox_t",   pal="YlOrRd",  fmt=0, unit="t/yr",   grp="chain", log=TRUE),
  "Scope 2 PM2.5 released at plants"     = list(col="emis_pm25_t",  pal="YlOrRd",  fmt=1, unit="t/yr",   grp="chain", log=TRUE),
  "Ambient PM2.5 (ACAG)"                 = list(col="pm25_acag_local",           pal="YlOrBr", fmt=1, unit="ug/m3"),
  "Surface NO2"                          = list(col="no2_surf",                  pal="YlOrRd", fmt=2, unit="ppb"),
  "Summer ozone (MDA8)"                  = list(col="o3_summer",                 pal="YlGn",   fmt=1, unit="ug/m3"),
  "Extreme heat days (>=35 C)"           = list(col="hot_days_peryr",            pal="Oranges",fmt=0, unit="days/yr"),
  "Asset wealth (NFHS-5 percentile)"     = list(col="wealth_pct",                pal="Blues",  fmt=0, unit="percentile of districts"),
  "Relative Wealth Index (Chi 2022)"     = list(col="rwi_mean",                  pal="Blues",  fmt=2, unit="index, 0 = country average"),
  "Urban share"                          = list(col="urban_share_2019",          pal="BuPu",   fmt=2, unit="proportion"),
  "Share SC/ST"                          = list(col="share_scst_2019",           pal="Greens", fmt=2, unit="proportion"),
  "Share below poverty line"             = list(col="share_bpl_2019",            pal="Greens", fmt=2, unit="proportion"),
  "Share Muslim"                         = list(col="share_muslim_2019",         pal="Greens", fmt=2, unit="proportion"),
  "Share without electricity"            = list(col="share_no_electricity_2019", pal="Greens", fmt=3, unit="proportion"),
  "Coal capacity"                        = list(col="coal_mw",                   pal="Greys",  fmt=0, unit="MW"),
  "Distance to nearest fossil plant"     = list(col="dist_fossil_km",            pal="PuBu",   fmt=0, unit="km"),
  "Baseline water stress (Aqueduct)"     = list(col="bws_raw",                   pal="RdYlBu", fmt=2, unit="ratio", rev=TRUE),
  "Population (2020)"                    = list(col="pop_2020",                  pal="Purples",fmt=0, unit="people")
)

TYPE_COL   <- c(hyperscale="#b2182b", colocation="#2166ac", telecom="#66a61e", enterprise="#e6ab02", government="#6a3d9a")
STATUS_LAB <- c(operating="Operating", construction="Under construction", announced="Announced")

fmtnum <- function(x, d = 0) ifelse(is.na(x), "n/a", formatC(x, format = "f", digits = d, big.mark = ","))
fmt1   <- function(x) formatC(as.numeric(x), format = "f", digits = 1)
esc    <- function(x) htmltools::htmlEscape(ifelse(is.na(x), "", as.character(x)))   # every data-derived string that enters HTML
safe_link <- function(url) {   # only http(s) URLs become anchors; everything else is shown as escaped text
  ok <- !is.na(url) & grepl("^https?://", url)
  shown <- ifelse(nchar(url) > 60, paste0(substr(url, 1, 57), "..."), url)
  ifelse(ok, sprintf("<a href='%s' target='_blank' rel='noopener noreferrer'>%s</a>",
                     htmltools::htmlEscape(url, attribute = TRUE), htmltools::htmlEscape(shown)),
         htmltools::htmlEscape(ifelse(is.na(url), "", url)))
}
yesno  <- function(x) ifelse(is.na(x) | x == "", "-", x)

# ---- submission-form helpers --------------------------------------------------
form_panel <- function(url, title, intro, fields, mail_subject) {
  if (nzchar(url)) {
    div(class = "p-2",
        p(intro),
        tags$iframe(src = url, width = "100%", height = "1400", frameborder = "0",
                    marginheight = "0", marginwidth = "0", "Loading form..."))
  } else {
    div(class = "p-3", style = "max-width:820px",
        h4(title), p(intro),
        p("The submission form is being set up. Until it is live, please email the details ",
          "below to ", tags$a(href = sprintf("mailto:%s?subject=%s", CONTACT_EMAIL,
                                             utils::URLencode(mail_subject)), CONTACT_EMAIL), "."),
        tags$ol(lapply(fields, tags$li)),
        p(tags$small("Every submission is checked against the source it cites before it enters ",
                     "the inventory; nothing submitted here changes the map automatically.")))
  }
}
DC_FIELDS <- list(   # mirrors the live form; shown only if the embed URL is ever unset
  "Is this a new facility or a correction to one already on the map?",
  "Data centre name (and operator, if different)",
  "Address, or the most precise location you can give (locality, city, state; a map link if you have one)",
  "Capacity, if known (IT load or total power in MW)",
  "Status: operating, under construction or announced",
  "How did you find out about this data centre? Link(s) to the source, or a description of it",
  "Your name and email (optional, only used to follow up on this entry)")
POL_FIELDS <- list(
  "State or union territory",
  "Policy name and year (e.g. 'Data Centre Policy 2024')",
  "Link to the notification, gazette or official summary (required)",
  "What it offers data centres: capital subsidy, stamp-duty exemption, electricity-duty exemption, land incentive, single-window clearance, power tariff concession, infrastructure status, other",
  "Does the policy require any environmental assessment, or set water or energy conditions? (yes / no / not stated)",
  "Anything else worth recording (amendments, successor policies, whether it replaces an earlier policy)",
  "Your name and email (optional)")

# ---- ui ---------------------------------------------------------------------
ui <- page_sidebar(
  title = "India Data Centre Environmental Justice Explorer",
  theme = bs_theme(version = 5, bootswatch = "flatly"),

  sidebar = sidebar(
    width = 340,
    radioButtons("scope", "Inventory",
                 choices = c("Operating facilities" = "operating",
                             "Stock plus pipeline (adds under-construction and announced)" = "all"),
                 selected = "operating"),
    selectInput("ind", "District layer", choices = names(IND), selected = "Data centres (count)"),
    checkboxInput("show_fac",    "Show data centres", TRUE),
    checkboxInput("show_plants", "Show coal & gas plants carrying the attributable emissions", FALSE),
    checkboxInput("show_osm",    "Show OpenStreetMap cross-check", FALSE),
    hr(),
    selectInput("state", "State", choices = c("All India", sort(unique(na.omit(districts$state_name)))),
                selected = "All India"),
    checkboxGroupInput("types", "Facility type", choices = names(TYPE_COL), selected = names(TYPE_COL)),
    helpText(tags$small("The type filter applies to the points, the value boxes, the district count layer and the ",
                        "district table's count. Every other district layer, including the PM2.5 increment, is an ",
                        "all-type aggregate and does not change with it.")),
    hr(),
    helpText(tags$small(
      tags$b("Two scopes, as in the paper."), " The operating inventory (",
      H$n_operating, " facilities, ", H$hosting_districts_operating, " districts) is the basis of every ",
      "result in the paper. The stock-plus-pipeline scenario adds ", H$n_construction,
      " under-construction and ", H$n_announced, " announced facilities (", H$n_all,
      " in all), sized at their reported build-out loads or the operating allocation; it is a scenario, ",
      "not a count of what exists.")),
    helpText(tags$small(
      "District layers are 2015-geography district means. The PM2.5 increment is the ",
      "modelled contribution of data-centre electricity demand, dispersed from the coal ",
      "and gas plants that serve it. The Scope 1 / Scope 2 chain layers are for the ",
      "operating inventory.")),
    helpText(tags$small(
      "Facility coordinates are city- or locality centroids, not site locations. Capacity is ",
      "an allocation for facilities that do not disclose it.")),
    hr(),
    helpText(tags$small("Contact: Dr Priyanka deSouza, ",
                        tags$a(href = paste0("mailto:", CONTACT_EMAIL), CONTACT_EMAIL),
                        " | ", tags$a(href = REPO_URL, target = "_blank", "code and data")))
  ),

  layout_columns(
    fill = FALSE,
    value_box(textOutput("vb_n_title"), textOutput("vb_n"), textOutput("vb_n_ctx"), theme = "primary"),
    value_box("Allocated IT capacity", textOutput("vb_mw"),  textOutput("vb_mw_ctx"),  theme = "secondary"),
    value_box("Electricity",           textOutput("vb_gwh"), textOutput("vb_gwh_ctx"), theme = "secondary"),
    value_box("CO2 (average grid factor)", textOutput("vb_co2"), textOutput("vb_co2_ctx"), theme = "secondary")
  ),
  p(class = "text-muted small px-2 mb-1",
    "Context lines compare the facilities shown with all-India figures: generation and peak demand ",
    "from the Central Electricity Authority (FY2024-25 / FY2025-26), per-capita consumption 1,460 kWh ",
    "(CEA, FY2024-25), and fossil CO2 of about 3.0 Gt (Global Carbon Budget 2024). Capacity is compared ",
    "at facility load (IT load x PUE 1.6)."),

  navset_card_tab(
    nav_panel("Map",        leafletOutput("map", height = "620px")),
    nav_panel("Districts",  DTOutput("dtab")),
    nav_panel("Facilities",
      div(class = "p-3",
        p("Every facility in the inventory, with the capacity the paper uses. ",
          "The sourced table below gives each facility's source links, every published capacity figure we ",
          "found and which one we used, and the cross-check against the ",
          tags$a(href = "https://www.atlasofdatacenterpolitics.com/", target = "_blank", "Atlas of Data Center Politics"), ". ",
          "Location is published at city and district level only. Column definitions and methods are in ",
          tags$a(href = paste0(REPO_URL, "/blob/main/DATA.md"), target = "_blank", "DATA.md"), ". ",
          "The facility table is licensed ", tags$a(href = "https://creativecommons.org/licenses/by-nc/4.0/", target = "_blank", "CC BY-NC 4.0"),
          " (credit required; no commercial use without permission)."),
        p("Every source is linked, and an archived copy (Internet Archive or archive.today) is given wherever the ",
          "site allows one, so each row can be checked even if the original page changes. The documented ",
          "dataset bundles the table, its data dictionary, a list of every cited URL with its archived copy and ",
          "snapshot date, and a README with the licence and how to cite it."),
        if (file.exists(PUB_ZIP)) downloadButton("dl_bundle", "Download the documented dataset (ZIP)", class = "btn-sm btn-primary mb-3 me-2"),
        if (!is.null(pubtab)) downloadButton("dl_public", "Facility table only (CSV)", class = "btn-sm mb-3"),
        DTOutput("ftab"),
        if (!is.null(pubtab)) tagList(h5(class = "mt-4", "Sources and capacity notes, facility by facility"), DTOutput("srctab")))),
    nav_panel("State policies",
      div(class = "p-3",
        p("State incentive policies for data centres, compiled from state notifications and ",
          "secondary legal summaries, joined to the burden geography of each state's hosting ",
          "districts. ", tags$b(sprintf("%d of the %d states reviewed have a dedicated policy or data-centre provisions",
                                        H$policy_states_dedicated, H$policy_states_reviewed)),
          sprintf("; together they host %d of the %d operating facilities (%d%%). ",
                  H$facilities_in_policy_states, H$n_operating,
                  round(100 * H$facilities_in_policy_states / H$n_operating)),
          "No state requires an environmental assessment for data centres. The second table ",
          "gives the source, the verbatim passage and the retrieval date behind every cell of ",
          "the first. Know of a policy we have missed, or a newer one? Use the ",
          tags$em("Submit a policy"), " tab."),
        h5("Policy compilation"), DTOutput("ptab"),
        h5(class = "mt-4", "Sources, claim by claim"), DTOutput("pstab"))),
    nav_panel("Submit a data centre",
      form_panel(FORM_DC_URL, "Tell us about a data centre we have missed",
        paste0("The inventory is built from operator facility lists and a curated directory; every ",
               "facility carries a source link, and the Facilities tab shows how far each was verified (", H$n_operating, " operating facilities; ",
               H$n_all, " including the pipeline). Facilities open, close and change hands faster ",
               "than any single source records, so we welcome additions and corrections. Please tell ",
               "us how you know about the facility: entries are verified against the source before ",
               "they are added."),
        DC_FIELDS, "New data centre for the India inventory")),
    nav_panel("Submit a policy",
      form_panel(FORM_POLICY_URL, "Tell us about a state data-centre policy",
        paste0("States are competing for data centres with capital subsidies, duty exemptions, land ",
               "and single-window clearance, and the policies change every year. We track them on ",
               "the State policies tab, with a source for every claim. If a state has enacted, ",
               "amended or replaced a policy, please send us the link to the notification or an ",
               "official summary."),
        POL_FIELDS, "State data-centre policy for the tracker")),
    nav_panel("About",
      div(class = "p-3", style = "max-width:820px",
        h4("What this shows"),
        p("Each point is a data centre. The shaded layer beneath is a district-level indicator ",
          "you choose on the left. The point of putting them together is that they disagree: ",
          "switch the district layer from ", tags$em("Data centres"), " to ",
          tags$em("PM2.5 increment from data centres"), " and the points stay in Mumbai, Chennai ",
          "and Bengaluru while the shading jumps to the thermal-generation corridors and the ",
          "areas downwind of them. Facilities sit in one geography; the air pollution their ",
          "electricity causes appears in another."),

        h4("Where the facilities come from"),
        p("The backbone of the inventory is the Data Center Map directory (datacentermap.com), whose ",
          "India listing was read entry by entry for status and reported IT load; every facility it lists ",
          "is kept unless it is closed or a second listing of the same building. Three other kinds of record ",
          "add facilities the directory misses: the facility lists that operators publish on their own websites ",
          "(an operator census), a census of government data centres (NIC and NICSI national data centres, ",
          "UIDAI, ISRO, railways and the State Data Centres), and operator, company, government or press records ",
          "for sites first noticed in a cross-check. The ",
          tags$a(href = "https://www.atlasofdatacenterpolitics.com/", target = "_blank", "Atlas of Data Center Politics"),
          " and a screened OpenStreetMap query are used only as cross-checks, never as the source of a row. ",
          "Every facility carries a source link; the Facilities tab gives them, with how each was verified."),
        p(sprintf(paste0("The result is %d operating facilities in %d districts, and %d facilities in %d ",
                         "districts once the %d under-construction and %d announced facilities are added. "),
                  H$n_operating, H$hosting_districts_operating, H$n_all, H$hosting_districts_all,
                  H$n_construction, H$n_announced),
          "The operating inventory is what the paper analyses; the stock-plus-pipeline scenario ",
          "is reported alongside it, never in place of it, because a pipeline is a set of ",
          "announcements and not all of it will be built."),

        h4("The OpenStreetMap cross-check"),
        p("Querying OpenStreetMap through the Overpass API for the tags ",
          tags$code("telecom=data_center"), " and ", tags$code("building=data_center"),
          " over India returns 238 features, but the tags are badly misapplied here: citizen ",
          "e-service kiosks, Aadhaar enrolment points, computer shops. Screening to records ",
          "identifiable as data centres from their name or operator leaves ", H$osm_points,
          " points inside the study geography, drawn as black rings when switched on. They are a ",
          "check on the geography and are counted in no total."),

        h4("What the capacity numbers are"),
        p(sprintf(paste0("Only a minority of facilities disclose their IT load. Reported loads are held ",
                         "fixed, and the remaining capacity is allocated: each facility gets a relative ",
                         "weight by operator class (telecom 0.5, enterprise and government 1, colocation 3, hyperscale ",
                         "10) and the commercial subset is scaled to a national anchor of %s MW of ",
                         "commercial IT load, giving %s MW across the operating inventory. "),
                  fmtnum(H$anchor_commercial_mw), fmtnum(H$mw_operating)),
          "Under the stock-plus-pipeline scenario, facilities that publish a build-out load keep it and the ",
          "rest are sized at the same per-weight allocation as the operating inventory, ",
          sprintf("giving %s MW. ", fmtnum(H$mw_all)),
          tags$b("An individual facility's megawatt figure is therefore an allocation, not a ",
                 "measurement"), "; treat state and national aggregates as the meaningful quantities."),
        p(sprintf(paste0("The operating inventory draws about %s TWh per year, %s%% of national ",
                         "generation, and is attributed %s Mt CO2 on average grid factors (the value in ",
                         "the boxes above) or %s Mt on state marginal factors, the paper's headline. "),
                  fmt1(H$twh_operating), fmt1(H$pct_nat_gen_operating), fmt1(H$co2_mt_avg_operating),
                  fmt1(H$co2_mt_marginal_operating)),
          sprintf("Marginal SO2, NOx and primary PM2.5 are %s, %s and %s kt per year.",
                  fmt1(H$so2_kt_operating), fmt1(H$nox_kt_operating), fmt1(H$pm25_kt_operating))),

        h4("Following one burden through the chain"),
        p("Five layers, grouped under Scope 1 and Scope 2, let you watch the sector's footprint ",
          "move across the map. ", tags$b("Scope 1"), " is what happens at the facility: cooling ",
          "water drawn on site. Backup diesel generators are the other Scope 1 burden, and the one air ",
          "emission that is not displaced: the paper puts their nitrogen oxides at ",
          sprintf("%s%% (central about %s%%) of the sector's grid-attributable NOx, emitted at ground level in the hosting ",
                  H$diesel_nox_pct_range, fmt1(H$diesel_nox_pct_central)),
          "districts. That estimate has not yet been rerun on the revised inventory, so it is not mapped here. ",
          tags$b("Scope 2 SO2, NOx and PM2.5"), " are the emissions the sector's ",
          "electricity causes, mapped where they are physically released, at the ",
          sprintf("%d coal and gas plants that serve the load, across %d districts. ",
                  H$plants, H$emission_districts),
          "Switch finally to ", tags$em("PM2.5 increment from data centres"), " and you see where ",
          "the resulting concentration settles, which is different again."),
        p(tags$small(tags$b("One label needs care."), " Scope 2 water is charged to the district ",
          "that consumed the electricity, not the district where the water was drawn; it is a ",
          "consumption account, not a location, because about a third of it is hydropower ",
          "reservoir evaporation and only the coal and gas fleet is geolocated. It uses average ",
          "grid water intensities because no marginal water intensity is published for India, ",
          sprintf("so it is an upper estimate (%s GL per year nationally; %s GL without hydropower).",
                  fmt1(H$scope2_gl_operating), fmt1(H$scope2_gl_nohydro_operating)))),

        h4("Reading the PM2.5 increment"),
        p(sprintf(paste0("The operating inventory raises population-weighted annual PM2.5 by %.4f ug/m3 across ",
                         "India, with %s million people above 0.01 ug/m3 and about %s attributable deaths a year ",
                         "(GEMM); the stock-plus-pipeline scenario raises it to %.4f ug/m3, %s million people and ",
                         "about %s deaths. Three district layers show the operating field, the build-out field and ",
                         "the difference between them, and the layer named simply 'PM2.5 increment from data centres' ",
                         "follows the scope switch."),
                  H$inmap_operating$pwm_ugm3, fmtnum(H$inmap_operating$pop_ge_0_01_million),
                  fmtnum(H$inmap_operating$deaths_per_yr), H$inmap_all$pwm_ugm3,
                  fmtnum(H$inmap_all$pop_ge_0_01_million), fmtnum(H$inmap_all$deaths_per_yr))),
        p("This is not measured pollution. It is the modelled annual-mean PM2.5 attributable to ",
          "the electricity these facilities consume, obtained by assigning each facility's demand ",
          "to the generators that respond at the margin and dispersing the resulting emissions ",
          "through the Global InMAP reduced-complexity model. It is a scenario-consistent ",
          "estimate, not an exact one, and it cannot be attributed to any individual facility."),

        h4("The two wealth measures"),
        p("Wealth appears twice, from independent sources, and neither is money. The ",
          tags$b("NFHS-5 asset score"), " is a principal-components index of household assets ",
          "whose raw values mean nothing on their own; it is shown as a percentile of India's ",
          "surveyed districts. The ", tags$b("Relative Wealth Index"), " (Chi et al., 2022) is a ",
          "satellite- and connectivity-based estimate at 2.4 km resolution, already dimensionless ",
          "and roughly centred on zero. The two are built from entirely different inputs and agree."),

        h4("Reading the district map"),
        p("District names denote polygons in the 2015 survey geography, not municipal entities. ",
          "The polygon labelled ", tags$b("Chennai"), " lies offshore and contains no land, ",
          "population or households; Chennai city falls inside the polygon labelled ",
          tags$b("Kancheepuram"), ", which is why that district carries the facilities at ",
          "central-Chennai addresses. Hyderabad's facilities sit in ", tags$b("Rangareddy"),
          ", and Telangana is part of unified Andhra Pradesh in this geography."),

        h4("Other data sources"),
        tags$ul(
          tags$li("Social composition: National Family Health Survey NFHS-5 (2019-21), household-member weighted district shares."),
          tags$li("Relative Wealth Index: ", tags$a(href = "https://dataforgood.facebook.com/dfg/tools/relative-wealth-index",
                                                    target = "_blank", "Meta Data for Good"), " (Chi et al., 2022)."),
          tags$li("Power plants: ", tags$a(href = "https://datasets.wri.org/datasets/global-power-plant-database",
                                           target = "_blank", "WRI Global Power Plant Database"), "; marginal emission factors from Sengupta et al. (2022)."),
          tags$li("Water stress: ", tags$a(href = "https://www.wri.org/aqueduct", target = "_blank", "WRI Aqueduct 4.0"), " baseline water stress."),
          tags$li("PM2.5: Washington University ", tags$a(href = "https://sites.wustl.edu/acag/datasets/surface-pm2-5/",
                                                          target = "_blank", "ACAG"), " surface product; surface NO2 (Anenberg et al., 2022) and ozone (Wang et al., 2025)."),
          tags$li("Grid reliability: Prayas Electricity Supply Monitoring Initiative (ESMI), 2014-2019."),
          tags$li("Dispersion: ", tags$a(href = "https://inmap.run/", target = "_blank", "InMAP"), ", global implementation of Thakrar et al. (2022)."),
          tags$li("State policies: state notifications and gazettes, investment-promotion portals, secondary legal summaries; every claim sourced on the State policies tab.")),

        h4("Limits worth knowing"),
        tags$ul(
          tags$li("Coordinates are city- or locality-precision; a point locates a facility in its town, not at its site."),
          tags$li("Most facilities do not disclose capacity; it is allocated by operator class and scaled to a national anchor."),
          tags$li("District values are means and hide within-district variation."),
          tags$li("The pipeline scenario counts announcements; not all of them will be built.")),

        h4("A living inventory"),
        p("The facility inventory and the state policy compilation are our best effort from public ",
          "sources on a stated date: operator facility lists and a curated directory read page by page, ",
          "two independent corroboration sources, and state notifications with a sourced passage behind ",
          "every policy claim. Both change faster than any single retrieval can track: facilities open, ",
          "close and change hands, and states enact, amend and replace incentive policies every year. ",
          "This site is therefore maintained as a living document. Use the ",
          tags$em("Submit a data centre"), " and ", tags$em("Submit a policy"),
          " tabs to send additions and corrections; every submission is checked against the source it ",
          "cites before it enters the inventory or the tracker, and the data files, the build date above ",
          "and the ", tags$a(href = REPO_URL, target = "_blank", "repository history"),
          " record what changed and when."),
        p(tags$small("Built ", H$built, ". Code and data: ",
                     tags$a(href = REPO_URL, target = "_blank", REPO_URL), ".")),
        h4("Contact"),
        p("Dr Priyanka deSouza, ", tags$a(href = paste0("mailto:", CONTACT_EMAIL), CONTACT_EMAIL), ".")
      ))
  )
)

# ---- server -----------------------------------------------------------------
server <- function(input, output, session) {

  is_all <- reactive(identical(input$scope, "all"))

  # facilities in scope, with the scope's own allocation columns copied to the
  # generic names the map and tables use
  fac_scope <- reactive({
    f <- facilities
    if (is_all()) {
      f$mw_use <- f$mw_it_all; f$gwh_use <- f$e_fac_gwh_all; f$co2_use <- f$co2_kt_all
      f$s1_use <- f$scope1_ml_all; f$s2_use <- f$scope2_ml_all
    } else {
      f <- f[f$is_operating, ]
      f$mw_use <- f$mw_it; f$gwh_use <- f$e_fac_gwh; f$co2_use <- f$co2_kt
      f$s1_use <- f$scope1_ml; f$s2_use <- f$scope2_ml
    }
    f
  })

  fac_f <- reactive({
    f <- fac_scope()
    f <- f[f$dc_type %in% input$types, ]
    if (input$state != "All India") f <- f[!is.na(f$state_name) & f$state_name == input$state, ]
    f
  })

  dist_f <- reactive({
    d <- if (input$state == "All India") districts
         else districts[!is.na(districts$state_name) & districts$state_name == input$state, ]
    # facility count for the CURRENT scope and type selection (equals dc_count / dc_count_all
    # when every type is selected)
    f <- sf::st_drop_geometry(fac_f())
    key_d <- paste(d$dist_name, d$state_name, sep = "||")
    cnt <- table(paste(f$dist_name, f$state_name, sep = "||"))
    d$dc_count_sel <- as.integer(ifelse(key_d %in% names(cnt), cnt[key_d], 0L))
    d
  })

  output$vb_n_title <- renderText(sprintf("Facilities shown (of %d)", nrow(fac_scope())))
  output$vb_n   <- renderText(format(nrow(fac_f()), big.mark = ","))
  output$vb_mw  <- renderText(paste0(fmtnum(sum(fac_f()$mw_use,  na.rm = TRUE), 0), " MW"))
  output$vb_gwh <- renderText(paste0(fmtnum(sum(fac_f()$gwh_use, na.rm = TRUE), 0), " GWh/yr"))
  output$vb_co2 <- renderText(paste0(fmtnum(sum(fac_f()$co2_use, na.rm = TRUE) / 1000, 2), " Mt/yr"))
  CX <- H$context
  output$vb_n_ctx <- renderText({
    f <- fac_f(); d <- length(unique(f$dist_name[!is.na(f$dist_name)]))
    sprintf("in %d of India's 642 districts%s", d,
            if (is_all()) sprintf("; %d operating, %d under construction, %d announced",
                                  sum(f$status == "operating"), sum(f$status == "construction"),
                                  sum(f$status == "announced")) else "")
  })
  output$vb_mw_ctx <- renderText({
    mw <- sum(fac_f()$mw_use, na.rm = TRUE)
    sprintf("~%s MW at facility load: %.2f%% of India's record peak demand (%.0f GW)",
            fmtnum(mw * 1.6), 100 * mw * 1.6 / 1000 / CX$peak_demand_gw, CX$peak_demand_gw)
  })
  output$vb_gwh_ctx <- renderText({
    gwh <- sum(fac_f()$gwh_use, na.rm = TRUE)
    sprintf("%.2f%% of India's generation; the average annual use of %s million Indians",
            100 * gwh / 1000 / CX$gen_total_twh, fmtnum(gwh * 1e6 / CX$per_capita_kwh / 1e6, 1))
  })
  output$vb_co2_ctx <- renderText({
    kt <- sum(fac_f()$co2_use, na.rm = TRUE)
    sprintf("%.2f%% of India's fossil CO2 (~%.1f Gt/yr)", 100 * kt / 1000 / CX$india_fossil_co2_mt,
            CX$india_fossil_co2_mt / 1000)
  })

  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(minZoom = 4)) |>
      addProviderTiles(providers$CartoDB.PositronNoLabels) |>
      setView(lng = 79, lat = 22, zoom = 5)
  })

  # exposure summary for the InMAP layers (from tab16_inmap_summary.txt of each scope)
  inmap_note <- function(spec) {
    if (is.null(spec$inmap)) return("")
    which <- if (identical(spec$inmap, TRUE)) (if (is_all()) "all" else "operating") else spec$inmap
    if (which == "added") {
      o <- H$inmap_operating; b <- H$inmap_all
      return(sprintf("<br/>pipeline adds %.3f ug/m3 to the population-weighted mean and ~%s deaths/yr",
                     b$pwm_ugm3 - o$pwm_ugm3, fmtnum(b$deaths_per_yr - o$deaths_per_yr)))
    }
    x <- if (which == "all") H$inmap_all else H$inmap_operating
    sprintf("<br/>population-weighted mean %.4f ug/m3; %s million people above 0.01; ~%s attributable deaths/yr (GEMM)",
            x$pwm_ugm3, fmtnum(x$pop_ge_0_01_million), fmtnum(x$deaths_per_yr))
  }

  observe({
    spec <- IND[[input$ind]]
    col  <- if (is_all() && !is.null(spec$alt)) spec$alt else spec$col
    d <- dist_f()
    v <- d[[col]]
    vshow <- if (isTRUE(spec$log)) ifelse(!is.na(v) & v > 0, log10(v), NA_real_) else v   # zeros are drawn grey, not as tiny positives
    pal <- colorNumeric(spec$pal, domain = vshow, na.color = "#f0f0f0", reverse = isTRUE(spec$rev))
    ncount <- d$dc_count_sel
    dp     <- if (is_all()) d$dpm25_all else d$dpm25
    nodata <- is.na(d$pop_2020) | d$pop_2020 == 0 | is.na(d$urban_share_2019)
    lab <- sprintf(
      "<b>%s</b><br/>%s%s<br/><hr style='margin:4px 0'/>
       %s: <b>%s</b> %s<br/>
       Data centres: %s &nbsp;|&nbsp; Coal capacity: %s MW<br/>
       Population: %s &nbsp;|&nbsp; Urban share: %s<br/>
       Asset wealth: %s pctile &nbsp;|&nbsp; SC/ST: %s &nbsp;|&nbsp; BPL: %s<br/>
       PM2.5 increment: %s ug/m3",
      esc(d$dist_name), esc(d$state_name),
      ifelse(nodata, "<br/><span style='color:#b2182b'>no land area, population or survey data in this polygon</span>", ""),
      esc(input$ind), fmtnum(v, spec$fmt), esc(spec$unit),
      fmtnum(ncount, 0), fmtnum(d$coal_mw, 0),
      fmtnum(d$pop_2020, 0), fmtnum(d$urban_share_2019, 2),
      fmtnum(d$wealth_pct, 0), fmtnum(d$share_scst_2019, 2), fmtnum(d$share_bpl_2019, 2),
      fmtnum(dp, 4)) |> lapply(htmltools::HTML)

    m <- leafletProxy("map", data = d) |>
      clearShapes() |> clearMarkers() |> clearControls() |>
      addPolygons(fillColor = ~pal(vshow), fillOpacity = 0.78, color = "white", weight = 0.4,
                  highlightOptions = highlightOptions(weight = 2, color = "#333", bringToFront = TRUE),
                  label = lab) |>
      addLegend("bottomright", pal = pal, values = vshow, opacity = 0.85,
                title = paste0(input$ind, "<br/><small>", spec$unit,
                               if (isTRUE(spec$log)) " (log scale; grey = zero or no data)" else "",
                               if (is_all() && !is.null(spec$alt)) " - stock plus pipeline" else "",
                               inmap_note(spec), "</small>"),
                labFormat = if (isTRUE(spec$log)) labelFormat(transform = function(x) 10^x) else labelFormat())

    if (isTRUE(input$show_plants) && nrow(plants) > 0) {
      m <- m |> addCircleMarkers(
        data = plants, radius = ~pmax(2, sqrt(pmax(capacity_mw, 1)) / 12),
        color = ~ifelse(fuel == "Coal", "#4d4d4d", "#1b7837"), stroke = FALSE, fillOpacity = 0.55,
        label = ~lapply(sprintf("<b>%s</b><br/>%s, %s MW<br/>Attributable SO2 %s t/yr | NOx %s t/yr | PM2.5 %s t/yr",
                                esc(name), esc(fuel), fmtnum(capacity_mw), fmtnum(so2_t), fmtnum(nox_t), fmtnum(pm25_t, 1)),
                        htmltools::HTML))
    }
    if (isTRUE(input$show_osm) && nrow(osm_check) > 0) {
      m <- m |> addCircleMarkers(
        data = osm_check, radius = 9, color = "#111", weight = 1.4, fill = FALSE, opacity = 0.85,
        label = ~lapply(sprintf("<b>%s</b><br/>OpenStreetMap cross-check<br/>%s, %s", esc(label), esc(dist_name), esc(state_name)),
                        htmltools::HTML))
    }
    f <- fac_f()
    if (isTRUE(input$show_fac) && nrow(f) > 0) {
      m <- m |> addCircleMarkers(
        data = f,
        radius = ~pmax(3.5, sqrt(pmax(mw_use, 0.3)) * 2.2),
        color = ~ifelse(status == "operating", "white", "#111"),
        weight = ~ifelse(status == "operating", 0.9, 1.6),
        dashArray = ~ifelse(status == "announced", "3,3", ""),
        fillColor = ~unname(TYPE_COL[dc_type]),
        fillOpacity = ~ifelse(status == "operating", 0.92, 0.55),
        label = ~lapply(sprintf(
          "<b>%s</b><br/>%s | %s | %s<br/>%s, %s<br/><hr style='margin:4px 0'/>
           IT capacity: %s MW%s<br/>Electricity: %s GWh/yr<br/>CO2: %s kt/yr<br/>
           On-site water: %s ML/yr<br/>Electricity-related water: %s ML/yr",
          esc(name), esc(operator), esc(dc_type), esc(STATUS_LAB[as.character(status)]), esc(dist_name), esc(state_name),
          fmtnum(mw_use, 2),
          ifelse(is.na(mw_reported), " (allocated)", paste0(" (", fmtnum(mw_reported, 1), " MW reported)")),
          fmtnum(gwh_use, 1), fmtnum(co2_use, 1), fmtnum(s1_use, 1), fmtnum(s2_use, 1)), htmltools::HTML))
    }
    m
  })

  output$dtab <- renderDT({
    d <- sf::st_drop_geometry(dist_f())
    cnt <- "dc_count_sel"
    dpc <- if (is_all()) "dpm25_all" else "dpm25"
    d <- d |>
      select(any_of(c("dist_name", "state_name", cnt, "pop_2020", "wealth_pct", "rwi_mean",
                      "urban_share_2019", "share_scst_2019", "share_bpl_2019",
                      "pm25_acag_local", "no2_surf", "coal_mw", "bws_raw", dpc,
                      "s1_water_ml", "emis_so2_t"))) |>
      rename(data_centres = all_of(cnt), pm25_increment = all_of(dpc)) |>
      arrange(desc(data_centres))
    datatable(d, rownames = FALSE, filter = "top", extensions = "Buttons",
              options = list(pageLength = 20, dom = "Bfrtip", buttons = c("csv", "excel"), scrollX = TRUE)) |>
      formatRound(c("pop_2020", "coal_mw", "s1_water_ml", "emis_so2_t"), 0) |>
      formatRound(c("wealth_pct", "rwi_mean", "urban_share_2019", "share_scst_2019", "share_bpl_2019",
                    "pm25_acag_local", "no2_surf", "bws_raw"), 2) |>
      formatRound("pm25_increment", 4)
  })

  output$ftab <- renderDT({
    f <- sf::st_drop_geometry(fac_f()) |>
      mutate(status = STATUS_LAB[as.character(status)]) |>
      select(any_of(c("name", "operator", "dc_type", "status", "dist_name", "state_name",
                      "mw_reported", "mw_use", "gwh_use", "co2_use", "s1_use", "s2_use", "src"))) |>
      rename(mw_allocated = mw_use, electricity_gwh = gwh_use, co2_kt = co2_use,
             onsite_water_ml = s1_use, electricity_water_ml = s2_use, source = src) |>
      arrange(desc(mw_allocated))
    datatable(f, rownames = FALSE, filter = "top", extensions = "Buttons",
              options = list(pageLength = 20, dom = "Bfrtip", buttons = c("csv", "excel"), scrollX = TRUE)) |>
      formatRound(c("mw_reported", "mw_allocated", "electricity_gwh", "co2_kt",
                    "onsite_water_ml", "electricity_water_ml"), 2)
  })

  output$dl_bundle <- downloadHandler(
    filename = function() "india_datacentres_documented.zip",
    content  = function(file) file.copy(PUB_ZIP, file),
    contentType = "application/zip")

  output$dl_public <- downloadHandler(
    filename = function() "india_datacentres_public.csv",
    content  = function(file) file.copy(PUB_CSV, file))

  output$srctab <- renderDT({
    req(pubtab)
    s <- pubtab |>
      transmute(ID = facility_id, Facility = facility_name, Operator = operator, Status = status,
                City = city, District = district_2015,
                `Reported IT MW (current)` = mw_it_reported_current, `Reported IT MW (build-out)` = mw_it_reported_buildout,
                `What the MW figure is` = mw_basis, `Capacity note` = mw_flag,
                `IT MW used in paper` = mw_it_used_in_paper, `How MW was set` = mw_method,
                Source = safe_link(source_url), `Source (archived)` = safe_link(source_url_archive),
                `Second source` = safe_link(source_url_2), `Second source (archived)` = safe_link(source_url_2_archive),
                Verification = source_verification, Confidence = confidence, `Open issue` = open_issue,
                `Atlas of Data Center Politics` = ifelse(adp_match == "none", "not in Atlas", paste0(adp_campus_name, " (", adp_size_bucket, ")")))
    datatable(s, rownames = FALSE, filter = "top",
              escape = -which(names(s) %in% c("Source", "Source (archived)", "Second source", "Second source (archived)")),
              extensions = "Buttons",
              options = list(pageLength = 15, dom = "Bfrtip", buttons = c("csv", "excel"), scrollX = TRUE))
  })

  output$ptab <- renderDT({
    p <- policies |>
      transmute(State = state,
                `Dedicated policy` = ifelse(has_policy, paste0(policy_name, " (", policy_year, ")"), "none dedicated"),
                `Capital subsidy` = yesno(capital_subsidy), `Stamp duty exemption` = yesno(stamp_duty_exemption),
                `Electricity duty exemption` = yesno(electricity_duty_exemption),
                `Land incentive` = yesno(land_incentive), `Single window` = yesno(single_window),
                `EIA required` = yesno(eia_required),
                `Operating facilities` = dc_count, `Incl. pipeline` = dc_count_all,
                `Hosting districts` = dc_districts,
                `Share of hosting districts in high water stress` = round(100 * share_dists_high_stress),
                `Median baseline water stress` = median_bws,
                `Mean hosting-district PM2.5 (ug/m3)` = mean_pm25,
                Verification = verify_note)
    datatable(p, rownames = FALSE, filter = "top", extensions = "Buttons",
              options = list(pageLength = 20, dom = "Bfrtip", buttons = c("csv", "excel"), scrollX = TRUE))
  })

  output$pstab <- renderDT({
    s <- pol_src |>
      transmute(State = state, Claim = gsub("_", " ", claim), Value = value,
                `Source type` = source_type, `Issuing body` = issuing_body, Title = source_title,
                Link = safe_link(url),
                `Document date` = document_date, Retrieved = retrieved, `Verbatim passage` = quote)
    datatable(s, rownames = FALSE, filter = "top", escape = -which(names(s) == "Link"), extensions = "Buttons",
              options = list(pageLength = 15, dom = "Bfrtip", buttons = c("csv", "excel"), scrollX = TRUE))
  })
}

shinyApp(ui, server)
