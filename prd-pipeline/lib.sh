# ============================================================
# lib.sh — 共享函数库（色彩输出、通用工具、项目配置）
# 被其他脚本 source 使用，兼容 bash 3.2
# ============================================================

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; CYAN='\033[36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { printf "${CYAN}[INFO]${NC}  %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
err()   { printf "${RED}[ERROR]${NC} %s\n" "$*"; }
bold()  { printf "${BOLD}%s${NC}\n" "$*"; }

# ─── 项目配置：在 source 此文件后调用 init_project_config ───
# 通过以下环境变量控制（由 prd_pipeline.sh 或外层传递）:
#   TARGET_DIR    — 目标代码目录路径（设置后启用 project 模式）
#   PROJECT_NAME  — 项目名（可选，默认从 TARGET_DIR basename 推导）
#
# 设置后输出以下变量（未设置 TARGET_DIR 时所有变量为空）:
#   PROJECT_DIR, SPEC_DIR, ISSUES_DIR, TASKS_DIR, EXEC_DIR

PROJECT_BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/projects"

init_project_config() {
    TARGET_DIR="${TARGET_DIR:-}"
    PROJECT_NAME="${PROJECT_NAME:-}"
    PROJECT_DIR=""; SPEC_DIR=""; ISSUES_DIR=""; TASKS_DIR=""; EXEC_DIR=""
    [ -z "$TARGET_DIR" ] && return 0

    # 确定项目名
    [ -z "$PROJECT_NAME" ] && PROJECT_NAME="$(basename "$TARGET_DIR")"

    PROJECT_DIR="$PROJECT_BASE/$PROJECT_NAME"
    SPEC_DIR="$PROJECT_DIR/01-spec"
    ISSUES_DIR="$PROJECT_DIR/02-issues"
    TASKS_DIR="$PROJECT_DIR/03-tasks"
    EXEC_DIR="$PROJECT_DIR/04-execution"

    mkdir -p "$SPEC_DIR" "$ISSUES_DIR" "$TASKS_DIR" "$EXEC_DIR" "$EXEC_DIR/logs"
}

# ─── 技术栈检测 ───
# 探测 TARGET_DIR 中常见技术栈标识文件，返回可读字符串
detect_tech_stack() {
    [ -z "$TARGET_DIR" ] && return 0
    local s=""
    [ -f "$TARGET_DIR/package.json" ] && s="${s}Node.js "
    [ -f "$TARGET_DIR/requirements.txt" ] || [ -f "$TARGET_DIR/setup.py" ] || [ -f "$TARGET_DIR/Pipfile" ] && s="${s}Python "
    [ -f "$TARGET_DIR/Cargo.toml" ] && s="${s}Rust "
    [ -f "$TARGET_DIR/Gemfile" ] && s="${s}Ruby "
    [ -f "$TARGET_DIR/go.mod" ] && s="${s}Go "
    [ -f "$TARGET_DIR/pom.xml" ] || [ -f "$TARGET_DIR/build.gradle" ] && s="${s}Java "
    [ -f "$TARGET_DIR/composer.json" ] && s="${s}PHP "
    [ -f "$TARGET_DIR/Makefile" ] && s="${s}Makefile "
    [ -f "$TARGET_DIR/Dockerfile" ] && s="${s}Docker "
    [ -z "$s" ] && s="未检测到"
    echo "$s" | sed 's/ $//'
}
