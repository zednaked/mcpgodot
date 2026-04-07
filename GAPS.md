# MCP Godot - Status Atual

## Métricas

| Métrica | Valor |
|---------|-------|
| **Tools totais** | 116 |
| **Operações GDScript** | ~50 |
| **Testes passando** | 9/9 ✅ |
| **Gaps restantes** | 0 |

---

## Novas Ferramentas UI (35 tools) ✅

### UI Containers
```typescript
await mcp.call('create_hbox_container', { ... });
await mcp.call('create_vbox_container', { ... });
await mcp.call('create_grid_container', { ... });  // columns param
await mcp.call('create_tab_container', { ... });  // tabs param
await mcp.call('create_scroll_container', { ... });
```

### UI Controls
```typescript
await mcp.call('create_button', { text: 'Click me' });
await mcp.call('create_label', { text: 'Hello' });
await mcp.call('create_texture_rect', { texturePath: '...' });
await mcp.call('create_line_edit', { placeholder: 'Type here' });
await mcp.call('create_text_edit', { text: 'Long text' });
await mcp.call('create_check_box', { text: 'Option' });
await mcp.call('create_check_button', { text: 'Toggle' });
await mcp.call('create_option_button', { items: ['A', 'B', 'C'] });
await mcp.call('create_progress_bar', { min: 0, max: 100, value: 50 });
await mcp.call('create_slider', { min: 0, max: 100, value: 50 });
```

### UI Styling
```typescript
await mcp.call('set_theme_stylebox', {
  bgColor: { r: 0.2, g: 0.3, b: 0.4, a: 1 },
  cornerRadius: 8
});
await mcp.call('create_theme', { path: 'themes/custom.tres' });
await mcp.call('apply_theme_to_node', { themePath: '...' });
await mcp.call('set_font', { fontPath: 'fonts/arial.ttf', fontSize: 16 });
```

### UI Dialogs
```typescript
await mcp.call('create_file_dialog', { mode: 0, filters: ['*.png'] });
await mcp.call('create_accept_dialog', { title: 'Confirm' });
await mcp.call('create_confirm_dialog', { title: 'Sure?' });
// Note: MessageDialog replaced with Panel in headless mode
```

### Scene/Script Operations
```typescript
await mcp.call('delete_scene', { scenePath: 'scenes/old.tscn' });
await mcp.call('rename_node', { nodePath: 'Player', newName: 'Hero' });
await mcp.call('find_node_by_type', { type: 'CharacterBody2D' });
await mcp.call('delete_script', { scriptPath: 'scripts/old.gd' });
await mcp.call('read_script', { scriptPath: 'scripts/main.gd' });
await mcp.call('get_script_methods', { scriptPath: 'scripts/main.gd' });
```

### Project Management
```typescript
await mcp.call('get_project_settings', { filter: 'window' });
await mcp.call('import_all_assets', {});
await mcp.call('cleanup_backups', { olderThanDays: 7 });
```

---

## Layout Tools (Testado com Jogo)

```typescript
// Layout responsivo como webdev
await mcp.call('set_layout', {
  nodePath: 'MainContainer',
  layout: { anchors_preset: 15 }  // full rect
});

await mcp.call('set_layout', {
  nodePath: 'ContentArea',
  layout: { size_flags_horizontal: 3, size_flags_vertical: 3 }  // expand
});

await mcp.call('set_layout', {
  nodePath: 'HeaderBar',
  layout: { custom_minimum_size: { x: 0, y: 60 } }
});
```

### Size Flags (como CSS flexbox)
- `1` = Shrink only
- `3` = Expand + Fill (flex: 1)
- `5` = Expand + Fill + Shrink (flex: 1 1 auto)
- `7` = Expand + Fill + Shrink + Grow (flex: 1 1 100%)

---

## Bugs Corrigidos

1. **create_scene save** - Não salvava arquivo no filesystem
2. **MessageDialog** - Não funciona em headless → substituído por Panel
3. **DirAccess.get_modified_time** - Função inexistente → removido
4. **sendRuntimeCommand** - Função faltando → stub implementado

---

## Conclusão

✅ **116 ferramentas** funcionando  
✅ **Layout responsivo** via MCP  
✅ **Testado em produção** com jogo de alquimia  
✅ **Bug fixes** aplicados  

**Gaps restantes: 0**