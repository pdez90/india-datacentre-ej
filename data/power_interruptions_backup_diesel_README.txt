power_interruptions_backup_diesel.csv - one row per district hosting an operating data centre (India, inventory v2), plus a total row.

Interruption hours. Prayas Energy Group, Electricity Supply Monitoring Initiative (ESMI), Harvard Dataverse doi:10.7910/DVN/CLLZZM:
voltage logged every minute at customer connections, Oct 2014 - Dec 2019. A minute with voltage below 80 V is an interruption; a blank
minute is missing data, not an interruption. Hours per year = interrupted minutes / recorded minutes x 8760, per monitor; monitors with
fewer than 30 recorded days are excluded; the district value is the plain mean over its monitors. Urban = state capital, district
headquarters or other municipal area; rural = gram panchayat. Monitors are at ordinary customer premises, not at data centres.
ESMI terms: non-commercial research use with acknowledgement; Prayas asks to be informed of publications (esmi@prayaspune.org).

Backup diesel (central scenario). Generator hours H = f x O_d + T, with O_d the district's urban-monitor interruption hours
(tiers: district urban monitors; district rural-only monitors; state median of urban monitors; national median of urban monitors),
f = 0.4 (data centres sit on dedicated high-tension feeders that see fewer interruptions than customer connections; 0.2-1.0 in the
sensitivity), T = 100 h/yr of scheduled testing (50-150). Diesel electricity = facility average load x H (full load during backup).
Emission factors: NOx 8 g/kWh (4-14), PM2.5 0.20 g/kWh (0.05-0.5), SO2 0.005 g/kWh, CO2 0.75 kg/kWh. The submitted paper's rule
(unmonitored districts get testing hours only) is reported as outage_hours_zero_fill_rule.
Scripts: 28_esmi_outages.py, 29_backup_diesel.R, 30_app_download_tables.R. Licence of this table: CC BY-NC 4.0.
