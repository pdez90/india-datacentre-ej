emission_factors.csv - every emission-related factor used in the analysis, one row per factor and level (low / central / high where a range is used).
Columns: factor, category, applies_to (state, fuel or all facilities), level, value, unit, used_in_paper, source, how_used, script, notes.
Grid marginal factors (kg/MWh) are Sengupta et al. (2022), 2017-18, flat-load weighted; each facility draws load from its own state (Telangana
has its own row; every load state of the 246 facilities has a factor, so no imputation was needed). The average grid CO2 factor (CEA 2024) gives the
footprint CO2; the marginal factors give the marginal CO2 and all SO2 / NOx / PM2.5. Electricity = IT MW x PUE x utilisation x 8.76.
Scripts: 15_attribution.R, 15a_mef_kilthub.R, 15b_marginal_mef.R, 16b_build_emissions.R, 29_backup_diesel.R. Licence: CC BY-NC 4.0.
