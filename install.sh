#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# 初始化日志系统
exec > >(tee -a install.log) 2>&1
echo "=== KDE Plasma 安装开始于 $(date) ==="

# 1. 修复环境问题
export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
echo "修复库路径: $LD_LIBRARY_PATH"

# 2. 更新系统和安装依赖
echo "更新系统并安装依赖..."
pkg update -y
pkg install -y x11-repo
pkg upgrade -y

# 修复可能存在的库冲突
pkg install -y libc++ libandroid-support

# 3. 安装必要工具
required_pkgs=(aria2 p7zip tar xz-utils coreutils)
for pkg in "${required_pkgs[@]}"; do
    if ! command -v "$pkg" &>/dev/null; then
        echo "正在安装 $pkg..."
        pkg install -y "$pkg" || {
            echo "安装 $pkg 失败!"
            exit 1
        }
    fi
done

# 4. 下载函数（带重试和多个镜像源）
download_with_retry() {
    local file=$1
    local sha=$2
    local mirrors=(
        "https://mirror.ghproxy.com/github.com/kde-yyds/termux-x11-plasma-image/releases/download/v1.0/$file"
        "https://github.com/kde-yyds/termux-x11-plasma-image/releases/download/v1.0/$file"
    )
    
    echo "校验文件 $file..."
    echo "$sha  $file" > "$file.sha1"
    
    if sha1sum -c "$file.sha1" &>/dev/null; then
        echo "$file 已存在且校验通过"
        return 0
    fi
    
    for mirror in "${mirrors[@]}"; do
        echo "尝试从 $mirror 下载..."
        if aria2c -x 16 -s 16 "$mirror"; then
            if sha1sum -c "$file.sha1"; then
                echo "$file 下载并校验成功"
                return 0
            else
                echo "文件校验失败，将重新下载"
                rm -f "$file"
            fi
        fi
    done
    
    echo "无法下载 $file"
    return 1
}

# 5. 下载和解压 termux.tar.xz
echo "处理 termux.tar.xz..."
download_with_retry "termux.tar.xz" "5b34da13d9c7876183c6ec2446214edac2d6d470" || exit 1

if [[ -f termux.tar.xz ]]; then
    echo "解压 termux.tar.xz..."
    tar -xvf termux.tar.xz -C /data/data/com.termux/files/ || {
        echo "解压失败!"
        exit 1
    }
fi

# 6. 下载和解压 plasma 分卷
plasma_parts=(
    "plasma.tar.xz.7z.001:25d2ff2bf287009bdbda8b4871f6431d30a6450e"
    "plasma.tar.xz.7z.002:38bc1a0aa1c29b066d0f9cb47d94b799c65ed313"
    "plasma.tar.xz.7z.003:303f41019d2a3f0d2fe0aeef7063ff7c301ed4e5"
    "plasma.tar.xz.7z.004:cc700b4cae43ddaeddfd5ed03974a97ebb2f68a7"
    "plasma.tar.xz.7z.005:c712ff34edf0ef97c12c72c57b14bf66ca22e51a"
)

echo "开始下载 Plasma 组件..."
for part in "${plasma_parts[@]}"; do
    IFS=':' read -r file sha <<< "$part"
    download_with_retry "$file" "$sha" || exit 1
done

# 7. 合并和解压 Plasma
if [[ -f plasma.tar.xz.7z.005 && ! -f plasma.tar.xz ]]; then
    echo "合并 Plasma 分卷..."
    7z x plasma.tar.xz.7z.001 || {
        echo "分卷合并失败!"
        exit 1
    }
fi

if [[ -f plasma.tar.xz && ! -d /data/data/com.termux/files/home/containers ]]; then
    echo "解压 Plasma..."
    tar -xvf plasma.tar.xz -C /data/data/com.termux/files/home/ || {
        echo "Plasma 解压失败!"
        exit 1
    }
fi

# 8. 创建启动脚本
echo "创建启动脚本..."
cat > /data/data/com.termux/files/usr/bin/plasma <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

# 启动 X11 服务器
termux-x11 :1 &
sleep 2

# 启动容器
/data/data/com.termux/files/home/containers/scripts/debianbullseye_xrenderkwin_xfce4-panel.sh &
/data/data/com.termux/files/home/containers/scripts/archlinuxarm_plasma.sh
EOF

chmod +x /data/data/com.termux/files/usr/bin/plasma

# 9. 修复 LD_PRELOAD 问题
echo "修复 LD_PRELOAD 问题..."
sed -i 's/env LD_PRELOAD=/env -u LD_PRELOAD/g' /data/data/com.termux/files/home/containers/scripts/*

# 10. 清理临时文件
echo "清理临时文件..."
rm -vf termux.tar.xz termux.tar.xz.sha1 plasma.tar.xz* plasma.tar.xz.7z.*

echo "=== 安装成功完成 ==="
echo "输入 'plasma' 并回车即可启动 KDE Plasma"
exit 0
