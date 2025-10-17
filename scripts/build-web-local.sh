#!/bin/bash
# Flutter Web 本地构建和测试脚本（Bash 版本）

# 设置颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${GREEN}==> $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 检查 Flutter 是否安装
if ! command -v flutter &> /dev/null; then
    print_error "Flutter not found. Please install Flutter first."
    exit 1
fi

print_step "Checking Flutter version..."
flutter --version

# 清理之前的构建
print_step "Cleaning previous builds..."
flutter clean

# 获取依赖
print_step "Getting Flutter dependencies..."
flutter pub get

# 准备 Web 资源（vodozemac）
print_step "Preparing Web resources (vodozemac)..."
if [ -f "./scripts/prepare-web.sh" ]; then
    chmod +x ./scripts/prepare-web.sh
    ./scripts/prepare-web.sh || print_warning "prepare-web.sh failed, continuing anyway..."
else
    print_warning "prepare-web.sh not found, skipping..."
fi

# 移除 vodozemac .gitignore
if [ -f "./assets/vodozemac/.gitignore" ]; then
    rm -f ./assets/vodozemac/.gitignore
    print_step "Removed vodozemac .gitignore"
fi

# 分析代码
print_step "Analyzing code..."
flutter analyze --no-fatal-infos || print_warning "Code analysis found issues, but continuing..."

# 运行测试（可选）
if [ "$1" == "--with-tests" ]; then
    print_step "Running tests..."
    flutter test || print_warning "Some tests failed, but continuing..."
fi

# 构建 Web
print_step "Building Flutter Web..."
flutter build web \
    --release \
    --web-renderer canvaskit \
    --dart-define=FLUTTER_WEB_CANVASKIT_URL=canvaskit/ \
    --source-maps \
    --no-wasm-dry-run \
    --base-href="/"

if [ $? -eq 0 ]; then
    print_step "Build successful! 🎉"
    
    # 显示构建信息
    echo ""
    print_step "Build Information:"
    echo "  📁 Output directory: build/web/"
    echo "  📦 Build size:"
    du -sh build/web/
    
    # 询问是否启动本地服务器
    echo ""
    read -p "Start local server? (y/n): " -n 1 answer
    echo ""
    
    if [[ $answer =~ ^[Yy]$ ]]; then
        print_step "Starting local server on http://localhost:8000"
        print_warning "Press Ctrl+C to stop the server"
        cd build/web
        python3 -m http.server 8000 || python -m http.server 8000
    fi
else
    print_error "Build failed!"
    exit 1
fi
