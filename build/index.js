#!/usr/bin/env node
import { fileURLToPath } from 'url';
import { join, dirname, basename, normalize } from 'path';
import { existsSync, readdirSync, statSync } from 'fs';
import { spawn, execFile } from 'child_process';
import { promisify } from 'util';
import { createHash } from 'crypto';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ErrorCode, ListToolsRequestSchema, McpError, } from '@modelcontextprotocol/sdk/types.js';
const DEBUG = process.env.DEBUG === 'true';
const execFileAsync = promisify(execFile);
const COMPRESSION_LEVEL = (process.env.COMPRESSION_LEVEL || 'medium');
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
class GodotMCP {
    server;
    activeProcess = null;
    godotPath = null;
    operationsScriptPath;
    validatedPaths = new Map();
    sceneCache = new Map();
    pathRegistry = new Map();
    pathIdCounter = 0;
    paramMap = {
        project_path: 'projectPath', scene_path: 'scenePath',
        root_node_type: 'rootNodeType', parent_node_path: 'parentNodePath',
        node_type: 'nodeType', node_name: 'nodeName',
        texture_path: 'texturePath', node_path: 'nodePath',
        output_path: 'outputPath', mesh_item_names: 'meshItemNames',
        new_path: 'newPath', file_path: 'filePath',
        directory: 'directory', recursive: 'recursive',
        new_name: 'newName', property: 'property',
        value: 'value', script_path: 'scriptPath',
        exported_properties: 'exportedProperties', properties: 'properties',
        enable_rollback: 'enableRollback', create_backup: 'createBackup',
    };
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    toolDefinitions = [];
    constructor() {
        this.operationsScriptPath = join(__dirname, 'scripts', 'godot_operations.gd');
        this.server = new Server({ name: 'mcpgodot', version: '1.0.0' }, { capabilities: { tools: {} } });
        this.setupTools();
        this.server.onerror = (e) => console.error('[MCP Error]', e);
        process.on('SIGINT', () => this.cleanup());
    }
    log(msg) {
        if (DEBUG)
            console.error(`[DEBUG] ${msg}`);
    }
    async detectGodotPath() {
        if (this.godotPath && await this.isValidGodotPath(this.godotPath))
            return;
        if (process.env.GODOT_PATH) {
            const p = normalize(process.env.GODOT_PATH);
            if (await this.isValidGodotPath(p)) {
                this.godotPath = p;
                return;
            }
        }
        const platform = process.platform;
        const candidates = platform === 'darwin'
            ? ['/Applications/Godot.app/Contents/MacOS/Godot', '/Applications/Godot_4.app/Contents/MacOS/Godot']
            : platform === 'win32'
                ? ['C:\\Program Files\\Godot\\Godot.exe', 'C:\\Program Files (x86)\\Godot\\Godot.exe']
                : ['/usr/bin/godot', '/usr/local/bin/godot', `${process.env.HOME}/.local/bin/godot`];
        for (const p of candidates) {
            if (await this.isValidGodotPath(p)) {
                this.godotPath = normalize(p);
                return;
            }
        }
        if (platform === 'linux')
            this.godotPath = 'godot';
        else if (platform === 'win32')
            this.godotPath = 'C:\\Program Files\\Godot\\Godot.exe';
        else
            this.godotPath = '/Applications/Godot.app/Contents/MacOS/Godot';
    }
    async isValidGodotPath(p) {
        if (this.validatedPaths.has(p))
            return this.validatedPaths.get(p);
        try {
            if (p !== 'godot' && !existsSync(p)) {
                this.validatedPaths.set(p, false);
                return false;
            }
            await execFileAsync(p, ['--version']);
            this.validatedPaths.set(p, true);
            return true;
        }
        catch {
            this.validatedPaths.set(p, false);
            return false;
        }
    }
    async ensureGodotPath() {
        if (!this.godotPath)
            await this.detectGodotPath();
        if (!this.godotPath)
            throw new Error('Godot not found');
        if (!(await this.isValidGodotPath(this.godotPath))) {
            throw new Error(`Invalid Godot path: ${this.godotPath}`);
        }
    }
    validatePath(path) {
        return !!path && !path.includes('..');
    }
    normParams(params) {
        const result = {};
        for (const k in params) {
            let key = k;
            if (k.includes('_') && this.paramMap[k])
                key = this.paramMap[k];
            if (typeof params[k] === 'object' && params[k] !== null && !Array.isArray(params[k])) {
                result[key] = this.normParams(params[k]);
            }
            else {
                result[key] = params[k];
            }
        }
        return result;
    }
    computeFileHash(filePath) {
        try {
            const stat = statSync(filePath);
            const content = existsSync(filePath) ? require('fs').readFileSync(filePath, 'utf8') : '';
            return createHash('md5').update(content + stat.mtimeMs).digest('hex');
        }
        catch {
            return 'unknown';
        }
    }
    getCachedScene(scenePath, forceReload = false) {
        const cached = this.sceneCache.get(scenePath);
        if (!cached || forceReload)
            return null;
        if (Date.now() - cached.timestamp > 60000)
            return null;
        return cached;
    }
    setCachedScene(scenePath, data) {
        const absPath = join(process.cwd(), scenePath.replace('res://', ''));
        this.sceneCache.set(scenePath, {
            hash: this.computeFileHash(absPath),
            data,
            timestamp: Date.now()
        });
    }
    compressResponse(obj) {
        if (COMPRESSION_LEVEL === 'none')
            return obj;
        if (COMPRESSION_LEVEL === 'max')
            return obj;
        if (Array.isArray(obj)) {
            return obj.map(item => this.compressResponse(item));
        }
        if (typeof obj === 'object' && obj !== null) {
            const result = {};
            const input = obj;
            if (COMPRESSION_LEVEL === 'high') {
                for (const [k, v] of Object.entries(input)) {
                    const shortKey = this.shortenKey(k);
                    if (shortKey !== k)
                        result[shortKey] = v;
                    else
                        result[k] = v;
                }
            }
            else {
                for (const [k, v] of Object.entries(input)) {
                    const shortKey = this.shortenKey(k);
                    if (shortKey !== k)
                        result[shortKey] = this.compressResponse(v);
                    else
                        result[k] = this.compressResponse(v);
                }
            }
            return result;
        }
        return obj;
    }
    shortenKey(key) {
        const map = {
            scene_path: 'p', node_path: 'n', node_name: 'nn', node_type: 'nt',
            project_path: 'pp', parent_node_path: 'pn', texture_path: 'tp',
            root_node_type: 'rt', new_path: 'np', file_path: 'fp',
            mesh_item_names: 'mi', exported_properties: 'ep', create_backup: 'cb',
            enable_rollback: 'er', recursive: 'rec', scenePath: 'sp', nodePath: 'np',
            nodeName: 'nn', nodeType: 'nt', projectPath: 'pp', parentNodePath: 'pnp',
            texturePath: 'tp', rootNodeType: 'rt', newPath: 'np', filePath: 'fp',
            meshItemNames: 'mi', exportedProperties: 'ep', createBackup: 'cb', enableRollback: 'er'
        };
        return map[key] || key;
    }
    async executeOp(op, params, projectPath) {
        await this.ensureGodotPath();
        const snakeParams = {};
        for (const k in params) {
            const snake = k.replace(/[A-Z]/g, c => `_${c.toLowerCase()}`);
            snakeParams[snake] = params[k];
        }
        const args = [
            '--headless', '--path', projectPath,
            '--script', this.operationsScriptPath,
            op, JSON.stringify(snakeParams),
            '--debug-godot'
        ];
        this.log(`Exec: ${this.godotPath} ${args.join(' ')}`);
        try {
            const { stdout, stderr } = await execFileAsync(this.godotPath, args);
            return { stdout: stdout ?? '', stderr: stderr ?? '' };
        }
        catch (e) {
            if (e instanceof Error && 'stdout' in e) {
                return { stdout: e.stdout ?? '', stderr: e.stderr ?? '' };
            }
            throw e;
        }
    }
    error(msg, solutions = []) {
        const content = [{ type: 'text', text: msg }];
        if (solutions.length) {
            content.push({ type: 'text', text: 'Solutions:\n- ' + solutions.join('\n- ') });
        }
        return { content, isError: true };
    }
    checkProject(path) {
        return existsSync(join(path, 'project.godot'));
    }
    setupTools() {
        const baseTools = [
            // Editor
            { name: 'launch_editor', desc: 'Launch Godot editor', props: { projectPath: 'string' } },
            { name: 'run_project', desc: 'Run Godot project', props: { projectPath: 'string', scene: 'string?' } },
            { name: 'get_debug_output', desc: 'Get debug output', props: {} },
            { name: 'stop_project', desc: 'Stop running project', props: {} },
            { name: 'get_godot_version', desc: 'Get Godot version', props: {} },
            { name: 'list_projects', desc: 'List Godot projects', props: { directory: 'string', recursive: 'boolean?' } },
            { name: 'get_project_info', desc: 'Get project info', props: { projectPath: 'string' } },
            // Scene
            { name: 'create_scene', desc: 'Create new scene', props: { projectPath: 'string', scenePath: 'string', rootNodeType: 'string?' } },
            { name: 'add_node', desc: 'Add node to scene', props: { projectPath: 'string', scenePath: 'string', nodeType: 'string', nodeName: 'string', parentNodePath: 'string?', properties: 'object?' } },
            { name: 'add_node_with_script', desc: 'Add node with script', props: { projectPath: 'string', scenePath: 'string', nodeName: 'string', nodeType: 'string?', scriptPath: 'string', parentNodePath: 'string?' } },
            { name: 'remove_node', desc: 'Remove node', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', createBackup: 'boolean?' } },
            { name: 'duplicate_node', desc: 'Duplicate node', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', newName: 'string', createBackup: 'boolean?' } },
            { name: 'list_nodes', desc: 'List nodes in scene', props: { projectPath: 'string', scenePath: 'string', fields: 'array?', maxDepth: 'number?', recursive: 'boolean?' } },
            { name: 'batch_operations', desc: 'Batch operations', props: { projectPath: 'string', scenePath: 'string', operations: 'array', enableRollback: 'boolean?' } },
            { name: 'load_sprite', desc: 'Load sprite texture', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', texturePath: 'string' } },
            { name: 'save_scene', desc: 'Save scene', props: { projectPath: 'string', scenePath: 'string', newPath: 'string?' } },
            // Node Info
            { name: 'get_node_info', desc: 'Get node info', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string' } },
            { name: 'get_node_property', desc: 'Get node property', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', property: 'string' } },
            { name: 'set_node_property', desc: 'Set node property', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', property: 'string', value: 'unknown', createBackup: 'boolean?' } },
            // Transform
            { name: 'get_node_transform', desc: 'Get node transform', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', global: 'boolean?' } },
            { name: 'set_node_position', desc: 'Set node position', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', position: 'object', global: 'boolean?', createBackup: 'boolean?' } },
            { name: 'set_node_rotation', desc: 'Set node rotation', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', rotation: 'number', global: 'boolean?', createBackup: 'boolean?' } },
            { name: 'set_node_scale', desc: 'Set node scale', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', scale: 'object', createBackup: 'boolean?' } },
            // Hierarchy
            { name: 'get_parent_path', desc: 'Get parent path', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string' } },
            { name: 'get_children', desc: 'Get children', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', recursive: 'boolean?', includeTypes: 'boolean?' } },
            { name: 'has_child', desc: 'Check if has child', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', childName: 'string' } },
            // Signals
            { name: 'connect_signal', desc: 'Connect signal', props: { projectPath: 'string', scenePath: 'string', fromNode: 'string', signal: 'string', toNode: 'string', method: 'string', createBackup: 'boolean?' } },
            { name: 'disconnect_signal', desc: 'Disconnect signal', props: { projectPath: 'string', scenePath: 'string', fromNode: 'string', signal: 'string', toNode: 'string', method: 'string', createBackup: 'boolean?' } },
            { name: 'emit_node_signal', desc: 'Emit signal', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', signal: 'string', args: 'array?' } },
            // Groups
            { name: 'get_groups', desc: 'Get node groups', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string' } },
            { name: 'add_to_group', desc: 'Add to group', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', group: 'string', createBackup: 'boolean?' } },
            { name: 'remove_from_group', desc: 'Remove from group', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', group: 'string', createBackup: 'boolean?' } },
            { name: 'call_group_method', desc: 'Call method on group', props: { projectPath: 'string', scenePath: 'string', group: 'string', method: 'string', args: 'array?' } },
            // UID
            { name: 'get_uid', desc: 'Get UID for file', props: { projectPath: 'string', filePath: 'string' } },
            { name: 'resave_resources', desc: 'Resave resources', props: { projectPath: 'string?' } },
            // Scene & Script
            { name: 'instance_scene', desc: 'Instance scene', props: { projectPath: 'string', targetScenePath: 'string', sourceScenePath: 'string', parentNodePath: 'string?', nodeName: 'string?', position: 'object?' } },
            { name: 'create_script', desc: 'Create script', props: { projectPath: 'string', scriptPath: 'string', className: 'string?', extends: 'string?', template: 'string?' } },
        ];
        this.toolDefinitions = baseTools;
        const getTools = () => {
            return baseTools.map(t => this.tool(t.name, t.desc, t.props));
        };
        const getCompressedTools = () => {
            return baseTools.map(t => {
                const schema = this.tool(t.name, t.desc, t.props);
                if (COMPRESSION_LEVEL === 'max') {
                    return { name: t.name, description: '', inputSchema: schema.inputSchema };
                }
                return {
                    name: t.name,
                    description: COMPRESSION_LEVEL === 'high' ? t.desc.split('.')[0] + '.' : t.desc,
                    inputSchema: schema.inputSchema
                };
            });
        };
        this.server.setRequestHandler(ListToolsRequestSchema, async () => {
            const tools = (COMPRESSION_LEVEL === 'high' || COMPRESSION_LEVEL === 'max') ? getCompressedTools() : getTools();
            return { tools };
        });
        this.server.setRequestHandler(CallToolRequestSchema, async (req) => {
            this.log(`Tool: ${req.params.name}`);
            const args = this.normParams(req.params.arguments || {});
            switch (req.params.name) {
                // Editor
                case 'launch_editor': return this.handleLaunchEditor(args);
                case 'run_project': return this.handleRunProject(args);
                case 'get_debug_output': return this.handleGetDebugOutput();
                case 'stop_project': return this.handleStopProject();
                case 'get_godot_version': return this.handleGetGodotVersion();
                case 'list_projects': return this.handleListProjects(args);
                case 'get_project_info': return this.handleGetProjectInfo(args);
                // Scene
                case 'create_scene': return this.handleCreateScene(args);
                case 'add_node': return this.handleAddNode(args);
                case 'add_node_with_script': return this.handleAddNodeWithScript(args);
                case 'remove_node': return this.handleRemoveNode(args);
                case 'duplicate_node': return this.handleDuplicateNode(args);
                case 'list_nodes': return this.handleListNodes(args);
                case 'batch_operations': return this.handleBatchOperations(args);
                case 'load_sprite': return this.handleLoadSprite(args);
                case 'save_scene': return this.handleSaveScene(args);
                case 'modify_node_property': return this.handleModifyProperty(args);
                // Node Info
                case 'get_node_info': return this.handleGenericOp('get_node_info', args);
                case 'get_node_property': return this.handleGenericOp('get_node_property', args);
                case 'set_node_property': return this.handleGenericOp('set_node_property', args);
                // Transform
                case 'get_node_transform': return this.handleGenericOp('get_node_transform', args);
                case 'set_node_position': return this.handleGenericOp('set_node_position', args);
                case 'set_node_rotation': return this.handleGenericOp('set_node_rotation', args);
                case 'set_node_scale': return this.handleGenericOp('set_node_scale', args);
                // Hierarchy
                case 'get_parent_path': return this.handleGenericOp('get_parent_path', args);
                case 'get_children': return this.handleGenericOp('get_children', args);
                case 'has_child': return this.handleGenericOp('has_child', args);
                // Signals
                case 'connect_signal': return this.handleGenericOp('connect_signal', args);
                case 'disconnect_signal': return this.handleGenericOp('disconnect_signal', args);
                case 'emit_node_signal': return this.handleGenericOp('emit_node_signal', args);
                case 'get_groups': return this.handleGenericOp('get_groups', args);
                case 'add_to_group': return this.handleGenericOp('add_to_group', args);
                case 'remove_from_group': return this.handleGenericOp('remove_from_group', args);
                case 'call_group_method': return this.handleGenericOp('call_group_method', args);
                // UID
                case 'get_uid': return this.handleGetUid(args);
                case 'resave_resources': return this.handleResaveResources(args);
                // Scene & Script
                case 'instance_scene': return this.handleInstanceScene(args);
                case 'create_script': return this.handleCreateScript(args);
                default: throw new McpError(ErrorCode.MethodNotFound, `Unknown tool: ${req.params.name}`);
            }
        });
    }
    tool(name, desc, props) {
        return {
            name,
            description: desc,
            inputSchema: {
                type: 'object',
                properties: Object.fromEntries(Object.entries(props).map(([k, v]) => [k, { type: String(v).endsWith('?') ? String(v).slice(0, -1) : String(v), description: k }])),
                required: Object.entries(props).filter(([, v]) => !String(v).endsWith('?')).map(([k]) => k)
            }
        };
    }
    async handleLaunchEditor(args) {
        if (!args.projectPath || !this.validatePath(args.projectPath)) {
            return this.error('Invalid project path');
        }
        if (!this.checkProject(args.projectPath)) {
            return this.error('Not a valid Godot project');
        }
        await this.ensureGodotPath();
        spawn(this.godotPath, ['-e', '--path', args.projectPath], { stdio: 'ignore' });
        return { content: [{ type: 'text', text: `Editor launched for ${args.projectPath}` }] };
    }
    async handleRunProject(args) {
        if (!args.projectPath || !this.validatePath(args.projectPath)) {
            return this.error('Invalid project path');
        }
        if (!this.checkProject(args.projectPath)) {
            return this.error('Not a valid Godot project');
        }
        await this.ensureGodotPath();
        if (this.activeProcess)
            this.activeProcess.process.kill();
        const cmdArgs = ['-d', '--path', args.projectPath];
        if (args.scene)
            cmdArgs.push(args.scene);
        const proc = spawn(this.godotPath, cmdArgs, { stdio: 'pipe' });
        const output = [], errors = [];
        proc.stdout?.on('data', (d) => output.push(...d.toString().split('\n')));
        proc.stderr?.on('data', (d) => errors.push(...d.toString().split('\n')));
        proc.on('exit', () => { if (this.activeProcess?.process === proc)
            this.activeProcess = null; });
        this.activeProcess = { process: proc, output, errors };
        return { content: [{ type: 'text', text: 'Project started in debug mode' }] };
    }
    handleGetDebugOutput() {
        if (!this.activeProcess)
            return this.error('No active process', ['Run run_project first']);
        return { content: [{ type: 'text', text: JSON.stringify({ output: this.activeProcess.output, errors: this.activeProcess.errors }, null, 2) }] };
    }
    handleStopProject() {
        if (!this.activeProcess)
            return this.error('No active process');
        this.activeProcess.process.kill();
        const r = { message: 'Stopped', output: this.activeProcess.output, errors: this.activeProcess.errors };
        this.activeProcess = null;
        return { content: [{ type: 'text', text: JSON.stringify(r) }] };
    }
    async handleGetGodotVersion() {
        await this.ensureGodotPath();
        const { stdout } = await execFileAsync(this.godotPath, ['--version']);
        return { content: [{ type: 'text', text: stdout.trim() }] };
    }
    handleListProjects(args) {
        const dir = args.directory;
        if (!dir || !this.validatePath(dir))
            return this.error('Invalid directory');
        if (!existsSync(dir))
            return this.error('Directory not found');
        const findProjects = (d, rec) => {
            const projects = [];
            if (existsSync(join(d, 'project.godot'))) {
                projects.push({ path: d, name: basename(d) });
            }
            if (rec || !projects.length) {
                for (const e of readdirSync(d, { withFileTypes: true })) {
                    if (e.isDirectory() && !e.name.startsWith('.')) {
                        projects.push(...findProjects(join(d, e.name), rec));
                    }
                }
            }
            return projects;
        };
        return { content: [{ type: 'text', text: JSON.stringify(findProjects(dir, args.recursive === true), null, 2) }] };
    }
    async handleGetProjectInfo(args) {
        if (!args.projectPath || !this.validatePath(args.projectPath)) {
            return this.error('Invalid project path');
        }
        if (!this.checkProject(args.projectPath)) {
            return this.error('Not a valid Godot project');
        }
        await this.ensureGodotPath();
        const { stdout } = await execFileAsync(this.godotPath, ['--version']);
        const countFiles = (d) => {
            const counts = { scenes: 0, scripts: 0, assets: 0, other: 0 };
            for (const e of readdirSync(d, { withFileTypes: true })) {
                if (e.name.startsWith('.'))
                    continue;
                if (e.isDirectory()) {
                    const sub = countFiles(join(d, e.name));
                    for (const k of Object.keys(sub))
                        counts[k] += sub[k];
                }
                else {
                    const ext = e.name.split('.').pop()?.toLowerCase();
                    if (ext === 'tscn')
                        counts.scenes++;
                    else if (['gd', 'gdscript', 'cs'].includes(ext ?? ''))
                        counts.scripts++;
                    else if (['png', 'jpg', 'webp', 'wav', 'mp3', 'ttf'].includes(ext ?? ''))
                        counts.assets++;
                    else
                        counts.other++;
                }
            }
            return counts;
        };
        const structure = countFiles(args.projectPath);
        return { content: [{ type: 'text', text: JSON.stringify({ name: basename(args.projectPath), godotVersion: stdout.trim(), structure }, null, 2) }] };
    }
    async handleCreateScene(args) {
        if (!args.projectPath || !args.scenePath)
            return this.error('Missing required params');
        if (!this.checkProject(args.projectPath))
            return this.error('Invalid project');
        const { stdout, stderr } = await this.executeOp('create_scene', {
            scene_path: args.scenePath, root_node_type: args.rootNodeType || 'Node2D'
        }, args.projectPath);
        if (stderr.includes('ERROR'))
            return this.error(`Failed: ${stderr}`);
        return { content: [{ type: 'text', text: `Scene created: ${args.scenePath}\n${stdout}` }] };
    }
    async handleAddNode(args) {
        if (!args.projectPath || !args.scenePath || !args.nodeType || !args.nodeName) {
            return this.error('Missing required params');
        }
        if (!this.checkProject(args.projectPath))
            return this.error('Invalid project');
        const { stdout, stderr } = await this.executeOp('add_node', {
            scene_path: args.scenePath, node_type: args.nodeType, node_name: args.nodeName,
            parent_node_path: args.parentNodePath || 'root', properties: args.properties || {}
        }, args.projectPath);
        if (stderr.includes('ERROR'))
            return this.error(`Failed: ${stderr}`);
        return { content: [{ type: 'text', text: `Node added: ${args.nodeName}\n${stdout}` }] };
    }
    async handleAddNodeWithScript(args) {
        if (!args.projectPath || !args.scenePath || !args.nodeName) {
            return this.error('Missing required params');
        }
        const { stdout, stderr } = await this.executeOp('add_node_with_script', {
            scene_path: args.scenePath, node_name: args.nodeName, node_type: args.nodeType || 'Node',
            script_path: args.scriptPath, parent_node_path: args.parentNodePath || 'root',
            properties: args.properties || {}, exported_properties: args.exportedProperties || []
        }, args.projectPath);
        if (stderr.includes('ERROR'))
            return this.error(`Failed: ${stderr}`);
        return { content: [{ type: 'text', text: `Node with script added: ${args.nodeName}\n${stdout}` }] };
    }
    async handleModifyProperty(args) {
        if (!args.projectPath || !args.scenePath || !args.nodePath || !args.property) {
            return this.error('Missing required params');
        }
        const { stdout, stderr } = await this.executeOp('modify_node_property', {
            scene_path: args.scenePath, node_path: args.nodePath,
            property: args.property, value: args.value, create_backup: args.createBackup !== false
        }, args.projectPath);
        if (stderr.includes('ERROR'))
            return this.error(`Failed: ${stderr}`);
        return { content: [{ type: 'text', text: `Property modified: ${args.property}\n${stdout}` }] };
    }
    async handleRemoveNode(args) {
        if (!args.projectPath || !args.scenePath || !args.nodePath) {
            return this.error('Missing required params');
        }
        const { stdout, stderr } = await this.executeOp('remove_node', {
            scene_path: args.scenePath, node_path: args.nodePath, create_backup: args.createBackup !== false
        }, args.projectPath);
        if (stderr.includes('ERROR'))
            return this.error(`Failed: ${stderr}`);
        return { content: [{ type: 'text', text: `Node removed: ${args.nodePath}\n${stdout}` }] };
    }
    async handleDuplicateNode(args) {
        if (!args.projectPath || !args.scenePath || !args.nodePath || !args.newName) {
            return this.error('Missing required params');
        }
        const { stdout, stderr } = await this.executeOp('duplicate_node', {
            scene_path: args.scenePath, node_path: args.nodePath,
            new_name: args.newName, create_backup: args.createBackup !== false
        }, args.projectPath);
        if (stderr.includes('ERROR'))
            return this.error(`Failed: ${stderr}`);
        return { content: [{ type: 'text', text: `Node duplicated as ${args.newName}\n${stdout}` }] };
    }
    async handleListNodes(args) {
        if (!args.projectPath || !args.scenePath)
            return this.error('Missing required params');
        const scenePath = args.scenePath;
        const forceReload = args.forceReload === true;
        const cached = this.getCachedScene(scenePath, forceReload);
        if (cached && !forceReload) {
            let result = cached.data;
            if (args.fields && Array.isArray(args.fields)) {
                result = this.filterFields(result, args.fields);
            }
            if (COMPRESSION_LEVEL !== 'none') {
                result = this.compressResponse(result);
            }
            return { content: [{ type: 'text', text: JSON.stringify(result) }] };
        }
        const { stdout } = await this.executeOp('list_nodes', {
            scene_path: scenePath,
            recursive: args.recursive !== false,
            fields: args.fields || [],
            max_depth: args.maxDepth || 999
        }, args.projectPath);
        try {
            const data = JSON.parse(stdout);
            this.setCachedScene(scenePath, data);
            let result = data;
            if (args.fields && Array.isArray(args.fields)) {
                result = this.filterFields(result, args.fields);
            }
            if (COMPRESSION_LEVEL !== 'none') {
                result = this.compressResponse(result);
            }
            return { content: [{ type: 'text', text: JSON.stringify(result) }] };
        }
        catch {
            return { content: [{ type: 'text', text: stdout }] };
        }
    }
    filterFields(data, fields) {
        if (Array.isArray(data)) {
            return data.map(item => this.filterFields(item, fields));
        }
        if (typeof data === 'object' && data !== null) {
            const result = {};
            for (const [k, v] of Object.entries(data)) {
                if (fields.includes(k)) {
                    result[k] = v;
                }
            }
            return result;
        }
        return data;
    }
    async handleBatchOperations(args) {
        if (!args.projectPath || !args.scenePath || !Array.isArray(args.operations)) {
            return this.error('Missing required params: projectPath, scenePath, operations[]');
        }
        const { stdout, stderr } = await this.executeOp('batch_operations', {
            scene_path: args.scenePath, operations: args.operations,
            enable_rollback: args.enableRollback !== false
        }, args.projectPath);
        if (stderr.includes('ERROR'))
            return this.error(`Batch failed: ${stderr}`);
        return { content: [{ type: 'text', text: stdout || `Batch complete\n${stderr}` }] };
    }
    async handleLoadSprite(args) {
        if (!args.projectPath || !args.scenePath || !args.nodePath || !args.texturePath) {
            return this.error('Missing required params');
        }
        const { stdout, stderr } = await this.executeOp('load_sprite', {
            scene_path: args.scenePath, node_path: args.nodePath, texture_path: args.texturePath
        }, args.projectPath);
        if (stderr.includes('ERROR'))
            return this.error(`Failed: ${stderr}`);
        return { content: [{ type: 'text', text: `Sprite loaded: ${args.texturePath}\n${stdout}` }] };
    }
    async handleSaveScene(args) {
        if (!args.projectPath || !args.scenePath)
            return this.error('Missing required params');
        const { stdout, stderr } = await this.executeOp('save_scene', {
            scene_path: args.scenePath, new_path: args.newPath || ''
        }, args.projectPath);
        if (stderr.includes('ERROR'))
            return this.error(`Failed: ${stderr}`);
        return { content: [{ type: 'text', text: `Scene saved\n${stdout}` }] };
    }
    async handleGetUid(args) {
        if (!args.projectPath || !args.filePath)
            return this.error('Missing required params');
        if (!this.checkProject(args.projectPath))
            return this.error('Invalid project');
        const { stdout } = await this.executeOp('get_uid', { file_path: args.filePath }, args.projectPath);
        return { content: [{ type: 'text', text: stdout }] };
    }
    async handleGenericOp(operation, args) {
        if (!args.projectPath || !args.scenePath) {
            return this.error('Missing required params: projectPath, scenePath');
        }
        const params = {
            scene_path: args.scenePath
        };
        // Copy all other params
        for (const [k, v] of Object.entries(args)) {
            if (k !== 'projectPath' && k !== 'scenePath') {
                const snakeKey = k.replace(/[A-Z]/g, c => `_${c.toLowerCase()}`);
                params[snakeKey] = v;
            }
        }
        const { stdout, stderr } = await this.executeOp(operation, params, args.projectPath);
        // Parse MCP_RESULT if present
        const mcpMatch = stdout.match(/MCP_RESULT:(.+)$/);
        if (mcpMatch) {
            try {
                const data = JSON.parse(mcpMatch[1]);
                return { content: [{ type: 'text', text: JSON.stringify(data) }] };
            }
            catch {
                return { content: [{ type: 'text', text: mcpMatch[1] }] };
            }
        }
        if (stderr.includes('ERROR'))
            return this.error(`Failed: ${stderr}`);
        return { content: [{ type: 'text', text: stdout || stderr }] };
    }
    async handleResaveResources(args) {
        const projectPath = args.projectPath || '';
        const { stdout } = await this.executeOp('resave_resources', { project_path: projectPath }, projectPath || '.');
        return { content: [{ type: 'text', text: stdout }] };
    }
    async handleInstanceScene(args) {
        if (!args.projectPath || !args.targetScenePath || !args.sourceScenePath) {
            return this.error('Missing required params: projectPath, targetScenePath, sourceScenePath');
        }
        const params = {
            target_scene_path: args.targetScenePath,
            source_scene_path: args.sourceScenePath,
        };
        if (args.parentNodePath)
            params.parent_node_path = args.parentNodePath;
        if (args.nodeName)
            params.node_name = args.nodeName;
        if (args.position)
            params.position = args.position;
        const { stdout, stderr } = await this.executeOp('instance_scene', params, args.projectPath);
        if (stderr.includes('ERROR'))
            return this.error(`Failed: ${stderr}`);
        return { content: [{ type: 'text', text: stdout }] };
    }
    async handleCreateScript(args) {
        if (!args.projectPath || !args.scriptPath) {
            return this.error('Missing required params: projectPath, scriptPath');
        }
        const params = {
            project_path: args.projectPath,
            script_path: args.scriptPath,
        };
        if (args.className)
            params.class_name = args.className;
        if (args.extends)
            params.extends = args.extends;
        if (args.template)
            params.template = args.template;
        const { stdout, stderr } = await this.executeOp('create_script', params, args.projectPath);
        if (stderr.includes('ERROR'))
            return this.error(`Failed: ${stderr}`);
        return { content: [{ type: 'text', text: stdout }] };
    }
    async cleanup() {
        if (this.activeProcess)
            this.activeProcess.process.kill();
        await this.server.close();
    }
    async run() {
        try {
            await this.detectGodotPath();
            if (!this.godotPath) {
                console.error('[SERVER] Godot not found');
                process.exit(1);
            }
            console.error(`[SERVER] Using Godot: ${this.godotPath}`);
            const transport = new StdioServerTransport();
            await this.server.connect(transport);
            console.error('[SERVER] mcpgodot running on stdio');
        }
        catch (e) {
            console.error('[SERVER] Failed to start:', e);
            process.exit(1);
        }
    }
}
const server = new GodotMCP();
server.run().catch(e => {
    console.error('Fatal:', e);
    process.exit(1);
});
