# 烟雨江湖 x86 安卓 7 云手机镜像

**简体中文** | [English](README.en.md) | [实现概览](OVERVIEW.md)

为《烟雨江湖》x86 运行环境准备的 Android 7 云手机。`image` 和 `dev` 都运行 **Android + 网页两个容器**，使用同一套 Compose 配置。默认 4 vCPU、6 GiB 内存、720×1280、上海时区，首次访问设置管理员密码。

检索关键词：烟雨江湖、烟雨江湖 x86、安卓7云手机、Android 7.1.1、API 25、x86_64、Docker、KVM、Houdini、Magisk、网页控制。

本项目不包含游戏 APK。Android 客体是 x86_64；安装 ARM APK 时仍需要 Houdini 转译，性能与原生 x86 APK 不同。

## 快速开始

需要 Linux x86_64、Docker Engine、Docker Compose 插件和 `/dev/kvm`。建议至少 4 个逻辑 CPU、12 GiB 内存、30 GiB 磁盘；虚拟机宿主需支持嵌套虚拟化。

两个镜像放在同一仓库，以标签区分：

| 组件 | 镜像 | 容器 | 数据卷 |
| --- | --- | --- | --- |
| Android | `blueobsidian/android7-magisk-yanyujianghu:1.1-android` | `yanyu-android7` | `yanyu-android7-data` |
| 网页 | `blueobsidian/android7-magisk-yanyujianghu:1.1-web` | `yanyu-ws-scrcpy-web` | `yanyu-ws-scrcpy-data` |

**这两个新标签需要先构建或发布。旧的 `1.0` 单容器镜像不能用于新的双容器部署。**

```bash
chmod +x android7.sh
./android7.sh image pull
```

默认使用两个发布标签：本地已有就直接复用，只有本地缺少才拉取；两个镜像检查成功后自动创建两个容器。Android 健康检查通过后启动网页。部署无需 SDK、系统文件缓存或源码构建工具，但需要 Compose。

打开 `http://localhost:8000`，为 `admin` 设置密码，再点击设备卡片的 `connect`。远程继续使用自己的 8000 端口转发；脚本不创建隧道。首次初始化前不要让其他人抢先访问。

```bash
./android7.sh image status
./android7.sh image log
./install-apk.sh -c yanyu-android7 /path/to/game.apk
```

## 两种模式

| 项目 | `image` | `dev` |
| --- | --- | --- |
| 运行结构 | Android + 网页两个容器 | 相同 |
| 网络 | 网页共享 Android 网络命名空间，只发布本地 8000 | 相同 |
| 参数、健康检查、启动顺序 | 共用生成器 | 相同 |
| 镜像来源 | 拉取或复用已经构建的两个镜像 | 从固定来源构建 |
| 系统文件 | 内置于 Android 镜像 | `patched/` 只读挂载 |
| Android 状态 | `yanyu-android7-data` 卷 | `docker-state/` |
| 网页状态 | `yanyu-ws-scrcpy-data` 卷 | `ws-scrcpy-data/` |

两种模式使用不同容器和数据，但都默认占用 8000 端口，不能同时占用该端口。切换模式不会自动迁移另一种模式的数据。

## 命令

```bash
./android7.sh help
./android7.sh help image
./android7.sh help dev
```

| 命令 | 作用 |
| --- | --- |
| `image pull` / `image start` | 拉取缺失镜像并启动两个容器 |
| `image build` | 构建两个镜像，自动登录检查并推送 Docker Hub，不启动容器 |
| `image stop` | 停止两个容器，保留数据 |
| `image restart` | 重启两个容器 |
| `image down` | 移除两个容器和网络，保留两个数据卷 |
| `image purge` | 输入 YES 后移除两个容器、删除两个数据卷，不自动启动 |
| `image log` / `image status` | 两个服务的日志 / 状态 |
| `dev start` | 准备来源、构建并启动两个开发容器 |
| `dev stop` / `dev restart` / `dev down` | 管理开发容器，保留数据 |
| `dev reset` | 输入 YES 后只重置 Android 并重新启动，保留网页账号 |
| `dev purge` | 输入 YES 后移除开发容器并清空 Android/网页数据，不自动启动 |
| `dev log` / `dev status` | 开发日志 / Android 详细诊断 |

自定义镜像时，必须同时指定 Android 和网页两个引用：

```bash
./android7.sh image start myrepo/phone:android myrepo/phone:web
```

部署只使用镜像标签，不固定发布镜像的 SHA256。选择结果保存在 `.android7-image.env`，之后不带参数的 `image start` 会复用它。需要更新时先拉取新镜像，再把两个新引用显式传给 `image start`；Compose 重建相关容器并保留数据卷。

`purge` 永久删除游戏、应用文件、账号、设置、日志、网页密码；仅作用于所选模式。镜像、源码和下载/构建缓存保留。其他输入或输入结束会取消；若还有其他容器引用数据，清理会报错停止。下次启动创建新手机并重新设置密码。

旧的平级命令（如 `./android7.sh start`、`./android7.sh purge`）仍是 **dev** 命令的别名。

## 构建与发布两个镜像

构建还需要 curl、7z 和 sha256sum。脚本只检查宿主工具，不自动安装。下载来源、镜像摘要与文件哈希固定；Ubuntu 软件包使用固定日期快照。

```bash
# 默认构建并推送 1.1-android 和 1.1-web
./android7.sh image build

# 或者明确指定两个新标签
./android7.sh image build \
  blueobsidian/android7-magisk-yanyujianghu:1.2-android \
  blueobsidian/android7-magisk-yanyujianghu:1.2-web
```

默认标签构建完成后，直接运行 `./android7.sh image start` 即可。自定义标签或已有配置选择了其他版本时，按输出的 `Deploy:` 命令显式传入两个标签。构建产物摘要可能随重新构建改变，不影响按标签启动。

构建复用 `dev` 的 Android/网页基础镜像。Android 发布镜像再内置经过校验的干净系统文件；网页基础镜像直接作为网页发布镜像。不会把两个服务合并，也不会复制当前手机的账号或数据。

`image build` 构建成功后自动调用 `docker login`：Docker 会验证并复用已有凭据；没有有效登录时，按终端提示完成浏览器验证。随后依次推送 Android 和网页镜像，两个都成功才报告发布完成。自定义构建目标必须是你有推送权限的 Docker Hub `用户名/仓库:标签`。

登录取消或推送失败会报错退出，本地镜像保留；如果第一个已推送成功，也会保留在仓库中。需要单独重试发布时，可以手动执行：

```bash
docker login -u blueobsidian
docker push blueobsidian/android7-magisk-yanyujianghu:1.1-android
docker push blueobsidian/android7-magisk-yanyujianghu:1.1-web
```

发布后按两个标签部署即可，不需要填写镜像摘要。`dev start` 仍只在本地构建和启动，不推送。

## 不用脚本：完整 Docker 部署命令

先拉取两个已发布镜像，再创建两个数据卷：

```bash
ANDROID_IMAGE=blueobsidian/android7-magisk-yanyujianghu:1.1-android
WEB_IMAGE=blueobsidian/android7-magisk-yanyujianghu:1.1-web
docker info
test -e /dev/kvm
docker pull "$ANDROID_IMAGE"
docker pull "$WEB_IMAGE"
docker volume create yanyu-android7-data
docker volume create yanyu-ws-scrcpy-data
```

启动 Android 并等待就绪：

```bash
docker run -d --name yanyu-android7 \
  --device /dev/kvm --shm-size 2g --stop-timeout 45 \
  --restart unless-stopped -p 127.0.0.1:8000:8000 \
  -v yanyu-android7-data:/data "$ANDROID_IMAGE"

for attempt in $(seq 1 90); do
  health=$(docker inspect -f '{{.State.Health.Status}}' yanyu-android7)
  [ "$health" = healthy ] && break
  sleep 5
done
test "$health" = healthy
```

上一段检查成功后启动网页：

```bash
docker run -d --name yanyu-ws-scrcpy-web \
  --network container:yanyu-android7 --stop-timeout 30 \
  --restart unless-stopped -e WS_SCRCPY_ALLOW_REMOTE_ADMIN=0 \
  -v yanyu-ws-scrcpy-data:/data "$WEB_IMAGE"
```

手动 Docker 容器不归 Compose 管理，不能与脚本的同名容器混用。若改用脚本，先停止并移除这两个手动容器，保留数据卷，再运行 `image start`。手动重建 Android 容器时，网页容器也需重建以共享新的网络命名空间。

```bash
# 手动管理：停止、移除容器，保留两个数据卷
docker stop yanyu-ws-scrcpy-web yanyu-android7
docker rm yanyu-ws-scrcpy-web yanyu-android7
```

## 从旧 1.0 单容器迁移

不要把旧的 `/data/web` 直接当成新网页的 `/data` 空目录。先准备好两个新镜像，停止旧容器取得一致的数据，再保留 Android 卷、把网页状态复制到新的网页卷。旧网页依赖路径与双容器不同，需要重新初始化依赖，数据库和账号应保留。

以下命令适用于默认名称，且 **`yanyu-ws-scrcpy-data` 尚不存在** 的旧部署。若已存在，请先核查内容，不要覆盖。

```bash
# 确认是旧容器，并记录其镜像以便回滚
docker inspect yanyu-android7 --format '{{.Image}} {{json .Mounts}}'
# 确认新镜像已经就绪
docker image inspect blueobsidian/android7-magisk-yanyujianghu:1.1-android >/dev/null
docker image inspect blueobsidian/android7-magisk-yanyujianghu:1.1-web >/dev/null
# 此命令应报告该卷不存在；若已存在，停止并核查
docker volume inspect yanyu-ws-scrcpy-data
```

确认上述条件后再执行：

```bash
docker stop yanyu-android7
docker rename yanyu-android7 yanyu-android7-legacy
docker volume create yanyu-ws-scrcpy-data
docker run --rm --network none --user 0:0 --entrypoint /bin/sh \
  -v yanyu-android7-data:/old:ro -v yanyu-ws-scrcpy-data:/new \
  blueobsidian/android7-magisk-yanyujianghu:1.1-web \
  -ec 'test -f /old/web/wsscrcpy.db; test -z "$(ls -A /new)"; cp -a /old/web/. /new/; rm -rf /new/dependencies; chown -R 1000:1000 /new'
./android7.sh image start
```

验证游戏和网页登录正常后，才移除已停止的 `yanyu-android7-legacy` 容器。原 Android 卷中的旧 `web/` 保留作迁移时的账号备份；新网页使用独立卷。

若迁移失败，先运行 `image down` 停止并移除新服务，再将旧容器改回原名并启动。两个旧/新 Android 容器不能同时使用同一数据卷；保留旧容器期间，`image purge` 会因旧容器仍引用 Android 卷而拒绝删除数据卷。

## 默认功能与排查

- Android 7.1.1 / API 25 / x86_64，4 vCPU、6144 MiB 内存、8 GiB 数据分区。
- 720×1280、320 dpi，KVM CPU 加速，SwiftShader 软件渲染，禁用 GLDMA 以规避旧内核在 6 GiB 下崩溃。
- Houdini ARM32/ARM64、Magisk 27、AOSP su；Magisk 的 ADB 守护恢复被 root 应用关闭的 adbd。
- 网页默认认证，首次设置 8～128 字符管理员密码；使用原生密码哈希、会话和 CSRF 校验。意外断连重试，手动关闭画面不自动重连。
- 两个容器均使用 `Asia/Shanghai`，不改写 Android 客体时区。`docker exec yanyu-android7 date '+%Z %z'` 应显示 `+0800`。

```bash
# Android 诊断和安装 APK
docker exec yanyu-android7 /opt/android/status.sh
docker cp /path/to/game.apk yanyu-android7:/tmp/game.apk
docker exec yanyu-android7 adb -s emulator-5556 install -r /tmp/game.apk
docker exec yanyu-android7 rm /tmp/game.apk
```

网页打不开先看两个容器健康状态和日志；8000 已占用时先停止另一种部署。重新要求设密码时检查网页数据卷。双容器本身不保证游戏提速，实际性能还取决于 APK 架构、渲染方式、编码和帧率。

## 项目文件

版本管理只保留 `android7.sh`、`install-apk.sh`、中英文 README/OVERVIEW 和 `.gitignore`。脚本及帮助纯英文，说明文档按语言分开。

`docker/`、`patched/`、`downloads/`、Compose、环境文件、构建清单和运行数据均自动生成且不纳入版本管理。不要手改生成的 Compose/Dockerfile，下次运行会覆盖；请改主脚本。无需独立 `image/`、`tests/` 目录。

## 上游来源

- [Android 7 Houdini/Magisk 系统](https://github.com/xBZZZZ/android_7.1.1_x86_64_libhoudini_magisk)：固定提交 `159eb29934e09fd15e7490326c53eb47732b0f57`。
- [ws-scrcpy-web](https://github.com/bilbospocketses/ws-scrcpy-web)：固定 beta.129 镜像摘要。
- [Android Emulator](https://developer.android.com/studio/run/emulator-commandline)：固定 build 15917651。

遵守上游组件及游戏的使用、再分发条款；本项目不是游戏官方发行。
