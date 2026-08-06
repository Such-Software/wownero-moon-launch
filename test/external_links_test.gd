class_name ExternalLinksTest
extends GdUnitTestSuite

const ExternalLinks = preload("res://game/net/ExternalLinks.gd")


func test_store_links_are_canonical_and_platform_specific() -> void:
	assert_str(ExternalLinks.store_url("iOS")).is_equal(
		"https://apps.apple.com/us/app/such-moon-launch/id6767909623"
	)
	assert_str(ExternalLinks.store_url("Android")).is_equal(
		"https://play.google.com/store/apps/details?id=com.suchsoftware.suchmoonlaunch"
	)
	assert_str(ExternalLinks.store_url("Linux")).is_equal(
		"https://suchsoftware.itch.io/such-moon-launch"
	)


func test_privacy_policy_names_this_app_not_the_umbrella_policy() -> void:
	assert_str(ExternalLinks.PRIVACY_POLICY_URL).is_equal(
		"https://such.software/products/such-moon-launch/privacy"
	)
