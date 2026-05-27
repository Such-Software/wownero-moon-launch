#
# © 2024-present https://github.com/cengiz-pz
#

class_name MediationNetwork extends RefCounted

enum Flag {
	APPLOVIN =		1 << 0,		## AppLovin
	CHARTBOOST =	1 << 1,		## Chartboost
	DTEXCHANGE =	1 << 2,		## DT Exchange (previously Fyber)
	IMOBILE =		1 << 3,		## i-mobile
	INMOBI =		1 << 4,		## InMobi
	IRONSOURCE =	1 << 5,		## ironSource
	LIFTOFF =		1 << 6,		## Liftoff Monetize (previously Vungle)
	LINE =			1 << 7,		## LINE Ads Network
	MAIO =			1 << 8,		## maio
	META =			1 << 9,		## Meta Audience Network (previously Facebook)
	MINTEGRAL =		1 << 10,	## Mintegral
	MOLOCO =		1 << 11,	## Moloco
	MYTARGET =		1 << 12,	## myTarget
	PANGLE =		1 << 13,	## Pangle
	UNITY =			1 << 14,	## Unity Ads
}

const FLAG_PROPERTY: String = "flag"
const TAG_PROPERTY: String = "tag"
const DEPENDENCIES_PROPERTY: String = "dependencies"
const MAVEN_REPO_PROPERTY: String = "maven_repo"
const POD_PROPERTY: String = "pod"
const POD_VERSION_PROPERTY: String = "pod_version"
const SK_AD_NETWORK_IDS_PROPERTY: String = "sk_ad_network_ids"

const GOOGLE_SK_AD_NETWORK_IDS = [ "cstr6suwn9", "4fzdc2evr5", "2fnua5tdw4", "ydx93a7ass", "p78axxw29g", "v72qych5uu", "ludvb6z3bs", "cp8zw746q7", "3sh42y64q3", "c6k4g5qg8m", "s39g8k73mm", "3qy4746246", "f38h382jlk", "hs6bdukanm", "mlmmfzh3r3", "v4nxqhlyqp", "wzmmz9fp6w", "su67r6k2v3", "yclnxrl5pm", "t38b2kh725", "7ug5zh24hu", "gta9lk7p23", "vutu7akeur", "y5ghdn5j9k", "v9wttpbfk9", "n38lu8286q", "47vhws6wlr", "kbd757ywx3", "9t245vhmpl", "a2p9lx4jpn", "22mmun2rn5", "44jx6755aq", "k674qkevps", "4468km3ulz", "2u9pt9hc89", "8s468mfl3y", "klf5c3l5u5", "ppxm28t8ap", "kbmxgpxpgc", "uw77j35x4d", "578prtvx9j", "4dzt52r2t5", "tl55sbb4fm", "c3frkrj4fj", "e5fvkxwrpn", "8c4e2ghe7u", "3rd42ekr43", "97r2b46745", "3qcr597p9d" ]
const SK_AD_NETWORK_ITEM_LIST_FORMAT: String = """
	<key>SKAdNetworkItems</key>
	<array>
%s
	</array>
"""
const SK_AD_NETWORK_ITEM_FORMAT: String = """
		<dict>
			<key>SKAdNetworkIdentifier</key>
			<string>%s.skadnetwork</string>
		</dict>
"""

const MEDIATION_NETWORKS: Dictionary = {
	Flag.APPLOVIN: {
			FLAG_PROPERTY: Flag.APPLOVIN,
			TAG_PROPERTY: "applovin",
			DEPENDENCIES_PROPERTY: [ "com.google.ads.mediation:applovin:13.4.0.1" ],
			MAVEN_REPO_PROPERTY: "",
			POD_PROPERTY: "GoogleMobileAdsMediationAppLovin",
			POD_VERSION_PROPERTY: "13.4.0.0",
			SK_AD_NETWORK_IDS_PROPERTY: [ "22mmun2rn5", "238da6jt44", "24t9a8vw3c", "24zw6aqk47", "252b5q8x7y", "275upjj5gd", "294l99pt4k", "2fnua5tdw4", "2u9pt9hc89", "32z4fx6l9h", "3l6bd9hu43", "3qcr597p9d", "3qy4746246", "3rd42ekr43", "3sh42y64q3", "424m5254lk", "4468km3ulz", "44jx6755aq", "44n7hlldy6", "47vhws6wlr", "488r3q3dtq", "4dzt52r2t5", "4fzdc2evr5", "4mn522wn87", "4pfyvq9l8r", "4w7y6s5ca2", "523jb4fst2", "52fl2v3hgk", "54nzkqm89y", "578prtvx9j", "5a6flpkh64", "5l3tpt7t6e", "5lm9lj6jb7", "5tjdwbrq8w", "6964rsfnh4", "6g9af3uyq4", "6p4ks3rnbw", "6v7lgmsu45", "6xzpu9s2p8", "737z793b9f", "74b6s63p6l", "79pbpufp6p", "7fmhfwg9en", "7rz58n8ntl", "7ug5zh24hu", "84993kbrcf", "89z7zv988g", "8c4e2ghe7u", "8m87ys6875", "8r8llnkz5a", "8s468mfl3y", "97r2b46745", "9b89h5y424", "9nlqeag3gk", "9rd848q2bz", "9t245vhmpl", "9vvzujtq5s", "9yg77x724h", "a2p9lx4jpn", "a7xqa6mtl2", "a8cz6cu7e5", "av6w8kgt66", "b9bk5wbcq9", "bxvub5ada5", "c3frkrj4fj", "c6k4g5qg8m", "cg4yq2srnc", "cj5566h2ga", "cp8zw746q7", "cs644xg564", "cstr6suwn9", "dbu4b84rxf", "dkc879ngq3", "dzg6xy7pwj", "e5fvkxwrpn", "ecpz2srf59", "eh6m2bh4zr", "ejvt5qm6ak", "f38h382jlk", "f73kdq92p3", "f7s53z58qe", "feyaarzu9v", "g28c52eehv", "g2y4y55b64", "g6gcrrvk4p", "ggvn48r87g", "glqzh8vgby", "gta8lk7p23", "gta9lk7p23", "hb56zgv37p", "hdw39hrw9y", "hs6bdukanm", "k674qkevps", "kbd757ywx3", "kbmxgpxpgc", "klf5c3l5u5", "krvm3zuq6h", "lr83yxwka7", "ludvb6z3bs", "m297p6643m", "m5mvw97r93", "m8dbw4sv7c", "mj797d8u6f", "mlmmfzh3r3", "mls7yz5dvl", "mp6xlyr22a", "mqn7fxpca7", "mtkv5xtk9e", "n38lu8286q", "n66cz3y3bx", "n6fk4nfna4", "n9x2a789qt", "nzq8sh4pbs", "p78axxw29g", "ppxm28t8ap", "prcb7njmu6", "pwa73g5rt2", "pwdxu55a5a", "qqp299437r", "qu637u8glc", "r45fhb6rf7", "rvh3l7un93", "rx5hdcabgc", "s39g8k73mm", "s69wq72ugq", "su67r6k2v3", "t38b2kh725", "tl55sbb4fm", "u679fj5vs4", "uw77j35x4d", "v4nxqhlyqp", "v72qych5uu", "v79kvwwj4g", "v9wttpbfk9", "vcra2ehyfk", "vhf287vqwu", "vutu7akeur", "w9q455wk68", "wg4vff78zm", "wzmmz9fp6w", "x44k69ngh6", "x5l83yy675", "x8jxxk4ff5", "x8uqf25wch", "xga6mpmplv", "xy9t38ct57", "y45688jllp", "y5ghdn5j9k", "yclnxrl5pm", "ydx93a7ass", "zmvfpc5aq8", "zq492l623r" ]
		},
	Flag.CHARTBOOST: {
			FLAG_PROPERTY: Flag.CHARTBOOST,
			TAG_PROPERTY: "chartboost",
			DEPENDENCIES_PROPERTY: [ "com.google.ads.mediation:chartboost:9.10.0.1" ],
			MAVEN_REPO_PROPERTY: "https://cboost.jfrog.io/artifactory/chartboost-ads/",
			POD_PROPERTY: "GoogleMobileAdsMediationChartboost",
			POD_VERSION_PROPERTY: "9.10.0.0",
			SK_AD_NETWORK_IDS_PROPERTY: [ "f38h382jlk" ]
		},
	Flag.DTEXCHANGE: {
			FLAG_PROPERTY: Flag.DTEXCHANGE,
			TAG_PROPERTY: "dtexchange",
			DEPENDENCIES_PROPERTY: [ "com.google.ads.mediation:fyber:8.4.0.0" ],
			MAVEN_REPO_PROPERTY: "",
			POD_PROPERTY: "GoogleMobileAdsMediationFyber",
			POD_VERSION_PROPERTY: "8.4.0.0",
			SK_AD_NETWORK_IDS_PROPERTY: [ "ydx93a7ass", "t6d3zquu66", "4fzdc2evr5", "a8cz6cu7e5", "9nlqeag3gk", "a2p9lx4jpn", "k674qkevps", "c3frkrj4fj", "n6fk4nfna4", "mtkv5xtk9e", "p78axxw29g", "n9x2a789qt", "kbmxgpxpgc", "s39g8k73mm", "krvm3zuq6h", "294l99pt4k", "3rd42ekr43", "ggvn48r87g", "4pfyvq9l8r", "cg4yq2srnc", "5a6flpkh64", "v72qych5uu", "x8uqf25wch", "c6k4g5qg8m", "wg4vff78zm", "rx5hdcabgc", "32z4fx6l9h", "3qy4746246", "252b5q8x7y", "f38h382jlk", "24t9a8vw3c", "hs6bdukanm", "9rd848q2bz", "prcb7njmu6", "m8dbw4sv7c", "9g2aggbj52", "wzmmz9fp6w", "yclnxrl5pm", "t38b2kh725", "7ug5zh24hu", "5lm9lj6jb7", "ejvt5qm6ak", "7rz58n8ntl", "kbd757ywx3", "9t245vhmpl", "44jx6755aq", "tl55sbb4fm", "8s468mfl3y", "4468km3ulz", "2u9pt9hc89", "av6w8kgt66", "klf5c3l5u5", "hdw39hrw9y", "y45688jllp", "dzg6xy7pwj", "3sh42y64q3", "ppxm28t8ap", "f73kdq92p3", "5l3tpt7t6e", "uw77j35x4d", "mlmmfzh3r3", "6g9af3uyq4", "su67r6k2v3", "g28c52eehv", "pwa73g5rt2", "zq492l623r", "22mmun2rn5", "8r8llnkz5a", "47vhws6wlr", "5tjdwbrq8w", "h65wbv5k3f", "2fnua5tdw4", "7fmhfwg9en", "tvvz7th9br", "x44k69ngh6", "vhf287vqwu", "4dzt52r2t5", "x8yj322td6", "tskbem2b5g", "cp8zw746q7", "cj5566h2ga", "578prtvx9j", "e5fvkxwrpn", "r45fhb6rf7", "mqn7fxpca7", "g6gcrrvk4p", "xga6mpmplv", "qu637u8glc", "w9q455wk68", "275upjj5gd", "97r2b46745", "cstr6suwn9" ]
		},
	Flag.IMOBILE: {
			FLAG_PROPERTY: Flag.IMOBILE,
			TAG_PROPERTY: "imobile",
			DEPENDENCIES_PROPERTY: [ "com.google.ads.mediation:imobile:2.3.2.1" ],
			MAVEN_REPO_PROPERTY: "https://imobile.github.io/adnw-sdk-android",
			POD_PROPERTY: "GoogleMobileAdsMediationIMobile",
			POD_VERSION_PROPERTY: "2.3.4.2",
			SK_AD_NETWORK_IDS_PROPERTY: [ "v4nxqhlyqp" ]
		},
	Flag.INMOBI: {
			FLAG_PROPERTY: Flag.INMOBI,
			TAG_PROPERTY: "inmobi",
			DEPENDENCIES_PROPERTY: [ "com.google.ads.mediation:inmobi:10.8.8.1" ],
			MAVEN_REPO_PROPERTY: "",
			POD_PROPERTY: "GoogleMobileAdsMediationInMobi",
			POD_VERSION_PROPERTY: "10.8.8.0",
			SK_AD_NETWORK_IDS_PROPERTY: [ "uw77j35x4d", "7ug5zh24hu", "hs6bdukanm", "4fzdc2evr5", "ggvn48r87g", "5lm9lj6jb7", "9rd848q2bz", "c6k4g5qg8m", "wzmmz9fp6w", "3sh42y64q3", "yclnxrl5pm", "kbd757ywx3", "f73kdq92p3", "ydx93a7ass", "w9q455wk68", "prcb7njmu6", "wg4vff78zm", "mlmmfzh3r3", "tl55sbb4fm", "4pfyvq9l8r", "t38b2kh725", "5l3tpt7t6e", "7rz58n8ntl", "klf5c3l5u5", "cg4yq2srnc", "av6w8kgt66", "9t245vhmpl", "v72qych5uu", "2u9pt9hc89", "44jx6755aq", "8s468mfl3y", "p78axxw29g", "ppxm28t8ap", "424m5254lk", "5a6flpkh64", "pwa73g5rt2", "e5fvkxwrpn", "9nlqeag3gk", "k674qkevps", "cj5566h2ga", "mtkv5xtk9e", "3rd42ekr43", "g28c52eehv", "2fnua5tdw4", "4468km3ulz", "97r2b46745", "glqzh8vgby", "3qcr597p9d", "578prtvx9j", "n6fk4nfna4", "b9bk5wbcq9", "kbmxgpxpgc", "294l99pt4k", "523jb4fst2", "mls7yz5dvl", "74b6s63p6l", "22mmun2rn5", "52fl2v3hgk", "6g9af3uyq4", "x5l83yy675", "mqn7fxpca7", "g6gcrrvk4p", "r45fhb6rf7", "c3frkrj4fj", "ejvt5qm6ak", "f38h382jlk", "488r3q3dtq", "55644vm79v", "5tjdwbrq8w", "nzq8sh4pbs", "m8dbw4sv7c", "7fmhfwg9en", "6v7lgmsu45", "s39g8k73mm", "6yxyv74ff7", "55y65gfgn7", "mqn7fxpca7", "qqp299437r", "32z4fx6l9h", "feyaarzu9v", "cp8zw746q7", "252b5q8x7y", "qu637u8glc", "vhf287vqwu", "a8cz6cu7e5", "cwn433xbcr", "fq6vru337s", "87u5trcl3r", "mj797d8u6f", "dbu4b84rxf", "238da6jt44", "4dzt52r2t5", "a2p9lx4jpn", "t6d3zquu66", "zq492l623r", "cstr6suwn9", "xga6mpmplv", "tmhh9296z4", "6xzpu9s2p8", "ludvb6z3bs", "v9wttpbfk9", "n38lu8286q", "fz2k2k5tej", "g2y4y55b64", "su67r6k2v3", "v79kvwwj4g", "275upjj5gd", "24zw6aqk47", "44n7hlldy6", "ecpz2srf59", "bvpn9ufa9b", "gta9lk7p23" ]
		},
	Flag.IRONSOURCE: {
			FLAG_PROPERTY: Flag.IRONSOURCE,
			TAG_PROPERTY: "ironsource",
			DEPENDENCIES_PROPERTY: [ "com.google.ads.mediation:ironsource:9.0.0.1" ],
			MAVEN_REPO_PROPERTY: "",
			POD_PROPERTY: "GoogleMobileAdsMediationIronSource",
			POD_VERSION_PROPERTY: "9.0.0.0.0",
			SK_AD_NETWORK_IDS_PROPERTY: [ "su67r6k2v3" ]
		},
	Flag.LIFTOFF: {
			FLAG_PROPERTY: Flag.LIFTOFF,
			TAG_PROPERTY: "liftoff",
			DEPENDENCIES_PROPERTY: [ "com.google.ads.mediation:vungle:7.6.0.0" ],
			MAVEN_REPO_PROPERTY: "",
			POD_PROPERTY: "GoogleMobileAdsMediationVungle",
			POD_VERSION_PROPERTY: "7.6.1.0",
			SK_AD_NETWORK_IDS_PROPERTY: [ "22mmun2rn5", "238da6jt44", "24t9a8vw3c", "24zw6aqk47", "275upjj5gd", "294l99pt4k", "2fnua5tdw4", "2u9pt9hc89", "32z4fx6l9h", "3l6bd9hu43", "3qcr597p9d", "3qy4746246", "3rd42ekr43", "3sh42y64q3", "424m5254lk", "4468km3ulz", "44jx6755aq", "44n7hlldy6", "488r3q3dtq", "4dzt52r2t5", "4fzdc2evr5", "4pfyvq9l8r", "4w7y6s5ca2", "523jb4fst2", "52fl2v3hgk", "54nzkqm89y", "578prtvx9j", "5a6flpkh64", "5l3tpt7t6e", "5lm9lj6jb7", "5tjdwbrq8w", "6964rsfnh4", "6g9af3uyq4", "6lz2ygh3q6", "6p4ks3rnbw", "6rd35atwn8", "6v7lgmsu45", "6xzpu9s2p8", "6yxyv74ff7", "737z793b9f", "74b6s63p6l", "79pbpufp6p", "7fmhfwg9en", "7rz58n8ntl", "7ug5zh24hu", "84993kbrcf", "87u5trcl3r", "89z7zv988g", "8m87ys6875", "8s468mfl3y", "97r2b46745", "9b89h5y424", "9nlqeag3gk", "9rd848q2bz", "9t245vhmpl", "9vvzujtq5s", "a2p9lx4jpn", "a7xqa6mtl2", "a8cz6cu7e5", "apzhy3va96", "av6w8kgt66", "b9bk5wbcq9", "bvpn9ufa9b", "bxvub5ada5", "c3frkrj4fj", "c6k4g5qg8m", "cg4yq2srnc", "cj5566h2ga", "cp8zw746q7", "cs644xg564", "cstr6suwn9", "cwn433xbcr", "dbu4b84rxf", "dkc879ngq3", "dzg6xy7pwj", "e5fvkxwrpn", "ecpz2srf59", "ejvt5qm6ak", "f2zub97jtl", "f38h382jlk", "f73kdq92p3", "f7s53z58qe", "feyaarzu9v", "fq6vru337s", "fz2k2k5tej", "g28c52eehv", "g2y4y55b64", "g6gcrrvk4p", "ggvn48r87g", "glqzh8vgby", "gta9lk7p23", "hb56zgv37p", "hdw39hrw9y", "hs6bdukanm", "k674qkevps", "k6y4y55b64", "kbd757ywx3", "kbmxgpxpgc", "klf5c3l5u5", "krvm3zuq6h", "ln5gz23vtd", "lr83yxwka7", "ludvb6z3bs", "m297p6643m", "m2jqnlggk3", "m5mvw97r93", "m8dbw4sv7c", "mj797d8u6f", "mlmmfzh3r3", "mls7yz5dvl", "mp6xlyr22a", "mqn7fxpca7", "mtkv5xtk9e", "n38lu8286q", "n6fk4nfna4", "n9x2a789qt", "ns5j362hk7", "p78axxw29g", "pg7ctvrt6f", "ppxm28t8ap", "prcb7njmu6", "pwa73g5rt2", "pwdxu55a5a", "qqp299437r", "qu637u8glc", "qwpu75vrh2", "r45fhb6rf7", "raa6f494kr", "rvh3l7un93", "rx5hdcabgc", "s39g8k73mm", "sczv5946wb", "su67r6k2v3", "t38b2kh725", "t6d3zquu66", "thzdn4h5nc", "tl55sbb4fm", "tmhh9296z4", "u679fj5vs4", "uw77j35x4d", "v72qych5uu", "v79kvwwj4g", "v9wttpbfk9", "vcra2ehyfk", "vhf287vqwu", "w9q455wk68", "wg4vff78zm", "wzmmz9fp6w", "x44k69ngh6", "x5l83yy675", "x8uqf25wch", "xga6mpmplv", "xy9t38ct57", "y45688jllp", "y5ghdn5j9k", "yclnxrl5pm", "ydx93a7ass", "z959bm4gru", "zmvfpc5aq8", "zq492l623r" ]
		},
	Flag.LINE: {
			FLAG_PROPERTY: Flag.LINE,
			TAG_PROPERTY: "line",
			DEPENDENCIES_PROPERTY: [ "com.google.ads.mediation:line:2.9.20250924.1" ],
			MAVEN_REPO_PROPERTY: "",
			POD_PROPERTY: "GoogleMobileAdsMediationLine",
			POD_VERSION_PROPERTY: "2.9.20250930.0",
			SK_AD_NETWORK_IDS_PROPERTY: [ "vutu7akeur", "eh6m2bh4zr", "cstr6suwn9", "578prtvx9j", "9t245vhmpl", "v72qych5uu", "x8uqf25wch", "7ug5zh24hu", "hs6bdukanm", "dbu4b84rxf", "8c4e2ghe7u" ]
		},
	Flag.MAIO: {
			FLAG_PROPERTY: Flag.MAIO,
			TAG_PROPERTY: "maio",
			DEPENDENCIES_PROPERTY: [ "com.google.ads.mediation:maio:2.0.6.0" ],
			MAVEN_REPO_PROPERTY: "https://imobile-maio.github.io/maven",
			POD_PROPERTY: "GoogleMobileAdsMediationMaio",
			POD_VERSION_PROPERTY: "2.2.0.0",
			SK_AD_NETWORK_IDS_PROPERTY: [ "v4nxqhlyqp" ]
		},
	Flag.META: {
			FLAG_PROPERTY: Flag.META,
			TAG_PROPERTY: "meta",
			DEPENDENCIES_PROPERTY: [ "com.google.ads.mediation:facebook:6.20.0.2" ],
			MAVEN_REPO_PROPERTY: "",
			POD_PROPERTY: "GoogleMobileAdsMediationFacebook",
			POD_VERSION_PROPERTY: "6.20.1.0",
			SK_AD_NETWORK_IDS_PROPERTY: [ "v9wttpbfk9", "n38lu8286q" ]
		},
	Flag.MINTEGRAL: {
			FLAG_PROPERTY: Flag.MINTEGRAL,
			TAG_PROPERTY: "mintegral",
			DEPENDENCIES_PROPERTY: [ "com.google.ads.mediation:mintegral:16.9.91.2" ],
			MAVEN_REPO_PROPERTY: "https://dl-maven-android.mintegral.com/repository/mbridge_android_sdk_oversea",
			POD_PROPERTY: "GoogleMobileAdsMediationMintegral",
			POD_VERSION_PROPERTY: "7.7.9.1",
			SK_AD_NETWORK_IDS_PROPERTY: [ "kbd757ywx3" ]
		},
	Flag.MOLOCO: {
			FLAG_PROPERTY: Flag.MOLOCO,
			TAG_PROPERTY: "moloco",
			DEPENDENCIES_PROPERTY: [ "com.google.ads.mediation:moloco:4.2.0.0" ],
			MAVEN_REPO_PROPERTY: "",
			POD_PROPERTY: "GoogleMobileAdsMediationMoloco",
			POD_VERSION_PROPERTY: "3.13.0.0",
			SK_AD_NETWORK_IDS_PROPERTY: [ "9t245vhmpl" ]
		},
	Flag.MYTARGET: {
			FLAG_PROPERTY: Flag.MYTARGET,
			TAG_PROPERTY: "mytarget",
			DEPENDENCIES_PROPERTY: [ "com.google.ads.mediation:mytarget:5.27.3.0" ],
			MAVEN_REPO_PROPERTY: "",
			POD_PROPERTY: "GoogleMobileAdsMediationMyTarget",
			POD_VERSION_PROPERTY: "5.36.0.0",
			SK_AD_NETWORK_IDS_PROPERTY: [ "n9x2a789qt", "r26jy69rpl" ]
		},
	Flag.PANGLE: {
			FLAG_PROPERTY: Flag.PANGLE,
			TAG_PROPERTY: "pangle",
			DEPENDENCIES_PROPERTY: [ "com.google.ads.mediation:pangle:7.6.0.5.0" ],
			MAVEN_REPO_PROPERTY: "https://artifact.bytedance.com/repository/pangle/",
			POD_PROPERTY: "GoogleMobileAdsMediationPangle",
			POD_VERSION_PROPERTY: "7.7.0.4.0",
			SK_AD_NETWORK_IDS_PROPERTY: [ "22mmun2rn5" ]
		},
	Flag.UNITY: {
			FLAG_PROPERTY: Flag.UNITY,
			TAG_PROPERTY: "unity",
			DEPENDENCIES_PROPERTY: [ "com.unity3d.ads:unity-ads:4.16.2", "com.google.ads.mediation:unity:4.16.3.0" ],
			MAVEN_REPO_PROPERTY: "",
			POD_PROPERTY: "GoogleMobileAdsMediationUnity",
			POD_VERSION_PROPERTY: "4.16.2.0",
			SK_AD_NETWORK_IDS_PROPERTY: [ "9nlqeag3gk", "hs6bdukanm", "9rd848q2bz", "22mmun2rn5", "f73kdq92p3", "tl55sbb4fm", "prcb7njmu6", "n9x2a789qt", "97r2b46745", "zmvfpc5aq8", "av6w8kgt66", "uw77j35x4d", "pwa73g5rt2", "e5fvkxwrpn", "klf5c3l5u5", "xga6mpmplv", "wg4vff78zm", "lr83yxwka7", "5tjdwbrq8w", "7ug5zh24hu", "glqzh8vgby", "feyaarzu9v", "6yxyv74ff7", "mqn7fxpca7", "vhf287vqwu", "g6gcrrvk4p", "v79kvwwj4g", "32z4fx6l9h", "2fnua5tdw4", "a8cz6cu7e5", "v72qych5uu", "a2p9lx4jpn", "5f5u5tfb26", "4fzdc2evr5", "5lm9lj6jb7", "4w7y6s5ca2", "3sh42y64q3", "4468km3ulz", "mj797d8u6f", "488r3q3dtq", "mlmmfzh3r3", "9t245vhmpl", "x44k69ngh6", "kbd757ywx3", "4dzt52r2t5", "k674qkevps", "294l99pt4k", "m8dbw4sv7c", "2u9pt9hc89", "p78axxw29g", "424m5254lk", "238da6jt44", "ydx93a7ass", "s39g8k73mm", "v9wttpbfk9", "44jx6755aq", "578prtvx9j", "yclnxrl5pm", "k6y4y55b64", "5a6flpkh64", "3rd42ekr43", "f38h382jlk", "cstr6suwn9", "ppxm28t8ap", "f7s53z58qe", "zq492l623r", "t38b2kh725", "mp6xlyr22a", "3qy4746246", "5l3tpt7t6e", "c6k4g5qg8m", "w9q455wk68", "4pfyvq9l8r", "wzmmz9fp6w", "8s468mfl3y" ]
		}
}

const MEDIATION_NETWORK_TAGS: Dictionary = {
	"applovin": Flag.APPLOVIN,
	"chartboost": Flag.CHARTBOOST,
	"dtexchange": Flag.DTEXCHANGE,
	"imobile": Flag.IMOBILE,
	"inmobi": Flag.INMOBI,
	"ironsource": Flag.IRONSOURCE,
	"liftoff": Flag.LIFTOFF,
	"line": Flag.LINE,
	"maio": Flag.MAIO,
	"meta": Flag.META,
	"mintegral": Flag.MINTEGRAL,
	"moloco": Flag.MOLOCO,
	"mytarget": Flag.MYTARGET,
	"pangle": Flag.PANGLE,
	"unity": Flag.UNITY
}

var flag: Flag
var tag: String
var android_dependencies: Array
var android_custom_maven_repo: String
var ios_pod: String
var ios_pod_version: String
var sk_ad_network_ids: PackedStringArray


func _init(a_data: Dictionary) -> void:
	flag = a_data[FLAG_PROPERTY]
	tag = a_data[TAG_PROPERTY]
	android_dependencies = a_data[DEPENDENCIES_PROPERTY]
	android_custom_maven_repo = a_data[MAVEN_REPO_PROPERTY]
	ios_pod = a_data[POD_PROPERTY]
	ios_pod_version = a_data[POD_VERSION_PROPERTY]
	sk_ad_network_ids = a_data[SK_AD_NETWORK_IDS_PROPERTY]


func get_pod_string() -> String:
	return "pod '%s', '%s'" % [ios_pod, ios_pod_version]


static func is_flag_enabled(a_value: int, a_flag: Flag) -> bool:
	return a_value & a_flag


static func is_valid_tag(a_tag: String) -> bool:
	return MEDIATION_NETWORK_TAGS.has(a_tag)


static func get_by_flag(a_flag: Flag) -> MediationNetwork:
	return MediationNetwork.new(MEDIATION_NETWORKS[a_flag])


static func get_by_tag(a_tag: String) -> MediationNetwork:
	return get_by_flag(MEDIATION_NETWORK_TAGS[a_tag])


static func get_all_enabled(a_value: int) -> Array[MediationNetwork]:
	var __enabled_networks: Array[MediationNetwork] = []

	for __flag in Flag.values():
		if is_flag_enabled(a_value, __flag):
			__enabled_networks.append(get_by_flag(__flag))

	return __enabled_networks


static func get_all_enabled_tags(a_value: int) -> Array[String]:
	var __enabled_network_tags: Array[String] = []

	for __flag in Flag.values():
		if is_flag_enabled(a_value, __flag):
			var __network: MediationNetwork = get_by_flag(__flag)
			__enabled_network_tags.append(__network.tag)

	return __enabled_network_tags


static func generate_sk_ad_network_plist(a_networks: Array[MediationNetwork]) -> String:
	var __sk_ad_ids_plist_content: String

	var __unique_sk_network_ad_ids: Dictionary = {}

	# Add Google-required SK Ad Network IDs
	for __network_id in GOOGLE_SK_AD_NETWORK_IDS:
		if not __unique_sk_network_ad_ids.has(__network_id):
			__unique_sk_network_ad_ids.set(__network_id, null)

	# Add SK Ad Network IDs required by other networks
	for __network in a_networks:
		for __network_id in __network.sk_ad_network_ids:
			if not __unique_sk_network_ad_ids.has(__network_id):
				__unique_sk_network_ad_ids.set(__network_id, null)

	for __network_id in __unique_sk_network_ad_ids.keys():
		__sk_ad_ids_plist_content += SK_AD_NETWORK_ITEM_FORMAT % __network_id

	return SK_AD_NETWORK_ITEM_LIST_FORMAT % __sk_ad_ids_plist_content


static func generate_pod_list(a_networks: Array[MediationNetwork]) -> String:
	var __pod_list_content: String = ""

	for __network in a_networks:
		__pod_list_content += "  " + __network.get_pod_string() + "\n"

	return __pod_list_content


static func generate_tag_list(a_networks: Array[MediationNetwork]) -> String:
	var __enabled_network_tags: PackedStringArray = []

	for __network in a_networks:
		__enabled_network_tags.append(__network.tag)

	return ",".join(__enabled_network_tags)
