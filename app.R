# =============================================================================
# India Data Centre Environmental Justice Explorer
# Companion app to: "Data centers in India locate in affluent districts while
# their environmental impacts extend through shared regional systems"
#
# Run locally:  shiny::runApp()
# Deploy:       rsconnect::deployApp()
# =============================================================================

library(shiny)
library(bslib)
library(leaflet)
library(sf)
library(dplyr)
library(DT)

# ---- data -------------------------------------------------------------------
# data are pre-baked GeoJSON; no pipeline dependency at runtime
districts  <- sf::st_read("data/districts.geojson", quiet = TRUE)
facilities <- sf::st_read("data/facilities.geojson", quiet = TRUE)
plants     <- sf::st_read("data/plants.geojson", quiet = TRUE)
osm_check  <- sf::st_read("data/osm_check.geojson", quiet = TRUE)

# indicator registry: column, label, legend title, palette, transform, digits
IND <- list(
  "Data centres (count)"                 = list(col="dc_count",                 pal="Reds",    fmt=0,  unit="facilities"),
  "PM2.5 increment from data centres"    = list(col="dpm25",                    pal="Purples", fmt=4,  unit="ug/m3", log=TRUE),
  "Ambient PM2.5 (ACAG)"                 = list(col="pm25_acag_local",          pal="YlOrBr",  fmt=1,  unit="ug/m3"),
  "Surface NO2"                          = list(col="no2_surf",                 pal="YlOrRd",  fmt=2,  unit="ppb"),
  "Summer ozone (MDA8)"                  = list(col="o3_summer",                pal="YlGn",    fmt=1,  unit="ug/m3"),
  "Extreme heat days (>=35 C)"           = list(col="hot_days_peryr",           pal="Oranges", fmt=0,  unit="days/yr"),
  "Mean wealth score (NFHS-5)"           = list(col="wealth_mean_2019",         pal="Blues",   fmt=0,  unit="index"),
  "Relative Wealth Index"                = list(col="rwi_mean",                 pal="Blues",   fmt=2,  unit="index"),
  "Urban share"                          = list(col="urban_share_2019",         pal="BuPu",    fmt=2,  unit="proportion"),
  "Share SC/ST"                          = list(col="share_scst_2019",          pal="Greens",  fmt=2,  unit="proportion"),
  "Share below poverty line"             = list(col="share_bpl_2019",           pal="Greens",  fmt=2,  unit="proportion"),
  "Share Muslim"                         = list(col="share_muslim_2019",        pal="Greens",  fmt=2,  unit="proportion"),
  "Share without electricity"            = list(col="share_no_electricity_2019",pal="Greens",  fmt=3,  unit="proportion"),
  "Coal capacity"                        = list(col="coal_mw",                  pal="Greys",   fmt=0,  unit="MW"),
  "Distance to nearest fossil plant"     = list(col="dist_fossil_km",           pal="PuBu",    fmt=0,  unit="km"),
  "Baseline water stress (Aqueduct)"     = list(col="bws_raw",                  pal="RdYlBu",  fmt=2,  unit="ratio", rev=TRUE),
  "Population (2020)"                    = list(col="pop_2020",                 pal="Purples", fmt=0,  unit="people")
)

TYPE_COL <- c(hyperscale="#b2182b", colocation="#2166ac",
              telecom="#66a61e", enterprise="#e6ab02")

fmtnum <- function(x, d = 0) ifelse(is.na(x), "n/a",
  formatC(x, format = "f", digits = d, big.mark = ","))

# ---- ui ---------------------------------------------------------------------
ui <- page_sidebar(
  title = "India Data Centre Environmental Justice Explorer",
  theme = bs_theme(version = 5, bootswatch = "flatly"),

  sidebar = sidebar(
    width = 330,
    selectInput("ind", "District layer", choices = names(IND),
                selected = "Data centres (count)"),
    checkboxInput("show_fac",    "Show data centres", TRUE),
    checkboxInput("show_plants", "Show coal & gas plants", FALSE),
    checkboxInput("show_osm",    "Show OpenStreetMap cross-check", FALSE),
    hr(),
    selectInput("state", "State", choices = c("All India", sort(unique(na.omit(districts$state_name)))),
                selected = "All India"),
    checkboxGroupInput("types", "Facility type",
                       choices  = names(TYPE_COL),
                       selected = names(TYPE_COL)),
    hr(),
    helpText(
      "District layers are 2015-geography district means. The PM2.5 increment ",
      "is the modelled contribution of data-centre electricity demand, dispersed ",
      "from the coal and gas plants that serve it."),
    helpText(
      tags$small("Facility coordinates are town- or postal-area centroids, not ",
                 "site locations. Capacity is imputed for facilities that do not ",
                 "disclose it. See the paper's Methods for the full accounting."))
  ),

  layout_columns(
    fill = FALSE,
    value_box("Facilities shown",   textOutput("vb_n"),    theme = "primary"),
    value_box("Imputed IT capacity", textOutput("vb_mw"),  theme = "secondary"),
    value_box("Electricity",         textOutput("vb_gwh"), theme = "secondary"),
    value_box("Attributable CO2",    textOutput("vb_co2"), theme = "secondary")
  ),

  navset_card_tab(
    nav_panel("Map",      leafletOutput("map", height = "620px")),
    nav_panel("Districts", DTOutput("dtab")),
    nav_panel("Facilities", DTOutput("ftab")),
    nav_panel("About",
      div(class = "p-3", style = "max-width:820px",
        h4("What this shows"),
        p("Each point is a data centre. The shaded layer beneath is a district-level ",
          "indicator you choose on the left. The point of putting them together is that ",
          "they disagree: switch the district layer from ", tags$em("Data centres"), " to ",
          tags$em("PM2.5 increment from data centres"), " and the points stay in Mumbai, ",
          "Chennai and Bengaluru while the shading jumps to the thermal-generation ",
          "corridors and the areas downwind of them. Facilities sit in one geography; the ",
          "air pollution their electricity causes appears in another."),

        h4("Where the facilities come from"),
        p("The map carries 373 facilities, assembled from two sources."),
        tags$ul(
          tags$li(tags$b("335 facilities"), " from the open Global Data Center Map ",
                  "inventory (referred to as ATLAS in the paper), filtered to India ",
                  "(342 rows) and de-duplicated against the second source below. ",
                  "It under-covers the large named campuses, which is why it is ",
                  "supplemented below. Source: ",
                  tags$a(href="https://github.com/Ringmast4r/Global-Data-Center-Map",
                         target="_blank", "github.com/Ringmast4r/Global-Data-Center-Map"), "."),
          tags$li(tags$b("38 major campuses compiled by hand"), " from press reporting and ",
                  "operator announcements, because named projects of this kind are ",
                  "largely absent from ATLAS: 31 of the 38 have no ATLAS counterpart. ",
                  "These are the large hyperscale and colocation ",
                  "projects: Yotta, AdaniConneX, STT GDC, NTT, CtrlS, Nxtra by Airtel, ",
                  "Princeton Digital, Sify, GPX/Equinix, AWS and Google. Each row records ",
                  "operator, city, status (operational, under construction, or announced), ",
                  "announced capacity where disclosed, and a source citation. ",
                  "Twenty-one were placed by hand at the locality named in the reporting ",
                  "— an industrial park or suburb such as Mahape, Airoli, Siruseri or ",
                  "Chandivali — and the remaining seventeen at their city centroid from ",
                  "the GeoNames gazetteer. None is a site-level pin.")),
        h4("The OpenStreetMap cross-check"),
        p("A third source is used to check the map rather than to build it. Querying ",
          "OpenStreetMap through the Overpass API for the tags ",
          tags$code("telecom=data_center"), " and ", tags$code("building=data_center"),
          " over India returns 238 features — but those tags turn out to be badly ",
          "misapplied here. Only 57 carry a name at all, and the named ones are dominated ",
          "by citizen e-service kiosks (Kerala's Akshaya centres), Aadhaar enrolment ",
          "points, and computer and internet shops. Taken at face value the extraction ",
          "would put data centres in 34 districts, 23 of them nowhere near the industry."),
        p("Screening to records identifiable as data centres from their name or operator ",
          "leaves 20, one of which is a university facility in Gilgit-Baltistan that falls ",
          "inside the clipping boundary and is dropped. The remaining ",
          tags$b("19 are the black rings"), " you can switch on in the sidebar. Seventeen ",
          "of them sit in districts the main inventory already covers — Chennai, ",
          "Bangalore, Mumbai Suburban, Thane — and the two that do not are Yotta's Panvel ",
          "campus, which the press compilation finds independently, and one facility in ",
          "North Goa. They are a check on the geography and are deliberately not counted ",
          "in any total on this page."),

        p("Adding the second group matters: those 38 campuses are only a tenth of the ",
          "facility count but a third of national IT capacity, because they are the ",
          "largest builds. Without them the map would understate the sector by a third."),

        h4("What the capacity anchor is"),
        p("Only 8 facilities in the whole inventory publicly disclose their IT capacity, ",
          "totalling 164 MW. Capacity for everything else has to be estimated, and it is ",
          "estimated in two steps. First, each facility gets a relative weight by operator ",
          "class, on a scale where a telecom site counts 0.5, an enterprise site 1, a ",
          "colocation site 3 and a hyperscale site 10. Second, those weights are multiplied ",
          "by a single common scale factor chosen so that the whole inventory adds up to an ",
          "assumed national total. That national total is the ", tags$b("anchor"), "."),
        p("The paper evaluates three anchors, 750, 1,000 and 1,500 MW, to bracket the ",
          "plausible range; independent market estimates put installed Indian capacity ",
          "near 950 MW in 2024 and about 1.28 GW in mid-2025. ",
          tags$b("This app uses the central 1,000 MW anchor throughout"), ", which is why ",
          "the capacity box reads 1,000 MW with every filter cleared, and why electricity ",
          "and carbon totals match the paper's central scenario."),
        p(tags$small(tags$b("Consequence worth understanding:"), " an individual facility's ",
          "megawatt figure is an allocation, not a measurement. The anchor fixes the ",
          "national total, and the class weights decide only how that total is divided ",
          "between facilities. Treat single-facility values as indicative and national or ",
          "state aggregates as the meaningful quantities.")),

        h4("Reading the PM2.5 increment"),
        p("This is not measured pollution. It is the modelled annual-mean PM2.5 ",
          "attributable to the electricity these facilities consume, obtained by assigning ",
          "each facility's demand to the generators that respond at the margin and ",
          "dispersing the resulting emissions through a reduced-complexity atmospheric ",
          "model. It is a scenario-consistent estimate, not an exact one."),

        h4("Other data sources"),
        tags$ul(
          tags$li("Social composition: National Family Health Survey NFHS-5 (2019-21), ",
                  "district design-weighted prevalences."),
          tags$li("Relative Wealth Index: ",
                  tags$a(href="https://dataforgood.facebook.com/dfg/tools/relative-wealth-index",
                         target="_blank", "Meta Data for Good"), " (Chi et al., 2022)."),
          tags$li("Power plants: ",
                  tags$a(href="https://datasets.wri.org/datasets/global-power-plant-database",
                         target="_blank", "WRI Global Power Plant Database"), "."),
          tags$li("Water stress: ",
                  tags$a(href="https://www.wri.org/aqueduct", target="_blank",
                         "WRI Aqueduct 4.0"), " baseline water stress."),
          tags$li("PM2.5: Washington University ", tags$a(
                    href="https://sites.wustl.edu/acag/datasets/surface-pm2-5/",
                    target="_blank", "ACAG"), " surface product. Surface NO2 (Anenberg ",
                  "et al., 2022) and ozone (Wang et al., 2025) from published gridded products."),
          tags$li("Geocoding fallbacks: ", tags$a(href="https://www.geonames.org/",
                  target="_blank", "GeoNames"), " postal and cities gazetteers."),
          tags$li("Dispersion: ", tags$a(href="https://inmap.run/", target="_blank",
                  "InMAP"), ", global implementation of Thakrar et al. (2022).")),

        h4("Limits worth knowing"),
        tags$ul(
          tags$li("Coordinates are town-precision; a point locates a facility in its town, not at its site."),
          tags$li("Most facilities do not disclose capacity; it is imputed by operator class and scaled to a national anchor."),
          tags$li("District values are means and hide within-district variation."),
          tags$li("The increment cannot be attributed to any individual facility.")
        )
      ))
  )
)

# ---- server -----------------------------------------------------------------
server <- function(input, output, session) {

  fac_f <- reactive({
    f <- facilities[facilities$dc_type %in% input$types, ]
    if (input$state != "All India") f <- f[!is.na(f$state_name) & f$state_name == input$state, ]
    f
  })

  dist_f <- reactive({
    if (input$state == "All India") districts
    else districts[!is.na(districts$state_name) & districts$state_name == input$state, ]
  })

  output$vb_n   <- renderText(format(nrow(fac_f()), big.mark = ","))
  output$vb_mw  <- renderText(paste0(fmtnum(sum(fac_f()$mw_it,      na.rm = TRUE), 0), " MW"))
  output$vb_gwh <- renderText(paste0(fmtnum(sum(fac_f()$e_fac_gwh,  na.rm = TRUE), 0), " GWh/yr"))
  output$vb_co2 <- renderText(paste0(fmtnum(sum(fac_f()$co2_kt,     na.rm = TRUE)/1000, 2), " Mt/yr"))

  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(minZoom = 4)) |>
      addProviderTiles(providers$CartoDB.PositronNoLabels) |>
      setView(lng = 79, lat = 22, zoom = 5)
  })

  observe({
    spec <- IND[[input$ind]]
    d <- dist_f()
    v <- d[[spec$col]]
    vshow <- if (isTRUE(spec$log)) log10(pmax(v, 1e-5)) else v
    pal <- colorNumeric(spec$pal, domain = vshow, na.color = "#f0f0f0",
                        reverse = isTRUE(spec$rev))

    lab <- sprintf(
      "<b>%s</b><br/>%s<br/><hr style='margin:4px 0'/>
       %s: <b>%s</b> %s<br/>
       Data centres: %s &nbsp;|&nbsp; Coal capacity: %s MW<br/>
       Population: %s &nbsp;|&nbsp; Urban share: %s<br/>
       Wealth score: %s &nbsp;|&nbsp; SC/ST: %s &nbsp;|&nbsp; BPL: %s<br/>
       PM2.5 increment: %s ug/m3",
      d$dist_name, d$state_name,
      input$ind, fmtnum(v, spec$fmt), spec$unit,
      fmtnum(d$dc_count, 0), fmtnum(d$coal_mw, 0),
      fmtnum(d$pop_2020, 0), fmtnum(d$urban_share_2019, 2),
      fmtnum(d$wealth_mean_2019, 0), fmtnum(d$share_scst_2019, 2),
      fmtnum(d$share_bpl_2019, 2), fmtnum(d$dpm25, 4)
    ) |> lapply(htmltools::HTML)

    m <- leafletProxy("map", data = d) |>
      clearShapes() |> clearMarkers() |> clearControls() |>
      addPolygons(
        fillColor = ~pal(vshow), fillOpacity = 0.78,
        color = "white", weight = 0.4,
        highlightOptions = highlightOptions(weight = 2, color = "#333", bringToFront = TRUE),
        label = lab) |>
      addLegend("bottomright", pal = pal, values = vshow, opacity = 0.85,
                title = paste0(input$ind, "<br/><small>", spec$unit,
                               if (isTRUE(spec$log)) " (log scale)" else "", "</small>"),
                labFormat = if (isTRUE(spec$log))
                  labelFormat(transform = function(x) 10^x) else labelFormat())

    if (isTRUE(input$show_plants) && nrow(plants) > 0) {
      m <- m |> addCircleMarkers(
        data = plants,
        radius = ~pmax(2, sqrt(pmax(capacity_mw, 1))/12),
        color = ~ifelse(primary_fuel == "Coal", "#4d4d4d", "#1b7837"),
        stroke = FALSE, fillOpacity = 0.55,
        label = ~sprintf("%s - %s, %s MW", name, primary_fuel, round(capacity_mw)))
    }

    if (isTRUE(input$show_osm) && nrow(osm_check) > 0) {
      m <- m |> addCircleMarkers(
        data = osm_check, radius = 9,
        color = "#111", weight = 1.4, fill = FALSE, opacity = 0.85,
        label = ~lapply(sprintf(
          "<b>%s</b><br/>OpenStreetMap cross-check<br/>%s, %s",
          label, dist_name, state_name), htmltools::HTML))
    }

    f <- fac_f()
    if (isTRUE(input$show_fac) && nrow(f) > 0) {
      m <- m |> addCircleMarkers(
        data = f,
        radius = ~pmax(3.5, sqrt(pmax(mw_it, 0.3)) * 2.2),
        color = "white", weight = 0.9,
        fillColor = ~unname(TYPE_COL[dc_type]), fillOpacity = 0.92,
        label = ~lapply(sprintf(
          "<b>%s</b><br/>%s<br/>%s<br/>%s, %s<br/><hr style='margin:4px 0'/>
           IT capacity: %s MW<br/>Electricity: %s GWh/yr<br/>
           CO2: %s kt/yr<br/>On-site water: %s ML/yr<br/>Electricity-related water: %s ML/yr",
          name, operator, dc_type,
          dist_name, state_name,
          fmtnum(mw_it, 2), fmtnum(e_fac_gwh, 1), fmtnum(co2_kt, 1),
          fmtnum(scope1_ml, 1), fmtnum(scope2_ml, 1)), htmltools::HTML))
    }
    m
  })

  output$dtab <- renderDT({
    d <- sf::st_drop_geometry(dist_f()) |>
      select(any_of(c("dist_name","state_name","dc_count","pop_2020","wealth_mean_2019",
                      "urban_share_2019","share_scst_2019","share_bpl_2019",
                      "pm25_acag_local","no2_surf","coal_mw","bws_raw","dpm25"))) |>
      arrange(desc(dc_count))
    datatable(d, rownames = FALSE, filter = "top",
              extensions = "Buttons",
              options = list(pageLength = 20, dom = "Bfrtip", buttons = c("csv","excel"),
                             scrollX = TRUE)) |>
      formatRound(c("wealth_mean_2019","pop_2020","coal_mw"), 0) |>
      formatRound(c("urban_share_2019","share_scst_2019","share_bpl_2019",
                    "pm25_acag_local","no2_surf","bws_raw"), 2) |>
      formatRound("dpm25", 4)
  })

  output$ftab <- renderDT({
    f <- sf::st_drop_geometry(fac_f()) |>
      select(any_of(c("name","operator","dc_type","dist_name","state_name",
                      "mw_it","e_fac_gwh","co2_kt","scope1_ml","scope2_ml"))) |>
      arrange(desc(mw_it))
    datatable(f, rownames = FALSE, filter = "top",
              extensions = "Buttons",
              options = list(pageLength = 20, dom = "Bfrtip", buttons = c("csv","excel"),
                             scrollX = TRUE)) |>
      formatRound(c("mw_it","e_fac_gwh","co2_kt","scope1_ml","scope2_ml"), 2)
  })
}

shinyApp(ui, server)
