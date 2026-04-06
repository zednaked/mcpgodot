# mcpgodot

MCP server para Godot 4.x com operações avançadas de cenas e otimização de tokens.

## Instalação

```bash
npm install
npm run build
```

## Uso

```bash
# Executar servidor
node build/index.js

# Com compressão de tokens
COMPRESSION_LEVEL=high node build/index.js
```

## Configuração

| Variável | Valores | Default | Descrição |
|----------|---------|---------|-----------|
| `COMPRESSION_LEVEL` | `none`, `medium`, `high`, `max` | `medium` | Compressão de schema |
| `DEBUG` | `true`, `false` | `false` | Logs de debug |
| `GODOT_PATH` | path | auto | Caminho do Godot |

## Ferramentas (36 total)

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
