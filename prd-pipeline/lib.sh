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

# ─── 技术栈检测 + 默认推荐 ───
# 已有项目：检测实际使用的技术栈
# 新项目：推荐经 AI 编程验证的最优组合
# 检测优先级：实际项目文件 > 技术栈规范说明.md > 默认推荐
detect_tech_stack() {
    [ -z "$TARGET_DIR" ] && return 0
    local s=""

    # 优先检测已有项目
    [ -f "$TARGET_DIR/package.json" ] && s="${s}Node.js "
    [ -f "$TARGET_DIR/requirements.txt" ] || [ -f "$TARGET_DIR/setup.py" ] || [ -f "$TARGET_DIR/Pipfile" ] && s="${s}Python "
    [ -f "$TARGET_DIR/Cargo.toml" ] && s="${s}Rust "
    [ -f "$TARGET_DIR/Gemfile" ] && s="${s}Ruby "
    [ -f "$TARGET_DIR/go.mod" ] && s="${s}Go "
    [ -f "$TARGET_DIR/pom.xml" ] || [ -f "$TARGET_DIR/build.gradle" ] && s="${s}Java "
    [ -f "$TARGET_DIR/composer.json" ] && s="${s}PHP "
    [ -f "$TARGET_DIR/Makefile" ] && s="${s}Makefile "
    [ -f "$TARGET_DIR/Dockerfile" ] && s="${s}Docker "

    # 检测到项目文件 → 返回实际检测结果
    [ -n "$s" ] && { echo "$s" | sed 's/ $//'; return; }

    # 新项目：检查是否有技术栈规范文件
    local spec_file=""
    for _f in "$TARGET_DIR/技术栈规范说明.md" "$TARGET_DIR/../技术栈规范说明.md" "$(dirname "$TARGET_DIR" 2>/dev/null)/技术栈规范说明.md"; do
        [ -f "$_f" ] && { spec_file="$_f"; break; }
    done

    if [ -n "$spec_file" ]; then
        # 从规范文件提取关键信息
        local frontend="$(grep -E '^\|.*前端.*\|' "$spec_file" 2>/dev/null | head -3 | tr '\n' ' ' | sed 's/  / /g')"
        local backend="$(grep -E '^\|.*后端.*\|' "$spec_file" 2>/dev/null | head -3 | tr '\n' ' ' | sed 's/  / /g')"
        [ -n "$frontend" ] && s="${s}前端规范 "
        [ -n "$backend" ] && s="${s}后端规范 "
        [ -z "$s" ] && s="技术栈规范已定义 "
        echo "${s}(详情见 $(basename "$spec_file"))" | sed 's/ $//'
        return
    fi

    # 无项目文件也无规范文件 → AI 编程最优默认推荐
    echo "推荐: TypeScript + React(Vite) + Tailwind CSS + Go(Gin) + PostgreSQL"
    echo "详情: 创建 技术栈规范说明.md 自定义，或直接在 prompt 中指定"
}

# ─── 设计系统检测 ───
# 读取 DESIGN.md，返回设计 Token 摘要
detect_design_system() {
    [ -z "$TARGET_DIR" ] && return 0
    local ds_file=""
    for _f in "$TARGET_DIR/DESIGN.md" "$TARGET_DIR/../DESIGN.md"; do
        [ -f "$_f" ] && { ds_file="$_f"; break; }
    done
    [ -z "$ds_file" ] && return 0

    local primary="$(grep -i 'primary.*#' "$ds_file" 2>/dev/null | head -1 | sed 's/.*#/#/' | sed 's/[" ,].*//')"
    local font="$(grep -i 'font.*family\|heading.*font' "$ds_file" 2>/dev/null | head -1 | sed 's/.*: *"//;s/".*//')"
    local radius="$(grep -i 'borderRadius\|border-radius' "$ds_file" 2>/dev/null | head -1 | sed 's/.*: *//;s/px.*//')"

    echo "设计系统: $(basename "$ds_file")"
    [ -n "$primary" ] && echo "主色: ${primary}"
    [ -n "$font" ] && echo "字体: ${font}"
    [ -n "$radius" ] && echo "圆角: ${radius}px"
}

# ─── Agent 配置加载 ───
# 读取项目根目录的 .agentrc 文件（如果存在）
# 格式: KEY=VALUE，支持注释 # 和空行
# 用于统一管理 AGENT_TYPE、AGENT_CMD、AGENT_CONFIG 等
load_agentrc() {
    local search_dir="${1:-$(pwd)}"
    local rc_file="$search_dir/.agentrc"
    [ ! -f "$rc_file" ] && return 0
    info "加载 Agent 配置: $rc_file"
    while IFS='=' read -r key val; do
        # 跳过空行和注释
        [ -z "$key" ] && continue
        echo "$key" | grep -q '^[[:space:]]*#' && continue
        # 去掉首尾空白和引号
        key="$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        val="$(echo "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')"
        [ -z "$key" ] && continue
        # 跳过非 Agent 配置项
        echo "$key" | grep -qE '^(AGENT_TYPE|AGENT_CMD|AGENT_CONFIG)$' || continue
        export "$key=$val"
    done < "$rc_file"
}

# ─── 测试框架检测 ───
# 返回: 测试命令字符串，或空字符串（未检测到）
detect_test_command() {
    [ -z "$TARGET_DIR" ] && return 0
    if [ -f "$TARGET_DIR/pyproject.toml" ] || [ -f "$TARGET_DIR/setup.py" ] || [ -f "$TARGET_DIR/requirements.txt" ]; then
        if [ -f "$TARGET_DIR/pyproject.toml" ] && grep -q '\[tool.pytest' "$TARGET_DIR/pyproject.toml" 2>/dev/null; then
            echo "cd '$TARGET_DIR' && python -m pytest -x --tb=short 2>&1 || true"
            return
        fi
        echo "cd '$TARGET_DIR' && python -m pytest -x --tb=short 2>&1 || true"
        return
    fi
    if [ -f "$TARGET_DIR/package.json" ]; then
        if grep -q '"jest"' "$TARGET_DIR/package.json" 2>/dev/null; then
            echo "cd '$TARGET_DIR' && npx jest --no-coverage 2>&1 || true"
            return
        fi
        echo "cd '$TARGET_DIR' && npm test 2>&1 || true"
        return
    fi
    if [ -f "$TARGET_DIR/Cargo.toml" ]; then
        echo "cd '$TARGET_DIR' && cargo test 2>&1 || true"
        return
    fi
    if [ -f "$TARGET_DIR/go.mod" ]; then
        echo "cd '$TARGET_DIR' && go test ./... 2>&1 || true"
        return
    fi
    echo ""
}
