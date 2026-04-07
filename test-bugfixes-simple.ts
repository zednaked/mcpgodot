#!/usr/bin/env node

import { spawn } from 'child_process';

const PROJECT_PATH = '/home/zed/dev/alchemy';

async function mcpCall(proc, tool, args = {}) {
  return new Promise((resolve, reject) => {
    const requestId = Date.now();
    const request = JSON.stringify({
      jsonrpc: '2.0',
      id: requestId,
      method: 'tools/call',
      params: { name: tool, arguments: args }
    });

    let output = '';
    const onData = (data) => { output += data.toString(); };
    proc.stdout.on('data', onData);
    
    const checkOutput = () => {
      proc.stdout.off('data', onData);
      const lines = output.split('\n').filter(l => l.trim());
      for (const line of lines) {
        try {
          const response = JSON.parse(line);
          if (response.result !== undefined) {
            resolve(response.result);
            return;
          }
        } catch { continue; }
      }
      resolve({ content: [{ text: output || 'No output' }] });
    };
    
    proc.on('close', checkOutput);
    
    setTimeout(() => {
      proc.stdout.off('data', onData);
      resolve({ content: [{ text: output || 'Timeout' }] });
    }, 8000);
    
    proc.stdin.write(request + '\n');
  });
}

function extractText(result: any): string {
  if (!result) return '';
  // Handle nested result structure
  if (result.result?.content?.[0]?.text) return result.result.content[0].text;
  if (result.content?.[0]?.text) return result.content[0].text;
  return '';
}

async function runTests() {
  console.log('===========================================');
  console.log('MCP Godot - Testes dos Bugs Corrigidos');
  console.log('===========================================\n');

  const proc = spawn('node', ['build/index.js'], { 
    stdio: ['pipe', 'pipe', 'pipe'],
    cwd: '/home/zed/mcpgodot'
  });

  let output = '';
  proc.stdout.on('data', (d) => { output += d.toString(); });
  proc.stderr.on('data', (d) => { /* ignore stderr */ });

  await new Promise(r => setTimeout(r, 500));
  
  const init = JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'test', version: '1.0' } } }) + '\n';
  const sub = JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'notifications/initialized' }) + '\n';
  proc.stdin.write(init);
  proc.stdin.write(sub);
  
  await new Promise(r => setTimeout(r, 500));

  let passed = 0;
  let failed = 0;

  // ========== BUG 1: run_project returns PID ==========
  console.log('🐛 BUG 1: run_project returns PID');
  try {
    const result = await mcpCall(proc, 'run_project', { projectPath: PROJECT_PATH });
    const text = extractText(result);
    console.log('   Result:', text.substring(0, 80));
    if (text.includes('PID:')) {
      console.log('   ✅ PASS\n');
      passed++;
    } else {
      console.log('   ❌ FAIL\n');
      failed++;
    }
  } catch (e: any) {
    console.log('   ❌ FAIL:', e.message, '\n');
    failed++;
  }

  // ========== BUG 2: get_debug_output shows running status ==========
  console.log('🐛 BUG 2: get_debug_output shows running status');
  await new Promise(r => setTimeout(r, 1000));
  try {
    const result = await mcpCall(proc, 'get_debug_output');
    const text = extractText(result);
    console.log('   Text:', text.substring(0, 150));
    try {
      const data = JSON.parse(text);
      if (data?.pid && data?.running !== undefined) {
        console.log('   ✅ PASS - running:', data.running, 'pid:', data.pid, '\n');
        passed++;
      } else {
        console.log('   ❌ FAIL - missing pid or running\n');
        failed++;
      }
    } catch (e) {
      console.log('   ❌ FAIL - not JSON:', e.message, '\n');
      failed++;
    }
  } catch (e: any) {
    console.log('   ❌ FAIL:', e.message, '\n');
    failed++;
  }

  // ========== BUG 3: run_scene shows output ==========
  console.log('🐛 BUG 3: run_scene shows output');
  try {
    const result = await mcpCall(proc, 'run_scene', { 
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/main.tscn'
    });
    const text = extractText(result);
    console.log('   Result:', text.substring(0, 80));
    if (text.includes('Output:') || text.includes('exit code') || text.includes('✅') || text.includes('❌')) {
      console.log('   ✅ PASS\n');
      passed++;
    } else {
      console.log('   ❌ FAIL\n');
      failed++;
    }
  } catch (e: any) {
    console.log('   ❌ FAIL:', e.message, '\n');
    failed++;
  }

  // ========== BUG 4: runtime_start_debug ==========
  console.log('🐛 BUG 4: runtime_start_debug waits for server');
  try {
    await mcpCall(proc, 'stop_project');
  } catch {}
  await new Promise(r => setTimeout(r, 500));
  
  try {
    const result = await mcpCall(proc, 'runtime_start_debug', { projectPath: PROJECT_PATH });
    const text = extractText(result);
    console.log('   Result:', text.substring(0, 80));
    if (text.includes('ready') || text.includes('✅')) {
      console.log('   ✅ PASS\n');
      passed++;
    } else {
      console.log('   ❌ FAIL\n');
      failed++;
    }
  } catch (e: any) {
    console.log('   ❌ FAIL:', e.message, '\n');
    failed++;
  }

  // ========== BUG 5: validate_scene path handling ==========
  console.log('🐛 BUG 5: validate_scene handles paths');
  try {
    const result = await mcpCall(proc, 'validate_scene', { 
      projectPath: PROJECT_PATH,
      scenePath: 'res://scenes/main.tscn'
    });
    const text = extractText(result);
    console.log('   Result:', text.substring(0, 80));
    if (!text.includes('ERROR') && !text.includes('Failed')) {
      console.log('   ✅ PASS\n');
      passed++;
    } else {
      console.log('   ❌ FAIL\n');
      failed++;
    }
  } catch (e: any) {
    console.log('   ❌ FAIL:', e.message, '\n');
    failed++;
  }

  // Cleanup
  try {
    await mcpCall(proc, 'stop_project');
  } catch {}
  
  await new Promise(r => setTimeout(r, 500));
  proc.kill();

  console.log('===========================================');
  console.log('RESUMO');
  console.log('===========================================');
  console.log(`✅ Passed: ${passed}`);
  console.log(`❌ Failed: ${failed}`);
  console.log(`📊 Success Rate: ${(passed/(passed+failed)*100).toFixed(1)}%`);

  process.exit(failed > 0 ? 1 : 0);
}
  } catch (e) {
    console.log('   ❌ FAIL:', e.message, '\n');
    failed++;
  }

  // ========== BUG 2: get_debug_output shows running status ==========
  console.log('🐛 BUG 2: get_debug_output shows running status');
  await new Promise(r => setTimeout(r, 1000));
  try {
    const result: any = await mcpCall(proc, 'get_debug_output');
    const raw = JSON.stringify(result);
    console.log('   Raw:', raw.substring(0, 100));
    const text = result?.result?.content?.[0]?.text || '';
    console.log('   Text:', text.substring(0, 100));
    try {
      const data = JSON.parse(text);
      console.log('   Data:', JSON.stringify(data).substring(0, 80));
      if (data?.pid && data?.running !== undefined) {
        console.log('   ✅ PASS - running:', data.running, 'pid:', data.pid, '\n');
        passed++;
      } else {
        console.log('   ❌ FAIL - missing pid or running\n');
        failed++;
      }
    } catch (e) {
      console.log('   ❌ FAIL - not JSON:', e.message, '\n');
      failed++;
    }
  } catch (e) {
    console.log('   ❌ FAIL:', e.message, '\n');
    failed++;
  }

  // ========== BUG 3: run_scene shows output ==========
  console.log('🐛 BUG 3: run_scene shows output');
  try {
    const result: any = await mcpCall(proc, 'run_scene', { 
      projectPath: PROJECT_PATH,
      scenePath: 'scenes/main.tscn'
    });
    const text = result?.content?.[0]?.text || '';
    console.log('   Result:', text.substring(0, 80));
    if (text.includes('Output:') || text.includes('exit code') || text.includes('✅') || text.includes('❌')) {
      console.log('   ✅ PASS\n');
      passed++;
    } else {
      console.log('   ❌ FAIL\n');
      failed++;
    }
  } catch (e) {
    console.log('   ❌ FAIL:', e.message, '\n');
    failed++;
  }

  // ========== BUG 4: runtime_start_debug ==========
  console.log('🐛 BUG 4: runtime_start_debug waits for server');
  try {
    await mcpCall(proc, 'stop_project');
  } catch {}
  await new Promise(r => setTimeout(r, 500));
  
  try {
    const result: any = await mcpCall(proc, 'runtime_start_debug', { projectPath: PROJECT_PATH });
    const text = result?.content?.[0]?.text || '';
    console.log('   Result:', text.substring(0, 80));
    if (text.includes('ready') || text.includes('✅')) {
      console.log('   ✅ PASS\n');
      passed++;
    } else {
      console.log('   ❌ FAIL\n');
      failed++;
    }
  } catch (e) {
    console.log('   ❌ FAIL:', e.message, '\n');
    failed++;
  }

  // ========== BUG 5: validate_scene path handling ==========
  console.log('🐛 BUG 5: validate_scene handles paths');
  try {
    const result: any = await mcpCall(proc, 'validate_scene', { 
      projectPath: PROJECT_PATH,
      scenePath: 'res://scenes/main.tscn'
    });
    const text = result?.content?.[0]?.text || '';
    console.log('   Result:', text.substring(0, 80));
    if (!text.includes('ERROR') && !text.includes('Failed')) {
      console.log('   ✅ PASS\n');
      passed++;
    } else {
      console.log('   ❌ FAIL\n');
      failed++;
    }
  } catch (e) {
    console.log('   ❌ FAIL:', e.message, '\n');
    failed++;
  }

  // Cleanup
  try {
    await mcpCall(proc, 'stop_project');
  } catch {}
  
  await new Promise(r => setTimeout(r, 500));
  proc.kill();

  console.log('===========================================');
  console.log('RESUMO');
  console.log('===========================================');
  console.log(`✅ Passed: ${passed}`);
  console.log(`❌ Failed: ${failed}`);
  console.log(`📊 Success Rate: ${(passed/(passed+failed)*100).toFixed(1)}%`);

  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});