# GitHub Release 与镜像发布

状态：当前配置；本地语法、版本校验和打包检查通过不代表 GitHub 已完成发布，以 Actions 运行结果为准。

发布入口为 [Verify and Publish](https://github.com/Const-Time/chatgpt2api/actions/workflows/docker-publish.yml)，配置位于 `.github/workflows/docker-publish.yml`。

## 首次启用

1. 将工作流提交并推送到默认分支 `main`。
2. 在仓库 Actions 页面启用工作流；Fork 仓库若显示启用提示，需要仓库维护者先确认。
3. 仓库或组织的 Actions 策略需要允许工作流使用 `contents: write` 创建 Release、`packages: write` 推送 GHCR。工作流使用 GitHub 自动提供的 `GITHUB_TOKEN`，无需另设 Docker Hub 密码或 PAT。
4. 首次生成 GHCR 包后，若希望服务器免登录拉取，在包设置中检查可见性为 Public；仓库公开不等于包一定允许匿名拉取。

GitHub 的手动触发入口要求工作流存在于默认分支，详见[官方说明](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)。

## 发布已有标签

适合标签已推送但首次 Actions 未启用、没有生成发布产物的情况。

1. 打开 **Actions → Verify and Publish → Run workflow**。
2. 工作流分支选择 **main**，以使用最新的流水线配置。
3. 在 **release_tag** 中填写已存在的稳定版本标签，例如 `v3.2.4`。
4. 点击运行。流水线检出该标签的代码，校验版本并固定提交 SHA，再构建镜像；镜像任务成功后创建或更新对应 Release。

`release_tag` 留空且所选 ref 是分支时，只做验证，不创建 Release 或推送镜像。不接受分支名代替版本标签，也不会自动创建标签或提升版本。

手动发布旧标签会使用旧标签中的源码与部署配置，不包含后续提交的联合部署或其他修改。要发布新修改，先按下一节准备新版本。

## 发布新版本

准备一个新的稳定版本 `X.Y.Z`，在同一提交中保持以下位置一致：

- `VERSION`
- `pyproject.toml` 与 `uv.lock` 中项目本身的版本
- `web-vue/package.json` 与 `web-vue/package-lock.json` 中根项目版本
- `CHANGELOG.md` 中非空的 `## X.Y.Z - YYYY-MM-DD` 版本记录

提交并推送后，在该提交创建并推送 `vX.Y.Z` 标签即可自动运行。普通 `main` 推送不会触发发布；PR 只验证。不要移动已经发布的标签。

## 产物

| 产物 | 内容 |
| --- | --- |
| `chatgpt2api-app.tar.gz` | 控制台在线更新包，包含构建后的前端及更新清单 |
| `chatgpt2api-deploy.tar.gz` | 标签中已提交的部署脚本、Compose、示例配置和部署说明；包含该标签存在的联合部署目录 |
| `checksums.txt` | 两个压缩包的 SHA-256 |
| `ghcr.io/const-time/chatgpt2api` | `linux/amd64`、`linux/arm64` 多架构镜像 |

镜像标签包括 `latest`、`vX.Y.Z`、`X.Y.Z`、`X.Y`。每次发布会更新 `latest` 和对应 `X.Y`；补发旧版本也会更新这些浮动标签，已有部署如需固定版本请使用完整版本标签。

部署包只含模板，不含真实密码、数据或完整源码。使用其中的镜像部署配置；若要从源码构建，下载该标签的完整源码。运行包和部署包都来自与镜像相同的提交。

## 验证与故障处理

在 Actions 中检查 `verify`、`docker`、`release-bundle` 三个任务。`verify` 检查版本、后端编译和前端生产构建；镜像任务执行 Dockerfile 的双架构构建。

- **没有任何运行记录**：检查 Actions 是否启用，然后通过 `main` 的手动入口指定已有标签。
- **版本检查失败**：修正版本文件或版本记录，并使用正确的新标签；不要绕过校验。
- **GHCR 推送被拒绝**：检查包与仓库关联及 Actions 的包写权限。
- **镜像成功、Release 失败**：可重跑失败任务；发布不是原子事务，镜像可能已经存在。
- **下载校验**：下载两个压缩包和 `checksums.txt` 到同一目录，执行 `sha256sum -c checksums.txt`。

本仓库不跟踪本地测试源码，CI 不运行缺失的 `tests/` 或 `web-vue/tests/`；构建通过不代表真实上游调用已经验收。
