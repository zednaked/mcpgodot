#!/usr/bin/env node

import { fileURLToPath } from 'url';
import { join, dirname, basename, normalize } from 'path';
import { existsSync, readdirSync, statSync } from 'fs';
import { spawn, execFile } from 'child_process';
import { promisify } from 'util';
import { createHash } from 'crypto';

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ErrorCode,
  ListToolsRequestSchema,
  McpError,
} from '@modelcontextprotocol/sdk/types.js';

const DEBUG = process.env.DEBUG === 'true';
const execFileAsync = promisify(execFile);
const COMPRESSION_LEVEL = (process.env.COMPRESSION_LEVEL || 'medium') as 'none' | 'low' | 'medium' | 'high' | 'max';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

interface GodotProcess {
  process: ReturnType<typeof spawn>;
  output: string[];
  errors: string[];
}

interface SceneCache {
  hash: string;
  data: unknown;
  timestamp: number;
}

class GodotMCP {
  private server: Server;
  private activeProcess: GodotProcess | null = null;
  private godotPath: string | null = null;
  private operationsScriptPath: string;
  private validatedPaths = new Map<string, boolean>();
  private sceneCache = new Map<string, SceneCache>();
  private pathRegistry = new Map<string, string>();
  private pathIdCounter = 0;

  private paramMap: Record<string, string> = {
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
  private toolDefinitions: Array<{name: string; desc: string; props: Record<string, any>}> = [];

  constructor() {
    this.operationsScriptPath = join(__dirname, 'scripts', 'godot_operations.gd');
    
    this.server = new Server(
      { name: 'mcpgodot', version: '1.0.0' },
      { capabilities: { tools: {} } }
    );

    this.setupTools();
    this.server.onerror = (e) => console.error('[MCP Error]', e);
    process.on('SIGINT', () => this.cleanup());
  }

  private log(msg: string) {
    if (DEBUG) console.error(`[DEBUG] ${msg}`);
  }

  private async detectGodotPath() {
    if (this.godotPath && await this.isValidGodotPath(this.godotPath)) return;

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

    if (platform === 'linux') this.godotPath = 'godot';
    else if (platform === 'win32') this.godotPath = 'C:\\Program Files\\Godot\\Godot.exe';
    else this.godotPath = '/Applications/Godot.app/Contents/MacOS/Godot';
  }

  private async isValidGodotPath(p: string): Promise<boolean> {
    if (this.validatedPaths.has(p)) return this.validatedPaths.get(p)!;
    try {
      if (p !== 'godot' && !existsSync(p)) {
        this.validatedPaths.set(p, false);
        return false;
      }
      await execFileAsync(p, ['--version']);
      this.validatedPaths.set(p, true);
      return true;
    } catch {
      this.validatedPaths.set(p, false);
      return false;
    }
  }

  private async ensureGodotPath() {
    if (!this.godotPath) await this.detectGodotPath();
    if (!this.godotPath) throw new Error('Godot not found');
    if (!(await this.isValidGodotPath(this.godotPath))) {
      throw new Error(`Invalid Godot path: ${this.godotPath}`);
    }
  }

  private validatePath(path: string): boolean {
    return !!path && !path.includes('..');
  }

  private normParams(params: Record<string, unknown>): Record<string, unknown> {
    const result: Record<string, unknown> = {};
    for (const k in params) {
      let key = k;
      if (k.includes('_') && this.paramMap[k]) key = this.paramMap[k];
      if (typeof params[k] === 'object' && params[k] !== null && !Array.isArray(params[k])) {
        result[key] = this.normParams(params[k] as Record<string, unknown>);
      } else {
        result[key] = params[k];
      }
    }
    return result;
  }

  private computeFileHash(filePath: string): string {
    try {
      const stat = statSync(filePath);
      const content = existsSync(filePath) ? require('fs').readFileSync(filePath, 'utf8') : '';
      return createHash('md5').update(content + stat.mtimeMs).digest('hex');
    } catch {
      return 'unknown';
    }
  }

  private getCachedScene(scenePath: string, forceReload = false): SceneCache | null {
    const cached = this.sceneCache.get(scenePath);
    if (!cached || forceReload) return null;
    if (Date.now() - cached.timestamp > 60000) return null;
    return cached;
  }

  private setCachedScene(scenePath: string, data: unknown) {
    const absPath = join(process.cwd(), scenePath.replace('res://', ''));
    this.sceneCache.set(scenePath, {
      hash: this.computeFileHash(absPath),
      data,
      timestamp: Date.now()
    });
  }

  private compressResponse(obj: unknown): unknown {
    if (COMPRESSION_LEVEL === 'none') return obj;
    if (COMPRESSION_LEVEL === 'max') return obj;

    if (Array.isArray(obj)) {
      return obj.map(item => this.compressResponse(item));
    }

    if (typeof obj === 'object' && obj !== null) {
      const result: Record<string, unknown> = {};
      const input = obj as Record<string, unknown>;

      if (COMPRESSION_LEVEL === 'high') {
        for (const [k, v] of Object.entries(input)) {
          const shortKey = this.shortenKey(k);
          if (shortKey !== k) result[shortKey] = v;
          else result[k] = v;
        }
      } else {
        for (const [k, v] of Object.entries(input)) {
          const shortKey = this.shortenKey(k);
          if (shortKey !== k) result[shortKey] = this.compressResponse(v);
          else result[k] = this.compressResponse(v);
        }
      }
      return result;
    }

    return obj;
  }

  private shortenKey(key: string): string {
    const map: Record<string, string> = {
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

  private async executeOp(op: string, params: Record<string, unknown>, projectPath: string) {
    await this.ensureGodotPath();
    
    const snakeParams: Record<string, unknown> = {};
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
      const { stdout, stderr } = await execFileAsync(this.godotPath!, args);
      return { stdout: stdout ?? '', stderr: stderr ?? '' };
    } catch (e: unknown) {
      if (e instanceof Error && 'stdout' in e) {
        return { stdout: (e as Record<string, string>).stdout ?? '', stderr: (e as Record<string, string>).stderr ?? '' };
      }
      throw e;
    }
  }

  private error(msg: string, solutions: string[] = []): { content: [{type: string, text: string}, ...{type: string, text: string}[]]; isError: boolean } {
    const content: [{type: string, text: string}, ...{type: string, text: string}[]] = [{ type: 'text', text: msg }];
    if (solutions.length) {
      content.push({ type: 'text', text: 'Solutions:\n- ' + solutions.join('\n- ') });
    }
    return { content, isError: true };
  }

  private checkProject(path: string): boolean {
    return existsSync(join(path, 'project.godot'));
  }

  private setupTools() {
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
      { name: 'move_node', desc: 'Move/reparent node or reorder within parent', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', newParentPath: 'string?', newIndex: 'number?', createBackup: 'boolean?' } },
      { name: 'list_nodes', desc: 'List nodes in scene. fields: name,type,path,script,children_count,properties (default: name+type+path+script). maxDepth: 0=unlimited.', props: { projectPath: 'string', scenePath: 'string', fields: 'array?', maxDepth: 'number?', recursive: 'boolean?' } },
      { name: 'batch_operations', desc: 'Batch multiple scene operations in one Godot process. Each op: {operation, ...params flat}. Accepted ops: add_node(nodeType,nodeName,parentPath,properties{}), set_node_property(nodePath,property,value), remove_node(nodePath), set_position(nodePath,position{x,y}). enableRollback default false.', props: { projectPath: 'string', scenePath: 'string', operations: 'array', enableRollback: 'boolean?' } },
      { name: 'generate_nodes', desc: 'Bulk-create N nodes in one call. Each node: {name,type,parent,properties{}}. Auto-converts: position/size as {x,y}→Vector2, color as [r,g,b,a]→Color, polygon as [x0,y0,x1,y1,...]→PackedVector2Array. Ideal for terrain tiles, markers, grids.', props: { projectPath: 'string', scenePath: 'string', nodes: 'array', createBackup: 'boolean?' } },
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
      { name: 'attach_script', desc: 'Attach script to node', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', scriptPath: 'string', createBackup: 'boolean?' } },
      { name: 'edit_script', desc: 'Edit script content', props: { projectPath: 'string', scriptPath: 'string', content: 'string', append: 'boolean?', createBackup: 'boolean?' } },
      { name: 'create_resource', desc: 'Create resource', props: { projectPath: 'string', type: 'string', path: 'string?', properties: 'object?' } },
      { name: 'assign_node_resource', desc: 'Assign inline resource to node property (embeds as sub_resource in .tscn — use for shapes on CollisionShape2D, materials, etc.)', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', resourceType: 'string', property: 'string?', resourceProperties: 'object?', createBackup: 'boolean?' } },
      { name: 'list_resources', desc: 'List project resources', props: { projectPath: 'string', folder: 'string?', extensions: 'array?', recursive: 'boolean?' } },
      { name: 'run_scene', desc: 'Run scene', props: { projectPath: 'string', scenePath: 'string?' } },
      // 3D Scene
      { name: 'create_scene_3d', desc: 'Create 3D scene', props: { projectPath: 'string', scenePath: 'string', rootNodeType: 'string?' } },
      { name: 'add_node_3d', desc: 'Add 3D node', props: { projectPath: 'string', scenePath: 'string', nodeType: 'string', nodeName: 'string', parentNodePath: 'string?', properties: 'object?' } },
      { name: 'set_node_position_3d', desc: 'Set 3D position', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', position: 'object', global: 'boolean?', createBackup: 'boolean?' } },
      { name: 'set_node_rotation_3d', desc: 'Set 3D rotation', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', rotation: 'object', global: 'boolean?', createBackup: 'boolean?' } },
      { name: 'set_node_scale_3d', desc: 'Set 3D scale', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', scale: 'object', createBackup: 'boolean?' } },
      { name: 'export_project', desc: 'Export project', props: { projectPath: 'string', preset: 'string?', outputPath: 'string?', debug: 'boolean?' } },
      { name: 'validate_scene', desc: 'Validate scene', props: { projectPath: 'string', scenePath: 'string' } },
      // Project Settings
      { name: 'get_project_setting', desc: 'Get project setting', props: { projectPath: 'string', setting: 'string', default: 'unknown?' } },
      { name: 'set_project_setting', desc: 'Set project setting', props: { projectPath: 'string', setting: 'string', value: 'unknown', save: 'boolean?' } },
      // Input
      { name: 'list_input_actions', desc: 'List input actions', props: { projectPath: 'string' } },
      { name: 'create_input_action', desc: 'Create input action', props: { projectPath: 'string', action: 'string', events: 'array?' } },
      // Collision
      { name: 'add_collision_layer', desc: 'Add collision layer', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', layer: 'number', createBackup: 'boolean?' } },
      { name: 'set_collision_mask', desc: 'Set collision mask', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', mask: 'number', createBackup: 'boolean?' } },
      // Assets
      { name: 'import_asset', desc: 'Import asset', props: { projectPath: 'string', sourcePath: 'string', destPath: 'string', type: 'string?' } },
      // Animation
      { name: 'create_animation', desc: 'Create animation', props: { projectPath: 'string', scenePath: 'string', animationName: 'string', duration: 'number?', loop: 'boolean?', animPlayerPath: 'string?' } },
      { name: 'add_animation_track', desc: 'Add animation track', props: { projectPath: 'string', scenePath: 'string', animationName: 'string', nodePath: 'string', property: 'string', keyframes: 'array', animPlayerPath: 'string?' } },
      // Find
      { name: 'find_nodes', desc: 'Find nodes', props: { projectPath: 'string', scenePath: 'string', type: 'string?', namePattern: 'string?', recursive: 'boolean?' } },
      // Script
      { name: 'execute_gdscript', desc: 'Execute GDScript', props: { projectPath: 'string', script: 'string', scenePath: 'string?' } },
      // Snapshot
      { name: 'snapshot_scene', desc: 'Snapshot scene', props: { projectPath: 'string', scenePath: 'string', outputPath: 'string?' } },
      { name: 'compare_scenes', desc: 'Compare scenes', props: { projectPath: 'string', sceneA: 'string', sceneB: 'string' } },
      // Runtime Debug
      { name: 'runtime_connect', desc: 'Connect to running game debug server', props: { projectPath: 'string', port: 'number?' } },
      { name: 'runtime_list_nodes', desc: 'List nodes in running game', props: { projectPath: 'string', maxDepth: 'number?' } },
      { name: 'runtime_get_property', desc: 'Get property from running game node', props: { projectPath: 'string', nodePath: 'string', property: 'string' } },
      { name: 'runtime_set_property', desc: 'Set property in running game', props: { projectPath: 'string', nodePath: 'string', property: 'string', value: 'unknown' } },
      { name: 'runtime_call_method', desc: 'Call method on running game node', props: { projectPath: 'string', nodePath: 'string', method: 'string', args: 'array?' } },
      { name: 'runtime_get_tree_info', desc: 'Get running game tree info', props: { projectPath: 'string' } },
      { name: 'runtime_find_node', desc: 'Find node in running game', props: { projectPath: 'string', pattern: 'string?', type: 'string?' } },
      { name: 'runtime_get_node_info', desc: 'Get node info from running game', props: { projectPath: 'string', nodePath: 'string' } },
      { name: 'runtime_start_debug', desc: 'Start game with debug server', props: { projectPath: 'string', scenePath: 'string?' } },
      // UI Layout
      { name: 'set_layout', desc: 'Set UI layout (anchors, offsets, size) in one call', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', layout: 'object', createBackup: 'boolean?' } },
      { name: 'apply_layout_preset', desc: 'Apply named layout preset (top_bar, bottom_right, full_rect, etc)', props: { projectPath: 'string', scenePath: 'string', nodePath: 'string', preset: 'string', createBackup: 'boolean?' } },
      { name: 'copy_layout', desc: 'Copy layout from one node to another', props: { projectPath: 'string', scenePath: 'string', fromNode: 'string', toNode: 'string', createBackup: 'boolean?' } },
      { name: 'list_layout_presets', desc: 'List available layout presets', props: {} },
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
      const args = this.normParams((req.params.arguments as Record<string, unknown>) || {});
      
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
        case 'attach_script': return this.handleAttachScript(args);
        case 'remove_node': return this.handleRemoveNode(args);
        case 'duplicate_node': return this.handleDuplicateNode(args);
        case 'move_node': return this.handleMoveNode(args);
        case 'list_nodes': return this.handleListNodes(args);
        case 'batch_operations': return this.handleBatchOperations(args);
        case 'generate_nodes': return this.handleGenerateNodes(args);
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
        case 'edit_script': return this.handleEditScript(args);
        case 'create_resource': return this.handleCreateResource(args);
        case 'assign_node_resource': return this.handleGenericOp('assign_node_resource', args);
        case 'list_resources': return this.handleListResources(args);
        case 'run_scene': return this.handleRunScene(args);
        // 3D Scene
        case 'create_scene_3d': return this.handleCreateScene(args);
        case 'add_node_3d': return this.handleAddNode(args);
        case 'set_node_position_3d': return this.handleGenericOp('set_node_position_3d', args);
        case 'set_node_rotation_3d': return this.handleGenericOp('set_node_rotation_3d', args);
        case 'set_node_scale_3d': return this.handleGenericOp('set_node_scale_3d', args);
        // Export & Validate
        case 'export_project': return this.handleExportProject(args);
        case 'validate_scene': return this.handleValidateScene(args);
        // Project Settings
        case 'get_project_setting': return this.handleGetProjectSetting(args);
        case 'set_project_setting': return this.handleSetProjectSetting(args);
        // Input
        case 'list_input_actions': return this.handleGenericOp('list_input_actions', args);
        case 'create_input_action': return this.handleGenericOp('create_input_action', args);
        // Collision
        case 'add_collision_layer': return this.handleGenericOp('add_collision_layer', args);
        case 'set_collision_mask': return this.handleGenericOp('set_collision_mask', args);
        // Assets
        case 'import_asset': return this.handleGenericOp('import_asset', args);
        // Animation
        case 'create_animation': return this.handleGenericOp('create_animation', args);
        case 'add_animation_track': return this.handleGenericOp('add_animation_track', args);
        // Find
        case 'find_nodes': return this.handleFindNodes(args);
        // Script
        case 'execute_gdscript': return this.handleGenericOp('execute_gdscript', args);
        // Snapshot
        case 'snapshot_scene': return this.handleGenericOp('snapshot_scene', args);
        case 'compare_scenes': return this.handleGenericOp('compare_scenes', args);
        // Runtime Debug
        case 'runtime_connect': return this.handleRuntimeConnect(args);
        case 'runtime_list_nodes': return this.handleRuntimeListNodes(args);
        case 'runtime_get_property': return this.handleRuntimeGetProperty(args);
        case 'runtime_set_property': return this.handleRuntimeSetProperty(args);
        case 'runtime_call_method': return this.handleRuntimeCallMethod(args);
        case 'runtime_get_tree_info': return this.handleRuntimeGetTreeInfo(args);
        case 'runtime_find_node': return this.handleRuntimeFindNode(args);
        case 'runtime_get_node_info': return this.handleRuntimeGetNodeInfo(args);
        case 'runtime_start_debug': return this.handleRuntimeStartDebug(args);
        case 'set_layout': return this.handleSetLayout(args);
        case 'apply_layout_preset': return this.handleApplyLayoutPreset(args);
        case 'copy_layout': return this.handleCopyLayout(args);
        case 'list_layout_presets': return this.handleListLayoutPresets();
        default: throw new McpError(ErrorCode.MethodNotFound, `Unknown tool: ${req.params.name}`);
      }
    });
  }

  private tool(name: string, desc: string, props: Record<string, any>) {
    return {
      name,
      description: desc,
      inputSchema: {
        type: 'object',
        properties: Object.fromEntries(
          Object.entries(props).map(([k, v]) => {
            const t = String(v).endsWith('?') ? String(v).slice(0, -1) : String(v);
            return [k, t === 'unknown' ? { description: k } : { type: t, description: k }];
          })
        ),
        required: Object.entries(props).filter(([, v]) => !String(v).endsWith('?')).map(([k]) => k)
      }
    };
  }

  private async handleLaunchEditor(args: Record<string, unknown>) {
    if (!args.projectPath || !this.validatePath(args.projectPath as string)) {
      return this.error('Invalid project path');
    }
    if (!this.checkProject(args.projectPath as string)) {
      return this.error('Not a valid Godot project');
    }
    await this.ensureGodotPath();
    spawn(this.godotPath!, ['-e', '--path', args.projectPath as string], { stdio: 'ignore' });
    return { content: [{ type: 'text', text: `Editor launched for ${args.projectPath}` }] };
  }

  private async handleRunProject(args: Record<string, unknown>) {
    if (!args.projectPath || !this.validatePath(args.projectPath as string)) {
      return this.error('Invalid project path');
    }
    if (!this.checkProject(args.projectPath as string)) {
      return this.error('Not a valid Godot project');
    }
    await this.ensureGodotPath();
    if (this.activeProcess) this.activeProcess.process.kill();
    
    const cmdArgs = ['-d', '--path', args.projectPath as string];
    if (args.scene) cmdArgs.push(args.scene as string);

    const proc = spawn(this.godotPath!, cmdArgs, { stdio: 'pipe' });
    const output: string[] = [], errors: string[] = [];

    proc.stdout?.on('data', (d: Buffer) => output.push(...d.toString().split('\n')));
    proc.stderr?.on('data', (d: Buffer) => errors.push(...d.toString().split('\n')));
    proc.on('exit', () => { if (this.activeProcess?.process === proc) this.activeProcess = null; });

    this.activeProcess = { process: proc, output, errors };
    return { content: [{ type: 'text', text: 'Project started in debug mode' }] };
  }

  private handleGetDebugOutput() {
    if (!this.activeProcess) return this.error('No active process', ['Run run_project first']);
    return { content: [{ type: 'text', text: JSON.stringify({ output: this.activeProcess.output, errors: this.activeProcess.errors }, null, 2) }] };
  }

  private handleStopProject() {
    if (!this.activeProcess) return this.error('No active process');
    this.activeProcess.process.kill();
    const r = { message: 'Stopped', output: this.activeProcess.output, errors: this.activeProcess.errors };
    this.activeProcess = null;
    return { content: [{ type: 'text', text: JSON.stringify(r) }] };
  }

  private async handleGetGodotVersion() {
    await this.ensureGodotPath();
    const { stdout } = await execFileAsync(this.godotPath!, ['--version']);
    return { content: [{ type: 'text', text: stdout.trim() }] };
  }

  private handleListProjects(args: Record<string, unknown>) {
    const dir = args.directory as string;
    if (!dir || !this.validatePath(dir)) return this.error('Invalid directory');
    if (!existsSync(dir)) return this.error('Directory not found');

    const findProjects = (d: string, rec: boolean): { path: string; name: string }[] => {
      const projects: { path: string; name: string }[] = [];
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

  private async handleGetProjectInfo(args: Record<string, unknown>) {
    if (!args.projectPath || !this.validatePath(args.projectPath as string)) {
      return this.error('Invalid project path');
    }
    if (!this.checkProject(args.projectPath as string)) {
      return this.error('Not a valid Godot project');
    }
    await this.ensureGodotPath();
    const { stdout } = await execFileAsync(this.godotPath!, ['--version']);
    
    const countFiles = (d: string): Record<string, number> => {
      const counts: Record<string, number> = { scenes: 0, scripts: 0, assets: 0, other: 0 };
      for (const e of readdirSync(d, { withFileTypes: true })) {
        if (e.name.startsWith('.')) continue;
        if (e.isDirectory()) {
          const sub = countFiles(join(d, e.name));
          for (const k of Object.keys(sub)) counts[k] += sub[k];
        } else {
          const ext = e.name.split('.').pop()?.toLowerCase();
          if (ext === 'tscn') counts.scenes++;
          else if (['gd', 'gdscript', 'cs'].includes(ext ?? '')) counts.scripts++;
          else if (['png', 'jpg', 'webp', 'wav', 'mp3', 'ttf'].includes(ext ?? '')) counts.assets++;
          else counts.other++;
        }
      }
      return counts;
    };

    const structure = countFiles(args.projectPath as string);
    return { content: [{ type: 'text', text: JSON.stringify({ name: basename(args.projectPath as string), godotVersion: stdout.trim(), structure }, null, 2) }] };
  }

  private async handleCreateScene(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scenePath) return this.error('Missing required params');
    if (!this.checkProject(args.projectPath as string)) return this.error('Invalid project');
    
    const { stdout, stderr } = await this.executeOp('create_scene', {
      scene_path: args.scenePath, root_node_type: args.rootNodeType || 'Node2D'
    }, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    return { content: [{ type: 'text', text: `Scene created: ${args.scenePath}\n${stdout}` }] };
  }

  private async handleAddNode(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scenePath || !args.nodeType || !args.nodeName) {
      return this.error('Missing required params');
    }
    if (!this.checkProject(args.projectPath as string)) return this.error('Invalid project');
    
    const { stdout, stderr } = await this.executeOp('add_node', {
      scene_path: args.scenePath, node_type: args.nodeType, node_name: args.nodeName,
      parent_node_path: args.parentNodePath || 'root', properties: args.properties || {}
    }, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    return { content: [{ type: 'text', text: `Node added: ${args.nodeName}\n${stdout}` }] };
  }

  private async handleAddNodeWithScript(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scenePath || !args.nodeName) {
      return this.error('Missing required params');
    }
    
    const { stdout, stderr } = await this.executeOp('add_node_with_script', {
      scene_path: args.scenePath, node_name: args.nodeName, node_type: args.nodeType || 'Node',
      script_path: args.scriptPath, parent_node_path: args.parentNodePath || 'root',
      properties: args.properties || {}, exported_properties: args.exportedProperties || []
    }, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    return { content: [{ type: 'text', text: `Node with script added: ${args.nodeName}\n${stdout}` }] };
  }

  private async handleAttachScript(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scenePath || !args.nodePath || !args.scriptPath) {
      return this.error('Missing required params');
    }
    
    const { stdout, stderr } = await this.executeOp('attach_script', {
      scene_path: args.scenePath, node_path: args.nodePath,
      script_path: args.scriptPath, create_backup: !!args.createBackup
    }, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    return { content: [{ type: 'text', text: `Script attached: ${args.nodePath}\n${stdout}` }] };
  }

  private async handleModifyProperty(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scenePath || !args.nodePath || !args.property) {
      return this.error('Missing required params');
    }
    
    const { stdout, stderr } = await this.executeOp('modify_node_property', {
      scene_path: args.scenePath, node_path: args.nodePath,
      property: args.property, value: args.value, create_backup: !!args.createBackup
    }, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    return { content: [{ type: 'text', text: `Property modified: ${args.property}\n${stdout}` }] };
  }

  private async handleRemoveNode(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scenePath || !args.nodePath) {
      return this.error('Missing required params');
    }
    
    const { stdout, stderr } = await this.executeOp('remove_node', {
      scene_path: args.scenePath, node_path: args.nodePath, create_backup: !!args.createBackup
    }, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    return { content: [{ type: 'text', text: `Node removed: ${args.nodePath}\n${stdout}` }] };
  }

  private async handleDuplicateNode(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scenePath || !args.nodePath || !args.newName) {
      return this.error('Missing required params');
    }
    
    const { stdout, stderr } = await this.executeOp('duplicate_node', {
      scene_path: args.scenePath, node_path: args.nodePath,
      new_name: args.newName, create_backup: !!args.createBackup
    }, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    return { content: [{ type: 'text', text: `Node duplicated as ${args.newName}\n${stdout}` }] };
  }

  private async handleMoveNode(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scenePath || !args.nodePath) {
      return this.error('Missing required params: projectPath, scenePath, nodePath');
    }
    const { stdout, stderr } = await this.executeOp('move_node', {
      scene_path: args.scenePath,
      node_path: args.nodePath,
      new_parent_path: args.newParentPath ?? '',
      new_index: args.newIndex ?? -1,
      create_backup: !!args.createBackup,
    }, args.projectPath as string);
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    const mcpMatch = stdout.match(/MCP_RESULT:(.+)$/);
    if (mcpMatch) {
      try { return { content: [{ type: 'text', text: `Node moved: ${JSON.stringify(JSON.parse(mcpMatch[1]))}` }] }; }
      catch { return { content: [{ type: 'text', text: stdout }] }; }
    }
    return { content: [{ type: 'text', text: stdout }] };
  }

  private async handleListNodes(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scenePath) return this.error('Missing required params');

    const scenePath = args.scenePath as string;
    const forceReload = args.forceReload === true;

    const cached = this.getCachedScene(scenePath, forceReload);
    if (cached && !forceReload) {
      let result = cached.data;
      if (args.fields && Array.isArray(args.fields)) {
        result = this.filterFields(result, args.fields as string[]);
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
    }, args.projectPath as string);

    try {
      const data = JSON.parse(stdout);
      this.setCachedScene(scenePath, data);
      let result = data;
      if (args.fields && Array.isArray(args.fields)) {
        result = this.filterFields(result, args.fields as string[]);
      }
      if (COMPRESSION_LEVEL !== 'none') {
        result = this.compressResponse(result);
      }
      return { content: [{ type: 'text', text: JSON.stringify(result) }] };
    } catch {
      return { content: [{ type: 'text', text: stdout }] };
    }
  }

  private filterFields(data: unknown, fields: string[]): unknown {
    if (Array.isArray(data)) {
      return data.map(item => this.filterFields(item, fields));
    }
    if (typeof data === 'object' && data !== null) {
      const result: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(data as Record<string, unknown>)) {
        if (fields.includes(k)) {
          result[k] = v;
        }
      }
      return result;
    }
    return data;
  }

  private async handleBatchOperations(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scenePath || !Array.isArray(args.operations)) {
      return this.error('Missing required params: projectPath, scenePath, operations[]');
    }

    const { stdout, stderr } = await this.executeOp('batch_operations', {
      scene_path: args.scenePath, operations: args.operations,
      enable_rollback: !!args.enableRollback   // default false
    }, args.projectPath as string);

    if (stderr.includes('[ERROR]')) return this.error(`Batch failed: ${stderr}`);
    return { content: [{ type: 'text', text: stdout || `Batch complete\n${stderr}` }] };
  }

  private async handleGenerateNodes(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scenePath || !Array.isArray(args.nodes)) {
      return this.error('Missing required params: projectPath, scenePath, nodes[]');
    }
    const { stdout, stderr } = await this.executeOp('generate_nodes', {
      scene_path: args.scenePath, nodes: args.nodes,
      create_backup: !!args.createBackup
    }, args.projectPath as string);
    if (stderr.includes('[ERROR]')) return this.error(stderr);
    const match = stdout.match(/MCP_RESULT:(.+)$/m);
    const result = match ? JSON.parse(match[1]) : { done: true };
    return { content: [{ type: 'text', text: JSON.stringify(result) }] };
  }

  private async handleLoadSprite(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scenePath || !args.nodePath || !args.texturePath) {
      return this.error('Missing required params');
    }
    
    const { stdout, stderr } = await this.executeOp('load_sprite', {
      scene_path: args.scenePath, node_path: args.nodePath, texture_path: args.texturePath
    }, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    return { content: [{ type: 'text', text: `Sprite loaded: ${args.texturePath}\n${stdout}` }] };
  }

  private async handleSaveScene(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scenePath) return this.error('Missing required params');
    
    const { stdout, stderr } = await this.executeOp('save_scene', {
      scene_path: args.scenePath, new_path: args.newPath || ''
    }, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    return { content: [{ type: 'text', text: `Scene saved\n${stdout}` }] };
  }

  private async handleGetUid(args: Record<string, unknown>) {
    if (!args.projectPath || !args.filePath) return this.error('Missing required params');
    if (!this.checkProject(args.projectPath as string)) return this.error('Invalid project');
    
    const { stdout } = await this.executeOp('get_uid', { file_path: args.filePath }, args.projectPath as string);
    return { content: [{ type: 'text', text: stdout }] };
  }

  private async handleGenericOp(operation: string, args: Record<string, unknown>) {
    if (!args.projectPath || !args.scenePath) {
      return this.error('Missing required params: projectPath, scenePath');
    }
    
    const params: Record<string, unknown> = {
      scene_path: args.scenePath
    };
    
    // Copy all other params
    for (const [k, v] of Object.entries(args)) {
      if (k !== 'projectPath' && k !== 'scenePath') {
        const snakeKey = k.replace(/[A-Z]/g, c => `_${c.toLowerCase()}`);
        params[snakeKey] = v;
      }
    }
    
    const { stdout, stderr } = await this.executeOp(operation, params, args.projectPath as string);
    
    // Parse MCP_RESULT if present
    const mcpMatch = stdout.match(/MCP_RESULT:(.+)$/);
    if (mcpMatch) {
      try {
        const data = JSON.parse(mcpMatch[1]);
        return { content: [{ type: 'text', text: JSON.stringify(data) }] };
      } catch {
        return { content: [{ type: 'text', text: mcpMatch[1] }] };
      }
    }
    
    // Only treat as error if stderr contains [ERROR] (actual error, not Godot warnings)
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    return { content: [{ type: 'text', text: stdout || stderr }] };
  }

  private async handleResaveResources(args: Record<string, unknown>) {
    const projectPath = args.projectPath as string || '';
    const { stdout } = await this.executeOp('resave_resources', { project_path: projectPath }, projectPath || '.');
    return { content: [{ type: 'text', text: stdout }] };
  }

  private async handleInstanceScene(args: Record<string, unknown>) {
    if (!args.projectPath || !args.targetScenePath || !args.sourceScenePath) {
      return this.error('Missing required params: projectPath, targetScenePath, sourceScenePath');
    }
    
    const params: Record<string, unknown> = {
      target_scene_path: args.targetScenePath,
      source_scene_path: args.sourceScenePath,
    };
    
    if (args.parentNodePath) params.parent_node_path = args.parentNodePath;
    if (args.nodeName) params.node_name = args.nodeName;
    if (args.position) params.position = args.position;
    
    const { stdout, stderr } = await this.executeOp('instance_scene', params, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    return { content: [{ type: 'text', text: stdout }] };
  }

  private async handleCreateScript(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scriptPath) {
      return this.error('Missing required params: projectPath, scriptPath');
    }
    
    const params: Record<string, unknown> = {
      project_path: args.projectPath,
      script_path: args.scriptPath,
    };
    
    if (args.className) params.class_name = args.className;
    if (args.extends) params.extends = args.extends;
    if (args.template) params.template = args.template;
    
    const { stdout, stderr } = await this.executeOp('create_script', params, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    return { content: [{ type: 'text', text: stdout }] };
  }

  private async handleEditScript(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scriptPath || !args.content) {
      return this.error('Missing required params: projectPath, scriptPath, content');
    }
    
    const params: Record<string, unknown> = {
      project_path: args.projectPath,
      script_path: args.scriptPath,
      content: args.content,
      append: args.append || false,
      create_backup: !!args.createBackup
    };
    
    const { stdout, stderr } = await this.executeOp('edit_script', params, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    
    const mcpMatch = stdout.match(/MCP_RESULT:(.+)$/);
    if (mcpMatch) {
      try {
        const data = JSON.parse(mcpMatch[1]);
        return { content: [{ type: 'text', text: `Script edited: ${args.scriptPath}\n${JSON.stringify(data)}` }] };
      } catch {
        return { content: [{ type: 'text', text: stdout }] };
      }
    }
    
    return { content: [{ type: 'text', text: stdout }] };
  }

  private async handleCreateResource(args: Record<string, unknown>) {
    if (!args.projectPath || !args.type) {
      return this.error('Missing required params: projectPath, type');
    }
    
    const params: Record<string, unknown> = {
      project_path: args.projectPath,
      type: args.type,
      path: args.path || 'resources/new_resource.tres',
      properties: args.properties || {}
    };
    
    const { stdout, stderr } = await this.executeOp('create_resource', params, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    
    const mcpMatch = stdout.match(/MCP_RESULT:(.+)$/);
    if (mcpMatch) {
      try {
        const data = JSON.parse(mcpMatch[1]);
        return { content: [{ type: 'text', text: `Resource created: ${params.path}\n${JSON.stringify(data)}` }] };
      } catch {
        return { content: [{ type: 'text', text: stdout }] };
      }
    }
    
    return { content: [{ type: 'text', text: stdout }] };
  }

  private async handleListResources(args: Record<string, unknown>) {
    if (!args.projectPath) {
      return this.error('Missing required params: projectPath');
    }
    
    const params: Record<string, unknown> = {
      folder: args.folder || 'res://',
      extensions: args.extensions || ['*.tres', '*.tscn', '*.gd', '*.png', '*.jpg'],
      recursive: args.recursive !== false
    };
    
    const { stdout, stderr } = await this.executeOp('list_resources', params, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    
    const mcpMatch = stdout.match(/MCP_RESULT:(.+)$/);
    if (mcpMatch) {
      try {
        const data = JSON.parse(mcpMatch[1]);
        const resourceList = data.resources.map((r: { path: string; type: string }) => `- ${r.type}: ${r.path}`).join('\n');
        return { content: [{ type: 'text', text: `Found ${data.count} resources:\n${resourceList}` }] };
      } catch {
        return { content: [{ type: 'text', text: stdout }] };
      }
    }
    
    return { content: [{ type: 'text', text: stdout }] };
  }

  private async handleRunScene(args: Record<string, unknown>) {
    if (!args.projectPath) {
      return this.error('Missing required params: projectPath');
    }
    
    const scenePath = args.scenePath as string;
    const projectPath = args.projectPath as string;
    
    const sceneArgs = scenePath ? ['--path', projectPath, scenePath] : ['--path', projectPath];
    
    return new Promise<{ content: [{type: string, text: string}] }>((resolve) => {
      const proc = spawn(this.godotPath!, ['--headless', ...sceneArgs], {
        stdio: ['ignore', 'pipe', 'pipe']
      });
      
      let stdout = '';
      let stderr = '';
      
      proc.stdout?.on('data', (data) => { stdout += data.toString(); });
      proc.stderr?.on('data', (data) => { stderr += data.toString(); });
      
      proc.on('close', (code) => {
        resolve({
          content: [{
            type: 'text',
            text: `Scene executed (exit code: ${code})\n${stdout}${stderr ? '\n' + stderr : ''}`
          }]
        });
      });
      
      setTimeout(() => {
        proc.kill();
        resolve({ content: [{ type: 'text', text: 'Scene execution timed out' }] });
      }, 30000);
    });
  }

  private async handleExportProject(args: Record<string, unknown>) {
    if (!args.projectPath) {
      return this.error('Missing required params: projectPath');
    }
    
    const params: Record<string, unknown> = {
      preset: args.preset || '',
      output_path: args.outputPath || '',
      debug: args.debug || false
    };
    
    const { stdout, stderr } = await this.executeOp('export_project', params, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    
    const mcpMatch = stdout.match(/MCP_RESULT:(.+)$/);
    if (mcpMatch) {
      try {
        const data = JSON.parse(mcpMatch[1]);
        return { content: [{ type: 'text', text: `Export info:\n${JSON.stringify(data, null, 2)}` }] };
      } catch {
        return { content: [{ type: 'text', text: stdout }] };
      }
    }
    
    return { content: [{ type: 'text', text: stdout }] };
  }

  private async handleValidateScene(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scenePath) {
      return this.error('Missing required params: projectPath, scenePath');
    }
    
    const params: Record<string, unknown> = {
      scene_path: args.scenePath
    };
    
    const { stdout, stderr } = await this.executeOp('validate_scene', params, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    
    const mcpMatch = stdout.match(/MCP_RESULT:(.+)$/);
    if (mcpMatch) {
      try {
        const data = JSON.parse(mcpMatch[1]);
        let message = data.valid ? '✅ Scene is valid' : '❌ Scene has issues';
        if (data.warnings_count > 0) {
          message += `\n⚠️ ${data.warnings_count} warnings`;
        }
        if (data.issues_count > 0) {
          message += `\n❌ ${data.issues_count} issues`;
        }
        if (data.issues.length > 0) {
          message += '\n\nIssues:\n' + data.issues.map((i: string) => '  - ' + i).join('\n');
        }
        if (data.warnings.length > 0) {
          message += '\n\nWarnings:\n' + data.warnings.map((w: string) => '  - ' + w).join('\n');
        }
        return { content: [{ type: 'text', text: message }] };
      } catch {
        return { content: [{ type: 'text', text: stdout }] };
      }
    }
    
    return { content: [{ type: 'text', text: stdout }] };
  }

  private async handleGetProjectSetting(args: Record<string, unknown>) {
    if (!args.projectPath || !args.setting) {
      return this.error('Missing required params: projectPath, setting');
    }
    
    const params: Record<string, unknown> = {
      setting: args.setting,
    };
    
    if (args.default !== undefined) params.default = args.default;
    
    const { stdout, stderr } = await this.executeOp('get_project_setting', params, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    
    const mcpMatch = stdout.match(/MCP_RESULT:(.+)$/);
    if (mcpMatch) {
      try {
        const data = JSON.parse(mcpMatch[1]);
        return { content: [{ type: 'text', text: `${data.setting} = ${JSON.stringify(data.value)}` }] };
      } catch {
        return { content: [{ type: 'text', text: stdout }] };
      }
    }
    
    return { content: [{ type: 'text', text: stdout }] };
  }

  private async handleSetProjectSetting(args: Record<string, unknown>) {
    if (!args.projectPath || !args.setting || args.value === undefined) {
      return this.error('Missing required params: projectPath, setting, value');
    }
    
    const params: Record<string, unknown> = {
      setting: args.setting,
      value: args.value,
      save: args.save !== false
    };
    
    const { stdout, stderr } = await this.executeOp('set_project_setting', params, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    
    return { content: [{ type: 'text', text: `Setting updated: ${args.setting}` }] };
  }

  private async handleFindNodes(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scenePath) {
      return this.error('Missing required params: projectPath, scenePath');
    }
    
    const params: Record<string, unknown> = {
      scene_path: args.scenePath,
    };
    
    if (args.type) params.type = args.type;
    if (args.namePattern) params.name_pattern = args.namePattern;
    if (args.recursive !== undefined) params.recursive = args.recursive;
    
    const { stdout, stderr } = await this.executeOp('find_nodes', params, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    
    const mcpMatch = stdout.match(/MCP_RESULT:(.+)$/);
    if (mcpMatch) {
      try {
        const data = JSON.parse(mcpMatch[1]);
        const nodes = data.nodes.map((n: { name: string; type: string }) => `- ${n.type}: ${n.name}`).join('\n');
        return { content: [{ type: 'text', text: `Found ${data.count} nodes:\n${nodes}` }] };
      } catch {
        return { content: [{ type: 'text', text: stdout }] };
      }
    }
    
    return { content: [{ type: 'text', text: stdout }] };
  }

  // ===== RUNTIME DEBUG HANDLERS =====

  private async sendRuntimeCommand(projectPath: string, command: object, port: number = 9090): Promise<{ result?: unknown; error?: string }> {
    const { Socket } = await import('net');
    
    return new Promise((resolve) => {
      const client = new Socket();
      let data = '';
      
      client.connect(port, '127.0.0.1', () => {
        client.write(JSON.stringify(command) + '\n');
      });
      
      client.on('data', (chunk) => {
        data += chunk.toString();
      });
      
      client.on('close', () => {
        try {
          const response = JSON.parse(data.trim());
          resolve(response);
        } catch {
          resolve({ error: 'Invalid response from debug server' });
        }
      });
      
      client.on('error', (err) => {
        resolve({ error: `Connection failed: ${err.message}` });
      });
      
      setTimeout(() => {
        client.destroy();
        resolve({ error: 'Timeout waiting for response' });
      }, 5000);
    });
  }

  private async handleRuntimeConnect(args: Record<string, unknown>) {
    if (!args.projectPath) {
      return this.error('Missing required param: projectPath');
    }
    
    const port = (args.port as number) || 9090;
    const result = await this.sendRuntimeCommand(args.projectPath as string, { command: 'ping', id: 1 }, port);
    
    if (result.error) {
      return { content: [{ type: 'text', text: `Not connected. Start game with debug server first.\nError: ${result.error}` }] };
    }
    
    return { content: [{ type: 'text', text: `Connected to debug server on port ${port}` }] };
  }

  private async handleRuntimeListNodes(args: Record<string, unknown>) {
    if (!args.projectPath) {
      return this.error('Missing required param: projectPath');
    }
    
    const result = await this.sendRuntimeCommand(args.projectPath as string, {
      command: 'list_nodes',
      params: { max_depth: args.maxDepth || 10 },
      id: 1
    });
    
    if (result.error) {
      return this.error(result.error);
    }
    
    const nodes = (result.result as { nodes: { name: string; type: string; path: string }[] })?.nodes || [];
    const text = nodes.map(n => `  ${n.path} [${n.type}]`).join('\n');
    return { content: [{ type: 'text', text: `Nodes in runtime (${nodes.length}):\n${text}` }] };
  }

  private async handleRuntimeGetProperty(args: Record<string, unknown>) {
    if (!args.projectPath || !args.nodePath || !args.property) {
      return this.error('Missing required params: projectPath, nodePath, property');
    }
    
    const result = await this.sendRuntimeCommand(args.projectPath as string, {
      command: 'get_node_property',
      params: { node_path: args.nodePath, property: args.property },
      id: 1
    });
    
    if (result.error) {
      return this.error(result.error);
    }
    
    const propData = result.result as { property: string; value: unknown; type: number };
    return { content: [{ type: 'text', text: `${args.nodePath}.${propData.property} = ${JSON.stringify(propData.value)} (type: ${propData.type})` }] };
  }

  private async handleRuntimeSetProperty(args: Record<string, unknown>) {
    if (!args.projectPath || !args.nodePath || !args.property || args.value === undefined) {
      return this.error('Missing required params: projectPath, nodePath, property, value');
    }
    
    const result = await this.sendRuntimeCommand(args.projectPath as string, {
      command: 'set_node_property',
      params: { node_path: args.nodePath, property: args.property, value: args.value },
      id: 1
    });
    
    if (result.error) {
      return this.error(result.error);
    }
    
    return { content: [{ type: 'text', text: `Set ${args.nodePath}.${args.property} = ${JSON.stringify(args.value)}` }] };
  }

  private async handleRuntimeCallMethod(args: Record<string, unknown>) {
    if (!args.projectPath || !args.nodePath || !args.method) {
      return this.error('Missing required params: projectPath, nodePath, method');
    }
    
    const result = await this.sendRuntimeCommand(args.projectPath as string, {
      command: 'call_method',
      params: { node_path: args.nodePath, method: args.method, args: args.args || [] },
      id: 1
    });
    
    if (result.error) {
      return this.error(result.error);
    }
    
    return { content: [{ type: 'text', text: `Called ${args.nodePath}.${args.method}() = ${JSON.stringify((result.result as { return_value?: unknown })?.return_value)}` }] };
  }

  private async handleRuntimeGetTreeInfo(args: Record<string, unknown>) {
    if (!args.projectPath) {
      return this.error('Missing required param: projectPath');
    }
    
    const result = await this.sendRuntimeCommand(args.projectPath as string, {
      command: 'get_tree_info',
      params: {},
      id: 1
    });
    
    if (result.error) {
      return this.error(result.error);
    }
    
    const info = result.result as { root_name: string; node_count: number; paused: boolean };
    return { content: [{ type: 'text', text: `Game Tree Info:\n  Root: ${info.root_name}\n  Nodes: ${info.node_count}\n  Paused: ${info.paused}` }] };
  }

  private async handleRuntimeFindNode(args: Record<string, unknown>) {
    if (!args.projectPath) {
      return this.error('Missing required param: projectPath');
    }
    
    const result = await this.sendRuntimeCommand(args.projectPath as string, {
      command: 'find_node',
      params: { pattern: args.pattern || '', type: args.type || '' },
      id: 1
    });
    
    if (result.error) {
      return this.error(result.error);
    }
    
    const nodes = (result.result as { nodes: { name: string; type: string; path: string }[] })?.nodes || [];
    const text = nodes.map(n => `  ${n.path} [${n.type}]`).join('\n');
    return { content: [{ type: 'text', text: `Found ${nodes.length} nodes:\n${text}` }] };
  }

  private async handleRuntimeGetNodeInfo(args: Record<string, unknown>) {
    if (!args.projectPath || !args.nodePath) {
      return this.error('Missing required params: projectPath, nodePath');
    }
    
    const result = await this.sendRuntimeCommand(args.projectPath as string, {
      command: 'get_node_info',
      params: { node_path: args.nodePath },
      id: 1
    });
    
    if (result.error) {
      return this.error(result.error);
    }
    
    const info = result.result as { name: string; type: string; properties: { name: string; type: number }[]; methods: string[] };
    const props = info.properties.map(p => p.name).join(', ');
    const methods = info.methods.slice(0, 10).join(', ') + (info.methods.length > 10 ? '...' : '');
    return { content: [{ type: 'text', text: `Node: ${info.name} [${info.type}]\nProperties: ${props}\nMethods: ${methods}` }] };
  }

  private async handleRuntimeStartDebug(args: Record<string, unknown>) {
    if (!args.projectPath || !this.validatePath(args.projectPath as string)) {
      return this.error('Invalid project path');
    }
    
    await this.ensureGodotPath();
    if (this.activeProcess) this.activeProcess.process.kill();
    
    const debugScriptPath = join(__dirname, 'scripts', 'mcp_debug_server.gd');
    
    const cmdArgs = ['-d', '--path', args.projectPath as string, '--script', debugScriptPath];
    if (args.scenePath) cmdArgs.push(args.scenePath as string);

    const proc = spawn(this.godotPath!, cmdArgs, { stdio: 'pipe' });
    const output: string[] = [], errors: string[] = [];

    proc.stdout?.on('data', (d: Buffer) => output.push(...d.toString().split('\n')));
    proc.stderr?.on('data', (d: Buffer) => errors.push(...d.toString().split('\n')));
    proc.on('exit', () => { if (this.activeProcess?.process === proc) this.activeProcess = null; });

    this.activeProcess = { process: proc, output, errors };
    return { content: [{ type: 'text', text: 'Game started with debug server on port 9090. Wait a moment for it to load, then use runtime tools.' }] };
  }

  private LAYOUT_PRESETS: Record<string, Record<string, unknown>> = {
    'full_rect': { anchors_preset: 15 },
    'top_bar': { anchors_preset: 10, offset_top: 0, offset_bottom: 80 },
    'bottom_bar': { anchors_preset: 11, offset_top: -80, offset_bottom: 0 },
    'left_panel': { anchors_preset: 9, offset_left: 0, offset_right: 250 },
    'right_panel': { anchors_preset: 11, offset_left: -250, offset_right: 0 },
    'center': { anchors_preset: 8 },
    'top_left': { anchors_preset: 0 },
    'top_right': { anchors_preset: 1 },
    'bottom_left': { anchors_preset: 4 },
    'bottom_right': { anchors_preset: 5 },
    'top_wide': { anchors_preset: 10, offset_top: 0, offset_bottom: 60 },
    'bottom_wide': { anchors_preset: 11, offset_top: -60, offset_bottom: 0 },
  };

  private async handleSetLayout(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scenePath || !args.nodePath || !args.layout) {
      return this.error('Missing required params: projectPath, scenePath, nodePath, layout');
    }

    const params = {
      scene_path: args.scenePath,
      node_path: args.nodePath,
      layout: args.layout,
      create_backup: !!args.createBackup
    };

    const { stdout, stderr } = await this.executeOp('set_layout', params, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    
    const mcpMatch = stdout.match(/MCP_RESULT:(.+)$/);
    if (mcpMatch) {
      try {
        const data = JSON.parse(mcpMatch[1]);
        return { content: [{ type: 'text', text: `Layout set: ${JSON.stringify(data)}` }] };
      } catch {
        return { content: [{ type: 'text', text: stdout }] };
      }
    }
    
    return { content: [{ type: 'text', text: stdout }] };
  }

  private async handleApplyLayoutPreset(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scenePath || !args.nodePath || !args.preset) {
      return this.error('Missing required params: projectPath, scenePath, nodePath, preset');
    }

    const presetName = args.preset as string;
    const preset = this.LAYOUT_PRESETS[presetName];
    if (!preset) {
      return this.error(`Unknown preset: ${presetName}. Use list_layout_presets to see available.`);
    }

    const params = {
      scene_path: args.scenePath,
      node_path: args.nodePath,
      layout: preset,
      create_backup: !!args.createBackup
    };

    const { stdout, stderr } = await this.executeOp('set_layout', params, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    
    return { content: [{ type: 'text', text: `Applied preset '${presetName}': ${stdout}` }] };
  }

  private async handleCopyLayout(args: Record<string, unknown>) {
    if (!args.projectPath || !args.scenePath || !args.fromNode || !args.toNode) {
      return this.error('Missing required params: projectPath, scenePath, fromNode, toNode');
    }

    // First get layout from source node
    const getParams = { scene_path: args.scenePath, node_path: args.fromNode };
    const { stdout } = await this.executeOp('get_node_info', getParams, args.projectPath as string);
    
    const mcpMatch = stdout.match(/MCP_RESULT:(.+)$/);
    if (!mcpMatch) {
      return this.error('Could not get source node info');
    }
    
    let nodeInfo;
    try {
      nodeInfo = JSON.parse(mcpMatch[1]);
    } catch {
      return this.error('Failed to parse node info');
    }
    
    // Extract layout properties
    const layoutProps = nodeInfo.properties || {};
    const layout: Record<string, unknown> = {};
    
    const layoutKeys = ['anchors_preset', 'offset_left', 'offset_top', 'offset_right', 'offset_bottom', 'custom_minimum_size', 'size_flags_horizontal', 'size_flags_vertical', 'layout_mode'];
    for (const key of layoutKeys) {
      if (layoutProps[key] !== undefined) {
        layout[key] = layoutProps[key];
      }
    }
    
    // Apply to target node
    const setParams = {
      scene_path: args.scenePath,
      node_path: args.toNode,
      layout: layout,
      create_backup: !!args.createBackup
    };

    const { stdout: setStdout, stderr } = await this.executeOp('set_layout', setParams, args.projectPath as string);
    
    if (stderr.includes('[ERROR]')) return this.error(`Failed: ${stderr}`);
    
    return { content: [{ type: 'text', text: `Layout copied from ${args.fromNode} to ${args.toNode}` }] };
  }

  private handleListLayoutPresets() {
    const presets = Object.entries(this.LAYOUT_PRESETS).map(([name, config]) => ({
      name,
      config
    }));
    
    let message = 'Available Layout Presets:\n\n';
    for (const p of presets) {
      message += `**${p.name}**: ${JSON.stringify(p.config)}\n`;
    }
    
    return { content: [{ type: 'text', text: message }] };
  }

  private async cleanup() {
    if (this.activeProcess) this.activeProcess.process.kill();
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
    } catch (e) {
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
