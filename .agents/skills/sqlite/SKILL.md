---
name: sqlite
description: Query and modify Reveric's SQLite databases directly. Use when the user asks to inspect, query, or update data in Reveric's databases — including novels, chapters, characters, AI providers, chat messages, settings, or any other persisted data. Also triggers on phrases like "check the database", "what's in the novel database", "show me all chapters", "update novel settings", "query sqlite", or when troubleshooting data persistence issues.
---

# Reveric SQLite Skill

Directly query and modify Reveric's SQLite databases for debugging, data inspection, and manual fixes.

## Database Locations

| Database | Path | Description |
|----------|------|-------------|
| **macOS Debug Main DB** | `~/Library/Application Support/ai.reveric.debug/reveric.sqlite` | Debug builds use bundle id `ai.reveric.debug` |
| **macOS Debug Novel Content DB** | `~/Library/Application Support/ai.reveric.debug/novel_workspaces/novel_{id}.sqlite` | Per-novel content DBs for Debug builds |
| **macOS Release/Profile Main DB** | `~/Library/Application Support/ai.reveric/reveric.sqlite` | Release/Profile builds use bundle id `ai.reveric` |
| **macOS Release/Profile Novel Content DB** | `~/Library/Application Support/ai.reveric/novel_workspaces/novel_{id}.sqlite` | Per-novel content DBs for Release/Profile builds |

## Select Target First

macOS Debug and Release/Profile use different bundle identifiers, so they read different Application Support directories. Do not assume one path fits all.

Before querying or writing, identify which app build the user means:

```bash
# Debug build
REVERIC_APP_SUPPORT="$HOME/Library/Application Support/ai.reveric.debug"
REVERIC_MAIN_DB="$REVERIC_APP_SUPPORT/reveric.sqlite"

# Release/Profile build
REVERIC_APP_SUPPORT="$HOME/Library/Application Support/ai.reveric"
REVERIC_MAIN_DB="$REVERIC_APP_SUPPORT/reveric.sqlite"
```

If the user says "debug", use `ai.reveric.debug`. If the user says "release", "profile", or "installed app", use `ai.reveric`. If unclear, inspect both with read-only counts before writing.

## Main Database Schema

### `novels`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Novel ID (format: `novel_xxx`) |
| title | TEXT | Novel title |
| description | TEXT | Novel description |
| cover_path | TEXT NULL | Cover image path |
| status | TEXT DEFAULT 'in_progress' | Novel status |
| content_database_path | TEXT NULL | Path to novel's content DB |
| word_count | INTEGER DEFAULT 0 | Total word count |
| category | TEXT DEFAULT '' | Novel category |
| tags | TEXT DEFAULT '[]' | Tags JSON array |
| ai_settings | TEXT NULL | AI configuration JSON |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

**Unique constraint:** `(title, deleted_at)`

### `app_settings`
| Column | Type | Description |
|--------|------|-------------|
| key | TEXT PK | Setting key |
| value | TEXT DEFAULT '' | Setting value |
| updated_at | INTEGER | Unix timestamp (ms) |

### `ai_providers`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Provider ID |
| name | TEXT | Display name |
| builtin | INTEGER (0/1) | Is built-in provider |
| type | TEXT | Provider type (openai, anthropic, google, etc.) |
| enabled | INTEGER (0/1) | Is enabled |
| api_key | TEXT DEFAULT '' | API key |
| base_url | TEXT DEFAULT '' | Custom base URL |
| models | TEXT DEFAULT '[]' | Available models JSON |
| image_models | TEXT DEFAULT '[]' | Image models JSON |
| embedding_models | TEXT DEFAULT '[]' | Embedding models JSON |
| temperature | REAL DEFAULT 0.7 | Temperature setting |
| max_tokens | INTEGER DEFAULT 65536 | Max tokens |
| max_turns | INTEGER DEFAULT 512 | Max conversation turns |
| reasoning_effort | TEXT NULL | Reasoning effort level |
| proxy_url | TEXT DEFAULT '' | Proxy URL |
| proxy_username | TEXT DEFAULT '' | Proxy username |
| proxy_password | TEXT DEFAULT '' | Proxy password |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

### `agents`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Agent ID (UUID) |
| scope | TEXT | Scope (global/novel) |
| novel_id | TEXT NULL | Novel ID (for novel-scoped agents) |
| slug | TEXT | URL-friendly unique identifier |
| name | TEXT | Display name |
| description | TEXT DEFAULT '' | Agent description |
| prompt | TEXT | System prompt |
| category | TEXT | Agent category |
| enabled | INTEGER (0/1) DEFAULT 1 | Is enabled |
| use_custom_prompt | INTEGER (0/1) DEFAULT 0 | Use custom prompt |
| sort_order | INTEGER DEFAULT 0 | Display order |
| callable_agent_slugs | TEXT DEFAULT '[]' | Sub-agent slugs JSON |
| allowed_tool_names | TEXT DEFAULT '[]' | Allowed tool names JSON |
| provider_id | TEXT NULL | AI provider ID |
| model | TEXT NULL | Model ID |
| avatar_path | TEXT NULL | Avatar image path |
| mode | TEXT DEFAULT 'chat' | Agent mode (chat/write/etc.) |
| ignored_skill_names | TEXT DEFAULT '[]' | Ignored skill names JSON |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

**Unique constraint:** `(scope, novel_id, slug, deleted_at)`

### `ai_chat_sessions`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Session ID (UUID) |
| novel_id | TEXT | Novel ID |
| title | TEXT DEFAULT '' | Session title |
| provider | TEXT NULL | AI provider used |
| model | TEXT NULL | Model used |
| mode | TEXT DEFAULT 'chat' | Chat mode |
| agent_slug | TEXT NULL | Agent slug |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

### `app_states`
| Column | Type | Description |
|--------|------|-------------|
| key | TEXT PK | State key |
| value | TEXT DEFAULT '' | State value |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |

### `memories`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Memory ID (UUID) |
| novel_id | TEXT NULL | Novel ID |
| category | TEXT | Memory category |
| priority | TEXT DEFAULT 'context' | Priority (context/core/etc.) |
| content | TEXT | Memory content |
| source | TEXT DEFAULT 'manual' | Source |
| source_session_id | TEXT NULL | Source session ID |
| enabled | INTEGER (0/1) DEFAULT 1 | Is enabled |
| sort_order | INTEGER DEFAULT 0 | Display order |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

### `todos`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Todo ID (UUID) |
| content | TEXT | Todo content |
| status | TEXT DEFAULT 'pending' | Status (pending/done) |
| priority | TEXT DEFAULT 'medium' | Priority |
| session_id | TEXT | Associated session ID |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |

### `agent_skills`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Skill ID (UUID) |
| agent_id | TEXT | Agent ID |
| scope | TEXT DEFAULT 'global' | Scope |
| novel_id | TEXT DEFAULT '' | Novel ID |
| name | TEXT | Skill name |
| description | TEXT | Skill description |
| prompt | TEXT | Skill prompt |
| category | TEXT DEFAULT '' | Skill category |
| enabled | INTEGER (0/1) DEFAULT 1 | Is enabled |
| sort_order | INTEGER DEFAULT 0 | Display order |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

**Unique constraint:** `(scope, novel_id, name, deleted_at)`

### `tips`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Tip ID (UUID) |
| novel_id | TEXT NULL | Novel ID |
| name | TEXT DEFAULT '' | Tip name |
| description | TEXT NULL | Tip description |
| status | TEXT DEFAULT 'pending' | Status (pending/dismissed) |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

### `tasks`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Task ID (UUID) |
| name | TEXT | Task name |
| description | TEXT NULL | Task description |
| status | TEXT DEFAULT 'todo' | Status (todo/in_progress/done) |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |

## Novel Content Database Schema

### `chapter_nodes`
Canonical writable table for chapter tree nodes. Insert, update, move, and delete chapters here, not in the `chapters` view.

| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Node ID (UUID) |
| type | TEXT | Node type: `volume`, `chapter`, or `extra` |
| parent_id | TEXT NULL | Parent node ID (FK → chapter_nodes.id) |
| sibling_order | INTEGER | Order among siblings |
| title | TEXT NULL | Chapter title |
| outline | TEXT DEFAULT '' | Chapter outline |
| content | TEXT DEFAULT '' | Chapter content |
| word_count | INTEGER DEFAULT 0 | Word count |
| stat | TEXT DEFAULT 'draft' | Status: `draft` or `published` |
| embedding_sync_status | TEXT DEFAULT 'pending' | Sync status (pending/syncing/synced/error) |
| embedding_synced_at | INTEGER NULL | Last sync time (Unix timestamp ms) |
| embedding_sync_model_id | TEXT NULL | Model used for embedding |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete timestamp; active rows compare as `deleted_at = 0` in app queries |

**Indexes:** `(parent_id, sibling_order)`, `(type, sibling_order)`

### `chapters` (VIEW)
Computed read view over `chapter_nodes` with additional computed columns. Do not write to this view directly.

| Column | Type | Description |
|--------|------|-------------|
| id | TEXT | Node ID |
| type | TEXT | Node type: `volume`, `chapter`, or `extra` |
| parent_id | TEXT NULL | Parent node ID |
| sibling_order | INTEGER | Order among siblings |
| title | TEXT NULL | Chapter title |
| outline | TEXT | Chapter outline |
| content | TEXT | Chapter content |
| word_count | INTEGER | Word count |
| stat | TEXT | Status: `draft` or `published` |
| embedding_sync_status | TEXT | Sync status |
| embedding_synced_at | INTEGER | Last sync time (Unix timestamp ms) |
| embedding_sync_model_id | TEXT | Model used |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER | Soft delete timestamp; active rows compare as `deleted_at = 0` |
| parent_sibling_order | INTEGER NULL | Parent's sibling order |
| volume_num | INTEGER NULL | Volume number (for volume nodes) |
| chapter_num | INTEGER NULL | Global chapter number (for chapter/extra) |
| volume_chapter_num | INTEGER NULL | Chapter number within volume |

Useful chapter checks:

```sql
SELECT id, type, parent_id, sibling_order, title, chapter_num, volume_chapter_num
FROM chapters
ORDER BY COALESCE(parent_sibling_order, sibling_order),
         CASE WHEN parent_id IS NULL THEN 0 ELSE sibling_order END;
```

```sql
SELECT id, type, parent_id, sibling_order, title, deleted_at
FROM chapter_nodes
WHERE deleted_at = 0;
```

### `character_profiles`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Character ID (UUID) |
| name | TEXT | Character name |
| role | TEXT DEFAULT 'supporting' | Role (protagonist/antagonist/supporting/minor) |
| gender | TEXT DEFAULT 'unknown' | Gender (male/female/non_binary/other/unknown) |
| summary | TEXT DEFAULT '' | Character summary |
| description | TEXT DEFAULT '' | Character description |
| avatar | TEXT NULL | Avatar image path |
| photos | TEXT NULL | Photos JSON |
| sort_order | INTEGER DEFAULT 0 | Display order |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

### `items`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Item ID (UUID) |
| type | TEXT | Item type |
| title | TEXT | Item title |
| content | TEXT DEFAULT '' | Item description |
| status | TEXT DEFAULT 'active' | Status (active/archived) |
| read_access | TEXT DEFAULT 'everyone' | Read access level |
| write_access | TEXT DEFAULT 'everyone' | Write access level |
| sort_order | INTEGER DEFAULT 0 | Display order |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

**Unique constraint:** `(type, title, deleted_at)`

### `foreshadowings`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Entry ID (UUID) |
| title | TEXT | Title |
| setup | TEXT DEFAULT '' | Setup description |
| payoff | TEXT DEFAULT '' | Payoff description |
| status | TEXT DEFAULT 'pending' | Status (pending/planted/payoff/abandoned) |
| sort_order | INTEGER DEFAULT 0 | Display order |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

**Unique constraint:** `(title, deleted_at)`

### `ai_chat_messages`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Message ID (UUID) |
| session_id | TEXT | Session ID |
| role | TEXT | Role (user/assistant/system/tool) |
| type | TEXT DEFAULT 'text' | Message type |
| content | TEXT DEFAULT '' | Message content |
| blocks | TEXT NULL | Structured blocks JSON |
| metadata | TEXT NULL | Metadata JSON |
| input_tokens | INTEGER DEFAULT 0 | Input token count |
| output_tokens | INTEGER DEFAULT 0 | Output token count |
| cache_read_tokens | INTEGER DEFAULT 0 | Cache read tokens |
| cache_write_tokens | INTEGER DEFAULT 0 | Cache write tokens |
| reasoning_tokens | INTEGER DEFAULT 0 | Reasoning tokens |
| sequence | INTEGER DEFAULT 0 | Message order |
| created_at | INTEGER | Unix timestamp (ms) |

### `ai_embedding_documents`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Document ID (UUID) |
| source_id | TEXT | Source ID (chapter, character, etc.) |
| source_type | TEXT | Source type |
| path | TEXT | Document path |
| title | TEXT DEFAULT '' | Document title |
| chunk_index | INTEGER | Chunk index |
| content | TEXT | Chunk content |
| embedding_model | TEXT | Model used |
| provider_id | TEXT NULL | Provider ID |
| vector | TEXT | Embedding vector JSON |
| metadata | TEXT NULL | Metadata JSON |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |

### `working_changes`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Change ID (UUID) |
| resource_path | TEXT | Resource path |
| resource_type | TEXT | Resource type |
| resource_id | TEXT NULL | Resource ID |
| field | TEXT NULL | Changed field |
| change_type | TEXT | Change type |
| source | TEXT | Change source |
| source_session_id | TEXT NULL | Source session ID |
| tool_name | TEXT NULL | Tool that made the change |
| summary | TEXT DEFAULT '' | Change summary |
| old_text | TEXT NULL | Previous value |
| new_text | TEXT NULL | New value |
| base_version | INTEGER DEFAULT 0 | Base version |
| status | TEXT DEFAULT 'active' | Status |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |

### `change_commits`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Commit ID (UUID) |
| message | TEXT DEFAULT '' | Commit message |
| source | TEXT DEFAULT 'manual_edit' | Source |
| change_count | INTEGER DEFAULT 0 | Number of changes |
| created_at | INTEGER | Unix timestamp (ms) |

### `change_commit_items`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Item ID (UUID) |
| commit_id | TEXT | Commit ID |
| working_change_id | TEXT | Working change ID |
| resource_path | TEXT | Resource path |
| resource_type | TEXT | Resource type |
| resource_id | TEXT NULL | Resource ID |
| field | TEXT NULL | Changed field |
| old_text | TEXT NULL | Previous value |
| new_text | TEXT NULL | New value |
| created_at | INTEGER | Unix timestamp (ms) |

### `novel_states`
| Column | Type | Description |
|--------|------|-------------|
| key | TEXT PK | State key |
| status | TEXT DEFAULT 'idle' | Status (idle/running/paused/error) |
| data | TEXT NULL | State data JSON |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |

### `agent_rules`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Rule ID (UUID) |
| name | TEXT | Rule name |
| content | TEXT | Rule content |
| enabled | INTEGER (0/1) DEFAULT 1 | Is enabled |
| sort_order | INTEGER DEFAULT 0 | Display order |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

### `documents`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Document ID (UUID) |
| type | TEXT | Document type (worldbuilding/outline/material) |
| title | TEXT | Document title |
| content | TEXT DEFAULT '' | Document content |
| status | TEXT DEFAULT 'active' | Status (active/archived) |
| tags | TEXT DEFAULT '' | Tags |
| read_access | TEXT DEFAULT 'everyone' | Read access level |
| write_access | TEXT DEFAULT 'everyone' | Write access level |
| parent_id | TEXT NULL | Parent folder ID |
| is_folder | INTEGER (0/1) DEFAULT 0 | Is folder |
| sort_order | INTEGER DEFAULT 0 | Display order |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

**Unique constraint:** `(type, parent_id, title, deleted_at)`

### `entity_relations`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Relation ID (UUID) |
| source_type | TEXT | Source entity type |
| source_id | TEXT | Source entity ID |
| target_type | TEXT | Target entity type |
| target_id | TEXT | Target entity ID |
| relation_type | TEXT | Relation type (see below) |
| chapter_id | TEXT NULL | Chapter that evidences this relation |
| proof | TEXT DEFAULT '' | Evidence description |
| properties | TEXT NULL | Additional properties JSON |
| sort_order | INTEGER DEFAULT 0 | Display order |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |

**Relation types by entity pair:**

| source_type → target_type | relation_type values |
|---------------------------|---------------------|
| character → character | `family`, `parent`, `sibling`, `grandparent`, `friend`, `enemy`, `lover`, `master_disciple`, `colleague`, `subordinate` |
| character → faction | `member`, `leader`, `founder`, `ally`, `enemy` |
| character → skill | `learned`, `mastering`, `mastered`, `creator` |
| character → item | `owner`, `user`, `creator`, `former_owner` |
| faction → faction | `ally`, `enemy`, `subordinate` |
| skill → skill | `prerequisite`, `evolves_to`, `branch` |
| item → item | `part_of`, `evolves_to` |
| creature → creature | `evolves_to`, `prey`, `predator` |

### `locations`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Location ID (UUID) |
| name | TEXT | Location name |
| description | TEXT DEFAULT '' | Description |
| type | TEXT DEFAULT 'generic' | Location type |
| parent_id | TEXT NULL | Parent location ID |
| tags | TEXT DEFAULT '' | Tags |
| meta | TEXT NULL | Metadata JSON |
| status | TEXT DEFAULT 'active' | Status (active/archived) |
| sort_order | INTEGER DEFAULT 0 | Display order |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

### `novel_maps`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Map ID (UUID) |
| name | TEXT | Map name |
| description | TEXT DEFAULT '' | Description |
| type | TEXT DEFAULT 'world' | Map type (world/region/city/building/dungeon) |
| width | REAL DEFAULT 1000.0 | Map width |
| height | REAL DEFAULT 800.0 | Map height |
| settings | TEXT NULL | Settings JSON |
| sort_order | INTEGER DEFAULT 0 | Display order |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

### `map_locations`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Map location ID (UUID) |
| map_id | TEXT | Map ID |
| location_id | TEXT | Location ID |
| x | REAL DEFAULT 0.0 | X coordinate |
| y | REAL DEFAULT 0.0 | Y coordinate |
| width | REAL NULL | Width |
| height | REAL NULL | Height |
| style | TEXT NULL | Style JSON |
| sort_order | INTEGER DEFAULT 0 | Display order |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

**Unique constraint:** `(map_id, location_id, deleted_at)`

### `map_features`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Feature ID (UUID) |
| map_id | TEXT | Map ID |
| location_id | TEXT | Location ID |
| geometry_type | TEXT DEFAULT 'point' | Geometry type (point/rect/polygon) |
| geometry | TEXT | Geometry JSON |
| style | TEXT NULL | Style JSON |
| label | TEXT NULL | Label JSON |
| layer_id | TEXT NULL | Layer ID |
| z_index | INTEGER DEFAULT 0 | Z-index |
| sort_order | INTEGER DEFAULT 0 | Display order |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

**Unique constraint:** `(map_id, location_id, deleted_at)`

### `map_layers`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Layer ID (UUID) |
| map_id | TEXT | Map ID |
| name | TEXT | Layer name |
| type | TEXT DEFAULT 'base' | Layer type |
| is_visible | INTEGER (0/1) DEFAULT 1 | Is visible |
| is_locked | INTEGER (0/1) DEFAULT 0 | Is locked |
| sort_order | INTEGER DEFAULT 0 | Display order |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

**Unique constraint:** `(map_id, name, deleted_at)`

### `location_connections`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Connection ID (UUID) |
| map_id | TEXT | Map ID |
| source_map_location_id | TEXT | Source map location ID |
| target_map_location_id | TEXT | Target map location ID |
| source_feature_id | TEXT NULL | Source feature ID |
| target_feature_id | TEXT NULL | Target feature ID |
| type | TEXT | Connection type (adjacent/path_to) |
| label | TEXT NULL | Label |
| distance | REAL NULL | Distance |
| conditions | TEXT NULL | Conditions |
| difficulty | TEXT NULL | Difficulty |
| travel_time_days | INTEGER NULL | Travel time in days |
| extra_properties | TEXT NULL | Extra properties JSON |
| sort_order | INTEGER DEFAULT 0 | Display order |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

**Unique constraint:** `(map_id, source_map_location_id, target_map_location_id, type, deleted_at)`

### `outlines`
| Column | Type | Description |
|--------|------|-------------|
| document_id | TEXT PK | Document ID (FK → documents.id) |
| title | TEXT DEFAULT '' | Outline title |
| content | TEXT DEFAULT '' | Outline content |
| status | TEXT DEFAULT 'pending' | Status |
| sort_order | INTEGER DEFAULT 0 | Display order |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

### `outline_beats`
| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Beat ID (UUID) |
| outline_document_id | TEXT | Outline document ID |
| title | TEXT DEFAULT '' | Beat title |
| content | TEXT DEFAULT '' | Beat content |
| status | TEXT DEFAULT 'pending' | Status |
| chapter_count | INTEGER DEFAULT 1 | Number of chapters |
| sort_order | INTEGER DEFAULT 0 | Display order |
| created_at | INTEGER | Unix timestamp (ms) |
| updated_at | INTEGER | Unix timestamp (ms) |
| deleted_at | INTEGER DEFAULT 0 | Soft delete flag |

## Common Query Patterns

### Get all novels
```bash
sqlite3 -header -column "$REVERIC_MAIN_DB" "SELECT id, title, status, word_count, datetime(created_at/1000, 'unixepoch') as created FROM novels WHERE deleted_at = 0 ORDER BY updated_at DESC;"
```

### Get novel content database path
```bash
sqlite3 "$REVERIC_MAIN_DB" "SELECT id, title, content_database_path FROM novels WHERE deleted_at = 0;"
```

### Get all chapters for a novel (using chapters VIEW)
```bash
sqlite3 -header -column "$REVERIC_APP_SUPPORT/novel_workspaces/novel_xxx.sqlite" "SELECT id, type, chapter_num, title, word_count, stat, datetime(updated_at/1000, 'unixepoch') as updated FROM chapters WHERE type IN ('chapter', 'extra') ORDER BY chapter_num;"
```

### Get all characters for a novel
```bash
sqlite3 -header -column "$REVERIC_APP_SUPPORT/novel_workspaces/novel_xxx.sqlite" "SELECT id, name, role, gender, summary FROM character_profiles WHERE deleted_at = 0 ORDER BY sort_order;"
```

### Get AI chat sessions for a novel
```bash
sqlite3 -header -column "$REVERIC_MAIN_DB" "SELECT id, title, provider, model, mode, agent_slug FROM ai_chat_sessions WHERE novel_id = 'novel_xxx' AND deleted_at = 0 ORDER BY updated_at DESC LIMIT 10;"
```

### Get chat messages for a session
```bash
sqlite3 -header -column "$REVERIC_APP_SUPPORT/novel_workspaces/novel_xxx.sqlite" "SELECT role, substr(content, 1, 100) as preview, input_tokens, output_tokens, datetime(created_at/1000, 'unixepoch') FROM ai_chat_messages WHERE session_id = 'SESSION_ID' ORDER BY sequence;"
```

### Get all AI providers
```bash
sqlite3 -header -column "$REVERIC_MAIN_DB" "SELECT id, name, type, enabled, temperature FROM ai_providers WHERE deleted_at = 0;"
```

### Get app settings
```bash
sqlite3 -header -column "$REVERIC_MAIN_DB" "SELECT key, value FROM app_settings;"
```

### Update a novel's title
```bash
sqlite3 "$REVERIC_MAIN_DB" "UPDATE novels SET title = 'New Title', updated_at = strftime('%s', 'now') * 1000 WHERE id = 'novel_xxx';"
```

### Count words in all chapters
```bash
sqlite3 "$REVERIC_APP_SUPPORT/novel_workspaces/novel_xxx.sqlite" "SELECT type, SUM(word_count) as total_words FROM chapter_nodes WHERE deleted_at = 0 GROUP BY type;"
```

### Get volumes structure
```bash
sqlite3 -header -column "$REVERIC_APP_SUPPORT/novel_workspaces/novel_xxx.sqlite" "SELECT id, sibling_order, title FROM chapter_nodes WHERE type = 'volume' AND deleted_at = 0 ORDER BY sibling_order;"
```

### Get chapters within a volume
```bash
sqlite3 -header -column "$REVERIC_APP_SUPPORT/novel_workspaces/novel_xxx.sqlite" "SELECT id, type, sibling_order as chapter_num, title, word_count, stat FROM chapter_nodes WHERE parent_id = 'VOLUME_ID' AND deleted_at = 0 ORDER BY sibling_order;"
```

### Get all agents
```bash
sqlite3 -header -column "$REVERIC_MAIN_DB" "SELECT id, slug, name, category, enabled, mode FROM agents WHERE deleted_at = 0 ORDER BY sort_order;"
```

## Helper Scripts

### Find all novel databases
```bash
ls "$REVERIC_APP_SUPPORT/novel_workspaces/"*.sqlite 2>/dev/null
```

### Get novel info with content DB path resolved
```bash
sqlite3 -header -column "$REVERIC_MAIN_DB" "SELECT id, title, content_database_path, word_count, status FROM novels WHERE deleted_at = 0 ORDER BY updated_at DESC;"
```

### List all tables with row counts
```bash
echo "=== Main DB ===" && sqlite3 "$REVERIC_MAIN_DB" "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;" && echo && echo "=== Novel Content DB ===" && for db in "$REVERIC_APP_SUPPORT/novel_workspaces/"*.sqlite; do echo "--- $(basename "$db") ---"; sqlite3 "$db" "SELECT name FROM sqlite_master WHERE type IN ('table','view') ORDER BY name;"; done
```

## Important Notes

1. **Select the target build first** - Debug and Release/Profile use different bundle IDs and therefore different DB directories. Set `REVERIC_APP_SUPPORT` and `REVERIC_MAIN_DB` before querying or writing.

2. **Two database types** - Remember there's a main app database and per-novel content databases. Check `novels.content_database_path` to find the correct content DB for a novel.

3. **Timestamps are milliseconds** - Timestamp fields are stored as INTEGER milliseconds (Unix epoch * 1000). Use `datetime(timestamp/1000, 'unixepoch')` to convert to readable format.

4. **Soft delete** - Most tables use `deleted_at` (INTEGER DEFAULT 0) for soft deletes. Always filter with `WHERE deleted_at = 0` unless you need to see deleted records.

5. **Novel IDs are TEXT** - Novel IDs are strings like `novel_xxx`, not integers.

6. **Use transactions for writes** - When making multiple related updates, wrap them in a transaction:
   ```sql
   BEGIN TRANSACTION;
   -- multiple UPDATE/INSERT statements
   COMMIT;
   ```

7. **Backup before major changes** - For destructive operations, backup first:
   ```bash
   cp "$REVERIC_MAIN_DB" ~/reveric.sqlite.backup
   ```

8. **JSON columns** - Many columns store JSON data (without `_json` suffix now). Use `json_extract()` if SQLite is compiled with JSON support, or parse in Dart/helper scripts. Key JSON columns: `tags`, `ai_settings`, `models`, `image_models`, `embedding_models`, `callable_agent_slugs`, `allowed_tool_names`, `ignored_skill_names`, `blocks`, `metadata`, `vector`, `properties`, `settings`, `style`, `geometry`, `label`, `meta`, `data`, `extra_properties`, `photos`.

9. **`chapters` is a VIEW** - The old `chapters` table was replaced by a `chapter_nodes` tree table + a `chapters` VIEW. When reading chapter data, query the VIEW by default. The VIEW filters `deleted_at = 0` automatically and provides computed `chapter_num`, `volume_num`, `volume_chapter_num`.

10. **`agents` table replaces `global_sub_agents`/`novel_sub_agents`** - Agents now have `scope` (global/novel) and `novel_id` to distinguish global vs per-novel agents.

11. **Dev-only: migration version merging** - During pre-release, multiple migration versions for the same feature may be merged into one. Never drop tables to force re-migration — that destroys data. Use ALTER TABLE to add missing columns instead.

## Dev-Only: Migration Merge Without Data Loss

When a migration method is edited under the same `schemaVersion` (e.g., `migrateToV8` gains new columns but version stays `8`), existing DBs at that version won't re-run, so they miss the new columns. **Do not drop tables** to force a re-run — that destroys all existing data.

### Proceed with routine development maintenance

When implementing an authorized schema change, updating the affected local development databases is part of that task. Identify the Debug target, back it up, add the required columns/indexes, and verify the result directly. Do not ask separately for approval of the database list, maintenance SQL, backup, or execution, and do not leave this work pending at the end of the implementation.

If the old Debug instance holds the databases, normally quit that instance, verify its handles are closed, complete maintenance, and launch the new Debug build. This necessary restart is included in development maintenance; do not make it another approval gate. If the instance has already exited, proceed. Preserve unsaved work: an actual save/discard prompt must not be bypassed by force-quitting.

Record the backup location, affected databases, schema and data-preservation checks, and restart result in the task handoff. This guidance covers local development maintenance within the implementation scope; it does not authorize Release/production changes, deleting business data, or an unplanned table rebuild. Resolve only concrete scope or data-loss decisions with the user; continue independent work while doing so.

### Safe fix: ALTER TABLE (preserves all data)

Add missing columns directly. All new columns should be nullable (or have DEFAULT) so existing rows are unaffected.

**Add columns to app DB:**
```bash
DB="$HOME/Library/Application Support/ai.reveric.debug/reveric.sqlite"
sqlite3 "$DB" "ALTER TABLE breakdown_runs ADD COLUMN metrics_started_at INTEGER NULL;"
sqlite3 "$DB" "ALTER TABLE breakdown_runs ADD COLUMN metrics_ended_at INTEGER NULL;"
sqlite3 "$DB" "ALTER TABLE breakdown_runs ADD COLUMN usage TEXT NULL;"
```

**Add columns to content DBs:**
```bash
for db in "$HOME/Library/Application Support/ai.reveric.debug/novel_workspaces/"*.sqlite; do
  # Check column existence first (skip if already present)
  col=$(sqlite3 "$db" "PRAGMA table_info(breakdown_chapters);" | grep -c 'tension_reason' || true)
  if [ "$col" -eq 0 ]; then
    sqlite3 "$db" "ALTER TABLE breakdown_chapters ADD COLUMN tension_reason TEXT NULL;"
  fi
done
```

### When ADD COLUMN isn't enough (rename + recreate + copy)

SQLite cannot `ALTER COLUMN` to change nullability, type, or defaults. When you need such changes, use rename + recreate + copy — this preserves all data without destructive drops.

```bash
# Example: make chapter_ids nullable (from NOT NULL to nullable)
TAB=breakdown_run_items
sqlite3 "$DB" "ALTER TABLE $TAB RENAME TO ${TAB}_old;"
sqlite3 "$DB" "CREATE TABLE $TAB (id TEXT NOT NULL PRIMARY KEY, run_id TEXT NOT NULL, phase TEXT NOT NULL DEFAULT 'map', status TEXT NOT NULL DEFAULT 'pending', chapter_ids TEXT NULL, error_message TEXT NULL, attempt INTEGER NOT NULL DEFAULT 0, started_at INTEGER NULL, completed_at INTEGER NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER NOT NULL DEFAULT 0);"
sqlite3 "$DB" "INSERT INTO $TAB (id, run_id, phase, status, chapter_ids, error_message, attempt, started_at, completed_at, created_at, updated_at, deleted_at) SELECT id, run_id, phase, status, chapter_ids, error_message, attempt, started_at, completed_at, created_at, updated_at, deleted_at FROM ${TAB}_old;"
sqlite3 "$DB" "DROP TABLE ${TAB}_old;"
# Recreate indexes
sqlite3 "$DB" "CREATE INDEX IF NOT EXISTS breakdown_run_items_by_run_id_status ON breakdown_run_items (run_id, status);"
sqlite3 "$DB" "CREATE INDEX IF NOT EXISTS breakdown_run_items_by_run_id_phase ON breakdown_run_items (run_id, phase);"
```

For a table rebuild not already explicitly authorized, show the proposed SQL and obtain confirmation before running it. This requirement applies to rebuilding tables, not routine development column/index maintenance above.

If you need to reset `user_version` after this (to trigger migration re-run for additional changes), check the current version first:
```bash
sqlite3 "$DB" "PRAGMA user_version;"
sqlite3 "$DB" "PRAGMA user_version = <previous_version>;"
```

## Workflow

When the user asks to query or modify the database:

1. **Identify the target** - Determine which database (main or novel content) and which table(s) are involved.

2. **Build the query** - Construct the appropriate SQL query. Use `-header` and `-column` flags for readable output:
   ```bash
   sqlite3 -header -column ~/path/to/db.sqlite "SELECT ...;"
   ```

3. **Execute and verify** - Run the query and check the results.

4. **For writes** - Apply existing task authorization. Perform routine development maintenance above directly; do not ask the user to approve it again. Ask only when the intended write scope is unclear or the operation requires authorization not already provided.

5. **Verify the result** - After writing, run a SELECT to confirm the change took effect.

## Examples

**User**: "Show me all novels"
```bash
sqlite3 -header -column "$REVERIC_MAIN_DB" "SELECT id, title, status, word_count, datetime(created_at/1000, 'unixepoch') as created FROM novels WHERE deleted_at = 0 ORDER BY updated_at DESC;"
```

**User**: "What chapters are in novel_xxx?"
```bash
CONTENT_DB=$(sqlite3 "$REVERIC_MAIN_DB" "SELECT content_database_path FROM novels WHERE id = 'novel_xxx' AND deleted_at = 0;")
sqlite3 -header -column "$CONTENT_DB" "SELECT chapter_num, type, title, word_count, stat FROM chapters WHERE type IN ('chapter', 'extra') ORDER BY chapter_num;"
```

**User**: "Update the API key for OpenAI provider"
```bash
sqlite3 "$REVERIC_MAIN_DB" "UPDATE ai_providers SET api_key = 'new-key-here', updated_at = strftime('%s', 'now') * 1000 WHERE id = 'openai';"
```
