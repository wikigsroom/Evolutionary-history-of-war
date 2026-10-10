class_name SessionCredentials
extends Node

var last_error = ""
var directory = "user://"

func installation_key(endpoint: String) -> String:
	var alias = "epoch_online_" + endpoint.sha256_text().left(24)
	if OS.has_feature("android"):
		if not Engine.has_singleton("EpochSecureStore"):
			last_error = "安全存储插件未加载"
			return ""
		var native = Engine.get_singleton("EpochSecureStore")
		var existing = String(native.readSecret(alias))
		if existing == "__ERROR__": last_error = "原联机身份无法解密，请保留应用数据"; return ""
		if existing.length() == 64: return existing
		var generated = Crypto.new().generate_random_bytes(32).hex_encode()
		if not bool(native.writeSecret(alias, generated)):
			last_error = "无法保存联机身份"
			return ""
		return generated
	if OS.get_name() != "Windows":
		last_error = "此构建尚未提供该平台的安全存储"
		return ""
	DirAccess.make_dir_recursive_absolute(directory)
	var helper_path = directory + "credential-helper.ps1"
	var helper = FileAccess.open(helper_path, FileAccess.WRITE)
	if helper == null: return ""
	helper.store_string(FileAccess.get_file_as_string("res://scripts/net/credential_helper.ps1"))
	helper.close()
	var path = directory + alias + ".dpapi"
	if FileAccess.file_exists(path):
		var existing = await _dpapi("unprotect", FileAccess.get_file_as_string(path), helper_path)
		if existing.length() == 64: return existing
		# A broken protected credential must not silently become a new identity.
		last_error = "联机身份无法解密，请使用原 Windows 用户"
		return ""
	var generated = Crypto.new().generate_random_bytes(32).hex_encode()
	var protected = await _dpapi("protect", generated, helper_path)
	if protected.is_empty(): last_error = "Windows 安全存储失败"; return ""
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return ""
	file.store_string(protected)
	file.flush()
	file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK: return ""
	return generated

func _dpapi(mode: String, value: String, helper_path: String) -> String:
	var process = OS.execute_with_pipe("powershell.exe", ["-NoLogo", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path(helper_path), "-Mode", mode], false)
	if process.is_empty(): return ""
	var pipe: FileAccess = process["stdio"]
	pipe.store_line(value)
	pipe.flush()
	var response = PackedByteArray()
	var started = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 10000:
		var data = pipe.get_buffer(4096)
		response.append_array(data)
		if response.size() > 8192: break
		if response.get_string_from_utf8().contains("\n"):
			var line = response.get_string_from_utf8().strip_edges()
			pipe.close()
			return "" if line == "ERROR" else line
		if not OS.is_process_running(int(process["pid"])): break
		await get_tree().process_frame
	pipe.close()
	if OS.is_process_running(int(process["pid"])): OS.kill(int(process["pid"]))
	return ""
