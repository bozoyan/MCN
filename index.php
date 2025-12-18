<?php
// 处理API路由
$request_uri = $_SERVER['REQUEST_URI'];
$path_parts = parse_url($request_uri);
$path = explode('/', trim($path_parts['path'], '/'));

// API路由处理
if ($path[0] === 'api') {
    header('Content-Type: application/json');
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type');

    // 处理 OPTIONS 请求
    if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
        exit(0);
    }

    $json_dir = __DIR__ . '/json/';

    // 确保目录存在
    if (!file_exists($json_dir)) {
        mkdir($json_dir, 0777, true);
    }

    if ($path[1] === 'configs' && $_SERVER['REQUEST_METHOD'] === 'GET') {
        // 获取配置文件列表
        $files = glob($json_dir . '*.json');
        $file_list = [];
        foreach ($files as $file) {
            $filename = basename($file);
            // 确保文件名是UTF-8编码
            $filename = mb_convert_encoding($filename, 'UTF-8', 'UTF-8,ISO-8859-1');
            $file_list[] = $filename;
        }
        echo json_encode($file_list, JSON_UNESCAPED_UNICODE);
        exit;
    } elseif ($path[1] === 'config' && isset($path[2])) {
        // URL解码文件名，支持中文
        $filename = urldecode($path[2]);

        // 转换编码以确保兼容性
        $filename = mb_convert_encoding($filename, 'UTF-8', 'UTF-8,ISO-8859-1');

        // 确保 .json 扩展名
        if (!preg_match('/\.json$/', $filename)) {
            $filename .= '.json';
        }

        $filepath = $json_dir . $filename;

        if ($_SERVER['REQUEST_METHOD'] === 'GET') {
            // 读取配置文件
            if (file_exists($filepath)) {
                $content = file_get_contents($filepath);
                echo $content;
            } else {
                http_response_code(404);
                echo json_encode(['error' => 'File not found']);
            }
            exit;
        } elseif ($_SERVER['REQUEST_METHOD'] === 'POST') {
            // 保存配置文件
            $json_data = file_get_contents('php://input');
            $data = json_decode($json_data, true);

            if ($data !== null) {
                $json_string = json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
                if (file_put_contents($filepath, $json_string) !== false) {
                    echo json_encode(['status' => 'success']);
                } else {
                    http_response_code(500);
                    echo json_encode(['error' => 'Failed to save file']);
                }
            } else {
                http_response_code(400);
                echo json_encode(['error' => 'Invalid JSON data']);
            }
            exit;
        } elseif ($_SERVER['REQUEST_METHOD'] === 'DELETE') {
            // 删除配置文件
            if (file_exists($filepath) && unlink($filepath)) {
                echo json_encode(['status' => 'success']);
            } else {
                http_response_code(404);
                echo json_encode(['error' => 'File not found or could not be deleted']);
            }
            exit;
        }
    }
}
?>
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>BizyAIR Studio | Ultimate Plus</title>
    <!-- CodeMirror CSS -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.2/codemirror.min.css">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.2/theme/monokai.min.css">
    <style>
        :root {
            --bg-color: #1e1e1e;
            --panel-bg: #2d2d2d;
            --text-main: #ffffff;
            --text-sub: #a0a0a0;
            --accent: #4dabf7;
            --border: #404040;
            --grid-color: #333333;
            --font-mono: 'SF Mono', 'Roboto Mono', 'Menlo', monospace;
            --sidebar-width: 64px;
            --right-sidebar-width: 240px; /* 右侧画廊宽度 */
        }

        * { box-sizing: border-box; margin: 0; padding: 0; outline: none; user-select: none; }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background-color: var(--bg-color);
            color: var(--text-main);
            height: 100vh;
            display: flex;
            overflow: hidden;
        }

        input, textarea, select { user-select: text; color: #fff; background: #111; border: 1px solid var(--border); }
        
        /* 左侧侧边栏 */
        .sidebar {
            width: var(--sidebar-width); background: var(--panel-bg); border-right: 1px solid var(--border);
            display: flex; flex-direction: column; align-items: center; padding-top: 20px; z-index: 100;
            flex-shrink: 0;
        }
        .icon-btn {
            width: 44px; height: 44px; margin-bottom: 12px; border-radius: 8px;
            cursor: pointer; display: flex; justify-content: center; align-items: center;
            border: 1px solid transparent; transition: all 0.2s; color: var(--text-sub);
        }
        .icon-btn:hover { background: #3d3d3d; color: var(--text-main); }
        .icon-btn.active { background: rgba(77, 171, 247, 0.2); border-color: var(--accent); color: var(--accent); }

        /* 主区域 */
        .main-area { flex: 1; display: flex; flex-direction: column; position: relative; overflow: hidden; }

        .header {
            height: 48px; background: var(--panel-bg); border-bottom: 1px solid var(--border);
            display: flex; align-items: center; justify-content: space-between; padding: 0 20px;
            font-family: var(--font-mono); font-size: 12px; z-index: 50;
        }
        .header-btn {
            background: transparent; border: 1px solid var(--border); color: var(--text-sub);
            width: 32px; height: 32px; border-radius: 6px; cursor: pointer;
            display: flex; align-items: center; justify-content: center;
        }
        .header-btn:hover { background: #404040; color: #fff; }

        /* 工作区容器 (动态调整右边距) */
        .workspace {
            position: absolute; top: 48px; left: 0; right: 0; bottom: 0;
            background-color: var(--bg-color);
            background-image: radial-gradient(var(--grid-color) 1px, transparent 1px);
            background-size: 20px 20px; overflow: hidden;
            visibility: hidden; opacity: 0; transition: opacity 0.2s, right 0.3s ease;
        }
        .workspace.active { visibility: visible; opacity: 1; }
        /* 当右侧画廊打开时，工作区向左挤压 */
        .workspace.shrink { right: var(--right-sidebar-width); }

        /* --- 右侧画廊侧边栏 --- */
        .right-sidebar {
            position: absolute; top: 48px; right: 0; bottom: 0; width: var(--right-sidebar-width);
            background: var(--panel-bg); border-left: 1px solid var(--border);
            z-index: 90; display: flex; flex-direction: column;
            transform: translateX(100%); transition: transform 0.3s ease;
        }
        .right-sidebar.open { transform: translateX(0); }
        
        .gallery-scroll-area { flex: 1; overflow-y: auto; padding: 10px; display: flex; flex-direction: column; gap: 10px; }
        .mini-card { 
            background: #222; border-radius: 6px; overflow: hidden; border: 1px solid #444; position: relative; 
            cursor: pointer; transition: border-color 0.2s;
        }
        .mini-card:hover { border-color: var(--accent); }
        .mini-card img, .mini-card video { width: 100%; height: 140px; object-fit: cover; display: block; }
        .mini-card-meta { 
            padding: 5px 8px; font-size: 9px; color: #888; font-family: var(--font-mono); 
            display: flex; justify-content: space-between; background: #1a1a1a;
        }

        .gallery-toggle-btn {
            height: 30px; background: #333; color: #888; border: none; border-top: 1px solid var(--border);
            cursor: pointer; font-size: 12px; display: flex; align-items: center; justify-content: center;
            transition: background 0.2s;
        }
        .gallery-toggle-btn:hover { background: #444; color: #fff; }
        
        /* 悬浮的打开按钮 (当侧边栏关闭时显示) */
        .gallery-open-trigger {
            position: absolute; bottom: 20px; right: 20px; width: 40px; height: 40px;
            background: var(--panel-bg); border: 1px solid var(--border); border-radius: 50%;
            display: flex; align-items: center; justify-content: center; cursor: pointer;
            box-shadow: 0 4px 12px rgba(0,0,0,0.3); z-index: 95; color: var(--text-sub);
            transition: transform 0.2s;
        }
        .gallery-open-trigger:hover { color: var(--accent); transform: scale(1.1); }


        /* --- 画布模式 --- */
        #view-canvas { overflow: hidden; }
        .canvas-wrapper {
            width: 100%; height: 100%; display: flex; justify-content: center; align-items: center;
            transform-origin: center center; transition: transform 0.1s;
        }
        #drawing-canvas {
            background: #fff; cursor: crosshair; box-shadow: 0 0 30px rgba(0,0,0,0.5);
            transition: width 0.3s, height 0.3s;
        }
        
        .floating-panel {
            position: absolute; bottom: 30px; left: 50%; transform: translateX(-50%);
            background: rgba(45, 45, 45, 0.98); backdrop-filter: blur(10px);
            padding: 12px 20px; border: 1px solid var(--border); border-radius: 12px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.5); display: flex; gap: 10px; align-items: flex-end; width: 940px; z-index: 60;
        }

        /* 计时器样式 */
        .timer-display {
            font-family: var(--font-mono); font-size: 11px; color: var(--accent);
            background: rgba(0,0,0,0.3); padding: 4px 8px; border-radius: 4px;
            margin-bottom: 4px; text-align: center; min-width: 60px; opacity: 0; transition: opacity 0.2s;
        }
        .timer-display.active { opacity: 1; }

        .input-group { flex: 1; display: flex; flex-direction: column; min-width: 80px; }
        .input-group label { font-family: var(--font-mono); font-size: 9px; color: var(--text-sub); margin-bottom: 4px; text-transform: uppercase; white-space: nowrap; }
        
        input[type="text"], textarea, select { 
            padding: 8px; border-radius: 4px; font-size: 11px; width: 100%; font-family: var(--font-mono); 
            background: #1a1a1a; border: 1px solid #444; color: #eee; height: 32px;
        }
        input:focus, textarea:focus, select:focus { border-color: var(--accent); }

        .action-btn {
            background: var(--accent); color: #fff; border: none; padding: 0 15px; height: 32px;
            border-radius: 6px; font-family: var(--font-mono); font-size: 12px; cursor: pointer; font-weight: 600; width: 120px;
        }
        .action-btn:hover { filter: brightness(1.1); }
        .action-btn:disabled { background: #555; color: #888; cursor: not-allowed; }

        .secondary-btn { background: transparent; color: var(--text-main); border: 1px solid var(--border); width: 32px; padding: 0; display:flex; justify-content:center; align-items:center; }
        .secondary-btn:hover { background: #444; }

        /* --- 节点模式 --- */
        #view-node { cursor: grab; }
        #view-node:active { cursor: grabbing; }
        .node-transform-layer { width: 100%; height: 100%; transform-origin: 0 0; position: absolute; top: 0; left: 0; }

        .node {
            background: rgba(45, 45, 45, 0.95); border: 1px solid var(--border); border-radius: 8px;
            width: 320px; padding: 0; box-shadow: 0 4px 20px rgba(0,0,0,0.2);
            position: absolute; z-index: 5; transition: box-shadow 0.2s;
        }
        .node:hover { border-color: #666; }
        .node-header {
            background: #383838; padding: 8px 12px; border-bottom: 1px solid var(--border);
            font-family: var(--font-mono); font-size: 11px; font-weight: bold; color: #ddd;
            border-radius: 8px 8px 0 0; cursor: move; display:flex; justify-content:space-between; align-items: center;
        }
        .node-delete { cursor: pointer; color: #ff6b6b; font-weight: bold; padding: 0 5px; }
        .node-body { padding: 12px; display: flex; flex-direction: column; gap: 10px; }
        .node-field { display: flex; flex-direction: column; gap: 4px; position: relative; }
        .node-field label { font-size: 10px; color: var(--text-sub); font-family: var(--font-mono); display: flex; justify-content: space-between; }
        .node-field input, .node-field textarea { background: #222; border-color: #444; font-size: 11px; }
        
        .node-thumb { width: 100%; height: 240px; object-fit: contain; background: #111; border: 1px dashed #444; margin-top: 5px; border-radius: 4px; display: none; }
        .node-thumb[src] { display: block; }

        .port { width: 10px; height: 10px; background: #666; border-radius: 50%; border: 2px solid #333; position: absolute; top: 50%; transform: translateY(-50%); cursor: crosshair; }
        .port-in { left: -6px; } .port-out { right: -6px; }
        
        svg.connections { position: absolute; top: 0; left: 0; width: 100%; height: 100%; pointer-events: none; z-index: 1; overflow: visible; }
        path.connector { fill: none; stroke: #666; stroke-width: 2; opacity: 0.6; }

        /* 预览区 */
        .preview-box { width: 100%; height: 240px; background: #111; border-radius: 4px; display: flex; align-items: center; justify-content: center; overflow: hidden; color:#555; font-size:10px; border:1px dashed #444; position:relative; }
        .preview-box img, .preview-box video { width:100%; height:100%; object-fit:contain; }
        .node-timer { position: absolute; top: 5px; right: 5px; background: rgba(0,0,0,0.6); color: var(--accent); font-family: var(--font-mono); font-size: 10px; padding: 2px 5px; border-radius: 3px; display:none;}

        /* 主历史记录页面 */
        #view-history { padding: 20px; overflow-y: auto; }
        .gallery-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 20px; padding-bottom: 50px; }
        .history-card { background: var(--panel-bg); border: 1px solid var(--border); border-radius: 8px; overflow: hidden; transition: transform 0.2s; position: relative; }
        .history-card:hover { transform: translateY(-5px); border-color: var(--accent); }
        .history-img, .history-video { width: 100%; height: 200px; object-fit: cover; background: #000; cursor: pointer; }
        .history-meta { padding: 10px; font-size: 10px; color: #888; font-family: var(--font-mono); display: flex; justify-content: space-between; align-items: center; }
        .trash-btn { cursor: pointer; color: #ff6b6b; padding: 4px; }
        .trash-btn:hover { color: #ff4444; }

        /* 弹窗 */
        .modal-overlay { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.7); backdrop-filter: blur(4px); z-index: 200; display: none; justify-content: center; align-items: center; }
        .modal-content { background: #2d2d2d; border: 1px solid #555; color: #fff; border-radius: 12px; padding: 20px; display: flex; flex-direction: column; box-shadow: 0 20px 50px rgba(0,0,0,0.5); }
        .modal-large { width: 800px; max-width: 95%; height: 80%; }
        .modal-small { width: 360px; max-width: 90%; }

        .lightbox { position: fixed; top:0; left:0; width:100%; height:100%; background:black; z-index:300; display:none; justify-content:center; align-items:center; }
        .lightbox img, .lightbox video { max-width:95%; max-height:95%; box-shadow: 0 0 30px rgba(255,255,255,0.2); }

        .add-node-btn {
            position: absolute; bottom: 20px; left: 20px; width: 50px; height: 50px; border-radius: 25px;
            background: var(--accent); color: white; font-size: 24px; display: flex; align-items: center; justify-content: center;
            cursor: pointer; box-shadow: 0 5px 15px rgba(0,0,0,0.5); transition: transform 0.2s; z-index: 80;
        }
        .add-node-btn:hover { transform: scale(1.1); }

        /* CodeMirror 样式调整 */
        .CodeMirror {
            font-family: var(--font-mono);
            font-size: 20px;
            background: #272822 !important;
            color: #f8f8f2 !important;
            line-height: 2.0;
        }

        /* 修复行号位置 */
        .CodeMirror-gutters {
            background-color: #1e1e1e !important;
            border-right: 2px solid #444 !important;
            min-width: 80px;
        }

        .CodeMirror-linenumber {
            color: #75715e !important;
            padding: 0 15px 0 25px !important;
            text-align: right !important;
            font-size: 18px;
            min-width: 60px;
        }

        /* 代码区域样式 */
        .CodeMirror-lines {
            padding: 20px 0 !important;
        }

        .CodeMirror pre.CodeMirror-line,
        .CodeMirror pre.CodeMirror-line-like {
            padding-left: 25px !important;
            line-height: 2.0 !important;
        }

        /* JSON 语法高亮颜色 - monokai主题优化 */
        .cm-property { color: #66d9ef !important; }
        .cm-string { color: #e6db74 !important; }
        .cm-number { color: #ae81ff !important; }
        .cm-atom { color: #ae81ff !important; }
        .cm-boolean { color: #ae81ff !important; }
        .cm-keyword { color: #f92672 !important; }
        .cm-variable { color: #f8f8f2 !important; }
        .cm-variable-2 { color: #9effff !important; }
        .cm-variable-3 { color: #66d9ef !important; }
        .cm-def { color: #fd971f !important; }
        .cm-operator { color: #f8f8f2 !important; }
        .cm-comment { color: #75715e !important; font-style: italic !important; }
        .cm-bracket { color: #f8f8f2 !important; }
        .cm-tag { color: #f92672 !important; }
        .cm-attribute { color: #a6e22e !important; }

        /* 匹配的括号高亮 */
        .CodeMirror-matchingbracket {
            color: #fff !important;
            background-color: rgba(255, 255, 255, 0.1) !important;
            outline: 1px solid rgba(255, 255, 255, 0.2) !important;
        }

        /* 选中文本样式 */
        .CodeMirror-selected {
            background: rgba(74, 192, 255, 0.25) !important;
        }

        /* 光标样式 */
        .CodeMirror-cursor {
            border-left: 2px solid #f8f8f0 !important;
        }

        /* 滚动条样式 */
        .CodeMirror-scrollbar-filler,
        .CodeMirror-gutter-filler {
            background-color: #272822 !important;
        }

        .CodeMirror-vscrollbar::-webkit-scrollbar,
        .CodeMirror-hscrollbar::-webkit-scrollbar {
            width: 12px;
            height: 12px;
        }

        .CodeMirror-vscrollbar::-webkit-scrollbar-track,
        .CodeMirror-hscrollbar::-webkit-scrollbar-track {
            background: #1e1e1e;
        }

        .CodeMirror-vscrollbar::-webkit-scrollbar-thumb,
        .CodeMirror-hscrollbar::-webkit-scrollbar-thumb {
            background: #444;
            border-radius: 6px;
        }

        .CodeMirror-vscrollbar::-webkit-scrollbar-thumb:hover,
        .CodeMirror-hscrollbar::-webkit-scrollbar-thumb:hover {
            background: #555;
        }

        /* 每行之间的分隔线 */
        .CodeMirror-line {
            padding-bottom: 8px;
            position: relative;
            margin-bottom: 5px;
        }

        .CodeMirror-line::after {
            content: '';
            position: absolute;
            bottom: 0;
            left: 0;
            right: 0;
            height: 1px;
            background: rgba(255, 255, 255, 0.05);
        }

        /* 确保所有编辑器容器高度 */
        #json-editor-container .CodeMirror,
        #config-editor-container .CodeMirror {
            height: auto !important;
            min-height: 500px !important;
        }

        /* 编辑器内容区域高度 */
        .CodeMirror-scroll {
            overflow-x: auto !important;
            overflow-y: auto !important;
            min-height: 400px !important;
        }

        /* 修复模态框中的CodeMirror显示问题 */
        .modal-content .CodeMirror {
            height: 400px !important;
            min-height: 400px !important;
        }

        .modal-content .CodeMirror-scroll {
            min-height: 400px !important;
        }

    </style>
</head>
<body>

    <!-- Sidebar -->
    <div class="sidebar">
        <div class="icon-btn active" onclick="switchMode('canvas')" title="Canvas">
            <svg width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"></path></svg>
        </div>
        <div class="icon-btn" onclick="switchMode('node')" title="Workflow">
            <svg width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><circle cx="18" cy="5" r="3"></circle><circle cx="6" cy="12" r="3"></circle><circle cx="18" cy="19" r="3"></circle><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"></line><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"></line></svg>
        </div>
        <div class="icon-btn" onclick="switchMode('history')" title="History">
            <svg width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"></path></svg>
        </div>
        <div class="icon-btn" onclick="switchMode('config')" title="Config Manager">
            <svg width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path></svg>
        </div>
    </div>

    <div class="main-area">
        <div class="header">
            <div style="font-weight: 700; display:flex; align-items:center; gap:10px;">
                BizyAIR <span style="color:#666; font-weight:400;">NanoBanana 2 金币版(BizyAIR充值金币使用)</span>
            </div>
            <div style="display:flex; gap:10px;">
                <button class="header-btn" onclick="openEditConfigModal()" title="Edit JSON" id="btn-edit-json" style="display:none;">
                    <svg width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4"/></svg>
                </button>
                <button class="header-btn" onclick="openImportModal()" title="Import JSON" id="btn-import" style="display:none;">
                    <svg width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12"></path></svg>
                </button>
                <button class="header-btn" onclick="openApiModal()" title="Settings">
                    <svg width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"></path><circle cx="12" cy="12" r="3"></circle></svg>
                </button>
            </div>
        </div>

        <!-- View 1: Canvas -->
        <div id="view-canvas" class="workspace active">
            <div class="canvas-wrapper" id="canvas-scale-wrap">
                <canvas id="drawing-canvas"></canvas>
            </div>
            
            <div class="floating-panel">
                <button class="action-btn secondary-btn" onclick="undoCanvas()" title="Undo">↩</button>
                <button class="action-btn secondary-btn" onclick="clearCanvas()" title="Clear">🗑</button>
                
                <div class="input-group">
                    <label>OPERATION</label>
                    <select id="operation-select">
                        <option value="edit" selected>Edit</option>
                        <option value="generate">Generate</option>
                        <option value="style_transfer">Style Transfer</option>
                        <option value="object_insertion">Object Insertion</option>
                    </select>
                </div>

                <div class="input-group">
                    <label>ASPECT RATIO</label>
                    <select id="aspect-ratio-select" onchange="updateCanvasRatio()">
                        <option value="1:1" data-w="1024" data-h="1024" selected>1:1</option>
                        <option value="16:9" data-w="1280" data-h="720">16:9</option>
                        <option value="9:16" data-w="720" data-h="1280">9:16</option>
                        <option value="4:3" data-w="1024" data-h="768">4:3</option>
                        <option value="3:4" data-w="768" data-h="1024">3:4</option>
                    </select>
                </div>

                <div class="input-group">
                    <label>RESOLUTION</label>
                    <select id="resolution-select">
                        <option value="1K" selected>1K</option>
                        <option value="2K">2K</option>
                        <option value="4K">4K</option>
                    </select>
                </div>

                <div class="input-group" style="flex: 2;">
                    <label>PROMPT</label>
                    <input type="text" id="canvas-prompt" value="老虎举着一张牌子，上面写着“BizyAir x NanoBananaPro”" placeholder="Input prompt...">
                </div>
                
                <!-- 生成按钮区域，包含计时器 -->
                <div style="display:flex; flex-direction:column; align-items:center;">
                    <div class="timer-display" id="canvas-timer">0.00s</div>
                    <button id="btn-canvas-generate" class="action-btn" onclick="startGeneration()">GENERATE</button>
                </div>
            </div>
        </div>

        <!-- View 2: Node Flow -->
        <div id="view-node" class="workspace">
            <div class="node-transform-layer" id="node-layer">
                <svg class="connections" id="connections-layer"></svg>
            </div>
            <div class="add-node-btn" onclick="openAddNodeModal()" title="Add Custom Node">+</div>
        </div>

        <!-- View 3: Main History -->
        <div id="view-history" class="workspace">
            <h2 style="margin-bottom:20px; font-family:var(--font-mono); color:#888;">GENERATION HISTORY</h2>
            <div class="gallery-grid" id="history-grid"></div>
        </div>

        <!-- View 4: Config Manager -->
        <div id="view-config" class="workspace">
            <h2 style="margin-bottom:20px; font-family:var(--font-mono); color:#888;">CONFIG MANAGER</h2>
            <div style="display:flex; gap:15px; height:calc(100% - 60px); overflow:hidden;">
                <!-- 左侧文件列表 -->
                <div style="width:200px; border:1px solid #444; border-radius:6px; overflow-y:auto; background:#1a1a1a;">
                    <div style="padding:10px; border-bottom:1px solid #444; font-family:var(--font-mono); font-size:10px; color:#888;">JSON FILES</div>
                    <div id="config-file-list" style="padding:5px;"></div>
                </div>
                <!-- 右侧编辑器 -->
                <div style="flex:1; display:flex; flex-direction:column;">
                    <div style="display:flex; gap:10px; margin-bottom:10px;">
                        <input type="text" id="current-config-name" placeholder="Select a file..." style="flex:1; padding:8px; border-radius:4px; font-size:11px; font-family:var(--font-mono); background:#1a1a1a; border:1px solid #444; color:#eee; display:none;" />
                        <button id="import-to-nodes-btn" class="action-btn secondary-btn" onclick="importConfigToNodes()" style="width:auto; padding:8px 15px; display:none; font-size:11px;" title="导入到节点模式">
                            <span style="display:inline-block; transform:rotate(45deg); margin-right:5px;">⎘</span>
                            导入节点
                        </button>
                    </div>
                    <div id="config-editor-container" style="flex:1; border:1px solid #444; min-height: 600px;"></div>
                    <div style="display:flex; gap:10px; margin-top:10px; justify-content:flex-end;">
                        <button class="action-btn secondary-btn" onclick="deleteCurrentConfig()" style="width:auto;">DELETE</button>
                        <button class="action-btn" onclick="saveCurrentConfig()" style="width:auto;">SAVE</button>
                    </div>
                </div>
            </div>
            <div style="display:flex; gap:10px; justify-content:flex-end; margin-top:15px;">
                <button class="action-btn" onclick="loadConfigToWorkspace()" style="width:auto;">LOAD TO WORKSPACE</button>
            </div>
        </div>

        <!-- 右侧同步画廊 -->
        <div class="right-sidebar" id="right-sidebar">
            <div style="padding:10px; font-family:var(--font-mono); font-size:11px; color:#888; text-align:center; border-bottom:1px solid var(--border);">
                GALLERY
            </div>
            <div class="gallery-scroll-area" id="mini-gallery">
                <!-- Mini Cards -->
            </div>
            <button class="gallery-toggle-btn" onclick="toggleRightSidebar()">HIDE PANEL ▼</button>
        </div>
        <!-- 侧边栏开启按钮 -->
        <div class="gallery-open-trigger" id="gallery-trigger" onclick="toggleRightSidebar()" style="display:none;">
            <svg width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path d="M4 6h16M4 12h16m-7 6h7"></path></svg>
        </div>

    </div>

    <!-- Modals -->
    <div class="modal-overlay" id="api-modal">
        <div class="modal-content modal-small">
            <h3 style="margin-bottom:15px; font-family:var(--font-mono);">API SETTINGS</h3>
            <div class="input-group" style="margin-bottom:20px;">
                <label>API Authorization Key</label>
                <input type="password" id="api-key-field" placeholder="输入您的API密钥（不需要Bearer前缀）">
            </div>
            <div style="display:flex; gap:10px; justify-content:flex-end;">
                <button class="action-btn secondary-btn" onclick="document.getElementById('api-modal').style.display='none'" style="width:auto;">CANCEL</button>
                <button class="action-btn" onclick="saveApiKey()" style="width:auto;">SAVE</button>
            </div>
        </div>
    </div>

    <div class="modal-overlay" id="import-modal">
        <div class="modal-content modal-large">
            <h3 style="margin-bottom:10px; font-family:var(--font-mono);">JSON CONFIGURATION</h3>
            <div id="json-editor-container" style="flex:1; border:1px solid #444; margin-bottom:10px; min-height: 500px;"></div>
            <div style="display:flex; gap:10px; align-items:center; margin-bottom:10px;">
                <label style="font-family:var(--font-mono); font-size:11px; color:var(--text-sub);">文件名:</label>
                <input type="text" id="json-filename" placeholder="config" style="flex:1; padding:8px; border-radius:4px; font-size:11px; background:#1a1a1a; border:1px solid #444; color:#eee;">
                <button class="action-btn" onclick="saveJsonToFile()" style="width:auto;">SAVE TO FILE</button>
            </div>
            <div style="display:flex; gap:10px; justify-content:flex-end;">
                <button class="action-btn secondary-btn" onclick="closeJsonEditor()" style="width:auto;">CLOSE</button>
                <button class="action-btn" onclick="runImport()" style="width:auto;">APPLY</button>
            </div>
        </div>
    </div>

    <div class="modal-overlay" id="add-node-modal">
        <div class="modal-content modal-small">
            <h3 style="margin-bottom:10px; font-family:var(--font-mono);">ADD NODE</h3>
            <div class="input-group" style="margin-bottom:10px;">
                <label>Node Definition (ID:Name.Type)</label>
                <input type="text" id="add-node-key" placeholder='3:BizyAirSiliconCloudLLMAPI.user_prompt'>
            </div>
            <div class="input-group" style="margin-bottom:20px;">
                <label>Default Value</label>
                <input type="text" id="add-node-value" placeholder='Enter value...'>
            </div>
            <div style="display:flex; gap:10px; justify-content:flex-end;">
                <button class="action-btn secondary-btn" onclick="document.getElementById('add-node-modal').style.display='none'" style="width:auto;">CANCEL</button>
                <button class="action-btn" onclick="addManualNode()" style="width:auto;">ADD</button>
            </div>
        </div>
    </div>

    <div class="lightbox" id="lightbox" onclick="this.style.display='none'">
        <div id="lightbox-content" style="display:flex;justify-content:center;align-items:center;width:100%;height:100%"></div>
    </div>


    <script>
        // --- Global State ---
        let currentMode = 'canvas';
        let apiKey = localStorage.getItem('id_works_api_key') || '';
        let canvasScale = 1.0; 
        let nodeScale = 1, nodePanX = 0, nodePanY = 0;
        let nodes = [];
        let currentWebAppId = 39419; 
        
        let strokeCanvas = document.createElement('canvas'); 
        let canvasImages = []; 
        let selectedImageIndex = -1;
        let isDraggingImage = false;
        let dragStart = { x: 0, y: 0 };
        let strokeHistory = [];
        
        let timerInterval = null; // Timer handle

        // CodeMirror 编辑器实例
        let jsonEditor = null;
        let configEditor = null;
        let currentConfigFile = null;

        window.onload = () => {
            initCanvas();
            loadHistory();
            if(nodes.length === 0) createDefaultNodes();
            window.addEventListener('paste', handlePaste);
            window.addEventListener('keydown', (e) => {
                if(currentMode === 'canvas' && selectedImageIndex !== -1 && (e.key === 'Delete' || e.key === 'Backspace')) {
                    canvasImages.splice(selectedImageIndex, 1);
                    selectedImageIndex = -1;
                    redrawCanvas();
                }
            });
            
            // 默认打开右侧画廊
            toggleRightSidebar(true);

            // 初始化 CodeMirror 编辑器
            initCodeMirrorEditors();
        };

        function switchMode(mode) {
            currentMode = mode;
            document.querySelectorAll('.workspace').forEach(el => el.classList.remove('active'));
            document.getElementById(`view-${mode}`).classList.add('active');

            document.querySelectorAll('.sidebar .icon-btn').forEach((btn, idx) => {
                btn.classList.toggle('active', (mode==='canvas'&&idx===0)||(mode==='node'&&idx===1)||(mode==='history'&&idx===2)||(mode==='config'&&idx===3));
            });

            const isNode = (mode === 'node');
            document.getElementById('btn-import').style.display = isNode ? 'flex' : 'none';
            document.getElementById('btn-edit-json').style.display = isNode ? 'flex' : 'none';

            if(mode === 'node') renderNodes();
            if(mode === 'history') loadHistory();
            if(mode === 'config') {
                loadConfigFileList();
            }
        }

        // --- Right Sidebar Logic ---
        function toggleRightSidebar(forceOpen) {
            const sidebar = document.getElementById('right-sidebar');
            const trigger = document.getElementById('gallery-trigger');
            const workspaces = document.querySelectorAll('.workspace');
            
            let isOpen = sidebar.classList.contains('open');
            if (forceOpen === true) isOpen = false; // Force to open logic below

            if (isOpen) {
                sidebar.classList.remove('open');
                trigger.style.display = 'flex';
                workspaces.forEach(el => el.classList.remove('shrink'));
            } else {
                sidebar.classList.add('open');
                trigger.style.display = 'none';
                workspaces.forEach(el => el.classList.add('shrink'));
            }
        }

        // --- Timer Logic ---
        function startRequestTimer() {
            const start = Date.now();
            const canvasTimer = document.getElementById('canvas-timer');
            const nodeTimer = document.querySelector('.node-timer'); // Inside output node
            
            canvasTimer.classList.add('active');
            if(nodeTimer) nodeTimer.style.display = 'block';

            if(timerInterval) clearInterval(timerInterval);
            
            timerInterval = setInterval(() => {
                const elapsed = ((Date.now() - start) / 1000).toFixed(2);
                const text = elapsed + 's';
                canvasTimer.innerText = text;
                if(nodeTimer) nodeTimer.innerText = text;
            }, 50);
        }

        function stopRequestTimer() {
            if(timerInterval) clearInterval(timerInterval);
            // Don't hide immediately, let user see the final time
        }

        // --- Canvas Logic ---
        const canvas = document.getElementById('drawing-canvas');
        const ctx = canvas.getContext('2d');
        const scaleWrap = document.getElementById('canvas-scale-wrap');

        function initCanvas() {
            updateCanvasRatio();
            document.getElementById('view-canvas').addEventListener('wheel', (e) => {
                if (e.shiftKey && selectedImageIndex !== -1) {
                    e.preventDefault();
                    const imgObj = canvasImages[selectedImageIndex];
                    const delta = e.deltaY > 0 ? 0.95 : 1.05;
                    imgObj.width *= delta; imgObj.height *= delta;
                    redrawCanvas();
                    return;
                }
                if(e.ctrlKey || e.metaKey || !e.shiftKey) {
                    e.preventDefault();
                    const delta = e.deltaY > 0 ? -0.1 : 0.1;
                    canvasScale = Math.min(Math.max(0.2, canvasScale + delta), 5);
                    scaleWrap.style.transform = `scale(${canvasScale})`;
                }
            }, { passive: false });
        }

        function updateCanvasRatio() {
            const select = document.getElementById('aspect-ratio-select');
            const opt = select.options[select.selectedIndex];
            const targetW = parseInt(opt.dataset.w);
            const targetH = parseInt(opt.dataset.h);

            canvas.width = targetW; canvas.height = targetH;
            strokeCanvas.width = targetW; strokeCanvas.height = targetH;
            strokeHistory = []; saveStrokeState();

            const maxDisplaySize = 600; 
            const ratio = targetW / targetH;
            let displayW, displayH;
            if (ratio > 1) { displayW = maxDisplaySize; displayH = maxDisplaySize / ratio; } 
            else { displayH = maxDisplaySize; displayW = maxDisplaySize * ratio; }
            canvas.style.width = `${displayW}px`; canvas.style.height = `${displayH}px`;
            redrawCanvas();
        }

        let isDrawing = false, lx = 0, ly = 0;
        function getPos(e) {
            const rect = canvas.getBoundingClientRect();
            return [(e.clientX - rect.left) * (canvas.width / rect.width), (e.clientY - rect.top) * (canvas.height / rect.height)];
        }
        function getHitImageIndex(x, y) {
            for (let i = canvasImages.length - 1; i >= 0; i--) {
                const img = canvasImages[i];
                if (x >= img.x && x <= img.x + img.width && y >= img.y && y <= img.y + img.height) return i;
            }
            return -1;
        }

        canvas.addEventListener('mousedown', e => {
            const [cx, cy] = getPos(e);
            const hitIndex = getHitImageIndex(cx, cy);
            if (hitIndex !== -1) {
                selectedImageIndex = hitIndex; isDraggingImage = true;
                const img = canvasImages[hitIndex];
                dragStart = { x: cx - img.x, y: cy - img.y };
                canvas.style.cursor = "move"; redrawCanvas();
            } else {
                selectedImageIndex = -1; isDrawing = true; [lx, ly] = [cx, cy];
                canvas.style.cursor = "crosshair"; redrawCanvas();
            }
        });

        canvas.addEventListener('mousemove', e => {
            const [cx, cy] = getPos(e);
            if (!isDrawing && !isDraggingImage) canvas.style.cursor = getHitImageIndex(cx, cy) !== -1 ? "move" : "crosshair";
            if (isDraggingImage && selectedImageIndex !== -1) {
                const img = canvasImages[selectedImageIndex];
                img.x = cx - dragStart.x; img.y = cy - dragStart.y; redrawCanvas();
            } else if (isDrawing) {
                const sCtx = strokeCanvas.getContext('2d');
                sCtx.beginPath(); sCtx.moveTo(lx, ly); sCtx.lineTo(cx, cy);
                sCtx.strokeStyle = "#000"; sCtx.lineWidth = 5; sCtx.lineCap = 'round'; sCtx.stroke();
                [lx, ly] = [cx, cy]; redrawCanvas();
            }
        });

        canvas.addEventListener('mouseup', () => {
            if (isDrawing) saveStrokeState();
            isDrawing = false; isDraggingImage = false;
        });

        function redrawCanvas() {
            ctx.fillStyle = "#ffffff"; ctx.fillRect(0, 0, canvas.width, canvas.height);
            canvasImages.forEach((obj, idx) => {
                ctx.drawImage(obj.img, obj.x, obj.y, obj.width, obj.height);
                if(idx === selectedImageIndex) { ctx.strokeStyle = "#4dabf7"; ctx.lineWidth = 3; ctx.strokeRect(obj.x, obj.y, obj.width, obj.height); }
            });
            ctx.drawImage(strokeCanvas, 0, 0);
        }

        function saveStrokeState() {
            if (strokeHistory.length > 20) strokeHistory.shift();
            strokeHistory.push(strokeCanvas.toDataURL());
        }
        function undoCanvas() {
            if (strokeHistory.length <= 1) { strokeCanvas.getContext('2d').clearRect(0, 0, strokeCanvas.width, strokeCanvas.height); redrawCanvas(); return; }
            strokeHistory.pop();
            const img = new Image(); img.src = strokeHistory[strokeHistory.length - 1];
            img.onload = () => { strokeCanvas.getContext('2d').clearRect(0, 0, strokeCanvas.width, strokeCanvas.height); strokeCanvas.getContext('2d').drawImage(img, 0, 0); redrawCanvas(); };
        }
        function clearCanvas() {
            strokeCanvas.getContext('2d').clearRect(0, 0, strokeCanvas.width, strokeCanvas.height);
            strokeHistory = []; saveStrokeState(); canvasImages = []; selectedImageIndex = -1; redrawCanvas();
        }
        function handlePaste(e) {
            if (currentMode !== 'canvas') return;
            const items = e.clipboardData.items;
            for (let i = 0; i < items.length; i++) {
                if (items[i].type.indexOf('image') !== -1) {
                    const blob = items[i].getAsFile(); const url = URL.createObjectURL(blob); const img = new Image();
                    img.onload = () => {
                        const aspect = img.width / img.height;
                        let w = canvas.width * 0.5; let h = w / aspect;
                        canvasImages.push({ img: img, x: (canvas.width - w)/2, y: (canvas.height - h)/2, width: w, height: h, id: Date.now() });
                        selectedImageIndex = canvasImages.length - 1; redrawCanvas();
                    }; img.src = url; e.preventDefault();
                }
            }
        }

        // --- Node Logic ---
        function createDefaultNodes() {
            parseAndBuildNodes({
                "web_app_id": 39419,
                "input_values": { "2:LoadImage.image": "", "3:BizyAirSiliconCloudLLMAPI.user_prompt": "Default Prompt", "1:BizyAir_NanoBananaPro.operation": "edit" }
            });
        }
        function openImportModal() {
            if (jsonEditor) {
                jsonEditor.setValue('');
            }
            document.getElementById('import-modal').style.display = 'flex';
            // 刷新编辑器以确保正确显示
            setTimeout(() => {
                if (jsonEditor) jsonEditor.refresh();
            }, 10);
        }
        function openEditConfigModal() {
            if (jsonEditor) {
                jsonEditor.setValue(JSON.stringify(generateJSONFromNodes(), null, 2));
            }
            document.getElementById('import-modal').style.display = 'flex';
            // 刷新编辑器以确保正确显示
            setTimeout(() => {
                if (jsonEditor) jsonEditor.refresh();
            }, 10);
        }
        function openAddNodeModal() { document.getElementById('add-node-modal').style.display = 'flex'; }

        function generateJSONFromNodes() {
            const inputs = {};
            document.querySelectorAll('.live-input').forEach(inp => {
                let val = inp.value;
                if(!isNaN(val) && val.trim() !== "") val = Number(val);
                inputs[inp.dataset.key] = val;
            });
            return { "web_app_id": currentWebAppId, "suppress_preview_output": false, "input_values": inputs };
        }

        function addManualNode() {
            const key = document.getElementById('add-node-key').value.trim();
            const val = document.getElementById('add-node-value').value.trim();
            if(!key) return;
            const match = key.match(/^(\d+):([^.]+)\.(.+)$/);
            if (!match) { alert("Invalid Format"); return; }
            const [_, id, name, field] = match;
            let existing = nodes.find(n => n.id === id);
            if(existing) existing.inputs.push({ key, field, value: val, type: 'string' });
            else nodes.splice(nodes.length-1, 0, { id, name, inputs: [{ key, field, value: val, type: 'string' }], x: 100, y: 100 });
            document.getElementById('add-node-modal').style.display='none'; renderNodes();
        }

        function deleteNode(nodeId) { if(confirm("Delete node?")) { nodes = nodes.filter(n => n.id !== nodeId); renderNodes(); } }
        function runImport() {
            try {
                const jsonContent = jsonEditor ? jsonEditor.getValue() : '';
                if (!jsonContent.trim()) {
                    alert('没有 JSON 内容');
                    return;
                }
                nodes = [];
                parseAndBuildNodes(JSON.parse(jsonContent));
                document.getElementById('import-modal').style.display = 'none';
                renderNodes();
            } catch (e) {
                alert(e.message);
            }
        }

        function parseAndBuildNodes(json) {
            if (json.web_app_id) currentWebAppId = json.web_app_id;
            const inputs = json.input_values || {};
            const nodeMap = {};
            for (let key in inputs) {
                const match = key.match(/^(\d+):([^.]+)\.(.+)$/);
                if (match) {
                    const [_, id, name, field] = match;
                    if (!nodeMap[id]) nodeMap[id] = { id, name, inputs: [], x: 0, y: 0 };
                    nodeMap[id].inputs.push({ key, field, value: inputs[key], type: typeof inputs[key] });
                }
            }
            let nodeList = Object.values(nodeMap);
            let startNode = nodeList.find(n => n.name.toLowerCase().includes('loadimage'));
            nodes = startNode ? [startNode, ...nodeList.filter(n => n !== startNode)] : nodeList;
            let x = 80; 
            nodes.forEach(node => { node.x = x; node.y = 100; x += 380; });
            nodes.push({ id: "OUTPUT", name: "Result Output", x: x, y: 100, isOutput: true, appId: currentWebAppId });
        }

        function renderNodes() {
            const layer = document.getElementById('node-layer');
            layer.querySelectorAll('.node').forEach(n => n.remove());
            nodes.forEach((n, index) => {
                const el = document.createElement('div');
                el.className = 'node'; el.style.left = n.x + 'px'; el.style.top = n.y + 'px'; el.dataset.id = n.id;
                let deleteHtml = (index === 0 || n.isOutput) ? '' : `<span class="node-delete" onclick="deleteNode('${n.id}')">×</span>`;
                let html = `<div class="node-header"><span>${n.id}: ${n.name}</span>${deleteHtml}</div><div class="node-body">`;
                
                if (n.isOutput) {
                    html += `<div style="display:flex;justify-content:space-between;font-size:11px;color:#888;"><span>ID:</span><span style="color:var(--accent)">${n.appId}</span></div>
                             <div class="preview-box" id="node-output-preview"><span class="node-timer">0.00s</span>Waiting...</div>
                             <button class="action-btn" style="width:100%; margin-top:5px;" onclick="startGeneration()">RUN FLOW ▶</button>
                             <div class="port port-in" style="top:50%"></div>`;
                } else {
                    if(index>0) html += `<div class="port port-in" style="top:50%"></div>`;
                    html += `<div class="port port-out" style="top:50%"></div>`;
                    n.inputs.forEach(inp => {
                        html += `<div class="node-field"><label>${inp.field}</label>`;
                        if (inp.field === 'image') {
                            // 判断是URL还是文件路径
                            const isUrl = inp.value && (inp.value.startsWith('http') || inp.value.startsWith('data:image'));
                            const displayValue = inp.value && !inp.value.startsWith('data:image') ? inp.value : '';

                            html += `<div style="margin-bottom:10px;">
                                        <select id="image-source-${inp.key}" onchange="toggleImageSource('${inp.key}')" style="width:100%; padding:4px; background:#2a2a2a; border:1px solid #444; color:#ccc; border-radius:4px; margin-bottom:5px;">
                                            <option value="url" ${isUrl ? 'selected' : ''}>URL图片</option>
                                            <option value="file" ${!isUrl && inp.value ? 'selected' : ''}>本地文件</option>
                                        </select>
                                     </div>
                                     <div id="url-input-${inp.key}" style="${isUrl ? 'display:block' : 'display:none'}">
                                        <input type="url" class="live-input" data-key="${inp.key}" value="${displayValue}" placeholder="输入图片URL..." onblur="updateImagePreview('${inp.key}', this.value)" style="width:100%; margin-bottom:5px;">
                                     </div>
                                     <div id="file-input-${inp.key}" style="${!isUrl && inp.value ? 'display:block' : 'display:none'}">
                                        <div style="display:flex; gap:5px; margin-bottom:5px;">
                                            <input type="text" id="file-path-${inp.key}" value="${!isUrl && inp.value ? inp.value : ''}" placeholder="点击选择本地文件..." readonly style="flex:1; padding:4px; background:#2a2a2a; border:1px solid #444; color:#ccc; border-radius:4px;">
                                            <input type="file" accept="image/*" onchange="handleImageFileUpload(this, '${inp.key}')" style="display:none;">
                                            <button onclick="this.previousElementSibling.click()" class="action-btn" style="width:auto; padding:0 10px; font-size:10px;">选择文件</button>
                                        </div>
                                     </div>
                                     <img id="preview-${inp.key}" src="${isUrl ? inp.value : (inp.value && inp.value.startsWith('data:') ? inp.value : '')}" class="node-thumb"
                                          ${isUrl || (inp.value && inp.value.startsWith('data:')) ? `onload="this.style.display='block'"` : ''}
                                          style="${isUrl || (inp.value && inp.value.startsWith('data:')) ? 'display:block' : 'display:none'}">`;
                        } else if (inp.field.toLowerCase().includes('prompt')) {
                            html += `<textarea class="live-input" data-key="${inp.key}" rows="4" placeholder="输入提示词...">${inp.value}</textarea>`;
                        } else if (inp.type === 'string' && inp.value.toString().length > 40) {
                            html += `<textarea class="live-input" data-key="${inp.key}" rows="4">${inp.value}</textarea>`;
                        } else {
                            html += `<input type="text" class="live-input" data-key="${inp.key}" value="${inp.value}">`;
                        }
                        html += `</div>`;
                    });
                }
                html += `</div>`; el.innerHTML = html; layer.appendChild(el); setupNodeDrag(el, n);
            });
            drawDynamicConnections();
        }

        function drawDynamicConnections() {
            const svg = document.getElementById('connections-layer'); svg.innerHTML = '';
            for(let i=0; i<nodes.length-1; i++) {
                const n1 = nodes[i], n2 = nodes[i+1];
                const el1 = document.querySelector(`.node[data-id="${n1.id}"]`), el2 = document.querySelector(`.node[data-id="${n2.id}"]`);
                if(!el1 || !el2) continue;
                const x1 = parseInt(el1.style.left) + 320, y1 = parseInt(el1.style.top) + el1.offsetHeight/2;
                const x2 = parseInt(el2.style.left), y2 = parseInt(el2.style.top) + el2.offsetHeight/2;
                const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
                path.setAttribute('d', `M ${x1} ${y1} C ${(x1+x2)/2} ${y1}, ${(x1+x2)/2} ${y2}, ${x2} ${y2}`);
                path.setAttribute('class', 'connector'); svg.appendChild(path);
            }
        }

        function setupNodeDrag(el, nodeData) {
            const header = el.querySelector('.node-header');
            if(!header) return;
            header.addEventListener('mousedown', (e) => {
                if(e.target.classList.contains('node-delete')) return;
                e.stopPropagation();
                let startX = e.clientX, startY = e.clientY, origX = nodeData.x, origY = nodeData.y;
                function move(ev) {
                    nodeData.x = origX + (ev.clientX - startX) / nodeScale;
                    nodeData.y = origY + (ev.clientY - startY) / nodeScale;
                    el.style.left = nodeData.x + 'px'; el.style.top = nodeData.y + 'px';
                    drawDynamicConnections();
                }
                function stop() { window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', stop); }
                window.addEventListener('mousemove', move); window.addEventListener('mouseup', stop);
            });
        }
        
        const nodeContainer = document.getElementById('view-node');
        nodeContainer.addEventListener('wheel', (e) => {
            if(e.target.closest('.node')) return; e.preventDefault();
            nodeScale = Math.min(Math.max(0.3, nodeScale + (e.deltaY > 0 ? -0.05 : 0.05)), 2);
            document.getElementById('node-layer').style.transform = `translate(${nodePanX}px, ${nodePanY}px) scale(${nodeScale})`;
        }, {passive:false});
        nodeContainer.addEventListener('mousedown', (e) => {
            if(e.target.closest('.node')) return;
            let sx = e.clientX, sy = e.clientY, px = nodePanX, py = nodePanY;
            function pan(ev) { nodePanX = px + (ev.clientX - sx); nodePanY = py + (ev.clientY - sy); document.getElementById('node-layer').style.transform = `translate(${nodePanX}px, ${nodePanY}px) scale(${nodeScale})`; }
            function stop() { window.removeEventListener('mousemove', pan); window.removeEventListener('mouseup', stop); }
            window.addEventListener('mousemove', pan); window.addEventListener('mouseup', stop);
        });

        async function startGeneration() {
            if(!apiKey) { alert("Please set API Key first."); openApiModal(); return; }

            const previewBox = document.getElementById('node-output-preview');
            const canvasBtn = document.getElementById('btn-canvas-generate');
            let originalText = "";

            startRequestTimer(); // Start Timer

            if (canvasBtn) { originalText = canvasBtn.innerText; canvasBtn.innerText = "RUNNING..."; }
            document.querySelectorAll('.action-btn').forEach(b => b.disabled = true);

            try {
                let payload = {};
                if (currentMode === 'canvas') {
                    const prevSelect = selectedImageIndex; selectedImageIndex = -1; redrawCanvas();
                    const operation = document.getElementById('operation-select').value;
                    const aspectRatio = document.getElementById('aspect-ratio-select').value;
                    const resolution = document.getElementById('resolution-select').value;
                    const prompt = document.getElementById('canvas-prompt').value;
                    redrawCanvas();
                    payload = { "web_app_id": 39419, "suppress_preview_output": false, "input_values": {
                        "2:LoadImage.image": canvas.toDataURL('image/png'), "3:BizyAirSiliconCloudLLMAPI.user_prompt": prompt,
                        "1:BizyAir_NanoBananaPro.operation": operation, "1:BizyAir_NanoBananaPro.aspect_ratio": aspectRatio, "1:BizyAir_NanoBananaPro.resolution": resolution
                    }};
                    selectedImageIndex = prevSelect; redrawCanvas();
                } else { payload = generateJSONFromNodes(); }

                // 打印请求负载到控制台
                console.log('Sending payload:', JSON.stringify(payload, null, 2));
                console.log('API Key:', apiKey ? apiKey.substring(0, 20) + '...' : 'No API key');
                console.log('Web App ID:', payload.web_app_id);

                // 确保API密钥格式正确（添加Bearer前缀）
              const authKey = apiKey.startsWith('Bearer ') ? apiKey : `Bearer ${apiKey}`;

              const res = await fetch('https://api.bizyair.cn/w/v1/webapp/task/openapi/create', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': authKey
                    },
                    body: JSON.stringify(payload)
                });

                // 检查HTTP响应状态
                if (!res.ok) {
                    const errorText = await res.text();
                    console.error('HTTP Error Response:', errorText);
                    console.error('Response headers:', Object.fromEntries(res.headers.entries()));
                    throw new Error(`HTTP ${res.status}: ${res.statusText}\n${errorText}`);
                }

                // 检查响应内容类型
                const contentType = res.headers.get('content-type');
                console.log('Response Content-Type:', contentType);

                let result;
                try {
                    const responseText = await res.text();
                    console.log('Raw Response:', responseText);
                    result = JSON.parse(responseText);
                } catch (parseError) {
                    console.error('Failed to parse JSON response:', parseError);
                    throw new Error('Invalid JSON response from server');
                }

                // 打印响应到控制台以便调试
                console.log('Parsed API Response:', result);

                // 检查API返回的状态
                if (result.status && result.status !== 'Success') {
                    // 如果状态不是Success，可能是处理中或其他状态
                    if (result.status === 'Running' || result.status === 'Pending') {
                        // 任务正在处理中，显示提示
                        if(previewBox) {
                            previewBox.innerHTML = `<span style="color:orange">Task is running...</span><br><small>Request ID: ${result.request_id || 'N/A'}</small>`;
                        }
                        // 可以添加轮询逻辑来检查任务状态
                        setTimeout(() => checkTaskStatus(result.request_id), 3000);
                        return; // 不停止计时器，让用户知道任务在运行
                    }
                    // 输出详细的错误信息
                    console.error('API Error Details:', {
                        status: result.status,
                        message: result.message,
                        error_code: result.error_code,
                        error_type: result.error_type,
                        full_response: result
                    });
                    throw new Error(`API Error: ${result.status} - ${result.message || result.error_type || 'Unknown error'} (Code: ${result.error_code || 'N/A'})`);
                } else if (!result.status) {
                    // 如果没有status字段，可能是不同的API格式
                    console.warn('No status field in response, treating as success');
                }

                let outputUrls = [];
                if(result.outputs && Array.isArray(result.outputs) && result.outputs.length > 0) {
                     // BizyAir API 返回数组，获取所有输出
                     result.outputs.forEach(output => {
                         if(output.object_url) {
                             outputUrls.push(output.object_url);
                         }
                     });
                }

                if(outputUrls.length > 0) {
                    // 构建所有媒体的HTML
                    let mediaHtml = `<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 10px; width: 100%;">`;

                    outputUrls.forEach((url, index) => {
                        const isVideo = url.endsWith('.mp4') || url.endsWith('.webm');
                        const media = isVideo
                            ? `<video src="${url}" autoplay loop muted controls style="width: 100%; height: auto; max-height: 300px; object-fit: contain;"></video>`
                            : `<img src="${url}" style="width: 100%; height: auto; max-height: 300px; object-fit: contain; cursor: pointer;" onclick="showLightbox('${url}')" alt="Output ${index + 1}">`;

                        mediaHtml += `<div style="position: relative;">
                            ${media}
                            <div style="position: absolute; bottom: 5px; right: 5px; background: rgba(0,0,0,0.6); color: white; padding: 2px 5px; font-size: 10px; border-radius: 3px;">
                                ${isVideo ? 'Video' : 'Image'} ${index + 1}
                            </div>
                        </div>`;
                    });

                    mediaHtml += `</div>`;

                    if(previewBox) {
                        previewBox.innerHTML = `<span class="node-timer" style="display:block">${document.getElementById('canvas-timer').innerText}</span>` + mediaHtml;
                    }

                    // 保存所有输出到历史记录
                    outputUrls.forEach(url => saveToHistory(url));

                    // 如果只有一个输出，显示lightbox
                    if(outputUrls.length === 1) {
                        showLightbox(outputUrls[0]);
                    }
                } else {
                    // 没有找到输出URL
                    console.error('No output URLs found in response:', result);
                    if(previewBox) previewBox.innerHTML = `<span style="color:red">No output returned</span>`;
                }
            } catch (e) { alert("Error: " + e.message); if(previewBox) previewBox.innerHTML = `<span style="color:red">Failed</span>`; } 
            finally { 
                stopRequestTimer(); 
                document.querySelectorAll('.action-btn').forEach(b => b.disabled = false); 
                if(canvasBtn) canvasBtn.innerText = originalText; 
            }
        }

        function saveToHistory(url) {
            let h = JSON.parse(localStorage.getItem('id_works_history') || '[]');
            h.unshift({ url, time: new Date().toLocaleTimeString(), id: Date.now() });
            if(h.length > 50) h.pop();
            localStorage.setItem('id_works_history', JSON.stringify(h));
            loadHistory(); // Updates both main and mini gallery
        }
        
        function deleteHistoryItem(timestampId) {
            if(!confirm("Delete this item?")) return;
            let h = JSON.parse(localStorage.getItem('id_works_history') || '[]');
            h = h.filter(item => item.id !== timestampId);
            localStorage.setItem('id_works_history', JSON.stringify(h));
            loadHistory();
        }

        function loadHistory() {
            const mainGrid = document.getElementById('history-grid');
            const miniGrid = document.getElementById('mini-gallery');
            const history = JSON.parse(localStorage.getItem('id_works_history')||'[]');
            
            // Render function
            const renderCard = (i, isMini) => {
                const isVideo = i.url.endsWith('.mp4') || i.url.endsWith('.webm');
                const mediaHtml = isVideo 
                    ? `<video src="${i.url}" class="${isMini?'':'history-video'}" autoplay loop muted onclick="showLightbox('${i.url}')"></video>`
                    : `<img src="${i.url}" class="${isMini?'':'history-img'}" onclick="showLightbox('${i.url}')">`;
                
                return `
                <div class="${isMini ? 'mini-card' : 'history-card'}">
                    ${mediaHtml}
                    <div class="${isMini ? 'mini-card-meta' : 'history-meta'}">
                        <span>${i.time}</span>
                        <div style="display:flex; gap:5px;">
                            <span class="trash-btn" onclick="deleteHistoryItem(${i.id})" title="Delete">🗑</span>
                            <span style="cursor:pointer" onclick="window.open('${i.url}')">⬇</span>
                        </div>
                    </div>
                </div>`;
            };

            mainGrid.innerHTML = history.map(i => renderCard(i, false)).join('');
            miniGrid.innerHTML = history.map(i => renderCard(i, true)).join('');
        }

        function openApiModal() { document.getElementById('api-modal').style.display='flex'; document.getElementById('api-key-field').value = apiKey; }
        function saveApiKey() {
            // 保存密钥时自动移除Bearer前缀
            let key = document.getElementById('api-key-field').value;
            if (key.startsWith('Bearer ')) {
                key = key.substring(7);
            }
            apiKey = key;
            localStorage.setItem('id_works_api_key', apiKey);
            document.getElementById('api-modal').style.display='none';
        }
        function showLightbox(src) {
            const box = document.getElementById('lightbox'); const content = document.getElementById('lightbox-content'); box.style.display='flex';
            content.innerHTML = (src.endsWith('.mp4')||src.endsWith('.webm')) ? `<video src="${src}" controls autoplay style="max-width:95%;max-height:95%"></video>` : `<img src="${src}" style="max-width:95%;max-height:95%">`;
        }

        // --- 新增功能函数 ---

        // 编码文件名以支持中文
        function encodeFilename(filename) {
            return encodeURIComponent(filename);
        }

        // 初始化 CodeMirror 编辑器
        function initCodeMirrorEditors() {
            jsonEditor = CodeMirror(document.getElementById('json-editor-container'), {
                value: '',
                mode: 'application/json',
                theme: 'monokai',
                lineNumbers: true,
                lineWrapping: true,
                indentUnit: 4,
                tabSize: 4,
                smartIndent: true,
                electricChars: true,
                autoCloseBrackets: true,
                matchBrackets: true,
                showCursorWhenSelecting: true,
                undoDepth: 200,
                viewportMargin: 200
            });

            configEditor = CodeMirror(document.getElementById('config-editor-container'), {
                value: '',
                mode: 'application/json',
                theme: 'monokai',
                lineNumbers: true,
                lineWrapping: true,
                indentUnit: 4,
                tabSize: 4,
                smartIndent: true,
                electricChars: true,
                autoCloseBrackets: true,
                matchBrackets: true,
                showCursorWhenSelecting: true,
                undoDepth: 200,
                viewportMargin: 200
            });

            // 强制刷新编辑器以应用样式
            setTimeout(() => {
                jsonEditor.refresh();
                configEditor.refresh();
            }, 100);
        }

        // 切换图片来源（URL/文件）
        function toggleImageSource(key) {
            const source = document.getElementById(`image-source-${key}`).value;
            const urlDiv = document.getElementById(`url-input-${key}`);
            const fileDiv = document.getElementById(`file-input-${key}`);
            const preview = document.getElementById(`preview-${key}`);

            if (source === 'url') {
                urlDiv.style.display = 'block';
                fileDiv.style.display = 'none';
                // 更新输入框的值
                const urlInput = urlDiv.querySelector('input');
                const fileInput = document.querySelector(`.live-input[data-key="${key}"]`);
                if (fileInput && fileInput.value && !fileInput.value.startsWith('data:')) {
                    urlInput.value = fileInput.value;
                }
            } else {
                urlDiv.style.display = 'none';
                fileDiv.style.display = 'block';
            }
        }

        // 更新图片预览（URL模式）
        function updateImagePreview(key, url) {
            const preview = document.getElementById(`preview-${key}`);
            const liveInput = document.querySelector(`.live-input[data-key="${key}"]`);

            if (liveInput) {
                liveInput.value = url;
                liveInput.dispatchEvent(new Event('input'));
            }

            if (url && (url.startsWith('http') || url.startsWith('data:'))) {
                preview.src = url;
                preview.style.display = 'block';
            } else {
                preview.style.display = 'none';
            }
        }

        // 处理本地图片文件上传
        function handleImageFileUpload(input, key) {
            const file = input.files[0];
            if (!file) return;

            const filePathInput = document.getElementById(`file-path-${key}`);
            const preview = document.getElementById(`preview-${key}`);
            const liveInput = document.querySelector(`.live-input[data-key="${key}"]`);

            // 显示文件名
            filePathInput.value = file.name;

            const reader = new FileReader();
            reader.onload = function(e) {
                // 将base64数据保存到live-input中
                if (liveInput) {
                    liveInput.value = e.target.result;
                    liveInput.dispatchEvent(new Event('input'));
                }

                // 更新预览
                preview.src = e.target.result;
                preview.style.display = 'block';
            };
            reader.readAsDataURL(file);
        }

        // 兼容旧的handleImageUpload函数
        function handleImageUpload(input, key) {
            handleImageFileUpload(input, key);
        }

        // 关闭 JSON 编辑器
        function closeJsonEditor() {
            document.getElementById('import-modal').style.display = 'none';
        }

        // 保存 JSON 到文件（保存到服务器）
        async function saveJsonToFile() {
            const content = jsonEditor.getValue();
            if (!content.trim()) {
                alert('没有内容可保存');
                return;
            }

            try {
                const data = JSON.parse(content); // 验证 JSON 格式
            } catch (e) {
                alert('JSON 格式错误: ' + e.message);
                return;
            }

            let filename = document.getElementById('json-filename').value.trim() || 'config';
            // 自动添加 .json 扩展名
            filename += '.json';

            try {
                // 保存到服务器
                const response = await fetch(`http://127.0.0.1:8004/api/config/${encodeFilename(filename)}`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: content
                });

                if (!response.ok) {
                    throw new Error('保存失败');
                }

                alert('配置已保存到 json 文件夹: ' + filename);
            } catch (e) {
                alert('保存失败: ' + e.message);
            }
        }

    
        // 加载配置文件列表
        async function loadConfigFileList() {
            const fileListEl = document.getElementById('config-file-list');
            fileListEl.innerHTML = '<div style="padding:10px; color:#888; font-size:10px;">加载中...</div>';

            try {
                // 从 PHP API 获取文件列表
                const response = await fetch('http://127.0.0.1:8004/api/configs');
                if (!response.ok) {
                    throw new Error('无法连接到配置服务器，请确保服务器已启动');
                }

                const files = await response.json();

                if (files.length === 0) {
                    fileListEl.innerHTML = '<div style="padding:10px; color:#888; font-size:10px;">没有找到 JSON 文件</div>';
                    return;
                }

                fileListEl.innerHTML = '';
                files.forEach(filename => {
                    const fileEl = document.createElement('div');
                    fileEl.className = 'config-file-item';
                    fileEl.style.cssText = `
                        padding: 8px 10px;
                        margin: 2px 0;
                        cursor: pointer;
                        border-radius: 4px;
                        font-size: 11px;
                        font-family: var(--font-mono);
                        color: #ccc;
                        transition: background 0.2s;
                    `;
                    fileEl.textContent = filename;
                    fileEl.onmouseover = () => fileEl.style.background = '#333';
                    fileEl.onmouseout = () => fileEl.style.background = '';
                    fileEl.onclick = () => loadConfigFile(filename);
                    fileListEl.appendChild(fileEl);
                });
            } catch (error) {
                console.error('加载文件列表失败:', error);
                fileListEl.innerHTML = `
                    <div style="padding:10px; color:#ff6666; font-size:10px;">
                        加载失败<br>
                        <small>请确保 PHP 服务器已启动</small>
                    </div>
                `;
            }
        }

        // 加载配置文件内容
        async function loadConfigFile(filename) {
            currentConfigFile = filename;
            const nameInput = document.getElementById('current-config-name');
            const importBtn = document.getElementById('import-to-nodes-btn');

            nameInput.value = filename;
            nameInput.style.display = 'block';
            importBtn.style.display = 'block';

            try {
                const response = await fetch(`http://127.0.0.1:8004/api/config/${encodeFilename(filename)}`);
                if (!response.ok) {
                    throw new Error(`无法加载文件: ${filename}`);
                }

                const config = await response.json();
                configEditor.setValue(JSON.stringify(config, null, 2));
            } catch (error) {
                console.error('加载配置失败:', error);
                alert('加载配置文件失败: ' + error.message);
                configEditor.setValue('');
            }
        }

        // 保存当前配置
        async function saveCurrentConfig() {
            if (!currentConfigFile) {
                alert('请先选择一个配置文件');
                return;
            }

            const nameInput = document.getElementById('current-config-name');
            let newFilename = nameInput.value.trim();

            if (!newFilename) {
                alert('请输入文件名');
                return;
            }

            // 确保 .json 扩展名
            if (!newFilename.endsWith('.json')) {
                newFilename += '.json';
            }

            try {
                const content = configEditor.getValue();
                const data = JSON.parse(content); // 验证格式

                // 如果文件名改变了，需要先删除旧文件
                if (newFilename !== currentConfigFile) {
                    // 删除旧文件
                    await fetch(`http://127.0.0.1:8004/api/config/${encodeFilename(currentConfigFile)}`, {
                        method: 'DELETE'
                    });
                    // 更新当前文件名
                    currentConfigFile = newFilename;
                }

                // 发送到服务器保存
                const response = await fetch(`http://127.0.0.1:8004/api/config/${encodeFilename(newFilename)}`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(data)
                });

                if (!response.ok) {
                    throw new Error('保存失败');
                }

                alert('配置已保存到 json 文件夹: ' + newFilename);
                // 刷新文件列表
                loadConfigFileList();
            } catch (e) {
                alert('保存失败: ' + e.message);
            }
        }

        // 导入配置到节点模式
        async function importConfigToNodes() {
            if (!currentConfigFile) {
                alert('请先选择一个配置文件');
                return;
            }

            try {
                const configContent = configEditor.getValue();
                const config = JSON.parse(configContent);

                // 切换到节点模式
                switchMode('node');

                // 等待节点模式初始化完成
                setTimeout(() => {
                    // 清空现有节点
                    nodes = [];

                    // 解析配置并构建节点
                    parseAndBuildNodes(config);

                    // 渲染节点
                    renderNodes();

                    // 更新编辑器内容（可选）
                    if (nodeEditor) {
                        nodeEditor.setValue(JSON.stringify(config, null, 2));
                    }

                    alert(`配置 "${currentConfigFile}" 已成功导入到节点模式\n\n已创建以下节点：\n` +
                          nodes.map(n => `• ${n.id}: ${n.name}`).join('\n') +
                          `\n\n提示：\n1. 可以拖动节点调整位置\n2. 确保API密钥已设置\n3. 点击RUN FLOW执行生成`);
                }, 200);
            } catch (e) {
                alert('导入失败: ' + e.message);
            }
        }

        // 删除当前配置
        async function deleteCurrentConfig() {
            if (!currentConfigFile) {
                alert('请先选择一个配置文件');
                return;
            }

            if (!confirm(`确定要删除 ${currentConfigFile} 吗？`)) {
                return;
            }

            try {
                const response = await fetch(`http://127.0.0.1:8004/api/config/${encodeFilename(currentConfigFile)}`, {
                    method: 'DELETE'
                });

                if (!response.ok) {
                    throw new Error('删除失败');
                }

                alert('配置已删除: ' + currentConfigFile);
                currentConfigFile = null;
                const nameInput = document.getElementById('current-config-name');
                const importBtn = document.getElementById('import-to-nodes-btn');
                nameInput.value = '';
                nameInput.style.display = 'none';
                importBtn.style.display = 'none';
                configEditor.setValue('');
                loadConfigFileList();
            } catch (e) {
                alert('删除失败: ' + e.message);
            }
        }

        // 加载配置到工作空间
        function loadConfigToWorkspace() {
            if (!currentConfigFile) {
                alert('请先选择一个配置文件');
                return;
            }

            try {
                const content = configEditor.getValue();
                const config = JSON.parse(content);
                openImportModal();
                jsonEditor.setValue(JSON.stringify(config, null, 2));
                // 刷新编辑器以确保正确显示
                setTimeout(() => {
                    if (jsonEditor) jsonEditor.refresh();
                }, 10);
            } catch (e) {
                alert('JSON 格式错误: ' + e.message);
            }
        }

        // 检查任务状态（用于轮询）
        async function checkTaskStatus(requestId) {
            if (!requestId) return;

            try {
                // 确保API密钥格式正确（添加Bearer前缀）
                const authKey = apiKey.startsWith('Bearer ') ? apiKey : `Bearer ${apiKey}`;

                const res = await fetch(`https://api.bizyair.cn/w/v1/webapp/task/${requestId}/status`, {
                    headers: {
                        'Authorization': authKey
                    }
                });

                if (!res.ok) {
                    console.error('Failed to check task status');
                    return;
                }

                const status = await res.json();
                console.log('Task Status:', status);

                const previewBox = document.getElementById('node-output-preview');
                if (status.status === 'Success' && status.outputs && status.outputs.length > 0) {
                    // 任务完成，显示所有结果
                    let outputUrls = [];
                    status.outputs.forEach(output => {
                        if(output.object_url) {
                            outputUrls.push(output.object_url);
                        }
                    });

                    // 构建所有媒体的HTML
                    let mediaHtml = `<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 10px; width: 100%;">`;

                    outputUrls.forEach((url, index) => {
                        const isVideo = url.endsWith('.mp4') || url.endsWith('.webm');
                        const media = isVideo
                            ? `<video src="${url}" autoplay loop muted controls style="width: 100%; height: auto; max-height: 300px; object-fit: contain;"></video>`
                            : `<img src="${url}" style="width: 100%; height: auto; max-height: 300px; object-fit: contain; cursor: pointer;" onclick="showLightbox('${url}')" alt="Output ${index + 1}">`;

                        mediaHtml += `<div style="position: relative;">
                            ${media}
                            <div style="position: absolute; bottom: 5px; right: 5px; background: rgba(0,0,0,0.6); color: white; padding: 2px 5px; font-size: 10px; border-radius: 3px;">
                                ${isVideo ? 'Video' : 'Image'} ${index + 1}
                            </div>
                        </div>`;
                    });

                    mediaHtml += `</div>`;

                    if(previewBox) {
                        previewBox.innerHTML = `<span class="node-timer" style="display:block">${document.getElementById('canvas-timer').innerText}</span>` + mediaHtml;
                    }

                    // 保存所有输出到历史记录
                    outputUrls.forEach(url => saveToHistory(url));

                    // 如果只有一个输出，显示lightbox
                    if(outputUrls.length === 1) {
                        showLightbox(outputUrls[0]);
                    }

                    stopRequestTimer();
                    document.querySelectorAll('.action-btn').forEach(b => b.disabled = false);
                } else if (status.status === 'Running' || status.status === 'Pending') {
                    // 继续等待
                    if(previewBox) {
                        previewBox.innerHTML = `<span style="color:orange">Task is running...</span><br><small>Elapsed: ${document.getElementById('canvas-timer').innerText}</small>`;
                    }
                    setTimeout(() => checkTaskStatus(requestId), 3000);
                } else {
                    // 任务失败
                    throw new Error(`Task failed: ${status.status}`);
                }
            } catch (e) {
                console.error('Error checking task status:', e);
                const previewBox = document.getElementById('node-output-preview');
                if(previewBox) {
                    previewBox.innerHTML = `<span style="color:red">Task failed</span>`;
                }
                stopRequestTimer();
                document.querySelectorAll('.action-btn').forEach(b => b.disabled = false);
            }
        }
    </script>
  <!-- CodeMirror JS -->
    <script src="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.2/codemirror.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.2/mode/javascript/javascript.min.js"></script>
</body>
</html>