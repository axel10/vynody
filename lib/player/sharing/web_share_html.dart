const String webShareHtmlContent = r'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>VibeFlow Web Share</title>
  <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;800&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg-color: #0b0813;
      --glass-bg: rgba(255, 255, 255, 0.03);
      --glass-border: rgba(255, 255, 255, 0.07);
      --primary-color: #9d4edd;
      --secondary-color: #3a86c8;
      --glow-color: rgba(157, 78, 221, 0.3);
      --text-color: #f3f0f7;
      --text-muted: #a09cb0;
    }
    
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }
    
    body {
      font-family: 'Outfit', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background-color: var(--bg-color);
      color: var(--text-color);
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 20px;
      overflow-x: hidden;
      position: relative;
    }

    /* Ambient Background Glows */
    body::before {
      content: '';
      position: absolute;
      width: 400px;
      height: 400px;
      background: radial-gradient(circle, var(--glow-color) 0%, transparent 70%);
      top: 10%;
      left: 10%;
      z-index: -1;
      filter: blur(40px);
    }
    body::after {
      content: '';
      position: absolute;
      width: 500px;
      height: 500px;
      background: radial-gradient(circle, rgba(58, 134, 200, 0.2) 0%, transparent 70%);
      bottom: 10%;
      right: 10%;
      z-index: -1;
      filter: blur(50px);
    }

    .container {
      width: 100%;
      max-width: 600px;
      background: var(--glass-bg);
      border: 1px solid var(--glass-border);
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      border-radius: 24px;
      padding: 30px;
      box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4);
      display: flex;
      flex-direction: column;
      gap: 24px;
    }

    header {
      text-align: center;
    }

    h1 {
      font-size: 2.2rem;
      font-weight: 800;
      background: linear-gradient(135deg, #fff 30%, #a09cb0 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      margin-bottom: 6px;
      letter-spacing: -0.5px;
    }

    .subtitle {
      color: var(--text-muted);
      font-size: 0.95rem;
      font-weight: 300;
    }

    .tab-container {
      display: flex;
      border-bottom: 1px solid var(--glass-border);
      margin-bottom: 8px;
    }

    .tab-btn {
      flex: 1;
      padding: 12px;
      background: transparent;
      border: none;
      color: var(--text-muted);
      font-family: inherit;
      font-size: 1rem;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.3s ease;
      position: relative;
    }

    .tab-btn.active {
      color: var(--text-color);
    }

    .tab-btn.active::after {
      content: '';
      position: absolute;
      bottom: -1px;
      left: 0;
      width: 100%;
      height: 2px;
      background: linear-gradient(90deg, var(--primary-color), var(--secondary-color));
      box-shadow: 0 0 10px var(--glow-color);
    }

    .tab-content {
      display: none;
    }

    .tab-content.active {
      display: block;
    }

    /* Upload Area Stylings */
    .dropzone {
      border: 2px dashed var(--glass-border);
      border-radius: 16px;
      padding: 40px 20px;
      text-align: center;
      cursor: pointer;
      transition: all 0.3s ease;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 16px;
    }

    .dropzone:hover, .dropzone.dragover {
      border-color: var(--primary-color);
      background: rgba(157, 78, 221, 0.02);
      box-shadow: 0 0 20px rgba(157, 78, 221, 0.1);
    }

    .dropzone svg {
      width: 48px;
      height: 48px;
      fill: none;
      stroke: var(--text-muted);
      stroke-width: 1.5;
      transition: all 0.3s ease;
    }

    .dropzone:hover svg, .dropzone.dragover svg {
      stroke: var(--primary-color);
      transform: translateY(-4px);
    }

    .dropzone p {
      font-size: 0.95rem;
      color: var(--text-muted);
    }

    .dropzone span {
      color: var(--text-color);
      font-weight: 600;
    }

    #fileInput {
      display: none;
    }

    /* Queue & File List Item */
    .file-list {
      display: flex;
      flex-direction: column;
      gap: 12px;
      margin-top: 16px;
      max-height: 250px;
      overflow-y: auto;
      padding-right: 4px;
    }

    /* Custom Scrollbar */
    .file-list::-webkit-scrollbar {
      width: 6px;
    }
    .file-list::-webkit-scrollbar-track {
      background: transparent;
    }
    .file-list::-webkit-scrollbar-thumb {
      background: var(--glass-border);
      border-radius: 4px;
    }

    .file-item {
      background: rgba(255, 255, 255, 0.02);
      border: 1px solid var(--glass-border);
      border-radius: 12px;
      padding: 12px 16px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      animation: slideIn 0.3s ease forwards;
    }

    @keyframes slideIn {
      from { opacity: 0; transform: translateY(10px); }
      to { opacity: 1; transform: translateY(0); }
    }

    .file-info {
      flex: 1;
      overflow: hidden;
    }

    .file-name {
      font-weight: 600;
      font-size: 0.9rem;
      white-space: nowrap;
      text-overflow: ellipsis;
      overflow: hidden;
    }

    .file-size {
      font-size: 0.8rem;
      color: var(--text-muted);
      margin-top: 2px;
    }

    .progress-bar-container {
      width: 100%;
      height: 4px;
      background: rgba(255, 255, 255, 0.05);
      border-radius: 2px;
      margin-top: 6px;
      overflow: hidden;
    }

    .progress-fill {
      height: 100%;
      width: 0%;
      background: linear-gradient(90deg, var(--primary-color), var(--secondary-color));
      border-radius: 2px;
      transition: width 0.1s linear;
    }

    .file-status {
      font-size: 0.8rem;
      font-weight: 600;
    }

    .status-pending { color: var(--text-muted); }
    .status-uploading { color: var(--secondary-color); }
    .status-success { color: #52b788; }
    .status-failed { color: #e63946; }

    /* Download Tab Styles */
    .download-list {
      display: flex;
      flex-direction: column;
      gap: 12px;
      max-height: 400px;
      overflow-y: auto;
    }

    .download-item {
      background: rgba(255, 255, 255, 0.02);
      border: 1px solid var(--glass-border);
      border-radius: 14px;
      padding: 14px 18px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
    }

    .song-details {
      display: flex;
      align-items: center;
      gap: 12px;
      flex: 1;
      overflow: hidden;
    }

    .music-icon {
      width: 40px;
      height: 40px;
      background: rgba(157, 78, 221, 0.1);
      border-radius: 10px;
      display: flex;
      align-items: center;
      justify-content: center;
      color: var(--primary-color);
      flex-shrink: 0;
    }

    .song-info {
      overflow: hidden;
    }

    .song-title {
      font-weight: 600;
      font-size: 0.95rem;
      white-space: nowrap;
      text-overflow: ellipsis;
      overflow: hidden;
    }

    .song-artist {
      font-size: 0.8rem;
      color: var(--text-muted);
      margin-top: 2px;
      white-space: nowrap;
      text-overflow: ellipsis;
      overflow: hidden;
    }

    .download-btn {
      background: linear-gradient(135deg, var(--primary-color), var(--secondary-color));
      border: none;
      color: white;
      padding: 8px 16px;
      border-radius: 8px;
      font-family: inherit;
      font-size: 0.85rem;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s ease;
      box-shadow: 0 4px 10px rgba(157, 78, 221, 0.2);
      text-decoration: none;
      display: inline-flex;
      align-items: center;
      justify-content: center;
    }

    .download-btn:hover {
      transform: translateY(-2px);
      box-shadow: 0 6px 15px rgba(157, 78, 221, 0.35);
    }

    .empty-state {
      text-align: center;
      padding: 40px 20px;
      color: var(--text-muted);
      font-size: 0.95rem;
    }

    footer {
      margin-top: 20px;
      font-size: 0.8rem;
      color: var(--text-muted);
      text-align: center;
    }

    footer a {
      color: var(--primary-color);
      text-decoration: none;
    }
  </style>
</head>
<body>

  <div class="container">
    <header>
      <h1>VibeFlow Web Share</h1>
      <p class="subtitle">局域网音乐互传平台</p>
    </header>

    <div class="tab-container">
      <button class="tab-btn active" onclick="switchTab('upload')">上传到应用</button>
      <button class="tab-btn" onclick="switchTab('download')">下载音乐</button>
    </div>

    <!-- Upload Tab -->
    <div id="uploadTab" class="tab-content active">
      <div class="dropzone" id="dropzone" onclick="document.getElementById('fileInput').click()">
        <svg viewBox="0 0 24 24">
          <path d="M12 16V8M12 8L9 11M12 8L15 11" stroke-linecap="round" stroke-linejoin="round"/>
          <path d="M3 15v3a3 3 0 0 0 3 3h12a3 3 0 0 0 3-3v-3M3 9V6a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3v3" stroke-linecap="round"/>
        </svg>
        <p>拖拽音乐文件至此，或 <span>点击选择文件</span></p>
        <p style="font-size: 0.8rem; opacity: 0.7;">支持 MP3, FLAC, M4A, WAV 等格式</p>
        <input type="file" id="fileInput" multiple accept="audio/*">
      </div>

      <div class="file-list" id="fileList">
        <!-- Dynamic list of file uploads -->
      </div>
    </div>

    <!-- Download Tab -->
    <div id="downloadTab" class="tab-content">
      <div class="download-list" id="downloadList">
        <div class="empty-state">正在加载音乐列表...</div>
      </div>
    </div>
  </div>

  <footer>
    <p>Powerd by VibeFlow &copy; 2026</p>
  </footer>

  <script>
    const dropzone = document.getElementById('dropzone');
    const fileInput = document.getElementById('fileInput');
    const fileList = document.getElementById('fileList');
    const downloadList = document.getElementById('downloadList');
    
    // Switch tabs
    function switchTab(tabId) {
      document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
      document.querySelectorAll('.tab-content').forEach(content => content.classList.remove('active'));
      
      if (tabId === 'upload') {
        document.querySelector('.tab-btn:nth-child(1)').classList.add('active');
        document.getElementById('uploadTab').classList.add('active');
      } else {
        document.querySelector('.tab-btn:nth-child(2)').classList.add('active');
        document.getElementById('downloadTab').classList.add('active');
        loadSongs();
      }
    }

    // Dropzone Events
    ['dragenter', 'dragover'].forEach(eventName => {
      dropzone.addEventListener(eventName, (e) => {
        e.preventDefault();
        dropzone.classList.add('dragover');
      }, false);
    });

    ['dragleave', 'drop'].forEach(eventName => {
      dropzone.addEventListener(eventName, (e) => {
        e.preventDefault();
        dropzone.classList.remove('dragover');
      }, false);
    });

    dropzone.addEventListener('drop', (e) => {
      const dt = e.dataTransfer;
      const files = dt.files;
      handleFiles(files);
    }, false);

    fileInput.addEventListener('change', () => {
      handleFiles(fileInput.files);
    });

    function formatBytes(bytes, decimals = 2) {
      if (bytes === 0) return '0 Bytes';
      const k = 1024;
      const dm = decimals < 0 ? 0 : decimals;
      const sizes = ['Bytes', 'KB', 'MB', 'GB'];
      const i = Math.floor(Math.log(bytes) / Math.log(k));
      return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
    }

    // Handle uploaded files
    function handleFiles(files) {
      for (let i = 0; i < files.length; i++) {
        uploadFile(files[i]);
      }
    }

    function uploadFile(file) {
      const fileId = 'file_' + Math.random().toString(36).substr(2, 9);
      
      // Create DOM elements
      const fileItem = document.createElement('div');
      fileItem.className = 'file-item';
      fileItem.id = fileId;
      fileItem.innerHTML = `
        <div class="file-info">
          <div class="file-name">${file.name}</div>
          <div class="file-size">${formatBytes(file.size)}</div>
          <div class="progress-bar-container">
            <div class="progress-fill" id="progress_${fileId}"></div>
          </div>
        </div>
        <div class="file-status status-pending" id="status_${fileId}">准备中</div>
      `;
      fileList.insertBefore(fileItem, fileList.firstChild);

      const statusEl = document.getElementById(`status_${fileId}`);
      const progressEl = document.getElementById(`progress_${fileId}`);

      // First call API to request transfer
      fetch('/api/transfer/request', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sender_id: 'web_browser',
          sender_name: 'Web Browser',
          files: [{ name: file.name, size: file.size, duration_ms: 0 }]
        })
      })
      .then(res => res.json())
      .then(data => {
        if (data.accepted) {
          statusEl.innerText = '传输中';
          statusEl.className = 'file-status status-uploading';
          
          // Perform upload
          const xhr = new XMLHttpRequest();
          xhr.open('POST', '/api/transfer/upload');
          xhr.setRequestHeader('Authorization', `Bearer ${data.token}`);
          xhr.setRequestHeader('X-File-Name', encodeURIComponent(file.name));
          xhr.setRequestHeader('Content-Type', 'application/octet-stream');

          xhr.upload.addEventListener('progress', (e) => {
            if (e.lengthComputable) {
              const percentage = Math.round((e.loaded / e.total) * 100);
              progressEl.style.width = percentage + '%';
              statusEl.innerText = '已上传 ' + percentage + '%';
            }
          });

          xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
              if (xhr.status === 200) {
                statusEl.innerText = '成功';
                statusEl.className = 'file-status status-success';
              } else {
                statusEl.innerText = '失败';
                statusEl.className = 'file-status status-failed';
              }
            }
          };

          xhr.onerror = function() {
            statusEl.innerText = '出错';
            statusEl.className = 'file-status status-failed';
          };

          // Send file as raw binary stream
          xhr.send(file);
        } else {
          statusEl.innerText = '拒绝: ' + (data.reason || '用户拒收');
          statusEl.className = 'file-status status-failed';
        }
      })
      .catch(err => {
        console.error(err);
        statusEl.innerText = '拒绝或错误';
        statusEl.className = 'file-status status-failed';
      });
    }

    // Load songs list for download
    function loadSongs() {
      downloadList.innerHTML = '<div class="empty-state">正在拉取歌曲列表...</div>';
      
      fetch('/api/songs')
        .then(res => res.json())
        .then(songs => {
          if (!songs || songs.length === 0) {
            downloadList.innerHTML = '<div class="empty-state">VibeFlow 暂无共享的音乐</div>';
            return;
          }

          downloadList.innerHTML = '';
          songs.forEach(song => {
            const item = document.createElement('div');
            item.className = 'download-item';
            
            const artist = song.artist || '未知艺术家';
            const title = song.title || song.name || '未知曲目';
            
            item.innerHTML = `
              <div class="song-details">
                <div class="music-icon">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M9 18V5l12-2v13"></path>
                    <circle cx="6" cy="18" r="3"></circle>
                    <circle cx="18" cy="16" r="3"></circle>
                  </svg>
                </div>
                <div class="song-info">
                  <div class="song-title">${title}</div>
                  <div class="song-artist">${artist}</div>
                </div>
              </div>
              <a class="download-btn" href="/api/download?id=${encodeURIComponent(song.path)}" download="${encodeURIComponent(song.name)}">
                下载
              </a>
            `;
            downloadList.appendChild(item);
          });
        })
        .catch(err => {
          console.error(err);
          downloadList.innerHTML = '<div class="empty-state">加载失败，请确保应用共享处于开启状态</div>';
        });
    }
  </script>
</body>
</html>
''';
