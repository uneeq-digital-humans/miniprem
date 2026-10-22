package mp

// Globals and tiny helpers that the nine scripts/*.sh libs read or assign but whose
// owning (first top-level assignment) file is the installer / miniprem.sh, which do
// not exist yet. Dedupe against inst_*.go / cli_*.go at integration.

// Assigned by install_miniprem.sh / miniprem.sh (PROJECT_ROOT = absolute repo root).
var PROJECT_ROOT string

// Canonical install variables (assigned by the installer's option parsing, by
// seed_apply_to_vars (scripts/seed.sh:150-178) and by prompts).
var (
	INSTALL_TYPE              string
	INSTALL_AS_SERVICE        string
	DEPLOYMENT_TARGET         string
	UNEEQ_REGION              string
	TTS_PROVIDER              string
	AZURE_REGION              string
	AZURE_SPEECH_KEY          string
	ELEVEN_LABS_API_KEY       string
	RIME_API_KEY              string
	RIME_QUAY_PASSWORD        string
	PLATFORM_ADDRESS          string
	PLATFORM_KEY              string
	TENANT_ID                 string
	RENNY_IMAGE               string
	TELEMETRY_CONSENT         string
	STT_PROVIDER              string
	CUSTOM_SERVICES_CHOICE    string
	CUSTOM_SERVICES_FILE_SEED string
	ALLINONE                  string
	NGC_API_KEY               string
	GEMMA_MODEL               string
	GEMMA_BACKEND             string
	KIOSK_STT_PROVIDER        string
	KIOSK_BRAND               string
	RAG_ADMIN_KEY             string
)

// INSTALLATION_MARKER_CREATED: bash holds the strings "true"/"false"; modelled as bool.
// Set by mark_installation_marker_created (install_miniprem.sh:130).
var INSTALLATION_MARKER_CREATED bool

// markInstallationMarkerCreated is owned by the installer (install_miniprem.sh:130);
// prompts.sh calls it. bash: docker/scripts/install_miniprem.sh:130
func markInstallationMarkerCreated() { INSTALLATION_MARKER_CREATED = true }
