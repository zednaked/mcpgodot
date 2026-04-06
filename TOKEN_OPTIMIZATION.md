# MCP Godot - Estratégias de Otimização de Token

## Resumo

| Técnica | Redução | Implementada |
|---------|---------|--------------|
| Schema Compression | 70-97% | ✅ |
| Scene Cache | 80%+ | ✅ |
| Response Filtering | 95%+ | ✅ |
| Batch Operations | 67% | ✅ |

---

## 1. Schema Compression

### Níveis Disponíveis

| Nível | Tokens | Uso |
|-------|--------|-----|
| `none` | ~4000 | Debugging |
| `medium` | ~1500 | Default |
| `high` | ~800 | Produção |
| `max` | ~300 | Mínimo contexto |

### Como Usar

```bash
COMPRESSION_LEVEL=high node build/index.js
```

### Comparação de Output

```typescript
// none - Full schema
{
  "name": "create_scene",
  "description": "Create a new scene with the specified root node type",
  "inputSchema": {
    "type": "object",
    "properties": {
      "projectPath": { "type": "string", "description": "Absolute path to the Godot project" },
      "scenePath": { "type": "string", "description": "Path for the new scene relative to res://" },
      "rootNodeType": { "type": "string", "description": "Type of root node (default: Node2D)" }
    },
    "required": ["projectPath", "scenePath"]
  }
}

// high - Minimal
{
  "name": "create_scene",
  "description": "Create scene.",
  "inputSchema": { ... }
}

// max - Names only
{
  "name": "create_scene",
  "description": "",
  "inputSchema": { ... }
}
```

---

## 2. Scene Cache

### Como Funciona

```typescript
interface SceneCache {
  hash: string;      // MD5 do arquivo
  data: unknown;     // Dados em cache
  timestamp: number; // TTL 60s
}
```

### Cache Hit Example

```bash
# Primeira chamada - ~600ms (Godot executa)
$ list_nodes(scenePath="Player.tscn")

# Segunda chamada - ~10ms (cache)
$ list_nodes(scenePath="Player.tscn")
```

### Invalidação

- TTL: 60 segundos
- Modificação de cena: Hash diferente

---

## 3. Response Filtering

### Campos Disponíveis

```bash
# Todos os campos (baseline)
$ list_nodes(scenePath="scene.tscn")
# ~5000 chars

# Só nome
$ list_nodes(scenePath="scene.tscn", fields=["name"])
# ~200 chars (-96%)

# Nome + tipo
$ list_nodes(scenePath="scene.tscn", fields=["name", "type"])
# ~500 chars (-90%)
```

### Implementação

```typescript
// Filtrar antes de retornar
if (args.fields && Array.isArray(args.fields)) {
  result = filterFields(result, args.fields);
}
```

---

## 4. Batch Operations

### Exemplo

```typescript
// Antes: 5 chamadas = 5 round trips
await add_node(...)
await add_node(...)
await add_node(...)
await modify_property(...)
await save_scene(...)

// Depois: 1 chamada = 1 round trip
await batch_operations({
  operations: [
    { operation: 'add_node', params: {...} },
    { operation: 'add_node', params: {...} },
    { operation: 'add_node', params: {...} },
    { operation: 'modify_property', params: {...} }
  ],
  enableRollback: true
});
```

### Redução de Tokens

| Cenário | Tokens |
|---------|--------|
| 5 operações separadas | ~6000 |
| 1 batch operation | ~2000 |
| **Redução** | **-67%** |

---

## 5. Rollback Automático

### Como Funciona

```gdscript
func batch_operations(params):
    backup_path = _create_backup(scene_path)  // Backup
    
    for op in operations:
        success = _execute_operation(op)
        if not success and enable_rollback:
            _restore_backup(scene_path, backup_path)  // Rollback
            quit(1)
```

### Uso

```typescript
await batch_operations({
  operations: [...],
  enableRollback: true  // Default: true
});
```

---

## 6. Compressão de Responses

### Renomeação de Keys

```typescript
const RENAME_MAP = {
  scene_path: 'p',
  node_path: 'n',
  node_name: 'nn',
  project_path: 'pp',
  // ...
};

// Output original
{ "scene_path": "...", "node_path": "..." }

// Output comprimido
{ "p": "...", "n": "..." }
```

### Ativação

```bash
COMPRESSION_LEVEL=high node build/index.js
```

---

## Métricas de Sucesso

| Métrica | Antes | Depois | Meta |
|---------|-------|--------|------|
| Schema tokens (high) | ~4000 | <800 | ✅ ~800 |
| list_nodes (fields) | ~5000 chars | <500 chars | ✅ <500 |
| Batch vs separate | ~6000 tokens | <2000 | ✅ <2000 |
| Round trips por task | 3-5 | 1-2 | ✅ 1-2 |

---

## Configuração

```bash
# Variáveis de ambiente
COMPRESSION_LEVEL=high    # none, medium, high, max
DEBUG=true                 # Logs detalhados
GODOT_PATH=/usr/bin/godot # Path do Godot
```

---

## Referências

- [godot-mcp](https://github.com/Coding-Solo/godot-mcp) - Projeto original
- [MCP Token Optimization (StackOne)](https://www.stackone.com/blog/mcp-token-optimization)
- [MCP Context Window (Mr. Phil Games)](https://www.mrphilgames.com/blog/mcp-is-wasting-your-context-window)
- [Anthropic Code Execution](https://www.anthropic.com/engineering/code-execution-with-mcp)
