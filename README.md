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

## Ferramentas (61 total)

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
| `list_nodes` | Lista nós |
| `batch_operations` | Operações atômicas |
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
│   ├── index.ts              # Server MCP
│   └── scripts/
│       └── godot_operations.gd  # GDScript operations
├── build/                    # Compiled output
├── test-suite.ts            # Tests
├── TEST_PLAN.md            # Plano de testes
├── TOKEN_OPTIMIZATION.md    # Estratégias de tokens
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
