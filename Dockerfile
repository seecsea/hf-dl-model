FROM python:3.12.12-slim-trixie

# 设置环境变量避免交互式安装
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# 安装必要的系统依赖
RUN apt-get update && apt-get install -y \
    git \
    git-lfs \
    curl \
    wget \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 升级 pip 并安装 Python 依赖
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir \
    huggingface_hub \
    requests \
    tqdm

# 设置工作目录
WORKDIR /models

# 设置环境变量（从构建参数获取）
ARG HF_TOKEN
ARG MODEL_NAME
ARG HF_ENDPOINT=https://hf-mirror.com

ENV HUGGINGFACE_HUB_TOKEN=${HF_TOKEN}
ENV HF_ENDPOINT=${HF_ENDPOINT}

# 创建模型目录
RUN mkdir -p /models

# 下载模型脚本
RUN cat > /download_model.py << 'EOF'
import os
import sys
from huggingface_hub import snapshot_download
from pathlib import Path

def download_model():
    model_name = os.environ.get('MODEL_NAME')
    token = os.environ.get('HUGGINGFACE_HUB_TOKEN')
    
    if not model_name:
        print("Error: MODEL_NAME environment variable not set")
        sys.exit(1)
    
    # 提取模型名称的最后部分作为目录名
    model_dir_name = model_name.split('/')[-1]
    local_dir = f"/models/{model_dir_name}"
    
    print(f"Downloading model: {model_name}")
    print(f"Target directory: {local_dir}")
    print(f"Using token: {'Yes' if token else 'No'}")
    
    try:
        snapshot_download(
            repo_id=model_name,
            local_dir=local_dir,
            local_dir_use_symlinks=False,
            token=token,
            resume_download=True
        )
        print(f"Successfully downloaded {model_name} to {local_dir}")
        
        # 显示下载的文件
        print("\nDownloaded files:")
        for root, dirs, files in os.walk(local_dir):
            level = root.replace(local_dir, '').count(os.sep)
            indent = ' ' * 2 * level
            print(f"{indent}{os.path.basename(root)}/")
            subindent = ' ' * 2 * (level + 1)
            for file in files:
                file_path = os.path.join(root, file)
                file_size = os.path.getsize(file_path)
                size_mb = file_size / (1024 * 1024)
                print(f"{subindent}{file} ({size_mb:.1f}MB)")
                
    except Exception as e:
        print(f"Error downloading model: {e}")
        sys.exit(1)

if __name__ == "__main__":
    download_model()
EOF

# 下载模型
RUN python /download_model.py

# 创建模型信息脚本
RUN cat > /model_info.py << 'EOF'
import os
import json
from pathlib import Path

def show_model_info():
    models_dir = Path("/models")
    
    print("=" * 60)
    print("🤖 MODEL STORAGE CONTAINER")
    print("=" * 60)
    
    if not models_dir.exists():
        print("❌ No models directory found")
        return
    
    model_dirs = [d for d in models_dir.iterdir() if d.is_dir()]
    
    if not model_dirs:
        print("❌ No models found")
        return
    
    for model_dir in model_dirs:
        print(f"\n📦 Model: {model_dir.name}")
        print("-" * 40)
        
        # 显示配置文件信息
        config_file = model_dir / "config.json"
        if config_file.exists():
            try:
                with open(config_file, 'r', encoding='utf-8') as f:
                    config = json.load(f)
                print(f"🏗️  Architecture: {config.get('architectures', ['Unknown'])[0]}")
                print(f"🔤 Model Type: {config.get('model_type', 'Unknown')}")
                if 'hidden_size' in config:
                    print(f"📏 Hidden Size: {config['hidden_size']}")
                if 'num_hidden_layers' in config:
                    print(f"🔢 Layers: {config['num_hidden_layers']}")
            except:
                print("⚠️  Could not read config.json")
        
        # 显示文件列表和大小
        total_size = 0
        file_count = 0
        
        print(f"\n📁 Files in {model_dir.name}:")
        for file_path in sorted(model_dir.rglob("*")):
            if file_path.is_file():
                file_size = file_path.stat().st_size
                total_size += file_size
                file_count += 1
                
                size_mb = file_size / (1024 * 1024)
                relative_path = file_path.relative_to(model_dir)
                
                if size_mb > 1:
                    print(f"  📄 {relative_path} ({size_mb:.1f}MB)")
                else:
                    size_kb = file_size / 1024
                    print(f"  📄 {relative_path} ({size_kb:.1f}KB)")
        
        total_gb = total_size / (1024 * 1024 * 1024)
        print(f"\n📊 Summary:")
        print(f"  • Total files: {file_count}")
        print(f"  • Total size: {total_gb:.2f}GB")
    
    print("\n" + "=" * 60)
    print("💡 Usage:")
    print("docker cp <container_name>:/models ./local-models")
    print("=" * 60)

if __name__ == "__main__":
    show_model_info()
EOF

# 创建简单的列表脚本
RUN cat > /list_models.sh << 'EOF'
#!/bin/bash
echo "📂 Models directory contents:"
ls -la /models/
echo ""
python /model_info.py
EOF

RUN chmod +x /list_models.sh

# 设置默认命令
CMD ["/list_models.sh"]

# 添加健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ls /models && echo "Models available" || exit 1

# 添加标签信息
LABEL maintainer="your-email@example.com"
LABEL description="HuggingFace model storage container"
LABEL version="1.0"
