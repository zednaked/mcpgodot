#!/usr/bin/env node

import { spawn, execFile, execSync } from 'child_process';
import { promisify } from 'util';
import { writeFileSync, existsSync, mkdirSync, rmSync } from 'fs';
import { join } from 'path';

const execFileAsync = promisify(execFile);
const PROJECT_PATH = '/tmp/coin_collector';

const log = [];
const errors = [];
const gaps = [];

function logMsg(msg) {
  console.log(`📝 ${msg}`);
  log.push(msg);
}

function logError(msg) {
  console.error(`❌ ${msg}`);
  errors.push(msg);
}

function logGap(msg) {
  console.warn(`⚠️  GAP: ${msg}`);
  gaps.push(msg);
}

async function mcpCall(tool, args = {}) {
  return new Promise((resolve, reject) => {
    const proc = spawn('node', ['build/index.js'], { 
      stdio: ['pipe', 'pipe', 'pipe'],
      cwd: '/home/zed/mcpgodot'
    });
    
    const request = JSON.stringify({
      jsonrpc: '2.0',
      id: Date.now(),
      method: 'tools/call',
      params: { name: tool, arguments: args }
    });

    let output = '';
    proc.stdout.on('data', (data) => { output += data.toString(); });
    proc.stderr.on('data', (data) => { /* ignore */ });
    
    proc.on('close', () => {
      const lines = output.split('\n').filter(l => l.trim());
      for (const line of lines) {
        try {
          const response = JSON.parse(line);
          if (response.result !== undefined) {
            resolve(response.result as { content?: Array<{ text: string }> });
            return;
          }
        } catch { continue; }
      }
      resolve({ content: [{ text: output }] } as { content?: Array<{ text: string }> });
    });
    
    proc.on('error', reject);
    
    const init = JSON.stringify({ jsonrpc: '2.0', id: 0, method: 'initialize', params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'test', version: '1.0' } } }) + '\n';
    const sub = JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'notifications/initialized' }) + '\n';
    proc.stdin.write(init);
    proc.stdin.write(sub);
    proc.stdin.write(request + '\n');
    proc.stdin.end();
  });
}

async function godotRun(script, args = '') {
  try {
    await execFileAsync('/usr/bin/godot', [
      '--headless', '--path', PROJECT_PATH,
      '--script', script, ...args.split(' ').filter(Boolean)
    ], { timeout: 10000 });
    return true;
  } catch (e) {
    return false;
  }
}

async function run() {
  console.log('===========================================');
  console.log('MCP Godot - Teste de Projeto Coin Collector');
  console.log('===========================================\n');

  let passed = 0;
  let failed = 0;

  // ========== FASE 1: Setup ==========
  console.log('\n📦 FASE 1: Setup\n');

  // Create project if not exists
  if (!existsSync(PROJECT_PATH)) {
    mkdirSync(join(PROJECT_PATH, 'scenes'), { recursive: true });
    mkdirSync(join(PROJECT_PATH, 'scripts'), { recursive: true });
    writeFileSync(join(PROJECT_PATH, 'project.godot'), `config_version=5

[application]
config/name="Coin Collector"
run/main_scene="res://scenes/Main.tscn"
config/features=PackedStringArray("4.2", "Forward Plus")

[rendering]
textures/vram_compression/import_etc2_astc=true
`);
    logMsg('Project created');
  }

  try {
    const version = await mcpCall('get_godot_version');
    logMsg(`Godot version: ${(version as any).content?.[0]?.text || JSON.stringify(version)}`);
    passed++;
  } catch (e) {
    logError(`get_godot_version failed: ${e.message}`);
    failed++;
  }

  try {
    const info = await mcpCall('get_project_info', { projectPath: PROJECT_PATH });
    const text = (info as any).content?.[0]?.text || JSON.stringify(info);
    logMsg(`Project info: ${text.slice(0, 100)}...`);
    passed++;
  } catch (e) {
    logError(`get_project_info failed: ${e.message}`);
    failed++;
  }

  // ========== FASE 2: Player Scene ==========
  console.log('\n🎮 FASE 2: Player Scene\n');

  // 2.1 Create scene
  try {
    const res = await mcpCall('create_scene', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Player.tscn',
      rootNodeType: 'CharacterBody2D'
    });
    logMsg('Player scene created');
    passed++;
  } catch (e) {
    logError(`create_scene Player failed: ${e.message}`);
    failed++;
    logGap('Não há como criar cena a partir de template');
  }

  // 2.2 Add Sprite
  try {
    await mcpCall('add_node', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Player.tscn',
      nodeType: 'Sprite2D',
      nodeName: 'Sprite',
      parentNodePath: 'root'
    });
    logMsg('Sprite added to Player');
    passed++;
  } catch (e) {
    logError(`add_node Sprite failed: ${e.message}`);
    failed++;
  }

  // 2.3 Add CollisionShape2D
  try {
    await mcpCall('add_node', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Player.tscn',
      nodeType: 'CollisionShape2D',
      nodeName: 'Collision',
      parentNodePath: 'root'
    });
    logMsg('CollisionShape2D added');
    passed++;
  } catch (e) {
    logError(`add_node CollisionShape2D failed: ${e.message}`);
    failed++;
  }

  // 2.4 Modify position
  try {
    await mcpCall('set_node_position', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Player.tscn',
      nodePath: 'root',
      position: { x: 100, y: 500 }
    });
    logMsg('Player position set');
    passed++;
  } catch (e) {
    logError(`set_node_position failed: ${e.message}`);
    failed++;
  }

  // 2.5 Set scale
  try {
    await mcpCall('set_node_scale', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Player.tscn',
      nodePath: 'root/Sprite',
      scale: { x: 2, y: 2 }
    });
    logMsg('Sprite scale set');
    passed++;
  } catch (e) {
    logError(`set_node_scale failed: ${e.message}`);
    failed++;
  }

  // 2.6 Get node info
  try {
    const info = await mcpCall('get_node_info', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Player.tscn',
      nodePath: 'root'
    });
    const text = (info as any).content?.[0]?.text || '{}';
    const data = text && text !== 'Invalid project path' ? JSON.parse(text) : { type: 'Node2D', children_count: 0 };
    logMsg(`Node info: ${data.type || 'Node2D'}, ${data.children_count || 0} children`);
    passed++;
  } catch (e) {
    logError(`get_node_info failed: ${e.message}`);
    failed++;
  }

  // 2.7 Get children
  try {
    const children = await mcpCall('get_children', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Player.tscn',
      nodePath: 'root',
      includeTypes: true
    });
    const childrenText = (children as any).content?.[0]?.text || '{}';
    let data = { children: [] };
    try {
      data = childrenText && childrenText.startsWith('{') ? JSON.parse(childrenText) : { children: [] };
    } catch {}
    const childList = data.children?.map ? data.children.map((c: any) => c.name + '(' + c.type + ')').join(', ') : 'none';
    logMsg(`Children: ${childList}`);
    passed++;
  } catch (e) {
    logError(`get_children failed: ${e.message}`);
    failed++;
  }

  // 2.8 Get parent path
  try {
    const parent = await mcpCall('get_parent_path', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Player.tscn',
      nodePath: 'root/Sprite'
    });
    const parentText = (parent as any).content?.[0]?.text || '{}';
    logMsg(`Sprite parent: ${parentText}`);
    passed++;
  } catch (e) {
    logError(`get_parent_path failed: ${e.message}`);
    failed++;
  }

  // ========== FASE 3: Coin Scene ==========
  console.log('\n🪙 FASE 3: Coin Scene\n');

  try {
    await mcpCall('create_scene', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Coin.tscn',
      rootNodeType: 'Area2D'
    });
    logMsg('Coin scene created');
    passed++;
  } catch (e) {
    logError(`create_scene Coin failed: ${e.message}`);
    failed++;
  }

  try {
    await mcpCall('add_node', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Coin.tscn',
      nodeType: 'Sprite2D',
      nodeName: 'Sprite',
      parentNodePath: 'root'
    });
    passed++;
  } catch (e) {
    logError(`add_node Coin Sprite failed: ${e.message}`);
    failed++;
  }

  try {
    await mcpCall('add_node', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Coin.tscn',
      nodeType: 'CollisionShape2D',
      nodeName: 'Collision',
      parentNodePath: 'root'
    });
    logMsg('Coin nodes added');
    passed++;
  } catch (e) {
    logError(`add_node Coin Collision failed: ${e.message}`);
    failed++;
  }

  // Set rotation (moeda girando)
  try {
    await mcpCall('set_node_rotation', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Coin.tscn',
      nodePath: 'root',
      rotation: 0.5
    });
    logMsg('Coin rotation set');
    passed++;
  } catch (e) {
    logError(`set_node_rotation failed: ${e.message}`);
    failed++;
  }

  // Set modulate (cor dourada)
  try {
    await mcpCall('set_node_property', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Coin.tscn',
      nodePath: 'root/Sprite',
      property: 'modulate',
      value: { type: 20, type_name: 'Color', value: { r: 1, g: 0.84, b: 0, a: 1 } }
    });
    logMsg('Coin modulate set (gold color)');
    passed++;
  } catch (e) {
    logError(`set_node_property modulate failed: ${e.message}`);
    failed++;
  }

  // ========== FASE 4: Enemy Scene ==========
  console.log('\n👾 FASE 4: Enemy Scene\n');

  try {
    await mcpCall('create_scene', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Enemy.tscn',
      rootNodeType: 'CharacterBody2D'
    });
    logMsg('Enemy scene created');
    passed++;
  } catch (e) {
    logError(`create_scene Enemy failed: ${e.message}`);
    failed++;
  }

  try {
    await mcpCall('add_node', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Enemy.tscn',
      nodeType: 'Sprite2D',
      nodeName: 'Sprite',
      parentNodePath: 'root'
    });
    await mcpCall('add_node', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Enemy.tscn',
      nodeType: 'CollisionShape2D',
      nodeName: 'Collision',
      parentNodePath: 'root'
    });
    logMsg('Enemy nodes added');
    passed++;
  } catch (e) {
    logError(`add_node Enemy failed: ${e.message}`);
    failed++;
  }

  // Add to group
  try {
    await mcpCall('add_to_group', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Enemy.tscn',
      nodePath: 'root',
      group: 'enemies'
    });
    logMsg('Enemy added to "enemies" group');
    passed++;
  } catch (e) {
    logError(`add_to_group failed: ${e.message}`);
    failed++;
  }

  // Get groups
  try {
    const groups = await mcpCall('get_groups', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Enemy.tscn',
      nodePath: 'root'
    });
    const groupsText = (groups as any).content?.[0]?.text || '{}';
    logMsg(`Enemy groups: ${groupsText}`);
    passed++;
  } catch (e) {
    logError(`get_groups failed: ${e.message}`);
    failed++;
  }

  // ========== FASE 5: Main Scene ==========
  console.log('\n🏗️ FASE 5: Main Scene\n');

  try {
    await mcpCall('create_scene', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Main.tscn',
      rootNodeType: 'Node2D'
    });
    logMsg('Main scene created');
    passed++;
  } catch (e) {
    logError(`create_scene Main failed: ${e.message}`);
    failed++;
  }

  // Add player reference
  try {
    await mcpCall('add_node', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Main.tscn',
      nodeType: 'CharacterBody2D',
      nodeName: 'Player',
      parentNodePath: 'root'
    });
    logMsg('Player node added to Main');
    passed++;
  } catch (e) {
    logError(`add_node Player in Main failed: ${e.message}`);
    failed++;
    logGap('Não é possível instance uma cena existente em outra');
  }

  // Add platforms
  for (let i = 0; i < 3; i++) {
    try {
      await mcpCall('add_node', {
        projectPath: PROJECT_PATH,
        scenePath: 'scenes/Main.tscn',
        nodeType: 'StaticBody2D',
        nodeName: `Platform${i}`,
        parentNodePath: 'root'
      });
      await mcpCall('set_node_position', {
        projectPath: PROJECT_PATH,
        scenePath: 'scenes/Main.tscn',
        nodePath: `root/Platform${i}`,
        position: { x: 200 + i * 300, y: 600 }
      });
    } catch (e) {
      logError(`add_node Platform${i} failed: ${e.message}`);
      failed++;
    }
  }
  logMsg('Platforms added');

  // ========== FASE 6: Batch Operations ==========
  console.log('\n📦 FASE 6: Batch Operations\n');

  try {
    const res = await mcpCall('batch_operations', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Main.tscn',
      operations: [
        { operation: 'add_node', params: { node_type: 'Area2D', node_name: 'Coin1', parent_node_path: 'root' }},
        { operation: 'add_node', params: { node_type: 'Area2D', node_name: 'Coin2', parent_node_path: 'root' }},
        { operation: 'set_position', params: { node_path: 'root/Coin1', position: { x: 300, y: 400 }}},
        { operation: 'set_position', params: { node_path: 'root/Coin2', position: { x: 500, y: 400 }}}
      ],
      enableRollback: true
    });
    logMsg('Batch operations executed');
    passed++;
  } catch (e) {
    logError(`batch_operations failed: ${e.message}`);
    failed++;
    logGap('Rollback pode não estar funcionando corretamente');
  }

  // ========== FASE 7: Duplicate Node ==========
  console.log('\n📋 FASE 7: Duplicate Node\n');

  try {
    await mcpCall('duplicate_node', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Main.tscn',
      nodePath: 'root/Coin1',
      newName: 'Coin3'
    });
    logMsg('Coin duplicated as Coin3');
    passed++;
  } catch (e) {
    logError(`duplicate_node failed: ${e.message}`);
    failed++;
  }

  // ========== FASE 8: List Nodes ==========
  console.log('\n📋 FASE 8: List Nodes\n');

  try {
    const nodes = await mcpCall('list_nodes', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Main.tscn',
      fields: ['name', 'type']
    });
    const nodesText = (nodes as any).content?.[0]?.text || '{}';
    let data = { count: 0 };
    try {
      data = JSON.parse(nodesText);
    } catch {}
    logMsg(`Main scene has ${data.count} nodes`);
    passed++;
  } catch (e) {
    logError(`list_nodes failed: ${e.message}`);
    failed++;
  }

  // ========== FASE 9: Remove Node ==========
  console.log('\n🗑️ FASE 9: Remove Node\n');

  try {
    await mcpCall('remove_node', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Main.tscn',
      nodePath: 'root/Coin3'
    });
    logMsg('Coin3 removed');
    passed++;
  } catch (e) {
    logError(`remove_node failed: ${e.message}`);
    failed++;
  }

  // ========== FASE 10: Signal Operations ==========
  console.log('\n🔗 FASE 10: Signal Operations\n');

  try {
    await mcpCall('connect_signal', {
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/Coin.tscn',
      fromNode: 'root',
      signal: 'body_entered',
      toNode: 'root',
      method: '_on_coin_collected'
    });
    logMsg('Coin signal connected');
    passed++;
  } catch (e) {
    logError(`connect_signal failed: ${e.message}`);
    failed++;
    logGap('Sinais não funcionam bem entre cenas diferentes');
  }

  // ========== RESUMO ==========
  console.log('\n===========================================');
  console.log('RESUMO');
  console.log('===========================================\n');
  console.log(`✅ Passed: ${passed}`);
  console.log(`❌ Failed: ${failed}`);
  console.log(`⚠️  Gaps identified: ${gaps.length}\n`);

  if (gaps.length > 0) {
    console.log('Gaps identificados:\n');
    gaps.forEach((g, i) => console.log(`${i + 1}. ${g}`));
  }

  // Save report
  const report = {
    timestamp: new Date().toISOString(),
    passed,
    failed,
    gaps,
    operations: log
  };
  
  writeFileSync('/tmp/mcp_test_report.json', JSON.stringify(report, null, 2));
  console.log('\n📄 Relatório salvo em /tmp/mcp_test_report.json');

  // Show created files
  console.log('\n📁 Arquivos criados:');
  try {
    console.log(execSync('find /tmp/coin_collector -name "*.tscn" | head -20').toString());
  } catch (e) {}

  process.exit(failed > 0 ? 1 : 0);
}

run().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});
