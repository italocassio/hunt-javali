class_name PowerManager
extends RefCounted
## Battery saver: frame-rate cap and (Web only) menu pixel-ratio cap. Pure rules plus two apply helpers;
## Profile calls apply() at boot and whenever the setting or the touch mode changes. Values: data/game.json "power".

## Same getter as HuntController.JS_DPR_CAP_INSTALL (idempotent through window.__huntDprInstalled).
## window.__huntMaxDpr <= 0 means no cap. HuntController reads the value on entering a hunt and restores it on exit.
const JS_DPR_CAP_INSTALL: String = """
(function () {
	if (window.__huntDprInstalled) { return; }
	var d = Object.getOwnPropertyDescriptor(window, 'devicePixelRatio');
	var real = function () { return (d && d.get) ? d.get.call(window) : (d ? d.value : 1); };
	Object.defineProperty(window, 'devicePixelRatio', {
		configurable: true, enumerable: true,
		get: function () { var m = window.__huntMaxDpr; return (m > 0) ? Math.min(real(), m) : real(); }
	});
	window.__huntDprInstalled = true;
})();
"""


## "auto" follows the touch mode; "on"/"off" are explicit. Anything else counts as "auto".
static func resolve_battery_saver(setting: Variant, is_touch: bool) -> bool:
	match str(setting):
		"on":
			return true
		"off":
			return false
	return is_touch


## Engine.max_fps for the resolved state: the data value when saving battery, 0 (uncapped) otherwise.
static func target_max_fps(saver_on: bool, power: Dictionary) -> int:
	if not saver_on:
		return 0
	return maxi(0, int(power.get("battery_saver_fps", 0)))


## Sets Engine.max_fps from the current setting and touch mode.
static func apply(setting: Variant, is_touch: bool, power: Dictionary) -> void:
	Engine.max_fps = target_max_fps(resolve_battery_saver(setting, is_touch), power)


## Web only: caps the canvas pixel ratio for the menus. A hunt overrides it with its preset and restores it afterwards.
static func apply_menu_pixel_ratio(power: Dictionary) -> void:
	var max_ratio: float = float(power.get("menu_max_pixel_ratio", 0.0))
	if not OS.has_feature("web") or max_ratio <= 0.0:
		return
	JavaScriptBridge.eval(JS_DPR_CAP_INSTALL, true)
	JavaScriptBridge.eval("window.__huntMaxDpr = %s;" % str(max_ratio), true)
