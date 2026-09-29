# 烟雨江湖 x86 安卓 7 云手机镜像

**简体中文** | [English](README.en.md) | [实现概览](OVERVIEW.md)

为《烟雨江湖》x86 运行环境准备的 Android 7 云手机。`image` 和 `dev` 都运行 **Android + 网页两个容器**，使用同一套 Compose 配置。默认 4 vCPU、6 GiB 内存、720×1280、上海时区，首次启动生成并输出随机管理员密码。

检索关键词：烟雨江湖、烟雨江湖 x86、安卓7云手机、Android 7.1.1、API 25、x86_64、Docker、KVM、Houdini、Magisk、网页控制。

本项目不包含游戏 APK。Android 客体是 x86_64；安装 ARM APK 时仍需要 Houdini 转译，性能与原生 x86 APK 不同。

## 快速开始

需要 Linux x86_64、Docker Engine、Docker Compose 插件和 `/dev/kvm`。建议至少 4 个逻辑 CPU、12 GiB 内存、30 GiB 磁盘；虚拟机宿主需支持嵌套虚拟化。

新机器先检查，再按需安装依赖：

```bash
chmod +x check-host.sh install-deps.sh android7.sh
sudo ./check-host.sh
# 缺少依赖时安装，然后重新检查
./install-deps.sh --dry-run
sudo ./install-deps.sh
sudo ./check-host.sh
```

首次检查缺少 Docker 时会报错，这是正常的；硬件虚拟化问题需要在 BIOS 或云服务商侧解决。检查通过后继续下面的镜像启动步骤。

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

本机打开 `http://localhost:8000`，远程打开 `http://服务器IP:8000`，使用脚本输出的 `admin` 和初始密码登录，再点击设备卡片的 `connect`。默认监听所有 IPv4 地址；远程连接还需要服务器网络和防火墙允许对应端口。脚本不创建隧道。脚本在发布网页端口前完成密码初始化。

```bash
./android7.sh image status
./android7.sh image log
./install-apk.sh -c yanyu-android7 /path/to/game.apk
```

## 独立的镜像部署脚本

`android7-image.sh` 可单独交付，不依赖 `android7.sh`。它包含主脚本 `image` 的部署和管理功能，**不含构建、推送和迁移**。仍运行 Android + 网页两个容器，默认 8000 端口、允许远程连接且强制登录。

```bash
# 首次下载缺少的镜像并启动；pull 与 start 的行为相同
sudo ./android7-image.sh start
sudo ./android7-image.sh status

# 如果只想下载，不启动
sudo ./android7-image.sh download
```

**新脚本需要子命令。** 直接执行 `./android7-image.sh` 会显示帮助。`start` / `pull` 优先复用本地镜像，仅拉取缺失镜像；`download` 每次向远程仓库检查两个标签，不创建或启动容器，也不更改已保存的部署配置。

| 命令 | 用途 |
| --- | --- |
| `start` / `pull` | 拉取缺少的镜像，准备登录密码，启动双容器 |
| `download` | 仅拉取两个远程镜像，固定下载 `linux/amd64` 平台 |
| `status` / `log` | 查看状态 / 持续查看日志，Ctrl+C 只退出日志查看 |
| `stop` / `restart` | 停止 / 重启；保留数据 |
| `down` | 移除容器和网络，保留两个数据卷 |
| `password` | 隐藏输入新密码两次，修改或重置 admin 密码，并撤销旧会话 |
| `reset` | 输入 YES 后重置安卓并重新启动，保留网页登录账号和密码 |
| `purge` | 输入 YES 后删除容器及全部安卓、网页登录数据；保留镜像，不重启 |
| `help` | 查看帮助 |

首次启动生成并显示一次独立的 32 位复杂密码，已有密码不会被覆盖。密码会在开放网页端口前初始化，兼容现有双容器镜像。忘记或错过密码时，保持服务运行后执行 `sudo ./android7-image.sh password`。

```bash
# 安全模式只允许本机连接；恢复默认远程连接
sudo ./android7-image.sh start --safe
sudo ./android7-image.sh start --public

# 自定义镜像必须成对提供；启动后记住这两个标签
sudo ./android7-image.sh start myrepo/phone:1.2-android myrepo/phone:1.2-web

# 仅下载自定义版本；之后 start 也要明确传入这一对标签才会切换
sudo ./android7-image.sh download myrepo/phone:1.2-android myrepo/phone:1.2-web
```

登录验证与访问范围是两件事。远程画面传输可能需要 HTTPS 入口；脚本不配置反向代理、隧道或端口转发。

独立脚本与主脚本在**同一文件夹**使用同一份 `.android7-image.env`、`compose.image.yml`、容器名和数据卷，主脚本创建的 image 部署可以直接管理。不要把配置文件丢掉，也不要同时运行两个管理脚本；新脚本会阻止本目录内多个自身修改操作并发。配置及目录不匹配、其他容器占用数据卷时，会拒绝相关操作。

如果已按旧 PDF 的 `docker run` 命令创建容器，新脚本不会静默接管。先确认这两个容器确实是本项目的手动部署，且 `/data` 分别使用 `yanyu-android7-data`、`yanyu-ws-scrcpy-data`，再执行一次：

```bash
sudo docker inspect -f '{{range .Mounts}}{{println .Destination .Name}}{{end}}' yanyu-android7 yanyu-ws-scrcpy-web
# 确认上述数据卷名称与说明一致后再执行；仅移除容器，保留数据卷
sudo docker stop yanyu-ws-scrcpy-web yanyu-android7
sudo docker rm yanyu-ws-scrcpy-web yanyu-android7
sudo ./android7-image.sh start
```

如果名称或挂载不同，先用原部署方式管理，不要删除或覆盖它的数据。`download` 失败会保留已经拉取的内容；私有仓库请用与脚本相同的 Docker 用户完成 `docker login`。

## 宿主机检查与依赖安装

两个独立脚本均提供 `--help`，统一安装或检查 Docker、Compose、Buildx、Python 3、curl、7z、SHA256 等完整工具，不区分 image/dev 模式。默认检查 8000 和 8001 两个端口，不会启动云手机或修改云手机数据。

| 脚本 | 用途 |
| --- | --- |
| `check-host.sh` | 检查 Linux/x86_64、CPU、内存、项目与 Docker 数据目录磁盘、Docker/Compose、KVM、网页端口 |
| `install-deps.sh` | 在 Ubuntu 22.04/24.04/26.04 或 Debian 12/13（x86_64、systemd）上安装缺少的依赖 |

```bash
# 统一安装并检查完整依赖，无需选择运行或构建模式
sudo ./install-deps.sh
sudo ./check-host.sh

# 检查自定义数据目录和端口，不会修改部署配置
sudo ./check-host.sh --disk-path /mnt/cloudphone --port 8000
```

检查脚本不联网、不下载、不启动容器，实际调用 KVM 接口创建并立即关闭一个无 CPU/内存的临时虚拟机。Python 3 用于这项验证；缺失或权限不足都会报告未通过，不会仅凭 `/dev/kvm` 存在判定可用。不支持远程 Docker、Docker Desktop 或 rootless Docker。普通用户运行时仅尝试无需密码的 sudo，不弹出密码提示；完整检查建议使用上面的 sudo 命令。

`FAIL` 表示必要条件缺失或无法验证；`WARN` 表示资源建议未满足或端口已占用（可能是当前云手机）。退出码 `0` 表示必要检查通过，`1` 表示存在失败，`2` 表示参数错误。**有警告时仍可能返回 0，请阅读报告。** 单台云手机建议 4 个逻辑 CPU、12 GiB 总内存、启动前 8 GiB 可用内存；磁盘检查以 30 GiB 可用空间为建议线；自行构建镜像时，为下载及构建缓存建议预留 60 GiB。单独配置的 containerd 镜像存储盘需要另外确认容量。检查不保证游戏性能、镜像下载可达性、HTTPS 或外网画面正常。

安装脚本提供无修改的 `--dry-run` 预览；使用 Docker 官方签名 APT 源，新建源时核验 Docker 签名公钥指纹，由 APT 验证软件包签名链及哈希。已有官方源会复用，不覆盖管理员配置。宿主依赖安装版本不属于云手机镜像的来源锁定范围。

安装方式参考 Docker 官方文档：[Ubuntu](https://docs.docker.com/engine/install/ubuntu/)、[Debian](https://docs.docker.com/engine/install/debian/)。

已有完整 Docker 安装会保留；缺少组件时如遇发行版 Docker、独立 containerd 等冲突包，脚本会停止并提示，不自动卸载。只请求安装缺少的软件包，不过 APT 可能为了依赖关系更新相关包。脚本启用 Docker 开机启动并启动服务；缺少 `/dev/kvm` 时尝试加载 Intel/AMD KVM 模块，不替代 BIOS/嵌套虚拟化设置。不会自动加入 docker 用户组、配置防火墙或隧道。安装完成后重新运行检查，再启动云手机。

## 两种模式

| 项目 | `image` | `dev` |
| --- | --- | --- |
| 运行结构 | Android + 网页两个容器 | 相同 |
| 容器名 | `yanyu-android7` + `yanyu-ws-scrcpy-web` | `yanyu-android7-dev` + `yanyu-ws-scrcpy-web-dev` |
| 网络 | 网页共享 Android 网络命名空间，发布宿主 8000 | 相同结构，发布宿主 8001 |
| 访问范围 | 默认 `0.0.0.0`；安全模式 `127.0.0.1` | 相同 |
| 参数、健康检查、启动顺序 | 共用生成器 | 相同 |
| 镜像来源 | 拉取或复用已经构建的两个镜像 | 从固定来源构建 |
| 系统文件 | 内置于 Android 镜像 | `patched/` 只读挂载 |
| Android 状态 | `yanyu-android7-data` 卷 | `docker-state-dev/` |
| 网页状态 | `yanyu-ws-scrcpy-data` 卷 | `ws-scrcpy-data-dev/` |

image 容器名为 `yanyu-android7` 和 `yanyu-ws-scrcpy-web`；dev 分别加上 `-dev` 后缀。两种模式的数据分别保存，image 使用 8000 端口，dev 使用 8001 端口，资源足够时可以同时运行。以下是只保留一种运行模式的切换示例，`down` 会移除容器并保留数据。脚本仍检查容器归属，切换不会自动迁移数据。

```bash
# image → dev
./android7.sh image down
./android7.sh dev start

# dev → image
./android7.sh dev down
./android7.sh image start

# image 模式：可省略容器名
./install-apk.sh /path/to/game.apk

# dev 模式：指定带 -dev 后缀的容器名
./install-apk.sh -c yanyu-android7-dev /path/to/game.apk
```

旧 dev 容器（包括曾使用无后缀名称的版本）仍可通过已保存的配置管理；执行 `dev down` 后再 `dev start` 即使用带 `-dev` 后缀的名称，原有目录数据保留。

## 数据目录与迁移

image 使用独立 Docker 数据卷 `yanyu-android7-data`、`yanyu-ws-scrcpy-data`；dev 使用项目目录 `docker-state-dev/`、`ws-scrcpy-data-dev/`，不会共享运行数据。

```bash
# 旧 dev 目录 docker-state/、ws-scrcpy-data/ → 带 -dev 后缀的新目录
./android7.sh dev migrate
./android7.sh dev start

# image → dev（目标 dev 目录必须为空）
./android7.sh data migrate image dev
./android7.sh dev start

# dev → image（目标 image 数据卷必须为空或不存在）
./android7.sh data migrate dev image
./android7.sh image start
```

每次只选择所需的迁移方向。迁移会停止相关容器，复制 Android 和网页的完整数据，保留应用、账号、密码、文件权限及稀疏磁盘；**源数据保留，非空目标拒绝覆盖**。迁移不构建、不推送、不自动启动，完成后执行目标模式的 `start`。如果还有其他运行中的容器引用数据，会拒绝复制。

检测到旧 dev 数据而新目录为空时，脚本会提示先运行 `dev migrate`，避免误建空手机。迁移后旧目录作为备份保留；标记文件 `.android7-legacy-dev-migrated` 表示不再自动检查这些备份，后续 `dev purge` 只清理新目录。

复制中断时，会留下 `.android7-migration-目标模式.pending` 并阻止目标启动。源数据保持不变；先检查目标，再使用目标模式的 `purge` 丢弃不完整副本，随后重新迁移。迁移复制的是同一份 Android 身份及网页登录信息；两边之后各自保存，不自动同步。

## 网页初始密码与修改密码

首次启动时，脚本自动生成一个 **32 字符随机复杂密码**（包含大小写字母、数字及符号），并在终端输出用户名 `admin` 和密码；直接用它登录即可。每份网页数据单独生成，不使用固定共享密码，不把密码写进镜像、Compose 或 `.env`。初始化在不发布端口的临时容器内完成，兼容已有的双容器发布镜像。

**已有密码不会被覆盖**。正常重启、Android `reset` 和数据迁移会保留网页登录账号。初始密码只输出一次；用于交付的临时密码文件位于网页 `/data/.android7-initial-password`，权限为 `0600`，成功输出后删除。错过输出或忘记密码，可在宿主机执行：

```bash
# 修改或重置 image 模式的 admin 密码
./android7.sh image password

# 修改或重置 dev 模式的 admin 密码
./android7.sh dev password
```

对应模式需已启动。命令要求输入两次新密码（8～128 字符），输入不回显，也不把密码放进命令参数或环境变量；无需提供旧密码，依赖宿主机的 Docker 管理权限。修改后会退出该管理员已有的登录会话，不影响 Android 应用数据。两种模式的网页账号分别保存。

## 网页访问与安全模式

默认允许通过服务器 IP 访问，但仍须使用生成的密码登录。“安全模式”只改变监听地址，不关闭登录验证，也不自动启用 HTTPS。

| 模式 | 默认远程地址 | 安全模式本机地址 |
| --- | --- | --- |
| image | `http://服务器IP:8000` | `http://127.0.0.1:8000` |
| dev | `http://服务器IP:8001` | `http://127.0.0.1:8001` |

```bash
# 仅限本机访问
./android7.sh image start --safe
./android7.sh dev start --safe

# 恢复通过服务器 IP 访问
./android7.sh image start --public
./android7.sh dev start --public
```

访问模式分别保存在 `.android7-image.env` 和 `.android7.env`，之后不带选项的 `start` 会保留选择。未保存选择时默认 `public`。修改绑定需要执行 `start`，仅 `restart` 不会更新端口；重建相关容器会短暂中断连接，但保留应用和网页登录数据。`image pull` 同样支持这两个选项。

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
| `image password` / `dev password` | 隐藏输入新密码，修改或重置对应网页的 admin 密码 |
| `image stop` | 停止两个容器，保留数据 |
| `image restart` | 重启两个容器 |
| `image down` | 移除两个容器和网络，保留两个数据卷 |
| `image reset` | 输入 YES 后重置 Android 并重新启动两个容器，保留网页账号和密码 |
| `image purge` | 输入 YES 后移除两个容器、删除两个数据卷，不自动启动 |
| `image log` / `image status` | 两个服务的日志 / 状态 |
| `dev start` | 准备来源、构建并启动两个开发容器 |
| `dev stop` / `dev restart` / `dev down` | 管理开发容器，保留数据 |
| `dev reset` | 输入 YES 后只重置 Android 并重新启动，保留网页账号 |
| `dev purge` | 输入 YES 后移除开发容器并清空 Android/网页数据，不自动启动 |
| `dev migrate` | 将旧 dev 数据复制到带 `-dev` 后缀的空目录，保留源目录 |
| `data migrate 来源 目标` | 在 image / dev 之间复制数据，目标必须为空 |
| `dev log` / `dev status` | 开发日志 / Android 详细诊断 |

自定义镜像时，必须同时指定 Android 和网页两个引用：

```bash
./android7.sh image start myrepo/phone:android myrepo/phone:web
```

部署只使用镜像标签，不固定发布镜像的 SHA256。选择结果保存在 `.android7-image.env`，之后不带参数的 `image start` 会复用它。需要更新时先拉取新镜像，再把两个新引用显式传给 `image start`；Compose 重建相关容器并保留数据卷。

`image reset` 只删除 Android 卷内的 `avd/` 和 `android.ready`，清除游戏、应用数据、Android 账号和设置；保留网页账号、密码和所选镜像。确认后停止两个服务，清理完成再启动，不构建或推送镜像。

`purge` 永久删除游戏、应用文件、账号、设置、日志、网页密码；仅作用于所选模式。镜像、源码和下载/构建缓存保留。其他输入或输入结束会取消；若还有其他容器引用数据，清理会报错停止。下次启动创建新手机，并生成、输出新的随机密码。

旧的平级命令（如 `./android7.sh start`、`./android7.sh purge`）仍是 **dev** 命令的别名。

## 构建与发布两个镜像

构建还需要 curl、7z 和 sha256sum。主脚本只检查宿主工具，不自动安装；新机器可先执行 `sudo ./install-deps.sh`。下载来源、镜像摘要与文件哈希固定；镜像内 Ubuntu 软件包使用固定日期快照。

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

下面的 `WEB_BIND_IP=0.0.0.0` 允许通过服务器 IP 访问；安全模式改为 `WEB_BIND_IP=127.0.0.1`。

启动 Android 并等待就绪：

```bash
WEB_BIND_IP=0.0.0.0
docker run -d --name yanyu-android7 \
  --device /dev/kvm --shm-size 2g --stop-timeout 45 \
  --restart unless-stopped -p "${WEB_BIND_IP}:8000:8000" \
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

新构建的网页镜像也会在手动 Docker 部署时自动生成初始密码。网页就绪后运行以下命令查看一次；旧版镜像的手动部署仍使用网页首次设置密码流程，脚本部署则会自动处理：

```bash
docker exec --user 1000:1000 yanyu-ws-scrcpy-web \
  node /app/dist/android7-password.cjs show
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
- 新建或恢复出厂后的 Android 默认语言为**简体中文（中国）**（`zh-Hans-CN`）。首次启动会自动初始化语言并重启 Android 界面服务一次；已有数据及之后手动选择的语言不会被覆盖。dev 和 image 使用相同逻辑；已发布镜像需重新构建并部署后才包含此默认设置。
- 720×1280、320 dpi，KVM CPU 加速，SwiftShader 软件渲染，禁用 GLDMA 以规避旧内核在 6 GiB 下崩溃。
- Houdini ARM32/ARM64、Magisk 27、AOSP su；Magisk 的 ADB 守护恢复被 root 应用关闭的 adbd。
- 网页默认认证，首次自动生成 32 字符随机复杂密码，支持修改为 8～128 字符密码；使用原生密码哈希、会话和 CSRF 校验。意外断连重试，手动关闭画面不自动重连。
- 两个容器均使用 `Asia/Shanghai`，不改写 Android 客体时区。`docker exec yanyu-android7 date '+%Z %z'` 应显示 `+0800`。

```bash
# Android 诊断和安装 APK
docker exec yanyu-android7 /opt/android/status.sh
docker cp /path/to/game.apk yanyu-android7:/tmp/game.apk
docker exec yanyu-android7 adb -s emulator-5556 install -r /tmp/game.apk
docker exec yanyu-android7 rm /tmp/game.apk
```

网页打不开先看两个容器健康状态和日志；确认 image 的 8000、dev 的 8001 端口未被其他程序占用，远程访问时检查监听模式及防火墙。原密码失效或出现新的初始密码时检查网页数据卷。双容器本身不保证游戏提速，实际性能还取决于 APK 架构、渲染方式、编码和帧率。

## 项目文件

版本管理只保留 `android7.sh`、`android7-image.sh`、`install-apk.sh`、`check-host.sh`、`install-deps.sh`、中英文 README/OVERVIEW 和 `.gitignore`。脚本及帮助纯英文，说明文档按语言分开。

`docker/`、`patched/`、`downloads/`、Compose、环境文件、构建清单和运行数据均自动生成且不纳入版本管理。不要手改生成的 Compose/Dockerfile，下次运行会覆盖；请改主脚本。无需独立 `image/`、`tests/` 目录。

## 上游来源

- [Android 7 Houdini/Magisk 系统](https://github.com/xBZZZZ/android_7.1.1_x86_64_libhoudini_magisk)：固定提交 `159eb29934e09fd15e7490326c53eb47732b0f57`。
- [ws-scrcpy-web](https://github.com/bilbospocketses/ws-scrcpy-web)：固定 beta.129 镜像摘要。
- [Android Emulator](https://developer.android.com/studio/run/emulator-commandline)：固定 build 15917651。

遵守上游组件及游戏的使用、再分发条款；本项目不是游戏官方发行。
