# 结构化设计数据

版本0.1.0；所有数值是待试玩的初值。本目录17个JSON配置，包含规则、内容及素材制作清单。

| 文件 | 条目 | 用途 |
| --- | --- | --- |
| [asset-manifest.json](asset-manifest.json) | 197 | 197逻辑素材项、阶段、计划路径和制作状态 |
| [builds.json](builds.json) | 6 | 六合法完整构筑样例 |
| [enemy-profiles.json](enemy-profiles.json) | 6 | 六AI角色与配兵权重 |
| [eras.json](eras.json) | 5 | 五时代倍率、基地与进化费用 |
| [heroes.json](heroes.json) | 6 | 六可玩角色、初值、专属和解锁 |
| [loot.json](loot.json) | 规则对象 | 奖励、概率、保底、首通与防重复 |
| [missions.json](missions.json) | 15 | 十五关、时代范围、公开章末条件与解锁 |
| [relics.json](relics.json) | 12 | 十二固定词条遗物 |
| [rules.json](rules.json) | 规则对象 | 全局循环、预算、数值上限、难度与初始解锁 |
| [run-upgrades.json](run-upgrades.json) | 12 | 四进化组三选一，共十二项 |
| [skills.json](skills.json) | 18 | 十二通用及六专属技能、效果字段 |
| [specializations.json](specializations.json) | 18 | 十八角色专精、收益与代价 |
| [statuses.json](statuses.json) | 10 | 十状态的叠加、时长与效果类型 |
| [talents.json](talents.json) | 18 | 三路线十八节点与点数 |
| [turrets.json](turrets.json) | 10 | 十炮塔、射程与价格 |
| [units.json](units.json) | 20 | 二十兵种、出生时代、武器和奖励 |
| [weapons.json](weapons.json) | 8 | 八种投射/接触/连锁执行族 |

脚本校验：`python docs/epoch-rush/tools/validate_design.py`。校验ID、构筑、数量、掉落、演算和链接，不宣称引擎实现通过。

[数据字典](../13-数据字典存档与配置.md) · [内容目录](../附录-内容目录.md) · [返回](../README.md)
