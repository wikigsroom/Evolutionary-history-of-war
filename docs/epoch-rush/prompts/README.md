# 素材生成规格与提示词

本目录服务于197项逻辑素材清单，提供可组合的生产提示词与处理要求；现阶段只有既有风格参考已完成，其余生产项待执行。

- [01 风格母版](01-风格母版.md)：所有对象共用的画风、尺寸与背景约束。
- [02 六角色与十八专精](02-角色与专精.md)：人物身份、全身/头像与专精表现。
- [03 五时代场景](03-五时代场景.md)：五基地及十五背景层。
- [04 二十兵与十炮塔](04-兵种与炮塔.md)：逐ID对象提示词。
- [05 UI、掉落物与特效](05-界面掉落与特效.md)：十八技能、十二遗物、状态、资源与特效参数。
- [06 动画与QA](06-动画制作与QA.md)：部件优先、整条帧图、处理与验收。

执行时把母版与对象段合成为纯文本prompt文件，放在output/imagegen/epoch-rush/prompts/，通过用户指定的sub2-image-gen脚本调用，默认gpt-image-2.5/high/PNG。实际生成输出放output/imagegen/epoch-rush/，验证后才接入public/assets/。

示例命令（待生产阶段执行）：

```text
python C:/Users/carzy/.codex/skills/sub2-image-gen/scripts/sub2_image_gen.py generate --prompt-file output/imagegen/epoch-rush/prompts/U31.txt --model gpt-image-2.5 --quality high --background transparent --out output/imagegen/epoch-rush/U31-raw.png
```

本目录没有复制网关地址或凭据；平台成品也不在运行时生成素材。声音按[音频制作](../10-音频与触觉.md)使用本地合成和编排。

[美术设定](../08-美术设定与素材制作.md) · [素材清单](../data/asset-manifest.json) · [返回](../README.md)
