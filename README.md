<div align="center">

# ⚡ Mi8Elite-charge-boost 充电加速

**小米 / 红米 骁龙 8 至尊版系列充电增强模块**

![version](https://img.shields.io/badge/version-v8.4.9-orange)
![device](https://img.shields.io/badge/device-Xiaomi%2015%20%7C%2015%20Pro%20%7C%20K80%20Pro%20%7C%20K90%20%7C%20K90%20Ultra-blue)
![root](https://img.shields.io/badge/root-KernelSU%20%7C%20Magisk-green)
![author](https://img.shields.io/badge/author-酷安@鱼楠-red)

</div>

---

## 📦 下载

| 文件 | 说明 |
| --- | --- |
| [`releases/Mi8Elite-charge-boost_v8.4.9.zip`](releases/Mi8Elite-charge-boost_v8.4.9.zip) | 刷入包，在 KernelSU / Magisk 中安装 |
| [`module/`](module/) | 模块完整源码 |
| [`CHANGELOG.md`](CHANGELOG.md) | 全部版本更新日志（v8.0.7 起，历史刷入包在 `releases/`） |

md5：`6b23ac841c21b648e43ae967c7311d6c`

---

## ✨ 功能一览

### 🔋 DTBO 充电参数修改（重启生效）
| 选项 | 可选值 | 说明 |
| --- | --- | --- |
| 快充电流 | 原厂值 / 模块上限 / 不修改 | 小米15 为 15.5A / 20.5A；K80 Pro 上限 22A |
| 满速/断充温度 | 55°C / 不修改 | 设定温度以下满速，超过才停充（原厂 48°C） |
| 内核关机电压 | 两档 / 不修改 | 原厂 3050mV 的机型 2900 / 3000mV；K90 系列（原厂 2850mV）2700 / 2800mV |
| 屏幕超频 | 165Hz / 不超频 | 仅小米15：华星屏添加 132 / 144 / 155 / 165Hz 档位 |

- 刷入前自动备份当前 dtbo 为原厂镜像，卸载模块即还原
- 原厂镜像哈希校验，已收录 OS3 / OS4 共 10 个官方版本
- 官改或非收录镜像可选择「以当前镜像修改刷入」
- 保留原厂 AVB 签名结构与 salt

### 🔌 公版 PPS 解锁
第三方 PPS 充电头放行高功率快充，小米原装头不受影响。已装 FreePPS 时本项自动停用。

### 🌡️ 免重启调节
- **温控解除**：关闭有线充电温控降速（`wired_thermal_remove`）
- **实时充电电流**：充电中直接改 `wired_chg_curr`，立即生效
- **私有协议功率**：小米15 / 15 Pro 可切 100W / 120W，K90 系列 120W，K80 Pro 原厂已 120W
- **原装头握手重试**（实验性，默认关）：插入 20 秒仍未进电荷泵快充时自动重走认证

### 🪫 低电量延迟关机
电量锁定 2%，屏蔽 0% 关机与 30 秒倒计时，电池电压降到设定值后才关机。

### 🖥️ 高刷切换
仅小米15：WebUI「高刷切换」页一键切换 120 / 132 / 144 / 156 / 165Hz。

### 📊 WebUI 与充电监测
- 实时功率、电流、电压、温度曲线与协议详情
- 充电记录、功率与温度极值统计（只在充电时记录）
- 内置 **充电监测 App**（含公版 PPS 控制中心磁贴）

---

## 📱 适用范围

| 项目 | 支持 |
| --- | --- |
| 机型 | 小米15（dada）、小米15 Pro（haotian）、红米K80 Pro（miro）、红米K90（annibale）、红米K90至尊版（warsaw），其他机型安装时自动拒绝 |
| 系统（小米15） | HyperOS OS4.0.0.6 / 7 / 8 / 16 / 19，OS3.0.2 / 301 / 302 / 303 / 305 / 307 |
| 移植包 | ColorOS 16.1 移植包（自动识别官改 dtbo） |
| Root | KernelSU / Magisk |

---

## 🛠️ 安装

1. 在 KernelSU / Magisk 中选择刷入包安装
2. 按 **音量+** 切换选项，**音量-** 确认，15 秒不操作选默认
3. 确认结果后重启生效；不想重启可在 WebUI 设置里点「启动」

---

## ⚠️ 风险提示

修改 DTBO 与充电参数存在风险，大电流、高温充电会加速电池老化。请确认机型与系统版本后再刷入，作者不对任何损坏负责。

---

## 🙏 致谢

- 酷安@低线阻狂魔
- 酷安@花橋桥（PPS 节点）
- 酷安@瓦力喀 / FreePPS（思路参考）
- 酷安@久保Sama / 刷新率 APP（高刷切换思路）
