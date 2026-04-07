#!/usr/bin/env node

import { spawn } from 'child_process';

const PROJECT_PATH = '/home/zed/dev/alchemy';

function extractText(result: unknown): string {
  if (!result) return '';
  const r = result as Record<string, unknown>;
  // Handle MCP response: {"result":{"content":[{"type":"text","text":"..."}]}}
  if (r.result && typeof r.result === 'object') {
    const rp = r.result as Record<string, unknown>;
    if (Array.isArray(rp.content)) {
      const content = rp.content[0] as Record<string, string>;
      if (content?.text) {
        return content.text;
      }
    }
  }
  if (Array.isArray(r.content)) {
    return (r.content[0] as Record<string, string>)?.text || '';
  }
  return '';
}

async function mcpCall(proc: ReturnType<typeof spawn>, tool: string, args = {}, timeoutMs = 8000) {
  return new Promise((resolve) => {
    const requestId = Date.now();
    const request = JSON.stringify({
      jsonrpc: '2.0',
      id: requestId,
      method: 'tools/call',
      params: { name: tool, arguments: args }
    });

    let output = '';
    const onData = (data: Buffer) => { output += data.toString(); };
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
    }, timeoutMs);
    
    proc.stdin.write(request + '\n');
  });
}

async function runTests() {
  console.log('===========================================');
  console.log('MCP Godot - Testes dos Bugs Corrigidos');
  console.log('===========================================\n');

  const proc = spawn('node', ['build/index.js'], { 
    stdio: ['pipe', 'pipe', 'pipe'],
    cwd: '/home/zed/mcpgodot'
  });

  proc.stdout.on('data', (d) => { /* collect output in test handlers */ });
  proc.stderr.on('data', () => { /* ignore */ });

  await new Promise(r => setTimeout(r, 500));
  
  const init = JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'test', version: '1.0' } } }) + '\n';
  const sub = JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'notifications/initialized' }) + '\n';
  proc.stdin.write(init);
  proc.stdin.write(sub);
  
  await new Promise(r => setTimeout(r, 500));

  let passed = 0;
  let failed = 0;

  // BUG 1
  console.log('🐛 BUG 1: run_project returns PID');
  const r1: any = await mcpCall(proc, 'run_project', { projectPath: PROJECT_PATH });
  const t1 = extractText(r1);
  console.log('   Result:', t1.substring(0, 80));
  if (t1.includes('PID:')) { console.log('   ✅ PASS\n'); passed++; } 
  else { console.log('   ❌ FAIL\n'); failed++; }

  // BUG 2
  console.log('🐛 BUG 2: get_debug_output shows running status');
  await new Promise(r => setTimeout(r, 1000));
  const r2: any = await mcpCall(proc, 'get_debug_output');
  const t2 = extractText(r2);
  console.log('   Text:', t2.substring(0, 120));
  try {
    // The result is double-encoded in MCP, parse the outer wrapper first
    // Then parse the inner JSON that's stored as text
    const outer = JSON.parse(t2);
    const innerText = outer.result?.content?.[0]?.text || outer.content?.[0]?.text || t2;
    const data = JSON.parse(innerText);
    console.log('   Data:', JSON.stringify(data).substring(0, 80));
    if (data?.pid && data?.running !== undefined) { console.log('   ✅ PASS\n'); passed++; } 
    else { console.log('   ❌ FAIL - missing data\n'); failed++; }
  } catch (e) { console.log('   ❌ FAIL - parse error:', e.message, '\n'); failed++; }

  // BUG 3
  console.log('🐛 BUG 3: run_scene shows output');
  const r3: any = await mcpCall(proc, 'run_scene', { projectPath: PROJECT_PATH, scenePath: 'scenes/main.tscn' });
  const t3 = extractText(r3);
  console.log('   Result:', t3.substring(0, 80));
  if (t3.includes('Output:') || t3.includes('exit code') || t3.includes('✅') || t3.includes('❌')) { console.log('   ✅ PASS\n'); passed++; } 
  else { console.log('   ❌ FAIL\n'); failed++; }

  // BUG 4
  console.log('🐛 BUG 4: runtime_start_debug waits for server');
  await mcpCall(proc, 'stop_project');
  await new Promise(r => setTimeout(r, 500));
  const r4: any = await mcpCall(proc, 'runtime_start_debug', { projectPath: PROJECT_PATH });
  const t4 = extractText(r4);
  console.log('   Result:', t4.substring(0, 80));
  if (t4.includes('ready') || t4.includes('✅')) { console.log('   ✅ PASS\n'); passed++; } 
  else { console.log('   ❌ FAIL\n'); failed++; }

  // BUG 5
  console.log('🐛 BUG 5: validate_scene handles paths');
  const r5: any = await mcpCall(proc, 'validate_scene', { projectPath: PROJECT_PATH, scenePath: 'res://scenes/main.tscn' });
  const t5 = extractText(r5);
  console.log('   Result:', t5.substring(0, 80));
  if (!t5.includes('ERROR') && !t5.includes('Failed')) { console.log('   ✅ PASS\n'); passed++; } 
  else { console.log('   ❌ FAIL\n'); failed++; }

  await mcpCall(proc, 'stop_project');
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

runTests().catch(e => { console.error('Fatal:', e); process.exit(1); });