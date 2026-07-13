# SEUI — GTNH 2.9.0-beta-1 太空电梯控制台

[![GTNH](https://img.shields.io/badge/GTNH-2.9.0--beta--1-blue)](https://github.com/GTNewHorizons/GT-New-Horizons-Modpack)
[![OpenComputers](https://img.shields.io/badge/OpenComputers-1.12.44--GTNH-green)](https://github.com/GTNewHorizons/OpenComputers)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## 从 GitHub 直接安装

OC 电脑需要安装互联网卡，并允许访问 `raw.githubusercontent.com`。在 OpenOS 中执行：

```sh
wget -f https://raw.githubusercontent.com/mnaccccs/gtnh-seui/main/install.lua /tmp/seui-install.lua && /tmp/seui-install.lua
```

若 GitHub Raw 握手失败或网络较差，使用徐同鑫的 GitHub 文件镜像：

```sh
wget -f https://github.xutongxin.me/https://raw.githubusercontent.com/mnaccccs/gtnh-seui/main/install.lua /tmp/seui-install.lua && /tmp/seui-install.lua
```

安装器下载项目文件时也会自动尝试两条线路：先 GitHub Raw，失败后改走该镜像。

默认安装到 `/home/seui`。指定其他目录：

```sh
/tmp/seui-install.lua /home/seui-1.0.5
```

安装完成后先只读检查，再启动真实控制：

```sh
/home/seui/main.lua --readonly
/home/seui/main.lua --control
```

重新执行安装命令即可更新；若目标目录已有 `config.lua`，安装器会备份为 `config.lua.bak` 并**保留现有配置，不覆盖方向等本机设置**。若服务器不能访问 GitHub Raw，则仍需使用文件夹拖入方式。

一套适用于 OpenComputers Tier 3 屏幕（160×50）的触摸控制程序，同时监控/调度：

- Space Pumping Module：流体库存维持；
- Space Mining Module：矿物或处理产物库存维持；
- `level_maintainer` 目标导入；
- `setParameter` 新接口与 `setParameters` legacy 接口探测；
- 非阻塞停机→写参→读回→启机状态机；
- PUMP / MINER / SYSTEM 三页 UI。

## 文件

```text
main.lua               主程序
config.lua             用户配置
lib/                    运行模块
tests/                  主机侧测试，不必复制到 OC
```

## 安装

将整个 `seui` 目录复制到 OC 硬盘根目录，例如 `/seui/`。程序会根据 OpenOS 的 `_` 环境变量自动定位自己的模块，因此可以从任意目录运行：

```text
/seui/main.lua --simulate
/seui/main.lua --readonly
/seui/main.lua --control
```

首次必须先用 `--simulate` 看 UI，再用 `--readonly` 核对真实库存和组件。确认 SYSTEM 页参数后端、目标路由和库存都正确，最后才用 `--control`。

注意：`--readonly` 只监控和导入目标，绝不会修改钻机/矿机参数或启停机器；要让程序实际控制机器，必须运行 `--control`。当前模式会显示在 UI 顶部 `mode:` 后。

钻机页内置 2.9.0-beta-1 的全部 40 种可抽取流体、星球/气体路由和基础流量。未在请求器中配置的条目默认 `关闭/0`，不会参与调度；请求器导入会按星球/气体路由合并并启用对应条目。选中流体后可点“输入”，也可直接在键盘键入数字打开目标量输入框，支持 `10M`、`1.5G`、`500T`，按 Enter 保存。

## 硬件

推荐 Tier 3 Case/APU/GPU、Tier 3.5 RAM、Tier 3 HDD、Tier 3 Screen、Keyboard。通过 Adapter/MFU 接入 Pump、Miner、ME 二合一接口、level maintainer 与转运器。

## 请求器导入

首次没有本地目标时会自动导入启用的 level maintainer 槽位。之后点击顶部 `IMPORT` 可显式重新导入；导入会更新 label/target/route/sourceRef，但保留 UI 中的 mode/weight/order。

默认 `importProfile="v1_simple"`：

```text
流体 batch = planetType*1000 + gasType
矿物 batch = droneTier*1000 + distance
```

若使用 v2.2 扩展编码，改为 `v2.2_extended`。

## 矿机无人机

默认后端为 `transposer`，采用 Wiki 原程序的全体同步方式：所有矿机追同一个目标，程序自动发现全部矿机和转运器；切换无人机时，先等所有矿机停稳，再让所有转运器统一退回旧无人机并分发同一等级的新无人机。**不需要填写矿机或转运器地址，也不需要逐矿机绑定表。**

硬件需要按 Wiki 方式搭建：每台矿机配一套转运器、输入总线和无人机末影箱；所有转运器摆放方向一致，末影箱使用同一频道。通常只需确认两个全局方向：

分发逻辑与 Wiki 原程序一致：统一退回旧无人机，只读取第一只转运器看到的共享末影箱一次，选定目标等级所在槽位，然后所有转运器从同一槽位各取 1 个。因此即使箱内同时有 MK-X 和 MK-VI，也只会给所有矿机分发目标要求的同一种无人机。无人机成功分发后才写入并校验所有矿机的距离参数；分发故障会阻止参数写入，这是安全停闭设计。

```lua
local sides = require("sides") -- config.lua 顶部已经有这一行

droneSide = sides.up   -- 上方：共享无人机末影箱
inputSide = sides.down -- 下方：矿机输入总线
```

默认布局现为“末影箱在转运器上方、输入总线在下方”。如果实际摆放不同，再修改这两个方向；方向不确定时可运行只读工具：

```sh
lua probe_bindings.lua
```

它会列出转运器六个方向连接的库存。为了容易辨认，可先在共享末影箱放一架无人机、在矿机输入侧放一个标记物，再运行探针。

若无人机一直手动固定，设 `droneBackend="manual"`。缺少目标等级无人机时默认 FAULT，不会偷偷换随机等级。

## 操作

- 点击目标：选择；
- TOP/UP/DOWN/BOTTOM：排序；
- OFF/TARGET/ALWAYS：调度模式；
- CUR/EDIT/数量按钮：调整目标库存；
- PLANET/GAS 或 DRONE/DIST：编辑路由；
- SYSTEM 页点击 FAULT 机器行：Retry；
- STOP 需在三秒内二次点击确认；
- Ctrl+Alt+C：安全退出并恢复终端。

## 重要限制

- 本地 `/etc/seui.dat` 是权威配置；level maintainer 只是导入源，因为其 OC `setSlot()` 写入路径受 32 位整数限制，不能保存 15G–500T 目标。
- 流体数量优先使用 AE 栈的 `.size`，避免 `.amount` 的约 2.147G 上限。
- beta-1 新参数列表没有公开矿机 overdrive 键，因此程序不会伪造 OD 写入。
- `--control` 会真实启停机器；先运行只读模式。
- 若发生未捕获异常，程序会先恢复终端，再显示并保留完整堆栈，直到按键或触摸确认；同一报告会写入 `/home/seui-crash.log`。

## 已验证

- 全部 Lua 文件通过 `luac5.2 -p` 与 `luac5.3 -p`；
- 调度/滞回/控制状态机测试通过；
- 160×50 UI mock smoke test 通过；
- `main.lua --simulate` 完整 mock 运行与退出清理通过。
