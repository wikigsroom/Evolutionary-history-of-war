class_name AudioSettings
extends RefCounted

static func add_rows(parent: Control, store: EpochStore, audio: BattleAudio) -> void:
	for entry in [["volume","总音量","sound"],["music_volume","配乐","sound"],["sfx_volume","战斗","sword"],["ui_volume","界面","queue"]]:
		var row = HBoxContainer.new(); row.add_theme_constant_override("separation",12); parent.add_child(row)
		var icon = TextureRect.new(); icon.texture=PixelTheme.icon(entry[2]);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.custom_minimum_size=Vector2(26,36);row.add_child(icon)
		var label=PixelTheme.label(entry[1],16);label.custom_minimum_size.x=78;row.add_child(label)
		var slider=HSlider.new();slider.name="Audio_"+entry[0];slider.min_value=0;slider.max_value=1;slider.step=.05;slider.value=store.settings[entry[0]];slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL;slider.custom_minimum_size=Vector2(140,36);slider.tooltip_text=entry[1];row.add_child(slider)
		var percent=PixelTheme.label("%d%%"%roundi(slider.value*100),15,PixelTheme.MUTED);percent.custom_minimum_size.x=48;row.add_child(percent)
		slider.value_changed.connect(func(value):store.settings[entry[0]]=value;percent.text="%d%%"%roundi(value*100);audio.apply_settings();store.save_settings())
		slider.drag_ended.connect(func(_changed):audio.sfx("ui_confirm",.65))
