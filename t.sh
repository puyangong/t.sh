#!/data/data/com.termux/files/usr/bin/bash
#===============================================================================
# ZT 一键脚本
# 作者：PYG
# 运行环境：Termux (Android)
# 功能：代码环境管理 / 安装卸载 / proot Linux 发行版 / 常用一键配置
#===============================================================================

#===============================================================================
# 全局变量与配置路径
#===============================================================================
PYG_DIR="$HOME/.pyg"
BIN_DIR="$PYG_DIR/bin"
STATE_DIR="$PYG_DIR"
UI_NODE_FILE="$STATE_DIR/ui_node"
CUR_DIR_FILE="$STATE_DIR/cur_dir"
DIALOG_INSTALLED_FILE="$STATE_DIR/dialog_installed"
PROOT_MAP_FILE="$STATE_DIR/proot_map"
FOLDER_ENV_LIST="$STATE_DIR/folder_env_list"

# 菜单位置持久化文件
MENUPOS_DIR="$PYG_DIR/menupos"
mkdir -p "$MENUPOS_DIR" 2>/dev/null

# 支持的环境类型
ENV_TYPES=("python3" "nodejs" "rust" "go" "java" "clang")

# 环境列表内依赖（代码环境管理列表内）
ENV_LIST_DEPS=("python3" "nodejs" "rust" "go" "java" "clang")

# Java 固定版本列表（笔记：不再拉取 apt 版本）
JAVA_VERSIONS=("openjdk-17" "openjdk-21" "openjdk-24")

#===============================================================================
# 全局按键标签
#===============================================================================
OK_LABEL="确认"
CANCEL_LABEL="返回"
EXTRA_LABEL="退出"

#===============================================================================
# 工具函数
#===============================================================================

ensure_pyg_dir() {
    mkdir -p "$PYG_DIR"
    mkdir -p "$BIN_DIR"
}

write_state() {
    local file="$1"
    local content="$2"
    ensure_pyg_dir
    echo "$content" > "$STATE_DIR/$file"
}

read_state() {
    local file="$1"
    if [ -f "$STATE_DIR/$file" ]; then
        cat "$STATE_DIR/$file"
    else
        echo ""
    fi
}

# 菜单位置持久化
save_menu_pos() {
    local menu_id="$1"
    local tag="$2"
    mkdir -p "$MENUPOS_DIR"
    echo "$tag" > "$MENUPOS_DIR/${menu_id}"
}

load_menu_pos() {
    local menu_id="$1"
    if [ -f "$MENUPOS_DIR/${menu_id}" ]; then
        cat "$MENUPOS_DIR/${menu_id}"
    else
        echo ""
    fi
}

get_local_bashrc() {
    local cur_dir
    cur_dir=$(read_state "cur_dir")
    if [ -z "$cur_dir" ]; then
        cur_dir="$PWD"
    fi
    echo "$cur_dir/.bashrc"
}

get_global_bashrc() {
    echo "$HOME/.bashrc"
}

get_next_seq() {
    local env_type="$1"
    local custom_name="$2"
    local target_dir="$BIN_DIR/$env_type"
    local max_seq=0
    if [ -d "$target_dir" ]; then
        for d in "$target_dir"/"$custom_name"-*; do
            if [ -d "$d" ]; then
                local seq
                seq=$(basename "$d" | sed "s/^${custom_name}-//")
                if [ "$seq" -gt "$max_seq" ] 2>/dev/null; then
                    max_seq=$seq
                fi
            fi
        done
    fi
    echo $((max_seq + 1))
}

#===============================================================================
# UI 节点管理（笔记：Cancel不保存 UI_NODE，退出保留最深层节点）
#===============================================================================
save_ui_node() {
    local node="$1"
    write_state "ui_node" "$node"
}

read_ui_node() {
    read_state "ui_node"
}

save_cur_dir() {
    local dir="$1"
    write_state "cur_dir" "$dir"
}

read_cur_dir() {
    local d
    d=$(read_state "cur_dir")
    if [ -z "$d" ]; then
        d="$HOME"
    fi
    echo "$d"
}

#===============================================================================
# 依赖检查
#===============================================================================
check_dialog() {
    ensure_pyg_dir
    if [ -f "$DIALOG_INSTALLED_FILE" ]; then
        return 0
    fi
    if command -v dialog &>/dev/null; then
        echo "installed" > "$DIALOG_INSTALLED_FILE"
        return 0
    fi
    echo "正在安装 dialog..."
    pkg install dialog -y >/dev/null 2>&1
    if command -v dialog &>/dev/null; then
        echo "installed" > "$DIALOG_INSTALLED_FILE"
        return 0
    else
        echo "错误：无法安装 dialog，请手动安装后重试。" >&2
        exit 1
    fi
}

ensure_component() {
    local component="$1"
    if ! command -v "$component" &>/dev/null; then
        echo "正在安装 $component..."
        pkg install "$component" -y >/dev/null 2>&1
        if command -v "$component" &>/dev/null; then
            echo "installed" > "$STATE_DIR/${component}_installed"
        else
            dialog --msgbox "无法安装 $component，请检查网络或手动安装。" 8 50
            return 1
        fi
    fi
    return 0
}

#===============================================================================
# 退出脚本（仅在 Extra 按钮触发，不 trap）
#===============================================================================
exit_script() {
    local cur_dir
    cur_dir=$(pwd)
    save_cur_dir "$cur_dir"
    save_ui_node "$(read_ui_node)"
    clear
    exec bash -c "cd \"$cur_dir\" 2>/dev/null || true; exec bash"
}

#===============================================================================
# 通用菜单框架（带焦点持久化）
#===============================================================================

# 主页面菜单：OK(确认) + Extra(退出)，无返回按钮
show_menu_main() {
    local menu_id="$1"
    local title="$2"
    shift 2
    local default_item
    default_item=$(load_menu_pos "$menu_id")
    local default_arg=()
    [ -n "$default_item" ] && default_arg=(--default-item "$default_item")
    dialog --clear --title " $title " \
        --ok-label "$OK_LABEL" \
        --nocancel \
        --extra-button --extra-label "$EXTRA_LABEL" \
        "${default_arg[@]}" \
        --menu "" 0 0 12 "$@" 2>&1 >/dev/tty
}

# 子页面菜单：OK(确认) + Cancel(返回)，无退出按钮
show_menu_sub() {
    local menu_id="$1"
    local title="$2"
    shift 2
    local default_item
    default_item=$(load_menu_pos "$menu_id")
    local default_arg=()
    [ -n "$default_item" ] && default_arg=(--default-item "$default_item")
    dialog --clear --title " $title " \
        --ok-label "$OK_LABEL" \
        --cancel-label "$CANCEL_LABEL" \
        "${default_arg[@]}" \
        --menu "" 0 0 12 "$@" 2>&1 >/dev/tty
}

# 子页面菜单（带自定义 Extra 按钮）
show_menu_sub_extra() {
    local menu_id="$1"
    local title="$2"
    local extra_label="$3"
    shift 3
    local default_item
    default_item=$(load_menu_pos "$menu_id")
    local default_arg=()
    [ -n "$default_item" ] && default_arg=(--default-item "$default_item")
    dialog --clear --title " $title " \
        --ok-label "$OK_LABEL" \
        --cancel-label "$CANCEL_LABEL" \
        --extra-button --extra-label "$extra_label" \
        "${default_arg[@]}" \
        --menu "" 0 0 12 "$@" 2>&1 >/dev/tty
}

show_inputbox() {
    local title="$1"
    local prompt="$2"
    local init="$3"
    dialog --clear --title " $title " \
        --ok-label "$OK_LABEL" \
        --cancel-label "$CANCEL_LABEL" \
        --inputbox "$prompt" 0 0 "$init" 2>&1 >/dev/tty
}

show_yesno() {
    local title="$1"
    local prompt="$2"
    dialog --clear --title " $title " \
        --yes-label "$OK_LABEL" \
        --no-label "取消" \
        --yesno "$prompt" 0 0
}

show_msgbox() {
    local title="$1"
    local msg="$2"
    dialog --clear --title " $title " \
        --ok-label "$OK_LABEL" \
        --msgbox "$msg" 0 0
}

#===============================================================================
# 代码环境管理 - 工具函数
#===============================================================================

get_active_version() {
    local env_type="$1"
    local bashrc_path="$2"
    if [ ! -f "$bashrc_path" ]; then
        echo ""
        return
    fi
    local line
    line=$(grep -E "^export PATH=.*\.pyg/bin/${env_type}/" "$bashrc_path" 2>/dev/null | head -1)
    if [ -z "$line" ]; then
        echo ""
        return
    fi
    local ver
    ver=$(echo "$line" | sed -E "s|.*\.pyg/bin/${env_type}/([^/]+)/.*|\1|")
    echo "$ver"
}

get_installed_versions() {
    local env_type="$1"
    local target_dir="$BIN_DIR/$env_type"
    if [ ! -d "$target_dir" ]; then
        echo ""
        return
    fi
    ls -1 "$target_dir" 2>/dev/null | sort
}

# 构建环境版本菜单项
build_env_version_menu() {
    local env_type="$1"
    local bashrc_path="$2"
    local menu_items=()
    local active
    active=$(get_active_version "$env_type" "$bashrc_path")
    
    local versions
    versions=$(get_installed_versions "$env_type")
    
    if [ -n "$versions" ]; then
        while IFS= read -r ver; do
            [ -z "$ver" ] && continue
            local display="$ver"
            if [ "$ver" = "$active" ]; then
                display="$ver  [当前激活]"
            fi
            menu_items+=("$ver" "$display")
        done <<< "$versions"
    fi
    
    # 返回数组通过全局变量
    ENV_VER_MENU_ITEMS=("${menu_items[@]}")
    ENV_VER_COUNT=${#menu_items[@]}
}

#===============================================================================
# 代码环境管理
#===============================================================================

# 选择环境（展示当前激活状态）
show_env_select() {
    local scope="$1"  # "global" or "local"
    local bashrc_path
    
    if [ "$scope" = "global" ]; then
        bashrc_path=$(get_global_bashrc)
    else
        bashrc_path=$(get_local_bashrc)
    fi
    
    save_ui_node "env_select_$scope"
    
    local menu_items=()
    for env in "${ENV_TYPES[@]}"; do
        local active
        active=$(get_active_version "$env" "$bashrc_path")
        local display_name="$env"
        if [ -n "$active" ]; then
            display_name="$env  [激活: $active]"
        else
            display_name="$env  [未激活]"
        fi
        menu_items+=("$env" "$display_name")
    done
    
    # 笔记：select_env_type 高度=6
    local choice
    local label
    [ "$scope" = "global" ] && label="全局" || label="当前文件夹"
    choice=$(show_menu_sub "env_select_$scope" "选择环境 ($label)" "${menu_items[@]}")
    local ret=$?
    
    case $ret in
        0)  # 确认
            if [ -n "$choice" ]; then
                save_menu_pos "env_select_$scope" "$choice"
                local active
                active=$(get_active_version "$choice" "$bashrc_path")
                if [ -z "$active" ]; then
                    show_msgbox "$choice" "当前无激活版本，将跳转至下载界面。"
                    download_env "$choice" "$scope" "$bashrc_path"
                else
                    switch_env_version "$choice" "$scope" "$bashrc_path"
                fi
            else
                show_env_select "$scope"
            fi
            ;;
        1)  # 返回 - 不保存UI_NODE（笔记）
            env_operation_menu "$scope"
            ;;
    esac
}

# 切换版本
switch_env_version() {
    local env_type="$1"
    local scope="$2"
    local bashrc_path="$3"
    
    save_ui_node "switch_${env_type}_$scope"
    
    build_env_version_menu "$env_type" "$bashrc_path"
    
    if [ "$ENV_VER_COUNT" -eq 0 ]; then
        show_msgbox "$env_type" "该环境暂无已下载版本。"
        show_env_select "$scope"
        return
    fi
    
    local choice
    choice=$(show_menu_sub_extra "switch_${env_type}_$scope" "切换版本 - $env_type" "重命名" "${ENV_VER_MENU_ITEMS[@]}")
    local ret=$?
    
    case $ret in
        0)  # 确认 - 切换版本
            if [ -n "$choice" ]; then
                save_menu_pos "switch_${env_type}_$scope" "$choice"
                local full_dir="$BIN_DIR/$env_type/$choice"
                local bin_subpath=""
                local found_bin
                found_bin=$(find "$full_dir" -type d -name "bin" 2>/dev/null | head -1)
                if [ -n "$found_bin" ]; then
                    bin_subpath="${found_bin#$full_dir/}"
                else
                    local first_exe
                    first_exe=$(find "$full_dir" -type f -executable 2>/dev/null | head -1)
                    [ -n "$first_exe" ] && bin_subpath=$(dirname "${first_exe#$full_dir/}")
                fi
                [ -z "$bin_subpath" ] && bin_subpath="bin"
                local new_path="\$HOME/.pyg/bin/${env_type}/${choice}/${bin_subpath}"
                
                if [ -f "$bashrc_path" ]; then
                    sed -i "\|export PATH=.*\.pyg/bin/${env_type}/|d" "$bashrc_path"
                    sed -i "\|export LD_LIBRARY_PATH=.*\.pyg/bin/${env_type}/${choice}/|d" "$bashrc_path"
                fi
                echo "export PATH=\"$new_path:\$PATH\"" >> "$bashrc_path"
                # 自动搜索所有 lib 目录，逐一挂载 LD_LIBRARY_PATH
                while IFS= read -r lib_dir; do
                    [ -z "$lib_dir" ] && continue
                    local lib_path="${lib_dir#$full_dir/}"
                    echo "export LD_LIBRARY_PATH=\"\$HOME/.pyg/bin/${env_type}/${choice}/${lib_path}:\$LD_LIBRARY_PATH\"" >> "$bashrc_path"
                done < <(find "$full_dir" -type d -name "lib" 2>/dev/null)
                show_msgbox "切换成功" "已切换到 $env_type 版本: $choice\n请执行 source $bashrc_path 使其生效。"
            fi
            show_env_select "$scope"
            ;;
        1)  # 返回
            show_env_select "$scope"
            ;;
        3)  # 重命名
            rename_env_version "$env_type" "$scope" "$bashrc_path"
            ;;
    esac
}

# 重命名环境版本（从选择环境界面触发）
rename_env_flow() {
    local scope="$1"
    local bashrc_path="$2"
    
    # 先选择环境类型
    local menu_items=()
    for env in "${ENV_TYPES[@]}"; do
        menu_items+=("$env" "$env")
    done
    
    local env_type
    env_type=$(show_menu_sub "rename_env_type" "重命名 - 选择环境类型" "${menu_items[@]}")
    local ret=$?
    
    if [ $ret -ne 0 ] || [ -z "$env_type" ]; then
        show_env_select "$scope"
        return
    fi
    
    rename_env_version "$env_type" "$scope" "$bashrc_path"
}

# 重命名环境版本
rename_env_version() {
    local env_type="$1"
    local scope="$2"
    local bashrc_path="$3"
    
    local versions
    versions=$(get_installed_versions "$env_type")
    if [ -z "$versions" ]; then
        show_msgbox "重命名" "该环境暂无已下载版本。"
        show_env_select "$scope"
        return
    fi
    
    local menu_items=()
    while IFS= read -r ver; do
        [ -z "$ver" ] && continue
        menu_items+=("$ver" "$ver")
    done <<< "$versions"
    
    local target_ver
    target_ver=$(show_menu_sub "rename_sel_${env_type}" "重命名 - 选择版本" "${menu_items[@]}")
    local ret=$?
    
    if [ $ret -ne 0 ] || [ -z "$target_ver" ]; then
        show_env_select "$scope"
        return
    fi
    
    local old_name
    old_name=$(echo "$target_ver" | sed -E 's/-[0-9]+$//')
    local old_seq
    old_seq=$(echo "$target_ver" | sed -E 's/.*-([0-9]+)$/\1/')
    
    local new_name
    new_name=$(show_inputbox "重命名 - $env_type" "输入新的名称（当前: $old_name）" "$old_name")
    local ret2=$?
    
    if [ $ret2 -ne 0 ] || [ -z "$new_name" ] || [ "$new_name" = "$old_name" ]; then
        show_env_select "$scope"
        return
    fi
    
    local new_ver="${new_name}-${old_seq}"
    local old_dir="$BIN_DIR/$env_type/$target_ver"
    local new_dir="$BIN_DIR/$env_type/$new_ver"
    
    if [ -d "$new_dir" ]; then
        show_msgbox "错误" "目标名称 $new_ver 已存在！"
        show_env_select "$scope"
        return
    fi
    
    mv "$old_dir" "$new_dir"
    
    if [ -f "$bashrc_path" ]; then
        sed -i "s|\.pyg/bin/${env_type}/${target_ver}/|.pyg/bin/${env_type}/${new_ver}/|g" "$bashrc_path"
    fi
    
    show_msgbox "重命名成功" "已将 $target_ver 重命名为 $new_ver"
    show_env_select "$scope"
}

# 非交互式安装环境包（供依赖调用）
_install_env_pkg() {
    local dep_env="$1"        # 环境类型: python3/nodejs/rust/go/java/clang
    local dep_pkg="$2"        # apt 包名
    local dep_name="$3"       # 自定义名称
    local bashrc_path="$4"    # .bashrc 路径
    
    # 检查是否已安装过该依赖
    local target_dir="$BIN_DIR/$dep_env"
    if [ -d "$target_dir" ]; then
        local already
        already=$(ls "$target_dir" 2>/dev/null | grep "^${dep_name}-")
        [ -n "$already" ] && return 0  # 已安装，跳过
    fi
    
    local seq
    seq=$(get_next_seq "$dep_env" "$dep_name")
    local dep_target="$BIN_DIR/$dep_env/${dep_name}-${seq}"
    local dep_tmp="$PYG_DIR/dep_tmp_$$_${dep_pkg}"
    mkdir -p "$dep_tmp" "$dep_target"
    cd "$dep_tmp"
    
    # 下载 .deb
    apt download "$dep_pkg" 2>/dev/null || pkg download "$dep_pkg" 2>/dev/null || { rm -rf "$dep_tmp"; return 0; }
    
    local deb_file
    deb_file=$(ls *.deb 2>/dev/null | head -1)
    [ -z "$deb_file" ] && { rm -rf "$dep_tmp"; return 0; }
    
    # ar 解压
    ar x "$deb_file" 2>/dev/null
    
    # 解压 data.tar.xz → 找 usr → 移到目标
    local dep_extract="$dep_tmp/extract"
    mkdir -p "$dep_extract"
    if [ -f data.tar.xz ]; then
        tar -xf data.tar.xz -C "$dep_extract" 2>/dev/null || true
    elif [ -f data.tar.gz ]; then
        tar -xf data.tar.gz -C "$dep_extract" 2>/dev/null || true
    fi
    
    local usr_dir
    usr_dir=$(find "$dep_extract" -type d -path "*/usr" 2>/dev/null | head -1)
    if [ -n "$usr_dir" ] && [ -d "$usr_dir" ]; then
        cp -r "$usr_dir"/* "$dep_target"/ 2>/dev/null || true
    else
        cp -r "$dep_extract"/* "$dep_target"/ 2>/dev/null || true
    fi
    
    # 在目标文件夹内遍历寻找 bin 目录
    local dep_bin=""
    local found_bin
    found_bin=$(find "$dep_target" -type d -name "bin" 2>/dev/null | head -1)
    if [ -n "$found_bin" ]; then
        dep_bin="${found_bin#$dep_target/}"
    else
        # 兜底：遍历查找含可执行文件的目录
        local first_exe
        first_exe=$(find "$dep_target" -type f -executable 2>/dev/null | head -1)
        [ -n "$first_exe" ] && dep_bin=$(dirname "${first_exe#$dep_target/}")
    fi
    [ -z "$dep_bin" ] && dep_bin="bin"
    
    # 写入 PATH
    local export_line="export PATH=\"\$HOME/.pyg/bin/${dep_env}/${dep_name}-${seq}/${dep_bin}:\$PATH\""
    if [ -f "$bashrc_path" ]; then
        sed -i "\|export PATH=.*\.pyg/bin/${dep_env}/${dep_name}-|d" "$bashrc_path"
    fi
    echo "$export_line" >> "$bashrc_path"
    
    # 自动搜索所有 lib 目录，逐一挂载到 LD_LIBRARY_PATH
    if [ -f "$bashrc_path" ]; then
        sed -i "\|export LD_LIBRARY_PATH=.*\.pyg/bin/${dep_env}/${dep_name}-|d" "$bashrc_path"
    fi
    while IFS= read -r lib_dir; do
        [ -z "$lib_dir" ] && continue
        local lib_path="${lib_dir#$dep_target/}"
        echo "export LD_LIBRARY_PATH=\"\$HOME/.pyg/bin/${dep_env}/${dep_name}-${seq}/${lib_path}:\$LD_LIBRARY_PATH\"" >> "$bashrc_path"
    done < <(find "$dep_target" -type d -name "lib" 2>/dev/null)
    
    # 递归处理该依赖自身的 Depends/Pre-Depends（限一层）
    if [ -f control.tar.xz ]; then
        tar -xf control.tar.xz control 2>/dev/null || true
    elif [ -f control.tar.gz ]; then
        tar -xf control.tar.gz control 2>/dev/null || true
    fi
    if [ -f control ]; then
        local sub_deps
        sub_deps=$(grep -E "^(Depends|Pre-Depends):" control 2>/dev/null | sed 's/^[^:]*://' | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed 's/([^)]*)//g' | sed 's/[>=<].*//' | xargs -n1 | sort -u)
        while IFS= read -r sdep; do
            [ -z "$sdep" ] && continue
            local in_list=false
            for env_item in "${ENV_LIST_DEPS[@]}"; do
                [[ "$sdep" == *"$env_item"* ]] || [[ "$env_item" == *"$sdep"* ]] && in_list=true && break
            done
            if $in_list; then
                local sdep_env=""
                case "$sdep" in
                    python|python3|python-*) sdep_env="python3" ;;
                    nodejs|node-*)           sdep_env="nodejs" ;;
                    rust|rustc|cargo)        sdep_env="rust" ;;
                    golang|go|golang-*)      sdep_env="go" ;;
                    openjdk*|jdk*|java-*)    sdep_env="java" ;;
                    clang|llvm|clang-*)      sdep_env="clang" ;;
                esac
                [ -n "$sdep_env" ] && _install_env_pkg "$sdep_env" "$sdep" "${sdep}-dep" "$bashrc_path"
            else
                pkg install "$sdep" -y >/dev/null 2>&1 || true
            fi
        done <<< "$sub_deps"
    fi
    
    rm -rf "$dep_tmp"
    return 0
}

# 下载环境
download_env() {
    local env_type="${1:-}"
    
    save_ui_node "download_env"
    
    if [ -z "$env_type" ]; then
        local menu_items=()
        for env in "${ENV_TYPES[@]}"; do
            menu_items+=("$env" "$env")
        done
        env_type=$(show_menu_sub "download_env_type" "选择环境类型" "${menu_items[@]}")
        local ret=$?
        case $ret in
            0)
                if [ -n "$env_type" ]; then
                    save_menu_pos "download_env_type" "$env_type"
                fi
                ;;
            1) return ;;
        esac
        if [ -z "$env_type" ]; then
            return
        fi
    fi
    
    local scope="${2:-global}"
    local bashrc_path="${3:-$(get_global_bashrc)}"
    
    # 选择版本
    local ver_menu=()
    
    case "$env_type" in
        java)
            # 笔记：Java 固定版本列表 openjdk-17/21/24
            for jver in "${JAVA_VERSIONS[@]}"; do
                ver_menu+=("$jver" "$jver")
            done
            ;;
        python3)
            ver_menu+=("python" "python (最新)")
            ;;
        nodejs)
            ver_menu+=("nodejs" "nodejs (最新)")
            ;;
        rust)
            ver_menu+=("rust" "rust (最新)")
            ;;
        go)
            ver_menu+=("golang" "golang (最新)")
            ;;
        clang)
            ver_menu+=("clang" "clang (最新)")
            ;;
        *)
            show_msgbox "错误" "不支持的环境类型: $env_type"
            return
            ;;
    esac
    
    local version_choice
    version_choice=$(show_menu_sub "download_ver_$env_type" "选择 $env_type 版本" "${ver_menu[@]}")
    local ret=$?
    case $ret in
        0) ;;
        1) download_env "" "$scope" "$bashrc_path"; return ;;
    esac
    
    if [ -z "$version_choice" ]; then
        return
    fi
    
    # 弹窗输入自定义名称
    local default_name="$env_type"
    case "$env_type" in
        java)
            default_name="$version_choice"
            ;;
    esac
    
    local custom_name
    custom_name=$(show_inputbox "自定义名称" "为此版本输入一个名称" "$default_name")
    local ret2=$?
    if [ $ret2 -ne 0 ] || [ -z "$custom_name" ]; then
        download_env "$env_type" "$scope" "$bashrc_path"
        return
    fi
    
    local seq
    seq=$(get_next_seq "$env_type" "$custom_name")
    local target_dir="$BIN_DIR/$env_type/${custom_name}-${seq}"
    local tmp_dir="$PYG_DIR/tmp_$$"
    mkdir -p "$tmp_dir"
    mkdir -p "$target_dir"
    
    # 确定包名
    local pkg_name="$version_choice"
    
    # 下载 .deb 包
    cd "$tmp_dir"
    (
        echo "10"
        echo "正在下载 $pkg_name..."
        apt download "$pkg_name" 2>/dev/null || pkg download "$pkg_name" 2>/dev/null || true
        echo "50"
    ) | dialog --gauge "下载 $env_type 环境" 8 60 0
    
    local deb_file
    deb_file=$(ls *.deb 2>/dev/null | head -1)
    if [ -z "$deb_file" ]; then
        show_msgbox "错误" "下载失败，请检查网络或包名。"
        rm -rf "$tmp_dir"
        cd "$(read_cur_dir)"
        return
    fi
    
    # 解压 .deb
    (
        echo "60"
        ar x "$deb_file" 2>/dev/null
        echo "80"
    ) | dialog --gauge "解压 .deb 包" 8 60 0
    
    # 解压 data：先解到临时目录，找到 usr 后将其所有内容移到目标目录
    local extract_dir="$tmp_dir/extract"
    mkdir -p "$extract_dir"
    if [ -f data.tar.xz ]; then
        tar -xf data.tar.xz -C "$extract_dir" 2>/dev/null || true
    elif [ -f data.tar.gz ]; then
        tar -xf data.tar.gz -C "$extract_dir" 2>/dev/null || true
    fi
    
    # 查找 usr 目录，将其下所有文件移至 target_dir
    local usr_dir
    usr_dir=$(find "$extract_dir" -type d -path "*/usr" 2>/dev/null | head -1)
    if [ -n "$usr_dir" ] && [ -d "$usr_dir" ]; then
        cp -r "$usr_dir"/* "$target_dir"/ 2>/dev/null || true
    else
        # 兜底：直接移所有内容
        cp -r "$extract_dir"/* "$target_dir"/ 2>/dev/null || true
    fi
    
    # 解压 control
    local date_str
    date_str=$(date +%Y%m%d-%H%M%S)
    if [ -f control.tar.xz ]; then
        tar -xf control.tar.xz control 2>/dev/null || true
        if [ -f control ]; then
            mv control "$PYG_DIR/control-${env_type}-${date_str}"
        fi
    elif [ -f control.tar.gz ]; then
        tar -xf control.tar.gz control 2>/dev/null || true
        if [ -f control ]; then
            mv control "$PYG_DIR/control-${env_type}-${date_str}"
        fi
    fi
    
    # 处理依赖：管理列表内用相同方式下载解压配置，列表外静默安装
    local control_file="$PYG_DIR/control-${env_type}-${date_str}"
    if [ -f "$control_file" ]; then
        local depends=""
        local pre_depends=""
        depends=$(grep -E "^Depends:" "$control_file" | sed 's/^Depends://' | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        pre_depends=$(grep -E "^Pre-Depends:" "$control_file" | sed 's/^Pre-Depends://' | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        
        local all_deps="$depends"
        [ -n "$pre_depends" ] && all_deps="$all_deps"$'\n'"$pre_depends"
        
        while IFS= read -r dep; do
            [ -z "$dep" ] && continue
            local dep_pkg
            dep_pkg=$(echo "$dep" | sed 's/([^)]*)//g' | sed 's/[>=<].*//' | xargs)
            [ -z "$dep_pkg" ] && continue
            
            # 匹配包名到环境类型
            local dep_env=""
            case "$dep_pkg" in
                python|python3|python-*) dep_env="python3" ;;
                nodejs|node-*)           dep_env="nodejs" ;;
                rust|rustc|cargo)        dep_env="rust" ;;
                golang|go|golang-*)      dep_env="go" ;;
                openjdk*|jdk*|java-*)    dep_env="java" ;;
                clang|llvm|clang-*)      dep_env="clang" ;;
            esac
            
            if [ -n "$dep_env" ]; then
                # 管理列表内：相同方式下载解压配置
                local dep_name="${dep_pkg}-dep"
                _install_env_pkg "$dep_env" "$dep_pkg" "$dep_name" "$bashrc_path"
            else
                # 列表外：静默安装
                pkg install "$dep_pkg" -y >/dev/null 2>&1 || true
            fi
        done <<< "$all_deps"
        
        [ -n "$pre_depends" ] && show_msgbox "Pre-Depends 信息" "以下为预依赖信息：\n\n$pre_depends"
    fi
    
    # 在自定义文件夹内遍历寻找 bin 目录
    local bin_subpath=""
    local found_bin
    found_bin=$(find "$target_dir" -type d -name "bin" 2>/dev/null | head -1)
    if [ -n "$found_bin" ]; then
        bin_subpath="${found_bin#$target_dir/}"
    else
        local first_exe
        first_exe=$(find "$target_dir" -type f -executable 2>/dev/null | head -1)
        [ -n "$first_exe" ] && bin_subpath=$(dirname "${first_exe#$target_dir/}")
    fi
    [ -z "$bin_subpath" ] && bin_subpath="bin"
    
    # 写入 PATH
    local export_line="export PATH=\"\$HOME/.pyg/bin/${env_type}/${custom_name}-${seq}/${bin_subpath}:\$PATH\""
    if [ -f "$bashrc_path" ]; then
        sed -i "\|export PATH=.*\.pyg/bin/${env_type}/|d" "$bashrc_path"
    fi
    echo "$export_line" >> "$bashrc_path"
    
    # 自动搜索所有 lib 目录，逐一挂载到 LD_LIBRARY_PATH
    if [ -f "$bashrc_path" ]; then
        sed -i "\|export LD_LIBRARY_PATH=.*\.pyg/bin/${env_type}/${custom_name}-|d" "$bashrc_path"
    fi
    while IFS= read -r lib_dir; do
        [ -z "$lib_dir" ] && continue
        local lib_path="${lib_dir#$target_dir/}"
        echo "export LD_LIBRARY_PATH=\"\$HOME/.pyg/bin/${env_type}/${custom_name}-${seq}/${lib_path}:\$LD_LIBRARY_PATH\"" >> "$bashrc_path"
    done < <(find "$target_dir" -type d -name "lib" 2>/dev/null)
    
    rm -rf "$tmp_dir"
    cd "$(read_cur_dir)"
    
    show_msgbox "安装完成" "环境 $env_type 已安装为: ${custom_name}-${seq}\n请执行 source $bashrc_path 使其生效。"
}

# 卸载环境
uninstall_env() {
    save_ui_node "uninstall_env"
    
    local menu_items=()
    for env in "${ENV_TYPES[@]}"; do
        menu_items+=("$env" "$env")
    done
    
    local env_type
    env_type=$(show_menu_sub "uninstall_env_type" "选择要卸载的环境类型" "${menu_items[@]}")
    local ret=$?
    case $ret in
        0)
            if [ -n "$env_type" ]; then
                save_menu_pos "uninstall_env_type" "$env_type"
            fi
            ;;
        1) return ;;
    esac
    if [ -z "$env_type" ]; then
        return
    fi
    
    local versions
    versions=$(get_installed_versions "$env_type")
    if [ -z "$versions" ]; then
        show_msgbox "卸载" "该环境暂无已下载版本。"
        return
    fi
    
    local ver_menu=()
    while IFS= read -r ver; do
        [ -z "$ver" ] && continue
        ver_menu+=("$ver" "$ver")
    done <<< "$versions"
    
    local target_ver
    target_ver=$(show_menu_sub "uninstall_ver_$env_type" "卸载 $env_type - 选择版本" "${ver_menu[@]}")
    local ret2=$?
    case $ret2 in
        0) ;;
        1) uninstall_env; return ;;
    esac
    if [ -z "$target_ver" ]; then
        return
    fi
    
    if ! show_yesno "确认卸载" "确定要卸载 $env_type 版本 $target_ver 吗？"; then
        uninstall_env
        return
    fi
    
    rm -rf "$BIN_DIR/$env_type/$target_ver"
    
    local bashrc_path
    bashrc_path=$(get_global_bashrc)
    if [ -f "$bashrc_path" ]; then
        sed -i "\|export PATH=.*\.pyg/bin/${env_type}/${target_ver}/|d" "$bashrc_path"
    fi
    
    show_msgbox "卸载成功" "已卸载 $env_type 版本: $target_ver"
}

#===============================================================================
# 环境操作菜单（笔记：env_ops 高度=0 让 dialog 自动）
#===============================================================================
env_operation_menu() {
    local scope="${1:-global}"
    
    # 笔记：Cancel不保存UI_NODE
    save_ui_node "env_op_$scope"
    
    local title
    if [ "$scope" = "global" ]; then
        title="环境管理 (全局)"
    else
        title="环境管理 (当前文件夹)"
    fi
    
    local choice
    choice=$(show_menu_sub "env_ops_$scope" "$title" \
        "select"    "选择环境" \
        "download"  "下载环境" \
        "uninstall" "卸载环境")
    local ret=$?
    
    case $ret in
        0)
            save_menu_pos "env_ops_$scope" "$choice"
            case "$choice" in
                select)
                    show_env_select "$scope"
                    ;;
                download)
                    local bashrc_path
                    if [ "$scope" = "global" ]; then
                        bashrc_path=$(get_global_bashrc)
                    else
                        bashrc_path=$(get_local_bashrc)
                    fi
                    download_env "" "$scope" "$bashrc_path"
                    ;;
                uninstall)
                    uninstall_env
                    ;;
            esac
            ;;
        1)  # 返回 - 不保存UI_NODE
            env_scope_menu
            ;;
    esac
}

# 环境作用域选择菜单
env_scope_menu() {
    save_ui_node "env_scope"
    
    local choice
    choice=$(show_menu_sub "env_scope" "环境作用域" \
        "global" "全局 (~/.bashrc)" \
        "local"  "当前文件夹 (./.bashrc)")
    local ret=$?
    
    case $ret in
        0)
            save_menu_pos "env_scope" "$choice"
            case "$choice" in
                global)
                    env_operation_menu "global"
                    ;;
                local)
                    local cur_dir
                    cur_dir=$(read_cur_dir)
                    if [ ! -f "$FOLDER_ENV_LIST" ]; then
                        touch "$FOLDER_ENV_LIST"
                    fi
                    if ! grep -qxF "$cur_dir" "$FOLDER_ENV_LIST" 2>/dev/null; then
                        echo "$cur_dir" >> "$FOLDER_ENV_LIST"
                    fi
                    env_operation_menu "local"
                    ;;
            esac
            ;;
        1)  # 返回主菜单 - 不保存UI_NODE
            main_menu
            ;;
    esac
}

#===============================================================================
# 安装或卸载模块
#===============================================================================

install_uninstall_menu() {
    save_ui_node "install_uninstall"
    
    local choice
    choice=$(show_menu_sub "install_uninstall" "安装 / 卸载" \
        "search_install"   "搜索安装" \
        "search_uninstall" "搜索卸载")
    local ret=$?
    
    case $ret in
        0)
            save_menu_pos "install_uninstall" "$choice"
            case "$choice" in
                search_install)
                    search_install
                    ;;
                search_uninstall)
                    search_uninstall
                    ;;
            esac
            ;;
        1) main_menu ;;
    esac
}

# 搜索安装
search_install() {
    save_ui_node "search_install"
    
    # 自动执行 pkg update 和 pkg upgrade
    (
        echo "0"
        echo "正在更新软件源..."
        pkg update -y >/dev/null 2>&1
        echo "50"
        echo "正在升级软件包..."
        pkg upgrade -y >/dev/null 2>&1
        echo "100"
    ) | dialog --gauge "更新软件源 & 升级软件包" 8 60 0
    
    while true; do
        local keyword
        keyword=$(show_inputbox "搜索安装" "输入要搜索的软件包关键词" "")
        local ret=$?
        
        case $ret in
            0) ;;
            1) install_uninstall_menu; return ;;
        esac

        if [ -z "$keyword" ]; then
            continue
        fi
        
        local search_results
        search_results=$(pkg search "$keyword" 2>/dev/null | head -30)
        
        if [ -z "$search_results" ]; then
            show_msgbox "搜索结果" "未找到与 \"$keyword\" 相关的软件包。"
            continue
        fi
        
        local menu_items=()
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local pkg
            pkg=$(echo "$line" | awk '{print $1}')
            local name
            name=$(echo "$pkg" | awk -F/ '{print $1}')
            local desc
            desc=$(echo "$line" | cut -d' ' -f2-)
            # 排除包名不包含关键词的无关结果
            if echo "$name" | grep -qi "$keyword"; then
                menu_items+=("$pkg" "$name" "$desc")
            fi
        done <<< "$search_results"
        
        local selected
        selected=$(dialog --clear --title " 搜索结果 - \"$keyword\" " \
            --ok-label "$OK_LABEL" --cancel-label "$CANCEL_LABEL" \
            --item-help \
            --menu "" 0 0 12 "${menu_items[@]}" 2>&1 >/dev/tty)
        local ret2=$?
        
        case $ret2 in
            0)
                if [ -n "$selected" ]; then
                    dialog --infobox "正在安装 $selected ..." 4 40
                    pkg install "$selected" -y 2>&1 | dialog --progressbox 20 60
                    show_msgbox "安装完成" "软件包 $selected 安装完成。"
                fi
                ;;
            1) continue ;;
        esac
    done
}

# 搜索卸载
search_uninstall() {
    save_ui_node "search_uninstall"
    
    while true; do
        local installed_pkgs
        installed_pkgs=$(pkg list-installed 2>/dev/null | awk '{print $1, $2}' | sort)
        
        if [ -z "$installed_pkgs" ]; then
            show_msgbox "搜索卸载" "没有已安装的软件包。"
            return
        fi
        
        local keyword
        keyword=$(show_inputbox "搜索卸载" "输入关键词筛选已安装软件包（留空显示全部）" "")
        local ret=$?
        
        case $ret in
            0) ;;
            1) install_uninstall_menu; return ;;
        esac

        local menu_items=()
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local pkg_name
            pkg_name=$(echo "$line" | awk '{print $1}')
            local pkg_ver
            pkg_ver=$(echo "$line" | awk '{print $2}')
            local display="${pkg_ver}  ${pkg_name}"
            
            if [ -z "$keyword" ] || echo "$pkg_name" | grep -qi "$keyword"; then
                menu_items+=("$pkg_name" "$display")
            fi
        done <<< "$installed_pkgs"
        
        if [ ${#menu_items[@]} -eq 0 ]; then
            show_msgbox "搜索卸载" "没有匹配 \"$keyword\" 的已安装软件包。"
            continue
        fi
        
        local selected
        selected=$(show_menu_sub "uninstall_result" "已安装软件 - \"$keyword\"" "${menu_items[@]}")
        local ret2=$?
        
        case $ret2 in
            0)
                if [ -n "$selected" ]; then
                    if show_yesno "确认卸载" "确定要卸载 $selected 吗？"; then
                        dialog --infobox "正在卸载 $selected ..." 4 40
                        pkg uninstall "$selected" -y 2>&1 | dialog --progressbox 20 60
                        show_msgbox "卸载完成" "软件包 $selected 已卸载。"
                    fi
                fi
                ;;
            1) continue ;;
        esac
    done
}

#===============================================================================
# proot Linux 发行版模块
#===============================================================================

proot_distro_menu() {
    save_ui_node "proot_distro"
    
    # 自动安装 proot-distro
    if ! command -v proot-distro &>/dev/null; then
        (
            echo "0"
            echo "正在安装 proot-distro..."
            pkg install proot-distro -y >/dev/null 2>&1
            echo "100"
        ) | dialog --gauge "安装 proot-distro" 8 60 0
    fi
    
    local choice
    choice=$(show_menu_sub "proot_distro" "proot Linux 发行版" \
        "ubuntu" "Ubuntu" \
        "alpine" "Alpine" \
        "debian" "Debian")
    local ret=$?
    
    case $ret in
        0)
            save_menu_pos "proot_distro" "$choice"
            # 检查是否已有该发行版实例：有则进管理，无则进安装
            local has_instance=false
            if [ -f "$PROOT_MAP_FILE" ]; then
                while IFS='=' read -r name dtype; do
                    [ -z "$name" ] && continue
                    [ "$dtype" = "$choice" ] && has_instance=true && break
                done < "$PROOT_MAP_FILE"
            fi
            if $has_instance; then
                proot_distro_manage "$choice"
            else
                proot_distro_install "$choice"
            fi
            ;;
        1) main_menu ;;
    esac
}

proot_distro_install() {
    local distro="$1"
    local force="${2:-false}"  # true=跳过已有实例检查
    
    save_ui_node "proot_install_$distro"
    
    # 检查是否已安装过该类型（非强制模式）
    if ! $force && [ -f "$PROOT_MAP_FILE" ]; then
        local existing=""
        while IFS='=' read -r name dtype; do
            [ "$dtype" = "$distro" ] && existing="$name" && break
        done < "$PROOT_MAP_FILE"
        if [ -n "$existing" ]; then
            proot_distro_manage "$distro"
            return
        fi
    fi
    
    local custom_name
    custom_name=$(show_inputbox "安装 $distro" "为 $distro 输入一个自定义名称" "$distro")
    local ret=$?
    
    case $ret in
        0) ;;
        1) proot_distro_menu; return ;;
    esac
    if [ -z "$custom_name" ]; then
        proot_distro_menu
        return
    fi
    
    local err_log="$PYG_DIR/proot_install_err"
    local rc_file="$PYG_DIR/install_rc"
    (
        echo "0"
        echo "正在安装 $distro (名称: $custom_name)..."
        proot-distro install "$distro" --name "$custom_name" >"$err_log" 2>&1
        echo "$?" > "$rc_file"
        echo "100"
    ) | dialog --gauge "安装 $distro 发行版" 8 60 0
    
    local rc
    rc=$(cat "$rc_file" 2>/dev/null)
    rm -f "$rc_file"
    
    if [ "$rc" != "0" ]; then
        show_msgbox "安装失败" "$(cat "$err_log" 2>/dev/null)"
        rm -f "$err_log"
        proot_distro_menu
        return
    fi
    rm -f "$err_log"
    
    ensure_pyg_dir
    if [ ! -f "$PROOT_MAP_FILE" ]; then
        touch "$PROOT_MAP_FILE"
    fi
    echo "${custom_name}=${distro}" >> "$PROOT_MAP_FILE"
    
    show_msgbox "安装完成" "$distro 发行版已安装为: $custom_name"
    proot_distro_manage "$distro"
}

proot_distro_manage() {
    local filter_distro="${1:-}"
    
    save_ui_node "proot_manage"
    
    local menu_items=()
    
    if [ -f "$PROOT_MAP_FILE" ]; then
        while IFS='=' read -r name dtype; do
            [ -z "$name" ] && continue
            if [ -n "$filter_distro" ] && [ "$dtype" != "$filter_distro" ]; then
                continue
            fi
            menu_items+=("$name" "$dtype - $name")
        done < "$PROOT_MAP_FILE"
    fi
    
    local title="已安装的发行版"
    if [ -n "$filter_distro" ]; then
        title="$filter_distro 发行版管理"
    fi
    
    menu_items+=("new_install" "→ 新安装")
    if [ ${#menu_items[@]} -eq 1 ]; then
        # 仅剩"新安装"选项，直接进入安装流程
        if [ -n "$filter_distro" ]; then
            proot_distro_install "$filter_distro" true
        else
            local new_distro
            new_distro=$(show_menu_sub "new_distro_type" "选择发行版类型" \
                "ubuntu" "Ubuntu" \
                "alpine" "Alpine" \
                "debian" "Debian")
            local ret_n=$?
            case $ret_n in
                0) [ -n "$new_distro" ] && proot_distro_install "$new_distro" true ;;
                1) proot_distro_menu ;;
            esac
        fi
        return
    fi
    local choice
    choice=$(show_menu_sub "proot_manage" "$title" "${menu_items[@]}")
    local ret=$?
    
    case $ret in
        0)
            if [ "$choice" = "new_install" ]; then
                if [ -n "$filter_distro" ]; then
                    proot_distro_install "$filter_distro" true
                else
                    local new_distro
                    new_distro=$(show_menu_sub "new_distro_type" "选择发行版类型" \
                        "ubuntu" "Ubuntu" \
                        "alpine" "Alpine" \
                        "debian" "Debian")
                    local ret_n=$?
                    case $ret_n in
                        0) [ -n "$new_distro" ] && proot_distro_install "$new_distro" true ;;
                        1) proot_distro_manage ;;
                    esac
                fi
            elif [ -n "$choice" ]; then
                save_menu_pos "proot_manage" "$choice"
                proot_distro_operations "$choice"
            fi
            ;;
        1) proot_distro_menu ;;
    esac
}

proot_distro_operations() {
    local container_name="$1"
    
    save_ui_node "proot_ops_$container_name"
    
    local distro_type=""
    if [ -f "$PROOT_MAP_FILE" ]; then
        distro_type=$(grep "^${container_name}=" "$PROOT_MAP_FILE" | head -1 | cut -d'=' -f2)
    fi
    
    local title="${distro_type:-发行版} - $container_name"
    
    local choice
    choice=$(show_menu_sub "proot_ops_$container_name" "$title" \
        "enter"     "进入系统" \
        "clone"     "克隆系统" \
        "shortcut"  "创建快捷方式" \
        "rename"    "重命名" \
        "delete"    "删除系统" \
        "backup"    "备份系统")
    local ret=$?
    
    case $ret in
        0)
            save_menu_pos "proot_ops_$container_name" "$choice"
            case "$choice" in
                enter)
                    clear
                    proot-distro login "$container_name"
                    ;;
                clone)
                    proot_clone "$container_name" "$distro_type"
                    ;;
                shortcut)
                    proot_shortcut "$container_name"
                    ;;
                rename)
                    proot_rename "$container_name" "$distro_type"
                    ;;
                delete)
                    proot_delete "$container_name" "$distro_type"
                    ;;
                backup)
                    proot_backup "$container_name"
                    ;;
            esac
            ;;
        1) proot_distro_manage "$distro_type" ;;
    esac
}

proot_rename() {
    local old_name="$1"
    local distro_type="$2"
    
    local new_name
    new_name=$(show_inputbox "重命名" "输入新的名称（当前: $old_name）" "$old_name")
    local ret=$?
    
    if [ $ret -ne 0 ] || [ -z "$new_name" ] || [ "$new_name" = "$old_name" ]; then
        proot_distro_operations "$old_name"
        return
    fi
    
    if [ -f "$PROOT_MAP_FILE" ] && grep -q "^${new_name}=" "$PROOT_MAP_FILE" 2>/dev/null; then
        show_msgbox "错误" "名称 $new_name 已存在！"
        proot_distro_operations "$old_name"
        return
    fi
    
    local proot_dir="$PREFIX/var/lib/proot-distro/containers"
    if [ -d "$proot_dir/$old_name" ]; then
        mv "$proot_dir/$old_name" "$proot_dir/$new_name"
    fi
    
    if [ -f "$PROOT_MAP_FILE" ]; then
        sed -i "s/^${old_name}=/${new_name}=/" "$PROOT_MAP_FILE"
    fi
    
    show_msgbox "重命名成功" "已将 $old_name 重命名为 $new_name"
    proot_distro_operations "$new_name"
}

# 创建快捷方式：rootfs/root → /data/data/com.termux/files/<名称>-<类型>
proot_shortcut() {
    local container_name="$1"
    local rootfs="$PREFIX/var/lib/proot-distro/containers/$container_name/rootfs/root"
    
    # 读取发行版类型
    local distro_type="$container_name"
    if [ -f "$PROOT_MAP_FILE" ]; then
        distro_type=$(grep "^${container_name}=" "$PROOT_MAP_FILE" | head -1 | cut -d'=' -f2)
        [ -z "$distro_type" ] && distro_type="$container_name"
    fi
    local link_target="$HOME/${container_name}-${distro_type}"
    
    if [ ! -d "$rootfs" ]; then
        show_msgbox "错误" "目录不存在: $rootfs"
        proot_distro_operations "$container_name"
        return
    fi
    
    if [ -L "$link_target" ] || [ -e "$link_target" ]; then
        if ! show_yesno "覆盖确认" "快捷方式已存在: $link_target\n是否覆盖？"; then
            proot_distro_operations "$container_name"
            return
        fi
        rm -f "$link_target"
    fi
    
    ln -s "$rootfs" "$link_target" 2>/dev/null
    if [ -L "$link_target" ]; then
        show_msgbox "快捷方式" "已创建: $link_target → $rootfs"
    else
        show_msgbox "失败" "无法创建快捷方式"
    fi
    proot_distro_operations "$container_name"
}

proot_clone() {
    local container_name="$1"
    local distro_type="$2"
    
    local new_name
    new_name=$(show_inputbox "克隆系统" "输入新系统的名称（不可与已有的重名）" "")
    local ret=$?
    
    if [ $ret -ne 0 ] || [ -z "$new_name" ]; then
        proot_distro_operations "$container_name"
        return
    fi
    
    if [ -f "$PROOT_MAP_FILE" ] && grep -q "^${new_name}=" "$PROOT_MAP_FILE" 2>/dev/null; then
        show_msgbox "错误" "名称 $new_name 已存在！"
        proot_distro_operations "$container_name"
        return
    fi
    
    local backup_file="/tmp/${container_name}_clone_$$.tar.xz"
    (
        echo "0"
        echo "正在备份 $container_name ..."
        proot-distro backup "$container_name" --output "$backup_file" >/dev/null 2>&1
        echo "40"
        echo "创建新系统目录..."
        local proot_dir="$PREFIX/var/lib/proot-distro/containers"
        mkdir -p "$proot_dir/$new_name"
        echo "60"
        echo "正在解压到新系统..."
        tar -xf "$backup_file" -C "$proot_dir/$new_name" --strip-components=1 2>/dev/null || \
            tar -xf "$backup_file" -C "$proot_dir/$new_name" 2>/dev/null
        echo "90"
        rm -f "$backup_file"
        echo "100"
    ) | dialog --gauge "克隆系统 $container_name → $new_name" 8 60 0
    
    ensure_pyg_dir
    echo "${new_name}=${distro_type}" >> "$PROOT_MAP_FILE"
    
    show_msgbox "克隆完成" "已克隆 $container_name 为 $new_name"
    proot_distro_operations "$container_name"
}

proot_backup() {
    local container_name="$1"
    
    local backup_file="$PYG_DIR/${container_name}_backup_$(date +%Y%m%d-%H%M%S).tar.xz"
    
    (
        echo "0"
        echo "正在备份 $container_name ..."
        proot-distro backup "$container_name" --output "$backup_file" >/dev/null 2>&1
        echo "100"
    ) | dialog --gauge "备份 $container_name" 8 60 0
    
    show_msgbox "备份完成" "备份文件保存于: $backup_file"
    proot_distro_operations "$container_name"
}

proot_delete() {
    local container_name="$1"
    local distro_type="$2"
    
    if ! show_yesno "确认删除" "确定要删除 $container_name 吗？此操作不可恢复！"; then
        proot_distro_operations "$container_name"
        return
    fi
    
    dialog --infobox "正在删除 $container_name ..." 4 40
    proot-distro remove "$container_name" >/dev/null 2>&1
    
    if [ -f "$PROOT_MAP_FILE" ]; then
        sed -i "/^${container_name}=/d" "$PROOT_MAP_FILE"
    fi
    
    show_msgbox "删除完成" "已删除 $container_name"
    proot_distro_menu
}

#===============================================================================
# 常用一键配置模块
#===============================================================================

common_config_menu() {
    save_ui_node "common_config"
    
    show_msgbox "常用一键配置" "该模块暂无内容，预留扩展。\n\n敬请期待..."
    main_menu
}

#===============================================================================
# 主菜单
#===============================================================================
main_menu() {
    save_ui_node "main"
    
    local choice
    choice=$(show_menu_main "main" "ZT 一键脚本" \
        "env"     "代码环境管理" \
        "pkg"     "安装 / 卸载" \
        "proot"   "proot Linux 发行版" \
        "config"  "常用一键配置")
    local ret=$?
    
    case $ret in
        0)
            save_menu_pos "main" "$choice"
            case "$choice" in
                env)    env_scope_menu ;;
                pkg)    install_uninstall_menu ;;
                proot)  proot_distro_menu ;;
                config) common_config_menu ;;
            esac
            ;;
        3|1|255) exit_script ;;
    esac
}

#===============================================================================
# 脚本入口
#===============================================================================
main() {
    check_dialog
    ensure_pyg_dir
    save_cur_dir "$PWD"
    
    # 自引导：每次启动创建新副本并确保 t 命令可用
    local self="$0"
    local target="$PYG_DIR/t.sh"
    cp "$self" "$target" 2>/dev/null
    chmod +x "$target" 2>/dev/null
    local bashrc="$HOME/.bashrc"
    if ! grep -q "alias t=" "$bashrc" 2>/dev/null && ! grep -q "function t" "$bashrc" 2>/dev/null; then
        echo "alias t='bash $target'" >> "$bashrc"
    fi
    
    # 首次进入时根据上次 UI 节点恢复
    local last_node
    last_node=$(read_ui_node)
    [ -z "$last_node" ] && last_node="main"
    
    case "$last_node" in
        env_scope|env_op_*|env_select_*|switch_*|download_env*|uninstall_env*|rename_env*)
            env_scope_menu ;;
        install_uninstall|search_install|search_uninstall)
            install_uninstall_menu ;;
        proot_distro|proot_install_*|proot_manage|proot_ops_*)
            proot_distro_menu ;;
        common_config)
            common_config_menu ;;
        *)
            main_menu ;;
    esac
    
    # 主循环：任何操作完成后回到主菜单，永不退出（除非按退出键触发 exit_script）
    while true; do
        main_menu
    done
}

main "$@"
