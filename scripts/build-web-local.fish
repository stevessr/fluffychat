#!/usr/bin/env fish
# Flutter Web 本地构建和测试脚本

# 设置颜色输出
set -g GREEN '\033[0;32m'
set -g YELLOW '\033[1;33m'
set -g RED '\033[0;31m'
set -g NC '\033[0m' # No Color

function print_step
    echo -e "$GREEN==> $argv[1]$NC"
end

function print_warning
    echo -e "$YELLOW⚠️  $argv[1]$NC"
end

function print_error
    echo -e "$RED❌ $argv[1]$NC"
end

# 检查 Flutter 是否安装
if not command -v flutter >/dev/null
    print_error "Flutter not found. Please install Flutter first."
    exit 1
end

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
if test -f ./scripts/prepare-web.sh
    chmod +x ./scripts/prepare-web.sh
    ./scripts/prepare-web.sh
    or begin
        print_warning "prepare-web.sh failed, continuing anyway..."
    end
else
    print_warning "prepare-web.sh not found, skipping..."
end

# 移除 vodozemac .gitignore
if test -f ./assets/vodozemac/.gitignore
    rm -f ./assets/vodozemac/.gitignore
    print_step "Removed vodozemac .gitignore"
end

# 分析代码
print_step "Analyzing code..."
flutter analyze --no-fatal-infos
or print_warning "Code analysis found issues, but continuing..."

# 运行测试（可选）
if test "$argv[1]" = "--with-tests"
    print_step "Running tests..."
    flutter test
    or print_warning "Some tests failed, but continuing..."
end

# 构建 Web
print_step "Building Flutter Web..."
flutter build web \
    --release \
    --web-renderer canvaskit \
    --dart-define=FLUTTER_WEB_CANVASKIT_URL=canvaskit/ \
    --source-maps \
    --no-wasm-dry-run \
    --base-href="/"

if test $status -eq 0
    print_step "Build successful! 🎉"
    
    # 显示构建信息
    echo ""
    print_step "Build Information:"
    echo "  📁 Output directory: build/web/"
    echo "  📦 Build size:"
    du -sh build/web/
    
    # 询问是否启动本地服务器
    echo ""
    read -P "Start local server? (y/n): " -n 1 answer
    echo ""
    
    if test "$answer" = "y" -o "$answer" = "Y"
        print_step "Starting local server on http://localhost:8000"
        print_warning "Press Ctrl+C to stop the server"
        cd build/web
        python3 -m http.server 8000
        or python -m http.server 8000
    end
else
    print_error "Build failed!"
    exit 1
end
