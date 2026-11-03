# 基于 FPGA 的实时多音色合成电子乐器引擎

本项目面向实时电子乐器应用，使用 Tang Mega 138K FPGA 完成 32 路并行 DDS
声部、每声部独立 ADSR 包络、按键事件分配、分级寄存混音和四种音频效果。

## 稳定版本

- 开发工具：Gowin V1.9.12.04
- FPGA：Tang Mega 138K Dock
- 器件：GW5AST-LV138PG484AC1/I0
- 最终上板版本：66 稳定版
- 最终顶层：`top_fx`
- 音频输出：PT8211 I2S
- 效果模式：干声、延迟、合唱、双反射空间
- DSP 使用量：0

最终码流不直接放在源码目录中，请在仓库右侧的 **Releases** 页面下载：

[下载 66 稳定版码流](../../releases/tag/v1.0-stable66)

## 主要功能

- 32 路并行 DDS 振荡器
- 32 位相位累加器和 256 点正弦波表
- 每个声部独立 ADSR 包络
- 四键演奏、动态声部分配和四音和弦
- Gray 指针异步事件 FIFO
- 逐级寄存的 32 声部平衡混音树
- IIR 低通、延迟、合唱、双反射空间和软限幅
- 1.589 MHz BCK、32 BCK/帧、16-bit 左右声道

## 按键说明

| 按键 | 功能 |
|---|---|
| K1 | C4，MIDI 60 |
| K2 | E4，MIDI 64 |
| K3 | G4，MIDI 67 |
| K4 | C5，MIDI 72 |
| S1 | 逐渐升高弯音 |
| S2 | 逐渐降低弯音 |
| S3/S4 | 选择四种效果模式 |

## 仓库结构

```text
src/          最终 RTL 源码
src/ip/       Gowin PLL、OSC 和时钟分频模块
constraints/  引脚约束
build/        Gowin 构建脚本与说明
evidence/     仿真图片、CSV 和 66 版 PnR 报告
release/      码流发布说明
```

## 构建

1. 安装 Gowin V1.9.12.04。
2. 新建 GW5AST-LV138PG484AC1/I0 工程。
3. 将 `src` 中文件加入工程。
4. 将 `constraints/top.cst` 作为物理约束文件。
5. 设置顶层模块为 `top_fx`。
6. 综合、布局布线并生成比特流。

也可以参考 `build/build.tcl` 中的相对路径构建脚本。

## 实验数据说明

`evidence/32voice_spectrum.png` 和 `evidence/fx_impulse_response.png` 来自
ModelSim 算法仿真，仿真基准采样率为 46.875 kHz。最终 66 上板工程沿用的
板级时钟约为 1.589 MHz BCK，对应约 49.66 kHz 帧率。资源与静态时序以
`evidence/gowin66_resource_report.txt` 和 `evidence/gowin66_timing_report.tr`
为准。

## 说明

本仓库只保存经过上板确认的 66 稳定版本。
