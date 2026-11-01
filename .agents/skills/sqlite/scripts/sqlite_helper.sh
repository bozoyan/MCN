#!/bin/bash
# SQLite helper script for Reveric databases
# Usage: sqlite_helper.sh <command> [args...]

set -e

MAIN_DB="$HOME/Library/Application Support/ai.reveric.debug/reveric.sqlite"
WORKSPACES_DIR="$HOME/Library/Application Support/ai.reveric.debug/novel_workspaces"

# Expand ~ in paths
MAIN_DB=$(eval echo "$MAIN_DB")

usage() {
    echo "Usage: $0 <command> [args...]"
    echo ""
    echo "Commands:"
    echo "  list-novels              List all novels"
    echo "  novel-info <id>          Show novel info and content DB path"
    echo "  novel-chapters <novel_id> List chapters for a novel"
    echo "  novel-characters <novel_id> List characters for a novel"
    echo "  novel-items <novel_id>   List items for a novel"
    echo "  list-providers           List AI providers"
    echo "  list-settings            List app settings"
    echo "  chat-sessions <novel_id> List chat sessions for a novel"
    echo "  chat-messages <session_id> List messages for a session"
    echo "  query <db_type> <sql>   Run custom SQL (db_type: main|novel:<id>)"
    echo ""
    echo "Examples:"
    echo "  $0 list-novels"
    echo "  $0 novel-info 1"
    echo "  $0 query main 'SELECT * FROM novels;'"
    echo "  $0 query novel:1 'SELECT * FROM chapters;'"
}

get_novel_db() {
    local novel_id=$1
    local content_db=$(sqlite3 "$MAIN_DB" "SELECT content_database_path FROM novels WHERE id = $novel_id;")
    if [ -z "$content_db" ]; then
        # Try default path
        content_db="$WORKSPACES_DIR/novel_${novel_id}.sqlite"
    fi
    echo "$content_db"
}

case "$1" in
    list-novels)
        sqlite3 -header -column "$MAIN_DB" "SELECT id, title, status, word_count, datetime(created_at/1000, 'unixepoch') as created FROM novels WHERE deleted_at = 0 ORDER BY updated_at DESC;"
        ;;
    novel-info)
        if [ -z "$2" ]; then echo "Error: novel ID required"; exit 1; fi
        sqlite3 -header -column "$MAIN_DB" "SELECT * FROM novels WHERE id = $2;"
        echo ""
        echo "Content DB path: $(get_novel_db $2)"
        ;;
    novel-chapters)
        if [ -z "$2" ]; then echo "Error: novel ID required"; exit 1; fi
        db=$(get_novel_db $2)
        if [ ! -f "$db" ]; then echo "Error: Content DB not found: $db"; exit 1; fi
        sqlite3 -header -column "$db" "SELECT id, chapter_num, title, word_count, stat, datetime(updated_at/1000, 'unixepoch') as updated FROM chapters ORDER BY chapter_num;"
        ;;
    novel-characters)
        if [ -z "$2" ]; then echo "Error: novel ID required"; exit 1; fi
        db=$(get_novel_db $2)
        if [ ! -f "$db" ]; then echo "Error: Content DB not found: $db"; exit 1; fi
        sqlite3 -header -column "$db" "SELECT id, name, role, substr(summary, 1, 50) as summary_preview FROM character_profiles ORDER BY sort_order;"
        ;;
    novel-items)
        if [ -z "$2" ]; then echo "Error: novel ID required"; exit 1; fi
        db=$(get_novel_db $2)
        if [ ! -f "$db" ]; then echo "Error: Content DB not found: $db"; exit 1; fi
        sqlite3 -header -column "$db" "SELECT id, type, title, status FROM items ORDER BY sort_order;"
        ;;
    list-providers)
        sqlite3 -header -column "$MAIN_DB" "SELECT id, name, type, enabled, temperature FROM ai_providers;"
        ;;
    list-settings)
        sqlite3 -header -column "$MAIN_DB" "SELECT key, substr(value, 1, 100) as value_preview FROM app_settings;"
        ;;
    chat-sessions)
        if [ -z "$2" ]; then echo "Error: novel ID required"; exit 1; fi
        sqlite3 -header -column "$MAIN_DB" "SELECT id, title, provider, model, mode, agent_slug, datetime(updated_at/1000, 'unixepoch') as updated FROM ai_chat_sessions WHERE novel_id = '$2' AND deleted_at = 0 ORDER BY updated_at DESC;"
        ;;
    chat-messages)
        if [ -z "$2" ]; then echo "Error: session ID required"; exit 1; fi
        # Get novel_id from session in main DB
        novel_id=$(sqlite3 "$MAIN_DB" "SELECT novel_id FROM ai_chat_sessions WHERE id = '$2' AND deleted_at = 0;")
        if [ -z "$novel_id" ]; then echo "Error: Session not found"; exit 1; fi
        db=$(get_novel_db "$novel_id")
        if [ ! -f "$db" ]; then echo "Error: Content DB not found: $db"; exit 1; fi
        sqlite3 -header -column "$db" "SELECT role, substr(content, 1, 100) as preview, input_tokens, output_tokens, datetime(created_at/1000, 'unixepoch') as created FROM ai_chat_messages WHERE session_id = '$2' ORDER BY sequence;"
        ;;
    query)
        if [ -z "$2" ] || [ -z "$3" ]; then echo "Error: db_type and SQL required"; exit 1; fi
        db_type=$2
        sql=$3
        if [ "$db_type" = "main" ]; then
            sqlite3 -header -column "$MAIN_DB" "$sql"
        elif [[ "$db_type" =~ ^novel:(.+)$ ]]; then
            novel_id="${BASH_REMATCH[1]}"
            db=$(get_novel_db $novel_id)
            if [ ! -f "$db" ]; then echo "Error: Content DB not found: $db"; exit 1; fi
            sqlite3 -header -column "$db" "$sql"
        else
            echo "Error: Invalid db_type. Use 'main' or 'novel:<id>'"
            exit 1
        fi
        ;;
    *)
        usage
        exit 1
        ;;
esac
