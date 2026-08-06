class_name SMLExternalLinks
extends RefCounted

const ITCH_URL := "https://suchsoftware.itch.io/such-moon-launch"
const APP_STORE_URL := "https://apps.apple.com/us/app/such-moon-launch/id6767909623"
const PLAY_STORE_URL := (
	"https://play.google.com/store/apps/details?id=com.suchsoftware.suchmoonlaunch"
)
# The umbrella policy at such.software/privacy explicitly defers to this one
# for Moon Launch, so linking the umbrella showed users a document that says
# it does not govern this app.
const PRIVACY_POLICY_URL := "https://such.software/products/such-moon-launch/privacy"


static func store_url(platform_name: String) -> String:
	match platform_name:
		"Android":
			return PLAY_STORE_URL
		"iOS":
			return APP_STORE_URL
		_:
			return ITCH_URL
