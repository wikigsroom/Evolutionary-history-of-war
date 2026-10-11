extends SceneTree

var first: EpochNetClient
var second: EpochNetClient
var checks = []
var directory = ""

func _initialize() -> void:
	directory = OS.get_environment("EPOCH_QA_OUTPUT").trim_suffix("/") + "/"
	call_deferred("run")

func check(value: bool, title: String) -> void:
	checks.append({"name":title,"passed":value})
	print("PUBLIC_RECOVERY_CHECK ", value, " ", title)
	if not value: push_error(title)

func wait_for(predicate: Callable, seconds = 50.0) -> bool:
	var until = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		if predicate.call(): return true
		await process_frame
	return false

func marker(name_: String) -> void:
	var file = FileAccess.open(directory + name_ + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"match_id":first.match_id,"player_id":first.player_id,"tick":first.battle_state.tick})); file.close()

func ready() -> bool:
	return first.battle_state != null and second.battle_state != null and first.battle_state.connected and second.battle_state.connected and not first.syncing and not second.syncing and not first.battle_state.paused and not second.battle_state.paused

func run() -> void:
	first = EpochNetClient.new(); first.session_directory = "user://qa-public-recovery-a-%d/" % Time.get_ticks_usec(); root.add_child(first)
	second = EpochNetClient.new(); second.session_directory = "user://qa-public-recovery-b-%d/" % Time.get_ticks_usec(); root.add_child(second)
	check(await first.connect_service() and await second.connect_service(), "Exported clients authenticate to the public TLS endpoint")
	await first.join_code("%06d" % (randi() % 1000000))
	await second.join_code(first.activity["room"]["code"])
	await first.refresh_activity()
	await first.room_ready(true); await second.refresh_activity(); await second.room_ready(true)
	check(await wait_for(ready), "Both exported clients enter the public authoritative match")
	first.battle_state.act({"type":"train","unitId":"U11"})
	check(await wait_for(func():return first.next_seq == 2 and first.pending.is_empty()), "Recruitment is committed before fault injection")
	var original = first.match_id
	var epoch = first.connection_epoch
	var tick = first.battle_state.tick
	marker("gateway-fault-ready")
	check(await wait_for(func():return FileAccess.file_exists(directory + "gateway-fault-done")), "Supervisor kills only the game gateway process")
	check(await wait_for(func():return ready() and first.connection_epoch > epoch), "Native clients automatically reconnect after systemd process-crash recovery")
	check(first.match_id == original and first.next_seq == 2 and first.pending.is_empty(), "Original seat and committed cursor survive the server crash")
	check(first.battle_state.tick >= tick, "Acknowledged battle state never rolls back")
	var database_tick = first.battle_state.last_server_tick
	marker("database-fault-ready")
	check(await wait_for(func():return FileAccess.file_exists(directory + "database-fault-done")), "Only the game's database connections are interrupted")
	# A previously connected projection can still be visible in the fault frame.
	# Wait through interruption detection, then require new post-fault simulation
	# progress from both subscribers before submitting one subsequent action.
	await create_timer(2.0).timeout
	check(await wait_for(func():return ready() and first.battle_state.last_server_tick > database_tick + 30 and second.battle_state.last_server_tick > database_tick + 30), "Native clients recover a current projection after database interruption")
	var outcome = first.battle_state.act({"type":"train","unitId":"U11"})
	print("PUBLIC_RECOVERY_POST_FAULT ", JSON.stringify({"accepted_locally":outcome.get("ok",false),"next_seq":first.next_seq,"pending":first.pending.size(),"tick":first.battle_state.last_server_tick,"finished":first.finished,"winner":first.battle_state.winner}))
	check(outcome.get("ok",false) and await wait_for(func():return first.next_seq == 3 and first.pending.is_empty()), "Another action commits after recovery without replaying the original action")
	await first.surrender()
	check(await wait_for(func():return first.finished and second.finished), "Both clients finish with one authoritative result after both faults")
	await first.acknowledge_result(); await second.acknowledge_result()
	var file = FileAccess.open(directory + "public-native-recovery.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"endpoint":EpochNetClient.DEFAULT_ENDPOINT,"checks":checks},"  ")); file.close()
	quit(0 if checks.all(func(row):return row["passed"]) else 1)
