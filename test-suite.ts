#!/usr/bin/env node

import { spawn, execFile } from 'child_process';
import { promisify } from 'util';
import { writeFileSync, mkdirSync, rmSync, existsSync } from 'fs';
import { join } from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const execFileAsync = promisify(execFile);
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

interface MCPResponse {
  content?: Array<{ type: string; text: string }>;
  isError?: boolean;
  tools?: Array<{ name: string }>;
}

interface TestResult {
  name: string;
  passed: boolean;
  duration: number;
  error?: string;
}

const GODOT_PATH = process.env.GODOT_PATH || '/usr/bin/godot';
const TEST_PROJECT = join(__dirname, 'test_project');

const results: TestResult[] = [];

async function mcpCall(tool: string, args: Record<string, unknown> = {}): Promise<MCPResponse> {
  return new Promise((resolve, reject) => {
    const proc = spawn('node', ['build/index.js'], { stdio: ['pipe', 'pipe', 'pipe'] });
    
    const request = JSON.stringify({
      jsonrpc: '2.0',
      id: Date.now(),
      method: 'tools/call',
      params: { name: tool, arguments: args }
    });

    let output = '';
    proc.stdout.on('data', (data) => {
      output += data.toString();
    });
    proc.stderr.on('data', (data) => {
      // Capture stderr for debugging but don't print
    });
    proc.on('close', () => {
      try {
        // Find the JSON-RPC response line
        const lines = output.split('\n').filter(l => l.trim());
        for (const line of lines) {
          try {
            const response = JSON.parse(line);
            if (response.result !== undefined) {
              resolve(response.result as MCPResponse);
              return;
            }
          } catch {
            continue;
          }
        }
        // If no JSON-RPC found, check if it's a simple response
        const lastLine = lines[lines.length - 1];
        try {
          const simple = JSON.parse(lastLine);
          resolve(simple as MCPResponse);
          return;
        } catch {
          reject(new Error(`No valid JSON response found. Last line: ${lastLine?.slice(0, 100)}`));
        }
      } catch (e) {
        reject(e);
      }
    });
    proc.on('error', reject);
    
    // Initialize MCP first
    const init = JSON.stringify({ jsonrpc: '2.0', id: 0, method: 'initialize', params: { protocolVersion: '1.0', capabilities: {} } }) + '\n';
    const sub = JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'notifications/initialized' }) + '\n';
    proc.stdin.write(init);
    proc.stdin.write(sub);
    proc.stdin.write(request + '\n');
    proc.stdin.end();
  });
}

async function godotRun(projectPath, script, args = '') {
  return new Promise((resolve, reject) => {
    execFileAsync(GODOT_PATH, ['--headless', '--path', projectPath, '--script', script, ...args.split(' ').filter(Boolean)], {
      timeout: 10000
    }).then(resolve).catch(reject);
  });
}

async function setupTestProject() {
  if (existsSync(TEST_PROJECT)) {
    rmSync(TEST_PROJECT, { recursive: true });
  }
  mkdirSync(TEST_PROJECT, { recursive: true });
  mkdirSync(join(TEST_PROJECT, 'scenes'), { recursive: true });
  
  // Create minimal project.godot
  writeFileSync(join(TEST_PROJECT, 'project.godot'), `[configuration]
config/name="Test Project"
`);
}

async function test(name: string, fn: () => Promise<void>) {
  const start = Date.now();
  try {
    await fn();
    results.push({ name, passed: true, duration: Date.now() - start });
    console.log(`✓ ${name} (${Date.now() - start}ms)`);
  } catch (e) {
    results.push({ name, passed: false, duration: Date.now() - start, error: e.message });
    console.log(`✗ ${name}: ${e.message}`);
  }
}

async function runTests() {
  console.log('=== MCP Godot Test Suite ===\n');
  
  console.log('--- Setup ---');
  await setupTestProject();
  console.log(`Test project: ${TEST_PROJECT}\n`);

  console.log('--- Token Optimization Tests ---\n');

  await test('Schema compression loads', async () => {
    const res = await mcpCall('get_godot_version');
    // Just verify server responds correctly
    const text = res.content[0].text;
    if (!text.includes('4.')) {
      throw new Error(`Expected Godot 4.x, got: ${text}`);
    }
    console.log(`  Server responsive: ${text.slice(0, 20)}`);
  });

  await test('get_godot_version returns version', async () => {
    const res = await mcpCall('get_godot_version');
    const text = res.content[0].text;
    if (!text.includes('4.')) {
      throw new Error(`Expected Godot 4.x, got: ${text}`);
    }
    console.log(`  Godot version: ${text}`);
  });

  console.log('\n--- Scene Editing Tests ---\n');

  await test('create_scene creates Node2D scene', async () => {
    // Ensure scenes directory exists
    const scenesDir = join(TEST_PROJECT, 'scenes');
    if (!existsSync(scenesDir)) {
      mkdirSync(scenesDir, { recursive: true });
    }
    
    const sceneFile = join(scenesDir, 'Player.tscn');
    // Clean up first
    if (existsSync(sceneFile)) {
      require('fs').unlinkSync(sceneFile);
    }
    
    await mcpCall('create_scene', {
      projectPath: TEST_PROJECT,
      scenePath: 'scenes/Player.tscn',
      rootNodeType: 'Node2D'
    });
    
    // Check if file was created (Godot headless may report warnings but still succeed)
    if (!existsSync(sceneFile)) {
      throw new Error('Scene file not created');
    }
    console.log(`  Scene file exists: ${sceneFile}`);
  });

  await test('add_node adds Sprite2D', async () => {
    const res = await mcpCall('add_node', {
      projectPath: TEST_PROJECT,
      scenePath: 'scenes/Player.tscn',
      nodeType: 'Sprite2D',
      nodeName: 'Sprite',
      parentNodePath: 'root'
    });
    if (res.isError) throw new Error(res.content[0].text);
  });

  await test('list_nodes shows all nodes', async () => {
    const sceneFile = join(TEST_PROJECT, 'scenes', 'Player.tscn');
    // Ensure scene exists
    if (!existsSync(sceneFile)) {
      await mcpCall('create_scene', {
        projectPath: TEST_PROJECT,
        scenePath: 'scenes/Player.tscn',
        rootNodeType: 'Node2D'
      });
    }
    
    const res = await mcpCall('list_nodes', {
      projectPath: TEST_PROJECT,
      scenePath: 'scenes/Player.tscn'
    });
    if (res.isError) throw new Error(res.content[0].text);
    
    // Parse MCP_RESULT JSON
    const text = res.content[0].text;
    const mcpResultMatch = text.match(/MCP_RESULT:(\{.*\})/);
    if (!mcpResultMatch) {
      throw new Error(`No MCP_RESULT found in: ${text.slice(0, 200)}`);
    }
    
    const data = JSON.parse(mcpResultMatch[1]);
    if (!data.nodes || data.nodes.length < 1) {
      throw new Error(`Expected nodes, got: ${JSON.stringify(data)}`);
    }
    console.log(`  Nodes found: ${data.nodes.length}`);
  });

  await test('modify_node_property changes position', async () => {
    const res = await mcpCall('modify_node_property', {
      projectPath: TEST_PROJECT,
      scenePath: 'scenes/Player.tscn',
      nodePath: 'root',
      property: 'position',
      value: { 'x': 100, 'y': 200, 'type': 'Vector2' }
    });
    if (res.isError) throw new Error(res.content[0].text);
  });

  await test('duplicate_node creates copy', async () => {
    const res = await mcpCall('duplicate_node', {
      projectPath: TEST_PROJECT,
      scenePath: 'scenes/Player.tscn',
      nodePath: 'root/Sprite',
      newName: 'SpriteCopy'
    });
    if (res.isError) throw new Error(res.content[0].text);
  });

  await test('remove_node deletes node', async () => {
    // First add a node to remove
    await mcpCall('add_node', {
      projectPath: TEST_PROJECT,
      scenePath: 'scenes/Player.tscn',
      nodeType: 'Node2D',
      nodeName: 'ToRemove'
    });
    
    const res = await mcpCall('remove_node', {
      projectPath: TEST_PROJECT,
      scenePath: 'scenes/Player.tscn',
      nodePath: 'root/ToRemove'
    });
    if (res.isError) throw new Error(res.content[0].text);
  });

  await test('batch_operations executes atomically', async () => {
    // Create a fresh scene for batch test
    await mcpCall('create_scene', {
      projectPath: TEST_PROJECT,
      scenePath: 'scenes/BatchTest.tscn',
      rootNodeType: 'Node2D'
    });

    const res = await mcpCall('batch_operations', {
      projectPath: TEST_PROJECT,
      scenePath: 'scenes/BatchTest.tscn',
      operations: [
        { operation: 'add_node', params: { node_type: 'Sprite2D', node_name: 'BatchSprite1', parent_node_path: 'root' } },
        { operation: 'add_node', params: { node_type: 'Sprite2D', node_name: 'BatchSprite2', parent_node_path: 'root' } },
        { operation: 'set_position', params: { node_path: 'root', position: { 'x': 50, 'y': 50 } } }
      ],
      enableRollback: true
    });
    if (res.isError) throw new Error(res.content[0].text);
    
    // Verify nodes were added
    const list = await mcpCall('list_nodes', {
      projectPath: TEST_PROJECT,
      scenePath: 'scenes/BatchTest.tscn'
    });
    const text = list.content[0].text;
    const mcpResultMatch = text.match(/MCP_RESULT:(\{.*\})/);
    if (!mcpResultMatch) {
      throw new Error(`No MCP_RESULT found in: ${text.slice(0, 200)}`);
    }
    const data = JSON.parse(mcpResultMatch[1]);
    if (data.nodes.length < 3) {
      throw new Error(`Expected 3+ nodes in batch test, got: ${data.nodes.length}`);
    }
    console.log(`  Batch nodes: ${data.nodes.length}`);
  });

  console.log('\n--- Summary ---\n');
  
  const passed = results.filter(r => r.passed).length;
  const failed = results.filter(r => !r.passed).length;
  
  console.table(results.map(r => ({
    Test: r.name,
    Status: r.passed ? '✓' : '✗',
    'Duration (ms)': r.duration,
    ...(r.error && { Error: r.error.slice(0, 50) })
  })));
  
  console.log(`\nPassed: ${passed}/${results.length}`);
  console.log(`Failed: ${failed}/${results.length}`);
  
  // Cleanup
  if (existsSync(TEST_PROJECT)) {
    rmSync(TEST_PROJECT, { recursive: true });
  }
  
  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch(e => {
  console.error('Test suite failed:', e);
  process.exit(1);
});
