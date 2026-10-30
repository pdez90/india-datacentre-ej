# =============================================================================
# India Data Centre Environmental Justice Explorer
# Companion app to: "The Environmental Geography of Data Centers in India"
#
# Data in data/ are baked by scripts/22_build_shiny_data.py (plus 30 and 22b) from the pipeline
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
# The 2011/2015 geography predates Telangana: show its ten districts under Telangana, as the paper does
# (scripts/00_config.R TELANGANA_DISTRICTS), so the state filter and labels match the policy table.
TELANGANA_DISTRICTS <- c("Adilabad", "Nizamabad", "Karimnagar", "Medak", "Hyderabad",
                         "Rangareddy", "Mahbubnagar", "Nalgonda", "Warangal", "Khammam")
to_telangana <- function(x) {
  if (all(c("state_name", "dist_name") %in% names(x)))
    x$state_name <- ifelse(!is.na(x$state_name) & x$state_name == "Andhra Pradesh" & x$dist_name %in% TELANGANA_DISTRICTS,
                           "Telangana", x$state_name)
  x
}
districts <- to_telangana(districts); facilities <- to_telangana(facilities)
plants <- to_telangana(plants); osm_check <- to_telangana(osm_check)
# Public, sourced facility table (scripts/24_public_inventory.R; data dictionary in DATA.md)
PUB_CSV    <- "data/india_datacentres_public.csv"
PUB_ZIP    <- "data/india_datacentres_documented.zip"
ESMI_CSV   <- "data/district_power_interruptions.csv"        # district supply-interruption hours (scripts/28, Prayas ESMI)
ESMI_MON   <- "data/esmi_monitor_power_interruptions.csv"    # the same, monitor by monitor
DIESEL_CSV <- "data/power_interruptions_backup_diesel.csv"   # hosting districts: interruption hours -> backup-diesel inputs and results (scripts/30)
EF_CSV     <- "data/emission_factors.csv"                    # every emission factor and intensity used, with source and use (scripts/30)
esmi_d     <- if (file.exists(ESMI_CSV)) read.csv(ESMI_CSV, stringsAsFactors = FALSE) else NULL   # table + data dictionary + every cited URL with its archived copy (scripts/22)
pubtab     <- if (file.exists(PUB_CSV)) read.csv(PUB_CSV, stringsAsFactors = FALSE) else NULL
policies   <- read.csv("data/policies.csv", stringsAsFactors = FALSE)
pol_src    <- read.csv("data/policy_sources.csv", stringsAsFactors = FALSE)
H          <- jsonlite::read_json("data/headline.json")

# ---- how each operating facility's IT load was set: the paper's calculation, recomputed from the facility layer ----
# (Equation S4.6). Published live loads are kept; the commercial market (colocation + hyperscale) is calibrated
# to the national anchor; every facility without a published load gets class weight x one MW-per-weight-unit
# factor (lambda); listings that fail the identity screen get 0 MW. tests/check_app_data.R checks this
# reproduces every facility's mw_it and the 2,051 MW total.
CLASS_WEIGHT <- c(hyperscale = 10, colocation = 3, enterprise = 1, government = 1, telecom = 0.5)
CAP <- local({
  f <- sf::st_drop_geometry(facilities); f <- f[f$is_operating %in% TRUE, ]
  com <- f$dc_type %in% c("hyperscale", "colocation"); rep <- !is.na(f$mw_reported)
  unsized <- !rep & f$mw_it == 0; mod <- !rep & !unsized
  anchor <- as.numeric(H$anchor_commercial_mw)
  vc <- sum(f$mw_reported[com & rep]); wc <- sum(CLASS_WEIGHT[f$dc_type[com & mod]])
  lam <- (anchor - vc) / wc
  types <- names(CLASS_WEIGHT)
  tab <- data.frame(type = types, weight = unname(CLASS_WEIGHT),
    n_rep = sapply(types, function(t) sum(f$dc_type == t & rep)),
    mw_rep = sapply(types, function(t) sum(f$mw_reported[f$dc_type == t & rep])),
    n_mod = sapply(types, function(t) sum(f$dc_type == t & mod)),
    mw_each = unname(CLASS_WEIGHT) * lam,
    mw_mod = sapply(types, function(t) sum(f$mw_it[f$dc_type == t & mod])),
    n_unsized = sapply(types, function(t) sum(f$dc_type == t & unsized)),
    mw_total = sapply(types, function(t) sum(f$mw_it[f$dc_type == t])), row.names = NULL)
  list(n = nrow(f), anchor = anchor, lam = lam, vc = vc, wc = wc, tab = tab,
       n_rep = sum(rep), mw_rep = sum(f$mw_reported[rep]), n_rep_c = sum(com & rep),
       n_mod_c = sum(com & mod), n_mod_n = sum(!com & mod), mw_mod_n = sum(f$mw_it[!com & mod]),
       n_rep_n = sum(!com & rep), mw_rep_n = sum(f$mw_reported[!com & rep]), n_unsized = sum(unsized),
       total = sum(f$mw_it), max_err = max(abs(f$mw_it[mod] - CLASS_WEIGHT[f$dc_type[mod]] * lam)))
})

# ---- From electricity to health: the air-quality chain (operating scope), recomputed from the app's own data ----
# Each step reproduces a number of the paper; tests/check_app_data.R checks that the emissions, the plant
# allocation and the deaths sum back to headline.json. GEMM NCD+LRI parameters and national constants: SI S4.1.
GEMM <- list(theta = 0.143, alpha = 1.6, mu = 15.5, nu = 36.8, cf = 2.4, adult = 0.562, y0 = 0.0087)
gemm_hr <- function(z) exp(GEMM$theta * log(1 + z / GEMM$alpha) / (1 + exp(-(z - GEMM$mu) / GEMM$nu)))
AQ_ST_FIX <- c("Nct Of Delhi" = "Delhi", "Chattisgarh" = "Chhattisgarh", "Uttarakhaand" = "Uttarakhand")
aq_fixst <- function(s) unname(ifelse(s %in% names(AQ_ST_FIX), AQ_ST_FIX[s], s))
# step selector with a play button (the server side is aq_player())
step_control <- function(id, labels) div(class = "d-flex flex-wrap align-items-center gap-2 mb-2",
  radioButtons(id, NULL, inline = TRUE, choices = setNames(seq_along(labels), sprintf("%d. %s", seq_along(labels), labels))),
  actionButton(paste0(id, "_play"), "Play", icon = icon("play"), class = "btn-sm btn-outline-primary ms-2"))
AQ <- local({
  fixst <- aq_fixst
  f <- sf::st_drop_geometry(facilities); f <- f[f$is_operating %in% TRUE, ]
  f$load_state <- fixst(f$state_name)
  el <- aggregate(cbind(gwh = e_fac_gwh, mw = mw_it, n = 1) ~ load_state, data = f, FUN = sum)
  ef <- read.csv(EF_CSV, stringsAsFactors = FALSE)
  ef <- ef[grepl("^Marginal emission factor", ef$factor) & ef$level == "central", ]
  ef$pol <- toupper(sub("^Marginal emission factor, ", "", ef$factor))
  getf <- function(pol, st) ef$value[ef$pol == pol & ef$applies_to == st][1]
  for (p in c("CO2", "SO2", "NOX", "PM2.5")) {
    el[[paste0("ef_", p)]] <- vapply(el$load_state, function(s) getf(p, s), 0)
    el[[paste0("t_", p)]] <- el$gwh * el[[paste0("ef_", p)]]          # GWh x kg/MWh = t
  }
  el <- el[order(-el$t_SO2), ]
  pl <- sf::st_drop_geometry(plants); pl$st <- fixst(pl$state)
  coal_cap <- tapply(pl$capacity_mw[pl$fuel == "Coal"], pl$st[pl$fuel == "Coal"], sum)
  # allocation of SO2 to plants, step by step (the same rule as the paper; gas : coal = 1 : 5,750 for SO2)
  r_so2 <- 5750
  so2_coal_state <- el$t_SO2 * r_so2 / (r_so2 + 1); names(so2_coal_state) <- el$load_state
  no_coal <- setdiff(el$load_state, names(coal_cap))
  pool <- sum(so2_coal_state[no_coal]); nat_coal <- sum(coal_cap)
  pl$so2_check <- NA_real_
  ic <- pl$fuel == "Coal"
  pl$so2_check[ic] <- ifelse(pl$st[ic] %in% names(so2_coal_state), so2_coal_state[pl$st[ic]], 0) * pl$capacity_mw[ic] / coal_cap[pl$st[ic]] +
                      pool * pl$capacity_mw[ic] / nat_coal
  d <- sf::st_drop_geometry(districts)
  d <- d[!is.na(d$dpm25) & !is.na(d$pop_2020) & !is.na(d$pm25_acag_local), ]
  d$z <- pmax(d$pm25_acag_local - GEMM$cf, 0)
  d$base_deaths <- d$pop_2020 * GEMM$adult * GEMM$y0
  d$deaths_1step <- d$base_deaths * (gemm_hr(d$z + d$dpm25) / gemm_hr(d$z) - 1)
  d <- d[order(-d$deaths), ]
  list(el = el, plants = pl, coal_cap = coal_cap, no_coal = no_coal, pool = pool, nat_coal = nat_coal, d = d,
       gwh = sum(f$e_fac_gwh), mw = sum(f$mw_it), n = nrow(f),
       so2 = sum(el$t_SO2), nox = sum(el$t_NOX), pm = sum(el$t_PM2.5), co2 = sum(el$t_CO2),
       plant_err = max(abs(pl$so2_check[ic] - pl$so2_t[ic])), deaths_1step = sum(d$deaths_1step), deaths_model = sum(d$deaths, na.rm = TRUE))
})

# animated overview of the chain (illustrative: InMAP itself is a steady-state, annual-average model)
aq_animation <- function() {
  A <- AQ; I <- H$inmap_operating
  puff <- function(i) sprintf('<circle class="aq-puff" cx="470" cy="70" r="7" style="animation-delay:%.1fs"/>', i * 0.8)
  svg <- sprintf('
<svg viewBox="0 0 1000 250" role="img" aria-label="Animated diagram: data-centre electricity, power plants, emissions drifting downwind and forming particles, people exposed, health impact" style="width:100%%;max-width:1000px;height:auto">
  <defs>
    <marker id="aqarr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#2c3e50"/></marker>
  </defs>
  <!-- 1 data centre -->
  <g class="aq-stage" style="animation-delay:0s">
    <rect x="40" y="70" width="90" height="90" rx="6" fill="#2c3e50"/>
    <g fill="#18bc9c"><rect x="52" y="82" width="66" height="8" rx="2"/><rect x="52" y="98" width="66" height="8" rx="2"/><rect x="52" y="114" width="66" height="8" rx="2"/><rect x="52" y="130" width="66" height="8" rx="2"/></g>
    <circle class="aq-blink" cx="110" cy="86" r="2.5" fill="#f39c12"/><circle class="aq-blink" cx="110" cy="118" r="2.5" fill="#f39c12" style="animation-delay:.7s"/>
    <text x="85" y="185" text-anchor="middle" class="aq-lab">Data centres</text>
    <text x="85" y="203" text-anchor="middle" class="aq-num">%s TWh/yr</text>
  </g>
  <!-- electricity flow -->
  <path class="aq-flow" d="M140,115 L250,115" stroke="#f39c12" stroke-width="4" fill="none" marker-end="url(#aqarr)"/>
  <text x="195" y="105" text-anchor="middle" class="aq-small">electricity</text>
  <!-- 2 grid pylon -->
  <g class="aq-stage" style="animation-delay:1s">
    <path d="M285,160 L300,60 L315,160 M290,125 L310,125 M294,95 L306,95 M280,75 L320,75" stroke="#2c3e50" stroke-width="3" fill="none"/>
    <text x="300" y="185" text-anchor="middle" class="aq-lab">State grids</text>
    <text x="300" y="203" text-anchor="middle" class="aq-num">marginal plants</text>
  </g>
  <path class="aq-flow" d="M330,115 L420,115" stroke="#f39c12" stroke-width="4" fill="none" marker-end="url(#aqarr)" style="animation-delay:.4s"/>
  <!-- 3 power plant -->
  <g class="aq-stage" style="animation-delay:2s">
    <rect x="430" y="110" width="70" height="50" fill="#7b8a8b"/>
    <rect x="462" y="70" width="16" height="42" fill="#95a5a6"/>
    <text x="470" y="185" text-anchor="middle" class="aq-lab">Coal and gas plants</text>
    <text x="470" y="203" text-anchor="middle" class="aq-num">%s kt SO2, %s kt NOx</text>
  </g>
  %s
  <!-- 4 atmosphere / InMAP -->
  <text x="640" y="30" text-anchor="middle" class="aq-small">InMAP: wind carries the gases; they turn into fine particles (sulfate, nitrate)</text>
  <!-- 5 people -->
  <g class="aq-stage" style="animation-delay:3s" fill="#2c3e50">
    <g transform="translate(720,120)"><circle cx="0" cy="0" r="7"/><rect x="-7" y="9" width="14" height="24" rx="5"/></g>
    <g transform="translate(755,120)"><circle cx="0" cy="0" r="7"/><rect x="-7" y="9" width="14" height="24" rx="5"/></g>
    <g transform="translate(790,120)"><circle cx="0" cy="0" r="7"/><rect x="-7" y="9" width="14" height="24" rx="5"/></g>
    <g transform="translate(825,120)"><circle cx="0" cy="0" r="7"/><rect x="-7" y="9" width="14" height="24" rx="5"/></g>
    <text x="772" y="185" text-anchor="middle" class="aq-lab" fill="#2c3e50">People downwind</text>
    <text x="772" y="203" text-anchor="middle" class="aq-num" fill="#2c3e50">+%s ug/m3 on average</text>
  </g>
  <!-- 6 health -->
  <g class="aq-stage" style="animation-delay:4s">
    <path class="aq-beat" d="M930,135 C905,115 900,95 915,88 C925,84 930,92 930,97 C930,92 935,84 945,88 C960,95 955,115 930,135 z" fill="#e74c3c"/>
    <text x="930" y="185" text-anchor="middle" class="aq-lab">Health</text>
    <text x="930" y="203" text-anchor="middle" class="aq-num">~%s deaths/yr</text>
  </g>
  <text x="500" y="240" text-anchor="middle" class="aq-small" fill="#7b8a8b">Illustration of the chain. The model itself computes an annual average, not a moving plume.</text>
</svg>',
    fmtnum(A$gwh / 1000, 1), fmtnum(A$so2 / 1000, 0), fmtnum(A$nox / 1000, 0),
    paste(vapply(0:5, puff, ""), collapse = "\n  "), fmtnum(I$pwm_ugm3, 3), fmtnum(round(I$deaths_per_yr, -2)))
  tagList(tags$style(HTML('
    .aq-lab { font: 600 14px sans-serif; fill: #2c3e50; }
    .aq-num { font: 13px sans-serif; fill: #18bc9c; font-weight: 600; }
    .aq-small { font: 12px sans-serif; fill: #2c3e50; }
    .aq-flow { stroke-dasharray: 10 8; animation: aqflow 1s linear infinite; }
    @keyframes aqflow { to { stroke-dashoffset: -18; } }
    .aq-puff { fill: #95a5a6; opacity: 0; animation: aqpuff 4.8s ease-in infinite; }
    @keyframes aqpuff {
      0%   { transform: translate(0,0) scale(.6); fill: #95a5a6; opacity: 0; }
      8%   { opacity: .9; }
      45%  { transform: translate(140px,-35px) scale(1.3); fill: #b0a28f; opacity: .85; }
      75%  { transform: translate(250px,10px) scale(.9); fill: #e67e22; opacity: .9; }
      100% { transform: translate(330px,45px) scale(.5); fill: #e67e22; opacity: 0; }
    }
    .aq-stage { animation: aqstage 6s ease-in-out infinite; }
    @keyframes aqstage { 0%, 100% { opacity: .55; } 10%, 30% { opacity: 1; } }
    .aq-blink { animation: aqblink 1.4s step-end infinite; }
    @keyframes aqblink { 50% { opacity: 0; } }
    .aq-beat { transform-origin: 930px 110px; animation: aqbeat 1.2s ease-in-out infinite; }
    @keyframes aqbeat { 0%,100% { transform: scale(1); } 15% { transform: scale(1.12); } 30% { transform: scale(1); } }
    @media (prefers-reduced-motion: reduce) { .aq-flow, .aq-puff, .aq-stage, .aq-blink, .aq-beat { animation: none; } .aq-puff { opacity: .8; } }
  ')), div(class = "card mb-4", div(class = "card-body", HTML(svg))))
}

# the InMAP grid behind the district increments (operating scope): one row per grid cell (lon/lat box, gridded
# population, increment by species) and one row per cell-district piece (share of the cell's area in the district).
# Built from the InMAP output by the same intersection as scripts/16d; tests check it reproduces every district.
AQG <- if (file.exists("data/inmap_grid.rds")) local({
  g <- readRDS("data/inmap_grid.rds"); cl <- as.data.frame(g$cells); pc <- as.data.frame(g$pieces)
  pc <- cbind(pc, cl[match(pc$cell, cl$cell), c("xmin", "ymin", "xmax", "ymax", "pop", "pm", "prim", "so4", "no3")])
  pc$popw <- pc$pop * pc$frac
  acag <- AQ$d$pm25_acag_local[match(pc$zone_uid, AQ$d$zone_uid)]
  pc$z <- pmax(acag - GEMM$cf, 0)
  pc$deaths <- ifelse(is.na(pc$z), 0, pc$popw * GEMM$adult * GEMM$y0 * (gemm_hr(pc$z + pc$pm) / gemm_hr(pc$z) - 1))
  w <- pc$popw
  comp <- c(total = sum(w * pc$pm), sulfate = sum(w * pc$so4), nitrate = sum(w * pc$no3), primary = sum(w * pc$prim)) / sum(w)
  list(pieces = pc, comp = comp)
}) else NULL

# Where one load state's emissions go (SI S4.1; scripts/16b): split gas : coal by a fixed national ratio per pollutant,
# then across that state's plants of each fuel by nameplate capacity; with no plant of a fuel in the state, across
# the national fleet of that fuel.
GAS_RATIO <- c(SO2 = 1 / 5750, NOX = 1 / 57.5, PM2.5 = 1 / 230)
aq_alloc <- function(state, pol) {
  el <- AQ$el[AQ$el$load_state == state, ]; tot <- el[[paste0("t_", pol)]]
  gf <- GAS_RATIO[[pol]] / (1 + GAS_RATIO[[pol]])
  pl <- AQ$plants; pl$idx <- seq_len(nrow(pl))
  out <- lapply(c("Coal", "Gas"), function(fu) {
    t_fuel <- tot * if (fu == "Gas") gf else 1 - gf
    own <- pl[pl$fuel == fu & pl$st == state, ]
    tgt <- if (nrow(own)) own else pl[pl$fuel == fu, ]
    if (!nrow(tgt)) return(NULL)
    data.frame(fuel = fu, idx = tgt$idx, name = tgt$name, plant_state = tgt$st, capacity_mw = tgt$capacity_mw,
               share = tgt$capacity_mw / sum(tgt$capacity_mw), t = t_fuel * tgt$capacity_mw / sum(tgt$capacity_mw),
               national = !nrow(own), fleet_mw = sum(tgt$capacity_mw), t_fuel = t_fuel, stringsAsFactors = FALSE)
  })
  list(total = tot, gas_frac = gf, el = el, rows = do.call(rbind, out))
}

aq_walkthrough <- function() {
  A <- AQ; I <- H$inmap_operating
  step <- function(k, title, ...) div(class = "d-flex mb-4",
    div(class = "me-3", tags$span(class = "badge rounded-pill bg-primary", style = "font-size:0.95rem", k)),
    div(class = "flex-grow-1", tags$b(title), ...))
  tbl <- function(head, rows, cls = "table table-sm mt-2 mb-1") tags$table(class = cls,
    tags$thead(tags$tr(lapply(seq_along(head), function(i) tags$th(class = if (i > 1) "text-end", head[i])))),
    tags$tbody(rows))
  tr <- function(...) { v <- list(...); tags$tr(lapply(seq_along(v), function(i) tags$td(class = if (i > 1) "text-end", v[[i]]))) }
  el <- A$el; top <- head(el, 6)
  pl <- A$plants[A$plants$fuel == "Coal", ]; pl <- pl[order(-pl$so2_t), ]; p1 <- pl[1, ]
  st1 <- p1$st; s_state <- el$t_SO2[el$load_state == st1] * 5750 / 5751
  dd <- A$d; dtop <- head(dd[order(-dd$dpm25), ], 8)
  mh <- el[el$load_state == "Maharashtra", ]
  div(class = "p-3", style = "max-width: 1100px",
    h3("From electricity to health: how the air-quality model works"),
    p(class = "text-muted",
      "The pollution in this app is not measured near data centres. It is modelled: the electricity the sector draws is ",
      "traced to the power plants that would generate it, their extra emissions are dispersed through the atmosphere with the ",
      "InMAP air-quality model, and the resulting fine-particle (PM2.5) increment is converted to deaths. ",
      "This tab walks through each step with the operating inventory's numbers, so every figure can be checked. ",
      "The paper gives the full method in SI sections S4 and S4.1."),
    aq_animation(),
    div(class = "card mb-4", div(class = "card-body",
      h4(class = "card-title", "Follow one facility"),
      p(class = "text-muted", "Pick a data centre to see its electricity, the emissions it causes, and the power plants those emissions are assigned to. ",
        "Plants are not chosen by distance: a facility draws on its own state's grid, so its emissions go to its state's plants in proportion to their capacity ",
        "(or to the national fleet where its state has no plant of a fuel), as in steps 2 and 3 below."),
      fluidRow(column(6, selectizeInput("aq_fac", "Facility", width = "100%", choices = NULL)),
               column(6, tags$label(class = "form-label", "Step (click one, or press play)"),
                      step_control("aq_fstep", c("The facility", "Its emissions", "The plants", "Where the pollution goes")))),
      fluidRow(column(7, leafletOutput("aq_facmap", height = 440)), column(5, uiOutput("aq_fac_text"))))),

    step(1, "How much electricity the data centres draw.",
      p(sprintf("Each facility's IT load (MW; see the step-by-step calculation on the Facilities tab) is converted to electricity with a power usage effectiveness (PUE) of 1.6, for cooling and other overheads, and an average utilisation of 0.7: 1 MW of IT load x 1.6 x 0.7 x 8,760 hours = %s MWh a year. ",
                fmtnum(1.6 * 0.7 * 8760)),
        sprintf("Across the %d operating facilities, %s MW of IT load draws %s GWh (%s TWh) a year, about %s%% of India's generation.",
                A$n, fmtnum(A$mw), fmtnum(A$gwh), fmtnum(A$gwh / 1000, 1), fmtnum(H$pct_nat_gen_operating, 1)))),

    step(2, "Which emissions that electricity causes.",
      p("A new, round-the-clock load is met by the plants that ramp up at the margin of each state's grid. ",
        "Sengupta et al. (2022) estimate, for every state, the extra emissions per extra MWh of demand (marginal emission factors), by season and time of day; ",
        "we average them over a flat 24-hour load. Each facility draws on its own state's grid, so its emissions are its electricity times its state's factors. ",
        sprintf("For example, Maharashtra's facilities use %s GWh a year; at %s kg of SO2 per MWh that is %s t of SO2.",
                fmtnum(mh$gwh), fmtnum(mh$ef_SO2, 2), fmtnum(mh$t_SO2))),
      tbl(c("Load state", "Facilities", "Electricity (GWh/yr)", "SO2 factor (kg/MWh)", "SO2 (t/yr)", "NOx (t/yr)", "PM2.5 (t/yr)"),
          c(lapply(seq_len(nrow(top)), function(i) with(top[i, ], tr(load_state, n, fmtnum(gwh), fmtnum(ef_SO2, 2), fmtnum(t_SO2), fmtnum(t_NOX), fmtnum(t_PM2.5)))),
            list(tr(sprintf("%d other states", nrow(el) - nrow(top)), sum(el$n[-(1:6)]), fmtnum(sum(el$gwh[-(1:6)])), "", fmtnum(sum(el$t_SO2[-(1:6)])), fmtnum(sum(el$t_NOX[-(1:6)])), fmtnum(sum(el$t_PM2.5[-(1:6)]))),
                 tags$tr(class = "fw-bold", tags$td("All India"), tags$td(class = "text-end", A$n), tags$td(class = "text-end", fmtnum(A$gwh)), tags$td(),
                         tags$td(class = "text-end", fmtnum(A$so2)), tags$td(class = "text-end", fmtnum(A$nox)), tags$td(class = "text-end", fmtnum(A$pm)))))),
      p(class = "small text-muted", sprintf("Totals: %s kt SO2, %s kt NOx and %s kt primary PM2.5 a year (and %s Mt of CO2), emitted at power plants, not at the data centres.",
                                            fmtnum(A$so2 / 1000, 1), fmtnum(A$nox / 1000, 1), fmtnum(A$pm / 1000, 1), fmtnum(A$co2 / 1e6, 1)))),

    step(3, "Which power plants emit them.",
      p("Each state's emissions are placed at that state's own plants: first split between coal and gas by fixed national ratios (for SO2, gas : coal = 1 : 5,750, so gas carries almost none), ",
        "then shared among the state's plants of that fuel in proportion to their capacity (WRI Global Power Plant Database: 253 coal and 68 gas plants; ",
        "one database coordinate is corrected: SOLAPUR STPP, NTPC's 1,320 MW coal plant, which the database places near Shimla, is moved to Solapur, Maharashtra). ",
        sprintf("States with no coal plant of their own (%s) have their share spread over all coal plants nationally, again by capacity. ", paste(A$no_coal, collapse = ", ")),
        "Plants release at a fixed height (200 m for coal stacks, 100 m for gas), and only SO2, NOx and primary PM2.5 are added."),
      p(sprintf(paste0("Example: %s, the plant that receives the most SO2, is a %s MW coal plant in %s. %s's coal plants total %s MW, so it takes %s / %s = %s%% of the %s t of coal SO2 caused by %s's data centres (%s t). ",
                       "It also takes its share of the national coal fleet (%s / %s MW) of the %s t from states without coal plants (%s t): %s t a year in all."),
                p1$name, fmtnum(p1$capacity_mw), st1, st1, fmtnum(A$coal_cap[[st1]]), fmtnum(p1$capacity_mw), fmtnum(A$coal_cap[[st1]]),
                fmtnum(100 * p1$capacity_mw / A$coal_cap[[st1]], 1), fmtnum(s_state), st1, fmtnum(s_state * p1$capacity_mw / A$coal_cap[[st1]]),
                fmtnum(p1$capacity_mw), fmtnum(A$nat_coal), fmtnum(A$pool), fmtnum(A$pool * p1$capacity_mw / A$nat_coal), fmtnum(p1$so2_t))),
      p("Choose a load state and a pollutant to follow its emissions to individual plants:"),
      fluidRow(column(5, selectInput("aq_state", "Load state (where the data centres are)", width = "100%",
                                     choices = setNames(el$load_state, sprintf("%s (%d %s)", el$load_state, el$n, ifelse(el$n == 1, "facility", "facilities"))))),
               column(7, radioButtons("aq_pol", "Pollutant", inline = TRUE, choices = c("SO2" = "SO2", "NOx" = "NOX", "Primary PM2.5" = "PM2.5")))),
      fluidRow(column(7, uiOutput("aq_alloc_text")), column(5, leafletOutput("aq_plantmap", height = 330))),
      uiOutput("aq_alloc_tab"),
      p(class = "small text-muted mt-2", "Each plant's total also includes its share of the emissions from states that have no plant of its fuel. Switch on \"coal & gas plants\" on the Map tab and hover a plant to see its total attributable SO2, NOx and PM2.5.")),

    step(4, "How the pollution spreads and forms fine particles: InMAP.",
      p(tags$a(href = "https://inmap.run", target = "_blank", "InMAP"), " (Intervention Model for Air Pollution; Tessum et al., 2017), here its global version (Thakrar et al., 2022, v1.9.6), ",
        "is a reduced-complexity air-quality model. Instead of simulating the weather hour by hour, it uses annual-average winds, mixing, rain-out and chemical reaction rates ",
        "pre-computed by the GEOS-Chem chemical transport model, and solves for the annual-average concentration that results from a change in emissions. ",
        "It tracks primary PM2.5 and the particles that form in the air from gases: sulfate from SO2, nitrate from NOx, ammonium from ammonia and organic aerosol from volatile organic compounds. ",
        "Only SO2, NOx and primary PM2.5 are added here, so the increment is ",
        if (!is.null(AQG)) sprintf("%s%% sulfate, %s%% nitrate and %s%% primary PM2.5 (population-weighted), with ammonium and secondary organic aerosol making up the rest. ",
                                   fmtnum(100 * AQG$comp[["sulfate"]] / AQG$comp[["total"]]), fmtnum(100 * AQG$comp[["nitrate"]] / AQG$comp[["total"]]),
                                   fmtnum(100 * AQG$comp[["primary"]] / AQG$comp[["total"]])) else "mostly sulfate. ",
        "The grid is finest where people live (cells of about 4 km in cities) and coarser elsewhere."),
      p("Because the added emissions are a tiny change, the model is run on the data-centre emissions alone, and its output is the extra annual-average PM2.5 in every grid cell. ",
        "Secondary particles form over hours to days, so much of the increment lands hundreds of kilometres downwind of the plants, and far from the data centres.")),

    step(5, "From grid cells to districts and people.",
      p("InMAP returns one increment per grid cell; the paper works with districts. Each cell is cut along district boundaries, its people are shared between the pieces in proportion to area ",
        "(the grid carries a 2020 population per cell), and a district's increment is the population-weighted mean of its pieces: ",
        tags$code("increment(district) = sum(people in piece x increment of its cell) / sum(people in piece)"), ". ",
        "Pick a district, then click a step or press play to watch the calculation."),
      fluidRow(
        column(5, selectInput("aq_dist", "District", width = "100%",
                              choices = setNames(A$d$zone_uid, sprintf("%s, %s (%s deaths/yr)", A$d$dist_name, A$d$state_name, fmtnum(A$d$deaths, 1))))),
        column(7, tags$label(class = "form-label", "Step (click one, or press play)"),
                  step_control("aq_step", c("Grid cells", "Cut at the boundary", "Weight by people", "District average")))),
      fluidRow(column(7, leafletOutput("aq_gridmap", height = 420)), column(5, uiOutput("aq_grid_text"))),
      uiOutput("aq_pieces_tab"),
      p(class = "mt-3", sprintf("Across India, weighted by population, the average resident receives %s ug/m3 more PM2.5 a year (about 0.13%% of the modelled national baseline of %s ug/m3; Peshin et al., 2024). ",
                fmtnum(I$pwm_ugm3, 4), "45.2"),
        sprintf("%s million people receive at least 0.01 ug/m3, and %s million at least 0.10 ug/m3.", fmtnum(I$pop_ge_0_01_million), fmtnum(I$pop_ge_0_10_million))),
      tbl(c("District (highest increments)", "State", "Increment (ug/m3)", "Population (million)", "Hosts data centres?"),
          lapply(seq_len(nrow(dtop)), function(i) with(dtop[i, ], tr(dist_name, state_name, fmtnum(dpm25, 3), fmtnum(pop_2020 / 1e6, 2), if (dc_count > 0) sprintf("yes (%d)", dc_count) else "no"))))),

    step(6, "From extra PM2.5 to deaths: the GEMM calculation.",
      p("The Global Exposure Mortality Model (GEMM; Burnett et al., 2018) gives how the risk of death from non-communicable diseases and lower respiratory infections (NCD+LRI) in adults 25 and over ",
        "rises with long-term PM2.5. With z the concentration above 2.4 ug/m3 (the lowest level in the underlying studies), the hazard ratio is"),
      tags$pre(class = "bg-light p-2 small", "HR(z) = exp( theta x ln(1 + z/alpha) x w(z) ),   w(z) = 1 / (1 + exp(-(z - mu)/nu))\ntheta = 0.143, alpha = 1.6, mu = 15.5, nu = 36.8"),
      p("The extra deaths in a place are its baseline deaths from these causes times the extra risk the increment adds on top of the PM2.5 already there:"),
      tags$pre(class = "bg-light p-2 small", "deaths = population x 0.562 (share aged 25+) x 0.0087 (NCD+LRI deaths per adult per year) x [ HR(z + increment) / HR(z) - 1 ]"),
      p("For the district chosen in step 5:"),
      uiOutput("aq_health"),
      p(sprintf("Summed over every piece of every district: %s deaths a year, about 2,000 as the paper reports. ",
                fmtnum(if (!is.null(AQG)) sum(AQG$pieces$deaths) else A$deaths_model)),
        "Most fall far from the data centres, in the generation corridors.")),

    step(7, "What this does and does not show.",
      tags$ul(class = "mb-0",
        tags$li("It is a scenario, not a measurement: it assumes the sector's demand is met at the margin of each state's grid, and that each state's emissions come from its own plants in proportion to capacity. It does not trace any facility's actual power purchases."),
        tags$li("Allocating by estimated generation instead of capacity gives the same result (the database's generation is capacity times a fixed factor for each fuel). Flat class weights raise the deaths to about 3,400 and hyperscale-dominant weights lower them to about 1,900; setting the 54 operating facilities that public sources can neither confirm nor refute (237 MW) to zero lowers them to about 1,800 (SI Table S4.1.3)."),
        tags$li("Deaths use one national adult share and baseline death rate, not state- or age-specific rates; the rate used (0.0087 per adult per year) is the upper end of the GBD 2023 range for India at ages 25+ (0.0084-0.0087), and the lower end would give about 2,000. The uncertainty of the GEMM curve and of the dispersion model is not propagated."),
        tags$li(sprintf("In the stock-plus-pipeline scenario (all %s facilities, including those under construction and announced) the population-weighted increment is %s ug/m3 and the deaths about %s a year.",
                        fmtnum(H$n_all), fmtnum(H$inmap_all$pwm_ugm3, 4), fmtnum(H$inmap_all$deaths_per_yr))))))
}

cap_walkthrough <- function() {
  C <- CAP; t <- C$tab; g <- function(x) t[t$type == x, ]
  n1 <- function(x, d = 1) fmtnum(x, d)
  step <- function(k, title, ...) div(class = "d-flex mb-3",
    div(class = "me-3", tags$span(class = "badge rounded-pill bg-primary", style = "font-size:0.95rem", k)),
    div(tags$b(title), p(class = "mb-0", ...)))
  rows <- lapply(seq_len(nrow(t)), function(i) with(t[i, ], tags$tr(
    tags$td(type), tags$td(class = "text-end", format(weight)),
    tags$td(class = "text-end", sprintf("%d (%s MW)", n_rep, n1(mw_rep))),
    tags$td(class = "text-end", sprintf("%d x %s MW = %s MW", n_mod, n1(mw_each, 2), n1(mw_mod))),
    tags$td(class = "text-end", n_unsized), tags$td(class = "text-end", tags$b(n1(mw_total))))))
  div(class = "card mb-4", div(class = "card-body",
    h4(class = "card-title", "How each facility's IT load was set: the calculation, step by step"),
    p(class = "text-muted",
      "Most data centres in India do not publish their IT load (the power drawn by their servers and network equipment). ",
      "This is how a megawatt figure is assigned to each of the ", C$n, " operating facilities, including those that publish none. ",
      "The same numbers are in the paper (section 2.4 and SI section S4); click any facility on the map to see its own calculation."),
    step(1, "Use the published figure wherever one exists.",
      sprintf("%d of the %d operating facilities have a published live capacity, together %s MW. ", C$n_rep, C$n, n1(C$mw_rep)),
      "A labelled IT load is used as published (tier T1); otherwise an unlabelled operational capacity or MVA is taken as IT load (T2), total facility power is divided by the PUE of 1.6 (T3), ",
      "a company-wide or campus figure is shared equally among the operator's sites (T4), or a rack count is taken at 4 kW per rack (T5). ",
      "Figures found only on listing sites (Data Center Map, Baxtel and similar) are never used. Each facility's tier is named in its capacity basis."),
    step(2, "Calibrate the commercial market to a national total.",
      sprintf("Colocation and hyperscale facilities are the commercial market, which Savills India (2026) puts at %s MW of operational IT capacity in the first half of 2026. ", fmtnum(C$anchor)),
      sprintf("%d commercial facilities publish a load (%s MW), so %s - %s = %s MW is left for the %d commercial facilities that publish none.",
              C$n_rep_c, n1(C$vc), fmtnum(C$anchor), n1(C$vc), n1(C$anchor - C$vc), C$n_mod_c)),
    step(3, "Share that remainder by operator class.",
      "A facility without a published load gets a relative weight for its class: hyperscale 10, colocation 3, enterprise 1, government 1, telecom 0.5. ",
      sprintf("The %d unpublished commercial facilities hold %d colocation x 3 + %d hyperscale x 10 = %s weight units, so one weight unit is worth %s / %s = %s MW.",
              C$n_mod_c, g("colocation")$n_mod, g("hyperscale")$n_mod, format(C$wc), n1(C$anchor - C$vc), format(C$wc), n1(C$lam, 2))),
    step(4, "Size each facility: class weight x MW per weight unit.",
      sprintf("An unpublished colocation facility is assigned 3 x %s = %s MW, and an unpublished hyperscale facility 10 x %s = %s MW. ",
              n1(C$lam, 2), n1(3 * C$lam, 2), n1(C$lam, 2), n1(10 * C$lam, 2)),
      "Within a class every unpublished facility gets the same figure: the inventory says where facilities are, not how large each one is."),
    step(5, "Size non-commercial facilities at the same rate, without rescaling.",
      sprintf("Enterprise and government facilities get 1 x %s = %s MW and telecom facilities 0.5 x %s = %s MW. ", n1(C$lam, 2), n1(C$lam, 2), n1(C$lam, 2), n1(0.5 * C$lam, 2)),
      sprintf("No national total exists for these, so they are not scaled to one: %d facilities add %s MW, and %d more publish a load (%s MW).",
              C$n_mod_n, n1(C$mw_mod_n), C$n_rep_n, n1(C$mw_rep_n))),
    step(6, "Assign nothing where the listing may not be a building of its own.",
      sprintf("%d directory listings could not be confirmed as separate buildings with their own load: the listing does not show whether it is a building of its own or a presence inside another provider's. ", C$n_unsized),
      "They stay in the inventory as facilities but are given 0 MW, so no capacity is counted twice or invented for a listing that may not be a separate building."),
    step(7, "Add up.",
      sprintf("%s MW commercial + %s MW non-commercial = %s MW for the operating inventory.",
              fmtnum(C$anchor), n1(C$total - C$anchor), fmtnum(C$total))),
    tags$table(class = "table table-sm mt-2",
      tags$thead(tags$tr(tags$th("Class"), tags$th(class = "text-end", "Weight"), tags$th(class = "text-end", "Published load: facilities (MW)"),
                         tags$th(class = "text-end", "No published load: facilities x MW each"), tags$th(class = "text-end", "Not sized (0 MW)"),
                         tags$th(class = "text-end", "Total MW"))),
      tags$tbody(rows,
        tags$tr(tags$td(tags$b("All")), tags$td(), tags$td(class = "text-end", sprintf("%d (%s MW)", C$n_rep, n1(C$mw_rep))),
                tags$td(class = "text-end", sprintf("%d facilities, %s MW", sum(t$n_mod), n1(sum(t$mw_mod)))),
                tags$td(class = "text-end", C$n_unsized), tags$td(class = "text-end", tags$b(n1(C$total)))))),
    p(class = "small text-muted mb-0",
      tags$b("What this means for a single facility. "), "A modelled figure is an allocation, not a measurement: it ",
      "places the national total across the known facilities in proportion to their class. State and national totals are the meaningful quantities. ",
      "The weights are assumptions; in the paper, flat weights and hyperscale-dominant weights change the non-commercial total but not the 1,800 MW commercial total, ",
      "and anchors of 1,500 and 2,100 MW bound it. In the stock-plus-pipeline scenario, facilities that publish a build-out load keep it, those with only a current published load keep that, and the rest are sized at the same ",
      sprintf("%s MW per weight unit.", n1(C$lam, 2)))))
}
EJ         <- jsonlite::fromJSON("data/ej_panel.json")           # the paper's distributional tables for the "Who benefits, who bears" tab (scripts/22)

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
  "Scope 1 air: backup-diesel NOx"       = list(col="diesel_nox_t", pal="Oranges", fmt=1, unit="t/yr",   grp="chain",
                                                note="; generator hours assumed from measured supply interruptions (ESMI, 2014-2019, mostly low-voltage monitors) plus testing; not measured generator operation"),
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
  "Power interruptions (ESMI, all monitors)"   = list(col="esmi_h_yr",       pal="OrRd", fmt=0, unit="h/yr", log=TRUE, note="; measured 2014-2019 on mostly low-voltage monitors, 79 districts"),
  "Power interruptions (ESMI, urban monitors)" = list(col="esmi_h_yr_urban", pal="OrRd", fmt=0, unit="h/yr", log=TRUE, note="; measured 2014-2019 on mostly low-voltage monitors, 70 districts"),
  "Population (2020)"                    = list(col="pop_2020",                  pal="Purples",fmt=0, unit="people")
)

# the layer picker shows the registry in five groups (the names are the IND keys)
IND_GROUPS <- list(
  "Data centres and their footprint" = names(IND)[1:11],
  "Air pollution and heat (baseline)" = c("Ambient PM2.5 (ACAG)", "Surface NO2", "Summer ozone (MDA8)", "Extreme heat days (>=35 C)"),
  "Wealth and social composition" = c("Asset wealth (NFHS-5 percentile)", "Relative Wealth Index (Chi 2022)", "Urban share", "Share SC/ST",
                                      "Share below poverty line", "Share Muslim", "Share without electricity"),
  "Energy, water and grid reliability" = c("Coal capacity", "Distance to nearest fossil plant", "Baseline water stress (Aqueduct)",
                                           "Power interruptions (ESMI, all monitors)", "Power interruptions (ESMI, urban monitors)"),
  "Population" = "Population (2020)")
stopifnot(setequal(unlist(IND_GROUPS), names(IND)))

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

# ---- "Who benefits, who bears": chart helpers ----------------------------------------------------------
# Colours: hosting / siting = blue, other districts / burden = orange (fixed, never cycled); quintiles = one blue ramp.
EJ_COL  <- c(hosting = "#2a78d6", other = "#eb6834", ink = "#0b0b0b", ink2 = "#52514e", grid = "#e6e5e1")
EJ_RAMP <- c("#c6dbef", "#9ecae1", "#6baed6", "#3182bd", "#08519c")
# map views are sent to the client as plain numbers: a named row from st_coordinates() would serialise lat as {"Y": ...}
fly_payload <- function(lat, lng, zoom) list(lat = unname(as.numeric(lat)), lng = unname(as.numeric(lng)), zoom = unname(as.numeric(zoom)))
wmean <- function(x, w) { k <- !is.na(x) & !is.na(w) & w > 0; if (!any(k)) NA_real_ else sum(x[k] * w[k]) / sum(w[k]) }
ej_bars <- function(v, main, ylab, lab) {
  b <- barplot(v, col = EJ_RAMP, border = NA, names.arg = c("Poorest\nfifth", "2nd", "Middle", "4th", "Richest\nfifth"),
               main = main, ylab = ylab, ylim = c(0, max(v, na.rm = TRUE) * 1.3), cex.names = 0.85, cex.main = 1, font.main = 1,
               col.main = EJ_COL["ink"], col.lab = EJ_COL["ink2"], col.axis = EJ_COL["ink2"], las = 1, yaxt = "n", space = 0.35)
  axis(2, las = 1, col = NA, col.ticks = NA, col.axis = EJ_COL["ink2"], cex.axis = 0.85)
  abline(h = axTicks(2), col = EJ_COL["grid"], lwd = 0.6); barplot(v, col = EJ_RAMP, border = NA, add = TRUE, axes = FALSE, names.arg = rep("", 5), space = 0.35)
  text(b, v, labels = lab, pos = 3, cex = 0.85, col = EJ_COL["ink"], xpd = TRUE, offset = 0.4)
  invisible(b)
}
ej_draw_quint <- function(q) {
  op <- par(mfrow = c(1, 3), mar = c(4.2, 4.6, 2.5, 1), mgp = c(3.2, 0.7, 0), bg = "white", family = "sans"); on.exit(par(op))
  ej_bars(q$Facilities, "Facilities (siting)", "facilities", sprintf("%d\n%s%%", q$Facilities, fmt1(q$`Share of facilities (%)`)))
  ej_bars(q$`Pop-weighted increment (ug/m3)`, "Modelled PM2.5 increment, per person", "population-weighted mean, ug/m3", sprintf("%.4f", q$`Pop-weighted increment (ug/m3)`))
  ej_bars(q$`Attributable deaths (/yr)`, "Attributable deaths, absolute", "deaths per year (GEMM, modelled)", sprintf("%s\n%.1f per M", fmtnum(q$`Attributable deaths (/yr)`), q$`Deaths per million residents`))
}
ej_draw_disp <- function(m) {
  n <- nrow(m)
  op <- par(mar = c(4.8, 14, 2.5, 1), mgp = c(2.2, 0.7, 0), bg = "white", family = "sans"); on.exit(par(op))
  r <- m$`Increment: ratio`; p <- m$`Siting: ratio, P(hosting)`
  xl <- c(min(c(r, p, 0.45), na.rm = TRUE) * 0.8, max(c(r, p, 1.6), na.rm = TRUE) * 1.15)
  plot(NA, xlim = xl, ylim = c(0.5, n + 0.5), log = "x", yaxt = "n", xaxt = "n", ylab = "", xlab = "ratio to the reference group (log scale; 1 = parity)",
       main = "Siting versus burden, group by group", font.main = 1, cex.main = 1, bty = "n",
       col.main = EJ_COL["ink"], col.lab = EJ_COL["ink2"])
  at <- c(0.02, 0.05, 0.1, 0.2, 0.5, 1, 2); at <- at[at >= xl[1] & at <= xl[2]]
  axis(1, at = at, labels = at, col = NA, col.ticks = NA, col.axis = EJ_COL["ink2"], cex.axis = 0.85)
  abline(v = at, col = EJ_COL["grid"], lwd = 0.6); abline(v = 1, col = EJ_COL["ink2"], lty = 2)
  y <- rev(seq_len(n))
  segments(pmin(p, r), y, pmax(p, r), y, col = EJ_COL["grid"], lwd = 3)
  points(p, y, pch = 21, cex = 1.7, bg = EJ_COL["hosting"], col = "white", lwd = 1.2)
  points(r, y, pch = 21, cex = 1.7, bg = EJ_COL["other"], col = "white", lwd = 1.2)
  axis(2, at = y, labels = paste0(m$Contrast, ifelse(m$` ` == "*", " *", "")), las = 1, cex.axis = 0.85, col = NA, col.ticks = NA, col.axis = EJ_COL["ink"])
  legend("topleft", inset = c(0, 0.01), legend = c("siting: chance of living in a hosting district", "burden: modelled PM2.5 increment"),
         pch = 21, pt.bg = EJ_COL[c("hosting", "other")], col = "white", pt.cex = 1.5, bty = "n", cex = 0.85, text.col = EJ_COL["ink2"])
  mtext("* sign of the burden contrast distinguishable from zero (state-clustered bootstrap, sign probability < 0.05)", side = 1, line = 3.5, adj = 1, cex = 0.72, col = EJ_COL["ink2"])
}

# ---- ui ---------------------------------------------------------------------
ui <- page_sidebar(
  title = "India Data Centre Environmental Justice Explorer",
  fillable = FALSE,   # let the page scroll so the map keeps its height instead of being squeezed below the value boxes
  theme = bs_theme(version = 5, bootswatch = "flatly"),

  sidebar = sidebar(
    width = 340,
    radioButtons("scope", "Inventory",
                 choices = c("Operating facilities" = "operating",
                             "Stock plus pipeline (adds under-construction and announced)" = "all"),
                 selected = "operating"),
    selectInput("ind", "District layer", choices = IND_GROUPS, selected = "Data centres (count)"),
    selectizeInput("search", "Find a facility or district", choices = NULL, options = list(placeholder = "type a name, operator or district", maxOptions = 15)),
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
      "District layers are district totals or averages (see each legend) over the 641 Census 2011 districts. The PM2.5 increment is the ",
      "modelled contribution of data-centre electricity demand, dispersed from the coal ",
      "and gas plants assigned the attributable emissions under a marginal-generation model; ",
      "no plant is shown to supply any particular facility. The Scope 1 / Scope 2 chain layers are for the ",
      "operating inventory.")),
    helpText(tags$small(
      "Facility points are the site geocodes, unrounded; their precision (building, campus, locality or city) is in the facility table. Capacity is ",
      "an allocation for facilities that do not disclose it.")),
    hr(),
    helpText(tags$small("The address bar always carries the current view (inventory, layer, state, map position, tab), so copying it shares exactly what you see. ",
                        tags$a(href = "#", onclick = "navigator.clipboard.writeText(window.location.href); this.textContent='Link copied'; return false;", "Copy link to this view"))),
    helpText(tags$small("Contact: Dr Priyanka deSouza, ",
                        tags$a(href = paste0("mailto:", CONTACT_EMAIL), CONTACT_EMAIL),
                        " | ", tags$a(href = REPO_URL, target = "_blank", "code and data")))
  ),

  tags$style(HTML(".bslib-value-box { min-height: 0; } .bslib-value-box .value-box-area { padding: 0.6rem 0.9rem; }
                   .bslib-value-box .value-box-title { font-size: 0.85rem; margin-bottom: 0.1rem; }
                   .bslib-value-box .value-box-value { font-size: 1.5rem; line-height: 1.2; margin-bottom: 0.15rem; }
                   .bslib-value-box p { font-size: 0.78rem; line-height: 1.25; margin: 0; }")),
  layout_columns(
    fill = FALSE, col_widths = breakpoints(sm = c(6, 6, 6, 6), lg = c(3, 3, 3, 3)),
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
    id = "tabs",
    full_screen = TRUE,
    nav_panel("Map",
      tags$style(HTML("#map { min-height: 560px; } .leaflet-labels-pane { pointer-events: none; }")),
      tags$script(HTML("Shiny.addCustomMessageHandler('fly_to', function(m) { var n = 0; (function go() {
        var el = document.getElementById('map'), w = (window.HTMLWidgets && HTMLWidgets.find) ? HTMLWidgets.find('#map') : null;
        var map = (w && el && el.offsetWidth > 0) ? w.getMap() : null;
        if (map && map._loaded) { map.invalidateSize(); map.setView([m.lat, m.lng], m.zoom); }   /* _loaded: the widget's own initial view has been applied, so ours is not overwritten */
        else if (n++ < 2400) { setTimeout(go, 250); } })(); });")),
      uiOutput("story_bar"),
      leafletOutput("map", height = "calc(100vh - 170px)")),
    nav_panel("Follow the electricity",
      div(class = "p-3", style = "max-width:900px",
        p("Four map views, in order, trace the paper's central finding: the places that host data centres are ",
          "not the places that carry the environmental cost of their electricity. Each step sets the map for ",
          "you (operating inventory, all-India) and leaves a one-line reading above the map with ",
          tags$em("Next"), " and ", tags$em("Back"), " buttons; the numbers come from the same files as every other tab."),
        uiOutput("story_cards"))),
    nav_panel("Who benefits, who bears",
      div(class = "p-3", style = "max-width:1100px",
        p("The paper's question is distributional: the districts that host data centres are not the districts ",
          "where the pollution from their electricity lands. This tab puts the two geographies side by side for the ",
          "scope chosen in the sidebar. Every number is either a sum over the district layer shown on the map ",
          "(facility counts, population, the modelled PM2.5 increment and GEMM deaths per district) or taken ",
          "verbatim from the paper's tables (the group contrasts of SI sections S6 and S4.1). ",
          tags$b("Two cautions."), " The increment and the deaths are modelled, scenario-consistent quantities, ",
          "not observations; and the group comparisons are district-level ecological associations, which weight ",
          "each district's increment by its population and group shares and say nothing about individuals."),
        layout_columns(fill = FALSE, col_widths = c(3, 3, 3, 3),
          value_box("Facilities in the richest wealth quintile (by population)", textOutput("ej_vb_rich"), textOutput("ej_vb_rich_ctx"), theme = "primary"),
          value_box("Attributable deaths outside hosting districts", textOutput("ej_vb_outside"), textOutput("ej_vb_outside_ctx"), theme = "secondary"),
          value_box("Increment: hosting vs other districts", textOutput("ej_vb_incr"), textOutput("ej_vb_incr_ctx"), theme = "secondary"),
          value_box("SC/ST vs General, increment ratio", textOutput("ej_vb_scst"), textOutput("ej_vb_scst_ctx"), theme = "secondary")),

        h4(class = "mt-3", "1. Hosting districts versus the districts that receive the pollution"),
        p("Districts are split by whether they contain at least one facility in the current scope. Shares are of ",
          "the all-India total; means are population-weighted. ", tags$em("Person-ug exposure"), " is population ",
          "times increment, the quantity the attributable deaths follow. Baseline PM2.5 is the ACAG 2013-2022 mean."),
        uiOutput("ej_interp_host"),
        DTOutput("ej_host_tab"),

        h4(class = "mt-4", "2. Siting and exposure by district wealth"),
        p("Districts are ranked by the NFHS-5 asset-wealth score and cut into five groups of equal population ",
          "(the paper's population-weighted quintiles, SI section S6), so each bar covers about one-fifth of ",
          "Indians. The left panel counts facilities; the middle panel gives the population-weighted mean ",
          "increment, a per-capita measure; the right panel gives attributable deaths, an absolute burden that ",
          "also depends on how many people live in the group. The two can rank the quintiles differently."),
        uiOutput("ej_interp_quint"),
        plotOutput("ej_quint_plot", height = "330px"),
        DTOutput("ej_quint_tab"),

        h4(class = "mt-4", "3. Who receives the modelled increment: group contrasts"),
        p("From the paper's disparity tables (SI Tables S6.2 and S4.1.1; scripts 20a and 20b). ", tags$em("Ratio"),
          " is the population-weighted mean received by the group divided by that of its reference group ",
          "(above 1 = the group receives more). ", tags$em("Z"), " is the pooled-SD standardized difference. ",
          tags$em("Sign prob."), " is the two-sided probability from a bootstrap that resamples whole states ",
          "(2,000 draws); below 0.05 (*) the sign of the contrast is distinguishable from zero. The ", tags$em("siting"),
          " columns show the same contrasts for the probability of living in a hosting district and for baseline ",
          "PM2.5, so the reversal between siting and burden can be read row by row. Every column follows the scope ",
          "switch in the sidebar: under the stock-plus-pipeline scenario a hosting district is one that holds an ",
          "operating, under-construction or announced facility."),
        uiOutput("ej_interp_disp"),
        plotOutput("ej_disp_plot", height = "360px"),
        DTOutput("ej_disp_tab"),
        p(tags$small("Wealth-quintile contrasts here use the paper's population-weighted quintiles of districts and compare each ",
                     "quintile with the richest; they are not the same as the Figure 3 bars in the paper, which use equal-count quintiles and are ratios to the ",
                     "national mean. A ratio above 1 with a sign probability above 0.05 (for example, the SC/ST row for the modelled increment in the operating inventory) is evidence ",
                     "neither of inequity nor of equality: the direction is suggestive and the uncertainty too large to settle it.")),

        h4(class = "mt-4", "4. Where in India the increment falls"),
        p("Population-weighted increment by zone (scripts/20b, tab20b_inmap_regional.csv; rural/urban ratios as in SI Table S4.1.2; range quoted in section S4.1). Rural/urban is the ratio of the ",
          "population-weighted increment received by rural residents to that received by urban residents within the zone."),
        DTOutput("ej_reg_tab"),

        h4(class = "mt-4", "5. Governance: incentives and conditions"),
        p("State incentive policies against the burden geography of each state's hosting districts (SI section S9). ",
          "'Incentive types' counts the instruments the policy offers out of five (capital subsidy, stamp-duty exemption, ",
          "electricity-duty exemption, land incentive, single-window clearance; 'partial' counts one half). No reviewed ",
          "policy attaches a data-centre-specific environmental-assessment, water or energy condition to its incentives; ",
          "general environmental-clearance, water and land-use rules apply regardless. States are listed by operating ",
          "facilities; the full compilation with every source is on the State policies tab."),
        DTOutput("ej_gov_tab"),
        p(tags$small("Definitions: hosting district = contains at least one facility in the current scope; population = GHSL 2020 ",
                     "district population for the district tables and group ratios (the counts of people above a threshold and the ",
                     "national deaths use GPW 2020 on the InMAP grid); wealth quintiles = population-weighted quintiles of the NFHS-5 district mean asset score ",
                     "(all 641 districts have an NFHS estimate); ",
                     "deaths = GEMM NCD+LRI, adults 25+, national baseline rate, computed per InMAP grid piece with the district baseline PM2.5 (SI section S4.1)."))
      )),
    nav_panel("Air-quality model", aq_walkthrough()),
    nav_panel("Districts",  DTOutput("dtab")),
    nav_panel("Facilities",
      div(class = "p-3",
        p("Every facility in the inventory, with the capacity the paper uses. ",
          "The sourced table below gives each facility's source links, every published capacity figure we ",
          "found and which one we used, and the cross-check against the ",
          tags$a(href = "https://www.atlasofdatacenterpolitics.com/", target = "_blank", "Atlas of Data Center Politics"), ". ",
          "Each facility's site coordinates are given with their precision (building, campus, locality or city). Column definitions and methods are in ",
          tags$a(href = paste0(REPO_URL, "/blob/main/DATA.md"), target = "_blank", "DATA.md"), ". ",
          "The facility table is licensed ", tags$a(href = "https://creativecommons.org/licenses/by-nc/4.0/", target = "_blank", "CC BY-NC 4.0"),
          " (credit required; no commercial use without permission)."),
        p("Every source is linked, and an archived copy (Internet Archive or archive.today) is given wherever the ",
          "site allows one, so each row can be checked even if the original page changes. The documented ",
          "dataset bundles the table, its data dictionary, a list of every cited URL with its archived copy and ",
          "snapshot date, the backup-diesel and emission-factor tables with their READMEs, and a README with the licence and how to cite it."),
        cap_walkthrough(),
        if (file.exists(PUB_ZIP)) downloadButton("dl_bundle", "Download the documented dataset (ZIP)", class = "btn-sm btn-primary mb-3 me-2"),
        if (!is.null(pubtab)) downloadButton("dl_public", "Facility table only (CSV)", class = "btn-sm mb-3"),
        DTOutput("ftab"),
        if (!is.null(pubtab)) tagList(h5(class = "mt-4", "Sources and capacity notes, facility by facility"), DTOutput("srctab")))),
    nav_panel("State policies",
      div(class = "p-3",
        p("State incentive policies for data centres, compiled from state notifications and ",
          "secondary legal summaries, joined to the burden geography of each state's hosting ",
          "districts. ", tags$b(sprintf("%d of the %d states reviewed have a dedicated policy or data-centre provisions in an IT policy",
                                        H$policy_states_dedicated, H$policy_states_reviewed)),
          sprintf("; together they host %d of the %d operating facilities (%d%%). ",
                  H$facilities_in_policy_states, H$n_operating,
                  round(100 * H$facilities_in_policy_states / H$n_operating)),
          "None of the reviewed data-centre policies sets a data-centre-specific environmental-assessment, water or energy condition; ",
          "general environmental-clearance, water, construction and land-use rules apply regardless. The second table ",
          "gives the source, the verbatim passage and the retrieval date behind every cell of ",
          "the first. Know of a policy we have missed, or a newer one? Use the ",
          tags$em("Submit a policy"), " tab."),
        h5("Policy compilation"), DTOutput("ptab"),
        h5(class = "mt-4", "Sources, claim by claim"), DTOutput("pstab"))),
    nav_panel("Power interruptions",
      div(class = "p-3",
        p("How often the grid fails in each district, measured. Prayas (Energy Group)'s Electricity Supply ",
          "Monitoring Initiative (ESMI) logged the supply voltage every minute at 528 monitors between ",
          sprintf("%s and %s; the ", H$esmi$first, H$esmi$last), H$esmi$monitors,
          " with at least 30 recorded days, in ", H$esmi$districts, " districts, are used. ",
          "A minute below 80 V counts as an interruption (a complete loss of supply or severe undervoltage); ",
          "minutes with no reading count as missing, not as interruptions. Each monitor's interrupted share of its ",
          "recorded minutes is scaled to hours per year, and a district's value is the mean over its monitors, ",
          "for all monitors and for urban monitors only (state capitals, district headquarters and other ",
          "municipal areas)."),
        p(sprintf(paste0("Data centres sit where the grid is most reliable: comparing urban monitors only, the %d ",
                         "districts with operating data centres and a monitor have a median of %s interruption hours a ",
                         "year, against %s in districts without data centres. These measured hours describe historical grid reliability, not ",
                         "data-centre generator operation; the paper uses them only as an input to bound potential backup-diesel ",
                         "generation and its emissions (SI section S5)."),
                  H$esmi$hosting_districts, fmtnum(H$esmi$hosting_median_h), fmtnum(H$esmi$nonhosting_urban_median_h))),
        p(tags$small(
          "Districts are the Census 2011 geography used throughout; ESMI areas that are not districts in this layer are pooled into their parent district ",
          "(Hapur into Ghaziabad, Palghar into Thane, Salcete into South Goa). Monitors with fewer than 30 recorded ",
          "days are listed but not used. A district with few monitors, or monitors on a single feeder, may not ",
          "represent the whole district. Data centres usually take supply on dedicated high-tension feeders, ",
          "which are more reliable than the domestic connections most monitors sit on. ",
          tags$b("Source: "), "Prayas (Energy Group), Electricity Supply Monitoring Initiative, minute-wise voltage ",
          "data 2014-2019, ", tags$a(href = "https://doi.org/10.7910/DVN/CLLZZM", target = "_blank", "doi:10.7910/DVN/CLLZZM"),
          ". Free for non-commercial, academic and research use with the source acknowledged. The map layers ",
          tags$em("Power interruptions (ESMI)"), " show the same values.")),
        if (!is.null(esmi_d)) tagList(
          downloadButton("dl_esmi", "Download district interruption hours (CSV)", class = "btn-sm btn-primary mb-3 me-2"),
          downloadButton("dl_esmi_mon", "Monitor by monitor (CSV)", class = "btn-sm mb-3 me-2"),
          if (file.exists(DIESEL_CSV)) downloadButton("dl_diesel", "Hosting districts: interruption hours and backup diesel (CSV)", class = "btn-sm mb-3"),
          if (file.exists(DIESEL_CSV)) p(tags$small("The third file has one row per district with an operating data centre: its ESMI monitors and measured hours, ",
            "which outage-hour value the backup-diesel model used and why (measured in the district, or the state or national urban median where the district has no monitor), ",
            "and the resulting generator hours, diesel electricity and NOx / PM2.5 at the paper's central scenario (40% of measured urban-monitor interruption hours plus 100 hours of testing). ",
            "A README with definitions and sources is included in the documented dataset.")),
          DTOutput("esmitab")))),
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
          "for sites found during a cross-check. The ",
          tags$a(href = "https://www.atlasofdatacenterpolitics.com/", target = "_blank", "Atlas of Data Center Politics"),
          " and a screened OpenStreetMap query are used only as cross-checks, never as the source of a row. ",
          "Listing sites (Data Center Map, Baxtel, Ocolo, Datacenterhawk, Cloudscene, IndiaMART) are not counted as independent evidence: ",
          "a row they alone support is rated low confidence, and they never supply a capacity. ",
          "Every facility carries a source link; the Facilities tab gives them, with how each was verified."),
        p("Every row was reviewed against its sources between 22 and 25 October 2026 (11 rows removed as hosting resellers, offices or second rows ",
          "for one building; 16 statuses corrected), then re-checked independently on 26 October by reviewers who did not see the earlier verdicts ",
          "(241 rows drew no fault; accepted challenges were corrected). Confidence is high for 176 facilities, medium for 34 and low for 119. ",
          "75 facilities (54 operating, 237 MW) can be neither confirmed nor refuted from public sources; each carries an open issue, and the paper ",
          "tests their removal. Cited pages have Internet Archive or archive.today copies; pages that could not be archived are held by the authors as dated snapshots."),
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
        p(sprintf(paste0("Only a minority of facilities publish their capacity. Published figures are held ",
                         "fixed, by one tiered rule: a labelled IT load as published; otherwise an unlabelled operational capacity ",
                         "taken as IT load, total power divided by the PUE of 1.6, a company-wide figure shared equally, or racks at 4 kW. ",
                         "Listing-site figures are never used. The remaining capacity is allocated: each facility gets a relative ",
                         "weight by operator class (telecom 0.5, enterprise and government 1, colocation 3, hyperscale ",
                         "10) and the commercial subset is scaled to a national anchor of %s MW of ",
                         "commercial IT load, giving %s MW across the operating inventory. "),
                  fmtnum(H$anchor_commercial_mw), fmtnum(H$mw_operating)),
          "Under the stock-plus-pipeline scenario, facilities that publish a build-out load keep it, those with only a current ",
          "published load keep that, and the rest are sized at the same per-weight allocation as the operating inventory, ",
          sprintf("giving %s MW. ", fmtnum(H$mw_all)),
          tags$b("An individual facility's megawatt figure is therefore an allocation, not a ",
                 "measurement"), "; treat state and national aggregates as the meaningful quantities. ",
          "The Facilities tab walks through the calculation step by step, with every number."),
        p(sprintf(paste0("The operating inventory draws about %s TWh per year, %s%% of national ",
                         "generation, and is attributed %s Mt CO2 on average grid factors (the value in ",
                         "the boxes above) or %s Mt on state marginal factors, the paper's headline. "),
                  fmt1(H$twh_operating), fmt1(H$pct_nat_gen_operating), fmt1(H$co2_mt_avg_operating),
                  fmt1(H$co2_mt_marginal_operating)),
          sprintf("Marginal SO2, NOx and primary PM2.5 are %s, %s and %s kt per year.",
                  fmt1(H$so2_kt_operating), fmt1(H$nox_kt_operating), fmt1(H$pm25_kt_operating))),

        if (file.exists(EF_CSV)) p(downloadButton("dl_ef", "Download every emission factor used (CSV)", class = "btn-sm btn-primary me-2"),
          tags$small("State marginal emission factors (Sengupta et al. 2022, flat-load weighted), the average grid CO2 factor, PUE, utilisation and water intensities, ",
                     "the gas/coal split and stack heights used to place emissions at plants, and the backup-diesel factors: one row per factor and level, with unit, source, how it is used and the script.")),
        h4("Following one burden through the chain"),
        p("Six layers, grouped under Scope 1 and Scope 2, let you watch the sector's footprint ",
          "move across the map. ", tags$b("Scope 1"), " is what happens at the facility: cooling ",
          "water drawn on site, and the nitrogen oxides from backup diesel generators, the one air ",
          "emission that is not displaced. The diesel layer is the paper's central scenario (measured district ",
          "urban-monitor supply interruptions from the Power interruptions tab, or the state or national urban median where a district has no monitor, scaled by 0.4 because data centres sit on dedicated feeders, plus 100 hours of testing a year), about ",
          sprintf("%s%% of the sector's grid-attributable NOx (%s%% across the scenarios), emitted at ground level in the hosting ",
                  fmt1(H$diesel_nox_pct_central), H$diesel_nox_pct_range),
          "districts. ",
          tags$b("Scope 2 SO2, NOx and PM2.5"), " are the emissions the sector's ",
          "electricity causes, mapped where they are physically released, at the ",
          sprintf("%d coal and gas plants assigned those emissions under the state marginal-generation model (an estimated marginal mix, not a demonstrated supply relationship), across %d districts. ",
                  H$plants, H$emission_districts),
          "Switch finally to ", tags$em("PM2.5 increment from data centres"), " and you see where ",
          "the resulting concentration settles, which is different again."),
        p(tags$small(tags$b("One label needs care."), " Scope 2 water is charged to the district ",
          "that consumed the electricity, not the district where the water was drawn; it is a ",
          "consumption account, not a location, because more than a third of it (about 37%) is hydropower ",
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
                  fmtnum(H$inmap_all$pop_ge_0_01_million), fmtnum(H$inmap_all$deaths_per_yr)),
          "The paper reruns InMAP for four sensitivity variants (SI Table S4.1.3): plant allocation by generation (identical), ",
          "flat class weights (about 3,400 deaths), hyperscale-dominant weights (about 1,900), and the unresolved-facility test, ",
          "which sets the 54 operating facilities that public sources can neither confirm nor refute to zero (1,824 deaths, 11% fewer)."),
        p("This is not measured pollution. It is the modelled annual-mean PM2.5 attributable to ",
          "the electricity these facilities consume, obtained by computing each state's emissions with state marginal emission factors, ",
          "placing them at that state's coal and gas plants in proportion to capacity and dispersing them ",
          "through the Global InMAP reduced-complexity model. It is a scenario-consistent ",
          "estimate, not an exact one, and it cannot be attributed to any individual facility. ",
          "The attributable deaths apply the GEMM concentration-response function (Burnett et al., 2018) for adults ",
          "aged 25 and over to this increment on top of each district's baseline PM2.5, with a national adult share ",
          "and baseline mortality rate, against a counterfactual without the sector's demand. They are modelled, ",
          "not observed, deaths, and scale with the assumed capacity."),

        h4("The two wealth measures"),
        p("Wealth appears twice, from independent sources, and neither is money. The ",
          tags$b("NFHS-5 asset score"), " is a principal-components index of household assets ",
          "whose raw values mean nothing on their own; it is shown as a percentile of India's ",
          "surveyed districts. The ", tags$b("Relative Wealth Index"), " (Chi et al., 2022) is a ",
          "satellite- and connectivity-based estimate at 2.4 km resolution, already dimensionless ",
          "and roughly centred on zero. The two are built from entirely different inputs and agree."),

        h4("Reading the district map"),
        p("Districts are the 641 Census 2011 district polygons, joined to the NFHS-5 survey districts. ",
          "Chennai, Hyderabad, Kolkata and Mumbai are districts in their own right, so their facilities sit in ",
          "those districts. Districts created after 2011 are not split out, and the ten Telangana districts are ",
          "shown under Telangana although the 2011 geography predates the state. The district shapefile distributed ",
          "with NFHS-5 is not used: it is displaced by a median of about 11 km (28 km at Chennai, which puts the city offshore)."),

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
          tags$li("Grid reliability: Prayas Electricity Supply Monitoring Initiative (ESMI), minute-wise voltage 2014-2019, ",
                  tags$a(href = "https://doi.org/10.7910/DVN/CLLZZM", target = "_blank", "doi:10.7910/DVN/CLLZZM"), "; see the Power interruptions tab."),
          tags$li("Dispersion: ", tags$a(href = "https://inmap.run/", target = "_blank", "InMAP"), ", global implementation of Thakrar et al. (2022)."),
          tags$li("State policies: state notifications and gazettes, investment-promotion portals, secondary legal summaries; every claim sourced on the State policies tab.")),

        h4("Limits worth knowing"),
        tags$ul(
          tags$li("Points are the site geocodes published in the facility table; 32 of the 329 rest on a city placeholder, and the table gives each one's precision."),
          tags$li("Most facilities do not disclose capacity; it is allocated by operator class and scaled to a national anchor."),
          tags$li("District values are totals or averages and hide within-district variation."),
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
      bo <- if ("mw_reported_buildout" %in% names(f)) f$mw_reported_buildout else rep(NA_real_, nrow(f))
      f$mw_rep_use <- ifelse(!is.na(bo), bo, f$mw_reported); f$mw_rep_lab <- ifelse(!is.na(bo), " MW published build-out)", " MW published)")
    } else {
      f <- f[f$is_operating, ]
      f$mw_use <- f$mw_it; f$gwh_use <- f$e_fac_gwh; f$co2_use <- f$co2_kt
      f$s1_use <- f$scope1_ml; f$s2_use <- f$scope2_ml
      f$mw_rep_use <- f$mw_reported; f$mw_rep_lab <- rep(" MW published)", nrow(f))
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
    f <- fac_f(); k <- !is.na(f$dist_name); d <- length(unique(paste(f$dist_name[k], f$state_name[k])))   # names repeat across states
    sprintf("in %d of India's %d districts%s", d, nrow(districts),
            if (is_all()) sprintf("; %d operating, %d under construction, %d announced",
                                  sum(f$status == "operating"), sum(f$status == "construction"),
                                  sum(f$status == "announced")) else "")
  })
  output$vb_mw_ctx <- renderText({
    mw <- sum(fac_f()$mw_use, na.rm = TRUE)
    sprintf("~%s MW at facility load: %.2f%% of India's peak demand in FY2025-26 (%.0f GW)",
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
    # Keyless basemaps: Esri's public tile services and the OpenStreetMap standard tiles need no API key
    # (CARTO's tiles now return "API key required"). Place names sit in their own pane above the district
    # fills so they stay readable over the choropleth.
    esri <- function(svc) sprintf("https://server.arcgisonline.com/ArcGIS/rest/services/%s/MapServer/tile/{z}/{y}/{x}", svc)
    leaflet(options = leafletOptions(minZoom = 4)) |>
      addMapPane("labels", zIndex = 450) |>
      addTiles(esri("Canvas/World_Light_Gray_Base"), group = "Light grey",
               attribution = "Tiles &copy; Esri &mdash; Esri, HERE, Garmin, &copy; OpenStreetMap contributors") |>
      addTiles("https://tile.openstreetmap.org/{z}/{x}/{y}.png", group = "OpenStreetMap",
               attribution = "&copy; <a href='https://www.openstreetmap.org/copyright'>OpenStreetMap</a> contributors") |>
      addTiles(esri("World_Imagery"), group = "Satellite",
               attribution = "Tiles &copy; Esri &mdash; Source: Esri, Maxar, Earthstar Geographics") |>
      addTiles(esri("Canvas/World_Light_Gray_Reference"), group = "Place names",
               options = tileOptions(pane = "labels")) |>
      addLayersControl(baseGroups = c("Light grey", "OpenStreetMap", "Satellite"), overlayGroups = "Place names",
                       position = "topleft", options = layersControlOptions(collapsed = TRUE)) |>
      addScaleBar(position = "bottomleft", options = scaleBarOptions(imperial = FALSE)) |>
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
      clearShapes() |> clearMarkers() |> removeControl("legend") |>
      addPolygons(fillColor = ~pal(vshow), fillOpacity = 0.78, color = "white", weight = 0.4,
                  highlightOptions = highlightOptions(weight = 2, color = "#333", bringToFront = TRUE),
                  label = lab) |>
      addLegend("bottomright", pal = pal, values = vshow, opacity = 0.85, layerId = "legend",
                title = paste0(input$ind, "<br/><small>", spec$unit,
                               if (isTRUE(spec$log)) " (log scale; grey = zero or no data)" else "",
                               if (is_all() && !is.null(spec$alt)) " - stock plus pipeline" else "",
                               inmap_note(spec), if (!is.null(spec$note)) spec$note else "", "</small>"),
                labFormat = if (isTRUE(spec$log)) labelFormat(transform = function(x) 10^x) else labelFormat())

    if (isTRUE(input$show_plants) && nrow(plants) > 0) {
      m <- m |> addCircleMarkers(
        data = plants, radius = ~pmax(2, sqrt(pmax(capacity_mw, 1)) / 12),
        color = ~ifelse(fuel == "Coal", "#4d4d4d", "#1b7837"), stroke = FALSE, fillOpacity = 0.55,
        label = ~lapply(sprintf("<b>%s</b><br/>%s, %s MW<br/>Attributable SO2 %s t/yr | NOx %s t/yr | PM2.5 %s t/yr (operating inventory)",
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
        data = f, layerId = ~facility_id,   # click -> the facility's documentary record
        radius = ~pmax(3.5, sqrt(pmax(mw_use, 0.3)) * 2.2),
        color = ~ifelse(status == "operating", "white", "#111"),
        weight = ~ifelse(status == "operating", 0.9, 1.6),
        dashArray = ~ifelse(status == "announced", "3,3", ""),
        fillColor = ~unname(TYPE_COL[dc_type]),
        fillOpacity = ~ifelse(status == "operating", 0.92, 0.55),
        label = ~lapply(sprintf(
          "<b>%s</b><br/>%s | %s | %s<br/>%s, %s<br/><hr style='margin:4px 0'/>
           IT capacity: %s MW%s<br/>Electricity: %s GWh/yr<br/>CO2: %s kt/yr<br/>
           On-site water: %s ML/yr<br/>Electricity-related water: %s ML/yr<br/><i>click for capacity basis, precision and sources</i>",
          esc(name), esc(operator), esc(dc_type), esc(STATUS_LAB[as.character(status)]), esc(dist_name), esc(state_name),
          fmtnum(mw_use, 2),
          ifelse(!is.na(mw_rep_use), paste0(" (", fmtnum(mw_rep_use, 1), mw_rep_lab),
                 ifelse(mw_use == 0, " (not sized: not confirmed as a separate building with its own load)", " (modelled: no published load)")),
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
                      "s1_water_ml", "diesel_nox_t", "emis_so2_t", "esmi_h_yr"))) |>
      rename(data_centres = all_of(cnt), pm25_increment = all_of(dpc)) |>
      arrange(desc(data_centres))
    datatable(d, rownames = FALSE, filter = "top", extensions = "Buttons",
              options = list(pageLength = 20, dom = "Bfrtip", buttons = c("csv", "excel"), scrollX = TRUE)) |>
      formatRound(c("pop_2020", "coal_mw", "s1_water_ml", "emis_so2_t", "esmi_h_yr"), 0) |>
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

  output$dl_bundle <- downloadHandler(
    filename = function() "india_datacentres_documented.zip",
    content  = function(file) file.copy(PUB_ZIP, file),
    contentType = "application/zip")

  output$dl_esmi <- downloadHandler(
    filename = function() "india_district_power_interruptions_esmi.csv",
    content  = function(file) file.copy(ESMI_CSV, file))
  output$dl_esmi_mon <- downloadHandler(
    filename = function() "india_esmi_monitor_power_interruptions.csv",
    content  = function(file) file.copy(ESMI_MON, file))
  output$dl_diesel <- downloadHandler(
    filename = function() "india_datacentres_power_interruptions_backup_diesel.csv",
    content  = function(file) file.copy(DIESEL_CSV, file))
  output$dl_ef <- downloadHandler(
    filename = function() "india_datacentres_emission_factors.csv",
    content  = function(file) file.copy(EF_CSV, file))

  output$esmitab <- renderDT({
    req(esmi_d)
    e <- esmi_d |>
      transmute(District = district_2015, State = state_2015,
                `Interruption h/yr (all monitors)` = interruption_h_per_yr,
                `Interruption h/yr (urban monitors)` = interruption_h_per_yr_urban,
                `Interruption h/yr (rural monitors)` = interruption_h_per_yr_rural,
                Monitors = n_monitors, Urban = n_urban_monitors, Rural = n_rural_monitors,
                `Monitor range (h/yr)` = paste0(round(min_monitor_h), "-", round(max_monitor_h)),
                `Recorded monitor-days` = recorded_monitor_days, From = first_date, To = last_date,
                `ESMI districts pooled` = esmi_districts_pooled,
                `Operating data centres` = dc_count_operating, `Incl. pipeline` = dc_count_all)
    datatable(e, rownames = FALSE, filter = "top", extensions = "Buttons",
              options = list(pageLength = 20, dom = "Bfrtip", buttons = c("csv", "excel"), scrollX = TRUE,
                             order = list(list(2, "desc")))) |>
      formatRound(c("Interruption h/yr (all monitors)", "Interruption h/yr (urban monitors)", "Interruption h/yr (rural monitors)"), 0)
  })

  output$dl_public <- downloadHandler(
    filename = function() "india_datacentres_public.csv",
    content  = function(file) file.copy(PUB_CSV, file))

  output$srctab <- renderDT({
    req(pubtab)
    s <- pubtab |>
      transmute(ID = facility_id, Facility = facility_name, Operator = operator, Status = status,
                City = city, District = district_2015,
                Latitude = latitude, Longitude = longitude, `Location precision` = location_precision,
                `Reported IT MW (current)` = mw_it_reported_current, `Reported IT MW (build-out)` = mw_it_reported_buildout,
                `What the MW figure is` = mw_basis, `Other published figures` = mw_published_figures, `Capacity note` = mw_flag,
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
                `Policy (dedicated or IT-policy provisions)` = ifelse(has_policy, paste0(policy_name, " (", policy_year, ")"), "none dedicated"),
                `Capital subsidy` = yesno(capital_subsidy), `Stamp duty exemption` = yesno(stamp_duty_exemption),
                `Electricity duty exemption` = yesno(electricity_duty_exemption),
                `Land incentive` = yesno(land_incentive), `Single window` = yesno(single_window),
                `EIA required` = yesno(eia_required),
                `Operating facilities` = dc_count, `Incl. pipeline` = dc_count_all,
                `Hosting districts` = dc_districts,
                `Hosting districts in high water stress (%, BWS >= 0.4)` = round(100 * share_dists_high_stress),
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
  # ---- "Who benefits, who bears": the distributional comparison -----------------------------------
  # Colours: hosting = blue, other districts = orange (fixed, never cycled); quintiles = one blue ramp.

  ej_d_for <- function(use_all) {
    d <- sf::st_drop_geometry(districts)
    if (use_all) { d$cnt <- d$dc_count_all; d$dp <- d$dpm25_all; d$de <- d$deaths_all }
    else          { d$cnt <- d$dc_count;     d$dp <- d$dpm25;     d$de <- d$deaths }
    d$cnt[is.na(d$cnt)] <- 0L; d$de[is.na(d$de)] <- 0
    d$hosting <- d$cnt > 0
    d$pop <- ifelse(is.na(d$pop_2020), 0, d$pop_2020)
    d$person_ug <- d$pop * ifelse(is.na(d$dp), 0, d$dp)
    # population-weighted wealth quintiles of districts (NFHS-5 asset score), 1 = poorest fifth of people
    d$wq <- NA_integer_
    k <- !is.na(d$wealth_mean_2019) & d$pop > 0
    o <- order(d$wealth_mean_2019[k]); cs <- cumsum(d$pop[k][o]) / sum(d$pop[k])
    q <- pmin(5L, as.integer(ceiling(cs * 5 - 1e-9))); q[q < 1L] <- 1L
    d$wq[which(k)[o]] <- q
    d
  }
  ej_d <- reactive(ej_d_for(is_all()))

  ej_host_for <- function(use_all) {
    d <- ej_d_for(use_all); tot_de <- sum(d$de); tot_pu <- sum(d$person_ug); tot_f <- sum(d$cnt); tot_pop <- sum(d$pop)
    row <- function(k, label) data.frame(
      Group = label, Districts = sum(k), `Population (million)` = round(sum(d$pop[k]) / 1e6, 0),
      `Share of facilities (%)` = round(100 * sum(d$cnt[k]) / tot_f, 1),
      `Share of population (%)` = round(100 * sum(d$pop[k]) / tot_pop, 1),
      `Share of person-ug exposure (%)` = round(100 * sum(d$person_ug[k]) / tot_pu, 1),
      `Share of attributable deaths (%)` = round(100 * sum(d$de[k]) / tot_de, 1),
      `Attributable deaths (/yr)` = round(sum(d$de[k]), 0),
      `Pop-weighted increment (ug/m3)` = round(wmean(d$dp[k], d$pop[k]), 4),
      `Baseline PM2.5 (ug/m3)` = round(wmean(d$pm25_acag_local[k], d$pop[k]), 1),
      `Asset-wealth percentile` = round(wmean(d$wealth_pct[k], d$pop[k]), 0),
      `Urban share` = round(wmean(d$urban_share_2019[k], d$pop[k]), 2),
      `SC/ST share` = round(wmean(d$share_scst_2019[k], d$pop[k]), 2),
      `BPL share` = round(wmean(d$share_bpl_2019[k], d$pop[k]), 2),
      `Coal capacity (GW)` = round(sum(d$coal_mw[k], na.rm = TRUE) / 1000, 1),
      check.names = FALSE)
    rbind(row(d$hosting, "Hosting districts"), row(!d$hosting, "Districts without a data centre"), row(rep(TRUE, nrow(d)), "All India"))
  }
  ej_host <- reactive(ej_host_for(is_all()))
  output$ej_host_tab <- renderDT({
    datatable(ej_host(), rownames = FALSE, options = list(dom = "t", ordering = FALSE, scrollX = TRUE))
  })

  ej_quint_for <- function(use_all) {
    d <- ej_d_for(use_all); k <- !is.na(d$wq)
    q <- lapply(1:5, function(i) {
      s <- k & d$wq == i
      data.frame(Quintile = c("Poorest fifth", "Second", "Middle", "Fourth", "Richest fifth")[i],
                 Districts = sum(s), `Population (million)` = round(sum(d$pop[s]) / 1e6, 0),
                 Facilities = sum(d$cnt[s]), `Share of facilities (%)` = round(100 * sum(d$cnt[s]) / sum(d$cnt[k]), 1),
                 `Pop-weighted increment (ug/m3)` = round(wmean(d$dp[s], d$pop[s]), 4),
                 `Attributable deaths (/yr)` = round(sum(d$de[s]), 0),
                 `Deaths per million residents` = round(sum(d$de[s]) / sum(d$pop[s]) * 1e6, 2),
                 `Baseline PM2.5 (ug/m3)` = round(wmean(d$pm25_acag_local[s], d$pop[s]), 1),
                 check.names = FALSE)
    })
    list(tab = do.call(rbind, q), excluded = sum(!k), excluded_fac = sum(d$cnt[!k]))
  }
  ej_quint <- reactive(ej_quint_for(is_all()))
  output$ej_quint_tab <- renderDT({
    q <- ej_quint()
    datatable(q$tab, rownames = FALSE, caption = if (q$excluded > 0) sprintf("%d districts without an NFHS-5 wealth estimate (holding %d facilities) are excluded from the quintiles.", q$excluded, q$excluded_fac) else NULL,
              options = list(dom = "t", ordering = FALSE, scrollX = TRUE))
  })
  output$ej_quint_plot <- renderPlot(ej_draw_quint(ej_quint()$tab), res = 96)

  ej_disp_for <- function(use_all) {
    sc <- if (use_all) "all" else "operating"
    inc <- EJ$disparity[[sc]]
    bl <- EJ$baseline[[sc]]   # siting contrasts for the same scope (20a is run for both inventories)
    pres <- bl[bl$exposure == "Data-center presence", ]; pmb <- bl[bl$exposure == "PM2.5 (ACAG)", ]
    m <- data.frame(Contrast = inc$contrast,
                    `Siting: ratio, P(hosting)` = round(pres$ratio[match(inc$contrast, pres$contrast)], 2),
                    `Siting: Z, P(hosting)` = round(pres$Z[match(inc$contrast, pres$contrast)], 2),
                    `Baseline PM2.5: Z` = round(pmb$Z[match(inc$contrast, pmb$contrast)], 2),
                    `Increment: group (ug/m3)` = round(inc$pwc_group, 4), `Increment: reference (ug/m3)` = round(inc$pwc_ref, 4),
                    `Increment: ratio` = round(inc$ratio, 2), `Increment: Z` = round(inc$Z, 2),
                    `Sign prob.` = round(inc$boot_sign_prob, 3), check.names = FALSE)
    m$` ` <- ifelse(m$`Sign prob.` < 0.05, "*", "")
    m
  }
  ej_disp <- reactive(ej_disp_for(is_all()))
  output$ej_disp_tab <- renderDT({
    datatable(ej_disp(), rownames = FALSE, options = list(dom = "t", ordering = FALSE, pageLength = 12, scrollX = TRUE))
  })
  output$ej_disp_plot <- renderPlot(ej_draw_disp(ej_disp()), res = 96)

  output$ej_reg_tab <- renderDT({
    sc <- if (is_all()) "all" else "operating"; r <- EJ$regional[[sc]]
    r <- data.frame(Zone = r$zone, Districts = r$districts, `Population (million)` = round(r$population_million, 0),
                    `Pop-weighted increment (ug/m3)` = round(r$pw_increment, 4), `Rural / urban` = round(r$rural_over_urban, 2), check.names = FALSE)
    datatable(r, rownames = FALSE, options = list(dom = "t", ordering = FALSE))
  })

  output$ej_gov_tab <- renderDT({
    sc01 <- function(x) ifelse(is.na(x) | x == "", 0, ifelse(x == "yes", 1, ifelse(x == "partial", 0.5, 0)))
    g <- policies |>
      mutate(`Incentive types (of 5)` = sc01(capital_subsidy) + sc01(stamp_duty_exemption) + sc01(electricity_duty_exemption) + sc01(land_incentive) + sc01(single_window)) |>
      transmute(State = state, `Policy (dedicated or IT-policy provisions)` = ifelse(has_policy, paste0(policy_name, " (", policy_year, ")"), "none dedicated"),
                `Incentive types (of 5)`, `Environmental assessment required` = yesno(eia_required),
                `Operating facilities` = dc_count, `Incl. pipeline` = dc_count_all, `Hosting districts` = dc_districts,
                `Hosting districts in high water stress (%, BWS >= 0.4)` = round(100 * share_dists_high_stress),
                `Mean hosting-district PM2.5 (ug/m3)` = round(mean_pm25, 1)) |>
      arrange(desc(`Operating facilities`))
    datatable(g, rownames = FALSE, options = list(dom = "t", pageLength = 25, ordering = TRUE, scrollX = TRUE))
  })

  # one-paragraph readings generated from the displayed numbers: descriptive, never causal, and explicit about uncertainty
  interp <- function(...) div(class = "alert alert-light border py-2 px-3 small", tags$b("Reading: "), paste0(...))
  scope_word <- reactive(if (is_all()) "stock-plus-pipeline scenario" else "operating inventory")
  output$ej_interp_host <- renderUI({
    h <- ej_host(); o <- h[2, ]; g <- h[1, ]
    interp(sprintf(paste0("Under the %s, the %d hosting districts hold %s%% of India's people, and the model places ",
                          "%s%% of the attributable deaths (%s of %s a year) in the %d districts without a data centre. Per person the increment is %s ",
                          "in hosting districts (%.3f vs %.3f ug/m3): the burden is spread far beyond the hosting districts in absolute terms, ",
                          "while the hosting districts themselves are %s (asset-wealth percentile %d vs %d), %s urban (%.2f vs %.2f) and ",
                          "breathe %s baseline PM2.5 (%.1f vs %.1f ug/m3). These are district-level averages, not individual exposures."),
                   scope_word(), g$Districts, fmt1(g$`Share of population (%)`),
                   fmt1(o$`Share of attributable deaths (%)`), fmtnum(o$`Attributable deaths (/yr)`), fmtnum(h$`Attributable deaths (/yr)`[3]), o$Districts,
                   if (g$`Pop-weighted increment (ug/m3)` > o$`Pop-weighted increment (ug/m3)`) "higher" else "lower",
                   g$`Pop-weighted increment (ug/m3)`, o$`Pop-weighted increment (ug/m3)`,
                   if (g$`Asset-wealth percentile` > o$`Asset-wealth percentile`) "wealthier" else "poorer", g$`Asset-wealth percentile`, o$`Asset-wealth percentile`,
                   if (g$`Urban share` > o$`Urban share`) "more" else "less", g$`Urban share`, o$`Urban share`,
                   if (g$`Baseline PM2.5 (ug/m3)` < o$`Baseline PM2.5 (ug/m3)`) "less" else "more", g$`Baseline PM2.5 (ug/m3)`, o$`Baseline PM2.5 (ug/m3)`))
  })
  output$ej_interp_quint <- renderUI({
    q <- ej_quint()$tab; inc <- q$`Pop-weighted increment (ug/m3)`; de <- q$`Attributable deaths (/yr)`
    interp(sprintf(paste0("%s%% of the facilities are in the districts holding the richest fifth of the population (by district wealth) and %s%% in the poorest fifth. The per-person increment is ",
                          "%s in the poorest fifth than in the richest (%.4f vs %.4f ug/m3, a ratio of %.2f) and peaks in the %s fifth (%.4f). ",
                          "In absolute terms the %s fifth carries the most attributable deaths (%s a year); the poorest fifth carries %s. ",
                          "%s"),
                   fmt1(q$`Share of facilities (%)`[5]), fmt1(q$`Share of facilities (%)`[1]),
                   if (inc[1] < inc[5]) "lower" else "higher", inc[1], inc[5], inc[1] / inc[5],
                   sub(" fifth$", "", tolower(q$Quintile[which.max(inc)])), max(inc), sub(" fifth$", "", tolower(q$Quintile[which.max(de)])), fmtnum(max(de)), fmtnum(de[1]),
                   if (which.max(inc) %in% 2:4) "So the modelled burden is concentrated neither on the poorest districts nor on the richest, hosting ones: it follows the generation corridors, which run through middle-wealth districts."
                   else if (which.max(inc) == 5) "The per-person burden is highest where the facilities are, in the richest fifth."
                   else "The per-person burden is highest in the poorest fifth."))
  })
  output$ej_interp_disp <- renderUI({
    m <- ej_disp(); k <- function(c) m[m$Contrast == c, ]
    sig <- m$Contrast[m$`Sign prob.` < 0.05]; more <- m$Contrast[m$`Increment: ratio` > 1]; rev_ <- m$Contrast[m$`Siting: ratio, P(hosting)` < 1 & m$`Increment: ratio` > 1]
    sc <- k("SC/ST vs General")
    lessk <- m$Contrast[m$`Siting: ratio, P(hosting)` < 1]
    interp(sprintf(paste0("%s, ",
                          "while the modelled increment is above parity for %s and below it for the rest. %s ",
                          "%s %s distinguishable from zero under the state-clustered bootstrap: %s. ",
                          "The SC/ST ratio of %.2f (sign probability %.3f) %s. None of these contrasts is a causal effect of siting; they describe where a modelled ",
                          "regional field happens to fall relative to where groups live."),
                   if (length(lessk) == nrow(m)) "Every group in the table is less likely than its reference group to live in a hosting district (siting ratios all below 1)"
                   else sprintf("%d of the %d groups are less likely than their reference group to live in a hosting district (siting ratio below 1)", length(lessk), nrow(m)),
                   if (length(more)) paste(more, collapse = "; ") else "no group",
                   if (length(rev_)) sprintf("For %s the sign reverses between siting and burden.", paste(rev_, collapse = "; ")) else "No contrast reverses sign between siting and burden.",
                   if (length(sig)) paste("Only", paste(sig, collapse = " and ")) else "No contrast", if (length(sig) <= 1) "is" else "are",
                   if (length(sig)) paste(sprintf("%s residents receive %s of the increment than %s (ratio %.2f, sign probability %.3f)",
                                                  sub(" vs .*$", "", sig), ifelse(m$`Increment: ratio`[m$`Sign prob.` < 0.05] > 1, "more", "less"), sub("^.* vs ", "", sig),
                                                  m$`Increment: ratio`[m$`Sign prob.` < 0.05], m$`Sign prob.`[m$`Sign prob.` < 0.05]), collapse = "; ")
                   else "all sign probabilities are above 0.05",
                   sc$`Increment: ratio`, sc$`Sign prob.`,
                   if (sc$`Sign prob.` < 0.05) sprintf("is distinguishable from parity in this scope, a %s modelled increment for SC/ST residents at the district scale", if (sc$`Increment: ratio` > 1) "higher" else "lower")
                   else "is evidence neither of inequity nor of equality: the direction is suggestive, the uncertainty too large to call it either a disparity or parity"))
  })

  # value boxes
  output$ej_vb_rich <- renderText({ q <- ej_quint()$tab; paste0(fmt1(q$`Share of facilities (%)`[5]), "%") })
  output$ej_vb_rich_ctx <- renderText({ q <- ej_quint()$tab; sprintf("%d of %d facilities; %s%% in the poorest fifth", q$Facilities[5], sum(q$Facilities), fmt1(q$`Share of facilities (%)`[1])) })
  output$ej_vb_outside <- renderText({ h <- ej_host(); paste0(fmt1(h$`Share of attributable deaths (%)`[2]), "%") })
  output$ej_vb_outside_ctx <- renderText({ h <- ej_host(); sprintf("%s of %s modelled deaths/yr fall in the %d districts without a data centre", fmtnum(h$`Attributable deaths (/yr)`[2]), fmtnum(h$`Attributable deaths (/yr)`[3]), h$Districts[2]) })
  output$ej_vb_incr <- renderText({ h <- ej_host(); sprintf("%.3f vs %.3f", h$`Pop-weighted increment (ug/m3)`[1], h$`Pop-weighted increment (ug/m3)`[2]) })
  output$ej_vb_incr_ctx <- renderText({ h <- ej_host(); sprintf("ug/m3, population-weighted; hosting districts hold %s%% of people and %s%% of person-ug exposure", fmt1(h$`Share of population (%)`[1]), fmt1(h$`Share of person-ug exposure (%)`[1])) })
  output$ej_vb_scst <- renderText({ m <- ej_disp(); sprintf("%.2f", m$`Increment: ratio`[m$Contrast == "SC/ST vs General"]) })
  output$ej_vb_scst_ctx <- renderText({ m <- ej_disp(); k <- m$Contrast == "SC/ST vs General"
    sprintf("sign probability %.3f%s; siting ratio %.2f (SC/ST %s likely to live in a hosting district)", m$`Sign prob.`[k], if (m$`Sign prob.`[k] < 0.05) ", distinguishable" else ", not distinguishable at 0.05", m$`Siting: ratio, P(hosting)`[k], if (m$`Siting: ratio, P(hosting)`[k] < 1) "less" else "more") })

  # ---- navigation: search, shareable links ---------------------------------------------------------
  # a setView sent while the Map tab is hidden lands on a zero-size map and yields a garbage centre, so views
  # are set by a client-side handler that waits until the map is visible (tags$script in the Map panel)
  fly_to <- function(lat, lng, zoom) session$sendCustomMessage("fly_to", fly_payload(lat, lng, zoom))
  dist_xy <- suppressWarnings(sf::st_coordinates(sf::st_centroid(sf::st_geometry(districts))))
  fac_xy  <- sf::st_coordinates(sf::st_geometry(facilities))
  search_choices <- local({
    f <- sf::st_drop_geometry(facilities); d <- sf::st_drop_geometry(districts)
    fl <- sprintf("%s - %s (%s, %s)", f$name, f$operator, f$dist_name, f$state_name)
    dl <- sprintf("%s, %s (district)", d$dist_name, d$state_name)
    c(setNames(paste0("f", seq_len(nrow(f))), fl), setNames(paste0("d", seq_len(nrow(d))), dl))
  })
  updateSelectizeInput(session, "search", choices = search_choices, selected = character(0), server = TRUE)
  observeEvent(input$search, {
    s <- input$search; if (is.null(s) || !nzchar(s)) return()
    i <- as.integer(substring(s, 2))
    if (startsWith(s, "f")) {
      xy <- unname(as.numeric(fac_xy[i, ])); f <- facilities[i, ]   # unname: a named row would serialise lat as {"Y": ...}
      fly_to(xy[2], xy[1], 11)
      leafletProxy("map") |> clearGroup("search") |>
        addCircleMarkers(lng = xy[1], lat = xy[2], radius = 16, color = "#111", weight = 2, fill = FALSE, group = "search",
                         label = htmltools::HTML(sprintf("<b>%s</b><br/>%s | %s", esc(f$name), esc(f$operator), esc(STATUS_LAB[as.character(f$status)]))))
      if (!f$is_operating && !is_all()) showNotification("This facility is in the pipeline: switch the inventory to 'Stock plus pipeline' to see its point.", type = "message", duration = 6)
    } else {
      xy <- unname(as.numeric(dist_xy[i, ]))
      fly_to(xy[2], xy[1], 8); leafletProxy("map") |> clearGroup("search")
    }
    nav_select("tabs", "Map")
  }, ignoreInit = TRUE)

  # the map state lives in the URL (?scope=&layer=&plants=&osm=&fac=&state=&tab=&lat=&lng=&zoom=) so a view can be shared
  restore_view <- reactiveVal(NULL)
  observeEvent(session$clientData$url_search, {
    q <- parseQueryString(session$clientData$url_search)
    if (!is.null(q$scope) && q$scope %in% c("operating", "all")) updateRadioButtons(session, "scope", selected = q$scope)
    if (!is.null(q$layer) && q$layer %in% names(IND)) updateSelectInput(session, "ind", selected = q$layer)
    if (!is.null(q$plants)) updateCheckboxInput(session, "show_plants", value = q$plants == "1")
    if (!is.null(q$osm))    updateCheckboxInput(session, "show_osm",    value = q$osm == "1")
    if (!is.null(q$fac))    updateCheckboxInput(session, "show_fac",    value = q$fac == "1")
    if (!is.null(q$state) && q$state %in% c("All India", unique(na.omit(districts$state_name)))) updateSelectInput(session, "state", selected = q$state)
    if (!is.null(q$tab)) nav_select("tabs", q$tab)
    lat <- suppressWarnings(as.numeric(q$lat)); lng <- suppressWarnings(as.numeric(q$lng)); z <- suppressWarnings(as.numeric(q$zoom))
    if (length(lat) == 1 && length(lng) == 1 && length(z) == 1 && all(is.finite(c(lat, lng, z)))) restore_view(list(lat = lat, lng = lng, zoom = z))
  }, once = TRUE)
  observeEvent(input$map_zoom, {   # first zoom event = map is up; apply a view carried in the URL
    v <- restore_view(); if (!is.null(v)) { fly_to(v$lat, v$lng, v$zoom); restore_view(NULL) }
  }, once = TRUE)
  observe({
    c0 <- input$map_center; z <- input$map_zoom
    q <- list(scope = input$scope, layer = input$ind, plants = as.integer(isTRUE(input$show_plants)), osm = as.integer(isTRUE(input$show_osm)),
              fac = as.integer(isTRUE(input$show_fac)), state = input$state, tab = input$tabs,
              lat = if (!is.null(c0)) round(c0$lat, 3), lng = if (!is.null(c0)) round(c0$lng, 3), zoom = z)
    q <- q[!vapply(q, is.null, TRUE)]
    updateQueryString(paste0("?", paste(names(q), vapply(q, function(x) utils::URLencode(as.character(x), reserved = TRUE), ""), sep = "=", collapse = "&")), mode = "replace")
  })

  # ---- guided story: demand -> emissions -> exposure -> governance ------------------------------------
  vd <- function(p) if (p < 0.05) "distinguishable from parity" else "not distinguishable from parity"
  STORY <- list(
    list(title = "1. Where the demand is", layer = "Data centres (count)", fac = TRUE, plants = FALSE,
         text = function() sprintf(paste0("%d operating facilities in %d of India's 641 districts draw about %s TWh a year (%s%% of national ",
                                          "generation). %s%% of them are in the districts holding the richest fifth of the population by asset wealth; %s%% in the poorest fifth."),
                                   H$n_operating, H$hosting_districts_operating, fmt1(H$twh_operating), fmt1(H$pct_nat_gen_operating),
                                   fmt1(ej_quint_for(FALSE)$tab$`Share of facilities (%)`[5]), fmt1(ej_quint_for(FALSE)$tab$`Share of facilities (%)`[1])),
         caption = "Points are facilities (size = allocated IT load); shading counts them by district. Hover a point for its capacity; click it for its sources."),
    list(title = "2. Where the emissions are released", layer = "Scope 2 SO2 released at plants", fac = FALSE, plants = TRUE,
         text = function() { h <- ej_host_for(FALSE); sprintf(paste0("The marginal generation that meets this demand emits about %s kt SO2, %s kt NOx and %s kt primary PM2.5 a year, ",
                                                            "placed at %d coal and gas plants in %d districts under the state marginal-generation model. Hosting districts ",
                                                            "hold %s%% of the people %s %s%% of district-assigned coal capacity."),
                                                     fmt1(H$so2_kt_operating), fmt1(H$nox_kt_operating), fmt1(H$pm25_kt_operating), H$plants, H$emission_districts,
                                                     fmt1(h$`Share of population (%)`[1]), if (100 * h$`Coal capacity (GW)`[1] / h$`Coal capacity (GW)`[3] < h$`Share of population (%)`[1]) "but only" else "and",
                                                     fmt1(100 * h$`Coal capacity (GW)`[1] / h$`Coal capacity (GW)`[3])) },
         caption = "Plant circles are sized by capacity (grey coal, green gas); shading is attributable SO2 by plant district. The assignment is an estimated marginal mix, not a demonstrated supply relationship."),
    list(title = "3. Who breathes it", layer = "PM2.5 increment: operating only", fac = TRUE, plants = FALSE,
         text = function() { h <- ej_host_for(FALSE); m <- ej_disp_for(FALSE); k <- function(c) m[m$Contrast == c, ]
           sprintf(paste0("Dispersed through InMAP, the emissions raise population-weighted PM2.5 across India by %.4f ug/m3 (%s million people receive at least 0.01 ug/m3), about %s ",
                          "modelled deaths a year (GEMM), %s%% of them in districts without a data centre. Rural residents receive %.2f times the urban ",
                          "increment (%s) and Muslims %.2f times the Hindu increment (%s); SC/ST residents %.2f times the General-category ",
                          "increment (sign probability %.3f, %s)."),
                   H$inmap_operating$pwm_ugm3, fmtnum(H$inmap_operating$pop_ge_0_01_million), fmtnum(H$inmap_operating$deaths_per_yr),
                   fmt1(h$`Share of attributable deaths (%)`[2]),
                   k("Rural vs urban")$`Increment: ratio`, vd(k("Rural vs urban")$`Sign prob.`),
                   k("Muslim vs Hindu")$`Increment: ratio`, vd(k("Muslim vs Hindu")$`Sign prob.`),
                   k("SC/ST vs General")$`Increment: ratio`, k("SC/ST vs General")$`Sign prob.`, vd(k("SC/ST vs General")$`Sign prob.`)) },
         caption = "Shading is the modelled annual PM2.5 increment (log scale); the points stay in the cities while the shading follows the generation corridors and the wind."),
    list(title = "4. Who decides", layer = "Baseline water stress (Aqueduct)", fac = TRUE, plants = FALSE,
         text = function() { ph <- policies[policies$has_policy, ]
           sprintf(paste0("%d of the %d states reviewed offer a dedicated data-centre policy or data-centre provisions in an IT policy; together they host %d of the %d operating facilities (%d%%). ",
                          "None attaches a data-centre-specific environmental-assessment, water or energy condition to its incentives, and in %d of the %d every hosting ",
                          "district is in high baseline water stress. %s%% of the modelled deaths fall outside the districts that host the facilities."),
                   H$policy_states_dedicated, H$policy_states_reviewed, H$facilities_in_policy_states, H$n_operating,
                   round(100 * H$facilities_in_policy_states / H$n_operating), sum(ph$share_dists_high_stress >= 0.999, na.rm = TRUE), nrow(ph),
                   fmt1(ej_host_for(FALSE)$`Share of attributable deaths (%)`[2])) },
         caption = "Shading is Aqueduct baseline water stress (blue low, red high) with the facilities on top; the State policies tab has every policy claim with its source.")
  )
  story_stage <- reactiveVal(0L)
  go_stage <- function(i) {
    s <- STORY[[i]]
    updateRadioButtons(session, "scope", selected = "operating")
    updateSelectInput(session, "state", selected = "All India")
    updateSelectInput(session, "ind", selected = s$layer)
    updateCheckboxInput(session, "show_fac", value = s$fac); updateCheckboxInput(session, "show_plants", value = s$plants)
    updateCheckboxInput(session, "show_osm", value = FALSE)
    story_stage(i); nav_select("tabs", "Map"); fly_to(22, 79, 5)
  }
  output$story_cards <- renderUI({
    lapply(seq_along(STORY), function(i) { s <- STORY[[i]]
      div(class = "card mb-3", div(class = "card-body",
        h5(class = "card-title", s$title), p(s$text()), p(class = "text-muted small", s$caption),
        actionButton(paste0("story_go_", i), "Show this on the map", class = "btn-sm btn-primary")))
    })
  })
  lapply(seq_along(STORY), function(i) observeEvent(input[[paste0("story_go_", i)]], go_stage(i), ignoreInit = TRUE))
  observeEvent(input$story_next, go_stage(min(length(STORY), story_stage() + 1L)))
  observeEvent(input$story_back, go_stage(max(1L, story_stage() - 1L)))
  observeEvent(input$story_close, story_stage(0L))
  output$story_bar <- renderUI({
    i <- story_stage(); if (i < 1) return(NULL); s <- STORY[[i]]
    div(class = "alert alert-info py-2 px-3 mb-2", style = "font-size:0.92rem",
        tags$b(sprintf("Step %d of %d: %s. ", i, length(STORY), s$title)), s$text(), tags$br(), tags$span(class = "text-muted small", s$caption),
        div(class = "mt-1",
            if (i > 1) actionButton("story_back", "Back", class = "btn-sm btn-outline-secondary me-1"),
            if (i < length(STORY)) actionButton("story_next", "Next", class = "btn-sm btn-primary me-1"),
            actionButton("story_close", "Close", class = "btn-sm btn-link")))
  })

  # ---- step players: advance a step selector every 3 s until its last step ----
  aq_player <- function(id, n) {
    playing <- reactiveVal(FALSE); armed <- reactiveVal(FALSE)
    set_btn <- function(on) updateActionButton(session, paste0(id, "_play"), label = if (on) "Pause" else "Play", icon = icon(if (on) "pause" else "play"))
    observeEvent(input[[paste0(id, "_play")]], {
      on <- !playing(); playing(on); armed(FALSE); set_btn(on)
      if (on && as.integer(input[[id]]) >= n) updateRadioButtons(session, id, selected = 1)
    })
    observe({
      req(playing()); invalidateLater(3000)
      if (!isolate(armed())) { armed(TRUE); return() }      # first tick: show the current step for 3 s
      s <- as.integer(isolate(input[[id]]))
      if (s >= n) { playing(FALSE); set_btn(FALSE) } else updateRadioButtons(session, id, selected = s + 1)
    })
  }
  aq_player("aq_step", 4); aq_player("aq_fstep", 4)

  # ---- Follow one facility ----
  aq_fac_list <- local({
    f <- sf::st_drop_geometry(facilities); ok <- f$is_operating %in% TRUE & f$mw_it > 0
    f <- f[ok, ]; o <- order(-f$mw_it)
    setNames(f$facility_id[o], sprintf("%s (%s; %s, %s; %s MW)", f$name[o], f$operator[o], f$dist_name[o], f$state_name[o], fmtnum(f$mw_it[o], 1)))
  })
  updateSelectizeInput(session, "aq_fac", choices = aq_fac_list, selected = aq_fac_list[1], server = TRUE)
  aq_fac <- reactive({
    req(input$aq_fac); i <- which(facilities$facility_id == input$aq_fac)[1]; req(length(i) == 1, !is.na(i))
    f <- sf::st_drop_geometry(facilities)[i, ]; xy <- unname(as.numeric(sf::st_coordinates(facilities)[i, 1:2]))   # plain numbers: named X/Y would serialise as an object and Leaflet draws nothing
    st <- aq_fixst(f$state_name); el <- AQ$el[AQ$el$load_state == st, ]; req(nrow(el) == 1)
    share <- f$e_fac_gwh / el$gwh
    al <- lapply(c("SO2", "NOX", "PM2.5"), function(p) { a <- aq_alloc(st, p); a$rows$t <- a$rows$t * share; a$rows$pol <- p; a$rows })
    so2 <- al[[1]]; so2$t_nox <- al[[2]]$t; so2$t_pm <- al[[3]]$t
    list(f = f, xy = xy, st = st, el = el, share = share, plants = so2,
         t = c(SO2 = f$e_fac_gwh * el$ef_SO2, NOX = f$e_fac_gwh * el$ef_NOX, PM2.5 = f$e_fac_gwh * el$ef_PM2.5, CO2 = f$e_fac_gwh * el$ef_CO2))
  })
  output$aq_facmap <- renderLeaflet({
    x <- aq_fac(); st <- if (is.null(input$aq_fstep)) 1L else as.integer(input$aq_fstep)
    pp <- x$plants[order(-x$plants$t), ]; pp <- pp[pp$t > 0, ]; top <- head(pp, 40)
    pxy <- sf::st_coordinates(plants)[top$idx, , drop = FALSE]
    m <- leaflet() |>
      addTiles("https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}",
               attribution = "Tiles &copy; Esri &mdash; Esri, HERE, Garmin, &copy; OpenStreetMap contributors")
    if (st == 4) {
      pal <- colorNumeric("YlOrRd", domain = log10(pmax(districts$dpm25, 1e-4)), na.color = "transparent")
      m <- m |> addPolygons(data = districts, fillColor = pal(log10(pmax(districts$dpm25, 1e-4))), fillOpacity = 0.75, color = "#999", weight = 0.3,
                            label = sprintf("%s: %.4f ug/m3 (whole sector)", districts$dist_name, districts$dpm25))
    }
    if (st >= 3) {
      w <- 1 + 7 * sqrt(top$t / max(top$t))
      for (k in seq_len(nrow(top))) m <- m |> addPolylines(lng = c(x$xy[1], pxy[k, 1]), lat = c(x$xy[2], pxy[k, 2]), weight = w[k],
                                                          color = if (top$fuel[k] == "Coal") "#2c3e50" else "#e67e22", opacity = if (st == 4) 0.35 else 0.6)
      m <- m |> addCircleMarkers(lng = pxy[, 1], lat = pxy[, 2], radius = 3 + 12 * sqrt(top$t / max(top$t)), weight = 1, color = "#333",
                                 fillColor = ifelse(top$fuel == "Coal", "#2c3e50", "#e67e22"), fillOpacity = 0.8,
                                 label = sprintf("%s (%s, %s MW): %s t SO2, %s t NOx, %s t PM2.5 a year from this facility",
                                                 top$name, top$fuel, fmtnum(top$capacity_mw), fmtnum(top$t, 2), fmtnum(top$t_nox, 2), fmtnum(top$t_pm, 3)))
    }
    m <- m |> addCircleMarkers(lng = x$xy[1], lat = x$xy[2], radius = 9, color = "#fff", weight = 2, fillColor = "#18bc9c", fillOpacity = 1,
                               label = sprintf("%s: %s MW, %s GWh/yr", x$f$name, fmtnum(x$f$mw_it, 1), fmtnum(x$f$e_fac_gwh)))
    if (st <= 2) m <- m |> setView(x$xy[1], x$xy[2], zoom = 9) else if (st == 3) {
      bb <- range(c(pxy[, 1], x$xy[1])); bb2 <- range(c(pxy[, 2], x$xy[2])); m <- m |> fitBounds(bb[1], bb2[1], bb[2], bb2[2])
    } else m <- m |> fitBounds(68, 7, 97, 36)
    m
  })
  output$aq_fac_text <- renderUI({
    x <- aq_fac(); st <- if (is.null(input$aq_fstep)) 1L else as.integer(input$aq_fstep); f <- x$f
    pp <- x$plants[order(-x$plants$t), ]; co <- pp[pp$fuel == "Coal", ]
    nat <- any(co$national)
    body <- switch(as.character(st),
      "1" = list(tags$b("1. The facility."),
                 sprintf("%s (%s, %s) is a %s facility with %s MW of IT load (%s). At a PUE of 1.6 and utilisation of 0.7 it uses %s MW x 9.811 GWh per MW = %s GWh of electricity a year, from the %s grid.",
                         f$name, f$dist_name, f$state_name, f$dc_type, fmtnum(f$mw_it, 2),
                         if (!is.na(f$mw_reported)) "published" else "modelled; see the Facilities tab", fmtnum(f$mw_it, 2), fmtnum(f$e_fac_gwh, 1), x$st)),
      "2" = list(tags$b("2. The emissions it causes."),
                 sprintf("%s GWh x %s's marginal emission factors (kg/MWh: SO2 %s, NOx %s, PM2.5 %s) = %s t SO2, %s t NOx and %s t primary PM2.5 a year (and %s t CO2). That is %s%% of %s's data-centre electricity, and %s%% of the sector's SO2.",
                         fmtnum(f$e_fac_gwh, 1), x$st, formatC(x$el$ef_SO2, format = "f", digits = 2), formatC(x$el$ef_NOX, format = "f", digits = 2), formatC(x$el$ef_PM2.5, format = "f", digits = 3),
                         fmtnum(x$t[["SO2"]], 1), fmtnum(x$t[["NOX"]], 1), fmtnum(x$t[["PM2.5"]], 2), fmtnum(x$t[["CO2"]]),
                         formatC(100 * x$share, format = "f", digits = 2), x$st, formatC(100 * x$t[["SO2"]] / AQ$so2, format = "f", digits = 3))),
      "3" = list(tags$b("3. The plants that emit them."),
                 sprintf("%s The lines (largest 40 shown) are sized by tonnes; the largest share, %s t SO2, goes to %s (%s MW, %s). Hover a plant for its tonnes.",
                         if (nat) sprintf("%s has no coal plant, so the coal share is spread over all %d coal plants in India by capacity.", x$st, sum(pp$fuel == "Coal"))
                         else sprintf("Coal carries %s%% of the SO2 and is shared among %s's %d coal plants by capacity; the small gas share goes to %s gas plants.",
                                      formatC(100 * (1 - GAS_RATIO[["SO2"]] / (1 + GAS_RATIO[["SO2"]])), format = "f", digits = 2), x$st, nrow(co),
                                      if (any(pp$fuel == "Gas" & pp$national)) "all of India's" else paste0(x$st, "'s")),
                         fmtnum(pp$t[1], 2), pp$name[1], fmtnum(pp$capacity_mw[1]), pp$plant_state[1])),
      "4" = list(tags$b("4. Where the pollution goes."),
                 "The map now shows InMAP's result for the whole sector: the increment in every district from all data centres' emissions together (log colour scale). ",
                 tags$br(), tags$br(),
                 tags$span(class = "text-muted", sprintf(paste0("InMAP was run once for the sector as a whole, not for each facility, so this facility's own map is not computed. ",
                         "It causes %s%% of the sector's SO2 and %s%% of the emissions of %s's data centres; because the model responds almost linearly at this scale, ",
                         "its contribution is roughly that share of the part of the field caused by %s's data centres. A facility-specific map would need separate model runs (about one per state)."),
                         formatC(100 * x$t[["SO2"]] / AQ$so2, format = "f", digits = 3), formatC(100 * x$share, format = "f", digits = 1), x$st, x$st))))
    div(class = "border rounded p-3 bg-light", style = "min-height: 260px", lapply(body, function(b) if (is.character(b)) p(b) else b))
  })

  # ---- Air-quality model tab: from a load state's emissions to individual plants ----
  aq_al <- reactive({ req(input$aq_state, input$aq_pol); aq_alloc(input$aq_state, input$aq_pol) })
  output$aq_alloc_text <- renderUI({
    a <- aq_al(); pol <- c(SO2 = "SO2", NOX = "NOx", PM2.5 = "primary PM2.5")[[input$aq_pol]]; st <- input$aq_state
    r <- a$rows; co <- r[r$fuel == "Coal", ]; ga <- r[r$fuel == "Gas", ]
    fuel_line <- function(x, fu) {
      if (!nrow(x)) return(NULL)
      if (x$national[1]) tags$li(sprintf("%s: %s t. %s has no %s plant, so this goes to all %d %s plants in India in proportion to capacity (%s MW).",
                                         fu, fmtnum(x$t_fuel[1], 1), st, tolower(fu), nrow(x), tolower(fu), fmtnum(x$fleet_mw[1])))
      else tags$li(sprintf("%s: %s t, shared among %s's %d %s plant%s (%s MW) by capacity: a plant with 1,000 MW gets %s t.",
                           fu, fmtnum(x$t_fuel[1], 1), st, nrow(x), tolower(fu), if (nrow(x) > 1) "s" else "", fmtnum(x$fleet_mw[1]),
                           fmtnum(1000 / x$fleet_mw[1] * x$t_fuel[1], 1)))
    }
    div(
      p(sprintf("%s's data centres draw %s GWh a year. At %s kg of %s per MWh (Sengupta et al., 2022) that is %s t of %s a year.",
                st, fmtnum(a$el$gwh), formatC(a$el[[paste0("ef_", input$aq_pol)]], format = "f", digits = 3), pol, fmtnum(a$total, 1), pol)),
      p(sprintf("Split between fuels with a fixed national gas : coal ratio for %s of 1 : %s, so gas carries %s%% and coal %s%%:",
                pol, fmtnum(1 / GAS_RATIO[[input$aq_pol]], if (input$aq_pol == "NOX") 1 else 0), formatC(100 * a$gas_frac, format = "f", digits = 3), formatC(100 * (1 - a$gas_frac), format = "f", digits = 3))),
      tags$ul(fuel_line(co, "Coal"), fuel_line(ga, "Gas")),
      p(class = "small text-muted", "The ratios reflect how little SO2 and particulate matter gas plants emit compared with coal; plants are point sources at 200 m (coal) or 100 m (gas) in InMAP."))
  })
  output$aq_alloc_tab <- renderUI({
    a <- aq_al(); r <- a$rows; r <- r[order(-r$t), ]; k <- head(r, 12)
    tags$details(tags$summary(sprintf("Plant by plant: where %s's %s goes (%d plants; largest 12 shown)", input$aq_state, c(SO2 = "SO2", NOX = "NOx", PM2.5 = "PM2.5")[[input$aq_pol]], nrow(r))),
      tags$table(class = "table table-sm mt-2",
        tags$thead(tags$tr(lapply(c("Plant", "State", "Fuel", "Capacity (MW)", "Share of the fleet it is in", "Tonnes a year from this state"), function(h) tags$th(h)))),
        tags$tbody(lapply(seq_len(nrow(k)), function(i) with(k[i, ], tags$tr(tags$td(name), tags$td(plant_state), tags$td(fuel), tags$td(class = "text-end", fmtnum(capacity_mw)),
                                                                             tags$td(class = "text-end", sprintf("%s / %s MW = %s%%", fmtnum(capacity_mw), fmtnum(fleet_mw), formatC(100 * share, format = "f", digits = 2))),
                                                                             tags$td(class = "text-end", fmtnum(t, 1))))),
                   tags$tr(class = "fw-bold", tags$td("All plants"), tags$td(), tags$td(), tags$td(), tags$td(), tags$td(class = "text-end", fmtnum(sum(r$t), 1))))))
  })
  output$aq_plantmap <- renderLeaflet({
    a <- aq_al(); r <- a$rows
    xy <- sf::st_coordinates(plants)[r$idx, , drop = FALSE]
    leaflet() |> addTiles("https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}", attribution = "Tiles &copy; Esri &mdash; Esri, HERE, Garmin, &copy; OpenStreetMap contributors") |>
      addTiles("https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Reference/MapServer/tile/{z}/{y}/{x}") |>
      addCircleMarkers(lng = xy[, 1], lat = xy[, 2], radius = 3 + 15 * sqrt(r$t / max(r$t)), stroke = TRUE, weight = 1, color = "#333",
                       fillColor = ifelse(r$fuel == "Coal", "#2c3e50", "#e67e22"), fillOpacity = 0.7,
                       label = sprintf("%s (%s, %s MW): %s t", r$name, r$fuel, fmtnum(r$capacity_mw), fmtnum(r$t, 1))) |>
      addLegend("bottomright", colors = c("#2c3e50", "#e67e22"), labels = c("coal", "gas"), opacity = 0.8)
  })

  # ---- Air-quality model tab: grid -> district for one district (animated by the step slider), then GEMM ----
  aq_sel <- reactive({
    req(AQG, input$aq_dist)
    pcs <- AQG$pieces[AQG$pieces$zone_uid == input$aq_dist, ]; req(nrow(pcs) > 0)
    dpoly <- sf::st_make_valid(districts[districts$zone_uid == input$aq_dist, ])
    boxes <- sf::st_sfc(lapply(seq_len(nrow(pcs)), function(i) with(pcs[i, ], sf::st_polygon(list(rbind(c(xmin, ymin), c(xmax, ymin), c(xmax, ymax), c(xmin, ymax), c(xmin, ymin)))))),
                        crs = sf::st_crs(dpoly))
    clip <- suppressWarnings(suppressMessages(sf::st_intersection(sf::st_sf(pcs, geometry = boxes), sf::st_geometry(dpoly))))
    lat <- (pcs$ymin + pcs$ymax) / 2
    pcs$w_km <- (pcs$xmax - pcs$xmin) * 111.32 * cos(lat * pi / 180); pcs$h_km <- (pcs$ymax - pcs$ymin) * 110.57
    list(pcs = pcs, clip = clip, dpoly = dpoly, d = AQ$d[AQ$d$zone_uid == input$aq_dist, ][1, ],
         dmean = sum(pcs$popw * pcs$pm) / sum(pcs$popw), pop = sum(pcs$popw), pu = sum(pcs$popw * pcs$pm))
  })
  output$aq_gridmap <- renderLeaflet({
    x <- aq_sel(); st <- if (is.null(input$aq_step)) 1L else as.integer(input$aq_step); pcs <- x$pcs
    pal <- colorNumeric("YlOrRd", domain = range(c(pcs$pm, x$dmean)))
    bb <- as.numeric(sf::st_bbox(x$dpoly))
    m <- leaflet(options = leafletOptions(zoomControl = TRUE)) |> addTiles("https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}", attribution = "Tiles &copy; Esri &mdash; Esri, HERE, Garmin, &copy; OpenStreetMap contributors") |>
      addTiles("https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Reference/MapServer/tile/{z}/{y}/{x}") |>
      addRectangles(lng1 = pcs$xmin, lat1 = pcs$ymin, lng2 = pcs$xmax, lat2 = pcs$ymax, fillColor = pal(pcs$pm),
                    fillOpacity = if (st == 1) 0.8 else 0.15, color = "#555", weight = 0.7,
                    label = sprintf("model cell: %.4f ug/m3; %s people in the whole cell", pcs$pm, fmtnum(pcs$pop)))
    if (st >= 2) m <- m |> addPolygons(data = x$clip, fillColor = pal(x$clip$pm), fillOpacity = if (st == 4) 0.15 else 0.8, color = "#333", weight = 0.6,
                                       label = sprintf("piece: %.0f%% of the cell inside; %s people; %.4f ug/m3", 100 * x$clip$frac, fmtnum(x$clip$popw), x$clip$pm))
    if (st >= 2) m <- m |> addPolygons(data = x$dpoly, fill = st == 4, fillColor = pal(x$dmean), fillOpacity = 0.85, color = "#2c3e50", weight = 3,
                                       label = sprintf("%s: district increment %.4f ug/m3", x$d$dist_name, x$dmean))
    if (st == 3) {
      ctr <- suppressWarnings(sf::st_coordinates(sf::st_point_on_surface(x$clip)))
      m <- m |> addCircleMarkers(lng = ctr[, 1], lat = ctr[, 2], radius = 2 + 14 * sqrt(x$clip$popw / max(x$clip$popw)), stroke = FALSE,
                                 fillColor = "#2c3e50", fillOpacity = 0.6, label = sprintf("%s people x %.4f ug/m3", fmtnum(x$clip$popw), x$clip$pm))
    }
    m |> addLegend("bottomright", pal = pal, values = c(pcs$pm, x$dmean), title = "ug/m3", opacity = 0.8) |>
      fitBounds(bb[1], bb[2], bb[3], bb[4])
  })
  output$aq_grid_text <- renderUI({
    x <- aq_sel(); st <- if (is.null(input$aq_step)) 1L else as.integer(input$aq_step); p <- x$pcs
    whole <- sum(p$frac > 0.999); big <- p[which.max(p$popw), ]
    txt <- switch(as.character(st),
      "1" = list(tags$b("Step 1. The model's grid."),
                 sprintf("%d InMAP %s overlap %s, from %s to %s km across. Each cell has a single annual-average increment, here from %s to %s ug/m3, and a 2020 population.",
                         nrow(p), if (nrow(p) == 1) "cell" else "cells", x$d$dist_name, fmtnum(min(pmin(p$w_km, p$h_km)), 1), fmtnum(max(pmax(p$w_km, p$h_km)), 1), formatC(min(p$pm), format = "f", digits = 4), formatC(max(p$pm), format = "f", digits = 4))),
      "2" = list(tags$b("Step 2. Cut the cells at the district boundary."),
                 sprintf("%d %s wholly inside; the other %d %s cut, and each piece keeps the share of the cell's area (and so of its people) that falls inside the district.", whole, if (whole == 1) "cell lies" else "cells lie", nrow(p) - whole, if (nrow(p) - whole == 1) "is" else "are")),
      "3" = list(tags$b("Step 3. Weight each piece by its people."),
                 sprintf("The pieces hold %s people in all. The most populous piece has %s people at %s ug/m3, contributing %s person-ug/m3; dots are sized by people.",
                         fmtnum(x$pop), fmtnum(big$popw), formatC(big$pm, format = "f", digits = 4), fmtnum(big$popw * big$pm, 1))),
      "4" = list(tags$b("Step 4. The district's increment."),
                 sprintf("sum(people x increment) / sum(people) = %s / %s = %s ug/m3, the value shown for %s on the Map tab (%s).",
                         fmtnum(x$pu, 1), fmtnum(x$pop), formatC(x$dmean, format = "f", digits = 4), x$d$dist_name, formatC(x$d$dpm25, format = "f", digits = 4))))
    div(class = "border rounded p-3 bg-light", style = "min-height: 200px", p(txt[[1]]), p(class = "mb-0", txt[[2]]))
  })
  output$aq_pieces_tab <- renderUI({
    x <- aq_sel(); p <- x$pcs[order(-x$pcs$popw), ]; k <- head(p, 10)
    row <- function(...) tags$tr(lapply(list(...), function(v) tags$td(class = "text-end", v)))
    tags$details(class = "mt-2", tags$summary(sprintf("All the numbers: the %d pieces of %s (largest 10 shown)", nrow(p), x$d$dist_name)),
      tags$table(class = "table table-sm mt-2",
        tags$thead(tags$tr(lapply(c("Cell centre (lat, lon)", "Cell size (km)", "Share inside", "People in piece", "Increment (ug/m3)", "People x increment", "Deaths/yr"),
                                  function(h) tags$th(class = "text-end", h)))),
        tags$tbody(lapply(seq_len(nrow(k)), function(i) with(k[i, ], row(sprintf("%.2f, %.2f", (ymin + ymax) / 2, (xmin + xmax) / 2), sprintf("%.0f x %.0f", w_km, h_km),
                                                                          sprintf("%.0f%%", 100 * frac), fmtnum(popw), formatC(pm, format = "f", digits = 4), fmtnum(popw * pm, 1), fmtnum(deaths, 2)))),
                   tags$tr(class = "fw-bold", tags$td(class = "text-end", sprintf("All %d pieces", nrow(p))), tags$td(), tags$td(), tags$td(class = "text-end", fmtnum(x$pop)),
                           tags$td(class = "text-end", formatC(x$dmean, format = "f", digits = 4)), tags$td(class = "text-end", fmtnum(x$pu, 1)),
                           tags$td(class = "text-end", fmtnum(sum(p$deaths), 1))))))
  })
  output$aq_health <- renderUI({
    x <- aq_sel(); d <- x$d
    base <- x$pop * GEMM$adult * GEMM$y0
    hz <- gemm_hr(d$z); hz2 <- gemm_hr(d$z + x$dmean); ex <- hz2 / hz - 1
    row <- function(k, v, cls = NULL) tags$tr(class = cls, tags$td(k), tags$td(class = "text-end", v))
    tags$table(class = "table table-sm mb-3", style = "max-width: 860px",
      tags$tbody(
        row(sprintf("People in %s on the model grid (step 5)", d$dist_name), fmtnum(x$pop)),
        row("x 0.562 adults (25+) x 0.0087 NCD+LRI deaths per adult per year = baseline deaths from these causes", fmtnum(base)),
        row(sprintf("PM2.5 already in the air (satellite-derived ACAG, 2013-2022): %s ug/m3, so z = %s - 2.4 =", fmtnum(d$pm25_acag_local, 2), fmtnum(d$pm25_acag_local, 2)), fmtnum(d$z, 2)),
        row("District increment from data-centre electricity (step 5)", formatC(x$dmean, format = "f", digits = 4)),
        row(sprintf("HR(z) = %s; HR(z + increment) = %s; extra risk = HR(z + increment) / HR(z) - 1 =", formatC(hz, format = "f", digits = 5), formatC(hz2, format = "f", digits = 5)),
            sprintf("%s%%", formatC(100 * ex, format = "f", digits = 3))),
        row(sprintf("Deaths a year = %s x %s%%", fmtnum(base), formatC(100 * ex, format = "f", digits = 3)), fmtnum(base * ex, 1), "fw-bold"),
        row("The model applies the same formula to each piece with its own increment and adds them up (table in step 5); that is the figure the paper and the map use", fmtnum(sum(x$pcs$deaths), 1), "text-muted")))
  })

  # ---- facility evidence on click: from the plotted point to its documentary record (public table) ----
  observeEvent(input$map_marker_click, {
    id <- input$map_marker_click$id; req(!is.null(id), !is.null(pubtab), id %in% pubtab$facility_id)
    r <- pubtab[pubtab$facility_id == id, ][1, ]
    f <- facilities[facilities$facility_id == id, ]; f <- if (nrow(f)) sf::st_drop_geometry(f)[1, ] else NULL
    has <- function(x) !is.null(x) && !is.na(x) && nzchar(trimws(as.character(x)))
    rowv <- function(k, v) tags$tr(tags$td(class = "text-muted pe-3", style = "white-space:nowrap", k), tags$td(HTML(v)))
    cap <- if (!is.null(f)) sprintf("%s MW used in the paper; %s MW in the stock-plus-pipeline scenario",
                                    if (is.na(r$mw_it_used_in_paper)) "none (not operating)" else fmtnum(r$mw_it_used_in_paper, 2),
                                    fmtnum(r$mw_it_used_in_pipeline_scenario, 2)) else ""
    showModal(modalDialog(
      title = tagList(esc(r$facility_name), tags$small(class = "text-muted ms-2", esc(r$facility_id))),
      tags$table(class = "table table-sm mb-2",
        rowv("Operator / type", paste0(esc(r$operator), " | ", esc(r$facility_type))),
        rowv("Status", paste0(esc(r$status), if (has(r$status_in_source)) paste0(" (source says: ", esc(r$status_in_source), ")") else "")),
        rowv("Location", sprintf("%s, %s, %s; %.5f, %.5f; geocode precision: <b>%s</b>",
                                 esc(r$city), esc(r$district_2015), esc(r$state_current), as.numeric(r$latitude), as.numeric(r$longitude), esc(r$location_precision))),
        rowv("Reported IT load", if (!has(r$mw_it_reported_current) && !has(r$mw_it_reported_buildout)) "not published" else
               sprintf("current %s MW; build-out %s MW%s%s",
                       fmtnum(r$mw_it_reported_current, 1), fmtnum(r$mw_it_reported_buildout, 1),
                       if (has(r$mw_basis)) paste0("; basis: ", esc(r$mw_basis)) else "",
                       if (has(r$mw_flag)) paste0(" (", esc(r$mw_flag), ")") else "")),
        if (has(r$mw_published_figures)) rowv("Published figures", esc(r$mw_published_figures)),
        rowv("How its IT load was set", paste0(esc(r$mw_method),
             if (grepl("^modelled", r$mw_method)) " <i>(step-by-step calculation on the Facilities tab)</i>" else "")),
        rowv("Capacity used", cap),
        rowv("Source", paste0(safe_link(r$source_url), " (", esc(r$source_type), ")",
                              if (has(r$source_url_archive)) paste0(" | archived: ", safe_link(r$source_url_archive)) else "")),
        rowv("Second source", if (has(r$source_url_2)) paste0(safe_link(r$source_url_2),
                              if (has(r$source_url_2_archive)) paste0(" | archived: ", safe_link(r$source_url_2_archive)) else "") else "none"),
        rowv("Verification", sprintf("%s; confidence <b>%s</b>%s; sources retrieved %s", esc(r$source_verification), esc(r$confidence),
                                     if (has(r$confidence_note)) paste0(" (", esc(r$confidence_note), ")") else "", esc(r$sources_retrieved))),
        rowv("Atlas of Data Center Politics", if (r$adp_match == "none") "not in the Atlas" else sprintf("%s (%s, %s)", esc(r$adp_campus_name), esc(r$adp_status), esc(r$adp_size_bucket))),
        if (has(r$correction_applied)) rowv("Corrections made during verification", paste0(esc(r$correction_applied), " - evidence: ", esc(r$correction_evidence))),
        if (has(r$open_issue)) rowv("Open issue", esc(r$open_issue))),
      p(class = "text-muted small mb-0", "Every row of the public facility table (CC BY-NC 4.0) is on the Facilities tab; the documented dataset bundles it with every cited URL and its archived copy."),
      easyClose = TRUE, size = "l", footer = modalButton("Close")))
  })
}

shinyApp(ui, server)
