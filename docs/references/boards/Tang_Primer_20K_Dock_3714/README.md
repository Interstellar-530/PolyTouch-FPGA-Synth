# Tang Primer 20K Dock 3714 板卡资料

## 本地文档

| 文件 | 内容 |
| --- | --- |
| `Tang_Primer_20K_规格书_V1.0.pdf` | Tang Primer 20K 核心板中文规格书 |
| `Sipeed_Tang_Primer_20K_Datasheet_V1.0.pdf` | Tang Primer 20K 英文数据手册 |
| `Tang_Primer_20K_Dock_3714_Schematics.pdf` | Dock 3714 原理图，当前板卡版本 |
| `Tang_Primer_20K_Dock-3713_Schematics.pdf` | Dock 3713 原理图，用于版本对照 |
| `Tang_Primer_20K_SOM-3961_Schematic.pdf` | Tang Primer 20K 核心板原理图 |

## 在线资料

- Sipeed 官方 Wiki：https://wiki.sipeed.com/hardware/zh/tang/tang-primer-20k/primer-20k.html
- 官方例程仓库：https://github.com/sipeed/TangPrimer-20K-example
- Sipeed 下载站：https://dl.sipeed.com/shareURL/TANG/Primer_20K

## 当前项目用到的固定引脚

| 信号 | FPGA 引脚 | 说明 |
| --- | --- | --- |
| 27 MHz 时钟 | H11 | 核心板板载时钟 |
| PT8211 BCK | N15 | Dock 3714 板载音频调试口 |
| PT8211 WS | P16 | 左右声道帧同步 |
| PT8211 DIN | P15 | 串行音频数据 |
| PA_EN | R16 | 耳机功放使能 |
| Orange_LED0 | C13 | 用户 LED |
| Orange_LED1 | A13 | 用户 LED |
| Orange_LED2 | N16 | 当前 blink 使用的 LED |
| Orange_LED3 | N14 | 用户 LED |
| Orange_LED4 | L14 | 用户 LED |
| Orange_LED5 | L16 | 用户 LED |

## 阅读提示

原理图和引脚表属于版面关键资料，不能只依赖 OCR 文本。需要核对某个引脚、电源域或连接关系时，应直接查看对应 PDF 页面，必要时把页面渲染成 PNG 再放大检查。
