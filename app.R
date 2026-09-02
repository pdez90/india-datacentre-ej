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
FORM_DC_URL     <- Sys.getenv("FORM_DC_URL",     unset = "https://docs.google.com/forms/d/e/1FAIpQLSeEsoKwHVzlHH3GAUOgQHr7WSCXS_fdi_iXVUBXzPe1ats0cw/viewform?embedded=true")
FORM_POLICY_URL <- Sys.getenv("FORM_POLICY_URL", unset = "https://docs.google.com/forms/d/e/1FAIpQLScjBODHJgp6u2Klg6XMzHoZtZsI2M9uHUULjcAsTYVej4SagA/viewform?embedded=true")
CONTACT_EMAIL   <- "priyanka.desouza@ucdenver.edu"
REPO_URL        <- "https://github.com/pdez90/india-datacentre-ej"

# ---- data -------------------------------------------------------------------
districts  <- sf::st_read("data/districts.geojson",  quiet = TRUE)
facilities <- sf::st_read("data/facilities.geojson", quiet = TRUE)
plants     <- sf::st_read("data/plants.geojson",     quiet = TRUE)
osm_check  <- sf::st_read("data/osm_check.geojson",  quiet = TRUE)
policies   <- read.csv("data/policies.csv", stringsAsFactors = FALSE)
pol_src    <- read.csv("data/policy_sources.csv", stringsAsFactors = FALSE)
H          <- jsonlite::read_json("data/headline.json")

facilities$status <- factor(facilities$status, levels = c("operating", "construction", "announced"))
policies$has_policy <- as.logical(policies$has_policy)

# indicator registry: column, palette, digits, unit. Columns ending in *_all
# have a build-out twin that the scope switch selects.
IND <- list(
  "Data centres (count)"                 = list(col="dc_count",   alt="dc_count_all", pal="Reds",    fmt=0, unit="facilities"),
  "PM2.5 increment from data centres"    = list(col="dpm25",      alt="dpm25_all",    pal="Purples", fmt=4, unit="ug/m3", log=TRUE),
  # --- the Scope 1 / Scope 2 chain (operating inventory): consumed here, released there, breathed elsewhere
  "Scope 1 water: on-site cooling"       = list(col="s1_water_ml",  pal="Blues",   fmt=0, unit="ML/yr",  grp="chain"),
  "Scope 1 air: backup-diesel NOx"       = list(col="diesel_nox_t", pal="Oranges", fmt=1, unit="t/yr",   grp="chain"),
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

TYPE_COL   <- c(hyperscale="#b2182b", colocation="#2166ac", telecom="#66a61e", enterprise="#e6ab02")
STATUS_LAB <- c(operating="Operating", construction="Under construction", announced="Announced")

fmtnum <- function(x, d = 0) ifelse(is.na(x), "n/a", formatC(x, format = "f", digits = d, big.mark = ","))
fmt1   <- function(x) formatC(as.numeric(x), format = "f", digits = 1)
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
DC_FIELDS <- list(
  "Data center name (and operator, if different)",
  "Address, or the most precise location you can give (locality, city, state; a map link if you have one)",
  "Capacity, if known - IT load or total power in MW, and whether it is operating, under construction or announced",
  "How did you find out about this data center? (operator page, news report, site visit, planning notice, other) - please include a link where possible",
  "Your contact details - name, email address and telephone number (optional; used only to follow up on this entry)")
POL_FIELDS <- list(
  "State or union territory",
  "Policy name and year (e.g. 'Data Centre Policy 2024')",
  "Link to the notification, gazette or official summary (required)",
  "What it offers data centers: capital subsidy, stamp-duty exemption, electricity-duty exemption, land incentive, single-window clearance, other (tick or describe)",
  "Does the policy require any environmental assessment or set water or energy conditions? (yes / no / not stated)",
  "Anything else worth recording (amendments, successor policies, whether it replaces an earlier policy)",
  "Your contact details - name, email address and telephone number (optional; used only to follow up on this entry)")

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
    hr(),
    helpText(tags$small(
      tags$b("Two scopes, as in the paper."), " The operating inventory (",
      H$n_operating, " facilities, ", H$hosting_districts_operating, " districts) is the basis of every ",
      "result in the paper. The stock-plus-pipeline scenario adds ", H$n_construction,
      " under-construction and ", H$n_announced, " announced facilities (", H$n_all,
      " in all) and re-allocates capacity to the build-out anchor; it is a scenario, ",
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
    value_box(textOutput("vb_n_title"), textOutput("vb_n"), theme = "primary"),
    value_box("Allocated IT capacity", textOutput("vb_mw"),  theme = "secondary"),
    value_box("Electricity",           textOutput("vb_gwh"), theme = "secondary"),
    value_box("CO2 (average grid factor)", textOutput("vb_co2"), theme = "secondary")
  ),

  navset_card_tab(
    nav_panel("Map",        leafletOutput("map", height = "620px")),
    nav_panel("Districts",  DTOutput("dtab")),
    nav_panel("Facilities", DTOutput("ftab")),
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
        paste0("The inventory is built from operator facility lists and a curated directory, checked ",
               "against two independent sources (", H$n_operating, " operating facilities; ",
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
        p("The inventory is assembled from two sources, each read entry by entry: the facility ",
          "lists that India's colocation and hyperscale operators publish on their own websites ",
          "(an operator census), and the DataCenterMap commercial directory, every page of which ",
          "was read for status and reported IT load. Where an operator's own list enumerates its ",
          "buildings in a market, those rows replace the directory's rows for that operator and ",
          "market. Two further sources corroborate the inventory without adding to it: the open ",
          tags$a(href = "https://github.com/Ringmast4r/Global-Data-Center-Map", target = "_blank",
                 "Global Data Center Map"), " (ATLAS) and a screened OpenStreetMap query."),
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
                         "weight by operator class (telecom 0.5, enterprise 1, colocation 3, hyperscale ",
                         "10) and the commercial subset is scaled to a national anchor of %s MW of ",
                         "commercial IT load, giving %s MW across the operating inventory. "),
                  fmtnum(H$anchor_commercial_mw), fmtnum(H$mw_operating)),
          "Under the stock-plus-pipeline scenario the anchor is the build-out figure and the ",
          sprintf("inventory totals %s MW. ", fmtnum(H$mw_all)),
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
        p("Six layers, grouped under Scope 1 and Scope 2, let you watch the sector's footprint ",
          "move across the map. ", tags$b("Scope 1"), " is what happens at the facility: cooling ",
          "water drawn on site, and the nitrogen oxides from backup diesel generators, the one air ",
          "emission that is not displaced. The diesel layer is the paper's central scenario, about ",
          sprintf("%s%% of the sector's grid-attributable NOx, emitted at ground level in the hosting ",
                  fmt1(H$diesel_nox_pct_central)),
          "districts. ", tags$b("Scope 2 SO2, NOx and PM2.5"), " are the emissions the sector's ",
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

        h4("Contribute"),
        p("Use the ", tags$em("Submit a data centre"), " and ", tags$em("Submit a policy"),
          " tabs to send additions and corrections. Every submission is checked against its ",
          "source before it enters the inventory or the policy tracker."),
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
    if (input$state == "All India") districts
    else districts[!is.na(districts$state_name) & districts$state_name == input$state, ]
  })

  output$vb_n_title <- renderText(sprintf("Facilities shown (of %d)", nrow(fac_scope())))
  output$vb_n   <- renderText(format(nrow(fac_f()), big.mark = ","))
  output$vb_mw  <- renderText(paste0(fmtnum(sum(fac_f()$mw_use,  na.rm = TRUE), 0), " MW"))
  output$vb_gwh <- renderText(paste0(fmtnum(sum(fac_f()$gwh_use, na.rm = TRUE), 0), " GWh/yr"))
  output$vb_co2 <- renderText(paste0(fmtnum(sum(fac_f()$co2_use, na.rm = TRUE) / 1000, 2), " Mt/yr"))

  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(minZoom = 4)) |>
      addProviderTiles(providers$CartoDB.PositronNoLabels) |>
      setView(lng = 79, lat = 22, zoom = 5)
  })

  observe({
    spec <- IND[[input$ind]]
    col  <- if (is_all() && !is.null(spec$alt)) spec$alt else spec$col
    d <- dist_f()
    v <- d[[col]]
    vshow <- if (isTRUE(spec$log)) log10(pmax(v, 1e-5)) else v
    pal <- colorNumeric(spec$pal, domain = vshow, na.color = "#f0f0f0", reverse = isTRUE(spec$rev))
    ncount <- if (is_all()) d$dc_count_all else d$dc_count
    dp     <- if (is_all()) d$dpm25_all else d$dpm25
    nodata <- is.na(d$pop_2020) | d$pop_2020 == 0 | is.na(d$urban_share_2019)
    lab <- sprintf(
      "<b>%s</b><br/>%s%s<br/><hr style='margin:4px 0'/>
       %s: <b>%s</b> %s<br/>
       Data centres: %s &nbsp;|&nbsp; Coal capacity: %s MW<br/>
       Population: %s &nbsp;|&nbsp; Urban share: %s<br/>
       Asset wealth: %s pctile &nbsp;|&nbsp; SC/ST: %s &nbsp;|&nbsp; BPL: %s<br/>
       PM2.5 increment: %s ug/m3",
      d$dist_name, d$state_name,
      ifelse(nodata, "<br/><span style='color:#b2182b'>no land area, population or survey data in this polygon</span>", ""),
      input$ind, fmtnum(v, spec$fmt), spec$unit,
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
                               if (isTRUE(spec$log)) " (log scale)" else "",
                               if (is_all() && !is.null(spec$alt)) " - stock plus pipeline" else "", "</small>"),
                labFormat = if (isTRUE(spec$log)) labelFormat(transform = function(x) 10^x) else labelFormat())

    if (isTRUE(input$show_plants) && nrow(plants) > 0) {
      m <- m |> addCircleMarkers(
        data = plants, radius = ~pmax(2, sqrt(pmax(capacity_mw, 1)) / 12),
        color = ~ifelse(fuel == "Coal", "#4d4d4d", "#1b7837"), stroke = FALSE, fillOpacity = 0.55,
        label = ~lapply(sprintf("<b>%s</b><br/>%s, %s MW<br/>Attributable SO2 %s t/yr | NOx %s t/yr | PM2.5 %s t/yr",
                                name, fuel, fmtnum(capacity_mw), fmtnum(so2_t), fmtnum(nox_t), fmtnum(pm25_t, 1)),
                        htmltools::HTML))
    }
    if (isTRUE(input$show_osm) && nrow(osm_check) > 0) {
      m <- m |> addCircleMarkers(
        data = osm_check, radius = 9, color = "#111", weight = 1.4, fill = FALSE, opacity = 0.85,
        label = ~lapply(sprintf("<b>%s</b><br/>OpenStreetMap cross-check<br/>%s, %s", label, dist_name, state_name),
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
          name, operator, dc_type, STATUS_LAB[as.character(status)], dist_name, state_name,
          fmtnum(mw_use, 2),
          ifelse(is.na(mw_reported), " (allocated)", paste0(" (", fmtnum(mw_reported, 1), " MW reported)")),
          fmtnum(gwh_use, 1), fmtnum(co2_use, 1), fmtnum(s1_use, 1), fmtnum(s2_use, 1)), htmltools::HTML))
    }
    m
  })

  output$dtab <- renderDT({
    d <- sf::st_drop_geometry(dist_f())
    cnt <- if (is_all()) "dc_count_all" else "dc_count"
    dpc <- if (is_all()) "dpm25_all" else "dpm25"
    d <- d |>
      select(any_of(c("dist_name", "state_name", cnt, "pop_2020", "wealth_pct", "rwi_mean",
                      "urban_share_2019", "share_scst_2019", "share_bpl_2019",
                      "pm25_acag_local", "no2_surf", "coal_mw", "bws_raw", dpc,
                      "s1_water_ml", "diesel_nox_t", "emis_so2_t"))) |>
      rename(data_centres = all_of(cnt), pm25_increment = all_of(dpc)) |>
      arrange(desc(data_centres))
    datatable(d, rownames = FALSE, filter = "top", extensions = "Buttons",
              options = list(pageLength = 20, dom = "Bfrtip", buttons = c("csv", "excel"), scrollX = TRUE)) |>
      formatRound(c("pop_2020", "coal_mw", "s1_water_ml", "emis_so2_t"), 0) |>
      formatRound(c("wealth_pct", "rwi_mean", "urban_share_2019", "share_scst_2019", "share_bpl_2019",
                    "pm25_acag_local", "no2_surf", "bws_raw", "diesel_nox_t"), 2) |>
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
                Link = ifelse(is.na(url) | url == "", "",
                              sprintf("<a href='%s' target='_blank'>%s</a>", url,
                                      ifelse(nchar(url) > 60, paste0(substr(url, 1, 57), "..."), url))),
                `Document date` = document_date, Retrieved = retrieved, `Verbatim passage` = quote)
    datatable(s, rownames = FALSE, filter = "top", escape = FALSE, extensions = "Buttons",
              options = list(pageLength = 15, dom = "Bfrtip", buttons = c("csv", "excel"), scrollX = TRUE))
  })
}

shinyApp(ui, server)
