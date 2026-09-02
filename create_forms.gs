/**
 * Creates the two community-submission Google Forms used by the India Data
 * Centre Environmental Justice Explorer (shinyapp/app.R), links both to one
 * response spreadsheet, and logs the embed URLs to set as FORM_DC_URL and
 * FORM_POLICY_URL on Posit Connect Cloud.
 *
 * How to run (once):
 *   1. Open https://script.google.com while signed in to the Google account that
 *      should own the forms  -> "New project".
 *   2. Replace the contents of Code.gs with this file, save, and run
 *      createSubmissionForms() (the ▶ Run button). Approve the Forms/Drive/Sheets
 *      permissions when asked (first run only).
 *   3. Open View -> Execution log (or Ctrl/Cmd+Enter). Copy the two embed URLs into
 *      Connect Cloud -> the app -> Settings -> Environment variables, then republish.
 *
 * Everything lands in a Drive folder "India DC Explorer submissions" so the forms
 * and the response sheet are easy to find.  Re-running creates a second set; delete
 * the folder first if you want a clean redo.
 */

var FOLDER_NAME   = 'India DC Explorer submissions';
var CONTACT_EMAIL = 'priyanka.desouza@ucdenver.edu';

var STATES_AND_UTS = [
  'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh', 'Goa',
  'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka', 'Kerala',
  'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland',
  'Odisha', 'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana', 'Tripura',
  'Uttar Pradesh', 'Uttarakhand', 'West Bengal',
  'Andaman and Nicobar Islands', 'Chandigarh', 'Dadra and Nagar Haveli and Daman and Diu',
  'Delhi (NCT)', 'Jammu and Kashmir', 'Ladakh', 'Lakshadweep', 'Puducherry'
];

function createSubmissionForms() {
  var folder = getOrCreateFolder_(FOLDER_NAME);

  // One spreadsheet, two response tabs (Google names them "Form Responses 1/2").
  var ss = SpreadsheetApp.create('India DC Explorer - form responses');
  moveToFolder_(DriveApp.getFileById(ss.getId()), folder);

  var dcForm  = buildFacilityForm_(ss, folder);
  var polForm = buildPolicyForm_(ss, folder);

  var dcEmbed  = embedUrl_(dcForm);
  var polEmbed = embedUrl_(polForm);

  Logger.log('\n==================== COPY THESE ====================');
  Logger.log('FORM_DC_URL=%s', dcEmbed);
  Logger.log('FORM_POLICY_URL=%s', polEmbed);
  Logger.log('====================================================');
  Logger.log('Edit facility form : %s', dcForm.getEditUrl());
  Logger.log('Edit policy form   : %s', polForm.getEditUrl());
  Logger.log('Response sheet     : %s', ss.getUrl());
  Logger.log('Drive folder       : %s', folder.getUrl());

  // Also drop a README into the folder so the URLs are not only in the log.
  var note = [
    'India DC Explorer - submission forms (created ' + new Date().toISOString() + ')', '',
    'Set these on Posit Connect Cloud (Settings -> Environment variables):',
    'FORM_DC_URL=' + dcEmbed,
    'FORM_POLICY_URL=' + polEmbed, '',
    'Edit facility form: ' + dcForm.getEditUrl(),
    'Edit policy form:   ' + polForm.getEditUrl(),
    'Responses:          ' + ss.getUrl()
  ].join('\n');
  moveToFolder_(DriveApp.createFile('README - form URLs.txt', note), folder);
}

// ---------------------------------------------------------------------------
// Form 1: facility submissions
// ---------------------------------------------------------------------------
function buildFacilityForm_(ss, folder) {
  var form = FormApp.create('India data centre inventory - submit a facility');
  moveToFolder_(DriveApp.getFileById(form.getId()), folder);

  form.setDescription(
    'The India Data Centre Environmental Justice Explorer inventory is built from ' +
    'operator facility lists and a curated directory, checked against independent ' +
    'sources. Facilities open, close and change hands faster than any single source ' +
    'records, so additions and corrections are welcome. Every submission is verified ' +
    'against the source you cite before it enters the inventory; nothing submitted ' +
    'here changes the map automatically. Questions: ' + CONTACT_EMAIL);
  applyCommonSettings_(form,
    'Thank you. We will check the facility against the source you gave before adding ' +
    'it to the inventory.');

  form.addMultipleChoiceItem()
    .setTitle('Is this a new facility or a correction to one already on the map?')
    .setChoiceValues(['New facility not on the map', 'Correction to an existing entry'])
    .setRequired(true);

  form.addTextItem()
    .setTitle('Data centre name (and operator, if different)')
    .setRequired(true);

  form.addParagraphTextItem()
    .setTitle('Address, or the most precise location you can give')
    .setHelpText('Locality, city, state; a map link if you have one.')
    .setRequired(true);

  form.addTextItem()
    .setTitle('Capacity, if known')
    .setHelpText('IT load or total power in MW. Say which, and quote the figure as ' +
                 'the source gives it (e.g. "20 MW IT", "45 MW total power").');

  form.addMultipleChoiceItem()
    .setTitle('Status')
    .setChoiceValues(['Operating', 'Under construction', 'Announced / planned', 'Closed', 'Not sure'])
    .setRequired(true);

  form.addCheckboxItem()
    .setTitle('How did you find out about this data centre?')
    .setChoiceValues(['Operator website or facility page', 'News report', 'Site visit',
                      'Planning or regulatory notice', 'Industry directory or report'])
    .showOtherOption(true)
    .setRequired(true);

  form.addParagraphTextItem()
    .setTitle('Link(s) to the source, or a description of it')
    .setHelpText('Entries are verified against this before they are added, so a URL ' +
                 'helps a lot. If it was a site visit, say roughly when.')
    .setRequired(true);

  addContactItems_(form, 'only used to follow up on this entry');
  return linkToSheet_(form, ss);
}

// ---------------------------------------------------------------------------
// Form 2: state policy submissions
// ---------------------------------------------------------------------------
function buildPolicyForm_(ss, folder) {
  var form = FormApp.create('India data centre policy tracker - submit a policy');
  moveToFolder_(DriveApp.getFileById(form.getId()), folder);

  form.setDescription(
    'States are competing for data centres with capital subsidies, duty exemptions, ' +
    'land and single-window clearance, and the policies change every year. The ' +
    'Explorer tracks them on its State policies tab with a source for every claim. If ' +
    'a state has enacted, amended or replaced a policy, please send the link to the ' +
    'notification or an official summary. Questions: ' + CONTACT_EMAIL);
  applyCommonSettings_(form,
    'Thank you. We will read the notification you linked before updating the tracker.');

  form.addListItem()
    .setTitle('State or union territory')
    .setChoiceValues(STATES_AND_UTS)
    .setRequired(true);

  form.addTextItem()
    .setTitle('Policy name and year')
    .setHelpText('e.g. "Data Centre Policy 2024", "IT & ITeS Policy 2022 (data-centre chapter)".')
    .setRequired(true);

  form.addTextItem()
    .setTitle('Link to the notification, gazette or official summary')
    .setHelpText('An official source (gazette, government order, department page). Press ' +
                 'coverage is fine as a second link, in the last question.')
    .setValidation(FormApp.createTextValidation()
      .setHelpText('Please paste a full URL starting with http:// or https://')
      .requireTextIsUrl()
      .build())
    .setRequired(true);

  form.addCheckboxItem()
    .setTitle('What does it offer data centres?')
    .setChoiceValues(['Capital subsidy', 'Stamp-duty exemption', 'Electricity-duty exemption',
                      'Land incentive (allotment, rebate or conversion)', 'Single-window clearance',
                      'Power tariff concession or open access', 'Infrastructure status'])
    .showOtherOption(true);

  form.addMultipleChoiceItem()
    .setTitle('Does the policy require any environmental assessment, or set water or energy conditions?')
    .setChoiceValues(['Yes', 'No', 'Not stated'])
    .setRequired(true);

  form.addParagraphTextItem()
    .setTitle('Anything else worth recording')
    .setHelpText('Amendments, successor policies, whether it replaces an earlier policy, ' +
                 'other links.');

  addContactItems_(form, 'only used to follow up on this entry');
  return linkToSheet_(form, ss);
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------
function applyCommonSettings_(form, confirmation) {
  form.setCollectEmail(false)            // contact is an optional question instead
      .setRequireLogin(false)            // anyone can submit; no Google sign-in needed
      .setLimitOneResponsePerUser(false)
      .setAllowResponseEdits(false)
      .setShowLinkToRespondAgain(true)
      .setProgressBar(false)
      .setAcceptingResponses(true)
      .setConfirmationMessage(confirmation);
}

function addContactItems_(form, why) {
  form.addTextItem()
    .setTitle('Your name (optional)')
    .setHelpText('Optional, ' + why + '.');
  form.addTextItem()
    .setTitle('Your email (optional)')
    .setHelpText('Optional, ' + why + '.')
    .setValidation(FormApp.createTextValidation()
      .setHelpText('Please enter a valid email address, or leave blank.')
      .requireTextIsEmail()
      .build());
}

function linkToSheet_(form, ss) {
  form.setDestination(FormApp.DestinationType.SPREADSHEET, ss.getId());
  // Forms created programmatically may start unpublished in newer accounts.
  if (typeof form.setPublished === 'function') {
    try { form.setPublished(true); } catch (e) { Logger.log('setPublished: %s', e); }
  }
  return form;
}

function embedUrl_(form) {
  // Same URL Google gives under Send -> < > (Embed HTML), minus the iframe wrapper.
  return form.getPublishedUrl().replace(/\?.*$/, '') + '?embedded=true';
}

function getOrCreateFolder_(name) {
  var it = DriveApp.getFoldersByName(name);
  return it.hasNext() ? it.next() : DriveApp.createFolder(name);
}

function moveToFolder_(file, folder) {
  try { file.moveTo(folder); } catch (e) { folder.addFile(file); }
}
