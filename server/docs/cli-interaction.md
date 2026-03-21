# CLI 交互与跨平台行编辑

## 问题

- **乱码**：Windows 控制台默认 GBK，直接读入后当 UTF-8 发 API 会报错；错误信息 UTF-8 在 GBK 终端显示乱码。
- **退格/删除键**：`std::getline` 在部分终端下会得到 `^H`/DEL 字面字符而非删除效果，需要后处理（如 `strip_backspace`），且多字节字符（如中文）退格可能不对。
- **跨平台**：不同平台 TTY、编码、键码不一致，手写逻辑难以兼顾。

## 通用 CLI 行编辑库（推荐）

用成熟的 **readline 替代库** 可统一解决上述问题：

| 库 | 协议 | 特点 | 适用 |
|---|------|------|------|
| **linenoise-ng** | BSD | C、UTF-8、Windows、自包含、可 FetchContent | ✅ 已集成 |
| Crossline | MIT | 零配置、跨平台 | 备选 |
| replxx | BSD | C++、语法高亮/提示、较重 | 需要高级编辑时 |
| GNU readline | GPL | 功能全但 GPL、Windows 需额外层 | 一般不选 |

HiClaw 已集成 **linenoise-ng**（默认开启）：

- **默认**：`HICLAW_USE_LINENOISE=ON`，使用 **third_party/linenoise-ng** 中的源码（来自 [arangodb/linenoise-ng](https://github.com/arangodb/linenoise-ng)），构建时无需拉取网络。交互式 config（`config>` 及添加 model 时的各字段输入）在 TTY 下使用 linenoise，否则回退到 `std::getline`。
- **关闭**：`-DHICLAW_USE_LINENOISE=OFF` 则不编译 linenoise，全部使用 `std::getline` + `strip_backspace`。

## 行为说明

- **TTY**（直接运行 `hiclaw config`）：用 linenoise 读行，退格/左右键/UTF-8 由库处理。
- **非 TTY**（管道/重定向）：用 `std::getline`，与原有行为一致。
- **编码**：linenoise-ng 在 Windows 上按 UTF-8 处理行内容；若控制台为 GBK，仍需在发 API 前对用户输入做 CP_ACP→UTF-8 转换（agent 中 `to_utf8` 已做）。

## 可选编译

- 默认：`HICLAW_USE_LINENOISE=ON`，使用 `hiclaw/third_party/linenoise-ng`，无需网络。
- 关闭：`-DHICLAW_USE_LINENOISE=OFF`，全部使用 `std::getline` + `strip_backspace`。
