extends Node

const PORT = 9090

var server: TCPServer
var client: StreamPeerTCP
var running = false
var buffer = ""

signal debug_command_received(command: Dictionary)

func _ready():
	start_server()

func start_server():
	server = TCPServer.new()
	var err = server.listen(PORT, "127.0.0.1")
	if err != OK:
		print("[MCP Debug] Failed to start server on port ", PORT)
		return
	
	running = true
	print("[MCP Debug] Server started on port ", PORT)
	_process_commands()

func _process_commands():
	while running:
		if server.is_connection_available():
			client = server.take_connection()
			print("[MCP Debug] Client connected")
		
		if client:
			var status = client.get_status()
			if status == StreamPeerTCP.STATUS_CONNECTED:
				# Try to get available data
				var available = client.get_available_bytes()
				if available > 0:
					var data = client.get_string(available)
					buffer += data
					
					# Process complete JSON messages (newline delimited)
					while buffer.find("\n") != -1:
						var line_end = buffer.find("\n")
						var line = buffer.substr(0, line_end)
						buffer = buffer.substr(line_end + 1)
						
						if line.strip_edges().is_empty():
							continue
						
						var result = _process_json_message(line)
						var response = JSON.stringify(result) + "\n"
						client.send_text(response)
						
						# Close after response (single-shot mode)
						client.disconnect_from_host()
						client = null
						break
			elif status == StreamPeerTCP.STATUS_DISCONNECTED:
				client = null
		
		await get_tree().process_frame

func _process_json_message(json_str: String) -> Dictionary:
	var json = JSON.new()
	var error = json.parse(json_str)
	
	if error != OK:
		return {"error": "Invalid JSON", "details": json.get_error_message()}
	
	var request = json.get_data()
	if typeof(request) != TYPE_DICTIONARY:
		return {"error": "Expected JSON object"}
	
	var command = request.get("command", "")
	var params = request.get("params", {})
	var id = request.get("id", 1)
	
	match command:
		"list_nodes":
			return _handle_list_nodes(params, id)
		"get_node_property":
			return _handle_get_node_property(params, id)
		"set_node_property":
			return _handle_set_node_property(params, id)
		"call_method":
			return _handle_call_method(params, id)
		"get_tree_info":
			return _handle_get_tree_info(params, id)
		"find_node":
			return _handle_find_node(params, id)
		"get_node_info":
			return _handle_get_node_info(params, id)
		"ping":
			return {"id": id, "result": {"pong": true}}
		_:
			return {"id": id, "error": "Unknown command: " + command}

func _handle_list_nodes(params: Dictionary, id: int) -> Dictionary:
	var root = get_tree().root
	var nodes = []
	_collect_nodes(root, "", nodes, params.get("max_depth", 10))
	return {"id": id, "result": {"nodes": nodes, "count": nodes.size()}}

func _collect_nodes(node: Node, path: String, results: Array, max_depth: int):
	if path.is_empty():
		path = node.name
	else:
		path = path + "/" + node.name
	
	results.append({
		"name": node.name,
		"path": path,
		"type": node.get_class()
	})
	
	if path.split("/").size() < max_depth:
		for child in node.get_children():
			_collect_nodes(child, path, results, max_depth)

func _handle_get_node_property(params: Dictionary, id: int) -> Dictionary:
	var node_path = params.get("node_path", "")
	var property = params.get("property", "")
	
	var node = _find_node(node_path)
	if node == null:
		return {"id": id, "error": "Node not found: " + node_path}
	
	if not property in node:
		return {"id": id, "error": "Property not found: " + property}
	
	var value = node.get(property)
	return {"id": id, "result": {"property": property, "value": _serialize(value), "type": typeof(value)}}

func _handle_set_node_property(params: Dictionary, id: int) -> Dictionary:
	var node_path = params.get("node_path", "")
	var property = params.get("property", "")
	var value = params.get("value")
	
	var node = _find_node(node_path)
	if node == null:
		return {"id": id, "error": "Node not found: " + node_path}
	
	if not property in node:
		return {"id": id, "error": "Property not found: " + property}
	
	node.set(property, value)
	return {"id": id, "result": {"success": true, "property": property}}

func _handle_call_method(params: Dictionary, id: int) -> Dictionary:
	var node_path = params.get("node_path", "")
	var method = params.get("method", "")
	var args = params.get("args", [])
	
	var node = _find_node_by_path(node_path)
	if node == null:
		return {"id": id, "error": "Node not found: " + node_path}
	
	if not node.has_method(method):
		return {"id": id, "error": "Method not found: " + method}
	
	var result = node.callv(method, _deserialize_args(args))
	return {"id": id, "result": {"success": true, "return_value": _serialize_value(result)}}

func _handle_get_tree_info(params: Dictionary, id: int) -> Dictionary:
	return {
		"id": id,
		"result": {
			"root_name": get_tree().root.name,
			"root_path": get_tree().root.get_path(),
			"node_count": _count_nodes(get_tree().root),
			"paused": get_tree().paused,
			"current_scene": get_tree().current_scene.name if get_tree().current_scene else null
		}
	}

func _count_nodes(node: Node) -> int:
	var count = 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count

func _handle_find_node(params: Dictionary, id: int) -> Dictionary:
	var pattern = params.get("pattern", "")
	var node_type = params.get("type", "")
	var results = []
	
	_find_nodes_matching(get_tree().root, pattern, node_type, results, 0, 10)
	return {"id": id, "result": {"nodes": results, "count": results.size()}}

func _find_nodes_matching(node: Node, pattern: String, node_type: String, results: Array, depth: int, max_depth: int):
	var name_matches = pattern.is_empty() or node.name.contains(pattern)
	var type_matches = node_type.is_empty() or node.get_class() == node_type
	
	if name_matches and type_matches:
		results.append({
			"name": node.name,
			"path": node.get_path(),
			"type": node.get_class()
		})
	
	if depth < max_depth:
		for child in node.get_children():
			_find_nodes_matching(child, pattern, node_type, results, depth + 1, max_depth)

func _handle_get_node_info(params: Dictionary, id: int) -> Dictionary:
	var node_path = params.get("node_path", "")
	
	var node = _find_node_by_path(node_path)
	if node == null:
		return {"id": id, "error": "Node not found: " + node_path}
	
	var properties = []
	for prop in node.get_property_list():
		if prop.usage & PROPERTY_USAGE_STORAGE:
			properties.append({
				"name": prop.name,
				"type": prop.type
			})
	
	var methods = []
	for method in node.get_method_list():
		methods.append(method.name)
	
	return {
		"id": id,
		"result": {
			"name": node.name,
			"path": node.get_path(),
			"type": node.get_class(),
			"properties": properties,
			"methods": methods,
			"groups": node.get_groups()
		}
	}

func _find_node_by_path(path: String) -> Node:
	if path.is_empty() or path == "root":
		return get_tree().root
	
	# Handle absolute paths like /root/root/Paddle
	return get_tree().root.get_node(path)

func _serialize_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL:
			return null
		TYPE_BOOL:
			return value
		TYPE_INT:
			return value
		TYPE_FLOAT:
			return value
		TYPE_STRING:
			return value
		TYPE_VECTOR2:
			return {"x": value.x, "y": value.y, "_type": "Vector2"}
		TYPE_VECTOR2I:
			return {"x": value.x, "y": value.y, "_type": "Vector2i"}
		TYPE_VECTOR3:
			return {"x": value.x, "y": value.y, "z": value.z, "_type": "Vector3"}
		TYPE_VECTOR3I:
			return {"x": value.x, "y": value.y, "z": value.z, "_type": "Vector3i"}
		TYPE_COLOR:
			return {"r": value.r, "g": value.g, "b": value.b, "a": value.a, "_type": "Color"}
		TYPE_ARRAY:
			return value.map(func(v): return _serialize_value(v))
		TYPE_DICTIONARY:
			var result = {}
			for k in value:
				result[k] = _serialize_value(value[k])
			return result
		_:
			return str(value)

func _deserialize_value(value: Variant, node: Node, property: String) -> Variant:
	if value == null:
		return null
	
	if typeof(value) == TYPE_DICTIONARY:
		if value.has("_type"):
			match value["_type"]:
				"Vector2":
					return Vector2(value.get("x", 0), value.get("y", 0))
				"Vector2i":
					return Vector2i(value.get("x", 0), value.get("y", 0))
				"Vector3":
					return Vector3(value.get("x", 0), value.get("y", 0), value.get("z", 0))
				"Vector3i":
					return Vector3i(value.get("x", 0), value.get("y", 0), value.get("z", 0))
				"Color":
					return Color(value.get("r", 1), value.get("g", 1), value.get("b", 1), value.get("a", 1))
		
		# Try to infer type from property
		if node and node.has(property):
			var prop_info = node.get_property_list().filter(func(p): return p.name == property)
			if prop_info.size() > 0:
				var prop_type = prop_info[0].type
				match prop_type:
					TYPE_VECTOR2:
						return Vector2(value.get("x", 0), value.get("y", 0))
					TYPE_VECTOR3:
						return Vector3(value.get("x", 0), value.get("y", 0), value.get("z", 0))
	
	return value

func _deserialize_args(args: Array) -> Array:
	return args.map(func(v): return _deserialize_value(v, null, ""))