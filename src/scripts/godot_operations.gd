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
        "attach_script": attach_script(params)
        "modify_node_property": modify_node_property(params)
        "remove_node": remove_node(params)
        "duplicate_node": duplicate_node(params)
        "list_nodes": list_nodes(params)
        "batch_operations": batch_operations(params)
        "generate_nodes": generate_nodes(params)
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
        "instance_scene": instance_scene(params)
        "create_script": create_script(params)
        "edit_script": edit_script(params)
        "create_resource": create_resource(params)
        "assign_node_resource": assign_node_resource(params)
        "list_resources": list_resources(params)
        "run_scene": run_scene(params)
        "create_scene_3d": create_scene_3d(params)
        "add_node_3d": add_node_3d(params)
        "set_node_position_3d": set_node_position_3d(params)
        "set_node_rotation_3d": set_node_rotation_3d(params)
        "set_node_scale_3d": set_node_scale_3d(params)
        "export_project": export_project(params)
        "validate_scene": validate_scene(params)
        "get_project_setting": get_project_setting(params)
        "set_project_setting": set_project_setting(params)
        "list_input_actions": list_input_actions(params)
        "create_input_action": create_input_action(params)
        "add_collision_layer": add_collision_layer(params)
        "set_collision_mask": set_collision_mask(params)
        "import_asset": import_asset(params)
        "create_animation": create_animation(params)
        "add_animation_track": add_animation_track(params)
        "find_nodes": find_nodes(params)
        "execute_gdscript": execute_gdscript(params)
        "snapshot_scene": snapshot_scene(params)
        "compare_scenes": compare_scenes(params)
        "set_layout": set_layout(params)
        "move_node": move_node(params)
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

func _create_script_backup(script_path: String) -> String:
    var abs_path = _to_absolute(script_path)
    var backup_name = script_path.md5_text() + "_" + str(Time.get_unix_time_from_system())
    var backup_path = "res://mcp_backups/" + backup_name + ".gd"
    var abs_backup_path = _to_absolute(backup_path)
    
    var dir = DirAccess.open("res://")
    if dir == null:
        return ""
    if not dir.dir_exists("mcp_backups"):
        if dir.make_dir("mcp_backups") != OK:
            return ""
    
    var source_file = FileAccess.open(abs_path, FileAccess.READ)
    if source_file:
        var content = source_file.get_buffer(source_file.get_length()).get_string_from_utf8()
        source_file.close()
        var dest_file = FileAccess.open(abs_backup_path, FileAccess.WRITE)
        if dest_file:
            dest_file.store_string(content)
            dest_file.close()
            return abs_backup_path
    return ""

func create_scene(params):
    var scene_path = _normalize_path(params.scene_path)
    var root_type = params.get("root_node_type", "Node2D")
    
    log_debug("Creating scene: " + scene_path + " with root type: " + root_type)
    
    var root = instantiate_node(root_type)
    if root == null:
        printerr("[ERROR] Failed to instantiate root node type: " + root_type)
        quit(1)

    root.name = "root"
    # NOTE: root.owner = root is not allowed in Godot 4.6+ (node cannot own itself)

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

func attach_script(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var script_path = _normalize_path(params.script_path)
    var create_backup = params.get("create_backup", false)
    
    log_debug("Attaching script '" + script_path + "' to node '" + node_path + "'")
    
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
    
    var script = load(script_path)
    if script == null:
        printerr("[ERROR] Script not found: " + script_path)
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    target.set_script(script)
    
    _save_packed_scene(root, scene_path)
    log_info("Script '" + script_path + "' attached to '" + node_path + "'")

func modify_node_property(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var property = params.property
    var value = params.value
    var create_backup = params.get("create_backup", false)
    
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
    var create_backup = params.get("create_backup", false)
    
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
    var create_backup = params.get("create_backup", false)
    
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

func move_node(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var new_parent_path = params.get("new_parent_path", "")
    var new_index = params.get("new_index", -1)
    var create_backup = params.get("create_backup", false)

    log_debug("Moving node: " + node_path)

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

    var old_parent = target.get_parent()
    var result_info = {"node": node_path}

    if new_parent_path != "" and new_parent_path != node_path:
        var new_parent = _find_node_by_path(root, new_parent_path)
        if new_parent == null:
            printerr("[ERROR] New parent not found: " + new_parent_path)
            if backup_path != "": _cleanup_backup(backup_path)
            quit(1)
        old_parent.remove_child(target)
        new_parent.add_child(target)
        target.owner = root
        # Recursively reassign owners for all children
        _reassign_owners(target, root)
        result_info["reparented_to"] = new_parent_path

    if new_index >= 0:
        var parent = target.get_parent()
        parent.move_child(target, new_index)
        result_info["new_index"] = new_index

    if _save_packed_scene(root, scene_path) != OK:
        if backup_path != "": _restore_backup(scene_path, backup_path)
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Failed to save scene")
        quit(1)

    if backup_path != "": _cleanup_backup(backup_path)
    log_info("Node moved: " + node_path)
    print("MCP_RESULT:" + JSON.stringify(result_info))

func _reassign_owners(node: Node, root: Node):
    for child in node.get_children():
        child.owner = root
        _reassign_owners(child, root)

func _collect_node_info(node: Node, prefix: String, fields: Array, depth: int, max_depth: int):
    var node_info = {}
    var path = prefix + node.name

    if fields.is_empty() or "name" in fields:
        node_info["name"] = node.name
    if fields.is_empty() or "type" in fields:
        node_info["type"] = node.get_class()
    if fields.is_empty() or "path" in fields:
        node_info["path"] = path
    if ("script" in fields or fields.is_empty()) and node.get_script() != null:
        node_info["script"] = node.get_script().resource_path
    if "children_count" in fields:
        node_info["children_count"] = node.get_child_count()
    if "properties" in fields:
        var exported_props = []
        for prop in node.get_property_list():
            if prop.usage & PROPERTY_USAGE_STORAGE:
                exported_props.append({"name": prop.name, "type": prop.type})
        node_info["properties"] = exported_props

    _nodes_collector.append(node_info)

    if _collect_recursive and (max_depth <= 0 or depth < max_depth):
        for child in node.get_children():
            _collect_node_info(child, path + "/", fields, depth + 1, max_depth)

func list_nodes(params):
    var scene_path = _normalize_path(params.scene_path)
    _collect_recursive = params.get("recursive", true)
    var max_depth = params.get("max_depth", 0)  # 0 = unlimited
    var fields = params.get("fields", [])        # [] = default (name, type, path, script)

    log_debug("Listing nodes in: " + scene_path)

    var scene = load(scene_path)
    if scene == null:
        printerr("[ERROR] Failed to load scene")
        quit(1)

    var root = scene.instantiate()
    _nodes_collector = []

    _collect_node_info(root, "", fields, 0, max_depth)

    print("MCP_RESULT:" + JSON.stringify({"nodes": _nodes_collector, "count": _nodes_collector.size()}))

func batch_operations(params):
    var scene_path = _normalize_path(params.scene_path)
    var operations = params.operations
    var enable_rollback = params.get("enable_rollback", false)
    
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
        var normalized = _normalize_batch_op(op)
        var op_type = normalized["operation"]
        var op_params = normalized["params"]

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

func _normalize_batch_op(op: Dictionary) -> Dictionary:
    # Map operation name aliases
    var op_name_map = {
        "set_node_property": "modify_property",
        "setNodeProperty":   "modify_property",
        "setProperty":       "modify_property",
    }
    var op_type = op_name_map.get(op.get("operation",""), op.get("operation",""))

    # Accept nested params OR flat params directly in op dict
    var raw = op.get("params", {})
    if raw.is_empty():
        raw = {}
        for key in op:
            if key != "operation":
                raw[key] = op[key]

    # Normalize camelCase → snake_case
    var key_map = {
        "nodeType":       "node_type",
        "nodeName":       "node_name",
        "parentPath":     "parent_node_path",
        "parentNodePath": "parent_node_path",
        "nodePath":       "node_path",
        "newParentPath":  "new_parent_path",
        "scriptPath":     "script_path",
        "newIndex":       "new_index",
        "texturePath":    "texture_path",
    }
    var normalized_params = {}
    for key in raw:
        normalized_params[key_map.get(key, key)] = raw[key]

    return {"operation": op_type, "params": normalized_params}

func generate_nodes(params):
    var scene_path = _normalize_path(params.scene_path)
    var nodes_data = params.nodes
    var backup_path = ""
    if params.get("create_backup", false):
        backup_path = _create_backup(scene_path)
        if backup_path == "":
            printerr("[ERROR] Failed to create backup")
            quit(1)

    var scene = load(scene_path)
    if scene == null:
        printerr("[ERROR] Failed to load scene: " + scene_path)
        quit(1)

    var root = scene.instantiate()
    var created = 0
    var skipped = 0

    for node_def in nodes_data:
        var node_type  = node_def.get("type",   "Node")
        var node_name  = node_def.get("name",   "NewNode")
        var parent_path = node_def.get("parent", "root")
        var properties = node_def.get("properties", {})

        var parent = _find_node_by_path(root, parent_path)
        if parent == null:
            printerr("[WARN] Parent not found: " + parent_path + " for " + node_name)
            skipped += 1
            continue

        var new_node = instantiate_node(node_type)
        if new_node == null:
            printerr("[WARN] Cannot instantiate: " + node_type)
            skipped += 1
            continue

        new_node.name = node_name

        for prop in properties:
            var val = properties[prop]
            # Auto-convert common Godot types
            if typeof(val) == TYPE_DICTIONARY and val.has("x") and val.has("y"):
                val = Vector2(float(val.x), float(val.y))
            elif prop == "color" and typeof(val) == TYPE_ARRAY and val.size() >= 3:
                val = Color(float(val[0]), float(val[1]), float(val[2]),
                            float(val[3]) if val.size() > 3 else 1.0)
            elif prop == "polygon" and typeof(val) == TYPE_ARRAY:
                var vecs = PackedVector2Array()
                for j in range(0, val.size() - 1, 2):
                    vecs.append(Vector2(float(val[j]), float(val[j+1])))
                val = vecs
            new_node.set(prop, val)

        parent.add_child(new_node)
        new_node.owner = root
        created += 1

    if _save_packed_scene(root, scene_path) != OK:
        if backup_path != "": _restore_backup(scene_path, backup_path)
        printerr("[ERROR] Failed to save scene")
        quit(1)

    if backup_path != "": _cleanup_backup(backup_path)
    log_info("generate_nodes: " + str(created) + " created, " + str(skipped) + " skipped")
    print("MCP_RESULT:" + JSON.stringify({"created": created, "skipped": skipped, "total": nodes_data.size()}))

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
        
        "set_property":
            var node_path = params.get("node_path", "")
            var prop = params.get("property", "")
            var value = params.get("value", null)
            
            var target = _find_node_by_path(root, node_path)
            if target == null:
                return false
            
            if typeof(value) == TYPE_STRING and value.begins_with("res://"):
                value = load(value)
            
            if typeof(value) == TYPE_DICTIONARY:
                value = _deserialize_value(value, target, prop)
            
            target.set(prop, value)
            return true
        
        "set_layout":
            var node_path = params.get("node_path", "")
            var layout = params.get("layout", {})
            
            var target = _find_node_by_path(root, node_path)
            if target == null:
                return false
            
            if layout.has("anchors_preset"):
                target.anchors_preset = int(layout.anchors_preset)
            if layout.has("offset_left"):
                target.offset_left = int(layout.offset_left)
            if layout.has("offset_top"):
                target.offset_top = int(layout.offset_top)
            if layout.has("offset_right"):
                target.offset_right = int(layout.offset_right)
            if layout.has("offset_bottom"):
                target.offset_bottom = int(layout.offset_bottom)
            if layout.has("custom_minimum_size"):
                var size = layout.custom_minimum_size
                if typeof(size) == TYPE_DICTIONARY:
                    target.custom_minimum_size = Vector2(float(size.get("x", 0)), float(size.get("y", 0)))
                else:
                    target.custom_minimum_size = size
            if layout.has("size_flags_horizontal"):
                target.size_flags_horizontal = int(layout.size_flags_horizontal)
            if layout.has("size_flags_vertical"):
                target.size_flags_vertical = int(layout.size_flags_vertical)
            if layout.has("layout_mode"):
                target.layout_mode = int(layout.layout_mode)
            
            return true
        
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
        "script": null if target.get_script() == null else target.get_script().resource_path,
        "groups": target.get_groups(),
        "properties": [],
        "signal_names": [],
        "children_count": target.get_child_count(),
        "parent": null if target == root else target.get_parent().name
    }
    
    for prop in target.get_property_list():
        if prop.usage & PROPERTY_USAGE_STORAGE:
            info["properties"].append({
                "name": prop.name,
                "type": prop.type,
                "type_name": _get_type_name(prop.type)
            })
    
    for sig in target.get_signal_list():
        info["signal_names"].append(sig.name)
    
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
    var create_backup = params.get("create_backup", false)
    
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

func set_layout(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var layout = params.layout
    var create_backup = params.get("create_backup", false)
    
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
    
    var changes = []
    
    if layout.has("anchors_preset"):
        target.anchors_preset = int(layout.anchors_preset)
        changes.append("anchors_preset=" + str(layout.anchors_preset))
    if layout.has("anchor_left"):
        target.anchor_left = float(layout.anchor_left)
        changes.append("anchor_left=" + str(layout.anchor_left))
    if layout.has("anchor_top"):
        target.anchor_top = float(layout.anchor_top)
        changes.append("anchor_top=" + str(layout.anchor_top))
    if layout.has("anchor_right"):
        target.anchor_right = float(layout.anchor_right)
        changes.append("anchor_right=" + str(layout.anchor_right))
    if layout.has("anchor_bottom"):
        target.anchor_bottom = float(layout.anchor_bottom)
        changes.append("anchor_bottom=" + str(layout.anchor_bottom))
    if layout.has("offset_left"):
        target.offset_left = int(layout.offset_left)
        changes.append("offset_left=" + str(layout.offset_left))
    if layout.has("offset_top"):
        target.offset_top = int(layout.offset_top)
        changes.append("offset_top=" + str(layout.offset_top))
    if layout.has("offset_right"):
        target.offset_right = int(layout.offset_right)
        changes.append("offset_right=" + str(layout.offset_right))
    if layout.has("offset_bottom"):
        target.offset_bottom = int(layout.offset_bottom)
        changes.append("offset_bottom=" + str(layout.offset_bottom))
    if layout.has("custom_minimum_size"):
        var size = layout.custom_minimum_size
        if typeof(size) == TYPE_DICTIONARY:
            target.custom_minimum_size = Vector2(float(size.get("x", 0)), float(size.get("y", 0)))
        else:
            target.custom_minimum_size = size
        changes.append("custom_minimum_size=" + str(target.custom_minimum_size))
    if layout.has("size_flags_horizontal"):
        target.size_flags_horizontal = int(layout.size_flags_horizontal)
        changes.append("size_flags_horizontal=" + str(layout.size_flags_horizontal))
    if layout.has("size_flags_vertical"):
        target.size_flags_vertical = int(layout.size_flags_vertical)
        changes.append("size_flags_vertical=" + str(layout.size_flags_vertical))
    if layout.has("layout_mode"):
        target.layout_mode = int(layout.layout_mode)
        changes.append("layout_mode=" + str(layout.layout_mode))
    
    if _save_packed_scene(root, scene_path) != OK:
        if backup_path != "": _restore_backup(scene_path, backup_path)
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Failed to save scene")
        quit(1)
    
    if backup_path != "": _cleanup_backup(backup_path)
    log_info("Layout set on '" + node_path + "': " + ", ".join(changes))
    print("MCP_RESULT:" + JSON.stringify({"success": true, "node": node_path, "changes": changes}))

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
    var create_backup = params.get("create_backup", false)
    
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
    var create_backup = params.get("create_backup", false)
    
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
    var create_backup = params.get("create_backup", false)
    
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
    var create_backup = params.get("create_backup", false)
    
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
    var create_backup = params.get("create_backup", false)
    
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
    var create_backup = params.get("create_backup", false)
    
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
    var create_backup = params.get("create_backup", false)
    
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
    if typeof(data) == TYPE_DICTIONARY:
        # Check for Color with r, g, b, a keys (direct format)
        if data.has("r") and data.has("g") and data.has("b"):
            var r = float(data.get("r", 1.0))
            var g = float(data.get("g", 1.0))
            var b = float(data.get("b", 1.0))
            var a = float(data.get("a", 1.0))
            return Color(r, g, b, a)
        # Check for wrapped format with type and value
        if data.has("type") and data.has("value"):
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

# ===== SCENE INSTANTIATION =====

func instance_scene(params):
    var target_scene_path = _normalize_path(params.target_scene_path)
    var source_scene_path = _normalize_path(params.source_scene_path)
    var parent_node_path = params.get("parent_node_path", "root")
    var node_name = params.get("node_name", "")
    var position = params.get("position", null)
    var create_backup = params.get("create_backup", false)
    
    log_debug("Instantiating " + source_scene_path + " into " + target_scene_path)
    
    var backup_path = ""
    if create_backup:
        backup_path = _create_backup(target_scene_path)
        if backup_path == "": printerr("[WARNING] Backup failed")
    
    var target_scene = load(target_scene_path)
    if target_scene == null:
        printerr("[ERROR] Failed to load target scene: " + target_scene_path)
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var root = target_scene.instantiate()
    
    var parent = _find_node_by_path(root, parent_node_path)
    if parent == null:
        printerr("[ERROR] Parent not found: " + parent_node_path)
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var source_scene = load(source_scene_path)
    if source_scene == null:
        printerr("[ERROR] Failed to load source scene: " + source_scene_path)
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    var instance = source_scene.instantiate()
    var instance_name = node_name if node_name != "" else source_scene_path.get_file().replace(".tscn", "")
    instance.name = instance_name
    
    if position != null:
        var pos = _parse_vector(position, 2)
        if pos != null and instance.has_method("set_position"):
            instance.set_position(pos)
    
    parent.add_child(instance)
    instance.owner = root
    
    if _save_packed_scene(root, target_scene_path) != OK:
        printerr("[ERROR] Failed to save scene")
        if backup_path != "": _restore_backup(target_scene_path, backup_path)
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    if backup_path != "": _cleanup_backup(backup_path)
    
    print("MCP_RESULT:" + JSON.stringify({
        "success": true,
        "instance_name": instance_name,
        "source_scene": source_scene_path,
        "target_scene": target_scene_path,
        "parent": parent_node_path
    }))

# ===== SCRIPT CREATION =====

func create_script(params):
    var project_path = params.get("project_path", "res://")
    if not project_path.begins_with("res://"):
        project_path = "res://" + project_path
    
    var script_path = _normalize_path(params.script_path)
    var cls_name = params.get("class_name", "")
    var extends_type = params.get("extends", "Node")
    var template = params.get("template", "node")
    
    log_debug("Creating script: " + script_path)
    
    var abs_path = _to_absolute(script_path)
    var script_dir = abs_path.get_base_dir()
    
    var dir = DirAccess.open(abs_path.get_base_dir().replace("res://", ""))
    if dir == null:
        var parent_dir = DirAccess.open("res://")
        if parent_dir != null:
            var rel_path = script_path.replace("res://", "").get_base_dir()
            parent_dir.make_dir_recursive(rel_path)
    
    var script_template = ""
    
    match template:
        "node":
            script_template = 'extends ' + extends_type + '\n\n' + \
                'func _ready() -> void:\n' + \
                '\tpass\n\n' + \
                'func _process(delta: float) -> void:\n' + \
                '\tpass\n'
        "character":
            script_template = 'extends CharacterBody2D\n\n' + \
                'const SPEED: float = 300.0\n' + \
                'const JUMP_VELOCITY: float = -400.0\n\n' + \
                'var gravity: int = ProjectSettings.get_setting("physics/2d/default_gravity")\n\n' + \
                'func _ready() -> void:\n' + \
                '\tpass\n\n' + \
                'func _physics_process(delta: float) -> void:\n' + \
                '\t# Add gravity\n' + \
                '\tif not is_on_floor():\n' + \
                '\t\tvelocity.y += gravity * delta\n\n' + \
                '\t# Handle jump\n' + \
                '\tif Input.is_action_just_pressed("ui_accept") and is_on_floor():\n' + \
                '\t\tvelocity.y = JUMP_VELOCITY\n\n' + \
                '\t# Get input direction\n' + \
                '\tvar input_dir: float = Input.get_axis("ui_left", "ui_right")\n' + \
                '\tvelocity.x = input_dir * SPEED\n\n' + \
                '\tmove_and_slide()\n'
        "area":
            script_template = 'extends Area2D\n\n' + \
                'signal body_entered(body: Node2D)\n\n' + \
                'func _ready() -> void:\n' + \
                '\tbody_entered.connect(_on_body_entered)\n\n' + \
                'func _on_body_entered(body: Node2D) -> void:\n' + \
                '\tprint("Body entered: ", body.name)\n'
        "resource":
            script_template = 'extends Resource\n\n' + \
                'class_name ' + (cls_name if cls_name != "" else "MyResource") + '\n\n' + \
                '# Export variables\n'
        _:
            script_template = 'extends ' + extends_type + '\n\n' + \
                '# ' + cls_name + '\n\n' + \
                'func _ready() -> void:\n' + \
                '\tpass\n'
    
    var file = FileAccess.open(abs_path, FileAccess.WRITE)
    if file == null:
        printerr("[ERROR] Failed to create script file: " + abs_path)
        quit(1)
    
    file.store_string(script_template)
    file.close()
    
    print("MCP_RESULT:" + JSON.stringify({
        "success": true,
        "script_path": script_path,
        "template": template,
        "extends": extends_type
    }))

func edit_script(params):
    var script_path = _normalize_path(params.script_path)
    var content = params.get("content", "")
    var create_backup = params.get("create_backup", false)
    var append_mode = params.get("append", false)
    
    log_debug("Editing script: " + script_path)
    
    var abs_path = _to_absolute(script_path)
    
    var backup_path = ""
    if create_backup:
        backup_path = _create_script_backup(abs_path)
        if backup_path == "":
            printerr("[ERROR] Failed to create backup")
            quit(1)
    
    var file_mode = FileAccess.WRITE if not append_mode else FileAccess.READ_WRITE
    var file = FileAccess.open(abs_path, file_mode)
    if file == null:
        printerr("[ERROR] Failed to open script file: " + abs_path)
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    if append_mode:
        file.seek_end()
        file.store_string(content)
    else:
        file.store_string(content)
    file.close()
    
    if backup_path != "": _cleanup_backup(backup_path)
    
    print("MCP_RESULT:" + JSON.stringify({
        "success": true,
        "script_path": script_path,
        "bytes_written": content.length(),
        "mode": "append" if append_mode else "replace"
    }))

# ===== 3D SCENE SUPPORT =====

func create_scene_3d(params):
    var scene_path = _normalize_path(params.scene_path)
    var root_type = params.get("root_node_type", "Node3D")
    
    log_debug("Creating 3D scene: " + scene_path + " with root type: " + root_type)
    
    var root = instantiate_node_3d(root_type)
    if root == null:
        printerr("[ERROR] Failed to instantiate root node type: " + root_type)
        quit(1)

    root.name = "root"
    # NOTE: root.owner = root is not allowed in Godot 4.6+ (node cannot own itself)

    var packed = PackedScene.new()
    if packed.pack(root) != OK:
        printerr("[ERROR] Failed to pack scene")
        quit(1)
    
    var scene_dir = scene_path.get_base_dir()
    if scene_dir != "res://":
        var abs_dir = _to_absolute(scene_dir)
        var dir = DirAccess.open("res://")
        if dir != null:
            dir.make_dir_recursive(scene_dir.replace("res://", ""))
    
    var abs_path = _to_absolute(scene_path)
    var error = ResourceSaver.save(packed, abs_path)
    if error != OK:
        printerr("[ERROR] Failed to save scene: " + str(error))
        quit(1)
    
    print("MCP_RESULT:" + JSON.stringify({
        "success": true,
        "scene_path": scene_path,
        "root_type": root_type
    }))

func add_node_3d(params):
    var scene_path = _normalize_path(params.scene_path)
    var parent_path = params.get("parent_node_path", "root")
    var node_type = params.get("node_type", "MeshInstance3D")
    var node_name = params.node_name
    var properties = params.get("properties", {})
    
    log_debug("Adding 3D node: " + node_name + " (" + node_type + ")")
    
    var scene = load(scene_path)
    if scene == null:
        printerr("[ERROR] Failed to load scene")
        quit(1)
    
    var root = scene.instantiate()
    var parent = _find_node_by_path(root, parent_path)
    if parent == null:
        printerr("[ERROR] Parent not found: " + parent_path)
        quit(1)
    
    var new_node = instantiate_node_3d(node_type)
    if new_node == null:
        printerr("[ERROR] Failed to instantiate: " + node_type)
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

func set_node_position_3d(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var position = params.position
    var global = params.get("global", false)
    var create_backup = params.get("create_backup", false)
    
    log_debug("Setting 3D position of '" + node_path + "'")
    
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
    
    var pos = _parse_vector(position, 3)
    if pos == null:
        printerr("[ERROR] Invalid position vector")
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    if global and target.has_method("set_global_position"):
        target.set_global_position(pos)
    elif target.has_method("set_position"):
        target.set_position(pos)
    
    _save_packed_scene(root, scene_path)
    if backup_path != "": _cleanup_backup(backup_path)
    log_info("Position set for '" + node_path + "'")

func set_node_rotation_3d(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var rotation = params.rotation
    var global = params.get("global", false)
    var create_backup = params.get("create_backup", false)
    
    log_debug("Setting 3D rotation of '" + node_path + "'")
    
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
    
    var rot = _parse_vector(rotation, 3)
    if rot == null:
        printerr("[ERROR] Invalid rotation vector")
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    target.rotation = rot
    
    _save_packed_scene(root, scene_path)
    if backup_path != "": _cleanup_backup(backup_path)
    log_info("Rotation set for '" + node_path + "'")

func set_node_scale_3d(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var scale = params.scale
    var create_backup = params.get("create_backup", false)
    
    log_debug("Setting 3D scale of '" + node_path + "'")
    
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
    
    var sc = _parse_vector(scale, 3)
    if sc == null:
        printerr("[ERROR] Invalid scale vector")
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    target.scale = sc
    
    _save_packed_scene(root, scene_path)
    if backup_path != "": _cleanup_backup(backup_path)
    log_info("Scale set for '" + node_path + "'")

func instantiate_node_3d(node_type: String) -> Node:
    match node_type:
        "Node3D": return Node3D.new()
        "MeshInstance3D": return MeshInstance3D.new()
        "StaticBody3D": return StaticBody3D.new()
        "RigidBody3D": return RigidBody3D.new()
        "CharacterBody3D": return CharacterBody3D.new()
        "Area3D": return Area3D.new()
        "Camera3D": return Camera3D.new()
        "DirectionalLight3D": return DirectionalLight3D.new()
        "OmniLight3D": return OmniLight3D.new()
        "SpotLight3D": return SpotLight3D.new()
        "CollisionShape3D": return CollisionShape3D.new()
        "CSGBox3D": return CSGBox3D.new()
        "CSGCylinder3D": return CSGCylinder3D.new()
        "CSGSphere3D": return CSGSphere3D.new()
        "NavigationRegion3D": return NavigationRegion3D.new()
        "WorldEnvironment": return WorldEnvironment.new()
        "Label3D": return Label3D.new()
        "Sprite3D": return Sprite3D.new()
        "AnimatedSprite3D": return AnimatedSprite3D.new()
        "VehicleBody3D": return VehicleBody3D.new()
        "VehicleWheel3D": return VehicleWheel3D.new()
        "Path3D": return Path3D.new()
        "PathFollow3D": return PathFollow3D.new()
        "GPUParticles3D": return GPUParticles3D.new()
        "CPUParticles3D": return CPUParticles3D.new()
        "RayCast3D": return RayCast3D.new()
        "ShapeCast3D": return ShapeCast3D.new()
        "VisibleOnScreenNotifier3D": return VisibleOnScreenNotifier3D.new()
        _:
            printerr("[ERROR] Unknown 3D node type: " + node_type)
            return null

# ===== RESOURCE CREATION =====

# ===== RESOURCE HELPERS =====

# Creates a Resource instance in memory without saving it to disk.
# Returns null and prints [ERROR] if the type is unknown.
func _make_resource_instance(resource_type: String, properties: Dictionary):
    var resource = null
    match resource_type:
        "RectangleShape2D":
            resource = RectangleShape2D.new()
            if properties.has("size"):
                resource.size = _parse_vector(properties.size, 2)
        "CircleShape2D":
            resource = CircleShape2D.new()
            if properties.has("radius"):
                resource.radius = float(properties.radius)
        "CapsuleShape2D":
            resource = CapsuleShape2D.new()
            if properties.has("radius"):
                resource.radius = float(properties.radius)
            if properties.has("height"):
                resource.height = float(properties.height)
        "SegmentShape2D":
            resource = SegmentShape2D.new()
            if properties.has("a"):
                resource.a = _parse_vector(properties.a, 2)
            if properties.has("b"):
                resource.b = _parse_vector(properties.b, 2)
        "ConvexPolygonShape2D":
            resource = ConvexPolygonShape2D.new()
            if properties.has("points"):
                var pts = []
                for p in properties.points:
                    pts.append(_parse_vector(p, 2))
                resource.points = PackedVector2Array(pts)
        "BoxShape3D", "RectangleShape3D":
            resource = BoxShape3D.new()
            if properties.has("size"):
                resource.size = _parse_vector(properties.size, 3)
        "SphereShape3D":
            resource = SphereShape3D.new()
            if properties.has("radius"):
                resource.radius = float(properties.radius)
        "CapsuleShape3D":
            resource = CapsuleShape3D.new()
            if properties.has("radius"):
                resource.radius = float(properties.radius)
            if properties.has("height"):
                resource.height = float(properties.height)
        "CylinderShape3D":
            resource = CylinderShape3D.new()
            if properties.has("radius"):
                resource.radius = float(properties.radius)
            if properties.has("height"):
                resource.height = float(properties.height)
        "WorldBoundaryShape3D", "PlaneShape":
            resource = WorldBoundaryShape3D.new()
            if properties.has("normal"):
                resource.normal = _parse_vector(properties.normal, 3)
            if properties.has("d"):
                resource.d = float(properties.d)
        "WorldEnvironment":
            resource = WorldEnvironment.new()
        "CameraAttributes":
            resource = CameraAttributesPractical.new()
        "Environment":
            resource = Environment.new()
        "NavigationMesh":
            resource = NavigationMesh.new()
        "HeightMapShape3D":
            resource = HeightMapShape3D.new()
            if properties.has("min_height"):
                resource.map_min_height = float(properties.min_height)
            if properties.has("max_height"):
                resource.map_max_height = float(properties.max_height)
        "PhysicsMaterial":
            resource = PhysicsMaterial.new()
            if properties.has("friction"):
                resource.friction = float(properties.friction)
            if properties.has("bounce"):
                resource.bounciness = float(properties.bounce)
            if properties.has("absorbent"):
                resource.absorbent = bool(properties.absorbent)
        "StyleBoxFlat":
            resource = StyleBoxFlat.new()
            if properties.has("bg_color"):
                resource.bg_color = _parse_color(properties.bg_color)
            if properties.has("border_color"):
                resource.border_color = _parse_color(properties.border_color)
            if properties.has("corner_radius"):
                resource.corner_radius_top_left = int(properties.corner_radius)
        "StyleBoxTexture":
            resource = StyleBoxTexture.new()
        "Theme":
            resource = Theme.new()
        "Gradient":
            resource = Gradient.new()
        "GradientTexture2D":
            resource = GradientTexture2D.new()
        _:
            printerr("[ERROR] Unknown resource type: " + resource_type)
            return null
    return resource

func create_resource(params):
    var resource_type = params.get("type", "Shape2D")
    var resource_path = _normalize_path(params.get("path", "resources/new_resource.tres"))
    var properties = params.get("properties", {})

    log_debug("Creating resource: " + resource_type + " at " + resource_path)

    var resource = _make_resource_instance(resource_type, properties)

    if resource == null:
        printerr("[ERROR] Failed to create resource instance")
        quit(1)

    var abs_path = _to_absolute(resource_path)
    var dir_path = abs_path.get_base_dir()
    var dir = DirAccess.open(dir_path)
    if dir == null:
        var parent_dir = DirAccess.open("res://")
        if parent_dir != null:
            parent_dir.make_dir_recursive(resource_path.replace("res://", "").get_base_dir())

    var error = ResourceSaver.save(resource, abs_path)
    if error != OK:
        printerr("[ERROR] Failed to save resource: " + str(error))
        quit(1)

    print("MCP_RESULT:" + JSON.stringify({
        "success": true,
        "type": resource_type,
        "path": resource_path
    }))

# Assigns a resource inline into a scene node property (e.g. shape on CollisionShape2D).
# The resource is embedded as a sub_resource in the .tscn file by Godot's ResourceSaver.
# Use this instead of create_resource when you don't want a standalone .tres file.
func assign_node_resource(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var property = params.get("property", "shape")
    var resource_type = params.resource_type
    var resource_properties = params.get("resource_properties", {})
    var create_backup = params.get("create_backup", false)

    log_debug("Assigning " + resource_type + " to " + node_path + "." + property)

    var backup_path = ""
    if create_backup:
        backup_path = _create_backup(scene_path)
        if backup_path == "":
            printerr("[ERROR] Failed to create backup")
            quit(1)

    var scene = load(scene_path)
    if scene == null:
        printerr("[ERROR] Failed to load scene: " + scene_path)
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)

    var root = scene.instantiate()
    var target = _find_node_by_path(root, node_path)
    if target == null:
        printerr("[ERROR] Node not found: " + node_path)
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)

    var resource = _make_resource_instance(resource_type, resource_properties)
    if resource == null:
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)

    target.set(property, resource)

    if _save_packed_scene(root, scene_path) != OK:
        if backup_path != "": _restore_backup(scene_path, backup_path)
        if backup_path != "": _cleanup_backup(backup_path)
        printerr("[ERROR] Failed to save scene")
        quit(1)

    if backup_path != "": _cleanup_backup(backup_path)
    log_info("Resource '" + resource_type + "' assigned to '" + node_path + "." + property + "'")
    print("MCP_RESULT:" + JSON.stringify({
        "success": true,
        "node_path": node_path,
        "property": property,
        "resource_type": resource_type
    }))

func _parse_color(val) -> Color:
    if typeof(val) == TYPE_COLOR:
        return val
    if typeof(val) == TYPE_STRING:
        return Color(val)
    if typeof(val) == TYPE_DICTIONARY:
        var r = float(val.get("r", 1))
        var g = float(val.get("g", 1))
        var b = float(val.get("b", 1))
        var a = float(val.get("a", 1))
        return Color(r, g, b, a)
    return Color(1, 1, 1, 1)

# ===== RESOURCE LISTING =====

func list_resources(params):
    var folder = params.get("folder", "res://")
    var extensions = params.get("extensions", ["*.tres", "*.tscn", "*.gd", "*.png", "*.jpg", "*.wav", "*.ogg", "*.mp3", "*.glb", "*.gltf"])
    var recursive = params.get("recursive", true)
    
    log_debug("Listing resources in: " + folder)
    
    var results = []
    var abs_folder = _to_absolute(folder)
    
    _scan_folder(abs_folder, extensions, recursive, results)
    
    print("MCP_RESULT:" + JSON.stringify({
        "folder": folder,
        "count": results.size(),
        "resources": results
    }))

func _scan_folder(folder: String, extensions: Array, recursive: bool, results: Array):
    var dir = DirAccess.open(folder)
    if dir == null:
        return
    
    dir.list_dir_begin()
    var file_name = dir.get_next()
    
    while file_name != "":
        if dir.current_is_dir():
            if recursive and file_name != "." and file_name != ".." and file_name != "mcp_backups":
                _scan_folder(folder + "/" + file_name, extensions, recursive, results)
        else:
            for ext in extensions:
                var pattern = ext.replace("*", "")
                if file_name.ends_with(pattern):
                    var full_path = folder + "/" + file_name
                    var res_path = full_path.replace("res://", "").replace(_to_absolute("res://"), "res://")
                    var stat = DirAccess.get_files_at(folder)
                    results.append({
                        "name": file_name,
                        "path": res_path,
                        "type": _guess_resource_type(file_name)
                    })
                    break
        file_name = dir.get_next()
    
    dir.list_dir_end()

func _guess_resource_type(file_name: String) -> String:
    if file_name.ends_with(".tscn"):
        return "PackedScene"
    if file_name.ends_with(".gd"):
        return "GDScript"
    if file_name.ends_with(".tres"):
        return "Resource"
    if file_name.ends_with(".png") or file_name.ends_with(".jpg") or file_name.ends_with(".jpeg"):
        return "Image"
    if file_name.ends_with(".wav") or file_name.ends_with(".ogg") or file_name.ends_with(".mp3"):
        return "AudioStream"
    if file_name.ends_with(".glb") or file_name.ends_with(".gltf"):
        return "Mesh"
    if file_name.ends_with(".obj"):
        return "Mesh"
    return "File"

# ===== RUN SCENE =====

func run_scene(params):
    var scene_path = params.get("scene_path", "")
    var headless = params.get("headless", false)
    
    log_info("Scene would be run: " + scene_path)
    
    print("MCP_RESULT:" + JSON.stringify({
        "success": true,
        "scene_path": scene_path,
        "message": "Use run_project tool to execute scenes"
    }))

# ===== EXPORT PROJECT =====

func export_project(params):
    var export_preset = params.get("preset", "")
    var output_path = params.get("output_path", "")
    var debug = params.get("debug", false)
    
    log_info("Export requested with preset: " + export_preset)
    
    var result = {
        "success": true,
        "preset": export_preset,
        "output_path": output_path,
        "message": "Export requires Godot editor with export templates installed",
        "note": "Use Godot editor GUI or godot --export-release for actual export"
    }
    
    print("MCP_RESULT:" + JSON.stringify(result))

# ===== VALIDATE SCENE =====

func validate_scene(params):
    var scene_path = _normalize_path(params.scene_path)
    
    log_debug("Validating scene: " + scene_path)
    
    var issues = []
    var warnings = []
    
    if not FileAccess.file_exists(_to_absolute(scene_path)):
        issues.append("Scene file does not exist: " + scene_path)
    else:
        var scene = load(scene_path)
        if scene == null:
            issues.append("Failed to load scene")
        else:
            var root = scene.instantiate()
            if root == null:
                issues.append("Failed to instantiate scene")
            else:
                if root.name == "":
                    warnings.append("Root node has empty name")
                
                if not root.has_method("_ready") and not root.has_method("_process"):
                    warnings.append("Root node has no _ready or _process methods")
                
                var children = root.get_children()
                for child in children:
                    if child.name == "":
                        warnings.append("Child node at index " + str(children.find(child)) + " has empty name")
                    
                    if child is CollisionShape2D or child is CollisionShape3D:
                        if child.get_shape() == null:
                            warnings.append("CollisionShape '" + child.name + "' has no shape assigned")
                    
                    if child is Sprite2D or child is Sprite3D:
                        if child.texture == null:
                            warnings.append("Sprite '" + child.name + "' has no texture assigned")
                    
                    if child is Light2D or child is Light3D:
                        if not child.enabled:
                            warnings.append("Light '" + child.name + "' is disabled")
                
                root.free()
    
    var is_valid = issues.size() == 0
    var result = {
        "valid": is_valid,
        "scene_path": scene_path,
        "issues_count": issues.size(),
        "warnings_count": warnings.size(),
        "issues": issues,
        "warnings": warnings
    }
    
    print("MCP_RESULT:" + JSON.stringify(result))

# ===== PROJECT SETTINGS =====

func get_project_setting(params):
    var setting = params.get("setting", "")
    var default = params.get("default", null)
    
    log_debug("Getting project setting: " + setting)
    
    if setting == "":
        printerr("[ERROR] Setting name required")
        quit(1)
    
    var value = ProjectSettings.get_setting(setting, default)
    
    print("MCP_RESULT:" + JSON.stringify({
        "setting": setting,
        "value": _serialize_variant(value),
        "type": typeof(value)
    }))

func set_project_setting(params):
    var setting = params.get("setting", "")
    var value = params.get("value", null)
    var save = params.get("save", true)
    
    log_debug("Setting project setting: " + setting)
    
    if setting == "":
        printerr("[ERROR] Setting name required")
        quit(1)
    
    ProjectSettings.set_setting(setting, value)
    
    if save:
        var error = ProjectSettings.save()
        if error != OK:
            printerr("[ERROR] Failed to save project settings")
            quit(1)
    
    print("MCP_RESULT:" + JSON.stringify({
        "setting": setting,
        "value": _serialize_variant(value),
        "saved": save
    }))

func _serialize_variant(val):
    match typeof(val):
        TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
            return val
        TYPE_VECTOR2:
            return {"x": val.x, "y": val.y}
        TYPE_VECTOR3:
            return {"x": val.x, "y": val.y, "z": val.z}
        TYPE_COLOR:
            return {"r": val.r, "g": val.g, "b": val.b, "a": val.a}
        TYPE_NODE_PATH:
            return val
        TYPE_DICTIONARY:
            return val
        TYPE_ARRAY:
            return val
        _:
            return str(val)

# ===== INPUT ACTIONS =====

func list_input_actions(params):
    var actions = ProjectSettings.get_property_list()
    var input_actions = []
    
    for prop in actions:
        if prop.name.begins_with("input/"):
            var action_name = prop.name.replace("input/", "")
            var events = ProjectSettings.get_setting("input/" + action_name)
            input_actions.append({
                "action": action_name,
                "events_count": events.size() if events else 0
            })
    
    print("MCP_RESULT:" + JSON.stringify({
        "count": input_actions.size(),
        "actions": input_actions
    }))

func create_input_action(params):
    var action = params.get("action", "")
    var events = params.get("events", [])
    
    log_debug("Creating input action: " + action)
    
    if action == "":
        printerr("[ERROR] Action name required")
        quit(1)
    
    if ProjectSettings.has_setting("input/" + action):
        log_info("Action already exists: " + action)
    else:
        ProjectSettings.set_setting("input/" + action, [])
    
    for event_data in events:
        var event = _create_input_event(event_data)
        if event != null:
            var current = ProjectSettings.get_setting("input/" + action)
            current.append(event)
            ProjectSettings.set_setting("input/" + action, current)
    
    ProjectSettings.save()
    
    print("MCP_RESULT:" + JSON.stringify({
        "action": action,
        "events_count": events.size()
    }))

func _create_input_event(event_data):
    match event_data.get("type", "key"):
        "key":
            var key_event = InputEventKey.new()
            if event_data.has("keycode"):
                key_event.keycode = _parse_keycode(event_data.keycode)
            elif event_data.has("scancode"):
                key_event.physical_keycode = _parse_scancode(event_data.scancode)
            return key_event
        "mouse_button":
            var mouse_event = InputEventMouseButton.new()
            mouse_event.button_index = int(event_data.get("button_index", 1))
            mouse_event.pressed = event_data.get("pressed", true)
            return mouse_event
        "joypad_button":
            var joy_event = InputEventJoypadButton.new()
            joy_event.button_index = int(event_data.get("button_index", 0))
            return joy_event
    return null

func _parse_keycode(keycode):
    match str(keycode).to_upper():
        "SPACE": return KEY_SPACE
        "ENTER": return KEY_ENTER
        "SHIFT": return KEY_SHIFT
        "CTRL": return KEY_CTRL
        "ALT": return KEY_ALT
        "UP": return KEY_UP
        "DOWN": return KEY_DOWN
        "LEFT": return KEY_LEFT
        "RIGHT": return KEY_RIGHT
        "W": return KEY_W
        "A": return KEY_A
        "S": return KEY_S
        "D": return KEY_D
        "ESCAPE": return KEY_ESCAPE
        _: return KEY_SPACE

func _parse_scancode(scancode):
    return int(scancode)

# ===== COLLISION LAYERS =====

func add_collision_layer(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var layer = int(params.layer or 1)
    var create_backup = params.get("create_backup", false)
    
    log_debug("Adding collision layer " + str(layer) + " to " + node_path)
    
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
    
    if target is CollisionObject2D:
        target.collision_layer |= (1 << (layer - 1))
    elif target is CollisionObject3D:
        target.collision_layer |= (1 << (layer - 1))
    else:
        printerr("[ERROR] Node is not a collision object")
        if backup_path != "": _cleanup_backup(backup_path)
        quit(1)
    
    _save_packed_scene(root, scene_path)
    if backup_path != "": _cleanup_backup(backup_path)
    
    print("MCP_RESULT:" + JSON.stringify({
        "success": true,
        "node_path": node_path,
        "layer": layer
    }))

func set_collision_mask(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_path = params.node_path
    var mask = int(params.mask or 1)
    var create_backup = params.get("create_backup", false)
    
    log_debug("Setting collision mask " + str(mask) + " on " + node_path)
    
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
    
    if target is CollisionObject2D:
        target.collision_mask = mask
    elif target is CollisionObject3D:
        target.collision_mask = mask
    
    _save_packed_scene(root, scene_path)
    if backup_path != "": _cleanup_backup(backup_path)
    
    print("MCP_RESULT:" + JSON.stringify({
        "success": true,
        "node_path": node_path,
        "mask": mask
    }))

# ===== ASSET IMPORT =====

func import_asset(params):
    var source_path = params.get("source_path", "")
    var dest_path = _normalize_path(params.get("dest_path", ""))
    var import_type = params.get("type", "Texture")
    
    log_debug("Importing asset from " + source_path)
    
    if source_path == "":
        printerr("[ERROR] Source path required")
        quit(1)
    
    if not FileAccess.file_exists(source_path):
        printerr("[ERROR] Source file not found: " + source_path)
        quit(1)
    
    var dest_abs = _to_absolute(dest_path)
    var dest_dir = dest_abs.get_base_dir()
    
    var dir = DirAccess.open(dest_dir)
    if dir == null:
        DirAccess.open("res://").make_dir_recursive(dest_path.get_base_dir())
    
    var dest_file = FileAccess.open(dest_abs, FileAccess.READ)
    if dest_file:
        dest_file.close()
        log_info("File already exists, skipping copy: " + dest_path)
    else:
        DirAccess.copy_absolute(source_path, dest_abs)
        log_info("Asset copied to: " + dest_path)
    
    print("MCP_RESULT:" + JSON.stringify({
        "success": true,
        "source": source_path,
        "dest": dest_path,
        "type": import_type
    }))

# ===== ANIMATION =====

func create_animation(params):
    var scene_path = _normalize_path(params.scene_path)
    var anim_player_path = params.get("anim_player_path", "")
    var anim_name = params.get("animation_name", "new_animation")
    var duration = float(params.get("duration", 1.0))
    var loop = params.get("loop", false)
    
    log_debug("Creating animation: " + anim_name)
    
    var scene = load(scene_path)
    if scene == null:
        printerr("[ERROR] Failed to load scene")
        quit(1)
    
    var root = scene.instantiate()
    var anim_player = _find_node_by_path(root, anim_player_path) if anim_player_path != "" else root.find_child("AnimationPlayer", true, false)
    
    if anim_player == null or not anim_player is AnimationPlayer:
        printerr("[ERROR] AnimationPlayer not found")
        root.free()
        quit(1)
    
    var animation = Animation.new()
    animation.length = duration
    animation.loop_mode = 1 if loop else 0
    
    anim_player.add_animation(anim_name, animation)
    _save_packed_scene(root, scene_path)
    root.free()
    
    print("MCP_RESULT:" + JSON.stringify({
        "success": true,
        "animation_name": anim_name,
        "duration": duration,
        "loop": loop
    }))

func add_animation_track(params):
    var scene_path = _normalize_path(params.scene_path)
    var anim_player_path = params.get("anim_player_path", "")
    var anim_name = params.get("animation_name", "")
    var node_path = params.get("node_path", "")
    var property = params.get("property", "")
    var keyframes = params.get("keyframes", [])
    
    log_debug("Adding track to animation: " + anim_name)
    
    var scene = load(scene_path)
    if scene == null:
        printerr("[ERROR] Failed to load scene")
        quit(1)
    
    var root = scene.instantiate()
    var anim_player = _find_node_by_path(root, anim_player_path) if anim_player_path != "" else root.find_child("AnimationPlayer", true, false)
    
    if anim_player == null or not anim_player is AnimationPlayer:
        printerr("[ERROR] AnimationPlayer not found")
        root.free()
        quit(1)
    
    if not anim_player.has_animation(anim_name):
        printerr("[ERROR] Animation not found: " + anim_name)
        root.free()
        quit(1)
    
    var animation = anim_player.get_animation(anim_name)
    var track_index = animation.add_track(Animation.TYPE_VALUE)
    animation.track_set_path(track_index, node_path + ":" + property)
    
    for kf in keyframes:
        var time = float(kf.get("time", 0))
        var value = kf.get("value", 0)
        var transition = int(kf.get("transition", 1))
        
        animation.track_insert_key(track_index, time, value)
        animation.key_set_transition(track_index, time, transition)
    
    _save_packed_scene(root, scene_path)
    root.free()
    
    print("MCP_RESULT:" + JSON.stringify({
        "success": true,
        "animation": anim_name,
        "track_index": track_index,
        "keys_added": keyframes.size()
    }))

# ===== FIND NODES =====

func find_nodes(params):
    var scene_path = _normalize_path(params.scene_path)
    var node_type = params.get("type", "")
    var name_pattern = params.get("name_pattern", "")
    var recursive = params.get("recursive", true)
    
    log_debug("Finding nodes in: " + scene_path)
    
    var scene = load(scene_path)
    if scene == null:
        printerr("[ERROR] Failed to load scene")
        quit(1)
    
    var root = scene.instantiate()
    var results = []
    
    _collect_nodes_matching(root, node_type, name_pattern, recursive, results)
    
    root.free()
    
    print("MCP_RESULT:" + JSON.stringify({
        "count": results.size(),
        "nodes": results
    }))

func _collect_nodes_matching(node: Node, node_type: String, name_pattern: String, recursive: bool, results: Array):
    var matches = true
    
    if node_type != "":
        var type_name = node.get_class()
        if node_type.to_lower() in type_name.to_lower():
            matches = true
        else:
            matches = false
    
    if name_pattern != "":
        if _match_pattern(node.name, name_pattern):
            matches = matches and true
        else:
            matches = false
    
    if matches and node.name != "root":
        results.append({
            "name": node.name,
            "type": node.get_class(),
            "path": ""
        })
    
    if recursive:
        for child in node.get_children():
            _collect_nodes_matching(child, node_type, name_pattern, recursive, results)

func _match_pattern(name: String, pattern: String) -> bool:
    if pattern == "*":
        return true
    if pattern.begins_with("*") and pattern.ends_with("*"):
        return pattern.trim_prefix("*").trim_suffix("*") in name
    if pattern.begins_with("*"):
        return name.ends_with(pattern.trim_prefix("*"))
    if pattern.ends_with("*"):
        return name.begins_with(pattern.trim_suffix("*"))
    return name == pattern

# ===== EXECUTE GDSCRIPT =====

func execute_gdscript(params):
    var script_content = params.get("script", "")
    var scene_path = params.get("scene_path", "")
    
    log_debug("Executing custom GDScript")
    
    if script_content == "":
        printerr("[ERROR] Script content required")
        quit(1)
    
    var script = GDScript.new()
    script.source_code = script_content
    
    var error = script.reload()
    if error != OK:
        printerr("[ERROR] Failed to compile script")
        quit(1)
    
    var result = null
    if scene_path != "":
        var scene = load(scene_path)
        if scene != null:
            var root = scene.instantiate()
            script.set_instance_binding_value(root, "root", root)
            result = script.new()
        else:
            result = script.new()
    else:
        result = script.new()
    
    if result != null and result is Node:
        result.free()
    
    print("MCP_RESULT:" + JSON.stringify({
        "success": true,
        "executed": true
    }))

# ===== SNAPSHOT & COMPARE =====

func snapshot_scene(params):
    var scene_path = _normalize_path(params.scene_path)
    var output_path = params.get("output_path", scene_path + ".snapshot.json")
    
    log_debug("Creating snapshot of: " + scene_path)
    
    var scene = load(scene_path)
    if scene == null:
        printerr("[ERROR] Failed to load scene")
        quit(1)
    
    var root = scene.instantiate()
    var snapshot = _node_to_dict(root)
    root.free()
    
    var abs_output = _to_absolute(output_path)
    var file = FileAccess.open(abs_output, FileAccess.WRITE)
    if file == null:
        printerr("[ERROR] Failed to create snapshot file")
        quit(1)
    
    file.store_string(JSON.stringify(snapshot, "  "))
    file.close()
    
    print("MCP_RESULT:" + JSON.stringify({
        "success": true,
        "scene_path": scene_path,
        "snapshot_path": output_path
    }))

func compare_scenes(params):
    var scene_a = _normalize_path(params.get("scene_a", ""))
    var scene_b = _normalize_path(params.get("scene_b", ""))
    
    log_debug("Comparing scenes")
    
    if scene_a == "" or scene_b == "":
        printerr("[ERROR] Both scene_a and scene_b required")
        quit(1)
    
    var a = load(scene_a)
    var b = load(scene_b)
    
    if a == null or b == null:
        printerr("[ERROR] Failed to load scenes")
        quit(1)
    
    var root_a = a.instantiate()
    var root_b = b.instantiate()
    
    var diff = _compare_nodes(root_a, root_b)
    
    root_a.free()
    root_b.free()
    
    print("MCP_RESULT:" + JSON.stringify({
        "scene_a": scene_a,
        "scene_b": scene_b,
        "identical": diff.size() == 0,
        "differences": diff
    }))

func _node_to_dict(node: Node) -> Dictionary:
    var dict = {
        "name": node.name,
        "type": node.get_class(),
        "properties": {},
        "children": []
    }
    
    for prop in node.get_property_list():
        var name = prop.name
        if not name.begins_with("_") and not name in ["script"]:
            dict.properties[name] = _serialize_variant(node.get(name))
    
    for child in node.get_children():
        dict.children.append(_node_to_dict(child))
    
    return dict

func _compare_nodes(node_a: Node, node_b: Node, path: String = "") -> Array:
    var differences = []
    var current_path = path + "/" + node_a.name if path != "" else node_a.name
    
    if node_a.get_class() != node_b.get_class():
        differences.append({
            "path": current_path,
            "type": "class_mismatch",
            "a": node_a.get_class(),
            "b": node_b.get_class()
        })
    
    for prop in node_a.get_property_list():
        var name = prop.name
        if not name.begins_with("_") and name in ["position", "rotation", "scale", "modulate"]:
            var val_a = node_a.get(name)
            var val_b = node_b.get(name)
            if val_a != val_b:
                differences.append({
                    "path": current_path,
                    "type": "property_diff",
                    "property": name,
                    "a": _serialize_variant(val_a),
                    "b": _serialize_variant(val_b)
                })
    
    var children_a = node_a.get_children()
    var children_b = node_b.get_children()
    
    if children_a.size() != children_b.size():
        differences.append({
            "path": current_path,
            "type": "children_count_diff",
            "a": children_a.size(),
            "b": children_b.size()
        })
    
    return differences
