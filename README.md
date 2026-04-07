# mcpgodot

MCP server para Godot 4.x com operações avançadas de cenas e otimização de tokens.

## Requisitos

- Node.js 18+
- Godot 4.x instalado

## Instalação

```bash
# Clonar repositório
git clone https://github.com/zednaked/mcpgodot.git
cd mcpgodot

# Instalar dependências
npm install

# Build
npm run build
```

### Instalação Global

```bash
npm install
npm run build
sudo npm link
# ou
npm install -g .
```

## Uso

```bash
# Executar servidor
node build/index.js

# Com compressão de tokens
COMPRESSION_LEVEL=high node build/index.js

# Com debug
DEBUG=true node build/index.js

# Com Godot específico
GODOT_PATH=/usr/local/bin/godot node build/index.js
```

## Configuração

| Variável | Valores | Default | Descrição |
|----------|---------|---------|-----------|
| `COMPRESSION_LEVEL` | `none`, `medium`, `high`, `max` | `medium` | Compressão de schema |
| `DEBUG` | `true`, `false` | `false` | Logs de debug |
| `GODOT_PATH` | path | auto | Caminho do Godot |

## Ferramentas (116 total)

### Editor

| Ferramenta | Descrição |
|------------|-----------|
| `launch_editor` | Abre Godot editor |
| `run_project` | Executa projeto |
| `get_debug_output` | Captura output |
| `stop_project` | Para execução |
| `get_godot_version` | Versão do Godot |
| `list_projects` | Lista projetos |
| `get_project_info` | Info do projeto |

### Scene

| Ferramenta | Descrição |
|------------|-----------|
| `create_scene` | Cria cena |
| `add_node` | Adiciona nó |
| `add_node_with_script` | Nó + script |
| `remove_node` | Remove nó |
| `duplicate_node` | Duplica nó |
| `move_node` | Move/repara nó |
| `list_nodes` | Lista nós |
| `batch_operations` | Operações atômicas |
| `generate_nodes` | Cria múltiplos nós |
| `load_sprite` | Carrega textura |
| `save_scene` | Salva cena |
| `modify_node_property` | Modifica propriedade |

### Node Info

| Ferramenta | Descrição |
|------------|-----------|
| `get_node_info` | Info completa do nó |
| `get_node_property` | Get property |
| `set_node_property` | Set property |

### Transform

| Ferramenta | Descrição |
|------------|-----------|
| `get_node_transform` | Get transform |
| `set_node_position` | Set position |
| `set_node_rotation` | Set rotation |
| `set_node_scale` | Set scale |

### Hierarchy

| Ferramenta | Descrição |
|------------|-----------|
| `get_parent_path` | Get parent |
| `get_children` | Lista filhos |
| `has_child` | Verifica filho |

### Signals

| Ferramenta | Descrição |
|------------|-----------|
| `connect_signal` | Conecta sinal |
| `disconnect_signal` | Desconecta sinal |
| `emit_node_signal` | Emite sinal |

### Groups

| Ferramenta | Descrição |
|------------|-----------|
| `get_groups` | Lista grupos |
| `add_to_group` | Adiciona a grupo |
| `remove_from_group` | Remove de grupo |
| `call_group_method` | Chama método em grupo |

### UID (Godot 4.4+)

| Ferramenta | Descrição |
|------------|-----------|
| `get_uid` | Obtém UID |
| `resave_resources` | Atualiza UIDs |

### Scene & Script

| Ferramenta | Descrição |
|------------|-----------|
| `instance_scene` | Instancia cena |
| `create_script` | Cria script |
| `attach_script` | Anexa script a nó |
| `edit_script` | Edita script |

### Resources

| Ferramenta | Descrição |
|------------|-----------|
| `create_resource` | Cria recurso |
| `list_resources` | Lista assets |

### 3D Scene

| Ferramenta | Descrição |
|------------|-----------|
| `create_scene_3d` | Cria cena 3D |
| `add_node_3d` | Adiciona nó 3D |
| `set_node_position_3d` | Posição 3D |
| `set_node_rotation_3d` | Rotação 3D |
| `set_node_scale_3d` | Escala 3D |

### Executar

| Ferramenta | Descrição |
|------------|-----------|
| `run_scene` | Executa cena/projeto |
| `export_project` | Exporta para plataforma |
| `validate_scene` | Valida estrutura da cena |

### Project Settings

| Ferramenta | Descrição |
|------------|-----------|
| `get_project_setting` | Ler configuração |
| `set_project_setting` | Modificar configuração |

### Input

| Ferramenta | Descrição |
|------------|-----------|
| `list_input_actions` | Listar ações de input |
| `create_input_action` | Criar ação de input |

### Collision

| Ferramenta | Descrição |
|------------|-----------|
| `add_collision_layer` | Adicionar layer de colisão |
| `set_collision_mask` | Configurar mask |

### Assets

| Ferramenta | Descrição |
|------------|-----------|
| `import_asset` | Importar asset |

### Animation

| Ferramenta | Descrição |
|------------|-----------|
| `create_animation` | Criar animação |
| `add_animation_track` | Adicionar track |

### Find

| Ferramenta | Descrição |
|------------|-----------|
| `find_nodes` | Buscar nós |

### Script

| Ferramenta | Descrição |
|------------|-----------|
| `execute_gdscript` | Executar GDScript |

### Snapshot

| Ferramenta | Descrição |
|------------|-----------|
| `snapshot_scene` | Salvar estado da cena |
| `compare_scenes` | Comparar cenas |

### UI Layout

| Ferramenta | Descrição |
|------------|-----------|
| `set_layout` | Define layout completo |
| `apply_layout_preset` | Aplica preset de layout |
| `copy_layout` | Copia layout entre nós |
| `list_layout_presets` | Lista presets disponíveis |

### Runtime Debug

| Ferramenta | Descrição |
|------------|-----------|
| `runtime_connect` | Conectar ao servidor de debug do jogo |
| `runtime_start_debug` | Iniciar jogo com servidor de debug |
| `runtime_list_nodes` | Listar nós do jogo em execução |
| `runtime_get_property` | Ler propriedade em tempo real |
| `runtime_set_property` | Modificar propriedade enquanto jogo roda |
| `runtime_call_method` | Chamar método de um nó |
| `runtime_get_tree_info` | Info da árvore do jogo |
| `runtime_find_node` | Buscar nó por nome/tipo |
| `runtime_get_node_info` | Info completa de um nó |
| `runtime_eval_gdscript` | Executar GDScript no jogo |

### UI Containers

| Ferramenta | Descrição |
|------------|-----------|
| `create_hbox_container` | Cria HBoxContainer |
| `create_vbox_container` | Cria VBoxContainer |
| `create_grid_container` | Cria GridContainer |
| `create_tab_container` | Cria TabContainer |
| `create_scroll_container` | Cria ScrollContainer |

### UI Controls

| Ferramenta | Descrição |
|------------|-----------|
| `create_button` | Cria Button |
| `create_label` | Cria Label |
| `create_texture_rect` | Cria TextureRect (imagem) |
| `create_line_edit` | Cria LineEdit (input) |
| `create_text_edit` | Cria TextEdit (textarea) |
| `create_check_box` | Cria CheckBox |
| `create_check_button` | Cria CheckButton (toggle) |
| `create_option_button` | Cria OptionButton (dropdown) |
| `create_progress_bar` | Cria ProgressBar |
| `create_slider` | Cria HSlider |

### UI Styling

| Ferramenta | Descrição |
|------------|-----------|
| `set_theme_stylebox` | Define StyleBoxFlat |
| `create_theme` | Cria Theme resource |
| `apply_theme_to_node` | Aplica theme a nó |
| `set_font` | Define fonte |

### UI Dialogs

| Ferramenta | Descrição |
|------------|-----------|
| `create_file_dialog` | Cria FileDialog |
| `create_accept_dialog` | Cria AcceptDialog |
| `create_confirm_dialog` | Cria ConfirmDialog |
| `create_message_dialog` | Cria MessageDialog |

### Scene Operations

| Ferramenta | Descrição |
|------------|-----------|
| `delete_scene` | Deleta cena |
| `rename_node` | Renomeia nó |
| `find_node_by_type` | Busca por tipo |

### Script Operations

| Ferramenta | Descrição |
|------------|-----------|
| `delete_script` | Deleta script |
| `read_script` | Lê script |
| `get_script_methods` | Lista métodos |

### Project Management

| Ferramenta | Descrição |
|------------|-----------|
| `get_project_settings` | Lista settings |
| `import_all_assets` | Reimporta assets |
| `cleanup_backups` | Limpa backups |

### Debugging

| Ferramenta | Descrição |
|------------|-----------|
| `log_to_console` | Log no console |

## Exemplos

### Criar Cena com Nós

```typescript
// Criar cena
await mcp.call('create_scene', {
  projectPath: '/path/to/project',
  scenePath: 'Player.tscn',
  rootNodeType: 'CharacterBody2D'
});

// Adicionar nós
await mcp.call('add_node', {
  projectPath: '/path/to/project',
  scenePath: 'Player.tscn',
  nodeType: 'Sprite2D',
  nodeName: 'Sprite',
  parentNodePath: 'root'
});

await mcp.call('add_node', {
  projectPath: '/path/to/project',
  scenePath: 'Player.tscn',
  nodeType: 'CollisionShape2D',
  nodeName: 'Collision'
});
```

### Modificar Propriedades

```typescript
// Setar posição
await mcp.call('set_node_position', {
  projectPath: '/path/to/project',
  scenePath: 'Player.tscn',
  nodePath: 'root',
  position: { x: 100, y: 200 }
});

// Modificar propriedade
await mcp.call('set_node_property', {
  projectPath: '/path/to/project',
  scenePath: 'Player.tscn',
  nodePath: 'root/Sprite',
  property: 'modulate',
  value: { type: 20, type_name: 'Color', value: { r: 1, g: 0, b: 0, a: 1 } }
});
```

### Operações em Batch

```typescript
await mcp.call('batch_operations', {
  projectPath: '/path/to/project',
  scenePath: 'Player.tscn',
  operations: [
    { operation: 'add_node', params: { node_type: 'Sprite2D', node_name: 'Shadow', parent_node_path: 'root' }},
    { operation: 'modify_property', params: { node_path: 'root', property: 'position', value: { x: 100, y: 200 }}},
    { operation: 'set_position', params: { node_path: 'root', position: { x: 50, y: 50 }}}
  ],
  enableRollback: true
});
```

### Conectar Sinais

```typescript
await mcp.call('connect_signal', {
  projectPath: '/path/to/project',
  scenePath: 'Player.tscn',
  fromNode: 'Area2D',
  signal: 'body_entered',
  toNode: 'Player',
  method: '_on_area_entered'
});
```

### Trabalhar com Grupos

```typescript
// Adicionar a grupo
await mcp.call('add_to_group', {
  projectPath: '/path/to/project',
  scenePath: 'Enemy.tscn',
  nodePath: 'root',
  group: 'enemies'
});

// Chamar método em todos do grupo
await mcp.call('call_group_method', {
  projectPath: '/path/to/project',
  scenePath: 'Level.tscn',
  group: 'enemies',
  method: 'take_damage',
  args: [{ type: 2, value: 10 }]
});
```

### Listar Nós com Filtros

```typescript
// Campos específicos
const result = await mcp.call('list_nodes', {
  projectPath: '/path/to/project',
  scenePath: 'Player.tscn',
  fields: ['name', 'type'],
  maxDepth: 2
});

// Resultado
{
  "nodes": [
    { "name": "root", "type": "CharacterBody2D" },
    { "name": "Sprite", "type": "Sprite2D" },
    { "name": "Collision", "type": "CollisionShape2D" }
  ],
  "count": 3
}
```

### Scripts

```typescript
// Criar script com template
await mcp.call('create_script', {
  projectPath: '/path/to/project',
  scriptPath: 'scripts/Player.gd',
  template: 'character'
});

// Editar script
await mcp.call('edit_script', {
  projectPath: '/path/to/project',
  scriptPath: 'scripts/Player.gd',
  content: 'extends CharacterBody2D\n\nfunc _ready() -> void:\n\tprint("Hello!")'
});

// Anexar script a nó existente
await mcp.call('attach_script', {
  projectPath: '/path/to/project',
  scenePath: 'scenes/Main.tscn',
  nodePath: 'Enemy',
  scriptPath: 'scripts/EnemyAI.gd'
});
```

### Resources

```typescript
// Criar shape de colisão
await mcp.call('create_resource', {
  projectPath: '/path/to/project',
  type: 'CircleShape2D',
  path: 'resources/coin_shape.tres',
  properties: { radius: 16 }
});

// Criar PhysicsMaterial
await mcp.call('create_resource', {
  projectPath: '/path/to/project',
  type: 'PhysicsMaterial',
  path: 'resources/bouncy.tres',
  properties: { friction: 0.5, bounce: 1.0 }
});

// Listar assets do projeto
await mcp.call('list_resources', {
  projectPath: '/path/to/project',
  extensions: ['*.gd', '*.tscn', '*.tres', '*.png'],
  recursive: true
});
```

### 3D

```typescript
// Criar cena 3D
await mcp.call('create_scene_3d', {
  projectPath: '/path/to/project',
  scenePath: 'scenes/World.tscn',
  rootNodeType: 'Node3D'
});

// Adicionar nó 3D
await mcp.call('add_node_3d', {
  projectPath: '/path/to/project',
  scenePath: 'scenes/World.tscn',
  nodeName: 'Player',
  nodeType: 'CharacterBody3D',
  parentNodePath: 'root'
});

// Posicionar na cena 3D
await mcp.call('set_node_position_3d', {
  projectPath: '/path/to/project',
  scenePath: 'scenes/World.tscn',
  nodePath: 'Player',
  position: { x: 10, y: 5, z: -3 }
});
```

### Executar

```typescript
// Executar projeto
await mcp.call('run_scene', {
  projectPath: '/path/to/project'
});
```

### Exportar e Validar

```typescript
// Validar cena
const result = await mcp.call('validate_scene', {
  projectPath: '/path/to/project',
  scenePath: 'scenes/Player.tscn'
});
// Retorna: valid, issues[], warnings[]

// Exportar projeto (requer Godot editor com export templates)
await mcp.call('export_project', {
  projectPath: '/path/to/project',
  preset: 'Linux',
  outputPath: '/tmp/export'
});
```

### Project Settings

```typescript
// Ler configuração
await mcp.call('get_project_setting', {
  projectPath: '/path/to/project',
  setting: 'physics/2d/default_gravity'
});

// Modificar configuração
await mcp.call('set_project_setting', {
  projectPath: '/path/to/project',
  setting: 'physics/2d/default_gravity',
  value: 980
});
```

### Input Actions

```typescript
// Listar ações
await mcp.call('list_input_actions', {
  projectPath: '/path/to/project'
});

// Criar ação
await mcp.call('create_input_action', {
  projectPath: '/path/to/project',
  action: 'jump',
  events: [{ type: 'key', keycode: 'Space' }]
});
```

### Collision

```typescript
// Adicionar layer de colisão
await mcp.call('add_collision_layer', {
  projectPath: '/path/to/project',
  scenePath: 'scenes/Player.tscn',
  nodePath: 'CollisionShape2D',
  layer: 2
});

// Configurar mask
await mcp.call('set_collision_mask', {
  projectPath: '/path/to/project',
  scenePath: 'scenes/Player.tscn',
  nodePath: 'CollisionShape2D',
  mask: 3
});
```

### Animation

```typescript
// Criar animação
await mcp.call('create_animation', {
  projectPath: '/path/to/project',
  scenePath: 'scenes/Player.tscn',
  animationName: 'walk',
  duration: 1.0,
  loop: true
});

// Adicionar track com keyframes
await mcp.call('add_animation_track', {
  projectPath: '/path/to/project',
  scenePath: 'scenes/Player.tscn',
  animationName: 'walk',
  nodePath: 'Sprite',
  property: 'position:x',
  keyframes: [
    { time: 0, value: 0 },
    { time: 0.5, value: 100 }
  ]
});
```

### Find Nodes

```typescript
// Buscar nós por tipo
await mcp.call('find_nodes', {
  projectPath: '/path/to/project',
  scenePath: 'scenes/Level.tscn',
  type: 'CollisionShape2D'
});

// Buscar por padrão de nome
await mcp.call('find_nodes', {
  projectPath: '/path/to/project',
  scenePath: 'scenes/Level.tscn',
  namePattern: '*Enemy*'
});
```

### Snapshot & Compare

```typescript
// Salvar snapshot
await mcp.call('snapshot_scene', {
  projectPath: '/path/to/project',
  scenePath: 'scenes/Player.tscn',
  outputPath: 'snapshots/player_v1.json'
});

// Comparar cenas
await mcp.call('compare_scenes', {
  projectPath: '/path/to/project',
  sceneA: 'scenes/Player_v1.tscn',
  sceneB: 'scenes/Player_v2.tscn'
});
```

### UI Layout

```typescript
// Aplicar preset de layout
await mcp.call('apply_layout_preset', {
  projectPath: '/path/to/project',
  scenePath: 'scenes/UI.tscn',
  nodePath: 'Panel',
  preset: 'top_bar'
});

// Definir layout completo
await mcp.call('set_layout', {
  projectPath: '/path/to/project',
  scenePath: 'scenes/UI.tscn',
  nodePath: 'Panel',
  layout: {
    anchors_preset: 15,
    offset_left: 0,
    offset_top: 0,
    offset_right: 800,
    offset_bottom: 60
  }
});

// Copiar layout entre nós
await mcp.call('copy_layout', {
  projectPath: '/path/to/project',
  scenePath: 'scenes/UI.tscn',
  fromNode: 'PanelTemplate',
  toNode: 'PanelNew'
});

// Listar presets disponíveis
await mcp.call('list_layout_presets', {});
```

### Runtime Debug

O mcpgodot suporta operação em runtime! Você pode conectar a um jogo em execução e manipular propriedades, chamar métodos, e inspecionar o estado do jogo em tempo real.

#### Como usar:

1. **Inicie o jogo com debug server:**
   
   Use a ferramenta `runtime_start_debug` que carrega automaticamente o script de debug:

```typescript
// Iniciar jogo com servidor de debug
await mcp.call('runtime_start_debug', {
  projectPath: '/path/to/project',
  scenePath: 'scenes/Main.tscn'  // opcional
});
```

O servidor de debug inicia automaticamente na porta 9090.

2. **Use as ferramentas runtime:**

```typescript
// Iniciar jogo com debug (forma recomendada)
await mcp.call('runtime_start_debug', {
  projectPath: '/path/to/project'
});

// Conectar ao jogo em execução
await mcp.call('runtime_connect', {
  projectPath: '/path/to/project'
});

// Listar todos os nós do jogo
await mcp.call('runtime_list_nodes', {
  projectPath: '/path/to/project',
  maxDepth: 10
});

// Ler propriedade de um nó
await mcp.call('runtime_get_property', {
  projectPath: '/path/to/project',
  nodePath: '/root/root/Player',
  property: 'position'
});

// Modificar propriedade (mover jogador)
await mcp.call('runtime_set_property', {
  projectPath: '/path/to/project',
  nodePath: '/root/root/Player',
  property: 'position',
  value: { x: 100, y: 200, _type: 'Vector2' }
});

// Chamar método (iniciar bola)
await mcp.call('runtime_call_method', {
  projectPath: '/path/to/project',
  nodePath: '/root/root/Ball',
  method: 'launch',
  args: [{ x: 0.3, y: -1, _type: 'Vector2' }]
});

// Buscar nó por tipo
await mcp.call('runtime_find_node', {
  projectPath: '/path/to/project',
  type: 'CharacterBody2D'
});

// Info completa de um nó
await mcp.call('runtime_get_node_info', {
  projectPath: '/path/to/project',
  nodePath: '/root/root/Player'
});
```

#### Servidor de Debug

O servidor de debug usa TCP na porta 9090 e suporta:
- Ler/modificar propriedades
- Chamar métodos com argumentos
- Serialização automática de Vector2, Vector3, Color
- Listar e buscar nós dinamicamente

## Otimização de Tokens

### Schema Compression

```bash
# Níveis de compressão
COMPRESSION_LEVEL=none   # Full schema (~4000 tokens)
COMPRESSION_LEVEL=medium # Descriptions curtas (~1500 tokens)
COMPRESSION_LEVEL=high   # Só nomes + params (~800 tokens)
COMPRESSION_LEVEL=max     # Só nomes (~300 tokens)
```

### Response Filtering

```typescript
// Filtrar campos
await mcp.call('list_nodes', {
  scenePath: 'scene.tscn',
  fields: ['name', 'type']  // Só estes campos
});
```

### Scene Cache

Cache automático com TTL de 60s para `list_nodes`.

## Testes

```bash
# Executar suite de testes
npx ts-node test-suite.ts

# Resultados
Passed: 9/9
Failed: 0/9
```

## Estrutura

```
mcpgodot/
├── src/
│   ├── index.ts              # Server MCP (TypeScript)
│   └── scripts/
│       └── godot_operations.gd  # Operações em arquivos de cena (GDScript)
├── scripts/
│   └── mcp_debug_server.gd   # Servidor de debug runtime
├── build/                    # Compiled output
├── test-suite.ts            # Tests
├── TEST_PLAN.md             # Plano de testes
├── TOKEN_OPTIMIZATION.md    # Estratégias de tokens
├── GAPS.md                  # Lacunas identificadas
└── package.json
```

## Requisitos

- Node.js >= 18.0.0
- Godot 4.x
- TypeScript 5.x

## Referências

- [godot-mcp](https://github.com/Coding-Solo/godot-mcp) - Projeto original
- [MCP SDK](https://github.com/modelcontextprotocol/sdk)
- [Godot Engine](https://godotengine.org)

## Licença

MIT

## Changelog

### 1.1.0 (2026-04-07)
- **35 novas ferramentas de UI** para produção de interfaces completas
- **UI Containers**: create_hbox_container, create_vbox_container, create_grid_container, create_tab_container, create_scroll_container
- **UI Controls**: create_button, create_label, create_texture_rect, create_line_edit, create_text_edit, create_check_box, create_check_button, create_option_button, create_progress_bar, create_slider
- **UI Styling**: set_theme_stylebox, create_theme, apply_theme_to_node, set_font
- **UI Dialogs**: create_file_dialog, create_accept_dialog, create_confirm_dialog
- **Scene Operations**: delete_scene, rename_node, find_node_by_type
- **Script Operations**: delete_script, read_script, get_script_methods
- **Project Management**: get_project_settings, import_all_assets, cleanup_backups
- **Bug fixes**: Correção de parse errors em GDScript (MessageDialog, DirAccess.get_modified_time)
- **Total de ferramentas: 116**
