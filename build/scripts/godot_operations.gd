#!/usr/bin/env -S godot --headless --script
extends SceneTree

var debug_mode = false
var backup_dir = ""
var _nodes_collector = []
var _collect_recursive = true

func _init():
    var args = OS.get_cmdline_args()
    debug_mode = "--debug-godot" in args
    
    var script_index = args.find("--script")
    if script_index == -1:
        printerr("[ERROR] Could not find --script argument")
        quit(1)
    
    var operation_index = script_index + 2
    var params_index = script_index + 3
    
    if args.size() <= params_index:
        printerr("[ERROR] Not enough command-line arguments")
        quit(1)
    
    var operation = args[operation_index]
    var params_json = args[params_index]
    
    var json = JSON.new()
    var error = json.parse(params_json)
    var params = null
    
    if error == OK:
        params = json.get_data()
    else:
        printerr("[ERROR] Failed to parse JSON: " + json.get_error_message())
        quit(1)
    
    log_debug("Executing operation: " + operation)
    
    match operation:
        "create_scene": create_scene(params)
        "add_node": add_node(params)
        "add_node_with_script": add_node_with_script(params)
        "modify_node_property": modify_node_property(params)
        "remove_node": remove_node(params)
        "duplicate_node": duplicate_node(params)
        "list_nodes": list_nodes(params)
        "batch_operations": batch_operations(params)
        "load_sprite": load_sprite(params)
        "save_scene": save_scene(params)
        "get_uid": get_uid(params)
        "resave_resources": resave_resources(params)
        "get_node_info": get_node_info(params)
        "get_node_property": get_node_property(params)
        "set_node_property": set_node_property(params)
        "get_node_transform": get_node_transform(params)
        "set_node_position": set_node_position(params)
        "set_node_rotation": set_node_rotation(params)
        "set_node_scale": set_node_scale(params)
        "get_parent_path": get_parent_path(params)
        "get_children": get_children(params)
        "has_child": has_child(params)
        "connect_signal": connect_signal(params)
        "disconnect_signal": disconnect_signal(params)
        "emit_node_signal": emit_node_signal(params)
        "get_groups": get_groups(params)
        "add_to_group": add_to_group(params)
        "remove_from_group": remove_from_group(params)
        "call_group_method": call_group_method(params)
        _:
            printerr("[ERROR] Unknown operation: " + operation)
            quit(1)
    
    quit()

func log_debug(msg: String):
    if debug_mode:
        print("[DEBUG] " + msg)

func log_info(msg: String):
    print("[INFO] " + msg)

func _normalize_path(path: String) -> String:
    if not path.begins_with("res://"):
        path = "res://" + path
    return path

func _to_absolute(path: String) -> String:
    return ProjectSettings.globalize_path(_normalize_path(path))

func _ensure_dir(dir_path: String) -> bool:
    var abs_path = _to_absolute(dir_path)
    if DirAccess.dir_exists_absolute(abs_path):
        return true
    var dir = DirAccess.open("res://")
    if dir == null:
        return false
    var rel_path = dir_path.replace("res://", "")
    return dir.make_dir_recursive(rel_path) == OK

func _ensure_dir_from_absolute(abs_path: String) -> bool:
    if DirAccess.dir_exists_absolute(abs_path):
        return true
    return DirAccess.make_dir_recursive_absolute(abs_path) == OK

func _delete_dir_recursive(abs_path: String) -> void:
    var dir = DirAccess.open(abs_path)
    if dir == null:
        return
    dir.list_dir_begin()
    var name = dir.get_next()
    while name != "":
        if dir.current_is_dir():
            _delete_dir_recursive(abs_path + "/" + name)
        else:
            dir.remove(name)
        name = dir.get_next()
    dir.list_dir_end()
    dir.remove(abs_path)

func validate_node_type(type_name: String) -> bool:
    if ClassDB.class_exists(type_name) and ClassDB.can_instantiate(type_name):
        return true
    if ResourceLoader.exists(type_name, "Script"):
        return true
    var global_classes = ProjectSettings.get_global_class_list()
    for gc in global_classes:
        if gc["class"] == type_name:
            return true
    return false

func instantiate_node(type_name: String):
    if not validate_node_type(type_name):
        printerr("[ERROR] Invalid or uninstantiable node type: " + type_name)
        return null
    
    if ClassDB.can_instantiate(type_name):
        return ClassDB.instantiate(type_name)
    
    var script_path = type_name
    if not ResourceLoader.exists(type_name, "Script"):
        var global_classes = ProjectSettings.get_global_class_list()
        for gc in global_classes:
            if gc["class"] == type_name:
                script_path = gc["path"]
                break
    
    var script = load(script_path)
    if script is GDScript:
        return script.new()
    return null

func _find_node_by_path(root: Node, path: String) -> Node:
    if path == "root" or path == "":
        return root
    var clean_path = path
    if clean_path.begins_with("root/"):
        clean_path = clean_path.substr(5)
    if clean_path.begins_with("/"):
        clean_path = clean_path.substr(1)
    return root.get_node_or_null(clean_path)

func _create_backup(scene_path: String) -> String:
    var abs_path = _to_absolute(scene_path)
    var backup_name = scene_path.md5_text() + "_" + str(Time.get_unix_time_from_system())
    var backup_path = "res://mcp_backups/" + backup_name + ".tscn"
    var abs_backup_path = _to_absolute(backup_path)
    
    # Create backup directory
    var dir = DirAccess.open("res://")
    if dir == null:
        printerr("[ERROR] Cannot open res://")
        return ""
    if not dir.dir_exists("mcp_backups"):
        if dir.make_dir("mcp_backups") != OK:
            printerr("[ERROR] Cannot create backup dir")
            return ""
    
    var source_file = FileAccess.open(abs_path, FileAccess.READ)
    if source_file:
        var content = source_file.get_buffer(source_file.get_length()).get_string_from_utf8()
        source_file.close()
        
        var dest_file = FileAccess.open(abs_backup_path, FileAccess.WRITE)
        if dest_file:
            dest_file.store_string(content)
            dest_file.close()
            log_debug("Backup created: " + backup_path)
            return abs_backup_path
    return ""

func _restore_backup(scene_path: String, backup_path: String) -> bool:
    if not FileAccess.file_exists(backup_path):
        return false
    var abs_dest = _to_absolute(scene_path)
    var source_file = FileAccess.open(backup_path, FileAccess.READ)
    if source_file:
        var content = source_file.get_buffer(source_file.get_length()).get_string_from_utf8()
        source_file.close()
        var dest_file = FileAccess.open(abs_dest, FileAccess.WRITE)
        if dest_file:
            dest_file.store_string(content)
            dest_file.close()
            return true
    return false

func _cleanup_backup(backup_path: String) -> void:
    if FileAccess.file_exists(backup_path):
        DirAccess.remove_absolute(backup_path)

func create_scene(params):
    var scene_path = _normalize_path(params.scene_path)
    var root_type = params.get("root_node_type", "Node2D")
    
    log_debug("Creating scene: " + scene_path + " with root type: " + root_type)
    
    var root = instantiate_node(root_type)
    if root == null:
        printerr("[ERROR] Failed to instantiate root node type: " + root_type)
        quit(1)
    
    root.name = "root"
    root.owner = root
    
    var packed = PackedScene.new()
    if packed.pack(root) != OK:
        printerr("[ERROR] Failed to pack scene")
        quit(1)
    
    var scene_dir = scene_path.get_base_dir()
    if scene_dir != "res://":
        var abs_dir = _to_absolute(scene_dir)
        _ensure_dir_from_absolute(abs_dir)
    
    if ResourceSaver.save(packed, scene_path) != OK:
        printerr("[ERROR] Failed to save scene")
        quit(1)
    
    log_info("Scene created: " + scene_path)

func add_node(params):
    var scene_path = _normalize_path(params.scene_path)
    var parent_path = params.get("parent_node_path", "root")
    var node_type = params.node_type
    var node_name = params.node_name
    var properties = params.get("properties", {})
    
    log_debug("Adding node " + node_name + " of type " + node_type + " to " + scene_path)
    
    var scene = load(scene_path)
    if scene == null:
        printerr("[ERROR] Failed to load scene: " + scene_path)
        quit(1)
    
    var root = scene.instantiate()
    var parent = _find_node_by_path(root, parent_path)
    if parent == null:
        printerr("[ERROR] Parent node not found: " + parent_path)
        quit(1)
    
    var new_node = instantiate_node(node_type)
    if new_node == null:
        printerr("[ERROR] Failed to instantiate node type: " + node_type)
        quit(1)
    
    new_node.name = node_name
    
    for prop in properties:
        var value = properties[prop]
        if typeof(value) == TYPE_STRING and value.begins_with("res://"):
            value = load(value)
        new_node.set(prop, value)
    
    parent.add_child(new_node)
    new_node.owner = root
    
    _save_packed_scene(root, scene_path)
    log_info("Node '" + node_name + "' added to '" + scene_path + "'")

func add_node_with_script(params):
    var scene_path = _normalize_path(params.scene_path)
    var parent_path = params.get("parent_node_path", "root")
    var node_type = params.get("node_type", "Node")
    var node_name = params.node_name
    var script_path = params.script_path
    var properties = params.get("properties", {})
    var exported_props = params.get("exported_properties", [])
    
    log_debug("Adding node with script: " + node_name)
    
    var scene = load(scene_path)
    if scene == null:
        printerr("[ERROR] Failed to load scene")
        quit(1)
    
    var root = scene.instantiate()
    var parent = _find_node_by_path(root, parent_path)
    if parent == null:
        printerr("[ERROR] Parent not found: " + parent_path)
        quit(1)
    
    var new_node = instantiate_node(node_type)
    if new_node == null:
        printerr("[ERROR] Failed to instantiate: " + node_type)
        quit(1)
    
    new_node.name = node_name
    
    if script_path != "":
        var script = load(script_path)
        if script != null:
            new_node.set_script(script)
            log_debug("Script attached: " + script_path)
    
    for prop in exported_props:
        if prop.has("name") and prop.has("value"):
            new_node.set(prop.name, prop.value)
    
    for prop in properties:
        var value = properties[prop]
        if typeof(value) == TYPE_STRING and value.begins_with("res://"):
            value = load(value)
        new_node.set(prop, value)
    
    parent.add_child(new_node)
    new_node.owner = root
    
    _save_packed_scene(root, scene_path)
    log_info("Node with script '" + node_name + "' added")

func modify_node_property(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var property = params.property
    var value = params.value
    var create_backup = params.get("create_backup", true)
    
    log_debug("Modifying property '" + property + "' on node '" + node_path + "'")
    
    var backup_path = ""
    if create_backup:
        backup_path = _create_backup(scene_path)
        if backup_path == "":
            printerr("[ERROR] Failed to create backup")
            quit(1)
    
    var scene = load(scene_path)
    if scene == null:
        printerr("[ERROR] Failed to load scene")
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var root = scene.instantiate()
    var target = _find_node_by_path(root, node_path)
    if target == null:
        printerr("[ERROR] Node not found: " + node_path)
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    if typeof(value) == TYPE_STRING and value.begins_with("res://"):
        value = load(value)
    
    # Convert Dictionary to Vector2 if needed
    if property == "position" and typeof(value) == TYPE_DICTIONARY:
        if value.has("x") and value.has("y"):
            value = Vector2(float(value.x), float(value.y))
    
    target.set(property, value)
    log_debug("Property set: " + property + " = " + str(value))
    
    if _save_packed_scene(root, scene_path) != OK:
        if backup_path != "": _restore_backup(scene_path, backup_path)
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Failed to save scene")
        quit(1)
    
    if backup_path != "": _cleanup_backup(backup_path)
    log_info("Property '" + property + "' modified on '" + node_path + "'")

func remove_node(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var create_backup = params.get("create_backup", true)
    
    log_debug("Removing node: " + node_path)
    
    var backup_path = ""
    if create_backup:
        backup_path = _create_backup(scene_path)
        if backup_path == "":
            printerr("[ERROR] Failed to create backup")
            quit(1)
    
    var scene = load(scene_path)
    if scene == null:
        printerr("[ERROR] Failed to load scene")
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var root = scene.instantiate()
    var target = _find_node_by_path(root, node_path)
    if target == null:
        printerr("[ERROR] Node not found: " + node_path)
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    if target == root:
        printerr("[ERROR] Cannot remove root node")
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var parent = target.get_parent()
    parent.remove_child(target)
    target.queue_free()
    
    if _save_packed_scene(root, scene_path) != OK:
        if backup_path != "": _restore_backup(scene_path, backup_path)
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Failed to save scene")
        quit(1)
    
    if backup_path != "": _cleanup_backup(backup_path)
    log_info("Node '" + node_path + "' removed from '" + scene_path + "'")

func duplicate_node(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var new_name = params.new_name
    var create_backup = params.get("create_backup", true)
    
    log_debug("Duplicating node: " + node_path + " as " + new_name)
    
    var backup_path = ""
    if create_backup:
        backup_path = _create_backup(scene_path)
        if backup_path == "":
            printerr("[ERROR] Failed to create backup")
            quit(1)
    
    var scene = load(scene_path)
    if scene == null:
        printerr("[ERROR] Failed to load scene")
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var root = scene.instantiate()
    var source = _find_node_by_path(root, node_path)
    if source == null:
        printerr("[ERROR] Source node not found: " + node_path)
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var duplicate = source.duplicate()
    duplicate.name = new_name
    
    var parent = source.get_parent()
    parent.add_child(duplicate)
    duplicate.owner = root
    
    if _save_packed_scene(root, scene_path) != OK:
        if backup_path != "": _restore_backup(scene_path, backup_path)
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Failed to save scene")
        quit(1)
    
    if backup_path != "": _cleanup_backup(backup_path)
    log_info("Node duplicated as '" + new_name + "' in '" + scene_path + "'")

func _collect_node_info(node: Node, prefix: String):
    var node_info = {
        "name": node.name,
        "type": node.get_class(),
        "path": prefix + node.name
    }
    
    if node.get_script() != null:
        node_info["script"] = node.get_script().resource_path
    
    var exported_props = []
    for prop in node.get_property_list():
        if prop.usage & PROPERTY_USAGE_STORAGE:
            exported_props.append({
                "name": prop.name,
                "type": prop.type
            })
    
    if exported_props.size() > 0:
        node_info["properties"] = exported_props
    
    _nodes_collector.append(node_info)
    
    if _collect_recursive:
        for child in node.get_children():
            _collect_node_info(child, prefix + node.name + "/")

func list_nodes(params):
    var scene_path = _normalize_path(params.scene_path)
    _collect_recursive = params.get("recursive", true)
    
    log_debug("Listing nodes in: " + scene_path)
    
    var scene = load(scene_path)
    if scene == null:
        printerr("[ERROR] Failed to load scene")
        quit(1)
    
    var root = scene.instantiate()
    _nodes_collector = []
    
    _collect_node_info(root, "root/")
    
    # Use print instead of log_info to avoid [INFO] prefix
    print("MCP_RESULT:" + JSON.stringify({"nodes": _nodes_collector, "count": _nodes_collector.size()}))

func batch_operations(params):
    var scene_path = _normalize_path(params.scene_path)
    var operations = params.operations
    var enable_rollback = params.get("enable_rollback", true)
    
    log_debug("Starting batch operations on: " + scene_path + " (" + str(operations.size()) + " ops)")
    
    var backup_path = ""
    if enable_rollback:
        backup_path = _create_backup(scene_path)
        if backup_path == "":
            printerr("[ERROR] Failed to create backup for rollback")
            quit(1)
        log_debug("Backup created: " + backup_path)
    
    var success_count = 0
    var fail_count = 0
    
    var scene = load(scene_path)
    if scene == null:
        printerr("[ERROR] Failed to load scene")
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var root = scene.instantiate()
    
    for i in range(operations.size()):
        var op = operations[i]
        var op_type = op.get("operation", "")
        var op_params = op.get("params", {})
        
        log_debug("Batch op " + str(i + 1) + "/" + str(operations.size()) + ": " + op_type)
        
        var success = _execute_operation(root, op_type, op_params)
        
        if success:
            success_count += 1
            log_debug("Batch op " + str(i + 1) + " succeeded")
        else:
            fail_count += 1
            log_debug("Batch op " + str(i + 1) + " failed")
            
            if enable_rollback and backup_path != "":
                log_info("Rolling back changes...")
                _restore_backup(scene_path, backup_path)
                _cleanup_backup(backup_path)
                printerr("[ERROR] Batch operation failed at step " + str(i + 1))
                quit(1)
    
    if _save_packed_scene(root, scene_path) != OK:
        if enable_rollback and backup_path != "":
            _restore_backup(scene_path, backup_path)
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Failed to save scene after batch operations")
        quit(1)
    
    if backup_path != "": _cleanup_backup(backup_path)
    
    log_info("Batch complete: " + str(success_count) + " succeeded, " + str(fail_count) + " failed")
    print("MCP_RESULT:" + JSON.stringify({"success": success_count, "failed": fail_count, "total": operations.size()}))

func _execute_operation(root: Node, op_type: String, params: Dictionary) -> bool:
    match op_type:
        "add_node":
            var node_type = params.get("node_type", "Node")
            var node_name = params.get("node_name", "NewNode")
            var parent_path = params.get("parent_node_path", "root")
            
            var parent = _find_node_by_path(root, parent_path)
            if parent == null:
                return false
            
            var new_node = instantiate_node(node_type)
            if new_node == null:
                return false
            
            new_node.name = node_name
            parent.add_child(new_node)
            new_node.owner = root
            
            if params.has("properties"):
                for prop in params.properties:
                    var value = params.properties[prop]
                    if typeof(value) == TYPE_STRING and value.begins_with("res://"):
                        value = load(value)
                    new_node.set(prop, value)
            
            return true
        
        "remove_node":
            var node_path = params.get("node_path", "")
            var target = _find_node_by_path(root, node_path)
            if target == null or target == root:
                return false
            var parent = target.get_parent()
            parent.remove_child(target)
            target.queue_free()
            return true
        
        "modify_property":
            var node_path = params.get("node_path", "")
            var prop = params.get("property", "")
            var value = params.get("value", null)
            
            var target = _find_node_by_path(root, node_path)
            if target == null:
                return false
            
            if typeof(value) == TYPE_STRING and value.begins_with("res://"):
                value = load(value)
            
            if prop == "position" and typeof(value) == TYPE_DICTIONARY:
                if value.has("x") and value.has("y"):
                    value = Vector2(float(value.x), float(value.y))
            
            target.set(prop, value)
            return true
        
        "set_position":
            var node_path = params.get("node_path", "root")
            var pos = params.get("position", Vector2(0, 0))
            var target = _find_node_by_path(root, node_path)
            if target == null:
                return false
            
            if typeof(pos) == TYPE_DICTIONARY:
                if pos.has("x") and pos.has("y"):
                    pos = Vector2(float(pos.x), float(pos.y))
            
            if target.has_method("set_position"):
                target.set_position(pos)
            return true
        
        "set_script":
            var node_path = params.get("node_path", "")
            var script_path = params.get("script_path", "")
            var target = _find_node_by_path(root, node_path)
            if target == null or script_path == "":
                return false
            var script = load(script_path)
            if script != null:
                target.set_script(script)
                return true
            return false
        
        _:
            log_debug("Unknown batch operation: " + op_type)
            return false

func _save_packed_scene(root: Node, path: String) -> int:
    var packed = PackedScene.new()
    var result = packed.pack(root)
    if result != OK:
        return result
    return ResourceSaver.save(packed, path)

func load_sprite(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var texture_path = _normalize_path(params.texture_path)
    
    log_debug("Loading sprite: " + texture_path + " into " + node_path)
    
    var backup_path = _create_backup(scene_path)
    
    var scene = load(scene_path)
    if scene == null:
        printerr("[ERROR] Failed to load scene")
        quit(1)
    
    var root = scene.instantiate()
    var sprite = _find_node_by_path(root, node_path)
    
    if sprite == null:
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Node not found: " + node_path)
        quit(1)
    
    if not (sprite is Sprite2D or sprite is Sprite3D or sprite is TextureRect):
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Node is not sprite-compatible: " + sprite.get_class())
        quit(1)
    
    var texture = load(texture_path)
    if texture == null:
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Failed to load texture: " + texture_path)
        quit(1)
    
    sprite.texture = texture
    
    if _save_packed_scene(root, scene_path) != OK:
        if backup_path != "": _restore_backup(scene_path, backup_path)
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Failed to save scene")
        quit(1)
    
    if backup_path != "": _cleanup_backup(backup_path)
    log_info("Sprite loaded: " + texture_path)

func save_scene(params):
    var scene_path = _normalize_path(params.scene_path)
    var new_path = params.get("new_path", "")
    
    if new_path != "":
        new_path = _normalize_path(new_path)
        var abs_dir = _to_absolute(new_path.get_base_dir())
        _ensure_dir_from_absolute(abs_dir)
    else:
        new_path = scene_path
    
    log_debug("Saving scene to: " + new_path)
    
    var scene = load(scene_path)
    if scene == null:
        printerr("[ERROR] Failed to load scene")
        quit(1)
    
    var root = scene.instantiate()
    
    if _save_packed_scene(root, new_path) != OK:
        printerr("[ERROR] Failed to save scene")
        quit(1)
    
    log_info("Scene saved: " + new_path)

func get_uid(params):
    var file_path = _normalize_path(params.file_path)
    var uid_path = file_path + ".uid"
    
    if FileAccess.file_exists(uid_path):
        var f = FileAccess.open(_to_absolute(uid_path), FileAccess.READ)
        if f:
            var uid = f.get_line()
            f.close()
            print("MCP_RESULT:" + JSON.stringify({"file": file_path, "uid": uid.strip_edges(), "exists": true}))
        else:
            printerr("[ERROR] Failed to read UID file")
            quit(1)
    else:
        print("MCP_RESULT:" + JSON.stringify({"file": file_path, "exists": false, "message": "UID not generated"}))

func _find_files_recursive(path: String, ext: String) -> Array:
    var files = []
    var dir = DirAccess.open(path)
    if dir:
        dir.list_dir_begin()
        var name = dir.get_next()
        while name != "":
            if dir.current_is_dir() and not name.begins_with("."):
                files.append_array(_find_files_recursive(path + name + "/", ext))
            elif name.ends_with(ext):
                files.append(path + name)
            name = dir.get_next()
    return files

func resave_resources(params):
    var project_path = params.get("project_path", "res://")
    if not project_path.begins_with("res://"):
        project_path = "res://" + project_path
    
    log_debug("Resaving resources in: " + project_path)
    
    var scenes = _find_files_recursive(project_path, ".tscn")
    var scripts = _find_files_recursive(project_path, ".gd") + _find_files_recursive(project_path, ".gdshader")
    
    var success = 0
    var failed = 0
    
    for s in scenes:
        var res = load(s)
        if res and ResourceSaver.save(res, s) == OK:
            success += 1
        else:
            failed += 1
    
    for s in scripts:
        var res = load(s)
        if res and ResourceSaver.save(res, s) == OK:
            success += 1
        else:
            failed += 1
    
    log_info("Resave complete: " + str(success) + " success, " + str(failed) + " failed")
    print("MCP_RESULT:" + JSON.stringify({"success": success, "failed": failed}))

# ===== NODE INFO OPERATIONS =====

func _load_scene_for_node(params):
    var scene_path = _normalize_path(params.scene_path)
    var scene = load(scene_path)
    if scene == null:
        printerr("[ERROR] Failed to load scene: " + scene_path)
        return null
    return scene.instantiate()

func get_node_info(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    
    var root = _load_scene_for_node(params)
    if root == null:
        quit(1)
    
    var target = _find_node_by_path(root, node_path)
    if target == null:
        printerr("[ERROR] Node not found: " + node_path)
        quit(1)
    
    var info = {
        "name": target.name,
        "type": target.get_class(),
        "path": node_path,
        "script": null,
        "groups": target.get_groups(),
        "properties": [],
        "signals": [],
        "children_count": target.get_child_count(),
        "parent": null if target == root else target.get_parent().name
    }
    
    if target.get_script() != null:
        info["script"] = target.get_script().resource_path
    
    for prop in target.get_property_list():
        if prop.usage & PROPERTY_USAGE_STORAGE:
            info["properties"].append({
                "name": prop.name,
                "type": prop.type,
                "type_name": _get_type_name(prop.type)
            })
    
    for sig in target.get_signal_list():
        info["signals"].append({
            "name": sig.name,
            "args": sig.args
        })
    
    print("MCP_RESULT:" + JSON.stringify(info))

func _get_type_name(type_id: int) -> String:
    match type_id:
        TYPE_NIL: return "nil"
        TYPE_BOOL: return "bool"
        TYPE_INT: return "int"
        TYPE_FLOAT: return "float"
        TYPE_STRING: return "string"
        TYPE_VECTOR2: return "Vector2"
        TYPE_VECTOR2I: return "Vector2i"
        TYPE_VECTOR3: return "Vector3"
        TYPE_VECTOR3I: return "Vector3i"
        TYPE_VECTOR4: return "Vector4"
        TYPE_VECTOR4I: return "Vector4i"
        TYPE_RECT2: return "Rect2"
        TYPE_RECT2I: return "Rect2i"
        TYPE_VECTOR3: return "Vector3"
        TYPE_TRANSFORM2D: return "Transform2D"
        TYPE_VECTOR3: return "Vector3"
        TYPE_TRANSFORM3D: return "Transform3D"
        TYPE_PLANE: return "Plane"
        TYPE_QUATERNION: return "Quaternion"
        TYPE_AABB: return "AABB"
        TYPE_BASIS: return "Basis"
        TYPE_PROJECTION: return "Projection"
        TYPE_COLOR: return "Color"
        TYPE_NODE_PATH: return "NodePath"
        TYPE_RID: return "RID"
        TYPE_OBJECT: return "Object"
        TYPE_DICTIONARY: return "Dictionary"
        TYPE_ARRAY: return "Array"
        TYPE_PACKED_BYTE_ARRAY: return "PackedByteArray"
        TYPE_PACKED_INT32_ARRAY: return "PackedInt32Array"
        TYPE_FLOAT: return "float"
        TYPE_PACKED_STRING_ARRAY: return "PackedStringArray"
        TYPE_PACKED_VECTOR2_ARRAY: return "PackedVector2Array"
        TYPE_PACKED_VECTOR3_ARRAY: return "PackedVector3Array"
        TYPE_PACKED_COLOR_ARRAY: return "PackedColorArray"
        TYPE_INT: return "int"
        TYPE_FLOAT: return "float"
        _: return "unknown"

# ===== PROPERTY OPERATIONS =====

func get_node_property(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var property = params.property
    
    var root = _load_scene_for_node(params)
    if root == null:
        quit(1)
    
    var target = _find_node_by_path(root, node_path)
    if target == null:
        printerr("[ERROR] Node not found: " + node_path)
        quit(1)
    
    if not target.has(property):
        printerr("[ERROR] Node has no property: " + property)
        quit(1)
    
    var value = target.get(property)
    var value_info = {
        "property": property,
        "value": _serialize_value(value),
        "type": typeof(value),
        "type_name": _get_type_name(typeof(value))
    }
    
    print("MCP_RESULT:" + JSON.stringify(value_info))

func set_node_property(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var property = params.property
    var value = params.value
    var create_backup = params.get("create_backup", true)
    
    var backup_path = ""
    if create_backup:
        backup_path = _create_backup(scene_path)
        if backup_path == "":
            printerr("[ERROR] Failed to create backup")
            quit(1)
    
    var root = _load_scene_for_node(params)
    if root == null:
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var target = _find_node_by_path(root, node_path)
    if target == null:
        printerr("[ERROR] Node not found: " + node_path)
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    if typeof(value) == TYPE_STRING and value.begins_with("res://"):
        value = load(value)
    
    if typeof(value) == TYPE_DICTIONARY:
        value = _deserialize_value(value, target, property)
    
    if not target.has(property):
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Node has no property: " + property)
        quit(1)
    
    target.set(property, value)
    
    if _save_packed_scene(root, scene_path) != OK:
        if backup_path != "": _restore_backup(scene_path, backup_path)
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Failed to save scene")
        quit(1)
    
    if backup_path != "": _cleanup_backup(backup_path)
    log_info("Property '" + property + "' set on '" + node_path + "'")
    print("MCP_RESULT:" + JSON.stringify({"success": true, "property": property, "value": _serialize_value(value)}))

# ===== TRANSFORM OPERATIONS =====

func get_node_transform(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var global = params.get("global", false)
    
    var root = _load_scene_for_node(params)
    if root == null:
        quit(1)
    
    var target = _find_node_by_path(root, node_path)
    if target == null:
        printerr("[ERROR] Node not found: " + node_path)
        quit(1)
    
    var transform_info = {
        "node": node_path,
        "position": _serialize_value(target.position if not global else target.global_position),
        "rotation": _serialize_value(target.rotation if not global else target.global_rotation),
        "scale": _serialize_value(target.scale if not global else target.global_scale)
    }
    
    if target is Node2D:
        transform_info["transform_2d"] = _serialize_value(target.transform)
    elif target is Node3D:
        transform_info["transform_3d"] = _serialize_value(target.transform)
    
    print("MCP_RESULT:" + JSON.stringify(transform_info))

func set_node_position(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var position = params.position
    var global = params.get("global", false)
    var create_backup = params.get("create_backup", true)
    
    var backup_path = ""
    if create_backup:
        backup_path = _create_backup(scene_path)
        if backup_path == "": printerr("[WARNING] Backup failed")
    
    var root = _load_scene_for_node(params)
    if root == null:
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var target = _find_node_by_path(root, node_path)
    if target == null:
        printerr("[ERROR] Node not found: " + node_path)
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var pos = _parse_vector(position, 2)
    if pos == null:
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Invalid position format")
        quit(1)
    
    if global and target.has_method("set_global_position"):
        target.set_global_position(pos)
    elif target.has_method("set_position"):
        target.set_position(pos)
    
    if _save_packed_scene(root, scene_path) != OK:
        if backup_path != "": _restore_backup(scene_path, backup_path)
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Failed to save scene")
        quit(1)
    
    if backup_path != "": _cleanup_backup(backup_path)
    print("MCP_RESULT:" + JSON.stringify({"success": true, "node": node_path, "position": _serialize_value(pos)}))

func set_node_rotation(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var rotation = params.rotation
    var global = params.get("global", false)
    var create_backup = params.get("create_backup", true)
    
    var backup_path = ""
    if create_backup:
        backup_path = _create_backup(scene_path)
        if backup_path == "": printerr("[WARNING] Backup failed")
    
    var root = _load_scene_for_node(params)
    if root == null:
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var target = _find_node_by_path(root, node_path)
    if target == null:
        printerr("[ERROR] Node not found: " + node_path)
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var rot = float(rotation)
    
    if global and target.has_method("set_global_rotation"):
        target.set_global_rotation(rot)
    elif target.has_method("set_rotation"):
        target.set_rotation(rot)
    
    if _save_packed_scene(root, scene_path) != OK:
        if backup_path != "": _restore_backup(scene_path, backup_path)
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Failed to save scene")
        quit(1)
    
    if backup_path != "": _cleanup_backup(backup_path)
    print("MCP_RESULT:" + JSON.stringify({"success": true, "node": node_path, "rotation": rot}))

func set_node_scale(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var scale = params.scale
    var create_backup = params.get("create_backup", true)
    
    var backup_path = ""
    if create_backup:
        backup_path = _create_backup(scene_path)
        if backup_path == "": printerr("[WARNING] Backup failed")
    
    var root = _load_scene_for_node(params)
    if root == null:
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var target = _find_node_by_path(root, node_path)
    if target == null:
        printerr("[ERROR] Node not found: " + node_path)
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var sc = _parse_vector(scale, 2)
    if sc == null:
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Invalid scale format")
        quit(1)
    
    target.scale = sc
    
    if _save_packed_scene(root, scene_path) != OK:
        if backup_path != "": _restore_backup(scene_path, backup_path)
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Failed to save scene")
        quit(1)
    
    if backup_path != "": _cleanup_backup(backup_path)
    print("MCP_RESULT:" + JSON.stringify({"success": true, "node": node_path, "scale": _serialize_value(sc)}))

# ===== HIERARCHY OPERATIONS =====

func get_parent_path(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    
    var root = _load_scene_for_node(params)
    if root == null:
        quit(1)
    
    var target = _find_node_by_path(root, node_path)
    if target == null:
        printerr("[ERROR] Node not found: " + node_path)
        quit(1)
    
    if target == root:
        print("MCP_RESULT:" + JSON.stringify({"node": node_path, "parent": null, "is_root": true}))
    else:
        var parent = target.get_parent()
        print("MCP_RESULT:" + JSON.stringify({"node": node_path, "parent": parent.name if parent else null, "is_root": false}))

func get_children(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var recursive = params.get("recursive", false)
    var include_types = params.get("include_types", false)
    
    var root = _load_scene_for_node(params)
    if root == null:
        quit(1)
    
    var target = _find_node_by_path(root, node_path)
    if target == null:
        printerr("[ERROR] Node not found: " + node_path)
        quit(1)
    
    var children = []
    var prefix = node_path + "/" if node_path != "root" else "root/"
    _collect_children(target, prefix, recursive, include_types, children)
    
    print("MCP_RESULT:" + JSON.stringify({"parent": node_path, "children": children, "count": children.size()}))

func _collect_children(node: Node, prefix: String, recursive: bool, include_types: bool, results: Array):
    for child in node.get_children():
        var child_info = {"name": child.name, "path": prefix + child.name}
        if include_types:
            child_info["type"] = child.get_class()
        results.append(child_info)
        if recursive:
            _collect_children(child, prefix + child.name + "/", recursive, include_types, results)

func has_child(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var child_name = params.child_name
    
    var root = _load_scene_for_node(params)
    if root == null:
        quit(1)
    
    var target = _find_node_by_path(root, node_path)
    if target == null:
        printerr("[ERROR] Node not found: " + node_path)
        quit(1)
    
    var has_it = target.has_node(child_name)
    print("MCP_RESULT:" + JSON.stringify({"parent": node_path, "child_name": child_name, "exists": has_it}))

# ===== SIGNAL OPERATIONS =====

func connect_signal(params):
    var scene_path = _normalize_path(params.scene_path)
    var from_node_path = params.from_node
    var signal_name = params.signal
    var to_node_path = params.to_node
    var method_name = params.method
    var create_backup = params.get("create_backup", true)
    
    var backup_path = ""
    if create_backup:
        backup_path = _create_backup(scene_path)
        if backup_path == "": printerr("[WARNING] Backup failed")
    
    var root = _load_scene_for_node(params)
    if root == null:
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var from_node = _find_node_by_path(root, from_node_path)
    var to_node = _find_node_by_path(root, to_node_path)
    
    if from_node == null:
        printerr("[ERROR] Source node not found: " + from_node_path)
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    if to_node == null:
        printerr("[ERROR] Target node not found: " + to_node_path)
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var result = from_node.connect(signal_name, Callable(to_node, method_name))
    
    if result != OK:
        printerr("[ERROR] Failed to connect signal: " + str(result))
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    if _save_packed_scene(root, scene_path) != OK:
        if backup_path != "": _restore_backup(scene_path, backup_path)
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Failed to save scene")
        quit(1)
    
    if backup_path != "": _cleanup_backup(backup_path)
    print("MCP_RESULT:" + JSON.stringify({"success": true, "signal": signal_name, "from": from_node_path, "to": to_node_path, "method": method_name}))

func disconnect_signal(params):
    var scene_path = _normalize_path(params.scene_path)
    var from_node_path = params.from_node
    var signal_name = params.signal
    var to_node_path = params.to_node
    var method_name = params.method
    var create_backup = params.get("create_backup", true)
    
    var backup_path = ""
    if create_backup:
        backup_path = _create_backup(scene_path)
        if backup_path == "": printerr("[WARNING] Backup failed")
    
    var root = _load_scene_for_node(params)
    if root == null:
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var from_node = _find_node_by_path(root, from_node_path)
    var to_node = _find_node_by_path(root, to_node_path)
    
    if from_node == null or to_node == null:
        printerr("[ERROR] Node not found")
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    from_node.disconnect(signal_name, Callable(to_node, method_name))
    
    if _save_packed_scene(root, scene_path) != OK:
        printerr("[ERROR] Failed to save scene")
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    if backup_path != "": _cleanup_backup(backup_path)
    print("MCP_RESULT:" + JSON.stringify({"success": true, "signal": signal_name, "from": from_node_path, "to": to_node_path}))

func emit_node_signal(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var signal_name = params.signal
    var args = params.get("args", [])
    
    var root = _load_scene_for_node(params)
    if root == null:
        quit(1)
    
    var target = _find_node_by_path(root, node_path)
    if target == null:
        printerr("[ERROR] Node not found: " + node_path)
        quit(1)
    
    if args.size() == 0:
        target.emit_signal(signal_name)
    elif args.size() == 1:
        target.emit_signal(signal_name, _deserialize_value(args[0], target, ""))
    elif args.size() == 2:
        target.emit_signal(signal_name, _deserialize_value(args[0], target, ""), _deserialize_value(args[1], target, ""))
    elif args.size() == 3:
        target.emit_signal(signal_name, _deserialize_value(args[0], target, ""), _deserialize_value(args[1], target, ""), _deserialize_value(args[2], target, ""))
    else:
        printerr("[ERROR] Too many signal arguments (max 3)")
        quit(1)
    
    log_info("Signal emitted: " + signal_name + " on " + node_path)
    print("MCP_RESULT:" + JSON.stringify({"success": true, "signal": signal_name, "node": node_path}))

# ===== GROUP OPERATIONS =====

func get_groups(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    
    var root = _load_scene_for_node(params)
    if root == null:
        quit(1)
    
    var target = _find_node_by_path(root, node_path)
    if target == null:
        printerr("[ERROR] Node not found: " + node_path)
        quit(1)
    
    print("MCP_RESULT:" + JSON.stringify({"node": node_path, "groups": target.get_groups()}))

func add_to_group(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var group_name = params.group
    var create_backup = params.get("create_backup", true)
    
    var backup_path = ""
    if create_backup:
        backup_path = _create_backup(scene_path)
        if backup_path == "": printerr("[WARNING] Backup failed")
    
    var root = _load_scene_for_node(params)
    if root == null:
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var target = _find_node_by_path(root, node_path)
    if target == null:
        printerr("[ERROR] Node not found: " + node_path)
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    target.add_to_group(group_name)
    
    if _save_packed_scene(root, scene_path) != OK:
        if backup_path != "": _restore_backup(scene_path, backup_path)
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Failed to save scene")
        quit(1)
    
    if backup_path != "": _cleanup_backup(backup_path)
    print("MCP_RESULT:" + JSON.stringify({"success": true, "node": node_path, "added_to_group": group_name}))

func remove_from_group(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var group_name = params.group
    var create_backup = params.get("create_backup", true)
    
    var backup_path = ""
    if create_backup:
        backup_path = _create_backup(scene_path)
        if backup_path == "": printerr("[WARNING] Backup failed")
    
    var root = _load_scene_for_node(params)
    if root == null:
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var target = _find_node_by_path(root, node_path)
    if target == null:
        printerr("[ERROR] Node not found: " + node_path)
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    target.remove_from_group(group_name)
    
    if _save_packed_scene(root, scene_path) != OK:
        printerr("[ERROR] Failed to save scene")
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    if backup_path != "": _cleanup_backup(backup_path)
    print("MCP_RESULT:" + JSON.stringify({"success": true, "node": node_path, "removed_from_group": group_name}))

func call_group_method(params):
    var scene_path = _normalize_path(params.scene_path)
    var group_name = params.group
    var method_name = params.method
    var args = params.get("args", [])
    
    var root = _load_scene_for_node(params)
    if root == null:
        quit(1)
    
    var nodes_called = []
    _call_group_on_node(root, group_name, method_name, args, nodes_called)
    
    print("MCP_RESULT:" + JSON.stringify({"group": group_name, "method": method_name, "nodes_called": nodes_called, "count": nodes_called.size()}))

func _call_group_on_node(node: Node, group_name: String, method_name: String, args: Array, results: Array):
    if node.is_in_group(group_name):
        if node.has_method(method_name):
            if args.size() == 0:
                node.call(method_name)
            elif args.size() == 1:
                node.call(method_name, _deserialize_value(args[0], node, ""))
            elif args.size() == 2:
                node.call(method_name, _deserialize_value(args[0], node, ""), _deserialize_value(args[1], node, ""))
            else:
                node.callv(method_name, [])
            results.append(node.name)
    for child in node.get_children():
        _call_group_on_node(child, group_name, method_name, args, results)

# ===== HELPER FUNCTIONS =====

func _serialize_value(value: Variant) -> Dictionary:
    var type_name = _get_type_name(typeof(value))
    var result = {"type": typeof(value), "type_name": type_name}
    
    match typeof(value):
        TYPE_BOOL: result["value"] = value
        TYPE_INT: result["value"] = value
        TYPE_FLOAT: result["value"] = value
        TYPE_STRING: result["value"] = value
        TYPE_VECTOR2: result["value"] = {"x": value.x, "y": value.y}
        TYPE_VECTOR2I: result["value"] = {"x": value.x, "y": value.y}
        TYPE_VECTOR3: result["value"] = {"x": value.x, "y": value.y, "z": value.z}
        TYPE_VECTOR3I: result["value"] = {"x": value.x, "y": value.y, "z": value.z}
        TYPE_VECTOR4: result["value"] = {"x": value.x, "y": value.y, "z": value.z, "w": value.w}
        TYPE_COLOR: result["value"] = {"r": value.r, "g": value.g, "b": value.b, "a": value.a}
        TYPE_NODE_PATH: result["value"] = str(value)
        TYPE_DICTIONARY: result["value"] = value
        TYPE_ARRAY: result["value"] = value
        TYPE_NIL: result["value"] = null
        TYPE_OBJECT:
            if value is Resource:
                result["value"] = value.resource_path if value.resource_path else str(value)
            else:
                result["value"] = str(value)
        _:
            result["value"] = str(value)
    
    return result

func _deserialize_value(data, node: Node, property: String) -> Variant:
    if typeof(data) == TYPE_DICTIONARY and data.has("type") and data.has("value"):
        var type_id = int(data.type)
        var value = data.value
        
        match type_id:
            TYPE_BOOL: return bool(value)
            TYPE_INT: return int(value)
            TYPE_FLOAT: return float(value)
            TYPE_STRING: return str(value)
            TYPE_VECTOR2:
                return Vector2(float(value.x), float(value.y))
            TYPE_VECTOR2I:
                return Vector2i(int(value.x), int(value.y))
            TYPE_VECTOR3:
                return Vector3(float(value.x), float(value.y), float(value.z))
            TYPE_VECTOR3I:
                return Vector3i(int(value.x), int(value.y), int(value.z))
            TYPE_COLOR:
                return Color(float(value.r), float(value.g), float(value.b), float(value.get("a", 1.0)))
            TYPE_NODE_PATH:
                return NodePath(str(value))
            _:
                return value
    return data

func _parse_vector(data, components: int):
    if typeof(data) == TYPE_VECTOR2:
        return data
    if typeof(data) == TYPE_VECTOR3:
        return data
    if typeof(data) == TYPE_DICTIONARY:
        if components == 2:
            if data.has("x") and data.has("y"):
                return Vector2(float(data.x), float(data.y))
        elif components == 3:
            if data.has("x") and data.has("y") and data.has("z"):
                return Vector3(float(data.x), float(data.y), float(data.z))
    return null
